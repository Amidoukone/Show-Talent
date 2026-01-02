/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */

import {randomUUID} from "crypto";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {db, fieldValue, storage} from "./firebase";

const REGION = "europe-west1";

interface VideoDoc {
  uid?: string;
  storagePath?: string;
  thumbnailPath?: string;
}

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
      typeof data.contentType === "string" && data.contentType.trim().length > 0 ?
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
        throw new HttpsError(
          "permission-denied",
          "Session appartenant à un autre utilisateur.",
        );
      }
      storagePath = doc?.storagePath ?? storagePath;
      thumbnailPath = doc?.thumbnailPath ?? thumbnailPath;

      await videoRef.set(
        {
          uid,
          storagePath,
          thumbnailPath,
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    } else {
      await videoRef.set(
        {
          id: sessionId,
          uid,
          storagePath,
          thumbnailPath,
          status: "processing",
          optimized: false,
          createdAt: fieldValue.serverTimestamp(),
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    const expiresAtMs = Date.now() + 45 * 60 * 1000; // 45 min

    const file = storage.bucket().file(storagePath);

    /**
     * ✅ Fix TypeScript overload:
     * - createResumableUpload attend un objet options conforme
     * - le contentType doit être dans metadata.contentType (et non à la racine)
     * - ainsi TS choisit le bon overload Promise<...> et [uploadUrl] fonctionne
     */
    const [uploadUrl] = await file.createResumableUpload({
      origin: "*",
      metadata: {
        contentType,
      },
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

export const finalizeUpload = onCall(
  {region: REGION},
  async (request): Promise<Record<string, unknown>> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const data = (request.data as Record<string, unknown>) ?? {};
    const sessionId = typeof data.sessionId === "string" ? data.sessionId.trim() : "";
    if (!sessionId) {
      throw new HttpsError("invalid-argument", "sessionId manquant.");
    }

    const meta = (data.metadata as Record<string, unknown> | undefined) ?? {};
    const videoRef = db.collection("videos").doc(sessionId);
    const snap = await videoRef.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "Session inconnue.");
    }

    const doc = snap.data() as VideoDoc | undefined;
    if (doc?.uid && doc.uid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Session appartenant à un autre utilisateur.",
      );
    }

    const allowedKeys = [
      "songName",
      "caption",
      "storagePath",
      "thumbnailPath",
      "duration",
      "width",
      "height",
      "likes",
      "reports",
      "reportCount",
      "shareCount",
      "optimized",
      "profilePhoto",
      "id",
      "uid",
      "videoUrl",
      "thumbnail",
    ];

    const payload: Record<string, unknown> = {
      status: "processing",
      updatedAt: fieldValue.serverTimestamp(),
    };

    const stringFields = ["songName", "caption"];
    for (const field of stringFields) {
      const value = meta[field];
      if (typeof value === "string") {
        payload[field] = value.trim();
      }
    }

    for (const key of allowedKeys) {
      if (meta[key] !== undefined && !stringFields.includes(key)) {
        payload[key] = meta[key];
      }
    }

    if (!payload.uid) {
      payload.uid = uid;
    }

    await videoRef.set(payload, {merge: true});
    return {ok: true};
  },
);
