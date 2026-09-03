#!/usr/bin/env node

/**
 * Reports what the Carrière tab actually holds in production.
 *
 * Two questions the source cannot answer, and both change what to build next:
 *
 *   1. How many offers and events are there, and how many are reachable —
 *      open, not expired? The header comment in `opportunities_screen.dart`
 *      recorded "one offer and two events" when the two tabs were merged. If
 *      that is still the shape, the tab's problem is emptiness, not filtering,
 *      and a position filter would sort three documents.
 *
 *   2. Do the offers carry the coded football vocabulary? The mobile app
 *      migrated `posteRecherche` (free text) to `positionCodes[]` and split
 *      `niveau` into `ageCategories[]` + `clubLevel`. Nothing backfilled the
 *      documents written before that. An offer holding only the old fields is
 *      displayed with no position and no level on mobile, because
 *      `Offre.fromMap` reads the coded keys alone — and one holding only the
 *      new fields is invisible to the admin console's search, which still
 *      reads the old ones.
 *
 * Counting both sides tells you whether a backfill is owed, and to whom.
 *
 * Reads only: two collection scans, no writes. Note that the ops credential is
 * NOT read-only in itself (see docs); this script simply never writes.
 *
 * Usage:
 *   node scripts/report-career-content.mjs
 *   node scripts/report-career-content.mjs --project-id adfoot-production
 *   node scripts/report-career-content.mjs --json
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

function resolveRepoPath(candidate) {
  if (!candidate) return '';
  return path.isAbsolute(candidate) ? candidate : path.resolve(repoRoot, candidate);
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
    `No service account found. Looked at: ${candidates.join(', ') || '(nothing)'}`,
  );
}

/** Firestore hands back Timestamps, but old documents hold strings and ints. */
function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'number') return new Date(value);
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function nonEmptyList(value) {
  return Array.isArray(value) && value.length > 0;
}

function nonEmptyText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function tally(map, key) {
  const k = key || '(absent)';
  map.set(k, (map.get(k) ?? 0) + 1);
}

function sortedTally(map) {
  return Object.fromEntries([...map.entries()].sort((a, b) => b[1] - a[1]));
}

async function readOffers(db, now) {
  const snapshot = await db.collection('offres').get();

  const byStatus = new Map();
  const report = {
    total: snapshot.size,
    byStatus: {},
    openAndUnexpired: 0,
    expiredButOpen: 0,
    withCodedPositions: 0,
    withCodedAgeCategories: 0,
    withClubLevel: 0,
    withAnyCodedVocabulary: 0,
    withLegacyPosteRecherche: 0,
    withLegacyNiveau: 0,
    withNeitherVocabulary: 0,
    totalCandidates: 0,
    offersWithAtLeastOneCandidate: 0,
    totalViews: 0,
    distinctRecruiters: 0,
    oldestCreatedAt: null,
    newestCreatedAt: null,
    positionCodeHistogram: {},
  };

  const recruiters = new Set();
  const positions = new Map();

  snapshot.forEach((doc) => {
    const data = doc.data() ?? {};
    const status = String(data.statut ?? '').trim().toLowerCase();
    tally(byStatus, status);

    const endsAt = toDate(data.dateFin);
    const isOpen = status === 'ouverte';
    if (isOpen) {
      if (endsAt && endsAt.getTime() >= now.getTime()) {
        report.openAndUnexpired += 1;
      } else {
        report.expiredButOpen += 1;
      }
    }

    const coded = {
      positions: nonEmptyList(data.positionCodes),
      ages: nonEmptyList(data.ageCategories),
      level: nonEmptyText(data.clubLevel),
    };
    if (coded.positions) report.withCodedPositions += 1;
    if (coded.ages) report.withCodedAgeCategories += 1;
    if (coded.level) report.withClubLevel += 1;

    const hasCoded = coded.positions || coded.ages || coded.level;
    if (hasCoded) report.withAnyCodedVocabulary += 1;

    const legacyPoste = nonEmptyText(data.posteRecherche);
    const legacyNiveau = nonEmptyText(data.niveau);
    if (legacyPoste) report.withLegacyPosteRecherche += 1;
    if (legacyNiveau) report.withLegacyNiveau += 1;

    if (!hasCoded && !legacyPoste && !legacyNiveau) {
      report.withNeitherVocabulary += 1;
    }

    if (coded.positions) {
      for (const code of data.positionCodes) {
        tally(positions, String(code));
      }
    }

    const candidates = Array.isArray(data.candidats) ? data.candidats.length : 0;
    report.totalCandidates += candidates;
    if (candidates > 0) report.offersWithAtLeastOneCandidate += 1;

    report.totalViews += Number.isFinite(data.vues) ? data.vues : 0;

    const recruiterUid = data?.recruteur?.uid;
    if (nonEmptyText(recruiterUid)) recruiters.add(recruiterUid);

    const createdAt = toDate(data.dateCreation);
    if (createdAt) {
      if (!report.oldestCreatedAt || createdAt < report.oldestCreatedAt) {
        report.oldestCreatedAt = createdAt;
      }
      if (!report.newestCreatedAt || createdAt > report.newestCreatedAt) {
        report.newestCreatedAt = createdAt;
      }
    }
  });

  report.byStatus = sortedTally(byStatus);
  report.positionCodeHistogram = sortedTally(positions);
  report.distinctRecruiters = recruiters.size;
  return report;
}

