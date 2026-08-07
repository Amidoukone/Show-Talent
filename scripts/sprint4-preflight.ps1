param(
    [switch]$SkipAnalyze,
    [switch]$SkipFlutterTests,
    [switch]$SkipIdsCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Action
    if ($LASTEXITCODE -gt 0) {
        throw "$Name failed (exit code $LASTEXITCODE)."
    }
}

function Find-LegacyUiPatterns {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    $targets = @(
        "lib/screens"
    )

    if (Get-Command rg -ErrorAction SilentlyContinue) {
        $joined = [string]::Join("|", $Patterns)
        $hits = rg -n $joined @targets -S
        if ($LASTEXITCODE -eq 1) {
            return @()
        }
        if ($LASTEXITCODE -gt 1) {
            throw "rg scan failed with exit code $LASTEXITCODE."
        }
        return @($hits)
    }

    $hits = @()
    $regex = [string]::Join("|", $Patterns)
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target -PathType Container) {
            $files = Get-ChildItem -LiteralPath $target -Recurse -File -Filter *.dart
            foreach ($file in $files) {
                $match = Select-String -Path $file.FullName -Pattern $regex
                if ($null -ne $match) {
                    $hits += $match | ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line)" }
                }
            }
            continue
        }

        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $match = Select-String -Path $target -Pattern $regex
            if ($null -ne $match) {
                $hits += $match | ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line)" }
            }
        }
    }
    return $hits
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Invoke-Step -Name "Guardrail scan (legacy dialog/snackbar patterns)" -Action {
        $patterns = @(
            "Get\.snackbar\s*\(",
            "Get\.dialog\s*\(",
            "showDialog\s*<",
            "showDialog\s*\(",
            "\bAlertDialog\b"
        )

        $hits = @(Find-LegacyUiPatterns -Patterns $patterns)
        if ($hits.Count -gt 0) {
            Write-Host "Legacy patterns detected:"
            $hits | ForEach-Object { Write-Host $_ }
            throw "Legacy UI patterns must be removed from guarded paths."
        }

        Write-Host "OK - no legacy pattern detected."
        $global:LASTEXITCODE = 0
    }

    if (-not $SkipAnalyze) {
        Invoke-Step -Name "Dart analyze (Sprint 4 critical paths)" -Action {
            $targets = @(
                "lib/config/app_bootstrap.dart",
                "lib/services/email_link_handler.dart",
                "lib/screens/login_screen.dart",
                "lib/screens/reset_password_screen.dart",
                "lib/screens/verify_email_screen.dart",
                "lib/screens/edit_profil_screen.dart",
                "lib/controller/profile_controller.dart",
                "lib/controller/upload_video_controller.dart",
                "lib/screens/upload_form.dart",
                "lib/screens/video_feed_screen.dart",
                "lib/controller/chat_controller.dart",
                "lib/screens/chat_screen.dart",
                "lib/screens/select_user_screen.dart",
                "lib/screens/conversation_screen.dart",
                "lib/screens/profile_screen.dart",
                "lib/services/account_cleanup_service.dart",
                "lib/screens/setting_screen.dart",
                "test/architecture_guardrails_test.dart"
            )
            & dart analyze @targets
        }
    }

    if (-not $SkipFlutterTests) {
        Invoke-Step -Name "Architecture guardrails tests" -Action {
            & flutter test test/architecture_guardrails_test.dart --reporter expanded
        }

        Invoke-Step -Name "Flutter test suite" -Action {
            & flutter test --reporter expanded
        }
    }

    if (-not $SkipIdsCheck) {
        Invoke-Step -Name "Mobile identifiers check" -Action {
            & npm.cmd run mobile:ids:check
        }
    }

    Write-Host ""
    Write-Host "Sprint 4 preflight completed successfully."
} finally {
    Pop-Location
}
