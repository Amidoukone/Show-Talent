param(
    [switch]$Strict,
    [switch]$SkipLocal,
    [switch]$SkipStaging,
    [switch]$SkipProduction,
    [switch]$SkipMobileChecks,
    [switch]$SkipFunctionsChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Action
    if ($LASTEXITCODE -gt 0) {
        throw "$Name failed (exit code $LASTEXITCODE)."
    }
}

function Read-DotEnvFile {
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

function Merge-Maps {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,
        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    $merged = @{}
    foreach ($entry in $Base.GetEnumerator()) {
        $merged[$entry.Key] = $entry.Value
    }
    foreach ($entry in $Override.GetEnumerator()) {
        $merged[$entry.Key] = $entry.Value
    }
    return $merged
}

function Get-ExpectedFunctionsPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    switch ($Environment) {
        "local" {
            return @{
                "ENFORCE_APPCHECK" = "false"
                "STORAGE_BUCKET" = "adfoot-staging.firebasestorage.app"
                "OPTIMIZE_TRIGGER_REGION" = "us-central1"
                "VIDEO_UPLOADS_ENABLED" = "false"
                "MAX_VIDEO_UPLOADS_PER_DAY" = "3"
                "MAX_CONCURRENT_VIDEO_UPLOADS" = "1"
                "MAX_OPTIMIZE_FILE_SIZE_BYTES" = "62914560"
                "UNVERIFIED_ACCOUNT_RETENTION_DAYS" = "3"
                "UNVERIFIED_PURGE_EXCLUDE_MANAGED" = "true"
            }
        }
        "staging" {
            return @{
                "ENFORCE_APPCHECK" = "false"
                "STORAGE_BUCKET" = "adfoot-staging.firebasestorage.app"
                "OPTIMIZE_TRIGGER_REGION" = "us-central1"
                "VIDEO_UPLOADS_ENABLED" = "true"
                "MAX_VIDEO_UPLOADS_PER_DAY" = "5"
                "MAX_CONCURRENT_VIDEO_UPLOADS" = "1"
                "MAX_OPTIMIZE_FILE_SIZE_BYTES" = "62914560"
                "UNVERIFIED_ACCOUNT_RETENTION_DAYS" = "3"
                "UNVERIFIED_PURGE_EXCLUDE_MANAGED" = "true"
            }
        }
        default {
            return @{
                "ENFORCE_APPCHECK" = "true"
                "STORAGE_BUCKET" = "show-talent-5987d.appspot.com"
                "OPTIMIZE_TRIGGER_REGION" = "europe-west1"
                "VIDEO_UPLOADS_ENABLED" = "true"
                "MAX_VIDEO_UPLOADS_PER_DAY" = "10"
                "MAX_CONCURRENT_VIDEO_UPLOADS" = "2"
                "MAX_OPTIMIZE_FILE_SIZE_BYTES" = "125829120"
                "UNVERIFIED_ACCOUNT_RETENTION_DAYS" = "3"
                "UNVERIFIED_PURGE_EXCLUDE_MANAGED" = "true"
            }
        }
    }
}

$selectedEnvironments = New-Object System.Collections.Generic.List[string]
if (-not $SkipLocal) { $selectedEnvironments.Add("local") }
if (-not $SkipStaging) { $selectedEnvironments.Add("staging") }
if (-not $SkipProduction) { $selectedEnvironments.Add("production") }

if ($selectedEnvironments.Count -eq 0) {
    Write-Error "No environment selected. Remove one of -SkipLocal/-SkipStaging/-SkipProduction."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptsRoot = Join-Path $repoRoot "scripts"

$checkMobileConfigScript = Join-Path $scriptsRoot "check-mobile-firebase-config.ps1"
$checkFunctionsEnvScript = Join-Path $scriptsRoot "check-functions-env.ps1"
$checkMobileIdsScript = Join-Path $scriptsRoot "check-mobile-identifiers.ps1"

Write-Host "Selected environments: $($selectedEnvironments -join ', ')"
Write-Host "Strict mode          : $Strict"

Invoke-Step -Name "Mobile identifiers baseline" -Action {
    & powershell -ExecutionPolicy Bypass -File $checkMobileIdsScript
}

if (-not $SkipMobileChecks) {
    foreach ($environment in $selectedEnvironments) {
        Invoke-Step -Name "Mobile Firebase config check ($environment)" -Action {
            $args = @(
                "-ExecutionPolicy", "Bypass",
                "-File", $checkMobileConfigScript,
                "-Environment", $environment
            )

            if ($Strict -and $environment -ne "local") {
                $args += "-RequireConfig"
                $args += "-RequireNativeFiles"
            }

            & powershell @args
        }
    }
}

if (-not $SkipFunctionsChecks) {
    foreach ($environment in $selectedEnvironments) {
        Invoke-Step -Name "Functions env check ($environment)" -Action {
            & powershell -ExecutionPolicy Bypass -File $checkFunctionsEnvScript -Environment $environment
        }
    }
}

if (-not $SkipFunctionsChecks) {
    $functionsPolicyWarnings = New-Object System.Collections.Generic.List[string]
    $functionsPolicyErrors = New-Object System.Collections.Generic.List[string]

    foreach ($environment in $selectedEnvironments) {
        $basePath = Join-Path $repoRoot "functions/.env"
        $overridePath = Join-Path $repoRoot "functions/.env.$environment"
        $effective = Merge-Maps -Base (Read-DotEnvFile -Path $basePath) -Override (Read-DotEnvFile -Path $overridePath)
        $expectedPolicy = Get-ExpectedFunctionsPolicy -Environment $environment
        $isStrictBlockingEnvironment = $Strict -and $environment -ne "local"

        foreach ($entry in $expectedPolicy.GetEnumerator()) {
            $key = [string]$entry.Key
            $expectedValue = [string]$entry.Value
            $actualValue = if ($effective.ContainsKey($key)) { [string]$effective[$key] } else { "<missing>" }

            if ($actualValue -ne $expectedValue) {
                $message = "Functions policy mismatch [$environment] $key=$actualValue (expected: $expectedValue)"
                if ($isStrictBlockingEnvironment) {
                    $functionsPolicyErrors.Add($message)
                } else {
                    $functionsPolicyWarnings.Add($message)
                }
            }
        }

    }

    if ($functionsPolicyWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Functions policy warnings:"
        foreach ($warning in $functionsPolicyWarnings) {
            Write-Host "- $warning"
        }
    }

    if ($functionsPolicyErrors.Count -gt 0) {
        Write-Host ""
        Write-Host "Functions policy errors:"
        foreach ($errorMessage in $functionsPolicyErrors) {
            Write-Host "- $errorMessage"
        }
        exit 1
    }
}

if ($Strict) {
    Invoke-Step -Name "Release-ready identifier guardrail" -Action {
        & powershell -ExecutionPolicy Bypass -File $checkMobileIdsScript -RequireReleaseReady
    }
}

Write-Host ""
Write-Host "Release configuration validation completed successfully."
