#!/usr/bin/env node

import { createHash } from 'crypto';
import { existsSync } from 'fs';
import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert } from 'firebase-admin/app';

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
  if (!value) throw new Error(`Missing ${key} in ${configPath}.`);
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
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(
    'Missing service account credentials. Pass --credentials, set ' +
      'GOOGLE_APPLICATION_CREDENTIALS, or create .credentials/<project>-ops.json.',
  );
}

async function getAccessToken(credentialsPath) {
  const serviceAccount = await readJsonFile(credentialsPath, 'service account');
  const credential = cert(serviceAccount);
  const token = await credential.getAccessToken();
  if (!token?.access_token) {
    throw new Error('Service account did not return an OAuth access token.');
  }
  return token.access_token;
}

async function fetchJson(url, accessToken) {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const body = await response.text();

  if (!response.ok) {
    throw new Error(`GET ${url} failed (HTTP ${response.status}). ${body}`);
  }

  return body ? JSON.parse(body) : {};
}

function sha256(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function normalizeRules(value) {
  return String(value ?? '').replace(/\r\n/g, '\n').trim();
}

function releaseLabel(releaseName) {
  return String(releaseName ?? '').split('/releases/').pop() || '<unknown>';
}

async function main() {
  if (typeof fetch !== 'function') {
    throw new Error('This script requires Node.js 18+ with global fetch.');
  }

  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
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
  const accessToken = await getAccessToken(credentialsPath);
  const baseUrl = 'https://firebaserules.googleapis.com/v1';

  const releasesResponse = await fetchJson(
    `${baseUrl}/projects/${projectId}/releases?pageSize=100`,
    accessToken,
  );
  const releases = releasesResponse.releases ?? [];
  const localByRelease = new Map([
    ['cloud.firestore', normalizeRules(await readFile(path.join(repoRoot, 'firestore.rules'), 'utf8'))],
    ['firebase.storage', normalizeRules(await readFile(path.join(repoRoot, 'storage.rules'), 'utf8'))],
  ]);

  console.log('Firebase Rules deployed comparison');
  console.log(`Project: ${projectId}`);

  for (const release of releases) {
    const label = releaseLabel(release.name);
    if (!localByRelease.has(label)) continue;

    const ruleset = await fetchJson(`${baseUrl}/${release.rulesetName}`, accessToken);
    const files = ruleset.source?.files ?? [];
    const deployed = normalizeRules(files.map((file) => file.content || '').join('\n'));
    const local = localByRelease.get(label);
    const deployedHash = sha256(deployed);
    const localHash = sha256(local);

    console.log('');
    console.log(`- ${label}`);
    console.log(`  ruleset: ${release.rulesetName}`);
    console.log(`  createTime: ${release.createTime || '<unknown>'}`);
    console.log(`  updateTime: ${release.updateTime || '<unknown>'}`);
    console.log(`  deployedSha256: ${deployedHash}`);
    console.log(`  localSha256:    ${localHash}`);
    console.log(`  matchesLocal:   ${deployedHash === localHash}`);
  }
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