async function readEvents(db, now) {
  const snapshot = await db.collection('events').get();

  const byStatus = new Map();
  const report = {
    total: snapshot.size,
    byStatus: {},
    openAndUpcoming: 0,
    alreadyFinished: 0,
    totalParticipants: 0,
    eventsWithAtLeastOneParticipant: 0,
    withFlyer: 0,
    withStreamingUrl: 0,
    withViewsField: 0,
    distinctOrganisers: 0,
    oldestCreatedAt: null,
    newestCreatedAt: null,
  };

  const organisers = new Set();

  snapshot.forEach((doc) => {
    const data = doc.data() ?? {};
    const status = String(data.statut ?? '').trim().toLowerCase();
    tally(byStatus, status);

    const endsAt = toDate(data.dateFin);
    if (endsAt && endsAt.getTime() < now.getTime()) {
      report.alreadyFinished += 1;
    } else if (status === 'ouvert') {
      report.openAndUpcoming += 1;
    }

    const participants = Array.isArray(data.participants)
      ? data.participants.length
      : 0;
    report.totalParticipants += participants;
    if (participants > 0) report.eventsWithAtLeastOneParticipant += 1;

    if (nonEmptyText(data.flyerUrl)) report.withFlyer += 1;
    if (nonEmptyText(data.streamingUrl)) report.withStreamingUrl += 1;
    if (data.views !== undefined && data.views !== null) report.withViewsField += 1;

    const organiserUid = data?.organisateur?.uid;
    if (nonEmptyText(organiserUid)) organisers.add(organiserUid);

    const createdAt = toDate(data.createdAt);
    if (createdAt) {
      if (!report.oldestCreatedAt || createdAt < report.oldestCreatedAt) {
        report.oldestCreatedAt = createdAt;
      }
      if (!report.newestCreatedAt || createdAt > report.newestCreatedAt) {
        report.newestCreatedAt = createdAt;
      }
    }
  });

  report.byStatus = sortedTally(byStatus);
  report.distinctOrganisers = organisers.size;
  return report;
}

function formatDate(value) {
  return value ? value.toISOString().slice(0, 10) : '—';
}

function printHuman(offers, events, projectId) {
  const line = (label, value) =>
    console.log(`  ${label.padEnd(38)} ${String(value)}`);

  console.log('');
  console.log(`Contenu de l'onglet Carriere — ${projectId}`);
  console.log('='.repeat(58));

  console.log('');
  console.log(`OFFRES  (${offers.total} document${offers.total === 1 ? '' : 's'})`);
  console.log('-'.repeat(58));
  line('par statut', JSON.stringify(offers.byStatus));
  line('ouvertes et non expirees', offers.openAndUnexpired);
  line('ouvertes mais deja expirees', offers.expiredButOpen);
  line('recruteurs distincts', offers.distinctRecruiters);
  line('creees entre', `${formatDate(offers.oldestCreatedAt)} et ${formatDate(offers.newestCreatedAt)}`);
  line('candidatures (total)', offers.totalCandidates);
  line('offres avec >= 1 candidature', offers.offersWithAtLeastOneCandidate);
  line('vues cumulees', offers.totalViews);

  console.log('');
  console.log('  Vocabulaire footballistique');
  line('  positionCodes[] renseigne', offers.withCodedPositions);
  line('  ageCategories[] renseigne', offers.withCodedAgeCategories);
  line('  clubLevel renseigne', offers.withClubLevel);
  line('  au moins un champ code', offers.withAnyCodedVocabulary);
  line('  ancien posteRecherche present', offers.withLegacyPosteRecherche);
  line('  ancien niveau present', offers.withLegacyNiveau);
  line('  ni code ni ancien', offers.withNeitherVocabulary);
  if (Object.keys(offers.positionCodeHistogram).length > 0) {
    line('  postes demandes', JSON.stringify(offers.positionCodeHistogram));
  }

  console.log('');
  console.log(`EVENEMENTS  (${events.total} document${events.total === 1 ? '' : 's'})`);
  console.log('-'.repeat(58));
  line('par statut', JSON.stringify(events.byStatus));
  line('ouverts et a venir', events.openAndUpcoming);
  line('deja termines', events.alreadyFinished);
  line('organisateurs distincts', events.distinctOrganisers);
  line('crees entre', `${formatDate(events.oldestCreatedAt)} et ${formatDate(events.newestCreatedAt)}`);
  line('inscriptions (total)', events.totalParticipants);
  line('evenements avec >= 1 inscrit', events.eventsWithAtLeastOneParticipant);
  line('avec une affiche (flyerUrl)', events.withFlyer);
  line('avec un lien de diffusion', events.withStreamingUrl);
  line('portant un champ views', events.withViewsField);
  console.log('');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = getStringArg(args, ['project-id', 'project'], 'adfoot-production');
  const credentialsPath = resolveCredentialsPath(args, projectId);

  const raw = await readFile(credentialsPath, 'utf8');
  const serviceAccount = JSON.parse(raw);

  if (getApps().length === 0) {
    initializeApp({ credential: cert(serviceAccount), projectId });
  }

  const db = getFirestore();
  const now = new Date();

  const [offers, events] = await Promise.all([
    readOffers(db, now),
    readEvents(db, now),
  ]);

  if (args.has('json')) {
    console.log(JSON.stringify({ projectId, generatedAt: now.toISOString(), offers, events }, null, 2));
    return;
  }

  printHuman(offers, events, projectId);
}

main().catch((error) => {
  console.error(`report-career-content failed: ${error.message}`);
  process.exitCode = 1;
});
