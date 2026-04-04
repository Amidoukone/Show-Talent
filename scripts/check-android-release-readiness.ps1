param(
    [ValidateSet("local", "staging", "production")]
    [string]$Environment = "production",

    [switch]$ReleaseGate,
    [switch]$RequireSigning,
    [switch]$RequireLegalUrls,
    [switch]$RequireNativeFirebase,
    [switch]$RequireVersionBump
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ReleaseGate) {
    if (-not $PSBoundParameters.ContainsKey("RequireSigning")) {
        $RequireSigning = $Environment -eq "production"
    }
    if (-not $PSBoundParameters.ContainsKey("RequireLegalUrls")) {
        $RequireLegalUrls = $Environment -eq "production"
    }
    if (-not $PSBoundParameters.ContainsKey("RequireNativeFirebase")) {
        $RequireNativeFirebase = $true
    }
    if (-not $PSBoundParameters.ContainsKey("RequireVersionBump")) {
        $RequireVersionBump = $Environment -eq "production"
    }
}

function Get-PlannedPackageId {
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

function Get-PlannedAppName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )

    switch ($EnvironmentName) {
        "local" { return "Adfoot Local" }
        "staging" { return "Adfoot Staging" }
        default { return "Adfoot" }
    }
}

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

        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key) {
            $result[$key] = $value
        }
    }

    return $result
}

$warnings = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]

$repoRoot = Split-Path -Parent $PSScriptRoot
$expectedPackage = Get-PlannedPackageId -EnvironmentName $Environment
$expectedAppName = Get-PlannedAppName -EnvironmentName $Environment

$gradlePath = Join-Path $repoRoot "android/app/build.gradle"
$manifestPath = Join-Path $repoRoot "android/app/src/main/AndroidManifest.xml"
$keyPropertiesPath = Join-Path $repoRoot "android/key.properties"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$androidFirebasePath = Join-Path $repoRoot "android/app/src/$Environment/google-services.json"
$privacyPagePath = Join-Path $repoRoot "site_pub/legal/privacy-policy.html"
$accountDeletionPagePath = Join-Path $repoRoot "site_pub/legal/account-deletion.html"
$assetLinksPath = Join-Path $repoRoot "site_pub/.well-known/assetlinks.json"
$storeComplianceDocPath = Join-Path $repoRoot "docs/store-compliance.md"

if (-not (Test-Path -LiteralPath $gradlePath)) {
    $errors.Add("Missing Android Gradle file: $gradlePath")
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    $errors.Add("Missing Android manifest: $manifestPath")
}

if (-not (Test-Path -LiteralPath $pubspecPath)) {
    $errors.Add("Missing pubspec file: $pubspecPath")
}

