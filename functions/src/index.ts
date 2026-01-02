/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */
/* eslint-disable max-len */

import {tmpdir} from "os";
import {join} from "path";
import {existsSync, unlinkSync} from "node:fs";
import * as fsp from "node:fs/promises";
import {Storage} from "@google-cloud/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import {onObjectFinalized, StorageObjectData} from "firebase-functions/v2/storage";
import {CloudEvent} from "firebase-functions/v2";
import {randomUUID} from "crypto";

import {db, fieldValue} from "./firebase";
import {createUploadSession, finalizeUpload} from "./upload_session";

/* -------------------------------------------------------------------------- */
/* REGION & INIT                                                               */
/* -------------------------------------------------------------------------- */

const REGION = "europe-west1";

ffmpeg.setFfmpegPath(ffmpegInstaller.path);
const gcs = new Storage();

/* -------------------------------------------------------------------------- */
/* Utils                                                                       */
/* -------------------------------------------------------------------------- */

function sleep(ms: number) {
  return new Promise((res) => setTimeout(res, ms));
}

type GcsUserMetadata = Record<string, string>;
interface GcsFileMetadata {
  metadata?: GcsUserMetadata;
}

interface VideoDoc {
  thumbnailPath?: string;
}

/* -------------------------------------------------------------------------- */
/* Download token helper                                                       */
/* -------------------------------------------------------------------------- */

async function ensureDownloadToken(
  bucketName: string,
  objectPath: string
): Promise<string> {
  const file = gcs.bucket(bucketName).file(objectPath);

  const [metaRaw] = await file.getMetadata().catch((): [null] => [null]);
  const meta: GcsFileMetadata | null =
    metaRaw && typeof metaRaw === "object" ?
      (metaRaw as unknown as GcsFileMetadata) :
      null;

  const md: GcsUserMetadata = meta?.metadata ?? {};
  let token =
    typeof md["firebaseStorageDownloadTokens"] === "string" ?
      md["firebaseStorageDownloadTokens"].trim() :
      "";

  if (!token) {
    token = randomUUID();
    await file.setMetadata({
      metadata: {...md, firebaseStorageDownloadTokens: token},
    });
  }
  return token;
}

/* -------------------------------------------------------------------------- */
/* Robust download                                                             */
/* -------------------------------------------------------------------------- */

async function robustDownload(
  bucketName: string,
  srcPath: string,
  destPath: string,
  attempts = 3
): Promise<void> {
  const file = gcs.bucket(bucketName).file(srcPath);
  let lastErr: unknown = null;

  for (let i = 1; i <= attempts; i++) {
    try {
      console.log(`⬇️ Téléchargement (tentative ${i}/${attempts})`, srcPath);
      await file.download({destination: destPath});
      const stat = await fsp.stat(destPath);
      if (stat.size > 0) return;
      throw new Error("Fichier téléchargé vide.");
    } catch (e) {
      lastErr = e;
      console.warn(`⚠️ Échec tentative ${i}:`, (e as Error).message);
      await sleep(250 * i);
    }
  }
  throw lastErr ?? new Error("Échec téléchargement.");
}

/* -------------------------------------------------------------------------- */
/* Thumbnail resolution                                                        */
/* -------------------------------------------------------------------------- */

async function tryResolveThumbnailPath(
  bucketName: string,
  videoId: string
): Promise<string | null> {
  try {
    const snap = await db.collection("videos").doc(videoId).get();
    const data = snap.data() as VideoDoc | undefined;
    if (data?.thumbnailPath) {
      const f = gcs.bucket(bucketName).file(data.thumbnailPath);
      const [exists] = await f.exists();
      if (exists) return data.thumbnailPath;
    }
  } catch (e) {
    console.warn("⚠️ Firestore thumbnailPath error:", (e as Error).message);
  }

  const candidates = [
    `thumbnails/thumbnail_${videoId}.jpg`,
    `thumbnails/thumbnail_${videoId}.jpeg`,
    `thumbnails/thumbnail_${videoId}.png`,
  ];

  for (const p of candidates) {
    const [exists] = await gcs.bucket(bucketName).file(p).exists();
    if (exists) return p;
  }
  return null;
}

/* -------------------------------------------------------------------------- */
/* MP4 Optimization                                                            */
/* -------------------------------------------------------------------------- */

