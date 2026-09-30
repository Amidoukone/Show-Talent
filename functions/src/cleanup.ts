/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {FieldPath} from "firebase-admin/firestore";

import {auth, db, fieldValue} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
import {pushTokenRef} from "./push_delivery";
import {syncPublicProfile} from "./public_profile_projection";
const DEFAULT_RETENTION_DAYS = 3;
const MANAGED_ROLES = new Set(["admin", "club", "recruteur", "agent"]);

/**
 * Migrates one user's legacy array into relation documents.
 * @param {string} uid Source user ID.
 * @param {unknown} rawFollowings Legacy following IDs.
 * @return {Promise<number>} Number of migrated edges.
 */
async function migrateLegacyFollowEdges(
  uid: string,
  rawFollowings: unknown,
): Promise<number> {
  const followingIds = Array.isArray(rawFollowings) ?
    [...new Set(rawFollowings
      .map((value) => String(value ?? "").trim())
      .filter((value) => value && value !== uid))] : [];
  if (followingIds.length === 0) return 0;

  const writer = db.bulkWriter();
  writer.onWriteError((error) => {
    if (error.code === 6) return false;
    return error.failedAttempts < 3;
  });
  const writes: Promise<unknown>[] = [];
  for (const targetUid of followingIds) {
    const relation = {
      followerUid: uid,
      followingUid: targetUid,
      active: true,
      migratedAt: fieldValue.serverTimestamp(),
    };
    for (const ref of [
      db.collection("users").doc(uid).collection("following").doc(targetUid),
      db.collection("users").doc(targetUid).collection("followers").doc(uid),
    ]) {
      writes.push(writer.create(ref, relation).catch((error: {code?: unknown}) => {
        if (error.code !== 6 && error.code !== "already-exists") throw error;
      }));
    }
  }
  await writer.close();
  await Promise.all(writes);
  return followingIds.length;
}

/**
 * Convert an app-owned Firebase download URL to its authenticated gs:// path.
 * @param {string} raw Candidate legacy download URL.
 * @param {string} uid Expected CV owner.
 * @return {string|null} Safe Storage path, or null for an unknown URL.
 */
function legacyCvStorageUrl(raw: string, uid: string): string | null {
  try {
    const parsed = new URL(raw);
    const parts = parsed.pathname.split("/");
    if (parsed.protocol !== "https:" ||
        parsed.hostname !== "firebasestorage.googleapis.com" ||
        parts[1] !== "v0" || parts[2] !== "b" ||
        parts[4] !== "o" || !parts[3] || !parts[5]) return null;
    const path = decodeURIComponent(parts.slice(5).join("/"));
    const prefix = `cvs/${uid}/`;
    if (!path.startsWith(prefix) ||
        !/^cv_[0-9]+[.]pdf$/.test(path.slice(prefix.length))) return null;
    return `gs://${parts[3]}/${path}`;
  } catch {
    return null;
  }
}

// Legacy CV URLs include long-lived download tokens on readable profiles.
// Convert known app-owned URLs to Storage paths; retain unusual values only
// in the owner's private contact document for manual review.
export const migrateLegacyCvUrls = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 5 minutes",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    // Old installed clients open cvUrl directly in a browser. Converting it
    // before they have upgraded would silently break their CV button. Enable
    // this migration only at the final access-tightening phase.
    if (process.env.ENABLE_LEGACY_CV_URL_MIGRATION !== "true") return;
    const users = await db.collection("users")
      .where("cvUrl", ">=", "http")
      .where("cvUrl", "<", "http\uf8ff")
      .limit(100)
      .get();
    let converted = 0;
    let heldForReview = 0;
    for (const user of users.docs) {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(user.ref);
        const raw = current.data()?.cvUrl;
        if (typeof raw !== "string" || !raw.startsWith("http")) return;
        const storageUrl = legacyCvStorageUrl(raw, user.id);
        if (storageUrl) {
          tx.update(user.ref, {cvUrl: storageUrl});
          converted++;
        } else {
          tx.set(user.ref.collection("private").doc("contact"), {
            legacyCvUrl: raw,
            legacyCvReviewAt: fieldValue.serverTimestamp(),
          }, {merge: true});
          tx.update(user.ref, {cvUrl: fieldValue.delete()});
          heldForReview++;
        }
      });
    }
    if (converted || heldForReview) {
      logger.info("legacy CV URLs removed from readable profiles", {
        converted,
        heldForReview,
      });
    }
  },
);

