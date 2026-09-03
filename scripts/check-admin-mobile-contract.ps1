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

function Get-MirrorBody {
    <#
        Normalise une copie miroir pour la comparaison.

        Retire l'en-tete de commentaires qui explique la copie, ramene le
        prefixe de paquet du depot admin sur celui du mobile, et neutralise
        les fins de ligne et espaces de fin. Ce qui reste doit etre identique
        des deux cotes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Raw
    )

    $normalized = $Raw -replace "`r`n", "`n"
    $normalized = $normalized -replace "package:show_talent/", "package:adfoot/"

    $lines = $normalized -split "`n"
    $start = 0
    while ($start -lt $lines.Count) {
        $line = $lines[$start].Trim()
        if ($line -eq "" -or $line.StartsWith("//")) {
            $start++
            continue
        }
        break
    }

    $body = ($lines[$start..($lines.Count - 1)] | ForEach-Object { $_.TrimEnd() }) -join "`n"
    return $body.Trim()
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$checkedFiles = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($AdminRepoPath)) {
    $AdminRepoPath = $env:ADFOOT_ADMIN_REPO
}

if ([string]::IsNullOrWhiteSpace($AdminRepoPath)) {
    $defaultAdminRepoPath = Join-Path $env:USERPROFILE "Desktop\MyApp\show_talent - web"
    if (Test-Path -LiteralPath $defaultAdminRepoPath) {
        $AdminRepoPath = $defaultAdminRepoPath
    }
}

$resolvedAdminRepoPath = $null
if (-not [string]::IsNullOrWhiteSpace($AdminRepoPath)) {
    try {
        $resolvedAdminRepoPath = (Resolve-Path -LiteralPath $AdminRepoPath).Path
    } catch {
        $errors.Add("Admin repo path cannot be resolved: $AdminRepoPath")
    }
} else {
    # This check exists to catch cross-repo drift (admin <-> mobile). A
    # missing sibling repo used to just skip that half with a warning and
    # still exit 0 -- silently proving nothing. It's a hard failure now:
    # pass -AdminRepoPath or set ADFOOT_ADMIN_REPO.
    $errors.Add(
        "Admin repo path not provided and could not be auto-detected. Set -AdminRepoPath or `$env:ADFOOT_ADMIN_REPO -- this check cannot validate cross-repo consistency without it."
    )
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
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/services/admin_content_service.dart"; Label = "admin/lib/services/admin_content_service.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/utils/account_role_policy.dart"; Label = "admin/lib/utils/account_role_policy.dart" },
        @{ Path = Join-Path $resolvedAdminRepoPath "lib/utils/admin_callable_action_catalog.dart"; Label = "admin/lib/utils/admin_callable_action_catalog.dart" },
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
}

# --- Vocabulaire du football : trois copies, zero divergence toleree --------
#
# Le meme vocabulaire existe en Dart cote mobile, en Dart cote admin et en
# TypeScript cote Functions. Ce n'est pas un accident : les deux depots se
# deploient separement, et un paquet partage ferait dependre une mise en
# production mobile d'une publication de paquet.
#
# La copie mobile <-> TypeScript est verrouillee par
# test/football_vocabulary_parity_test.dart. Celle-ci verrouille l'autre
# moitie, et elle est la plus dangereuse : le SDK Admin contourne
# firestore.rules, donc un code que le portail ecrirait sans que le mobile le
# connaisse produirait un champ lu comme nul -- une fiche qui perd son poste
# sans erreur nulle part, dans l'outil meme qui sert a moderer les fiches.
#
# La comparaison porte sur le fichier entier, pas seulement sur les codes :
# une borne, un parseur ou une regle de troncature qui divergerait ferait
# exactement le meme genre de degat.
if ($null -ne $resolvedAdminRepoPath) {
    $mirroredModelFiles = @(
        "lib/models/football_vocabulary.dart",
        "lib/models/player_football_profile.dart",
        "lib/models/org_football_profile.dart",
        # L'offre porte le meme vocabulaire que la fiche joueur, et c'est ce
        # qui rend le rapprochement possible. Elle a pourtant derive sans que
        # rien ne le dise : le mobile a remplace `posteRecherche` et `niveau`
        # par `positionCodes[]`, `ageCategories[]` et `clubLevel`, ce portail a
        # continue de lire les anciens champs, et une cle absente se lit comme
        # nulle -- la recherche par poste ne remontait plus rien, en silence.
        "lib/models/offre.dart",
        "lib/utils/country_codes.dart"
    )

    foreach ($relativePath in $mirroredModelFiles) {
        $mobilePath = Join-Path $repoRoot $relativePath
        $adminPath = Join-Path $resolvedAdminRepoPath $relativePath

        if (-not (Test-Path -LiteralPath $mobilePath)) {
            $errors.Add("Missing mirrored model in the mobile repo: $relativePath")
            continue
        }
        if (-not (Test-Path -LiteralPath $adminPath)) {
            $errors.Add(
                "Missing mirrored model in the admin repo: $relativePath. The admin portal cannot read a profile it does not share the vocabulary of."
            )
            continue
        }

        $mobileBody = Get-MirrorBody -Raw (Get-Content -LiteralPath $mobilePath -Raw)
        $adminBody = Get-MirrorBody -Raw (Get-Content -LiteralPath $adminPath -Raw)

        if ($mobileBody -ne $adminBody) {
            $errors.Add(
                "Mirrored model drifted between repos: $relativePath. Copy the mobile file over the admin one, keeping only the admin mirror header and the package prefix."
            )
        }

        $checkedFiles.Add("mirrored: $relativePath")
    }
}

