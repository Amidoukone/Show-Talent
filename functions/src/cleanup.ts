/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
const DEFAULT_RETENTION_DAYS = 3;
const MANAGED_ROLES = new Set(["admin", "club", "recruteur", "agent"]);

/**
 * Parse an integer env value with positive fallback.
 * @param {string|undefined} value Raw env value.
 * @param {number} fallback Fallback value.
 * @return {number}
 */
function parsePositiveInt(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.floor(parsed);
}

/**
 * Parse a boolean env flag with fallback when value is missing/invalid.
 * @param {string|undefined} value Raw env value.
 * @param {boolean} fallback Fallback value.
 * @return {boolean}
 */
function parseBoolean(value: string | undefined, fallback: boolean): boolean {
  if (!value) {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  return fallback;
}

/**
 * Detect whether a Firestore user doc belongs to managed/admin accounts.
 * @param {FirebaseFirestore.DocumentData|undefined} data Firestore user doc.
 * @return {boolean}
 */
function asManagedAccount(data: FirebaseFirestore.DocumentData | undefined): boolean {
  if (!data) {
    return false;
  }
  if (data["createdByAdmin"] === true) {
    return true;
  }
  const role = typeof data["role"] === "string" ?
    data["role"].trim().toLowerCase() :
    "";
  return MANAGED_ROLES.has(role);
}

/**
 * Detect Firebase Auth "user not found" errors in a safe way.
 * @param {unknown} error Caught error.
 * @return {boolean}
 */
function isAuthUserNotFound(error: unknown): boolean {
  const code = typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof (error as {code?: unknown}).code === "string" ?
    (error as {code: string}).code :
    "";
  return code === "auth/user-not-found";
}

type CleanupStats = {
  authScanned: number;
  authDeleted: number;
  authMissing: number;
  firestoreDeleted: number;
  orphanFirestoreDeleted: number;
  skippedRecent: number;
  skippedVerifiedInAuth: number;
  skippedManaged: number;
  syncedVerifiedInFirestore: number;
  errors: number;
};

/**
 * Supprime les utilisateurs non verifies apres 3 jours (Auth + Firestore).
 * Les comptes geres par admin sont exclus par defaut.
 * Exécution quotidienne.
 */
export const cleanupUnverifiedUsers = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 24 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const retentionDays = parsePositiveInt(
      process.env.UNVERIFIED_ACCOUNT_RETENTION_DAYS,
      DEFAULT_RETENTION_DAYS,
    );
    const excludeManaged = parseBoolean(
      process.env.UNVERIFIED_PURGE_EXCLUDE_MANAGED,
      true,
    );
    const cutoffMs = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
    const cutoffDate = new Date(cutoffMs);

    const stats: CleanupStats = {
      authScanned: 0,
      authDeleted: 0,
      authMissing: 0,
      firestoreDeleted: 0,
      orphanFirestoreDeleted: 0,
      skippedRecent: 0,
      skippedVerifiedInAuth: 0,
      skippedManaged: 0,
      syncedVerifiedInFirestore: 0,
      errors: 0,
    };
    const processedUids = new Set<string>();

    logger.info("Unverified cleanup started", {
      retentionDays,
      excludeManaged,
      cutoffIso: cutoffDate.toISOString(),
    });

    try {
      let nextPageToken: string | undefined;
      do {
        const page = await auth.listUsers(1000, nextPageToken);
        nextPageToken = page.pageToken;

        for (const user of page.users) {
          stats.authScanned += 1;

          if (user.emailVerified) {
            stats.skippedVerifiedInAuth += 1;
            continue;
          }

          const creationMs = Date.parse(user.metadata.creationTime || "");
          if (!Number.isFinite(creationMs) || creationMs > cutoffMs) {
            stats.skippedRecent += 1;
            continue;
          }

          const userRef = db.collection("users").doc(user.uid);
          const userSnap = await userRef.get();
          const userData = userSnap.data();

          if (excludeManaged && asManagedAccount(userData)) {
            stats.skippedManaged += 1;
            continue;
          }

          try {
            await auth.deleteUser(user.uid);
            stats.authDeleted += 1;
          } catch (error) {
            if (!isAuthUserNotFound(error)) {
              stats.errors += 1;
              logger.error("Auth deletion failed", {uid: user.uid, error});
              continue;
            }
            stats.authMissing += 1;
          }

          await userRef.delete();
          stats.firestoreDeleted += 1;
          processedUids.add(user.uid);
        }
      } while (nextPageToken);

      const firestoreCandidates = await db
        .collection("users")
        .where("emailVerified", "==", false)
        .where("dateInscription", "<=", cutoffDate)
        .get();

      for (const doc of firestoreCandidates.docs) {
        const uid = doc.id;
        if (processedUids.has(uid)) {
          continue;
        }

        const data = doc.data();
        if (excludeManaged && asManagedAccount(data)) {
          stats.skippedManaged += 1;
          continue;
        }

        try {
          const authUser = await auth.getUser(uid);
          if (authUser.emailVerified) {
            await doc.ref.set({
              emailVerified: true,
              emailVerifiedAt: fieldValue.serverTimestamp(),
              updatedAt: fieldValue.serverTimestamp(),
            }, {merge: true});
            stats.syncedVerifiedInFirestore += 1;
            continue;
          }

          const creationMs = Date.parse(authUser.metadata.creationTime || "");
          if (!Number.isFinite(creationMs) || creationMs > cutoffMs) {
            stats.skippedRecent += 1;
            continue;
          }

          await auth.deleteUser(uid);
          stats.authDeleted += 1;
          await doc.ref.delete();
          stats.firestoreDeleted += 1;
          processedUids.add(uid);
        } catch (error) {
          if (isAuthUserNotFound(error)) {
            await doc.ref.delete();
            stats.orphanFirestoreDeleted += 1;
            continue;
          }
          stats.errors += 1;
          logger.error("Firestore candidate cleanup failed", {uid, error});
        }
      }

      logger.info("Unverified cleanup completed", stats);
    } catch (err) {
      logger.error("Unverified cleanup failed", err);
      throw err;
    }
  }
);
