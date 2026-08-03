# Mobile App Check Validation Runbook

Project: `adfoot-production`
Region: `europe-west1`

Goal: keep upload callables protected by App Check while allowing release-build
validation before the app is published on Play Store.

## Current security model

- Mobile production config uses `APP_CHECK_ENABLED=true`.
- Upload callables use `ENFORCE_APPCHECK=true` when deployed with production
  env overrides.
- The upload path is protected on all callable steps:
  - `createUploadSession`
  - `requestThumbnailUploadUrl`
  - `finalizeUpload`

## Pre-Play-Store release validation

Use this lane only for trusted development phones. It keeps backend App Check
enforcement enabled, but uses a registered debug token because the release build
is installed outside Play Store.

```powershell
npm.cmd run mobile:appcheck:debug:production
npm.cmd run mobile:run:production -- --release
```

The first command registers a Firebase App Check debug token for the Android app
and writes the token to `config/mobile/production.json`, which is ignored by
git. The second command keeps the normal production flavor and build command.

Expected local config additions:

```json
{
  "APP_CHECK_ENABLED": "true",
  "APP_CHECK_DEBUG_PROVIDER": "true",
  "APP_CHECK_ANDROID_PROVIDER": "debug",
  "APP_CHECK_ANDROID_DEBUG_TOKEN": "<registered UUIDv4 token>"
}
```

Do not commit, paste into tickets, or share the debug token. Revoke it in
Firebase Console after validation if the phone or workstation is no longer
trusted.

## Real Play Integrity production path

Before a public Play Store build:

1. Remove `APP_CHECK_DEBUG_PROVIDER`, `APP_CHECK_ANDROID_PROVIDER`, and
   `APP_CHECK_ANDROID_DEBUG_TOKEN` from `config/mobile/production.json`.
2. Register the Android app in Firebase App Check with the Play Integrity
   provider.
3. Add the release signing certificate SHA-256 fingerprint used by
   `android/key.properties`.
4. If validating outside Play Store, configure the Firebase App Check Play
   Integrity advanced settings for that distribution channel.
5. Rebuild with:

```powershell
npm.cmd run mobile:run:production -- --release
```

## Upload validation

On a real Android device:

1. Sign in with a verified `joueur` account.
2. Add a short MP4 video.
3. Confirm the upload reaches `Finalisation...`.
4. Confirm the video document eventually becomes `status == "ready"` and
   `optimized == true`.

If the app shows `Verification de securite indisponible`, the client could not
obtain a valid App Check token. Check the local config provider first, then the
Firebase App Check registration for the Android app.

## Closed-test emergency mitigation

Use this only when the Play Store closed-test build is already live and client
logs show `App attestation failed`.

Read the remote production state:

```powershell
node scripts/check-mobile-appcheck-status.mjs --environment production
node scripts/list-recent-client-errors.mjs --environment production --limit 120 --inspect-users
node scripts/check-deployed-firebase-rules.mjs --environment production
```

Temporary closed-test mitigation, no new AAB required:

```powershell
node scripts/check-mobile-appcheck-status.mjs --environment production --allow-unrecognized-version true --execute
```

Then force-stop and reopen the Play-installed app on the tester phone. If App
Check was the blocker, `AppCheckService.initialize` should stop logging
`App attestation failed` and the upload callables should show
`app=VALID, auth=VALID` in Functions logs.

Rollback before a broader production rollout:

```powershell
node scripts/check-mobile-appcheck-status.mjs --environment production --allow-unrecognized-version false --execute
```

Before rolling back, confirm that the Firebase Android app `org.adfoot.app`
contains the Google Play **App signing key certificate** SHA-256 fingerprint
from Play Console > App integrity. Keep the upload-key SHA-256 registered too
if direct release-device validation is still needed.

## Remote smoke option

For CI or backend validation, provide a Firebase App Check token explicitly:

```powershell
$env:FIREBASE_APP_CHECK_TOKEN="<valid app check token>"
$env:FIREBASE_SMOKE_EMAIL="<verified joueur email>"
$env:FIREBASE_SMOKE_PASSWORD="<password>"
npm.cmd run video:quality:release:remote:verify
```
