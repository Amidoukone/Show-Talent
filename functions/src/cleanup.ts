/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable comma-dangle */

import {pubsub} from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";

// ✅ Import Firebase centralisé
import {db, auth} from "./firebase";

/**
 * Supprime les utilisateurs dont l'adresse email n’a pas été vérifiée après 7 jours.
 * Cette fonction est planifiée pour s'exécuter automatiquement tous les jours.
 */
export const cleanupUnverifiedUsers = pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000); // il y a 7 jours

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
        return null;
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

    return null;
  });
