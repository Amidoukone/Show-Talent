/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {auth, db} from "./firebase";
import {MOBILE_CALLABLE_OPTIONS, logAppCheckState} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";
import {purgeAccountData} from "./admin_account_actions";
import {normalizeRole} from "./admin_account_support";

// Mirrors adminPortalOnlyRoles in the mobile app's account_role_policy.dart.
const ADMIN_PORTAL_ONLY_ROLES = new Set(["admin"]);

// Matches _maxDeleteAuthSessionAge in the mobile app's
// account_cleanup_service.dart, and replaces the client-side
// `requires-recent-login` check that Firebase Auth used to perform when the
// app deleted the Auth user itself. Deleting through the Admin SDK bypasses
// that guard entirely, so it has to be reimposed here: without it, anyone
// holding an unlocked phone with a live session could erase the account.
const MAX_AUTH_AGE_SECONDS = 20 * 60;

// The cascade walks videos (plus their Storage objects), offers, events,
// conversations and every follower/following reference. The 60s default is
// comfortable for a typical account and too tight for a heavy one, and a
// deletion cut off halfway leaves the account half-erased.
const DELETE_OWN_ACCOUNT_OPTIONS = {
  ...MOBILE_CALLABLE_OPTIONS,
  timeoutSeconds: 300,
} as const;

/**
 * Seconds since the caller last actually authenticated.
 *
 * @param {Record<string, unknown> | null} token Decoded ID token claims.
 * @return {number | null} Age in seconds, or null when the claim is absent.
 */
function authAgeSeconds(token: Record<string, unknown> | null): number | null {
  const authTime = token?.["auth_time"];
  if (typeof authTime !== "number" || !Number.isFinite(authTime)) {
    return null;
  }
  return Math.max(0, Math.floor(Date.now() / 1000) - authTime);
}

/**
 * Deletes the caller's own account: owned data first, then the Auth user.
 *
 * This exists because the cascade cannot run on the client. Removing the
 * departing uid from other users' `followersList` / `followingsList` means
 * writing to documents the caller does not own, which firestore.rules refuses
 * (`allow update: if isOwner(userId)`). The mobile app used to attempt it and
 * swallow the permission-denied, leaving deleted accounts referenced in
 * everybody else's follow lists with inflated counters.
 *
 * Ordering matters and is deliberate: data, then the profile document, then
 * Auth. The reverse order would destroy the credential the cascade needs. The
 * recency check happens before anything is touched, so a caller who fails it
 * still has a complete, working account to retry from -- the previous
 * client-side flow deleted the profile first and only then discovered Auth
 * refused, which left the user unable to log back in and finish.
 */
export const deleteOwnAccount = onCall(
  DELETE_OWN_ACCOUNT_OPTIONS,
  async (request): Promise<Record<string, unknown>> => {
    const {uid, token} = await resolveCallableAuth(request);
    logAppCheckState("deleteOwnAccount", request, uid);

    const ageSeconds = authAgeSeconds(token);
    if (ageSeconds === null || ageSeconds > MAX_AUTH_AGE_SECONDS) {
      throw new HttpsError(
        "failed-precondition",
        "Verification de securite requise. Merci de vous reconnecter puis de relancer la suppression.",
        {reason: "requires_recent_login"},
      );
    }

    // An admin account has no business being deleted through the mobile
    // client, and the blast radius if it were is the whole back office. These
    // roles are already refused at sign-in on mobile (adminPortalOnlyRoles),
    // so this only closes the direct-callable path.
    if (
      token?.["admin"] === true ||
      token?.["platformAdmin"] === true ||
      token?.["superAdmin"] === true
    ) {
      throw new HttpsError(
        "permission-denied",
        "Un compte d'administration ne peut pas etre supprime depuis l'application.",
      );
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const role = userSnap.exists ?
      normalizeRole(String(userSnap.data()?.["role"] ?? "")) :
      "";
    if (ADMIN_PORTAL_ONLY_ROLES.has(role)) {
      throw new HttpsError(
        "permission-denied",
        "Un compte d'administration ne peut pas etre supprime depuis l'application.",
      );
    }

    logger.info("self-service account deletion started", {uid, role});

    await purgeAccountData(uid);

    try {
      await auth.deleteUser(uid);
    } catch (error) {
      // The Firestore side is already gone at this point, so surfacing a
      // failure as "deletion failed" would be wrong: retrying would find
      // nothing left to erase. Report it loudly instead -- an orphaned Auth
      // user with no profile cannot sign in (the session resolver treats a
      // missing profile as a closed account) and is cleaned up by
      // cleanupUnverifiedUsers or by an admin.
      logger.error("self-service auth deletion failed after data purge", {
        uid,
        error,
      });
      return {
        success: true,
        code: "account_data_deleted_auth_pending",
        message: "Compte supprime.",
        data: {uid, authDeleted: false},
      };
    }

    logger.info("self-service account deletion completed", {uid});

    return {
      success: true,
      code: "account_deleted",
      message: "Compte supprime.",
      data: {uid, authDeleted: true},
    };
  },
);
