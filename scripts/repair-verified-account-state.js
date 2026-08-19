#!/usr/bin/env node

/*
 * Repairs accounts whose Firebase Auth record says the email is verified while
 * their Firestore profile still says it is not.
 *
 * Why this happens and why it locks the user out:
 *
 * Auth is the source of truth for verification, but every gate in the app and
 * in the Cloud Functions reads the *profile* fields (`emailVerified`,
 * `estActif`). The client cannot repair the mismatch itself — Security Rules
 * deliberately keep those two fields out of the owner-writable allowlist — so
 * the only sanctioned repair path is the `completeEmailVerification` callable,
 * which writes through the Admin SDK. When that callable fails or is not
 * deployed, the account is stuck permanently: AuthSessionService retries it
 * five times with a two-second gap on every single sign-in
 * (_retryEmailVerificationSync), never reaches
 * AuthSessionDestination.main, and the user watches a spinner that resolves to
 * "Profil indisponible". assertUploadCallerEligible refuses their uploads for
 * the same reason.
 *
 * This script performs that same repair out-of-band, so stuck accounts can be
 * unblocked without shipping a build. It only ever promotes a profile to match
 * Auth — it never marks anything unverified, and it never touches an account
 * whose Auth record is itself unverified.
 *
 * Usage:
 *   node .\scripts\repair-verified-account-state.js --project-id <gcp-project> \
 *     [--credentials <service-account.json>] [--apply]
 *
 * Without --apply it only reports what it would change.
 */

const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];

    if (!next || next.startsWith("--")) {
      args[key] = "true";
      continue;
    }

    args[key] = next;
    index += 1;
  }
  return args;
}

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node .\\scripts\\repair-verified-account-state.js --project-id <gcp-project> " +
        "[--credentials <service-account.json>] [--apply]",
    ].join("\n"),
  );
}

async function listAllAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help === "true" || args.h === "true") {
    printUsage();
    process.exit(0);
  }

  const projectId = args["project-id"] || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    printUsage();
    throw new Error("Missing --project-id and GOOGLE_CLOUD_PROJECT.");
  }

  if (args.credentials) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = args.credentials;
  }

  const apply = args.apply === "true";

  admin.initializeApp({projectId});
  const db = admin.firestore();
  const auth = admin.auth();

  const authUsers = await listAllAuthUsers(auth);
  const stuck = [];

  for (const user of authUsers) {
    if (!user.emailVerified) {
      // Auth itself says unverified: nothing to propagate, and forcing it
      // would hand out access the user never earned.
      continue;
    }

    const ref = db.collection("users").doc(user.uid);
    const snap = await ref.get();
    if (!snap.exists) {
      continue;
    }

    const data = snap.data() || {};
    if (data.emailVerified === true && data.estActif === true) {
      continue;
    }

    stuck.push({
      uid: user.uid,
      email: (user.email || "").replace(/(.{2}).*(@.*)/, "$1***$2"),
      role: data.role ?? null,
      profileEmailVerified: data.emailVerified ?? null,
      profileEstActif: data.estActif ?? null,
      authDisabled: data.authDisabled === true,
      lastSignIn: user.metadata.lastSignInTime || null,
    });

    if (!apply) {
      continue;
    }

    await ref.set(
      {
        emailVerified: true,
        estActif: true,
        emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }

  console.log(
    JSON.stringify(
      {
        projectId,
        mode: apply ? "apply" : "dry-run",
        authUsersScanned: authUsers.length,
        accountsLockedOut: stuck.length,
        accounts: stuck,
        checkedAtUtc: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  const isAuthError = message.includes("Could not load the default credentials");
  console.error(
    JSON.stringify(
      {
        success: false,
        error: message,
        ...(isAuthError ?
          {
            hint:
              "Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON path, " +
              "or pass --credentials <path>.",
          } :
          {}),
        checkedAtUtc: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
