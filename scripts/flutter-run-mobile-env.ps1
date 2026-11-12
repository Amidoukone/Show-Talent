param(
    [ValidateSet("local", "staging", "production", "production-next")]
    [string]$Environment = "production",

    [string]$Target = "lib/main.dart",

    [string]$DeviceId,

    [switch]$UseNativeFlavor,

    # Builds and installs the release variant, the one a tester must exercise.
    #
    # A switch and not just "pass --release yourself": in PowerShell a
    # double-dash token is a VALUE, not a parameter name, so a trailing
    # `--release` binds to the first free positional parameter instead of
    # reaching $AdditionalArgs. It silently became the value of -Target, then
    # of -DeviceId, producing `flutter run -t --release` and
    # `flutter run ... -d --release`. Both fail, but neither says why.
    [switch]$Release,

    [switch]$UseFirebaseEmulators,

    [switch]$SkipRemoteAuthPreflight,

    [string]$EmulatorHost,

    [string]$ConfigPath,

    [switch]$RequireConfig,

    [switch]$PrintOnly,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EffectiveFlavorEnvironment {
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
# Belt and braces for any step that shells out to Gradle directly
# (gradlew honours JAVA_HOME). It is NOT what decides the JDK for
# `flutter build`: Flutter reads `flutter config --jdk-dir` first and
# only falls back to JAVA_HOME. While jdk-dir pointed at JDK 17 this
# assignment looked like the fix and changed nothing -- AGP 9.3's lint
# worker still ran on 17 and died on NoSuchMethodError
# java.util.List.removeLast(). Keep jdk-dir on a JDK 21+ runtime; the
# readiness check now verifies that and fails the gate when it drifts.
# Scoped to this process either way: the user's JAVA_HOME is untouched.
$androidStudioJbr = Join-Path ${env:ProgramFiles} "Android\Android Studio\jbr"
$androidStudioJava = Join-Path $androidStudioJbr "bin\java.exe"
if (Test-Path -LiteralPath $androidStudioJava) {
    $env:JAVA_HOME = $androidStudioJbr
    $env:PATH = "$(Join-Path $androidStudioJbr 'bin');$env:PATH"
    Write-Host "Using Android Studio JBR for the Android build: $androidStudioJbr"
}
$authPreflightScript = Join-Path $repoRoot "scripts/check-mobile-auth-preflight.mjs"
$effectiveFlavorEnvironment = Get-EffectiveFlavorEnvironment -EnvironmentName $Environment
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

if ($null -eq $configDefines -and $Environment -ne "local") {
    Write-Error "Missing mobile config file for '$Environment': $resolvedConfigPath"
    Write-Error "Create it from config/mobile/$Environment.example.json before running this environment."
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
    $flutterArgs += @("--flavor", $effectiveFlavorEnvironment)
}

if ($DeviceId) {
    $flutterArgs += @("-d", $DeviceId)
}

# Appended before $AdditionalArgs so an explicit `-AdditionalArgs "--release"`
# -- the workaround that existed before this switch -- cannot double it up.
$alreadyAskedForRelease = $null -ne $AdditionalArgs -and ($AdditionalArgs -contains "--release")
if ($Release -and -not $alreadyAskedForRelease) {
    $flutterArgs += "--release"
}

if ($AdditionalArgs) {
    $flutterArgs += $AdditionalArgs
}

$previewArgs = @()
foreach ($arg in $flutterArgs) {
    $previewArgs += Mask-PreviewArg -Arg ([string]$arg)
}
$commandPreview = "flutter " + ($previewArgs -join " ")
Write-Host $commandPreview
Write-Host "Effective native flavor: $effectiveFlavorEnvironment"
if ($null -ne $configDefines) {
    Write-Host "Mobile config file: $resolvedConfigPath"
} else {
    Write-Host "Mobile config file: <none> (local placeholder defaults; real backend access may be unavailable)"
}

if ($PrintOnly) {
    exit 0
}

$shouldRunRemoteAuthPreflight =
    -not $SkipRemoteAuthPreflight -and
    -not $UseFirebaseEmulators -and
    $Environment -ne "local" -and
    $null -ne $configDefines

if ($shouldRunRemoteAuthPreflight) {
    Write-Host "Running remote Firebase Auth preflight..."
    & node $authPreflightScript --environment $Environment --config $resolvedConfigPath
    if ($LASTEXITCODE -gt 0) {
        throw "Remote Firebase Auth preflight failed (exit code $LASTEXITCODE). Use -SkipRemoteAuthPreflight to bypass."
    }
}

& flutter @flutterArgs
exit $LASTEXITCODE
