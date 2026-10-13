#!/usr/bin/env node

/**
 * Measures the three preconditions for closing the `users` ->
 * `public_profiles` migration (phase 3 of
 * `docs/checklists/public-profile-rollout-2026-09-28.md`).
 *
 * The checklist says to verify the migration threshold "avec des donnees
 * reelles" before flipping the legacy flags, but nothing measured it. The
 * flags are deployed in their phase-1 posture while `firestore.rules` is
 * already the final ruleset in production, so the question is no longer
 * "is it safe to close" but "what is left to close". Those are different
 * questions and only a count answers the second one.
 *
 * What it counts, and why each one blocks a different flag:
 *
 *   1. `users.cvUrl` still holding an `http...` download URL. Those URLs
 *      carry a long-lived Storage token on a profile document, so they stay
 *      readable by anyone who ever saw the value, even after the profile is
 *      hidden. `ENABLE_LEGACY_CV_URL_MIGRATION=true` drains them. The final
 *      rules already reject any new `http` value (`ownerCvUrlChangeIsSafe`
 *      requires `gs://`), so a non-zero count here is residue, never inflow.
 *
 *   2. `users.followersList` / `users.followingsList` arrays, plus the
 *      `following` / `followers` subcollections. `MIRROR_LEGACY_FOLLOW_ARRAYS`
 *      keeps writing the arrays for clients that read them;
 *      `ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP` deletes them. Flipping the second
 *      one while an installed client still reads the arrays empties that
 *      client's follow lists silently, so the edge counts matter more than
 *      the account count.
 *
 *   3. `users.fcmToken`, drained by `migrateLegacyFcmTokens` into
 *      `user_push_tokens`. That migration needs no flag, so a non-zero count
 *      means the scheduled drain has not caught up rather than a decision
 *      pending.
 *
 * It also reports the `migration_state` checkpoints, because
 * `backfillPublicProfiles` writes to a *different* checkpoint document once
 * `ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP=true`
 * (`public_profiles_follow_cleanup_v1` instead of
 * `public_profiles_and_follows_v5`). A closure is only finished when that
 * second document reports `completed: true`.
 *
 * Reads only: collection scans and one `migration_state` read. No writes. The
 * ops credential is not read-only in itself; this script simply never writes.
 *
 * Usage:
 *   node scripts/check-legacy-profile-residue.mjs \
 *     --project adfoot-production \
 *     --service-account .credentials/adfoot-production-ops.json
 *
 *   Add --require-clean to turn the report into a release gate: it then exits
 *   non-zero while any residue remains, for use after the flags are flipped
 *   to confirm the drain actually finished.
 */
import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import {cert, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

const argv = process.argv.slice(2);
const option = (name) => {
  const index = argv.indexOf(name);
  return index < 0 ? undefined : argv[index + 1];
};
const projectId = option("--project");
const keyPath = option("--service-account");
const requireClean = argv.includes("--require-clean");
if (!["adfoot-staging", "adfoot-production"].includes(projectId) || !keyPath) {
  throw new Error("Usage: node scripts/check-legacy-profile-residue.mjs --project adfoot-staging|adfoot-production --service-account PATH [--require-clean]");
}
const account = JSON.parse(await readFile(resolve(keyPath), "utf8"));
if (account.type !== "service_account" || account.project_id !== projectId) {
  throw new Error("Service account project_id does not match --project");
}

const app = initializeApp({credential: cert(account), projectId});
const db = getFirestore(app);

const users = (await db.collection("users").get()).docs;

const legacyCvUrls = [];
const legacyFollowArrays = [];
const legacyFcmTokens = [];
let legacyFollowEdges = 0;
let relationSubcollectionDocs = 0;

for (const user of users) {
  const data = user.data();

  if (typeof data.cvUrl === "string" && data.cvUrl.startsWith("http")) {
    legacyCvUrls.push(user.id);
  }

  const followers = Array.isArray(data.followersList) ?
    data.followersList.length :
    null;
  const followings = Array.isArray(data.followingsList) ?
    data.followingsList.length :
    null;
  if (followers !== null || followings !== null) {
    legacyFollowArrays.push({uid: user.id, followers, followings});
    legacyFollowEdges += (followers ?? 0) + (followings ?? 0);
  }

  if (typeof data.fcmToken === "string" && data.fcmToken.length > 0) {
    legacyFcmTokens.push(user.id);
  }

  for (const sub of ["following", "followers"]) {
    relationSubcollectionDocs +=
      (await user.ref.collection(sub).count().get()).data().count;
  }
}

const migrationState = {};
for (const doc of (await db.collection("migration_state").get()).docs) {
  migrationState[doc.id] = doc.data().completed === true;
}

const blockers = [];
if (legacyCvUrls.length) {
  blockers.push(`${legacyCvUrls.length} profil(s) exposent encore une URL CV avec jeton (ENABLE_LEGACY_CV_URL_MIGRATION)`);
}
if (legacyFollowArrays.length) {
  blockers.push(`${legacyFollowArrays.length} profil(s) portent encore les tableaux de suivi (${legacyFollowEdges} arete(s)) (ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP)`);
}
if (legacyFcmTokens.length) {
  blockers.push(`${legacyFcmTokens.length} profil(s) portent encore fcmToken (migrateLegacyFcmTokens, sans flag)`);
}
if (migrationState.public_profiles_and_follows_v5 !== true) {
  blockers.push("public_profiles_and_follows_v5 n'est pas completed");
}
if (migrationState.conversation_sort_dates_v1 !== true) {
  blockers.push("conversation_sort_dates_v1 n'est pas completed");
}

console.log(JSON.stringify({
  projectId,
  accounts: users.length,
  residue: {
    legacyCvUrlAccounts: legacyCvUrls.length,
    legacyCvUrlUids: legacyCvUrls,
    legacyFollowArrayAccounts: legacyFollowArrays.length,
    legacyFollowArrayEdges: legacyFollowEdges,
    legacyFollowArrays,
    relationSubcollectionDocs,
    legacyFcmTokenAccounts: legacyFcmTokens.length,
  },
  migrationState,
  blockers,
  // `public_profiles_follow_cleanup_v1` only exists once the cleanup flag has
  // been deployed and the scheduled backfill has run at least once.
  cleanupCheckpointPresent:
    Object.prototype.hasOwnProperty.call(
      migrationState, "public_profiles_follow_cleanup_v1"),
}, null, 2));

if (requireClean && blockers.length) {
  console.error("\nResidu legacy present; la fermeture de la migration n'est pas terminee.");
  process.exitCode = 1;
}