# This mobile repo must never re-grow its own create-admin script -- the
# admin repo is the sole source of truth (see docs/shared-backend-contract.md).
$mobileCreateAdminScriptPath = Join-Path $repoRoot "scripts/create_admin_account.mjs"
if (Test-Path -LiteralPath $mobileCreateAdminScriptPath) {
    $errors.Add(
        "scripts/create_admin_account.mjs exists in the mobile repo. Admin account bootstrap must live only in the admin repo -- delete this copy."
    )
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
    "updateManagedAccountProfile",
    # Entitlements recorded by the agency. It stayed out of this list for as
    # long as the admin portal had no interface calling it -- adding it then
    # would only have failed the guardrail. The interface exists now
    # (ManagedAccountService + user_management_widget), so it is held to the
    # same standard as the rest.
    "setManagedAccountMembership"
)

# Content-moderation callables (video/offer/event/contact-intake). These are
# real and already called from the admin repo's AdminContentService, but
# used to be absent from every catalog/contract check -- that's exactly how
# they went undocumented for a whole rollout. submitContactIntakeFeedback is
# deliberately excluded: it's a participant-facing callable, not an admin one.
$requiredContentCallables = @(
    "adminSetOfferStatus",
    "adminDeleteOffer",
    "adminSetEventStatus",
    "adminDeleteEvent",
    "adminSetVideoStatus",
    "adminRejectVideo",
    "adminDeleteVideo",
    "adminSetContactIntakeFollowUp",
    "adminDeleteContactIntake",
    "adminDeleteContactIntakeConversation"
)

