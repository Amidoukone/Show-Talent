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
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {checkManagedProfiles} from './managed-profile.integration.mjs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, collection, query, where, orderBy, limit, setDoc, updateDoc, deleteDoc,
  serverTimestamp, increment, arrayUnion, writeBatch,
} from 'firebase/firestore';

const REPO = path.resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Emulator required');
const require = createRequire(import.meta.url);
const {syncPublicProfile} = require('../../functions/lib/public_profile_projection.js');

const RECRUITER = '1CpBpamIhJR5Agz5wG5fnX6jMsl2';
const PLAYER = 'RuLh6bcq6fhHYCD4chuu6ryI8Cl2';
const RIVAL = 'zDuzNuDD4LYFMKv0bBhTrNT08sb2';
const OUTSIDER = 'wQwEeVMa5reprTpScRlm7rWy6Ol1';
const MINOR = 'minor_player_1';
const VERIFIED_SCOUT = 'verified_scout_1';
const LEGACY_PROFILE = 'legacy_profile_without_minor_marker';

const OFFER = 'offer_1';
const EVENT = 'event_1';
const CONV = 'conv_1';

function embedded(uid, role) {
  return {
    uid, nom: 'N-' + uid.slice(0, 4), role,
    photoProfil: '', estActif: true, authDisabled: false,
    emailVerified: true, createdByAdmin: true, profileVerified: false,
    profilePublic: true, allowMessages: true, isMinorProfile: false,
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
      [RIVAL, 'joueur'], [OUTSIDER, 'joueur'], [MINOR, 'joueur'],
      [VERIFIED_SCOUT, 'recruteur'],
    ]) {
      const profile = {
        ...embedded(uid, role),
        authDisabled: false,
        ...(uid === MINOR ? {
          isMinorProfile: true,
          minorProfileApproved: true,
          profilePublic: true,
        } : {}),
        ...(uid === VERIFIED_SCOUT ? {
          profileVerified: true,
          profileVerificationStatus: 'verified',
        } : {}),
      };
      await setDoc(doc(db, 'users', uid), profile);
      await setDoc(doc(db, 'public_profiles', uid), {
        ...profile,
        ...(uid === MINOR ? {
          isMinorProfile: true,
          allowMessages: false,
          isSearchable: true,
          positionCodes: ['ST'],
          nationalities: ['ML'],
          birthYear: 2010,
        } : { isMinorProfile: false }),
      });
    }
    const legacy = {
      ...embedded(LEGACY_PROFILE, 'joueur'),
      authDisabled: false,
      profilePublic: true,
    };
    delete legacy.isMinorProfile;
    await setDoc(doc(db, 'users', LEGACY_PROFILE), legacy);
    await setDoc(doc(db, 'public_profiles', LEGACY_PROFILE), legacy);
    await setDoc(doc(db, 'users', PLAYER, 'private', 'contact'), {phone: '+000000'});
    await setDoc(doc(db, 'users', PLAYER, 'following', RIVAL), {
      followerUid: PLAYER, followingUid: RIVAL, active: true,
    });

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
    await setDoc(doc(db, 'conversations', 'conv_minor'), {
      utilisateurIds: [RECRUITER, MINOR],
    });
    await setDoc(doc(db, 'conversations', 'conv_minor', 'messages', 'm_old'), {
      expediteurId: RECRUITER, destinataireId: MINOR,
      contenu: 'Ancien message', estLu: false,
    });
  });
}

await seed();

const player = env.authenticatedContext(PLAYER).firestore();
const recruiter = env.authenticatedContext(RECRUITER).firestore();
const outsider = env.authenticatedContext(OUTSIDER).firestore();
const verifiedScout = env.authenticatedContext(VERIFIED_SCOUT).firestore();
const minor = env.authenticatedContext(MINOR).firestore();

const rivalRow = embedded(RIVAL, 'joueur');
const playerRow = embedded(PLAYER, 'joueur');

await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'videos', 'adult_ready'), {
    uid: PLAYER, status: 'ready', updatedAt: new Date(),
  });
  await setDoc(doc(ctx.firestore(), 'videos', 'minor_restricted'), {
    uid: MINOR, status: 'ready', publicFeedVisible: false, updatedAt: new Date(),
  });
});
await syncPublicProfile(PLAYER);
await syncPublicProfile(RECRUITER);
await check('le flux de videos adultes reste accessible par requete', 'allow', () =>
  getDocs(query(collection(player, 'videos'), where('status', '==', 'ready'), where('publicFeedVisible', '==', true), limit(20))));
