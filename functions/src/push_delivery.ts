/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import type {ApnsConfig} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

import {db, fieldValue} from "./firebase";

/**
 * Server-only token document; never part of a readable user profile.
 * @param {string} uid User ID.
 * @return {FirebaseFirestore.DocumentReference} Private token reference.
 */
export function pushTokenRef(uid: string) {
  return db.collection("user_push_tokens").doc(uid);
}

/**
 * Read the private token, with a short-lived legacy fallback for migration.
 * @param {string} uid User ID.
 * @return {Promise<string>} Registration token, if any.
 */
export async function getUserPushToken(uid: string): Promise<string> {
  const [privateSnap, userSnap] = await Promise.all([
    pushTokenRef(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);
  const privateToken = privateSnap.data()?.token;
  if (typeof privateToken === "string" && privateToken.trim()) {
    return privateToken.trim();
  }
  // Compatibility only while migrateLegacyFcmTokens clears old documents.
  const legacy = userSnap.data()?.fcmToken;
  return typeof legacy === "string" ? legacy.trim() : "";
}

/**
 * The APNs half of every alert this app sends, stated once.
 *
 * `apns-push-type` is mandatory on APNs for iOS 13 and later, and
 * `apns-priority: 10` is what "show this now" means — a background priority
 * of 5 lets Apple hold an alert back indefinitely to save power. FCM derives
 * both from the `notification` block when they are absent, so this is not a
 * fix on its own; it is the payload being explicit about what it is, and the
 * one place to add `mutable-content` or a badge if either is ever needed.
 *
 * Shared because the three senders (direct message, offer/event fanout,
 * video moderation) had three separate copies of `{payload: {aps: {sound}}}`
 * and no reason to differ.
 */
export const APNS_ALERT_OPTIONS: ApnsConfig = {
  headers: {
    "apns-priority": "10",
    "apns-push-type": "alert",
  },
  payload: {
    aps: {
      sound: "default",
    },
  },
};

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
 * FCM error code meaning "I have a token, but no way to reach Apple".
 *
 * Raised when the Firebase project holds no APNs authentication key (or
 * certificate) for the app's bundle id, or holds one Apple rejects. It is
 * *not* a problem with the device, the token, or the payload: every iOS send
 * in the project fails with it, forever, until someone uploads the key in
 * Firebase Console > Project settings > Cloud Messaging > Apple app
 * configuration.
 *
 * Singled out because nothing else in this pipeline can tell the two apart,
 * and they are repaired in completely different places. A dead token is
 * per-device and self-heals on the next sign-in; a missing APNs credential is
 * project-wide and self-heals never. Both used to arrive here as "the send
 * threw", logged next to each other, and the second one is the reason no
 * iPhone has ever received a notification from this app.
 */
const APNS_CREDENTIAL_ERROR_CODE = "messaging/third-party-auth-error";

/** Why a single push did not reach its device. */
export type PushFailureKind =
  | "token_unregistered"
  | "apns_credential"
  | "other";

/**
 * Sorts a failed send into the three outcomes that are acted on differently.
 *
 * @param {unknown} error Error thrown by `send`, or reported per-recipient by
 *   `sendEachForMulticast`.
 * @return {PushFailureKind} What kind of failure this is.
 */
export function classifyPushFailure(error: unknown): PushFailureKind {
  if (!error || typeof error !== "object") {
    return "other";
  }
  const code = (error as {code?: unknown}).code;
  if (code === UNREGISTERED_TOKEN_ERROR_CODE) {
    return "token_unregistered";
  }
  if (code === APNS_CREDENTIAL_ERROR_CODE) {
    return "apns_credential";
  }
  return "other";
}

/**
 * Drops a dead token from its private token document (and any legacy public
 * field), but only if it is still the one we just failed to send to.
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
  const tokenRef = pushTokenRef(uid);

  try {
    return await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(userRef);
      const privateSnap = await transaction.get(tokenRef);
      if (!snap.exists) {
        return false;
      }

      const privateStored = privateSnap.data()?.token;
      const legacyStored = snap.data()?.fcmToken;
      let pruned = false;
      if (typeof privateStored === "string" && privateStored.trim() === token) {
        transaction.delete(tokenRef);
        pruned = true;
      }
      if (typeof legacyStored === "string" && legacyStored.trim() === token) {
        transaction.set(userRef, {
          fcmToken: fieldValue.delete(),
          fcmTokenUpdatedAt: fieldValue.delete(),
          fcmTokenPrunedAt: fieldValue.serverTimestamp(),
        }, {merge: true});
        pruned = true;
      }
      return pruned;
    });
  } catch (error) {
    // Cleanup is opportunistic: the notification outcome must never depend on
    // it, and the next failed send will simply try again.
    logger.warn("fcm token prune failed", {uid, reason: params.reason, error});
    return false;
  }
}

/**
 * Inspects a failed send: prunes a dead token, names a broken APNs setup.
 *
 * The APNs branch logs at `error` and says what to do, because it is the one
 * failure here that no amount of retrying, reinstalling or signing in again
 * can clear — and the one that is invisible from every other vantage point.
 * Without a token, a send never reaches Apple and reports `token_missing`;
 * with a token but no credential, it reaches FCM and dies there. The only
 * place the difference is observable is right here.
 *
 * @param {object} params The send error, the owner uid, the token used, and a
 *   short reason recorded in the logs.
 * @return {Promise<PushFailureKind>} What went wrong, so the caller can tell
 *   an unreachable device from a configuration fault from a real outage.
 */
export async function reportPushSendFailure(params: {
  error: unknown;
  uid: string;
  token: string;
  reason: string;
}): Promise<PushFailureKind> {
  const kind = classifyPushFailure(params.error);

  if (kind === "token_unregistered") {
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
    return kind;
  }

  if (kind === "apns_credential") {
    logger.error(
      "APNs credential missing or rejected: no iOS device in this project " +
      "can receive a notification until an APNs authentication key is " +
      "uploaded in Firebase Console > Project settings > Cloud Messaging",
      {uid: params.uid, reason: params.reason, error: params.error},
    );
  }

  return kind;
}