foreach ($callable in ($requiredCallables + $requiredContentCallables)) {
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
    -Raw $managedAccountsRaw `
    -Pattern 'isPrivilegedClaims\(userRecord\.customClaims\)' `
    -Message "provisionManagedAccount no longer rejects existing Auth users with admin claims."
if ($null -ne $msg) { $errors.Add($msg) }

$userCreateDisabledPattern = 'match\s+/users/\{userId\}\s*\{[\s\S]*?allow create:\s*if false;'
if ($firestoreRulesRaw -match $userCreateDisabledPattern) {
    # expected rule
} else {
    $errors.Add(
        "firestore.rules user create rule does not match the expected admin-only provisioning guardrail."
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
    -Pattern 'publicSignupDisabledMessage' `
    -Message "AuthSessionService no longer disables public mobile self-signup."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $authSessionRaw `
    -Pattern 'adminPortalOnly' `
    -Message "AuthSessionService no longer handles adminPortalOnly access issue."
if ($null -ne $msg) { $errors.Add($msg) }

$msg = Assert-ContainsRegex `
    -Raw $sharedContractRaw `
    -Pattern 'APP_ENV=production' `
    -Message "docs/shared-backend-contract.md no longer documents environment-driven backend targeting."
if ($null -ne $msg) { $errors.Add($msg) }

foreach ($callable in ($requiredCallables + $requiredContentCallables)) {
    $callablePattern = "(?<![A-Za-z0-9_])" + [regex]::Escape($callable) + "(?![A-Za-z0-9_])"
    $msg = Assert-ContainsRegex `
        -Raw $sharedContractRaw `
        -Pattern $callablePattern `
        -Message "docs/shared-backend-contract.md is missing callable: $callable"
    if ($null -ne $msg) { $errors.Add($msg) }
}

$msg = Assert-ContainsRegex `
    -Raw $interRepoRunbookRaw `
    -Pattern 'region Functions pour les callables admin : `europe-west1`' `
    -Message "docs/inter-repo-admin-mobile-runbook.md no longer pins admin callable region."
if ($null -ne $msg) { $errors.Add($msg) }

if ($null -ne $resolvedAdminRepoPath) {
    $adminManagedAccountServicePath = Join-Path $resolvedAdminRepoPath "lib/services/managed_account_service.dart"
    $adminContentServicePath = Join-Path $resolvedAdminRepoPath "lib/services/admin_content_service.dart"
    $adminCallableCatalogPath = Join-Path $resolvedAdminRepoPath "lib/utils/admin_callable_action_catalog.dart"
    $adminRolePolicyPath = Join-Path $resolvedAdminRepoPath "lib/utils/account_role_policy.dart"
    $adminMainPath = Join-Path $resolvedAdminRepoPath "lib/main.dart"
    $adminFirebaseOptionsPath = Join-Path $resolvedAdminRepoPath "lib/firebase_options.dart"
    $adminCreateScriptPath = Join-Path $resolvedAdminRepoPath "scripts/create_admin_account.mjs"
    $adminPrdRunbookPath = Join-Path $resolvedAdminRepoPath "docs/prd-runbook-exploitation-inter-depots.md"
    $adminProductionRunbookPath = Join-Path $resolvedAdminRepoPath "docs/runbook-production-admin-mobile.md"

    $adminManagedAccountServiceRaw = Get-Content -LiteralPath $adminManagedAccountServicePath -Raw
    $adminContentServiceRaw = Get-Content -LiteralPath $adminContentServicePath -Raw
    $adminCallableCatalogRaw = Get-Content -LiteralPath $adminCallableCatalogPath -Raw
    $adminRolePolicyRaw = Get-Content -LiteralPath $adminRolePolicyPath -Raw
    $adminMainRaw = Get-Content -LiteralPath $adminMainPath -Raw
    $adminFirebaseOptionsRaw = Get-Content -LiteralPath $adminFirebaseOptionsPath -Raw
    $adminCreateScriptRaw = Get-Content -LiteralPath $adminCreateScriptPath -Raw
    $adminPrdRunbookRaw = Get-Content -LiteralPath $adminPrdRunbookPath -Raw
    $adminProductionRunbookRaw = Get-Content -LiteralPath $adminProductionRunbookPath -Raw

    $msg = Assert-ContainsRegex `
        -Raw $adminManagedAccountServiceRaw `
        -Pattern "AppEnvironmentConfig\.functionsRegion" `
        -Message "Admin managed_account_service.dart does not use AppEnvironmentConfig.functionsRegion."
    if ($null -ne $msg) { $errors.Add($msg) }

    foreach ($callable in $requiredCallables) {
        $callablePattern = [regex]::Escape("'" + $callable + "'")
        $msg = Assert-ContainsRegex `
            -Raw $adminManagedAccountServiceRaw `
            -Pattern $callablePattern `
            -Message "Admin managed_account_service.dart is missing callable usage: $callable"
        if ($null -ne $msg) { $errors.Add($msg) }

        $catalogMsg = Assert-ContainsRegex `
            -Raw $adminCallableCatalogRaw `
            -Pattern $callablePattern `
            -Message "Admin admin_callable_action_catalog.dart is missing catalog entry: $callable"
        if ($null -ne $catalogMsg) { $errors.Add($catalogMsg) }
    }

    # Content-moderation callables must be wired in AdminContentService AND
    # listed in the catalog -- the whole point is one list, not two that
    # drift independently (see docs/admin-offer-event-rollout-plan.md).
    foreach ($callable in $requiredContentCallables) {
        $callablePattern = [regex]::Escape("'" + $callable + "'")
        $msg = Assert-ContainsRegex `
            -Raw $adminContentServiceRaw `
            -Pattern $callablePattern `
            -Message "Admin admin_content_service.dart is missing callable usage: $callable"
        if ($null -ne $msg) { $errors.Add($msg) }

        $catalogMsg = Assert-ContainsRegex `
            -Raw $adminCallableCatalogRaw `
            -Pattern $callablePattern `
            -Message "Admin admin_callable_action_catalog.dart is missing catalog entry: $callable"
        if ($null -ne $catalogMsg) { $errors.Add($catalogMsg) }
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
        -Pattern "projectId:\s*'adfoot-production'" `
        -Message "Admin firebase_options.dart does not default to adfoot-production."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminCreateScriptRaw `
        -Pattern "const DEFAULT_ADMIN_NAME = 'Admin Adfoot';" `
        -Message "Admin bootstrap script default display name is not aligned to Adfoot branding."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminPrdRunbookRaw `
        -Pattern 'APP_ENV` / `FIREBASE_PROJECT_ID' `
        -Message "Admin PRD runbook does not document environment-driven project selection."
    if ($null -ne $msg) { $errors.Add($msg) }

    $msg = Assert-ContainsRegex `
        -Raw $adminProductionRunbookRaw `
        -Pattern 'FIREBASE_FUNCTIONS_REGION' `
        -Message "Admin production runbook does not document the Functions region configuration."
    if ($null -ne $msg) { $errors.Add($msg) }
}

if ($Strict) {
    if ($sharedContractRaw -notmatch "source d'? ?autorite unique") {
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
