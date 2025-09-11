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

const REGION = "europe-west1";

ffmpeg.setFfmpegPath(ffmpegInstaller.path);
const gcs = new Storage();

function sleep(ms: number) {
  return new Promise((res) => setTimeout(res, ms));
}

/** Métadonnées personnalisées sur un objet GCS (seule partie utile ici). */
type GcsUserMetadata = Record<string, string>;
interface GcsFileMetadata {
  metadata?: GcsUserMetadata;
}

/** Sous-ensemble utile du document Firestore "videos/{id}". */
interface VideoDoc {
  thumbnailPath?: string;
}

async function ensureDownloadToken(bucketName: string, objectPath: string): Promise<string> {
  const file = gcs.bucket(bucketName).file(objectPath);

  // getMetadata() peut échouer si l’objet vient d’être écrit → catch et retourner [null]
  const [metaRaw] = await file.getMetadata().catch((/* _err */): [null] => [null]);

  // On ne s’intéresse qu’à meta.metadata (user metadata)
  const meta: GcsFileMetadata | null =
    metaRaw && typeof metaRaw === "object" ? (metaRaw as unknown as GcsFileMetadata) : null;

  const md: GcsUserMetadata = meta?.metadata ?? {};
  const raw = md["firebaseStorageDownloadTokens"];
  let token: string | undefined =
    typeof raw === "string" && raw.trim().length > 0 ? raw.trim() : undefined;

  if (!token) {
    token = randomUUID();
    await file.setMetadata({
      metadata: {...md, firebaseStorageDownloadTokens: token},
    });
  }
  return token;
}

async function robustDownload(bucketName: string, srcPath: string, destPath: string, attempts = 3): Promise<void> {
  const file = gcs.bucket(bucketName).file(srcPath);
  let lastErr: unknown = null;

  for (let i = 1; i <= attempts; i++) {
    try {
      console.log(`⬇️ Téléchargement (tentative ${i}/${attempts})…`, srcPath);
      await file.download({destination: destPath});
      const stat = await fsp.stat(destPath);
      if (stat.size > 0) return;
      throw new Error("Fichier téléchargé vide.");
    } catch (e) {
      lastErr = e;
      console.warn(`⚠️ Échec download tentative ${i}:`, (e as Error).message);
      await sleep(250 * i);
    }
  }
  throw lastErr ?? new Error("Échec téléchargement inconnu.");
}

async function tryResolveThumbnailPath(bucketName: string, videoId: string): Promise<string | null> {
  // 1) Firestore (champ thumbnailPath écrit côté client)
  try {
    const snap = await db.collection("videos").doc(videoId).get();
    const data = snap.data() as VideoDoc | undefined;
    if (data?.thumbnailPath) {
      const f = gcs.bucket(bucketName).file(data.thumbnailPath);
      const [exists] = await f.exists();
      if (exists) return String(data.thumbnailPath);
    }
  } catch (e) {
    console.warn("⚠️ Lecture Firestore pour thumbnailPath échouée:", (e as Error).message);
  }

  // 2) Heuristiques
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

/**
 * Optimise une vidéo MP4 uploadée dans "videos/"
 * - Télécharge robuste → encode h264/aac → remplace le fichier
 * - Marque metadata.optimized="true" pour éviter les boucles
 * - Garantit un token de download (vidéo + miniature)
 * - Met à jour Firestore: videoUrl, thumbnail, status="ready", optimized=true
 */
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

    console.log("🎯 Déclenchement pour :", filePath);

    // Filtre strict
    if (!filePath.startsWith("videos/") || !filePath.endsWith(".mp4") || !contentType.startsWith("video/")) {
      console.log("⛔️ Ignoré (pas une vidéo MP4 valide)");
      return;
    }

    // Anti-boucle
    if (object.metadata?.optimized === "true") {
      console.log("ℹ️ Déjà optimisée (metadata.optimized=true).");
      await videoRef.set({optimized: true}, {merge: true});
      return;
    }

    const bucket = gcs.bucket(bucketName);
    const tempInputFile = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);

    try {
      await robustDownload(bucketName, filePath, tempInputFile, 3);
      await sleep(150);

      console.log("🎬 Compression / Optimisation FFmpeg…");
      await new Promise<void>((resolve, reject) => {
        ffmpeg(tempInputFile)
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
          .on("end", () => resolve())
          .on("error", (err) => reject(err))
          .save(optimizedFile);
      });

      console.log("⬆️ Upload optimisé (écrasement au même chemin)...");
      await bucket.upload(optimizedFile, {
        destination: filePath,
        metadata: {
          contentType: "video/mp4",
          cacheControl: "public,max-age=86400",
          metadata: {optimized: "true"},
        },
      });

      // URLs finales (alt=media + token)
      const videoToken = await ensureDownloadToken(bucketName, filePath);
      const videoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
        filePath
      )}?alt=media&token=${videoToken}`;

      let thumbUrl = "";
      const thumbPath = await tryResolveThumbnailPath(bucketName, videoId);
      if (thumbPath) {
        const thumbToken = await ensureDownloadToken(bucketName, thumbPath);
        thumbUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
          thumbPath
        )}?alt=media&token=${thumbToken}`;
      } else {
        console.warn("⚠️ Aucune miniature trouvée pour", videoId);
      }

      await videoRef.set(
        {
          videoUrl,
          ...(thumbUrl ? {thumbnail: thumbUrl} : {}),
          optimized: true,
          status: "ready",
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      console.log("✅ Terminé : Firestore mis à jour (ready + URLs)");
    } catch (error) {
      console.error("❌ Erreur :", (error as Error).message);
      await videoRef.set(
        {status: "error", optimized: false, updatedAt: fieldValue.serverTimestamp()},
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

// Fonctions existantes
export {sendVerificationReminder} from "./reminder";
export {cleanupUnverifiedUsers} from "./cleanup";
