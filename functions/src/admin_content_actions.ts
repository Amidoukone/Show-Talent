/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db, fieldValue, messaging, storage} from "./firebase";
import {
  LOW_CPU_CALLABLE_OPTIONS,
  assertAdminCaller,
  getString,
} from "./admin_account_support";
import {normalizeNotificationText} from "./notification_text";

const OFFER_STATUSES = new Set(["brouillon", "ouverte", "fermee", "archivee"]);
const EVENT_STATUSES = new Set(["brouillon", "ouvert", "ferme", "archive"]);
const VIDEO_MODERATION_STATUSES = new Set([
  "approved",
  "pending",
  "under_review",
  "hidden",
  "removed",
  "rejected",
]);
const MAX_PUBLIC_PLAYER_VIDEOS = parsePositiveIntEnv(
  process.env.MAX_PUBLIC_PLAYER_VIDEOS,
  10,
);

type AdminContentCallableRequest = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
  data: unknown;
};

function parsePositiveIntEnv(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

type DeleteContentConfig = {
  collectionName: "offres" | "events";
  contentLabel: "offre" | "event";
  contentIdKey: "offerId" | "eventId";
  ownerPath: "recruteur.uid" | "organisateur.uid";
  ownerPublishedField: "offrePubliees" | "eventPublies";
  deletedCode: "offer_deleted" | "event_deleted";
  deletedMessage: string;
  alreadyDeletedCode: "offer_already_deleted" | "event_already_deleted";
  alreadyDeletedMessage: string;
  collectStoragePaths: (data: Record<string, unknown>) => string[];
};

function normalizeOfferStatus(rawStatus: string): string {
  const value = rawStatus.trim().toLowerCase();
  switch (value) {
  case "ouverte":
    return "ouverte";
  case "fermee":
  case "fermée":
    return "fermee";
  case "archivee":
  case "archivée":
    return "archivee";
  case "brouillon":
    return "brouillon";
  default:
    return value;
  }
}

function normalizeEventStatus(rawStatus: string): string {
  const value = rawStatus.trim().toLowerCase();
  switch (value) {
  case "ouvert":
    return "ouvert";
  case "ferme":
  case "fermé":
    return "ferme";
  case "archive":
  case "archivé":
    return "archive";
  case "brouillon":
    return "brouillon";
  default:
    return value;
  }
}

function normalizeVideoModerationStatus(rawStatus: string): string {
  const value = rawStatus.trim().toLowerCase();
  switch (value) {
  case "ready":
  case "published":
  case "publiee":
  case "publiée":
  case "approved":
  case "approve":
  case "validee":
  case "validée":
    return "approved";
  case "pending":
  case "under_review":
  case "review":
  case "a_revoir":
  case "en_attente":
    return "pending";
  case "hidden":
  case "masquee":
  case "masquée":
    return "hidden";
  case "removed":
  case "supprimee":
  case "supprimée":
    return "removed";
  case "rejected":
  case "reject":
  case "refusee":
  case "refusée":
    return "rejected";
  default:
    return value;
  }
}

function getContentId(
  data: unknown,
  preferredKey: string,
): string {
  return getString(data, preferredKey) || getString(data, "id");
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  ) {
    return value as Record<string, unknown>;
  }
  return null;
}

function getNestedString(data: unknown, path: string): string {
  const segments = path.split(".");
  let current: unknown = data;

  for (const segment of segments) {
    const record = asRecord(current);
    if (!record || !(segment in record)) {
      return "";
    }
    current = record[segment];
  }

  return typeof current === "string" ? current.trim() : "";
}

