Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$privateKeyHeaderRegex = "-----BEGIN " +
    "(RSA |EC |OPENSSH |PRIVATE )?" +
    "PRIVATE KEY-----"
$serviceAccountPrivateKeyRegex = '"private_key"\s*:\s*"' +
    "-----BEGIN " +
    "PRIVATE KEY-----"
$patterns = @(
    @{
        Name = "Firebase API key"
        Regex = "AIza[0-9A-Za-z_-]{20,}"
    },
    @{
        Name = "Private key block"
        Regex = $privateKeyHeaderRegex
    },
    @{
        Name = "Firebase service account private key"
        Regex = $serviceAccountPrivateKeyRegex
    }
)

$findings = New-Object System.Collections.Generic.List[string]
$trackedFiles = git -C $repoRoot ls-files

foreach ($relativePath in $trackedFiles) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        continue
    }

    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }

    try {
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    } catch {
        continue
    }

    foreach ($pattern in $patterns) {
        if ($content -match $pattern.Regex) {
            $findings.Add("$relativePath contains $($pattern.Name).")
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Tracked secret scan failed:"
    foreach ($finding in $findings) {
        Write-Host "- $finding"
    }
    exit 1
}

Write-Host "Tracked secret scan completed."
exit 0
