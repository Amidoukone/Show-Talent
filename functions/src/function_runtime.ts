/* eslint-disable linebreak-style */

import type {CallableOptions} from "firebase-functions/v2/https";
import type {SupportedRegion} from "firebase-functions/v2/options";

const REGION: SupportedRegion = "europe-west1";

// Keep lightweight Gen 2 functions on the lower Gen 1 CPU profile to reduce
// Cloud Run regional CPU quota pressure without changing the callable API.
const LOW_CPU_REGION_OPTIONS = {
  region: REGION,
  cpu: "gcf_gen1" as const,
};

const LOW_CPU_CALLABLE_OPTIONS = {
  ...LOW_CPU_REGION_OPTIONS,
  cors: true,
  invoker: "public",
  ingressSettings: "ALLOW_ALL",
} satisfies CallableOptions;

/**
 * Parses a non-negative integer from an environment variable.
 *
 * @param {string | undefined} rawValue Raw environment variable value.
 * @param {number} fallback Fallback value used when parsing fails.
 * @return {number} Parsed integer or fallback.
 */
function parseNonNegativeIntEnv(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number(rawValue);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return Math.round(parsed);
}

/**
 * Parses a positive integer from an environment variable.
 *
 * @param {string | undefined} rawValue Raw environment variable value.
 * @param {number} fallback Fallback value used when parsing fails.
 * @return {number} Parsed integer or fallback.
 */
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

// ENFORCE_APPCHECK is true in production/production-next and false
// elsewhere (see functions/.env.*). The Flutter client activates App Check
// app-wide at startup once it's enabled for the running environment (see
// lib/services/app_check_service.dart), so every request from the mobile
// app already carries a token by the time it reaches a callable here.
const ENFORCE_APP_CHECK = process.env.ENFORCE_APPCHECK === "true";
const UPLOAD_CALLABLE_MIN_INSTANCES = parseNonNegativeIntEnv(
  process.env.UPLOAD_CALLABLE_MIN_INSTANCES,
  ENFORCE_APP_CHECK ? 1 : 0,
);
const UPLOAD_CALLABLE_TIMEOUT_SECONDS = parsePositiveIntEnv(
  process.env.UPLOAD_CALLABLE_TIMEOUT_SECONDS,
  120,
);

// For callables reachable ONLY from the mobile app. The admin web app
// (show_talent - web) doesn't activate App Check yet, so callables it also
// calls (admin_*.ts, managed_accounts.ts) must keep using
// LOW_CPU_CALLABLE_OPTIONS as-is — enforcing here would reject every admin
// panel request outright.
const MOBILE_CALLABLE_OPTIONS = {
  ...LOW_CPU_CALLABLE_OPTIONS,
  enforceAppCheck: ENFORCE_APP_CHECK,
} satisfies CallableOptions;

const UPLOAD_CALLABLE_OPTIONS = {
  ...LOW_CPU_CALLABLE_OPTIONS,
  enforceAppCheck: ENFORCE_APP_CHECK,
  timeoutSeconds: UPLOAD_CALLABLE_TIMEOUT_SECONDS,
  minInstances: UPLOAD_CALLABLE_MIN_INSTANCES,
} satisfies CallableOptions;

export {
  ENFORCE_APP_CHECK,
  LOW_CPU_CALLABLE_OPTIONS,
  MOBILE_CALLABLE_OPTIONS,
  UPLOAD_CALLABLE_OPTIONS,
  REGION,
  LOW_CPU_REGION_OPTIONS,
};
