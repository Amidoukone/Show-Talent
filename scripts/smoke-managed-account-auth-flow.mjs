#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const DEFAULT_PROJECT_ID = 'show-talent-5987d';
const DEFAULT_REGION = 'europe-west1';
const DEFAULT_SERVICE_ACCOUNT = path.join('.credentials', 'show-talent-5987d-ops.json');
const DEFAULT_ADMIN_CLAIM = 'admin';

function parseArgs(argv) {
  const parsed = {
    projectId: DEFAULT_PROJECT_ID,
    region: DEFAULT_REGION,
    serviceAccount: DEFAULT_SERVICE_ACCOUNT,
    cleanup: true,
    roles: ['club', 'recruteur', 'agent'],
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];

    if (arg === '--no-cleanup') {
      parsed.cleanup = false;
      continue;
    }

    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      throw new Error(`Missing value for --${key}`);
    }

    switch (key) {
      case 'api-key':
        parsed.apiKey = next.trim();
        break;
      case 'project-id':
        parsed.projectId = next.trim();
        break;
      case 'region':
        parsed.region = next.trim();
        break;
      case 'service-account':
        parsed.serviceAccount = next.trim();
        break;
      case 'admin-email':
        parsed.adminEmail = next.trim().toLowerCase();
        break;
      case 'admin-password':
        parsed.adminPassword = next.trim();
        break;
      case 'roles':
        parsed.roles = next
          .split(',')
          .map((role) => role.trim().toLowerCase())
          .filter(Boolean);
        break;
      default:
        throw new Error(`Unsupported option --${key}`);
    }

    i += 1;
  }

  if (!parsed.apiKey) {
    throw new Error('Missing --api-key');
  }

  if (!parsed.roles.length) {
    throw new Error('No roles supplied.');
  }

  return parsed;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function nowTag() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function randomSuffix() {
  return Math.random().toString(36).slice(2, 8);
}

function buildEphemeralPassword(role, runId) {
  const normalizedRole = String(role || 'user').replace(/[^a-z0-9]/gi, '').slice(0, 12) || 'user';
  return `Smoke-${normalizedRole}-${runId}-${randomSuffix()}!Aa1`;
}

function readServiceAccount(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Service account not found: ${resolved}`);
  }

  const raw = fs.readFileSync(resolved, 'utf8');
  const parsed = JSON.parse(raw);

  if (!parsed || parsed.type !== 'service_account') {
    throw new Error('Invalid service account json.');
  }

  return { resolved, parsed };
}

async function restJson(url, payload, idToken) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }

  if (!response.ok || body?.error) {
    const message =
      body?.error?.message ||
      body?.error?.status ||
      body?.raw ||
      `HTTP ${response.status}`;
    const error = new Error(message);
    error.details = { status: response.status, body };
    throw error;
  }

  return body;
}

async function signInWithPassword({ apiKey, email, password }) {
  return restJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      email,
      password,
      returnSecureToken: true,
    },
  );
}

async function lookupAccount({ apiKey, idToken }) {
  const result = await restJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`,
    { idToken },
  );

  const users = Array.isArray(result.users) ? result.users : [];
  return users[0] || null;
}

async function confirmPasswordReset({ apiKey, oobCode, newPassword }) {
  return restJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${encodeURIComponent(apiKey)}`,
    {
      oobCode,
      newPassword,
    },
  );
}

async function verifyPasswordResetCode({ apiKey, oobCode }) {
  return restJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${encodeURIComponent(apiKey)}`,
    {
      oobCode,
    },
  );
}

async function applyActionCode({ apiKey, oobCode }) {
  return restJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:update?key=${encodeURIComponent(apiKey)}`,
    {
      oobCode,
    },
  );
}

function extractOobCode(link) {
  if (!link) {
    return null;
  }

  try {
    const url = new URL(link);
    return url.searchParams.get('oobCode');
  } catch {
    return null;
  }
}

async function callCallable({ projectId, region, callableName, idToken, data }) {
  const url = `https://${region}-${projectId}.cloudfunctions.net/${callableName}`;
  const response = await restJson(url, { data }, idToken);
  return Object.prototype.hasOwnProperty.call(response, 'result') ? response.result : response;
}

function evaluateUserAccessIssue(userDoc) {
  if (!userDoc) {
    return 'missingProfile';
  }

  const role = String(userDoc.role || '').trim().toLowerCase();
  if (role === 'admin') {
    return 'adminPortalOnly';
  }

  if (userDoc.authDisabled === true) {
    return 'disabledAccount';
  }

  return null;
}

