#!/usr/bin/env node

const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");

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
      "  node .\\scripts\\check-feed-playback-metrics.js --project-id <gcp-project> [--credentials <service-account.json>] [--since <ISO-8601 UTC>] [--until <ISO-8601 UTC>] [--window-minutes 60] [--user-id <uid>] [--entry-context <context>]",
    ].join("\n"),
  );
}

function configureCredentials(args) {
  if (args.credentials) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = args.credentials;
  }
}

function parseDate(input, flagName) {
  const date = new Date(input);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return date;
}

function parsePositiveInt(input, flagName) {
  const value = Number.parseInt(String(input), 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return value;
}

function iso(date) {
  return date.toISOString();
}

function safeMetadata(value) {
  return value && typeof value === "object" ? value : {};
}

function asNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function asString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function createAccumulator() {
  return {
    count: 0,
    hadFirstFrameCount: 0,
    completedCount: 0,
    stallRecoverySessions: 0,
    ttfbSamples: 0,
    ttfbSumMs: 0,
    watchDurationSumMs: 0,
    sessionDurationSumMs: 0,
    rebufferCountSum: 0,
    rebufferDurationSumMs: 0,
    rebufferRateSamples: 0,
    rebufferRateSum: 0,
    completionRateSum: 0,
    estimatedBytesSum: 0,
    stallRecoveryRateSamples: 0,
    stallRecoveryRateSum: 0,
  };
}

function ingest(accumulator, metadata) {
  accumulator.count += 1;
  if (metadata.hadFirstFrame === true) {
    accumulator.hadFirstFrameCount += 1;
  }
  if (metadata.completed === true) {
    accumulator.completedCount += 1;
  }
  if (asNumber(metadata.stallRecoveryCount) > 0) {
    accumulator.stallRecoverySessions += 1;
  }

  const timeToFirstFrameMs = asNumber(metadata.timeToFirstFrameMs);
  if (timeToFirstFrameMs != null) {
    accumulator.ttfbSamples += 1;
    accumulator.ttfbSumMs += timeToFirstFrameMs;
  }

  const watchDurationMs = asNumber(metadata.watchDurationMs);
  if (watchDurationMs != null) {
    accumulator.watchDurationSumMs += watchDurationMs;
  }

  const sessionDurationMs = asNumber(metadata.sessionDurationMs);
  if (sessionDurationMs != null) {
    accumulator.sessionDurationSumMs += sessionDurationMs;
  }

  const rebufferCount = asNumber(metadata.rebufferCount);
  if (rebufferCount != null) {
    accumulator.rebufferCountSum += rebufferCount;
  }

  const rebufferDurationMs = asNumber(metadata.rebufferDurationMs);
  if (rebufferDurationMs != null) {
    accumulator.rebufferDurationSumMs += rebufferDurationMs;
  }

  const rebufferRate = asNumber(metadata.rebufferRate);
  if (rebufferRate != null) {
    accumulator.rebufferRateSamples += 1;
    accumulator.rebufferRateSum += rebufferRate;
  }

  const completionRate = asNumber(metadata.completionRate);
  if (completionRate != null) {
    accumulator.completionRateSum += completionRate;
  }

  const estimatedBytesPlayed = asNumber(metadata.estimatedBytesPlayed);
  if (estimatedBytesPlayed != null) {
    accumulator.estimatedBytesSum += estimatedBytesPlayed;
  }

  const stallRecoveryRate = asNumber(metadata.stallRecoveryRate);
  if (stallRecoveryRate != null) {
    accumulator.stallRecoveryRateSamples += 1;
    accumulator.stallRecoveryRateSum += stallRecoveryRate;
  }
}

function finalizeAccumulator(accumulator) {
  if (accumulator.count <= 0) {
    return {
      count: 0,
    };
  }

  return {
    count: accumulator.count,
    hadFirstFrameRate: accumulator.hadFirstFrameCount / accumulator.count,
    completionRate: accumulator.completionRateSum / accumulator.count,
    avgTimeToFirstFrameMs:
      accumulator.ttfbSamples > 0 ?
        Math.round(accumulator.ttfbSumMs / accumulator.ttfbSamples) :
        null,
    avgWatchDurationMs: Math.round(
      accumulator.watchDurationSumMs / accumulator.count,
    ),
    avgSessionDurationMs: Math.round(
      accumulator.sessionDurationSumMs / accumulator.count,
    ),
    avgRebufferCount: accumulator.rebufferCountSum / accumulator.count,
    avgRebufferDurationMs: Math.round(
      accumulator.rebufferDurationSumMs / accumulator.count,
    ),
    avgRebufferRate:
      accumulator.rebufferRateSamples > 0 ?
        accumulator.rebufferRateSum / accumulator.rebufferRateSamples :
        null,
    avgEstimatedBytesPlayed: Math.round(
      accumulator.estimatedBytesSum / accumulator.count,
    ),
    stallRecoverySessionRate:
      accumulator.stallRecoverySessions / accumulator.count,
    avgStallRecoveryRate:
      accumulator.stallRecoveryRateSamples > 0 ?
        accumulator.stallRecoveryRateSum /
          accumulator.stallRecoveryRateSamples :
        null,
  };
}

function latestExample(doc, metadata) {
  return {
    id: doc.id,
    userId: doc.get("userId") || null,
    receivedAtUtc: (() => {
      const value = doc.get("receivedAt");
      if (value && typeof value.toDate === "function") {
        return value.toDate().toISOString();
      }
      return null;
    })(),
    videoId: asString(metadata.videoId),
    entryContext: asString(metadata.entryContext),
    networkTier: asString(metadata.networkTier),
    finalSourceHeight: asNumber(metadata.finalSourceHeight),
    timeToFirstFrameMs: asNumber(metadata.timeToFirstFrameMs),
    rebufferCount: asNumber(metadata.rebufferCount),
    rebufferRate: asNumber(metadata.rebufferRate),
    completionRate: asNumber(metadata.completionRate),
    estimatedBytesPlayed: asNumber(metadata.estimatedBytesPlayed),
    endReason: asString(metadata.endReason),
  };
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

  const until = args.until ? parseDate(args.until, "--until") : new Date();
  const since = args.since ?
    parseDate(args.since, "--since") :
    new Date(until.getTime() - parsePositiveInt(args["window-minutes"] || "60", "--window-minutes") * 60 * 1000);
  const latestLimit = parsePositiveInt(args["latest-limit"] || "5", "--latest-limit");
  const userId = args["user-id"] || null;
  const entryContextFilter = asString(args["entry-context"]);

  configureCredentials(args);
  admin.initializeApp({projectId});
  const db = admin.firestore();

  const snapshot = await db
    .collection("client_logs")
    .where("receivedAt", ">=", Timestamp.fromDate(since))
    .where("receivedAt", "<", Timestamp.fromDate(until))
    .get();

  const overall = createAccumulator();
  const byNetworkTier = {};
  const bySourceHeight = {};
  const byEntryContext = {};
  const problematicSessions = [];

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.source !== "feed_playback") {
      return;
    }
    if (userId && data.userId !== userId) {
      return;
    }

    const metadata = safeMetadata(data.metadata);
    if (
      entryContextFilter &&
      asString(metadata.entryContext) !== entryContextFilter
    ) {
      return;
    }

    ingest(overall, metadata);

    const networkTier = asString(metadata.networkTier) || "unknown";
    byNetworkTier[networkTier] ||= createAccumulator();
    ingest(byNetworkTier[networkTier], metadata);

    const sourceHeight = asNumber(metadata.finalSourceHeight) || 0;
    const sourceHeightKey = sourceHeight > 0 ? `${sourceHeight}p` : "unknown";
    bySourceHeight[sourceHeightKey] ||= createAccumulator();
    ingest(bySourceHeight[sourceHeightKey], metadata);

    const entryContext = asString(metadata.entryContext) || "unknown";
    byEntryContext[entryContext] ||= createAccumulator();
    ingest(byEntryContext[entryContext], metadata);

    const isProblematic =
      metadata.hadFirstFrame !== true ||
      asNumber(metadata.rebufferCount) > 0 ||
      asNumber(metadata.stallRecoveryCount) > 0;
    if (isProblematic && problematicSessions.length < latestLimit) {
      problematicSessions.push(latestExample(doc, metadata));
    }
  });

  const summary = finalizeAccumulator(overall);
  const interpretation =
    summary.count <= 0 ?
      {
        note:
          "No feed_playback sessions found in the selected window. Check the deployed mobile build, session sample rate, and client traffic.",
      } :
      {
        note:
          "Use avgTimeToFirstFrameMs, avgRebufferRate, completionRate, and avgEstimatedBytesPlayed to compare MP4-first windows by networkTier, sourceHeight, and entryContext.",
      };

  console.log(
    JSON.stringify(
      {
        projectId,
        collection: "client_logs",
        filters: {
          sinceUtc: iso(since),
          untilUtc: iso(until),
          userId,
          entryContext: entryContextFilter || null,
        },
        scannedDocs: snapshot.size,
        summary,
        breakdowns: {
          byNetworkTier: Object.fromEntries(
            Object.entries(byNetworkTier).map(([key, value]) => [
              key,
              finalizeAccumulator(value),
            ]),
          ),
          bySourceHeight: Object.fromEntries(
            Object.entries(bySourceHeight).map(([key, value]) => [
              key,
              finalizeAccumulator(value),
            ]),
          ),
          byEntryContext: Object.fromEntries(
            Object.entries(byEntryContext).map(([key, value]) => [
              key,
              finalizeAccumulator(value),
            ]),
          ),
        },
        problematicSessions,
        interpretation,
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
