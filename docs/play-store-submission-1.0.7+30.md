# Play Store Submission — Adfoot 1.0.7+30

Reference date: 1 September 2026

Operator runbook for the build intended to become the **first Production
release** of `org.adfoot.app`. Play production access was granted by Google
before `1.0.7+9`; every release since has stayed on Internal testing on
purpose.

Replaces `docs/play-store-submission-1.0.7+29.md`, deleted rather than kept.
**No `29` AAB was ever built** — the last artefact is
`artifacts/android/adfoot-production-20260829T004239Z.aab`, which carries
`versionCode 28`. `29` was reserved in `pubspec.yaml`, described in a
committed dossier, and never produced. The number is technically still free on
Play, but reusing it for entirely different content would leave two
contradictory records under one version code; `30` keeps the written history
unambiguous.

Nothing here replaces the generic list in
`docs/checklists/android-release-checklist.md`. This records what was verified
for *this* build, on which date, by which command.

## What this build contains that `28` does not

`versionCode 28` was built on **2026-08-29 00:41**, verified from the bundle's
own manifest (`versionCode 28`, `versionName 1.0.7`, `targetSdk 36`,
`minSdk 24`). Everything up to `97c8c74` is in it.

Twenty-five commits landed after it, in three waves.

### 2026-08-30 — hardening

| Commit | What changes for a user |
| --- | --- |
| `3a6e8b8` | An upload's fate is decided once, where it stops. |
| `fa40ff7` | Rules enforce server-side what the client already did; profile photos gain a size and content-type ceiling. |
| `552f899` | Conversations, messages and the inbox become bounded queries; silent failures are reported; a release build without `key.properties` now fails at configuration. |
| `2fd5d9d` | A terms-acceptance gate (**dormant**) and a membership record no client can write. |
| `6f5277f` | Documentation and cost modelling only. |

### 2026-08-31 — agency badge, tooling, then the profile redesign begins

| Commit | What changes for a user |
| --- | --- |
| `98fd498` | A "Joueur agence" badge, shown only while an `adfoot` record is live. **Invisible in production**: no account carries a record. |
| `3723c38`, `4ec743f`, `eba4c14` | Guardrails and tooling. No app code. |
| `1090c48`, `a002521` | "Profil Élite" requires a country. The age requirement was added then withdrawn the same day — see *Corrections made in the open* below. |
| `7dc3027` | The profile lists what a partial scouting file is still missing, to its owner only. |
| `c7ab7c3` | Specification only. |

### 2026-08-31 → 09-01 — the profile redesign

| Commit | What changes for a user |
| --- | --- |
| `c65ab1c` | Closed vocabularies: ten positions, foot, contract status, club level, age category — codes stored, labels shown. Plus an ISO country list. |
| `8a0c742` | `PlayerFootballProfile`: nationalities, contract status and end date, club level, a dated season. Flat on the document so a query can index it. Rules updated in **both** lists. |
| `ee57ce9` | The player forms and the profile display move to the typed model. Positions are chosen from chips, not typed. Self-declared "qualités clés" are gone. |
| `06b4e43` | Offers speak the same language: `positionCodes`, `ageCategories`, `clubLevel` replace free-text `posteRecherche` and `niveau`. |
| `ca95f4a` | Club and agent profiles typed. The club gains a federation number; the agent's licence gains its issuing federation. |
| `3b3bab1` | `birthYear` and `isSearchable` derived server-side by two triggers, plus four `users` indexes. |
| `09e4aad`, `2b76fea` | The admin callable validates against the closed lists; the three-way vocabulary copies are locked by tests and by the contract guardrail. |
| `33c8747` | **Filtered talent search.** A recruiter filters by position, nationality, birth-year range and availability — asked of Firestore, not of the phone. |
| `38e8dd4` | Ops tooling. No app code. |

## The one thing to understand before promoting

**This build ships a search that returns nothing.** That is correct, and it is
not a defect.

The search only returns accounts the server has marked `isSearchable`, which
requires a position, a nationality and a year of birth. Measured on
`adfoot-production` on 2026-09-01: **0 of 17 accounts qualify**. One account
carries a `birthYear`; none carries a position code.

What is missing is data, not code. Filling it is the job of the players and of
the administration portal. Promote this build knowing that the Joueurs tab
will be empty until profiles are filled — and that showing an empty result is
the honest behaviour, since a file with no position cannot be filtered at all.

## Backend state — deployed and verified on 2026-09-01

Unlike every earlier release, the backend this build depends on was deployed
**before** the build, and checked afterwards.