// Drain legacy tokens from publicly readable user documents after the new
// private-token backend has been deployed. Each run is bounded and resumable.
export const migrateLegacyFcmTokens = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 5 minutes",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const legacyUsers = await db.collection("users")
      .where("fcmToken", ">", "")
      .limit(100)
      .get();
    let migrated = 0;
    for (const user of legacyUsers.docs) {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(user.ref);
        const tokenRef = pushTokenRef(user.id);
        const privateToken = await tx.get(tokenRef);
        const legacy = current.data()?.fcmToken;
        if (typeof legacy !== "string" || !legacy.trim()) return;
        if (!privateToken.exists) {
          tx.set(tokenRef, {
            token: legacy.trim(),
            updatedAt: fieldValue.serverTimestamp(),
          });
        }
        tx.update(user.ref, {
          fcmToken: fieldValue.delete(),
          fcmTokenUpdatedAt: fieldValue.delete(),
        });
        migrated++;
      });
    }
    if (migrated > 0) logger.info("legacy FCM tokens migrated", {migrated});
  },
);

// An account whose data was purged but whose Auth deletion failed needs its
// own retry queue. The unverified-account cleanup below skips verified users.
export const retryPendingAccountDeletions = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const pending = await db.collection("account_deletion_pending")
      .orderBy("lastErrorAt")
      .limit(100)
      .get();
    for (const marker of pending.docs) {
      try {
        await auth.deleteUser(marker.id);
        await marker.ref.delete();
        logger.info("pending account Auth deletion completed", {uid: marker.id});
      } catch (error) {
        if (isAuthUserNotFound(error)) {
          await marker.ref.delete();
          continue;
        }
        await marker.ref.update({
          lastErrorAt: fieldValue.serverTimestamp(),
          attemptCount: fieldValue.increment(1),
        });
        logger.error("pending account Auth deletion retry failed", {
          uid: marker.id,
          error,
        });
      }
    }
  },
);

// Existing users predate public_profiles and relation-based follows. The
// cursor makes both migrations bounded and resumable. BulkWriter.create keeps
// an unfollow tombstone written during migration from being overwritten.
export const backfillPublicProfiles = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const cleanupLegacyArrays =
      process.env.ENABLE_LEGACY_FOLLOW_FIELD_CLEANUP === "true";
    const stateRef = db.collection("migration_state")
      // v3 reindexes search prefixes even when the v2 projection/follow
      // migration already completed on a deployed environment.
      .doc(cleanupLegacyArrays ?
        "public_profiles_follow_cleanup_v1" :
        "public_profiles_and_follows_v3");
    const state = await stateRef.get();
    if (state.data()?.completed === true) return;

    let query = db.collection("users")
      .orderBy(FieldPath.documentId())
      .limit(200);
    const cursor = state.data()?.cursor;
    if (typeof cursor === "string" && cursor) {
      query = query.startAfter(cursor);
    }
    const users = await query.get();
    let migratedEdges = 0;
    for (const user of users.docs) {
      await syncPublicProfile(user.id);
      migratedEdges += await migrateLegacyFollowEdges(
        user.id,
        user.data().followingsList,
      );
      if (cleanupLegacyArrays) {
        await user.ref.update({
          followersList: fieldValue.delete(),
          followingsList: fieldValue.delete(),
        });
      }
    }

    if (users.empty || users.size < 200) {
      await stateRef.set({
        completed: true,
        completedAt: fieldValue.serverTimestamp(),
      });
      logger.info("public profile and follow backfill completed", {
        processed: users.size,
        migratedEdges,
      });
      return;
    }
    await stateRef.set({
      cursor: users.docs[users.docs.length - 1].id,
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});
  },
);

