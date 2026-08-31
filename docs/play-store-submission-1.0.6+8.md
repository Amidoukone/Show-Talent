# Play Store Submission - Adfoot 1.0.6+8

Reference date: 12 August 2026

This runbook is the operator checklist for uploading the already-built Android
App Bundle to Google Play **Internal testing**. It updates
`docs/play-store-submission-1.0.2+3.md` for the current build. Play production
access for `org.adfoot.app` has already been granted by Google, but this build
must still go through Internal testing before being promoted to Production.

## Artifact

- App name: Adfoot
- Package name: `org.adfoot.app`
- Version name: `1.0.6`
- Version code: `8`
- AAB: `artifacts/android/adfoot-production-20260812T123009Z.aab`
- Size: 69,696,914 bytes (66.47 MB)
- SHA-256: `B6F40D9266ADCAFDC407FD795E29F6F49AD0DC95EEEB5DCECD67DC9285CB380E`
- Android config: `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`, NDK `29.0.13599879`, ABI `arm64-v8a` only

Do not upload any older AAB from `artifacts/android/`.

## Local release state (verified 12 August 2026)

Passed gates for this bundle:

- `release:config:validate:strict` (production, strict)
- `check-android-release-readiness.ps1 -Environment production -ReleaseGate -RequirePlayIntegrityAppCheck` (no errors, no warnings)
- `check-production-backend-gate.ps1` (`cleanupUnverifiedUsers` last success 2026-08-11T14:26:08Z, within the 30h window)
- `release:android:bundle:playstore` (this build) completed successfully

Post-build verification (12 August 2026):

- Confirmed the AAB is bound to the **production** Firebase project, not
  staging: package `org.adfoot.app` (no `.staging` suffix anywhere in the
  manifest), Firebase project id `adfoot-production`, storage bucket
  `adfoot-production.firebasestorage.app`, sender id `975666203662`. No
  `adfoot-staging` string present anywhere in the bundle.
- Legal URLs all returned HTTP 200:
  - `https://adfoot.org/legal/privacy-policy.html`
  - `https://adfoot.org/legal/account-deletion.html`
  - `https://adfoot.org/.well-known/assetlinks.json`
- Live `assetlinks.json` currently lists a SHA-256 for `org.adfoot.app` that
  matches the local upload keystore. **Re-check this after the Play Console
  upload** — if Play App Signing is enabled, Google re-signs the app with its
  own certificate for distribution, which can differ from the upload key. See
  Step 3 below.

Known gap carried over from the previous release doc:

- Full `flutter test` should be run (not just the targeted readiness guardrail
  test) before promoting this build past Internal testing.

## What changed since the last tagged release (`android-playstore-1.0.2+3`)

47 commits since 1.0.2+3, mostly stability and polish. No new third-party SDKs
were added (data safety declarations in `docs/play-console-data-safety.md`
remain valid as-is). Notable groups of changes:

- Video upload/playback reliability: atomic upload rate-limit and public-video
  count checks, bounded retry on upload callables, stale-processing video
  reaping, duration-probe failures now fail fast, fixed a permanent
  `VideoController` leak and overlapping-overlay bug on tap-to-pause.
- Crash/error hardening: malformed Event/Offre/Notification/Video parsing no
  longer crashes, non-essential bootstrap steps are now failure-resilient,
  uncaught errors are reported to remote logs in production, raw technical
  errors no longer leak to end users (settings, upload flow).
- Auth/security: App Check enforced on mobile-only callables, admin auth now
  requires the custom claim (not Firestore role alone), fixed an App Check
  `activate()` hang blocking startup, fixed permission-denied on profile/CV
  writes for unverified accounts.
- Data integrity: fixed lost follower/following counters during account
  deletion, fixed a video owner being able to reset an already-live video.
- UI polish: unified profile/event/offer card headers onto shared widgets,
  football-context design tokens on Home, wired error-banner colors, widened
  text scale cap.
