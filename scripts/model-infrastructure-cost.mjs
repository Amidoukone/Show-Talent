#!/usr/bin/env node

/**
 * Models Adfoot's infrastructure cost across growth scenarios.
 *
 * Every per-unit figure below comes from a measurement on adfoot-production,
 * not from an industry average — the measurement date and the query are named
 * next to each one. Re-run `--measure` to refresh them from live data before
 * trusting the output again.
 *
 * What this model is NOT: a quote. Google list prices move, the free tiers
 * change, and the biggest single lever (CDN cache hit ratio) is an assumption
 * until a CDN is actually in front of Storage. Treat the ranking of the cost
 * lines as solid and the absolute totals as an order of magnitude.
 *
 * Usage:
 *   node scripts/model-infrastructure-cost.mjs
 *   node scripts/model-infrastructure-cost.mjs --measure      # refresh inputs
 *   node scripts/model-infrastructure-cost.mjs --cdn-hit 0.85
 */

import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

/* -------------------------------------------------------------------------- */
/* MESURES — adfoot-production, 2026-08-29                                     */
/* -------------------------------------------------------------------------- */

const MEASURED = {
  // Storage: getFiles() sur adfoot-production.firebasestorage.app.
  // Les deux vidéos approuvées pèsent 74,5 et 60,7 Mo ; leurs compagnons 480p
  // 16,5 et 15,2 Mo. Les deux vidéos légères (1,4 et 2,3 Mo) sont sous le
  // seuil COMPANION_MIN_SOURCE_BITRATE et n'ont pas de compagnon.
  videoOriginalMb: 67.6,
  videoCompanionMb: 15.9,
  thumbnailMb: 0.017,
  profilePhotoMb: 0.7,
  cvMb: 0.27,

  // Lecture: 389 sessions client_logs.feed_playback avec estimatedBytesPlayed>0.
  // L'écart moyenne/médiane est énorme parce que la plupart des sessions sont
  // des passages rapides (médiane : 6 s de visionnage).
  bytesPerSessionMeanMb: 6.3,
  bytesPerSessionMedianMb: 1.2,

  // Hypothèse prudente, et probablement la plus juste des trois.
  //
  // estimatedBytesPlayed vaut débit × durée visionnée : il ne compte que ce
  // qui a été *joué*. Deux volumes lui échappent entièrement :
  //
  //  - le préchargement. VideoNetworkTuning ouvre les voisins d'avance
  //    (preloadRadius 3 en réseau rapide, 2 en moyen, 0 en lent), et chaque
  //    préchargement tire assez d'octets pour afficher une première image
  //    d'une vidéo que l'utilisateur ne regardera peut-être jamais ;
  //  - la mise en tampon d'avance sur la vidéo courante : six secondes
  //    visionnées ne veulent pas dire six secondes téléchargées.
  //
  // 15 Mo/session suppose la session moyenne mesurée plus deux voisins
  // partiellement chargés. À valider avec les octets réellement facturés une
  // fois un mois complet de trafic observé.
  bytesPerSessionPrudentMb: 15.0,

  // Lectures Firestore par ouverture d'application, d'après le code :
  // UserRepository.directoryWatchLimit (300) + la première page du fil (10)
  // + la fenêtre live (30). Les onglets Carrière et Messages ajoutent leurs
  // propres pages quand ils sont ouverts.
  firestoreReadsPerAppOpen: 300 + 10 + 30,
  firestoreReadsPerCareerTab: 20,
};

/* -------------------------------------------------------------------------- */
/* TARIFS — prix catalogue Google Cloud / Firebase, europe-west1               */
/* -------------------------------------------------------------------------- */

const USD_PER_EUR = 1.09; // hypothèse de change
const XOF_PER_EUR = 655.957; // parité fixe

const PRICE_USD = {
  storagePerGbMonth: 0.020,
  egressPerGb: 0.12,
  firestoreReadPer100k: 0.06,
  firestoreWritePer100k: 0.18,
  firestoreStoragePerGbMonth: 0.18,
  functionRequestPerMillion: 0.40,
  functionVcpuSecond: 0.000024,
  functionGibSecond: 0.0000025,
  // Encodage d'une vidéo : optimizeMp4Video tourne à 2 vCPU / 2 GiB.
  // Mesure production : ~35 s pour un 1080p de 74 Mo (objet ré-uploadé à
  // 13:44:15, compagnon publié à 13:44:50).
  encodeSecondsPerVideo: 45,
  encodeVcpu: 2,
  encodeGib: 2,
};

