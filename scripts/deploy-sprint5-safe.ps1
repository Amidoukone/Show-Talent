param(
    [switch]$Execute,
    [switch]$AutoApprove,
    [switch]$SkipStaging,
    [switch]$SkipProduction,
    [switch]$SkipBuild,
    [switch]$SkipStrictValidation,
    [switch]$SkipLogSnapshot,
    [int]$LogLines = 80
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

    if (-not $Execute) {
        Write-Host "[PLAN] $Name"
        return
    }

    & $Action
    if ($LASTEXITCODE -gt 0) {
        throw "$Name failed (exit code $LASTEXITCODE)."
    }
}

function Invoke-OptionalStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name"

    if (-not $Execute) {
        Write-Host "[PLAN] $Name"
        return
    }

    try {
        & $Action
        if ($LASTEXITCODE -gt 0) {
            throw "$Name failed (exit code $LASTEXITCODE)."
        }
    } catch {
        Write-Warning "$Name failed (non-blocking): $($_.Exception.Message)"
    }
}

function Confirm-Gate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "Gate: $Message"

    if (-not $Execute) {
        Write-Host "[PLAN] Confirmation gate skipped (plan mode)."
        return
    }

    if ($AutoApprove) {
        Write-Host "Auto-approved."
        return
    }

    $answer = Read-Host "Type YES to continue"
    if ($answer -ne "YES") {
        throw "Deployment aborted at gate: $Message"
    }
}

$targets = New-Object System.Collections.Generic.List[string]
if (-not $SkipStaging) { $targets.Add("staging") }
if (-not $SkipProduction) { $targets.Add("production") }

if ($targets.Count -eq 0) {
    Write-Error "No deploy target selected. Remove -SkipStaging or -SkipProduction."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$timestampUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$headSha = ""
try {
    $headSha = (git rev-parse --short HEAD 2>$null).Trim()
} catch {
    $headSha = "<unknown>"
}

Write-Host "Sprint 5 deployment orchestrator"
Write-Host "Timestamp (UTC) : $timestampUtc"
Write-Host "Git HEAD        : $headSha"
Write-Host "Targets         : $($targets -join ', ')"
Write-Host "Execute mode    : $Execute"

if (-not $Execute) {
    Write-Host ""
    Write-Host "Plan mode active. No deployment command will be executed."
    Write-Host "Run again with -Execute (and optional -AutoApprove) to deploy."
}

Push-Location $repoRoot
try {
    if (-not $SkipStrictValidation) {
        Invoke-Step -Name "Strict configuration validation (selected targets)" -Action {
            $validationArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", ".\\scripts\\validate-release-config.ps1",
                "-Strict",
                "-SkipLocal"
            )
            if (-not $targets.Contains("staging")) {
                $validationArgs += "-SkipStaging"
            }
            if (-not $targets.Contains("production")) {
                $validationArgs += "-SkipProduction"
            }
            & powershell @validationArgs
        }
    } else {
        Write-Host ""
        Write-Host "Skipping strict validation as requested."
    }

    if (-not $SkipBuild) {
        Invoke-Step -Name "Build Functions bundle" -Action {
            Push-Location "functions"
            try {
                & npm.cmd run build
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-Host ""
        Write-Host "Skipping functions build as requested."
    }

    if ($targets.Contains("staging")) {
        Confirm-Gate -Message "Deploy to STAGING"

        Invoke-Step -Name "Deploy functions to staging" -Action {
            & npm.cmd run functions:deploy:staging
        }

        Invoke-Step -Name "Post-deploy staging env validation" -Action {
            & npm.cmd run functions:env:check:staging
        }

        if (-not $SkipLogSnapshot) {
            Invoke-OptionalStep -Name "Staging log snapshot (cleanupUnverifiedUsers)" -Action {
                & firebase.cmd functions:log --project staging --only cleanupUnverifiedUsers --lines $LogLines
            }
        }
    }

    if ($targets.Contains("production")) {
        Confirm-Gate -Message "Production gate passed after staging verification"
        Confirm-Gate -Message "Deploy to PRODUCTION"

        Invoke-Step -Name "Deploy functions to production" -Action {
            & npm.cmd run functions:deploy:production
        }

        Invoke-Step -Name "Post-deploy production env validation" -Action {
            & npm.cmd run functions:env:check:production
        }

        if (-not $SkipLogSnapshot) {
            Invoke-OptionalStep -Name "Production log snapshot (cleanupUnverifiedUsers)" -Action {
                & firebase.cmd functions:log --project production --only cleanupUnverifiedUsers --lines $LogLines
            }
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Sprint 5 deployment lot completed."
Write-Host "Release stamp: $timestampUtc / git $headSha"
if (-not $Execute) {
    Write-Host "No change applied (plan mode)."
}
