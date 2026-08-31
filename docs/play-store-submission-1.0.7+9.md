# Play Store Submission - Adfoot 1.0.7+9

Reference date: 12 August 2026

This runbook is the operator checklist for uploading the already-built Android
App Bundle to Google Play **Internal testing**. It supersedes
`docs/play-store-submission-1.0.6+8.md`. Play production access for
`org.adfoot.app` has already been granted by Google, but this build must still
go through Internal testing before being promoted to Production.

## Why this doc exists instead of reusing 1.0.6+8

The `1.0.6+8` AAB (`artifacts/android/adfoot-production-20260812T123009Z.aab`)
was built and verified correct, but was never uploaded. `versionCode 8` had
already been released to Internal testing on **2026-08-09 22:49** (visible in
Play Console as "Release summary ... Available to internal testers ...
Released on 9 Aug 22:49 ... App bundle 8 (1.0.6)"). Google Play rejects any
upload whose `versionCode` was already used on any track, so uploading that
AAB would have failed. `pubspec.yaml` was bumped from `1.0.6+8` to `1.0.7+9`
and the AAB was rebuilt before uploading anything.

## Artifact

- App name: Adfoot
- Package name: `org.adfoot.app`
- Version name: `1.0.7`
- Version code: `9`
- AAB: `artifacts/android/adfoot-production-20260812T151214Z.aab`
- Size: 69,696,914 bytes (66.47 MB)
- SHA-256: `EC9207BA6F6642AABB46961AF27ED83CEBF391DC4B0087069D7527051E8F0F37`
- Android config: `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`, NDK `29.0.13599879`, ABI `arm64-v8a` only

Do not upload any older AAB from `artifacts/android/`, including the
`1.0.6+8` build from earlier today — its versionCode is already consumed.

## Local release state (verified 12 August 2026)

Passed gates for this bundle:

- `release:config:validate:strict` (production, strict) — verified before the
  first (1.0.6+8) build attempt; config did not change for this rebuild.
- `check-android-release-readiness.ps1 -Environment production -ReleaseGate -RequirePlayIntegrityAppCheck` — re-run after the version bump, no errors, no
  warnings (build number 9 satisfies the version-bump requirement).
- `check-production-backend-gate.ps1` (`cleanupUnverifiedUsers` last success
  2026-08-11T14:26:08Z, within the 30h window) — verified before the first
  build attempt.
- `release:android:bundle:playstore` completed successfully on the second
  attempt. The first attempt failed with a Windows file-lock error
  (`AVERTISSEMENT: Could not move generated build directory before
  cleanup ... file ... en cours d'utilisation par un autre processus`)
  because a Gradle daemon from the prior 1.0.6+8 build was still holding a
  handle on a file under `build\`. Fixed by running `gradlew --stop` in
  `android\` to release the daemon, then rebuilding.

Post-build verification (12 August 2026):

- Confirmed the AAB is bound to the **production** Firebase project, not
  staging: package `org.adfoot.app` (no `.staging` suffix anywhere in the
  manifest), Firebase project id `adfoot-production`, storage bucket
  `adfoot-production.firebasestorage.app`, sender id `975666203662`. No
  `adfoot-staging` string present anywhere in the bundle.
- Confirmed `versionName` `1.0.7` is present in the compiled manifest.
- Legal URLs all returned HTTP 200 (checked prior to the first build attempt
  the same day):
  - `https://adfoot.org/legal/privacy-policy.html`
  - `https://adfoot.org/legal/account-deletion.html`
  - `https://adfoot.org/.well-known/assetlinks.json`
- Live `assetlinks.json` lists a SHA-256 for `org.adfoot.app` that matches the
  local upload keystore. **Re-check this after the Play Console upload** — if
  Play App Signing is enabled, Google re-signs the app with its own
  certificate for distribution, which can differ from the upload key. See
  Step 3 below. This app already has a release on Internal testing from
  2026-08-09, so Play App Signing setup should already be complete — skip
  Step 3 unless the assetlinks fingerprint check starts failing.

Known gap carried over from the previous release docs:

- Full `flutter test` should be run (not just the targeted readiness guardrail
  test) before promoting this build past Internal testing.

## What changed since the last tagged release (`android-playstore-1.0.2+3`)

Same set of changes as documented in
`docs/play-store-submission-1.0.6+8.md` — no code changed between 1.0.6+8 and
1.0.7+9, only the version number. See that doc for the full commit-grouped
summary (video upload/playback reliability, crash/error hardening, auth/
security hardening, data integrity fixes, UI polish, Android 16/API 36
targeting).

## Suggested release notes (Internal testing "What's new")

```text
Version 1.0.7 - stabilite et corrections.

- Fiabilite accrue de l'upload et de la lecture video.
- Corrections de plantages sur profils, evenements et notifications.
- Renforcement de la securite des comptes et de l'authentification.
- Corrections d'affichage sur l'accueil, les profils et les evenements.
```

## Step 1 - Upload to Internal testing

Path: `Test and release > Testing > Internal testing`.

1. Open the existing `org.adfoot.app` app in Play Console (already created;
   do not create a new app).
2. Go to the Internal testing track (it already has the `8 (1.0.6)` release
   from 2026-08-09).
3. Create a new release.
4. Upload:

   ```text
   artifacts/android/adfoot-production-20260812T151214Z.aab
   ```

5. Confirm Play reads back:
   - Package: `org.adfoot.app`
   - Version code: `9`
   - Version name: `1.0.7`
6. Paste the release notes above into the release notes field.
7. Save, review the release, and roll out to Internal testing.
8. Copy the opt-in/test link (or reuse the existing one if testers already
   opted in from the `8 (1.0.6)` release — the same link stays valid).

## Step 2 - Testers

Internal testing supports up to 100 testers by email list. If testers were
already added for the `8 (1.0.6)` release on 2026-08-09, they do not need to
opt in again — the same tester list and link apply to every release on this
track.

- [ ] Confirm the existing tester list is still correct, or add new testers
      under Internal testing > Testers.

## Step 3 - Play App Signing follow-up (skip unless the fingerprint check fails)

This app already completed its first-ever upload on 2026-08-09, so Play App
Signing is already configured. Skip this step unless the assetlinks
fingerprint check in Step 4 fails.

1. Go to `Test and release > Setup > App signing`.
2. Copy the SHA-256 certificate fingerprint for the `App signing key
   certificate`.
3. Confirm it is registered in Firebase App Check / Play Integrity for the
   production Android app.
4. Confirm `site_pub/.well-known/assetlinks.json` matches. If not:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\update-assetlinks-fingerprints.ps1 -ReleaseFingerprint "<PLAY_APP_SIGNING_SHA256>"
   ```

5. Redeploy hosting so `https://adfoot.org/.well-known/assetlinks.json` serves
   the updated value.

## Step 4 - Smoke tests from the Play-installed build

Install from the Internal testing opt-in link, not from `flutter run`.

Run on a real Android device:

- [ ] Login with a managed tester account.
- [ ] Email verification and password reset deep links.
- [ ] Profile read/edit, including profile photo.
- [ ] Video upload from gallery, processing, feed playback, sharing.
- [ ] Notifications in foreground and background.
- [ ] Messaging/contact flow.
- [ ] Opportunity/event browsing.
- [ ] Account deletion entry point and follower/following counters stay
      correct afterward.
- [ ] App Check protected backend calls succeed.
- [ ] App links for `https://adfoot.org/v/...` and auth action links.

If App Check fails only on the Play-installed build, check the Play app
signing SHA-256 registration in Firebase first (Step 3).

## Step 5 - Before promoting to Production

1. Check the Play pre-launch report for this release.
2. Check Android vitals if Internal testing produced enough signal.
3. Resolve any Play policy warnings shown on the release.
4. Confirm the Data Safety form (`docs/play-console-data-safety.md`) and app
   content declarations are still accurate — no new SDKs were added in this
   release, so no changes are expected.
5. If any code/config change is made after this AAB, bump `versionCode`
   above `9` in `pubspec.yaml`, rebuild with
   `npm.cmd run release:android:bundle:playstore`, and upload the new AAB
   instead of reusing this artifact. If a build fails with a file-lock error
   on `build\`, run `gradlew --stop` from `android\` first.
6. Promote the same reviewed release from Internal testing to Production in
   Play Console (no rebuild needed if nothing changed).

## Reference

Full first-time setup steps (creating the app, store listing, app content,
data safety, target audience, content rating) are documented in
`docs/play-store-submission-1.0.2+3.md` and do not need to be repeated for
this release since the app already exists in Play Console with production
access granted and an existing Internal testing release.
