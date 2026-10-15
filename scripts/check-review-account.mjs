#!/usr/bin/env node

/**
 * Checks that the App Review demo account is fit to be handed to a store
 * reviewer (`docs/store-compliance.md`, "App access: the review account is
 * mandatory, not optional").
 *
 * Why this is a script and not a look at the Firestore console.
 *
 * The account has to satisfy several independent conditions at once, and the
 * one that matters most is invisible. `cleanupUnverifiedAccounts` runs every
 * 24 hours and deletes unverified accounts older than three days;
 * `asManagedAccount()` (functions/src/cleanup.ts) spares an account when
 * `createdByAdmin === true` **or** its role is in
 * `{admin, club, recruteur, agent}`. The demo account must be a `joueur`,
 * because that is the journey the screenshots promise, and `joueur` is *not*
 * in that set. So a player demo account survives the purge on
 * `createdByAdmin` alone, with no fallback: created by hand in the Firebase
 * Auth console it looks perfect on day one and is gone on day four, in the
 * middle of the review, leaving the reviewer with an invalid login and the
 * submission with a Guideline 2.1 rejection nobody can reproduce locally.
 *
 * Nothing about that failure is visible by reading the account. It is visible
 * by reading one boolean, which is what this script does, together with the
 * conditions a reviewer would hit in order: can it sign in, is it active, does
 * it show a populated profile rather than empty screens, and has it already
 * accepted the terms version the gate requires.
 *
 * Read-only. It writes nothing and needs no `--apply`.
 *
 * Usage:
 *   node scripts/check-review-account.mjs --environment production \
 *     --email demo.joueur@example.org
 *
 * `--role` defaults to `joueur`, the demo account the stores are handed. Pass
 * the role explicitly to check the second account kept for showing messaging:
 * a club has no playing position and no videos of its own, and reporting those
 * as defects would make the whole output untrustworthy.
 */

import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';

const MANAGED_ROLES = new Set(['admin', 'club', 'recruteur', 'agent']);

const args = process.argv.slice(2);
let environment;
let email;
let credentials;
let expectedRole = 'joueur';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--environment' && args[i + 1]) environment = args[++i];
  else if (args[i] === '--email' && args[i + 1]) email = args[++i];
  else if (args[i] === '--role' && args[i + 1]) expectedRole = args[++i].trim().toLowerCase();
  else if (args[i] === '--credentials' && args[i + 1]) credentials = resolve(args[++i]);
  else throw new Error(`Unknown or incomplete argument: ${args[i]}`);
}
if (!['staging', 'production'].includes(environment)) {
  throw new Error('--environment staging|production is required');
}
if (!email) throw new Error('--email is required');
if (process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Unexpected emulator configuration');
}

const projectId = `adfoot-${environment}`;
const credentialsPath = credentials ?? resolve(`.credentials/${projectId}-ops.json`);
const account = JSON.parse(readFileSync(credentialsPath, 'utf8'));
if (account.type !== 'service_account' || account.project_id !== projectId) {
  throw new Error(`A ${projectId} service account is required, got ${account.project_id}`);
}

const require = createRequire(resolve('functions/package.json'));
const {initializeApp, cert} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');

initializeApp({credential: cert(account), projectId});
const db = getFirestore();
const auth = getAuth();

const blocking = [];
const advisory = [];

function report(ok, label, detail, {advisoryOnly = false} = {}) {
  console.log(`  ${ok ? 'ok   ' : 'FAIL '} ${label.padEnd(34)} ${detail}`);
  if (!ok) (advisoryOnly ? advisory : blocking).push(`${label}: ${detail}`);
}

console.log(`project     : ${projectId}`);
console.log(`email       : ${email}\n`);

let authUser;
try {
  authUser = await auth.getUserByEmail(email);
} catch (error) {
  console.error(`No Firebase Auth user for ${email} (${error.code ?? error.message}).`);
  console.error('Provision it through the admin portal (provisionManagedAccount).');
  process.exit(1);
}

console.log('Firebase Auth');
report(true, 'uid', authUser.uid);
report(authUser.emailVerified, 'emailVerified', String(authUser.emailVerified));
report(!authUser.disabled, 'not disabled', authUser.disabled ? 'account is disabled' : 'enabled');