function evaluateMobileDestination({ emailVerified, userDoc }) {
  const issue = evaluateUserAccessIssue(userDoc);

  if (!emailVerified) {
    if (issue === 'adminPortalOnly' || issue === 'disabledAccount') {
      return { destination: 'login', issue };
    }
    return { destination: 'verifyEmail', issue };
  }

  if (issue !== null) {
    return { destination: 'login', issue };
  }

  return { destination: 'main', issue: null };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function ensureSmokeAdmin({ auth, db, email, password }) {
  let userRecord = null;

  try {
    userRecord = await auth.getUserByEmail(email);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') {
      throw error;
    }
  }

  if (!userRecord) {
    userRecord = await auth.createUser({
      email,
      password,
      displayName: 'Smoke Admin',
      emailVerified: true,
      disabled: false,
    });
  } else {
    userRecord = await auth.updateUser(userRecord.uid, {
      displayName: 'Smoke Admin',
      disabled: false,
      emailVerified: true,
      password,
    });
  }

  await auth.setCustomUserClaims(userRecord.uid, {
    [DEFAULT_ADMIN_CLAIM]: true,
  });

  const docRef = db.collection('users').doc(userRecord.uid);
  await docRef.set(
    {
      uid: userRecord.uid,
      nom: 'Smoke Admin',
      email,
      role: 'admin',
      authDisabled: false,
      createdByAdmin: false,
      estActif: true,
      emailVerified: true,
      updatedAt: new Date(),
    },
    { merge: true },
  );

  return userRecord;
}

