#!/usr/bin/env node
//
// Proves — or disproves — that an iOS push can actually reach a device.
//
// Two independent things have to be true, and on 10 October 2026 neither was:
//
//  1. The device obtained an APNs token and the app stored the resulting FCM
//     registration token in `user_push_tokens/{uid}`. Before the fix in
//     `lib/services/web_messaging_helper.dart`, iOS never did: `getToken()`
//     throws `apns-token-not-set` until the system has delivered the APNs
//     token, and the helper swallowed that without retrying.
//  2. The Firebase project holds an APNs **authentication key** (or
//     certificate) for the app's bundle id. Firebase Console reported none at
//     all for `org.adfoot.app`, so FCM had no way to talk to Apple.
//
// Neither is visible from the other side: with no token, a send reports
// `token_missing` and never reaches APNs; with no APNs credential, FCM answers
// `THIRD_PARTY_AUTH_ERROR` but only once it has a token to route. There is no
// API that reports whether the APNs key is loaded, which is exactly why this
// script exists: a send is the only thing that answers the question.
//
// A dry run (the default) validates the message without delivering it, and
// without contacting Apple — so a dry-run success proves the token is
// well-formed and proves nothing about APNs. `--send` performs the real send:
// that is the one that returns THIRD_PARTY_AUTH_ERROR when the credential is
// missing, and the one that makes a notification appear on the device.
//
// Usage:
//   node scripts/check-ios-push-delivery.mjs --environment production --list
//   node scripts/check-ios-push-delivery.mjs --environment production \
//     --uid UID_DU_COMPTE [--send]
//
// Credentials resolve the way every other operational script here does them:
// `--credentials`, then GOOGLE_APPLICATION_CREDENTIALS, then the per-project
// ops key derived from the project id. No path to a key file is written down
// in this repository -- a committed one tells a reader exactly which file to
// go looking for, and test/sign_in_never_hangs_guardrails_test enforces it.
//
// Never prints a registration token: they are per-install secrets.

import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);

function resolveRepoPath(candidate) {
  if (!candidate) return '';
  return path.isAbsolute(candidate) ? candidate : path.join(repoRoot, candidate);
}

function resolveCredentialsPath(explicit, projectId) {
  const candidates = [
    explicit,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY_PATH,
    path.join('.credentials', `${projectId}-ops.json`),
  ]
    .map(resolveRepoPath)
    .filter(Boolean);

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or create .credentials/<project>-ops.json.',
  );
}

function parseArgs(argv) {
  const args = new Map();
  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    if (!current.startsWith('--')) continue;
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      args.set(current.slice(2), true);
    } else {
      args.set(current.slice(2), next);
      i += 1;
    }
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
const environment = args.get('environment');
const explicitCredentials =
  typeof args.get('credentials') === 'string' ? args.get('credentials') : '';
const uid = typeof args.get('uid') === 'string' ? args.get('uid').trim() : '';
const wantsList = args.get('list') === true;
const wantsSend = args.get('send') === true;

if (!['staging', 'production'].includes(environment)) {
  console.error(
    'Expected --environment staging|production (then --list, or --uid UID [--send])',
  );
  process.exit(2);
}
if (!wantsList && !uid) {
  console.error('Expected --uid UID, or --list to enumerate registered tokens');
  process.exit(2);
}
if (process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Refusing to run against an emulator: this check is about production delivery');
  process.exit(2);
}

const projectId = `adfoot-${environment}`;
const credentialsPath = resolveCredentialsPath(explicitCredentials, projectId);
const account = JSON.parse(await readFile(credentialsPath, 'utf8'));
// Same guard as smoke-release-candidate.mjs: the target is stated twice and
// both statements must agree before any cloud client is created.
if (account.type !== 'service_account' || account.project_id !== projectId) {
  console.error(`Project/credentials mismatch: key is for ${account.project_id}, asked for ${projectId}`);
  process.exit(2);
}

