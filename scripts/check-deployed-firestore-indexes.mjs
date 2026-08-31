#!/usr/bin/env node

/**
 * Compares `firestore.indexes.json` with the indexes actually deployed.
 *
 * The sibling gate `check-deployed-firebase-rules.mjs` answers the same
 * question for rules, and rules fail loudly: a denied write surfaces as an
 * error the user sees. A missing index does not. Firestore answers
 * `code: 9 FAILED_PRECONDITION`, the repository catches it like any other
 * failure, and the screen shows an empty list — the feed, the offers tab or
 * the notification list simply looks like it has nothing in it. That is the
 * exact shape of a silent production failure, and nothing in this repo
 * detected it before a user reported it.
 *
 * A `CREATING` index is reported as a failure on purpose: it is not yet
 * serving queries, so shipping a build that depends on it is the same
 * outage as never having deployed it, only shorter.
 *
 * Usage:
 *   node scripts/check-deployed-firestore-indexes.mjs \
 *     [--environment production] [--credentials .credentials/<project>-ops.json]
 */

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert } from 'firebase-admin/app';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const args = new Map();

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    if (!current.startsWith('--')) continue;

    const eqIndex = current.indexOf('=');
    if (eqIndex >= 0) {
      args.set(current.slice(2, eqIndex), current.slice(eqIndex + 1));
      continue;
    }

    const key = current.slice(2);
    const next = argv[index + 1];
    if (next && !next.startsWith('--')) {
      args.set(key, next);
      index += 1;
    } else {
      args.set(key, true);
    }
  }

  return args;
}

function getStringArg(args, names, fallback = '') {
  for (const name of names) {
    if (args.has(name)) {
      const value = args.get(name);
      return value === true ? 'true' : String(value);
    }
  }
  return fallback;
}

function resolveRepoPath(candidate) {
  if (!candidate) return '';
  return path.isAbsolute(candidate) ? candidate : path.resolve(repoRoot, candidate);
}

async function readJsonFile(filePath, label) {
  let raw = '';
  try {
    raw = await readFile(filePath, 'utf8');
  } catch (error) {
    throw new Error(`Unable to read ${label} at ${filePath}. ${error.message}`);
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`Invalid JSON in ${label} at ${filePath}. ${error.message}`);
  }
}

function requireConfigValue(config, key, configPath) {
  const value = String(config[key] ?? '').trim();
  if (!value) throw new Error(`Missing ${key} in ${configPath}.`);
  return value;
}

