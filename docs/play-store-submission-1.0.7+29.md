# Play Store Submission — Adfoot 1.0.7+29

Reference date: 30 August 2026, re-verified 31 August 2026

This is the operator runbook for the build that is intended to become the
**first Production release** of `org.adfoot.app`. Play production access was
granted by Google before `1.0.7+9`; every release since has stayed on Internal
testing on purpose. It supersedes `docs/play-store-submission-1.0.7+9.md`.

Nothing here replaces the generic list in
`docs/checklists/android-release-checklist.md` — this doc records what was
actually verified for *this* build, on which date, and by which command.

## What this build contains that `28` does not

`versionCode 28` was built on **2026-08-29 00:41**
(`artifacts/android/adfoot-production-20260829T004239Z.aab`, verified from the
bundle's own manifest: `versionCode 28`, `versionName 1.0.7`, `targetSdk 36`,
`minSdk 24`). Everything up to `97c8c74` is in it.

Eight commits landed after it, on 2026-08-30 and 2026-08-31:

| Commit | What changes for a user |
| --- | --- |
| `3a6e8b8` | An upload's fate is decided once, where it stops. Finalisation no longer leaves a session stranded between "uploaded" and "ready". |
| `fa40ff7` | Firestore and Storage rules now enforce server-side what the client already did. Profile photos gain a size and content-type ceiling; the Storage admin check no longer accepts the Firestore `role` field. |
| `552f899` | Conversations, messages and the inbox are bounded queries instead of unbounded live listeners; upload-cleanup, session-persistence and resume-probe failures are reported instead of swallowed; a release build without `key.properties` now fails at configuration instead of producing a debug-signed AAB. |
| `2fd5d9d` | A terms-acceptance gate (**dormant** — see below) and a membership record that no client can write. No pricing, no payment surface anywhere in the app. |
| `6f5277f` | Documentation and cost modelling only. No app code. |
| `98fd498` | A "Joueur agence" badge on the profile, the video search results and the contact directory — shown only while an `adfoot` record is live, never for a paying `external` one, and never with the term or the internal reference. **Invisible in production today**: no account carries a record. |
| `3723c38` | Guardrail only. `setManagedAccountMembership` joins the 17 automatically-checked callables now that the admin portal actually calls it. No app code. |
| `4ec743f` | Tooling and tests only. A backend parity gate (rules, indexes, TTL) wired into the coherence gate, and the first behavioural coverage of `storage.rules` against the real engine. No app code. |

Two of these change **backend behaviour that was already deployed on
2026-08-29, before the commits existed** (rules at 16:50 and 18:35 UTC). That
ordering is why the parity check below matters more than usual for this build.

## Deliberately dormant in this build

These are switched off by data, not by code, and are expected to stay off
until the legal work outside the repo is finished. Do not "fix" them:

- **Terms acceptance gate.** `TermsConfig.bundledVersion` is empty and
  `config/legal` does not exist in `adfoot-production` (verified 2026-08-30).
  The gate therefore never shows. It is armed for the whole fleet — with no
  new build — by writing `config/legal.requiredVersion` the day
  `https://adfoot.org/legal/terms.html` is published. That URL returns **404
  today, on purpose**: shipping the gate active would send every user to
  accept a text they cannot read. See `docs/legal-drafts/README.md`.
- **Membership.** All 17 production accounts carry no membership record, and
  `none` is the absence of a file, not a third population. No restriction is
  attached to any value: the single thing a record now changes is a
  "Joueur agence" badge on a player's profile, shown only while an `adfoot`
  record is live. With no record anywhere in production, this release still
  changes no behaviour for anyone; the badge appears the day the
  administration records a file, with no new build.
- **No monetisation surface.** No price, no pay button, no billing SDK. The
  Play Console declaration "contains in-app purchases: no" stays true, and a
  test fails the suite if `amount`/`price`/`currency`/`montant` appears in the
  membership callable.

## Verified locally on 30 August 2026

