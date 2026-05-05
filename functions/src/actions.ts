/* eslint-disable linebreak-style */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable require-jsdoc */
/* eslint-disable max-len */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {db, fieldValue, messaging, storage} from "./firebase";
import {LOW_CPU_CALLABLE_OPTIONS} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";

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
type FanoutStats = {targeted: number; sent: number; failed: number};

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

type AuthenticatedCallableRequestLike = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
};

async function requireAuth(
  request: AuthenticatedCallableRequestLike,
): Promise<string> {
  const {uid} = await resolveCallableAuth(request);
  return uid;
}

function getString(data: unknown, key: string): string {
  if (typeof data !== "object" || data === null) return "";
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value.trim() : "";
}

function getNestedString(data: unknown, path: string): string {
  if (typeof data !== "object" || data === null) return "";
  const parts = path.split(".").filter(Boolean);
  let current: unknown = data;

  for (const part of parts) {
    if (typeof current !== "object" || current === null) return "";
    current = (current as Record<string, unknown>)[part];
  }

  return typeof current === "string" ? current.trim() : "";
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

function getSafeStoragePath(
  rawPath: unknown,
  options: {prefix: string; videoId: string}
): string | null {
  if (typeof rawPath !== "string") return null;

  const normalized = rawPath.trim().replace(/^\/+/, "");
  if (!normalized || normalized.includes("..")) return null;
  if (!normalized.startsWith(options.prefix)) return null;
  if (!normalized.includes(options.videoId)) return null;

  return normalized;
}

function collectOwnedVideoAssetPaths(
  videoId: string,
  data: Record<string, unknown>
): string[] {
  const paths = new Set<string>([
    `videos/${videoId}.mp4`,
    `thumbnails/thumbnail_${videoId}.jpg`,
    `thumbnails/thumbnail_${videoId}.jpeg`,
    `thumbnails/thumbnail_${videoId}.png`,
  ]);

  const storagePath = getSafeStoragePath(data.storagePath, {
    prefix: "videos/",
    videoId,
  });
  if (storagePath) {
    paths.add(storagePath);
  }

  const thumbnailPath = getSafeStoragePath(data.thumbnailPath, {
    prefix: "thumbnails/",
    videoId,
  });
  if (thumbnailPath) {
    paths.add(thumbnailPath);
  }

  return Array.from(paths);
}

async function deleteStorageObjectIfExists(path: string): Promise<void> {
  try {
    await storage.bucket().file(path).delete();
  } catch (error) {
    const code = (error as {code?: number | string}).code;
    if (code === 404 || code === "404") {
      return;
    }
    throw error;
  }
}

async function cleanupVideoAssets(
  videoId: string,
  data: Record<string, unknown>
): Promise<void> {
  const paths = collectOwnedVideoAssetPaths(videoId, data);

  for (const path of paths) {
    try {
      await deleteStorageObjectIfExists(path);
    } catch (error) {
      logger.warn("⚠️ deleteVideo asset cleanup skipped", {
        videoId,
        path,
        error: (error as Error).message || String(error),
      });
    }
  }
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

function chunkArray<T>(items: T[], size: number): T[][] {
  if (size <= 0) return [items];
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

function clampSampleRate(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  if (parsed <= 0) return 0;
  if (parsed >= 1) return 1;
  return parsed;
}

const videoManagerInfoLogSampleRate = clampSampleRate(
  process.env.VIDEO_MANAGER_INFO_LOG_SAMPLE_RATE,
  0,
);

function shouldPersistClientLog(entry: {level: string; source: string}): boolean {
  if (entry.source !== "video_manager") return true;
  if (entry.level === "error") return true;
  return Math.random() < videoManagerInfoLogSampleRate;
}

/**
 * Toggle like sur une vidéo
 */
export const likeVideo = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{liked: boolean; likes: number}>> => {
    const uid = await requireAuth(request);

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
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{reportCount: number}>> => {
    const uid = await requireAuth(request);

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
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<null>> => {
    const uid = await requireAuth(request);

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

      const data = (snap.data() || {}) as Record<string, unknown>;
      const ownerId = getString(data, "uid");

      if (ownerId !== uid) {
        throw new HttpsError("permission-denied", "Suppression réservée au propriétaire.");
      }

      await ref.delete();
      await cleanupVideoAssets(videoId, data);
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
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{shareCount: number}>> => {
    const uid = await requireAuth(request);

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
/**
 * @param {string} senderUid UID de l'expéditeur
 * @param {string} recipientUid UID du destinataire
 * @param {string} contextType Type de contexte (message/offre/event)
 * @param {string} contextData ID du contexte
 * @return {Promise<void>}
 */
async function assertPushPermission(
  senderUid: string,
  recipientUid: string,
  contextType: string,
  contextData: string
): Promise<void> {
  if (recipientUid === senderUid) {
    throw new HttpsError("invalid-argument", "recipientUid invalide.");
  }

  if (contextType === "message") {
    const convSnap = await db.collection("conversations").doc(contextData).get();
    if (!convSnap.exists) {
      throw new HttpsError("not-found", "Conversation introuvable.");
    }

    const ids = sanitizeStringArray(convSnap.data()?.utilisateurIds);
    if (!ids.includes(senderUid) || !ids.includes(recipientUid)) {
      throw new HttpsError(
        "permission-denied",
        "Envoi interdit pour cette conversation."
      );
    }
    return;
  }

  if (contextType === "offre") {
    await assertOfferOwner(senderUid, contextData);
    return;
  }

  if (contextType === "event") {
    await assertEventOwner(senderUid, contextData);
    return;
  }

  throw new HttpsError("invalid-argument", "contextType invalide.");
}

async function assertOfferOwner(senderUid: string, offerId: string): Promise<void> {
  const offerSnap = await db.collection("offres").doc(offerId).get();
  if (!offerSnap.exists) {
    throw new HttpsError("not-found", "Offre introuvable.");
  }

  const ownerId = getNestedString(offerSnap.data(), "recruteur.uid");
  if (ownerId !== senderUid) {
    throw new HttpsError(
      "permission-denied",
      "Seul le recruteur de l'offre peut notifier."
    );
  }
}

async function assertEventOwner(senderUid: string, eventId: string): Promise<void> {
  const eventSnap = await db.collection("events").doc(eventId).get();
  if (!eventSnap.exists) {
    throw new HttpsError("not-found", "Evenement introuvable.");
  }

  const ownerId = getNestedString(eventSnap.data(), "organisateur.uid");
  if (ownerId !== senderUid) {
    throw new HttpsError(
      "permission-denied",
      "Seul l'organisateur peut notifier."
    );
  }
}

async function listPlayerTokens(excludedUid: string): Promise<string[]> {
  const usersSnap = await db
    .collection("users")
    .where("role", "==", "joueur")
    .select("fcmToken")
    .get();

  const uniqueTokens = new Set<string>();
  for (const doc of usersSnap.docs) {
    if (doc.id === excludedUid) continue;
    const token = getString(doc.data(), "fcmToken");
    if (token) uniqueTokens.add(token);
  }

  return Array.from(uniqueTokens);
}

async function sendFanoutToPlayers(params: {
  senderUid: string;
  title: string;
  body: string;
  contextType: "offre" | "event";
  contextData: string;
}): Promise<FanoutStats> {
  const tokens = await listPlayerTokens(params.senderUid);
  if (!tokens.length) {
    return {targeted: 0, sent: 0, failed: 0};
  }

  let sent = 0;
  let failed = 0;

  for (const tokenChunk of chunkArray(tokens, 500)) {
    const response = await messaging.sendEachForMulticast({
      tokens: tokenChunk,
      notification: {
        title: params.title,
        body: params.body,
      },
      data: {
        type: params.contextType,
        id: params.contextData,
        senderId: params.senderUid,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "high_importance_channel",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    sent += response.successCount;
    failed += response.failureCount;
  }

  return {
    targeted: tokens.length,
    sent,
    failed,
  };
}

/**
 * Envoi push securise via backend (plus de cle privee cote client)
 */
export const sendUserPush = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{sent: boolean}>> => {
    const uid = await requireAuth(request);

    const recipientUid = getString(request.data, "recipientUid");
    const contextType = getString(request.data, "contextType");
    const contextData = getString(request.data, "contextData");
    const title = getString(request.data, "title").slice(0, 120);
    const body = getString(request.data, "body").slice(0, 300);

    if (!recipientUid || !contextType || !contextData || !title || !body) {
      throw new HttpsError("invalid-argument", "Paramètres push invalides.");
    }

    await assertPushPermission(uid, recipientUid, contextType, contextData);

    const userSnap = await db.collection("users").doc(recipientUid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Destinataire introuvable.");
    }

    const token = getString(userSnap.data(), "fcmToken");
    if (!token) {
      return err("token_missing", "Destinataire sans token FCM.");
    }

    try {
      await messaging.send({
        token,
        notification: {title, body},
        data: {
          type: contextType,
          id: contextData,
          senderId: uid,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "high_importance_channel",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      return ok("sent", "Notification envoyée.", {sent: true});
    } catch (error) {
      logger.error("❌ sendUserPush error", error);
      return err("push_failed", "Échec envoi notification.", true);
    }
  }
);

export const sendOfferFanout = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<FanoutStats>> => {
    const uid = await requireAuth(request);

    const offerId = getString(request.data, "offerId");
    if (!offerId) {
      throw new HttpsError("invalid-argument", "offerId manquant.");
    }

    await assertOfferOwner(uid, offerId);

    const title =
      getString(request.data, "title").slice(0, 120) ||
      "Nouvelle offre disponible";
    const body =
      getString(request.data, "body").slice(0, 300) ||
      "Une nouvelle offre a ete publiee.";

    try {
      const stats = await sendFanoutToPlayers({
        senderUid: uid,
        title,
        body,
        contextType: "offre",
        contextData: offerId,
      });
      return ok("fanout_sent", "Notifications offre envoyees.", stats);
    } catch (error) {
      logger.error("❌ sendOfferFanout error", error);
      return err("fanout_failed", "Echec fanout offre.", true);
    }
  }
);

export const sendEventFanout = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<FanoutStats>> => {
    const uid = await requireAuth(request);

    const eventId = getString(request.data, "eventId");
    if (!eventId) {
      throw new HttpsError("invalid-argument", "eventId manquant.");
    }

    await assertEventOwner(uid, eventId);

    const title =
      getString(request.data, "title").slice(0, 120) ||
      "Nouvel evenement";
    const body =
      getString(request.data, "body").slice(0, 300) ||
      "Un nouvel evenement est disponible.";

    try {
      const stats = await sendFanoutToPlayers({
        senderUid: uid,
        title,
        body,
        contextType: "event",
        contextData: eventId,
      });
      return ok("fanout_sent", "Notifications evenement envoyees.", stats);
    } catch (error) {
      logger.error("❌ sendEventFanout error", error);
      return err("fanout_failed", "Echec fanout evenement.", true);
    }
  }
);

export const logClientEvents = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{count: number}>> => {
    const uid = await requireAuth(request);

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

    const persisted = sanitized.filter(shouldPersistClientLog);
    if (!persisted.length) {
      return ok("noop", "Tous les logs ont ete echantillonnes.");
    }

    const batch = db.batch();
    for (const entry of persisted) {
      const ref = db.collection("client_logs").doc();
      batch.set(ref, {
        ...entry,
        userId: uid,
        receivedAt: fieldValue.serverTimestamp(),
        context: request.data?.context || {},
      });
    }

    try {
      await batch.commit();
      return ok("logged", `${persisted.length} log(s) enregistré(s).`, {
        count: persisted.length,
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
  LOW_CPU_CALLABLE_OPTIONS,
  async (request): Promise<ActionResponse<{logged: boolean}>> => {
    const uid = await requireAuth(request);

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
      userId: uid,
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
