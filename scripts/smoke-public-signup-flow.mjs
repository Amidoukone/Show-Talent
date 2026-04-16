#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const DEFAULT_ENVIRONMENT = 'production-next';
const DEFAULT_REGION = 'europe-west1';
const DEFAULT_ROLE = 'joueur';

function parseArgs(argv) {
  const parsed = {
    environment: DEFAULT_ENVIRONMENT,
    region: DEFAULT_REGION,
    role: DEFAULT_ROLE,
    cleanup: true,
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
      case 'environment':
        parsed.environment = next.trim();
        break;
      case 'config':
        parsed.configPath = next.trim();
        break;
      case 'region':
        parsed.region = next.trim();
        break;
      case 'role':
        parsed.role = next.trim().toLowerCase();
        break;
      case 'service-account':
        parsed.serviceAccount = next.trim();
        break;
      case 'email-link-host':
        parsed.emailLinkHost = next.trim().toLowerCase();
        break;
      default:
        throw new Error(`Unsupported option --${key}`);
    }

    i += 1;
  }

  if (!['joueur', 'fan'].includes(parsed.role)) {
    throw new Error('Only public roles joueur and fan are supported.');
  }

  return parsed;
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readJson(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Missing JSON file: ${resolved}`);
  }
  return JSON.parse(fs.readFileSync(resolved, 'utf8'));
}

function resolveMobileConfigPath(environment, explicitPath) {
  if (explicitPath) {
    return explicitPath;
  }
  return path.join('config', 'mobile', `${environment}.json`);
}

function effectiveAppEnvironment(environment) {
  switch (String(environment || '').trim().toLowerCase()) {
    case 'local':
      return 'local';
    case 'staging':
      return 'staging';
    default:
      return 'production';
  }
}

function packageNameForEnvironment(environment) {
  switch (effectiveAppEnvironment(environment)) {
    case 'local':
      return 'org.adfoot.app.local';
    case 'staging':
      return 'org.adfoot.app.staging';
    default:
      return 'org.adfoot.app';
  }
}

function actionUrlForHost(host, pathName) {
  const normalizedPath = pathName.startsWith('/') ? pathName : `/${pathName}`;
  return `https://${host}${normalizedPath}`;
}

function resolveServiceAccountPath(explicitPath, projectId) {
  const envPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY_PATH ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const candidate =
    explicitPath ||
    envPath ||
    path.join('.credentials', `${projectId}-ops.json`);
  return path.resolve(candidate);
}

function readServiceAccount(filePath, projectId) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    throw new Error(
      `Missing service account for ${projectId}: ${resolved}. ` +
      'Provide --service-account or set FIREBASE_SERVICE_ACCOUNT_KEY_PATH / GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }

  const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  if (!parsed || parsed.type !== 'service_account') {
    throw new Error(`Invalid service account json: ${resolved}`);
  }

  if (parsed.project_id !== projectId) {
    throw new Error(
      `Service account project mismatch. Expected ${projectId}, got ${String(parsed.project_id || '')}.`,
    );
  }

  return { resolved, parsed };
}

function defaultEmailLinkHostForProject(mobileConfig, projectId) {
  const authDomain = String(mobileConfig.FIREBASE_WEB_AUTH_DOMAIN || '').trim().toLowerCase();
  if (authDomain) {
    return authDomain;
  }

  return `${projectId}.firebaseapp.com`;
}

async function restJson(url, { method = 'POST', headers = {}, body } = {}) {
  const response = await fetch(url, {
    method,
    headers,
    body,
  });

  const text = await response.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw: text };
  }

  if (!response.ok || parsed?.error) {
    const message =
      parsed?.error?.message ||
      parsed?.error?.status ||
      parsed?.raw ||
      `HTTP ${response.status}`;
    const error = new Error(message);
    error.details = {
      status: response.status,
      body: parsed,
      url,
      method,
    };
    throw error;
  }

  return parsed;
}

