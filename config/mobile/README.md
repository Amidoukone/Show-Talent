# Mobile Firebase Environment Config

This folder keeps the future Firebase runtime values used by the mobile
launcher script.

Committed templates:

- `config/mobile/local.example.json`
- `config/mobile/staging.example.json`
- `config/mobile/production.example.json`
- `config/mobile/production-next.example.json`

Templates also expose optional web FCM keys (`FIREBASE_WEB_*`) so web push can
run without hardcoded values.

Local files to create later:

- `config/mobile/local.json`
- `config/mobile/staging.json`
- `config/mobile/production.json`
- `config/mobile/production-next.json`

The real `*.json` files are ignored by git on purpose.

## How it works

`scripts/flutter-run-mobile-env.ps1` now looks for `config/mobile/<environment>.json`
automatically.

`production-next` is an operational lane before final cutover. It reuses the
native `production` flavor and IDs, but keeps its own runtime config file and
Firebase alias.

If the file exists, its flat key/value pairs are converted into
`--dart-define=...` arguments.

If the file does not exist, the script can still run, but Firebase runtime
values will be placeholders from committed templates.

For real backend access, create and use local non-committed files:

- `config/mobile/<environment>.json`
- `android/app/google-services.json` (or flavor-specific native files)
- `ios/Firebase/<environment>/GoogleService-Info.plist`

## Current policy

Policy after secret hardening:

- never commit real API keys in `lib/firebase_options.dart` or native Firebase files
- keep real values only in local ignored files
- use `.example` templates as references and fill local files before real runs

## Validation

Use the validation script before wiring real native Firebase files:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-mobile-firebase-config.ps1 -Environment staging
```

Strict mode for future native activation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-mobile-firebase-config.ps1 -Environment staging -RequireConfig -RequireNativeFiles
```

Remote Firebase Auth preflight before a real device test:

```powershell
npm.cmd run mobile:auth:preflight:staging
```

`scripts/flutter-run-mobile-env.ps1` now runs this preflight automatically for
non-local environments when a real config file is present. Use
`-SkipRemoteAuthPreflight` only when you intentionally want to bypass the
remote check.