const { cert, initializeApp } = await import('firebase-admin/app');
const { getFirestore } = await import('firebase-admin/firestore');
const { getMessaging } = await import('firebase-admin/messaging');

const app = initializeApp({ credential: cert(account), projectId });
const db = getFirestore(app);
const messaging = getMessaging(app);

if (wantsList) {
  const snapshot = await db.collection('user_push_tokens').limit(100).get();
  console.log(`user_push_tokens in ${projectId}: ${snapshot.size}`);
  for (const doc of snapshot.docs) {
    const token = doc.data()?.token;
    const present = typeof token === 'string' && token.trim().length > 0;
    const user = await db.collection('users').doc(doc.id).get();
    console.log(
      `  ${doc.id}  role=${user.data()?.role ?? '-'}  token=${present ? 'present' : 'EMPTY'}` +
        `  updatedAt=${doc.data()?.updatedAt?.toDate?.().toISOString() ?? '-'}`,
    );
  }
  if (snapshot.empty) {
    console.log('\nNo device has registered a token. Nothing can be delivered to anyone.');
  }
  process.exit(0);
}

const tokenDoc = await db.collection('user_push_tokens').doc(uid).get();
const token = tokenDoc.data()?.token;
if (typeof token !== 'string' || !token.trim()) {
  console.error(
    `No push token stored for ${uid} in ${projectId}.\n` +
      '\n' +
      'That is itself the finding, not a setup error: the backend answers\n' +
      '"token_missing" for this account and no notification of any kind can\n' +
      'reach it. On iOS, check that the build carries the APNs-token wait in\n' +
      'WebMessagingHelper and that the user granted the notification prompt.',
  );
  process.exit(1);
}

const dryRun = !wantsSend;
try {
  await messaging.send(
    {
      token: token.trim(),
      notification: {
        title: 'Adfoot',
        body: 'Vérification de la remise des notifications.',
      },
      data: { type: 'delivery_check' },
      apns: { payload: { aps: { sound: 'default' } } },
      android: {
        priority: 'high',
        notification: { channelId: 'high_importance_channel', sound: 'default' },
      },
    },
    dryRun,
  );

  if (dryRun) {
    console.log(
      `Dry run accepted for ${uid}.\n` +
        '\n' +
        'This proves the token is well-formed and that FCM accepts the payload.\n' +
        'It does NOT prove the APNs credential is loaded: a dry run does not\n' +
        'contact Apple. Re-run with --send to settle that.',
    );
  } else {
    console.log(
      `Delivered to FCM for ${uid}.\n` +
        '\n' +
        'FCM accepted the message and had a credential to reach the push\n' +
        'service with. If the device is an iPhone and the notification\n' +
        'appears on it, the whole chain works: token, APNs key, entitlement.',
    );
  }
} catch (error) {
  const code = error?.errorInfo?.code ?? error?.code ?? 'unknown';
  console.error(`Send failed for ${uid}: ${code}`);
  if (error?.message) console.error(`  ${error.message}`);

  if (String(code).includes('third-party-auth-error')) {
    console.error(
      '\nThis is the APNs credential, not the token and not the app.\n' +
        'FCM has no way to authenticate with Apple for this bundle id.\n' +
        '\n' +
        `Firebase Console -> ${projectId} -> Project settings -> Cloud Messaging\n` +
        '  -> Apple app configuration -> APNs Authentication Key -> Upload\n' +
        '\n' +
        'One key (.p8, created under Keys in the Apple Developer portal) covers\n' +
        'both the development and production APNs environments, and every bundle\n' +
        'id in the Apple account — so the same file serves staging and production.',
    );
  } else if (String(code).includes('registration-token-not-registered')) {
    console.error(
      '\nThe token is dead: the app was uninstalled, its data cleared, or it was\n' +
        'restored onto another device. pruneUnregisteredToken clears these on a\n' +
        'real send; sign in again on the device to register a fresh one.',
    );
  }
  process.exit(1);
}
