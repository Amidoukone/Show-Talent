#!/usr/bin/env node

const admin = require("firebase-admin");

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];

    if (!next || next.startsWith("--")) {
      args[key] = "true";
      continue;
    }

    args[key] = next;
    index += 1;
  }
  return args;
}

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node .\\scripts\\backfill-playback-contract.js --project-id <gcp-project> [--credentials <service-account.json>] [--limit 20] [--scan 100] [--video-id <docId>] [--apply]",
    ].join("\n"),
  );
}

function configureCredentials(args) {
  if (args.credentials) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = args.credentials;
  }
}

function parsePositiveInt(input, flagName) {
  const value = Number.parseInt(String(input), 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return value;
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function toIso(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function normalizeSource(source) {
  if (!source || typeof source !== "object") {
    return null;
  }

  const url = isNonEmptyString(source.url) ? source.url.trim() : "";
  if (!url) {
    return null;
  }

  const type = isNonEmptyString(source.type) ? source.type.trim().toLowerCase() : "";
  const quality = isNonEmptyString(source.quality) ? source.quality.trim() : null;
  const path = isNonEmptyString(source.path) ? source.path.trim() : null;
  const height = typeof source.height === "number" ? source.height : null;
  const bitrate = typeof source.bitrate === "number" ? source.bitrate : null;

  return {
    url,
    type,
    quality,
    path,
    height,
    bitrate,
  };
}

function isMp4Source(source) {
  return source.type === "mp4" || /\.mp4(?:$|\?)/i.test(source.url);
}

function isHlsSource(source) {
  return source.type === "hls" || /\.m3u8(?:$|\?)/i.test(source.url);
}

function compareByHeight(a, b) {
  const left = typeof a.height === "number" ? a.height : 0;
  const right = typeof b.height === "number" ? b.height : 0;
  return left - right;
}

function dedupeSources(sources) {
  const seen = new Set();
  const result = [];

  for (const source of sources) {
    const key = source?.url || "";
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(source);
  }

  return result;
}

function selectCanonicalMp4Source(mp4Sources) {
  const sorted = [...mp4Sources].sort(compareByHeight);

  const exact480 = sorted.find((source) => source.height === 480);
  if (exact480) {
    return exact480;
  }

  for (let index = sorted.length - 1; index >= 0; index -= 1) {
    const source = sorted[index];
    if (typeof source.height === "number" && source.height <= 480) {
      return source;
    }
  }

  return sorted[0] || null;
}

function toPlaybackSourceMap(source) {
  return {
    url: source.url,
    type: "mp4",
    ...(source.path ? {path: source.path} : {}),
    quality: source.quality || (source.height != null ? `${source.height}p` : "480p"),
    ...(source.height != null ? {height: source.height} : {}),
    ...(source.bitrate != null ? {bitrate: source.bitrate} : {}),
  };
}

function normalizePlaybackForComparison(playback) {
  if (!playback || typeof playback !== "object") {
    return null;
  }

  const normalizedSources = dedupeSources(
    (Array.isArray(playback.sources) ? playback.sources : [])
      .map(normalizeSource)
      .filter((source) => source != null && isMp4Source(source)),
  )
    .sort(compareByHeight)
    .map(toPlaybackSourceMap);
  const fallbackSource = normalizeSource(playback.fallback);
  const sourceAsset = normalizeSource(playback.sourceAsset);

  return {
    version: typeof playback.version === "number" ? playback.version : 2,
    mode: isNonEmptyString(playback.mode) ? playback.mode.trim() : null,
    sources: normalizedSources,
    ...(sourceAsset ? {sourceAsset: toPlaybackSourceMap(sourceAsset)} : {}),
    ...(fallbackSource ? {fallback: toPlaybackSourceMap(fallbackSource)} : {}),
    ...(playback.hls &&
    typeof playback.hls === "object" &&
    Object.keys(playback.hls).length > 0 ?
      {hls: playback.hls} :
      {}),
  };
}

function pickPlaybackSources(data, videoId) {
  const existingPlayback =
    data.playback && typeof data.playback === "object" ? data.playback : {};
  const renditionCandidates = [
    ...(Array.isArray(data.sources) ? data.sources : []),
    ...(Array.isArray(existingPlayback.sources) ? existingPlayback.sources : []),
  ];
  const normalized = dedupeSources(
    renditionCandidates
    .map(normalizeSource)
    .filter((source) => source != null),
  );

  const mp4Sources = normalized
    .filter((source) => isMp4Source(source))
    .sort(compareByHeight);
  const legacyFallbackSources = [
    normalizeSource(existingPlayback.fallback),
    normalizeSource(existingPlayback.sourceAsset),
  ].filter((source) => source != null && isMp4Source(source));

  const fallbackMp4 =
    selectCanonicalMp4Source(mp4Sources) ||
    legacyFallbackSources[0] ||
    (isNonEmptyString(data.videoUrl) ?
      {
        url: data.videoUrl.trim(),
        type: "mp4",
        quality: "480p",
        path: isNonEmptyString(data.storagePath) ? data.storagePath.trim() : `videos/${videoId}.mp4`,
        height: 480,
        bitrate: null,
      } :
      null);

  const playbackSources = mp4Sources.length > 0 ? mp4Sources : (fallbackMp4 ? [fallbackMp4] : []);

  return {playbackSources, fallbackMp4};
}

function buildDesiredPlaybackUpdate(data, videoId) {
  const existingPlayback =
    data.playback && typeof data.playback === "object" ? data.playback : null;
  const {fallbackMp4} = pickPlaybackSources(data, videoId);
  if (!fallbackMp4) {
    return null;
  }

  const fallbackSource = {
    url: fallbackMp4.url,
    path: fallbackMp4.path || (isNonEmptyString(data.storagePath) ? data.storagePath.trim() : `videos/${videoId}.mp4`),
    type: "mp4",
    quality: fallbackMp4.quality || "480p",
    ...(fallbackMp4.height != null ? {height: fallbackMp4.height} : {}),
    ...(fallbackMp4.bitrate != null ? {bitrate: fallbackMp4.bitrate} : {}),
  };

  const canonicalSource = toPlaybackSourceMap(fallbackSource);

  const playback = {
    version: 2,
    mode: "mp4_only",
    sources: [canonicalSource],
    sourceAsset: fallbackSource,
    fallback: fallbackSource,
  };

  const nextVideoUrl = fallbackSource.url;
  const currentVideoUrl = isNonEmptyString(data.videoUrl) ? data.videoUrl.trim() : "";
  const currentPlaybackJson = JSON.stringify(
    normalizePlaybackForComparison(existingPlayback),
  );
  const nextPlaybackJson = JSON.stringify(
    normalizePlaybackForComparison(playback),
  );

  if (currentPlaybackJson === nextPlaybackJson && currentVideoUrl === nextVideoUrl) {
    return null;
  }

  return {
    playback,
    videoUrl: nextVideoUrl,
  };
}

async function fetchCandidates(db, args) {
  const videoId = args["video-id"] || null;
  if (videoId) {
    const doc = await db.collection("videos").doc(videoId).get();
    return doc.exists ? [doc] : [];
  }

  const limit = parsePositiveInt(args.limit || "20", "--limit");
  const scan = parsePositiveInt(args.scan || String(Math.max(limit * 5, 25)), "--scan");
  const snapshot = await db
    .collection("videos")
    .orderBy("updatedAt", "desc")
    .limit(scan)
    .get();

  return snapshot.docs.slice(0, scan);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help === "true" || args.h === "true") {
    printUsage();
    process.exit(0);
  }

  const projectId = args["project-id"] || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) {
    printUsage();
    throw new Error("Missing --project-id and GOOGLE_CLOUD_PROJECT.");
  }

  configureCredentials(args);
  admin.initializeApp({projectId});
  const db = admin.firestore();

  const docs = await fetchCandidates(db, args);
  const apply = args.apply === "true";
  const limit = parsePositiveInt(args.limit || "20", "--limit");

  const candidates = [];
  let scanned = 0;
  for (const doc of docs) {
    if (!doc.exists) {
      continue;
    }

    scanned += 1;
    const data = doc.data() || {};
    if (data.status !== "ready") {
      continue;
    }

    const nextUpdate = buildDesiredPlaybackUpdate(data, doc.id);
    if (!nextUpdate) {
      continue;
    }

    candidates.push({
      id: doc.id,
      updatedAtUtc: toIso(data.updatedAt),
      optimized: data.optimized === true,
      status: data.status || null,
      hasHlsSource: !!nextUpdate.playback.hls?.manifest?.url,
      sourceTypes: Array.isArray(data.sources) ?
        data.sources.map((source) => source?.type || null).filter(Boolean) :
        [],
      currentVideoUrl: isNonEmptyString(data.videoUrl) ? data.videoUrl.trim() : null,
      nextVideoUrl: nextUpdate.videoUrl,
      nextPlayback: nextUpdate.playback,
    });

    if (candidates.length >= limit) {
      break;
    }
  }

  if (apply) {
    const batch = db.batch();
    for (const candidate of candidates) {
      const ref = db.collection("videos").doc(candidate.id);
      batch.set(
        ref,
        {
          playback: candidate.nextPlayback,
          videoUrl: candidate.nextVideoUrl,
        },
        {merge: true},
      );
    }
    if (candidates.length > 0) {
      await batch.commit();
    }
  }

  console.log(
    JSON.stringify(
      {
        projectId,
        collection: "videos",
        scannedDocs: scanned,
        dryRun: !apply,
        updatedCount: apply ? candidates.length : 0,
        candidatesCount: candidates.length,
        candidates,
        checkedAtUtc: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  const isAuthError = message.includes("Could not load the default credentials");
  console.error(
    JSON.stringify(
      {
        success: false,
        error: message,
        ...(isAuthError ?
          {
            hint:
              "Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON path, or pass --credentials <path>.",
          } :
          {}),
        checkedAtUtc: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
