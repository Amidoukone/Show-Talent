/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import type {UserRecord} from "firebase-admin/auth";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue, storage} from "./firebase";
import {
  LOW_CPU_CALLABLE_OPTIONS,
  assertAdminCaller,
  assertAdminProvisionedRole,
  buildEmailVerificationActionCodeSettings,
  buildHostedAuthActionLink,
  buildPasswordResetActionCodeSettings,
  cloneCallableRecord,
  getOptionalString,
  getPlainObject,
  getString,
  isManagedRole,
  isPrivilegedClaims,
  isUserNotFound,
  normalizeRole,
} from "./admin_account_support";

type ManagedTargetContext = {
  uid: string;
  userRef: FirebaseFirestore.DocumentReference;
  userData: Record<string, unknown>;
  userRecord: UserRecord | null;
  role: string;
  createdByAdmin: boolean;
};

type ManagedAccountSummary = {
  uid: string;
  email: string;
  role: string;
  createdByAdmin: boolean;
  estActif: boolean;
  authDisabled: boolean;
};

function readBoolean(data: Record<string, unknown>, key: string): boolean {
  return data[key] === true;
}

function getTargetUid(data: unknown): string {
  const uid = getString(data, "uid");
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid est requis.");
  }
  return uid;
}

async function loadManagedTarget(uid: string): Promise<ManagedTargetContext> {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Compte utilisateur introuvable.");
  }

  const userData = userSnap.data() ?? {};
  const role = normalizeRole(getString(userData, "role"));
  const createdByAdmin = userData["createdByAdmin"] === true;

  let userRecord: UserRecord | null = null;
  try {
    userRecord = await auth.getUser(uid);
  } catch (error) {
    if (!isUserNotFound(error)) {
      logger.error("managed target auth lookup failed", error);
      throw error;
    }
  }

  return {
    uid,
    userRef,
    userData,
    userRecord,
    role,
    createdByAdmin,
  };
}

function assertManagedTarget(target: ManagedTargetContext): void {
  if (!target.createdByAdmin && !isManagedRole(target.role)) {
    throw new HttpsError(
      "failed-precondition",
      "Ce compte n’est pas un compte géré par l’administration.",
    );
  }
}

function assertSafeAdminMutation(
  target: ManagedTargetContext,
  adminUid: string,
): void {
  if (target.uid == adminUid) {
    throw new HttpsError(
      "failed-precondition",
      "Vous ne pouvez pas administrer votre propre compte avec cette action.",
    );
  }

  if (target.role == "admin") {
    throw new HttpsError(
      "permission-denied",
      "Les comptes d administration ne peuvent pas etre modifies ici.",
    );
  }

  if (isPrivilegedClaims(target.userRecord?.customClaims)) {
    throw new HttpsError(
      "permission-denied",
      "Les comptes avec claims admin ne peuvent pas etre modifies ici.",
    );
  }
}

function computeAccountActiveState(
  target: ManagedTargetContext,
  options?: {
    authDisabled?: boolean;
  },
): boolean {
  const authDisabled = options?.authDisabled ?? target.userRecord?.disabled === true;
  const emailVerified =
    target.userRecord?.emailVerified ?? readBoolean(target.userData, "emailVerified");

  return !authDisabled && emailVerified;
}

function buildManagedAccountSummary(
  target: ManagedTargetContext,
  options?: {
    estActif?: boolean;
    authDisabled?: boolean;
  },
): ManagedAccountSummary {
  const email = target.userRecord?.email ??
    getString(target.userData, "email");
  const authDisabled = options?.authDisabled ?? target.userRecord?.disabled === true;
  const estActif = options?.estActif ?? computeAccountActiveState(target, {
    authDisabled,
  });

  return {
    uid: target.uid,
    email,
    role: target.role,
    createdByAdmin: target.createdByAdmin,
    estActif,
    authDisabled,
  };
}

