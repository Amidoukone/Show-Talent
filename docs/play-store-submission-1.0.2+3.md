# Play Store Submission - Adfoot 1.0.2+3

Reference date: 23 July 2026

This runbook is the operator checklist for publishing the already-built Android
App Bundle to Google Play. It is scoped to the current Adfoot production Android
package and should not be reused for another package name.

## Artifact

- App name: Adfoot
- Package name: `org.adfoot.app`
- Version name: `1.0.2`
- Version code: `3`
- AAB: `artifacts/android/adfoot-production-20260707T011755Z.aab`
- Size: 68,590,479 bytes
- SHA-256: `31DC47C8504F844471C777F51FDB879026C7940CE20C07F480F532F20724F224`
- Current Flutter version in `pubspec.yaml`: `1.0.2+3`
- Android config: `compileSdk = 36`, `targetSdk = 35`, `minSdk = 24`

Do not upload any older AAB from `artifacts/android/`.

Target API note:

- On 23 July 2026, `targetSdk = 35` is still aligned with the current release
  plan.
- For submissions on or after 31 August 2026, rebuild with `targetSdk = 36`
  and a higher `versionCode` before uploading.

## Local release state

Passed gates reported for this bundle:

- `release:config:validate:playstore`
- `release:android:check:playstore`
- `contract:admin-mobile:check`
- `security:secrets:check`
- `flutter analyze --no-pub`
- `flutter test test/android_release_readiness_guardrails_test.dart`

Known gap:

- Full `flutter test` had previously timed out and should be rerun when time
  allows before production rollout.

Current repository/release markers checked on 23 July 2026:

- Git tag exists: `android-playstore-1.0.2+3`
- Latest release commit observed: `e41f931 Prepare Android Play Store release build`
- Public legal URLs return HTTP 200:
  - `https://adfoot.org/legal/privacy-policy.html`
  - `https://adfoot.org/legal/account-deletion.html`
  - `https://adfoot.org/.well-known/assetlinks.json`

If this document is edited after the release tag, keep those doc-only changes
separate from the released AAB unless a new AAB is generated.

## One rule

Upload to `Internal testing` first. Do not send the first AAB directly to
production.

Recommended path:

1. Internal testing.
2. Closed testing.
3. Production access / production rollout.

If the Play developer account is a personal account created after
13 November 2023, plan for a closed test with at least 12 opted-in testers for
14 continuous days before applying for production access.

## Step 1 - Create the Play Console app

In Play Console:

1. Go to `Home > Create app`.
2. Fill:
   - App name: `Adfoot`
   - Default language: `French (France)` or the closest French locale shown by
     Play Console
   - App or game: `App`
   - Free or paid: `Free`, unless the product is ready for a paid app launch
   - Contact email: `support@adfoot.org` or the active support inbox
3. Accept the Developer Program Policies, US export laws, and Play App Signing
   declarations.
4. Create the app.

Important:

- The first uploaded artifact fixes the package name. For this release it must
  be `org.adfoot.app`.
- Do not create a separate Play Console app for `org.adfoot.app.staging` or
  `org.adfoot.app.local`.

## Step 2 - Main store listing

Path: `Grow users > Store presence > Main store listing`.

Use these draft values:

- App name: `Adfoot`
- Short description, max 80 chars:

```text
Profils, videos et mises en relation pour talents du football.
```

- Full description:

```text
Adfoot aide les talents du football, clubs, agents, recruteurs et coachs a se presenter et a entrer en relation dans un cadre structure.

Avec Adfoot, les utilisateurs peuvent creer un profil, publier ou consulter des videos, suivre des profils, echanger par messagerie, partager des contenus et acceder a des opportunites sportives.

La plateforme met l'accent sur la visibilite des profils, la verification, la securite des comptes et des parcours de contact plus clairs entre acteurs du football.
```

Category recommendation:

- App category: `Sports`
- Tags, if Play Console asks: football, sports community, recruiting,
  messaging. Use the closest available tags.

Graphics:

- App icon: 512 x 512 PNG, max 1024 KB.
  - Candidate in repo: `site_pub/web-app-manifest-512x512.png`
  - Use it only if it is the clean Adfoot icon without marketing text.
- Feature graphic: 1024 x 500 JPEG or 24-bit PNG.
  - Not currently identified as a dedicated Play asset in the repo.
  - Create/export one before production if Play requires it for this listing.