await check('la recherche multi-auteurs publique exclut les videos protegees', 'allow', async () => {
  const result = await getDocs(query(collection(recruiter, 'videos'), where('status', '==', 'ready'),
    where('publicFeedVisible', '==', true), where('uid', 'in', [PLAYER, MINOR]), limit(20)));
  assert.deepEqual(result.docs.map(doc => doc.id), ['adult_ready']);
});
await check('une recherche multi-auteurs sans audience ne doit pas exposer un mineur', 'deny', () =>
  getDocs(query(collection(recruiter, 'videos'), where('status', '==', 'ready'), where('uid', 'in', [PLAYER, MINOR]), limit(20))));
await check('la pagination du profil adulte reste accessible par uid', 'allow', async () => {
  const result = await getDocs(query(collection(recruiter, 'videos'), where('uid', '==', PLAYER),
    where('status', '==', 'ready'), orderBy('updatedAt', 'desc'), limit(20)));
  assert.deepEqual(result.docs.map(doc => doc.id), ['adult_ready']);
});
await check('la liste des conversations adultes reste accessible par requete', 'allow', () =>
  getDocs(query(collection(player, 'conversations'), where('readableBy', 'array-contains', PLAYER), limit(20))));
await check('la boite du recruteur exclut les anciennes conversations mineures', 'allow', async () => {
  const inbox = await getDocs(query(collection(recruiter, 'conversations'), where('readableBy', 'array-contains', RECRUITER)));
  assert.deepEqual(inbox.docs.map((d) => d.id), [CONV]);
});
await check('une nouvelle conversation adulte porte son audience autorisee', 'allow', () =>
  setDoc(doc(player, 'conversations', 'new_adult_conversation'), {
    utilisateurIds: [PLAYER, OUTSIDER], readableBy: [PLAYER, OUTSIDER],
  }));
await check('une conversation ne donne pas acces a un tiers', 'deny', () =>
  setDoc(doc(player, 'conversations', 'forged_conversation_audience'), {
    utilisateurIds: [PLAYER, OUTSIDER], readableBy: [PLAYER, OUTSIDER, RECRUITER],
  }));
await check('la page video dun auteur adulte reste interrogeable', 'allow', () =>
  getDocs(query(collection(recruiter, 'videos'), where('uid', '==', PLAYER), where('status', '==', 'ready'))));
await check('la boite privee ne peut pas etre interrogee par un tiers', 'deny', () =>
  getDocs(query(collection(outsider, 'conversations'), where('readableBy', 'array-contains', PLAYER))));
await check('un participant ne peut pas restaurer un acces de conversation', 'deny', () =>
  updateDoc(doc(recruiter, 'conversations', 'conv_minor'), {readableBy: [RECRUITER, MINOR]}));
await check('un joueur ne peut pas modifier son audience video', 'deny', () =>
  updateDoc(doc(player, 'videos', 'adult_ready'), {publicFeedVisible: false}));
await check('la recherche adulte reste accessible par requete', 'allow', () =>
  getDocs(query(collection(player, 'public_profiles'), where('isMinorProfile', '==', false), limit(20))));
await check('la recherche mineur est accessible au recruteur verifie', 'allow', () =>
  getDocs(query(collection(verifiedScout, 'public_profiles'), where('isSearchable', '==', true), where('isMinorProfile', 'in', [false, true]), limit(20))));
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'users', MINOR, 'private', 'contact'), {
    birthDate: new Date('2010-01-01'), phone: 'old',
  });
});
await check('un mineur peut corriger son telephone sans changer sa date', 'allow', () =>
  updateDoc(doc(minor, 'users', MINOR, 'private', 'contact'), {phone: 'new'}));
await check('un mineur ne peut pas se declarer adulte', 'deny', () =>
  updateDoc(doc(minor, 'users', MINOR, 'private', 'contact'), {birthDate: new Date('1990-01-01')}));

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

