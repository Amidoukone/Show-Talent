/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */

import {randomBytes} from "crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
import {resolveCallableAuth} from "./callable_auth";

const REGION = "europe-west1";
const MANAGED_ROLE_LIST = ["club", "recruteur", "agent"] as const;
const MANAGED_ROLES = new Set<string>(MANAGED_ROLE_LIST);

type AdminCallableRequestLike = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
};

function getString(data: unknown, key: string): string {
  if (typeof data !== "object" || data === null) return "";
  const value = (data as Record<string, unknown>)[key];
  return typeof value === "string" ? value.trim() : "";
}

function getOptionalString(data: unknown, key: string): string | null {
  const value = getString(data, key);
  return value || null;
}

function getPlainObject(
  data: unknown,
  key: string,
): Record<string, unknown> | null {
  if (typeof data !== "object" || data === null) return null;
  const value = (data as Record<string, unknown>)[key];
  if (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  ) {
    return {...(value as Record<string, unknown>)};
  }
  return null;
}

function normalizeRole(role: string): string {
  return role.trim().toLowerCase();
}

function isManagedRole(role: string): boolean {
  return MANAGED_ROLES.has(normalizeRole(role));
}

function assertManagedRole(role: string): string {
  const normalized = normalizeRole(role);
  if (!isManagedRole(normalized)) {
    throw new HttpsError(
      "invalid-argument",
      "Le role doit etre club, recruteur ou agent.",
    );
  }
  return normalized;
}

function isPrivilegedClaims(
  token: Record<string, unknown> | null | undefined,
): boolean {
  if (!token) return false;
  return token["admin"] === true ||
    token["platformAdmin"] === true ||
    token["superAdmin"] === true;
}

async function assertAdminCaller(
  request: AdminCallableRequestLike,
): Promise<string> {
  const {uid, token} = await resolveCallableAuth(request);
  if (isPrivilegedClaims(token)) {
    return uid;
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const userData = userSnap.data() ?? {};
  const role = normalizeRole(getString(userData, "role"));
  const hasFirestoreAdminAccess = role === "admin" ||
    userData["admin"] === true ||
    userData["platformAdmin"] === true ||
    userData["superAdmin"] === true;

  if (!hasFirestoreAdminAccess) {
    throw new HttpsError(
      "permission-denied",
      "Action reservee a l administration.",
    );
  }

  return uid;
}

function isUserNotFound(error: unknown): boolean {
  const code =
    typeof error === "object" &&
      error !== null &&
      "code" in error &&
      typeof (error as {code?: unknown}).code === "string" ?
      (error as {code: string}).code :
      "";

  return code === "auth/user-not-found";
}

function buildTemporaryPassword(): string {
  return `${randomBytes(12).toString("base64url")}Aa1!`;
}

function cloneCallableValue(value: unknown): unknown {
  if (value === null) return null;

  switch (typeof value) {
  case "string":
    return value.trim();
  case "number":
  case "boolean":
    return value;
  default:
    break;
  }

  if (Array.isArray(value)) {
    return value
      .map((entry) => cloneCallableValue(entry))
      .filter((entry) => entry !== undefined);
  }

  if (
    typeof value === "object" &&
    value !== null &&
    Object.prototype.toString.call(value) === "[object Object]"
  ) {
    const out: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value)) {
      const cloned = cloneCallableValue(entry);
      if (cloned !== undefined) {
        out[key] = cloned;
      }
    }
    return out;
  }

  return undefined;
}

function cloneCallableRecord(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const cloned = cloneCallableValue(value);
  if (
    typeof cloned === "object" &&
    cloned !== null &&
    !Array.isArray(cloned)
  ) {
    return cloned as Record<string, unknown>;
  }
  return {};
}

export {
  LOW_CPU_REGION_OPTIONS,
  REGION,
  MANAGED_ROLE_LIST,
  MANAGED_ROLES,
  assertAdminCaller,
  assertManagedRole,
  buildTemporaryPassword,
  cloneCallableRecord,
  getOptionalString,
  getPlainObject,
  getString,
  isManagedRole,
  isPrivilegedClaims,
  isUserNotFound,
  normalizeRole,
};
