#!/usr/bin/env node
// Creates disposable fixtures only on the explicitly selected project.
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {cert, initializeApp as initializeAdmin, deleteApp as deleteAdmin} from 'firebase-admin/app';
import {getAuth as getAdminAuth} from 'firebase-admin/auth';
import {getFirestore as getAdminFirestore} from 'firebase-admin/firestore';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, signInWithCustomToken, signOut} from 'firebase/auth';
import {getFirestore, getDocsFromServer, collection, query, where, orderBy, limit, doc, setDoc, terminate} from 'firebase/firestore';

const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== '--credentials' || args[2] !== '--environment' ||
    !['staging', 'production'].includes(args[3])) throw new Error('Expected --credentials PATH --environment staging|production');
const environment = args[3];
const projectId = `adfoot-${environment}`;
const account = JSON.parse(await readFile(resolve(args[1]), 'utf8'));
if (account.type !== 'service_account' || account.project_id !== projectId) throw new Error('Project/credentials mismatch');
const config = JSON.parse(await readFile(`config/mobile/${environment}.json`, 'utf8'));
if (config.FIREBASE_PROJECT_ID !== projectId) throw new Error('Project/config mismatch');
if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Unexpected emulator configuration');
const publicOrigin = `https://${projectId}.web.app`;
const adminOrigin = environment === 'staging' ? 'https://adfoot-admin-staging.web.app' : 'https://adfoot-admin.web.app';
const adminApp = initializeAdmin({credential: cert(account), projectId});
const adminAuth = getAdminAuth(adminApp);
const adminDb = getAdminFirestore(adminApp);
const clientApp = initializeApp({projectId, apiKey: config.FIREBASE_WEB_API_KEY, appId: config.FIREBASE_WEB_APP_ID});
const clientAuth = getAuth(clientApp);
const clientDb = getFirestore(clientApp);
const uid = `release-smoke-${randomUUID()}`;
const adultUid = `${uid}-adult`;
const minorUid = `${uid}-minor`;
const videoId = `${uid}-video`;
const conversationId = `${uid}-conversation`;
let created = false;
try {
  await adminAuth.createUser({uid});
  created = true;
  await adminDb.collection('users').doc(uid).set({uid, nom: 'Release smoke test', role: 'recruteur',
    authDisabled: false, estActif: true, emailVerified: true, isMinorProfile: false,
    profileVerified: true, profileVerificationStatus: 'verified', profilePublic: false});
  await signInWithCustomToken(clientAuth, await adminAuth.createCustomToken(uid));
  for (const [playerUid, birthDate, minor] of [[adultUid, '2005-01-01', false], [minorUid, '2010-01-01', true]]) {
    const batch = adminDb.batch();
    const ref = adminDb.collection('users').doc(playerUid);
    batch.set(ref, {uid: playerUid, nom: 'Temporary release fixture', role: 'joueur',
      authDisabled: false, estActif: true, emailVerified: true, profilePublic: true,
      allowMessages: !minor, minorProfileApproved: minor, positionCodes: ['ST'],
      nationalities: ['ML'], openToOpportunities: true});
    batch.set(ref.collection('private').doc('contact'), {birthDate: new Date(birthDate)});
    await batch.commit();
  }
  await adminDb.collection('videos').doc(videoId).set({uid: adultUid, status: 'ready',
    approvedAt: new Date(), updatedAt: new Date()});
  // Exercise the deployed triggers, without writing their derived fields.
  let ready = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    const [adult, minor, video] = await Promise.all([
      adminDb.collection('public_profiles').doc(adultUid).get(),
      adminDb.collection('public_profiles').doc(minorUid).get(),
      adminDb.collection('videos').doc(videoId).get(),
    ]);
    if (adult.data()?.isSearchable === true && adult.data()?.isMinorProfile === false &&
        minor.data()?.isSearchable === true && minor.data()?.isMinorProfile === true &&
        video.data()?.publicFeedVisible === true) { ready = true; break; }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  assert.ok(ready, 'Deployed profile/search/video triggers did not converge');
  await setDoc(doc(clientDb, 'conversations', conversationId), {
    utilisateurIds: [uid, adultUid], readableBy: [uid, adultUid], lastMessageDate: new Date(),
  });
  const checks = [
    ['directory', query(collection(clientDb, 'public_profiles'), where('isMinorProfile', '==', false), limit(5))],
    ['talents', query(collection(clientDb, 'public_profiles'), where('isSearchable', '==', true), where('isMinorProfile', 'in', [false, true]), limit(5))],
    ['talent-filters', query(collection(clientDb, 'public_profiles'), where('isSearchable', '==', true), where('isMinorProfile', 'in', [false, true]), where('positionCodes', 'array-contains-any', ['ST']), where('openToOpportunities', '==', true), where('birthYear', '>=', 2000), orderBy('birthYear'), limit(5))],
    ['video-feed', query(collection(clientDb, 'videos'), where('status', '==', 'ready'), where('publicFeedVisible', '==', true), orderBy('approvedAt', 'desc'), limit(5))],
    ['recent-videos', query(collection(clientDb, 'videos'), where('status', '==', 'ready'), where('publicFeedVisible', '==', true), orderBy('updatedAt', 'desc'), limit(5))],
    ['inbox', query(collection(clientDb, 'conversations'), where('readableBy', 'array-contains', uid), orderBy('lastMessageDate', 'desc'), limit(5))],
  ];
  for (const [name, request] of checks) {
    const result = await getDocsFromServer(request);
    if (name === 'talents' || name === 'talent-filters') {
      assert.ok(result.docs.some((doc) => doc.id === adultUid), `${name}: adult fixture missing`);
      assert.ok(result.docs.some((doc) => doc.id === minorUid), `${name}: approved minor fixture missing`);
    }
    if (name === 'video-feed' || name === 'recent-videos') assert.ok(result.docs.some((doc) => doc.id === videoId));
    if (name === 'inbox') assert.ok(result.docs.some((doc) => doc.id === conversationId));
    console.log(`${name}: OK (${result.size} results)`);
  }
  await adminDb.collection('users').doc(uid).update({role: 'fan', profileVerified: false, profileVerificationStatus: 'unverified'});
  await assert.rejects(getDocsFromServer(checks[1][1]), (error) => error.code === 'permission-denied');
  console.log('minor-search-by-unverified-account: denied as expected');
  await assert.rejects(setDoc(doc(clientDb, 'public_profiles', uid), {isMinorProfile: false}),
    (error) => error.code === 'permission-denied');
  console.log('public-profile-client-write: denied as expected');
  for (const [url, status] of [
    [`${publicOrigin}/`, 200],
    [`${publicOrigin}/account/reset`, 200],
    [`${publicOrigin}/legal/privacy-policy.html`, 200],
    [`${publicOrigin}/legal/terms.draft.html`, 404],
    [`${adminOrigin}/`, 200],
    [`${publicOrigin}/cv/view/invalid`, 404],
  ]) {
    const response = await fetch(url, {signal: AbortSignal.timeout(20000)});
    assert.equal(response.status, status, url);
    console.log(`${url}: ${response.status}`);
  }
} finally {
  await signOut(clientAuth).catch(() => {});
  if (created) {
    await adminDb.collection('conversations').doc(conversationId).delete();
    await adminDb.collection('videos').doc(videoId).delete();
    for (const playerUid of [adultUid, minorUid]) {
      await adminDb.collection('users').doc(playerUid).collection('private').doc('contact').delete();
      await adminDb.collection('users').doc(playerUid).delete();
      await adminDb.collection('public_profiles').doc(playerUid).delete();
    }
    // Only documents owned by this script's random, newly created UID.
    await adminDb.collection('users').doc(uid).delete();
    await adminDb.collection('public_profiles').doc(uid).delete();
    await adminAuth.deleteUser(uid);
    console.log(`Disposable ${environment} account removed`);
  }
  await terminate(clientDb);
  await deleteApp(clientApp);
  await adminDb.terminate();
  await deleteAdmin(adminApp);
}
