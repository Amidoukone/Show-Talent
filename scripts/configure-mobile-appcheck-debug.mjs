#!/usr/bin/env node

import { randomUUID } from 'crypto';
import { existsSync } from 'fs';
import { readFile, writeFile } from 'fs/promises';
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
      const normalized = String(value).trim().toLowerCase();
      return ['1', 'true', 'yes', 'y'].includes(normalized);
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

function assertUuid4(token) {
  const uuid4 =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuid4.test(token)) {
    throw new Error('App Check debug token must be a UUIDv4.');
  }
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

function compactTimestamp(date = new Date()) {
  return date.toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z';
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

async function createDebugToken({
  projectNumber,
  appId,
  displayName,
  token,
  credentialsPath,
}) {
  if (typeof fetch !== 'function') {
    throw new Error('This script requires Node.js 18+ with global fetch.');
  }

  const accessToken = await getAccessToken(credentialsPath);
  const url =
    'https://firebaseappcheck.googleapis.com/v1/' +
    `projects/${encodeURIComponent(projectNumber)}/` +
    `apps/${encodeURIComponent(appId)}/debugTokens`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      displayName,
      token,
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(
      `Firebase App Check debug token creation failed ` +
        `(HTTP ${response.status}). ${body}`,
    );
  }

  return body ? JSON.parse(body) : {};
}

async function updateMobileConfig(configPath, config, token) {
  const updated = {
    ...config,
    APP_CHECK_ENABLED: 'true',
    APP_CHECK_DEBUG_PROVIDER: 'true',
    APP_CHECK_ANDROID_PROVIDER: 'debug',
    APP_CHECK_ANDROID_DEBUG_TOKEN: token,
  };

  await writeFile(configPath, `${JSON.stringify(updated, null, 2)}\n`, 'utf8');
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const environment = getStringArg(args, ['environment', 'env'], 'production');
  const configPath = resolveRepoPath(
    getStringArg(
      args,
      ['config', 'config-path'],
      path.join('config', 'mobile', `${environment}.json`),
    ),
  );
  const explicitTokenProvided = args.has('token');
  const token = getStringArg(args, ['token'], randomUUID());
  const displayName = getStringArg(
    args,
    ['display-name', 'displayName'],
    `adfoot-${environment}-prestore-${compactTimestamp()}`,
  );
  const writeConfig = getBoolArg(args, ['write-config', 'writeConfig'], false);
  const registerToken = !getBoolArg(args, ['no-register', 'noRegister'], false);

  assertUuid4(token);

  if (registerToken && !writeConfig && !explicitTokenProvided) {
    throw new Error(
      'Refusing to create a generated debug token without --write-config. ' +
        'Use --write-config, or pass your own --token value.',
    );
  }

  const config = await readJsonFile(configPath, 'mobile config');
  const configEnv = String(config.APP_ENV ?? '').trim();
  if (configEnv && configEnv !== environment) {
    throw new Error(
      `Mobile config APP_ENV is '${configEnv}' but --environment is '${environment}'.`,
    );
  }

  const projectId = requireConfigValue(config, 'FIREBASE_PROJECT_ID', configPath);
  const projectNumber = requireConfigValue(
    config,
    'FIREBASE_MESSAGING_SENDER_ID',
    configPath,
  );
  const appId = requireConfigValue(config, 'FIREBASE_ANDROID_APP_ID', configPath);

  if (registerToken) {
    const credentialsPath = resolveCredentialsPath(args, projectId);
    await createDebugToken({
      projectNumber,
      appId,
      displayName,
      token,
      credentialsPath,
    });
    console.log(`Registered App Check debug token: ${displayName}`);
  } else {
    console.log('Skipped Firebase App Check debug token registration.');
  }

  if (writeConfig) {
    await updateMobileConfig(configPath, config, token);
    console.log(`Updated local mobile config: ${path.relative(repoRoot, configPath)}`);
  } else {
    console.log('Mobile config not updated. Re-run with --write-config to persist it.');
  }

  console.log(`Project: ${projectId}`);
  console.log(`Android app: ${appId}`);
  console.log(
    writeConfig
      ? 'Debug token: <written to ignored local config>'
      : 'Debug token: <not printed; use the --token value you supplied>',
  );
  console.log('Next run: npm.cmd run mobile:run:production -- --release');
}

main().catch((error) => {
  console.error(error?.stack || error?.message || String(error));
  process.exit(1);
});
