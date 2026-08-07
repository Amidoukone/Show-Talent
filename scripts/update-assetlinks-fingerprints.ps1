param(
    [string]$AssetLinksPath = "site_pub/.well-known/assetlinks.json",
    [string]$ReleasePackageName = "org.adfoot.app",
    [string]$StagingPackageName = "org.adfoot.app.staging",
    [string]$ReleaseFingerprint,
    [string]$StagingFingerprint,
    [string]$KeystorePath,
    [string]$StorePassword,
    [string]$KeyAlias,
    [string]$KeyPassword,
    [switch]$PrintOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-KeyValueFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $result[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $result
}

function Resolve-KeystoreInfoFromKeyProperties {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $androidDir = Join-Path $RepoRoot "android"
    $path = Join-Path $androidDir "key.properties"
    $props = Read-KeyValueFile -Path $path
    if ($props.Count -eq 0) {
        return $null
    }

    $rawStoreFile = if ($props.ContainsKey("storeFile")) { [string]$props["storeFile"] } else { "" }
    $resolvedStoreFile = if ([string]::IsNullOrWhiteSpace($rawStoreFile)) {
        $null
    } elseif ([System.IO.Path]::IsPathRooted($rawStoreFile)) {
        $rawStoreFile
    } else {
        Join-Path $androidDir $rawStoreFile
    }

    return @{
        keystorePath = $resolvedStoreFile
        storePassword = if ($props.ContainsKey("storePassword")) { [string]$props["storePassword"] } else { "" }
        keyAlias = if ($props.ContainsKey("keyAlias")) { [string]$props["keyAlias"] } else { "" }
        keyPassword = if ($props.ContainsKey("keyPassword")) { [string]$props["keyPassword"] } else { "" }
    }
}

function Get-Sha256Fingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedKeystorePath,
        [Parameter(Mandatory = $true)]
        [string]$Alias,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedStorePassword,
        [string]$ResolvedKeyPassword
    )

    $candidateKeytool = if ($env:JAVA_HOME) {
        Join-Path $env:JAVA_HOME "bin/keytool.exe"
    } else {
        ""
    }
    $keytool = if ($candidateKeytool -and (Test-Path -LiteralPath $candidateKeytool)) {
        $candidateKeytool
    } else {
        "keytool"
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedKeyPassword)) {
        $ResolvedKeyPassword = $ResolvedStorePassword
    }

    $args = @(
        "-list",
        "-v",
        "-keystore", $ResolvedKeystorePath,
        "-alias", $Alias,
        "-storepass", $ResolvedStorePassword,
        "-keypass", $ResolvedKeyPassword
    )

    $output = & $keytool @args 2>&1
    if ($LASTEXITCODE -gt 0) {
        throw "keytool failed to read keystore fingerprint (exit code $LASTEXITCODE)."
    }

    $line = $output | Where-Object { $_ -match 'SHA256:\s*([A-F0-9:]+)' } | Select-Object -First 1
    if ($null -eq $line) {
        throw "Unable to extract SHA256 fingerprint from keytool output."
    }

    $match = [regex]::Match([string]$line, 'SHA256:\s*([A-F0-9:]+)')
    if (-not $match.Success) {
        throw "Unable to parse SHA256 fingerprint."
    }

    return $match.Groups[1].Value.Trim()
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedAssetLinksPath = if ([System.IO.Path]::IsPathRooted($AssetLinksPath)) {
    $AssetLinksPath
} else {
    Join-Path $repoRoot $AssetLinksPath
}

if (-not (Test-Path -LiteralPath $resolvedAssetLinksPath)) {
    Write-Error "Missing assetlinks file: $resolvedAssetLinksPath"
    exit 1
}

$autoInfo = Resolve-KeystoreInfoFromKeyProperties -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($KeystorePath) -and $null -ne $autoInfo) {
    $KeystorePath = [string]$autoInfo["keystorePath"]
}
if ([string]::IsNullOrWhiteSpace($StorePassword) -and $null -ne $autoInfo) {
    $StorePassword = [string]$autoInfo["storePassword"]
}
if ([string]::IsNullOrWhiteSpace($KeyAlias) -and $null -ne $autoInfo) {
    $KeyAlias = [string]$autoInfo["keyAlias"]
}
if ([string]::IsNullOrWhiteSpace($KeyPassword) -and $null -ne $autoInfo) {
    $KeyPassword = [string]$autoInfo["keyPassword"]
}

if ([string]::IsNullOrWhiteSpace($ReleaseFingerprint)) {
    if (
        -not [string]::IsNullOrWhiteSpace($KeystorePath) -and
        -not [string]::IsNullOrWhiteSpace($StorePassword) -and
        -not [string]::IsNullOrWhiteSpace($KeyAlias)
    ) {
        $resolvedKeystorePath = if ([System.IO.Path]::IsPathRooted($KeystorePath)) {
            $KeystorePath
        } else {
            Join-Path $repoRoot $KeystorePath
        }

        if (-not (Test-Path -LiteralPath $resolvedKeystorePath)) {
            Write-Error "Keystore not found: $resolvedKeystorePath"
            exit 1
        }

        $ReleaseFingerprint = Get-Sha256Fingerprint `
            -ResolvedKeystorePath $resolvedKeystorePath `
            -Alias $KeyAlias `
            -ResolvedStorePassword $StorePassword `
            -ResolvedKeyPassword $KeyPassword
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseFingerprint) -and [string]::IsNullOrWhiteSpace($StagingFingerprint)) {
    Write-Error "No fingerprint provided. Provide ReleaseFingerprint or keystore credentials."
    exit 1
}

$rawJson = Get-Content -LiteralPath $resolvedAssetLinksPath -Raw
$assetLinks = $rawJson | ConvertFrom-Json
$updated = $false

foreach ($entry in $assetLinks) {
    $pkg = [string]$entry.target.package_name
    if ($pkg -eq $ReleasePackageName -and -not [string]::IsNullOrWhiteSpace($ReleaseFingerprint)) {
        $entry.target.sha256_cert_fingerprints = @($ReleaseFingerprint)
        $updated = $true
    }
    if ($pkg -eq $StagingPackageName -and -not [string]::IsNullOrWhiteSpace($StagingFingerprint)) {
        $entry.target.sha256_cert_fingerprints = @($StagingFingerprint)
        $updated = $true
    }
}

if (-not $updated) {
    Write-Error "No matching package entry updated in assetlinks.json."
    exit 1
}

$jsonOut = $assetLinks | ConvertTo-Json -Depth 10

if ($PrintOnly) {
    Write-Host "Release package   : $ReleasePackageName"
    Write-Host "Release fingerprint: $ReleaseFingerprint"
    if (-not [string]::IsNullOrWhiteSpace($StagingFingerprint)) {
        Write-Host "Staging package   : $StagingPackageName"
        Write-Host "Staging fingerprint: $StagingFingerprint"
    }
    Write-Host ""
    Write-Host $jsonOut
    exit 0
}

Set-Content -LiteralPath $resolvedAssetLinksPath -Value $jsonOut -Encoding UTF8

Write-Host "assetlinks.json updated."
Write-Host "Path                : $resolvedAssetLinksPath"
Write-Host "Release package      : $ReleasePackageName"
Write-Host "Release fingerprint  : $ReleaseFingerprint"
if (-not [string]::IsNullOrWhiteSpace($StagingFingerprint)) {
    Write-Host "Staging package      : $StagingPackageName"
    Write-Host "Staging fingerprint  : $StagingFingerprint"
}

exit 0