async function getAdminIdToken({ apiKey, auth, email, password }) {
  for (let attempt = 1; attempt <= 8; attempt += 1) {
    const signIn = await signInWithPassword({ apiKey, email, password });
    const decoded = await auth.verifyIdToken(signIn.idToken);

    if (
      decoded.admin === true ||
      decoded.platformAdmin === true ||
      decoded.superAdmin === true
    ) {
      return signIn.idToken;
    }

    await sleep(1200);
  }

  throw new Error('Unable to get admin id token with required claims.');
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  const runId = nowTag();
  const serviceAccountInfo = readServiceAccount(args.serviceAccount);

  if (!getApps().length) {
    initializeApp({
      credential: cert(serviceAccountInfo.parsed),
      projectId: args.projectId,
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  const adminEmail =
    args.adminEmail || `smoke.admin.${runId.replace(/[^0-9]/g, '').slice(0, 14)}@example.com`;
  const adminPassword = args.adminPassword || `SmokeAdmin!${Math.floor(Math.random() * 1000000)}`;

  const summary = {
    runId,
    projectId: args.projectId,
    region: args.region,
    roles: args.roles,
    serviceAccountPath: serviceAccountInfo.resolved,
    admin: {
      email: adminEmail,
      password: adminPassword,
      uid: null,
    },
    steps: [],
    roleResults: [],
    cleanup: {
      managedAccountsDeleted: [],
      adminDeleted: false,
    },
  };

  const addStep = (name, ok, details = {}) => {
    summary.steps.push({
      timestamp: new Date().toISOString(),
      name,
      ok,
      details,
    });
  };

  const createdManagedUids = [];

  try {
    const adminUser = await ensureSmokeAdmin({
      auth,
      db,
      email: adminEmail,
      password: adminPassword,
    });
    summary.admin.uid = adminUser.uid;
    addStep('ensure_smoke_admin', true, { uid: adminUser.uid, email: adminEmail });

    const adminIdToken = await getAdminIdToken({
      apiKey: args.apiKey,
      auth,
      email: adminEmail,
      password: adminPassword,
    });
    addStep('admin_sign_in_with_claims', true);

    for (const role of args.roles) {
      const roleRun = {
        role,
        email: `smoke.${role}.${runId}.${randomSuffix()}@example.com`,
        uid: null,
        password: buildEphemeralPassword(role, runId),
        checks: {},
      };

      const provisionResponse = await callCallable({
        projectId: args.projectId,
        region: args.region,
        callableName: 'provisionManagedAccount',
        idToken: adminIdToken,
        data: {
          email: roleRun.email,
          nom: `Smoke ${role}`,
          role,
        },
      });

      const provisionData = provisionResponse?.data || provisionResponse;
      assert(provisionData?.uid, `provisionManagedAccount did not return uid for ${role}`);
      assert(provisionData?.role === role, `provisionManagedAccount role mismatch for ${role}`);
      roleRun.uid = provisionData.uid;
      createdManagedUids.push(provisionData.uid);

      const managedDocSnap = await db.collection('users').doc(roleRun.uid).get();
      const managedDoc = managedDocSnap.data() || null;
      assert(managedDocSnap.exists, `Missing /users doc after provision for ${role}`);
      assert(String(managedDoc.role || '').toLowerCase() === role, `Firestore role mismatch for ${role}`);
      assert(managedDoc.createdByAdmin === true, `createdByAdmin should be true for ${role}`);

      roleRun.checks.provision = {
        uid: roleRun.uid,
        existingUser: provisionData.existingUser === true,
      };

      const resetCode = extractOobCode(provisionData.passwordSetupLink);
      assert(resetCode, `Missing password reset code for ${role}`);

      await verifyPasswordResetCode({
        apiKey: args.apiKey,
        oobCode: resetCode,
      });
      await auth.updateUser(roleRun.uid, {
        password: roleRun.password,
        emailVerified: false,
        disabled: false,
      });
      roleRun.checks.passwordSetup = { ok: true };

      const signInBeforeVerify = await signInWithPassword({
        apiKey: args.apiKey,
        email: roleRun.email,
        password: roleRun.password,
      });
      const lookupBeforeVerify = await lookupAccount({
        apiKey: args.apiKey,
        idToken: signInBeforeVerify.idToken,
      });
      const beforeDecision = evaluateMobileDestination({
        emailVerified: lookupBeforeVerify?.emailVerified === true,
        userDoc: managedDoc,
      });
      assert(beforeDecision.destination === 'verifyEmail', `Expected verifyEmail before verification for ${role}`);
      roleRun.checks.loginBeforeVerification = beforeDecision;

      const verifyCode = extractOobCode(provisionData.emailVerificationLink);
      assert(verifyCode, `Missing email verification code for ${role}`);
      await applyActionCode({
        apiKey: args.apiKey,
        oobCode: verifyCode,
      });
      roleRun.checks.emailVerificationApplied = { ok: true };

      const signInAfterVerify = await signInWithPassword({
        apiKey: args.apiKey,
        email: roleRun.email,
        password: roleRun.password,
      });
      const lookupAfterVerify = await lookupAccount({
        apiKey: args.apiKey,
        idToken: signInAfterVerify.idToken,
      });
      const refreshedDocAfterVerify = (await db.collection('users').doc(roleRun.uid).get()).data() || null;
      const afterDecision = evaluateMobileDestination({
        emailVerified: lookupAfterVerify?.emailVerified === true,
        userDoc: refreshedDocAfterVerify,
      });
      assert(afterDecision.destination === 'main', `Expected main after verification for ${role}`);
      roleRun.checks.loginAfterVerification = afterDecision;

      await callCallable({
        projectId: args.projectId,
        region: args.region,
        callableName: 'disableManagedAccountAuth',
        idToken: adminIdToken,
        data: { uid: roleRun.uid },
      });

      let disabledError = null;
      try {
        await signInWithPassword({
          apiKey: args.apiKey,
          email: roleRun.email,
          password: roleRun.password,
        });
      } catch (error) {
        disabledError = String(error.message || 'unknown_error');
      }
      assert(disabledError !== null, `Expected sign-in failure when auth disabled for ${role}`);
      roleRun.checks.authDisabled = { signInError: disabledError };

      await callCallable({
        projectId: args.projectId,
        region: args.region,
        callableName: 'enableManagedAccountAuth',
        idToken: adminIdToken,
        data: { uid: roleRun.uid },
      });

      const signInAfterEnable = await signInWithPassword({
        apiKey: args.apiKey,
        email: roleRun.email,
        password: roleRun.password,
      });
      const lookupAfterEnable = await lookupAccount({
        apiKey: args.apiKey,
        idToken: signInAfterEnable.idToken,
      });
      const enabledDoc = (await db.collection('users').doc(roleRun.uid).get()).data() || null;
      const enabledDecision = evaluateMobileDestination({
        emailVerified: lookupAfterEnable?.emailVerified === true,
        userDoc: enabledDoc,
      });
      assert(enabledDecision.destination === 'main', `Expected main after auth re-enable for ${role}`);
      roleRun.checks.authReEnabled = enabledDecision;

      summary.roleResults.push(roleRun);
      addStep(`role_smoke_${role}`, true, {
        email: roleRun.email,
        uid: roleRun.uid,
      });
    }

    if (args.cleanup) {
      const adminIdToken = await getAdminIdToken({
        apiKey: args.apiKey,
        auth,
        email: adminEmail,
        password: adminPassword,
      });

      for (const uid of createdManagedUids) {
        await callCallable({
          projectId: args.projectId,
          region: args.region,
          callableName: 'deleteManagedAccount',
          idToken: adminIdToken,
          data: { uid },
        });
        summary.cleanup.managedAccountsDeleted.push(uid);
      }

      if (summary.admin.uid) {
        await db.collection('users').doc(summary.admin.uid).delete().catch(() => {});
        await auth.deleteUser(summary.admin.uid).catch(() => {});
        summary.cleanup.adminDeleted = true;
      }
      addStep('cleanup', true, {
        managedDeletedCount: summary.cleanup.managedAccountsDeleted.length,
        adminDeleted: summary.cleanup.adminDeleted,
      });
    }

    const reportPath = path.resolve('docs', `smoke-managed-account-auth-${runId}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');

    process.stdout.write(`Smoke run completed successfully.\n`);
    process.stdout.write(`Report: ${reportPath}\n`);
    process.stdout.write(`${JSON.stringify({
      runId,
      rolesChecked: summary.roleResults.map((entry) => entry.role),
      cleanup: summary.cleanup,
    }, null, 2)}\n`);
  } catch (error) {
    const reportPath = path.resolve('docs', `smoke-managed-account-auth-${runId}-failed.json`);
    const failure = {
      ...summary,
      failedAt: new Date().toISOString(),
      error: {
        message: String(error?.message || error),
        details: error?.details || null,
      },
    };
    fs.writeFileSync(reportPath, `${JSON.stringify(failure, null, 2)}\n`, 'utf8');
    process.stderr.write(`Smoke run failed. Report: ${reportPath}\n`);
    process.stderr.write(`${failure.error.message}\n`);
    process.exitCode = 1;
  }
}

run();