function resolveCredentialsPath(args, projectId) {
  const explicit = getStringArg(args, ['credentials', 'service-account']);
  const fromEnv =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY_PATH ||
    '';

  const candidates = [
    explicit,
    fromEnv,
    projectId ? path.join('.credentials', `${projectId}-ops.json`) : '',
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

async function getAccessToken(credentialsPath) {
  const serviceAccount = await readJsonFile(credentialsPath, 'service account');
  const credential = cert(serviceAccount);
  const token = await credential.getAccessToken();
  if (!token?.access_token) {
    throw new Error('Service account did not return an OAuth access token.');
  }
  return token.access_token;
}

async function fetchJson(url, accessToken) {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const body = await response.text();

  if (!response.ok) {
    throw new Error(`GET ${url} failed (HTTP ${response.status}). ${body}`);
  }

  return body ? JSON.parse(body) : {};
}

/**
 * The identity of an index, as the two sides describe it differently.
 *
 * The deployed side always appends `__name__` and the local file never
 * mentions it, so it is dropped from both. `order` and `arrayConfig` are
 * mutually exclusive; whichever is present is what makes two same-field
 * indexes different objects.
 */
function indexKey(collectionGroup, queryScope, fields) {
  const parts = (fields ?? [])
    .filter((field) => field.fieldPath !== '__name__')
    .map((field) => {
      const mode =
        field.order ||
        field.arrayConfig ||
        (field.vectorConfig ? 'VECTOR' : '') ||
        'UNSPECIFIED';
      return `${field.fieldPath}:${mode}`;
    });

  return `${collectionGroup} [${queryScope || 'COLLECTION'}] ${parts.join(' , ')}`;
}

function deployedCollectionGroup(indexName) {
  const afterGroups = String(indexName ?? '').split('/collectionGroups/')[1] || '';
  return afterGroups.split('/indexes/')[0] || '<unknown>';
}

async function listDeployedIndexes(projectId, accessToken) {
  // `pageSize` is rejected by this endpoint (it accepts 0 and nothing else),
  // so paging is driven by the token alone.
  const base =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    '/databases/(default)/collectionGroups/-/indexes';

  const collected = [];
  let pageToken = '';

  do {
    const url = pageToken ? `${base}?pageToken=${encodeURIComponent(pageToken)}` : base;
    const page = await fetchJson(url, accessToken);
    collected.push(...(page.indexes ?? []));
    pageToken = page.nextPageToken ?? '';
  } while (pageToken);

  return collected;
}

/**
 * The TTL policies Firestore is really applying, keyed `collection/field`.
 *
 * `firestore.indexes.json` declares them under `fieldOverrides`, but a
 * declared TTL and an active one are different facts: the policy takes
 * minutes to arm after a deploy, and until it is `ACTIVE` nothing is being
 * deleted. `client_logs` and `video_action_logs` are the two collections
 * that grow without a ceiling, so an unarmed policy here is a bill, not a
 * bug report.
 */
async function listTtlStates(projectId, accessToken) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    '/databases/(default)/collectionGroups/-/fields' +
    `?filter=${encodeURIComponent('ttlConfig:*')}`;

  const states = new Map();
  const page = await fetchJson(url, accessToken);

  for (const field of page.fields ?? []) {
    const name = String(field.name ?? '');
    const collection = deployedCollectionGroup(name.replace('/fields/', '/indexes/'));
    const fieldPath = name.split('/fields/')[1] || '<unknown>';
    states.set(`${collection}/${fieldPath}`, field.ttlConfig?.state ?? 'UNKNOWN');
  }

  return states;
}

async function main() {
  if (typeof fetch !== 'function') {
    throw new Error('This script requires Node.js 18+ with global fetch.');
  }

  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const configPath = resolveRepoPath(
    getStringArg(
      args,
      ['config', 'config-path'],
      path.join('config', 'mobile', `${environment}.json`),
    ),
  );
  const config = await readJsonFile(configPath, 'mobile config');
  const projectId = requireConfigValue(config, 'FIREBASE_PROJECT_ID', configPath);
  const credentialsPath = resolveCredentialsPath(args, projectId);
  const accessToken = await getAccessToken(credentialsPath);

  const localFile = await readJsonFile(
    path.join(repoRoot, 'firestore.indexes.json'),
    'firestore.indexes.json',
  );
  const localIndexes = localFile.indexes ?? [];
  const localOverrides = localFile.fieldOverrides ?? [];

  const deployedIndexes = await listDeployedIndexes(projectId, accessToken);
  const deployedByKey = new Map();
  for (const index of deployedIndexes) {
    const key = indexKey(
      deployedCollectionGroup(index.name),
      index.queryScope,
      index.fields,
    );
    deployedByKey.set(key, index.state ?? 'UNKNOWN');
  }

  console.log('Firestore indexes deployed comparison');
  console.log(`Project: ${projectId}`);
  console.log(`Declared: ${localIndexes.length}   Deployed: ${deployedIndexes.length}`);
  console.log('');

  const missing = [];
  const notReady = [];
  const localKeys = new Set();

  for (const index of localIndexes) {
    const key = indexKey(index.collectionGroup, index.queryScope, index.fields);
    localKeys.add(key);

    const state = deployedByKey.get(key);
    if (!state) {
      missing.push(key);
    } else if (state !== 'READY') {
      notReady.push(`${key} (state=${state})`);
    }
  }

  // Not a failure: single-field and legacy indexes live in the project
  // without being declared, and `firebase deploy --only firestore:indexes`
  // only ever offers to delete them interactively. Printed so that the
  // number the deploy quotes is never a surprise.
  const undeclared = [...deployedByKey.keys()].filter((key) => !localKeys.has(key));

  for (const key of missing) console.log(`MISSING   ${key}`);
  for (const key of notReady) console.log(`NOT READY ${key}`);
  for (const key of undeclared) console.log(`EXTRA     ${key}`);
  if (!missing.length && !notReady.length && !undeclared.length) {
    console.log('Every declared index is deployed and READY, with no extras.');
  }

  let ttlProblems = [];
  try {
    const ttlStates = await listTtlStates(projectId, accessToken);
    console.log('');
    console.log('TTL policies');
    for (const override of localOverrides) {
      if (override.ttl !== true) continue;
      const key = `${override.collectionGroup}/${override.fieldPath}`;
      const state = ttlStates.get(key) ?? 'ABSENT';
      console.log(`- ${key}: ${state}`);
      if (state !== 'ACTIVE') ttlProblems.push(`${key} (${state})`);
    }
  } catch (error) {
    // A denied `fields.list` must not turn an index check into a failure:
    // the indexes above were compared successfully and that answer stands.
    console.log('');
    console.log(`TTL policies not readable with this credential: ${error.message}`);
  }

  console.log('');
  if (missing.length) {
    console.error(
      `${missing.length} declared index(es) are not deployed. ` +
        'Run: npm run firestore:indexes:deploy:production',
    );
  }
  if (notReady.length) {
    console.error(
      `${notReady.length} index(es) are still building and do not serve queries yet.`,
    );
  }
  if (ttlProblems.length) {
    console.error(`TTL policy not active for: ${ttlProblems.join(', ')}.`);
  }

  if (missing.length || notReady.length || ttlProblems.length) {
    process.exitCode = 1;
    return;
  }

  console.log(
    `All ${localIndexes.length} declared indexes are READY in ${projectId}.`,
  );
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