function extractStoragePathFromUrl(url: string): string | null {
  const trimmed = url.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith("gs://")) {
    const withoutPrefix = trimmed.slice(5);
    const slashIndex = withoutPrefix.indexOf("/");
    if (slashIndex > 0 && slashIndex < withoutPrefix.length - 1) {
      return withoutPrefix.slice(slashIndex + 1);
    }
    return null;
  }

  try {
    const parsed = new URL(trimmed);
    const marker = "/o/";
    const markerIndex = parsed.pathname.indexOf(marker);
    if (markerIndex >= 0) {
      return decodeURIComponent(parsed.pathname.slice(markerIndex + marker.length));
    }
  } catch (_) {
    return null;
  }

  return null;
}

function addStoragePath(
  value: unknown,
  out: Set<string>,
): void {
  if (typeof value !== "string") return;
  const trimmed = value.trim();
  if (!trimmed) return;

  const directPath = trimmed.includes("://") ?
    extractStoragePathFromUrl(trimmed) :
    trimmed;

  if (directPath) {
    out.add(directPath);
  }
}

function collectOfferStoragePaths(data: Record<string, unknown>): string[] {
  const paths = new Set<string>();
  addStoragePath(data["pieceJointeUrl"], paths);
  addStoragePath(data["pieceJointePath"], paths);
  return [...paths];
}

function collectEventStoragePaths(data: Record<string, unknown>): string[] {
  const paths = new Set<string>();
  addStoragePath(data["flyerUrl"], paths);
  addStoragePath(data["flyerPath"], paths);
  addStoragePath(data["streamingUrl"], paths);
  return [...paths];
}

function addVideoStoragePath(
  value: unknown,
  out: Set<string>,
  videoId: string,
): void {
  if (typeof value !== "string") return;
  const trimmed = value.trim();
  if (!trimmed) return;

  const path = trimmed.includes("://") ?
    extractStoragePathFromUrl(trimmed) :
    trimmed.replace(/^\/+/, "");

  if (!path || path.includes("..") || !path.includes(videoId)) {
    return;
  }

  if (
    path.startsWith("videos/") ||
    path.startsWith("thumbnails/") ||
    path.startsWith("mp4/")
  ) {
    out.add(path);
  }
}

function addVideoSourceStoragePath(
  value: unknown,
  out: Set<string>,
  videoId: string,
): void {
  const source = asRecord(value);
  if (!source) return;
  addVideoStoragePath(source["path"], out, videoId);
  addVideoStoragePath(source["url"], out, videoId);
  addVideoStoragePath(source["videoUrl"], out, videoId);
}

function collectVideoStoragePaths(
  videoId: string,
  data: Record<string, unknown>,
): string[] {
  const paths = new Set<string>([
    `videos/${videoId}.mp4`,
    `thumbnails/thumbnail_${videoId}.jpg`,
    `thumbnails/thumbnail_${videoId}.jpeg`,
    `thumbnails/thumbnail_${videoId}.png`,
  ]);

  addVideoStoragePath(data["storagePath"], paths, videoId);
  addVideoStoragePath(data["thumbnailPath"], paths, videoId);
  addVideoStoragePath(data["videoUrl"], paths, videoId);
  addVideoStoragePath(data["thumbnail"], paths, videoId);
  addVideoStoragePath(data["thumbnailUrl"], paths, videoId);

  if (Array.isArray(data["sources"])) {
    for (const source of data["sources"]) {
      addVideoSourceStoragePath(source, paths, videoId);
    }
  }

  const playback = asRecord(data["playback"]);
  if (playback) {
    addVideoSourceStoragePath(playback["sourceAsset"], paths, videoId);
    addVideoSourceStoragePath(playback["fallback"], paths, videoId);

    if (Array.isArray(playback["sources"])) {
      for (const source of playback["sources"]) {
        addVideoSourceStoragePath(source, paths, videoId);
      }
    }
  }

  return [...paths];
}

