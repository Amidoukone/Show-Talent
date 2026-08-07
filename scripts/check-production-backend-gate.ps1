param(
    [string]$Project = "production",
    [string]$FunctionName = "cleanupUnverifiedUsers",
    [int]$Lines = 120,
    [int]$MaxSuccessAgeHours = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Parse-LogTimestamp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    $match = [regex]::Match(
        $Line,
        '^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z)'
    )
    if (-not $match.Success) {
        return $null
    }

    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($match.Groups[1].Value, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

$cmd = @(
    "functions:log",
    "--project", $Project,
    "--only", $FunctionName,
    "--lines", "$Lines"
)

$rawOutput = & firebase.cmd @cmd 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -gt 0) {
    Write-Error "firebase functions:log failed (exit code $exitCode)."
    exit $exitCode
}

$logLines = @($rawOutput | ForEach-Object { [string]$_ })
if ($logLines.Count -eq 0) {
    Write-Error "No log lines returned for '$FunctionName' on project '$Project'."
    exit 1
}

$latestSuccessTime = $null
$latestFailureTime = $null
$latestFailureLine = $null

foreach ($line in $logLines) {
    $lineTs = Parse-LogTimestamp -Line $line
    if ($null -eq $lineTs) {
        continue
    }

    if ($line -match 'Unverified cleanup completed') {
        if ($null -eq $latestSuccessTime -or $lineTs -gt $latestSuccessTime) {
            $latestSuccessTime = $lineTs
        }
    }

    if ($line -match 'FAILED_PRECONDITION') {
        if ($null -eq $latestFailureTime -or $lineTs -gt $latestFailureTime) {
            $latestFailureTime = $lineTs
            $latestFailureLine = $line
        }
    }
}

$nowUtc = (Get-Date).ToUniversalTime()
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if ($null -eq $latestSuccessTime) {
    $errors.Add("No successful '$FunctionName' run found in the last $Lines log lines.")
} else {
    $ageHours = ($nowUtc - $latestSuccessTime.UtcDateTime).TotalHours
    if ($ageHours -gt $MaxSuccessAgeHours) {
        $errors.Add(
            "Latest successful '$FunctionName' run is older than $MaxSuccessAgeHours hours: $latestSuccessTime."
        )
    }
}

if ($null -ne $latestFailureTime) {
    if ($null -eq $latestSuccessTime -or $latestFailureTime -gt $latestSuccessTime) {
        $errors.Add(
            "A FAILED_PRECONDITION was observed after the latest success. Latest failure: $latestFailureTime."
        )
    } else {
        $warnings.Add(
            "Historical FAILED_PRECONDITION exists before latest success (expected during pre-index period)."
        )
    }
}

Write-Host "Backend gate project      : $Project"
Write-Host "Backend gate function     : $FunctionName"
Write-Host "Fetched log lines         : $Lines"
Write-Host "Max success age (hours)   : $MaxSuccessAgeHours"
Write-Host "Latest success timestamp  : $latestSuccessTime"
Write-Host "Latest failure timestamp  : $latestFailureTime"

if ($null -ne $latestFailureLine) {
    Write-Host "Latest failure sample     : $latestFailureLine"
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
Write-Host "Backend gate check completed."
exit 0
