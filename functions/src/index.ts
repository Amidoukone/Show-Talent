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
  "adfoot-production.firebasestorage.app";
// maxInstances: 1 serialized *every* video optimization in the whole service.
// Measured in production: 4m14s for a cold first run, then ~1m to 1m30 each.
// At that rate a burst of uploads queues linearly — twenty near-simultaneous
// uploads left the last user waiting half an hour, and pending Storage events
// eventually expire rather than wait forever.
//
// Raising the ceiling costs nothing at rest: there is no minInstances here, so
// instances exist only while an encode is actually running. It raises peak
// concurrent spend during a burst, which is the trade this feature needs —
// video is the product. Tunable per environment so the ceiling can be moved
// without a code change.
const OPTIMIZE_MAX_INSTANCES = parsePositiveIntEnv(
  process.env.OPTIMIZE_MAX_INSTANCES,
  3,
);
// Raising the quality ceiling to 1080p roughly triples the pixels x264 has to
// chew through per clip, and the 540s budget has to cover download, encode and
// re-upload. Two vCPUs keeps a worst-case 3-minute 1080p encode comfortably
// inside it. Nothing runs at rest -- there is no minInstances here -- so this
// only costs more while an encode is actually happening.
const OPTIMIZE_CPU = parsePositiveIntEnv(process.env.OPTIMIZE_CPU, 2);
const OPTIMIZE_TRIGGER_OPTIONS = {
  region: OPTIMIZE_TRIGGER_REGION,
  memory: "2GiB" as const,
  cpu: OPTIMIZE_CPU,
  timeoutSeconds: 540,
  maxInstances: OPTIMIZE_MAX_INSTANCES,
  ...(STORAGE_BUCKET ? {bucket: STORAGE_BUCKET} : {}),
};
const MAX_OPTIMIZE_FILE_SIZE_BYTES = parsePositiveIntEnv(
  process.env.MAX_OPTIMIZE_FILE_SIZE_BYTES,
  150 * 1024 * 1024,
);
// Quality ceiling, not a target. A clip is only ever scaled *down*, and only
// when its short edge exceeds this. Everything at or under it keeps the exact
// pixel dimensions the phone recorded.
//
// The previous ladder stopped at 720p and, worse, picked the largest preset
// *below* the source's short edge — so a 1024x576 upload was re-encoded to
// 853x480 at 900 kbps and a 1080x1920 one to 720x1280. Users saw exactly that:
// heavier clips came back visibly softer than the file in their gallery.
const MAX_OUTPUT_SHORT_EDGE = parsePositiveIntEnv(
  process.env.MAX_OUTPUT_SHORT_EDGE,
  1080,
);

// Rate ceilings by output short edge. With CRF driving the encode these are
// caps for pathological scenes (confetti, grass in motion, crowd pans), not
// the bitrate every clip lands on -- a calm 1080p clip typically finishes far
// below its ceiling.
const MP4_RENDITION_PRESETS: readonly Mp4RenditionPreset[] = [
  {
    label: "360p",
    height: 360,
    videoBitrate: 900000,
    maxRate: 1200000,
    bufSize: 2400000,
    audioBitrate: 96000,
  },
  {
    label: "480p",
    height: 480,
    videoBitrate: 1600000,
    maxRate: 2200000,
    bufSize: 4400000,
    audioBitrate: 128000,
  },
  {
    label: "720p",
    height: 720,
    videoBitrate: 3500000,
    maxRate: 4500000,
    bufSize: 9000000,
    audioBitrate: 128000,
  },
  {
    label: "1080p",
    height: 1080,
    videoBitrate: 6500000,
    maxRate: 8500000,
    bufSize: 17000000,
    audioBitrate: 160000,
  },
];

// Constant Rate Factor: the encoder spends whatever bits the picture needs to
// hit a visual quality target, instead of forcing every clip through the same
// average bitrate. 20 is visually transparent for phone footage at these
// resolutions.
const OUTPUT_CRF = parsePositiveIntEnv(process.env.OUTPUT_CRF, 20);

// x264 speed/efficiency trade-off. "veryfast" was chosen when the ceiling was
// 720p; at 1080p it wastes roughly a third of the bitrate for the same
// quality. "faster" costs a little more CPU per clip and stays well inside the
// 540s budget.
const OUTPUT_X264_PRESET = process.env.OUTPUT_X264_PRESET || "faster";

