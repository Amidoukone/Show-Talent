param(
  [string]$ProjectId = "show-talent-5987d",
  [int]$Lines = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$functions = @(
  "createUploadSession",
  "requestThumbnailUploadUrl",
  "finalizeUpload"
)

if (-not (Get-Command firebase.cmd -ErrorAction SilentlyContinue)) {
  Write-Error "firebase.cmd not found in PATH."
  exit 1
}

$summary = @()
$allValid = $true

foreach ($fn in $functions) {
  $output = (& firebase.cmd functions:log --only $fn --lines $Lines --project $ProjectId 2>&1 | Out-String)

  $hasBoth = $false
  foreach ($line in ($output -split "`r?`n")) {
    if ($line -match '"verifications"' -and
        $line -match '"auth":"VALID"' -and
        $line -match '"app":"VALID"') {
      $hasBoth = $true
      break
    }
  }

  if (-not $hasBoth) {
    $allValid = $false
  }

  $summary += [PSCustomObject]@{
    function = $fn
    authAndAppValidSeen = $hasBoth
  }
}

$result = [PSCustomObject]@{
  success = $allValid
  projectId = $ProjectId
  checkedLines = $Lines
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  functions = $summary
}

$result | ConvertTo-Json -Depth 10

if (-not $allValid) {
  exit 1
}
