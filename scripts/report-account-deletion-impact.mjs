#!/usr/bin/env node

/**
 * Inventaire avant suppression : ce que chaque compte emporterait avec lui.
 *
 * Lecture seule, strictement. Les collections et les champs interrogés sont
 * ceux de `purgeAccountData` (functions/src/admin_account_actions.ts), pas une
 * liste écrite de mémoire : videos.uid, offres.recruteur.uid,
 * events.organisateur.uid, conversations.utilisateurIds, et les deux
 * sous-documents privés.
 *
 * La colonne `suivis` compte les documents d'AUTRES comptes que
 * cleanupFollowReferences() réécrit : chaque profil dont followersList ou
 * followingsList contient la cible perd l'entrée et voit son compteur
 * décrémenté. C'est le seul effet de la suppression qui sort du compte
 * supprimé, et celui qu'aucun écran n'annonce.
 *
 * Dit aussi si le callable `deleteManagedAccount` accepterait la cible.
 * Attention : ce portillon n'est PAS celui des autres actions admin. La
 * suppression n'appelle que `assertSafeAdminMutation`, jamais
 * `assertManagedTarget` — elle ne demande donc ni `createdByAdmin` ni un rôle
 * géré. Elle refuse trois choses : un rôle `admin`, des claims privilégiés
 * (`admin`, `platformAdmin` ou `superAdmin`), et l'administrateur appelant
 * lui-même. Ce dernier cas dépend de qui appelle et ne peut pas être décidé
 * ici.
 */

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const projectId = process.argv.includes('--staging') ? 'adfoot-staging' : 'adfoot-production';
const credentialsPath = path.join(repoRoot, '.credentials', `${projectId}-ops.json`);

if (!existsSync(credentialsPath)) {
  console.error(`Credentials introuvables : ${credentialsPath}`);
  process.exit(1);
}

const serviceAccount = JSON.parse(await readFile(credentialsPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount), projectId });

const db = getFirestore();
const auth = getAuth();

const [users, videos, offres, events, conversations] = await Promise.all([
  db.collection('users').get(),
  db.collection('videos').get(),
  db.collection('offres').get(),
  db.collection('events').get(),
  db.collection('conversations').get(),
]);

function ownerOf(data, pathParts) {
  let current = data;
  for (const part of pathParts) {
    if (current === null || typeof current !== 'object') return null;
    current = current[part];
  }
  return typeof current === 'string' ? current : null;
}

const byOwner = new Map();
function bump(uid, key, extra) {
  if (!uid) return;
  if (!byOwner.has(uid)) {
    byOwner.set(uid, { videos: 0, offres: 0, events: 0, conversations: 0, videoTitles: [] });
  }
  const row = byOwner.get(uid);
  row[key] += 1;
  if (extra) row.videoTitles.push(extra);
}

videos.forEach((doc) => {
  const data = doc.data() ?? {};
  const title = String(data.titre ?? data.title ?? doc.id).slice(0, 40);
  bump(ownerOf(data, ['uid']), 'videos', `${title} [${data.status ?? '?'}]`);
});
offres.forEach((doc) => bump(ownerOf(doc.data() ?? {}, ['recruteur', 'uid']), 'offres'));
events.forEach((doc) => bump(ownerOf(doc.data() ?? {}, ['organisateur', 'uid']), 'events'));
conversations.forEach((doc) => {
  const ids = (doc.data() ?? {}).utilisateurIds;
  if (!Array.isArray(ids)) return;
  for (const id of ids) bump(String(id), 'conversations');
});

// Documents d'autres comptes que cleanupFollowReferences() réécrirait. Calculé
// sur l'instantané `users` déjà lu : aucune lecture supplémentaire, donc aucun
// coût en plus de celui du rapport.
const followRefs = new Map();
function bumpFollowRef(uid, owner) {
  if (typeof uid !== 'string' || uid === '' || uid === owner) return;
  followRefs.set(uid, (followRefs.get(uid) ?? 0) + 1);
}

users.forEach((doc) => {
  const data = doc.data() ?? {};
  const seen = new Set();
  for (const field of ['followersList', 'followingsList']) {
    const list = data[field];
    if (!Array.isArray(list)) continue;
    // Un même profil peut citer la cible dans les deux listes ; il ne sera
    // réécrit qu'une fois par liste, mais c'est bien un seul document touché.
    for (const id of list) {
      if (typeof id !== 'string' || seen.has(id)) continue;
      seen.add(id);
      bumpFollowRef(id, doc.id);
    }
  }
});

const rows = [];
let orphanVideos = 0;
const knownUids = new Set(users.docs.map((doc) => doc.id));

for (const [uid, row] of byOwner) {
  if (!knownUids.has(uid)) orphanVideos += row.videos;
}

for (const doc of users.docs) {
  const data = doc.data() ?? {};
  const uid = doc.id;
  const role = String(data.role ?? '').trim().toLowerCase();
  const owned = byOwner.get(uid) ?? { videos: 0, offres: 0, events: 0, conversations: 0, videoTitles: [] };

  let claims = null;
  let authExists = true;
  try {
    const record = await auth.getUser(uid);
    claims = record.customClaims ?? null;
  } catch (error) {
    authExists = false;
  }

  // isPrivilegedClaims() dans functions/src/admin_account_support.ts.
  const privileged = Boolean(
    claims && (claims.admin === true || claims.platformAdmin === true || claims.superAdmin === true),
  );
  const deletable = role !== 'admin' && !privileged;

  rows.push({
    uid: uid.slice(0, 8),
    role: role || '?',
    nom: String(data.nom ?? '').slice(0, 22),
    admin: data.createdByAdmin === true ? 'oui' : 'non',
    auth: authExists ? 'ok' : 'ABSENT',
    videos: owned.videos,
    offres: owned.offres,
    events: owned.events,
    convs: owned.conversations,
    suivis: followRefs.get(uid) ?? 0,
    supprimable: deletable ? 'oui' : 'NON',
    titles: owned.videoTitles.join(' | '),
  });
}

console.log('');
console.log(`Projet : ${projectId} — lecture seule`);
console.log(
  `${users.size} comptes, ${videos.size} vidéos, ${offres.size} offres, ` +
    `${events.size} événements, ${conversations.size} conversations.`,
);
console.log('');
console.table(rows.map(({ titles, ...rest }) => rest));

const withVideos = rows.filter((row) => row.videos > 0);
if (withVideos.length > 0) {
  console.log('');
  console.log('Vidéos qui partiraient avec leur propriétaire :');
  for (const row of rows) {
    if (row.videos > 0) console.log(`- ${row.uid} (${row.role}) : ${row.titles}`);
  }
}

if (orphanVideos > 0) {
  console.log('');
  console.log(`${orphanVideos} vidéo(s) sans compte propriétaire connu.`);
}

const followTouching = rows.filter((row) => row.suivis > 0);
if (followTouching.length > 0) {
  console.log('');
  console.log('Profils tiers réécrits par cleanupFollowReferences() :');
  for (const row of followTouching) {
    console.log(`- ${row.uid} (${row.role}) : ${row.suivis} document(s) d'autres comptes`);
  }
}

const refused = rows.filter((row) => row.supprimable === 'NON');
console.log('');
console.log(
  `${rows.length - refused.length} compte(s) supprimables par le callable, ` +
    `${refused.length} refusé(s) : ${refused.map((row) => `${row.uid} (${row.role})`).join(', ') || 'aucun'}.`,
);
console.log(
  "L'administrateur qui appelle ne peut pas se supprimer lui-même : ce refus " +
    'dépend de la session et ne figure pas dans la colonne.',
);
process.exit(0);
