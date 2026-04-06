param()

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
  Invoke-ExternalStep -Name "Flutter event release tests" -Command {
    & flutter test `
      test/event_model_test.dart `
      test/event_release_quality_guardrails_test.dart `
      --reporter expanded
  }

  Invoke-ExternalStep -Name "Flutter event targeted analyze" -Command {
    & flutter analyze `
      lib/models/event.dart `
      lib/services/events/event_repository.dart `
      lib/controller/event_controller.dart `
      lib/controller/push_notification.dart `
      lib/screens/event_form_screen.dart `
      lib/screens/event_list_screen.dart `
      lib/screens/event_detail_screen.dart
  }

  Invoke-ExternalStep -Name "Functions targeted lint (event fanout)" -Command {
    & npm.cmd --prefix functions run lint -- src/actions.ts
  }

  Invoke-ExternalStep -Name "Functions build" -Command {
    & npm.cmd --prefix functions run build
  }

  Write-Host ""
  Write-Host "Event release quality gate completed."
} finally {
  Pop-Location
}
