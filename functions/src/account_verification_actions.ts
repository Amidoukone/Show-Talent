/* eslint-disable linebreak-style */

import {HttpsError, onCall} from "firebase-functions/v2/https";

import {auth, db, fieldValue} from "./firebase";
import {LOW_CPU_CALLABLE_OPTIONS} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";

/**
 * Reads a boolean flag from a Firestore-like record.
 * @param {Record<string, unknown>} data Source record.
 * @param {string} key Field name to inspect.
 * @return {boolean} Whether the field is explicitly true.
 */
function readBoolean(data: Record<string, unknown>, key: string): boolean {
  return data[key] === true;
}

/**
 * Extracts the optional updateLastLogin flag from callable payload data.
 * @param {unknown} data Raw callable payload.
 * @return {boolean} Whether dernierLogin should be refreshed.
 */
function readUpdateLastLogin(data: unknown): boolean {
  if (typeof data !== "object" || data === null) {
    return false;
  }

  return (data as Record<string, unknown>)["updateLastLogin"] === true;
}

/**
 * Formats an unknown runtime error into a short debug string.
 * @param {unknown} error Unknown runtime error.
 * @return {string} Normalized message safe to surface in smoke diagnostics.
 */
function formatUnknownErrorMessage(error: unknown): string {
  if (error instanceof HttpsError) {
    return `${error.code}: ${error.message}`;
  }

  if (error instanceof Error && typeof error.message === "string") {
    return error.message;
  }

  if (
    typeof error === "object" &&
    error !== null &&
    typeof (error as {message?: unknown}).message === "string"
  ) {
    return (error as {message: string}).message;
  }

  return "unknown_error";
}

export const completeEmailVerification = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    try {
      const {uid} = await resolveCallableAuth(request);
      const updateLastLogin = readUpdateLastLogin(request.data);

      console.log("completeEmailVerification:start", {
        uid,
        updateLastLogin,
      });

      const authRecord = await auth.getUser(uid);
      if (!authRecord.emailVerified) {
        throw new HttpsError(
          "failed-precondition",
          "L’e-mail n’est pas encore vérifié dans Firebase Auth.",
        );
      }

      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      if (!userSnap.exists) {
        throw new HttpsError(
          "not-found",
          "Profil utilisateur introuvable.",
        );
      }

      const userData = userSnap.data() ?? {};
      const nextActiveState = authRecord.disabled !== true;
      const updates: Record<string, unknown> = {
        emailVerified: true,
        estActif: nextActiveState,
        authDisabled: authRecord.disabled === true,
        authDisabledAt: authRecord.disabled === true ?
          userData["authDisabledAt"] ?? fieldValue.serverTimestamp() :
          fieldValue.delete(),
        authDisabledBy: authRecord.disabled === true ?
          userData["authDisabledBy"] ?? "system" :
          fieldValue.delete(),
        authDisabledReason: authRecord.disabled === true ?
          userData["authDisabledReason"] ?? "account_disabled_in_auth" :
          fieldValue.delete(),
        estBloque: fieldValue.delete(),
        blockedAt: fieldValue.delete(),
        blockedBy: fieldValue.delete(),
        blockedReason: fieldValue.delete(),
        blockMode: fieldValue.delete(),
        blockedUntil: fieldValue.delete(),
        updatedAt: fieldValue.serverTimestamp(),
      };

      if (!readBoolean(userData, "emailVerified")) {
        updates["emailVerified"] = true;
      }

      if (userData["emailVerifiedAt"] == null) {
        updates["emailVerifiedAt"] = fieldValue.serverTimestamp();
      }

      if (updateLastLogin) {
        updates["dernierLogin"] = fieldValue.serverTimestamp();
      }

      await userRef.set(updates, {merge: true});

      console.log("completeEmailVerification:success", {
        uid,
        estActif: nextActiveState,
        authDisabled: authRecord.disabled === true,
      });

      return {
        success: true,
        code: "email_verification_completed",
        message: "Verification e-mail synchronisee.",
        data: {
          uid,
          emailVerified: true,
          estActif: nextActiveState,
          authDisabled: authRecord.disabled === true,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      const message = formatUnknownErrorMessage(error);
      console.error("completeEmailVerification:failure", {
        message,
      });
      throw new HttpsError(
        "internal",
        `completeEmailVerification failed: ${message}`,
      );
    }
  },
);
