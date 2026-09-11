# iOS Build via Codemagic — Setup Runbook

Goal: build, sign and ship the iOS app to TestFlight without owning a Mac.
`codemagic.yaml` at the repo root defines two workflows (`ios-staging`,
`ios-production`) mirroring the existing Android flavor split
(`android/app/build.gradle`) and the iOS schemes already in the project
(`ios/Runner.xcodeproj/xcshareddata/xcschemes/{staging,production}.xcscheme`).

Nothing in this file runs automatically yet — both workflows have no
`triggering:` block, so a build only starts when you click "Start new build"
in the Codemagic dashboard. Add automatic triggering later, once a build has
actually succeeded once.

**STATUS (2026-09-11): DONE — first `ios-staging` build succeeded and was
accepted by App Store Connect (build 36, "Although delivery was successful"
email, only a non-blocking advisory left).** Everything below this line is
now historical/reference material for the next person (or session) touching
this pipeline — the setup is complete and working. Four real, distinct bugs
were hit and fixed in this exact order on the way to a green build, none of
them hypothetical/guessed — each was diagnosed from an actual Codemagic or
Apple error message:

1. **`keychain add-certificates` before `fetch-signing-files`** — the
   original script order tried to add certificates to the keychain before
   `app-store-connect fetch-signing-files --create` had downloaded/created
   any `.p12` to add, failing with "Did not find any certificates from
   specified locations." Fixed by splitting `keychain_setup` into
   `keychain_initialize` (runs first) and `keychain_add_certificates` (runs
   after `fetch_signing_files`) in `codemagic.yaml`.
2. **Missing `CERTIFICATE_PRIVATE_KEY`** — `fetch-signing-files --create`
   cannot generate a brand-new distribution certificate without a private
   key handed to it explicitly (env var or `--certificate-key`); failed with
   "Cannot save Signing Certificates without certificate private key" even
   with zero existing certificates on the Apple account. Fixed by generating
   a 2048-bit RSA key (`openssl genrsa` + `openssl rsa -traditional` for the
   classic `RSA PRIVATE KEY` PEM header) and adding it as `CERTIFICATE_PRIVATE_KEY`
   in Codemagic's `appstore_credentials` environment variable group (already
   referenced by both workflows' `groups:`).
3. **iOS deployment target too low for Firebase's Swift Package Manager
   dependencies** — Xcode archiving failed with "Target Integrity: the
   package product 'cloud-firestore' (and 6 other Firebase products)
   requires minimum platform version 15.0 ... but this target supports
   13.0." Fixed by raising `IPHONEOS_DEPLOYMENT_TARGET` (12 configs in
   `ios/Runner.xcodeproj/project.pbxproj`), `platform :ios` in `ios/Podfile`,
   and `MinimumOSVersion` in `ios/Flutter/AppFrameworkInfo.plist` all to
   `15.0`. Real consequence, not just config: the app no longer installs on
   iOS 12/13/14 — unavoidable given the currently pinned Firebase plugin
   versions.
4. **App icon PNGs misplaced one directory level too deep** —
   `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` referenced
   e.g. `152.png` (relative to the appiconset folder itself, as Xcode
   expects), but the actual files were committed one level down, in an
   `AppIcon.appiconset/_/` subfolder — invisible to `actool` since it never
   surfaced until this, the very first real iOS build ever attempted on this
   project. App Store Connect rejected the upload with "Missing required
   icon file ... 167x167 / 152x152 ... for iPad." Fixed with `git mv` of all
   34 PNGs up one level, no content changes.
5. **Missing Info.plist purpose strings (`ITMS-90683`)** — the app's own
   `lib/` code never calls the camera or location APIs directly (all
   `image_picker` calls use `ImageSource.gallery`), but a dependency
   references those APIs at the native level regardless, and Apple statically
   scans the linked binary rather than actual call sites. Two rounds of this,
   one key at a time as each successive upload surfaced the next missing key
   Apple's scanner happened to report: `NSCameraUsageDescription` (blocking,
   build 35 was rejected outright), then `NSLocationWhenInUseUsageDescription`
   and `NSLocationAlwaysAndWhenInUseUsageDescription` (both advisory only,
   build 36 was still accepted). All three added to `ios/Runner/Info.plist`
   with honest, generic French copy matching the existing entries' style. If
   a *third* variant (e.g. background location) gets flagged on a future
   upload, same pattern: add the key, no need to treat it as a regression.

Two housekeeping items that came along for the ride, not bugs but required
by this project's own guardrail tests once the build number moved:
`pubspec.yaml` bumped `1.0.7+35` → `1.0.7+36` (Apple had already "consumed"
35 with the rejected upload, so the retry needed a new number), and
`scripts/aab-content-expectations.json`'s `forVersionCode` updated to match
(same witnesses kept — `lib/` had not changed since 35, only `ios/` and
`pubspec.yaml`, so nothing needed re-verifying against the Android bundle
content).

