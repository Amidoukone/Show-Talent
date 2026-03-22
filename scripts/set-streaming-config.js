#!/usr/bin/env node

const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");

const PRESETS = {
  off: {
    adaptiveEnabled: false,
    rolloutPercent: 0,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
  },
  single_mp4: {
    adaptiveEnabled: false,
    rolloutPercent: 0,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
  },
  contract_mp4: {
    adaptiveEnabled: true,
    rolloutPercent: 100,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
  },
  hls_canary: {
    adaptiveEnabled: true,
    rolloutPercent: 10,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
  },
  hls_full: {
    adaptiveEnabled: true,
    rolloutPercent: 100,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
  },
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
      "  node .\\scripts\\set-streaming-config.js --project-id <gcp-project> [--credentials <service-account.json>] --show",
      "  node .\\scripts\\set-streaming-config.js --project-id <gcp-project> [--credentials <service-account.json>] --preset <off|single_mp4|contract_mp4|hls_canary|hls_full> [--reason \"...\"] [--dry-run]",
      "  node .\\scripts\\set-streaming-config.js --project-id <gcp-project> [--credentials <service-account.json>] --adaptive-enabled <true|false> --rollout-percent <0-100> --hls-playback-enabled <true|false> --prefer-hls-playback <true|false>",
    ].join("\n"),
  );
}

function configureCredentials(args) {
  if (args.credentials) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = args.credentials;
  }
}

function parseBoolean(input, flagName) {
  const value = String(input).trim().toLowerCase();
  if (["true", "1", "yes", "y"].includes(value)) {
    return true;
  }
  if (["false", "0", "no", "n"].includes(value)) {
    return false;
  }
  throw new Error(`Invalid ${flagName}: ${input}`);
}

function parsePercent(input, flagName) {
  const value = Number.parseInt(String(input), 10);
  if (!Number.isFinite(value) || value < 0 || value > 100) {
    throw new Error(`Invalid ${flagName}: ${input}`);
  }
  return value;
}

function clonePreset(name) {
  const preset = PRESETS[name];
  if (!preset) {
    throw new Error(
      `Unknown --preset ${name}. Valid presets: ${Object.keys(PRESETS).join(", ")}`,
    );
  }
  return {...preset};
}

function buildNextConfig(args) {
  const base = args.preset ? clonePreset(args.preset) : {};

  if (args["adaptive-enabled"] != null) {
    base.adaptiveEnabled = parseBoolean(
      args["adaptive-enabled"],
      "--adaptive-enabled",
    );
  }
  if (args["rollout-percent"] != null) {
    base.rolloutPercent = parsePercent(
      args["rollout-percent"],
      "--rollout-percent",
    );
  }
  if (args["hls-playback-enabled"] != null) {
    base.hlsPlaybackEnabled = parseBoolean(
      args["hls-playback-enabled"],
      "--hls-playback-enabled",
    );
  }
  if (args["prefer-hls-playback"] != null) {
    base.preferHlsPlayback = parseBoolean(
      args["prefer-hls-playback"],
      "--prefer-hls-playback",
    );
  }

  const requiredKeys = [
    "adaptiveEnabled",
    "rolloutPercent",
    "hlsPlaybackEnabled",
    "preferHlsPlayback",
  ];

  for (const key of requiredKeys) {
    if (base[key] == null) {
      throw new Error(
        `Missing ${key}. Use --preset or pass all explicit flags.`,
      );
    }
  }

  return {
    adaptiveEnabled: base.adaptiveEnabled,
    rolloutPercent: base.rolloutPercent,
    hlsPlaybackEnabled: false,
    preferHlsPlayback: false,
    // Legacy mirror for older clients still reading `useHls`.
    useHls: false,
  };
}

function buildOpsMetadata(args) {
  return {
    preset: args.preset || null,
    reason: args.reason || null,
    updatedBy:
      process.env.USERNAME ||
      process.env.USER ||
      process.env.EMAIL ||
      "unknown",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function readCurrentConfig(docRef) {
  const snapshot = await docRef.get();
  return snapshot.exists ? snapshot.data() : null;
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
  const docRef = db.collection("config").doc("streaming");

  if (args.show === "true") {
    const current = await readCurrentConfig(docRef);
    console.log(
      JSON.stringify(
        {
          projectId,
          documentPath: "config/streaming",
          exists: current != null,
          current,
          checkedAtUtc: new Date().toISOString(),
        },
        null,
        2,
      ),
    );
    return;
  }

  const nextConfig = buildNextConfig(args);
  const payload = {
    ...nextConfig,
    ops: buildOpsMetadata(args),
  };

  if (args["dry-run"] === "true") {
    console.log(
      JSON.stringify(
        {
          projectId,
          documentPath: "config/streaming",
          dryRun: true,
          next: payload,
          checkedAtUtc: new Date().toISOString(),
        },
        null,
        2,
      ),
    );
    return;
  }

  await docRef.set(payload, {merge: true});
  const current = await readCurrentConfig(docRef);

  console.log(
    JSON.stringify(
      {
        success: true,
        projectId,
        documentPath: "config/streaming",
        applied: nextConfig,
        current,
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