function extractStoragePathFromUrl(url: string): string | null {
  const trimmed = url.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith("gs://")) {
    const withoutPrefix = trimmed.slice(5);
    const slashIndex = withoutPrefix.indexOf("/");
    if (slashIndex > 0 && slashIndex < withoutPrefix.length - 1) {
      return withoutPrefix.slice(slashIndex + 1);
    }
    return null;
  }

  try {
    const parsed = new URL(trimmed);
    const marker = "/o/";
    const markerIndex = parsed.pathname.indexOf(marker);
    if (markerIndex >= 0) {
      return decodeURIComponent(parsed.pathname.slice(markerIndex + marker.length));
    }
  } catch (_) {
    return null;
  }

  return null;
}

function addStoragePath(
  value: unknown,
  out: Set<string>,
): void {
  if (typeof value != "string") return;
  const trimmed = value.trim();
  if (!trimmed) return;

  const directPath = trimmed.includes("://") ?
    extractStoragePathFromUrl(trimmed) :
    trimmed;

  if (directPath) {
    out.add(directPath);
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  ) {
    return value as Record<string, unknown>;
  }
  return null;
}

function collectVideoStoragePaths(data: Record<string, unknown>): string[] {
  const paths = new Set<string>();

  addStoragePath(data["storagePath"], paths);
  addStoragePath(data["thumbnailPath"], paths);
  addStoragePath(data["videoUrl"], paths);
  addStoragePath(data["thumbnail"], paths);
  addStoragePath(data["thumbnailUrl"], paths);

  const addSourcePath = (source: unknown) => {
    const sourceMap = asRecord(source);
    if (!sourceMap) return;
    addStoragePath(sourceMap["path"], paths);
    addStoragePath(sourceMap["url"], paths);
    addStoragePath(sourceMap["videoUrl"], paths);
  };

  if (Array.isArray(data["sources"])) {
    for (const source of data["sources"]) {
      addSourcePath(source);
    }
  }

  const playback = asRecord(data["playback"]);
  if (playback) {
    addSourcePath(playback["sourceAsset"]);
    addSourcePath(playback["fallback"]);

    if (Array.isArray(playback["sources"])) {
      for (const source of playback["sources"]) {
        addSourcePath(source);
      }
    }

    const hls = asRecord(playback["hls"]);
    if (hls) {
      addSourcePath(hls["manifest"]);
    }
  }

  return [...paths];
}

async function deleteStoragePathIfPresent(path: string): Promise<void> {
  try {
    await storage.bucket().file(path).delete();
  } catch (error) {
    logger.warn("managed account asset deletion skipped", {path, error});
  }
}

