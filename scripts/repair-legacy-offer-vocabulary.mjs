#!/usr/bin/env node

/**
 * Gives back to an offer the position and the level its author typed.
 *
 * The mobile app used to store `posteRecherche` and `niveau` as free text.
 * Commit 06b4e43 replaced them with `positionCodes[]`, `ageCategories[]` and
 * `clubLevel`, so that a club looking for a left-back and a player filed as
 * `LB` would finally be talking about the same thing. Nothing went back over
 * the documents written before that day.
 *
 * `Offre.fromMap` reads the coded keys by direct access, with no fallback —
 * the mobile app no longer mentions `posteRecherche` or `niveau` anywhere. So
 * a pre-migration offer renders with no position, no age category and no
 * level, and because the sheet hides empty rows nothing says it was lost.
 *
 * This reads the vocabulary out of `lib/models/football_vocabulary.dart`
 * rather than restating it, so there is still only one source per football
 * fact. Free text that does not resolve is reported, never guessed.
 *
 * The old fields are left in place: the admin console still reads them, and
 * removing them would break its offer search before its model is aligned.
 *
 * Dry run by default. Pass --apply to write.
 *
 * Usage:
 *   node scripts/repair-legacy-offer-vocabulary.mjs
 *   node scripts/repair-legacy-offer-vocabulary.mjs --apply
 */

import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

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

function resolveCredentialsPath(args, projectId) {
  const candidates = [
    getStringArg(args, ['credentials', 'service-account']),
    process.env.GOOGLE_APPLICATION_CREDENTIALS || '',
    projectId ? path.join('.credentials', `${projectId}-ops.json`) : '',
  ]
    .map(resolveRepoPath)
    .filter(Boolean);

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(`No service account found. Looked at: ${candidates.join(', ')}`);
}

/** Lowercase, unaccented, single-spaced — so "Latéral gauche" meets "lateral gauche". */
function fold(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Reads the enums out of the Dart source.
 *
 * Entries wrap across lines when the labels are long, so the block is
 * flattened before matching.
 */
async function readVocabulary() {
  const source = await readFile(
    path.join(repoRoot, 'lib/models/football_vocabulary.dart'),
    'utf8',
  );

  function block(name) {
    const start = source.indexOf(`enum ${name} {`);
    if (start < 0) throw new Error(`enum ${name} not found`);
    const end = source.indexOf('\n}', start);
    return source.slice(start, end).replace(/\s+/g, ' ');
  }

  const positions = [];
  for (const m of block('FootballPosition').matchAll(
    /([a-zA-Z]+)\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'/g,
  )) {
    positions.push({ code: m[2], labelFr: m[3], labelEn: m[4] });
  }

  const ageCategories = [];
  for (const m of block('AgeCategory').matchAll(
    /([a-zA-Z0-9]+)\(\s*'([^']+)'\s*,/g,
  )) {
    ageCategories.push({ code: m[2] });
  }

  const clubLevels = [];
  for (const m of block('ClubLevel').matchAll(
    /([a-zA-Z]+)\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'/g,
  )) {
    clubLevels.push({ code: m[2], labelFr: m[3], labelEn: m[4] });
  }

  if (!positions.length || !ageCategories.length || !clubLevels.length) {
    throw new Error('vocabulary parsed empty — the Dart source has changed shape');
  }

  return { positions, ageCategories, clubLevels };
}

/** "Latéral gauche ou arrière droit" -> ["lateral gauche", "arriere droit"] */
function splitFreeText(raw) {
  return String(raw ?? '')
    .split(/[,;/|]| ou | et |&|\+/i)
    .map((part) => part.trim())
    .filter(Boolean);
}

function matchOne(entries, fragment) {
  const needle = fold(fragment);
  if (!needle) return null;
  return (
    entries.find((entry) => fold(entry.code) === needle) ??
    entries.find((entry) => fold(entry.labelFr) === needle) ??
    entries.find((entry) => fold(entry.labelEn) === needle) ??
    null
  );
}

function resolveOffer(data, vocab) {
  const unresolved = [];

  const positionCodes = [];
  for (const fragment of splitFreeText(data.posteRecherche)) {
    const hit = matchOne(vocab.positions, fragment);
    if (!hit) {
      unresolved.push(`posteRecherche: "${fragment}"`);
      continue;
    }
    if (!positionCodes.includes(hit.code)) positionCodes.push(hit.code);
  }

  const ageCategories = [];
  let clubLevel = null;
  for (const fragment of splitFreeText(data.niveau)) {
    const age = matchOne(vocab.ageCategories, fragment);
    if (age) {
      if (!ageCategories.includes(age.code)) ageCategories.push(age.code);
      continue;
    }
    const level = matchOne(vocab.clubLevels, fragment);
    if (level) {
      clubLevel = level.code;
      continue;
    }
    unresolved.push(`niveau: "${fragment}"`);
  }

  return { positionCodes, ageCategories, clubLevel, unresolved };
}