All at commit `4ec743f` plus the version bump to `1.0.7+29`:

| Check | Command | Result |
| --- | --- | --- |
| Static analysis | `flutter analyze` | No issues found (615 s) |
| Test suite | `flutter test` | **724 tests, all passed** (711 at `6f5277f`; the badge adds 13) |
| Firestore rules, real engine | `npm run rules:test` | 31/31 conformes |
| Storage rules, real engine | `npm run rules:test:storage` | 25/25 conformes (new — this file had no behavioural coverage before) |
| Functions lint | `npm --prefix functions run lint` | exit 0 |
| Functions build | `npm --prefix functions run build` (tsc) | exit 0 |
| Android readiness | `check-android-release-readiness.ps1 -Environment production -ReleaseGate` | no errors, no warnings, at `+29` |
| Backend parity | `npm run backend:parity:check:production` | rules, 15/15 indexes READY, both TTL policies ACTIVE |
| Scheduler | `check-production-backend-gate.ps1` | `cleanupUnverifiedUsers` last success 2026-08-29T14:26:07Z |

Backend parity, in detail — this is the check that did not exist for earlier
releases:

- `cloud.firestore` ruleset deployed 2026-08-29T18:35:32Z — SHA-256 identical
  to `firestore.rules` in this checkout.
- `firebase.storage` ruleset deployed 2026-08-29T16:50:12Z — SHA-256 identical
  to `storage.rules` in this checkout.
- 15 declared indexes, 15 deployed, all `READY`, no undeclared extras.
- `client_logs/expireAt` and `video_action_logs/expireAt` TTL policies both
  `ACTIVE`.
- Callables reachable in `europe-west1`, including the newest
  (`setManagedAccountMembership`, `notifyContactIntakeCreated`), so the
  deployed Functions include the 2026-08-30 code.
- Hosting serves the current `site_pub/` (`/robots.txt`, `/sitemap.xml`,
  `/legal/privacy-policy.html`, `/.well-known/assetlinks.json` all HTTP 200).

Production data at the moment of this build: 17 users, 4 videos (all
`status: ready`, `moderationStatus: approved`, public), 3 `contact_intakes`
still `status: new`, 0 conversations, 1 offer, 1 event.

## Not verified — and the reason this build must not be promoted blind

**No build since `1.0.7+27` has been run on a physical device.** The suite is
a source-level guardrail suite for most of these changes; four of them are the
kind it structurally cannot judge. Install `29` from the Internal testing link
and check exactly this list, then record what was *seen*, not what should
happen:

Carried over, still unverified since build 28:

- [ ] **Navigation bar** — the tab reads `Carrière`. No label clipped, the `+`
      Publier pill sits on the same line as its neighbours. Then set the system
      font size to maximum and look again (the bar clamps its own text scale to
      0.85–1.15 while the rest of the app honours up to 1.6).
- [ ] **Background playback** — start a video, press Home. The sound must stop.
- [ ] **Scroll away from a loading video** — swipe past a video that is still
      buffering; it must not start playing once it finishes.
- [ ] **Feed position** — scroll a few videos down, switch tab, come back. The
      feed reopens on the same video and restarts it from its beginning (the
      player was disposed to give the decoder back — that is expected).

New in build 29:

- [ ] **Terms gate stays invisible.** Cold start, tapped notification, shared
      video link: no consent screen anywhere. If one appears, `config/legal`
      was written by mistake — delete it and the fleet recovers with no build.
- [ ] **Profile photo change still works.** The Storage rule now requires a
      content type matching `image/*` and a size ≤ 8 MB. The client sends
      `image/jpeg` explicitly, and `npm run rules:test:storage` proves the
      owner's write is allowed against the real engine — but no real device
      has exercised it against the deployed ruleset.
- [ ] **Video upload end to end**, on a real connection: pick, upload,
      processing, appears in the feed and plays. The finalisation change
      (`3a6e8b8`) and the deployed rules have never met a real upload — the
      four videos in production all predate the 2026-08-29 rules deploy.