- Phone screenshots:
  - Minimum: 2.
  - Recommended: 4 portrait screenshots at 1080 x 1920 or higher.
  - Capture actual app screens, not mockups.
  - Suggested sequence: login/home, video feed, profile, messaging or
    opportunities.

Avoid in the listing:

- Claims like "best", "#1", "free for a limited time", awards, or download
  calls-to-action.
- Store copy that targets children if the Play target audience is set to
  `18 and over`.

## Step 3 - Store settings

Path: `Grow users > Store presence > Store settings`.

Recommended values:

- App category: `Sports`
- Contact email: `support@adfoot.org`
- Website: `https://adfoot.org`
- Phone: use the official business/support phone only if it is monitored.
- External marketing: leave enabled unless you do not want Google to reuse
  preview assets in promotional surfaces.

## Step 4 - App content

Path: `Policy > App content`.

Complete these sections before closed testing/production.

### Privacy policy

Use:

```text
https://adfoot.org/legal/privacy-policy.html
```

This URL was reachable with HTTP 200 on 23 July 2026.

### Data safety

Use `docs/play-console-data-safety.md` as the detailed draft.

High-level answers:

- Does the app collect or share user data? `Yes`
- Is data encrypted in transit? `Yes`
- Can users request data deletion? `Yes`
- Is user data sold? `No`
- Ads / advertising ID: `No`, unless an ads SDK is added later.

Data categories to review and declare:

- Personal info: name, email, user ID, phone number, birth date, profile fields.
- Approximate location: country, city, region when provided in profile.
- Photos and videos: profile photos, uploaded videos, thumbnails.
- Messages: in-app chat messages.
- Files and docs: uploaded CV PDFs.
- App activity: follows, likes, shares, reports, app interactions.
- App info and performance: diagnostics/client logs if collected.
- Device or other IDs: Firebase/App Check/FCM identifiers.
- Fitness info: player physical/performance profile fields if enabled or
  exposed in production.

### Account deletion

Because Adfoot supports account creation, answer that account deletion is
available.

- In-app path: `Parametres > Suppression du compte`
- Web deletion URL:

```text
https://adfoot.org/legal/account-deletion.html
```

This URL was reachable with HTTP 200 on 23 July 2026.

### App access

If reviewers cannot use the app without logging in, answer that login is
required and provide a test account in Play Console only.

Do not put credentials in git.

Recommended reviewer account profile:

- Role: `joueur` or the most complete non-admin role
- Email verified: yes
- Account blocked/disabled: no
- No 2FA, no manual admin approval, no one-time code
- Has enough sample data to open profile, feed, messaging, and settings

Draft Play Console instructions:

```text
Open Adfoot, tap Connexion, and sign in with the provided email and password.
No payment is required. The account is a reviewer test account with access to
profile, video feed, messaging, notifications, settings, and account deletion
entry point.
```

### Target audience and content

Recommended first-release stance:

- Target age: `18 and over`
- Restrict access for users Google identifies as minors if Play Console offers
  the option.

Reason: Adfoot has user-generated video, profile visibility, messaging, and
recruiting/contact workflows. If the business intentionally targets users under
18, do not use the simple first-release path. Run a separate legal/policy review
for minors, Families requirements, moderation, consent, and store listing copy.

### Content rating

Complete the IARC questionnaire honestly.

Expected answers to pay attention to:

- User-generated content: `Yes`
- In-app user interaction / messaging: `Yes`
- Sharing user-created videos/profiles: `Yes`
- Reporting/moderation tools: `Yes`, if asked
- Gambling, real-money games, sexual content, explicit violence: `No`, unless
  product behavior changes

Keep the generated rating and review whether it matches the target audience.

### Ads

Current recommendation: `No ads`.

The app manifest does not declare `com.google.android.gms.permission.AD_ID`, and
no Google Mobile Ads dependency was identified in `pubspec.yaml`. Recheck this
if any advertising or analytics SDK is added later.

### Sensitive app declarations

Expected answers for this release:

- News app: `No`
- Government app: `No`
- Financial features: `No`
- Health app: `No`
- COVID/contact tracing: `No`
- VPN: `No`

## Step 5 - First upload to Internal testing

Path: `Test and release > Testing > Internal testing`.

