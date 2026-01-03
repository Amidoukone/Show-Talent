/* eslint-disable linebreak-style */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable require-jsdoc */
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

function getNumber(data: unknown, key: string): number {
  if (typeof data !== "object" || data === null) return 0;
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "number" ? value : 0;
}

function timestampToMillis(value: unknown): number {
  if (!value) return 0;
  const candidate = value as any;
  if (typeof candidate.toMillis === "function") {
    return Number(candidate.toMillis()) || 0;
  }
  return 0;
}

function safeJson(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null) return {};
  try {
    return JSON.parse(JSON.stringify(value));
  } catch (e) {
    logger.warn("⚠️ safeJson fallback:", (e as Error).message);
    return {};
  }
}

/**
 * Toggle like sur une vidéo
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
 * Signaler une vidéo
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
          return {alreadyReported: true, count: reports.length};
        }

        tx.update(ref, {
          reports: fieldValue.arrayUnion(uid),
          reportCount: fieldValue.increment(1),
        });

        return {alreadyReported: false, count: reports.length + 1};
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
 * Suppression d’une vidéo
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
 * Enregistrement du partage (auth + anti-spam)
 */
export const shareVideo = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{shareCount: number}>> => {
    const uid = request.auth?.uid;
    assertAuth(uid);

    const videoId = getString(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId manquant.");
    }

    const now = Date.now();
    const throttleMs = 15_000;

    const videoRef = db.collection("videos").doc(videoId);
    const throttleRef =
      db.collection("video_share_limits").doc(`${videoId}_${uid}`);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(videoRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Vidéo introuvable.");
        }

        const shareSnap = await tx.get(throttleRef);
        const shareData = shareSnap.data() || {};
        const lastShareMs = timestampToMillis(shareData.lastShare);

        if (lastShareMs && now - lastShareMs < throttleMs) {
          const remaining =
            Math.ceil((throttleMs - (now - lastShareMs)) / 1000);
          throw new HttpsError(
            "resource-exhausted",
            `Partage trop fréquent. Réessaie dans ${remaining}s.`
          );
        }

        const videoData = snap.data() || {};
        const currentShareCount = getNumber(videoData, "shareCount");

        tx.update(videoRef, {shareCount: fieldValue.increment(1)});
        tx.set(
          throttleRef,
          {
            videoId,
            userId: uid,
            lastShare: fieldValue.serverTimestamp(),
            count: fieldValue.increment(1),
            updatedAt: fieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        return {shareCount: currentShareCount + 1};
      });

      return ok("shared", "Partage enregistré.", result);
    } catch (error) {
      logger.error("❌ shareVideo error", error);
      if (error instanceof HttpsError) throw error;
      return err("share_failed", "Impossible d’enregistrer le partage.", true);
    }
  }
);

/**
 * Réception batch des logs client
 */
export const logClientEvents = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{count: number}>> => {
    const entries = Array.isArray(request.data?.entries) ?
      request.data.entries :
      [];

    if (!entries.length) {
      return ok("noop", "Aucun log reçu.");
    }

    const sanitized = entries
      .slice(0, 50)
      .map((raw: any) => ({
        level: raw?.level === "error" ? "error" : "info",
        source:
          typeof raw?.source === "string" ?
            raw.source.slice(0, 120) :
            "client",
        message:
          typeof raw?.message === "string" ?
            raw.message.slice(0, 2000) :
            "",
        metadata:
          typeof raw?.metadata === "object" && raw?.metadata ?
            raw.metadata :
            {},
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

/**
 * Centralisation des erreurs/actions vidéo
 */
export const videoActionLog = onCall(
  {region: REGION},
  async (request): Promise<ActionResponse<{logged: boolean}>> => {
    const action = getString(request.data, "action");
    if (!action) {
      throw new HttpsError("invalid-argument", "action manquant.");
    }

    const payload = {
      action,
      videoId: getString(request.data, "videoId") || null,
      status: getString(request.data, "status") || "failure",
      code: getString(request.data, "code") || null,
      message: getString(request.data, "message").slice(0, 500),
      extra: safeJson(request.data?.extra),
      platform: getString(request.data, "platform") || "client",
      userId: request.auth?.uid || null,
      createdAt: fieldValue.serverTimestamp(),
    };

    try {
      await db.collection("video_action_logs").add(payload);
      return ok("logged", "Log enregistré.", {logged: true});
    } catch (error) {
      logger.error("❌ videoActionLog error", error);
      return err("log_failed", "Impossible d’enregistrer le log.", true);
    }
  }
);
