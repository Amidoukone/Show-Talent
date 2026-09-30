/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {FieldPath, FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db} from "./firebase";
import {MOBILE_CALLABLE_OPTIONS} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";

type SuccessResponse<T> = {
  success: true;
  code: string;
  message: string;
  data?: T;
};
type ActionResponse<T> = SuccessResponse<T>;
type FollowActionData = {
  following: boolean;
  followers: number;
  followings: number;
};
type FollowListItem = {
  uid: string;
  nom: string;
  photoProfil: string;
  role: string;
  isFollowing: boolean;
};
type FollowListData = {
  items: FollowListItem[];
  nextCursor: string | null;
  hasMore: boolean;
};

const FOLLOW_PAGE_SIZE = 30;
const ok = <T>(code: string, message: string, data?: T): SuccessResponse<T> =>
  ({success: true, code, message, data});

type AuthenticatedCallableRequestLike = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {headers?: Record<string, string | string[] | undefined>} | null;
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

function hasLegacyFollow(raw: unknown, targetUserId: string): boolean {
  return Array.isArray(raw) && raw.some((value) =>
    String(value ?? "").trim() === targetUserId,
  );
}

function isActiveUser(data: FirebaseFirestore.DocumentData): boolean {
  return data.estActif !== false && data.authDisabled !== true;
}

async function mutateFollowState(
  currentUserId: string,
  targetUserId: string,
  shouldFollow: boolean,
): Promise<FollowActionData> {
  const currentRef = db.collection("users").doc(currentUserId);
  const targetRef = db.collection("users").doc(targetUserId);
  const followingRef = currentRef.collection("following").doc(targetUserId);
  const followerRef = targetRef.collection("followers").doc(currentUserId);
  const firstBlockRef = db.collection("blocks")
    .doc(`${currentUserId}_${targetUserId}`);
  const secondBlockRef = db.collection("blocks")
    .doc(`${targetUserId}_${currentUserId}`);

  return db.runTransaction(async (transaction) => {
    const [currentSnap, targetSnap, followingSnap, firstBlock, secondBlock] =
      await Promise.all([
        transaction.get(currentRef),
        transaction.get(targetRef),
        transaction.get(followingRef),
        transaction.get(firstBlockRef),
        transaction.get(secondBlockRef),
      ]);
    if (!currentSnap.exists || !isActiveUser(currentSnap.data() ?? {})) {
      throw new HttpsError("failed-precondition", "Profil appelant indisponible.");
    }
    if (!targetSnap.exists || !isActiveUser(targetSnap.data() ?? {})) {
      throw new HttpsError("not-found", "Profil cible introuvable.");
    }
    if (firstBlock.exists || secondBlock.exists) {
      throw new HttpsError("permission-denied", "Abonnement indisponible entre ces profils.");
    }

    const currentData = currentSnap.data() ?? {};
    const targetData = targetSnap.data() ?? {};
    const relationActive = followingSnap.data()?.active === true;
    const legacyActive = hasLegacyFollow(
      currentData.followingsList,
      targetUserId,
    );
    const wasFollowing = relationActive ||
      (!followingSnap.exists && legacyActive);
    const changed = wasFollowing !== shouldFollow;
    const now = FieldValue.serverTimestamp();
    const relation = {
      followerUid: currentUserId,
      followingUid: targetUserId,
      active: shouldFollow,
      updatedAt: now,
      ...(shouldFollow && !wasFollowing ? {createdAt: now} : {}),
    };
    transaction.set(followingRef, relation, {merge: true});
    transaction.set(followerRef, relation, {merge: true});
    // Older installed clients still render these arrays. Keep them mirrored
    // during the public_profiles rollout; the relation documents remain the
    // authoritative state for the new client. Retire the mirror only after
    // old builds no longer need it.
    const currentPatch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
    const targetPatch: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
    if (process.env.MIRROR_LEGACY_FOLLOW_ARRAYS !== "false") {
      const legacyFollowingChange = shouldFollow ?
        FieldValue.arrayUnion(targetUserId) : FieldValue.arrayRemove(targetUserId);
      const legacyFollowerChange = shouldFollow ?
        FieldValue.arrayUnion(currentUserId) : FieldValue.arrayRemove(currentUserId);
      currentPatch.followingsList = legacyFollowingChange;
      targetPatch.followersList = legacyFollowerChange;
    }
    if (changed) {
      const delta = shouldFollow ? 1 : -1;
      currentPatch.followings = FieldValue.increment(delta);
      targetPatch.followers = FieldValue.increment(delta);
    }
    if (Object.keys(currentPatch).length > 0) transaction.update(currentRef, currentPatch);
    if (Object.keys(targetPatch).length > 0) transaction.update(targetRef, targetPatch);

    const delta = changed ? (shouldFollow ? 1 : -1) : 0;
    return {
      following: shouldFollow,
      followers: Math.max(0, Number(targetData.followers ?? 0) + delta),
      followings: Math.max(0, Number(currentData.followings ?? 0) + delta),
    };
  });
}

