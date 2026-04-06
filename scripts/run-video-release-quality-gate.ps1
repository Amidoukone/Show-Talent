param(
  [switch]$RunRemoteSmoke,
  [switch]$VerifyUploadLogs,
  [string]$ProjectId = "show-talent-5987d",
  [string]$Region = "europe-west1",
  [string]$ApiKey = $env:FIREBASE_WEB_API_KEY,
  [int]$ReadyTimeoutSec = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-ExternalStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Command
  )

  Write-Host ""
  Write-Host "==> $Name"
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot

try {
  Invoke-ExternalStep -Name "Flutter video smoke/guardrail tests" -Command {
    & flutter test `
      test/upload_client_test.dart `
      test/video_controller_scoped_test.dart `
      test/video_release_quality_guardrails_test.dart `
      --reporter expanded
  }

  Invoke-ExternalStep -Name "Functions targeted lint" -Command {
    & npm.cmd --prefix functions run lint -- src/upload_session.ts src/actions.ts
  }

  Invoke-ExternalStep -Name "Functions build" -Command {
    & npm.cmd --prefix functions run build
  }

  if ($RunRemoteSmoke.IsPresent) {
    Invoke-ExternalStep -Name "Remote upload->ready->playback->delete smoke flow" -Command {
      $smokeArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", ".\scripts\smoke-upload-flow.ps1",
        "-ProjectId", $ProjectId,
        "-Region", $Region,
        "-ReadyTimeoutSec", "$ReadyTimeoutSec"
      )

      if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $smokeArgs += @("-ApiKey", $ApiKey)
      }

      & powershell @smokeArgs
    }
  }

  if ($VerifyUploadLogs.IsPresent) {
    Invoke-ExternalStep -Name "Upload auth/app check log verification" -Command {
      & powershell -ExecutionPolicy Bypass -File .\scripts\verify-mobile-upload-logs.ps1 -ProjectId $ProjectId
    }
  }

  Write-Host ""
  Write-Host "Video release quality gate completed."
} finally {
  Pop-Location
}
