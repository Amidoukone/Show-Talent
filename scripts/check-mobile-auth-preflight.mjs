#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const DEFAULT_ENVIRONMENT = 'staging';
const INVALID_PRECHECK_EMAIL = 'not-an-email';

function parseArgs(argv) {
  const parsed = {
    environment: DEFAULT_ENVIRONMENT,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2);
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

async function restJson(url, payload) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
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
      body: parsed,
      url,
      method: 'POST',
    };
    throw error;
  }

  return parsed;
}

async function probePasswordSignup(apiKey) {
  const url =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp' +
    `?key=${encodeURIComponent(apiKey)}`;

  try {
    await restJson(url, {
      email: INVALID_PRECHECK_EMAIL,
      password: buildProbePassword(),
      returnSecureToken: false,
    });

    return {
      ok: false,
      kind: 'unexpected-success',
      message: 'Unexpected success from preflight probe.',
    };
  } catch (error) {
    const remoteCode = String(
      error?.details?.body?.error?.message || error?.message || '',
    ).trim();

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
  const config = readJson(configPath);
  const projectId = String(config.FIREBASE_PROJECT_ID || '').trim();
  const apiKey = String(config.FIREBASE_ANDROID_API_KEY || '').trim();

  if (!projectId) {
    throw new Error(`Missing FIREBASE_PROJECT_ID in ${configPath}`);
  }

  if (!apiKey) {
    throw new Error(`Missing FIREBASE_ANDROID_API_KEY in ${configPath}`);
  }

  process.stdout.write(`Environment : ${args.environment}\n`);
  process.stdout.write(`Project     : ${projectId}\n`);
  process.stdout.write(`Config file : ${configPath}\n`);
  process.stdout.write(`API key     : ${maskApiKey(apiKey)}\n`);
  process.stdout.write('\n');

  const probe = await probePasswordSignup(apiKey);
  if (!probe.ok) {
    printChecklist(projectId, probe);
    process.exitCode = 1;
    return;
  }

  process.stdout.write(`${probe.message}\n`);
}

run().catch((error) => {
  process.stderr.write(`${String(error?.message || error)}\n`);
  process.exitCode = 1;
});