async function handleMutation(
  request: AuthenticatedCallableRequestLike & {data?: unknown},
  shouldFollow: boolean,
): Promise<ActionResponse<FollowActionData>> {
  const currentUserId = await requireAuth(request);
  const targetUserId = getString(request.data, "targetUserId");
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "targetUserId manquant.");
  }
  if (currentUserId === targetUserId) {
    throw new HttpsError("failed-precondition", "Impossible de modifier son propre abonnement.");
  }
  const data = await mutateFollowState(currentUserId, targetUserId, shouldFollow);
  return ok(
    "follow_updated",
    shouldFollow ? "Abonnement active." : "Abonnement retire.",
    data,
  );
}

export const followUser = onCall(MOBILE_CALLABLE_OPTIONS, async (request) => {
  try {
    return await handleMutation(request, true);
  } catch (error) {
    logger.error("followUser error", {error});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Impossible de traiter l abonnement pour le moment.");
  }
});

export const unfollowUser = onCall(MOBILE_CALLABLE_OPTIONS, async (request) => {
  try {
    return await handleMutation(request, false);
  } catch (error) {
    logger.error("unfollowUser error", {error});
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Impossible de traiter le desabonnement pour le moment.");
  }
});

export const listUserFollows = onCall(
  MOBILE_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<FollowListData>> => {
    const requesterUid = await requireAuth(request);
    const uid = getString(request.data, "uid");
    const listType = getString(request.data, "listType");
    const cursor = getString(request.data, "cursor");
    if (!uid || (listType !== "followers" && listType !== "followings")) {
      throw new HttpsError("invalid-argument", "Liste d abonnements invalide.");
    }

    const [requesterSnap, profileSnap] = await Promise.all([
      db.collection("users").doc(requesterUid).get(),
      db.collection("public_profiles").doc(uid).get(),
    ]);
    if (!requesterSnap.exists || !isActiveUser(requesterSnap.data() ?? {})) {
      throw new HttpsError("permission-denied", "Compte appelant indisponible.");
    }
    if (!profileSnap.exists) {
      throw new HttpsError("not-found", "Profil introuvable.");
    }
    if (uid !== requesterUid && profileSnap.data()?.profilePublic === false) {
      throw new HttpsError("permission-denied", "Ce profil est prive.");
    }

    let relationQuery: FirebaseFirestore.Query = db.collection("users")
      .doc(uid)
      .collection(listType)
      .where("active", "==", true)
      .orderBy(FieldPath.documentId())
      .limit(FOLLOW_PAGE_SIZE + 1);
    if (cursor) relationQuery = relationQuery.startAfter(cursor);
    const relationSnap = await relationQuery.get();
    const visibleRelations = relationSnap.docs.slice(0, FOLLOW_PAGE_SIZE);
    const ids = visibleRelations.map((document) => document.id);
    const profileRefs = ids.map((id) =>
      db.collection("public_profiles").doc(id));
    const followingRefs = ids.map((id) => db.collection("users")
      .doc(requesterUid).collection("following").doc(id));
    const [profiles, requesterRelations] = await Promise.all([
      profileRefs.length > 0 ? db.getAll(...profileRefs) : Promise.resolve([]),
      followingRefs.length > 0 ? db.getAll(...followingRefs) : Promise.resolve([]),
    ]);
    const followsById = new Map(
      requesterRelations.map((snapshot) => [
        snapshot.id,
        snapshot.data()?.active === true,
      ]),
    );
    const items: FollowListItem[] = profiles
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => {
        const data = snapshot.data() ?? {};
        return {
          uid: snapshot.id,
          nom: String(data.nom ?? ""),
          photoProfil: String(data.photoProfil ?? ""),
          role: String(data.role ?? ""),
          isFollowing: followsById.get(snapshot.id) === true,
        };
      });
    const hasMore = relationSnap.docs.length > FOLLOW_PAGE_SIZE;
    return ok("follow_list", "Liste chargee.", {
      items,
      nextCursor: hasMore && visibleRelations.length > 0 ?
        visibleRelations[visibleRelations.length - 1].id : null,
      hasMore,
    });
  },
);
