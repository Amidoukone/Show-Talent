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

Production templates set `APP_CHECK_ENABLED=true` so Android release builds use
Play Integrity before backend App Check enforcement is enabled.

`VIDEO_SHARE_BASE_URL` controls the public URL used when a user shares a video.
Production should use `https://adfoot.org`; staging can use the staging Hosting
domain so shared staging video IDs resolve against the staging project.

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

## Pre-Play-Store App Check validation

Production config keeps `APP_CHECK_ENABLED=true`. For a release build installed
directly on a phone before Play Store publication, use a registered App Check
debug token instead of disabling backend enforcement:

```powershell
npm.cmd run mobile:appcheck:debug:production
npm.cmd run mobile:run:production -- --release
```

The debug command creates a Firebase App Check debug token for the Android app
and writes these keys only to the ignored local config file:

- `APP_CHECK_DEBUG_PROVIDER=true`
- `APP_CHECK_ANDROID_PROVIDER=debug`
- `APP_CHECK_ANDROID_DEBUG_TOKEN=<registered UUIDv4 token>`

Do not commit or share the generated token. Before the final Play Store build,
remove those debug keys from the local config and verify that Play Integrity is
registered in Firebase App Check with the release signing SHA-256 fingerprint.

Final Play Store guard:

```powershell
npm.cmd run release:config:validate:playstore
npm.cmd run release:android:check:playstore
npm.cmd run release:android:bundle:playstore
```

Those commands fail if the production mobile config still requests the App
Check debug provider or contains a debug App Check token.