| Element | State |
| --- | --- |
| `firestore.rules`, `storage.rules` | Deployed; SHA-256 identical to this checkout |
| Indexes | 19 declared, 19 deployed, all `READY`, no extras |
| TTL policies | `client_logs/expireAt` and `video_action_logs/expireAt` both `ACTIVE` |
| `deriveUserSearchFields` | Deployed, `europe-west1` |
| `deriveUserSearchFieldsFromContact` | Deployed, `europe-west1` |
| Admin portal | `master` merged and deployed; live bundle byte-identical to the local build |

`npm run backend:parity:check:production`: **deployed backend matches this
checkout**.

The derivation was primed on the existing accounts
(`npm run users:search-fields:refresh:production`): two dead `playerProfile`
maps removed, 17 accounts touched, one `birthYear` derived from its private
contact document. The other sixteen wrote nothing — the recursion guard found
the computed value already in place, which is the guard working.

## Deliberately dormant — do not "fix"

- **Terms acceptance gate.** `TermsConfig.bundledVersion` is empty and
  `config/legal` does not exist in production. Armed fleet-wide, with no new
  build, by writing `config/legal.requiredVersion` the day
  `https://adfoot.org/legal/terms.html` is published. That URL returns 404 on
  purpose.
- **Membership.** No account carries a record, so the "Joueur agence" badge
  shows on nobody.
- **No monetisation surface.** No price, no pay button, no billing SDK. The
  Play Console declaration "contains in-app purchases: no" stays true.

## Verified locally on 2026-09-01, at `38e8dd4`

| Check | Command | Result |
| --- | --- | --- |
| Static analysis | `flutter analyze` | No issues found |
| Test suite | `flutter test` | **824 tests, all passed** |
| Firestore rules, real engine | `npm run rules:test` | **31/31 conformes** |
| Storage rules, real engine | `npm run rules:test:storage` | **25/25 conformes** |
| Functions lint | `npm --prefix functions run lint` | exit 0 |
| Functions build | `npm --prefix functions run build` | exit 0 |
| Inter-repo contract | `check-admin-mobile-contract.ps1` | green, including the 4 mirrored model files |
| Backend parity | `npm run backend:parity:check:production` | green |
| Admin repo | `flutter test` (admin) | **102 tests, all passed** |

**Not re-run at `38e8dd4`, and owed before the build:**
`check-android-release-readiness.ps1 -ReleaseGate` and
`check-production-backend-gate.ps1`. Say so rather than imply otherwise.

## Production data at 2026-09-01

17 users (11 joueurs, 2 agents, 1 club, 1 recruteur, 1 fan, 1 admin) ·
4 videos, all `ready/approved`, **all belonging to a single player** ·
3 `contact_intakes` still `new` · 1 offer · 1 event · 0 conversations ·
**0 accounts searchable**, 1 with a derived `birthYear`.

## Corrections made in the open

Two defects were introduced and fixed during this work. They are recorded
because both were the kind that a green suite does not catch.

- **A verdict that depended on its reader.** Requiring a birth date for
  "Profil Élite" made the label invisible to recruiters: `birthDate` lives in
  the private contact document and reaches only the profile owner, so a player
  saw "Élite" while a recruiter saw "partiel" on the same file. Withdrawn in
  `a002521`; a guardrail now builds the same user with and without the private
  document and demands an identical verdict.
- **A level that became unreachable.** `isMvpProfileComplete` still read
  `position`, the free-text field nothing writes since the redesign. "Profil
  complet" became impossible for any player, and with it the prompt to
  complete the advanced file, which only shows on a complete profile without
  one. Fixed in `2b76fea`; a test now checks all four levels are reachable.

## Not verified — and the reason this build must not be promoted blind

**No build since `1.0.7+27` has been run on a physical device**, and this one
adds more untested surface than any release before it. Install from the
Internal testing link — **not** `flutter run`, since App Check and Play App
Signing differ — and record what was *seen*.

Carried over, still unverified:

- [ ] **Navigation bar** — the tab reads `Carrière`, nothing clipped, the `+`
      Publier pill on the same line. Then set the system font size to maximum.
- [ ] **Background playback** — start a video, press Home. Sound must stop.
- [ ] **Scroll away from a loading video** — it must not start playing later.
- [ ] **Feed position** — scroll, switch tab, come back; same video, restarted
      from its beginning (expected: the player was disposed).
- [ ] **Terms gate stays invisible** — cold start, tapped notification, shared
      link. If one appears, `config/legal` was written by mistake.
