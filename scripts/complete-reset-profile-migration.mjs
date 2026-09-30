#!/usr/bin/env node

// Completes the v3 profile projection after a test-data reset. Safe only when
// all legacy follow arrays and relation collections are empty.
import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import {cert, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const argv = process.argv.slice(2);
const option = (name) => argv[argv.indexOf(name) + 1];
const projectId = option("--project");
const keyPath = option("--service-account");
if (!["adfoot-staging", "adfoot-production"].includes(projectId) ||
    !keyPath || option("--confirm-project") !== projectId) {
  throw new Error("Usage: node scripts/complete-reset-profile-migration.mjs --project PROJECT --service-account PATH --confirm-project PROJECT");
}
const account = JSON.parse(await readFile(resolve(keyPath), "utf8"));
if (account.type !== "service_account" || account.project_id !== projectId) {
  throw new Error("Service account project_id does not match --project");
}
// The compiled Functions may resolve their own nested firebase-admin copy.
// Give that copy the same explicit identity through ADC as this script.
process.env.GOOGLE_APPLICATION_CREDENTIALS = resolve(keyPath);
process.env.GCLOUD_PROJECT = projectId;
initializeApp({credential: cert(account), projectId,
  storageBucket: `${projectId}.firebasestorage.app`});
const db = getFirestore();
const users = (await db.collection("users").get()).docs;
for (const user of users) {
  const data = user.data();
  if ((data.followingsList?.length ?? 0) !== 0 ||
      (data.followersList?.length ?? 0) !== 0 ||
      (await user.ref.collection("following").limit(1).get()).size ||
      (await user.ref.collection("followers").limit(1).get()).size) {
    throw new Error("Legacy follow data remains; scheduled migration must handle it");
  }
}
const {syncPublicProfile} = await import("../functions/lib/public_profile_projection.js");
for (const user of users) await syncPublicProfile(user.id);
const expected = users.filter((user) => user.data().authDisabled !== true &&
  user.data().estActif !== false).length;
const actual = (await db.collection("public_profiles").count().get()).data().count;
if (actual !== expected) {
  throw new Error(`Projection count mismatch: expected ${expected}, got ${actual}`);
}
await db.collection("migration_state").doc("public_profiles_and_follows_v3").set({
  completed: true,
  completedAt: FieldValue.serverTimestamp(),
  source: "reset-test-data",
  processed: users.length,
});
console.log(`${projectId}: v3 completed; ${users.length} accounts, ${actual} projections`);
