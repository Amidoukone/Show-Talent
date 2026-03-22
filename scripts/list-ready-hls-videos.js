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
      "  node .\\scripts\\list-ready-hls-videos.js --project-id <gcp-project> [--credentials <service-account.json>] [--limit 10] [--scan 50]",
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

function pickLegacyHlsSource(data) {
  const sources = Array.isArray(data.sources) ? data.sources : [];
  return sources.find((source) => {
    if (!source || typeof source !== "object") {
      return false;
    }

    const type = String(source.type || "").trim().toLowerCase();
    const url = String(source.url || "").trim();
    return isNonEmptyString(url) && (type === "hls" || /\.m3u8(?:$|\?)/i.test(url));
  }) || null;
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
  let readyCount = 0;
  let readyWithPlayback = 0;
  let readyWithPlaybackHls = 0;
  let readyWithLegacySourceHls = 0;
  let readyWithHls = 0;
  let readyAdaptiveEligible = 0;

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.status === "ready") {
      readyCount += 1;
    }

    const playback = data.playback || {};
    const manifest = playback?.hls?.manifest || {};
    const playbackManifestUrl = isNonEmptyString(manifest.url) ? manifest.url : "";
    const legacyHlsSource = pickLegacyHlsSource(data);
    const legacyManifestUrl = isNonEmptyString(legacyHlsSource?.url) ? legacyHlsSource.url : "";
    const manifestUrl = playbackManifestUrl || legacyManifestUrl;
    const adaptiveEligible =
      data.status === "ready" &&
      playback?.mode === "multi_rendition_hls" &&
      playback?.hls?.adaptive === true &&
      typeof playback?.hls?.renditionCount === "number" &&
      playback.hls.renditionCount >= 2;

    if (data.status === "ready" && playback && Object.keys(playback).length > 0) {
      readyWithPlayback += 1;
    }
    if (data.status === "ready" && playbackManifestUrl) {
      readyWithPlaybackHls += 1;
    }
    if (data.status === "ready" && legacyManifestUrl) {
      readyWithLegacySourceHls += 1;
    }
    if (data.status === "ready" && manifestUrl) {
      readyWithHls += 1;
    }
    if (adaptiveEligible) {
      readyAdaptiveEligible += 1;
    }

    if (videos.length >= limit) {
      return;
    }
    if (data.status !== "ready" || !manifestUrl) {
      return;
    }

    videos.push({
      id: doc.id,
      updatedAtUtc: toIso(data.updatedAt),
      optimized: data.optimized === true,
      playbackMode:
        playback.mode ||
        (legacyManifestUrl ? "legacy_sources_hls" : null),
      mp4Url: isNonEmptyString(data.videoUrl) ? data.videoUrl : "",
      mp4Path: playback?.fallback?.path || playback?.sourceAsset?.path || null,
      hlsManifestUrl: manifestUrl,
      hlsManifestPath: manifest.path || legacyHlsSource?.path || null,
      hlsAdaptive:
        playback?.hls?.adaptive === true ||
        (legacyManifestUrl ? false : null),
      hlsRenditionCount:
        typeof playback?.hls?.renditionCount === "number" ?
          playback.hls.renditionCount :
          (legacyManifestUrl ? 1 : null),
      hlsPlaybackEligible: adaptiveEligible,
      hlsSourceOrigin:
        playbackManifestUrl ? "playback" :
        legacyManifestUrl ? "legacy_sources" :
          null,
    });
  });

  console.log(
    JSON.stringify(
      {
        projectId,
        collection: "videos",
        scannedDocs: snapshot.size,
        summary: {
          readyCount,
        readyWithPlayback,
        readyWithPlaybackHls,
        readyWithLegacySourceHls,
        readyWithHls,
        readyAdaptiveEligible,
      },
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