// Upper bound on a source we are willing to pass through untouched (see
// shouldRemuxWithoutReencoding). Beyond it the file is re-encoded so a single
// huge upload can't become a huge download for every viewer on mobile data.
const MAX_PASSTHROUGH_BITRATE = parsePositiveIntEnv(
  process.env.MAX_PASSTHROUGH_BITRATE,
  12000000,
);

// --- Companion rendition ---------------------------------------------------
//
// A *second*, lighter MP4 published next to the delivered asset — never
// instead of it. The primary keeps the exact pixels and bitrate it has today:
// a recruiter on wifi sees what the phone filmed, untouched, passthrough
// included.
//
// The point is the other end of the fleet. The app already ships the whole
// adaptive ladder (VideoSourceSelector picks `_bestAtMost(sorted, 540)` on a
// low-tier network) and has never had anything to choose from, because this
// function emits exactly one source. On a connection that cannot sustain a
// 12 Mb/s stream, "one source" means buffering with no way out; the companion
// turns that into a video that plays.
//
// Off by default. Turning it on adds one encode per upload, and on the
// non-passthrough path that is a *second* encode sharing the same 540s budget
// as a worst-case 1080p one — measure a 3-minute clip before enabling this
// fleet-wide. Nothing about the primary asset changes either way.
const COMPANION_RENDITION_ENABLED =
  process.env.COMPANION_RENDITION_ENABLED === "true";
