param(
    [ValidateSet("local", "staging", "production", "production-next")]
    [string]$Environment = "production",

    [string]$ConfigPath,

    [switch]$RequireConfig,

    [switch]$RequireNativeFiles,

    [switch]$RequirePlayIntegrityAppCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        $Config,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($Config.Contains($Key)) {
        return [string]$Config[$Key]
    }

    return ""
}

function Test-AppCheckDebugProviderRequested {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $rawForceDebugProvider = Get-ConfigValue -Config $Config -Key "APP_CHECK_DEBUG_PROVIDER"
    $rawAndroidProvider = Get-ConfigValue -Config $Config -Key "APP_CHECK_ANDROID_PROVIDER"
    $rawAndroidDebugToken = Get-ConfigValue -Config $Config -Key "APP_CHECK_ANDROID_DEBUG_TOKEN"
    $rawAppleDebugToken = Get-ConfigValue -Config $Config -Key "APP_CHECK_APPLE_DEBUG_TOKEN"

    return $rawForceDebugProvider.Trim().ToLowerInvariant() -eq "true" -or
        $rawAndroidProvider.Trim().ToLowerInvariant() -eq "debug" -or
        -not [string]::IsNullOrWhiteSpace($rawAndroidDebugToken) -or
        -not [string]::IsNullOrWhiteSpace($rawAppleDebugToken)
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
$effectiveNativeEnvironment = Get-EffectiveNativeEnvironment -EnvironmentName $Environment
$defaultConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"
$resolvedConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath
} else {
    Resolve-RepoRelativePath -RepoRoot $repoRoot -Path $ConfigPath
}

$androidFirebasePath = Join-Path $repoRoot "android/app/src/$effectiveNativeEnvironment/google-services.json"
$iosFirebasePath = Join-Path $repoRoot "ios/Firebase/$effectiveNativeEnvironment/GoogleService-Info.plist"
$plannedMobileId = Get-PlannedMobileId -EnvironmentName $Environment

$warnings = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]

$config = Read-MobileConfig -Path $resolvedConfigPath
if ($null -eq $config) {
    $warnings.Add("Missing mobile config file: $resolvedConfigPath")
    $warnings.Add("Committed Firebase options/native files are sanitized placeholders. Real runs should use local non-committed config files.")
    if ($RequireConfig) {
        $errors.Add("Mobile config is required for environment '$Environment'.")
    }
} else {
    $requiredKeys = @(
        "FIREBASE_PROJECT_ID",
        "FIREBASE_MESSAGING_SENDER_ID",
        "FIREBASE_STORAGE_BUCKET",
        "VIDEO_SHARE_BASE_URL",
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

    $optionalWebKeys = @(
        "FIREBASE_WEB_API_KEY",
        "FIREBASE_WEB_APP_ID",
        "FIREBASE_WEB_AUTH_DOMAIN",
        "FIREBASE_WEB_VAPID_KEY"
    )
    foreach ($key in $optionalWebKeys) {
        $rawValue = if ($config.Contains($key)) { [string]$config[$key] } else { "" }
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            $warnings.Add("Missing optional web key in mobile config: $key (required for full web FCM behavior).")
        }
    }

    if ($config.Contains("APP_ENV")) {
        $rawAppEnvironment = [string]$config["APP_ENV"]
        if (-not [string]::IsNullOrWhiteSpace($rawAppEnvironment) -and $rawAppEnvironment -ne $Environment) {
            $errors.Add("APP_ENV in '$resolvedConfigPath' is '$rawAppEnvironment' but expected '$Environment'.")
        }
    }

    if ($Environment -in @("production", "production-next")) {
        $rawAppCheckEnabled = Get-ConfigValue -Config $config -Key "APP_CHECK_ENABLED"

        if ($rawAppCheckEnabled.Trim().ToLowerInvariant() -ne "true") {
            $errors.Add("APP_CHECK_ENABLED must be true in mobile config for '$Environment'.")
        }

        if (Test-AppCheckDebugProviderRequested -Config $config) {
            $message = "App Check debug provider is configured for '$Environment'. This is allowed only for direct pre-Play-Store device validation; remove APP_CHECK_DEBUG_PROVIDER, APP_CHECK_ANDROID_PROVIDER=debug and debug tokens before the final Play Store build."
            if ($RequirePlayIntegrityAppCheck) {
                $errors.Add($message)
            } else {
                $warnings.Add($message)
            }
        }
    }

    if ($config.Contains("VIDEO_SHARE_BASE_URL")) {
        $shareBaseUrl = [string]$config["VIDEO_SHARE_BASE_URL"]
        $shareUri = $null
        if (
            -not [System.Uri]::TryCreate($shareBaseUrl, [System.UriKind]::Absolute, [ref]$shareUri) -or
            $shareUri.Scheme -ne "https" -or
            [string]::IsNullOrWhiteSpace($shareUri.Host)
        ) {
            $errors.Add("VIDEO_SHARE_BASE_URL must be an absolute HTTPS URL.")
        }

        $expectedShareBaseUrl = if ($Environment -in @("production", "production-next")) {
            "https://adfoot.org"
        } else {
            "https://adfoot-staging.firebaseapp.com"
        }

        if ($shareBaseUrl.TrimEnd("/") -ne $expectedShareBaseUrl) {
            $errors.Add("VIDEO_SHARE_BASE_URL is '$shareBaseUrl' but expected '$expectedShareBaseUrl' for '$Environment'.")
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
Write-Host "Effective native env     : $effectiveNativeEnvironment"
Write-Host "Mobile config file       : $resolvedConfigPath"
Write-Host "Planned Android package  : $plannedMobileId"
Write-Host "Planned iOS bundle ID    : $plannedMobileId"
Write-Host "Android native file      : $androidFirebasePath"
Write-Host "iOS native file          : $iosFirebasePath"
Write-Host "Require Play Integrity   : $RequirePlayIntegrityAppCheck"

if ($null -ne $config) {
    Write-Host ""
    Write-Host "Config summary:"
    foreach ($key in @("APP_ENV", "VIDEO_SHARE_BASE_URL", "FIREBASE_PROJECT_ID", "FIREBASE_STORAGE_BUCKET", "FIREBASE_IOS_BUNDLE_ID")) {
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
