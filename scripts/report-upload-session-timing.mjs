#!/usr/bin/env node

/**
 * Reports how long createUploadSession actually takes in production, so the
 * ceiling that guards it can be set from a percentile instead of a guess.
 *
 * UploadClient.sessionCreationBudget is derived, not invented: three attempts
 * of a 75s callable plus linear backoff, ~233s. That derivation is what fixed
 * the `session-creation-timeout` failures where the caller used to cut the
 * session off below the retry budget it was waiting on. But it is also the
 * longest an uploader can watch "connexion sécurisée en cours" before learning
 * it failed, and nothing measured whether the ceiling is ever approached.
 *
 * UploadVideoController now records `upload_session_created` with `elapsedMs`
 * on every successful session. That lands in `video_action_logs`, which is
 * written unsampled by the videoActionLog callable -- unlike `client_logs`,
 * where info-level entries are sampled at 2% in production and would take far
 * too long to accumulate a distribution at this upload volume.
 *
 * Reads only. Requires the same read-only ops service account as the other
 * diagnostics scripts.
 *
 * Usage:
 *   node scripts/report-upload-session-timing.mjs
 *   node scripts/report-upload-session-timing.mjs --days 30 --environment production
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

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil(fraction * sorted.length) - 1),
  );
  return sorted[index];
}

function formatMs(value) {
  if (value === null) return '—';
  return value >= 1000 ?
    `${(value / 1000).toFixed(1)} s` :
    `${value} ms`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const days = getIntArg(args, ['days'], 30);
  const limit = getIntArg(args, ['limit'], 5000);

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

  // Ordered by createdAt only, then partitioned in memory. Filtering on
  // `action` server-side would need a composite index on video_action_logs,
  // and a read-only diagnostics script has no business adding an index to
  // production. One pass also halves the reads versus one query per action.
  // If the window looks short for the requested --days, raise --limit.
  const snapshot = await db
    .collection('video_action_logs')
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  const samples = [];
  let budgetMs = null;
  let timeouts = 0;
  let scanned = 0;
  let oldestScanned = null;

  for (const doc of snapshot.docs) {
    const row = doc.data();
    const createdAt = toDate(row.createdAt);
    if (createdAt && createdAt < since) continue;

    scanned += 1;
    if (createdAt && (oldestScanned === null || createdAt < oldestScanned)) {
      oldestScanned = createdAt;
    }

    const action = String(row.action ?? '');
    const extra = row.extra && typeof row.extra === 'object' ? row.extra : {};

    if (action === 'upload_session_created') {
      const elapsed = Number(extra.elapsedMs);
      if (Number.isFinite(elapsed) && elapsed >= 0) {
        samples.push(elapsed);
        const budget = Number(extra.budgetMs);
        if (Number.isFinite(budget) && budget > 0) budgetMs = budget;
      }
      continue;
    }

    // A timeout never reaches `upload_session_created` -- it is recorded as an
    // upload failure instead. Counting those separately is what tells a healthy
    // distribution apart from one whose tail the ceiling simply truncated.
    if (action === 'upload_failed' &&
        String(extra.code ?? row.code ?? '') === 'session-creation-timeout') {
      timeouts += 1;
    }
  }

  console.log('');
  console.log(`Projet          : ${projectId}`);
  console.log(`Fenetre         : ${days} derniers jours`);
  console.log(`Journaux lus    : ${scanned} (plafond --limit ${limit})`);
  console.log(`Sessions creees : ${samples.length}`);
  console.log(`Timeouts        : ${timeouts}`);
  if (scanned >= limit) {
    console.log('');
    console.log(`ATTENTION : plafond --limit atteint. La fenetre reellement couverte`);
    console.log(`s'arrete a ${oldestScanned ? oldestScanned.toISOString() : '?'}.`);
    console.log('Relancez avec --limit plus eleve pour couvrir les ' + days + ' jours.');
  }
  console.log('');

  if (samples.length === 0) {
    console.log('Aucune mesure. Deux explications possibles :');
    console.log('  - aucun upload reussi sur la fenetre ;');
    console.log('  - la version instrumentee n\'est pas encore deployee.');
    console.log('');
    console.log('L\'instrumentation est arrivee en 1.0.7+18 (upload_session_created).');
    return;
  }

  const sorted = [...samples].sort((a, b) => a - b);
  const p50 = percentile(sorted, 0.5);
  const p95 = percentile(sorted, 0.95);
  const p99 = percentile(sorted, 0.99);
  const max = sorted[sorted.length - 1];

  console.log('Duree de creation de session');
  console.log(`  mediane   : ${formatMs(p50)}`);
  console.log(`  p95       : ${formatMs(p95)}`);
  console.log(`  p99       : ${formatMs(p99)}`);
  console.log(`  maximum   : ${formatMs(max)}`);
  if (budgetMs !== null) {
    console.log(`  plafond   : ${formatMs(budgetMs)}  (sessionCreationBudget)`);
  }
  console.log('');

  if (budgetMs === null) {
    console.log('Plafond inconnu : impossible de conclure.');
    return;
  }

  // A ceiling is only safe to lower if it sits comfortably above the observed
  // tail *and* nothing is currently hitting it. Two times p99 keeps room for a
  // cold start that this window happened not to contain.
  const suggested = Math.ceil((p99 * 2) / 1000) * 1000;

  if (timeouts > 0) {
    console.log('VERDICT : ne pas toucher au plafond.');
    console.log(`  ${timeouts} upload(s) l'ont atteint sur la fenetre : il fait son travail.`);
    console.log('  Regardez plutot la latence serveur (UPLOAD_CALLABLE_MIN_INSTANCES,');
    console.log('  journaux Functions de createUploadSession).');
    return;
  }

  if (suggested >= budgetMs) {
    console.log('VERDICT : ne pas toucher au plafond.');
    console.log('  La queue observee est trop proche du plafond pour le resserrer sans risque.');
    return;
  }

  console.log('VERDICT : le plafond peut etre resserre.');
  console.log(`  Aucun timeout, et 2 x p99 = ${formatMs(suggested)} reste sous le plafond actuel.`);
  console.log('  Le plafond derive de UploadClient._callableTimeout (75 s x 3 tentatives');
  console.log('  + backoff). Baisser _callableTimeout est donc le levier, pas le plafond');
  console.log('  lui-meme, qui se recalcule tout seul.');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