const COMPANION_RENDITION_HEIGHT = parsePositiveIntEnv(
  process.env.COMPANION_RENDITION_HEIGHT,
  480,
);
// Below this delivered bitrate the primary already streams anywhere, and a
// companion would be pure cost: an encode, an object, a token, for a file
// nobody would ever be served.
const COMPANION_MIN_SOURCE_BITRATE = parsePositiveIntEnv(
  process.env.COMPANION_MIN_SOURCE_BITRATE,
  2500000,
);
type StorageClient = {
  bucket: (name: string) => {
    file: (path: string) => {
      getMetadata: () => Promise<[unknown]>;
      setMetadata: (metadata: Record<string, unknown>) => Promise<unknown>;
      download: (
        options: {destination: string} | {start: number; end: number},
      ) => Promise<[Buffer]>;
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
  type: "mp4";
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

interface ProbedMedia extends VideoDimensions {
  // Lowercase ffmpeg codec name ("h264", "hevc", ...), null when unreadable.
  videoCodec: string | null;
  // Lowercase ffmpeg codec name, null when the file carries no audio stream.
  audioCodec: string | null;
  // Container bitrate in bits per second, null when ffmpeg did not report it.
  bitrate: number | null;
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

/**
 * Rate ceiling to apply to an output of the given short edge.
 *
 * The smallest preset at or above the output resolution — never one below it,
 * which is what used to starve a 576-tall clip on a 480p budget.
 *
 * @param {number} outputShortEdge Short edge of the encoded output, in pixels.
 * @return {Mp4RenditionPreset} Bitrate ceilings and label for that size.
 */
function selectRatePreset(outputShortEdge: number): Mp4RenditionPreset {
  const preset = MP4_RENDITION_PRESETS.find(
    (candidate) => candidate.height >= outputShortEdge,
  );
  return preset ?? MP4_RENDITION_PRESETS[MP4_RENDITION_PRESETS.length - 1];
}

function buildSingleMp4Rendition(
  sourceWidth: number | null,
  sourceHeight: number | null
): Mp4Rendition {
  return buildMp4RenditionForCeiling(
    sourceWidth,
    sourceHeight,
    MAX_OUTPUT_SHORT_EDGE,
  );
}

/**
 * Builds the rendition an encode should target for a given short-edge ceiling.
 *
 * Extracted so the companion rendition goes through the exact same scaling
 * rules as the delivered asset — same `min()` guard against upscaling, same
 * short-edge detection, same rate preset lookup — with nothing but the
 * ceiling differing between them.
 *
 * @param {number | null} sourceWidth Probed width, null when unknown.
 * @param {number | null} sourceHeight Probed height, null when unknown.
 * @param {number} ceiling Largest short edge the output may have, in pixels.
 * @return {Mp4Rendition} Scale plan, rate ceilings and output file name.
 */
function buildMp4RenditionForCeiling(
  sourceWidth: number | null,
  sourceHeight: number | null,
  ceiling: number,
): Mp4Rendition {
  const normalizedWidth = asPositiveInt(sourceWidth);
  const normalizedHeight = asPositiveInt(sourceHeight);
  const shortEdge =
    normalizedWidth && normalizedHeight ?
      Math.min(normalizedWidth, normalizedHeight) :
      normalizedHeight ?? normalizedWidth;

  // No source dimensions at all: encode as-is and only cap at the ceiling.
  const actualHeight = shortEdge ?
    toEven(Math.min(shortEdge, ceiling)) :
    ceiling;
  const preset = selectRatePreset(actualHeight);

  // Which dimension the short edge *is*, so the scale filter caps that one and
  // lets the other follow the source aspect ratio (-2 keeps it even).
  const scaleDimension =
    normalizedWidth && normalizedHeight && normalizedWidth <= normalizedHeight ?
      "width" :
      "height";

  return {
    ...preset,
    label: `${actualHeight}p`,
    actualHeight,
    scaleDimension,
    outputFileName: `${actualHeight}p.mp4`,
  };
}

/**
 * Bitrate viewers will actually be served for the delivered asset.
 *
 * On the passthrough path that is the source's own bitrate, not the rendition
 * ceiling — the ceiling would describe an encode that never ran.
 *
 * @param {ProbedMedia | null} media Probe result for the uploaded file.
 * @param {Mp4Rendition} rendition Rendition plan for the delivered asset.
 * @param {boolean} canRemux Whether the asset ships without re-encoding.
 * @return {number | null} Delivered bitrate in bps, null when unknown.
 */
function deliveredBitrate(
  media: ProbedMedia | null,
  rendition: Mp4Rendition,
  canRemux: boolean,
): number | null {
  if (canRemux) {
    return media?.bitrate ?? null;
  }
  return rendition.videoBitrate;
}

/**
 * True when a lighter companion rendition is worth encoding and publishing.
 *
 * Deliberately conservative: every "no" here leaves the video exactly as it
 * ships today, with a single source.
 *
 * @param {ProbedMedia | null} media Probe result for the uploaded file.
 * @param {number | null} delivered Bitrate viewers get for the primary asset.
 * @return {boolean} Whether to build the companion.
 */
function shouldBuildCompanionRendition(
  media: ProbedMedia | null,
  delivered: number | null,
): boolean {
  if (!COMPANION_RENDITION_ENABLED) {
    return false;
  }
  // Without real dimensions the scale filter has nothing to preserve the
  // aspect ratio against, and a companion that reframes the picture is worse
  // than no companion at all.
  if (!media || !media.width || !media.height) {
    return false;
  }
  // Never upscale, and never publish a "lighter" source that is not actually
  // lighter than the one it is meant to relieve.
  if (Math.min(media.width, media.height) <= COMPANION_RENDITION_HEIGHT) {
    return false;
  }
  if (delivered === null || delivered < COMPANION_MIN_SOURCE_BITRATE) {
    return false;
  }
  return true;
}

/**
 * Object path for a rendition published beside the delivered asset.
 *
 * `mp4/{videoId}/...`, never `videos/...`: optimizeMp4Video triggers on every
 * finalized `videos/**.mp4`, so publishing a companion there would re-enter
 * this function with a videoId of `{videoId}_something` and merge a ghost
 * document into the `videos` collection. The `mp4/` prefix is outside the
 * trigger, already public-readable in storage.rules, already owner-deletable
 * there, and already whitelisted by the admin asset collector.
 *
 * @param {string} videoId Firestore document id of the video.
 * @param {string} fileName Rendition file name, e.g. "480p.mp4".
 * @return {string} Full object path inside the bucket.
 */
function buildRenditionObjectPath(videoId: string, fileName: string): string {
  return `mp4/${videoId}/${fileName}`;
}

/**
 * True when the upload can be served as-is, with only its metadata rewritten.
 *
 * Re-encoding an already-fine H.264/AAC MP4 is pure generation loss: the
 * picture can only come back softer than the file the user picked in their
 * gallery, and it costs an ffmpeg run per upload. Every condition here is
 * about what the *player* needs — a codec the app can decode, a resolution
 * within the ceiling, and a bitrate a phone on mobile data can pull — so when
 * they all hold, the honest thing is to keep the user's own pixels.
 *
 * @param {ProbedMedia | null} media Probe result for the uploaded file.
 * @return {boolean} Whether the file can be remuxed instead of re-encoded.
 */
function shouldRemuxWithoutReencoding(media: ProbedMedia | null): boolean {
  if (!media || !media.width || !media.height) {
    return false;
  }
  if (media.videoCodec !== "h264") {
    return false;
  }
  // No audio stream is fine; a non-AAC one is not, since it would have to be
  // re-encoded anyway and a mixed copy/encode run buys nothing.
  if (media.audioCodec !== null && media.audioCodec !== "aac") {
    return false;
  }
  if (Math.min(media.width, media.height) > MAX_OUTPUT_SHORT_EDGE) {
    return false;
  }
  if (media.bitrate !== null && media.bitrate > MAX_PASSTHROUGH_BITRATE) {
    return false;
  }
  return true;
}

/**
 * Rewrites the container without touching a single encoded frame.
 *
 * `-movflags +faststart` is the whole point: it moves the moov atom to the
 * front so playback can start before the file has finished downloading.
 *
 * @param {string} inputPath Local path of the uploaded file.
 * @param {string} outputPath Local path to write.
 * @return {Promise<void>} Resolves once the remux completes.
 */
async function remuxMp4(
  inputPath: string,
  outputPath: string,
): Promise<void> {
  const ffmpeg = await getFfmpeg();

  await new Promise<void>((resolve, reject) => {
    const cmd = ffmpeg(inputPath)
      .outputOptions([
        "-y",
        "-c copy",
        "-movflags +faststart",
      ])
      .on("end", () => resolve())
      .on("error", (err: unknown) => reject(err))
      .save(outputPath);

    void cmd;
  });
}

async function transcodeMp4Rendition(
  inputPath: string,
  outputPath: string,
  rendition: Mp4Rendition
): Promise<void> {
  const ffmpeg = await getFfmpeg();
  // `min(...)` in the filter means a source already at or below the ceiling is
  // never upscaled — it passes through at its native size.
  const scaleFilter =
    rendition.scaleDimension === "width" ?
      `scale='min(${rendition.actualHeight},trunc(iw/2)*2)':-2` :
      `scale=-2:'min(${rendition.actualHeight},trunc(ih/2)*2)'`;

  await new Promise<void>((resolve, reject) => {
    const cmd = ffmpeg(inputPath)
      .outputOptions([
        "-y",
        "-c:v libx264",
        // High profile: better compression at the same quality than main, and
        // universally decodable on the Android/iOS versions this app targets.
        "-profile:v high",
        "-level 4.1",
        `-preset ${OUTPUT_X264_PRESET}`,
        "-pix_fmt yuv420p",
        "-movflags +faststart",
        `-vf ${scaleFilter}`,
        "-g 60",
        "-keyint_min 60",
        // CRF drives quality; maxrate/bufsize only cap the worst case.
        `-crf ${OUTPUT_CRF}`,
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

/**
 * Reads dimensions, codecs and overall bitrate out of `ffmpeg -i` stderr.
 *
 * The lines of interest look like:
 *   Duration: 00:01:09.32, start: 0.000000, bitrate: 4821 kb/s
 *   Stream #0:0(und): Video: h264 (High) (avc1 / ...), yuv420p, 1080x1920, ...
 *   Stream #0:1(und): Audio: aac (LC) (mp4a / ...), 48000 Hz, stereo, ...
 *
 * Every field is optional on purpose: a missing one only costs the caller the
 * remux fast path, never the upload.
 *
 * @param {string} logOutput Raw stderr captured from `ffmpeg -i`.
 * @return {ProbedMedia | null} Parsed media facts, or null without dimensions.
 */
function parseProbedMediaFromFfmpegLog(
  logOutput: string
): ProbedMedia | null {
  let dimensions: VideoDimensions | null = null;
  let videoCodec: string | null = null;
  let audioCodec: string | null = null;
  let bitrate: number | null = null;

  for (const rawLine of logOutput.split(/\r?\n/)) {
    const line = rawLine.trim();

    if (bitrate === null && line.startsWith("Duration:")) {
      const rateMatch = /bitrate:\s*(\d+)\s*kb\/s/i.exec(line);
      if (rateMatch) {
        bitrate = Number.parseInt(rateMatch[1], 10) * 1000;
      }
    }

    if (audioCodec === null && line.includes("Audio:")) {
      const codecMatch = /Audio:\s*([a-z0-9_]+)/i.exec(line);
      if (codecMatch) {
        audioCodec = codecMatch[1].toLowerCase();
      }
    }

    if (!line.includes("Video:")) {
      continue;
    }

    if (videoCodec === null) {
      const codecMatch = /Video:\s*([a-z0-9_]+)/i.exec(line);
      if (codecMatch) {
        videoCodec = codecMatch[1].toLowerCase();
      }
    }

    if (dimensions) {
      continue;
    }

    const match = /(?:^|[ ,])(\d{2,5})x(\d{2,5})(?:[ ,]|$)/.exec(line);
    if (!match) {
      continue;
    }

    const width = asPositiveInt(Number.parseInt(match[1], 10));
    const height = asPositiveInt(Number.parseInt(match[2], 10));
    if (width && height) {
      dimensions = {width, height};
    }
  }

  if (!dimensions) {
    return null;
  }

  return {
    width: dimensions.width,
    height: dimensions.height,
    videoCodec,
    audioCodec,
    bitrate,
  };
}

async function probeMedia(
  inputPath: string
): Promise<ProbedMedia | null> {
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
    proc.on("close", () => resolve(parseProbedMediaFromFfmpegLog(stderr)));
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

    // contentType above is whatever the client declared during upload —
    // trivial to spoof. Check the actual bytes before this file ever
    // reaches ffprobe/ffmpeg: a real MP4 starts with a 4-byte box size
    // followed by the ASCII box type "ftyp" at offset 4-8 (ISO base media
    // file format). A cheap ranged read here avoids running ffmpeg on
    // attacker-controlled bytes and avoids the full download below.
    const earlyStorage = await getStorage();
    const earlyFile = earlyStorage.bucket(bucketName).file(filePath);
    const [magicBytesHeader] = await earlyFile.download({start: 0, end: 11});
    const looksLikeMp4 = magicBytesHeader.length >= 8 &&
      magicBytesHeader.subarray(4, 8).toString("ascii") === "ftyp";

    if (!looksLikeMp4) {
      console.warn(`⛔ Rejected upload that isn't a real MP4: ${filePath}`);
      await videoRef.set(
        {
          status: "error",
          optimized: false,
          optimizationError: "invalid_file_format",
          updatedAt: fieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      await earlyFile.delete().catch((error) => {
        console.warn("⚠️ Invalid file deletion skipped:", (error as Error).message);
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
    // Named here so the `finally` below can reclaim it whether the companion
    // encode succeeded, failed halfway, or never ran.
    let companionFile: string | null = null;

    try {
      await robustDownload(bucketName, filePath, tempInput);
      const videoSnap = await videoRef.get();
      const videoDoc = videoSnap.data() as VideoDoc | undefined;
      const persistedWidth = asPositiveInt(videoDoc?.width) ?? null;
      const persistedHeight = asPositiveInt(videoDoc?.height) ?? null;
      const probedMedia = await probeMedia(tempInput);
      const sourceWidth = probedMedia?.width ?? persistedWidth;
      const sourceHeight = probedMedia?.height ?? persistedHeight;

      if (probedMedia) {
        await videoRef.set(
          {
            width: sourceWidth,
            height: sourceHeight,
          },
          {merge: true}
        );

        console.log(
          `Playback source probed from media: ${sourceWidth}x${sourceHeight} ` +
            `${probedMedia.videoCodec ?? "?"}/${probedMedia.audioCodec ?? "none"} ` +
            `@${probedMedia.bitrate ?? "?"} bps`,
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
      const canRemux = shouldRemuxWithoutReencoding(probedMedia);

      if (canRemux) {
        console.log(
          `Passthrough: source already streamable at ${sourceWidth}x${sourceHeight}, ` +
            "remuxing without re-encoding.",
        );
      } else if (sourceWidth && sourceHeight) {
        console.log(
          `Single MP4 output selected: ${sourceWidth}x${sourceHeight} -> ${fallbackMp4Rendition.label}`,
        );
      } else {
        console.log(
          `Single MP4 fallback (missing source dimensions) -> ${fallbackMp4Rendition.label}`,
        );
      }

      console.log("🎬 FFmpeg optimisation…");
      if (canRemux) {
        await remuxMp4(tempInput, optimizedFile);
      } else {
        await transcodeMp4Rendition(
          tempInput,
          optimizedFile,
          fallbackMp4Rendition,
        );
      }

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
      // On the passthrough path the delivered asset is the source itself, so
      // the contract must advertise the source's own height and bitrate --
      // the rendition ceiling would misreport what viewers actually receive,
      // and the feed-quality metrics are read straight off these fields.
      const deliveredRendition = canRemux && probedMedia ?
        {
          label: `${Math.min(probedMedia.width, probedMedia.height)}p`,
          actualHeight: Math.min(probedMedia.width, probedMedia.height),
          videoBitrate:
            probedMedia.bitrate ?? fallbackMp4Rendition.videoBitrate,
        } :
        fallbackMp4Rendition;

      const fallbackSource = buildMp4PlaybackSource(
        videoUrl,
        filePath,
        deliveredRendition,
      );
      const mp4Sources: PlaybackSource[] = [fallbackSource];

      // The delivered asset is already uploaded and contracted at this point.
      // Everything below is additive and fully isolated: a companion that
      // fails to encode, upload or tokenize leaves the video exactly as it
      // ships without this feature -- one source, full quality, published.
      // A lighter fallback is never worth failing an upload over.
      const companionRendition = shouldBuildCompanionRendition(
        probedMedia,
        deliveredBitrate(probedMedia, fallbackMp4Rendition, canRemux),
      ) ?
        buildMp4RenditionForCeiling(
          sourceWidth,
          sourceHeight,
          COMPANION_RENDITION_HEIGHT,
        ) :
        null;

      if (companionRendition) {
        try {
          console.log(
            `Companion rendition: ${sourceWidth}x${sourceHeight} -> ` +
              `${companionRendition.label}`,
          );
          companionFile = join(
            tmpdir(),
            `companion_${companionRendition.actualHeight}p_${fileName}`,
          );
          await transcodeMp4Rendition(
            tempInput,
            companionFile,
            companionRendition,
          );

          const companionPath = buildRenditionObjectPath(
            videoId,
            companionRendition.outputFileName,
          );
          await bucket.upload(companionFile, {
            destination: companionPath,
            metadata: {
              contentType: "video/mp4",
              cacheControl: "public,max-age=86400",
              // Belt and braces: `mp4/` is outside the trigger prefix, but a
              // future trigger widening must not turn this into a loop.
              metadata: {optimized: "true"},
            },
          });

          const companionToken = await ensureDownloadToken(
            bucketName,
            companionPath,
          );
          const companionSource = buildMp4PlaybackSource(
            buildStorageDownloadUrl(bucketName, companionPath, companionToken),
            companionPath,
            companionRendition,
          );
          // Appended, never prepended: `playback.fallback`, `sourceAsset` and
          // any consumer reading `sources.first` must keep resolving to the
          // full-quality asset exactly as they do today. Only the adaptive
          // selector, which sorts by height itself, looks further.
          mp4Sources.push(companionSource);
          console.log(`Companion rendition published: ${companionPath}`);
        } catch (companionError) {
          console.warn(
            "⚠️ Companion rendition skipped:",
            (companionError as Error).message,
          );
        }
      }

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
          status: "under_review",
          moderationStatus: "pending",
          visibility: "private",
          isPublic: false,
          updatedAt: fieldValue.serverTimestamp(),
          submittedForReviewAt: fieldValue.serverTimestamp(),
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
      const tempFiles = [tempInput, optimizedFile];
      if (companionFile) {
        tempFiles.push(companionFile);
      }
      for (const f of tempFiles) {
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

export {cleanupUnverifiedUsers, reapAbandonedUploadSessions} from "./cleanup";

/* -------------------------------------------------------------------------- */
/* ACTIONS (Cloud Functions callable)                                          */
/* -------------------------------------------------------------------------- */

export {
  likeVideo,
  reportVideo,
  deleteVideo,
  saveUserFcmToken,
  sendUserPush,
  sendOfferFanout,
  sendEventFanout,
  logClientEvents,
  shareVideo,
  videoActionLog,
} from "./actions";
export {followUser, unfollowUser} from "./follow_actions";

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
  adminDeleteVideo,
  adminRejectVideo,
  adminSetVideoStatus,
  adminDeleteEvent,
  adminDeleteOffer,
  adminSetEventStatus,
  adminSetOfferStatus,
} from "./admin_content_actions";
export {
  adminDeleteContactIntake,
  adminDeleteContactIntakeConversation,
  adminSetContactIntakeFollowUp,
  submitContactIntakeFeedback,
} from "./admin_contact_intake_actions";
export {completeEmailVerification} from "./account_verification_actions";
export {deleteOwnAccount} from "./account_deletion_actions";
export {videoSharePage} from "./video_share_page";

/* -------------------------------------------------------------------------- */
/* UPLOAD SESSION                                                              */
/* -------------------------------------------------------------------------- */

export {createUploadSession, finalizeUpload, requestThumbnailUploadUrl};
