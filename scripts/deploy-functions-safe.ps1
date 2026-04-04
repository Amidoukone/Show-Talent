param(
  [Parameter(Mandatory = $false)]
  [string]$Environment = "production",
  [Parameter(Mandatory = $false)]
  [string]$Only = "functions",
  [Parameter(Mandatory = $false)]
  [string[]]$Functions = @(),
  [switch]$Sequential,
  [Parameter(Mandatory = $false)]
  [string]$Project,
  [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetProject = if ([string]::IsNullOrWhiteSpace($Project)) { $Environment } else { $Project }

if (-not $SkipValidation) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "check-functions-env.ps1") -Environment $Environment
  if ($LASTEXITCODE -gt 0) {
    exit $LASTEXITCODE
  }
}

Write-Host "Deploy target : $targetProject"
if ($Functions.Count -gt 0) {
  Write-Host "Deploy scope  : selected functions ($($Functions -join ', '))"
  Write-Host "Sequential    : $Sequential"
} else {
  Write-Host "Deploy scope  : $Only"
}
Write-Host ""

Push-Location $repoRoot
try {
  if ($Functions.Count -gt 0) {
    $targets = @()
    foreach ($functionArg in $Functions) {
      if ([string]::IsNullOrWhiteSpace($functionArg)) {
        continue
      }

      foreach ($functionName in ($functionArg -split ",")) {
        if ([string]::IsNullOrWhiteSpace($functionName)) {
          continue
        }

        $trimmed = $functionName.Trim()
        if ($trimmed.StartsWith("functions:")) {
          $targets += $trimmed
        } else {
          $targets += "functions:$trimmed"
        }
      }
    }

    if ($targets.Count -eq 0) {
      throw "No valid function target provided in -Functions."
    }

    if ($Sequential) {
      foreach ($target in $targets) {
        Write-Host "Deploying target: $target"
        & firebase.cmd deploy --only $target --project $targetProject
        if ($LASTEXITCODE -gt 0) {
          exit $LASTEXITCODE
        }
      }
    } else {
      $joinedTargets = $targets -join ","
      & firebase.cmd deploy --only $joinedTargets --project $targetProject
      if ($LASTEXITCODE -gt 0) {
        exit $LASTEXITCODE
      }
    }
  } else {
    & firebase.cmd deploy --only $Only --project $targetProject
    if ($LASTEXITCODE -gt 0) {
      exit $LASTEXITCODE
    }
  }
} finally {
  Pop-Location
}