if ($errors.Count -eq 0) {
    $gradleRaw = Get-Content -LiteralPath $gradlePath -Raw
    $manifestRaw = Get-Content -LiteralPath $manifestPath -Raw
    $pubspecRaw = Get-Content -LiteralPath $pubspecPath -Raw

    $namespaceMatch = [regex]::Match($gradleRaw, 'namespace\s*=\s*"([^"]+)"')
    $baseApplicationIdMatch = [regex]::Match($gradleRaw, 'applicationId\s*=\s*"([^"]+)"')

    $androidNamespace = if ($namespaceMatch.Success) {
        $namespaceMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    $baseApplicationId = if ($baseApplicationIdMatch.Success) {
        $baseApplicationIdMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    $suffixPattern = "(?s)$Environment\s*\{.*?applicationIdSuffix\s+""([^""]+)"""
    $suffixMatch = [regex]::Match($gradleRaw, $suffixPattern)
    $applicationIdSuffix = if ($suffixMatch.Success) {
        $suffixMatch.Groups[1].Value.Trim()
    } else {
        ""
    }

    $effectiveApplicationId = $baseApplicationId
    if ($applicationIdSuffix) {
        if ($applicationIdSuffix.StartsWith(".")) {
            $effectiveApplicationId = "$baseApplicationId$applicationIdSuffix"
        } else {
            $effectiveApplicationId = "$baseApplicationId.$applicationIdSuffix"
        }
    }

    $appNamePattern = "(?s)$Environment\s*\{.*?resValue\s+""string""\s*,\s*""app_name""\s*,\s*""([^""]+)"""
    $appNameMatch = [regex]::Match($gradleRaw, $appNamePattern)
    $configuredAppName = if ($appNameMatch.Success) {
        $appNameMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    if ($androidNamespace -ne "org.adfoot.app") {
        $errors.Add("Android namespace is '$androidNamespace' but expected 'org.adfoot.app'.")
    }

    if ($effectiveApplicationId -ne $expectedPackage) {
        $errors.Add(
            "Effective applicationId for '$Environment' is '$effectiveApplicationId' but expected '$expectedPackage'."
        )
    }

    if ($configuredAppName -ne $expectedAppName) {
        $errors.Add(
            "Configured app_name for '$Environment' is '$configuredAppName' but expected '$expectedAppName'."
        )
    }

    if ($gradleRaw -notmatch '(?s)release\s*\{.*?minifyEnabled\s+true') {
        $errors.Add("Android release build type does not enable minifyEnabled=true.")
    }

    if ($gradleRaw -notmatch '(?s)release\s*\{.*?shrinkResources\s+true') {
        $errors.Add("Android release build type does not enable shrinkResources=true.")
    }

    if ($manifestRaw -notmatch 'android\.permission\.INTERNET') {
        $errors.Add("Android manifest is missing INTERNET permission.")
    }

    if ($manifestRaw -notmatch 'android\.permission\.POST_NOTIFICATIONS') {
        $warnings.Add("Android manifest is missing POST_NOTIFICATIONS permission.")
    }

    if ($manifestRaw -notmatch 'android:autoVerify\s*=\s*"true"') {
        $warnings.Add("No android:autoVerify=true app link intent filter found in Android manifest.")
    }

    if ($manifestRaw -notmatch 'android:host\s*=\s*"adfoot\.org"') {
        $warnings.Add("No app link host 'adfoot.org' found in Android manifest.")
    }

    $versionMatch = [regex]::Match(
        $pubspecRaw,
        '(?m)^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
    )

    if ($versionMatch.Success) {
        $buildName = $versionMatch.Groups[1].Value
        $buildNumber = [int]$versionMatch.Groups[2].Value

        if ($buildNumber -lt 1) {
            $errors.Add(
                "pubspec version is '$buildName+$buildNumber'. Build number must be >= 1."
            )
        } elseif ($RequireVersionBump -and $buildNumber -le 1) {
            $warnings.Add(
                "pubspec build number is '$buildNumber'. If this is not the first store upload, increase it."
            )
        } elseif ($buildNumber -le 1) {
            $warnings.Add(
                "pubspec build number is '$buildNumber'. Consider increasing it before release."
            )
        }
    } else {
        $warnings.Add("Could not parse pubspec version format '<semver>+<buildNumber>'.")
    }
}

if (Test-Path -LiteralPath $androidFirebasePath) {
    try {
        $androidFirebaseJson = Get-Content -LiteralPath $androidFirebasePath -Raw | ConvertFrom-Json
        $firstClient = @($androidFirebaseJson.client)[0]
        $firebasePackage = [string]$firstClient.client_info.android_client_info.package_name
        if ($firebasePackage -ne $expectedPackage) {
            $errors.Add(
                "Android native Firebase package for '$Environment' is '$firebasePackage' but expected '$expectedPackage'."
            )
        }
    } catch {
        $errors.Add("Could not parse '$androidFirebasePath'. $($_.Exception.Message)")
    }
} else {
    $message = "Missing Android native Firebase file: $androidFirebasePath"
    if ($RequireNativeFirebase) {
        $errors.Add($message)
    } else {
        $warnings.Add($message)
    }
}

if (Test-Path -LiteralPath $keyPropertiesPath) {
    $keyProps = Read-KeyValueFile -Path $keyPropertiesPath
    foreach ($requiredKey in @("storePassword", "keyPassword", "keyAlias", "storeFile")) {
        if (-not $keyProps.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$keyProps[$requiredKey])) {
            $errors.Add("android/key.properties is missing key '$requiredKey'.")
        }
    }

    if ($keyProps.ContainsKey("storeFile") -and -not [string]::IsNullOrWhiteSpace([string]$keyProps["storeFile"])) {
        $androidDir = Join-Path $repoRoot "android"
        $rawStoreFile = [string]$keyProps["storeFile"]
        $resolvedStoreFile = if ([System.IO.Path]::IsPathRooted($rawStoreFile)) {
            $rawStoreFile
        } else {
            Join-Path $androidDir $rawStoreFile
        }

        if (-not (Test-Path -LiteralPath $resolvedStoreFile)) {
            $message = "Release keystore file does not exist: $resolvedStoreFile"
            if ($RequireSigning) {
                $errors.Add($message)
            } else {
                $warnings.Add($message)
            }
        }
    }
} else {
    $message = "Missing android/key.properties. Release build falls back to debug signing."
    if ($RequireSigning) {
        $errors.Add($message)
    } else {
        $warnings.Add($message)
    }
}

foreach ($legalPath in @($privacyPagePath, $accountDeletionPagePath, $assetLinksPath)) {
    if (-not (Test-Path -LiteralPath $legalPath)) {
        $message = "Missing store/compliance file: $legalPath"
        if ($RequireLegalUrls) {
            $errors.Add($message)
        } else {
            $warnings.Add($message)
        }
    }
}

if (Test-Path -LiteralPath $assetLinksPath) {
    $assetLinksRaw = Get-Content -LiteralPath $assetLinksPath -Raw

    if ($assetLinksRaw -match 'REPLACE_WITH_') {
        $message = "assetlinks.json still contains placeholder fingerprints."
        if ($RequireLegalUrls) {
            $errors.Add($message)
        } else {
            $warnings.Add($message)
        }
    }

    if ($assetLinksRaw -notmatch '"package_name"\s*:\s*"org\.adfoot\.app"') {
        $message = "assetlinks.json does not reference org.adfoot.app."
        if ($RequireLegalUrls) {
            $errors.Add($message)
        } else {
            $warnings.Add($message)
        }
    }
}

if (Test-Path -LiteralPath $storeComplianceDocPath) {
    $storeDocRaw = Get-Content -LiteralPath $storeComplianceDocPath -Raw
    if ($storeDocRaw -notmatch 'https://adfoot\.org/legal/privacy-policy\.html') {
        $warnings.Add("docs/store-compliance.md does not contain the privacy policy URL.")
    }
    if ($storeDocRaw -notmatch 'https://adfoot\.org/legal/account-deletion\.html') {
        $warnings.Add("docs/store-compliance.md does not contain the account deletion URL.")
    }
} else {
    $warnings.Add("Missing store compliance doc: $storeComplianceDocPath")
}

Write-Host "Environment                 : $Environment"
Write-Host "Expected package            : $expectedPackage"
Write-Host "Expected app name           : $expectedAppName"
Write-Host "Release gate mode           : $ReleaseGate"
Write-Host "Require signing             : $RequireSigning"
Write-Host "Require legal URLs          : $RequireLegalUrls"
Write-Host "Require native Firebase     : $RequireNativeFirebase"
Write-Host "Require version bump        : $RequireVersionBump"

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
Write-Host "Android release readiness check completed."
exit 0