- Platform: targets Android 16 (API 36), production video limits raised to
  150 MB / 3 minutes.

## Suggested release notes (Internal testing "What's new")

```text
Version 1.0.6 - stabilite et corrections.

- Fiabilite accrue de l'upload et de la lecture video.
- Corrections de plantages sur profils, evenements et notifications.
- Renforcement de la securite des comptes et de l'authentification.
- Corrections d'affichage sur l'accueil, les profils et les evenements.
```

Internal testing notes do not need to be as polished as a production listing,
but keep them accurate to what testers should focus on.

## Step 1 - Upload to Internal testing

Path: `Test and release > Testing > Internal testing`.

1. Open the existing `org.adfoot.app` app in Play Console (already created;
   do not create a new app).
2. Go to the Internal testing track. If no release exists yet, create one.
3. Create a new release.
4. Upload:

   ```text
   artifacts/android/adfoot-production-20260812T123009Z.aab
   ```

5. Confirm Play reads back:
   - Package: `org.adfoot.app`
   - Version code: `8`
   - Version name: `1.0.6`
6. Paste the release notes above into the release notes field.
7. Save, review the release, and roll out to Internal testing.
8. Copy the opt-in/test link from the Internal testing page and share it with
   your testers.

## Step 2 - Testers

Internal testing supports up to 100 testers by email list.

- [ ] Decide the tester email list (yourself + any colleagues who should
      validate this build). Add them under Internal testing > Testers.
- [ ] Send each tester the opt-in link from Step 1.8. They must open it and
      tap "Become a tester" before the Play Store listing becomes visible to
      their account.

This is separate from the "12 testers / 14 days" closed-testing requirement in
the previous doc — that requirement applies to closed testing before first
production access, which Google has already granted for this app. Internal
testing has no minimum tester count or duration; it exists purely to validate
the build before promoting it.

## Step 3 - Play App Signing follow-up (only if this is the first-ever upload)

If this is not the first AAB ever uploaded for `org.adfoot.app`, skip this
step — Play App Signing is already configured and the assetlinks fingerprint
was already reconciled in a previous release.

Otherwise, after this upload:

1. Go to `Test and release > Setup > App signing`.
2. Copy the SHA-256 certificate fingerprint for the `App signing key
   certificate` (this may differ from the local upload key fingerprint
   checked above).
3. Register that fingerprint in Firebase App Check / Play Integrity for the
   production Android app if not already registered.
4. If it differs from what is currently live, update
   `site_pub/.well-known/assetlinks.json`:

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
      correct afterward (regression check for `ac18ee3`).
- [ ] App Check protected backend calls succeed (regression check for
      `4743bd2`).
- [ ] App links for `https://adfoot.org/v/...` and auth action links.

If App Check fails only on the Play-installed build, check the Play app
signing SHA-256 registration in Firebase first (Step 3).

## Step 5 - Before promoting to Production

1. Check the Play pre-launch report for this release.
2. Check Android vitals if Internal testing produced enough signal.
3. Resolve any Play policy warnings shown on the release.
4. Confirm the Data Safety form (`docs/play-console-data-safety.md`) and app
   content declarations from `docs/play-store-submission-1.0.2+3.md` Step 4
   are still accurate — no new SDKs were added in this release, so no changes
   are expected.
5. If any code/config change is made after this AAB, bump `versionCode` above
   `8` in `pubspec.yaml`, rebuild with
   `npm.cmd run release:android:bundle:playstore`, and upload the new AAB
   instead of reusing this artifact.
6. Promote the same reviewed release from Internal testing to Production in
   Play Console (no rebuild needed if nothing changed).

## Reference

Full first-time setup steps (creating the app, store listing, app content,
data safety, target audience, content rating) are documented in
`docs/play-store-submission-1.0.2+3.md` and do not need to be repeated for
this release since the app already exists in Play Console with production
access granted.