const snapshot = await db.collection('users').doc(authUser.uid).get();
if (!snapshot.exists) {
  console.error(`\nNo users/${authUser.uid} document. The Auth user exists without a profile,`);
  console.error('which is what creating an account by hand in the console produces.');
  process.exit(1);
}
const user = snapshot.data();
const role = typeof user.role === 'string' ? user.role.trim().toLowerCase() : '';

console.log('\nusers document');
report(role === expectedRole, 'role', `${role || '(absent)'}, expected ${expectedRole}`);
report(user.estActif === true, 'estActif', String(user.estActif));
report(user.authDisabled !== true, 'authDisabled', String(user.authDisabled ?? false));
report(user.emailVerified === true, 'emailVerified (doc)', String(user.emailVerified));

console.log('\nSurvival of cleanupUnverifiedAccounts');
const exemptByFlag = user.createdByAdmin === true;
const exemptByRole = MANAGED_ROLES.has(role);
report(exemptByFlag, 'createdByAdmin', String(user.createdByAdmin ?? false));
report(
  exemptByFlag || exemptByRole,
  'purge exemption',
  exemptByFlag
    ? 'exempt by createdByAdmin'
    : exemptByRole
      ? `exempt by role ${role}`
      : `role ${role || '(absent)'} is not in {${[...MANAGED_ROLES].join(', ')}} and ` +
        'createdByAdmin is not true, so this account is deleted three days after creation',
);

console.log('\nWhat the reviewer sees');
report(typeof user.nom === 'string' && user.nom.trim().length > 0, 'nom', user.nom || '(absent)');
report(
  typeof user.photoProfil === 'string' && user.photoProfil.trim().length > 0,
  'photoProfil',
  user.photoProfil ? 'set' : '(absent)',
);
if (expectedRole === 'joueur') {
  // `positionCodes`, not `position`. The football facts sit flattened on the
  // user document and `positionCodes` is the name in
  // PlayerFootballProfile.writableFieldPaths; plain `position` appears
  // nowhere in the model, so reading it reported a complete profile as
  // missing its position. Measured on the demo account on 2026-10-15.
  const positionCodes = Array.isArray(user.positionCodes) ?
    user.positionCodes.filter((code) => typeof code === 'string' && code.trim() !== '') :
    [];
  report(
    positionCodes.length > 0,
    'positionCodes',
    positionCodes.length > 0 ? positionCodes.join(', ') : '(absent)',
  );

  const videos = await db
    .collection('videos')
    .where('uid', '==', authUser.uid)
    .get();
  const approved = videos.docs.filter((doc) => doc.data().moderationStatus === 'approved');
  report(
    approved.length > 0,
    'approved videos',
    `${approved.length} approved of ${videos.size} total`,
  );
} else {
  console.log(
    `  n/a    ${'position, videos'.padEnd(34)} not facts about a ${expectedRole} account`,
  );
}

console.log('\nTerms acceptance gate');
const legal = await db.doc('config/legal').get();
const requiredVersion = legal.exists ? (legal.data().requiredVersion ?? '').trim() : '';
const acceptedVersion = (user.acceptedTermsVersion ?? '').trim();
if (requiredVersion === '') {
  report(true, 'gate', 'dormant, config/legal requires no version');
  if (acceptedVersion === '') {
    advisory.push(
      'The gate is dormant. Arming it later makes this account meet the consent ' +
        'screen, so accept the terms on it once right after arming.',
    );
  }
} else {
  const matches = acceptedVersion === requiredVersion;
  report(
    matches,
    'accepted version',
    matches
      ? `${acceptedVersion}, matches the armed gate`
      : `gate requires ${requiredVersion}, account has ${acceptedVersion || '(nothing)'}, ` +
        'so the reviewer meets the consent screen before the app',
  );
}

console.log('');
if (advisory.length > 0) {
  console.log('Advisory:');
  for (const line of advisory) console.log(`  - ${line}`);
  console.log('');
}
if (blocking.length > 0) {
  console.log(`NOT READY: ${blocking.length} blocking condition(s).`);
  for (const line of blocking) console.log(`  - ${line}`);
  process.exit(1);
}
console.log('READY: this account can be handed to a store reviewer.');
process.exit(0);
