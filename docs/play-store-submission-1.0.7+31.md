# Play Store Submission — Adfoot 1.0.7+31

Reference date: 2 September 2026

Operator runbook for the build that carries the profile rework. Play
production access was granted before `1.0.7+9`; every release since has stayed
on Internal testing on purpose, and this one should too until the device
checks below are done.

`docs/play-store-submission-1.0.7+30.md` is **kept**, not replaced. Unlike
`29`, `30` was really built and really ran on a phone in Internal testing —
that record stands on its own. This dossier only covers what `31` adds.

Nothing here replaces the generic list in
`docs/checklists/android-release-checklist.md`. This records what was verified
for *this* build, on which date, by which command.

## What this build contains that `30` does not

`versionCode 30` was built at `5e71413`. Seven commits landed after it, all on
`profil-football-refonte`. Three of them fix defects that were live in
production and that neither `flutter analyze` nor the 826 tests of the day
could see — they were not type errors, they were the app and the server
disagreeing.

### The three silent defects

| Commit | Defect |
| --- | --- |
| `4070389` | A player who filled everything **except their date of birth** was shown a green "Dossier scout prêt" and appeared in **no recruiter search**. `missingScoutRequirements` never asked for the age; `computeIsSearchable` refuses a null `birthYear`. |
| `7e0c36f` | A **verified** player could not save their advanced profile at all. The rules refuse a trust-field change that does not carry the verification reset; the client only attached that reset for the legacy field names, none of the sixteen typed football fields. The form answered "reconnectez-vous", which changed nothing. |
| `57be74b` | Two clubs on one file. `team`, `clubActuel` and `currentClubName` all carried the club, and none of the three writers wrote all three — reachable from the base editor, the advanced form **and** the admin portal. |

### The rest

- `348cd3d` — the profile no longer repeats itself. Name, role, age, club and
  location were each shown twice or three times; the header card now carries
  only what is nowhere else. The `Ville, Région, Pays` overflow is fixed at its
  cause: `_InfoPill` measured the screen instead of asking its parent.
- `9d193fc` — **season history**. A file had one season; it now has a career,
  bounded at ten, each past season carrying the club and level it was played
  at. Archiving is a gesture ("Archiver cette saison"), not another form.
- `1475bbd` — the admin callable validates and accepts `currentSeason` and
  `seasonHistory`. Before this, a file with wrong statistics had **no recourse**
  at all, which is precisely what a recruiter reports.
- `0e00b60` — **stats provenance**, said next to the figures: attested by
  Adfoot, attestation suspended, or declared by the player. Nothing new is
  stored; the provenance *is* the verification state, which only the admin
  callable writes and which the rules invalidate as soon as a statistic moves.

## The one thing to understand before promoting

**This build needs the rules that were deployed on 2 September.** They were,
and parity is green — but the two must stay together. A `31` APK running
against the previous ruleset would refuse every season archive with
`permission-denied`, and because `changesOnly()` fails the *whole* write, the
player would silently lose their other edits in the same save.

Second point, less obvious: **the admin portal is not deployed yet.** Two
commits sit on `profil-football-sources` in the web repo. This is safe in this
order and only in this order — the production portal still writes `team`, and
`31` reads `currentClubName ?? team ?? clubActuel`, so an admin correction
still reaches the phone through the fallback. Deploying the portal *before*
the mobile build would break that: it would write `currentClubName`, which
`30` does not read.

## Backend state — deployed and verified on 2026-09-02

| Element | State |
| --- | --- |
| `firestore.rules` | Deployed 02:01:26 UTC, SHA-256 `aa894907…` identical to this checkout |
| `storage.rules` | Unchanged (`b1c7b466…`), never touched by this work |
| Indexes | 19 declared, 19 deployed, all `READY`, no extras |
| TTL policies | `client_logs/expireAt` and `video_action_logs/expireAt` `ACTIVE` |
| Functions | 43 updated, including `updateManagedAccountProfile`, `deriveUserSearchFields`, `deriveUserSearchFieldsFromContact` |

`scripts/check-backend-parity.ps1`: **deployed backend matches this checkout**.

Two things to know about that deploy:

- It was made **from `profil-football-refonte`, not from `master`**. Until the
  branch is merged, running the parity check from a `master` checkout reports a
  drift that is an artefact of the branch, not a real one.
