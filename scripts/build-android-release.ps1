param(
    [ValidateSet("local", "staging", "production", "production-next")]
    [string]$Environment = "production",

    [string]$Target = "lib/main.dart",
    [string]$BuildName,
    [int]$BuildNumber,

    [switch]$ReleaseGate,
    [switch]$RequireSigning,
    [switch]$RequirePlayIntegrityAppCheck,
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

function Get-MobileConfigValue {
    param(
        $MobileConfig,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -ne $MobileConfig -and $MobileConfig.Contains($Key)) {
        return [string]$MobileConfig[$Key]
    }

    return ""
}

function Test-MobileConfigUsesAppCheckDebugProvider {
    param(
        $MobileConfig
    )

    $rawForceDebugProvider = Get-MobileConfigValue -MobileConfig $MobileConfig -Key "APP_CHECK_DEBUG_PROVIDER"
    $rawAndroidProvider = Get-MobileConfigValue -MobileConfig $MobileConfig -Key "APP_CHECK_ANDROID_PROVIDER"
    $rawAndroidDebugToken = Get-MobileConfigValue -MobileConfig $MobileConfig -Key "APP_CHECK_ANDROID_DEBUG_TOKEN"
    $rawAppleDebugToken = Get-MobileConfigValue -MobileConfig $MobileConfig -Key "APP_CHECK_APPLE_DEBUG_TOKEN"

    return $rawForceDebugProvider.Trim().ToLowerInvariant() -eq "true" -or
        $rawAndroidProvider.Trim().ToLowerInvariant() -eq "debug" -or
        -not [string]::IsNullOrWhiteSpace($rawAndroidDebugToken) -or
        -not [string]::IsNullOrWhiteSpace($rawAppleDebugToken)
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

function Find-AndroidAppBundle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveNativeEnvironment
    )

    $variantBundleDir = Get-AndroidAppBundleVariantDirectory `
        -RepoRoot $RepoRoot `
        -EffectiveNativeEnvironment $EffectiveNativeEnvironment
    $preferredAab = Get-PreferredAndroidAppBundlePath `
        -RepoRoot $RepoRoot `
        -EffectiveNativeEnvironment $EffectiveNativeEnvironment

    if (Test-Path -LiteralPath $preferredAab) {
        return $preferredAab
    }

    $latestAab = Get-ChildItem -Path $variantBundleDir -Filter "*.aab" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $latestAab) {
        return $latestAab.FullName
    }

    return $null
}

function Get-AndroidAppBundleDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return Join-Path $RepoRoot "build/app/outputs/bundle"
}

function Get-AndroidAppBundleVariantDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveNativeEnvironment
    )

    $bundleDir = Get-AndroidAppBundleDirectory -RepoRoot $RepoRoot
    return Join-Path $bundleDir "$($EffectiveNativeEnvironment)Release"
}

function Get-PreferredAndroidAppBundlePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveNativeEnvironment
    )

    $variantBundleDir = Get-AndroidAppBundleVariantDirectory `
        -RepoRoot $RepoRoot `
        -EffectiveNativeEnvironment $EffectiveNativeEnvironment
    return Join-Path $variantBundleDir "app-$EffectiveNativeEnvironment-release.aab"
}

function Test-PathIsUnderDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullDirectory = [System.IO.Path]::GetFullPath($Directory)
    if (-not $fullDirectory.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullDirectory = "$fullDirectory$([System.IO.Path]::DirectorySeparatorChar)"
    }

    return $fullPath.StartsWith($fullDirectory, [System.StringComparison]::OrdinalIgnoreCase)
}

function Clear-AndroidAppBundleOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveNativeEnvironment
    )

    $variantBundleDir = Get-AndroidAppBundleVariantDirectory `
        -RepoRoot $RepoRoot `
        -EffectiveNativeEnvironment $EffectiveNativeEnvironment

    if (-not (Test-Path -LiteralPath $variantBundleDir)) {
        return
    }

    if (-not (Test-PathIsUnderDirectory -Path $variantBundleDir -Directory $RepoRoot)) {
        throw "Refusing to clean Android bundle output outside the repository: '$variantBundleDir'."
    }

    Get-ChildItem -Path $variantBundleDir -Filter "*.aab" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

