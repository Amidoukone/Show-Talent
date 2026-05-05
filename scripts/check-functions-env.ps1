param(
  [Parameter(Mandatory = $false)]
  [string]$Environment = "production"
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

function Mask-Value {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Key,
    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Value
  )

  if ($Key -match "KEY|SECRET|TOKEN|PASSWORD") {
    if ([string]::IsNullOrWhiteSpace($Value)) {
      return "<empty>"
    }
    if ($Value.Length -le 8) {
      return "********"
    }
    return ("*" * ($Value.Length - 4)) + $Value.Substring($Value.Length - 4)
  }

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "<empty>"
  }

  return $Value
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$functionsDir = Join-Path $repoRoot "functions"
$baseEnvPath = Join-Path $functionsDir ".env"
$envSpecificPath = Join-Path $functionsDir ".env.$Environment"
$firebasercPath = Join-Path $repoRoot ".firebaserc"

$baseEnv = Read-DotEnvFile -Path $baseEnvPath
$envSpecific = Read-DotEnvFile -Path $envSpecificPath
$effective = Merge-Maps -Base $baseEnv -Override $envSpecific

$requiredKeys = @(
  "APP_ENV",
  "ENFORCE_APPCHECK",
  "STORAGE_BUCKET",
  "OPTIMIZE_TRIGGER_REGION",
  "VIDEO_UPLOADS_ENABLED",
  "MAX_VIDEO_UPLOADS_PER_DAY",
  "MAX_CONCURRENT_VIDEO_UPLOADS",
  "MAX_OPTIMIZE_FILE_SIZE_BYTES",
  "UNVERIFIED_ACCOUNT_RETENTION_DAYS",
  "UNVERIFIED_PURGE_EXCLUDE_MANAGED"
)

$booleanKeys = @(
  "ENFORCE_APPCHECK",
  "VIDEO_UPLOADS_ENABLED",
  "UNVERIFIED_PURGE_EXCLUDE_MANAGED"
)

$positiveIntKeys = @(
  "MAX_VIDEO_UPLOADS_PER_DAY",
  "MAX_CONCURRENT_VIDEO_UPLOADS",
  "MAX_OPTIMIZE_FILE_SIZE_BYTES",
  "UNVERIFIED_ACCOUNT_RETENTION_DAYS"
)

$allowedAppEnvironmentValues = @("local", "staging", "production")

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $envSpecificPath)) {
  $warnings.Add("Missing environment override file: $envSpecificPath")
}

if (Test-Path -LiteralPath $firebasercPath) {
  $firebaserc = Get-Content -LiteralPath $firebasercPath -Raw | ConvertFrom-Json
  $projectAliases = @($firebaserc.projects.PSObject.Properties.Name)
  if ($Environment -ne "local" -and $projectAliases -notcontains $Environment) {
    $warnings.Add("Alias '$Environment' is not present in .firebaserc")
  }
} else {
  $warnings.Add("Missing .firebaserc at repo root")
}

foreach ($key in $requiredKeys) {
  if (-not $effective.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$effective[$key])) {
    $errors.Add("Missing required setting: $key")
  }
}

foreach ($key in $booleanKeys) {
  if ($effective.ContainsKey($key)) {
    $value = [string]$effective[$key]
    if ($value -notin @("true", "false")) {
      $errors.Add("Invalid boolean value for ${key}: $value")
    }
  }
}

foreach ($key in $positiveIntKeys) {
  if ($effective.ContainsKey($key)) {
    $raw = [string]$effective[$key]
    $parsed = 0
    if (-not [int]::TryParse($raw, [ref]$parsed) -or $parsed -lt 1) {
      $errors.Add("Invalid positive integer for ${key}: $raw")
    }
  }
}

if ($effective.ContainsKey("APP_ENV")) {
  $appEnvironment = [string]$effective["APP_ENV"]
  if ($allowedAppEnvironmentValues -notcontains $appEnvironment) {
    $errors.Add("Invalid APP_ENV value: $appEnvironment")
  }
}

Write-Host "Environment: $Environment"
Write-Host "Base file   : $baseEnvPath"
Write-Host "Override    : $envSpecificPath"
Write-Host ""
Write-Host "Effective values:"
foreach ($key in ($effective.Keys | Sort-Object)) {
  Write-Host ("- {0}={1}" -f $key, (Mask-Value -Key $key -Value ([string]$effective[$key])))
}

if ($warnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Warnings:"
  foreach ($warning in $warnings) {
    Write-Host "- $warning"
  }
}

if ($errors.Count -gt 0) {
  Write-Host ""
  Write-Host "Errors:"
  foreach ($errorMessage in $errors) {
    Write-Host "- $errorMessage"
  }
  exit 1
}

Write-Host ""
Write-Host "Environment configuration is valid."
