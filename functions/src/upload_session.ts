/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */

import {createHash, randomUUID} from "crypto";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {db, fieldValue, storage} from "./firebase";

const REGION = "europe-west1";
const ALLOWED_IMAGE_TYPES = ["image/jpeg", "image/png"] as const;

interface ThumbnailGuard {
  hash?: string;
  size?: number;
  expiresAt?: number;
  contentType?: string;
}

interface VideoDoc {
  uid?: string;
  storagePath?: string;
  thumbnailPath?: string;
  thumbnailGuard?: ThumbnailGuard;
}

type RawMetadata = Record<string, unknown>;

interface ParsedMetadata {
  description?: string;
  caption?: string;
  profilePhoto?: string;
  storagePath?: string;
  thumbnailPath?: string;
  thumbnailHash?: string;
  thumbnailSize?: number;
  thumbnailContentType?: string;
  status?: string;
  likes?: string[];
  reports?: string[];
  reportCount?: number;
  shareCount?: number;
  optimized?: boolean;
  duration?: number;
  width?: number;
  height?: number;
}

/* -------------------------------------------------------------------------- */
/*                                CREATE SESSION                              */
/* -------------------------------------------------------------------------- */

export const createUploadSession = onCall(
  {region: REGION},
  async (request): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const data = (request.data as Record<string, unknown>) ?? {};
    const providedSessionId =
      typeof data.sessionId === "string" ? data.sessionId.trim() : "";

    const contentType =
      typeof data.contentType === "string" && data.contentType.trim() ?
        data.contentType.trim() :
        "video/mp4";

    const sessionId = providedSessionId || randomUUID();
    const videoRef = db.collection("videos").doc(sessionId);

    let storagePath = `videos/${sessionId}.mp4`;
    let thumbnailPath = `thumbnails/thumbnail_${sessionId}.jpg`;

    const existing = await videoRef.get();
    if (existing.exists) {
      const doc = existing.data() as VideoDoc | undefined;
      if (doc?.uid && doc.uid !== uid) {
        throw new HttpsError("permission-denied", "Session appartenant à un autre utilisateur.");
      }
      storagePath = doc?.storagePath ?? storagePath;
      thumbnailPath = doc?.thumbnailPath ?? thumbnailPath;
    }

    await videoRef.set(
      {
        id: sessionId,
        uid,
        storagePath,
        thumbnailPath,
        status: "processing",
        optimized: false,
        updatedAt: fieldValue.serverTimestamp(),
        createdAt: fieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    const expiresAtMs = Date.now() + 45 * 60 * 1000;

    const file = storage.bucket().file(storagePath);
    const [uploadUrl] = await file.createResumableUpload({
      origin: "*",
      metadata: {contentType},
    });

    return {
      sessionId,
      uploadUrl,
      videoPath: storagePath,
      thumbnailPath,
      expiresAt: expiresAtMs,
    };
  },
);

/* -------------------------------------------------------------------------- */
/*                         THUMBNAIL HELPERS                                   */
/* -------------------------------------------------------------------------- */

function parseImageContentType(raw: unknown): string {
  const value =
    typeof raw === "string" ? raw.trim().toLowerCase() : "image/jpeg";
  if (!ALLOWED_IMAGE_TYPES.includes(value as any)) {
    throw new HttpsError("invalid-argument", "Type d'image non supporté.");
  }
  return value;
}

function sanitizeThumbnailPath(
  sessionId: string,
  contentType: string,
  provided?: string,
): string {
  const ext = contentType === "image/png" ? "png" : "jpg";
  const fallback = `thumbnails/thumbnail_${sessionId}.${ext}`;
  if (!provided) return fallback;

  const safe = provided
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_./-]/g, "");

  return safe.endsWith(`.${ext}`) ? safe : fallback;
}

/* -------------------------------------------------------------------------- */
/*                       REQUEST THUMBNAIL URL                                 */
/* -------------------------------------------------------------------------- */