async function identityJson(apiKey, methodName, payload) {
  return restJson(
    `https://identitytoolkit.googleapis.com/v1/${methodName}?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    },
  );
}

async function signUpWithPassword({ apiKey, email, password }) {
  return identityJson(apiKey, 'accounts:signUp', {
    email,
    password,
    returnSecureToken: true,
  });
}

async function signInWithPassword({ apiKey, email, password }) {
  return identityJson(apiKey, 'accounts:signInWithPassword', {
    email,
    password,
    returnSecureToken: true,
  });
}

async function lookupAccount({ apiKey, idToken }) {
  const result = await identityJson(apiKey, 'accounts:lookup', { idToken });
  const users = Array.isArray(result.users) ? result.users : [];
  return users[0] || null;
}

async function updateAccountProfile({ apiKey, idToken, displayName }) {
  return identityJson(apiKey, 'accounts:update', {
    idToken,
    displayName,
    returnSecureToken: true,
  });
}

async function sendEmailVerificationOob({
  adminAuth,
  email,
  continueUrl,
  androidPackageName,
  iOSBundleId,
}) {
  const oobLink = await adminAuth.generateEmailVerificationLink(email, {
    url: continueUrl,
    handleCodeInApp: true,
    android: {
      packageName: androidPackageName,
      installApp: true,
    },
    iOS: {
      bundleId: iOSBundleId,
    },
  });

  return { oobLink };
}

async function applyActionCode({ apiKey, oobCode }) {
  return identityJson(apiKey, 'accounts:update', { oobCode });
}

async function deleteAccount({ apiKey, idToken }) {
  return identityJson(apiKey, 'accounts:delete', { idToken });
}

function extractQueryParamsFromUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl);
    return Object.fromEntries(parsed.searchParams.entries());
  } catch {
    return {};
  }
}

function extractActionParams(rawUrl, depth = 0) {
  const params = extractQueryParamsFromUrl(rawUrl);
  if (depth >= 3) {
    return params;
  }

  for (const nestedKey of ['link', 'continueUrl', 'deep_link_id']) {
    const nestedValue = params[nestedKey];
    if (!nestedValue) {
      continue;
    }
    const nestedParams = extractActionParams(nestedValue, depth + 1);
    for (const [key, value] of Object.entries(nestedParams)) {
      if (!(key in params)) {
        params[key] = value;
      }
    }
  }

  return params;
}

function firestoreTimestamp(date) {
  return { timestampValue: date.toISOString() };
}

function firestoreString(value) {
  return { stringValue: value };
}

function firestoreBool(value) {
  return { booleanValue: value };
}

function firestoreInt(value) {
  return { integerValue: String(value) };
}

function firestoreNull() {
  return { nullValue: null };
}

function firestoreArray(values) {
  return {
    arrayValue: {
      values,
    },
  };
}

function firestoreMap(fields) {
  return {
    mapValue: {
      fields,
    },
  };
}

function buildPublicSignupFirestoreFields({
  uid,
  nom,
  email,
  role,
  phone,
  now,
}) {
  return {
    uid: firestoreString(uid),
    nom: firestoreString(nom),
    email: firestoreString(email),
    role: firestoreString(role),
    photoProfil: firestoreString(''),
    estActif: firestoreBool(false),
    authDisabled: firestoreBool(false),
    emailVerified: firestoreBool(false),
    createdByAdmin: firestoreBool(false),
    followers: firestoreInt(0),
    followings: firestoreInt(0),
    dateInscription: firestoreTimestamp(now),
    dernierLogin: firestoreTimestamp(now),
    emailVerifiedAt: firestoreNull(),
    phone: phone ? firestoreString(phone) : firestoreNull(),
    authDisabledReason: firestoreNull(),
    birthDate: firestoreNull(),
    country: firestoreNull(),
    city: firestoreNull(),
    region: firestoreNull(),
    languages: firestoreNull(),
    openToOpportunities: firestoreNull(),
    bio: firestoreNull(),
    position: firestoreNull(),
    clubActuel: firestoreNull(),
    nombreDeMatchs: firestoreNull(),
    buts: firestoreNull(),
    assistances: firestoreNull(),
    videosPubliees: firestoreArray([]),
    performances: firestoreMap({}),
    playerProfile: firestoreNull(),
    clubProfile: firestoreNull(),
    agentProfile: firestoreNull(),
    eventOrganizerProfile: firestoreNull(),
    nomClub: firestoreNull(),
    ligue: firestoreNull(),
    offrePubliees: firestoreArray([]),
    eventPublies: firestoreArray([]),
    entreprise: firestoreNull(),
    nombreDeRecrutements: firestoreNull(),
    team: firestoreNull(),
    joueursSuivis: firestoreArray([]),
    clubsSuivis: firestoreArray([]),
    videosLikees: firestoreArray([]),
    followersList: firestoreArray([]),
    followingsList: firestoreArray([]),
    cvUrl: firestoreNull(),
    profilePublic: firestoreBool(true),
    allowMessages: firestoreBool(true),
  };
}

function firestoreDocumentUrl(projectId, uid) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${uid}`;
}

async function createUserDocument({
  projectId,
  uid,
  idToken,
  fields,
}) {
  return restJson(firestoreDocumentUrl(projectId, uid), {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ fields }),
  });
}