- [ ] **Profile photo change still works** against the deployed Storage rule.
- [ ] **Video upload end to end** on a real connection.
- [ ] **Kill the app mid-upload and reopen it.**
- [ ] **Messaging** — send, then scroll back. Production has 0 conversations,
      so this code has never run on real data.
- [ ] **A contact request produces an e-mail** to `support@adfoot.org`
      (`OPS_NOTIFICATION_EMAIL` is unset, so the fallback is `MAIL_REPLY_TO`).
      Confirm that address is actually read.

New in `30`, and none of it has ever run on hardware:

- [ ] **The player profile form.** Position chips: three maximum, the first
      chosen is primary, an unselected chip goes inactive at the limit. The
      nationality picker opens, searches, and its list is usable one-handed.
      The contract end date appears only for "sous contrat" or "en prêt", and
      disappears when the status becomes "libre".
- [ ] **The season form.** Season, competition and category save together with
      the numbers; an entirely empty season is erased rather than stored as a
      shell of nulls.
- [ ] **The missing-requirements panel.** On your own incomplete profile it
      lists what is left. On **another** player's profile it must not appear.
- [ ] **The four profile levels.** A player with a name and a team reads
      "Profil complet"; adding a position moves them to "Profil avancé".
- [ ] **Publishing an offer.** Positions and categories as chips, club level as
      a dropdown. The offer then displays them, and the search bar finds it by
      label ("défenseur"), not by code.
- [ ] **The Joueurs tab.** Present for a club, recruiter or agent; **absent
      for a player and a fan**. It is the third tab: a notification for an
      event must still land on Événements.
- [ ] **An empty search says so.** With no profile filled, the search must read
      "Aucun joueur ne correspond" — not an error, and not a blank screen.
- [ ] **A filled profile becomes searchable.** Fill one player from the admin
      portal (position, nationality, birth date), wait for the trigger, then
      search. This is the single end-to-end check that proves the whole chain.
- [ ] **The admin portal writes what the app reads.** Edit a player's positions
      from the portal and confirm the change appears in the app.

## Build

```powershell
npm.cmd run release:android:bundle:playstore
```

If it fails with a file-lock error under `build\`, run `gradlew --stop` from
`android\` and rebuild. After the build, record here: AAB path, byte size,
SHA-256, and confirm from the bundle manifest that `versionCode` is `30`.

- AAB: _fill after build_
- Size: _fill after build_
- SHA-256: _fill after build_
- 16 KB alignment: `powershell -File .\scripts\check-aab-native-alignment.ps1`
  — _fill after build_

## Release notes (Internal testing / Production "What's new")

```text
Version 1.0.7 - profils footballistiques et recherche de joueurs.

- Profils structures : poste, pied, gabarit, nationalites, situation contractuelle et saison en cours.
- Nouvelle recherche de joueurs pour les clubs, recruteurs et agents.
- Offres plus precises : postes et categories recherches sont desormais choisis dans une liste.
- Le profil indique ce qu'il reste a renseigner pour etre visible des recruteurs.
- Corrections d'affichage et de stabilite.
```

## Before promoting to Production

1. Every box in the device checklist above ticked on at least one real Android
   phone, from the Play-installed build.
2. Play pre-launch report for `30` shows no new crash or accessibility blocker.
3. Android vitals show no regression from the Internal testing cohort.
4. `npm run backend:parity:check:production` still green at promotion time.
5. Data Safety form (`docs/play-console-data-safety.md`) still accurate — no
   SDK was added in this release.
6. The privacy policy URL still returns 200 and names a legally identifiable
   controller. **The one open item outside the repo**: the published policy is
   the pre-Adfoot text, and `docs/legal-drafts/README.md` explains why
   replacing it waits on Adfoot's registration. Promoting makes the app
   publicly installable, which is exactly when that gap stops being
   theoretical.
7. If any code or config changes after the AAB, bump to `31` and rebuild.

## Rollback

- **App:** halt the rollout, or promote the previous release back. There is no
  data migration in `30`, so a downgrade to `28` loses nothing the app reads.
- **The redesign is additive on the document.** The new fields sit beside the
  old ones; `28` ignores them and keeps working.
- **Terms gate:** off. If armed by mistake, delete `config/legal`.
- **Rules and indexes:** deployed 2026-09-01 and unchanged by the build.
  A rules rollback is `firebase deploy --only firestore:rules,storage` from an
  earlier checkout; `npm run backend:parity:check:production` says what is live.
- **The two triggers** can be removed with
  `firebase functions:delete deriveUserSearchFields deriveUserSearchFieldsFromContact`.
  The fields they wrote stay, harmless: no client writes them and the search
  simply stops finding new accounts.
