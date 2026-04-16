/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */
/* eslint-disable eol-last */
/* eslint-disable max-len */

import {tmpdir} from "os";
import {join} from "path";
import {existsSync, unlinkSync} from "node:fs";
import * as fsp from "node:fs/promises";
import {spawn} from "node:child_process";
import {onObjectFinalized, StorageObjectData} from "firebase-functions/v2/storage";
import {CloudEvent} from "firebase-functions/v2";
import {randomUUID} from "crypto";

import {db, fieldValue} from "./firebase";
import {REGION} from "./function_runtime";
import {
  createUploadSession,
  finalizeUpload,
  requestThumbnailUploadUrl,
} from "./upload_session";

/* -------------------------------------------------------------------------- */
/* REGION & INIT                                                               */
/* -------------------------------------------------------------------------- */

const OPTIMIZE_TRIGGER_REGION =
  process.env.OPTIMIZE_TRIGGER_REGION || REGION;
const FIREBASE_CONFIG = parseFirebaseConfig(process.env.FIREBASE_CONFIG);
const STORAGE_BUCKET =
  process.env.STORAGE_BUCKET ||
  FIREBASE_CONFIG?.storageBucket ||
  defaultStorageBucket(process.env.GCLOUD_PROJECT) ||
  "show-talent-5987d.appspot.com";
const OPTIMIZE_TRIGGER_OPTIONS = {
  region: OPTIMIZE_TRIGGER_REGION,
  memory: "2GiB" as const,
  timeoutSeconds: 540,
  maxInstances: 1,
  ...(STORAGE_BUCKET ? {bucket: STORAGE_BUCKET} : {}),
};
const MAX_OPTIMIZE_FILE_SIZE_BYTES = parsePositiveIntEnv(
  process.env.MAX_OPTIMIZE_FILE_SIZE_BYTES,
  120 * 1024 * 1024,
);
const MP4_RENDITION_PRESETS: readonly Mp4RenditionPreset[] = [
  {
    label: "360p",
    height: 360,
    videoBitrate: 450000,
    maxRate: 600000,
    bufSize: 900000,
    audioBitrate: 64000,
  },
  {
    label: "480p",
    height: 480,
    videoBitrate: 900000,
    maxRate: 1100000,
    bufSize: 1650000,
    audioBitrate: 96000,
  },
  {
    label: "720p",
    height: 720,
    videoBitrate: 1800000,
    maxRate: 2200000,
    bufSize: 3300000,
    audioBitrate: 128000,
  },
];
type StorageClient = {
  bucket: (name: string) => {
    file: (path: string) => {
      getMetadata: () => Promise<[unknown]>;
      setMetadata: (metadata: Record<string, unknown>) => Promise<unknown>;
      download: (options: {destination: string}) => Promise<unknown>;
      exists: () => Promise<[boolean]>;
      delete: () => Promise<unknown>;
    };
    upload: (
      path: string,
      options: {destination: string; metadata: Record<string, unknown>},
    ) => Promise<unknown>;
  };
};
type FfmpegBuilder = {
  outputOptions: (options: string[]) => FfmpegBuilder;
  on: (event: string, handler: (arg?: unknown) => void) => FfmpegBuilder;
  save: (path: string) => void;
};
type FfmpegFactory = ((inputPath: string) => FfmpegBuilder) & {
  setFfmpegPath: (path: string) => void;
};

let storagePromise: Promise<StorageClient> | null = null;
let ffmpegPromise: Promise<FfmpegFactory> | null = null;
let ffmpegPathPromise: Promise<string> | null = null;

function getStorage(): Promise<StorageClient> {
  if (!storagePromise) {
    storagePromise = import("@google-cloud/storage").then(
      ({Storage}) => new Storage() as unknown as StorageClient,
    );
  }
  return storagePromise;
}

function getFfmpegPath(): Promise<string> {
  if (!ffmpegPathPromise) {
    ffmpegPathPromise = import("@ffmpeg-installer/ffmpeg").then(
      (module) => module.default.path,
    );
  }
  return ffmpegPathPromise;
}

async function getFfmpeg(): Promise<FfmpegFactory> {
  if (!ffmpegPromise) {
    ffmpegPromise = Promise.all([
      import("fluent-ffmpeg"),
      getFfmpegPath(),
    ]).then(([module, ffmpegPath]) => {
      const ffmpeg = module.default as unknown as FfmpegFactory;
      ffmpeg.setFfmpegPath(ffmpegPath);
      return ffmpeg;
    });
  }
  return ffmpegPromise;
}