async function deleteDocsInChunks(
  refs: readonly FirebaseFirestore.DocumentReference[],
): Promise<void> {
  const chunkSize = 400;
  for (let index = 0; index < refs.length; index += chunkSize) {
    const batch = db.batch();
    const chunk = refs.slice(index, index + chunkSize);
    for (const ref of chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

async function deleteManagedVideos(uid: string): Promise<void> {
  const snapshot = await db.collection("videos").where("uid", "==", uid).get();
  const refs: FirebaseFirestore.DocumentReference[] = [];

  for (const doc of snapshot.docs) {
    refs.push(doc.ref);
    const paths = collectVideoStoragePaths(doc.data());
    for (const path of paths) {
      await deleteStoragePathIfPresent(path);
    }
  }

  if (refs.length > 0) {
    await deleteDocsInChunks(refs);
  }
}

async function deleteOwnedDocs(
  collectionName: string,
  ownerField: string,
  uid: string,
): Promise<void> {
  const snapshot = await db
    .collection(collectionName)
    .where(ownerField, "==", uid)
    .get();

  const refs = snapshot.docs.map((doc) => doc.ref);
  if (refs.length > 0) {
    await deleteDocsInChunks(refs);
  }
}

async function deleteManagedConversations(uid: string): Promise<void> {
  const snapshot = await db
    .collection("conversations")
    .where("utilisateurIds", "array-contains", uid)
    .get();

  for (const conversationDoc of snapshot.docs) {
    const messages = await conversationDoc.ref.collection("messages").get();
    const messageRefs = messages.docs.map((doc) => doc.ref);
    if (messageRefs.length > 0) {
      await deleteDocsInChunks(messageRefs);
    }
    await conversationDoc.ref.delete();
  }
}

async function cleanupFollowReferences(uid: string): Promise<void> {
  const followersSnapshot = await db
    .collection("users")
    .where("followersList", "array-contains", uid)
    .get();

  for (const doc of followersSnapshot.docs) {
    const data = doc.data();
    const followers =
      typeof data["followers"] == "number" && Number.isFinite(data["followers"]) ?
        Math.max(0, Math.trunc(data["followers"] as number) - 1) :
        0;

    await doc.ref.update({
      followersList: fieldValue.arrayRemove(uid),
      followers,
      updatedAt: fieldValue.serverTimestamp(),
    });
  }

  const followingsSnapshot = await db
    .collection("users")
    .where("followingsList", "array-contains", uid)
    .get();

  for (const doc of followingsSnapshot.docs) {
    const data = doc.data();
    const followings =
      typeof data["followings"] == "number" &&
      Number.isFinite(data["followings"]) ?
        Math.max(0, Math.trunc(data["followings"] as number) - 1) :
        0;

    await doc.ref.update({
      followingsList: fieldValue.arrayRemove(uid),
      followings,
      updatedAt: fieldValue.serverTimestamp(),
    });
  }
}

function sanitizeManagedProfilePatch(
  patch: Record<string, unknown>,
): Record<string, unknown> {
  const stringFields = [
    "phone",
    "photoProfil",
    "bio",
    "country",
    "city",
    "region",
    "nomClub",
    "ligue",
    "entreprise",
    "team",
    "clubActuel",
  ];

  const booleanFields = [
    "profilePublic",
    "allowMessages",
    "openToOpportunities",
  ];

  const mapFields = ["clubProfile", "agentProfile"];

  const updates: Record<string, unknown> = {};

  const rawName = patch["nom"];
  if (typeof rawName === "string" && rawName.trim()) {
    updates["nom"] = rawName.trim();
  }

  for (const field of stringFields) {
    const value = patch[field];
    if (value === null) {
      updates[field] = null;
      continue;
    }
    if (typeof value === "string") {
      updates[field] = value.trim();
    }
  }

  for (const field of booleanFields) {
    const value = patch[field];
    if (typeof value === "boolean") {
      updates[field] = value;
    }
  }

  const rawLanguages = patch["languages"];
  if (Array.isArray(rawLanguages)) {
    updates["languages"] = rawLanguages
      .map((entry) => entry?.toString().trim() ?? "")
      .filter((entry) => entry.length > 0);
  }

  for (const field of mapFields) {
    const value = patch[field];
    if (value === null) {
      updates[field] = null;
      continue;
    }
    const record = asRecord(value);
    if (record) {
      updates[field] = cloneCallableRecord(record);
    }
  }

  return updates;
}

export const disableManagedAccountAuth = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);
    const reason = getOptionalString(request.data, "reason");

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);

    if (!target.userRecord) {
      throw new HttpsError(
        "not-found",
        "Le compte Auth associe est introuvable.",
      );
    }

    const alreadyDisabled = target.userRecord.disabled === true;
    if (!alreadyDisabled) {
      await auth.updateUser(uid, {disabled: true});
    }

    await target.userRef.set({
      estActif: false,
      authDisabled: true,
      authDisabledBy: adminUid,
      authDisabledAt: fieldValue.serverTimestamp(),
      authDisabledReason: reason ?? fieldValue.delete(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      success: true,
      code: alreadyDisabled ?
        "managed_account_auth_already_disabled" :
        "managed_account_auth_disabled",
      message: alreadyDisabled ?
        "Le compte Auth était déjà désactivé." :
        "Le compte Auth a été désactivé.",
      data: buildManagedAccountSummary(target, {
        estActif: false,
        authDisabled: true,
      }),
    };
  },
);

export const enableManagedAccountAuth = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);

    if (!target.userRecord) {
      throw new HttpsError(
        "not-found",
        "Le compte Auth associe est introuvable.",
      );
    }

    const alreadyEnabled = target.userRecord.disabled !== true;
    if (!alreadyEnabled) {
      await auth.updateUser(uid, {disabled: false});
    }

    const estActif = computeAccountActiveState(target, {
      authDisabled: false,
    });

    await target.userRef.set({
      estActif,
      authDisabled: false,
      authDisabledBy: fieldValue.delete(),
      authDisabledAt: fieldValue.delete(),
      authDisabledReason: fieldValue.delete(),
      updatedByAdmin: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      success: true,
      code: alreadyEnabled ?
        "managed_account_auth_already_enabled" :
        "managed_account_auth_enabled",
      message: alreadyEnabled ?
        "Le compte Auth était déjà actif." :
        "Le compte Auth a été réactivé.",
      data: buildManagedAccountSummary(target, {
        estActif,
        authDisabled: false,
      }),
    };
  },
);

