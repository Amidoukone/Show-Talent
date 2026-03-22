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
      "  node .\\scripts\\list-ready-playback-contracts.js --project-id <gcp-project> [--credentials <service-account.json>] [--limit 10] [--scan 50]",
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

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function normalizeSource(source) {
  if (!source || typeof source !== "object") {
    return null;
  }

  const url = isNonEmptyString(source.url) ? source.url.trim() : "";
  if (!url) {
    return null;
  }

  return {
    url,
    path: isNonEmptyString(source.path) ? source.path.trim() : null,
    type: isNonEmptyString(source.type) ? source.type.trim().toLowerCase() : null,
    quality: isNonEmptyString(source.quality) ? source.quality.trim() : null,
    height: typeof source.height === "number" ? source.height : null,
    bitrate: typeof source.bitrate === "number" ? source.bitrate : null,
  };
}

function isMp4Source(source) {
  return source && (source.type === "mp4" || /\.mp4(?:$|\?)/i.test(source.url));
}

function isHlsSource(source) {
  return source && (source.type === "hls" || /\.m3u8(?:$|\?)/i.test(source.url));
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

  const limit = parsePositiveInt(args.limit || "10", "--limit");
  const scan = parsePositiveInt(args.scan || String(Math.max(limit * 5, 25)), "--scan");

  configureCredentials(args);
  admin.initializeApp({projectId});
  const db = admin.firestore();

  const snapshot = await db
    .collection("videos")
    .orderBy("updatedAt", "desc")
    .limit(scan)
    .get();

  const videos = [];
  const summary = {
    readyCount: 0,
    readyWithPlayback: 0,
    readyPlaybackV2: 0,
    readyMultiRenditionMp4: 0,
    readyWithThreeMp4Sources: 0,
    readyWithHlsManifest: 0,
  };

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.status !== "ready") {
      return;
    }

    summary.readyCount += 1;

    const playback =
      data.playback && typeof data.playback === "object" ? data.playback : {};
    const playbackVersion =
      typeof playback.version === "number" ? playback.version : null;
    const playbackMode = isNonEmptyString(playback.mode) ? playback.mode.trim() : null;
    const mp4Sources = (Array.isArray(playback.sources) ? playback.sources : [])
      .map(normalizeSource)
      .filter((source) => source && isMp4Source(source));
    const hlsManifest = normalizeSource(playback?.hls?.manifest);
    const fallback = normalizeSource(playback?.fallback);

    if (Object.keys(playback).length > 0) {
      summary.readyWithPlayback += 1;
    }
    if (playbackVersion >= 2) {
      summary.readyPlaybackV2 += 1;
    }
    if (playbackMode === "multi_rendition_mp4") {
      summary.readyMultiRenditionMp4 += 1;
    }
    if (mp4Sources.length >= 3) {
      summary.readyWithThreeMp4Sources += 1;
    }
    if (hlsManifest && isHlsSource(hlsManifest)) {
      summary.readyWithHlsManifest += 1;
    }

    if (videos.length >= limit) {
      return;
    }

    videos.push({
      id: doc.id,
      updatedAtUtc: toIso(data.updatedAt),
      optimized: data.optimized === true,
      status: data.status || null,
      playbackVersion,
      playbackMode,
      videoUrl: isNonEmptyString(data.videoUrl) ? data.videoUrl.trim() : null,
      fallbackPath: fallback?.path || null,
      mp4SourceCount: mp4Sources.length,
      mp4Heights: mp4Sources
        .map((source) => source.height)
        .filter((height) => typeof height === "number"),
      mp4Qualities: mp4Sources
        .map((source) => source.quality)
        .filter((quality) => isNonEmptyString(quality)),
      mp4Paths: mp4Sources
        .map((source) => source.path)
        .filter((path) => isNonEmptyString(path)),
      hlsManifestPath: hlsManifest?.path || null,
      hlsAdaptive: playback?.hls?.adaptive === true,
      hlsRenditionCount:
        typeof playback?.hls?.renditionCount === "number" ?
          playback.hls.renditionCount :
          null,
    });
  });

  console.log(
    JSON.stringify(
      {
        projectId,
        collection: "videos",
        scannedDocs: snapshot.size,
        summary,
        videos,
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
