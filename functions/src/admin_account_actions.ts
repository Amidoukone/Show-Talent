/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import type {UserRecord} from "firebase-admin/auth";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue, storage} from "./firebase";
import {
  LOW_CPU_CALLABLE_OPTIONS,
  assertAdminCaller,
  assertAdminProvisionedRole,
  cloneCallableRecord,
  getOptionalString,
  getPlainObject,
  generateHostedEmailVerificationLink,
  generateHostedPasswordResetLink,
  getString,
  isManagedRole,
  isPrivilegedClaims,
  isUserNotFound,
  normalizeRole,
  privateAdminNotesRef,
  privateContactRef,
} from "./admin_account_support";
import {EMAIL_SECRETS, sendAccountInviteEmail} from "./email_delivery";

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
    // FieldValue.increment is commutative and applied server-side, unlike
    // a computed followers = count - 1 from a snapshot read here: that
    // read-then-write pattern loses updates if a followUser/unfollowUser
    // transaction (see follow_actions.ts) commits against the same doc
    // between this read and this write.
    await doc.ref.update({
      followersList: fieldValue.arrayRemove(uid),
      followers: fieldValue.increment(-1),
      updatedAt: fieldValue.serverTimestamp(),
    });
  }

  const followingsSnapshot = await db
    .collection("users")
    .where("followingsList", "array-contains", uid)
    .get();

  for (const doc of followingsSnapshot.docs) {
    await doc.ref.update({
      followingsList: fieldValue.arrayRemove(uid),
      followings: fieldValue.increment(-1),
      updatedAt: fieldValue.serverTimestamp(),
    });
  }
}

/**
 * Erases every document and storage object an account owns, then the account
 * document itself. Does NOT touch Firebase Auth — callers decide that.
 *
 * Shared by the admin path (deleteManagedAccount) and the user-initiated path
 * (deleteOwnAccount in account_deletion_actions.ts). It has to live on the
 * server for both: cleanupFollowReferences() writes to *other* users'
 * documents, which Security Rules forbid to any client
 * (`allow update: if isOwner(userId)`). The mobile app used to attempt that
 * cascade itself and swallow the resulting permission-denied, so a user who
 * deleted their own account stayed in everybody else's followersList with
 * their follower counts left over-counted.
 *
 * @param {string} uid Account whose data is being erased.
 * @return {Promise<void>} Resolves once every owned document is gone.
 */
export async function purgeAccountData(uid: string): Promise<void> {
  await deleteManagedVideos(uid);
  await deleteOwnedDocs("offres", "recruteur.uid", uid);
  await deleteOwnedDocs("events", "organisateur.uid", uid);
  await deleteManagedConversations(uid);
  await cleanupFollowReferences(uid);

  // Deleting a document does NOT delete its subcollections in Firestore, so
  // users/{uid}/private/contact (phone, birthDate, email) and
  // private/adminNotes used to outlive the account they belong to --
  // indefinitely, and unreachable from any UI. That is a data-retention
  // defect on the exact fields that were moved into this subcollection
  // *because* they are the sensitive ones. Delete them explicitly, before
  // the parent doc, so a failure here aborts the deletion loudly instead of
  // leaving the personal data behind with the profile already gone.
  await Promise.all([
    privateContactRef(uid).delete(),
    privateAdminNotesRef(uid).delete(),
  ]);

  await db.collection("users").doc(uid).delete();
}

// Mirrors ownerProfileTrustFieldsChanged() in firestore.rules and
// _trustSensitiveProfileKeys in the mobile app's profile_repository.dart.
// Admin SDK writes bypass Security Rules, so that invariant (editing a
// trust-sensitive field on an already-verified profile invalidates the
// verification) has to be reimplemented here explicitly, or an admin edit
// could silently leave a stale "verified" badge on materially changed data.
const TRUST_SENSITIVE_PROFILE_FIELDS = [
  "nom",
  "phone",
  "languages",
  "bio",
  "birthDate",
  "position",
  "team",
  "clubActuel",
  "nombreDeMatchs",
  "buts",
  "assistances",
  "performances",
  "nomClub",
  "ligue",
  "entreprise",
  "nombreDeRecrutements",
  "country",
  "city",
  "region",
  "openToOpportunities",
  "playerProfile",
  "clubProfile",
  "agentProfile",
  "eventOrganizerProfile",
  "photoProfil",
  "cvUrl",
];

