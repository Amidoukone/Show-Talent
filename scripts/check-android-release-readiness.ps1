param(
    [ValidateSet("local", "staging", "production", "production-next")]
    [string]$Environment = "production",

    [switch]$ReleaseGate,
    [switch]$RequireSigning,
    [switch]$RequireLegalUrls,
    [switch]$RequireNativeFirebase,
    [switch]$RequireVersionBump,
    [switch]$RequirePlayIntegrityAppCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($ReleaseGate) {
    if (-not $PSBoundParameters.ContainsKey("RequireSigning")) {
        $RequireSigning = $Environment -in @("production", "production-next")
    }
    if (-not $PSBoundParameters.ContainsKey("RequireLegalUrls")) {
        $RequireLegalUrls = $Environment -in @("production", "production-next")
    }
    if (-not $PSBoundParameters.ContainsKey("RequireNativeFirebase")) {
        $RequireNativeFirebase = $true
    }
    if (-not $PSBoundParameters.ContainsKey("RequireVersionBump")) {
        $RequireVersionBump = $Environment -in @("production", "production-next")
    }
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

function Read-FlatJsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in '$Path'. $($_.Exception.Message)"
    }

    if ($null -eq $json) {
        return $result
    }

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

function Get-ConfigValue {
    param(
        $Config,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -ne $Config -and $Config.Contains($Key)) {
        return [string]$Config[$Key]
    }

    return ""
}

function Test-AppCheckDebugProviderRequested {
    param(
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

function Get-ConfiguredJavaHome {
    $userJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    if (-not [string]::IsNullOrWhiteSpace($userJavaHome)) {
        return $userJavaHome
    }

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        return $env:JAVA_HOME
    }

    $machineJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (-not [string]::IsNullOrWhiteSpace($machineJavaHome)) {
        return $machineJavaHome
    }

    return ""
}

function Resolve-KeytoolPath {
    $javaHome = Get-ConfiguredJavaHome
    $candidateKeytool = if ($javaHome) {
        Join-Path $javaHome "bin/keytool.exe"
    } else {
        ""
    }

    if ($candidateKeytool -and (Test-Path -LiteralPath $candidateKeytool)) {
        return $candidateKeytool
    }

    return "keytool"
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

    if ([string]::IsNullOrWhiteSpace($ResolvedKeyPassword)) {
        $ResolvedKeyPassword = $ResolvedStorePassword
    }

    $keytool = Resolve-KeytoolPath
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
        throw "keytool failed to read release keystore fingerprint (exit code $LASTEXITCODE)."
    }

    $line = $output | Where-Object { $_ -match 'SHA\s*256:\s*([A-F0-9:]+)' } | Select-Object -First 1
    if ($null -eq $line) {
        throw "Unable to extract SHA256 fingerprint from keytool output."
    }

    $match = [regex]::Match([string]$line, 'SHA\s*256:\s*([A-F0-9:]+)')
    if (-not $match.Success) {
        throw "Unable to parse SHA256 fingerprint."
    }

    return $match.Groups[1].Value.Trim()
}

function Test-FileStartsWithUtf8Bom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 3) {
            return $false
        }

        $bytes = New-Object byte[] 3
        [void]$stream.Read($bytes, 0, 3)
        return $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    } finally {
        $stream.Dispose()
    }
}

function Get-JavaMajorVersion {
    $javaHome = Get-ConfiguredJavaHome
    $javaExecutable = if ($javaHome) {
        $candidateJava = Join-Path $javaHome "bin/java.exe"
        if (Test-Path -LiteralPath $candidateJava) {
            $candidateJava
        } else {
            "java"
        }
    } else {
        "java"
    }

    try {
        $javaOutput = & cmd.exe /c "`"$javaExecutable`" -version 2>&1" | ForEach-Object { $_.ToString() }
    } catch {
        return $null
    }

    if ($LASTEXITCODE -gt 0 -or $null -eq $javaOutput) {
        return $null
    }

    $versionText = $javaOutput -join "`n"
    $match = [regex]::Match($versionText, 'version\s+"([^"]+)"')
    if (-not $match.Success) {
        return $null
    }

    $version = $match.Groups[1].Value
    if ($version.StartsWith("1.")) {
        $legacyMatch = [regex]::Match($version, '^1\.(\d+)')
        if ($legacyMatch.Success) {
            return [int]$legacyMatch.Groups[1].Value
        }
    }

    $majorMatch = [regex]::Match($version, '^(\d+)')
    if ($majorMatch.Success) {
        return [int]$majorMatch.Groups[1].Value
    }

    return $null
}

function Get-ConfiguredAndroidSdkRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $localPropertiesPath = Join-Path $RepoRoot "android/local.properties"
    if (Test-Path -LiteralPath $localPropertiesPath) {
        $localProps = Read-KeyValueFile -Path $localPropertiesPath
        if (
            $localProps.ContainsKey("sdk.dir") -and
            -not [string]::IsNullOrWhiteSpace([string]$localProps["sdk.dir"])
        ) {
            return ([string]$localProps["sdk.dir"]) -replace '\\\\', '\'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
        return $env:ANDROID_SDK_ROOT
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
        return $env:ANDROID_HOME
    }

    return ""
}

function Test-AndroidSdkPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SdkRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $packagePath = Join-Path $SdkRoot $RelativePath
    return Test-Path -LiteralPath $packagePath
}

