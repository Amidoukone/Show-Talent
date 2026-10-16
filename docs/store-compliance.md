# Store Compliance

Reference URLs required by the Play Console (Data Safety form, App content)
and validated automatically by `scripts/check-android-release-readiness.ps1`.

- Terms of service: https://adfoot.org/legal/terms.html
- Privacy policy: https://adfoot.org/legal/privacy-policy.html
- Account deletion: https://adfoot.org/legal/account-deletion.html

Each page has an English counterpart at the same path with an `.en` infix
(`terms.en.html`, `privacy-policy.en.html`, `account-deletion.en.html`). French
is the reference text and the `x-default`; the app opens the English page when
the app language is English (`TermsConfig.termsUrlForLanguage`). Declare the
French URLs in both store consoles.

All six pages are served from `site_pub/legal/` and must be deployed (hosting)
before submitting a release build to Play Console review.

**The terms page was absent from the live site until 2026-10-14**, while the
app's Reglages > Documents tile and the account activation email both linked to
it, a live 404 on a consent document. Three checks now fail on it instead of
nobody noticing: `test/terms_acceptance_guardrails_test.dart` maps every URL
the app and the email can emit to a file under `site_pub/legal/`,
`scripts/check-production-hosting.mjs` byte-compares all six deployed pages
plus their stylesheet, and this script refuses a release gate when a page still
carries a draft marker.

## Confirmed for the next production submission

