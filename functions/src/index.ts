/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */
/* eslint-disable max-len */

import {tmpdir} from "os";
import {join, relative, sep, posix} from "path";
import {existsSync, unlinkSync} from "node:fs";
import * as fsp from "node:fs/promises";
import {Storage} from "@google-cloud/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import {onObjectFinalized, StorageObjectData} from "firebase-functions/v2/storage";
import {CloudEvent} from "firebase-functions/v2";
import {randomUUID} from "crypto";

import {db, fieldValue} from "./firebase";
import {
  createUploadSession,
  finalizeUpload,
  requestThumbnailUploadUrl,
} from "./upload_session";

/* -------------------------------------------------------------------------- */
/* REGION & INIT                                                               */
/* -------------------------------------------------------------------------- */

const REGION = "europe-west1";
const HLS_SEGMENT_TIME_SECONDS = 6;

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

function toPosixPath(p: string): string {
  return p.split(sep).join("/");
}

async function listFilesRecursively(dir: string): Promise<string[]> {
  const entries = await fsp.readdir(dir, {withFileTypes: true});
  const files: string[] = [];

  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFilesRecursively(full));
    } else if (entry.isFile()) {
      files.push(full);
    }
  }
  return files;
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
/* MP4 + HLS Optimization                                                      */
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

    console.log("🎯 Optimize trigger:", filePath);

    if (
      !filePath.startsWith("videos/") ||
      !filePath.endsWith(".mp4") ||
      !contentType.startsWith("video/")
    ) {
      console.log("⛔️ Ignoré (non MP4)");
      return null;
    }

    const fileName = filePath.split("/").pop();
    if (!fileName) {
      console.log("⛔️ Ignoré (fileName introuvable)");
      return null;
    }

    const videoId = fileName.replace(/\.mp4$/i, "");
    const videoRef = db.collection("videos").doc(videoId);

    // ✅ garder le comportement existant : si déjà optimisée via metadata, on marque Firestore
    if (object.metadata?.optimized === "true") {
      console.log("ℹ️ Déjà optimisée (metadata)");
      await videoRef.set({optimized: true}, {merge: true});
      return null;
    }

    const bucket = gcs.bucket(bucketName);
    const tempInput = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);
    const hlsDir = join(tmpdir(), `hls_${videoId}_${Date.now()}`);

    try {
      await robustDownload(bucketName, filePath, tempInput);

      console.log("🎬 FFmpeg optimisation…");
      await new Promise<void>((resolve, reject) => {
        const cmd = ffmpeg(tempInput)
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
          .on("error", (err: unknown) => reject(err))
          .save(optimizedFile);

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

      /* ---------------------- HLS generation ---------------------- */

      console.log("🎞️ Génération HLS…");
      const renditionDir = join(hlsDir, "480p");
      await fsp.mkdir(renditionDir, {recursive: true});

      await new Promise<void>((resolve, reject) => {
        const cmd = ffmpeg(optimizedFile)
          .outputOptions([
            "-y",
            "-c:v libx264",
            "-profile:v main",
            "-preset veryfast",
            "-crf 23",
            "-vf scale=-2:480",
            "-g 30",
            "-keyint_min 30",
            "-maxrate 1M",
            "-bufsize 2M",
            "-c:a aac",
            "-b:a 96k",
            `-hls_time ${HLS_SEGMENT_TIME_SECONDS}`,
            "-hls_playlist_type vod",
            `-hls_segment_filename ${join(renditionDir, "seg_%03d.ts")}`,
          ])
          .on("end", () => resolve())
          .on("error", (err: unknown) => reject(err))
          .save(join(renditionDir, "480p.m3u8"));

        void cmd;
      });

      const masterPath = join(hlsDir, "master.m3u8");
      const masterPlaylist = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480",
        "480p/480p.m3u8",
        "",
      ].join("\n");

      await fsp.writeFile(masterPath, masterPlaylist, "utf8");

      /* ---------------------- Upload HLS files ---------------------- */

      const hlsPrefix = `hls/${videoId}`;
      const hlsFiles = await listFilesRecursively(hlsDir);

      const urlMap = new Map<string, string>();// relPath -> URL tokenisée
      const tokenMap = new Map<string, string>(); // relPath -> token

      // 1) upload tous les fichiers
      for (const file of hlsFiles) {
        const rel = toPosixPath(relative(hlsDir, file));
        const dest = `${hlsPrefix}/${rel}`;
        const isPlaylist = rel.endsWith(".m3u8");

        await bucket.upload(file, {
          destination: dest,
          metadata: {
            contentType: isPlaylist ?
              "application/vnd.apple.mpegurl" :
              "video/MP2T",
            cacheControl: "public,max-age=86400",
          },
        });
      }

      // 2) assurer token + construire les URLs
      for (const file of hlsFiles) {
        const rel = toPosixPath(relative(hlsDir, file));
        const dest = `${hlsPrefix}/${rel}`;

        const token = await ensureDownloadToken(bucketName, dest);
        tokenMap.set(rel, token);

        const url =
          `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
            dest
          )}?alt=media&token=${token}`;

        urlMap.set(rel, url);
      }

      // 3) réécrire les playlists pour pointer sur URLs tokenisées
      for (const rel of urlMap.keys()) {
        if (!rel.endsWith(".m3u8")) continue;

        const playlistLocalPath = join(hlsDir, rel);
        const original = await fsp.readFile(playlistLocalPath, "utf8");

        const rewritten = original
          .split(/\r?\n/)
          .map((line) => {
            if (!line || line.startsWith("#")) return line;

            const resolved = posix.normalize(
              posix.join(posix.dirname(rel), line)
            );

            return urlMap.get(resolved) ?? line;
          })
          .join("\n");

        const dest = `${hlsPrefix}/${rel}`;
        const token = tokenMap.get(rel) ?? "";

        // ✅ save écrase le fichier dans GCS en conservant le token
        await bucket.file(dest).save(rewritten, {
          metadata: {
            contentType: "application/vnd.apple.mpegurl",
            cacheControl: "public,max-age=86400",
            ...(token ? {metadata: {firebaseStorageDownloadTokens: token}} : {}),
          },
        });
      } // ✅ fermeture boucle playlists

      /* ---------------------- Build MP4 URL ---------------------- */

      const videoToken = await ensureDownloadToken(bucketName, filePath);
      const videoUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
          filePath
        )}?alt=media&token=${videoToken}`;

      const hlsUrl = urlMap.get("master.m3u8") ?? "";
      if (!hlsUrl) {
        console.warn("⚠️ HLS master introuvable, fallback MP4 only.");
      }

      /* ---------------------- Thumbnail URL ---------------------- */

      let thumbnail = "";
      const thumbPath = await tryResolveThumbnailPath(bucketName, videoId);
      if (thumbPath) {
        const thumbToken = await ensureDownloadToken(bucketName, thumbPath);
        thumbnail =
          `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(
            thumbPath
          )}?alt=media&token=${thumbToken}`;
      }

      /* ---------------------- Firestore write ---------------------- */

      await videoRef.set(
        {
          videoUrl,
          sources: [
            {
              url: videoUrl,
              type: "mp4",
              quality: "480p",
              height: 480,
            },
            ...(hlsUrl ?
              [
                {
                  url: hlsUrl,
                  type: "hls",
                  quality: "auto",
                  height: 480,
                },
              ] :
              []),
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
      for (const f of [tempInput, optimizedFile]) {
        if (existsSync(f)) {
          try {
            unlinkSync(f);
            console.log("🧹 Fichier supprimé :", f);
          } catch (e) {
            console.warn("⚠️ Erreur suppression :", (e as Error).message);
          }
        }
      }

      if (existsSync(hlsDir)) {
        try {
          await fsp.rm(hlsDir, {recursive: true, force: true});
          console.log("🧹 Dossier HLS supprimé :", hlsDir);
        } catch (e) {
          console.warn("⚠️ Erreur suppression HLS :", (e as Error).message);
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
  shareVideo,
  videoActionLog,
} from "./actions";

/* -------------------------------------------------------------------------- */
/* UPLOAD SESSION                                                              */
/* -------------------------------------------------------------------------- */

export {createUploadSession, finalizeUpload, requestThumbnailUploadUrl};
