# Mobile App Check Validation Runbook

Project: `adfoot-production`
Region: `europe-west1`

Goal: keep upload callables protected by App Check while allowing release-build
validation before the app is published on Play Store.

## Current security model

App Check runs in **soft mode** in production (`APP_CHECK_MODE=soft` in
`functions/.env.production`). The token is still requested by the client,
still verified by the platform when present, and now logged per call — but a
missing or invalid token no longer rejects the request.

### Why soft and not enforce

Production client logs (`client_logs` collection) showed Play Integrity
attestation failing on real tester devices, both as
`403 App attestation failed` and as repeated activation timeouts. Under
`enforce`, that single failure took down **every** mobile callable, because
`MOBILE_CALLABLE_OPTIONS` and `UPLOAD_CALLABLE_OPTIONS` both enforced it:
video upload, likes, reports, shares, follows, FCM token registration,
`completeEmailVerification` — and `logClientEvents`, which is why the
failures were nearly invisible in our own telemetry.

Play Integrity cannot be relied on as a hard gate for this device fleet: it
requires a Play-certified device with current Google Play services, and a
large share of low-cost Android handsets do not qualify. The App Check
config is already at its most permissive (`allowUnrecognizedVersion: true`,
`minDeviceRecognitionLevel: NO_INTEGRITY`, `requireLicensed: false`) and
attestation still fails.

### What actually protects the upload path

App Check was never the thing holding the door shut. Every upload callable
still enforces, server-side:

- Firebase ID token verification (`resolveCallableAuth`).
- Role/account state: `joueur`, not `authDisabled`, email verified
  (`assertUploadCallerEligible`).
- Per-user daily and concurrent upload quotas, transactionally
  (`MAX_VIDEO_UPLOADS_PER_DAY`, `MAX_CONCURRENT_VIDEO_UPLOADS`).
- File size and duration ceilings.
- Ownership on every session/finalize step; the video document is stamped
  with the uid decoded from the token, never a client-supplied one.
- Short-lived, per-object signed resumable upload URLs.

Firestore and Storage App Check enforcement is `UNENFORCED` for this project
(verify with `node scripts/check-mobile-appcheck-status.mjs`), so no client
read or write depends on a token either.

### Client contract

- `AppCheckService` never blocks: activation is fired and forgotten at
  startup (`unawaited` in `AppBootstrap.initialize`), failures retry in the
  background, and `getToken()` returns `null` rather than waiting.
- `CallableAuthGuard` attaches `X-Firebase-AppCheck` only when a token is
  available; a missing token never aborts a call.
- `ProfileRepository` warms App Check in the background but never gates a
  write on it.

Guardrail tests lock all three behaviours in — see
`test/callable_auth_guard_test.dart`,
`test/profile_edit_coherence_guardrails_test.dart` and
`test/android_release_readiness_guardrails_test.dart`.

## Soft mode is the destination, not a waypoint

**Decision: production stays on `APP_CHECK_MODE=soft` permanently.** This is
settled, not a pending migration. Play Integrity attestation fails on a large
share of the handsets this app actually serves, and enforcement traded a real,
measurable outage — every mobile callable down at once — for a hypothetical
attacker. There is no scheduled return to `enforce`.

`test/app_check_posture_guardrails_test.dart` pins this, because the change
that breaks it is a one-word edit in an env file and the damage only appears on
real handsets: never in CI, never on a Play-certified developer device.

### What replaces enforcement

App Check was never what held the door shut. The controls that do:

| Control | Where |
| --- | --- |
| Firebase ID token verified on every callable | `resolveCallableAuth` |
| No self-signup — accounts are admin-provisioned only | admin web app |
| Role and account state checked per call | `assertUploadCallerEligible` |
| Per-user daily / concurrent / pending / public video quotas | `upload_session.ts` |
| File size and duration limits | `upload_session.ts` |
| Outbound push ceilings (`MAX_FANOUTS_PER_HOUR`, `MAX_DIRECT_PUSHES_PER_MINUTE`) | `actions.ts` |
| Per-document and per-object ownership | `firestore.rules`, `storage.rules` |

The push ceilings exist specifically because of this posture: `sendOfferFanout`
notifies **every** player in one authenticated call, and with no platform
attestation gate in front of it, the ceiling has to live in the handler.

### Keeping attestation observable

Soft is not off. Tokens are still read and attached to `request.app`, and every
handler emits a structured line per call:

```json
{"event":"app_check_state","callable":"createUploadSession","appCheck":"valid|invalid|absent","mode":"soft","uid":"..."}
```

Read these as ongoing telemetry, not as a countdown. `absent` means the client
never produced a token — expected on much of the fleet, and harmless.
`invalid` means it produced one the platform refused; that is the anomaly worth
investigating. A sudden collapse in `valid` points at a client or Play Integrity
regression rather than at an attack.

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

In soft mode the app must never show an App Check error to the user. If an
upload still fails, the cause is elsewhere (auth, role, quota, network) —
read the failure code from `client_logs` and the `app_check_state` log line
for the same call before touching App Check configuration.

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
