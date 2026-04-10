/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db, fieldValue, storage} from "./firebase";
import {
  LOW_CPU_REGION_OPTIONS,
  assertAdminCaller,
  getString,
} from "./admin_account_support";

const OFFER_STATUSES = new Set(["brouillon", "ouverte", "fermee", "archivee"]);
const EVENT_STATUSES = new Set(["brouillon", "ouvert", "ferme", "archive"]);

type AdminContentCallableRequest = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
  data: unknown;
};

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
  case "fermÃ©e":
  case "fermÃ£Â©e":
    return "fermee";
  case "archivee":
  case "archivÃ©e":
  case "archivÃ£Â©e":
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
  case "fermÃ©":
  case "fermÃ£Â©":
    return "ferme";
  case "archive":
  case "archivÃ©":
  case "archivÃ£Â©":
    return "archive";
  case "brouillon":
    return "brouillon";
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
  deletedMessage: "Offre supprimee.",
  alreadyDeletedCode: "offer_already_deleted",
  alreadyDeletedMessage: "Offre deja supprimee.",
  collectStoragePaths: collectOfferStoragePaths,
};

const EVENT_DELETE_CONFIG: DeleteContentConfig = {
  collectionName: "events",
  contentLabel: "event",
  contentIdKey: "eventId",
  ownerPath: "organisateur.uid",
  ownerPublishedField: "eventPublies",
  deletedCode: "event_deleted",
  deletedMessage: "Evenement supprime.",
  alreadyDeletedCode: "event_already_deleted",
  alreadyDeletedMessage: "Evenement deja supprime.",
  collectStoragePaths: collectEventStoragePaths,
};

export const adminSetOfferStatus = onCall(
  LOW_CPU_REGION_OPTIONS,
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
        "Status offre invalide. Valeurs: brouillon, ouverte, fermee, archivee.",
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
        message: `Statut offre mis a jour: ${status}.`,
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
        "Mise a jour du statut offre impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteOffer = onCall(
  LOW_CPU_REGION_OPTIONS,
  async (request) => deleteContentWithAdminRights(
    OFFER_DELETE_CONFIG,
    request,
  ),
);

export const adminSetEventStatus = onCall(
  LOW_CPU_REGION_OPTIONS,
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
        "Status evenement invalide. Valeurs: brouillon, ouvert, ferme, archive.",
      );
    }

    try {
      const eventRef = db.collection("events").doc(eventId);
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "Evenement introuvable.");
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
        message: `Statut evenement mis a jour: ${status}.`,
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
        "Mise a jour du statut evenement impossible pour le moment.",
      );
    }
  },
);

export const adminDeleteEvent = onCall(
  LOW_CPU_REGION_OPTIONS,
  async (request) => deleteContentWithAdminRights(
    EVENT_DELETE_CONFIG,
    request,
  ),
);

