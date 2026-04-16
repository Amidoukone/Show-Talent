param(
    [switch]$Strict,
    [string]$AdminRepoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-ContainsRegex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Raw,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Raw -notmatch $Pattern) {
        return $Message
    }
    return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$checkedFiles = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($AdminRepoPath)) {
    $AdminRepoPath = $env:ADFOOT_ADMIN_REPO
}

$resolvedAdminRepoPath = $null
if (-not [string]::IsNullOrWhiteSpace($AdminRepoPath)) {
    try {
        $resolvedAdminRepoPath = (Resolve-Path -LiteralPath $AdminRepoPath).Path
    } catch {
        $errors.Add("Admin repo path cannot be resolved: $AdminRepoPath")
    }
}

$functionsIndexPath = Join-Path $repoRoot "functions/src/index.ts"
$adminSupportPath = Join-Path $repoRoot "functions/src/admin_account_support.ts"
$managedAccountsPath = Join-Path $repoRoot "functions/src/managed_accounts.ts"
$firestoreRulesPath = Join-Path $repoRoot "firestore.rules"
$rolePolicyPath = Join-Path $repoRoot "lib/utils/account_role_policy.dart"
$authSessionServicePath = Join-Path $repoRoot "lib/services/auth/auth_session_service.dart"
$sharedContractDocPath = Join-Path $repoRoot "docs/shared-backend-contract.md"
$interRepoRunbookPath = Join-Path $repoRoot "docs/inter-repo-admin-mobile-runbook.md"

$mobileFiles = @(
    @{ Path = $functionsIndexPath; Label = "functions/src/index.ts" },
    @{ Path = $adminSupportPath; Label = "functions/src/admin_account_support.ts" },
    @{ Path = $managedAccountsPath; Label = "functions/src/managed_accounts.ts" },
    @{ Path = $firestoreRulesPath; Label = "firestore.rules" },
    @{ Path = $rolePolicyPath; Label = "lib/utils/account_role_policy.dart" },
    @{ Path = $authSessionServicePath; Label = "lib/services/auth/auth_session_service.dart" },
    @{ Path = $sharedContractDocPath; Label = "docs/shared-backend-contract.md" },
    @{ Path = $interRepoRunbookPath; Label = "docs/inter-repo-admin-mobile-runbook.md" }
)

foreach ($entry in $mobileFiles) {
    if (-not (Test-Path -LiteralPath $entry.Path)) {
        $errors.Add("Missing required contract file: $($entry.Path)")
    } else {
        $checkedFiles.Add($entry.Label)
    }
}

$adminFiles = $null
if ($null -ne $resolvedAdminRepoPath) {
    $adminFiles = @(
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/services/managed_account_service.dart"; Label = "admin/lib/services/managed_account_service.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/utils/account_role_policy.dart"; Label = "admin/lib/utils/account_role_policy.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/main.dart"; Label = "admin/lib/main.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/firebase_options.dart"; Label = "admin/lib/firebase_options.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "scripts/create_admin_account.mjs"; Label = "admin/scripts/create_admin_account.mjs" },
        @{ Path = Join-Path $resolvedAdminRepoPath "docs/prd-runbook-exploitation-inter-depots.md"; Label = "admin/docs/prd-runbook-exploitation-inter-depots.md" },
        @{ Path = Join-Path $resolvedAdminRepoPath "docs/runbook-production-admin-mobile.md"; Label = "admin/docs/runbook-production-admin-mobile.md" }
    )

    foreach ($entry in $adminFiles) {
        if (-not (Test-Path -LiteralPath $entry.Path)) {
            $errors.Add("Missing required admin contract file: $($entry.Path)")
        } else {
            $checkedFiles.Add($entry.Label)
        }
    }
} else {
    $warnings.Add("Admin repo path not provided. External admin checks were skipped.")
}

if ($errors.Count -gt 0) {
    Write-Host "Errors:"
    foreach ($errorMessage in $errors) {
        Write-Host "- $errorMessage"
    }
    exit 1
}

$functionsIndexRaw = Get-Content -LiteralPath $functionsIndexPath -Raw
$adminSupportRaw = Get-Content -LiteralPath $adminSupportPath -Raw
$managedAccountsRaw = Get-Content -LiteralPath $managedAccountsPath -Raw
$firestoreRulesRaw = Get-Content -LiteralPath $firestoreRulesPath -Raw
$rolePolicyRaw = Get-Content -LiteralPath $rolePolicyPath -Raw
$authSessionRaw = Get-Content -LiteralPath $authSessionServicePath -Raw
$sharedContractRaw = Get-Content -LiteralPath $sharedContractDocPath -Raw
$interRepoRunbookRaw = Get-Content -LiteralPath $interRepoRunbookPath -Raw

