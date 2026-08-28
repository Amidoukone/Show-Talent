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
import {EMAIL_SECRETS, sendAccountInviteEmail} from "./email_delivery";

type ProvisionedManagedAccount = {
  uid: string;
  email: string;
  role: string;
  existingUser: boolean;
  passwordSetupLink: string;
  emailVerificationLink: string | null;
  /**
   * Whether the invitation was e-mailed to the new member.
   *
   * `passwordSetupLink` stays in the response whatever this says. The portal
   * shows it either way, so an SMTP outage costs an extra copy-paste and
   * never an account nobody can reach.
   */
  inviteEmailSent: boolean;
  /** Coarse reason the invitation was not sent, when it was not. */
  inviteEmailReason: string | null;
};

export const provisionManagedAccount = onCall(
  {...LOW_CPU_CALLABLE_OPTIONS, secrets: EMAIL_SECRETS},
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

    // The address is trusted the moment an admin provisions it, and saying so
    // here is what makes the account usable immediately.
    //
    // There is no self-signup on this platform: an admin types the address
    // and the invitation is delivered to it, so nobody arrives without an
    // admin vouching for their mailbox. Leaving the flag false only moved the
    // cost around. The profile below was written `estActif: false`, the
    // portal showed the member "Inactif / Acces limite", and it stayed that
    // way even after the password was set -- completing a reset updates
    // Firebase Auth and nothing else. The profile was reconciled only on the
    // member's first mobile sign-in, by the repair callable, so an operator
    // looking at the portal in between saw an account that appeared broken
    // and had no button that would fix it.
    //
    // It grants no new access. The account still holds the random temporary
    // password from createUser, which nobody knows, so the only way in
    // remains the link e-mailed to that same address. What changes is that
    // the verification link is no longer minted at all: setting the password
    // is the single action asked of the member.
    if (!userRecord.emailVerified) {
      userRecord = await auth.updateUser(userRecord.uid, {
        emailVerified: true,
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

    // Last, and after the commit above on purpose. The account exists in Auth
    // and Firestore by now, so a relay that refuses the message costs an
    // e-mail, not a half-created member. sendAccountInviteEmail never throws
    // for the same reason.
    const invite = await sendAccountInviteEmail({
      to: email,
      displayName,
      passwordSetupLink,
    });

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
        inviteEmailSent: invite.sent,
        inviteEmailReason: invite.reason ?? null,
      } satisfies ProvisionedManagedAccount,
    };
  },
);
