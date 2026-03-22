/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */

import {createHash, randomUUID} from "crypto";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {db, fieldValue, storage} from "./firebase";

const REGION = "europe-west1";
const ALLOWED_IMAGE_TYPES = ["image/jpeg", "image/png"] as const;
type AllowedImageType = (typeof ALLOWED_IMAGE_TYPES)[number];
// Safe rollout: keep App Check optional until mobile clients are fully configured.
const ENFORCE_APP_CHECK = process.env.ENFORCE_APPCHECK === "true";

/* -------------------------------------------------------------------------- */
/* TYPES                                                                       */
/* -------------------------------------------------------------------------- */

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

/**
 * Métadonnées upload (robustes) : on déclare explicitement les clés possibles
 * pour éviter tout `any` et rester ESLint-safe.
 */
type UploadMetadata = RawMetadata & {
  // Canonique (nouveau)
  description?: unknown;
  caption?: unknown;

  // Legacy / alias possibles
  songName?: unknown;
  title?: unknown;
  desc?: unknown;

  captionText?: unknown;
  legend?: unknown;
  legende?: unknown;
  "légende"?: unknown;

  // Champs déjà utilisés
  profilePhoto?: unknown;
  storagePath?: unknown;
  thumbnailPath?: unknown;
  thumbnailHash?: unknown;
  thumbnailSize?: unknown;
  thumbnailContentType?: unknown;

  // Stats
  status?: unknown;
  likes?: unknown;
  reports?: unknown;
  reportCount?: unknown;
  shareCount?: unknown;
  optimized?: unknown;

  // Media
  duration?: unknown;
  width?: unknown;
  height?: unknown;
};

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
/* HELPERS                                                                     */
/* -------------------------------------------------------------------------- */

function parseImageContentType(raw: unknown): string {
  const value = typeof raw === "string" ? raw.trim().toLowerCase() : "image/jpeg";
  // NB: on conserve ton comportement existant
  if (!ALLOWED_IMAGE_TYPES.includes(value as AllowedImageType)) {
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

/* -------------------------------------------------------------------------- */
/* CREATE SESSION                                                              */
/* -------------------------------------------------------------------------- */

export const createUploadSession = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK},
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
/* REQUEST THUMBNAIL URL                                                       */
/* -------------------------------------------------------------------------- */

export const requestThumbnailUploadUrl = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK},
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
/* FINALIZE UPLOAD                                                             */
/* -------------------------------------------------------------------------- */

export const finalizeUpload = onCall(
  {region: REGION, enforceAppCheck: ENFORCE_APP_CHECK},
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

    const rawMetadata = (request.data as { metadata?: UploadMetadata } | undefined)?.metadata;
    const safe: ParsedMetadata = {};

    if (rawMetadata && typeof rawMetadata === "object") {
      // ✅ Description : canonique + fallbacks legacy
      safe.description =
        asString(rawMetadata.description, 500) ??
        asString(rawMetadata.songName, 500) ??
        asString(rawMetadata.title, 500) ??
        asString(rawMetadata.desc, 500);

      // ✅ Caption : canonique + fallbacks legacy FR/EN
      safe.caption =
        asString(rawMetadata.caption, 500) ??
        asString(rawMetadata.captionText, 500) ??
        asString(rawMetadata.legend, 500) ??
        asString(rawMetadata.legende, 500) ??
        asString(rawMetadata["légende"], 500);

      safe.profilePhoto = asString(rawMetadata.profilePhoto, 600);
      safe.storagePath = asString(rawMetadata.storagePath, 400);
      safe.thumbnailPath = asString(rawMetadata.thumbnailPath, 400);
      safe.thumbnailHash = asString(rawMetadata.thumbnailHash, 100);
      safe.thumbnailContentType = asString(rawMetadata.thumbnailContentType, 60);
      safe.thumbnailSize = asPositiveInt(rawMetadata.thumbnailSize);

      safe.reportCount = asPositiveInt(rawMetadata.reportCount);
      safe.shareCount = asPositiveInt(rawMetadata.shareCount);

      safe.duration = asNumber(rawMetadata.duration);
      safe.width = asPositiveInt(rawMetadata.width);
      safe.height = asPositiveInt(rawMetadata.height);

      safe.likes = asStringList(rawMetadata.likes);
      safe.reports = asStringList(rawMetadata.reports);

      // NB: status/optimized ne doivent pas être trust côté client.
      // On garde ton comportement existant: on force status=processing, optimized=false.
      // (Si tu veux quand même accepter, il faut whitelister et valider.)
    }

    // On n’écrit que les valeurs présentes dans safe
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
      "likes",
      "reports",
      "reportCount",
      "shareCount",
      "duration",
      "width",
      "height",
    ] as (keyof ParsedMetadata)[]).forEach(assignIfPresent);

    await videoRef.set(
      {
        uid,
        status: "processing",
        optimized: false,

        // ✅ CANONIQUE (nouveau standard)
        ...(safe.description ? {description: safe.description} : {}),
        ...(safe.caption ? {caption: safe.caption} : {}),

        // ✅ LEGACY / COMPAT (pour anciens écrans/lectures)
        ...(safe.description ? {songName: safe.description, title: safe.description} : {}),
        ...(safe.caption ? {legend: safe.caption, legende: safe.caption, captionText: safe.caption} : {}),

        // ✅ le reste
        ...sanitizedMetadata,

        updatedAt: fieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {ok: true};
  },
);
