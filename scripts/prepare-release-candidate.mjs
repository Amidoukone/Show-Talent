#!/usr/bin/env node
// Explicit target and matching credentials required. Read-only by default.
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {isDeepStrictEqual} from 'node:util';

const args = process.argv.slice(2);
let credentials;
let environment;
let apply = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--apply') apply = true;
  else if (args[i] === '--credentials' && args[i + 1]) credentials = resolve(args[++i]);
  else if (args[i] === '--environment' && args[i + 1]) environment = args[++i];
  else throw new Error(`Unknown or incomplete argument: ${args[i]}`);
}
if (!credentials) throw new Error('--credentials is required');
if (!['staging', 'production'].includes(environment)) throw new Error('--environment staging|production is required');
const account = JSON.parse(await readFile(credentials, 'utf8'));
const projectId = `adfoot-${environment}`;
if (account.type !== 'service_account' || account.project_id !== projectId) {
  throw new Error(`A ${projectId} service account is required`);
}
if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Unexpected emulator configuration');
process.env.GOOGLE_APPLICATION_CREDENTIALS = credentials;
process.env.GCLOUD_PROJECT = projectId;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId, storageBucket: `${projectId}.firebasestorage.app`});
process.env.ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP = 'false';
const require = createRequire(import.meta.url);
const {db} = require('../functions/lib/firebase.js');
const {buildPublicProfileProjection} = require('../functions/lib/public_profile_projection.js');
const {deriveBirthYearAndMinorStatus} = require('../functions/lib/user_search_fields.js');
const migrationId = 'public_profiles_and_follows_v5';

if (apply) {
  const {backfillPublicProfiles, backfillConversationSortDates} = require('../functions/lib/cleanup.js');
  for (const [id, handler] of [[migrationId, backfillPublicProfiles], ['conversation_sort_dates_v1', backfillConversationSortDates]]) {
    let completed = false;
    for (let batch = 0; batch < 100; batch++) {
      if ((await db.collection('migration_state').doc(id).get()).data()?.completed === true) {
        completed = true;
        break;
      }
      await handler.run({jobName: `manual-${environment}-candidate`, scheduleTime: new Date().toISOString()});
    }
    if (!completed) throw new Error(`Migration not complete after 100 pages: ${id}`);
  }
}

const readCollection = async (name) => {
  const snapshot = await db.collection(name).limit(5001).get();
  if (snapshot.size > 5000) throw new Error(`Candidate audit limit exceeded: ${name}`);
  return new Map(snapshot.docs.map((doc) => [doc.id, doc.data()]));
};
const [users, profiles, videos, conversations] = await Promise.all(
  ['users', 'public_profiles', 'videos', 'conversations'].map(readCollection),
);
const issues = {};
const note = (kind) => { issues[kind] = (issues[kind] ?? 0) + 1; };
for (const [uid, data] of users) {
  const contact = (await db.collection('users').doc(uid).collection('private').doc('contact').get()).data();
  const age = deriveBirthYearAndMinorStatus(contact?.birthDate);
  const isMinor = age?.isMinor === true || (age == null &&
    (contact?.birthDate != null || data.isMinorProfile === true || data.minorProtectionRequired === true));
  if (data.isMinorProfile !== isMinor) note('ageMarker');
  if (!isDeepStrictEqual(profiles.get(uid) ?? null, buildPublicProfileProjection(uid, data, isMinor))) note('projection');
  if (data.minorMediaPurgePending === true) note('pendingMediaPurge');
}
for (const uid of profiles.keys()) if (!users.has(uid)) note('orphanProjection');
for (const data of videos.values()) {
  if (data.publicFeedVisible !== (users.get(data.uid)?.isMinorProfile === false)) note('videoAudience');
}
for (const data of conversations.values()) {
  const ids = data.utilisateurIds;
  const expected = Array.isArray(ids) && ids.length === 2 &&
    ids.every((uid) => users.get(uid)?.isMinorProfile === false) ? ids : [];
  if (!isDeepStrictEqual(data.readableBy, expected)) note('conversationAudience');
  if (!Object.hasOwn(data, 'lastMessageDate')) note('conversationSortDate');
}
const migration = (await db.collection('migration_state').doc(migrationId).get()).data();
console.log(JSON.stringify({projectId, mode: apply ? 'apply-and-verify' : 'read-only',
  counts: {users: users.size, profiles: profiles.size, videos: videos.size, conversations: conversations.size},
  migrationId, migrationComplete: migration?.completed === true, issues}, null, 2));
if (Object.keys(issues).length || migration?.completed !== true) process.exitCode = 1;
await db.terminate();
