# Node 22 + firebase-functions Upgrade Checklist (Safe Migration)

Project: `show-talent-5987d`  
Codebase: `functions/`  
Date target: before Node 20 deprecation window closes (`2026-04-30` deprecation, `2026-10-30` decommission)

## 1) Target versions

- Runtime: Node.js `22`
- `firebase-functions`: `7.x` (latest stable)
- `firebase-admin`: `13.x` (latest stable)
- `typescript`: `5.x` (required by `firebase-functions` 7)
- Firebase CLI: latest `14.x` recommended

## 2) Preconditions (must pass before changing versions)

- Fix IAM deploy issue for `sendVerificationReminder` first (Cloud Run invoker policy).
- Confirm deploy principal has:
  - `roles/cloudfunctions.admin`
  - `roles/run.admin`
  - `roles/iam.serviceAccountUser`
  - `roles/cloudbuild.builds.editor`
  - `roles/artifactregistry.writer`
  - `roles/eventarc.admin`
  - `roles/pubsub.admin`
  - `roles/cloudscheduler.admin`
- Confirm no removed API usage:
  - `rg -n "functions\\.config\\(|firebase-functions/v1|runtimeConfig" functions/src -S`
  - Expected: no result.

## 3) Create migration branch + backup

```bash
git checkout -b chore/functions-node22-upgrade
git add -A
git commit -m "chore: checkpoint before Node22/functions7 migration"
```

## 4) Update runtime and dependencies

From project root:

```bash
cd functions
```

Update `functions/package.json`:

- `"engines": { "node": "22" }`
- set:
  - `"firebase-functions": "^7.0.0"`
  - `"firebase-admin": "^13.0.0"`
  - `"typescript": "^5.0.0"` (devDependency)

Install and refresh lockfile:

```bash
npm install
```

## 5) Local validation gates (hard stop if one fails)

```bash
npm run lint
npm run build
```

Optional emulator smoke test:

```bash
npm run serve
```

Verify at least these functions load and execute:

- callable: `sendUserPush`
- callable: `sendOfferFanout`
- callable: `sendEventFanout`
- scheduler: `sendVerificationReminder`
- scheduler: `cleanupUnverifiedUsers`
- storage trigger: `optimizeMp4Video`

## 6) Production deploy strategy (low risk)

Deploy in batches instead of full blast:

1. Callables first:
```bash
firebase deploy --only functions:sendUserPush,functions:sendOfferFanout,functions:sendEventFanout,functions:likeVideo,functions:reportVideo,functions:deleteVideo,functions:shareVideo,functions:logClientEvents,functions:videoActionLog
```

2. Upload/session functions:
```bash
firebase deploy --only functions:createUploadSession,functions:finalizeUpload,functions:requestThumbnailUploadUrl
```

3. Triggers/schedulers:
```bash
firebase deploy --only functions:optimizeMp4Video,functions:sendVerificationReminder,functions:cleanupUnverifiedUsers
```

4. Full reconcile:
```bash
firebase deploy --only functions
```

## 7) Post-deploy checks

- Firebase Console -> Functions: all statuses green.
- Cloud Scheduler jobs run OK:
  - `sendVerificationReminder`
  - `cleanupUnverifiedUsers`
- Cloud Logging: no startup/runtime errors on first invocation.
- Mobile smoke:
  - chat send/receive + push
  - offer creation + fanout
  - event creation + fanout

## 8) Known breakpoints to watch

- `firebase-functions` 7 removes `functions.config()`:
  - this codebase already uses `process.env.*`, so risk is low.
- TypeScript 5 requirement:
  - if ESLint plugin compatibility warns, upgrade lint stack in a separate PR.
- Scheduler IAM:
  - if deploy fails on invoker policy, fix Cloud Run IAM binding, then redeploy only failed function.

## 9) Rollback plan (fast)

If production issue appears:

1. Revert package changes (`package.json` + `package-lock.json`) to previous commit.
2. Redeploy only impacted functions first, then full functions deploy.
3. Keep rollback branch/tag:
```bash
git tag rollback-functions-node20-<date>
```

## 10) Recommended follow-up (after successful migration)

- Remove lint warning in `functions/src/upload_session.ts` (`no-explicit-any`).
- Upgrade `firebase-tools` globally in deploy environment to latest `14.x`.
- Add CI gate for functions:
  - `npm --prefix functions run lint`
  - `npm --prefix functions run build`
  - deploy dry-run in staging project.
