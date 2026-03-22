# Video Metrics Logging Runbook

Project: `show-talent-5987d`

Goal: keep `video_manager` errors visible while reducing success-log noise in release and protecting Firestore from older clients.

Code anchors:

- mobile policy: `lib/services/video_metrics_observer.dart`
- backend guardrail: `functions/src/actions.ts`

## 1) Effective defaults

### Mobile observer

`VideoMetricsPolicy.forCurrentBuild()` applies these defaults:

| Build mode | `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` unset | Effective success behavior | `VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS` default |
| --- | --- | --- | --- |
| debug/profile | `1.0` | all successes emitted | `true` |
| release | `0.0` | no success emitted (`errors-only`) | `false` |

Rules:

- errors are always emitted
- success sample rate is clamped to `[0, 1]`
- invalid sample-rate values fall back to the build default
- preload successes stay filtered in release unless `VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS=true`

### Backend callable

`logClientEvents` applies these defaults for persisted `client_logs`:

| Variable | Unset/invalid default | Effective behavior |
| --- | --- | --- |
| `VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE` | `0` | `video_manager` `info` logs are dropped |

Rules:

- `video_manager` errors are always persisted
- backend sample rate is clamped to `[0, 1]`
- non-`video_manager` sources keep the existing persistence behavior

## 2) Release operations note

Treat release as `errors-only` unless you explicitly opt back into success sampling.

Recommended release posture:

- keep `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` unset for normal production rollout
- set `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` only for a temporary diagnostic window
- keep `VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS` unset unless preload behavior is the specific issue under investigation
- keep `VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE=0` unless backend-side sampling is intentionally reopened

Example mobile commands:

```bash
flutter build appbundle --release
flutter build appbundle --release --dart-define=VIDEO_METRICS_SUCCESS_SAMPLE_RATE=0.05
flutter build appbundle --release --dart-define=VIDEO_METRICS_SUCCESS_SAMPLE_RATE=0.05 --dart-define=VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS=true
```

When release sampling is reopened, note the exact value and the deployment timestamp in the release ticket.

## 3) Staging and production verification

Use the same comparison flow in staging first, then in production.

Preconditions:

- the build/deploy timestamp is known precisely
- Application Default Credentials or a service-account JSON is available for Firestore access
- the backend deployment environment already contains the intended `VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE`

Run the audit script from repo root:

```bash
node .\scripts\check-video-manager-log-sampling.js --project-id show-talent-5987d --cutoff 2026-03-14T12:00:00Z --window-minutes 60
```

What the script checks:

- compares one window before and one window after the release cutoff
- scans `client_logs` by `receivedAt`
- counts only entries where `source == "video_manager"`
- reports separate `info` and `error` totals for each window
- computes the `info` drop ratio after the rollout

Interpretation:

- `after.info` should drop sharply versus `before.info` when release stays `errors-only`
- `after.error` must still be non-zero if the application continues to generate video-manager failures in that window
- if both windows show `0` errors, the script cannot prove error retention; extend the observation window or reproduce a controlled failure in staging

Suggested staging validation:

1. Deploy the build and functions config with the intended default sample rates.
2. Exercise normal playback and at least one controlled video init failure.
3. Run the script with a 30 to 60 minute window around the deployment timestamp.
4. Confirm `info` volume drops and the forced failure is still visible as `error`.

Suggested production validation:

1. Record the exact deployment time.
2. Run the script after enough live traffic has accumulated.
3. Compare counts with the pre-release window.
4. Keep the release note with:
   - mobile sample rate used
   - backend sample rate used
   - before/after `info` counts
   - before/after `error` counts

## 4) Credentials note

The audit script uses `firebase-admin` and relies on Google credentials already available on the machine.

Examples:

- Cloud Shell with the correct project selected
- local shell with `GOOGLE_APPLICATION_CREDENTIALS` pointing to a service-account JSON

If credentials are missing, the script exits before querying Firestore.