async function deleteStoragePaths(
  paths: readonly string[],
  context: {
    collectionName: string;
    contentId: string;
  },
): Promise<string[]> {
  const deletedPaths: string[] = [];

  for (const path of paths) {
    try {
      await storage.bucket().file(path).delete();
      deletedPaths.push(path);
    } catch (error) {
      logger.warn("admin content asset deletion skipped", {
        collectionName: context.collectionName,
        contentId: context.contentId,
        path,
        error,
      });
    }
  }

  return deletedPaths;
}

function filterPublishedContentEntries(
  entries: unknown,
  contentId: string,
): {
  filtered: unknown[] | null;
  changed: boolean;
} {
  if (!Array.isArray(entries)) {
    return {filtered: null, changed: false};
  }

  const filtered = entries.filter((entry) => {
    const record = asRecord(entry);
    if (!record) return true;
    return getString(record, "id") !== contentId;
  });

  return {
    filtered,
    changed: filtered.length !== entries.length,
  };
}

async function cleanupOwnerPublishedContent(params: {
  ownerUid: string;
  userPublishedField: "offrePubliees" | "eventPublies";
  contentId: string;
  adminUid: string;
}): Promise<boolean> {
  if (!params.ownerUid) {
    return false;
  }

  try {
    const userRef = db.collection("users").doc(params.ownerUid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      return false;
    }

    const data = userSnap.data() ?? {};
    const currentEntries = data[params.userPublishedField];
    const filtered = filterPublishedContentEntries(
      currentEntries,
      params.contentId,
    );

    if (!filtered.changed || filtered.filtered === null) {
      return false;
    }

    await userRef.set({
      [params.userPublishedField]: filtered.filtered,
      updatedByAdmin: params.adminUid,
      updatedAt: fieldValue.serverTimestamp(),
      lastUpdated: fieldValue.serverTimestamp(),
    }, {merge: true});

    return true;
  } catch (error) {
    logger.warn("admin content owner cleanup skipped", {
      ownerUid: params.ownerUid,
      userPublishedField: params.userPublishedField,
      contentId: params.contentId,
      adminUid: params.adminUid,
      error,
    });
    return false;
  }
}

async function deleteContentWithAdminRights(
  config: DeleteContentConfig,
  request: AdminContentCallableRequest,
) {
  const adminUid = await assertAdminCaller(request);
  const contentId = getContentId(request.data, config.contentIdKey);
  if (!contentId) {
    throw new HttpsError("invalid-argument", `${config.contentIdKey} est requis.`);
  }

  try {
    const contentRef = db.collection(config.collectionName).doc(contentId);
    const contentSnap = await contentRef.get();

    if (!contentSnap.exists) {
      return {
        success: true,
        code: config.alreadyDeletedCode,
        message: config.alreadyDeletedMessage,
        data: {
          [config.contentIdKey]: contentId,
          deletedBy: adminUid,
          alreadyDeleted: true,
          deletedAssetPaths: [],
        },
      };
    }

    const contentData = contentSnap.data() ?? {};
    const ownerUid = getNestedString(contentData, config.ownerPath);
    const assetPaths = config.collectStoragePaths(contentData);
    const deletedAssetPaths = await deleteStoragePaths(assetPaths, {
      collectionName: config.collectionName,
      contentId,
    });
    const ownerCleanupApplied = await cleanupOwnerPublishedContent({
      ownerUid,
      userPublishedField: config.ownerPublishedField,
      contentId,
      adminUid,
    });

    await contentRef.delete();

    logger.info("admin content deleted", {
      collectionName: config.collectionName,
      contentId,
      deletedBy: adminUid,
      ownerUid: ownerUid || null,
      deletedAssetCount: deletedAssetPaths.length,
      ownerCleanupApplied,
    });

    return {
      success: true,
      code: config.deletedCode,
      message: config.deletedMessage,
      data: {
        [config.contentIdKey]: contentId,
        deletedBy: adminUid,
        ownerUid: ownerUid || null,
        deletedAssetPaths,
        ownerCleanupApplied,
      },
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }

    logger.error("admin content deletion failed", {
      collectionName: config.collectionName,
      contentId,
      deletedBy: adminUid,
      error,
    });
    throw new HttpsError(
      "internal",
      `Suppression ${config.contentLabel} impossible pour le moment.`,
    );
  }
}

