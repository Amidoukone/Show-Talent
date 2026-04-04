# Android Staging Flavor Scaffold

This directory is intentionally a scaffold only.

Add the staging `google-services.json` here only after:

1. the staging Firebase project exists,
2. the Android staging app is registered there,
3. native product flavors are activated in Gradle.

Planned Android publication IDs:

- local: `org.adfoot.app.local`
- staging: `org.adfoot.app.staging`
- production: `org.adfoot.app`
