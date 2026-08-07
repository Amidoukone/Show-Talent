# Android Firebase Local Config

The root file `android/app/google-services.json` is intentionally ignored by
git to avoid committing real API keys.

Use this workflow:

1. Copy `android/app/google-services.example.json` to
   `android/app/google-services.json`.
2. Replace placeholder values with real local values from Firebase.
3. Keep `android/app/google-services.json` local only (never commit).

When native flavors are fully active, prefer flavor-specific files in:

- `android/app/src/local/google-services.json`
- `android/app/src/staging/google-services.json`
- `android/app/src/production/google-services.json`
