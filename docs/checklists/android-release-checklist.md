# Android Release Checklist

Reference date: 4 April 2026

## Preflight

- [ ] `npm.cmd run release:android:gate` passes
- [ ] `npm.cmd run backend:parity:check:production` passes — rules, indexes and
      TTL policies deployed match this checkout. Run it *before* the build:
      a build that ships against an index only present in the file does not
      error, it shows an empty screen
- [ ] if `firestore.rules` or `storage.rules` changed since the last release:
      `npm.cmd run rules:test:all` passes (real rules engine, both services;
      needs Java on PATH)
- [ ] `android/key.properties` exists on build machine
- [ ] `android/upload-keystore.jks` exists and matches `key.properties`
- [ ] `.well-known/assetlinks.json` has real SHA-256 fingerprints
- [ ] hosting legal pages are deployed

## Build

- [ ] `npm.cmd run release:android:gate:build` passes
- [ ] `.aab` exists under `artifacts/android/`
- [ ] release build uses `minifyEnabled true`
- [ ] release build uses `shrinkResources true`
- [ ] native libraries are 16 KB page-size ready (`ndkVersion` r28+ and packaging guardrail passes)

## Functional smoke tests (real device)

- [ ] `npm.cmd run video:quality:release` passes
- [ ] `npm.cmd run video:quality:release:remote` passes on target project/environment
- [ ] `npm.cmd run offer:quality:release` passes
- [ ] `npm.cmd run event:quality:release` passes
- [ ] onboarding/signup/email verification
- [ ] login/reset password/deep links
- [ ] profile read/edit
- [ ] video upload/finalize/feed playback
- [ ] notifications (foreground/background)
- [ ] account deletion flow

## Store package

- [ ] Data safety form completed (`docs/play-console-data-safety.md`)
- [ ] privacy policy URL set
- [ ] account deletion URL set
- [ ] app name/icon/version checked in release artifact
- [ ] release notes prepared

## Final GO

- [ ] no blocker open on critical user flows
- [ ] release owner and reviewer approved the bundle
