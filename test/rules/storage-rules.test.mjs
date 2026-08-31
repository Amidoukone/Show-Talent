/**
 * Authorization tests for storage.rules, run against the real rules engine.
 *
 * firestore.rules has had this since it was hardened; storage.rules never did,
 * and it is the file that guards the two objects a member uploads by hand: an
 * avatar served publicly from this project's domain, and a CV.
 *
 * The gap this closes is specific. On 2026-08-29 the profile-photo rule gained
 * a size ceiling and a content-type check, and the deployed ruleset was
 * updated the same day — but the four videos and every avatar in production
 * predate that deploy, so no real client write has ever been evaluated against
 * it. A tightening whose legitimate path is untested is indistinguishable from
 * an outage until someone tries to change their photo.
 *
 * Every deny case is therefore paired with the allow case it must not break.
 *
 * Run:  npm run rules:test:storage
 * (starts the Storage *and* Firestore emulators — storage.rules calls
 * firestore.get() for the profile document, so both must be up.)
 */

import path, { dirname } from 'path';
import { fileURLToPath } from 'url';
import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import {
  ref, uploadBytes, getBytes, deleteObject,
} from 'firebase/storage';

const REPO = path.resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const PLAYER = 'RuLh6bcq6fhHYCD4chuu6ryI8Cl2';
const RECRUITER = '1CpBpamIhJR5Agz5wG5fnX6jMsl2';
const PRIVATE_PLAYER = 'zDuzNuDD4LYFMKv0bBhTrNT08sb2';
const DISABLED = 'wQwEeVMa5reprTpScRlm7rWy6Ol1';

const VIDEO = 'video_1';

/** A byte payload of the requested size. Content is irrelevant to the rules. */
function bytes(size) {
  return new Uint8Array(size);
}

const JPEG = { contentType: 'image/jpeg' };
const PDF = { contentType: 'application/pdf' };

const results = [];
async function check(name, expectation, fn) {
  try {
    await (expectation === 'allow' ? assertSucceeds(fn()) : assertFails(fn()));
    results.push({ name, expectation, ok: true });
  } catch (error) {
    results.push({
      name,
      expectation,
      ok: false,
      error: String(error.message || error).slice(0, 160),
    });
  }
}

const env = await initializeTestEnvironment({
  projectId: 'demo-adfoot',
  firestore: {
    host: '127.0.0.1',
    port: 8080,
    rules: readFileSync(`${REPO}/firestore.rules`, 'utf8'),
  },
  storage: {
    host: '127.0.0.1',
    port: 9199,
    rules: readFileSync(`${REPO}/storage.rules`, 'utf8'),
  },
});

function profile(uid, role, overrides = {}) {
  return {
    uid,
    nom: 'N-' + uid.slice(0, 4),
    role,
    estActif: true,
    authDisabled: false,
    emailVerified: true,
    profilePublic: true,
    ...overrides,
  };
}

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users', PLAYER), profile(PLAYER, 'joueur'));
  await setDoc(doc(db, 'users', RECRUITER), profile(RECRUITER, 'recruteur'));
  await setDoc(
    doc(db, 'users', PRIVATE_PLAYER),
    profile(PRIVATE_PLAYER, 'joueur', { profilePublic: false }),
  );
  await setDoc(
    doc(db, 'users', DISABLED),
    profile(DISABLED, 'joueur', { authDisabled: true }),
  );
  await setDoc(doc(db, 'videos', VIDEO), { uid: PLAYER, status: 'ready' });

  // Objects that read/delete cases need to find.
  const storage = ctx.storage();
  await uploadBytes(ref(storage, `profilePhotos/${PLAYER}`), bytes(1024), JPEG);
  await uploadBytes(
    ref(storage, `cvs/${PLAYER}/cv_1.pdf`),
    bytes(1024),
    PDF,
  );
  await uploadBytes(
    ref(storage, `cvs/${PRIVATE_PLAYER}/cv_1.pdf`),
    bytes(1024),
    PDF,
  );
  await uploadBytes(ref(storage, `videos/${VIDEO}.mp4`), bytes(1024));
  await uploadBytes(
    ref(storage, `thumbnails/thumbnail_${VIDEO}.jpg`),
    bytes(1024),
    JPEG,
  );
  await uploadBytes(ref(storage, `mp4/${VIDEO}/480.mp4`), bytes(1024));
});

const player = env.authenticatedContext(PLAYER).storage();
const recruiter = env.authenticatedContext(RECRUITER).storage();
const disabled = env.authenticatedContext(DISABLED).storage();
const admin = env
  .authenticatedContext('admin_1', { admin: true })
  .storage();
const anonymous = env.unauthenticatedContext().storage();

/* ---------------- Profile photo ---------------- */

// The legitimate path first. lib/services/users/profile_repository.dart sends
// SettableMetadata(contentType: 'image/jpeg'), and this is the case that says
// the 2026-08-29 tightening did not break changing your photo.
await check("le proprietaire remplace sa photo de profil", 'allow', () =>
  uploadBytes(ref(player, `profilePhotos/${PLAYER}`), bytes(1024 * 512), JPEG));

await check("une photo de profil de 9 Mo", 'deny', () =>
  uploadBytes(
    ref(player, `profilePhotos/${PLAYER}`),
    bytes(9 * 1024 * 1024),
    JPEG,
  ));

