/**
 * Authorization tests for firestore.rules, run against the real rules engine.
 *
 * The Dart guardrails assert on the *text* of firestore.rules; this asserts on
 * its behaviour. Both are needed: the candidate-list and message rules
 * hardened here are the kind whose wording looks right and whose evaluation
 * does not.
 *
 * Run:  npm run rules:test
 * (starts the Firestore emulator, needs Java on PATH)
 */

import path, { dirname } from 'path';
import { fileURLToPath } from 'url';
import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc,
  serverTimestamp, increment, arrayUnion,
} from 'firebase/firestore';

const REPO = path.resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const RECRUITER = '1CpBpamIhJR5Agz5wG5fnX6jMsl2';
const PLAYER = 'RuLh6bcq6fhHYCD4chuu6ryI8Cl2';
const RIVAL = 'zDuzNuDD4LYFMKv0bBhTrNT08sb2';
const OUTSIDER = 'wQwEeVMa5reprTpScRlm7rWy6Ol1';

const OFFER = 'offer_1';
const EVENT = 'event_1';
const CONV = 'conv_1';

function embedded(uid, role) {
  return {
    uid, nom: 'N-' + uid.slice(0, 4), role,
    photoProfil: '', estActif: true, authDisabled: false,
    emailVerified: true, createdByAdmin: true, profileVerified: false,
    profilePublic: true, allowMessages: true,
  };
}

const results = [];
async function check(name, expectation, fn) {
  try {
    await (expectation === 'allow' ? assertSucceeds(fn()) : assertFails(fn()));
    results.push({ name, expectation, ok: true });
  } catch (error) {
    results.push({ name, expectation, ok: false, error: String(error.message || error).slice(0, 160) });
  }
}

const env = await initializeTestEnvironment({
  projectId: 'demo-adfoot',
  firestore: {
    host: '127.0.0.1',
    port: 8080,
    rules: readFileSync(`${REPO}/firestore.rules`, 'utf8'),
  },
});

async function seed() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, role] of [
      [RECRUITER, 'recruteur'], [PLAYER, 'joueur'],
      [RIVAL, 'joueur'], [OUTSIDER, 'joueur'],
    ]) {
      await setDoc(doc(db, 'users', uid), { ...embedded(uid, role), authDisabled: false });
    }

    await setDoc(doc(db, 'offres', OFFER), {
      statut: 'ouverte',
      recruteur: embedded(RECRUITER, 'recruteur'),
      candidats: [embedded(RIVAL, 'joueur')],
      vues: 1,
      viewedBy: [RIVAL],
    });

    await setDoc(doc(db, 'events', EVENT), {
      statut: 'ouvert',
      organisateur: embedded(RECRUITER, 'recruteur'),
      participants: [embedded(RIVAL, 'joueur')],
    });

    await setDoc(doc(db, 'conversations', CONV), {
      utilisateurIds: [PLAYER, RECRUITER],
    });
    await setDoc(doc(db, 'conversations', CONV, 'messages', 'm_player'), {
      expediteurId: PLAYER, destinataireId: RECRUITER,
      contenu: 'Bonjour, voici ma candidature.', estLu: false,
    });
    await setDoc(doc(db, 'conversations', CONV, 'messages', 'm_recruiter'), {
      expediteurId: RECRUITER, destinataireId: PLAYER,
      contenu: 'Merci, je regarde.', estLu: false,
    });
  });
}

await seed();

const player = env.authenticatedContext(PLAYER).firestore();
const recruiter = env.authenticatedContext(RECRUITER).firestore();
const outsider = env.authenticatedContext(OUTSIDER).firestore();

const rivalRow = embedded(RIVAL, 'joueur');
const playerRow = embedded(PLAYER, 'joueur');

/* ---------------- Offer candidates ---------------- */

await check('un joueur postule (s\'ajoute lui-meme)', 'allow', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [rivalRow, playerRow],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur vide la liste des candidats', 'deny', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur supprime un rival', 'deny', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [playerRow],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur inscrit quelqu\'un d\'autre', 'deny', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [rivalRow, embedded(OUTSIDER, 'joueur')],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur ajoute deux candidats d\'un coup', 'deny', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [rivalRow, playerRow, embedded(OUTSIDER, 'joueur')],
    lastUpdated: serverTimestamp(),
  }));

