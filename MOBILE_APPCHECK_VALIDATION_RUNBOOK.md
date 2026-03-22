# Mobile App Check Validation Runbook (Progressive / Safe)

Project: `show-talent-5987d`  
Region: `europe-west1`

Goal: validate upload flow from the real mobile app with Firebase Auth token and App Check, without blocking development.

## Safety model (already applied)

- Client App Check is integrated but disabled by default (`APP_CHECK_ENABLED=false`).
- Upload callables use a backend toggle:
  - `ENFORCE_APPCHECK=false` by default (safe for development).
  - can be switched to `true` when all active clients send valid App Check tokens.

## 1) Development validation from real mobile app

Run the app in debug with App Check enabled:

```bash
flutter run \
  --dart-define=APP_CHECK_ENABLED=true \
  --dart-define=APP_CHECK_DEBUG_PROVIDER=true
```

Then execute the real upload flow in the app:

1. login with a normal user account
2. create upload session
3. upload video
4. upload thumbnail
5. finalize upload

Expected behavior:

- no `unauthenticated` error on callables
- upload completes as before

## 2) Register debug App Check token (Firebase Console)

In debug mode, Firebase prints a debug App Check token in device logs.

Add it in Firebase Console:

1. App Check
2. Manage debug tokens
3. Add token

Repeat test flow in app after token registration.

## 3) Verify server logs

Use this helper script from repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-mobile-upload-logs.ps1
```

Expected:

- `createUploadSession`, `requestThumbnailUploadUrl`, `finalizeUpload`
- each function has at least one log with `"auth":"VALID"` and `"app":"VALID"`

## 4) Progressive production rollout

Keep this sequence:

1. deploy client build with App Check enabled (release providers)
2. monitor logs until app tokens are consistently valid
3. switch backend env `ENFORCE_APPCHECK=true`
4. deploy only upload callables

Do not enable enforcement before step 2 is stable.

## 5) Backend switch details

`functions/src/upload_session.ts` uses:

```ts
const ENFORCE_APP_CHECK = process.env.ENFORCE_APPCHECK === "true";
```

When `true`, these callables enforce App Check:

- `createUploadSession`
- `requestThumbnailUploadUrl`
- `finalizeUpload`
