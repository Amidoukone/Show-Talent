param(
    [ValidateSet("local", "staging", "production")]
    [string]$Environment = "production",

    [string]$Target = "lib/main.dart",

    [string]$DeviceId,

    [switch]$UseNativeFlavor,

    [switch]$UseFirebaseEmulators,

    [string]$EmulatorHost,

    [string]$ConfigPath,

    [switch]$RequireConfig,

    [switch]$PrintOnly,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $RepoRoot $Path
}

function ConvertTo-DartDefineValue {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }

    return [string]$Value
}

function Read-MobileConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in mobile config file '$Path'. $($_.Exception.Message)"
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
            throw "Unsupported nested value for key '$($property.Name)' in '$Path'. Use flat key/value pairs only."
        }

        $result[$property.Name] = ConvertTo-DartDefineValue -Value $value
    }

    return $result
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$defaultConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"
$resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath
} else {
    Resolve-RepoRelativePath -RepoRoot $repoRoot -Path $ConfigPath
}

$configDefines = Read-MobileConfig -Path $resolvedConfigPath
if ($RequireConfig -and $null -eq $configDefines) {
    Write-Error "Missing required mobile config file: $resolvedConfigPath"
    exit 1
}

if (
    $null -ne $configDefines -and
    $configDefines.Contains("APP_ENV") -and
    $configDefines["APP_ENV"] -ne $Environment
) {
    Write-Error "Mobile config APP_ENV '$($configDefines["APP_ENV"])' does not match requested environment '$Environment'."
    exit 1
}

$effectiveDefines = [ordered]@{}

if ($null -ne $configDefines) {
    foreach ($entry in $configDefines.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            $effectiveDefines[$entry.Key] = [string]$entry.Value
        }
    }
}

$effectiveDefines["APP_ENV"] = $Environment

if ($Environment -eq "local" -or $UseFirebaseEmulators) {
    $effectiveDefines["USE_FIREBASE_EMULATORS"] = "true"
}

if ($EmulatorHost) {
    $effectiveDefines["FIREBASE_EMULATOR_HOST"] = $EmulatorHost
}

$dartDefines = @()
foreach ($entry in $effectiveDefines.GetEnumerator()) {
    $dartDefines += "--dart-define=$($entry.Key)=$($entry.Value)"
}

$flutterArgs = @("run", "-t", $Target) + $dartDefines

if ($UseNativeFlavor) {
    $flutterArgs += @("--flavor", $Environment)
}

if ($DeviceId) {
    $flutterArgs += @("-d", $DeviceId)
}

if ($AdditionalArgs) {
    $flutterArgs += $AdditionalArgs
}

$commandPreview = "flutter " + ($flutterArgs -join " ")
Write-Host $commandPreview
if ($null -ne $configDefines) {
    Write-Host "Mobile config file: $resolvedConfigPath"
} else {
    Write-Host "Mobile config file: <none> (fallback to compiled defaults and active native files)"
}

if ($PrintOnly) {
    exit 0
}

& flutter @flutterArgs
exit $LASTEXITCODE