function isProfileCurrentlyVerified(data: Record<string, unknown>): boolean {
  return data["profileVerified"] === true ||
    data["profileVerificationStatus"] === "verified";
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

// Mirrors AppUser.isMvpProfileComplete (lib/models/user.dart, both apps).
function isMvpProfileComplete(
  role: string,
  data: Record<string, unknown>,
): boolean {
  const nom = trimmedString(data["nom"]);
  if (!nom) {
    return false;
  }

  switch (role) {
  case "joueur":
    return (
      trimmedString(data["position"]).length > 0 &&
        trimmedString(data["team"]).length > 0
    );
  case "club":
    return trimmedString(data["ligue"]).length > 0;
  case "recruteur":
  case "agent":
    return trimmedString(data["entreprise"]).length > 0;
  default:
    return true;
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
    "position",
  ];

  const booleanFields = [
    "profilePublic",
    "allowMessages",
    "openToOpportunities",
    "profileVerified",
  ];

  const nonNegativeIntFields = [
    "nombreDeMatchs",
    "buts",
    "assistances",
    "nombreDeRecrutements",
  ];

  const mapFields = ["clubProfile", "agentProfile", "playerProfile"];

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

  for (const field of nonNegativeIntFields) {
    const value = patch[field];
    if (value === null) {
      updates[field] = null;
      continue;
    }
    if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
      updates[field] = Math.trunc(value);
    }
  }

  const rawVerificationStatus = patch["profileVerificationStatus"];
  if (typeof rawVerificationStatus === "string") {
    const normalized = rawVerificationStatus.trim().toLowerCase();
    if (["verified", "unverified", "pending", "rejected"].includes(normalized)) {
      updates["profileVerificationStatus"] = normalized;
    }
  }

  const rawVerificationNote = patch["profileVerificationNote"];
  if (rawVerificationNote === null) {
    updates["profileVerificationNote"] = null;
  } else if (typeof rawVerificationNote === "string") {
    const normalized = rawVerificationNote.trim();
    if (normalized) {
      updates["profileVerificationNote"] = normalized.slice(0, 500);
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

    const disableBatch = db.batch();
    disableBatch.set(target.userRef, {
      estActif: false,
      authDisabled: true,
      authDisabledBy: adminUid,
      authDisabledAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});
    disableBatch.set(privateContactRef(uid), {
      authDisabledReason: reason ?? fieldValue.delete(),
    }, {merge: true});
    await disableBatch.commit();

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

    const enableBatch = db.batch();
    enableBatch.set(target.userRef, {
      estActif,
      authDisabled: false,
      authDisabledBy: fieldValue.delete(),
      authDisabledAt: fieldValue.delete(),
      updatedByAdmin: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});
    enableBatch.set(privateContactRef(uid), {
      authDisabledReason: fieldValue.delete(),
    }, {merge: true});
    await enableBatch.commit();

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
  {...LOW_CPU_CALLABLE_OPTIONS, secrets: EMAIL_SECRETS},
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
        "Le compte cible ne contient pas d’e-mail exploitable.",
      );
    }

    const passwordSetupLink = await generateHostedPasswordResetLink(email);
    const emailVerificationLink =
      target.userRecord?.emailVerified === true ?
        null :
        await generateHostedEmailVerificationLink(email);

    await target.userRef.set({
      invitedBy: adminUid,
      invitedAt: fieldValue.serverTimestamp(),
      lastInviteAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});

    // Same contract as provisioning: the links are returned whatever the
    // relay does, so "renvoyer l'invitation" degrades to what it does today
    // rather than failing.
    const invite = await sendAccountInviteEmail({
      to: email,
      displayName:
        target.userRecord?.displayName ?? getString(target.userData, "nom"),
      passwordSetupLink,
      resend: true,
    });

    return {
      success: true,
      code: "managed_account_invite_resent",
      message: invite.sent ?
        "Invitation envoyée par e-mail." :
        "Liens d invitation regeneres.",
      data: {
        ...buildManagedAccountSummary(target),
        passwordSetupLink,
        emailVerificationLink,
        inviteEmailSent: invite.sent,
        inviteEmailReason: invite.reason ?? null,
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

    const sanitizedPatch = sanitizeManagedProfilePatch(rawPatch);
    if (Object.keys(sanitizedPatch).length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Aucun champ profil autorisé n’a été fourni.",
      );
    }

    const accountActive = computeAccountActiveState(target);

    // The read that the profileVerified/invalidation decision below depends
    // on happens inside the transaction (tx.get()), not via the
    // loadManagedTarget() snapshot taken above — otherwise a concurrent
    // write landing between that earlier read and this function's commit
    // (another admin action, or the owner editing their own profile) could
    // make the decision on stale data while still committing unconditionally.
    // sanitizedPatch is rebuilt into a fresh `updates` object on every
    // attempt so a transaction retry (Firestore retries on contention)
    // starts from the original patch instead of a previous attempt's
    // already-mutated state.
    const updatedFields = await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(target.userRef);
      const freshData = freshSnap.exists ? freshSnap.data() ?? {} : {};
      const updates: Record<string, unknown> = {...sanitizedPatch};

      const adminExplicitlySetVerification = "profileVerified" in updates;
      if (
        !adminExplicitlySetVerification &&
        isProfileCurrentlyVerified(freshData) &&
        Object.keys(updates).some((key) =>
          TRUST_SENSITIVE_PROFILE_FIELDS.includes(key)
        )
      ) {
        updates["profileVerified"] = false;
        updates["profileVerificationStatus"] = "pending";
        updates["profileVerificationInvalidatedAt"] =
          fieldValue.serverTimestamp();
        updates["profileVerificationInvalidatedBy"] = adminUid;
        updates["profileVerificationInvalidationReason"] =
          "profile_updated_by_admin";
      }

      if (updates["profileVerified"] === true) {
        // Mirrors AppUser.canBeProfileVerifiedByAdmin on the client: that
        // check only gates which button the admin UI shows, and Admin SDK
        // writes bypass Security Rules entirely, so without this the
        // callable itself would happily verify an incomplete or inactive
        // profile if called directly.
        if (!accountActive) {
          throw new HttpsError(
            "failed-precondition",
            "Le compte doit être actif (email vérifié, non désactivé) avant d’être certifié.",
          );
        }
        if (!isMvpProfileComplete(target.role, {...freshData, ...updates})) {
          throw new HttpsError(
            "failed-precondition",
            "Le profil ne contient pas encore les informations minimales requises pour être certifié.",
          );
        }

        updates["profileVerificationStatus"] = "verified";
        updates["profileVerifiedBy"] = adminUid;
        updates["profileVerifiedAt"] = fieldValue.serverTimestamp();
        updates["profileVerificationUpdatedBy"] = adminUid;
        updates["profileVerificationUpdatedAt"] = fieldValue.serverTimestamp();
        updates["profileVerificationInvalidatedAt"] = fieldValue.delete();
        updates["profileVerificationInvalidatedBy"] = fieldValue.delete();
        updates["profileVerificationInvalidationReason"] = fieldValue.delete();
      } else if (updates["profileVerified"] === false) {
        updates["profileVerificationStatus"] =
          updates["profileVerificationStatus"] ?? "unverified";
        updates["profileVerifiedBy"] = fieldValue.delete();
        updates["profileVerifiedAt"] = fieldValue.delete();
        updates["profileVerificationUpdatedBy"] = adminUid;
        updates["profileVerificationUpdatedAt"] = fieldValue.serverTimestamp();
      }

      const mainDocUpdates = {...updates};
      const contactUpdates: Record<string, unknown> = {};
      const adminNotesUpdates: Record<string, unknown> = {};

      if ("phone" in mainDocUpdates) {
        contactUpdates["phone"] = mainDocUpdates["phone"];
        delete mainDocUpdates["phone"];
      }
      if ("profileVerificationNote" in mainDocUpdates) {
        adminNotesUpdates["profileVerificationNote"] =
          mainDocUpdates["profileVerificationNote"];
        delete mainDocUpdates["profileVerificationNote"];
      }

      tx.set(target.userRef, {
        ...mainDocUpdates,
        updatedByAdmin: adminUid,
        updatedAt: fieldValue.serverTimestamp(),
      }, {merge: true});
      if (Object.keys(contactUpdates).length > 0) {
        tx.set(privateContactRef(uid), contactUpdates, {merge: true});
      }
      if (Object.keys(adminNotesUpdates).length > 0) {
        tx.set(privateAdminNotesRef(uid), adminNotesUpdates, {merge: true});
      }

      return updates;
    });

    if (typeof updatedFields["nom"] === "string" && target.userRecord) {
      await auth.updateUser(uid, {displayName: updatedFields["nom"]});
    }

    return {
      success: true,
      code: "managed_account_profile_updated",
      message: "Profil du compte géré mis à jour.",
      data: {
        ...buildManagedAccountSummary(target),
        updatedFields: Object.keys(updatedFields),
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

    await purgeAccountData(uid);

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


/* -------------------------------------------------------------------------- */
/* DROITS D'ACCÈS ENREGISTRÉS PAR L'ADMINISTRATION                             */
/* -------------------------------------------------------------------------- */

/**
 * Les deux populations de joueurs, plus l'absence de dossier.
 *
 * Adfoot porte deux économies opposées : les joueurs sous contrat avec
 * l'agence, qui ne paient jamais rien — ni inscription ni accompagnement —, et
 * les joueurs extérieurs, libres de tout lien, qui paient les services qu'ils
 * utilisent. Les clubs et recruteurs s'abonnent.
 *
 * "none" n'est pas une troisième population : c'est l'absence de dossier, ce
 * que porte aujourd'hui chaque compte existant et ce qui doit continuer de se
 * comporter exactement comme aujourd'hui.
 */
const MEMBERSHIP_TIERS = new Set(["none", "adfoot", "external"]);

/** Durée maximale accordable en un appel : cinq ans. */
const MAX_MEMBERSHIP_VALIDITY_MS = 5 * 365 * 24 * 60 * 60 * 1000;

/**
 * Lit la date d'échéance facultative.
 *
 * @param {unknown} raw Chaîne ISO, millisecondes epoch, ou rien.
 * @return {Date | null} L'échéance, ou null pour un droit sans terme.
 */
function parseMembershipValidUntil(raw: unknown): Date | null {
  if (raw === undefined || raw === null || raw === "") return null;

  let parsed: Date | null = null;
  if (typeof raw === "number" && Number.isFinite(raw)) {
    parsed = new Date(raw);
  } else if (typeof raw === "string") {
    const candidate = new Date(raw.trim());
    if (!Number.isNaN(candidate.getTime())) parsed = candidate;
  }

  if (!parsed || Number.isNaN(parsed.getTime())) {
    throw new HttpsError(
      "invalid-argument",
      "validUntil doit être une date ISO ou un timestamp en millisecondes.",
    );
  }

  const now = Date.now();
  if (parsed.getTime() <= now) {
    throw new HttpsError(
      "invalid-argument",
      "validUntil doit être dans le futur. Pour retirer un droit, " +
        "utilisez tier: \"none\".",
    );
  }
  if (parsed.getTime() - now > MAX_MEMBERSHIP_VALIDITY_MS) {
    throw new HttpsError(
      "invalid-argument",
      "validUntil ne peut pas dépasser cinq ans.",
    );
  }

  return parsed;
}

/**
 * Enregistre — ou retire — les droits d'accès d'un compte.
 *
 * Callable dédié plutôt qu'un champ ajouté à updateManagedAccountProfile :
 * ce dernier porte l'invariant d'invalidation du profil vérifié, et
 * enregistrer un paiement ne doit pas coûter son badge à un joueur. Même
 * raisonnement que pour l'acceptation des CGU.
 *
 * **Ce callable ne déplace aucun argent et ne connaît aucun prix.** Le
 * paiement a lieu hors plateforme — mobile money, virement, espèces à
 * l'agence — et ceci ne fait que refléter la décision de l'administration pour
 * que l'application puisse en tenir compte. L'application mobile n'affiche
 * aucun prix, n'offre aucun moyen de payer et ne renvoie vers aucun : c'est ce
 * qui maintient vraie la déclaration Play Console « aucun achat intégré ».
 * Ne pas ajouter de montant à cette charge utile : le jour où un prix vit dans
 * la plateforme, cette déclaration cesse d'être vraie.
 */
export const setManagedAccountMembership = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = getTargetUid(request.data);

    const tier = (getString(request.data, "tier") || "").trim().toLowerCase();
    if (!MEMBERSHIP_TIERS.has(tier)) {
      throw new HttpsError(
        "invalid-argument",
        "tier doit valoir \"adfoot\", \"external\" ou \"none\".",
      );
    }

    const reference = getString(request.data, "reference").slice(0, 120);
    const validUntil = tier === "none" ?
      null :
      parseMembershipValidUntil(
        (request.data as Record<string, unknown> | undefined)?.validUntil,
      );

    const target = await loadManagedTarget(uid);
    assertSafeAdminMutation(target, adminUid);
    assertManagedTarget(target);

    if (tier === "none") {
      // Effacé, et non ramené à une forme "expirée" : un compte sans dossier
      // doit être indiscernable d'un compte qui n'en a jamais eu, sinon chaque
      // garde-fou devrait apprendre un troisième état dont il n'a pas besoin.
      await target.userRef.set(
        {
          membership: fieldValue.delete(),
          membershipUpdatedAt: fieldValue.serverTimestamp(),
          membershipUpdatedBy: adminUid,
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      return {
        success: true,
        code: "managed_account_membership_cleared",
        message: "Droits retirés.",
        data: {...buildManagedAccountSummary(target), tier: "none"},
      };
    }

    await target.userRef.set(
      {
        membership: {
          tier,
          startedAt: fieldValue.serverTimestamp(),
          validUntil: validUntil ? Timestamp.fromDate(validUntil) : null,
          ...(reference ? {reference} : {}),
        },
        membershipUpdatedAt: fieldValue.serverTimestamp(),
        membershipUpdatedBy: adminUid,
        updatedAt: fieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {
      success: true,
      code: "managed_account_membership_set",
      message: validUntil ?
        `Droits enregistrés jusqu'au ${validUntil.toISOString().slice(0, 10)}.` :
        "Droits enregistrés, sans terme.",
      data: {
        ...buildManagedAccountSummary(target),
        tier,
        validUntil: validUntil ? validUntil.toISOString() : null,
      },
    };
  },
);