async function getUserDocument({ projectId, uid, idToken }) {
  return restJson(firestoreDocumentUrl(projectId, uid), {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${idToken}`,
    },
  });
}

async function deleteUserDocument({ projectId, uid, idToken }) {
  return restJson(firestoreDocumentUrl(projectId, uid), {
    method: 'DELETE',
    headers: {
      Authorization: `Bearer ${idToken}`,
    },
  });
}

async function callCallable({ projectId, region, callableName, idToken, data }) {
  return restJson(`https://${region}-${projectId}.cloudfunctions.net/${callableName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
}

function firestoreValueToPlain(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if ('nullValue' in value) {
    return null;
  }
  if ('stringValue' in value) {
    return value.stringValue;
  }
  if ('booleanValue' in value) {
    return value.booleanValue;
  }
  if ('integerValue' in value) {
    return Number(value.integerValue);
  }
  if ('doubleValue' in value) {
    return Number(value.doubleValue);
  }
  if ('timestampValue' in value) {
    return value.timestampValue;
  }
  if ('arrayValue' in value) {
    const values = Array.isArray(value.arrayValue?.values) ? value.arrayValue.values : [];
    return values.map((entry) => firestoreValueToPlain(entry));
  }
  if ('mapValue' in value) {
    const fields = value.mapValue?.fields || {};
    return Object.fromEntries(
      Object.entries(fields).map(([key, entry]) => [key, firestoreValueToPlain(entry)]),
    );
  }
  return value;
}

function firestoreDocumentToPlain(document) {
  const fields = document?.fields || {};
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, firestoreValueToPlain(value)]),
  );
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

async function retry(operation, { attempts = 6, delayMs = 1500, shouldRetry } = {}) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation(attempt);
    } catch (error) {
      lastError = error;
      if (attempt >= attempts || (typeof shouldRetry === 'function' && !shouldRetry(error))) {
        throw error;
      }
      await sleep(delayMs);
    }
  }
  throw lastError;
}

async function retryLookupVerifiedAccount({ apiKey, email, password }) {
  return retry(
    async () => {
      const signIn = await signInWithPassword({ apiKey, email, password });
      const lookup = await lookupAccount({ apiKey, idToken: signIn.idToken });
      assert(lookup?.emailVerified === true, 'emailVerified is still false in Firebase Auth.');
      return { signIn, lookup };
    },
    {
      attempts: 8,
      delayMs: 2000,
      shouldRetry: () => true,
    },
  );
}

