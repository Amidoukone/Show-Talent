#!/usr/bin/env node

/**
 * Arms, inspects or disarms the terms acceptance gate by writing
 * `config/legal` (see "Activating the acceptance gate" in
 * `docs/store-compliance.md`).
 *
 * Why a script rather than a click in the Firestore console.
 *
 * This one document decides whether every account in the fleet meets a
 * full-screen consent gate on its next launch, within the 15-minute cache
 * window of `TermsConfig`. A typo in `requiredVersion` locks the fleet behind
 * a version nobody can ever match; a wrong URL asks users to accept a text
 * they cannot open. Both are silent: nothing fails in a log, users simply
 * cannot get past a screen. A console click leaves no trace of who wrote what
 * and offers no preflight, so the two failure modes are caught by users
 * instead of before the write.
 *
 * So the script refuses to arm unless the documents it is about to point at
 * are actually being served. `check-production-hosting.mjs` already compares
 * the deployed bytes with this repo; this is the narrower, mandatory check
 * that the four URLs going into the document resolve with a 200. Arming a
 * gate towards a 404 is the exact defect the config indirection exists to
 * prevent, and the preflight makes it unrepresentable rather than documented.
 *
 * Read-only by default: without `--apply` it prints the current document and
 * the one it would write, and changes nothing.
 *
 * Usage:
 *   node scripts/set-legal-gate.mjs --environment production
 *   node scripts/set-legal-gate.mjs --environment production --apply
 *   node scripts/set-legal-gate.mjs --environment production --disarm --apply
 */

import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';

const DEFAULTS = {
  requiredVersion: '1.2',
  effectiveOn: '15 octobre 2026',
  termsUrl: 'https://adfoot.org/legal/terms.html',
  privacyUrl: 'https://adfoot.org/legal/privacy-policy.html',
  termsUrlEn: 'https://adfoot.org/legal/terms.en.html',
  privacyUrlEn: 'https://adfoot.org/legal/privacy-policy.en.html',
};

const args = process.argv.slice(2);
let environment;
let credentials;
let apply = false;
let disarm = false;
let requiredVersion = DEFAULTS.requiredVersion;
let effectiveOn = DEFAULTS.effectiveOn;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--apply') apply = true;
  else if (args[i] === '--disarm') disarm = true;
  else if (args[i] === '--environment' && args[i + 1]) environment = args[++i];
  else if (args[i] === '--credentials' && args[i + 1]) credentials = resolve(args[++i]);
  else if (args[i] === '--version' && args[i + 1]) requiredVersion = args[++i];
  else if (args[i] === '--effective-on' && args[i + 1]) effectiveOn = args[++i];
  else throw new Error(`Unknown or incomplete argument: ${args[i]}`);
}

if (!['staging', 'production'].includes(environment)) {
  throw new Error('--environment staging|production is required');
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Unexpected emulator configuration');
}

const projectId = `adfoot-${environment}`;
const credentialsPath = credentials ?? resolve(`.credentials/${projectId}-ops.json`);
const account = JSON.parse(readFileSync(credentialsPath, 'utf8'));
if (account.type !== 'service_account' || account.project_id !== projectId) {
  throw new Error(`A ${projectId} service account is required, got ${account.project_id}`);
}

/** The four URLs must resolve before anyone is asked to accept what they hold. */
async function assertDocumentsAreServed() {
  const urls = [
    DEFAULTS.termsUrl,
    DEFAULTS.privacyUrl,
    DEFAULTS.termsUrlEn,
    DEFAULTS.privacyUrlEn,
  ];
  const failures = [];
  for (const url of urls) {
    try {
      const response = await fetch(url, {redirect: 'follow'});
      console.log(`  ${response.status === 200 ? 'ok  ' : 'FAIL'} ${response.status} ${url}`);
      if (response.status !== 200) failures.push(`${url} -> ${response.status}`);
    } catch (error) {
      console.log(`  FAIL     ${url} (${error.message})`);
      failures.push(`${url} -> ${error.message}`);
    }
  }
  if (failures.length > 0) {
    throw new Error(
      `Refusing to arm the gate: ${failures.length} legal document(s) are not served.\n` +
        failures.map((line) => `  - ${line}`).join('\n') +
        '\nDeploy hosting first: npm.cmd run hosting:marketing:deploy:production',
    );
  }
}

const require = createRequire(resolve('functions/package.json'));
const {initializeApp, cert} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');

initializeApp({credential: cert(account), projectId});
const reference = getFirestore().doc('config/legal');

const before = await reference.get();
console.log(`project            : ${projectId}`);
console.log(`credentials        : ${credentialsPath}`);
console.log(`config/legal       : ${before.exists ? 'exists' : 'does not exist'}`);
if (before.exists) console.log(JSON.stringify(before.data(), null, 2));

const target = disarm
  ? {...DEFAULTS, requiredVersion: '', effectiveOn: ''}
  : {...DEFAULTS, requiredVersion, effectiveOn};

console.log(`\naction             : ${disarm ? 'DISARM' : 'ARM'}`);
console.log('document to write  :');
console.log(JSON.stringify(target, null, 2));

if (!disarm) {
  console.log('\npreflight, are the documents served:');
  await assertDocumentsAreServed();
}

if (!apply) {
  console.log('\nRead-only run, nothing written. Pass --apply to write.');
  process.exit(0);
}

await reference.set(target, {merge: false});
const after = await reference.get();
console.log('\nwritten. config/legal is now:');
console.log(JSON.stringify(after.data(), null, 2));
console.log(
  disarm
    ? '\nThe gate is disarmed. No account is asked to accept anything.'
    : '\nThe gate is armed. Every account that has not accepted ' +
        `${target.requiredVersion} meets the consent screen within 15 minutes.\n` +
        'Accept the terms once on the App Review demo account now, or the ' +
        'reviewer meets that screen first.',
);
process.exit(0);
