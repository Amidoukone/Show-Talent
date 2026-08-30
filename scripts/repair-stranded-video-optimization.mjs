#!/usr/bin/env node

/**
 * Repairs videos whose optimization finished but whose Firestore state was
 * overwritten back to `processing` / `optimized: false`.
 *
 * The race this repairs is fixed at the source in
 * functions/src/upload_session.ts (finalizeUpload now decides the lifecycle
 * inside a transaction), but documents already stranded in production stay
 * stranded: nothing re-runs optimizeMp4Video, and adminSetVideoStatus refuses
 * to approve anything whose `optimized` is not true. The result is an upload
 * the player made, the admin can see, and nobody can publish.
 *
 * A document is only repaired when the optimizer demonstrably finished, which
 * is decidable from the document alone:
 *
 *   - `playback.sources` holds at least one source, and
 *   - `videoUrl` is set, and
 *   - `playback.sources[0].path` matches this video's canonical object path.
 *
 * That triple is written by exactly one place -- optimizeMp4Video's terminal
 * `videoRef.set` -- and by nothing else in the codebase. finalizeUpload never
 * writes `playback`, and the client cannot write to `videos/*` at all
 * (firestore.rules: `allow create: if false`).
 *
 * Everything else is left alone: a video genuinely still encoding has no
 * playback contract, an errored one carries `status: "error"`, and a live one
 * is never touched because `under_review` is only ever written over
 * `processing`.
 *
 * Usage:
 *   node scripts/repair-stranded-video-optimization.mjs --env production
 *   node scripts/repair-stranded-video-optimization.mjs --env production --apply
 *
 * Dry run is the default and prints the exact patch it would commit.
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
    return path.isAbsolute(explicit) ? explicit : path.resolve(repoRoot, explicit);
  }

  const fromEnv = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (fromEnv && existsSync(fromEnv)) return fromEnv;

  const conventional = path.join(repoRoot, '.credentials', `${projectId}-ops.json`);
  if (existsSync(conventional)) return conventional;

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or place ' +
      `.credentials/${projectId}-ops.json in the repository.`,
  );
}

/** The object path optimizeMp4Video publishes the delivered asset at. */
function canonicalStoragePath(videoId) {
  return `videos/${videoId}.mp4`;
}

/**
 * True when this document carries proof that optimizeMp4Video completed.
 *
 * Deliberately strict: three independent fields, all written by that single
 * terminal `set`, and the first source has to point at this video's own
 * object. A partial or foreign contract is not proof and is not repaired.
 */
function optimizationCompleted(videoId, data) {
  const playback = data.playback;
  if (!playback || typeof playback !== 'object') return false;

  const sources = Array.isArray(playback.sources) ? playback.sources : [];
  if (sources.length === 0) return false;

  const first = sources[0];
  if (!first || typeof first !== 'object') return false;
  if (typeof first.url !== 'string' || !first.url) return false;
  if (first.path !== canonicalStoragePath(videoId)) return false;

  return typeof data.videoUrl === 'string' && data.videoUrl.length > 0;
}

/** True when the document still claims the optimization has not happened. */
function stateDeniesOptimization(data) {
  return data.optimized !== true || data.status === 'processing';
}

/**
 * The states this repair must never touch.
 *
 * `error` is a real terminal failure and has to stay visible. `ready` and any
 * live/moderated state is already past review -- rewriting it would either
 * unpublish a public video or resurrect a rejected one.
 */
const UNTOUCHABLE_STATUSES = new Set([
  'error',
  'failed',
  'failure',
  'ready',
  'rejected',
  'removed',
  'hidden',
]);

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = String(args.get('env') ?? args.get('environment') ?? 'production');
  const apply = args.get('apply') === true || args.get('apply') === 'true';

  const configPath = path.join(repoRoot, 'config', 'mobile', `${environment}.json`);
  const config = await readJson(configPath, 'mobile config');
  const projectId = config.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error(`FIREBASE_PROJECT_ID missing from ${configPath}`);
  }

  const credentialsPath = resolveCredentialsPath(args, projectId);
  const serviceAccount = await readJson(credentialsPath, 'service account');

  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();

  console.log('Stranded video optimization repair');
  console.log(`Project: ${projectId}`);
  console.log(`Mode:    ${apply ? 'APPLY (writes Firestore)' : 'dry run'}`);
  console.log('');

  const snapshot = await db.collection('videos').get();

  const stranded = [];
  const skipped = [];

  snapshot.forEach((doc) => {
    const data = doc.data() ?? {};
    const status = typeof data.status === 'string' ? data.status : '';

    if (!stateDeniesOptimization(data)) return;

    if (UNTOUCHABLE_STATUSES.has(status)) {
      skipped.push({ id: doc.id, status, why: 'terminal or live status' });
      return;
    }

    if (!optimizationCompleted(doc.id, data)) {
      skipped.push({
        id: doc.id,
        status,
        why: 'no proof the optimizer finished (still encoding, or genuinely failed)',
      });
      return;
    }

    stranded.push({ id: doc.id, status, data });
  });

  if (skipped.length) {
    console.log(`Left untouched (${skipped.length}):`);
    for (const row of skipped) {
      console.log(`  ${row.id}  status=${row.status || '<none>'}  -- ${row.why}`);
    }
    console.log('');
  }

  if (!stranded.length) {
    console.log('No stranded video found. Nothing to repair.');
    return;
  }

  console.log(`Stranded, repairable (${stranded.length}):`);
  for (const row of stranded) {
    const sources = row.data.playback?.sources ?? [];
    const qualities = sources
      .map((source) => `${source.quality ?? '?'}@${source.bitrate ?? '?'}`)
      .join(', ');
    console.log(`  ${row.id}`);
    console.log(`    now:   status=${row.status} optimized=${row.data.optimized}`);
    console.log(`    after: status=under_review optimized=true`);
    console.log(`    proof: playback.sources = [${qualities}]`);
  }
  console.log('');

  if (!apply) {
    console.log('Dry run: nothing was written. Re-run with --apply to commit.');
    return;
  }

  for (const row of stranded) {
    // A transaction, and the same proof re-checked inside it: by the time this
    // runs, a concurrent finalizeUpload or an admin action may have moved the
    // document on, and this repair must never be the thing that overwrites it.
    const videoRef = db.collection('videos').doc(row.id);
    const outcome = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(videoRef);
      if (!snap.exists) return 'vanished';

      const data = snap.data() ?? {};
      const status = typeof data.status === 'string' ? data.status : '';
      if (UNTOUCHABLE_STATUSES.has(status)) return `moved on to ${status}`;
      if (!stateDeniesOptimization(data)) return 'already repaired';
      if (!optimizationCompleted(row.id, data)) return 'proof no longer holds';

      transaction.set(
        videoRef,
        {
          status: 'under_review',
          optimized: true,
          // Not touched on purpose: moderationStatus stays `pending`, so the
          // video enters review exactly where the optimizer meant to leave it,
          // and visibility/isPublic stay private until an admin approves.
          optimizationRepairedAt: new Date(),
        },
        { merge: true },
      );
      return 'repaired';
    });

    console.log(`  ${row.id}: ${outcome}`);
  }

  console.log('');
  console.log('Done. Re-run without --apply to confirm the collection is clean.');
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