const OFFER_DELETE_CONFIG: DeleteContentConfig = {
  collectionName: "offres",
  contentLabel: "offre",
  contentIdKey: "offerId",
  ownerPath: "recruteur.uid",
  ownerPublishedField: "offrePubliees",
  deletedCode: "offer_deleted",
  deletedMessage: "Offre supprimée.",
  alreadyDeletedCode: "offer_already_deleted",
  alreadyDeletedMessage: "Offre déjà supprimée.",
  collectStoragePaths: collectOfferStoragePaths,
};

const EVENT_DELETE_CONFIG: DeleteContentConfig = {
  collectionName: "events",
  contentLabel: "event",
  contentIdKey: "eventId",
  ownerPath: "organisateur.uid",
  ownerPublishedField: "eventPublies",
  deletedCode: "event_deleted",
  deletedMessage: "Événement supprimé.",
  alreadyDeletedCode: "event_already_deleted",
  alreadyDeletedMessage: "Événement déjà supprimé.",
  collectStoragePaths: collectEventStoragePaths,
};


function resolveVideoTitle(data: Record<string, unknown>): string {
  return getString(data, "caption") ||
    getString(data, "captionText") ||
    getString(data, "description") ||
    getString(data, "songName") ||
    "Video";
}

function isPublicPlayerVideoData(
  data: Record<string, unknown>,
  excludeVideoId?: string,
): boolean {
  if (excludeVideoId && getString(data, "id") === excludeVideoId) {
    return false;
  }

  if (getString(data, "status") !== "ready") {
    return false;
  }

  const moderationStatus = getString(data, "moderationStatus");
  return moderationStatus === "" ||
    moderationStatus === "approved" ||
    getString(data, "visibility") === "public" ||
    data["isPublic"] === true;
}

// Takes a transaction so the count-then-write in adminSetVideoStatus can't
// race: two admins approving two different pending videos for the same
// player at nearly the same time used to both read the same pre-write
// count outside any transaction and could both pass the
// MAX_PUBLIC_PLAYER_VIDEOS check, exceeding the configured cap.
async function countPublicPlayerVideos(
  transaction: FirebaseFirestore.Transaction,
  ownerUid: string,
  excludeVideoId: string,
): Promise<number> {
  if (!ownerUid) {
    return 0;
  }

  const snapshot = await transaction.get(
    db.collection("videos")
      .where("uid", "==", ownerUid)
      .where("status", "==", "ready"),
  );

  let count = 0;
  for (const doc of snapshot.docs) {
    const data = {id: doc.id, ...(doc.data() ?? {})};
    if (isPublicPlayerVideoData(data, excludeVideoId)) {
      count += 1;
    }
  }
  return count;
}

