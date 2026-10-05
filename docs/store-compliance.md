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

Publisher details supplied by SIRA:

- Legal name: **SIRA DIGITAL INNOVATION STUDIO SARL**, abbreviated **SIRA SARL**;
  Mali registration: `425900104010012M0004L`
- Registered office: Bamako, Quartier Sébénikoro, near ORYX station
- Official phone: `70.45.33.45`
- Privacy/contact email: `support@adfoot.org`
