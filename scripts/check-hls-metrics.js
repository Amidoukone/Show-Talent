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
      "  node .\\scripts\\check-hls-metrics.js --project-id <gcp-project> [--credentials <service-account.json>] [--since <ISO-8601 UTC>] [--until <ISO-8601 UTC>] [--window-minutes 60] [--user-id <uid>] [--url-contains <substring>]",
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

function safeMetadata(entry) {
  return entry && typeof entry === "object" ? entry : {};
}

function latestExample(doc, metadata) {
  return {
    id: doc.id,
    userId: doc.get("userId") || null,
    level: doc.get("level") || null,
    message: doc.get("message") || null,
    receivedAtUtc: (() => {
      const value = doc.get("receivedAt");
      if (value && typeof value.toDate === "function") {
        return value.toDate().toISOString();
      }
      return null;
    })(),
    url: typeof metadata.url === "string" ? metadata.url : null,
    sourceType: typeof metadata.sourceType === "string" ? metadata.sourceType : null,
    requestedHls: metadata.requestedHls === true,
    usedStreamFallback: metadata.usedStreamFallback === true,
    fallbackFromSourceType:
      typeof metadata.fallbackFromSourceType === "string" ?
        metadata.fallbackFromSourceType :
        null,
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
  const urlContains = (args["url-contains"] || "").toLowerCase().trim();

  configureCredentials(args);
  admin.initializeApp({projectId});
  const db = admin.firestore();

  const snapshot = await db
    .collection("client_logs")
    .where("receivedAt", ">=", Timestamp.fromDate(since))
    .where("receivedAt", "<", Timestamp.fromDate(until))
    .get();

  const summary = {
    totalVideoManagerLogs: 0,
    successLogs: 0,
    errorLogs: 0,
    requestedHlsSuccess: 0,
    actualHlsSuccess: 0,
    mp4Success: 0,
    requestedHlsEndedAsMp4: 0,
    streamFallbackSuccess: 0,
    hlsRequestedErrors: 0,
    hlsSourceErrors: 0,
    sourceTypes: {},
  };

  const latestRequestedHls = [];
  const latestHlsErrors = [];

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.source !== "video_manager") {
      return;
    }
    if (userId && data.userId !== userId) {
      return;
    }

    const metadata = safeMetadata(data.metadata);
    const url = typeof metadata.url === "string" ? metadata.url : "";
    if (urlContains && !url.toLowerCase().includes(urlContains)) {
      return;
    }

    const level = data.level === "error" ? "error" : "info";
    const message = typeof data.message === "string" ? data.message : "";
    const sourceType =
      typeof metadata.sourceType === "string" && metadata.sourceType ?
        metadata.sourceType :
        "unknown";
    const requestedHls = metadata.requestedHls === true;
    const usedStreamFallback = metadata.usedStreamFallback === true;
    const isSuccess = level === "info" && message === "Video init success";
    const isError = level === "error" && message === "Video init error";

    summary.totalVideoManagerLogs += 1;
    summary.sourceTypes[sourceType] = (summary.sourceTypes[sourceType] || 0) + 1;

    if (isSuccess) {
      summary.successLogs += 1;

      if (requestedHls) {
        summary.requestedHlsSuccess += 1;
      }
      if (sourceType === "hls") {
        summary.actualHlsSuccess += 1;
      }
      if (sourceType === "mp4") {
        summary.mp4Success += 1;
      }
      if (requestedHls && sourceType === "mp4") {
        summary.requestedHlsEndedAsMp4 += 1;
      }
      if (usedStreamFallback) {
        summary.streamFallbackSuccess += 1;
      }
      if (requestedHls && latestRequestedHls.length < latestLimit) {
        latestRequestedHls.push(latestExample(doc, metadata));
      }
      return;
    }

    if (isError) {
      summary.errorLogs += 1;
      if (requestedHls) {
        summary.hlsRequestedErrors += 1;
      }
      if (sourceType === "hls") {
        summary.hlsSourceErrors += 1;
      }
      if ((requestedHls || sourceType === "hls") && latestHlsErrors.length < latestLimit) {
        latestHlsErrors.push(latestExample(doc, metadata));
      }
    }
  });

  const interpretation = {
    requestedHlsObserved: summary.requestedHlsSuccess > 0 || summary.hlsRequestedErrors > 0,
    actualHlsObserved: summary.actualHlsSuccess > 0,
    fallbackObserved: summary.requestedHlsEndedAsMp4 > 0 || summary.streamFallbackSuccess > 0,
    note:
      summary.requestedHlsSuccess === 0 && summary.hlsRequestedErrors === 0 ?
        "No HLS-requested metrics observed. Check rollout bucket, device build, and mobile success sample rate." :
      summary.actualHlsSuccess === 0 ?
        "HLS was requested but no successful HLS init was observed. Inspect fallback/error examples." :
        "HLS success was observed on at least one client log in the selected window.",
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
          urlContains: urlContains || null,
        },
        scannedDocs: snapshot.size,
        summary,
        interpretation,
        latestRequestedHls,
        latestHlsErrors,
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
