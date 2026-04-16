param(
    [ValidateSet("local", "staging", "production", "production-next")]
    [string]$Environment = "production",

    [string]$Target = "lib/main.dart",
    [string]$BuildName,
    [int]$BuildNumber,

    [switch]$ReleaseGate,
    [switch]$RequireSigning,
    [switch]$SkipPreflight,
    [switch]$Clean,
    [switch]$PrintOnly,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ReleaseGate -and -not $PSBoundParameters.ContainsKey("RequireSigning")) {
    $RequireSigning = $Environment -in @("production", "production-next")
}

function Get-EffectiveNativeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )

    switch ($EnvironmentName) {
        "production-next" { return "production" }
        default { return $EnvironmentName }
    }
}

function Read-MobileConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $json = $raw | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in '$Path'. $($_.Exception.Message)"
    }

    if ($null -eq $json) {
        return [ordered]@{}
    }

    $result = [ordered]@{}
    foreach ($property in $json.PSObject.Properties) {
        $value = $property.Value
        if ($null -eq $value) {
            continue
        }

        if (
            $value -is [System.Management.Automation.PSCustomObject] -or
            $value -is [System.Collections.IList] -or
            $value -is [hashtable]
        ) {
            throw "Unsupported nested value for key '$($property.Name)' in '$Path'."
        }

        $result[$property.Name] = [string]$value
    }

    return $result
}

function Mask-PreviewArg {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arg
    )

    if ($Arg -notlike "--dart-define=*") {
        return $Arg
    }

    $payload = $Arg.Substring("--dart-define=".Length)
    $parts = $payload.Split("=", 2)
    if ($parts.Count -ne 2) {
        return $Arg
    }

    $key = [string]$parts[0]
    $value = [string]$parts[1]
    if ($key -match "KEY|SECRET|TOKEN|PASSWORD") {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return "--dart-define=$key=<empty>"
        }
        return "--dart-define=$key=***"
    }

    return $Arg
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$effectiveNativeEnvironment = Get-EffectiveNativeEnvironment -EnvironmentName $Environment
$preflightScript = Join-Path $repoRoot "scripts/check-android-release-readiness.ps1"
$mobileConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"

Push-Location $repoRoot
try {
    if (-not $SkipPreflight) {
        $preflightArgs = @(
            "-ExecutionPolicy", "Bypass",
            "-File", $preflightScript,
            "-Environment", $Environment
        )
        if ($ReleaseGate) {
            $preflightArgs += "-ReleaseGate"
        }
        if ($RequireSigning) {
            $preflightArgs += "-RequireSigning"
        }

        & powershell @preflightArgs
        if ($LASTEXITCODE -gt 0) {
            throw "Android preflight failed (exit code $LASTEXITCODE)."
        }
    }

    $dartDefines = [ordered]@{
        "APP_ENV" = $Environment
    }

    $mobileConfig = Read-MobileConfig -Path $mobileConfigPath
    if ($null -ne $mobileConfig) {
        foreach ($entry in $mobileConfig.GetEnumerator()) {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
                $dartDefines[[string]$entry.Key] = [string]$entry.Value
            }
        }
    }

    $flutterArgs = @(
        "build", "appbundle",
        "--release",
        "--flavor", $effectiveNativeEnvironment,
        "-t", $Target
    )

    foreach ($entry in $dartDefines.GetEnumerator()) {
        $flutterArgs += "--dart-define=$($entry.Key)=$($entry.Value)"
    }

    if (-not [string]::IsNullOrWhiteSpace($BuildName)) {
        $flutterArgs += "--build-name=$BuildName"
    }

    if ($BuildNumber -gt 0) {
        $flutterArgs += "--build-number=$BuildNumber"
    }

    if ($AdditionalArgs) {
        $flutterArgs += $AdditionalArgs
    }

    $previewArgs = @()
    foreach ($arg in $flutterArgs) {
        $previewArgs += Mask-PreviewArg -Arg ([string]$arg)
    }
    $preview = "flutter " + ($previewArgs -join " ")
    Write-Host $preview
    Write-Host "Effective native flavor: $effectiveNativeEnvironment"
    if ($null -ne $mobileConfig) {
        Write-Host "Mobile config file: $mobileConfigPath"
    } else {
        Write-Host "Mobile config file: <none>"
    }

    if ($PrintOnly) {
        exit 0
    }

    if ($Clean) {
        & flutter clean
        if ($LASTEXITCODE -gt 0) {
            throw "flutter clean failed (exit code $LASTEXITCODE)."
        }

        & flutter pub get
        if ($LASTEXITCODE -gt 0) {
            throw "flutter pub get failed (exit code $LASTEXITCODE)."
        }
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -gt 0) {
        throw "flutter build appbundle failed (exit code $LASTEXITCODE)."
    }

    $bundleDir = Join-Path $repoRoot "build/app/outputs/bundle"
    $preferredAab = Join-Path $bundleDir "$($effectiveNativeEnvironment)Release/app-$effectiveNativeEnvironment-release.aab"
    $aabPath = $null

    if (Test-Path -LiteralPath $preferredAab) {
        $aabPath = $preferredAab
    } else {
        $latestAab = Get-ChildItem -Path $bundleDir -Filter "*.aab" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $latestAab) {
            $aabPath = $latestAab.FullName
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$aabPath)) {
        throw "AAB output not found under '$bundleDir'."
    }

    $artifactsDir = Join-Path $repoRoot "artifacts/android"
    New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $artifactPath = Join-Path $artifactsDir ("adfoot-{0}-{1}.aab" -f $Environment, $timestamp)
    Copy-Item -LiteralPath $aabPath -Destination $artifactPath -Force

    $artifactFile = Get-Item -LiteralPath $artifactPath
    $artifactSizeMb = [math]::Round(($artifactFile.Length / 1MB), 2)

    Write-Host ""
    Write-Host "AAB generated successfully."
    Write-Host "Source AAB : $aabPath"
    Write-Host "Artifact   : $artifactPath"
    Write-Host "Size (MB)  : $artifactSizeMb"
} finally {
    Pop-Location
}

exit 0