$requiredCallables = @(
    "provisionManagedAccount",
    "deleteManagedAccount",
    "changeManagedAccountRole",
    "resendManagedAccountInvite",
    "disableManagedAccountAuth",
    "enableManagedAccountAuth",
    "updateManagedAccountProfile"
)

foreach ($callable in $requiredCallables) {
    $callablePattern = "(?<![A-Za-z0-9_])" + [regex]::Escape($callable) + "(?![A-Za-z0-9_])"
    $msg = Assert-ContainsRegex `
        -Raw $functionsIndexRaw `
        -Pattern $callablePattern `
        -Message "Missing admin callable export in functions/src/index.ts: $callable"
    if ($null -ne $msg) { $errors.Add($msg) }
}

$msg = Assert-ContainsRegex `
    -Raw $adminSupportRaw `
    -Pattern 'const REGION = "europe-west1";' `
    -Message "Admin callable region is not pinned to europe-west1 in admin_account_support.ts."
if ($null -ne $msg) { $errors.Add($msg) }

foreach ($managedRole in @("club", "recruteur", "agent")) {
    $managedRolePattern = [regex]::Escape('"' + $managedRole + '"')
    $msg = Assert-ContainsRegex `
        -Raw $adminSupportRaw `
        -Pattern $managedRolePattern `
        -Message "Managed role '$managedRole' missing from admin_account_support.ts."
    if ($null -ne $msg) { $errors.Add($msg) }
}

$msg = Assert-ContainsRegex `
    -Raw $managedAccountsRaw `
    -Pattern 'createdByAdmin:\s*true' `
    -Message "provisionManagedAccount no longer enforces createdByAdmin=true in Firestore user document."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $firestoreRulesRaw `
    -Pattern 'function isPublicSignupRole\(role\)\s*\{\s*return role == "joueur" \|\| role == "fan";\s*\}' `
    -Message "firestore.rules no longer restricts public signup to joueur/fan."
if ($null -ne $msg) { $errors.Add($msg) }

if ($firestoreRulesRaw -match 'allow create: if isOwner\(userId\)\s*&&\s*request\.resource\.data\.uid == request\.auth\.uid\s*&&\s*isPublicSignupRole\(request\.resource\.data\.role\)\s*&&\s*request\.resource\.data\.createdByAdmin != true;') {
    # expected rule
} else {
    $errors.Add(
        "firestore.rules user create rule does not match the expected public self-signup guardrail."
    )
}

foreach ($roleLiteral in @("'joueur'", "'fan'", "'club'", "'recruteur'", "'agent'", "'admin'")) {
    $roleLiteralPattern = [regex]::Escape($roleLiteral)
    $msg = Assert-ContainsRegex `
        -Raw $rolePolicyRaw `
        -Pattern $roleLiteralPattern `
        -Message "Role literal $roleLiteral missing from lib/utils/account_role_policy.dart."
    if ($null -ne $msg) { $errors.Add($msg) }
}

$msg = Assert-ContainsRegex `
    -Raw $authSessionRaw `
    -Pattern 'Seuls les comptes joueur et fan peuvent' `
    -Message "AuthSessionService no longer blocks managed/admin self-signup on mobile."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $authSessionRaw `
    -Pattern 'adminPortalOnly' `
    -Message "AuthSessionService no longer handles adminPortalOnly access issue."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $sharedContractRaw `
    -Pattern 'projectId : `show-talent-5987d`' `
    -Message "docs/shared-backend-contract.md no longer pins the shared Firebase projectId."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $interRepoRunbookRaw `
    -Pattern 'region Functions pour les callables admin : `europe-west1`' `
    -Message "docs/inter-repo-admin-mobile-runbook.md no longer pins admin callable region."
if ($null -ne $msg) { $errors.Add($msg) }

if ($null -ne $resolvedAdminRepoPath) {
    $adminManagedAccountServicePath = Join-Path $resolvedAdminRepoPath "lib/services/managed_account_service.dart"
    $adminRolePolicyPath = Join-Path $resolvedAdminRepoPath "lib/utils/account_role_policy.dart"
    $adminMainPath = Join-Path $resolvedAdminRepoPath "lib/main.dart"
    $adminFirebaseOptionsPath = Join-Path $resolvedAdminRepoPath "lib/firebase_options.dart"
    $adminCreateScriptPath = Join-Path $resolvedAdminRepoPath "scripts/create_admin_account.mjs"
    $adminPrdRunbookPath = Join-Path $resolvedAdminRepoPath "docs/prd-runbook-exploitation-inter-depots.md"
    $adminProductionRunbookPath = Join-Path $resolvedAdminRepoPath "docs/runbook-production-admin-mobile.md"

    $adminManagedAccountServiceRaw = Get-Content -LiteralPath $adminManagedAccountServicePath -Raw
    $adminRolePolicyRaw = Get-Content -LiteralPath $adminRolePolicyPath -Raw
    $adminMainRaw = Get-Content -LiteralPath $adminMainPath -Raw
    $adminFirebaseOptionsRaw = Get-Content -LiteralPath $adminFirebaseOptionsPath -Raw
    $adminCreateScriptRaw = Get-Content -LiteralPath $adminCreateScriptPath -Raw
    $adminPrdRunbookRaw = Get-Content -LiteralPath $adminPrdRunbookPath -Raw
    $adminProductionRunbookRaw = Get-Content -LiteralPath $adminProductionRunbookPath -Raw

    $msg = Assert-ContainsRegex `
        -Raw $adminManagedAccountServiceRaw `
        -Pattern "static const String _functionsRegion = 'europe-west1';" `
        -Message "Admin managed_account_service.dart does not pin callable region to europe-west1."
    if ($null -ne $msg) { $errors.Add($msg) }

    foreach ($callable in $requiredCallables) {
        $callablePattern = [regex]::Escape("'" + $callable + "'")
        $msg = Assert-ContainsRegex `
            -Raw $adminManagedAccountServiceRaw `
            -Pattern $callablePattern `
            -Message "Admin managed_account_service.dart is missing callable usage: $callable"
        if ($null -ne $msg) { $errors.Add($msg) }
    }

    foreach ($roleLiteral in @("'joueur'", "'fan'", "'club'", "'recruteur'", "'agent'", "'admin'", "'platformAdmin'", "'superAdmin'")) {
        $roleLiteralPattern = [regex]::Escape($roleLiteral)
        $msg = Assert-ContainsRegex `
            -Raw $adminRolePolicyRaw `
            -Pattern $roleLiteralPattern `
            -Message "Admin role policy is missing literal $roleLiteral."
        if ($null -ne $msg) { $errors.Add($msg) }
    }

    $msg = Assert-ContainsRegex `
        -Raw $adminMainRaw `
        -Pattern "title:\s*'Adfoot Admin'" `
        -Message "Admin app title is not aligned to Adfoot branding in admin/lib/main.dart."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminFirebaseOptionsRaw `
        -Pattern "projectId:\s*'show-talent-5987d'" `
        -Message "Admin firebase_options.dart no longer pins projectId show-talent-5987d."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminCreateScriptRaw `
        -Pattern "const DEFAULT_ADMIN_NAME = 'Admin Adfoot';" `
        -Message "Admin bootstrap script default display name is not aligned to Adfoot branding."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminPrdRunbookRaw `
        -Pattern 'projectId : `show-talent-5987d`' `
        -Message "Admin PRD runbook no longer pins shared projectId."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminProductionRunbookRaw `
        -Pattern 'region Functions admin : `europe-west1`' `
        -Message "Admin production runbook no longer pins callable region."
    if ($null -ne $msg) { $errors.Add($msg) }
}

if ($Strict) {
    if ($sharedContractRaw -notmatch 'source d''autorite unique') {
        $warnings.Add("shared-backend-contract wording changed. Re-validate cross-repo governance manually.")
    }
    if ($null -ne $resolvedAdminRepoPath -and $adminFirebaseOptionsRaw -match "iosBundleId:\s*'com\.example\.showTalent'") {
        $warnings.Add("admin/lib/firebase_options.dart still references com.example.showTalent bundle IDs.")
    }
}

Write-Host "Checked files:"
foreach ($label in $checkedFiles) {
    Write-Host "- $label"
}

if ($null -ne $resolvedAdminRepoPath) {
    Write-Host "- admin/repositoryPath: $resolvedAdminRepoPath"
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
Write-Host "Admin/mobile shared contract check completed."
exit 0
