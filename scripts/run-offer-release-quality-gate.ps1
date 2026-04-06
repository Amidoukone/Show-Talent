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
  Invoke-ExternalStep -Name "Flutter offre release tests" -Command {
    & flutter test `
      test/offre_model_test.dart `
      test/offre_release_quality_guardrails_test.dart `
      --reporter expanded
  }

  Invoke-ExternalStep -Name "Flutter offre targeted analyze" -Command {
    & flutter analyze `
      lib/models/offre.dart `
      lib/controller/offre_controller.dart `
      lib/controller/push_notification.dart `
      lib/screens/offre_screen.dart `
      lib/screens/offres_form.dart
  }

  Invoke-ExternalStep -Name "Functions targeted lint (offer fanout)" -Command {
    & npm.cmd --prefix functions run lint -- src/actions.ts
  }

  Invoke-ExternalStep -Name "Functions build" -Command {
    & npm.cmd --prefix functions run build
  }

  Write-Host ""
  Write-Host "Offer release quality gate completed."
} finally {
  Pop-Location
}