await check('l\'auteur ne reecrit pas un message envoye', 'deny', () =>
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

await check('un membre ne peut pas creer un message vers un tiers', 'deny', () =>
  setDoc(doc(player, 'conversations', CONV, 'messages', 'm_wrong_recipient'), {
    expediteurId: PLAYER, destinataireId: OUTSIDER,
    contenu: 'Message detourne.', estLu: false,
  }));

await check('l\'auteur supprime son propre message', 'allow', () =>
  deleteDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_recruiter')));

await check('un participant ajoute un tiers a la conversation', 'deny', () =>
  updateDoc(doc(recruiter, 'conversations', CONV), {
    utilisateurIds: [PLAYER, RECRUITER, OUTSIDER],
  }));

await check('un tiers lit la conversation', 'deny', () =>
  getDoc(doc(outsider, 'conversations', CONV)));

/* ---------------- Blocks ---------------- */

await check('un joueur bloque un rival', 'allow', () =>
  setDoc(doc(player, 'blocks', `${PLAYER}_${RIVAL}`), {
    blockerUid: PLAYER, blockedUid: RIVAL, createdAt: serverTimestamp(),
  }));

await check('usurper le blockerUid d\'un autre', 'deny', () =>
  setDoc(doc(player, 'blocks', `${RIVAL}_${OUTSIDER}`), {
    blockerUid: RIVAL, blockedUid: OUTSIDER, createdAt: serverTimestamp(),
  }));

await check('se bloquer soi-meme', 'deny', () =>
  setDoc(doc(player, 'blocks', `${PLAYER}_${PLAYER}`), {
    blockerUid: PLAYER, blockedUid: PLAYER, createdAt: serverTimestamp(),
  }));

await check('un id de doc qui ne correspond pas aux champs', 'deny', () =>
  setDoc(doc(player, 'blocks', 'id_incoherent'), {
    blockerUid: PLAYER, blockedUid: OUTSIDER, createdAt: serverTimestamp(),
  }));

await check('createdAt sans horodatage serveur', 'deny', () =>
  setDoc(doc(player, 'blocks', `${PLAYER}_${OUTSIDER}`), {
    blockerUid: PLAYER, blockedUid: OUTSIDER,
    createdAt: new Date('2020-01-01T00:00:00Z'),
  }));

await check('le bloqueur relit son propre blocage', 'allow', () =>
  getDoc(doc(player, 'blocks', `${PLAYER}_${RIVAL}`)));

await check('la personne bloquee lit le blocage qui la vise', 'allow', () =>
  getDoc(doc(env.authenticatedContext(RIVAL).firestore(), 'blocks', `${PLAYER}_${RIVAL}`)));

await check('un tiers lit un blocage qui ne le concerne pas', 'deny', () =>
  getDoc(doc(outsider, 'blocks', `${PLAYER}_${RIVAL}`)));

await check('la personne bloquee supprime le blocage qui la vise', 'deny', () =>
  deleteDoc(doc(env.authenticatedContext(RIVAL).firestore(), 'blocks', `${PLAYER}_${RIVAL}`)));

await check('un tiers supprime un blocage qui ne le concerne pas', 'deny', () =>
  deleteDoc(doc(outsider, 'blocks', `${PLAYER}_${RIVAL}`)));

await check('le bloqueur retire son propre blocage', 'allow', () =>
  deleteDoc(doc(player, 'blocks', `${PLAYER}_${RIVAL}`)));

// Le joueur bloque maintenant le recruteur -- ceci doit couper les NOUVEAUX
// messages entre eux dans les deux sens, sans jamais toucher a la lecture de
// l'historique deja echange (m_player/m_recruiter, geres plus haut).
await check('un joueur bloque le recruteur', 'allow', () =>
  setDoc(doc(player, 'blocks', `${PLAYER}_${RECRUITER}`), {
    blockerUid: PLAYER, blockedUid: RECRUITER, createdAt: serverTimestamp(),
  }));

await check('le joueur tente d\'ecrire au recruteur bloque', 'deny', () =>
  setDoc(doc(player, 'conversations', CONV, 'messages', 'm_blocked_attempt_by_player'), {
    expediteurId: PLAYER, destinataireId: RECRUITER,
    contenu: 'Un dernier message.', estLu: false,
  }));

await check('le recruteur tente d\'ecrire au joueur qui l\'a bloque', 'deny', () =>
  setDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_blocked_attempt_by_recruiter'), {
    expediteurId: RECRUITER, destinataireId: PLAYER,
    contenu: 'Toujours la ?', estLu: false,
  }));

await check('l\'historique reste lisible malgre le blocage', 'allow', () =>
  getDoc(doc(recruiter, 'conversations', CONV, 'messages', 'm_player')));

await check('une nouvelle conversation entre deux bloques est refusee', 'deny', () =>
  setDoc(doc(player, 'conversations', 'conv_blocked_new'), {
    utilisateurIds: [PLAYER, RECRUITER],
  }));

await check('un recruteur ne peut pas ouvrir une conversation vers un profil protege', 'deny', () =>
  setDoc(doc(recruiter, 'conversations', 'conv_to_minor'), {
    utilisateurIds: [RECRUITER, MINOR],
  }));

