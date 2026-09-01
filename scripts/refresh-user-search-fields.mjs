#!/usr/bin/env node

/**
 * Amorce la dérivation des champs de recherche sur les comptes existants.
 *
 * `deriveUserSearchFields` ne se déclenche qu'à l'écriture. Les comptes créés
 * avant son déploiement ne portent donc ni `birthYear` ni `isSearchable`, et
 * la recherche filtrée ne les voit pas — non parce qu'ils sont incomplets,
 * mais parce que personne ne les a réécrits depuis. Ce script provoque cette
 * écriture, une fois.
 *
 * Il fait deux choses, et rien d'autre.
 *
 * 1. Retire `playerProfile`, `clubProfile` et `agentProfile`, les trois maps
 *    en texte libre que la refonte a remplacées. Elles ne sont plus lues par
 *    personne ; les laisser ferait croire à un futur lecteur qu'elles portent
 *    encore quelque chose.
 * 2. Réécrit `role` avec sa propre valeur. C'est l'écriture la plus neutre
 *    possible : elle ne change aucune donnée et suffit à faire passer le
 *    trigger, qui recalcule alors `birthYear` depuis le document privé et
 *    `isSearchable` depuis les faits présents.
 *
 * **Il n'invente rien.** Ni poste, ni nationalité, ni date de naissance. Un
 * compte qui n'a pas ces faits ressortira `isSearchable: false`, et c'est la
 * bonne réponse : une fiche vide n'a rien à faire dans les résultats d'un
 * recruteur. Les remplir est le travail du joueur ou de l'administration.
 *
 * Lecture seule sauf `--apply`.
 *
 * Usage :
 *   node scripts/refresh-user-search-fields.mjs \
 *     [--environment production] [--credentials .credentials/<projet>-ops.json] \
 *     [--apply] [--wait-seconds 20]
 */

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');

const LEGACY_PROFILE_FIELDS = [
  'playerProfile',
  'clubProfile',
  'agentProfile',
];

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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const apply = args.has('apply');
  const waitSeconds = Number.parseInt(
    getStringArg(args, ['wait-seconds'], '20'),
    10,
  );

  const projectId = await resolveProjectId(args);
  const credentialsPath = resolveCredentialsPath(args, projectId);
  const serviceAccount = await readJsonFile(credentialsPath, 'service account');

  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();

  const snapshot = await db.collection('users').get();

  console.log(`Project:      ${projectId}`);
  console.log(`Credentials:  ${credentialsPath}`);
  console.log(`Mode:         ${apply ? 'APPLY' : 'dry run'}`);
  console.log('');

  const plan = [];
  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    const legacy = LEGACY_PROFILE_FIELDS.filter((field) => field in data);

    plan.push({
      ref: doc.ref,
      id: doc.id,
      role: data.role ?? null,
      legacy,
      birthYear: typeof data.birthYear === 'number' ? data.birthYear : null,
      isSearchable: data.isSearchable === true,
    });
  }

  const needingDerivation = plan.filter(
    (entry) => entry.birthYear === null && !entry.isSearchable,
  );
  const carryingLegacy = plan.filter((entry) => entry.legacy.length > 0);

  console.log(
    `${plan.length} accounts: ${needingDerivation.length} never derived, ` +
      `${carryingLegacy.length} still carrying a legacy profile map.`,
  );

  for (const entry of carryingLegacy) {
    console.log(`- ${entry.id} [${entry.role}] drops ${entry.legacy.join(', ')}`);
  }

  if (!apply) {
    console.log('');
    console.log('Dry run: nothing was written. Re-run with --apply.');
    return 0;
  }

  let touched = 0;
  for (const entry of plan) {
    const update = {};
    for (const field of entry.legacy) {
      update[field] = FieldValue.delete();
    }
    // L'ecriture la plus neutre possible : `role` reecrit avec sa propre
    // valeur. Elle ne change rien et suffit a declencher la derivation.
    if (entry.role !== null) {
      update.role = entry.role;
    }

    if (Object.keys(update).length === 0) continue;

    await entry.ref.update(update);
    touched += 1;
  }

  console.log('');
  console.log(`Touched ${touched} accounts. Waiting ${waitSeconds}s for the`);
  console.log('triggers to settle, then reading back what they derived.');
  await sleep(waitSeconds * 1000);

  const after = await db.collection('users').get();
  const rows = [];
  let searchable = 0;
  after.forEach((doc) => {
    const data = doc.data() ?? {};
    if (data.isSearchable === true) searchable += 1;
    rows.push({
      uid: doc.id.slice(0, 8),
      role: data.role ?? null,
      birthYear: data.birthYear ?? null,
      isSearchable: data.isSearchable ?? null,
    });
  });

  console.table(rows);
  console.log(
    `${searchable} of ${after.size} accounts are searchable. A player with no ` +
      'position, nationality or year of birth is correctly excluded: filling ' +
      'those facts is the job of the player or of the administration, not of ' +
      'this script.',
  );

  return 0;
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
