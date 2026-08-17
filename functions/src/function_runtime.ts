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

/**
 * App Check posture for callables reachable from the mobile app.
 *
 * - "enforce": the platform rejects any call without a valid App Check token
 *   before our handler ever runs.
 * - "soft": the token is still read and attached to `request.app` when the
 *   client managed to produce one, but a missing/invalid token no longer
 *   rejects the call. Handlers log the outcome (see
 *   describeAppCheckState/logAppCheckState) so the real attestation success
 *   rate can be measured from Functions logs.
 * - "off": App Check is ignored entirely.
 *
 * Production runs in "soft", and that is a settled decision rather than a
 * temporary observation window. Play Integrity attestation fails outright on
 * a large share of the real device fleet this app serves (Play-uncertified
 * handsets, missing or outdated Play services, slow first attestation).
 * Production client logs showed `403 App attestation failed` and 15s
 * activation timeouts on ordinary user phones. Under "enforce" that single
 * signal took down every mobile callable at once — uploads, likes, follows,
 * FCM token registration, even logClientEvents, which is precisely why the
 * failures were so hard to see. Enforcement would trade a real, measurable
 * outage for a hypothetical attacker.
 *
 * Soft mode is defensible here because App Check was never the thing holding
 * the door shut. The controls that actually do:
 *
 * - every handler verifies the Firebase ID token (resolveCallableAuth);
 * - there is no self-signup at all — accounts are provisioned by an admin
 *   through the separate admin web app, so reaching any callable requires a
 *   real account somebody deliberately created;
 * - role and account state are checked per call (assertUploadCallerEligible,
 *   assertAdminCaller);
 * - the upload path enforces per-user daily, concurrent, pending-review and
 *   public-video quotas plus file size and duration limits;
 * - the outbound push paths are rate limited per user, because those are the
 *   calls whose blast radius extends beyond the caller;
 * - Firestore and Storage rules gate every document and object by ownership,
 *   independently of the callables.
 *
 * App Check remains switched on as a *signal*: tokens are still read and
 * attached to `request.app` when a device manages to produce one, and every
 * handler records the outcome (see logAppCheckState). What changed is that a
 * missing token no longer costs an honest user their upload.
 *
 * Flipping this back to "enforce" is a breaking change to the mobile fleet,
 * not a hardening tweak. See the guardrail in
 * test/app_check_posture_guardrails_test.dart.
 */
type AppCheckMode = "enforce" | "soft" | "off";

/**
 * Resolves the App Check mode from the environment.
 *
 * APP_CHECK_MODE wins when set. Otherwise the legacy ENFORCE_APPCHECK flag is
 * mapped to "soft" (not "enforce") so an existing deployment picks up the new
 * posture without an env change, while still reading tokens for measurement.
 *
 * @return {AppCheckMode} Effective App Check mode.
 */
function resolveAppCheckMode(): AppCheckMode {
  const raw = (process.env.APP_CHECK_MODE ?? "").trim().toLowerCase();
  if (raw === "enforce" || raw === "soft" || raw === "off") {
    return raw;
  }
  return process.env.ENFORCE_APPCHECK === "true" ? "soft" : "off";
}

const APP_CHECK_MODE = resolveAppCheckMode();
const ENFORCE_APP_CHECK = APP_CHECK_MODE === "enforce";
// Read the token whenever App Check is not fully off, so "soft" still
// populates request.app for logging without gating the call.
const READ_APP_CHECK_TOKEN = APP_CHECK_MODE !== "off";

// Deliberately independent of the App Check mode: the upload callables need a
// warm instance because they sit on the critical path of the app's core
// feature, and that has nothing to do with whether attestation is enforced.
// Tying the two together meant relaxing App Check would silently reintroduce
// cold starts, which is exactly what the `unavailable` errors in the
// production client logs looked like.
const UPLOAD_CALLABLE_MIN_INSTANCES = parseNonNegativeIntEnv(
  process.env.UPLOAD_CALLABLE_MIN_INSTANCES,
  1,
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
  consumeAppCheckToken: false,
} satisfies CallableOptions;

const UPLOAD_CALLABLE_OPTIONS = {
  ...LOW_CPU_CALLABLE_OPTIONS,
  enforceAppCheck: ENFORCE_APP_CHECK,
  consumeAppCheckToken: false,
  timeoutSeconds: UPLOAD_CALLABLE_TIMEOUT_SECONDS,
  minInstances: UPLOAD_CALLABLE_MIN_INSTANCES,
} satisfies CallableOptions;

type AppCheckAwareRequest = {
  app?: unknown;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
};

/**
 * Classifies the App Check state of an incoming callable request.
 *
 * "valid" — the platform verified a token and populated request.app.
 * "invalid" — the client sent a token the platform refused (in "soft" mode
 *   the call still runs, but this is the case worth alerting on).
 * "absent" — the client sent no token at all (App Check inactive on device).
 * "disabled" — App Check is off for this deployment.
 *
 * @param {AppCheckAwareRequest} request Callable request candidate.
 * @return {string} One of "valid" | "invalid" | "absent" | "disabled".
 */
function describeAppCheckState(request: AppCheckAwareRequest): string {
  if (!READ_APP_CHECK_TOKEN) {
    return "disabled";
  }
  if (request.app) {
    return "valid";
  }
  const header = request.rawRequest?.headers?.["x-firebase-appcheck"];
  const sent = Array.isArray(header) ?
    header.some((value) => (value ?? "").trim().length > 0) :
    (header ?? "").trim().length > 0;
  return sent ? "invalid" : "absent";
}

/**
 * Logs the App Check state of a callable request without ever throwing.
 *
 * Ongoing telemetry, not a countdown to enforcement. In the chosen "soft"
 * posture these lines are how attestation stays observable: a sudden collapse
 * of "valid" points at a client or Play Integrity regression, and a rise in
 * "invalid" — a token the platform actively refused — is the case worth
 * investigating, since honest devices that simply cannot attest report
 * "absent" instead.
 *
 * @param {string} callableName Name of the callable being served.
 * @param {AppCheckAwareRequest} request Callable request candidate.
 * @param {string} uid Authenticated caller uid.
 * @return {void}
 */
function logAppCheckState(
  callableName: string,
  request: AppCheckAwareRequest,
  uid: string,
): void {
  const state = describeAppCheckState(request);
  if (state === "disabled") {
    return;
  }
  console.log(
    JSON.stringify({
      event: "app_check_state",
      callable: callableName,
      appCheck: state,
      mode: APP_CHECK_MODE,
      uid,
    }),
  );
}

export {
  APP_CHECK_MODE,
  ENFORCE_APP_CHECK,
  LOW_CPU_CALLABLE_OPTIONS,
  MOBILE_CALLABLE_OPTIONS,
  UPLOAD_CALLABLE_OPTIONS,
  REGION,
  LOW_CPU_REGION_OPTIONS,
  describeAppCheckState,
  logAppCheckState,
};
