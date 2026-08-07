#!/usr/bin/env node

// Verifies that every user who looks like an admin in Firestore (role
// "admin", or a legacy admin/platformAdmin/superAdmin boolean field) also
// carries the matching Firebase Auth custom claim. Run this against staging
// then production BEFORE relying on assertAdminCaller()/isAdminOperator()
// requiring the claim alone (see functions/src/admin_account_support.ts and
// firestore.rules) — it's the safety net for that tightening, not a
// replacement for it. Exits non-zero if any gap is found.
//
// Usage:
//   node scripts/audit_admin_claims.mjs --service-account /path/to/sa.json

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

import {cert, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

const ADMIN_CLAIM_KEYS = ["admin", "platformAdmin", "superAdmin"];

const HELP_TEXT = `Usage:
  node scripts/audit_admin_claims.mjs --service-account /path/to/sa.json

Options:
  --service-account <path>   Chemin absolu vers un JSON service account
  --help                     Affiche cette aide

Env supportes:
  FIREBASE_SERVICE_ACCOUNT_KEY_PATH
  GOOGLE_APPLICATION_CREDENTIALS
`;

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    if (!current.startsWith("--")) {
      throw new Error(`Argument inattendu: ${current}`);
    }
    const key = current.slice(2);
    if (key === "help") {
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

function resolveServiceAccountPath(options) {
  const candidate =
    options["service-account"] ||
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY_PATH ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS;

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

  const parsed = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));

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

function hasPrivilegedClaim(customClaims) {
  if (!customClaims || typeof customClaims !== "object") return false;
  return ADMIN_CLAIM_KEYS.some((key) => customClaims[key] === true);
}

async function collectFirestoreAdminSignals(db) {
  const candidates = new Map();

  const addDocs = (snapshot, reason) => {
    for (const doc of snapshot.docs) {
      const existing = candidates.get(doc.id) ?? new Set();
      existing.add(reason);
      candidates.set(doc.id, existing);
    }
  };

  const usersRef = db.collection("users");
  addDocs(await usersRef.where("role", "==", "admin").get(), "role == \"admin\"");
  addDocs(await usersRef.where("admin", "==", true).get(), "admin == true");
  addDocs(
    await usersRef.where("platformAdmin", "==", true).get(),
    "platformAdmin == true",
  );
  addDocs(
    await usersRef.where("superAdmin", "==", true).get(),
    "superAdmin == true",
  );

  return candidates;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    process.stdout.write(`${HELP_TEXT}\n`);
    return;
  }

  const serviceAccountPath = resolveServiceAccountPath(options);
  const serviceAccount = loadServiceAccount(serviceAccountPath);

  if (!getApps().length) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id,
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  const candidates = await collectFirestoreAdminSignals(db);

  process.stdout.write(
    `Audit ${serviceAccount.project_id}: ${candidates.size} compte(s) avec un signal d'administration Firestore.\n`,
  );

  const gaps = [];
  const orphans = [];

  for (const [uid, reasons] of candidates) {
    let userRecord;
    try {
      userRecord = await auth.getUser(uid);
    } catch (error) {
      const code =
        error && typeof error === "object" && "code" in error ? error.code : "";
      if (code === "auth/user-not-found") {
        orphans.push({uid, reasons: [...reasons]});
        continue;
      }
      throw error;
    }

    if (!hasPrivilegedClaim(userRecord.customClaims)) {
      gaps.push({uid, email: userRecord.email ?? null, reasons: [...reasons]});
    }
  }

  if (orphans.length > 0) {
    process.stdout.write(
      `\n${orphans.length} document(s) Firestore avec signal admin mais sans utilisateur Auth associe :\n`,
    );
    for (const orphan of orphans) {
      process.stdout.write(`  - ${orphan.uid} (${orphan.reasons.join(", ")})\n`);
    }
  }

  if (gaps.length === 0) {
    process.stdout.write(
      "\nAucun ecart : tout signal d'administration Firestore a son custom claim correspondant.\n",
    );
    return;
  }

  process.stdout.write(
    `\n${gaps.length} compte(s) ont un signal d'administration Firestore SANS custom claim correspondant :\n`,
  );
  for (const gap of gaps) {
    process.stdout.write(
      `  - ${gap.uid}${gap.email ? ` (${gap.email})` : ""} : ${gap.reasons.join(", ")}\n`,
    );
  }
  process.stdout.write(
    "\nCes comptes perdront l'acces admin une fois assertAdminCaller()/isAdminOperator() resserres. " +
      "Pose le claim manquant (via scripts/create_admin_account.mjs --claim admin --role admin) avant de deployer.\n",
  );
  process.exitCode = 1;
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Erreur: ${message}\n`);
  process.exitCode = 1;
});
