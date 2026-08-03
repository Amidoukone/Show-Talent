#!/usr/bin/env node

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const args = new Map();

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    if (!current.startsWith('--')) {
      continue;
    }

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

function getIntArg(args, names, fallback) {
  const raw = getStringArg(args, names, String(fallback));
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function getBoolArg(args, names, fallback = false) {
  for (const name of names) {
    if (args.has(name)) {
      const value = args.get(name);
      if (value === true) return true;
      return ['1', 'true', 'yes', 'y'].includes(String(value).trim().toLowerCase());
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
  if (!value) {
    throw new Error(`Missing ${key} in ${configPath}.`);
  }
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
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or create .credentials/<project>-ops.json.',
  );
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function compact(value, maxLength = 180) {
  const text = String(value ?? '').replace(/\s+/g, ' ').trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 3)}...`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const limit = getIntArg(args, ['limit'], 40);
  const inspectUsers = getBoolArg(args, ['inspect-users'], false);
  const sourceFilter = getStringArg(
    args,
    ['source'],
    'ProfileController,AppCheckService,CallableAuthGuard',
  )
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);

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
  const serviceAccount = await readJsonFile(credentialsPath, 'service account');

  if (getApps().length === 0) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId,
    });
  }

  const db = getFirestore();
  const snapshot = await db
    .collection('client_logs')
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  const rows = snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((row) => row.level === 'error')
    .filter((row) => {
      const source = String(row.source ?? '');
      return sourceFilter.some((prefix) => source.startsWith(prefix));
    });

  console.log(`Recent client errors: ${rows.length}/${snapshot.size}`);
  console.log(`Project: ${projectId}`);
  for (const row of rows) {
    const createdAt = toDate(row.createdAt)?.toISOString() || '<unknown>';
    const metadata = row.metadata && typeof row.metadata === 'object' ?
      row.metadata :
      {};
    console.log('');
    console.log(`- ${createdAt} ${row.source || '<unknown>'}`);
    if (row.userId) console.log(`  userId: ${row.userId}`);
    console.log(`  message: ${compact(row.message)}`);
    if (metadata.code) console.log(`  code: ${metadata.code}`);
    if (metadata.uidMatchesAuth !== undefined) {
      console.log(`  uidMatchesAuth: ${metadata.uidMatchesAuth}`);
    }
    if (metadata.role) console.log(`  role: ${metadata.role}`);
    if (metadata.patchKeys) console.log(`  patchKeys: ${metadata.patchKeys}`);
    if (metadata.byteSize) console.log(`  byteSize: ${metadata.byteSize}`);
    if (metadata.hasFile !== undefined) console.log(`  hasFile: ${metadata.hasFile}`);
    if (metadata.hasBytes !== undefined) console.log(`  hasBytes: ${metadata.hasBytes}`);
    if (metadata.hasStream !== undefined) console.log(`  hasStream: ${metadata.hasStream}`);
    if (metadata.error) console.log(`  error: ${compact(metadata.error, 240)}`);
  }

  if (inspectUsers) {
    const userIds = Array.from(
      new Set(rows.map((row) => String(row.userId ?? '')).filter(Boolean)),
    );

    console.log('');
    console.log(`User access snapshots: ${userIds.length}`);
    for (const userId of userIds) {
      const doc = await db.collection('users').doc(userId).get();
      if (!doc.exists) {
        console.log(`- ${userId}: missing`);
        continue;
      }
      const data = doc.data() || {};
      console.log(
        `- ${userId}: role=${data.role || '<missing>'}, ` +
          `authDisabled=${data.authDisabled === true}, ` +
          `profileVerified=${data.profileVerified === true}, ` +
          `profileVerificationStatus=${data.profileVerificationStatus || '<missing>'}, ` +
          `cvUrl=${typeof data.cvUrl === 'string' && data.cvUrl ? 'present' : 'missing'}`,
      );
    }
  }
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