async function retryVerifiedFirestoreSync({
  projectId,
  uid,
  idToken,
}) {
  return retry(
    async () => {
      const document = await getUserDocument({ projectId, uid, idToken });
      const userDoc = firestoreDocumentToPlain(document);
      assert(userDoc.emailVerified === true, 'Firestore user doc emailVerified is still false.');
      assert(userDoc.estActif === true, 'Firestore user doc estActif is still false.');
      assert(userDoc.emailVerifiedAt, 'Firestore user doc emailVerifiedAt is still missing.');
      return userDoc;
    },
    {
      attempts: 8,
      delayMs: 2000,
      shouldRetry: () => true,
    },
  );
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  const runId = nowTag();
  const configPath = resolveMobileConfigPath(args.environment, args.configPath);
  const mobileConfig = readJson(configPath);

  const apiKey =
    String(
      mobileConfig.FIREBASE_ANDROID_API_KEY ||
      mobileConfig.FIREBASE_WEB_API_KEY ||
      mobileConfig.FIREBASE_IOS_API_KEY ||
      '',
    ).trim();
  const projectId = String(mobileConfig.FIREBASE_PROJECT_ID || '').trim();
  const androidPackageName = packageNameForEnvironment(args.environment);
  const iOSBundleId =
    String(mobileConfig.FIREBASE_IOS_BUNDLE_ID || packageNameForEnvironment(args.environment)).trim();
  const emailLinkHost =
    String(args.emailLinkHost || '').trim().toLowerCase() ||
    defaultEmailLinkHostForProject(mobileConfig, projectId);
  const continueUrl = actionUrlForHost(emailLinkHost, '/verify');
  const serviceAccountInfo = readServiceAccount(
    resolveServiceAccountPath(args.serviceAccount, projectId),
    projectId,
  );

  if (!apiKey) {
    throw new Error(`Missing Firebase API key in ${path.resolve(configPath)}`);
  }
  if (!projectId) {
    throw new Error(`Missing FIREBASE_PROJECT_ID in ${path.resolve(configPath)}`);
  }

  if (!getApps().length) {
    initializeApp({
      credential: cert(serviceAccountInfo.parsed),
      projectId,
    });
  }

  const adminAuth = getAuth();

  const email = `smoke.public.${args.role}.${runId}.${randomSuffix()}@example.com`;
  const password = buildEphemeralPassword(args.role, runId);
  const nom = `Smoke ${args.role}`;
  const phone = '66443300';
  const report = {
    runId,
    environment: args.environment,
    projectId,
    region: args.region,
    configPath: path.resolve(configPath),
    role: args.role,
    email,
    serviceAccountPath: serviceAccountInfo.resolved,
    cleanup: {
      firestoreUserDeleted: false,
      authUserDeleted: false,
    },
    steps: [],
  };

  const addStep = (name, ok, details = {}) => {
    report.steps.push({
      timestamp: new Date().toISOString(),
      name,
      ok,
      details,
    });
  };

  let currentIdToken = null;
  let currentUid = null;

  try {
    const signUp = await signUpWithPassword({ apiKey, email, password });
    currentUid = signUp.localId;
    currentIdToken = signUp.idToken;
    assert(currentUid, 'Firebase signUp did not return a uid.');
    addStep('signup_auth_account', true, { uid: currentUid });

    const updatedProfile = await updateAccountProfile({
      apiKey,
      idToken: currentIdToken,
      displayName: nom,
    });
    currentIdToken = updatedProfile.idToken || currentIdToken;
    addStep('signup_update_display_name', true, { displayName: nom });

    const now = new Date();
    await createUserDocument({
      projectId,
      uid: currentUid,
      idToken: currentIdToken,
      fields: buildPublicSignupFirestoreFields({
        uid: currentUid,
        nom,
        email,
        role: args.role,
        phone,
        now,
      }),
    });
    addStep('signup_firestore_user_doc', true, { uid: currentUid, role: args.role });

    const beforeVerifyLookup = await lookupAccount({
      apiKey,
      idToken: currentIdToken,
    });
    const beforeVerifyDoc = firestoreDocumentToPlain(
      await getUserDocument({ projectId, uid: currentUid, idToken: currentIdToken }),
    );
    const beforeVerifyDecision = evaluateMobileDestination({
      emailVerified: beforeVerifyLookup?.emailVerified === true,
      userDoc: beforeVerifyDoc,
    });
    assert(beforeVerifyDecision.destination === 'verifyEmail', 'Expected verifyEmail before email verification.');
    assert(beforeVerifyDoc.emailVerified === false, 'Firestore user doc should start with emailVerified=false.');
    assert(beforeVerifyDoc.estActif === false, 'Firestore user doc should start with estActif=false.');
    addStep('pre_verification_state', true, {
      authEmailVerified: beforeVerifyLookup?.emailVerified === true,
      firestoreEmailVerified: beforeVerifyDoc.emailVerified,
      firestoreEstActif: beforeVerifyDoc.estActif,
      destination: beforeVerifyDecision.destination,
    });

    const emailVerificationResponse = await sendEmailVerificationOob({
      adminAuth,
      email,
      continueUrl,
      androidPackageName,
      iOSBundleId,
    });
    const oobLink =
      emailVerificationResponse.oobLink ||
      emailVerificationResponse.emailVerificationLink ||
      null;
    assert(oobLink, 'Email verification response did not return an oob link.');
    const actionParams = extractActionParams(oobLink);
    const oobCode = actionParams.oobCode || null;
    assert(oobCode, 'Unable to extract oobCode from the email verification link.');
    addStep('send_email_verification', true, {
      emailLinkHost,
      continueUrl,
      androidPackageName,
      iOSBundleId,
      mode: actionParams.mode || null,
    });

    await applyActionCode({ apiKey, oobCode });
    addStep('apply_action_code', true, { oobCodeLength: oobCode.length });

    const verifiedAccount = await retryLookupVerifiedAccount({
      apiKey,
      email,
      password,
    });
    currentIdToken = verifiedAccount.signIn.idToken;
    addStep('post_verification_auth_state', true, {
      authEmailVerified: verifiedAccount.lookup?.emailVerified === true,
    });

    const callableResponse = await retry(
      async () => {
        const response = await callCallable({
          projectId,
          region: args.region,
          callableName: 'completeEmailVerification',
          idToken: currentIdToken,
          data: { updateLastLogin: true },
        });
        const result = Object.prototype.hasOwnProperty.call(response, 'result') ?
          response.result :
          response;
        if (result?.error) {
          throw new Error(String(result.error.message || result.error.status || 'completeEmailVerification failed'));
        }
        return result;
      },
      {
        attempts: 6,
        delayMs: 2000,
        shouldRetry: () => true,
      },
    );
    addStep('call_complete_email_verification', true, callableResponse?.data || callableResponse || {});

    const syncedUserDoc = await retryVerifiedFirestoreSync({
      projectId,
      uid: currentUid,
      idToken: currentIdToken,
    });
    addStep('post_verification_firestore_sync', true, {
      emailVerified: syncedUserDoc.emailVerified,
      estActif: syncedUserDoc.estActif,
      emailVerifiedAt: syncedUserDoc.emailVerifiedAt,
    });

    const loginAfterVerify = await signInWithPassword({
      apiKey,
      email,
      password,
    });
    currentIdToken = loginAfterVerify.idToken;
    const lookupAfterLogin = await lookupAccount({
      apiKey,
      idToken: currentIdToken,
    });
    const loginUserDoc = firestoreDocumentToPlain(
      await getUserDocument({ projectId, uid: currentUid, idToken: currentIdToken }),
    );
    const afterVerifyDecision = evaluateMobileDestination({
      emailVerified: lookupAfterLogin?.emailVerified === true,
      userDoc: loginUserDoc,
    });
    assert(afterVerifyDecision.destination === 'main', 'Expected main after email verification and sync.');
    addStep('login_after_verification', true, {
      authEmailVerified: lookupAfterLogin?.emailVerified === true,
      firestoreEmailVerified: loginUserDoc.emailVerified,
      firestoreEstActif: loginUserDoc.estActif,
      destination: afterVerifyDecision.destination,
    });

    const reportPath = path.resolve('docs', `smoke-public-signup-${runId}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');

    process.stdout.write(`Public signup smoke completed successfully.\n`);
    process.stdout.write(`Report: ${reportPath}\n`);
    process.stdout.write(`${JSON.stringify({
      environment: args.environment,
      projectId,
      email,
      uid: currentUid,
      cleanupPlanned: args.cleanup,
    }, null, 2)}\n`);
  } catch (error) {
    const reportPath = path.resolve('docs', `smoke-public-signup-${runId}-failed.json`);
    const failure = {
      ...report,
      failedAt: new Date().toISOString(),
      error: {
        message: String(error?.message || error),
        details: error?.details || null,
      },
    };
    fs.writeFileSync(reportPath, `${JSON.stringify(failure, null, 2)}\n`, 'utf8');
    process.stderr.write(`Public signup smoke failed. Report: ${reportPath}\n`);
    process.stderr.write(`${failure.error.message}\n`);
    process.exitCode = 1;
  } finally {
    if (args.cleanup && currentUid && currentIdToken) {
      try {
        await deleteUserDocument({
          projectId,
          uid: currentUid,
          idToken: currentIdToken,
        });
        report.cleanup.firestoreUserDeleted = true;
      } catch (_) {}

      try {
        await deleteAccount({
          apiKey,
          idToken: currentIdToken,
        });
        report.cleanup.authUserDeleted = true;
      } catch (_) {}
    }
  }
}

run().catch((error) => {
  process.stderr.write(`${String(error?.message || error)}\n`);
  process.exitCode = 1;
});
