/* eslint-disable linebreak-style */

import {HttpsError} from "firebase-functions/v2/https";

import {auth} from "./firebase";

type CallableRequestLike = {
  auth?: {uid?: string; token?: Record<string, unknown> | null} | null;
  rawRequest?: {
    headers?: Record<string, string | string[] | undefined>;
  } | null;
};

type ResolvedCallableAuth = {
  uid: string;
  token: Record<string, unknown> | null;
};

/**
 * Reads the raw Authorization header from a callable request.
 * @param {CallableRequestLike} request Callable request candidate.
 * @return {string} Raw Authorization header value.
 */
function readAuthorizationHeader(
  request: CallableRequestLike,
): string {
  const rawHeader = request.rawRequest?.headers?.authorization;
  if (typeof rawHeader === "string") {
    return rawHeader.trim();
  }
  if (Array.isArray(rawHeader) && rawHeader.length > 0) {
    return rawHeader[0]?.trim() ?? "";
  }
  return "";
}

/**
 * Extracts the bearer token value from an Authorization header.
 * @param {string} headerValue Raw Authorization header value.
 * @return {string} Bearer token when present, otherwise an empty string.
 */
function extractBearerToken(headerValue: string): string {
  const match = /^Bearer\s+(.+)$/i.exec(headerValue);
  return match?.[1]?.trim() ?? "";
}

/**
 * Resolves the caller auth payload, with a fallback to raw bearer verification.
 * @param {CallableRequestLike} request Callable request candidate.
 * @return {Promise<ResolvedCallableAuth>} Normalized callable auth payload.
 */
async function resolveCallableAuth(
  request: CallableRequestLike,
): Promise<ResolvedCallableAuth> {
  const authUid = request.auth?.uid;
  if (authUid) {
    return {
      uid: authUid,
      token: request.auth?.token ?? null,
    };
  }

  const bearerToken = extractBearerToken(readAuthorizationHeader(request));
  if (!bearerToken) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }

  try {
    const decoded = await auth.verifyIdToken(bearerToken, true);
    return {
      uid: decoded.uid,
      token: decoded as unknown as Record<string, unknown>,
    };
  } catch (_) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
}

export {resolveCallableAuth};