async function notifyVideoOwner(params: {
  ownerUid: string;
  videoId: string;
  decision: "approved" | "rejected";
  title: string;
  body: string;
}): Promise<boolean> {
  if (!params.ownerUid) {
    return false;
  }

  try {
    const userSnap = await db.collection("users").doc(params.ownerUid).get();
    if (!userSnap.exists) {
      return false;
    }

    const token = getString(userSnap.data(), "fcmToken");
    if (!token) {
      return false;
    }

    await messaging.send({
      token,
      notification: {
        title: normalizeNotificationText(params.title, 120),
        body: normalizeNotificationText(params.body, 300),
      },
      data: {
        type: "video_moderation",
        videoId: params.videoId,
        decision: params.decision,
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

    return true;
  } catch (error) {
    logger.warn("video moderation notification skipped", {
      videoId: params.videoId,
      ownerUid: params.ownerUid,
      decision: params.decision,
      error,
    });
    return false;
  }
}

async function recordVideoModerationDecision(params: {
  videoId: string;
  ownerUid: string;
  decision: string;
  reason?: string;
  adminUid: string;
  videoData: Record<string, unknown>;
  deletedAssetPaths?: string[];
}): Promise<void> {
  await db.collection("videoModerationDecisions").doc(params.videoId).set({
    videoId: params.videoId,
    ownerUid: params.ownerUid || null,
    decision: params.decision,
    reason: params.reason?.trim() || null,
    title: resolveVideoTitle(params.videoData),
    reviewedBy: params.adminUid,
    reviewedAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
    deletedAssetPaths: params.deletedAssetPaths ?? [],
  }, {merge: true});
}

async function rejectVideoWithAdminRights(params: {
  videoId: string;
  adminUid: string;
  reason?: string;
}) {
  const videoRef = db.collection("videos").doc(params.videoId);
  const videoSnap = await videoRef.get();

  if (!videoSnap.exists) {
    return {
      success: true,
      code: "video_already_deleted",
      message: "Video deja supprimee.",
      data: {
        videoId: params.videoId,
        deletedBy: params.adminUid,
        alreadyDeleted: true,
        deletedAssetPaths: [],
      },
    };
  }

  const videoData = videoSnap.data() ?? {};
  const ownerUid = getString(videoData, "uid");
  const assetPaths = collectVideoStoragePaths(params.videoId, videoData);
  const deletedAssetPaths = await deleteStoragePaths(assetPaths, {
    collectionName: "videos",
    contentId: params.videoId,
  });

  await recordVideoModerationDecision({
    videoId: params.videoId,
    ownerUid,
    decision: "rejected",
    reason: params.reason,
    adminUid: params.adminUid,
    videoData,
    deletedAssetPaths,
  });

  await videoRef.delete();

  const notified = await notifyVideoOwner({
    ownerUid,
    videoId: params.videoId,
    decision: "rejected",
    title: "Video refusee",
    body: params.reason?.trim() ||
      "Votre video n'a pas ete retenue apres revue admin.",
  });

  logger.info("admin video rejected and deleted", {
    videoId: params.videoId,
    ownerUid: ownerUid || null,
    deletedBy: params.adminUid,
    deletedAssetCount: deletedAssetPaths.length,
    notified,
  });

  return {
    success: true,
    code: "video_rejected_deleted",
    message: "Video refusee, fichiers supprimes et decision enregistree.",
    data: {
      videoId: params.videoId,
      ownerUid: ownerUid || null,
      deletedBy: params.adminUid,
      deletedAssetPaths,
      notified,
    },
  };
}
export const adminSetVideoStatus = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const videoId = getContentId(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId est requis.");
    }

    const rawStatus = getString(request.data, "status");
    if (!rawStatus) {
      throw new HttpsError("invalid-argument", "status est requis.");
    }

    const status = normalizeVideoModerationStatus(rawStatus);
    if (!VIDEO_MODERATION_STATUSES.has(status)) {
      throw new HttpsError(
        "invalid-argument",
        "Statut video invalide. Valeurs : approved, pending, hidden, removed, rejected.",
      );
    }

    const reason = getString(request.data, "reason").slice(0, 500);

    try {
      if (status === "rejected") {
        return await rejectVideoWithAdminRights({
          videoId,
          adminUid,
          reason,
        });
      }

      const videoRef = db.collection("videos").doc(videoId);
      const videoSnap = await videoRef.get();
      if (!videoSnap.exists) {
        throw new HttpsError("not-found", "Video introuvable.");
      }

      const videoData = videoSnap.data() ?? {};
      if (status === "approved" && videoData.optimized !== true) {
        throw new HttpsError(
          "failed-precondition",
          "La video doit etre optimisee avant approbation.",
        );
      }

      const ownerUid = getString(videoData, "uid");

      const nextStatus = status === "approved" ?
        "ready" :
        status === "pending" ?
          (videoData.optimized === true ? "under_review" : "processing") :
          status;
      const moderationStatus = status === "pending" ? "pending" : status;
      const isPublic = status === "approved";

      await db.runTransaction(async (transaction) => {
        if (status === "approved") {
          const publicVideoCount = await countPublicPlayerVideos(
            transaction,
            ownerUid,
            videoId,
          );
          if (publicVideoCount >= MAX_PUBLIC_PLAYER_VIDEOS) {
            throw new HttpsError(
              "resource-exhausted",
              `Ce joueur a deja ${MAX_PUBLIC_PLAYER_VIDEOS} videos publiques. Approbation impossible.`,
            );
          }
        }

        transaction.set(videoRef, {
          status: nextStatus,
          moderationStatus,
          visibility: isPublic ? "public" : "private",
          isPublic,
          updatedByAdmin: adminUid,
          updatedAt: fieldValue.serverTimestamp(),
          lastModeratedAt: fieldValue.serverTimestamp(),
          ...(status === "approved" ? {
            approvedAt: fieldValue.serverTimestamp(),
            approvedBy: adminUid,
            rejectedAt: fieldValue.delete(),
            rejectionReason: fieldValue.delete(),
            hiddenAt: fieldValue.delete(),
            removedAt: fieldValue.delete(),
          } : {}),
          ...(status === "pending" ? {
            approvedAt: fieldValue.delete(),
            approvedBy: fieldValue.delete(),
            rejectedAt: fieldValue.delete(),
            rejectionReason: fieldValue.delete(),
            submittedForReviewAt: fieldValue.serverTimestamp(),
          } : {}),
          ...(status === "hidden" ? {
            hiddenAt: fieldValue.serverTimestamp(),
          } : {}),
          ...(status === "removed" ? {
            removedAt: fieldValue.serverTimestamp(),
          } : {}),
        }, {merge: true});
      });

      if (status === "approved") {
        await recordVideoModerationDecision({
          videoId,
          ownerUid,
          decision: "approved",
          adminUid,
          videoData,
        });

        await notifyVideoOwner({
          ownerUid,
          videoId,
          decision: "approved",
          title: "Video approuvee",
          body: "Votre video a ete approuvee. Elle est maintenant visible par les clubs et recruteurs.",
        });
      }

      logger.info("admin video status updated", {
        videoId,
        status,
        nextStatus,
        updatedBy: adminUid,
      });

      return {
        success: true,
        code: status === "approved" ? "video_approved" : "video_status_updated",
        message: status === "approved" ?
          "Video approuvee et rendue publique." :
          `Statut video mis a jour : ${status}.`,
        data: {
          videoId,
          status,
          firestoreStatus: nextStatus,
          updatedBy: adminUid,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin video status update failed", {
        videoId,
        status,
        updatedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Mise a jour du statut video impossible pour le moment.",
      );
    }
  },
);

export const adminRejectVideo = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const videoId = getContentId(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId est requis.");
    }

    const reason = getString(request.data, "reason").slice(0, 500);
    return rejectVideoWithAdminRights({
      videoId,
      adminUid,
      reason,
    });
  },
);
export const adminDeleteVideo = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const videoId = getContentId(request.data, "videoId");
    if (!videoId) {
      throw new HttpsError("invalid-argument", "videoId est requis.");
    }

    try {
      const videoRef = db.collection("videos").doc(videoId);
      const videoSnap = await videoRef.get();

      if (!videoSnap.exists) {
        return {
          success: true,
          code: "video_already_deleted",
          message: "Vidéo déjà supprimée.",
          data: {
            videoId,
            deletedBy: adminUid,
            alreadyDeleted: true,
            deletedAssetPaths: [],
          },
        };
      }

      const videoData = videoSnap.data() ?? {};
      const assetPaths = collectVideoStoragePaths(videoId, videoData);
      const deletedAssetPaths = await deleteStoragePaths(assetPaths, {
        collectionName: "videos",
        contentId: videoId,
      });

      await videoRef.delete();

      logger.info("admin video deleted", {
        videoId,
        deletedBy: adminUid,
        deletedAssetCount: deletedAssetPaths.length,
      });

      return {
        success: true,
        code: "video_deleted",
        message: "Vidéo supprimée.",
        data: {
          videoId,
          deletedBy: adminUid,
          deletedAssetPaths,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin video deletion failed", {
        videoId,
        deletedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Suppression vidéo impossible pour le moment.",
      );
    }
  },
);

