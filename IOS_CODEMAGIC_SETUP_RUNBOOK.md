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

## What you need to do yourself (no Mac required — all of this is browser-based)

### 1. Apple Developer Program

Non-negotiable, independent of Codemagic: https://developer.apple.com/programs/
— $99/year. Required to get an App Store Connect account, a Team ID, and to
create App Store Connect API keys.

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

- `fetch-signing-files` fails / no signing files found → the App Store
  Connect API key's role is too low, or the app record for that bundle ID
  (step 2) does not exist yet.
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

## Promoting a build past TestFlight

Both workflows are deliberately `submit_to_app_store: false`. Moving a
TestFlight build to the public App Store listing is a distinct, manual
decision made in App Store Connect once you're ready — this pipeline will
never do that on its own.