export const resendManagedAccountInvite = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);
    assertManagedTarget(target);

    const email = target.userRecord?.email ?? getString(target.userData, "email");
    if (!email) {
      throw new HttpsError(
        "failed-precondition",
        "Le compte cible ne contient pas d email exploitable.",
      );
    }

    const passwordSetupLink = buildHostedAuthActionLink(
      await auth.generatePasswordResetLink(
        email,
        buildPasswordResetActionCodeSettings(),
      ),
      "/account/reset",
    );
    const emailVerificationLink =
      target.userRecord?.emailVerified === true ?
        null :
        buildHostedAuthActionLink(
          await auth.generateEmailVerificationLink(
            email,
            buildEmailVerificationActionCodeSettings(),
          ),
          "/account/verify",
        );

    await target.userRef.set({
      invitedBy: adminUid,
      invitedAt: fieldValue.serverTimestamp(),
      lastInviteAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      success: true,
      code: "managed_account_invite_resent",
      message: "Liens d invitation regeneres.",
      data: {
        ...buildManagedAccountSummary(target),
        passwordSetupLink,
        emailVerificationLink,
      },
    };
  },
);

export const changeManagedAccountRole = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);
    const nextRole = assertAdminProvisionedRole(
      getString(request.data, "newRole") || getString(request.data, "role"),
    );

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);
    assertManagedTarget(target);

    const roleChanged = target.role != nextRole;
    if (roleChanged) {
      await target.userRef.set({
        role: nextRole,
        createdByAdmin: true,
        roleChangedBy: adminUid,
        roleChangedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return {
      success: true,
      code: roleChanged ?
        "managed_account_role_changed" :
        "managed_account_role_unchanged",
      message: roleChanged ?
        "Rôle du compte mis à jour." :
        "Le compte possède déjà ce rôle.",
      data: {
        ...buildManagedAccountSummary(target),
        previousRole: target.role,
        role: nextRole,
      },
    };
  },
);

export const updateManagedAccountProfile = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);
    const rawPatch =
      getPlainObject(request.data, "patch") ??
      getPlainObject(request.data, "data");

    if (!rawPatch) {
      throw new HttpsError(
        "invalid-argument",
        "Un objet patch ou data est requis.",
      );
    }

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);
    assertManagedTarget(target);

    const updates = sanitizeManagedProfilePatch(rawPatch);
    if (Object.keys(updates).length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Aucun champ profil autorisé n’a été fourni.",
      );
    }

    await target.userRef.set({
      ...updates,
      updatedByAdmin: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});

    if (typeof updates["nom"] === "string" && target.userRecord) {
      await auth.updateUser(uid, {displayName: updates["nom"]});
    }

    return {
      success: true,
      code: "managed_account_profile_updated",
      message: "Profil du compte géré mis à jour.",
      data: {
        ...buildManagedAccountSummary(target),
        updatedFields: Object.keys(updates),
      },
    };
  },
);

export const deleteManagedAccount = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);

    logger.info("account deletion started", {
      uid,
      role: target.role,
      deletedBy: adminUid,
    });

    await deleteManagedVideos(uid);
    await deleteOwnedDocs("offres", "recruteur.uid", uid);
    await deleteOwnedDocs("events", "organisateur.uid", uid);
    await deleteManagedConversations(uid);
    await cleanupFollowReferences(uid);

    await target.userRef.delete();

    if (target.userRecord) {
      await auth.deleteUser(uid);
    }

    return {
      success: true,
      code: "managed_account_deleted",
      message: "Compte supprime.",
      data: {
        uid,
        role: target.role,
        deletedBy: adminUid,
      },
    };
  },
);
