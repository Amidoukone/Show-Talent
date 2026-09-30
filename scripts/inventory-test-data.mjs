#!/usr/bin/env node

// Read-only inventory before a test-data reset. Prints aggregate counts only.
import {readFile} from "node:fs/promises";
import {resolve} from "node:path";
import {cert, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== "--project" ||
    args[2] !== "--service-account" ||
    !["adfoot-staging", "adfoot-production"].includes(args[1])) {
  throw new Error("Usage: node scripts/inventory-test-data.mjs --project adfoot-staging|adfoot-production --service-account PATH");
}

const projectId = args[1];
const account = JSON.parse(await readFile(resolve(args[3]), "utf8"));
if (account.type !== "service_account" || account.project_id !== projectId) {
  throw new Error("Service account project_id does not match --project");
}

const app = initializeApp({
  credential: cert(account),
  projectId,
  storageBucket: `${projectId}.firebasestorage.app`,
});
const db = getFirestore(app);
const auth = getAuth(app);
const bucket = getStorage(app).bucket();

const collections = await db.listCollections();
const collectionCounts = {};
for (const collection of collections.sort((a, b) => a.id.localeCompare(b.id))) {
  collectionCounts[collection.id] = (await collection.count().get()).data().count;
}
const profileDocs = (await db.collection("users").get()).docs;
const projectedIds = new Set((await db.collection("public_profiles").get())
  .docs.map((doc) => doc.id));
const expectedProjected = profileDocs.filter((doc) =>
  doc.data().authDisabled !== true && doc.data().estActif !== false);
const projectionCheck = {
  expected: expectedProjected.length,
  present: projectedIds.size,
  missing: expectedProjected.filter((doc) => !projectedIds.has(doc.id)).length,
  orphaned: [...projectedIds].filter((id) =>
    !profileDocs.some((doc) => doc.id === id)).length,
};
const migrationState = {};
for (const doc of (await db.collection("migration_state").get()).docs) {
  migrationState[doc.id] = {completed: doc.data().completed === true};
}

let authUsers = 0;
let privilegedAuthUsers = 0;
const preservedCandidates = [];
let nextPageToken;
do {
  const page = await auth.listUsers(1000, nextPageToken);
  authUsers += page.users.length;
  privilegedAuthUsers += page.users.filter((user) =>
    ["admin", "platformAdmin", "superAdmin"].some((key) =>
      user.customClaims?.[key] === true)).length;
  for (const user of page.users) {
    if (/^amidou(?:dev|\.kone\.pro)/i.test(user.email ?? "")) {
      const profile = await db.collection("users").doc(user.uid).get();
      preservedCandidates.push({
        email: user.email,
        role: profile.data()?.role ?? null,
        adminClaim: ["admin", "platformAdmin", "superAdmin"].some((key) =>
          user.customClaims?.[key] === true),
      });
    }
  }
  nextPageToken = page.pageToken;
} while (nextPageToken);

const storagePrefixes = [
  "profilePhotos/", "cvs/", "eventFlyers/", "videos/", "mp4/", "thumbnails/",
];
const storageCounts = {};
for (const prefix of storagePrefixes) {
  let count = 0;
  let bytes = 0;
  let pageToken;
  do {
    const [files, , response] = await bucket.getFiles({
      prefix, autoPaginate: false, maxResults: 1000, pageToken,
    });
    for (const file of files) {
      count += 1;
      bytes += Number(file.metadata?.size ?? 0);
    }
    pageToken = response?.nextPageToken;
  } while (pageToken);
  storageCounts[prefix] = {objects: count, bytes};
}

console.log(JSON.stringify({
  projectId,
  firestore: collectionCounts,
  projectionCheck,
  migrationState,
  auth: {users: authUsers, privilegedClaimUsers: privilegedAuthUsers},
  preservedCandidates,
  storageBucket: bucket.name,
  storage: storageCounts,
}, null, 2));
