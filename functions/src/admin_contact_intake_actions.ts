/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db, fieldValue} from "./firebase";
import {
  LOW_CPU_CALLABLE_OPTIONS,
  assertAdminCaller,
  getOptionalString,
  getString,
} from "./admin_account_support";
import {resolveCallableAuth} from "./callable_auth";

const CONTACT_INTAKE_FOLLOW_UP_STATUSES = new Set([
  "new",
  "reviewing",
  "in_progress",
  "qualified",
  "closed",
]);

const CONTACT_INTAKE_PARTICIPANT_FEEDBACK_STATUSES = new Set([
  "no_response",
  "discussion_started",
  "trial_scheduled",
  "opportunity_serious",
  "not_relevant",
  "issue_reported",
]);

function normalizeAgencyFollowUpStatus(rawStatus: string): string {
  switch (rawStatus.trim().toLowerCase()) {
  case "reviewing":
    return "reviewing";
  case "in_progress":
  case "in progress":
    return "in_progress";
  case "qualified":
    return "qualified";
  case "closed":
    return "closed";
  case "new":
  default:
    return "new";
  }
}

function agencyFollowUpLabel(status: string): string {
  switch (normalizeAgencyFollowUpStatus(status)) {
  case "reviewing":
    return "En revue";
  case "in_progress":
    return "En accompagnement";
  case "qualified":
    return "Qualifié";
  case "closed":
    return "Clos";
  case "new":
  default:
    return "Nouveau lead";
  }
}

function normalizeParticipantFeedbackStatus(rawStatus: string): string {
  switch (rawStatus.trim().toLowerCase()) {
  case "discussion_started":
  case "discussion started":
    return "discussion_started";
  case "trial_scheduled":
  case "trial scheduled":
  case "meeting_scheduled":
  case "meeting scheduled":
    return "trial_scheduled";
  case "opportunity_serious":
  case "opportunity serious":
    return "opportunity_serious";
  case "not_relevant":
  case "not relevant":
    return "not_relevant";
  case "issue_reported":
  case "issue reported":
    return "issue_reported";
  case "no_response":
  case "no response":
  default:
    return "no_response";
  }
}

function recommendedFollowUpStatusFromFeedback(status: string): string {
  switch (normalizeParticipantFeedbackStatus(status)) {
  case "discussion_started":
    return "in_progress";
  case "trial_scheduled":
  case "opportunity_serious":
    return "qualified";
  case "not_relevant":
    return "closed";
  case "issue_reported":
    return "reviewing";
  case "no_response":
  default:
    return "reviewing";
  }
}

function resolveParticipantRole(
  intakeData: FirebaseFirestore.DocumentData,
  uid: string,
): string {
  if (intakeData["requesterUid"] === uid) {
    return typeof intakeData["requesterRole"] === "string" ?
      intakeData["requesterRole"].trim() :
      "requester";
  }
  if (intakeData["targetUid"] === uid) {
    return typeof intakeData["targetRole"] === "string" ?
      intakeData["targetRole"].trim() :
      "target";
  }
  return "participant";
}

function assertCanSubmitParticipantFeedback(
  intakeData: FirebaseFirestore.DocumentData,
  uid: string,
): void {
  if (intakeData["requesterUid"] === uid || intakeData["targetUid"] === uid) {
    return;
  }

  throw new HttpsError(
    "permission-denied",
    "Seuls les participants de la mise en relation peuvent envoyer un retour.",
  );
}

function readString(
  data: FirebaseFirestore.DocumentData,
  key: string,
): string {
  const value = data[key];
  return typeof value === "string" ? value.trim() : "";
}

function readParticipants(
  data: FirebaseFirestore.DocumentData,
): string[] {
  const rawParticipants = data["utilisateurIds"];
  if (!Array.isArray(rawParticipants)) {
    return [];
  }

  return rawParticipants
    .map((value) => typeof value === "string" ? value.trim() : "")
    .filter((value) => value.length > 0);
}