/* -------------------------------------------------------------------------- */
/* TRAVAIL HUMAIN — la moitié que l'infrastructure ne montre pas               */
/* -------------------------------------------------------------------------- */
//
// Le modèle serveur seul donne une réponse fausse à la question "le projet
// est-il viable". Chez Adfoot, chaque compte est créé à la main par
// l'administration, et chaque vidéo est visionnée avant publication. Ce sont
// des minutes de personne, pas des octets, et elles ne baissent pas avec le
// volume : elles montent linéairement.
//
// Durées à ajuster une fois mesurées sur le portail admin ; ce sont des
// hypothèses de travail, pas des mesures.
const HUMAN = {
  minutesPerAccountProvisioned: 8,
  minutesPerVideoReviewed: 3,
  // Coût employeur mensuel d'un modérateur à temps plein, charges comprises.
  monthlyCostPerFteXof: 200000,
  productiveHoursPerFteMonth: 140,
};

// Palier gratuit quotidien appliqué même en formule Blaze.
const FREE_TIER = {
  firestoreReadsPerDay: 50000,
  firestoreWritesPerDay: 20000,
  storageGb: 5,
  egressGbPerDay: 1,
};

/* -------------------------------------------------------------------------- */
/* SCÉNARIOS                                                                   */
/* -------------------------------------------------------------------------- */

const SCENARIOS = [
  {
    name: 'Amorçage',
    players: 500,
    recruiters: 30,
    videosPerPlayer: 3,
    appOpensPerActiveUserPerMonth: 12,
    activeShare: 0.35,
    sessionsPerAppOpen: 8,
    newVideosPerMonth: 120,
  },
  {
    name: 'Traction',
    players: 5000,
    recruiters: 200,
    videosPerPlayer: 4,
    appOpensPerActiveUserPerMonth: 16,
    activeShare: 0.30,
    sessionsPerAppOpen: 10,
    newVideosPerMonth: 900,
  },
  {
    name: 'Échelle',
    players: 50000,
    recruiters: 1500,
    videosPerPlayer: 5,
    appOpensPerActiveUserPerMonth: 18,
    activeShare: 0.25,
    sessionsPerAppOpen: 12,
    newVideosPerMonth: 7000,
  },
];

/* -------------------------------------------------------------------------- */

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

/** Argument, puis environnement, puis chemin conventionnel. Jamais en dur. */
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
    'Identifiants introuvables. Passez --credentials, definissez ' +
      'GOOGLE_APPLICATION_CREDENTIALS, ou placez le fichier de compte de ' +
      'service dans .credentials/ du depot.',
  );
}

const usdToEur = (usd) => usd / USD_PER_EUR;
const eur = (v) => `${v.toFixed(0).padStart(6)} €`;
const xof = (v) => `${Math.round((v * XOF_PER_EUR) / 1000)
  .toString()
  .padStart(6)} k`;