- A plain `firebase deploy --only functions` fails on this machine with
  `Cannot determine backend specification. Timeout after 10000`. Use the repo's
  own script, which also validates the environment files first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-functions-safe.ps1 `
  -Environment production -Only functions -DiscoveryTimeoutSeconds 120
```

## Deliberately dormant — do not "fix"

- **`position`, `team` and `clubActuel` are still read**, as a fallback behind
  the typed fields, and are written by nothing. Accounts created before the
  switch keep their file; the first save converts them. Removing them from the
  model is a separate step, to be done once the accounts have gone through the
  editor once.
- **A coach still types a free-text position.** "Préparateur physique" has no
  equivalent in the closed list of pitch positions, and removing the field
  would leave coaches with nothing.
- **The admin portal removes seasons, it does not add them.** A season is
  archived from the phone, when it ends, with the club the profile carried at
  that moment. Retyping one from memory is how an invented fact enters a base
  presented as qualified.

## Verified locally on 2026-09-02, at `0e00b60`

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues found (424.9 s) |
| `flutter test` | **845 passed** |
| `npm run lint` + `npm run build` (functions) | clean, run again by the deploy predeploy |
| Admin repo `flutter test` | 102 passed |

Seven guardrails were added along the way. The one that matters most compares
the client's trust-sensitive key set against `ownerProfileTrustFieldsChanged()`
in `firestore.rules`; nothing compared those two lists before, which is exactly
why they had drifted. It did its job the next day by demanding `seasonHistory`
on both sides at once.

## Not verified — and the reason this build must not be promoted blind

**Nothing in this build has run on a phone.** 845 tests render no pixels, and
three of the seven commits change what the critical path writes. Do these on
the device, in this order:

1. **A verified account saves its advanced profile.** This is the `7e0c36f`
   scenario. Before the fix the save was refused with a message telling the
   user to sign in again. It must now succeed — and the "Vérifié par Adfoot"
   badge must drop to "A revalider", because the figures changed.
2. **`Ville`, `Région`, `Pays` filled with long values.** The label must
   ellipsise inside the card, never cross the right edge. Check on the
   narrowest phone available.
3. **The name appears once**, in the top bar, and not beside the photo.
4. **Archive a season**, then reopen the profile: it must appear under
   "Parcours" with its club, and the current-season fields must be empty.
5. **A player with no date of birth** shows "Dossier scout partiel" and names
   "Date de naissance" in the missing list — not a green badge.
6. **An unverified player's figures** carry "Chiffres déclarés par le joueur,
   non attestés."
7. **Video playback and the feed** — untouched by this work, but the profile
   screen hosts the video list, so a smoke pass is warranted.

## Build

```powershell
npm.cmd run release:android:bundle:playstore
```

If it fails with a file-lock error under `build\`, run `gradlew --stop` from
`android\` and rebuild. After the build, record here: AAB path, byte size,
SHA-256, and confirm **from the bundle's own manifest** that `versionCode` is
`31` — read the AAB, not the source.

- AAB: _fill after build_
- Size: _fill after build_
- SHA-256: _fill after build_
- 16 KB alignment: `powershell -File .\scripts\check-aab-native-alignment.ps1`
  — _fill after build_

## Release notes (Internal testing / Production "What's new")

```text
Version 1.0.7 - profils plus lisibles et parcours du joueur.

- Le profil ne repete plus la meme information a deux endroits.
- Parcours : archivez vos saisons passees, avec le club et le niveau.
- Les chiffres indiquent desormais s'ils sont declares ou attestes par Adfoot.
- Un poste se choisit dans une liste, la meme que celle des recruteurs.
- Correction : un profil complet sans date de naissance n'apparaissait dans aucune recherche.
- Correction : un profil verifie ne pouvait plus etre enregistre.
- Corrections d'affichage.
```

## Before promoting to Production

- The seven device checks above, done and written down.
- The admin portal deployed, **after** this build ships.
- `profil-football-refonte` merged into `master`, so the deployed backend and
  `master` agree again.

## Rollback

- **Rules:** `firebase deploy --only firestore:rules` from a commit before
  `9d193fc`. The previous ruleset was `5901072e…`. Note that rolling the rules
  back while a `31` client is in the field re-breaks season archiving — roll
  the build back first, or together.
- **Functions:** the same `deploy-functions-safe.ps1` from an earlier commit.
  The change is additive (two new sanitised fields), so an older callable
  simply ignores them.
- **Build:** halt the Internal testing rollout; `30` remains installable and
  is unaffected by the deployed rules, which only added whitelist entries.
