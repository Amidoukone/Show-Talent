#!/usr/bin/env node

/**
 * Gives already-published videos the thumbnail URL they were never written.
 *
 * The defect, fixed at the source in functions/src/storage_download_url.ts and
 * functions/src/upload_session.ts: a video document carried `thumbnailPath` (a
 * Storage object path) but no `thumbnail` (a URL a client can fetch). The URL
 * had exactly one writer — `optimizeMp4Video`, after FFmpeg — and that
 * function is triggered by the *video* object landing in Storage, while the
 * client uploads the still only afterwards. On a light clip or a weak
 * connection the optimizer reached the lookup before the still existed, wrote
 * nothing, and nothing ever looked again: no trigger fires for `thumbnails/`.
 *
 * What the user saw: every video in a player's profile grid rendered a
 * placeholder icon instead of a frame. The feed hid it, because there the
 * still is only a brief placeholder before the video itself renders.
 *
 * Documents already in production stay broken on their own — this repairs
 * them. The work is the same the server now does: find the object, make sure
 * it carries a Firebase download token, write the URL.
 *
 * Deliberately narrow:
 *   - only documents with no usable `thumbnail` are considered;
 *   - a document whose `thumbnail` is already an http(s) URL is never touched;
 *   - a video whose still genuinely does not exist in Storage is reported and
 *     left alone, because inventing a URL for a missing object would turn a
 *     clean fallback back into a broken image.
 *
 * Usage:
 *   node scripts/repair-video-thumbnails.mjs --env production
 *   node scripts/repair-video-thumbnails.mjs --env production --apply
 *
 * Dry run is the default and prints exactly what it would write.
 */

import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import { randomUUID } from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

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

/** The same rule the mobile model applies: a path is not an address. */
function isFetchableUrl(value) {
  return (
    typeof value === 'string' &&
    (value.startsWith('http://') || value.startsWith('https://'))
  );
}

/** Mirrors resolveThumbnailObjectPath in functions/src/storage_download_url.ts. */
async function findThumbnailObject(bucket, videoId, recordedPath) {
  if (typeof recordedPath === 'string' && recordedPath.trim()) {
    const recorded = recordedPath.trim();
    const [exists] = await bucket.file(recorded).exists();
    if (exists) return recorded;
  }

  for (const candidate of [
    `thumbnails/thumbnail_${videoId}.jpg`,
    `thumbnails/thumbnail_${videoId}.jpeg`,
    `thumbnails/thumbnail_${videoId}.png`,
  ]) {
    const [exists] = await bucket.file(candidate).exists();
    if (exists) return candidate;
  }

  return '';
}

/** Mirrors ensureDownloadToken: reuse before mint, so links stay stable. */
async function ensureDownloadToken(bucket, objectPath, apply) {
  const file = bucket.file(objectPath);
  const [metadata] = await file.getMetadata();
  const existing = metadata?.metadata?.firebaseStorageDownloadTokens;
  if (typeof existing === 'string' && existing.trim()) {
    return { token: existing.trim(), minted: false };
  }

  const token = randomUUID();
  if (apply) {
    await file.setMetadata({
      metadata: { ...(metadata?.metadata ?? {}), firebaseStorageDownloadTokens: token },
    });
  }
  return { token, minted: true };
}

function buildStorageDownloadUrl(bucketName, objectPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${
    encodeURIComponent(objectPath)
  }?alt=media&token=${token}`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = String(args.get('env') ?? args.get('environment') ?? 'production');
  const apply = args.get('apply') === true || args.get('apply') === 'true';

  const configPath = path.join(repoRoot, 'config', 'mobile', `${environment}.json`);
  const config = await readJson(configPath, 'mobile config');
  const projectId = config.FIREBASE_PROJECT_ID;
  const bucketName = config.FIREBASE_STORAGE_BUCKET;
  if (!projectId) throw new Error(`FIREBASE_PROJECT_ID missing from ${configPath}`);
  if (!bucketName) throw new Error(`FIREBASE_STORAGE_BUCKET missing from ${configPath}`);

  const credentialsPath = resolveCredentialsPath(args, projectId);
  const serviceAccount = await readJson(credentialsPath, 'service account');
  if (serviceAccount.project_id !== projectId) {
    throw new Error(
      `Project/credentials mismatch: key is for ${serviceAccount.project_id}, asked for ${projectId}`,
    );
  }

  initializeApp({ credential: cert(serviceAccount), projectId, storageBucket: bucketName });
  const db = getFirestore();
  const bucket = getStorage().bucket(bucketName);

  console.log('Video thumbnail URL repair');
  console.log(`Project: ${projectId}`);
  console.log(`Bucket:  ${bucketName}`);
  console.log(`Mode:    ${apply ? 'APPLY (writes Firestore + object metadata)' : 'dry run'}`);
  console.log('');

  const snapshot = await db.collection('videos').get();

  const repairable = [];
  const missingStill = [];
  let alreadyFine = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    if (isFetchableUrl(data.thumbnail) || isFetchableUrl(data.thumbnailUrl)) {
      alreadyFine += 1;
      continue;
    }

    const objectPath = await findThumbnailObject(bucket, doc.id, data.thumbnailPath);
    if (!objectPath) {
      missingStill.push({ id: doc.id, status: data.status ?? '<none>' });
      continue;
    }

    const { token, minted } = await ensureDownloadToken(bucket, objectPath, apply);
    repairable.push({
      id: doc.id,
      status: data.status ?? '<none>',
      objectPath,
      minted,
      url: buildStorageDownloadUrl(bucketName, objectPath, token),
    });
  }

  console.log(`Already carrying a usable thumbnail URL: ${alreadyFine}`);

  if (missingStill.length) {
    console.log('');
    console.log(`No still in Storage (left alone, ${missingStill.length}):`);
    for (const row of missingStill) {
      console.log(`  ${row.id}  status=${row.status}`);
    }
    console.log(
      '  These render the grid fallback, which is the correct outcome for a\n' +
        '  video that has no frame. Inventing a URL would turn that clean\n' +
        '  fallback into a broken image.',
    );
  }

  if (!repairable.length) {
    console.log('');
    console.log('Nothing to repair.');
    return;
  }

  console.log('');
  console.log(`Repairable (${repairable.length}):`);
  for (const row of repairable) {
    console.log(`  ${row.id}  status=${row.status}`);
    console.log(`    object: ${row.objectPath}${row.minted ? '  (token minted)' : '  (token reused)'}`);
  }

  if (!apply) {
    console.log('');
    console.log('Dry run: nothing was written. Re-run with --apply to commit.');
    return;
  }

  // `thumbnail` and nothing else -- deliberately no `updatedAt`.
  //
  // ProfileRepository.fetchUserVideos orders a player's grid by `updatedAt`
  // descending, and the home feed falls back to the same field whenever its
  // own index is unavailable (VideoRepository._legacyOrderField). Stamping it
  // here would reorder every repaired player's profile into the order this
  // script happened to walk the collection, and could reshuffle the public
  // feed with it. Backfilling a derived display field must not move anything.
  let written = 0;
  for (const row of repairable) {
    await db.collection('videos').doc(row.id).set(
      { thumbnail: row.url },
      { merge: true },
    );
    written += 1;
  }

  console.log('');
  console.log(`Repaired ${written} video(s).`);
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
