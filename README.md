# adfoot

Flutter mobile app and Firebase backend for Show-Talent.

## Operational runbooks

- [Mobile App Check Validation Runbook](./MOBILE_APPCHECK_VALIDATION_RUNBOOK.md)
- [IAM Safe Configuration Runbook](./IAM_SAFE_CONFIGURATION_RUNBOOK.md)
- [Video Metrics Logging Runbook](./VIDEO_METRICS_LOGGING_RUNBOOK.md)
- [MP4 Production Baseline Runbook](./MP4_PRODUCTION_BASELINE_RUNBOOK.md)
- [HLS Staging Validation Runbook](./HLS_STAGING_VALIDATION_RUNBOOK.md)

## Video metrics logging

Video initialization metrics now use a defensive two-stage policy:

- mobile release builds are `errors-only` by default
- mobile success logs resume only when `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` is set explicitly
- backend `logClientEvents` still persists `video_manager` errors, but samples `info` logs with `VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE`

See [VIDEO_METRICS_LOGGING_RUNBOOK.md](./VIDEO_METRICS_LOGGING_RUNBOOK.md) for the effective defaults, release behavior, and staging/production verification flow.