function ConvertTo-LongPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (
        [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
        -not $fullPath.StartsWith("\\?\", [System.StringComparison]::Ordinal)
    ) {
        return "\\?\$fullPath"
    }

    return $fullPath
}

function Clear-GeneratedBuildDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $buildDir = Join-Path $RepoRoot "build"
    if (-not (Test-Path -LiteralPath $buildDir)) {
        return
    }

    if (-not (Test-PathIsUnderDirectory -Path $buildDir -Directory $RepoRoot)) {
        throw "Refusing to clean build directory outside the repository: '$buildDir'."
    }

    $buildDirForDelete = ConvertTo-LongPath -Path $buildDir
    Remove-Item -LiteralPath $buildDirForDelete -Recurse -Force
}

function Test-AabContainsFlutterDebugSymbols {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AabPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::OpenRead($AabPath)
    try {
        foreach ($entry in $zip.Entries) {
            if (
                $entry.FullName -match '^BUNDLE-METADATA/com\.android\.tools\.build\.debugsymbols/.+/libflutter\.so\.(sym|dbg)$'
            ) {
                return $true
            }
        }
    } finally {
        $zip.Dispose()
    }

    return $false
}

function Get-RepoLockHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $normalized = [System.IO.Path]::GetFullPath($RepoRoot).ToLowerInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hash = $sha256.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha256.Dispose()
    }
}

function New-AndroidReleaseBuildLock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $lockRoot = Join-Path ([System.IO.Path]::GetTempPath()) "adfoot-release-locks"
    New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null

    $lockHash = Get-RepoLockHash -RepoRoot $RepoRoot
    $lockPath = Join-Path $lockRoot "android-release-$lockHash.lock"

    try {
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    } catch {
        throw "Another Android release build is already running for this repository. Stop it before starting a new release build. Lock file: $lockPath"
    }

    $lockStream.SetLength(0)
    $writer = New-Object System.IO.StreamWriter($lockStream, [System.Text.Encoding]::UTF8, 1024, $true)
    try {
        $writer.WriteLine("repo=$RepoRoot")
        $writer.WriteLine("pid=$PID")
        $writer.WriteLine("startedAt=$((Get-Date).ToString("o"))")
        $writer.Flush()
        $lockStream.Flush()
    } finally {
        $writer.Dispose()
    }

    return $lockStream
}

function Assert-NoConflictingAndroidBuildProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return
    }

    $fullRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    $conflicts = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                if ([string]::IsNullOrWhiteSpace($commandLine)) {
                    $false
                } else {
                    $isSameRepo = $commandLine.IndexOf($fullRepoRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    $isAndroidBundle = (
                        $commandLine.IndexOf("GradleWrapperMain", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                        $commandLine.IndexOf("bundle", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    )

                    $isSameRepo -and $isAndroidBundle
                }
            } |
            Select-Object ProcessId, Name, CommandLine
    )

    if ($conflicts.Count -gt 0) {
        $summary = ($conflicts | ForEach-Object { "$($_.ProcessId) $($_.Name)" }) -join ", "
        throw "Another Android/Gradle bundle build is already running for this repository ($summary). Stop it before starting a new release build."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$effectiveNativeEnvironment = Get-EffectiveNativeEnvironment -EnvironmentName $Environment
$preflightScript = Join-Path $repoRoot "scripts/check-android-release-readiness.ps1"
$mobileConfigPath = Join-Path $repoRoot "config/mobile/$Environment.json"
$releaseBuildLock = $null

Push-Location $repoRoot
try {
    if (-not $PrintOnly) {
        Assert-NoConflictingAndroidBuildProcess -RepoRoot $repoRoot
        $releaseBuildLock = New-AndroidReleaseBuildLock -RepoRoot $repoRoot
    }

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

    $mobileConfig = Read-MobileConfig -Path $mobileConfigPath
    if ($null -eq $mobileConfig -and ($Environment -ne "local" -or $ReleaseGate)) {
        throw "Missing required mobile config file for '$Environment': $mobileConfigPath"
    }

    if (
        $null -ne $mobileConfig -and
        $mobileConfig.Contains("APP_ENV") -and
        $mobileConfig["APP_ENV"] -ne $Environment
    ) {
        throw "Mobile config APP_ENV '$($mobileConfig["APP_ENV"])' does not match requested environment '$Environment'."
    }

    if ($Environment -in @("production", "production-next")) {
        $rawAppCheckEnabled = Get-MobileConfigValue -MobileConfig $mobileConfig -Key "APP_CHECK_ENABLED"

        if ($rawAppCheckEnabled.Trim().ToLowerInvariant() -ne "true") {
            throw "APP_CHECK_ENABLED must be true in mobile config for '$Environment'."
        }

        if (Test-MobileConfigUsesAppCheckDebugProvider -MobileConfig $mobileConfig) {
            $message = "App Check debug provider is configured for '$Environment'. This is allowed only for direct pre-Play-Store device validation; remove APP_CHECK_DEBUG_PROVIDER, APP_CHECK_ANDROID_PROVIDER=debug and debug tokens before the final Play Store build."
            if ($RequirePlayIntegrityAppCheck) {
                throw $message
            }

            Write-Warning $message
        }
    }

    $dartDefines = [ordered]@{}
    if ($null -ne $mobileConfig) {
        foreach ($entry in $mobileConfig.GetEnumerator()) {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
                $dartDefines[[string]$entry.Key] = [string]$entry.Value
            }
        }
    }
    $dartDefines["APP_ENV"] = $Environment

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
    Write-Host "Require Play Integrity App Check: $RequirePlayIntegrityAppCheck"
    if ($null -ne $mobileConfig) {
        Write-Host "Mobile config file: $mobileConfigPath"
    } else {
        Write-Host "Mobile config file: <none>"
    }

    if ($PrintOnly) {
        exit 0
    }

    if ($Clean) {
        Clear-GeneratedBuildDirectory -RepoRoot $repoRoot

        & flutter clean
        if ($LASTEXITCODE -gt 0) {
            throw "flutter clean failed (exit code $LASTEXITCODE)."
        }

        & flutter pub get
        if ($LASTEXITCODE -gt 0) {
            throw "flutter pub get failed (exit code $LASTEXITCODE)."
        }
    }

    $bundleDir = Get-AndroidAppBundleDirectory -RepoRoot $repoRoot
    Clear-AndroidAppBundleOutput `
        -RepoRoot $repoRoot `
        -EffectiveNativeEnvironment $effectiveNativeEnvironment

    $buildStartedAt = Get-Date
    & flutter @flutterArgs
    $flutterExitCode = $LASTEXITCODE

    $aabPath = Find-AndroidAppBundle -RepoRoot $repoRoot -EffectiveNativeEnvironment $effectiveNativeEnvironment

    if ($flutterExitCode -gt 0) {
        $canAcceptFlutterDebugSymbolFalseNegative = $false

        if (-not [string]::IsNullOrWhiteSpace([string]$aabPath) -and (Test-Path -LiteralPath $aabPath)) {
            $aabFile = Get-Item -LiteralPath $aabPath
            $wasProducedByThisBuild = $aabFile.LastWriteTime -ge $buildStartedAt.AddMinutes(-5)
            $hasFlutterDebugSymbols = Test-AabContainsFlutterDebugSymbols -AabPath $aabPath
            $canAcceptFlutterDebugSymbolFalseNegative = $wasProducedByThisBuild -and $hasFlutterDebugSymbols

            if ($canAcceptFlutterDebugSymbolFalseNegative) {
                Write-Host ""
                Write-Host "Flutter returned exit code $flutterExitCode after producing an AAB with native debug symbols."
                Write-Host "Continuing because this matches Flutter's apkanalyzer/cmdline-tools debug-symbol check false negative."
            }
        }

        if (-not $canAcceptFlutterDebugSymbolFalseNegative) {
            throw "flutter build appbundle failed (exit code $flutterExitCode)."
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
    if ($null -ne $releaseBuildLock) {
        $releaseBuildLock.Dispose()
    }
    Pop-Location
}

exit 0
