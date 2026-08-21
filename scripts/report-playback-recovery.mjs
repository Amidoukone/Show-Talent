#!/usr/bin/env node

/**
 * Reports what playback recovery actually did on real devices.
 *
 * "Lecture interrompue. Réessayez." has two sources in SmartVideoPlayer and
 * they look identical on screen:
 *
 *   1. automatic recovery gave up  -> logged as play_error / recovery_exhausted
 *   2. the controller itself errored, with recovery still available
 *      -> shown straight from VideoPlayerValue.hasError, no give-up event
 *
 * Telling them apart from a screenshot is impossible; telling them apart from
 * the logs is trivial, because every recovery attempt is already recorded with
 * the reason that triggered it. That is what this reads.
 *
 * Each retry also carries `purgeCachedFile` / `preferDownloadedFile`, so after
 * the escalation fix (attempt 1 reuses the cache, later attempts discard it
 * and stream) the strategy is visible in the data rather than assumed.
 *
 * Reads `video_action_logs`, which the videoActionLog callable writes
 * unsampled -- unlike `client_logs`, where info entries are sampled at 2% in
 * production.
 *
 * Reads only. Requires the same read-only ops service account as the other
 * diagnostics scripts.
 *
 * Usage:
 *   node scripts/report-playback-recovery.mjs
 *   node scripts/report-playback-recovery.mjs --days 7 --limit 8000
 */

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
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function bump(counter, key) {
  counter.set(key, (counter.get(key) ?? 0) + 1);
}

function printCounter(title, counter) {
  console.log(title);
  if (counter.size === 0) {
    console.log('  (aucun)');
    return;
  }
  const rows = [...counter.entries()].sort((a, b) => b[1] - a[1]);
  const width = Math.max(...rows.map(([key]) => key.length));
  for (const [key, count] of rows) {
    console.log(`  ${key.padEnd(width)}  ${String(count).padStart(5)}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const days = getIntArg(args, ['days'], 7);
  const limit = getIntArg(args, ['limit'], 8000);

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
    initializeApp({ credential: cert(serviceAccount), projectId });
  }

  const db = getFirestore();
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  // Ordered by createdAt only, then partitioned in memory: filtering on
  // `action` server-side would need a composite index, and a read-only
  // diagnostics script has no business adding one to production.
  const snapshot = await db
    .collection('video_action_logs')
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  const retriesByReason = new Map();
  const errorsByReason = new Map();
  const strategy = new Map();
  const exhausted = [];
  let scanned = 0;

  for (const doc of snapshot.docs) {
    const row = doc.data();
    const createdAt = toDate(row.createdAt);
    if (createdAt && createdAt < since) continue;
    scanned += 1;

    const action = String(row.action ?? '');
    const extra = row.extra && typeof row.extra === 'object' ? row.extra : {};
    const reason = String(extra.reason ?? row.code ?? 'inconnu');

    if (action === 'retry') {
      bump(retriesByReason, reason);
      const purge = extra.purgeCachedFile === true;
      const download = extra.preferDownloadedFile === true;
      bump(
        strategy,
        `purgeCache=${purge ? 'oui' : 'non'} prefereFichierLocal=${download ? 'oui' : 'non'}`,
      );
      continue;
    }

    if (action === 'play_error') {
      bump(errorsByReason, reason);
      if (reason === 'recovery_exhausted') {
        exhausted.push({
          at: createdAt ? createdAt.toISOString() : '<inconnu>',
          videoId: String(row.videoId ?? extra.videoId ?? '?'),
          loadState: String(extra.loadState ?? '?'),
          hasFirstFrame: extra.hasFirstFrame,
          hasError: extra.hasError,
          errorDescription: String(extra.errorDescription ?? '').slice(0, 160),
        });
      }
    }
  }

  console.log('');
  console.log(`Projet        : ${projectId}`);
  console.log(`Fenetre       : ${days} derniers jours`);
  console.log(`Journaux lus  : ${scanned} (plafond --limit ${limit})`);
  if (scanned >= limit) {
    console.log('ATTENTION : plafond atteint, relancez avec --limit plus eleve.');
  }
  console.log('');

  printCounter('Reprises automatiques, par declencheur', retriesByReason);
  console.log('');
  printCounter('Strategie employee par les reprises', strategy);
  console.log('');
  printCounter('Erreurs de lecture, par motif', errorsByReason);
  console.log('');

  const gaveUp = errorsByReason.get('recovery_exhausted') ?? 0;

  if (gaveUp > 0) {
    console.log(`VERDICT : la reprise automatique a abandonne ${gaveUp} fois.`);
    console.log('Le message vu par l\'utilisateur venait bien du budget de reprise.');
    console.log('');
    for (const item of exhausted.slice(0, 10)) {
      console.log(`  ${item.at}  video=${item.videoId}`);
      console.log(
        `    loadState=${item.loadState} premiereImage=${item.hasFirstFrame} ` +
          `erreurControleur=${item.hasError}`,
      );
      if (item.errorDescription) {
        console.log(`    ${item.errorDescription}`);
      }
    }
    return;
  }

  if (retriesByReason.size === 0) {
    console.log('VERDICT : aucune reprise sur la fenetre.');
    console.log('Un message "Lecture interrompue" vu pendant cette periode ne venait');
    console.log('donc pas du budget de reprise, mais de VideoPlayerValue.hasError');
    console.log('affiche directement — typiquement un controleur libere par un');
    console.log('rafraichissement du fil pendant que la vignette etait encore montee.');
    return;
  }

  console.log('VERDICT : des reprises ont eu lieu, aucune n\'a abandonne.');
  console.log('Le systeme a rattrape seul. Un message vu malgre tout venait de');
  console.log('VideoPlayerValue.hasError affiche pendant la reprise, pas du budget.');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