/* -------------------------------------------------------------------------- */
/* Utils                                                                       */
/* -------------------------------------------------------------------------- */

function sleep(ms: number) {
  return new Promise((res) => setTimeout(res, ms));
}

function parseFirebaseConfig(
  rawValue: string | undefined,
): {storageBucket?: string} | null {
  if (!rawValue) {
    return null;
  }

  try {
    return JSON.parse(rawValue) as {storageBucket?: string};
  } catch {
    return null;
  }
}

function defaultStorageBucket(projectId: string | undefined): string {
  if (!projectId) {
    return "";
  }
  return `${projectId}.appspot.com`;
}

function parsePositiveIntEnv(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number(rawValue);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.round(parsed);
}

type GcsUserMetadata = Record<string, string>;
interface GcsFileMetadata {
  metadata?: GcsUserMetadata;
}

interface VideoDoc {
  thumbnailPath?: string;
  width?: number;
  height?: number;
}

interface PlaybackSource {
  url: string;
  path: string;
  type: "mp4" | "hls";
  quality: string;
  height: number;
  bitrate?: number;
}

interface PlaybackContract {
  version: number;
  mode: string;
  sources: PlaybackSource[];
  sourceAsset: PlaybackSource;
  fallback: PlaybackSource;
}

interface Mp4RenditionPreset {
  label: string;
  height: number;
  videoBitrate: number;
  maxRate: number;
  bufSize: number;
  audioBitrate: number;
}

interface Mp4Rendition extends Mp4RenditionPreset {
  actualHeight: number;
  scaleDimension: "width" | "height";
  outputFileName: string;
}

interface VideoDimensions {
  width: number;
  height: number;
}

/* -------------------------------------------------------------------------- */
/* Download token helper                                                       */
/* -------------------------------------------------------------------------- */