function hasCodedVocabulary(data) {
  return (
    (Array.isArray(data.positionCodes) && data.positionCodes.length > 0) ||
    (Array.isArray(data.ageCategories) && data.ageCategories.length > 0) ||
    (typeof data.clubLevel === 'string' && data.clubLevel.trim().length > 0)
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = getStringArg(args, ['project-id', 'project'], 'adfoot-production');
  const apply = args.has('apply');
  const credentialsPath = resolveCredentialsPath(args, projectId);

  const vocab = await readVocabulary();
  const serviceAccount = JSON.parse(await readFile(credentialsPath, 'utf8'));

  if (getApps().length === 0) {
    initializeApp({ credential: cert(serviceAccount), projectId });
  }

  const db = getFirestore();
  const snapshot = await db.collection('offres').get();

  const planned = [];
  const skipped = [];
  const blocked = [];

  snapshot.forEach((doc) => {
    const data = doc.data() ?? {};

    if (hasCodedVocabulary(data)) {
      skipped.push({ id: doc.id, why: 'porte deja le vocabulaire code' });
      return;
    }

    const resolved = resolveOffer(data, vocab);
    const nothingToWrite =
      resolved.positionCodes.length === 0 &&
      resolved.ageCategories.length === 0 &&
      resolved.clubLevel === null;

    if (nothingToWrite) {
      skipped.push({
        id: doc.id,
        why: resolved.unresolved.length
          ? `rien de reconnu (${resolved.unresolved.join(', ')})`
          : 'aucun ancien champ a reprendre',
      });
      return;
    }

    if (resolved.unresolved.length) {
      blocked.push({ id: doc.id, titre: data.titre, unresolved: resolved.unresolved, resolved });
      return;
    }

    planned.push({ id: doc.id, titre: data.titre, data, resolved });
  });

  console.log('');
  console.log(`Reprise du vocabulaire des offres — ${projectId}`);
  console.log(`Mode : ${apply ? 'ECRITURE' : 'marche a blanc (--apply pour ecrire)'}`);
  console.log('='.repeat(62));
  console.log(`Offres lues : ${snapshot.size}`);
  console.log('');

  for (const item of planned) {
    console.log(`  ${item.id}`);
    console.log(`    titre          : ${item.titre}`);
    console.log(`    posteRecherche : "${item.data.posteRecherche ?? ''}"  ->  positionCodes: ${JSON.stringify(item.resolved.positionCodes)}`);
    console.log(`    niveau         : "${item.data.niveau ?? ''}"  ->  ageCategories: ${JSON.stringify(item.resolved.ageCategories)}, clubLevel: ${JSON.stringify(item.resolved.clubLevel)}`);
    console.log('');
  }

  for (const item of blocked) {
    console.log(`  ${item.id}  NON REPRIS — du texte n'a pas de code`);
    console.log(`    titre     : ${item.titre}`);
    console.log(`    non resolu: ${item.unresolved.join(', ')}`);
    console.log('    (a coder a la main, ou a laisser tel quel)');
    console.log('');
  }

  for (const item of skipped) {
    console.log(`  ${item.id}  ignore — ${item.why}`);
  }

  console.log('');
  console.log(`A reprendre : ${planned.length}   bloquees : ${blocked.length}   ignorees : ${skipped.length}`);

  if (!apply) {
    console.log('');
    console.log('Rien n\'a ete ecrit. Relancer avec --apply pour appliquer le plan ci-dessus.');
    return;
  }

  if (planned.length === 0) {
    console.log('');
    console.log('Rien a ecrire.');
    return;
  }

  for (const item of planned) {
    // Les anciens champs restent : la console admin les lit encore.
    const patch = { lastUpdated: FieldValue.serverTimestamp() };
    if (item.resolved.positionCodes.length) patch.positionCodes = item.resolved.positionCodes;
    if (item.resolved.ageCategories.length) patch.ageCategories = item.resolved.ageCategories;
    if (item.resolved.clubLevel !== null) patch.clubLevel = item.resolved.clubLevel;

    await db.collection('offres').doc(item.id).update(patch);
    console.log(`  ecrit : ${item.id}`);
  }

  console.log('');
  console.log(`${planned.length} offre(s) reprise(s).`);
}

main().catch((error) => {
  console.error(`repair-legacy-offer-vocabulary failed: ${error.message}`);
  process.exitCode = 1;
});