// Firestore orderBy excludes documents without the ordered field. Older
// conversations can therefore disappear from the paged inbox until repaired.
export const backfillConversationSortDates = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const stateRef = db.collection("migration_state")
      .doc("conversation_sort_dates_v1");
    const state = await stateRef.get();
    if (state.data()?.completed === true) return;
    let query = db.collection("conversations")
      .orderBy(FieldPath.documentId()).limit(100);
    const cursor = state.data()?.cursor;
    if (typeof cursor === "string" && cursor) query = query.startAfter(cursor);
    const conversations = await query.get();
    for (const conversation of conversations.docs) {
      if (Object.prototype.hasOwnProperty.call(
        conversation.data(), "lastMessageDate",
      )) continue;
      const newest = await conversation.ref.collection("messages")
        .orderBy("dateEnvoi", "desc").limit(1).get();
      const newestDate = newest.docs[0]?.data()?.dateEnvoi;
      await conversation.ref.update({
        lastMessageDate: newestDate ?? conversation.data().createdAt ?? null,
      });
    }
    if (conversations.size < 100) {
      await stateRef.set({completed: true, completedAt: fieldValue.serverTimestamp()});
    } else {
      await stateRef.set({
        cursor: conversations.docs[conversations.docs.length - 1].id,
        updatedAt: fieldValue.serverTimestamp(),
      }, {merge: true});
    }
  },
);

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
 * Supprime les utilisateurs non vérifiés après 3 jours (Auth + Firestore).
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

// Generous vs. the ~45min upload session TTL: the client can now retry a
// session refresh up to twice on a slow connection (see
// UploadClient._maxSessionRefreshes in the Flutter app), so a legitimately
// still-uploading video can stay in "processing" for a couple of hours.
const ABANDONED_UPLOAD_TIMEOUT_MS = 3 * 60 * 60 * 1000;

/**
 * Reaps videos/{id} docs stuck at status:"processing" long past any
 * realistic upload session lifetime -- the app being killed/backgrounded
 * mid-upload, or a client crash, leaves createUploadSession's doc behind
 * forever with nothing else to ever move it out of "processing".
 * assertUploadRateLimits counts these toward MAX_CONCURRENT_VIDEO_UPLOADS
 * and MAX_PENDING_VIDEO_REVIEWS, so a couple of abandoned attempts
 * permanently locks that user out of uploading with no self-service
 * recovery. Marks them status:"error" (excluded from both limits) instead
 * of deleting, matching optimizeMp4Video's existing failure convention --
 * no Storage cleanup needed since an abandoned resumable upload never
 * commits a final object in the bucket.
 * Runs hourly since MAX_CONCURRENT_VIDEO_UPLOADS is a tight cap (2).
 */
export const reapAbandonedUploadSessions = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 60 minutes",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const cutoffDate = new Date(Date.now() - ABANDONED_UPLOAD_TIMEOUT_MS);

    let scanned = 0;
    let reaped = 0;
    let errors = 0;

    try {
      const stale = await db.collection("videos")
        .where("status", "==", "processing")
        .where("updatedAt", "<=", cutoffDate)
        .get();

      scanned = stale.docs.length;

      for (const doc of stale.docs) {
        try {
          await doc.ref.set({
            status: "error",
            optimized: false,
            optimizationError: "abandoned_upload_timeout",
            updatedAt: fieldValue.serverTimestamp(),
          }, {merge: true});
          reaped += 1;
        } catch (error) {
          errors += 1;
          logger.error("Abandoned upload session reap failed", {
            videoId: doc.id,
            error,
          });
        }
      }

      logger.info("Abandoned upload session reap completed", {
        scanned,
        reaped,
        errors,
        cutoffIso: cutoffDate.toISOString(),
      });
    } catch (err) {
      logger.error("Abandoned upload session reap failed", err);
      throw err;
    }
  }
);
