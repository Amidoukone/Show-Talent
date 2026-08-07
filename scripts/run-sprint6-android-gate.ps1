param(
    [ValidateSet("production", "staging")]
    [string]$Environment = "production",
    [switch]$ExecuteBuild,
    [switch]$SkipBackendGate,
    [switch]$SkipReleaseConfigValidation,
    [switch]$SkipAndroidReadiness,
    [switch]$CleanBuild,
    [string]$BuildName,
    [int]$BuildNumber
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

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (-not $SkipBackendGate -and $Environment -eq "production") {
        Invoke-Step -Name "Backend gate (cleanupUnverifiedUsers)" -Action {
            & powershell -ExecutionPolicy Bypass -File ".\scripts\check-production-backend-gate.ps1"
        }
    } elseif (-not $SkipBackendGate) {
        Write-Host ""
        Write-Host "Skipping backend gate for environment '$Environment' (production gate only)."
    }

    if (-not $SkipReleaseConfigValidation) {
        Invoke-Step -Name "Release config strict validation" -Action {
            $args = @(
                "-ExecutionPolicy", "Bypass",
                "-File", ".\scripts\validate-release-config.ps1",
                "-Strict",
                "-SkipLocal"
            )
            if ($Environment -eq "production") {
                $args += "-SkipStaging"
            } else {
                $args += "-SkipProduction"
            }
            & powershell @args
        }
    }

    if (-not $SkipAndroidReadiness) {
        Invoke-Step -Name "Android readiness gate ($Environment)" -Action {
            & powershell -ExecutionPolicy Bypass -File ".\scripts\check-android-release-readiness.ps1" -Environment $Environment -ReleaseGate
        }
    }

    if ($ExecuteBuild) {
        Invoke-Step -Name "Build Android app bundle ($Environment)" -Action {
            $args = @(
                "-ExecutionPolicy", "Bypass",
                "-File", ".\scripts\build-android-release.ps1",
                "-Environment", $Environment,
                "-ReleaseGate"
            )

            if ($CleanBuild) {
                $args += "-Clean"
            }
            if (-not [string]::IsNullOrWhiteSpace($BuildName)) {
                $args += "-BuildName"
                $args += $BuildName
            }
            if ($BuildNumber -gt 0) {
                $args += "-BuildNumber"
                $args += "$BuildNumber"
            }

            & powershell @args
        }
    } else {
        Write-Host ""
        Write-Host "Build step skipped. Use -ExecuteBuild to generate the .aab artifact."
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Sprint 6 Android gate completed."
exit 0
