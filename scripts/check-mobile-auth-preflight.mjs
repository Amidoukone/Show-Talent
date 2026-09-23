#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_ENVIRONMENT = 'staging';
const INVALID_PRECHECK_EMAIL = 'not-an-email';
const PLATFORMS = new Set(['android', 'ios']);

function parseArgs(argv) {
  const parsed = {
    environment: DEFAULT_ENVIRONMENT,
    platform: 'android',
    fromEnv: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2);
    if (key === 'from-env') {
      parsed.fromEnv = true;
      continue;
    }
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      throw new Error(`Missing value for --${key}`);
    }

    switch (key) {
      case 'environment':
        parsed.environment = next.trim();
        break;
      case 'config':
        parsed.configPath = next.trim();
        break;
      case 'platform':
        parsed.platform = next.trim().toLowerCase();
        if (!PLATFORMS.has(parsed.platform)) {
          throw new Error(`Unsupported platform: ${parsed.platform}`);
        }
        break;
      default:
        throw new Error(`Unsupported option --${key}`);
    }

    i += 1;
  }

  return parsed;
}

function resolveConfigPath(environment, explicitPath) {
  if (explicitPath) {
    return path.resolve(explicitPath);
  }

  return path.resolve('config', 'mobile', `${environment}.json`);
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing mobile config file: ${filePath}`);
  }

  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function maskApiKey(value) {
  if (!value) {
    return '<missing>';
  }

  if (value.length <= 10) {
    return '********';
  }

  return `${value.slice(0, 6)}...${value.slice(-4)}`;
}

function buildProbePassword() {
  const entropy = Math.random().toString(36).slice(2, 10);
  return `Probe-${Date.now().toString(36)}-${entropy}!Aa1`;
}

function buildProbeEmail() {
  return `auth-preflight-${Date.now()}-${Math.random().toString(36).slice(2)}@example.invalid`;
}

async function restJson(url, payload, { method = 'POST', headers = {} } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    ...(method === 'POST' ? { body: JSON.stringify(payload) } : {}),
  });

  const text = await response.text();
  let parsed = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw: text };
  }

  if (!response.ok || parsed?.error) {
    const error = new Error(
      parsed?.error?.message || parsed?.raw || `HTTP ${response.status}`,
    );
    error.details = {
      status: response.status,
      remoteCode: parsed?.error?.message || null,
      endpoint: new URL(url).pathname,
      method,
    };
    throw error;
  }

  return parsed;
}

async function probePasswordSignup(apiKey, headers = {}) {
  const url =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp' +
    `?key=${encodeURIComponent(apiKey)}`;

  try {
    await restJson(url, {
      email: INVALID_PRECHECK_EMAIL,
      password: buildProbePassword(),
      returnSecureToken: false,
    }, { headers });

    return {
      ok: false,
      kind: 'unexpected-success',
      message: 'Unexpected success from preflight probe.',
    };
  } catch (error) {
    const remoteCode = String(error?.details?.remoteCode || error?.message || '').trim();

    switch (remoteCode) {
      case 'INVALID_EMAIL':
        return {
          ok: true,
          kind: 'auth-ready',
          message:
            'Firebase Authentication responds correctly for Email/Password.',
        };
      case 'OPERATION_NOT_ALLOWED':
      case 'PASSWORD_LOGIN_DISABLED':
        return {
          ok: false,
          kind: 'provider-disabled',
          message:
            'Email/Password is disabled for this Firebase project.',
        };
      case 'CONFIGURATION_NOT_FOUND':
        return {
          ok: false,
          kind: 'configuration-not-found',
          message:
            'Firebase Authentication is not initialized correctly for this environment.',
        };
      default:
        return {
          ok: false,
          kind: 'unexpected-error',
          message: remoteCode || 'Unknown Firebase Auth preflight failure.',
          details: error?.details || null,
        };
    }
  }
}

async function probePasswordSignIn(apiKey, headers = {}) {
  const url =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword' +
    `?key=${encodeURIComponent(apiKey)}`;
  try {
    await restJson(url, {
      email: buildProbeEmail(),
      password: buildProbePassword(),
      returnSecureToken: false,
    }, { headers });
    throw new Error('Unexpected sign-in with a random, nonexistent account.');
  } catch (error) {
    const remoteCode = String(error?.details?.remoteCode || error?.message || '').trim();
    if (['INVALID_LOGIN_CREDENTIALS', 'EMAIL_NOT_FOUND', 'INVALID_PASSWORD'].includes(remoteCode)) {
      return;
    }
    throw new Error(`Firebase Email/Password sign-in probe failed: ${remoteCode}`);
  }
}

async function probeIosProject({ apiKey, bundleId, appId, projectNumber }) {
  const url = new URL('https://identitytoolkit.googleapis.com/v1/projects');
  url.searchParams.set('key', apiKey);
  url.searchParams.set('iosBundleId', bundleId);
  url.searchParams.set('firebaseAppId', appId);

  const config = await restJson(url, null, {
    method: 'GET',
    headers: { 'X-Ios-Bundle-Identifier': bundleId },
  });
  // This legacy endpoint returns the numeric Google project number in
  // `projectId`, not the human-readable Firebase project ID.
  if (String(config.projectId) !== projectNumber) {
    throw new Error(
      `iOS API key resolves to project number ${config.projectId || '<unknown>'}, ` +
      `expected ${projectNumber}.`,
    );
  }
  return config.projectId;
}

function printChecklist(projectId, probe) {
  process.stderr.write('\nRemote Auth preflight failed.\n');
  process.stderr.write(`Project: ${projectId}\n`);
  process.stderr.write(`Reason : ${probe.message}\n`);
  process.stderr.write('\nChecklist:\n');

  if (probe.kind === 'configuration-not-found') {
    process.stderr.write(
      '- Open Firebase Console for this project and initialize Authentication.\n',
    );
    process.stderr.write(
      '- In Authentication > Sign-in method, enable Email/Password.\n',
    );
    process.stderr.write(
      '- Verify the mobile API key belongs to the same Firebase project.\n',
    );
    process.stderr.write(
      '- Wait a few minutes after saving the Auth configuration, then retry.\n',
    );
    return;
  }

  if (probe.kind === 'provider-disabled') {
    process.stderr.write(
      '- In Authentication > Sign-in method, enable Email/Password.\n',
    );
    process.stderr.write(
      '- Retry the mobile launch after the provider is enabled.\n',
    );
    return;
  }

  process.stderr.write(
    '- Re-check the Firebase project, API key, and Authentication configuration.\n',
  );
  if (probe.details) {
    process.stderr.write(`${JSON.stringify(probe.details, null, 2)}\n`);
  }
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  const configPath = resolveConfigPath(args.environment, args.configPath);
  const config = args.fromEnv ? process.env : readJson(configPath);
  const projectId = String(config.FIREBASE_PROJECT_ID || '').trim();
  const apiKeyName = args.platform === 'ios'
    ? 'FIREBASE_IOS_API_KEY'
    : 'FIREBASE_ANDROID_API_KEY';
  const apiKey = String(config[apiKeyName] || '').trim();

  if (!projectId) {
    throw new Error(`Missing FIREBASE_PROJECT_ID in ${configPath}`);
  }

  if (!apiKey) {
    throw new Error(`Missing ${apiKeyName} in ${args.fromEnv ? 'environment' : configPath}`);
  }

  const bundleId = String(config.FIREBASE_IOS_BUNDLE_ID || '').trim();
  const appId = String(config.FIREBASE_IOS_APP_ID || '').trim();
  const projectNumber = String(config.FIREBASE_MESSAGING_SENDER_ID || '').trim();
  if (args.platform === 'ios' && (!bundleId || !appId || !projectNumber)) {
    throw new Error('Missing Firebase iOS bundle ID, app ID or project number.');
  }

  process.stdout.write(`Environment : ${args.environment}\n`);
  process.stdout.write(`Platform    : ${args.platform}\n`);
  process.stdout.write(`Project     : ${projectId}\n`);
  process.stdout.write(`Config source: ${args.fromEnv ? 'environment' : configPath}\n`);
  process.stdout.write(`API key     : ${maskApiKey(apiKey)}\n`);
  process.stdout.write('\n');

  const headers = args.platform === 'ios'
    ? { 'X-Ios-Bundle-Identifier': bundleId }
    : {};
  if (args.platform === 'ios') {
    const resolvedProjectId = await probeIosProject({
      apiKey, bundleId, appId, projectNumber,
    });
    process.stdout.write(`iOS key, app ID and bundle resolve to ${resolvedProjectId}.\n`);
  }

  const probe = await probePasswordSignup(apiKey, headers);
  if (!probe.ok) {
    printChecklist(projectId, probe);
    process.exitCode = 1;
    return;
  }

  await probePasswordSignIn(apiKey, headers);
  process.stdout.write(`${probe.message}\n`);
  process.stdout.write('Firebase Email/Password sign-in endpoint responds correctly.\n');
}

run().catch((error) => {
  process.stderr.write(`${String(error?.message || error)}\n`);
  process.exitCode = 1;
});
