# Adfoot

Flutter mobile app and Firebase backend for Adfoot.

Product branding is `Adfoot`.

Historical infrastructure identifiers such as `show-talent-5987d` may still
appear in technical configuration and legacy runbooks until the backend
migration is completed.

## Operational runbooks

- [Mobile App Check Validation Runbook](./MOBILE_APPCHECK_VALIDATION_RUNBOOK.md)
- [IAM Safe Configuration Runbook](./IAM_SAFE_CONFIGURATION_RUNBOOK.md)
- [Video Metrics Logging Runbook](./VIDEO_METRICS_LOGGING_RUNBOOK.md)
- [MP4 Production Baseline Runbook](./MP4_PRODUCTION_BASELINE_RUNBOOK.md)
- [HLS Staging Validation Runbook](./HLS_STAGING_VALIDATION_RUNBOOK.md)
- [Firebase Environments Runbook](./docs/firebase-environments-runbook.md)
- [Mobile Firebase Config Runbook](./docs/mobile-firebase-config-runbook.md)
- [Mobile Firebase Project Bootstrap Runbook](./docs/mobile-firebase-project-bootstrap-runbook.md)
- [Cloud Cost Control Plan](./docs/cloud-cost-control-plan.md)
- [Admin Bootstrap Runbook](./docs/admin-bootstrap-runbook.md)
- [Shared Backend Contract](./docs/shared-backend-contract.md)
- [Inter-Repo Admin / Mobile Runbook](./docs/inter-repo-admin-mobile-runbook.md)
- [Admin / Mobile Production Runbook](./docs/admin-mobile-production-runbook.md)
- [Sprint 6 Android Store Ready](./docs/sprints/sprint-6-android-store-ready.md)
- [Sprint 6 Development Coherence](./docs/sprints/sprint-6-development-coherence.md)
- [Sprint 7 iOS Readiness](./docs/sprints/sprint-7-ios-readiness.md)
- [Store Compliance](./docs/store-compliance.md)
- [Android Release Checklist](./docs/checklists/android-release-checklist.md)
- [Play Console Data Safety Draft](./docs/play-console-data-safety.md)

## Development coherence gate

Default gate (pre-store):

```powershell
npm.cmd run quality:coherence:check
```

Full gate including backend scheduler signal:

```powershell
npm.cmd run quality:coherence:check:full
```

Cross-repo gate including external admin repository checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-product-coherence-gate.ps1 `
  -IncludeBackendGate `
  -AdminRepoPath "C:\Users\Ing.Amidou.KONE\Desktop\MyApp\show_talent - web"
```

## Sprint 6 command set

Backend + Android gate:

```powershell
npm.cmd run release:android:gate
```

Android signed bundle build (after signing and assetlinks setup):

```powershell
npm.cmd run release:android:gate:build
```

Android signing setup (local machine):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-android-signing.ps1 `
  -StorePassword "<STORE_PASSWORD>" `
  -KeyPassword "<KEY_PASSWORD>" `
  -GenerateKeystore
```

Asset Links SHA update:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-assetlinks-fingerprints.ps1 `
  -StagingFingerprint "<STAGING_SHA256_IF_AVAILABLE>"
```

## Video metrics logging

Video initialization metrics now use a defensive two-stage policy:

- mobile release builds are `errors-only` by default
- mobile success logs resume only when `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` is set explicitly
- backend `logClientEvents` still persists `video_manager` errors, but samples `info` logs with `VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE`

See [VIDEO_METRICS_LOGGING_RUNBOOK.md](./VIDEO_METRICS_LOGGING_RUNBOOK.md) for the effective defaults, release behavior, and staging/production verification flow.
