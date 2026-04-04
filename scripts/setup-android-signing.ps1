param(
    [string]$KeystorePath = "android/upload-keystore.jks",
    [string]$KeyAlias = "upload",
    [Parameter(Mandatory = $true)]
    [string]$StorePassword,
    [string]$KeyPassword,
    [switch]$GenerateKeystore,
    [string]$DName = "CN=Adfoot, OU=Mobile, O=Adfoot, L=Abidjan, ST=Abidjan, C=CI",
    [int]$ValidityDays = 10000,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($KeyPassword)) {
    $KeyPassword = $StorePassword
}

if ([string]::IsNullOrWhiteSpace($StorePassword)) {
    Write-Error "StorePassword is required."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($KeyAlias)) {
    Write-Error "KeyAlias is required."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot "android"

$resolvedKeystorePath = if ([System.IO.Path]::IsPathRooted($KeystorePath)) {
    $KeystorePath
} else {
    Join-Path $repoRoot $KeystorePath
}

$keyPropertiesPath = Join-Path $androidDir "key.properties"

if ($GenerateKeystore) {
    $keystoreParent = Split-Path -Parent $resolvedKeystorePath
    if (-not (Test-Path -LiteralPath $keystoreParent)) {
        New-Item -ItemType Directory -Path $keystoreParent -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $resolvedKeystorePath) -and -not $Force) {
        Write-Error "Keystore already exists: $resolvedKeystorePath (use -Force to overwrite)."
        exit 1
    }

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

    $keytoolArgs = @(
        "-genkeypair",
        "-v",
        "-keystore", $resolvedKeystorePath,
        "-storepass", $StorePassword,
        "-alias", $KeyAlias,
        "-keypass", $KeyPassword,
        "-keyalg", "RSA",
        "-keysize", "2048",
        "-validity", "$ValidityDays",
        "-dname", $DName
    )

    & $keytool @keytoolArgs
    if ($LASTEXITCODE -gt 0) {
        Write-Error "keytool generation failed (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath $resolvedKeystorePath)) {
    Write-Error "Keystore file not found: $resolvedKeystorePath"
    exit 1
}

$relativeStoreFile = [System.IO.Path]::GetRelativePath($androidDir, $resolvedKeystorePath)
$relativeStoreFile = $relativeStoreFile -replace '\\', '/'

if ((Test-Path -LiteralPath $keyPropertiesPath) -and -not $Force) {
    Write-Error "android/key.properties already exists. Use -Force to overwrite."
    exit 1
}

$content = @(
    "storePassword=$StorePassword",
    "keyPassword=$KeyPassword",
    "keyAlias=$KeyAlias",
    "storeFile=$relativeStoreFile"
)

Set-Content -LiteralPath $keyPropertiesPath -Value $content -Encoding UTF8

Write-Host "Android signing configured."
Write-Host "Keystore path    : $resolvedKeystorePath"
Write-Host "Key alias        : $KeyAlias"
Write-Host "key.properties   : $keyPropertiesPath"
Write-Host "storeFile (rel.) : $relativeStoreFile"

exit 0
