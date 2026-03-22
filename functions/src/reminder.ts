/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable comma-dangle */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {ServerClient} from "postmark";

// ✅ Import Firebase centralisé (inchangé)
import {db, auth} from "./firebase";

/**
 * Rappel d’email de vérification après 3 jours si non vérifié
 */
export const sendVerificationReminder = onSchedule(
  {
    schedule: "every 24 hours",
    region: "europe-west1",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const apiKey = process.env.POSTMARK_API_KEY || process.env.postmark_apikey;

    if (!apiKey) {
      logger.error(
        "🛑 Aucune clé Postmark trouvée. Définis POSTMARK_API_KEY dans les variables d'environnement Firebase."
      );
      return;
    }

    const client = new ServerClient(apiKey);
    const cutoff = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000); // 3 jours

    try {
      const snap = await db
        .collection("users")
        .where("emailVerified", "==", false)
        .where("dateInscription", "<=", cutoff)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const email = data.email as string | undefined;
        const nom = (data.nom as string) || "Utilisateur";

        if (!email) {
          logger.warn(`❌ Email manquant pour l'utilisateur ${doc.id}`);
          continue;
        }

        const link = await auth.generateEmailVerificationLink(email, {
          url: `https://adfoot.org/verify?uid=${doc.id}`,
          handleCodeInApp: false,
        });

        await client.sendEmailWithTemplate({
          From: "amidou@adfoot.org",
          To: email,
          TemplateAlias: "welcome",
          TemplateModel: {
            recipient_name: nom,
            verification_link: link,
            product_name: "Adfoot",
          },
          MessageStream: "outboundTransactional",
        });

        logger.info(`📧 Rappel de vérification envoyé à ${email}`);
      }

      logger.info("✅ Tous les rappels ont été traités avec succès.");
    } catch (error) {
      logger.error("❌ Erreur lors des rappels de vérification :", error);
    }
  }
);