await check('un recruteur ne peut pas envoyer de message a un profil protege', 'deny', () =>
  setDoc(doc(recruiter, 'conversations', 'conv_minor', 'messages', 'm_to_minor'), {
    expediteurId: RECRUITER, destinataireId: MINOR,
    contenu: 'Bonjour', estLu: false,
  }));

await check('un mineur ne cree pas de conversation directe', 'deny', () =>
  setDoc(doc(minor, 'conversations', 'conv_minor_created_by_player'), {
    utilisateurIds: [MINOR, RECRUITER],
  }));

await check('un mineur ne peut pas envoyer de message direct', 'deny', () =>
  setDoc(doc(minor, 'conversations', 'conv_minor', 'messages', 'm_new'), {
    expediteurId: MINOR, destinataireId: RECRUITER,
    contenu: 'Message direct', estLu: false,
  }));

await check('un recruteur ne lit pas une ancienne conversation avec un mineur', 'deny', () =>
  getDoc(doc(recruiter, 'conversations', 'conv_minor')));

await check('un recruteur ne lit pas les anciens messages du mineur', 'deny', () =>
  getDoc(doc(recruiter, 'conversations', 'conv_minor', 'messages', 'm_old')));

await check('le joueur debloque le recruteur', 'allow', () =>
  deleteDoc(doc(player, 'blocks', `${PLAYER}_${RECRUITER}`)));

await check('l\'envoi redevient possible apres deblocage', 'allow', () =>
  setDoc(doc(player, 'conversations', CONV, 'messages', 'm_after_unblock'), {
    expediteurId: PLAYER, destinataireId: RECRUITER,
    contenu: 'Toujours partant.', estLu: false,
  }));

/* ---------------- Account deletion and contact intake ---------------- */

await check('un utilisateur relit son profil interne', 'allow', () =>
  getDoc(doc(player, 'users', PLAYER)));

await check('un tiers ne lit pas le profil interne', 'deny', () =>
  getDoc(doc(recruiter, 'users', PLAYER)));

await check('un utilisateur actif lit une projection publique', 'allow', () =>
  getDoc(doc(recruiter, 'public_profiles', PLAYER)));

await check('un compte non vérifié ne lit pas le profil protégé', 'deny', () =>
  getDoc(doc(recruiter, 'public_profiles', MINOR)));
await check('un recruteur certifié lit la fiche football limitée', 'allow', () =>
  getDoc(doc(verifiedScout, 'public_profiles', MINOR)));
await check('une fiche historique sans marqueur âge reste fermée pendant la migration', 'deny', () =>
  getDoc(doc(verifiedScout, 'public_profiles', LEGACY_PROFILE)));

await check('un client ne modifie pas une projection publique', 'deny', () =>
  updateDoc(doc(player, 'public_profiles', PLAYER), {nom: 'Nom detourne'}));

await check('un utilisateur lit ses propres abonnements', 'allow', () =>
  getDoc(doc(player, 'users', PLAYER, 'following', RIVAL)));

await check("un tiers ne lit pas les relations d'abonnement", 'deny', () =>
  getDoc(doc(recruiter, 'users', PLAYER, 'following', RIVAL)));

await check("un client n'ecrit pas directement une relation", 'deny', () =>
  setDoc(doc(player, 'users', PLAYER, 'following', OUTSIDER), {
    followerUid: PLAYER, followingUid: OUTSIDER, active: true,
  }));

await check('suppression directe du profil refusee', 'deny', () =>
  deleteDoc(doc(player, 'users', PLAYER)));

await check('suppression directe du contact prive refusee', 'deny', () =>
  deleteDoc(doc(player, 'users', PLAYER, 'private', 'contact')));

await check('ecriture directe du jeton FCM public refusee', 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {fcmToken: 'device-secret'}));

await check('lecture du jeton FCM prive refusee', 'deny', () =>
  getDoc(doc(player, 'user_push_tokens', PLAYER)));

await check('ecriture du jeton FCM prive refusee', 'deny', () =>
  setDoc(doc(player, 'user_push_tokens', PLAYER), {token: 'device-secret'}));

await check('chemin Storage de CV accepte', 'allow', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    cvUrl: `gs://demo-bucket/cvs/${PLAYER}/cv_123.pdf`,
  }));

await check('URL de CV avec jeton refusee', 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    cvUrl: `https://firebasestorage.googleapis.com/v0/b/demo/o/cvs%2F${PLAYER}%2Fcv_123.pdf?token=leaked`,
  }));

const intakeData = {
  requesterUid: PLAYER, targetUid: RECRUITER,
  status: 'new', agencyFollowUpStatus: 'new',
  contactReason: 'recrutement', introMessage: 'Bonjour',
};