async function deleteDocsInChunks(
  refs: readonly FirebaseFirestore.DocumentReference[],
): Promise<number> {
  const chunkSize = 400;
  for (let index = 0; index < refs.length; index += chunkSize) {
    const batch = db.batch();
    const chunk = refs.slice(index, index + chunkSize);
    for (const ref of chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }

  return refs.length;
}

async function clearActiveConversationForParticipants(
  participants: readonly string[],
  conversationId: string,
): Promise<number> {
  let clearedCount = 0;

  for (const uid of participants) {
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      continue;
    }

    const userData = userSnap.data() ?? {};
    if (readString(userData, "activeConversationId") !== conversationId) {
      continue;
    }

    await userRef.set({
      activeConversationId: null,
      activeAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, {merge: true});
    clearedCount += 1;
  }

  return clearedCount;
}

async function deleteLinkedContactIntakeConversation({
  contactIntakeId,
  intakeData,
  requestedConversationId,
}: {
  contactIntakeId: string;
  intakeData: FirebaseFirestore.DocumentData;
  requestedConversationId: string;
}): Promise<{
  conversationId: string;
  conversationDeleted: boolean;
  deletedMessageCount: number;
  activeConversationClearedCount: number;
}> {
  const linkedConversationId = readString(intakeData, "conversationId");
  if (
    requestedConversationId &&
    linkedConversationId &&
    requestedConversationId !== linkedConversationId
  ) {
    throw new HttpsError(
      "failed-precondition",
      "La conversation demandée ne correspond pas à cette mise en relation.",
    );
  }

  const conversationId = linkedConversationId || requestedConversationId;
  if (!conversationId) {
    return {
      conversationId: "",
      conversationDeleted: false,
      deletedMessageCount: 0,
      activeConversationClearedCount: 0,
    };
  }

  const conversationRef = db.collection("conversations").doc(conversationId);
  const conversationSnap = await conversationRef.get();
  if (!conversationSnap.exists) {
    return {
      conversationId,
      conversationDeleted: false,
      deletedMessageCount: 0,
      activeConversationClearedCount: 0,
    };
  }

  const conversationData = conversationSnap.data() ?? {};
  const linkedIntakeId = readString(conversationData, "contactIntakeId");
  if (linkedIntakeId && linkedIntakeId !== contactIntakeId) {
    throw new HttpsError(
      "failed-precondition",
      "Cette conversation est liée à une autre mise en relation.",
    );
  }

  const participants = readParticipants(conversationData);
  const messageSnapshot = await conversationRef.collection("messages").get();
  const deletedMessageCount = await deleteDocsInChunks(
    messageSnapshot.docs.map((doc) => doc.ref),
  );
  await conversationRef.delete();
  const activeConversationClearedCount =
    await clearActiveConversationForParticipants(
      participants,
      conversationId,
    );

  return {
    conversationId,
    conversationDeleted: true,
    deletedMessageCount,
    activeConversationClearedCount,
  };
}

async function buildUserSnapshot(uid: string): Promise<Record<string, string>> {
  const snap = await db.collection("users").doc(uid).get();
  const data = snap.exists ? snap.data() ?? {} : {};
  const firstName = readString(data, "prenom");
  const lastName = readString(data, "nom");
  const displayName = readString(data, "displayName") ||
    [firstName, lastName].filter((value) => value.length > 0).join(" ") ||
    lastName ||
    uid;
  const organization = readString(data, "organisation") ||
    readString(data, "organization") ||
    readString(data, "club") ||
    readString(data, "nomClub") ||
    readString(data, "entreprise");
  const snapshot: Record<string, string> = {
    uid,
    displayName,
  };

  for (const [key, value] of Object.entries({
    prenom: firstName,
    nom: lastName,
    role: readString(data, "role"),
    email: readString(data, "email"),
    organisation: organization,
    photoProfil: readString(data, "photoProfil"),
  })) {
    if (value.length > 0) {
      snapshot[key] = value;
    }
  }

  return snapshot;
}

async function recoverMissingContactIntakeFromConversation({
  contactIntakeId,
  conversationId,
  uid,
}: {
  contactIntakeId: string;
  conversationId: string;
  uid: string;
}): Promise<{
  intakeRef: FirebaseFirestore.DocumentReference;
  intakeData: FirebaseFirestore.DocumentData;
  conversationId: string;
} | null> {
  if (!conversationId) {
    return null;
  }

  const conversationRef = db.collection("conversations").doc(conversationId);
  const conversationSnap = await conversationRef.get();
  if (!conversationSnap.exists) {
    return null;
  }

  const conversationData = conversationSnap.data() ?? {};
  const participants = readParticipants(conversationData);
  if (!participants.includes(uid)) {
    throw new HttpsError(
      "permission-denied",
      "Seuls les participants de la conversation peuvent restaurer cette mise en relation.",
    );
  }
  if (participants.length < 2) {
    return null;
  }

  const linkedIntakeId = readString(conversationData, "contactIntakeId");
  if (linkedIntakeId && linkedIntakeId !== contactIntakeId) {
    const linkedIntakeRef = db.collection("contact_intakes").doc(linkedIntakeId);
    const linkedIntakeSnap = await linkedIntakeRef.get();
    if (linkedIntakeSnap.exists) {
      return {
        intakeRef: linkedIntakeRef,
        intakeData: linkedIntakeSnap.data() ?? {},
        conversationId,
      };
    }
  }

  const requesterCandidate = readString(conversationData, "initiatedByUid");
  const requesterUid = participants.includes(requesterCandidate) ?
    requesterCandidate :
    participants[0];
  const targetUid = participants.find((participant) => participant !== requesterUid);
  if (!targetUid) {
    return null;
  }

  const [requesterSnapshot, targetSnapshot] = await Promise.all([
    buildUserSnapshot(requesterUid),
    buildUserSnapshot(targetUid),
  ]);
  const intakeRef = db.collection("contact_intakes").doc(contactIntakeId);
  const recoveredData = {
    id: contactIntakeId,
    requesterUid,
    targetUid,
    requesterRole: readString(conversationData, "initiatedByRole") ||
      requesterSnapshot["role"] ||
      "",
    targetRole: targetSnapshot["role"] || "",
    contextType: readString(conversationData, "contextType") || "none",
    contextId: readString(conversationData, "contextId"),
    contextTitle: readString(conversationData, "contextTitle"),
    contactReason: readString(conversationData, "contactReason") || "information",
    introMessage: readString(conversationData, "lastMessage") ||
      "Mise en relation restaurée depuis la conversation.",
    status: "new",
    agencyFollowUpStatus: normalizeAgencyFollowUpStatus(
      readString(conversationData, "agencyFollowUpStatus"),
    ),
    conversationId,
    requesterSnapshot,
    targetSnapshot,
    createdAt: conversationData["createdAt"] ?? fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
  };

  await intakeRef.set(recoveredData, {merge: true});
  await conversationRef.set({
    contactIntakeId,
    agencyFollowUpStatus: recoveredData.agencyFollowUpStatus,
    updatedAt: fieldValue.serverTimestamp(),
    lastUpdated: fieldValue.serverTimestamp(),
  }, {merge: true});

  logger.info("missing contact intake recovered from conversation", {
    contactIntakeId,
    conversationId,
    recoveredBy: uid,
    requesterUid,
    targetUid,
  });

  return {
    intakeRef,
    intakeData: recoveredData,
    conversationId,
  };
}

export const submitContactIntakeFeedback = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const {uid} = await resolveCallableAuth(request);
    const contactIntakeId =
      getString(request.data, "contactIntakeId") ||
      getString(request.data, "id");
    if (!contactIntakeId) {
      throw new HttpsError(
        "invalid-argument",
        "contactIntakeId est requis.",
      );
    }

    const rawStatus = getString(request.data, "status");
    if (!rawStatus) {
      throw new HttpsError("invalid-argument", "status est requis.");
    }

    const status = normalizeParticipantFeedbackStatus(rawStatus);
    if (!CONTACT_INTAKE_PARTICIPANT_FEEDBACK_STATUSES.has(status)) {
      throw new HttpsError(
        "invalid-argument",
        "Statut de retour invalide.",
      );
    }

    const note = getOptionalString(request.data, "note");
    const requestedConversationId =
      getOptionalString(request.data, "conversationId") ?? "";
    if (note && note.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "Le retour ne doit pas dépasser 500 caractères.",
      );
    }

    if (status === "issue_reported" && (!note || note.length < 8)) {
      throw new HttpsError(
        "invalid-argument",
        "Ajoutez une note pour décrire le problème signalé.",
      );
    }

    try {
      let intakeRef = db.collection("contact_intakes").doc(contactIntakeId);
      const intakeSnap = await intakeRef.get();
      let intakeData = intakeSnap.data() ?? {};
      let recoveredConversationId = "";
      if (!intakeSnap.exists) {
        const recovered = await recoverMissingContactIntakeFromConversation({
          contactIntakeId,
          conversationId: requestedConversationId,
          uid,
        });
        if (!recovered) {
          throw new HttpsError("not-found", "Mise en relation introuvable.");
        }
        intakeRef = recovered.intakeRef;
        intakeData = recovered.intakeData;
        recoveredConversationId = recovered.conversationId;
      }

      assertCanSubmitParticipantFeedback(intakeData, uid);

      const conversationId =
        typeof intakeData["conversationId"] === "string" ?
          intakeData["conversationId"].trim() :
          recoveredConversationId;
      const participantRole = resolveParticipantRole(intakeData, uid);
      const suggestedStatus = recommendedFollowUpStatusFromFeedback(status);
      const feedbackPayload = {
        uid,
        role: participantRole,
        status,
        note: note ?? "",
        submittedAt: fieldValue.serverTimestamp(),
      };
      const sharedPatch = {
        latestParticipantFeedbackStatus: status,
        latestParticipantFeedbackNote: note ?? "",
        latestParticipantFeedbackByUid: uid,
        latestParticipantFeedbackByRole: participantRole,
        latestParticipantFeedbackAt: fieldValue.serverTimestamp(),
        suggestedAgencyFollowUpStatus: suggestedStatus,
        updatedAt: fieldValue.serverTimestamp(),
      };

      await intakeRef.set({
        ...sharedPatch,
        participantFeedbackByUid: {
          [uid]: feedbackPayload,
        },
      }, {merge: true});

      let conversationSynced = false;
      if (conversationId) {
        const conversationRef = db.collection("conversations").doc(conversationId);
        const conversationSnap = await conversationRef.get();
        if (conversationSnap.exists) {
          await conversationRef.set({
            ...sharedPatch,
            lastUpdated: fieldValue.serverTimestamp(),
          }, {merge: true});
          conversationSynced = true;
        }
      }

      logger.info("contact intake participant feedback submitted", {
        contactIntakeId: intakeRef.id,
        submittedBy: uid,
        status,
        suggestedStatus,
        conversationId: conversationId || null,
        conversationSynced,
      });

      return {
        success: true,
        code: "contact_intake_feedback_submitted",
        message: "Retour de mise en relation enregistré.",
        data: {
          contactIntakeId: intakeRef.id,
          status,
          suggestedAgencyFollowUpStatus: suggestedStatus,
          submittedBy: uid,
          conversationId: conversationId || null,
          conversationSynced,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("contact intake participant feedback failed", {
        contactIntakeId,
        submittedBy: uid,
        status,
        error,
      });
      throw new HttpsError(
        "internal",
        "Retour de mise en relation impossible pour le moment.",
      );
    }
  },
);