$warnings = New-Object System.Collections.Generic.List[string]
$errors = New-Object System.Collections.Generic.List[string]

$repoRoot = Split-Path -Parent $PSScriptRoot
$effectiveNativeEnvironment = Get-EffectiveNativeEnvironment -EnvironmentName $Environment
$expectedPackage = Get-PlannedPackageId -EnvironmentName $Environment
$expectedAppName = Get-PlannedAppName -EnvironmentName $Environment
$expectedAgpVersionPattern = '^8\.11\.'
$expectedAgpVersionLabel = "8.11.x"
$expectedGradleVersion = "8.14.3"
$expectedCompileSdk = "36"
$expectedTargetSdk = "36"
$expectedBuildToolsVersion = "35.0.0"
$expectedNdkVersion = "29.0.13599879"

$gradlePath = Join-Path $repoRoot "android/app/build.gradle"
$manifestPath = Join-Path $repoRoot "android/app/src/main/AndroidManifest.xml"
$settingsGradlePath = Join-Path $repoRoot "android/settings.gradle"
$gradleWrapperPath = Join-Path $repoRoot "android/gradle/wrapper/gradle-wrapper.properties"
$keyPropertiesPath = Join-Path $repoRoot "android/key.properties"
$mobileConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$androidFirebasePath = Join-Path $repoRoot "android/app/src/$effectiveNativeEnvironment/google-services.json"
$privacyPagePath = Join-Path $repoRoot "site_pub/legal/privacy-policy.html"
$accountDeletionPagePath = Join-Path $repoRoot "site_pub/legal/account-deletion.html"
$assetLinksPath = Join-Path $repoRoot "site_pub/.well-known/assetlinks.json"
$storeComplianceDocPath = Join-Path $repoRoot "docs/store-compliance.md"
$releaseSigningFingerprint = ""

if (-not (Test-Path -LiteralPath $gradlePath)) {
    $errors.Add("Missing Android Gradle file: $gradlePath")
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    $errors.Add("Missing Android manifest: $manifestPath")
}

if (-not (Test-Path -LiteralPath $pubspecPath)) {
    $errors.Add("Missing pubspec file: $pubspecPath")
}

if (-not (Test-Path -LiteralPath $settingsGradlePath)) {
    $errors.Add("Missing Android settings Gradle file: $settingsGradlePath")
}

if (-not (Test-Path -LiteralPath $gradleWrapperPath)) {
    $errors.Add("Missing Android Gradle wrapper file: $gradleWrapperPath")
}

