/* eslint-disable */
/**
 * One-off backfill for the users/{uid}/private/contact migration.
 *
 * What it does, in order:
 *   1. For every users/{uid} doc: copies phone, email, authDisabledReason
 *      into users/{uid}/private/contact, copies profileVerificationNote
 *      into users/{uid}/private/adminNotes, then deletes those four keys
 *      from the main doc. (birthDate/cvUrl stay on the main doc — see
 *      firestore.rules for why.)
 *   2. Strips email/phone from every offres/{id}.candidats[] and
 *      events/{id}.participants[] entry (they were embedded there via
 *      AppUser.toEmbeddedMap() and are readable by any signed-in active
 *      user through those collections' rules).
 *   3. Strips email/phone from users/{uid}.joueursSuivis[]/clubsSuivis[]
 *      (same embedding leak, via follow lists).
 *
 * Idempotent: a user already migrated (private/contact already has the
 * data and the main doc no longer has the keys) is skipped on re-run.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/adfoot-staging-key.json \
 *     node functions/scripts/migrate_private_user_fields.js --project adfoot-staging --dry-run
 *
 *   (drop --dry-run once the staging run looks correct, then repeat
 *   against adfoot-production with its own service account key)
 */

const admin = require("firebase-admin");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const projectArgIndex = args.indexOf("--project");
const projectId = projectArgIndex >= 0 ? args[projectArgIndex + 1] : null;

if (!projectId) {
  console.error("Usage: node migrate_private_user_fields.js --project <firebase-project-id> [--dry-run]");
  process.exit(1);
}

admin.initializeApp({projectId});
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const USER_BATCH_SIZE = 400;
const MAIN_DOC_SENSITIVE_KEYS = ["phone", "email", "authDisabledReason"];
const ADMIN_NOTE_KEY = "profileVerificationNote";

const stats = {
  usersScanned: 0,
  usersMigrated: 0,
  usersSkipped: 0,
  usersFailed: 0,
  offresScanned: 0,
  offresCleaned: 0,
  eventsScanned: 0,
  eventsCleaned: 0,
  followListsScanned: 0,
  followListsCleaned: 0,
};

function stripEmailPhone(entry) {
  if (!entry || typeof entry !== "object") {
    return {entry, changed: false};
  }
  if (!("email" in entry) && !("phone" in entry)) {
    return {entry, changed: false};
  }
  const cleaned = {...entry};
  delete cleaned.email;
  delete cleaned.phone;
  return {entry: cleaned, changed: true};
}

function stripEmailPhoneFromList(list) {
  if (!Array.isArray(list)) {
    return {list, changed: false};
  }
  let changed = false;
  const cleaned = list.map((item) => {
    const result = stripEmailPhone(item);
    if (result.changed) changed = true;
    return result.entry;
  });
  return {list: cleaned, changed};
}

async function migrateUsers() {
  let lastDoc = null;
  for (;;) {
    let query = db.collection("users").orderBy("__name__").limit(USER_BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      stats.usersScanned++;
      const uid = doc.id;
      const data = doc.data();

      const hasSensitiveMainDocField = MAIN_DOC_SENSITIVE_KEYS.some((k) => k in data);
      const hasAdminNote = ADMIN_NOTE_KEY in data;

      if (!hasSensitiveMainDocField && !hasAdminNote) {
        stats.usersSkipped++;
        continue;
      }

      try {
        const contactPatch = {};
        for (const key of MAIN_DOC_SENSITIVE_KEYS) {
          if (key in data) contactPatch[key] = data[key];
        }
        const adminNotePatch = hasAdminNote ? {[ADMIN_NOTE_KEY]: data[ADMIN_NOTE_KEY]} : null;

        const mainDocDelete = {};
        for (const key of MAIN_DOC_SENSITIVE_KEYS) {
          if (key in data) mainDocDelete[key] = FieldValue.delete();
        }
        if (hasAdminNote) mainDocDelete[ADMIN_NOTE_KEY] = FieldValue.delete();

        if (dryRun) {
          console.log(`[dry-run] would migrate users/${uid}:`, {
            contactPatch: Object.keys(contactPatch),
            adminNotePatch: adminNotePatch ? Object.keys(adminNotePatch) : [],
          });
        } else {
          const batch = db.batch();
          if (Object.keys(contactPatch).length > 0) {
            batch.set(
              db.collection("users").doc(uid).collection("private").doc("contact"),
              contactPatch,
              {merge: true},
            );
          }
          if (adminNotePatch) {
            batch.set(
              db.collection("users").doc(uid).collection("private").doc("adminNotes"),
              adminNotePatch,
              {merge: true},
            );
          }
          batch.update(doc.ref, mainDocDelete);
          await batch.commit();
        }
        stats.usersMigrated++;
      } catch (error) {
        stats.usersFailed++;
        console.error(`Failed to migrate users/${uid}:`, error);
      }
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < USER_BATCH_SIZE) break;
  }
}

async function cleanEmbeddedListCollection(collectionName, arrayField) {
  const snap = await db.collection(collectionName).get();
  for (const doc of snap.docs) {
    const counterKey = collectionName === "offres" ? "offresScanned" : "eventsScanned";
    const cleanedKey = collectionName === "offres" ? "offresCleaned" : "eventsCleaned";
    stats[counterKey]++;

    const data = doc.data();
    const {list, changed} = stripEmailPhoneFromList(data[arrayField]);
    if (!changed) continue;

    if (dryRun) {
      console.log(`[dry-run] would strip email/phone from ${collectionName}/${doc.id}.${arrayField}`);
    } else {
      await doc.ref.update({[arrayField]: list});
    }
    stats[cleanedKey]++;
  }
}

async function cleanFollowLists() {
  let lastDoc = null;
  for (;;) {
    let query = db.collection("users").orderBy("__name__").limit(USER_BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      stats.followListsScanned++;
      const data = doc.data();
      const joueurs = stripEmailPhoneFromList(data.joueursSuivis);
      const clubs = stripEmailPhoneFromList(data.clubsSuivis);
      if (!joueurs.changed && !clubs.changed) continue;

      const patch = {};
      if (joueurs.changed) patch.joueursSuivis = joueurs.list;
      if (clubs.changed) patch.clubsSuivis = clubs.list;

      if (dryRun) {
        console.log(`[dry-run] would strip email/phone from users/${doc.id} follow lists:`, Object.keys(patch));
      } else {
        await doc.ref.update(patch);
      }
      stats.followListsCleaned++;
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < USER_BATCH_SIZE) break;
  }
}

async function main() {
  console.log(`Starting private-field backfill on project "${projectId}"${dryRun ? " (dry run)" : ""}`);

  await migrateUsers();
  await cleanEmbeddedListCollection("offres", "candidats");
  await cleanEmbeddedListCollection("events", "participants");
  await cleanFollowLists();

  console.log("Done.", stats);
  if (stats.usersFailed > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("Backfill failed:", error);
  process.exit(1);
});
