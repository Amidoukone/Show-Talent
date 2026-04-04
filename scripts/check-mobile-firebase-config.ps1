param(
    [ValidateSet("local", "staging", "production")]
    [string]$Environment = "production",

    [string]$ConfigPath,

    [switch]$RequireConfig,

    [switch]$RequireNativeFiles
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

function Convert-JsonObjectToHashtable {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    $result = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    return $result
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

    return Convert-JsonObjectToHashtable -InputObject $json
}

function Get-PlannedMobileId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )

    switch ($EnvironmentName) {
        "local" { return "org.adfoot.app.local" }
        "staging" { return "org.adfoot.app.staging" }
        default { return "org.adfoot.app" }
    }
}

function Get-PlistStringValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $pattern = "<key>\s*$Key\s*</key>\s*<string>\s*([^<]+)\s*</string>"
    $match = [regex]::Match($content, $pattern, $options)

    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$defaultConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"
$resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath
} else {
    Resolve-RepoRelativePath -RepoRoot $repoRoot -Path $ConfigPath
}

$androidFirebasePath = Join-Path $repoRoot "android/app/src/$Environment/google-services.json"
$iosFirebasePath = Join-Path $repoRoot "ios/Firebase/$Environment/GoogleService-Info.plist"
$plannedMobileId = Get-PlannedMobileId -EnvironmentName $Environment

$warnings = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]

$config = Read-MobileConfig -Path $resolvedConfigPath
if ($null -eq $config) {
    $warnings.Add("Missing mobile config file: $resolvedConfigPath")
    $warnings.Add("The run script will fall back to lib/firebase_options.dart and the currently active native Firebase files.")
    if ($RequireConfig) {
        $errors.Add("Mobile config is required for environment '$Environment'.")
    }
} else {
    $requiredKeys = @(
        "FIREBASE_PROJECT_ID",
        "FIREBASE_MESSAGING_SENDER_ID",
        "FIREBASE_STORAGE_BUCKET",
        "FIREBASE_ANDROID_API_KEY",
        "FIREBASE_ANDROID_APP_ID",
        "FIREBASE_IOS_API_KEY",
        "FIREBASE_IOS_APP_ID",
        "FIREBASE_IOS_BUNDLE_ID"
    )

    foreach ($key in $requiredKeys) {
        $rawValue = if ($config.Contains($key)) { [string]$config[$key] } else { "" }
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            $errors.Add("Missing required mobile config key: $key")
        }
    }

    if ($config.Contains("APP_ENV")) {
        $rawAppEnvironment = [string]$config["APP_ENV"]
        if (-not [string]::IsNullOrWhiteSpace($rawAppEnvironment) -and $rawAppEnvironment -ne $Environment) {
            $errors.Add("APP_ENV in '$resolvedConfigPath' is '$rawAppEnvironment' but expected '$Environment'.")
        }
    }

    if (
        $config.Contains("FIREBASE_IOS_BUNDLE_ID") -and
        -not [string]::IsNullOrWhiteSpace([string]$config["FIREBASE_IOS_BUNDLE_ID"]) -and
        [string]$config["FIREBASE_IOS_BUNDLE_ID"] -ne $plannedMobileId
    ) {
        $warnings.Add(
            "FIREBASE_IOS_BUNDLE_ID is '$([string]$config["FIREBASE_IOS_BUNDLE_ID"])' but the planned ID for '$Environment' is '$plannedMobileId'."
        )
    }
}

if (Test-Path -LiteralPath $androidFirebasePath) {
    try {
        $androidConfig = Get-Content -LiteralPath $androidFirebasePath -Raw | ConvertFrom-Json
        $androidProjectId = [string]$androidConfig.project_info.project_id
        $androidClient = @($androidConfig.client)[0]
        $androidPackageName = [string]$androidClient.client_info.android_client_info.package_name

        if (-not [string]::IsNullOrWhiteSpace($androidPackageName) -and $androidPackageName -ne $plannedMobileId) {
            $errors.Add(
                "Android native package in '$androidFirebasePath' is '$androidPackageName' but expected '$plannedMobileId'."
            )
        }

        if (
            $null -ne $config -and
            $config.Contains("FIREBASE_PROJECT_ID") -and
            -not [string]::IsNullOrWhiteSpace([string]$config["FIREBASE_PROJECT_ID"]) -and
            $androidProjectId -ne [string]$config["FIREBASE_PROJECT_ID"]
        ) {
            $errors.Add(
                "Android native Firebase project '$androidProjectId' does not match FIREBASE_PROJECT_ID '$([string]$config["FIREBASE_PROJECT_ID"])'."
            )
        }
    } catch {
        $errors.Add("Could not parse Android Firebase file '$androidFirebasePath'. $($_.Exception.Message)")
    }
} else {
    $warnings.Add("Missing Android native Firebase file: $androidFirebasePath")
    if ($RequireNativeFiles) {
        $errors.Add("Android native Firebase file is required for '$Environment'.")
    }
}

if (Test-Path -LiteralPath $iosFirebasePath) {
    $iosBundleId = Get-PlistStringValue -Path $iosFirebasePath -Key "BUNDLE_ID"
    $iosProjectId = Get-PlistStringValue -Path $iosFirebasePath -Key "PROJECT_ID"

    if ([string]::IsNullOrWhiteSpace($iosBundleId)) {
        $errors.Add("Could not read BUNDLE_ID from '$iosFirebasePath'.")
    } elseif ($iosBundleId -ne $plannedMobileId) {
        $errors.Add("iOS native bundle ID in '$iosFirebasePath' is '$iosBundleId' but expected '$plannedMobileId'.")
    }

    if (
        $null -ne $config -and
        $config.Contains("FIREBASE_PROJECT_ID") -and
        -not [string]::IsNullOrWhiteSpace([string]$config["FIREBASE_PROJECT_ID"]) -and
        -not [string]::IsNullOrWhiteSpace($iosProjectId) -and
        $iosProjectId -ne [string]$config["FIREBASE_PROJECT_ID"]
    ) {
        $errors.Add(
            "iOS native Firebase project '$iosProjectId' does not match FIREBASE_PROJECT_ID '$([string]$config["FIREBASE_PROJECT_ID"])'."
        )
    }
} else {
    $warnings.Add("Missing iOS native Firebase file: $iosFirebasePath")
    if ($RequireNativeFiles) {
        $errors.Add("iOS native Firebase file is required for '$Environment'.")
    }
}

Write-Host "Environment              : $Environment"
Write-Host "Mobile config file       : $resolvedConfigPath"
Write-Host "Planned Android package  : $plannedMobileId"
Write-Host "Planned iOS bundle ID    : $plannedMobileId"
Write-Host "Android native file      : $androidFirebasePath"
Write-Host "iOS native file          : $iosFirebasePath"

if ($null -ne $config) {
    Write-Host ""
    Write-Host "Config summary:"
    foreach ($key in @("APP_ENV", "FIREBASE_PROJECT_ID", "FIREBASE_STORAGE_BUCKET", "FIREBASE_IOS_BUNDLE_ID")) {
        if ($config.Contains($key) -and -not [string]::IsNullOrWhiteSpace([string]$config[$key])) {
            Write-Host ("- {0}={1}" -f $key, [string]$config[$key])
        }
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:"
    foreach ($warning in $warnings) {
        Write-Host "- $warning"
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors:"
    foreach ($errorMessage in $errors) {
        Write-Host "- $errorMessage"
    }
    exit 1
}

Write-Host ""
Write-Host "Mobile Firebase config check completed."