- [ ] **Kill the app mid-upload and reopen it.** The resume path now logs when
      it cannot resume; confirm the upload either resumes or restarts cleanly
      rather than hanging.
- [ ] **Messaging.** Open a conversation, send a message, scroll back through
      history. Messages now load 50 at a time and widen by 50 on scroll-back;
      production has 0 conversations, so this code has never run against real
      data.
- [ ] **A contact request produces an e-mail.** Filing one from the app should
      reach the operations mailbox via `notifyContactIntakeCreated`. No
      `OPS_NOTIFICATION_EMAIL` is set, so the recipient falls back to
      `MAIL_REPLY_TO` — **support@adfoot.org**. Confirm that address is
      actually read before relying on it. The three existing requests
      (2026-06-02, 2026-07-24, 2026-07-26, all still `status: new`) predate
      the trigger and will never generate mail: answer them from the admin
      portal.

## Build

```powershell
npm.cmd run release:android:bundle:playstore
```

If it fails with a file-lock error under `build\`, run `gradlew --stop` from
`android\` and rebuild. After the build, record here: AAB path, byte size,
SHA-256, and confirm from the bundle manifest that `versionCode` is `29`.

- AAB: _fill after build_
- Size: _fill after build_
- SHA-256: _fill after build_
- 16 KB alignment: `powershell -File .\scripts\check-aab-native-alignment.ps1`
  — _fill after build_

## Upload to Internal testing

Path: `Test and release > Testing > Internal testing`.

1. Create a new release on the existing Internal testing track.
2. Upload the `29` AAB. Confirm Play reads back package `org.adfoot.app`,
   version code `29`, version name `1.0.7`.
3. Paste the release notes below.
4. Roll out to Internal testing and install from the opt-in link — **not**
   from `flutter run`. The device checklist above is only meaningful on the
   Play-installed build (App Check and Play App Signing differ otherwise).

## Release notes (Internal testing / Production "What's new")

```text
Version 1.0.7 - stabilite, securite et performances.

- Envoi de video plus fiable : reprise apres coupure et fin de traitement plus sure.
- Messagerie plus rapide a l'ouverture, avec chargement progressif de l'historique.
- Renforcement de la securite des photos de profil et des acces aux donnees.
- Diagnostics ameliores : les echecs silencieux sont desormais remontes.
- Corrections d'affichage et de navigation.
```

## Before promoting to Production

Do not promote on a green test suite alone. All of the following:

1. Every box in the device checklist above is ticked, on at least one real
   Android phone, from the Play-installed build.
2. Play pre-launch report for release `29` has no new crash or accessibility
   blocker.
3. Android vitals show no regression from the Internal testing cohort.
4. `npm run backend:parity:check:production` still passes at promotion time —
   the backend can drift between the build and the promotion.
5. Data Safety form (`docs/play-console-data-safety.md`) still accurate: no
   SDK was added in this release.
6. The privacy policy URL still returns 200 and still names a legally
   identifiable controller. **This is the one open item outside the repo**: the
   published policy is the pre-Adfoot text, and
   `docs/legal-drafts/README.md` explains why replacing it waits on Adfoot's
   registration. Promoting to Production makes the app publicly installable,
   which is exactly the moment that gap stops being theoretical.
7. If any code or config changes after the `29` AAB, bump `versionCode` to
   `30` and rebuild — Play rejects a reused version code on any track.

## Rollback

- App: halt the rollout in Play Console, or promote the previous release back
  to the track. There is no data migration in `29`, so a downgrade to `28`
  loses nothing.
- Terms gate: it is off. If it is ever armed by mistake, delete
  `config/legal` — every client falls back to the bundled empty version within
  15 minutes (its cache TTL) or at the next cold start.
- Rules and indexes: already deployed and unchanged by this build. A rules
  rollback is `firebase deploy --only firestore:rules,storage` from an earlier
  checkout; `npm run backend:parity:check:production` tells you what is live.
