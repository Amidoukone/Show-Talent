/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import * as logger from "firebase-functions/logger";

import {db, fieldValue} from "./firebase";

/**
 * FCM error code meaning "this token no longer belongs to an install".
 *
 * FCM rotates and revokes registration tokens on its own: an app uninstall, a
 * "clear data", a restore onto a new phone, or a long period of inactivity all
 * invalidate the token we stored. Nothing tells us — the token simply starts
 * failing, forever, on every send.
 *
 * Only this one code is treated as proof that the token is dead.
 * `messaging/invalid-argument` deliberately is not: the Admin SDK also raises
 * it for a malformed *payload*, so pruning on it would delete a perfectly
 * valid token the first time we shipped a bad notification body — a silent,
 * permanent loss of reachability caused by a bug elsewhere.
 */
const UNREGISTERED_TOKEN_ERROR_CODE = "messaging/registration-token-not-registered";

/**
 * True when FCM rejected the send because the token itself is dead.
 *
 * @param {unknown} error Error thrown by `send` or reported per-recipient by
 *   `sendEachForMulticast`.
 * @return {boolean} Whether the token should be considered unregistered.
 */
export function isUnregisteredTokenError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  const code = (error as {code?: unknown}).code;
  return code === UNREGISTERED_TOKEN_ERROR_CODE;
}

/**
 * Drops a dead token from `users/{uid}`, but only if it is still the one we
 * just failed to send to.
 *
 * The compare-and-clear matters. A send is not instantaneous, and the client
 * persists a new token as soon as FirebaseMessaging hands one over (see
 * NotificationService.listenTokenRefresh). A blind delete could therefore wipe
 * the *replacement* token that arrived while the failing send was in flight,
 * turning a self-healing cleanup into the very outage it exists to prevent.
 *
 * @param {object} params Owner uid, the token that failed, and a short reason
 *   recorded in the logs.
 * @return {Promise<boolean>} True when a token was actually cleared.
 */
export async function pruneUnregisteredToken(params: {
  uid: string;
  token: string;
  reason: string;
}): Promise<boolean> {
  const uid = params.uid.trim();
  const token = params.token.trim();
  if (!uid || !token) {
    return false;
  }

  const userRef = db.collection("users").doc(uid);

  try {
    return await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(userRef);
      if (!snap.exists) {
        return false;
      }

      const stored = snap.data()?.fcmToken;
      if (typeof stored !== "string" || stored.trim() !== token) {
        return false;
      }

      transaction.set(
        userRef,
        {
          fcmToken: fieldValue.delete(),
          fcmTokenUpdatedAt: fieldValue.delete(),
          fcmTokenPrunedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return true;
    });
  } catch (error) {
    // Cleanup is opportunistic: the notification outcome must never depend on
    // it, and the next failed send will simply try again.
    logger.warn("fcm token prune failed", {uid, reason: params.reason, error});
    return false;
  }
}

/**
 * Convenience wrapper: inspect a failed send and prune when the token is dead.
 *
 * @param {object} params The send error, the owner uid, the token used, and a
 *   short reason recorded in the logs.
 * @return {Promise<boolean>} True when the failure was a dead token (whether
 *   or not the document still carried it), so callers can distinguish
 *   "unreachable device" from a genuine delivery error worth alerting on.
 */
export async function handlePushSendError(params: {
  error: unknown;
  uid: string;
  token: string;
  reason: string;
}): Promise<boolean> {
  if (!isUnregisteredTokenError(params.error)) {
    return false;
  }

  const pruned = await pruneUnregisteredToken({
    uid: params.uid,
    token: params.token,
    reason: params.reason,
  });

  logger.info("fcm token unregistered", {
    uid: params.uid,
    reason: params.reason,
    pruned,
  });

  return true;
}
