#!/usr/bin/env node

// Resets disposable test data, preserving operator accounts and configuration.
// Dry run by default. An --apply run first downloads a local, ignored backup.
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {resolve, join, dirname} from "node:path";
import {cert, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const argv = process.argv.slice(2);
const value = (name) => {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : undefined;
};
const projectId = value("--project");
const keyPath = value("--service-account");
const apply = argv.includes("--apply");
if (!keyPath || !["adfoot-staging", "adfoot-production"].includes(projectId) ||
    (apply && value("--confirm-project") !== projectId)) {
  throw new Error("Usage: node scripts/reset-test-data.mjs --project adfoot-staging|adfoot-production --service-account PATH [--apply --confirm-project SAME_PROJECT]");
}
const account = JSON.parse(await readFile(resolve(keyPath), "utf8"));
if (account.type !== "service_account" || account.project_id !== projectId) {
  throw new Error("Service account project_id does not match --project");
}

const app = initializeApp({
  credential: cert(account), projectId,
  storageBucket: `${projectId}.firebasestorage.app`,
});
const db = getFirestore(app);
const auth = getAuth(app);
const bucket = getStorage(app).bucket();
const personalPrefixes = ["profilePhotos/", "cvs/"];
const contentPrefixes = ["eventFlyers/", "videos/", "mp4/", "thumbnails/"];
const preservedEmails = new Set([
  "amidoudev@gmail.com", "amidou.kone.pro@gmail.com",
]);
const privileged = (record) => ["admin", "platformAdmin", "superAdmin"]
  .some((key) => record.customClaims?.[key] === true);

const allowedRootCollections = new Set([
  "users", "public_profiles", "user_push_tokens", "videos", "offres",
  "events", "conversations", "blocks", "contact_intakes",
  "contact_intake_limits", "push_campaigns", "push_message_receipts",
  "cv_view_tickets", "cv_view_limits", "migration_state",
  "account_deletion_pending", "client_logs", "video_action_logs",
  "video_share_limits", "log_call_limits", "push_call_limits",
  "videoModerationDecisions", "config",
]);
const allCollections = await db.listCollections();
const unknown = allCollections.map((collection) => collection.id)
  .filter((id) => !allowedRootCollections.has(id));
if (unknown.length) throw new Error(`Unknown root collections: ${unknown.join(", ")}`);

const users = (await db.collection("users").get()).docs;
const profileByUid = new Map(users.map((doc) => [doc.id, doc.data()]));
const authUsers = [];
let pageToken;
do {
  const page = await auth.listUsers(1000, pageToken);
  authUsers.push(...page.users);
  pageToken = page.pageToken;
} while (pageToken);
const preserve = new Set();
for (const user of authUsers) {
  if (privileged(user) || preservedEmails.has(user.email?.toLowerCase())) {
    preserve.add(user.uid);
  }
}
for (const [uid, data] of profileByUid) {
  if (data.role === "admin" || data.admin === true ||
      data.platformAdmin === true || data.superAdmin === true) preserve.add(uid);
}
for (const email of preservedEmails) {
  if (!authUsers.some((user) => user.email?.toLowerCase() === email)) {
    throw new Error(`Required preserved account absent: ${email}`);
  }
}
const deletableUsers = authUsers.filter((user) => !preserve.has(user.uid));
const protectedCollections = new Set(["config"]);
const rootCounts = {};
for (const collection of allCollections) {
  rootCounts[collection.id] = (await collection.count().get()).data().count;
}
const plan = {
  projectId, mode: apply ? "apply" : "dry-run",
  authUsers: authUsers.length, preserveAccounts: preserve.size,
  deleteAuthUsers: deletableUsers.length,
  preservedEmails: authUsers.filter((user) => preserve.has(user.uid))
    .map((user) => user.email ?? "(no email)"),
  preservedRootCollections: [...protectedCollections], rootCounts,
};
console.log(JSON.stringify(plan, null, 2));
if (!apply) process.exit(0);

const stamp = new Date().toISOString().replaceAll(":", "-");
const backupDir = resolve("artifacts", "reset-backups", `${projectId}-${stamp}`);
await mkdir(backupDir, {recursive: true});
await writeFile(join(backupDir, "manifest.json"), JSON.stringify(plan, null, 2));
await writeFile(join(backupDir, "auth-users.json"), JSON.stringify(authUsers.map((user) => ({
  uid: user.uid, email: user.email, disabled: user.disabled,
  emailVerified: user.emailVerified, customClaims: user.customClaims,
})), null, 2));

// Backup all root documents, plus the known nested collections containing
// user data. Firestore values are serialized for audit, not automatic replay.
for (const collection of allCollections) {
  const docs = (await collection.get()).docs;
  const rows = docs.map((doc) => ({path: doc.ref.path, data: doc.data()}));
  if (collection.id === "users") {
    for (const doc of docs) {
      for (const nested of await doc.ref.listCollections()) {
        const nestedDocs = (await nested.get()).docs;
        rows.push(...nestedDocs.map((child) => ({
          path: child.ref.path, data: child.data(),
        })));
      }
    }
  }
  if (collection.id === "conversations" ||
      collection.id === "push_message_receipts") {
    for (const doc of docs) {
      const messages = await doc.ref.collection("messages").get();
      rows.push(...messages.docs.map((child) => ({
        path: child.ref.path, data: child.data(),
      })));
    }
  }
  await writeFile(join(backupDir, `${collection.id}.json`), JSON.stringify(rows, null, 2));
}

const objectsToDelete = [];
for (const prefix of [...personalPrefixes, ...contentPrefixes]) {
  let token;
  do {
    const [files, , response] = await bucket.getFiles({
      prefix, autoPaginate: false, maxResults: 1000, pageToken: token,
    });
    for (const file of files) {
      const ownerUid = personalPrefixes.includes(prefix) ?
        file.name.slice(prefix.length).split("/")[0] : null;
      if (ownerUid && preserve.has(ownerUid)) continue;
      const destination = join(backupDir, "storage", ...file.name.split("/"));
      await mkdir(dirname(destination), {recursive: true});
      await file.download({destination});
      objectsToDelete.push(file);
    }
    token = response?.nextPageToken;
  } while (token);
}
await writeFile(join(backupDir, "storage-delete-list.json"),
  JSON.stringify(objectsToDelete.map((file) => file.name), null, 2));
console.log(`Backup complete: ${backupDir}`);

// Delete content first, then user documents and Auth. Each Firestore deletion
// is recursive, so nested messages and private documents cannot be orphaned.
for (const collection of allCollections) {
  if (protectedCollections.has(collection.id)) continue;
  if (["users", "public_profiles", "user_push_tokens"].includes(collection.id)) {
    for (const doc of (await collection.get()).docs) {
      if (!preserve.has(doc.id)) await db.recursiveDelete(doc.ref);
    }
  } else {
    await db.recursiveDelete(collection);
  }
}
for (const uid of preserve) {
  const ref = db.collection("users").doc(uid);
  for (const name of ["following", "followers"]) {
    await db.recursiveDelete(ref.collection(name));
  }
  if (profileByUid.has(uid)) {
    await ref.update({
      followers: 0, followings: 0,
      followersList: [], followingsList: [],
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await db.collection("user_push_tokens").doc(uid).delete();
}
for (let index = 0; index < deletableUsers.length; index += 1000) {
  const result = await auth.deleteUsers(deletableUsers.slice(index, index + 1000)
    .map((user) => user.uid));
  if (result.failureCount) {
    throw new Error(`Auth deletion failed for ${result.failureCount} accounts`);
  }
}
for (const file of objectsToDelete) await file.delete();
console.log(`Reset complete: ${projectId}; backup: ${backupDir}`);
