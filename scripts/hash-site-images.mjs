// Renomme les images de site_pub/images/ sur leur empreinte de contenu et met
// a jour les references de site_pub/index.html.
//
// Pourquoi : firebase.json sert /images/** en `max-age=31536000, immutable`.
// Un nom de fichier reutilise pour un contenu different laisse donc les
// visiteurs deja venus sur l'ancienne image pendant un an, sans recours. Le
// 14 octobre 2026, `player-05.jpg` a porte le joueur n12 puis le n5 : le
// navigateur a continue d'afficher le n12 alors que le serveur envoyait le bon
// fichier. Avec l'empreinte dans le nom, une image modifiee change d'URL.
//
// Idempotent : un nom deja de la forme `base.<8 hex>.jpg` est laisse tel quel,
// sauf si son contenu ne correspond plus, auquel cas il est re-condense.
//
// Usage :
//   node scripts/hash-site-images.mjs            (applique)
//   node scripts/hash-site-images.mjs --check    (verifie sans rien ecrire)
//
// Le garde-fou equivalent cote tests est
// `test/video_release_quality_guardrails_test.dart`, qui refuse une reference
// sans empreinte ou dont l'empreinte ne correspond plus au fichier.

import {createHash} from 'node:crypto';
import {readFileSync, readdirSync, renameSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

const IMAGE_DIR = 'site_pub/images';
const PAGE = 'site_pub/index.html';
const HASHED = /^(.+)\.([0-9a-f]{8})\.(jpg|jpeg|png|webp)$/;
const IMAGE = /\.(jpg|jpeg|png|webp)$/;

const checkOnly = process.argv.includes('--check');
const digestOf = (bytes) => createHash('sha256').update(bytes).digest('hex').slice(0, 8);

let page = readFileSync(PAGE, 'utf8');
const renames = [];

for (const name of readdirSync(IMAGE_DIR).sort()) {
  if (!IMAGE.test(name)) continue;

  const bytes = readFileSync(join(IMAGE_DIR, name));
  const digest = digestOf(bytes);
  const parsed = HASHED.exec(name);

  // Deja condense et toujours exact : rien a faire.
  if (parsed && parsed[2] === digest) continue;

  const base = parsed ? parsed[1] : name.replace(IMAGE, '');
  const extension = name.slice(name.lastIndexOf('.'));
  renames.push([name, `${base}.${digest}${extension}`]);
}

const problems = [];
for (const [from, to] of renames) {
  const needle = `/images/${from}"`;
  const count = page.split(needle).length - 1;
  if (count !== 1) {
    problems.push(`${from} : ${count} reference(s) dans ${PAGE}, 1 attendue`);
    continue;
  }
  if (!checkOnly) {
    renameSync(join(IMAGE_DIR, from), join(IMAGE_DIR, to));
    page = page.split(needle).join(`/images/${to}"`);
  }
  console.log(`${checkOnly ? 'a renommer' : 'renomme  '} ${from} -> ${to}`);
}

if (!checkOnly) writeFileSync(PAGE, page);

// Controle final : chaque reference porte une empreinte exacte, et aucune
// image n'est publiee sans etre utilisee.
const referenced = [...page.matchAll(/\/images\/([^"]+)"/g)].map((m) => m[1]);
for (const name of new Set(referenced)) {
  const parsed = HASHED.exec(name);
  if (!parsed) {
    problems.push(`reference sans empreinte : ${name}`);
    continue;
  }
  try {
    if (digestOf(readFileSync(join(IMAGE_DIR, name))) !== parsed[2]) {
      problems.push(`empreinte perimee : ${name}`);
    }
  } catch {
    problems.push(`reference morte : ${name}`);
  }
}
for (const name of readdirSync(IMAGE_DIR)) {
  if (IMAGE.test(name) && !referenced.includes(name)) {
    problems.push(`image publiee mais jamais utilisee : ${name}`);
  }
}

if (renames.length === 0) console.log('toutes les images sont deja condensees');
for (const problem of problems) console.error(`PROBLEME : ${problem}`);
process.exit(problems.length ? 1 : 0);
