# MP4 Production Baseline Runbook

Project: `show-talent-5987d`

Goal: deploy the MP4-first feed baseline safely, validate that new uploads expose a multi-rendition MP4 contract, then switch production to `contract_mp4` with a clear rollback path.

Code anchors:

- mobile MP4-first source selection: `lib/utils/video_source_selector.dart`
- mobile playback session metrics: `lib/services/feed_playback_metrics_service.dart`
- backend ladder generation: `functions/src/index.ts`
- config switch script: `scripts/set-streaming-config.js`
- playback contract verification: `scripts/list-ready-playback-contracts.js`
- playback metrics audit: `scripts/check-feed-playback-metrics.js`

## 1) Preflight

Run these from repo root before any deploy:

```bash
flutter test test/feed_playback_metrics_service_test.dart test/video_model_test.dart test/video_source_selector_test.dart test/video_metrics_observer_test.dart test/video_manager_hls_policy_test.dart test/video_manager_network_profile_test.dart test/widget_test.dart
npm.cmd --prefix functions run build
```

If you want a quick contract sanity check on local scripts:

```bash
node --check .\scripts\list-ready-playback-contracts.js
node --check .\scripts\check-feed-playback-metrics.js
```

## 2) Deploy backend first

Deploy Functions before uploading new videos. This keeps the storage trigger ready to generate MP4 ladders for fresh assets.

```bash
firebase deploy --only functions
```

Notes:

- `firebase.json` already runs `lint` and `build` for `functions` during deploy.
- No backfill is required if you plan to delete the existing test videos and upload fresh ones after deploy.

## 3) Upload fresh validation videos

After Functions deploy, upload a small set of fresh videos from the mobile app or the expected upload flow.

Wait until each new document is `status == "ready"`, then verify the generated playback contract:

```bash
node .\scripts\list-ready-playback-contracts.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --limit 10 --scan 50
```

Expected contract signals:

- `playbackVersion` is `2`
- `playbackMode` is `multi_rendition_mp4` for fresh MP4-only baseline assets
- `mp4SourceCount` is typically `3`
- `mp4Heights` includes `360`, `480`, `720` when source dimensions allow it
- `fallbackPath` still points to the canonical root MP4 (`videos/<id>.mp4`)

Do not switch production config before at least one fresh ready video exposes the new contract.

## 4) Build and ship the mobile app

The mobile app now emits session-level feed metrics through `feed_playback`. Keep legacy init success metrics in their current safe posture unless you intentionally reopen them.

Recommended release build:

```bash
flutter build appbundle --release --dart-define=FEED_PLAYBACK_METRICS_SAMPLE_RATE=0.2
```

Notes:

- leaving `VIDEO_METRICS_SUCCESS_SAMPLE_RATE` unset keeps `video_manager` success logs in `errors-only`
- `FEED_PLAYBACK_METRICS_SAMPLE_RATE=0.2` gives a production sample for feed session summaries without reopening all init-success noise

Distribute the build to your validation devices first, then promote normally.

## 5) Switch production config to MP4-first

Once fresh assets are ready and the mobile build is validated, switch production streaming config:

```bash
node .\scripts\set-streaming-config.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --preset contract_mp4 --reason "mp4-first production baseline"
```

What `contract_mp4` means in this repo:

- `adaptiveEnabled=true`
- `rolloutPercent=100`
- `hlsPlaybackEnabled=true`
- `preferHlsPlayback=false`

This keeps the HLS contract field available when present, but the feed remains MP4-first in production.

## 6) Post-switch validation

### A. Contract validation

Check again after the config switch:

```bash
node .\scripts\list-ready-playback-contracts.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --limit 10 --scan 50
```

### B. Device playback validation

On at least one real Android device:

1. Open `home`
2. Scroll through several fresh videos
3. Reopen one or two videos to exercise cache hits
4. Leave and re-enter the feed once
5. Confirm no false `Video init error` regression appears

### C. Metrics validation

After enough traffic accumulates:

```bash
node .\scripts\check-feed-playback-metrics.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --window-minutes 60
```

Useful focused checks:

```bash
node .\scripts\check-feed-playback-metrics.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --window-minutes 60 --entry-context home
node .\scripts\check-feed-playback-metrics.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --window-minutes 60 --user-id <test-user-uid>
```

Key outputs to watch:

- `avgTimeToFirstFrameMs`
- `avgRebufferRate`
- `completionRate`
- `avgEstimatedBytesPlayed`
- breakdowns by `networkTier`, `finalSourceHeight`, `entryContext`

## 7) Rollback

Fast rollback if you want to keep the playback contract fields but stop using the MP4 adaptive selection path:

```bash
node .\scripts\set-streaming-config.js --project-id show-talent-5987d --credentials .\.credentials\show-talent-5987d-ops.json --preset off --reason "rollback mp4-first baseline"
```

If the issue is mobile-only and backend contracts are healthy:

- stop distribution of the new build
- keep Functions deployed
- upload no additional validation assets until the issue is understood

If the issue is backend ladder generation:

1. switch config to `off`
2. inspect fresh upload failures in Functions logs
3. delete broken validation videos
4. patch and redeploy Functions

## 8) Release note checklist

Record these exact values in the release note:

- Functions deploy timestamp
- mobile build timestamp and version code
- `FEED_PLAYBACK_METRICS_SAMPLE_RATE` value used in the build
- config switch timestamp for `contract_mp4`
- at least one sample output from `list-ready-playback-contracts.js`
- at least one sample output from `check-feed-playback-metrics.js`