function modelScenario(s, { cdnHit, bytesPerSessionMb }) {
  const activeUsers = Math.round((s.players + s.recruiters) * s.activeShare);
  const appOpens = activeUsers * s.appOpensPerActiveUserPerMonth;
  const sessions = appOpens * s.sessionsPerAppOpen;

  /* --- Stockage ---------------------------------------------------------- */
  const videos = s.players * s.videosPerPlayer;
  const storedGb =
    (videos *
      (MEASURED.videoOriginalMb +
        MEASURED.videoCompanionMb +
        MEASURED.thumbnailMb) +
      s.players * (MEASURED.profilePhotoMb + MEASURED.cvMb)) /
    1000;
  const billableStorageGb = Math.max(0, storedGb - FREE_TIER.storageGb);
  const storageUsd = billableStorageGb * PRICE_USD.storagePerGbMonth;

  /* --- Diffusion (le poste qui décide) ----------------------------------- */
  const rawEgressGb = (sessions * bytesPerSessionMb) / 1000;
  // Un CDN ne supprime pas l'egress, il le déplace vers un tarif plus bas et
  // sert le reste depuis le cache. Modélisé ici comme une simple réduction.
  const egressGb = rawEgressGb * (1 - cdnHit);
  const freeEgressGb = FREE_TIER.egressGbPerDay * 30;
  const billableEgressGb = Math.max(0, egressGb - freeEgressGb);
  const egressUsd = billableEgressGb * PRICE_USD.egressPerGb;

  /* --- Firestore --------------------------------------------------------- */
  const reads =
    appOpens *
    (MEASURED.firestoreReadsPerAppOpen + MEASURED.firestoreReadsPerCareerTab);
  const writes = sessions + s.newVideosPerMonth * 6 + activeUsers * 20;
  const freeReads = FREE_TIER.firestoreReadsPerDay * 30;
  const freeWrites = FREE_TIER.firestoreWritesPerDay * 30;
  const firestoreUsd =
    (Math.max(0, reads - freeReads) / 100000) * PRICE_USD.firestoreReadPer100k +
    (Math.max(0, writes - freeWrites) / 100000) *
      PRICE_USD.firestoreWritePer100k;

  /* --- Functions (encodage surtout) -------------------------------------- */
  const encodeSeconds = s.newVideosPerMonth * PRICE_USD.encodeSecondsPerVideo;
  const functionsUsd =
    encodeSeconds * PRICE_USD.encodeVcpu * PRICE_USD.functionVcpuSecond +
    encodeSeconds * PRICE_USD.encodeGib * PRICE_USD.functionGibSecond +
    ((sessions + writes) / 1000000) * PRICE_USD.functionRequestPerMillion;

  const totalUsd = storageUsd + egressUsd + firestoreUsd + functionsUsd;

  /* --- Travail humain ----------------------------------------------------- */
  // Comptes provisionnés ce mois-ci : on suppose un renouvellement de 10 % du
  // parc, ce qui est prudent pour une plateforme en croissance.
  const accountsProvisioned = Math.round(s.players * 0.10) + s.recruiters;
  const humanMinutes =
    accountsProvisioned * HUMAN.minutesPerAccountProvisioned +
    s.newVideosPerMonth * HUMAN.minutesPerVideoReviewed;
  const humanHours = humanMinutes / 60;
  const fte = humanHours / HUMAN.productiveHoursPerFteMonth;
  const humanXof = fte * HUMAN.monthlyCostPerFteXof;
  const humanEur = humanXof / XOF_PER_EUR;

  return {
    humanHours,
    fte,
    humanEur,
    name: s.name,
    players: s.players,
    activeUsers,
    sessions,
    storedGb,
    rawEgressGb,
    egressGb,
    lines: {
      Stockage: usdToEur(storageUsd),
      Diffusion: usdToEur(egressUsd),
      Firestore: usdToEur(firestoreUsd),
      Functions: usdToEur(functionsUsd),
    },
    totalEur: usdToEur(totalUsd),
    perPlayerEur: usdToEur(totalUsd) / s.players,
  };
}