// The offer now holds [rival, player]. A withdrawal must still be reachable:
// canApplyToOffer() is evaluated first and must return false without erroring,
// or the || would never reach canWithdrawFromOffer().
await check('un joueur retire sa propre candidature', 'allow', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    candidats: [rivalRow],
    lastUpdated: serverTimestamp(),
  }));

await check('le recruteur modifie sa propre offre', 'allow', () =>
  updateDoc(doc(recruiter, 'offres', OFFER), {
    titre: 'Recherche lateral gauche U19 (mise a jour)',
    lastUpdated: serverTimestamp(),
  }));

await check('un tiers modifie le titre de l\'offre', 'deny', () =>
  updateDoc(doc(outsider, 'offres', OFFER), {
    titre: 'Offre detournee',
    lastUpdated: serverTimestamp(),
  }));

/* ---------------- Offer views ---------------- */

await check('un lecteur incremente vues de 1', 'allow', () =>
  updateDoc(doc(player, 'offres', OFFER), {
    vues: increment(1),
    viewedBy: arrayUnion(PLAYER),
    lastUpdated: serverTimestamp(),
  }));

await check('un lecteur gonfle le compteur de vues', 'deny', () =>
  updateDoc(doc(outsider, 'offres', OFFER), {
    vues: 99999,
    viewedBy: arrayUnion(OUTSIDER),
    lastUpdated: serverTimestamp(),
  }));

/* ---------------- Event participants ---------------- */

await check('un joueur s\'inscrit a un evenement', 'allow', () =>
  updateDoc(doc(player, 'events', EVENT), {
    participants: [rivalRow, playerRow],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur desinscrit un rival', 'deny', () =>
  updateDoc(doc(outsider, 'events', EVENT), {
    participants: [],
    lastUpdated: serverTimestamp(),
  }));

await check('un joueur se desinscrit lui-meme', 'allow', () =>
  updateDoc(doc(player, 'events', EVENT), {
    participants: [rivalRow],
    lastUpdated: serverTimestamp(),
  }));

await check('l\'organisateur modifie son evenement', 'allow', () =>
  updateDoc(doc(recruiter, 'events', EVENT), {
    lieu: 'Abidjan',
    lastUpdated: serverTimestamp(),
  }));

/* ---------------- Messages ---------------- */

await check('l\'auteur modifie son propre message', 'allow', () =>
  updateDoc(doc(player, 'conversations', CONV, 'messages', 'm_player'), {
    contenu: 'Bonjour, candidature mise a jour.',
  }));

await check('le recruteur reecrit le message du joueur', 'deny', () =>
  updateDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_player'), {
    contenu: 'Je retire ma candidature.',
  }));

await check('le recruteur supprime le message du joueur', 'deny', () =>
  deleteDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_player')));

await check('le destinataire marque le message comme lu', 'allow', () =>
  updateDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_player'), {
    estLu: true,
  }));

await check('l\'auteur supprime son propre message', 'allow', () =>
  deleteDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_recruiter')));

await check('un participant ajoute un tiers a la conversation', 'deny', () =>
  updateDoc(doc(recruiter, 'conversations', CONV), {
    utilisateurIds: [PLAYER, RECRUITER, OUTSIDER],
  }));

await check('un tiers lit la conversation', 'deny', () =>
  getDoc(doc(outsider, 'conversations', CONV)));

/* ---------------- Report ---------------- */

let failed = 0;
console.log('');
for (const r of results) {
  const verdict = r.ok ? 'OK  ' : 'ECHEC';
  if (!r.ok) failed += 1;
  console.log(`${verdict}  [${r.expectation === 'allow' ? 'autorise' : 'refuse '}]  ${r.name}`);
  if (!r.ok) console.log(`        -> ${r.error}`);
}
console.log('');
console.log(`${results.length - failed}/${results.length} conformes`);

await env.cleanup();
process.exit(failed ? 1 : 0);
