/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable comma-dangle */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

// ✅ Import Firebase centralisé (inchangé)
import {db, auth} from "./firebase";

/**
 * Supprime les utilisateurs dont l'adresse email n’a pas été vérifiée après 7 jours.
 * Exécution quotidienne.
 */
export const cleanupUnverifiedUsers = onSchedule(
  {
    schedule: "every 24 hours",
    region: "europe-west1",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    try {
      const snapshot = await db
        .collection("users")
        .where("emailVerified", "==", false)
        .where("dateInscription", "<=", cutoff)
        .get();

      const total = snapshot.size;
      logger.info(`🔍 ${total} utilisateur(s) non vérifiés à analyser.`);

      if (total === 0) {
        logger.info("✅ Aucun utilisateur à supprimer aujourd’hui.");
        return;
      }

      for (const doc of snapshot.docs) {
        const uid = doc.id;

        try {
          await auth.deleteUser(uid);
          await db.collection("users").doc(uid).delete();
          logger.info(`🗑️ Utilisateur supprimé : ${uid}`);
        } catch (error) {
          logger.error(`❌ Échec suppression utilisateur ${uid} :`, error);
        }
      }

      logger.info("✅ Opération de nettoyage terminée.");
    } catch (err) {
      logger.error("❌ Erreur globale pendant le nettoyage :", err);
    }
  }
);
