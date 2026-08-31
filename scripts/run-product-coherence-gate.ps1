param(
    [switch]$IncludeBackendGate,
    [switch]$SkipFlutterTest,
    [switch]$SkipAnalyze,
    [switch]$StrictContract,
    [string]$AdminRepoPath,
    [string]$BackendEnvironment = "production"
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
    Invoke-Step -Name "Admin/mobile shared contract gate" -Action {
        $args = @(
            "-ExecutionPolicy", "Bypass",
            "-File", ".\scripts\check-admin-mobile-contract.ps1"
        )
        if ($StrictContract) {
            $args += "-Strict"
        }
        if (-not [string]::IsNullOrWhiteSpace($AdminRepoPath)) {
            $args += "-AdminRepoPath"
            $args += $AdminRepoPath
        }
        & powershell @args
    }

    if ($IncludeBackendGate) {
        # Rules and indexes before the scheduler: this one answers "is the
        # backend this checkout assumes the backend that is deployed", and a
        # build made against an index that only exists in the file shows up as
        # an empty screen, never as an error. Read-only, so it is safe to run
        # from any machine that holds the ops credential.
        Invoke-Step -Name "Backend parity gate (rules, indexes, TTL)" -Action {
            & powershell -ExecutionPolicy Bypass -File ".\scripts\check-backend-parity.ps1" -Environment $BackendEnvironment
        }

        Invoke-Step -Name "Backend scheduler gate (cleanupUnverifiedUsers)" -Action {
            & powershell -ExecutionPolicy Bypass -File ".\scripts\check-production-backend-gate.ps1"
        }
    }

    if (-not $SkipFlutterTest) {
        Invoke-Step -Name "Flutter tests" -Action {
            & flutter test
        }
    }

    if (-not $SkipAnalyze) {
        Invoke-Step -Name "Flutter analyze (non-fatal infos)" -Action {
            & flutter analyze --no-fatal-infos
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Product coherence gate completed."
exit 0
