/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue} from "./firebase";
import {
  LOW_CPU_CALLABLE_OPTIONS,
  assertAdminCaller,
  assertAdminProvisionedRole,
  buildTemporaryPassword,
  generateHostedEmailVerificationLink,
  generateHostedPasswordResetLink,
  getString,
  isPrivilegedClaims,
  isUserNotFound,
  normalizeRole,
  privateContactRef,
} from "./admin_account_support";

type ProvisionedManagedAccount = {
  uid: string;
  email: string;
  role: string;
  existingUser: boolean;
  passwordSetupLink: string;
  emailVerificationLink: string | null;
};

export const provisionManagedAccount = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);

    const email = getString(request.data, "email").toLowerCase();
    const displayName =
      getString(request.data, "nom") || getString(request.data, "displayName");
    const rawRole = getString(request.data, "role");
    const phone = getString(request.data, "phone");

    if (!email || !displayName || !rawRole) {
      throw new HttpsError(
        "invalid-argument",
        "email, nom et rôle sont requis."
      );
    }

    const role = assertAdminProvisionedRole(rawRole);

    let userRecord;
    let existingUser = false;

    try {
      userRecord = await auth.getUserByEmail(email);
      existingUser = true;
    } catch (error) {
      if (!isUserNotFound(error)) {
        logger.error("managed account lookup failed", error);
        throw error;
      }

      userRecord = await auth.createUser({
        email,
        displayName,
        password: buildTemporaryPassword(),
        disabled: false,
      });
    }

    if (existingUser && isPrivilegedClaims(userRecord.customClaims)) {
      throw new HttpsError(
        "permission-denied",
        "Un compte avec claims admin ne peut pas etre provisionne " +
          "comme compte metier.",
      );
    }

    const existingDoc = await db.collection("users").doc(userRecord.uid).get();
    const existingData = existingDoc.data() ?? {};
    const existingRole = normalizeRole(
      getString(existingData, "role"),
    );
    const existingContactDoc = await privateContactRef(userRecord.uid).get();
    const existingContactData = existingContactDoc.data() ?? {};

    if (existingRole && existingRole !== role) {
      throw new HttpsError(
        "already-exists",
        "Un compte existe déjà avec un autre rôle."
      );
    }

    if (
      existingUser &&
      (userRecord.displayName !== displayName || userRecord.disabled === true)
    ) {
      userRecord = await auth.updateUser(userRecord.uid, {
        displayName,
        disabled: false,
      });
    }

    const emailVerifiedAt = userRecord.emailVerified ?
      existingData.emailVerifiedAt ?? fieldValue.serverTimestamp() :
      null;

    const provisionBatch = db.batch();
    provisionBatch.set(db.collection("users").doc(userRecord.uid), {
      uid: userRecord.uid,
      nom: displayName,
      role,
      photoProfil: existingData.photoProfil ?? "",
      estActif: userRecord.emailVerified && userRecord.disabled !== true,
      authDisabled: userRecord.disabled === true,
      emailVerified: userRecord.emailVerified,
      emailVerifiedAt,
      dateInscription: existingDoc.exists ?
        (existingData.dateInscription ?? fieldValue.serverTimestamp()) :
        fieldValue.serverTimestamp(),
      dernierLogin: existingDoc.exists ?
        (existingData.dernierLogin ?? fieldValue.serverTimestamp()) :
        fieldValue.serverTimestamp(),
      followers: existingData.followers ?? 0,
      followings: existingData.followings ?? 0,
      followersList: existingData.followersList ?? [],
      followingsList: existingData.followingsList ?? [],
      profilePublic: existingData.profilePublic ?? true,
      allowMessages: existingData.allowMessages ?? true,
      createdByAdmin: true,
      invitedBy: adminUid,
      invitedAt: existingData.invitedAt ?? fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});
    provisionBatch.set(privateContactRef(userRecord.uid), {
      email,
      phone: phone || existingContactData.phone || null,
    }, {merge: true});
    await provisionBatch.commit();

    const passwordSetupLink = await generateHostedPasswordResetLink(email);
    const emailVerificationLink = userRecord.emailVerified ?
      null :
      await generateHostedEmailVerificationLink(email);

    return {
      success: true,
      code: existingUser ?
        "managed_account_updated" :
        "managed_account_created",
      message: existingUser ?
        "Compte géré mis à jour." :
        "Compte géré créé.",
      data: {
        uid: userRecord.uid,
        email,
        role,
        existingUser,
        passwordSetupLink,
        emailVerificationLink,
      } satisfies ProvisionedManagedAccount,
    };
  },
);
