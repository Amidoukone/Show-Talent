/* eslint-disable linebreak-style */
// eslint-disable-next-line linebreak-style
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */
/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {db, fieldValue} from "./firebase";

const REGION = "europe-west1";

type SuccessResponse<T> = {
  success: true;
  code: string;
  message: string;
  data?: T;
};

type ErrorResponse = {
  success: false;
  code: string;
  message: string;
  retriable?: boolean;
};

type ActionResponse<T> = SuccessResponse<T> | ErrorResponse;

const ok = <T>(code: string, message: string, data?: T): SuccessResponse<T> => ({
  success: true,
  code,
  message,
  data,
});

const err = (code: string, message: string, retriable = false): ErrorResponse => ({
  success: false,
  code,
  message,
  retriable,
});

function assertAuth(uid?: string): asserts uid is string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
}

function getString(data: unknown, key: string): string {
  if (typeof data !== "object" || data === null) return "";
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value.trim() : "";
}

function sanitizeStringArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((v) => String(v));
}

/**
 * Toggle like sur une vidéo en validant l’utilisateur
 */
export const likeVideo = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{liked: boolean; likes: number}>> => {
    const uid = request.auth?.uid;
    assertAuth(uid);

    const videoId = getString(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId manquant.");
    }

    const ref = db.collection("videos").doc(videoId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Vidéo introuvable.");
        }

        const data = snap.data() || {};
        const likes = sanitizeStringArray(data.likes);
        const hasLiked = likes.includes(uid);

        tx.update(
          ref,
          hasLiked ?
            {likes: fieldValue.arrayRemove(uid)} :
            {likes: fieldValue.arrayUnion(uid)}
        );

        return {
          liked: !hasLiked,
          likes: hasLiked ? Math.max(0, likes.length - 1) : likes.length + 1,
        };
      });

      return ok(
        "like-toggled",
        result.liked ? "Like ajouté." : "Like retiré.",
        result
      );
    } catch (error) {
      logger.error("❌ likeVideo error", error);
      if (error instanceof HttpsError) throw error;
      return err("like_failed", "Impossible de traiter le like pour le moment.", true);
    }
  }
);

/**
 * Signaler une vidéo (anti-doublon)
 */
export const reportVideo = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{reportCount: number}>> => {
    const uid = request.auth?.uid;
    assertAuth(uid);

    const videoId = getString(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId manquant.");
    }

    const ref = db.collection("videos").doc(videoId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Vidéo introuvable.");
        }

        const data = snap.data() || {};
        const reports = sanitizeStringArray(data.reports);
        if (reports.includes(uid)) {
          return {
            alreadyReported: true,
            count: reports.length,
          };
        }

        tx.update(ref, {
          reports: fieldValue.arrayUnion(uid),
          reportCount: fieldValue.increment(1),
        });
        return {
          alreadyReported: false,
          count: reports.length + 1,
        };
      });

      if (result.alreadyReported) {
        return err("already_reported", "Tu as déjà signalé cette vidéo.");
      }

      return ok("reported", "Signalement envoyé, merci !", {
        reportCount: result.count,
      });
    } catch (error) {
      logger.error("❌ reportVideo error", error);
      if (error instanceof HttpsError) throw error;
      return err("report_failed", "Impossible d’enregistrer le signalement.", true);
    }
  }
);

/**
 * Suppression d’une vidéo (propriétaire uniquement)
 */
export const deleteVideo = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<null>> => {
    const uid = request.auth?.uid;
    assertAuth(uid);

    const videoId = getString(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId manquant.");
    }

    const ref = db.collection("videos").doc(videoId);
    try {
      const snap = await ref.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Vidéo introuvable.");
      }

      const data = snap.data() || {};
      const ownerId = getString(data, "uid");

      if (ownerId !== uid) {
        throw new HttpsError("permission-denied", "Suppression réservée au propriétaire.");
      }

      await ref.delete();
      return ok("deleted", "Vidéo supprimée.");
    } catch (error) {
      logger.error("❌ deleteVideo error", error);
      if (error instanceof HttpsError) throw error;
      return err("delete_failed", "Suppression impossible pour le moment.", true);
    }
  }
);

/**
 * Réception batch des logs client (niveau info/erreur)
 */
export const logClientEvents = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{count: number}>> => {
    const entries = Array.isArray(request.data?.entries) ? request.data.entries : [];

    if (!entries.length) {
      return ok("noop", "Aucun log reçu.");
    }

    const sanitized = entries
      .slice(0, 50)
      .map((raw: any) => ({
        level: raw?.level === "error" ? "error" : "info",
        source: typeof raw?.source === "string" ? raw.source.slice(0, 120) : "client",
        message: typeof raw?.message === "string" ? raw.message.slice(0, 2000) : "",
        metadata: typeof raw?.metadata === "object" && raw?.metadata ? raw.metadata : {},
        createdAt: raw?.createdAt ? new Date(raw.createdAt) : new Date(),
      }))
      .filter((e: any) => e.message);

    if (!sanitized.length) {
      return ok("noop", "Aucun log exploitable.");
    }

    const batch = db.batch();
    for (const entry of sanitized) {
      const ref = db.collection("client_logs").doc();
      batch.set(ref, {
        ...entry,
        userId: request.auth?.uid || null,
        receivedAt: fieldValue.serverTimestamp(),
        context: request.data?.context || {},
      });
    }

    try {
      await batch.commit();
      return ok("logged", `${sanitized.length} log(s) enregistré(s).`, {
        count: sanitized.length,
      });
    } catch (error) {
      logger.error("❌ logClientEvents error", error);
      return err("log_failed", "Impossible d’enregistrer les logs.", true);
    }
  }
);
