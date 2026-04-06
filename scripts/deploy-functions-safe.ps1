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

function Resolve-FirebaseProjectId {
  param(
    [Parameter(Mandatory = $true)]
    [string]$AliasOrProjectId,
    [Parameter(Mandatory = $true)]
    [string]$FirebasercPath
  )

  if (-not (Test-Path -LiteralPath $FirebasercPath)) {
    return $AliasOrProjectId
  }

  try {
    $firebaserc = Get-Content -LiteralPath $FirebasercPath -Raw | ConvertFrom-Json
    $projectAliases = @($firebaserc.projects.PSObject.Properties.Name)
    if ($projectAliases -contains $AliasOrProjectId) {
      return [string]$firebaserc.projects.$AliasOrProjectId
    }
  } catch {
    Write-Warning "Unable to resolve Firebase project alias from .firebaserc: $($_.Exception.Message)"
  }

  return $AliasOrProjectId
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetProject = if ([string]::IsNullOrWhiteSpace($Project)) { $Environment } else { $Project }
$functionsDir = Join-Path $repoRoot "functions"
$baseEnvPath = Join-Path $functionsDir ".env"
$envSpecificPath = Join-Path $functionsDir ".env.$Environment"
$firebasercPath = Join-Path $repoRoot ".firebaserc"
$effectiveEnv = Merge-Maps -Base (Read-DotEnvFile -Path $baseEnvPath) -Override (Read-DotEnvFile -Path $envSpecificPath)
$resolvedProjectId = Resolve-FirebaseProjectId -AliasOrProjectId $targetProject -FirebasercPath $firebasercPath

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
Write-Host "Project ID    : $resolvedProjectId"
Write-Host ""

Push-Location $repoRoot
try {
  foreach ($entry in $effectiveEnv.GetEnumerator()) {
    Set-Item -Path ("Env:{0}" -f $entry.Key) -Value ([string]$entry.Value)
  }

  if (-not [string]::IsNullOrWhiteSpace($resolvedProjectId)) {
    Set-Item -Path Env:GCLOUD_PROJECT -Value $resolvedProjectId
  }

  if (
    -not [string]::IsNullOrWhiteSpace([string]$effectiveEnv["STORAGE_BUCKET"]) -and
    [string]::IsNullOrWhiteSpace($env:FIREBASE_CONFIG)
  ) {
    $firebaseConfig = @{
      projectId = $resolvedProjectId
      storageBucket = [string]$effectiveEnv["STORAGE_BUCKET"]
    } | ConvertTo-Json -Compress

    Set-Item -Path Env:FIREBASE_CONFIG -Value $firebaseConfig
  }

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