## What you need to do yourself (no Mac required — all of this is browser-based)

### 1. Apple Developer Program

Non-negotiable, independent of Codemagic: https://developer.apple.com/programs/
— $99/year. Required to get an App Store Connect account, a Team ID, and to
create App Store Connect API keys.

**Decision (2026-09-10): enroll as an Individual, not an Organization.**
Organization enrollment requires a D-U-N-S number (a registered legal entity
lookup, free but can take 1-3 weeks to issue/verify) and shows "Adfoot" as
the seller name. Individual enrollment verifies against a personal Apple ID
+ government ID and is typically approved same-day to 48h, but shows the
enrolled person's legal name as the App Store "seller" (e.g. "Amidou Koné"),
not "Adfoot" — acceptable tradeoff to unblock the release now. The account
can be converted to an Organization later without losing the app or its
TestFlight/App Store history, once a D-U-N-S number is available. To enroll:

1. Use (or create) an Apple ID with the exact legal name/address that
   matches a government-issued ID — mismatches are the #1 cause of
   enrollment delay/rejection.
2. Go to https://developer.apple.com/programs/enroll/, sign in, choose
   "Individual", pay the $99 with a card that bills to the same name/address.
3. Apple may ask for an ID photo/verification call for individual
   enrollment in some countries — expect this, it's normal.
4. Wait for the confirmation email before moving to step 2 below —
   App Store Connect access unlocks only after enrollment is approved.

**Status (2026-09-11): APPROVED — activation email received.**
Apple ID `amidoudev@gmail.com` (Amidou Kone), account region corrected from
a default "United States" to **Mali** via account.apple.com > Personal
Information > Country/Region *before* enrolling — the enrollment form
inherits the Apple ID's region, so this had to be fixed first (it was
showing US-only address fields like "State"). Enrollment order confirmed:
**Enrollment ID `HB8Y6QXX28`**, $99 charged. Apple's activation email
arrived on 2026-09-11 — the Individual Apple Developer Program membership is
now active, App Store Connect access is unlocked. Next actionable steps are
2-4 below (App Store Connect app records, API key, Codemagic integration).

Codemagic account creation + GitHub repo connection (step 5 below) is
**already done** in parallel: Individual plan, repo connected in YAML mode,
`codemagic.yaml` auto-detected with both `ios-staging`/`ios-production`
workflows visible.

### 2. Create the two app records in App Store Connect

App Store Connect > Apps > + > New App, once for each bundle ID already fixed
in the Xcode project (`ios/Runner.xcodeproj/project.pbxproj`):

- `org.adfoot.app` — production
- `org.adfoot.app.staging` — staging

(`org.adfoot.app.local` has no App Store Connect record — it is a local/debug
flavor, never distributed.)

You will need, per app: name, primary language, SKU (any unique string, e.g.
`adfoot-production`), and eventually the App Privacy questionnaire, screenshots
and description before any TestFlight external testing or App Store
submission — Codemagic cannot fill these in for you.

### 3. Create an App Store Connect API key

App Store Connect > Users and Access > Integrations > App Store Connect API >
Generate API Key. Role: **App Manager** is enough for build upload; avoid
Admin unless you need it elsewhere. Download the `.p8` file **once** — Apple
does not let you download it again — and note the Issuer ID and Key ID shown
next to it.

### 4. Connect that key to Codemagic

Codemagic > Team settings > Integrations > Apple Developer Portal > add the
Issuer ID, Key ID and the `.p8` file. Name the integration
`adfoot_app_store_connect` — `codemagic.yaml` references that exact name
under `integrations: app_store_connect:` in both workflows. If you name it
differently, update the file to match.

This one integration is what lets `app-store-connect fetch-signing-files` and
`keychain add-certificates` in the pipeline create/fetch the distribution
certificate and provisioning profile automatically — you never manually
handle a `.p12` or `.mobileprovision` file.

### 5. Connect the repository to Codemagic

Codemagic > Add application > select this GitHub repo. Codemagic auto-detects
`codemagic.yaml` and exposes the two workflows.

### 6. First build

From the Codemagic dashboard, pick `ios-staging`, click "Start new build."
Watch the log. Expected failure modes on a first attempt, and what they mean:

- **`Set up keychain and certificates for code signing` fails with "Did not
  find any certificates from specified locations" (hit on the actual first
  build, 2026-09-11)** → the original `codemagic.yaml` ran `keychain
  add-certificates` *before* `app-store-connect fetch-signing-files`, but
  `add-certificates` only picks up `.p12` files that `fetch-signing-files
  --create` itself downloads/creates on disk — so with the steps in that
  order, nothing exists yet to add. Fixed by splitting the old combined
  `keychain_setup` anchor into `keychain_initialize` (runs first) and
  `keychain_add_certificates` (runs *after* `fetch_signing_files`) in both
  workflows. If you ever reorder these scripts again, the correct sequence
  is: `keychain initialize` → `app-store-connect fetch-signing-files` →
  `keychain add-certificates` → `xcode-project use-profiles`.
