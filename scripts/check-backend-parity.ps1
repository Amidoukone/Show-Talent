<#
.SYNOPSIS
    Verifies that the backend a build is about to depend on is the backend
    that is actually deployed.

.DESCRIPTION
    Two drift checks, run together because they answer the same question and
    fail in opposite ways:

    - Rules drift fails loudly. A build shipped against rules that were never
      deployed gets permission-denied, the user sees an error, and the report
      arrives the same day.
    - Index drift fails silently. Firestore answers `code 9
      FAILED_PRECONDITION`, the repository catches it like any other failure,
      and the screen simply looks empty. Nobody reports "the feed is empty
      because an index is missing"; they report "the app is broken", weeks
      later.

    Both scripts existed or were needed before this gate, and neither was
    referenced by any release ritual -- an operator had to remember them.
    Remembering is not a control.

    Read-only: every call is a GET against the Firebase Rules and Firestore
    Admin APIs with the ops service account. It deploys nothing and changes
    nothing.

.PARAMETER Environment
    Mobile environment name, resolved through config/mobile/<env>.json to a
    Firebase project id. Defaults to production.

.PARAMETER Credentials
    Service-account JSON. Defaults to .credentials/<project>-ops.json, which
    is what both underlying scripts already look for.
#>
param(
    [string]$Environment = "production",
    [string]$Credentials = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $failures = @()

    $checks = @(
        @{
            Name   = "Firestore/Storage rules parity"
            Script = ".\scripts\check-deployed-firebase-rules.mjs"
        },
        @{
            Name   = "Firestore indexes and TTL parity"
            Script = ".\scripts\check-deployed-firestore-indexes.mjs"
        }
    )

    foreach ($check in $checks) {
        Write-Host ""
        Write-Host "==> $($check.Name)"

        $nodeArgs = @($check.Script, "--environment", $Environment)
        if (-not [string]::IsNullOrWhiteSpace($Credentials)) {
            $nodeArgs += @("--credentials", $Credentials)
        }

        & node @nodeArgs
        if ($LASTEXITCODE -gt 0) {
            $failures += $check.Name
        }
    }

    Write-Host ""
    if ($failures.Count -gt 0) {
        Write-Host "Backend parity check FAILED:"
        foreach ($failure in $failures) {
            Write-Host "- $failure"
        }
        Write-Host ""
        Write-Host "Deploy the backend before building, or the build ships"
        Write-Host "against a backend that does not exist yet."
        exit 1
    }

    Write-Host "Backend parity check completed: deployed backend matches this checkout."
} finally {
    Pop-Location
}

exit 0
