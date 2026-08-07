# Adfoot Go-Live Plan (3 Sprints)

## Sprint 1 - Security and Release Hardening (done in this iteration)
- Remove private service account key from mobile code.
- Rotate/revoke compromised service-account credentials in Google Cloud IAM.
- Move push dispatch to a secured backend callable (`sendUserPush`).
- Add authorization checks for push contexts (`message`, `offre`, `event`).
- Require authentication for client logging callables.
- Remove insecure Android flags (`usesCleartextTraffic`, `requestLegacyExternalStorage`).
- Add production-ready Android release setup:
  - release keystore support (`android/key.properties` pattern)
  - resource shrinking + minification
  - `proguard-rules.pro`
- Version Firebase rules in repo:
  - `firestore.rules`
  - `storage.rules`
  - `firebase.json` wired to both.

Deliverables:
- No private key in Flutter source.
- Push notifications sent only through backend.
- Security rules tracked in git and deployable.
- Android release build configured for production.

## Sprint 2 - Scalability and Cost Control
- Replace chat unread N+1 reads by aggregated counters per conversation.
- Add deterministic conversation ID to avoid duplicate conversation creation.
- Remove global `users` stream and replace with paginated, targeted queries.
- Move mass-notification loops (offres/events) to backend jobs/callables.
- Add write-safe transactions for participants/candidates updates.

Deliverables:
- Lower Firestore reads per active user.
- Stable chat performance with large conversation counts.
- Server-side fanout for notifications.
- Reduced race-condition risk on offers/events.

## Sprint 3 - Maintainability and Release Governance
- Fix failing widget test and keep test suite green.
- Resolve high-priority analyzer issues and enforce lint gates.
- Add CI pipeline: lint + test + build + dependency/security checks.
- Upgrade vulnerable/outdated backend dependencies in `functions`.
- Add release checklist (versioning, signing, Play Console pre-launch report, rollback runbook).

Deliverables:
- Green CI required before merge/deploy.
- Reproducible release process.
- Reduced operational risk for first public launch.
