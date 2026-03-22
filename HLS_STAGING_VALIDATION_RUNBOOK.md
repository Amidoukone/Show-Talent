# HLS Staging Validation Runbook

Project target: staging first, then production only after staging is clean.

Goal: open `config/streaming` in a controlled sequence, validate that real devices can request and play HLS, and confirm fallback to MP4 remains healthy before starting ABR multi-renditions.

## 1) Streaming config contract

Firestore document: `config/streaming`

Fields used by the current app:

- `adaptiveEnabled`: enables adaptive source selection logic
- `rolloutPercent`: user-bucket rollout percentage for adaptive/HLS gates
- `hlsPlaybackEnabled`: product gate for HLS playback
- `preferHlsPlayback`: strategy gate that actually prefers HLS when HLS is enabled
- `useHls`: legacy mirror, kept for older clients

Important separation:

- `hlsPlaybackEnabled=true` opens the product capability
- `preferHlsPlayback=true` makes the player actively request HLS

So the rollout can be opened without immediately preferring HLS.

## 2) Presets for controlled opening

Use the repo script instead of editing Firestore manually:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --show
```

Supported presets:

- `off`
  - `adaptiveEnabled=false`
  - `rolloutPercent=0`
  - `hlsPlaybackEnabled=false`
  - `preferHlsPlayback=false`
- `contract_mp4`
  - `adaptiveEnabled=true`
  - `rolloutPercent=100`
  - `hlsPlaybackEnabled=true`
  - `preferHlsPlayback=false`
- `hls_canary`
  - `adaptiveEnabled=true`
  - `rolloutPercent=10`
  - `hlsPlaybackEnabled=true`
  - `preferHlsPlayback=true`
- `hls_full`
  - `adaptiveEnabled=true`
  - `rolloutPercent=100`
  - `hlsPlaybackEnabled=true`
  - `preferHlsPlayback=true`

Examples:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset contract_mp4 --reason "staging contract validation"
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset hls_canary --reason "staging canary"
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset off --reason "rollback"
```

Use `--dry-run` before any write if needed.

## 3) Pre-check that staging has HLS-ready assets

List recent ready videos that already contain an HLS manifest:

```bash
node .\scripts\list-ready-hls-videos.js --project-id <staging-project> --limit 10
```

Expected:

- `summary.readyWithHls > 0`
- returned videos have `playback.mode` equal to `single_rendition_hls` or `multi_rendition_hls`
- new uploads should ideally expose `playback.hls.adaptive == true` and `playback.hls.renditionCount >= 2`
- returned videos have both `mp4Url` and `hlsManifestUrl`

Do not start device validation before at least one ready HLS asset exists.

## 4) Recommended staging opening sequence

### Step A: contract and fallback only

Apply:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset contract_mp4 --reason "staging contract only"
```

Expected behavior:

- users stay on MP4
- HLS contract is present in Firestore
- no HLS request should appear in metrics

### Step B: HLS canary

Apply:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset hls_canary --reason "staging HLS canary"
```

Expected behavior:

- only rollout-bucket users prefer HLS
- HLS success and HLS fallback can now be observed in metrics

### Step C: full staging

Apply only after Step B is clean:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset hls_full --reason "staging HLS full"
```

Expected behavior:

- all staging rollout users prefer HLS
- MP4 fallback still remains available for recovery

## 5) Real-device validation flow

Use a physical device. Emulator-only validation is not enough for playback startup behavior.

### Option 1: quickest real-device validation

Use a `profile` build on the device:

```bash
flutter run --profile
```

Why:

- real hardware/player path
- success metrics stay enabled by default
- easier than release signing for a first pass

### Option 2: release-like validation

Use a release build and explicitly reopen success metrics:

```bash
flutter run --release --dart-define=VIDEO_METRICS_SUCCESS_SAMPLE_RATE=1
```

If preload metrics are needed too:

```bash
flutter run --release --dart-define=VIDEO_METRICS_SUCCESS_SAMPLE_RATE=1 --dart-define=VIDEO_METRICS_INCLUDE_PRELOAD_SUCCESS=true
```

On device:

1. sign in with the staging test account
2. open a video returned by `list-ready-hls-videos.js`
3. let the first playback start
4. swipe to the next video and back once
5. if playback stalls, wait for recovery and note whether it recovers on MP4 fallback

Record:

- device model
- OS version
- app build mode (`profile` or `release`)
- selected streaming preset
- test user UID
- tested video ID

## 6) Validate HLS metrics after device playback

Audit the last hour:

```bash
node .\scripts\check-hls-metrics.js --project-id <staging-project> --window-minutes 60 --user-id <test-user-uid>
```

Optional URL filter if the user tested a known manifest or video:

```bash
node .\scripts\check-hls-metrics.js --project-id <staging-project> --window-minutes 60 --user-id <test-user-uid> --url-contains master.m3u8
```

Expected outcomes by phase:

### `contract_mp4`

- `requestedHlsSuccess == 0`
- `actualHlsSuccess == 0`
- `mp4Success > 0`

### `hls_canary` or `hls_full`

- `requestedHlsObserved == true`
- `actualHlsObserved == true` on at least one success path
- `requestedHlsEndedAsMp4` may be non-zero, but should not dominate
- `hlsRequestedErrors` should stay low

If `requestedHlsObserved == false`:

- the user may be outside the rollout bucket
- the wrong preset may be applied
- the build may still be suppressing success metrics

If `actualHlsObserved == false` but `requestedHlsObserved == true`:

- HLS is being attempted but not completing successfully
- inspect `latestHlsErrors` and `latestRequestedHls`
- rollback to `contract_mp4` if needed

## 7) Rollback

Immediate rollback:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset off --reason "staging HLS rollback"
```

Safer rollback if you want to keep the contract live but stop preferring HLS:

```bash
node .\scripts\set-streaming-config.js --project-id <staging-project> --preset contract_mp4 --reason "stop preferring HLS"
```

## 8) Exit criteria before ABR

Do not start multi-rendition ABR until staging shows all of these:

- ready videos expose both MP4 fallback and HLS manifest
- at least one real device shows `actualHlsObserved == true`
- MP4 fallback remains healthy when HLS fails
- no blocking HLS startup regression is seen on the staging devices tested