1. Select or create the internal test track.
2. Add trusted tester emails.
3. Create a release.
4. Upload:

```text
artifacts/android/adfoot-production-20260707T011755Z.aab
```

5. Confirm Play reads:
   - Package: `org.adfoot.app`
   - Version code: `3`
   - Version name: `1.0.2`
6. In the release notes field, use the notes below.
7. Save, review, and roll out to internal testing.
8. Copy the opt-in/test link and share it with testers.

## Step 6 - Play App Signing follow-up

After the first AAB upload and Play App Signing setup:

1. Go to `Test and release > Setup > App signing`.
2. Copy the SHA-256 certificate fingerprint for the `App signing key
   certificate`.
3. Register that fingerprint in Firebase App Check / Play Integrity for the
   production Android app if it is not already registered.
4. Update `site_pub/.well-known/assetlinks.json` with the Play app signing
   SHA-256 for `org.adfoot.app` if it differs from the current fingerprint.
5. Deploy hosting again so `https://adfoot.org/.well-known/assetlinks.json`
   serves the updated value.

The existing script for local updates is:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-assetlinks-fingerprints.ps1 -ReleaseFingerprint "<PLAY_APP_SIGNING_SHA256>"
```

Then deploy hosting/functions/rules using the release deployment process already
used by the project.

## Step 7 - Smoke tests from Play install

Install the app from the Play internal test link, not from `flutter run`.

Run on a real Android device:

- Login with a managed tester account.
- Email verification and password reset deep links.
- Profile read/edit, including profile photo.
- Video upload from gallery, processing, feed playback, and sharing.
- Notifications in foreground and background.
- Messaging/contact flow.
- Opportunity/event browsing if enabled for the test role.
- Account deletion entry point.
- App Check protected backend calls.
- App links for `https://adfoot.org/v/...` and auth action links.

If App Check fails only for Play-installed builds, check the Play app signing
SHA-256 registration in Firebase first.

## Step 8 - Closed testing

Path: `Test and release > Testing > Closed testing`.

Use closed testing after internal smoke tests are green.

If the developer account is a new personal account:

1. Create a closed testing track.
2. Add at least 12 testers by email list or Google Group.
3. Roll out the same AAB or a newer AAB with a higher versionCode.
4. Share the opt-in link.
5. Make sure testers opt in and stay opted in for 14 continuous days.
6. Ask testers to cover login, profiles, video, messaging, notifications, and
   account deletion.
7. After the 14-day requirement is met, apply for production access from the
   Play Console dashboard.

If the account is an organization account or an older personal account, closed
testing is still recommended, but production access may not require the 12
tester / 14 day gate.

## Suggested release notes

```text
Premiere version Play Store d'Adfoot.

- Connexion securisee et comptes geres.
- Profils talents, clubs, agents et coachs.
- Publication et lecture de videos.
- Messagerie et mises en relation.
- Notifications et liens de verification.
```

## Step 9 - Production

Before production:

1. Check Play pre-launch report.
2. Check Android vitals if the test has enough signal.
3. Resolve Play policy warnings.
4. Re-run the local release gates if code/config changed since the AAB:

```powershell
npm.cmd run release:config:validate:playstore
npm.cmd run release:android:check:playstore
flutter analyze --no-pub
flutter test test/android_release_readiness_guardrails_test.dart
```

5. If any code/config changes are required, increase `versionCode` above `3`,
   rebuild, and upload the new AAB instead of reusing this artifact.

For the first public release, use a normal production rollout after review.
Staged rollout is mainly useful for updates after the first production launch.

## Official references checked

- Create and set up an app:
  `https://support.google.com/googleplay/android-developer/answer/9859152`
- Internal/closed/open testing:
  `https://support.google.com/googleplay/android-developer/answer/9845334`
- New personal account testing requirements:
  `https://support.google.com/googleplay/android-developer/answer/14151465`
- Data Safety:
  `https://support.google.com/googleplay/android-developer/answer/10787469`
- Account deletion:
  `https://support.google.com/googleplay/android-developer/answer/13327111`
- Store listing preview assets:
  `https://support.google.com/googleplay/android-developer/answer/9866151`
- Target API:
  `https://developer.android.com/google/play/requirements/target-sdk`
- Play App Signing:
  `https://developer.android.com/studio/publish/app-signing`
