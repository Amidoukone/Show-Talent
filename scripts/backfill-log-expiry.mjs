#!/usr/bin/env node

/**
 * Gives the diagnostic logs written before the TTL policy an expiry date.
 *
 * `client_logs` and `video_action_logs` had no retention at all: no TTL
 * policy, no purge job, and `fieldOverrides` empty in firestore.indexes.json.
 * They grew for the life of the project. The policy now exists and
 * `logClientEvents` / `videoActionLog` stamp `expireAt` on every new
 * document — but Firestore TTL ignores a document that has no such field, so
 * everything written before the deploy would stay forever.
 *
 * Default mode is a grace period rather than the real retention: every
 * existing document expires `--grace-days` from now, so nothing is deleted
 * today and the whole history stays readable while a release is being
 * validated on a device. The collection still stops growing without bound,
 * which was the point.
 *
 * `--policy` applies the real retention instead (from `createdAt`: 90 days for
 * errors, 30 for telemetry). That deletes anything already past it on the next
 * TTL pass, and it cannot be undone.
 *
 * Usage:
 *   node scripts/backfill-log-expiry.mjs --env production
 *   node scripts/backfill-log-expiry.mjs --env production --apply
 *   node scripts/backfill-log-expiry.mjs --env production --policy --apply
 *
 * Dry run is the default. Idempotent: a document that already carries
 * `expireAt` is never touched.
 */

import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

/** Must match CLIENT_LOG_RETENTION_DAYS in functions/src/actions.ts. */
const ERROR_RETENTION_DAYS = 90;
/** Must match TELEMETRY_LOG_RETENTION_DAYS in functions/src/actions.ts. */
const TELEMETRY_RETENTION_DAYS = 30;

const DEFAULT_GRACE_DAYS = 30;
const BATCH_LIMIT = 400;
const DAY_MS = 24 * 60 * 60 * 1000;

function parseArgs(argv) {
  const args = new Map();
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;

    const eq = token.indexOf('=');
    if (eq >= 0) {
      args.set(token.slice(2, eq), token.slice(eq + 1));
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) {
      args.set(key, next);
      i += 1;
    } else {
      args.set(key, true);
    }
  }
  return args;
}

async function readJson(filePath, label) {
  try {
    return JSON.parse(await readFile(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`Unable to read ${label} at ${filePath}. ${error.message}`);
  }
}

function resolveCredentialsPath(args, projectId) {
  const explicit = args.get('credentials');
  if (typeof explicit === 'string') {
    return path.isAbsolute(explicit)
      ? explicit
      : path.resolve(repoRoot, explicit);
  }

  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (fromEnv && existsSync(fromEnv)) return fromEnv;

  const conventional = path.join(
    repoRoot,
    '.credentials',
    `${projectId}-ops.json`,
  );
  if (existsSync(conventional)) return conventional;

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or place ' +
      `.credentials/${projectId}-ops.json in the repository.`,
  );
}

function createdAtMillis(data) {
  const seconds = data?.createdAt?._seconds ?? data?.createdAt?.seconds;
  if (typeof seconds === 'number') return seconds * 1000;
  if (typeof data?.createdAt?.toMillis === 'function') {
    return data.createdAt.toMillis();
  }
  return 0;
}

/** Retention in days that the real policy gives this document. */
function retentionDaysFor(collection, data) {
  if (collection === 'video_action_logs') return ERROR_RETENTION_DAYS;
  return data?.level === 'error'
    ? ERROR_RETENTION_DAYS
    : TELEMETRY_RETENTION_DAYS;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = String(
    args.get('env') ?? args.get('environment') ?? 'production',
  );
  const apply = args.get('apply') === true || args.get('apply') === 'true';
  const usePolicy = args.get('policy') === true || args.get('policy') === 'true';
  const graceDays = Number(args.get('grace-days') ?? DEFAULT_GRACE_DAYS);

  if (!Number.isFinite(graceDays) || graceDays <= 0) {
    throw new Error('--grace-days must be a positive number of days');
  }

  const configPath = path.join(
    repoRoot,
    'config',
    'mobile',
    `${environment}.json`,
  );
  const config = await readJson(configPath, 'mobile config');
  const projectId = config.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error(`FIREBASE_PROJECT_ID missing from ${configPath}`);
  }

  const credentialsPath = resolveCredentialsPath(args, projectId);
  const serviceAccount = await readJson(credentialsPath, 'service account');

  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();

  const now = Date.now();

  console.log('Diagnostic log expiry backfill');
  console.log(`Project: ${projectId}`);
  console.log(
    `Mode:    ${apply ? 'APPLY (writes Firestore)' : 'dry run'} — ` +
      (usePolicy
        ? `real retention (${ERROR_RETENTION_DAYS}d errors / ` +
          `${TELEMETRY_RETENTION_DAYS}d telemetry, from createdAt)`
        : `grace period of ${graceDays} days from now`),
  );
  console.log('');

  let totalPlanned = 0;
  let totalImmediate = 0;

  for (const collection of ['client_logs', 'video_action_logs']) {
    const snapshot = await db.collection(collection).get();

    const planned = [];
    let alreadyStamped = 0;
    let undatable = 0;

    snapshot.forEach((doc) => {
      const data = doc.data() ?? {};
      // Idempotent: never overwrite an expiry, whether it came from the
      // Functions or from an earlier run of this script.
      if (data.expireAt) {
        alreadyStamped += 1;
        return;
      }

      let expireAtMs;
      if (usePolicy) {
        const created = createdAtMillis(data);
        if (!created) {
          // No createdAt means the real policy has no anchor. Falling back to
          // the grace period keeps the document bounded instead of leaving it
          // immortal, and never deletes something whose age is unknown.
          undatable += 1;
          expireAtMs = now + graceDays * DAY_MS;
        } else {
          expireAtMs = created + retentionDaysFor(collection, data) * DAY_MS;
        }
      } else {
        expireAtMs = now + graceDays * DAY_MS;
      }

      planned.push({ ref: doc.ref, expireAt: new Date(expireAtMs) });
      if (expireAtMs < now) totalImmediate += 1;
    });

    totalPlanned += planned.length;

    console.log(`- ${collection}`);
    console.log(`    total:            ${snapshot.size}`);
    console.log(`    already stamped:  ${alreadyStamped}`);
    console.log(`    to stamp:         ${planned.length}`);
    if (undatable) {
      console.log(`    no createdAt:     ${undatable} (given the grace period)`);
    }

    if (!apply || planned.length === 0) continue;

    for (let index = 0; index < planned.length; index += BATCH_LIMIT) {
      const slice = planned.slice(index, index + BATCH_LIMIT);
      const batch = db.batch();
      for (const entry of slice) {
        batch.update(entry.ref, { expireAt: entry.expireAt });
      }
      await batch.commit();
      console.log(`    written:          ${index + slice.length}`);
    }
  }

  console.log('');
  console.log(`Documents to stamp: ${totalPlanned}`);
  console.log(
    `Eligible for deletion on the next TTL pass: ${totalImmediate}`,
  );

  if (!apply) {
    console.log('');
    console.log('Dry run: nothing was written. Re-run with --apply to commit.');
  }
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
