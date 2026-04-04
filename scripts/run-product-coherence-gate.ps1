param(
    [switch]$IncludeBackendGate,
    [switch]$SkipFlutterTest,
    [switch]$SkipAnalyze,
    [switch]$StrictContract,
    [string]$AdminRepoPath
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