export const adminSetContactIntakeFollowUp = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const contactIntakeId =
      getString(request.data, "contactIntakeId") ||
      getString(request.data, "id");
    if (!contactIntakeId) {
      throw new HttpsError(
        "invalid-argument",
        "contactIntakeId est requis.",
      );
    }

    const rawStatus = getString(request.data, "status");
    if (!rawStatus) {
      throw new HttpsError("invalid-argument", "status est requis.");
    }

    const status = normalizeAgencyFollowUpStatus(rawStatus);
    if (!CONTACT_INTAKE_FOLLOW_UP_STATUSES.has(status)) {
      throw new HttpsError(
        "invalid-argument",
        "Statut de suivi invalide. Valeurs : new, reviewing, in_progress, qualified, closed.",
      );
    }

    const note = getOptionalString(request.data, "note");
    if (note && note.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "La note de suivi ne doit pas dépasser 500 caractères.",
      );
    }

    try {
      const intakeRef = db.collection("contact_intakes").doc(contactIntakeId);
      const intakeSnap = await intakeRef.get();
      if (!intakeSnap.exists) {
        throw new HttpsError("not-found", "Prise de contact introuvable.");
      }

      const intakeData = intakeSnap.data() ?? {};
      const conversationId =
        typeof intakeData["conversationId"] === "string" ?
          intakeData["conversationId"].trim() :
          "";

      await intakeRef.set({
        agencyFollowUpStatus: status,
        agencyFollowUpNote: note ?? fieldValue.delete(),
        agencyLastUpdatedByUid: adminUid,
        agencyLastUpdatedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      }, {merge: true});

      let conversationSynced = false;
      if (conversationId) {
        const conversationRef = db.collection("conversations").doc(conversationId);
        const conversationSnap = await conversationRef.get();

        if (conversationSnap.exists) {
          await conversationRef.set({
            agencyFollowUpStatus: status,
            updatedAt: fieldValue.serverTimestamp(),
            lastUpdated: fieldValue.serverTimestamp(),
          }, {merge: true});
          conversationSynced = true;
        }
      }

      logger.info("admin contact intake follow-up updated", {
        contactIntakeId,
        status,
        updatedBy: adminUid,
        conversationId: conversationId || null,
        conversationSynced,
      });

      return {
        success: true,
        code: "contact_intake_follow_up_updated",
        message: `Suivi agence mis à jour : ${agencyFollowUpLabel(status)}.`,
        data: {
          contactIntakeId,
          status,
          updatedBy: adminUid,
          conversationId: conversationId || null,
          conversationSynced,
          note: note ?? null,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin contact intake follow-up failed", {
        contactIntakeId,
        status,
        updatedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Mise à jour du suivi agence impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteContactIntakeConversation = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const contactIntakeId =
      getString(request.data, "contactIntakeId") ||
      getString(request.data, "id");
    if (!contactIntakeId) {
      throw new HttpsError(
        "invalid-argument",
        "contactIntakeId est requis.",
      );
    }

    const requestedConversationId =
      getOptionalString(request.data, "conversationId") ?? "";

    try {
      const intakeRef = db.collection("contact_intakes").doc(contactIntakeId);
      const intakeSnap = await intakeRef.get();
      if (!intakeSnap.exists) {
        throw new HttpsError("not-found", "Mise en relation introuvable.");
      }

      const deletion = await deleteLinkedContactIntakeConversation({
        contactIntakeId,
        intakeData: intakeSnap.data() ?? {},
        requestedConversationId,
      });

      await intakeRef.set({
        conversationId: fieldValue.delete(),
        conversationDeletedAt: fieldValue.serverTimestamp(),
        conversationDeletedByUid: adminUid,
        updatedAt: fieldValue.serverTimestamp(),
      }, {merge: true});

      logger.info("admin contact intake conversation deleted", {
        contactIntakeId,
        conversationId: deletion.conversationId || null,
        deletedBy: adminUid,
        conversationDeleted: deletion.conversationDeleted,
        deletedMessageCount: deletion.deletedMessageCount,
        activeConversationClearedCount:
          deletion.activeConversationClearedCount,
      });

      return {
        success: true,
        code: deletion.conversationDeleted ?
          "contact_intake_conversation_deleted" :
          "contact_intake_conversation_not_found",
        message: deletion.conversationDeleted ?
          "Conversation supprimée. Le suivi admin reste conservé." :
          "Aucune conversation active à supprimer. Le suivi admin a été mis à jour.",
        data: {
          contactIntakeId,
          conversationId: deletion.conversationId || null,
          deletedBy: adminUid,
          conversationDeleted: deletion.conversationDeleted,
          deletedMessageCount: deletion.deletedMessageCount,
          activeConversationClearedCount:
            deletion.activeConversationClearedCount,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin contact intake conversation deletion failed", {
        contactIntakeId,
        conversationId: requestedConversationId || null,
        deletedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Suppression de la conversation impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteContactIntake = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const contactIntakeId =
      getString(request.data, "contactIntakeId") ||
      getString(request.data, "id");
    if (!contactIntakeId) {
      throw new HttpsError(
        "invalid-argument",
        "contactIntakeId est requis.",
      );
    }

    const requestedConversationId =
      getOptionalString(request.data, "conversationId") ?? "";

    try {
      const intakeRef = db.collection("contact_intakes").doc(contactIntakeId);
      const intakeSnap = await intakeRef.get();
      if (!intakeSnap.exists) {
        return {
          success: true,
          code: "contact_intake_already_deleted",
          message: "Mise en relation déjà supprimée.",
          data: {
            contactIntakeId,
            deletedBy: adminUid,
            alreadyDeleted: true,
            conversationId: requestedConversationId || null,
            conversationDeleted: false,
            deletedMessageCount: 0,
            activeConversationClearedCount: 0,
          },
        };
      }

      const deletion = await deleteLinkedContactIntakeConversation({
        contactIntakeId,
        intakeData: intakeSnap.data() ?? {},
        requestedConversationId,
      });

      await intakeRef.delete();

      logger.info("admin contact intake deleted", {
        contactIntakeId,
        conversationId: deletion.conversationId || null,
        deletedBy: adminUid,
        conversationDeleted: deletion.conversationDeleted,
        deletedMessageCount: deletion.deletedMessageCount,
        activeConversationClearedCount:
          deletion.activeConversationClearedCount,
      });

      return {
        success: true,
        code: "contact_intake_deleted",
        message: deletion.conversationDeleted ?
          "Mise en relation supprimée avec sa conversation." :
          "Mise en relation supprimée. Aucune conversation active n'était liée.",
        data: {
          contactIntakeId,
          deletedBy: adminUid,
          alreadyDeleted: false,
          conversationId: deletion.conversationId || null,
          conversationDeleted: deletion.conversationDeleted,
          deletedMessageCount: deletion.deletedMessageCount,
          activeConversationClearedCount:
            deletion.activeConversationClearedCount,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin contact intake deletion failed", {
        contactIntakeId,
        conversationId: requestedConversationId || null,
        deletedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Suppression de la mise en relation impossible pour le moment.",
      );
    }
  },
);
