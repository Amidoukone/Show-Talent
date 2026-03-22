#!/usr/bin/env node

const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = "true";
      continue;
    }

    args[key] = next;
    i += 1;
  }
  return args;
}

function printUsage() {
  console.error(
    [
      "Usage:",
      "  node .\\scripts\\check-video-manager-log-sampling.js \\",
      "    --project-id <gcp-project> \\",
      "    --cutoff <ISO-8601 UTC timestamp> \\",
      "    --window-minutes <minutes>",
    ].join("\n"),
  );
}

function parseDateOrThrow(input, flagName) {
  const date = new Date(input);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return date;
}

function parsePositiveIntOrThrow(input, flagName) {
  const value = Number.parseInt(input, 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return value;
}

function iso(date) {
  return date.toISOString();
}

async function countVideoManagerLogs(db, start, end) {
  const snapshot = await db
    .collection("client_logs")
    .where("receivedAt", ">=", Timestamp.fromDate(start))
    .where("receivedAt", "<", Timestamp.fromDate(end))
    .get();

  const counts = {
    totalWindowDocs: snapshot.size,
    matchingSourceDocs: 0,
    info: 0,
    error: 0,
    otherLevel: 0,
  };

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (data.source !== "video_manager") {
      return;
    }

    counts.matchingSourceDocs += 1;

    if (data.level === "error") {
      counts.error += 1;
      return;
    }

    if (data.level === "info") {
      counts.info += 1;
      return;
    }

    counts.otherLevel += 1;
  });

  return counts;
}

function buildSummary(before, after) {
  const infoDropRatio =
    before.info > 0 ? Number((after.info / before.info).toFixed(4)) : null;
  const infoDropped =
    before.info > 0 ? after.info < before.info : after.info === 0;
  const errorSignalPresent = after.error > 0;

  return {
    infoDropRatio,
    infoDropped,
    errorSignalPresent,
    interpretation: {
      info:
        before.info > 0 ?
          "after.info should be materially lower than before.info" :
          "no before-window info baseline was present",
      error:
        after.error > 0 ?
          "error logs are still present after rollout" :
          "no after-window error observed; extend the window or reproduce a staging failure",
    },
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help === "true" || args.h === "true") {
    printUsage();
    process.exit(0);
  }

  const projectId = args["project-id"] || process.env.GOOGLE_CLOUD_PROJECT;
  const cutoffRaw = args.cutoff;
  const windowMinutesRaw = args["window-minutes"];

  if (!projectId || !cutoffRaw || !windowMinutesRaw) {
    printUsage();
    process.exit(1);
  }

  const cutoff = parseDateOrThrow(cutoffRaw, "--cutoff");
  const windowMinutes = parsePositiveIntOrThrow(
    windowMinutesRaw,
    "--window-minutes",
  );

  const windowMs = windowMinutes * 60 * 1000;
  const beforeStart = new Date(cutoff.getTime() - windowMs);
  const beforeEnd = cutoff;
  const afterStart = cutoff;
  const afterEnd = new Date(cutoff.getTime() + windowMs);

  admin.initializeApp({projectId});
  const db = admin.firestore();

  const before = await countVideoManagerLogs(db, beforeStart, beforeEnd);
  const after = await countVideoManagerLogs(db, afterStart, afterEnd);

  const result = {
    projectId,
    collection: "client_logs",
    source: "video_manager",
    cutoffUtc: iso(cutoff),
    windowMinutes,
    windows: {
      before: {
        startUtc: iso(beforeStart),
        endUtc: iso(beforeEnd),
        counts: before,
      },
      after: {
        startUtc: iso(afterStart),
        endUtc: iso(afterEnd),
        counts: after,
      },
    },
    summary: buildSummary(before, after),
    checkedAtUtc: new Date().toISOString(),
  };

  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(
    JSON.stringify(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
        checkedAtUtc: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
  process.exit(1);
});
