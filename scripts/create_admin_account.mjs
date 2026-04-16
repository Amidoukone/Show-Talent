#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {randomBytes} from "node:crypto";

import {cert, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const ALLOWED_CLAIMS = new Set(["admin", "platformAdmin", "superAdmin"]);
const ALLOWED_ROLES = new Set(["admin"]);
const ADMIN_CLAIM_KEYS = ["admin", "platformAdmin", "superAdmin"];

const HELP_TEXT = `Usage:
  npm.cmd run create-admin -- --email admin@example.com --password "TempPass123!" --name "Admin Principal" --claim admin

Options:
  --email <value>            E-mail du compte admin
  --password <value>         Mot de passe initial. Si omis, un mot de passe temporaire est genere
  --name <value>             Nom complet affiche dans Firebase Auth et Firestore
  --claim <value>            admin | platformAdmin | superAdmin (defaut: admin)
  --role <value>             Role Firestore (defaut: admin)
  --phone <value>            Telephone optionnel
  --service-account <path>   Chemin absolu vers un JSON service account
  --update-password          Met a jour aussi le mot de passe si le compte existe deja
  --help                     Affiche cette aide

Env supportes:
  FIREBASE_SERVICE_ACCOUNT_KEY_PATH
  GOOGLE_APPLICATION_CREDENTIALS

Important:
  google-services.json n'est pas un service account valide pour Firebase Admin SDK.
`;

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];

    if (!current.startsWith("--")) {
      throw new Error(`Argument inattendu: ${current}`);
    }

    const key = current.slice(2);
    if (key === "help" || key === "update-password") {
      options[key] = true;
      continue;
    }

    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      throw new Error(`La valeur de --${key} est manquante.`);
    }

    options[key] = next;
    index += 1;
  }

  return options;
}

function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

function resolveServiceAccountPath(options) {
  const explicitPath = options["service-account"];
  const envPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY_PATH ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const candidate = explicitPath || envPath;

  if (!candidate) {
    throw new Error(
      "Aucun service account fourni. Renseigne --service-account ou FIREBASE_SERVICE_ACCOUNT_KEY_PATH.",
    );
  }

  return path.resolve(candidate);
}

