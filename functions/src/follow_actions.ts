/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db} from "./firebase";
import {LOW_CPU_CALLABLE_OPTIONS} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";

type SuccessResponse<T> = {
  success: true;
  code: string;
  message: string;
  data?: T;
};

type ErrorResponse = {
  success: false;
  code: string;
  message: string;
  retriable?: boolean;
};

type ActionResponse<T> = SuccessResponse<T> | ErrorResponse;

type FollowActionData = {
  following: boolean;
  followers: number;
  followings: number;
};

const ok = <T>(
  code: string,
  message: string,
  data?: T,
): SuccessResponse<T> => ({
    success: true,
    code,
    message,
    data,
  });

type AuthenticatedCallableRequestLike = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
};

async function requireAuth(
  request: AuthenticatedCallableRequestLike,
): Promise<string> {
  const {uid} = await resolveCallableAuth(request);
  return uid;
}

function getString(data: unknown, key: string): string {
  if (typeof data !== "object" || data === null) return "";
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value.trim() : "";
}

function sanitizeStringArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((value) => String(value).trim())
    .filter((value) => value.length > 0);
}

async function mutateFollowState(
  currentUserId: string,
  targetUserId: string,
  shouldFollow: boolean,
): Promise<FollowActionData> {
  const currentRef = db.collection("users").doc(currentUserId);
  const targetRef = db.collection("users").doc(targetUserId);

  return db.runTransaction(async (transaction) => {
    const [currentSnap, targetSnap] = await Promise.all([
      transaction.get(currentRef),
      transaction.get(targetRef),
    ]);

    if (!currentSnap.exists) {
      throw new HttpsError("failed-precondition", "Profil appelant introuvable.");
    }

    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "Profil cible introuvable.");
    }

    const currentData = currentSnap.data() || {};
    const targetData = targetSnap.data() || {};

    const currentFollowings = new Set(
      sanitizeStringArray(currentData["followingsList"]),
    );
    const targetFollowers = new Set(
      sanitizeStringArray(targetData["followersList"]),
    );

    if (shouldFollow) {
      currentFollowings.add(targetUserId);
      targetFollowers.add(currentUserId);
    } else {
      currentFollowings.delete(targetUserId);
      targetFollowers.delete(currentUserId);
    }

    const nextFollowingsList = Array.from(currentFollowings);
    const nextFollowersList = Array.from(targetFollowers);

    transaction.update(currentRef, {
      followingsList: nextFollowingsList,
      followings: nextFollowingsList.length,
    });

    transaction.update(targetRef, {
      followersList: nextFollowersList,
      followers: nextFollowersList.length,
    });

    return {
      following: shouldFollow,
      followers: nextFollowersList.length,
      followings: nextFollowingsList.length,
    };
  });
}

export const followUser = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<FollowActionData>> => {
    const currentUserId = await requireAuth(request);
    const targetUserId = getString(request.data, "targetUserId");

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId manquant.");
    }

    if (currentUserId === targetUserId) {
      throw new HttpsError(
        "failed-precondition",
        "Impossible de s abonner a son propre profil.",
      );
    }

    try {
      const data = await mutateFollowState(currentUserId, targetUserId, true);
      return ok("follow_updated", "Abonnement active.", data);
    } catch (error) {
      logger.error("followUser error", {
        currentUserId,
        targetUserId,
        error,
      });
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Impossible de traiter l abonnement pour le moment.",
      );
    }
  },
);

export const unfollowUser = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<FollowActionData>> => {
    const currentUserId = await requireAuth(request);
    const targetUserId = getString(request.data, "targetUserId");

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId manquant.");
    }

    if (currentUserId === targetUserId) {
      throw new HttpsError(
        "failed-precondition",
        "Impossible de modifier l abonnement sur son propre profil.",
      );
    }

    try {
      const data = await mutateFollowState(currentUserId, targetUserId, false);
      return ok("follow_updated", "Abonnement retire.", data);
    } catch (error) {
      logger.error("unfollowUser error", {
        currentUserId,
        targetUserId,
        error,
      });
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Impossible de traiter le desabonnement pour le moment.",
      );
    }
  },
);
