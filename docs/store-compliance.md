# Store Compliance

Reference URLs required by the Play Console (Data Safety form, App content)
and validated automatically by `scripts/check-android-release-readiness.ps1`.

- Privacy policy: https://adfoot.org/legal/privacy-policy.html
- Account deletion: https://adfoot.org/legal/account-deletion.html

Both pages are served from `site_pub/legal/` and must be deployed (hosting)
before submitting a release build to Play Console review.

## Confirmed for the next production submission

- Developer/seller display name: **SIRA SARL**
- Launch territory: **Mali**
- Minimum player age: **12**. The declared audience therefore includes children
  under 13; complete Google Play Families declarations and verify the required
  adult controls for social features before submission. Existing accounts are
  test accounts; no production backfill is needed. New managed player accounts
  and admin birth-date corrections enforce the 12-year minimum.
- Players aged 12–17 require a parent or legal guardian's recorded consent.
  Parents do not need an app account; they can contact `support@adfoot.org` to
  request changes to or withdrawal of the parental and media permissions.
- The mobile backend and admin portal now include
  `withdrawManagedMinorConsent`, which removes a minor's public profile and
  purges published media after a verified parent request. Deploy the backend
  and admin portal together before treating this support workflow as live.
- Player records are reclassified daily after their eighteenth birthday so the
  adult profile and messaging rules do not depend on the player editing their
  account.
- The public privacy page and the legal drafts must be reviewed together before
  publishing the revised policy. The draft terms and privacy pages are not live.

## App access: the review account is mandatory, not optional

Measured in this checkout on 2026-10-13: `publicSelfSignupRoles` in
`lib/utils/account_role_policy.dart` is the **empty list**, and
`lib/screens/signup_screen.dart` is an information screen — a logo, three
explanatory cards and a "back to login" button. It contains no form. All five
roles (`joueur`, `fan`, `club`, `recruteur`, `agent`) are provisioned by an
administrator.

Consequence: a reviewer who opens the app can reach **nothing** without
credentials. Both stores treat that as a blocking defect rather than a
limitation, and each has its own form for it:

- **Apple** — App Store Connect -> the version -> *App Review Information* ->
  **Sign-In Required** checked, with `Username` and `Password`. A build whose
  entire functionality sits behind a login with no usable account is the
  standard Guideline 2.1 rejection, and the rejection costs a full review
  cycle, not an hour.
- **Google** — Play Console -> *Policy* -> *App content* -> **App access** ->
  "All or some functionality is restricted", then one entry per restricted
  area with the same credentials. Leaving this on the default
  "All functionality is available without special access" is a false
  declaration about this app.

### What the account must be

A real administrator-provisioned account in `adfoot-production`, not a
throwaway:

- Role `joueur`. It is the role that reaches the most surface: profile, CV,
  video publishing, feed, messaging, career tab. A `club` or `recruteur`
  account cannot show the player journey, and the player journey is what the
  screenshots promise.
- A profile already populated — name, photo, position, at least one approved
  video — so the reviewer sees the app rather than an empty state. An account
  that logs in successfully and then shows blank screens invites a Guideline
  2.1 rejection for a different reason.
- **Created through the admin portal (`provisionManagedAccount`), never by
  hand in the Firebase Auth console.** This is the one that silently destroys
  a submission. `cleanupUnverifiedAccounts` runs every 24 hours and deletes
  accounts older than `UNVERIFIED_ACCOUNT_RETENTION_DAYS=3`;
  `UNVERIFIED_PURGE_EXCLUDE_MANAGED=true` spares an account only when
  `asManagedAccount()` recognises it, which means `createdByAdmin === true`
  **or** a role in `{admin, club, recruteur, agent}` on its `users` document
  (`functions/src/cleanup.ts`). `provisionManagedAccount` writes
  `createdByAdmin: true` for every provisioned role, `joueur` included, so a
  portal-created player is protected. An account created directly in the Auth
  console has no `users` document at all: `asManagedAccount(undefined)`
  returns `false`, and the account is deleted within three days — in the
  middle of the review, with the reviewer seeing an invalid login and no way
  to know why.
- A password with no expiry and no mandatory rotation.
- Not reused as a personal test account. A reviewer and a tester writing to
  the same profile at the same time produces behaviour neither of them can
  explain.

### Review notes text to paste

English, because that is what the reviewer reads. Replace the two bracketed
values; keep the rest, because each paragraph answers a question that
otherwise comes back as a rejection:

```
Adfoot is a closed professional network for football in Mali. Accounts are
created by Adfoot administrators for verified players, clubs, recruiters and
agents; there is no public self-registration, which is why the sign-up screen
only explains the process. The demo account below is a player account.

Demo account (player):
  Email: [DEMO_EMAIL]
  Password: [DEMO_PASSWORD]

Notes for the reviewer:
- Videos published from the app are reviewed by a human moderator before they
  appear in the public feed. A video uploaded during review will therefore
  stay in "pending" state. Already-approved videos are visible in the feed.
- Messaging is restricted to accounts that are connected on the platform, so
  the demo account can only write to the contacts it already has.
- The minimum age is 12. Accounts for players aged 12-17 require a recorded
  parent or guardian consent, collected by the administrator before the
  account is created, and such profiles are excluded from public discovery.
- Account deletion is available in the app under Profile -> Settings, and is
  also documented at https://adfoot.org/legal/account-deletion.html
```

Add the Apple-only line below if the submitted build still ships
`APP_CHECK_MODE=soft`; it pre-empts a question about declined attestations
appearing in the backend logs during review:

```
- The backend records a device-attestation signal for diagnostics but does not
  reject requests when it is absent, so the app behaves identically on the
  review device.
```

### Verifying the account before submission, not after

Two checks, because they fail differently.

1. The document, which decides whether the account survives the review
   window. On `users/<demo uid>`, confirm `createdByAdmin == true`,
   `emailVerified == true`, `estActif == true`, and `role == "joueur"`. The
   first field is what keeps `cleanupUnverifiedAccounts` away from it. There
   is no script for this check today; read the document in the Firebase
   console or the admin portal.

2. The login, which decides whether the reviewer gets past the first screen.
   Sign in with the exact credentials written in the review notes, on a device
   that has never held a session, **from the submitted build** — not a debug
   build and not a build on a different Firebase project. The failure this
   catches is a password that works in the console and not in the app, and a
   demo account provisioned in `adfoot-staging` while the build points at
   `adfoot-production`.

Keep the credentials out of this file and out of git: `.gitignore` already
excludes `docs/smoke-managed-account-auth-*.json` and
`docs/smoke-public-signup-*.json` for the same reason. The review notes in App
Store Connect and Play Console are the only place they belong.

Publisher details supplied by SIRA:

- Legal name: **SIRA DIGITAL INNOVATION STUDIO SARL**, abbreviated **SIRA SARL**;
  Mali registration: `425900104010012M0004L`
- Registered office: Bamako, Quartier Sébénikoro, near ORYX station
- Official phone: `70.45.33.45`
- Privacy/contact email: `support@adfoot.org`
