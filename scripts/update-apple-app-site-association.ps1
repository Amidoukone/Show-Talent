param(
    [Parameter(Mandatory = $true)]
    [string]$TeamId,
    [string]$FilePath = "site_pub/.well-known/apple-app-site-association",
    [string[]]$BundleIds = @("org.adfoot.app", "org.adfoot.app.staging"),
    [switch]$PrintOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TeamId)) {
    Write-Error "TeamId is required."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedFilePath = if ([System.IO.Path]::IsPathRooted($FilePath)) {
    $FilePath
} else {
    Join-Path $repoRoot $FilePath
}

if (-not (Test-Path -LiteralPath $resolvedFilePath)) {
    Write-Error "File not found: $resolvedFilePath"
    exit 1
}

$raw = Get-Content -LiteralPath $resolvedFilePath -Raw
$obj = $raw | ConvertFrom-Json

if ($null -eq $obj.applinks -or $null -eq $obj.applinks.details -or $obj.applinks.details.Count -eq 0) {
    Write-Error "Invalid apple-app-site-association format (missing applinks.details)."
    exit 1
}

$newAppIds = @()
foreach ($bundleId in $BundleIds) {
    if (-not [string]::IsNullOrWhiteSpace($bundleId)) {
        $newAppIds += "$TeamId.$bundleId"
    }
}

if ($newAppIds.Count -eq 0) {
    Write-Error "No bundle IDs provided."
    exit 1
}

$obj.applinks.details[0].appIDs = $newAppIds
$jsonOut = $obj | ConvertTo-Json -Depth 10

if ($PrintOnly) {
    Write-Host $jsonOut
    exit 0
}

Set-Content -LiteralPath $resolvedFilePath -Value $jsonOut -Encoding UTF8

Write-Host "apple-app-site-association updated."
Write-Host "Path    : $resolvedFilePath"
Write-Host "Team ID : $TeamId"
Write-Host "App IDs : $($newAppIds -join ', ')"

exit 0