await check("un PDF depose comme photo de profil", 'deny', () =>
  uploadBytes(ref(player, `profilePhotos/${PLAYER}`), bytes(1024), PDF));

await check("un fichier sans type depose comme photo de profil", 'deny', () =>
  uploadBytes(ref(player, `profilePhotos/${PLAYER}`), bytes(1024), {
    contentType: 'application/octet-stream',
  }));

await check("un tiers ecrit la photo d'un autre", 'deny', () =>
  uploadBytes(ref(recruiter, `profilePhotos/${PLAYER}`), bytes(1024), JPEG));

await check("un compte desactive ecrit sa propre photo", 'deny', () =>
  uploadBytes(ref(disabled, `profilePhotos/${DISABLED}`), bytes(1024), JPEG));

// The avatar is world-readable on purpose: it is rendered next to a name in
// the feed, in a share page, in the admin portal.
await check("la photo de profil est lisible sans compte", 'allow', () =>
  getBytes(ref(anonymous, `profilePhotos/${PLAYER}`)));

await check("le proprietaire supprime sa photo", 'allow', () =>
  deleteObject(ref(player, `profilePhotos/${PLAYER}`)));

/* ---------------- CV ---------------- */

await check("un joueur depose son CV", 'allow', () =>
  uploadBytes(ref(player, `cvs/${PLAYER}/cv_2.pdf`), bytes(1024 * 64), PDF));

await check("un CV de 6 Mo", 'deny', () =>
  uploadBytes(
    ref(player, `cvs/${PLAYER}/cv_3.pdf`),
    bytes(6 * 1024 * 1024),
    PDF,
  ));

await check("un nom de fichier hors convention", 'deny', () =>
  uploadBytes(ref(player, `cvs/${PLAYER}/dossier.pdf`), bytes(1024), PDF));

// Only a player has a CV. A recruiter uploading one to their own path would
// be storing a document the product never shows.
await check("un recruteur depose un CV sur son propre chemin", 'deny', () =>
  uploadBytes(ref(recruiter, `cvs/${RECRUITER}/cv_1.pdf`), bytes(1024), PDF));

await check("un tiers depose un CV sur le chemin d'un joueur", 'deny', () =>
  uploadBytes(ref(recruiter, `cvs/${PLAYER}/cv_9.pdf`), bytes(1024), PDF));

// profilePublic is what the setting screen toggles, and reading a CV is the
// one place where it is enforced server-side.
await check("un recruteur lit le CV d'un profil public", 'allow', () =>
  getBytes(ref(recruiter, `cvs/${PLAYER}/cv_1.pdf`)));

await check("un recruteur lit le CV d'un profil masque", 'deny', () =>
  getBytes(ref(recruiter, `cvs/${PRIVATE_PLAYER}/cv_1.pdf`)));

await check("un CV n'est pas lisible sans compte", 'deny', () =>
  getBytes(ref(anonymous, `cvs/${PLAYER}/cv_1.pdf`)));

// The claim, and only the claim. Before 2026-08-29 a Firestore `role` field
// reading "admin" was accepted here, which firestore.rules explicitly refuses
// to treat as sufficient.
await check("un operateur admin lit le CV d'un profil masque", 'allow', () =>
  getBytes(ref(admin, `cvs/${PRIVATE_PLAYER}/cv_1.pdf`)));

/* ---------------- Video objects ---------------- */

// Uploads go through a signed session minted by createUploadSession, never
// through a client write on this path.
await check("un client ecrit directement une video", 'deny', () =>
  uploadBytes(ref(player, `videos/${VIDEO}.mp4`), bytes(1024)));

await check("un client ecrit directement un rendu 480p", 'deny', () =>
  uploadBytes(ref(player, `mp4/${VIDEO}/480.mp4`), bytes(1024)));

await check("la video est lisible sans compte", 'allow', () =>
  getBytes(ref(anonymous, `videos/${VIDEO}.mp4`)));

await check("un tiers supprime la video d'un autre", 'deny', () =>
  deleteObject(ref(recruiter, `videos/${VIDEO}.mp4`)));

await check("le proprietaire supprime sa miniature", 'allow', () =>
  deleteObject(ref(player, `thumbnails/thumbnail_${VIDEO}.jpg`)));

await check("le proprietaire supprime son rendu 480p", 'allow', () =>
  deleteObject(ref(player, `mp4/${VIDEO}/480.mp4`)));

await check("le proprietaire supprime sa video", 'allow', () =>
  deleteObject(ref(player, `videos/${VIDEO}.mp4`)));

/* ---------------- Everything else ---------------- */

await check("un chemin non prevu est ferme en ecriture", 'deny', () =>
  uploadBytes(ref(player, `exports/${PLAYER}.zip`), bytes(1024)));

/* ---------------- Report ---------------- */

let failed = 0;
console.log('');
for (const r of results) {
  const verdict = r.ok ? 'OK  ' : 'ECHEC';
  if (!r.ok) failed += 1;
  console.log(
    `${verdict}  [${r.expectation === 'allow' ? 'autorise' : 'refuse '}]  ${r.name}`,
  );
  if (!r.ok) console.log(`        -> ${r.error}`);
}
console.log('');
console.log(`${results.length - failed}/${results.length} conformes`);

await env.cleanup();
process.exit(failed ? 1 : 0);