async function ensureDownloadToken(
  bucketName: string,
  objectPath: string
): Promise<string> {
  const storage = await getStorage();
  const file = storage.bucket(bucketName).file(objectPath);

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

function buildStorageDownloadUrl(
  bucketName: string,
  objectPath: string,
  token: string
): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${
    encodeURIComponent(objectPath)
  }?alt=media&token=${token}`;
}

function buildMp4PlaybackSource(
  url: string,
  objectPath: string,
  rendition: Pick<Mp4Rendition, "label" | "actualHeight" | "videoBitrate">
): PlaybackSource {
  return {
    url,
    path: objectPath,
    type: "mp4",
    quality: rendition.label,
    height: rendition.actualHeight,
    bitrate: rendition.videoBitrate,
  };
}

function buildPlaybackContract(
  mp4Sources: readonly PlaybackSource[],
  fallbackSource: PlaybackSource
): PlaybackContract {
  return {
    version: 2,
    mode: "mp4_only",
    sources: [...mp4Sources],
    sourceAsset: fallbackSource,
    fallback: fallbackSource,
  };
}

function toKbps(bitsPerSecond: number): string {
  return `${Math.round(bitsPerSecond / 1000)}k`;
}

function toEven(value: number): number {
  const rounded = Math.max(2, Math.round(value));
  return rounded % 2 === 0 ? rounded : rounded - 1;
}

function asPositiveInt(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  return Math.round(value);
}

function buildSingleMp4Rendition(
  sourceWidth: number | null,
  sourceHeight: number | null
): Mp4Rendition {
  const normalizedWidth = asPositiveInt(sourceWidth);
  const normalizedHeight = asPositiveInt(sourceHeight);
  const shortEdge =
    normalizedWidth && normalizedHeight ?
      Math.min(normalizedWidth, normalizedHeight) :
      normalizedHeight ?? normalizedWidth;

  let preset =
    shortEdge ?
      [...MP4_RENDITION_PRESETS]
        .reverse()
        .find((candidate) => candidate.height <= shortEdge) :
      undefined;

  if (!preset) {
    const smallestPreset = MP4_RENDITION_PRESETS[0];
    const fallbackHeight = toEven(shortEdge ?? smallestPreset.height);
    preset = {
      ...smallestPreset,
      label: `${fallbackHeight}p`,
      height: fallbackHeight,
    };
  }

  const actualHeight = shortEdge ?
    toEven(Math.min(preset.height, shortEdge)) :
    preset.height;
  const scaleDimension =
    normalizedWidth && normalizedHeight && normalizedWidth <= normalizedHeight ?
      "width" :
      "height";

  return {
    ...preset,
    actualHeight,
    scaleDimension,
    outputFileName: `${preset.label}.mp4`,
  };
}

async function transcodeMp4Rendition(
  inputPath: string,
  outputPath: string,
  rendition: Mp4Rendition
): Promise<void> {
  const ffmpeg = await getFfmpeg();
  const scaleFilter =
    rendition.scaleDimension === "width" ?
      `scale='min(${rendition.actualHeight},trunc(iw/2)*2)':-2` :
      `scale=-2:'min(${rendition.actualHeight},trunc(ih/2)*2)'`;

  await new Promise<void>((resolve, reject) => {
    const cmd = ffmpeg(inputPath)
      .outputOptions([
        "-y",
        "-c:v libx264",
        "-profile:v main",
        "-preset veryfast",
        "-pix_fmt yuv420p",
        "-movflags +faststart",
        `-vf ${scaleFilter}`,
        "-g 30",
        "-keyint_min 30",
        `-b:v ${toKbps(rendition.videoBitrate)}`,
        `-maxrate ${toKbps(rendition.maxRate)}`,
        `-bufsize ${toKbps(rendition.bufSize)}`,
        "-c:a aac",
        `-b:a ${toKbps(rendition.audioBitrate)}`,
        "-ar 48000",
        "-ac 2",
      ])
      .on("end", () => resolve())
      .on("error", (err: unknown) => reject(err))
      .save(outputPath);

    void cmd;
  });
}

function parseVideoDimensionsFromFfmpegLog(
  logOutput: string
): VideoDimensions | null {
  for (const rawLine of logOutput.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line.includes("Video:")) {
      continue;
    }

    const match = /(?:^|[ ,])(\d{2,5})x(\d{2,5})(?:[ ,]|$)/.exec(line);
    if (!match) {
      continue;
    }

    const width = asPositiveInt(Number.parseInt(match[1], 10));
    const height = asPositiveInt(Number.parseInt(match[2], 10));
    if (width && height) {
      return {width, height};
    }
  }

  return null;
}

async function probeVideoDimensions(
  inputPath: string
): Promise<VideoDimensions | null> {
  const ffmpegPath = await getFfmpegPath();
  return new Promise((resolve) => {
    const proc = spawn(ffmpegPath, ["-i", inputPath], {
      stdio: ["ignore", "ignore", "pipe"],
    });

    let stderr = "";

    proc.stderr.on("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
      if (stderr.length > 32768) {
        stderr = stderr.slice(-32768);
      }
    });

    proc.on("error", () => resolve(null));
    proc.on("close", () => resolve(parseVideoDimensionsFromFfmpegLog(stderr)));
  });
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
  const storage = await getStorage();
  const file = storage.bucket(bucketName).file(srcPath);
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
  const storage = await getStorage();
  try {
    const snap = await db.collection("videos").doc(videoId).get();
    const data = snap.data() as VideoDoc | undefined;

    if (data?.thumbnailPath) {
      const f = storage.bucket(bucketName).file(data.thumbnailPath);
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
    const [exists] = await storage.bucket(bucketName).file(p).exists();
    if (exists) return p;
  }

  return null;
}

/* -------------------------------------------------------------------------- */
/* MP4 Optimization                                                            */
/* -------------------------------------------------------------------------- */

export const optimizeMp4Video = onObjectFinalized(
  OPTIMIZE_TRIGGER_OPTIONS,
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
    const objectSize = Number.parseInt(String(object.size ?? "0"), 10);

    if (
      Number.isFinite(objectSize) &&
      objectSize > MAX_OPTIMIZE_FILE_SIZE_BYTES
    ) {
      console.warn(
        `⛔ File too large for optimization (${objectSize} bytes): ${filePath}`,
      );
      await videoRef.set(
        {
          status: "error",
          optimized: false,
          optimizationError: "file_too_large",
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      const storage = await getStorage();
      await storage.bucket(bucketName).file(filePath).delete().catch((error) => {
        console.warn("⚠️ Oversized file deletion skipped:", (error as Error).message);
      });
      return null;
    }

    // ✅ garder le comportement existant : si déjà optimisée via metadata, on marque Firestore
    if (object.metadata?.optimized === "true") {
      console.log("ℹ️ Déjà optimisée (metadata)");
      await videoRef.set({optimized: true}, {merge: true});
      return null;
    }

    const storage = await getStorage();
    const bucket = storage.bucket(bucketName);
    const tempInput = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);

    try {
      await robustDownload(bucketName, filePath, tempInput);
      const videoSnap = await videoRef.get();
      const videoDoc = videoSnap.data() as VideoDoc | undefined;
      const persistedWidth = asPositiveInt(videoDoc?.width) ?? null;
      const persistedHeight = asPositiveInt(videoDoc?.height) ?? null;
      const probedDimensions = await probeVideoDimensions(tempInput);
      const sourceWidth = probedDimensions?.width ?? persistedWidth;
      const sourceHeight = probedDimensions?.height ?? persistedHeight;

      if (probedDimensions) {
        await videoRef.set(
          {
            width: sourceWidth,
            height: sourceHeight,
          },
          {merge: true}
        );

        console.log(
          `Playback source probed from media: ${sourceWidth}x${sourceHeight}`,
        );
      } else if (sourceWidth && sourceHeight) {
        console.log(
          `Playback source reused from metadata: ${sourceWidth}x${sourceHeight}`,
        );
      }

      const fallbackMp4Rendition = buildSingleMp4Rendition(
        sourceWidth,
        sourceHeight,
      );

      if (sourceWidth && sourceHeight) {
        console.log(
          `Single MP4 output selected: ${sourceWidth}x${sourceHeight} -> ${fallbackMp4Rendition.label}`,
        );
      } else {
        console.log(
          `Single MP4 fallback (missing source dimensions) -> ${fallbackMp4Rendition.label}`,
        );
      }

      console.log("🎬 FFmpeg optimisation…");
      await transcodeMp4Rendition(tempInput, optimizedFile, fallbackMp4Rendition);

      console.log("⬆️ Upload optimisé…");
      await bucket.upload(optimizedFile, {
        destination: filePath,
        metadata: {
          contentType: "video/mp4",
          cacheControl: "public,max-age=86400",
          metadata: {optimized: "true"},
        },
      });

      console.log("Uploading canonical MP4 contract...");
      const videoToken = await ensureDownloadToken(bucketName, filePath);
      const videoUrl = buildStorageDownloadUrl(bucketName, filePath, videoToken);
      const fallbackSource = buildMp4PlaybackSource(
        videoUrl,
        filePath,
        fallbackMp4Rendition,
      );
      const mp4Sources: PlaybackSource[] = [fallbackSource];
      const playback = buildPlaybackContract(
        mp4Sources,
        fallbackSource,
      );

      /* ---------------------- Thumbnail URL ---------------------- */

      let thumbnail = "";
      const thumbPath = await tryResolveThumbnailPath(bucketName, videoId);
      if (thumbPath) {
        const thumbToken = await ensureDownloadToken(bucketName, thumbPath);
        thumbnail = buildStorageDownloadUrl(bucketName, thumbPath, thumbToken);
      }

      /* ---------------------- Firestore write ---------------------- */

      await videoRef.set(
        {
          videoUrl,
          playback,
          sources: [...mp4Sources],
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
    }

    return null;
  }
);

/* -------------------------------------------------------------------------- */
/* EXISTING EXPORTS                                                            */
/* -------------------------------------------------------------------------- */

export {cleanupUnverifiedUsers} from "./cleanup";

/* -------------------------------------------------------------------------- */
/* ACTIONS (Cloud Functions callable)                                          */
/* -------------------------------------------------------------------------- */

export {
  likeVideo,
  reportVideo,
  deleteVideo,
  sendUserPush,
  sendOfferFanout,
  sendEventFanout,
  logClientEvents,
  shareVideo,
  videoActionLog,
} from "./actions";

export {provisionManagedAccount} from "./managed_accounts";
export {
  deleteManagedAccount,
  changeManagedAccountRole,
  resendManagedAccountInvite,
  disableManagedAccountAuth,
  enableManagedAccountAuth,
  updateManagedAccountProfile,
} from "./admin_account_actions";
export {
  adminDeleteEvent,
  adminDeleteOffer,
  adminSetEventStatus,
  adminSetOfferStatus,
} from "./admin_content_actions";
export {adminSetContactIntakeFollowUp} from "./admin_contact_intake_actions";
export {completeEmailVerification} from "./account_verification_actions";

/* -------------------------------------------------------------------------- */
/* UPLOAD SESSION                                                              */
/* -------------------------------------------------------------------------- */

export {createUploadSession, finalizeUpload, requestThumbnailUploadUrl};