export const optimizeMp4Video = onObjectFinalized(
  {
    region: REGION,
    memory: "2GiB",
    timeoutSeconds: 540,
  },
  async (event: CloudEvent<StorageObjectData>) => {
    const object = event.data;
    const bucketName = object.bucket;
    const filePath = object.name || "";
    const contentType = object.contentType || "";
    const fileName = filePath.split("/").pop() || "";
    const videoId = fileName.replace(/\.mp4$/i, "");
    const videoRef = db.collection("videos").doc(videoId);

    console.log("🎯 Optimize trigger:", filePath);

    if (
      !filePath.startsWith("videos/") ||
      !filePath.endsWith(".mp4") ||
      !contentType.startsWith("video/")
    ) {
      console.log("⛔️ Ignoré (non MP4)");
      return null;
    }

    if (object.metadata?.optimized === "true") {
      console.log("ℹ️ Déjà optimisée (metadata)");
      await videoRef.set({optimized: true}, {merge: true});
      return null;
    }

    const bucket = gcs.bucket(bucketName);
    const tempInputFile = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);

    try {
      await robustDownload(bucketName, filePath, tempInputFile);

      console.log("🎬 FFmpeg optimisation…");
      await new Promise<void>((resolve, reject) => {
        const cmd = ffmpeg(tempInputFile)
          .outputOptions([
            "-y",
            "-c:v libx264",
            "-profile:v main",
            "-preset veryfast",
            "-crf 23",
            "-movflags +faststart",
            "-vf scale='min(854,iw)':'-2'",
            "-g 30",
            "-keyint_min 30",
            "-maxrate 1M",
            "-bufsize 2M",
            "-c:a aac",
            "-b:a 96k",
          ])
          // ✅ Fix ESLint: no unused args, same behavior
          .on("end", () => resolve())
          .on("error", (err: unknown) => reject(err))
          .save(optimizedFile);

        // (cmd est volontairement conservé pour debug éventuel)
        void cmd;
      });

      console.log("⬆️ Upload optimisé…");
      await bucket.upload(optimizedFile, {
        destination: filePath,
        metadata: {
          contentType: "video/mp4",
          cacheControl: "public,max-age=86400",
          metadata: {optimized: "true"},
        },
      });

      const videoToken = await ensureDownloadToken(bucketName, filePath);
      const videoUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
          filePath
        )}?alt=media&token=${videoToken}`;

      let thumbnail = "";
      const thumbPath = await tryResolveThumbnailPath(bucketName, videoId);
      if (thumbPath) {
        const thumbToken = await ensureDownloadToken(bucketName, thumbPath);
        thumbnail =
          `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
            thumbPath
          )}?alt=media&token=${thumbToken}`;
      }

      await videoRef.set(
        {
          videoUrl,
          sources: [
            {
              quality: 480,
              url: videoUrl,
              isHls: false,
            },
          ],
          ...(thumbnail ? {thumbnail} : {}),
          optimized: true,
          status: "ready",
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      console.log("✅ Vidéo prête");
    } catch (error) {
      console.error("❌ Erreur optimisation:", (error as Error).message);
      await videoRef.set(
        {
          status: "error",
          optimized: false,
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    } finally {
      for (const f of [tempInputFile, optimizedFile]) {
        if (existsSync(f)) {
          try {
            unlinkSync(f);
            console.log("🧹 Fichier supprimé :", f);
          } catch (e) {
            console.warn("⚠️ Erreur suppression :", (e as Error).message);
          }
        }
      }
    }

    return null;
  }
);

/* -------------------------------------------------------------------------- */
/* EXISTING EXPORTS                                                            */
/* -------------------------------------------------------------------------- */

export {sendVerificationReminder} from "./reminder";
export {cleanupUnverifiedUsers} from "./cleanup";

/* -------------------------------------------------------------------------- */
/* ACTIONS (Cloud Functions callable)                                          */
/* -------------------------------------------------------------------------- */

export {
  likeVideo,
  reportVideo,
  deleteVideo,
  logClientEvents,
} from "./actions";

/* -------------------------------------------------------------------------- */
/* UPLOAD SESSION                                                              */
/* -------------------------------------------------------------------------- */

export {createUploadSession, finalizeUpload};
