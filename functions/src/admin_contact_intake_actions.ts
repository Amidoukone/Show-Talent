/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db, fieldValue} from "./firebase";
import {
  LOW_CPU_REGION_OPTIONS,
  assertAdminCaller,
  getOptionalString,
  getString,
} from "./admin_account_support";

const CONTACT_INTAKE_FOLLOW_UP_STATUSES = new Set([
  "new",
  "reviewing",
  "in_progress",
  "qualified",
  "closed",
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

export const adminSetContactIntakeFollowUp = onCall(
  LOW_CPU_REGION_OPTIONS,
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
        "Statut de suivi invalide. Valeurs: new, reviewing, in_progress, qualified, closed.",
      );
    }

    const note = getOptionalString(request.data, "note");
    if (note && note.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "La note de suivi ne doit pas depasser 500 caracteres.",
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
        message: `Suivi agence mis a jour: ${status}.`,
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
        "Mise a jour du suivi agence impossible pour le moment.",
      );
    }
  },
);