await check('demande de contact sans mise a jour du quota refusee', 'deny', () =>
  setDoc(doc(player, 'contact_intakes', 'intake_without_limit'), intakeData));

await check('demande de contact avec quota atomique autorisee', 'allow', () => {
  const batch = writeBatch(player);
  batch.set(doc(player, 'contact_intakes', 'intake_valid'), intakeData);
  batch.set(doc(player, 'contact_intake_limits', PLAYER), {
    lastIntakeAt: serverTimestamp(),
  });
  return batch.commit();
});

await check('deuxieme demande immediate refusee', 'deny', () => {
  const batch = writeBatch(player);
  batch.set(doc(player, 'contact_intakes', 'intake_too_soon'), intakeData);
  batch.set(doc(player, 'contact_intake_limits', PLAYER), {
    lastIntakeAt: serverTimestamp(),
  });
  return batch.commit();
});

const minorIntakeData = {
  ...intakeData,
  requesterUid: VERIFIED_SCOUT,
  targetUid: MINOR,
  requesterRole: 'recruteur',
  targetRole: 'joueur',
};
await check('un recruteur non vérifié ne peut contacter un mineur', 'deny', () =>
  setDoc(doc(recruiter, 'contact_intakes', 'minor_intake_unverified'), {
    ...minorIntakeData,
    requesterUid: RECRUITER,
  }));
await check('un recruteur vérifié soumet une demande médiée pour un mineur', 'allow', () => {
  const batch = writeBatch(verifiedScout);
  batch.set(
    doc(verifiedScout, 'contact_intakes', 'minor_intake_verified'),
    minorIntakeData,
  );
  batch.set(doc(verifiedScout, 'contact_intake_limits', VERIFIED_SCOUT), {
    lastIntakeAt: serverTimestamp(),
  });
  return batch.commit();
});
await check('le mineur ne lit pas la demande avant médiation admin', 'deny', () =>
  getDoc(doc(
    env.authenticatedContext(MINOR).firestore(),
    'contact_intakes',
    'minor_intake_verified',
  )));

/* ---------------- Terms acceptance ---------------- */

await check('un utilisateur enregistre son acceptation des CGU', 'allow', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    acceptedTermsVersion: '1.0',
    acceptedTermsAt: serverTimestamp(),
  }));

await check('une acceptation sans horodatage serveur', 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    acceptedTermsVersion: '1.0',
    acceptedTermsAt: new Date('2020-01-01T00:00:00Z'),
  }));

await check('une acceptation avec une version vide', 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    acceptedTermsVersion: '',
    acceptedTermsAt: serverTimestamp(),
  }));

await check("accepter pour le compte d'un autre", 'deny', () =>
  updateDoc(doc(player, 'users', RIVAL), {
    acceptedTermsVersion: '1.0',
    acceptedTermsAt: serverTimestamp(),
  }));

// La porte ne doit pas devenir un cheval de Troie : elle n'autorise que ces
// deux champs, jamais un champ sensible qui voyagerait avec.
await check("glisser un role dans l'acceptation", 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    acceptedTermsVersion: '1.0',
    acceptedTermsAt: serverTimestamp(),
    role: 'admin',
  }));

await check("glisser une verification de profil dans l'acceptation", 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    acceptedTermsVersion: '1.0',
    acceptedTermsAt: serverTimestamp(),
    profileVerified: true,
  }));

/* ---------------- Droits d'acces (membership) ---------------- */

// Le mecanisme de droits vaut ce que vaut cette garantie : si un joueur peut
// s'attribuer lui-meme un droit, tout le modele economique s'effondre en
// silence. `membership` est absent de la liste blanche canUpdateOwnProfile,
// donc seul le callable admin (Admin SDK, qui contourne les regles) l'ecrit.

await check("un joueur s'attribue un droit adfoot", 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    membership: { tier: 'adfoot', validUntil: null },
  }));

await check("un joueur prolonge son propre droit", 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    membership: { tier: 'external', validUntil: new Date('2030-01-01') },
  }));

await check("un joueur efface le droit d'un autre", 'deny', () =>
  updateDoc(doc(player, 'users', RIVAL), { membership: null }));

// Et le champ ne doit pas non plus pouvoir voyager avec une ecriture par
// ailleurs legitime.
await check("glisser un droit dans une mise a jour de profil", 'deny', () =>
  updateDoc(doc(player, 'users', PLAYER), {
    bio: 'Milieu de terrain',
    membership: { tier: 'adfoot' },
  }));

/* ---------------- Report ---------------- */

await checkManagedProfiles(check);

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