export const requestThumbnailUploadUrl = onCall(
  {region: REGION},
  async (request): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentification requise.");

    const data = (request.data as Record<string, unknown>) ?? {};
    const sessionId = typeof data.sessionId === "string" ? data.sessionId.trim() : "";
    const hash = typeof data.hash === "string" ? data.hash.trim() : "";
    const size = typeof data.size === "number" ? Math.round(data.size) : 0;
    const contentType = parseImageContentType(data.contentType);

    if (!sessionId || !hash || size <= 0) {
      throw new HttpsError("invalid-argument", "Métadonnées miniature invalides.");
    }

    const videoRef = db.collection("videos").doc(sessionId);
    const snap = await videoRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Session inconnue.");

    const doc = snap.data() as VideoDoc | undefined;
    if (doc?.uid !== uid) {
      throw new HttpsError("permission-denied", "Session appartenant à un autre utilisateur.");
    }

    const thumbnailPath = sanitizeThumbnailPath(
      sessionId,
      contentType,
      doc?.thumbnailPath,
    );

    const expiresAtMs = Date.now() + 20 * 60 * 1000;
    const file = storage.bucket().file(thumbnailPath);

    const [uploadUrl] = await file.createResumableUpload({
      origin: "*",
      metadata: {
        contentType,
        metadata: {
          expectedHash: hash,
          expectedSize: `${size}`,
        },
      },
    });

    await videoRef.set(
      {
        thumbnailPath,
        thumbnailGuard: {
          hash,
          size,
          expiresAt: expiresAtMs,
          contentType,
        },
        updatedAt: fieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {
      uploadUrl,
      expiresAt: expiresAtMs,
      thumbnailPath,
    };
  },
);

/* -------------------------------------------------------------------------- */
/*                              FINALIZE UPLOAD                                */
/* -------------------------------------------------------------------------- */

async function validateThumbnail(
  path: string | undefined,
  guard: ThumbnailGuard | undefined,
): Promise<void> {
  if (!path || !guard) return;

  if (guard.expiresAt && guard.expiresAt < Date.now()) {
    throw new HttpsError("deadline-exceeded", "URL miniature expirée.");
  }

  const file = storage.bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) throw new HttpsError("not-found", "Miniature introuvable.");

  const [meta] = await file.getMetadata();
  const actualSize = Number(meta.size ?? 0);

  if (guard.size && actualSize !== guard.size) {
    throw new HttpsError("failed-precondition", "Taille miniature invalide.");
  }

  const [buffer] = await file.download();
  const computedHash = createHash("md5").update(buffer).digest("hex");

  if (guard.hash && computedHash !== guard.hash) {
    throw new HttpsError("failed-precondition", "Hash miniature invalide.");
  }
}

export const finalizeUpload = onCall(
  {region: REGION},
  async (request): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentification requise.");

    const data = (request.data as Record<string, unknown>) ?? {};
    const sessionId = typeof data.sessionId === "string" ? data.sessionId.trim() : "";
    if (!sessionId) throw new HttpsError("invalid-argument", "sessionId manquant.");

    const videoRef = db.collection("videos").doc(sessionId);
    const snap = await videoRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "Session inconnue.");

    const doc = snap.data() as VideoDoc | undefined;
    if (doc?.uid !== uid) {
      throw new HttpsError("permission-denied", "Session appartenant à un autre utilisateur.");
    }

    await validateThumbnail(doc?.thumbnailPath, doc?.thumbnailGuard);

    const rawMetadata = (request.data as RawMetadata | undefined)?.metadata;
    const safe: ParsedMetadata = {};

    const asString = (value: unknown, max = 300): string | undefined => {
      if (typeof value !== "string") return undefined;
      const trimmed = value.trim();
      return trimmed ? trimmed.slice(0, max) : undefined;
    };

    const asNumber = (value: unknown): number | undefined => {
      if (typeof value !== "number") return undefined;
      return Number.isFinite(value) ? value : undefined;
    };

    const asPositiveInt = (value: unknown): number | undefined => {
      if (typeof value !== "number") return undefined;
      const n = Math.round(value);
      return n >= 0 ? n : undefined;
    };

    const asStringList = (value: unknown): string[] | undefined => {
      if (!Array.isArray(value)) return undefined;
      const items = value
        .map((v) => (typeof v === "string" ? v.trim() : ""))
        .filter((v) => v.length > 0);
      return items.length ? items : undefined;
    };

    if (rawMetadata && typeof rawMetadata === "object") {
      const meta = rawMetadata as RawMetadata;
      safe.description = asString(meta.description, 500);
      safe.caption = asString(meta.caption, 500);
      safe.profilePhoto = asString(meta.profilePhoto, 600);
      safe.storagePath = asString(meta.storagePath, 400);
      safe.thumbnailPath = asString(meta.thumbnailPath, 400);
      safe.thumbnailHash = asString(meta.thumbnailHash, 100);
      safe.thumbnailContentType = asString(meta.thumbnailContentType, 60);
      safe.thumbnailSize = asPositiveInt(meta.thumbnailSize);
      safe.reportCount = asPositiveInt(meta.reportCount);
      safe.shareCount = asPositiveInt(meta.shareCount);
      safe.duration = asNumber(meta.duration);
      safe.width = asPositiveInt(meta.width);
      safe.height = asPositiveInt(meta.height);
      safe.likes = asStringList(meta.likes);
      safe.reports = asStringList(meta.reports);

      // For backward compatibility we accept songName but store it as description.
      if (!safe.description) {
        safe.description = asString(meta.songName, 500);
      }
    }

    const sanitizedMetadata: Record<string, unknown> = {};
    const assignIfPresent = <K extends keyof ParsedMetadata>(key: K) => {
      const value = safe[key];
      if (value !== undefined) sanitizedMetadata[key] = value;
    };

    ([
      "description",
      "caption",
      "profilePhoto",
      "storagePath",
      "thumbnailPath",
      "thumbnailHash",
      "thumbnailSize",
      "thumbnailContentType",
      "status",
      "likes",
      "reports",
      "reportCount",
      "shareCount",
      "optimized",
      "duration",
      "width",
      "height",
    ] as (keyof ParsedMetadata)[]).forEach(assignIfPresent);

    await videoRef.set(
      {
        uid,
        status: "processing",
        optimized: false,
        songName: safe.description,
        ...sanitizedMetadata,
        updatedAt: fieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {ok: true};
  },
);