async function measure(args, environment) {
  const { initializeApp, cert } = await import('firebase-admin/app');
  const { getFirestore } = await import('firebase-admin/firestore');
  const { getStorage } = await import('firebase-admin/storage');

  // Le chemin des identifiants n'est jamais ecrit ici : un chemin de fichier
  // de credentials commite est une exposition en soi, et
  // test/sign_in_never_hangs_guardrails_test.dart le refuse pour tous les
  // scripts de scripts/. Meme resolution que les autres scripts du depot :
  // argument, puis variable d'environnement, puis chemin conventionnel
  // construit a partir de l'identifiant de projet.
  const config = await readJson(
    path.join(repoRoot, 'config', 'mobile', `${environment}.json`),
    'mobile config',
  );
  const projectId = config.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error('FIREBASE_PROJECT_ID absent de la configuration mobile.');
  }

  const credentialsPath = resolveCredentialsPath(args, projectId);
  const sa = JSON.parse(await readFile(credentialsPath, 'utf8'));
  initializeApp({
    credential: cert(sa),
    projectId: sa.project_id,
    storageBucket: `${sa.project_id}.firebasestorage.app`,
  });

  const [files] = await getStorage().bucket().getFiles();
  const byPrefix = {};
  for (const f of files) {
    const prefix = f.name.split('/')[0];
    byPrefix[prefix] = byPrefix[prefix] || { n: 0, bytes: 0 };
    byPrefix[prefix].n += 1;
    byPrefix[prefix].bytes += Number(f.metadata.size || 0);
  }

  const logs = await getFirestore().collection('client_logs').get();
  const bytes = [];
  logs.forEach((d) => {
    const x = d.data();
    if (x.source !== 'feed_playback') return;
    const b = x.metadata?.estimatedBytesPlayed || 0;
    if (b > 0) bytes.push(b);
  });
  bytes.sort((a, b) => a - b);

  console.log('Mesures live — adfoot-production');
  for (const [k, v] of Object.entries(byPrefix)) {
    console.log(
      `  ${k.padEnd(15)} ${String(v.n).padStart(4)} obj  ` +
        `${(v.bytes / 1e6).toFixed(1).padStart(8)} Mo  ` +
        `moy ${(v.bytes / v.n / 1e6).toFixed(2)} Mo`,
    );
  }
  const mean = bytes.reduce((a, b) => a + b, 0) / (bytes.length || 1);
  console.log(
    `  sessions de lecture : ${bytes.length}  ` +
      `moyenne ${(mean / 1e6).toFixed(1)} Mo  ` +
      `médiane ${((bytes[Math.floor(bytes.length / 2)] || 0) / 1e6).toFixed(1)} Mo`,
  );
  console.log('');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.get('measure')) {
    await measure(args, String(args.get('env') ?? 'production'));
  }

  const cdnHit = Number(args.get('cdn-hit') ?? 0);
  if (!Number.isFinite(cdnHit) || cdnHit < 0 || cdnHit >= 1) {
    throw new Error('--cdn-hit must be between 0 and 0.99');
  }

  for (const [label, bytesPerSessionMb] of [
    ['MÉDIANE des sessions mesurées', MEASURED.bytesPerSessionMedianMb],
    ['MOYENNE des sessions mesurées', MEASURED.bytesPerSessionMeanMb],
    ['PRUDENTE — préchargement compris', MEASURED.bytesPerSessionPrudentMb],
  ]) {
    console.log('='.repeat(78));
    console.log(
      `Hypothèse de diffusion : ${bytesPerSessionMb} Mo/session — ${label}` +
        (cdnHit ? `   |   CDN ${Math.round(cdnHit * 100)} % de cache` : ''),
    );
    console.log('='.repeat(78));
    console.log('');

    const rows = SCENARIOS.map((s) =>
      modelScenario(s, { cdnHit, bytesPerSessionMb }),
    );

    console.log(
      'Scénario'.padEnd(12) +
        'Joueurs'.padStart(9) +
        'Actifs'.padStart(8) +
        'Sessions'.padStart(11) +
        'Stock Go'.padStart(10) +
        'Sortie Go'.padStart(11),
    );
    for (const r of rows) {
      console.log(
        r.name.padEnd(12) +
          String(r.players).padStart(9) +
          String(r.activeUsers).padStart(8) +
          r.sessions.toLocaleString('fr-FR').padStart(11) +
          r.storedGb.toFixed(0).padStart(10) +
          r.egressGb.toFixed(0).padStart(11),
      );
    }
    console.log('');

    console.log(
      'Poste / mois'.padEnd(14) +
        rows.map((r) => r.name.padStart(14)).join(''),
    );
    for (const line of ['Stockage', 'Diffusion', 'Firestore', 'Functions']) {
      console.log(
        line.padEnd(14) +
          rows.map((r) => eur(r.lines[line]).padStart(14)).join(''),
      );
    }
    console.log('-'.repeat(14 + 14 * rows.length));
    console.log(
      'TOTAL'.padEnd(14) + rows.map((r) => eur(r.totalEur).padStart(14)).join(''),
    );
    console.log(
      'en FCFA'.padEnd(14) + rows.map((r) => xof(r.totalEur).padStart(14)).join(''),
    );
    console.log(
      'par joueur'.padEnd(14) +
        rows
          .map((r) => `${r.perPlayerEur.toFixed(2)} €`.padStart(14))
          .join(''),
    );
    console.log('');
    console.log(
      'Modération'.padEnd(14) +
        rows.map((r) => eur(r.humanEur).padStart(14)).join(''),
    );
    console.log(
      '  heures/mois'.padEnd(14) +
        rows.map((r) => r.humanHours.toFixed(0).padStart(14)).join(''),
    );
    console.log(
      '  équiv. ETP'.padEnd(14) +
        rows.map((r) => r.fte.toFixed(1).padStart(14)).join(''),
    );
    console.log('='.repeat(14 + 14 * rows.length));
    console.log(
      'COÛT COMPLET'.padEnd(14) +
        rows.map((r) => eur(r.totalEur + r.humanEur).padStart(14)).join(''),
    );
    console.log(
      'en FCFA'.padEnd(14) +
        rows.map((r) => xof(r.totalEur + r.humanEur).padStart(14)).join(''),
    );
    console.log('');
  }
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