export const adminSetOfferStatus = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const offerId = getContentId(request.data, "offerId");
    if (!offerId) {
      throw new HttpsError("invalid-argument", "offerId est requis.");
    }

    const rawStatus = getString(request.data, "status");
    if (!rawStatus) {
      throw new HttpsError("invalid-argument", "status est requis.");
    }

    const status = normalizeOfferStatus(rawStatus);
    if (!OFFER_STATUSES.has(status)) {
      throw new HttpsError(
        "invalid-argument",
        "Statut offre invalide. Valeurs : brouillon, ouverte, fermée, archivée.",
      );
    }

    try {
      const offerRef = db.collection("offres").doc(offerId);
      const offerSnap = await offerRef.get();
      if (!offerSnap.exists) {
        throw new HttpsError("not-found", "Offre introuvable.");
      }

      await offerRef.set({
        statut: status,
        updatedByAdmin: adminUid,
        updatedAt: fieldValue.serverTimestamp(),
        lastUpdated: fieldValue.serverTimestamp(),
        ...(status === "archivee" ?
          {archivedAt: fieldValue.serverTimestamp()} :
          {archivedAt: fieldValue.delete()}),
      }, {merge: true});

      return {
        success: true,
        code: "offer_status_updated",
        message: `Statut offre mis à jour : ${status}.`,
        data: {
          offerId,
          status,
          updatedBy: adminUid,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin offer status update failed", {
        offerId,
        status,
        updatedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Mise à jour du statut offre impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteOffer = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => deleteContentWithAdminRights(
    OFFER_DELETE_CONFIG,
    request,
  ),
);

export const adminSetEventStatus = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const eventId = getContentId(request.data, "eventId");
    if (!eventId) {
      throw new HttpsError("invalid-argument", "eventId est requis.");
    }

    const rawStatus = getString(request.data, "status");
    if (!rawStatus) {
      throw new HttpsError("invalid-argument", "status est requis.");
    }

    const status = normalizeEventStatus(rawStatus);
    if (!EVENT_STATUSES.has(status)) {
      throw new HttpsError(
        "invalid-argument",
        "Statut événement invalide. Valeurs : brouillon, ouvert, fermé, archivé.",
      );
    }

    try {
      const eventRef = db.collection("events").doc(eventId);
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "Événement introuvable.");
      }

      await eventRef.set({
        statut: status,
        updatedByAdmin: adminUid,
        updatedAt: fieldValue.serverTimestamp(),
        lastUpdated: fieldValue.serverTimestamp(),
        ...(status === "archive" ?
          {archivedAt: fieldValue.serverTimestamp()} :
          {archivedAt: fieldValue.delete()}),
      }, {merge: true});

      return {
        success: true,
        code: "event_status_updated",
        message: `Statut événement mis à jour : ${status}.`,
        data: {
          eventId,
          status,
          updatedBy: adminUid,
        },
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("admin event status update failed", {
        eventId,
        status,
        updatedBy: adminUid,
        error,
      });
      throw new HttpsError(
        "internal",
        "Mise à jour du statut événement impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteEvent = onCall(
  LOW_CPU_CALLABLE_OPTIONS,
  async (request) => deleteContentWithAdminRights(
    EVENT_DELETE_CONFIG,
    request,
  ),
);