function loadServiceAccount(serviceAccountPath) {
  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(`Service account introuvable: ${serviceAccountPath}`);
  }

  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
  } catch (error) {
    throw new Error(
      `Impossible de lire le JSON service account: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  if (
    parsed &&
    typeof parsed === "object" &&
    "project_info" in parsed &&
    "client" in parsed
  ) {
    throw new Error(
      "Le fichier fourni ressemble a un google-services.json Android. Il faut un JSON de service_account Firebase Admin SDK.",
    );
  }

  if (
    !parsed ||
    typeof parsed !== "object" ||
    parsed.type !== "service_account" ||
    typeof parsed.project_id !== "string" ||
    typeof parsed.client_email !== "string" ||
    typeof parsed.private_key !== "string"
  ) {
    throw new Error(
      "Le fichier fourni n'est pas un service account valide. Champs attendus: type=service_account, project_id, client_email, private_key.",
    );
  }

  return parsed;
}

function requireNonEmpty(options, key, label) {
  const value = typeof options[key] === "string" ? options[key].trim() : "";
  if (!value) {
    throw new Error(`${label} est requis.`);
  }
  return value;
}

function buildTemporaryPassword() {
  return `${randomBytes(12).toString("base64url")}Aa1!`;
}

function sanitizeClaims(existingClaims, selectedClaim) {
  const nextClaims = {
    ...(existingClaims && typeof existingClaims === "object" ? existingClaims : {}),
  };

  for (const claim of ADMIN_CLAIM_KEYS) {
    delete nextClaims[claim];
  }

  nextClaims[selectedClaim] = true;
  return nextClaims;
}

function buildSummary(result) {
  return JSON.stringify(result, null, 2);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    process.stdout.write(`${HELP_TEXT}\n`);
    return;
  }

  const email = normalizeEmail(requireNonEmpty(options, "email", "L email"));
  const displayName = requireNonEmpty(options, "name", "Le nom");
  const claim = (options.claim || "admin").trim();
  const role = (options.role || "admin").trim().toLowerCase();
  const phone =
    typeof options.phone === "string" && options.phone.trim() ?
      options.phone.trim() :
      null;
  const serviceAccountPath = resolveServiceAccountPath(options);
  const serviceAccount = loadServiceAccount(serviceAccountPath);
  const generatedPassword =
    typeof options.password === "string" && options.password.trim() ?
      null :
      buildTemporaryPassword();
  const password = options.password?.trim() || generatedPassword;

  if (!ALLOWED_CLAIMS.has(claim)) {
    throw new Error(
      `Claim invalide: ${claim}. Valeurs acceptees: ${[...ALLOWED_CLAIMS].join(", ")}.`,
    );
  }

  if (!ALLOWED_ROLES.has(role)) {
    throw new Error(
      `Role invalide: ${role}. Valeurs acceptees: ${[...ALLOWED_ROLES].join(", ")}.`,
    );
  }

  if (!getApps().length) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id,
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  let existingUser = false;
  let passwordUpdated = false;
  let userRecord;

  try {
    userRecord = await auth.getUserByEmail(email);
    existingUser = true;
  } catch (error) {
    const code =
      error && typeof error === "object" && "code" in error ?
        error.code :
        "";

    if (code !== "auth/user-not-found") {
      throw error;
    }
  }

  if (!userRecord) {
    userRecord = await auth.createUser({
      email,
      password,
      displayName,
      disabled: false,
      phoneNumber: phone || undefined,
    });
  } else {
    const updates = {
      displayName,
      disabled: false,
    };

    if (phone && userRecord.phoneNumber !== phone) {
      updates.phoneNumber = phone;
    }

    if (options["update-password"] === true) {
      updates.password = password;
      passwordUpdated = true;
    }

    userRecord = await auth.updateUser(userRecord.uid, updates);
  }

  const nextClaims = sanitizeClaims(userRecord.customClaims, claim);
  await auth.setCustomUserClaims(userRecord.uid, nextClaims);
  userRecord = await auth.getUser(userRecord.uid);

  const userRef = db.collection("users").doc(userRecord.uid);
  const existingDoc = await userRef.get();
  const existingData = existingDoc.data() ?? {};

  await userRef.set({
    uid: userRecord.uid,
    nom: displayName,
    email,
    phone: phone || existingData.phone || null,
    role,
    photoProfil: existingData.photoProfil ?? "",
    estActif: userRecord.emailVerified && userRecord.disabled !== true,
    authDisabled: userRecord.disabled === true,
    emailVerified: userRecord.emailVerified,
    emailVerifiedAt:
      userRecord.emailVerified ?
        existingData.emailVerifiedAt ?? FieldValue.serverTimestamp() :
        null,
    dateInscription:
      existingData.dateInscription ?? FieldValue.serverTimestamp(),
    dernierLogin: existingData.dernierLogin ?? FieldValue.serverTimestamp(),
    followers: existingData.followers ?? 0,
    followings: existingData.followings ?? 0,
    followersList: existingData.followersList ?? [],
    followingsList: existingData.followingsList ?? [],
    profilePublic: false,
    allowMessages: false,
    createdByAdmin: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  const summary = {
    projectId: serviceAccount.project_id,
    uid: userRecord.uid,
    email,
    name: displayName,
    role,
    claim,
    existingUser,
    passwordUpdated,
    temporaryPasswordGenerated: generatedPassword !== null,
    passwordToUse: generatedPassword || (existingUser ? null : password),
    emailVerified: userRecord.emailVerified,
    authDisabled: userRecord.disabled === true,
    firestoreUserPath: `users/${userRecord.uid}`,
  };

  process.stdout.write(`${buildSummary(summary)}\n`);

  if (!userRecord.emailVerified) {
    process.stdout.write(
      "Le compte admin a ete cree ou mis a jour, mais l email n est pas encore verifie.\n",
    );
  }

  if (existingUser && options["update-password"] !== true) {
    process.stdout.write(
      "Le compte existait deja: le mot de passe n a pas ete modifie. Ajoute --update-password pour le remplacer.\n",
    );
  }
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Erreur: ${message}\n`);
  process.exitCode = 1;
});