- Developer/seller display name: **SIRA SARL**
- Launch territory: **Mali**
- Minimum player age: **13**, raised from 12 on 2026-10-14. **Declare the target
  audience as 13+ and no younger.** The whole point of the change is that an
  audience including under-13s puts the app under Google Play's
  [Families Policy](https://support.google.com/googleplay/android-developer/answer/9893335?hl=en),
  which requires verifiable parental consent and a means for an adult to manage
  the social features. Adfoot's consent is recorded orally by the
  administration and parents manage it by emailing `support@adfoot.org`:
  defensible, but not obviously sufficient for a store declaration. Thirteen
  removes that entire surface for one year of age range, and changes nothing
  about the 13-17 protections. Selecting any under-13 age group in the Play
  Console reinstates every one of those requirements.
- The rule lives in exactly one place, `MINIMUM_PLAYER_AGE` in
  `functions/src/minor_consent.ts`, enforced server-side at three call sites
  (`admin_account_actions.ts` twice, `managed_accounts.ts` once). The mobile app
  holds no age threshold of its own. **Raising or lowering it means changing
  that constant, the published terms and privacy policy, the marketing site and
  the admin portal's two messages together.**
- Existing accounts are test accounts; no production backfill is needed. A
  player already recorded as 12 would not be removed by this change, since the
  check runs on creation and on admin birth-date correction, not retroactively.
- Players aged 13-17 require a parent or legal guardian's recorded consent.
  Parents do not need an app account; they can contact `support@adfoot.org` to
  request changes to or withdrawal of the parental and media permissions.
- The mobile backend and admin portal now include
  `withdrawManagedMinorConsent`, which removes a minor's public profile and
  purges published media after a verified parent request. Deploy the backend
  and admin portal together before treating this support workflow as live.
- Player records are reclassified daily after their eighteenth birthday so the
  adult profile and messaging rules do not depend on the player editing their
  account.
- **Registration is chargeable, and the app must stay silent about it.**
  15,000 FCFA once for a player; 25,000 FCFA per year for a club, recruiter or
  agent. Payment is cash only, at the Bamako agency. The mobile app displays no
  price, offers no way to pay and links to none, and
  `setManagedAccountMembership` carries no amount: that is what keeps the Play
  Console "no in-app purchases" declaration true and keeps the build clear of
  App Store guideline 3.1.1. **Never add a price, a payment button or a payment
  link to the app.** Pricing lives in the published terms (§7.1) and on the
  marketing site, which are not subject to those rules. `Membership`
  (`lib/models/membership.dart`) mirrors the administration's decision only;
  `MembershipTier.adfoot` is a player the agency carries at its own cost.
- Terms of service and privacy policy are **version 1.2, effective
  15 October 2026**, published in French and English. Version 1.0 was published
  the same day and withdrawn within hours: it stated that player access was
  free, which was wrong. The short interim privacy
  page was replaced by the full policy, which now states concrete retention
  periods taken from the code (90 days for error and video-action logs, 30 days
  for other telemetry, 3 days for an unverified account that the administration
  did not create) and names the three processors: Google Firebase/Google Cloud,
  Brevo for outbound email, ImprovMX for inbound email.
- The in-app acceptance gate is still **dormant on purpose**:
  `TermsConfig.bundledVersion` stays empty so the gate cannot arm from a build
  alone. It is switched on fleet-wide by writing `config/legal`. See
  "Activating the acceptance gate" below.

## App access: the review account is mandatory, not optional

Measured in this checkout on 2026-10-13: `publicSelfSignupRoles` in
`lib/utils/account_role_policy.dart` is the **empty list**, and
`lib/screens/signup_screen.dart` is an information screen: a logo, three
explanatory cards and a "back to login" button. It contains no form. All five
roles (`joueur`, `fan`, `club`, `recruteur`, `agent`) are provisioned by an
administrator.

Consequence: a reviewer who opens the app can reach **nothing** without
credentials. Both stores treat that as a blocking defect rather than a
limitation, and each has its own form for it:

- **Apple**: App Store Connect -> the version -> *App Review Information* ->
  **Sign-In Required** checked, with `Username` and `Password`. A build whose
  entire functionality sits behind a login with no usable account is the
  standard Guideline 2.1 rejection, and the rejection costs a full review
  cycle, not an hour.
- **Google**: Play Console -> *Policy* -> *App content* -> **App access** ->
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
- A profile already populated with a name, photo, position and at least one approved
  video, so the reviewer sees the app rather than an empty state. An account
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
  returns `false`, and the account is deleted within three days, in the
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
- The minimum age is 13. Accounts for players aged 13-17 require a recorded
  parent or guardian consent, collected by the administrator before the
  account is created, and such a profile appears in recruiter search only
  after an administrator has approved it.
- Account deletion is available in the app under Profile -> Settings, and is
  also documented at https://adfoot.org/legal/account-deletion.html
- Terms of service and privacy policy are published in French, the launch
  market's language, with English translations for review:
  https://adfoot.org/legal/terms.en.html
  https://adfoot.org/legal/privacy-policy.en.html
  They are also reachable in the app under Profile -> Settings -> Documents.
```

**The minor line said something the code contradicts, until 2026-10-16.** It
claimed minors were excluded from public discovery. They are not:
`user_search_fields.ts:209` computes `isSearchable` as
`isMinor ? (minorProfileApproved === true && computeIsSearchable(...)) : computeIsSearchable(...)`,
so an approved minor **is** searchable, with a position code and a
nationality. The protection is an administrator's approval, not an exclusion,
and that is what the notes now say. Telling a reviewer something their own
testing can disprove is worse than saying nothing: it invites them to doubt
every other line. The ternary is formatted across three lines in a way that
reads as two identical branches at a glance, which is how the error survived.

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
   window. One command reads every condition at once, including the acceptance
   version once the gate is armed:

   ```
   npm run review:account:check:production -- --email <address>
   ```

   It exits non-zero until the account is fit to hand over, and prints `READY`
   when it is. Pass `--role club` for the second account kept for showing
   messaging; a club has no playing position and no videos of its own, so
   without the flag those two checks report defects that are not defects.

   The condition that matters most is `createdByAdmin == true`, because it is
   the only thing keeping `cleanupUnverifiedAccounts` away from a `joueur`
   account: `MANAGED_ROLES` is `{admin, club, recruteur, agent}` and `joueur`
   is not in it, so there is no fallback.

2. The login, which decides whether the reviewer gets past the first screen.
   Sign in with the exact credentials written in the review notes, on a device
   that has never held a session, **from the submitted build**, not a debug
   build and not a build on a different Firebase project. The failure this
   catches is a password that works in the console and not in the app, and a
   demo account provisioned in `adfoot-staging` while the build points at
   `adfoot-production`.

Keep the credentials out of this file and out of git: `.gitignore` already
excludes `docs/smoke-managed-account-auth-*.json` and
`docs/smoke-public-signup-*.json` for the same reason. The review notes in App
Store Connect and Play Console are the only place they belong.

## Activating the acceptance gate

The gate is a Firestore switch, not a build constant. `TermsConfig`
(`lib/services/legal/terms_acceptance_service.dart`) ships with
`bundledVersion = ''`, which means no acceptance is required; it reads
`config/legal` at most once every 15 minutes and fails open on any error.

Order matters, and the reason is the defect this replaced: arming the gate
before the pages are reachable asks every user to accept a document they cannot
open.

1. Deploy hosting: `npm.cmd run hosting:marketing:deploy:production`.
2. Verify the deployed bytes: `node scripts/check-production-hosting.mjs`
   (exits non-zero if any of the six pages is missing or differs from this
   repo). Then open `/legal/terms.html` and `/legal/terms.en.html` on a phone
   and on a desktop browser, and follow the language switcher both ways.
3. Only then write `config/legal` in `adfoot-production`:

   ```
   requiredVersion: "1.2"
   effectiveOn:     "15 octobre 2026"
   termsUrl:        "https://adfoot.org/legal/terms.html"
   privacyUrl:      "https://adfoot.org/legal/privacy-policy.html"
   termsUrlEn:      "https://adfoot.org/legal/terms.en.html"
   privacyUrlEn:    "https://adfoot.org/legal/privacy-policy.en.html"
   ```

   Leave the four URL keys out and the build's own constants are used, which
   are the same values; they exist so a page can be moved without a release.

There is a second ordering constraint, measured on 2026-10-15, and it is about
*which build* is installed when the gate opens. Build `1.0.7+50` shipped the
consent screen with the pre-correction highlights: "Gratuit pour les joueurs"
and "sans commission". Both statements became false in version 1.1 of the
terms, which names the 15 000 FCFA access fee and allows a share of a contract.
That build also has no English URL support at all, so an English user lands on
the French text. Arming the gate while `+50` is the installed build would
therefore ask users to tick "I accept" in front of a screen contradicting the
document they are accepting, and record that consent. Distribute the corrected
build (`1.0.7+51` or later) first, then arm.

Writing `requiredVersion` makes every account that has not accepted version
`1.2` see the consent screen on its next launch, within the 15-minute cache
window. That includes the App Review demo account, so accept the terms on it
once after arming the gate, or the reviewer meets the consent screen first and
reports the app as blocked. Clearing `requiredVersion` back to `""` disarms the
gate just as fast.

Publisher details supplied by SIRA:

- Legal name: **SIRA DIGITAL INNOVATION STUDIO SARL**, abbreviated **SIRA SARL**;
  Mali registration: `425900104010012M0004L`
- Registered office: Bamako, Quartier Sébénikoro, near ORYX station
- Official phone: `70.45.33.45`

Two mailboxes, with the split the published legal pages declare. Both are
`@adfoot.org` aliases forwarded by ImprovMX, so **both must exist and be read**.
A legal page naming a mailbox nobody opens is worse than naming one address:

| Address | What it receives | Where it is declared |
| --- | --- | --- |
| `support@adfoot.org` | account and access, reports of content/accounts/behaviour, security, parental consent and media permission for a minor | the app's own strings (`app_fr.arb`, `app_en.arb`), terms §2/§3/§6, privacy §7/§9, the deletion page |
| `contact@adfoot.org` | publisher contact for SIRA SARL, and personal-data requests (access, rectification, erasure, restriction, objection) | terms §1/§14, privacy §1/§7/§12, the site footer form |

Use `contact@adfoot.org` wherever a console asks for the **privacy / data
controller** contact, and `support@adfoot.org` wherever it asks for **user
support**. Apple's App Store Connect asks for a support URL and a support
contact: that one is `support@adfoot.org`.
