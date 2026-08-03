#!/usr/bin/env node

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

function getBoolArg(args, names, fallback = false) {
  for (const name of names) {
    if (args.has(name)) {
      const value = args.get(name);
      if (value === true) return true;
      return ['1', 'true', 'yes', 'y'].includes(
        String(value).trim().toLowerCase(),
      );
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

async function patchJson(url, accessToken, body) {
  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();

  if (!response.ok) {
    throw new Error(`PATCH ${url} failed (HTTP ${response.status}). ${text}`);
  }

  return text ? JSON.parse(text) : {};
}

function compactName(resourceName) {
  return String(resourceName ?? '').split('/').pop() || '<unknown>';
}

function printPlayIntegrity(config) {
  console.log('');
  console.log('Play Integrity config:');
  console.log(`- tokenTtl: ${config.tokenTtl || '<default 3600s>'}`);
  console.log(
    `- allowUnrecognizedVersion: ${
      config.appIntegrity?.allowUnrecognizedVersion ?? false
    }`,
  );
  console.log(
    `- minDeviceRecognitionLevel: ${
      config.deviceIntegrity?.minDeviceRecognitionLevel || '<default NO_INTEGRITY>'
    }`,
  );
  console.log(
    `- requireLicensed: ${config.accountDetails?.requireLicensed ?? false}`,
  );
}

function printDebugTokens(response) {
  const tokens = response.debugTokens ?? [];
  console.log('');
  console.log('Debug tokens:');
  console.log(`- count: ${tokens.length}`);
  for (const token of tokens) {
    console.log(
      `- ${token.displayName || compactName(token.name)} ` +
        `(updateTime=${token.updateTime || '<unknown>'})`,
    );
  }
}

function printServices(response) {
  const services = response.services ?? [];
  const interestingIds = new Set([
    'firestore.googleapis.com',
    'firebasestorage.googleapis.com',
    'identitytoolkit.googleapis.com',
  ]);

  console.log('');
  console.log('Firebase service enforcement:');
  for (const service of services) {
    const serviceId = compactName(service.name);
    if (!interestingIds.has(serviceId)) {
      continue;
    }

    console.log(
      `- ${serviceId}: ${service.enforcementMode || '<unset>'}` +
        `, replay=${service.replayProtection || '<unset>'}`,
    );
  }
}

async function main() {
  if (typeof fetch !== 'function') {
    throw new Error('This script requires Node.js 18+ with global fetch.');
  }

  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const shouldExecute = getBoolArg(args, ['execute'], false);
  const shouldPatchAllowUnrecognized =
    args.has('allow-unrecognized-version') ||
    args.has('allowUnrecognizedVersion');
  const allowUnrecognizedVersion = getBoolArg(
    args,
    ['allow-unrecognized-version', 'allowUnrecognizedVersion'],
    false,
  );
  const configPath = resolveRepoPath(
    getStringArg(
      args,
      ['config', 'config-path'],
      path.join('config', 'mobile', `${environment}.json`),
    ),
  );
  const config = await readJsonFile(configPath, 'mobile config');
  const projectId = requireConfigValue(config, 'FIREBASE_PROJECT_ID', configPath);
  const projectNumber = requireConfigValue(
    config,
    'FIREBASE_MESSAGING_SENDER_ID',
    configPath,
  );
  const appId = requireConfigValue(config, 'FIREBASE_ANDROID_APP_ID', configPath);
  const credentialsPath = resolveCredentialsPath(args, projectId);
  const accessToken = await getAccessToken(credentialsPath);
  const encodedAppId = encodeURIComponent(appId);
  const baseUrl = 'https://firebaseappcheck.googleapis.com/v1';
  const playIntegrityUrl =
    `${baseUrl}/projects/${projectNumber}/apps/${encodedAppId}/playIntegrityConfig`;

  if (shouldPatchAllowUnrecognized) {
    console.log(
      shouldExecute ?
        'Applying Play Integrity App Check update...' :
        'Planned Play Integrity App Check update (dry-run):',
    );
    console.log(`- allowUnrecognizedVersion: ${allowUnrecognizedVersion}`);

    if (shouldExecute) {
      await patchJson(
        `${playIntegrityUrl}?updateMask=appIntegrity.allowUnrecognizedVersion`,
        accessToken,
        { appIntegrity: { allowUnrecognizedVersion } },
      );
      console.log('Update applied.');
    } else {
      console.log('Re-run with --execute to apply this remote update.');
    }
  }

  const [playIntegrity, debugTokens, services] = await Promise.all([
    fetchJson(playIntegrityUrl, accessToken),
    fetchJson(
      `${baseUrl}/projects/${projectNumber}/apps/${encodedAppId}/debugTokens`,
      accessToken,
    ),
    fetchJson(`${baseUrl}/projects/${projectNumber}/services`, accessToken),
  ]);

  console.log('App Check remote status');
  console.log(`Project: ${projectId} (${projectNumber})`);
  console.log(`Android app: ${appId}`);
  printPlayIntegrity(playIntegrity);
  printDebugTokens(debugTokens);
  printServices(services);
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