if ($errors.Count -eq 0) {
    $gradleRaw = Get-Content -LiteralPath $gradlePath -Raw
    $manifestRaw = Get-Content -LiteralPath $manifestPath -Raw
    $pubspecRaw = Get-Content -LiteralPath $pubspecPath -Raw
    $settingsGradleRaw = Get-Content -LiteralPath $settingsGradlePath -Raw
    $gradleWrapperRaw = Get-Content -LiteralPath $gradleWrapperPath -Raw

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

    $agpVersionMatch = [regex]::Match(
        $settingsGradleRaw,
        'id\s+"com\.android\.application"\s+version\s+"([^"]+)"'
    )
    $agpVersion = if ($agpVersionMatch.Success) {
        $agpVersionMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    $gradleWrapperVersionMatch = [regex]::Match(
        $gradleWrapperRaw,
        'gradle-([0-9.]+)-bin\.zip'
    )
    $gradleWrapperVersion = if ($gradleWrapperVersionMatch.Success) {
        $gradleWrapperVersionMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    $suffixPattern = "(?s)$effectiveNativeEnvironment\s*\{.*?applicationIdSuffix\s+""([^""]+)"""
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

    $appNamePattern = "(?s)$effectiveNativeEnvironment\s*\{.*?resValue\s+""string""\s*,\s*""app_name""\s*,\s*""([^""]+)"""
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

    if ($agpVersion -notmatch $expectedAgpVersionPattern) {
        $errors.Add(
            "Android Gradle Plugin version is '$agpVersion'. Flutter 3.44 release builds should use AGP $expectedAgpVersionLabel with Gradle $expectedGradleVersion."
        )
    }

    if ($gradleWrapperVersion -ne $expectedGradleVersion) {
        $errors.Add(
            "Gradle wrapper version is '$gradleWrapperVersion' but expected '$expectedGradleVersion'."
        )
    }

    if ($gradleRaw -notmatch "compileSdk\s*=\s*$expectedCompileSdk") {
        $errors.Add("Android compileSdk must be $expectedCompileSdk.")
    }

    if ($gradleRaw -notmatch "targetSdk\s*=\s*$expectedTargetSdk") {
        $errors.Add("Android targetSdk must be $expectedTargetSdk.")
    }

    if ($gradleRaw -notmatch "buildToolsVersion\s*=\s*`"$([regex]::Escape($expectedBuildToolsVersion))`"") {
        $errors.Add("Android buildToolsVersion must be '$expectedBuildToolsVersion'.")
    }

    if ($gradleRaw -notmatch '(?s)release\s*\{.*?minifyEnabled\s+true') {
        $errors.Add("Android release build type does not enable minifyEnabled=true.")
    }

    if ($gradleRaw -notmatch '(?s)release\s*\{.*?shrinkResources\s+true') {
        $errors.Add("Android release build type does not enable shrinkResources=true.")
    }

    if ($gradleRaw -notmatch 'storeFile\s+keystoreProperties\["storeFile"\]\s*\?\s*rootProject\.file\(keystoreProperties\["storeFile"\]\)') {
        $errors.Add("Android release signing must resolve key.properties storeFile relative to the android rootProject.")
    }

    $ndkVersionMatch = [regex]::Match($gradleRaw, 'ndkVersion\s*=\s*"([^"]+)"')
    $ndkVersion = if ($ndkVersionMatch.Success) {
        $ndkVersionMatch.Groups[1].Value.Trim()
    } else {
        "<missing>"
    }

    if ($ndkVersion -ne $expectedNdkVersion) {
        $errors.Add(
            "Android ndkVersion is '$ndkVersion'. Expected '$expectedNdkVersion' for consistent 16 KB page-size release builds."
        )
    }

    if ($gradleRaw -notmatch '(?s)jniLibs\s*\{.*?useLegacyPackaging\s+true') {
        $errors.Add(
            "Android native library packaging does not enable useLegacyPackaging=true for 16 KB page-size compatibility."
        )
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

$javaMajorVersion = Get-JavaMajorVersion
if ($null -eq $javaMajorVersion) {
    $errors.Add("Unable to determine Java version. Install JDK 17 and configure JAVA_HOME/flutter --jdk-dir.")
} elseif ($javaMajorVersion -ne 17) {
    $errors.Add("Java major version is '$javaMajorVersion'. Android release builds must use JDK 17, not newer JDKs.")
}

$androidSdkRoot = Get-ConfiguredAndroidSdkRoot -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) {
    $errors.Add("Android SDK root is not configured. Set sdk.dir in android/local.properties or ANDROID_SDK_ROOT.")
} elseif (-not (Test-Path -LiteralPath $androidSdkRoot)) {
    $errors.Add("Android SDK root does not exist: $androidSdkRoot")
} else {
    $requiredAndroidPackages = [ordered]@{
        "cmdline-tools/latest/bin/sdkmanager.bat" = "Android SDK Command-line Tools latest"
        "platform-tools" = "Android SDK Platform-Tools"
        "platforms/android-$expectedCompileSdk" = "Android SDK Platform $expectedCompileSdk"
        "build-tools/$expectedBuildToolsVersion" = "Android SDK Build-Tools $expectedBuildToolsVersion"
        "ndk/$expectedNdkVersion" = "Android NDK $expectedNdkVersion"
    }

    foreach ($entry in $requiredAndroidPackages.GetEnumerator()) {
        if (-not (Test-AndroidSdkPackage -SdkRoot $androidSdkRoot -RelativePath $entry.Key)) {
            $errors.Add("Missing $($entry.Value) under Android SDK root '$androidSdkRoot'.")
        }
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

if ($Environment -in @("production", "production-next")) {
    try {
        $mobileConfig = Read-FlatJsonFile -Path $mobileConfigPath
        if ($null -eq $mobileConfig) {
            $message = "Missing mobile config file: $mobileConfigPath"
            if ($ReleaseGate) {
                $errors.Add($message)
            } else {
                $warnings.Add($message)
            }
        } elseif (Test-AppCheckDebugProviderRequested -Config $mobileConfig) {
            $message = "App Check debug provider is configured for '$Environment'. This is allowed only for direct pre-Play-Store device validation; remove APP_CHECK_DEBUG_PROVIDER, APP_CHECK_ANDROID_PROVIDER=debug and debug tokens before the final Play Store build."
            if ($RequirePlayIntegrityAppCheck) {
                $errors.Add($message)
            } else {
                $warnings.Add($message)
            }
        }
    } catch {
        $errors.Add("Could not validate mobile App Check config '$mobileConfigPath'. $($_.Exception.Message)")
    }
}

if (Test-Path -LiteralPath $keyPropertiesPath) {
    if (Test-FileStartsWithUtf8Bom -Path $keyPropertiesPath) {
        $errors.Add("android/key.properties starts with a UTF-8 BOM. Regenerate it with npm.cmd run release:android:signing:setup so Gradle can read storePassword correctly.")
    }

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
        } elseif (
            $keyProps.ContainsKey("storePassword") -and
            -not [string]::IsNullOrWhiteSpace([string]$keyProps["storePassword"]) -and
            $keyProps.ContainsKey("keyAlias") -and
            -not [string]::IsNullOrWhiteSpace([string]$keyProps["keyAlias"])
        ) {
            try {
                $releaseSigningFingerprint = Get-Sha256Fingerprint `
                    -ResolvedKeystorePath $resolvedStoreFile `
                    -Alias ([string]$keyProps["keyAlias"]) `
                    -ResolvedStorePassword ([string]$keyProps["storePassword"]) `
                    -ResolvedKeyPassword ([string]$keyProps["keyPassword"])
            } catch {
                $message = "Could not read release keystore SHA-256 fingerprint. $($_.Exception.Message)"
                if ($RequireSigning) {
                    $errors.Add($message)
                } else {
                    $warnings.Add($message)
                }
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

    if (
        $RequireSigning -and
        $expectedPackage -eq "org.adfoot.app" -and
        -not [string]::IsNullOrWhiteSpace($releaseSigningFingerprint)
    ) {
        try {
            $assetLinks = $assetLinksRaw | ConvertFrom-Json
            $releaseEntries = @($assetLinks | Where-Object {
                [string]$_.target.package_name -eq "org.adfoot.app"
            })
            $releaseFingerprints = @()

            foreach ($entry in $releaseEntries) {
                foreach ($fingerprint in @($entry.target.sha256_cert_fingerprints)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$fingerprint)) {
                        $releaseFingerprints += [string]$fingerprint
                    }
                }
            }

            if ($releaseFingerprints -notcontains $releaseSigningFingerprint) {
                $message = "assetlinks.json fingerprint for org.adfoot.app does not match the release keystore SHA-256. Run npm.cmd run release:android:assetlinks:update after the final upload key is set."
                if ($RequireLegalUrls) {
                    $errors.Add($message)
                } else {
                    $warnings.Add($message)
                }
            }
        } catch {
            $message = "Could not parse assetlinks.json for fingerprint validation. $($_.Exception.Message)"
            if ($RequireLegalUrls) {
                $errors.Add($message)
            } else {
                $warnings.Add($message)
            }
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
Write-Host "Effective native env        : $effectiveNativeEnvironment"
Write-Host "Expected package            : $expectedPackage"
Write-Host "Expected app name           : $expectedAppName"
Write-Host "Expected AGP                : $expectedAgpVersionLabel"
Write-Host "Expected Gradle wrapper     : $expectedGradleVersion"
Write-Host "Expected Android SDK        : compile $expectedCompileSdk / target $expectedTargetSdk, build-tools $expectedBuildToolsVersion, NDK $expectedNdkVersion"
Write-Host "Detected Java major         : $(if ($null -eq $javaMajorVersion) { '<unknown>' } else { $javaMajorVersion })"
Write-Host "Android SDK root            : $(if ([string]::IsNullOrWhiteSpace($androidSdkRoot)) { '<missing>' } else { $androidSdkRoot })"
Write-Host "Release gate mode           : $ReleaseGate"
Write-Host "Require signing             : $RequireSigning"
Write-Host "Require legal URLs          : $RequireLegalUrls"
Write-Host "Require native Firebase     : $RequireNativeFirebase"
Write-Host "Require version bump        : $RequireVersionBump"
Write-Host "Require Play Integrity      : $RequirePlayIntegrityAppCheck"

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
