#!/usr/bin/env node

/*
 * Adds the missing social counters to videos/{id} documents.
 *
 * Why this exists: finalizeUpload deliberately refuses client-supplied
 * counters, and createUploadSession did not seed them either, so every video
 * created by the upload pipeline landed in Firestore with no `likes` /
 * `reports` array at all. The mobile app read them back as an immutable empty
 * list, and the first tap on the heart threw UnsupportedError out of an
 * unawaited callback: the like silently did nothing. The app no longer depends
 * on the field being present (lib/models/video.dart normalises it) and
 * createUploadSession now seeds it, but existing documents still need the
 * fields so likeVideo's transaction and the admin dashboards read consistent
 * values.
 *
 * Only ever *adds* absent fields. A document that already has `likes` is left
 * untouched, so this is safe to re-run.
 *
 * Usage:
 *   node .\scripts\backfill-video-social-fields.js --project-id adfoot-production \
 *     --credentials .credentials\adfoot-production-ops.json [--apply]
 *
 * Without --apply it only reports what it would change.
 */

const admin = require("firebase-admin");

const SOCIAL_DEFAULTS = {
  likes: [],
  reports: [],
  reportCount: 0,
  shareCount: 0,
};

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
      "  node .\\scripts\\backfill-video-social-fields.js --project-id <gcp-project> " +
        "[--credentials <service-account.json>] [--apply]",
    ].join("\n"),
  );
}

function missingFields(data) {
  const missing = {};

  if (!Array.isArray(data.likes)) {
    missing.likes = SOCIAL_DEFAULTS.likes;
  }
  if (!Array.isArray(data.reports)) {
    missing.reports = SOCIAL_DEFAULTS.reports;
  }
  if (typeof data.reportCount !== "number") {
    // Keep the counter consistent with whatever the array already holds.
    missing.reportCount = Array.isArray(data.reports) ? data.reports.length : 0;
  }
  if (typeof data.shareCount !== "number") {
    missing.shareCount = SOCIAL_DEFAULTS.shareCount;
  }

  return missing;
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

  if (args.credentials) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = args.credentials;
  }

  const apply = args.apply === "true";

  admin.initializeApp({projectId});
  const db = admin.firestore();

  const snapshot = await db.collection("videos").get();

  const planned = [];
  let batch = db.batch();
  let batched = 0;

  for (const doc of snapshot.docs) {
    const missing = missingFields(doc.data() || {});
    if (Object.keys(missing).length === 0) {
      continue;
    }

    planned.push({id: doc.id, added: Object.keys(missing)});

    if (!apply) {
      continue;
    }

    batch.set(doc.ref, missing, {merge: true});
    batched += 1;

    // Firestore caps a batch at 500 writes.
    if (batched === 400) {
      await batch.commit();
      batch = db.batch();
      batched = 0;
    }
  }

  if (apply && batched > 0) {
    await batch.commit();
  }

  console.log(
    JSON.stringify(
      {
        projectId,
        mode: apply ? "apply" : "dry-run",
        scannedDocs: snapshot.size,
        documentsNeedingBackfill: planned.length,
        planned,
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
              "Set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON path, " +
              "or pass --credentials <path>.",
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
