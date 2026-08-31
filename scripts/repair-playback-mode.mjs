#!/usr/bin/env node

/**
 * Restates `playback.mode` on video documents whose contract contradicts
 * their own `sources` array.
 *
 * `optimizeMp4Video` used to hard-code `mode: "mp4_only"` even when it had
 * just published a companion rendition beside the master, so every
 * multi-source video in adfoot-production advertises a single-source
 * contract. `buildPlaybackContract` (functions/src/index.ts) states the truth
 * since 2026-08-30, but only for videos optimized after that deploy: the four
 * already in production still carry the old label.
 *
 * Nothing plays wrong today -- both clients derive the real mode from
 * `sources` and never read this field (`VideoSourceSelector.preferredSource`
 * takes the sources array; `mode` is parsed into `Video.playback` and used
 * nowhere). That is exactly what makes it worth repairing rather than
 * ignoring: a field that is wrong and unread is a trap for whoever reads it
 * next. `list-ready-playback-contracts.js` already reports
 * `readyMultiRenditionMp4: 0` for a project where two of four videos genuinely
 * carry two renditions.
 *
 * Deliberately narrow. It writes the single field path `playback.mode` and
 * nothing else -- not `sources`, not `fallback`, not `sourceAsset`, not
 * `videoUrl`. The sibling `backfill-playback-contract.js` rebuilds a whole
 * contract from scratch and collapses `sources` to one canonical entry;
 * running it here would delete the 1080p master from the two multi-rendition
 * videos and leave every viewer on 480p. Do not use it for this.
 *
 * Dry run unless `--apply` is passed. Exits 1 while drift remains, so a gate
 * can read it.
 *
 * Usage:
 *   node scripts/repair-playback-mode.mjs \
 *     [--environment production] [--credentials .credentials/<project>-ops.json] \
 *     [--scan 200] [--video-id <docId>] [--apply]
 */

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

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
  try {
    return JSON.parse(await readFile(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`Unable to read ${label} at ${filePath}: ${error.message}`);
  }
}

async function resolveProjectId(args) {
  const explicit = getStringArg(args, ['project-id', 'project']);
  if (explicit) return explicit;

  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const configPath = resolveRepoPath(
    path.join('config', 'mobile', `${environment}.json`),
  );
  if (!existsSync(configPath)) {
    throw new Error(
      `Unknown environment "${environment}": ${configPath} does not exist.`,
    );
  }

  const config = await readJsonFile(configPath, 'mobile environment config');
  const projectId = (config.FIREBASE_PROJECT_ID || '').trim();
  if (!projectId) {
    throw new Error(`${configPath} declares no FIREBASE_PROJECT_ID.`);
  }
  return projectId;
}

function resolveCredentialsPath(args, projectId) {
  const explicit = getStringArg(args, ['credentials', 'service-account']);
  const candidates = [
    explicit,
    process.env.GOOGLE_APPLICATION_CREDENTIALS || '',
    projectId ? path.join('.credentials', `${projectId}-ops.json`) : '',
  ]
    .filter(Boolean)
    .map(resolveRepoPath);

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or create .credentials/<project>-ops.json.',
  );
}

/**
 * The same test the mobile model applies (`VideoSource.isMp4` in
 * lib/models/video.dart): a source counts only if it is a usable MP4, so a
 * malformed entry cannot inflate the count and promote a single-rendition
 * video to `multi_rendition_mp4`.
 */
function isUsableMp4Source(source) {
  if (!source || typeof source !== 'object') return false;

  const url = String(source.url ?? '').trim().toLowerCase();
  if (!url) return false;

  const type = String(source.type ?? '').trim().toLowerCase();
  const sourcePath = String(source.path ?? '').trim().toLowerCase();

  return type === 'mp4' || url.includes('.mp4') || sourcePath.endsWith('.mp4');
}

/**
 * The rule `buildPlaybackContract` applies, kept identical on purpose: one
 * published source is `mp4_only`, more than one is an adaptive ladder.
 */
function expectedMode(sources) {
  return sources.length > 1 ? 'multi_rendition_mp4' : 'mp4_only';
}

async function fetchDocs(db, args) {
  const videoId = getStringArg(args, ['video-id', 'video']);
  if (videoId) {
    const doc = await db.collection('videos').doc(videoId).get();
    return doc.exists ? [doc] : [];
  }

  const scan = Number.parseInt(getStringArg(args, ['scan'], '200'), 10);
  if (!Number.isFinite(scan) || scan <= 0) {
    throw new Error(`Invalid --scan: ${getStringArg(args, ['scan'])}`);
  }

  const snapshot = await db
    .collection('videos')
    .orderBy('updatedAt', 'desc')
    .limit(scan)
    .get();

  return snapshot.docs;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const apply = args.has('apply');

  const projectId = await resolveProjectId(args);
  const credentialsPath = resolveCredentialsPath(args, projectId);
  const serviceAccount = await readJsonFile(credentialsPath, 'service account');

  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();

  const docs = await fetchDocs(db, args);

  const drifted = [];
  let scanned = 0;
  let withoutContract = 0;
  let alreadyCorrect = 0;

  for (const doc of docs) {
    scanned += 1;
    const data = doc.data() || {};
    const playback = data.playback;

    if (!playback || typeof playback !== 'object') {
      withoutContract += 1;
      continue;
    }

    const sources = (Array.isArray(playback.sources) ? playback.sources : [])
      .filter(isUsableMp4Source);
    const expected = expectedMode(sources);
    const current =
      typeof playback.mode === 'string' ? playback.mode.trim() : null;

    if (current === expected) {
      alreadyCorrect += 1;
      continue;
    }

    drifted.push({
      id: doc.id,
      ref: doc.ref,
      status: data.status ?? null,
      sourceCount: sources.length,
      heights: sources.map((source) => source.height ?? null),
      current,
      expected,
    });
  }

  console.log(`Project:      ${projectId}`);
  console.log(`Credentials:  ${credentialsPath}`);
  console.log(`Mode:         ${apply ? 'APPLY (writes playback.mode)' : 'dry run'}`);
  console.log('');
  console.log(
    `Scanned ${scanned} video documents: ${alreadyCorrect} already correct, ` +
      `${withoutContract} without a playback contract, ${drifted.length} drifted.`,
  );

  if (drifted.length === 0) {
    console.log('');
    console.log('Every playback contract states what its sources show.');
    return 0;
  }

  console.log('');
  for (const entry of drifted) {
    console.log(
      `- ${entry.id} [${entry.status ?? 'no status'}] ` +
        `${entry.sourceCount} mp4 source(s) ${JSON.stringify(entry.heights)}: ` +
        `${entry.current ?? '(absent)'} -> ${entry.expected}`,
    );
  }

  if (!apply) {
    console.log('');
    console.log('Dry run: nothing was written. Re-run with --apply to repair.');
    return 1;
  }

  let repaired = 0;
  const failures = [];

  for (const entry of drifted) {
    try {
      // A single field path. `sources`, `fallback`, `sourceAsset` and
      // `videoUrl` are left exactly as the optimizer wrote them.
      await entry.ref.update({ 'playback.mode': entry.expected });
      repaired += 1;
    } catch (error) {
      failures.push({ id: entry.id, message: error.message });
    }
  }

  console.log('');
  console.log(`Repaired ${repaired} of ${drifted.length} documents.`);

  if (failures.length > 0) {
    for (const failure of failures) {
      console.log(`- FAILED ${failure.id}: ${failure.message}`);
    }
    return 1;
  }

  return 0;
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