- `fetch-signing-files` fails / no signing files found → the App Store
  Connect API key's role is too low, or the app record for that bundle ID
  (step 2) does not exist yet.
- Provisioning profile / entitlements mismatch mentioning
  `com.apple.developer.associated-domains` → `ios/Runner/Runner.entitlements`
  declares `applinks:adfoot.org`, but `fetch-signing-files ... --create`
  only auto-creates a *basic* App ID with no capabilities. Fix: Apple
  Developer > Certificates, Identifiers & Profiles > Identifiers > pick
  `org.adfoot.app` (and `org.adfoot.app.staging`) > enable the **Associated
  Domains** capability > Save, then re-run the build so a fresh profile
  picks it up. (Push Notifications capability is not yet declared in the
  entitlements file, so it does not block this build — only relevant if/when
  APNs is wired up for chat push notifications.)
- CocoaPods install fails → almost always a Flutter/CocoaPods version
  mismatch; check the Codemagic build log for the actual pod error before
  changing `codemagic.yaml`'s pinned `flutter:`/`cocoapods:` versions.

## What does *not* need attention right now

`ios/Firebase/{local,staging,production}/GoogleService-Info.plist` exist
locally (gitignored, mirroring how `android/app/src/production/google-services.json`
is handled) but — verified against `ios/Runner/AppDelegate.swift` and
`ios/Runner.xcodeproj/project.pbxproj` — nothing in the iOS build actually
reads them: there is no `FirebaseApp.configure()` call and no build-phase
script copying a flavor's plist into the bundle. iOS Firebase initialization
goes entirely through `lib/firebase_options.dart` (FlutterFire-CLI generated,
already committed, already correct per flavor), the same as it does today
without ever having shipped an iOS build.

Those plist folders are scaffolding for a *future* need — most likely
Crashlytics' native dSYM-upload script, which does want a real
`GoogleService-Info.plist` on disk, or Google Sign-In's URL scheme, if either
gets added later. When that day comes, add a Codemagic step that materializes
the right flavor's plist from an encrypted file variable before the build,
the same way `android/key.properties` and `google-services.json` are kept
local-only today — do not commit the real plist contents to get there.

## Ongoing cost

- Apple Developer Program: $99/year, regardless of CI choice.
- Codemagic: free tier is 500 build minutes/month, generally enough for
  occasional TestFlight builds. Paid tiers exist if that stops being true.

## Testing without owning an iPhone

Codemagic itself needs no Apple hardware (it builds on Mac cloud runners),
but *installing and using* a TestFlight build normally happens on a real
iOS device or the Simulator. Options, cheapest/fastest first:

1. **Borrow a device** for the critical-path smoke test before each public
   release (signup, camera/video upload, push notification receipt, deep
   links) — these are the areas most likely to behave differently from
   Android; most other UI/logic bugs will already show up on Android since
   it's the same Flutter codebase. A single borrowed session before a
   public (not staging) release is enough; it does not need to be your own
   device.
2. **Ask a friend/beta tester to join TestFlight** — invite by email from
   App Store Connect once a build is up; they test on their own device and
   report back. This is the normal way small teams do iOS QA without every
   developer owning a device.
3. **Cloud real-device farms** (BrowserStack App Live, AWS Device Farm,
   Sauce Labs) — install the `.ipa` Codemagic produces on a real iOS device
   rented by the minute, remotely, from a browser. Paid, but no purchase
   commitment; useful for a one-off pre-submission check.
4. **Xcode Simulator** — Codemagic's Mac runner has it, but you can't drive
   it remotely through the CI log; it's mainly useful for *screenshots* (see
   below), not interactive testing, since you have no way to click into it
   from Windows.

**None of this blocks shipping.** TestFlight review and App Store review
both happen without you needing a device — Apple's automated + human review
runs the build itself. A device only matters for *your own* QA confidence.

## App Store screenshots without a device

App Store Connect requires screenshots per size class (6.9" and 6.5" iPhone
at minimum, iPad if the app supports it — check "supports iPad" in Xcode
project settings). None of these require a physical device:

- Simplest: add a `screenshot` step to the `ios-staging` workflow that runs
  the app in the Mac runner's iOS Simulator and captures screenshots via
  `flutter drive` + `flutter_driver` or Fastlane `snapshot` — fully
  automatable in CI, zero device needed. Not wired up yet in
  `codemagic.yaml`; add this once the first signed build succeeds, so it
  can be debugged against a known-working pipeline.
- Manual fallback: run the app in Android Studio's iOS Simulator support or
  any Mac you have brief access to (a friend's, a library, a cloud Mac
  rental) just long enough to screenshot each required size.

## Promoting a build past TestFlight

Both workflows are deliberately `submit_to_app_store: false`. Moving a
TestFlight build to the public App Store listing is a distinct, manual
decision made in App Store Connect once you're ready — this pipeline will
never do that on its own.
