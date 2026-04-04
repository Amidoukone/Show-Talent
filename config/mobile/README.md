# Mobile Firebase Environment Config

This folder keeps the future Firebase runtime values used by the mobile
launcher script.

Committed templates:

- `config/mobile/local.example.json`
- `config/mobile/staging.example.json`
- `config/mobile/production.example.json`

Local files to create later:

- `config/mobile/local.json`
- `config/mobile/staging.json`
- `config/mobile/production.json`

The real `*.json` files are ignored by git on purpose.

## How it works

`scripts/flutter-run-mobile-env.ps1` now looks for `config/mobile/<environment>.json`
automatically.

If the file exists, its flat key/value pairs are converted into
`--dart-define=...` arguments.

If the file does not exist, the script keeps the current safe behavior and
falls back to:

- `lib/firebase_options.dart`
- the active native Firebase files already wired in the project

## Current policy

Until the real staging and production Firebase projects are created:

- `local.json` is optional because local work can stay emulator-first
- `staging.json` and `production.json` can stay absent
- missing files must not break the current base project

## Validation

Use the validation script before wiring real native Firebase files:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-mobile-firebase-config.ps1 -Environment staging
```

Strict mode for future native activation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-mobile-firebase-config.ps1 -Environment staging -RequireConfig -RequireNativeFiles
```
