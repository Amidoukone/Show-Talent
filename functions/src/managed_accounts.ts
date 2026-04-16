/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue} from "./firebase";
import {
  LOW_CPU_REGION_OPTIONS,
  MANAGED_ROLES,
  assertAdminCaller,
  buildTemporaryPassword,
  getString,
  isUserNotFound,
  normalizeRole,
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
  LOW_CPU_REGION_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);

    const email = getString(request.data, "email").toLowerCase();
    const displayName =
      getString(request.data, "nom") || getString(request.data, "displayName");
    const role = normalizeRole(getString(request.data, "role"));
    const phone = getString(request.data, "phone");

    if (!email || !displayName || !role) {
      throw new HttpsError(
        "invalid-argument",
        "email, nom et role sont requis."
      );
    }

    if (!MANAGED_ROLES.has(role)) {
      throw new HttpsError(
        "invalid-argument",
        "Le role doit etre club, recruteur ou agent."
      );
    }

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

    const existingDoc = await db.collection("users").doc(userRecord.uid).get();
    const existingData = existingDoc.data() ?? {};
    const existingRole = normalizeRole(
      getString(existingData, "role"),
    );

    if (existingRole && existingRole !== role) {
      throw new HttpsError(
        "already-exists",
        "Un compte existe deja avec un autre role."
      );
    }

    if (existingUser && userRecord.displayName !== displayName) {
      userRecord = await auth.updateUser(userRecord.uid, {
        displayName,
        disabled: false,
      });
    }

    await db.collection("users").doc(userRecord.uid).set({
      uid: userRecord.uid,
      nom: displayName,
      email,
      phone: phone || existingData.phone || null,
      role,
      photoProfil: existingData.photoProfil ?? "",
      estActif: userRecord.emailVerified && userRecord.disabled !== true,
      authDisabled: userRecord.disabled === true,
      emailVerified: userRecord.emailVerified,
      emailVerifiedAt: userRecord.emailVerified ?
        fieldValue.serverTimestamp() :
        null,
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

    const passwordSetupLink = await auth.generatePasswordResetLink(email);
    const emailVerificationLink = userRecord.emailVerified ?
      null :
      await auth.generateEmailVerificationLink(email);

    return {
      success: true,
      code: existingUser ?
        "managed_account_updated" :
        "managed_account_created",
      message: existingUser ?
        "Compte gere mis a jour." :
        "Compte gere cree.",
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
