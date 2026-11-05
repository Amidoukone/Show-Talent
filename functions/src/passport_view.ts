/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

// Mirrors cv_view.ts exactly -- same ticket/view-link shape, same
// authorization logic (owner, admin, or a verified recruiter/club viewing a
// public, non-minor-or-consented profile), same re-check at read time, not
// only at mint time. A passport scan is a government ID, more sensitive than
// a CV, so it gets the identical treatment rather than a shortcut: never a
// tokenized Storage download URL (which bypasses storage.rules for anyone
// who later holds it), always a short-lived, single-purpose, re-authorized
// ticket. Kept in its own file with its own ticket/rate-limit collections
// (passport_view_tickets, passport_view_limits) rather than reusing the CV
// ones, so the two never share a rate budget or an expiry sweep.

import {createHash, randomBytes} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue, storage} from "./firebase";
import {resolveCallableAuth} from "./callable_auth";
import {LOW_CPU_REGION_OPTIONS, MOBILE_CALLABLE_OPTIONS} from "./function_runtime";

const PASSPORT_TICKET_LIFETIME_MS = 5 * 60_000;
const MAX_PASSPORT_BYTES = 8 * 1024 * 1024;
const MAX_TICKETS_PER_MINUTE = 30;
const TICKET_PATH = /^\/passport\/view\/([0-9a-f]{64})\/?$/;
const PASSPORT_FILE_NAME = /^passport_[0-9]+\.(jpg|jpeg|png)$/;

function ticketRef(token: string) {
  const digest = createHash("sha256").update(token).digest("hex");
  return db.collection("passport_view_tickets").doc(digest);
}

export function passportObjectPath(raw: unknown, uid: string, bucketName: string): string | null {
  if (typeof raw !== "string" || !raw.trim()) return null;
  try {
    const url = new URL(raw);
    let path = "";
    if (url.protocol === "gs:" && url.hostname === bucketName) {
      path = decodeURIComponent(url.pathname.replace(/^\//, ""));
    } else if (url.protocol === "https:" &&
        url.hostname === "firebasestorage.googleapis.com") {
      const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(url.pathname);
      if (!match || match[1] !== bucketName) return null;
      path = decodeURIComponent(match[2]);
    } else {
      return null;
    }
    const prefix = `identityDocuments/${uid}/`;
    const fileName = path.startsWith(prefix) ? path.slice(prefix.length) : "";
    return PASSPORT_FILE_NAME.test(fileName) ? path : null;
  } catch {
    return null;
  }
}

function hasAdminClaim(claims: Record<string, unknown> | null | undefined): boolean {
  return claims?.admin === true ||
    claims?.platformAdmin === true || claims?.superAdmin === true;
}

// Deliberately *not* a copy of cv_view.ts's authorizedCvPath, even though
// the product decision was "same audience as the CV". That function only
// requires isVerifiedRecruiter inside the minor branch -- any active
// recruiter, verified or not, can read an *adult* player's CV. A passport is
// a government ID, more sensitive than a CV, and the choice made for it was
// specifically "verified recruiters/clubs", unconditionally -- so that check
// applies to every non-owner, non-admin viewer here, not only to minors. See
// the matching comment on canReadPassportPhoto in storage.rules, which this
// mirrors (the Firestore write path and this callable must agree on who may
// read, or one of them is either too strict or a leak).
async function authorizedPassportPath(
  ownerUid: string,
  viewerUid: string,
  claims: Record<string, unknown> | null | undefined,
): Promise<string | null> {
  const [owner, viewer] = await Promise.all([
    db.collection("users").doc(ownerUid).get(),
    db.collection("users").doc(viewerUid).get(),
  ]);
  const ownerData = owner.data();
  const viewerData = viewer.data();
  if (!ownerData || !viewerData ||
      viewerData.authDisabled === true || viewerData.estActif === false ||
      ownerData.role !== "joueur") return null;
  const isVerifiedRecruiter =
    (viewerData.role === "recruteur" || viewerData.role === "club") &&
    (viewerData.profileVerified === true ||
      viewerData.profileVerificationStatus === "verified");
  const ownerIsMinor = ownerData.isMinorProfile === true;
  const mayReadPublishedProfile = ownerData.profilePublic === true &&
    ownerData.authDisabled !== true && ownerData.estActif !== false &&
    isVerifiedRecruiter &&
    (ownerIsMinor ?
      ownerData.minorProfileApproved === true &&
        ownerData.minorMediaPurgePending !== true &&
        ownerData.minorMediaConsentApproved === true :
      ownerData.isMinorProfile === false);
  const mayRead = viewerUid === ownerUid || hasAdminClaim(claims) ||
    mayReadPublishedProfile;
  if (!mayRead) return null;
  return passportObjectPath(ownerData.passportPhotoUrl, ownerUid, storage.bucket().name);
}

function passportBaseUrl(): string {
  const raw = (process.env.VIDEO_SHARE_BASE_URL ?? "https://adfoot.org").trim();
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || !url.hostname || url.username || url.password) {
      throw new Error("invalid URL");
    }
    return url.origin;
  } catch {
    return "https://adfoot.org";
  }
}

export function parsePassportByteRange(
  raw: string,
  size: number,
): {start: number; end: number} | null {
  const match = /^bytes=(\d*)-(\d*)$/.exec(raw);
  if (!match || (!match[1] && !match[2])) return null;
  let start = match[1] ? Number(match[1]) : NaN;
  let end = match[2] ? Number(match[2]) : size - 1;
  if (!match[1]) {
    const suffixLength = Number(match[2]);
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  }
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
      start < 0 || start >= size || end < start) return null;
  end = Math.min(end, size - 1);
  return {start, end};
}

async function enforceTicketLimit(uid: string): Promise<void> {
  const ref = db.collection("passport_view_limits").doc(uid);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const previous = snapshot.data() ?? {};
    const now = Date.now();
    const windowStart = Number(previous.windowStartMs ?? 0);
    const withinWindow = now - windowStart >= 0 && now - windowStart < 60_000;
    const count = withinWindow ? Number(previous.count ?? 0) : 0;
    if (count >= MAX_TICKETS_PER_MINUTE) {
      throw new HttpsError("resource-exhausted", "Trop de demandes de passeport.");
    }
    tx.set(ref, {
      windowStartMs: withinWindow ? windowStart : now,
      count: count + 1,
    });
  });
}

function contentTypeForFileName(path: string): string {
  return /\.png$/i.test(path) ? "image/png" : "image/jpeg";
}

// JPEG: FF D8 FF. PNG: 89 50 4E 47 0D 0A 1A 0A. Guards against a file whose
// declared Storage content-type lied, or a renamed non-image -- the same
// reasoning cv_view.ts applies to the "%PDF-" magic bytes.
function hasExpectedMagicBytes(contents: Buffer, contentType: string): boolean {
  if (contentType === "image/png") {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    return contents.subarray(0, 8).equals(png);
  }
  return contents[0] === 0xff && contents[1] === 0xd8 && contents[2] === 0xff;
}

export const createPassportViewLink = onCall(
  MOBILE_CALLABLE_OPTIONS,
  async (request) => {
    const caller = await resolveCallableAuth(request);
    const ownerUid = typeof request.data?.ownerUid === "string" ?
      request.data.ownerUid.trim() : "";
    if (!ownerUid || ownerUid.length > 128 || ownerUid.includes("/")) {
      throw new HttpsError("invalid-argument", "Profil invalide.");
    }
    const path = await authorizedPassportPath(ownerUid, caller.uid, caller.token);
    if (!path) throw new HttpsError("permission-denied", "Document indisponible.");
    await enforceTicketLimit(caller.uid);

    const file = storage.bucket().file(path);
    try {
      const [metadata] = await file.getMetadata();
      const size = Number(metadata.size);
      const expectedType = contentTypeForFileName(path);
      if ((metadata.contentType !== expectedType && metadata.contentType !== "image/jpg") ||
          !Number.isFinite(size) || size < 1 || size > MAX_PASSPORT_BYTES) {
        throw new Error("invalid passport metadata");
      }
    } catch (error) {
      logger.warn("Passport view unavailable", {ownerUid, error});
      throw new HttpsError("not-found", "Document indisponible.");
    }

    const token = randomBytes(32).toString("hex");
    await ticketRef(token).create({
      ownerUid,
      viewerUid: caller.uid,
      path,
      expiresAt: Timestamp.fromMillis(Date.now() + PASSPORT_TICKET_LIFETIME_MS),
      createdAt: fieldValue.serverTimestamp(),
    });
    return {url: `${passportBaseUrl()}/passport/view/${token}`};
  },
);

export const passportViewPage = onRequest(
  {
    ...LOW_CPU_REGION_OPTIONS,
    invoker: "public",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request, response) => {
    response.set({
      "Cache-Control": "private, no-store, max-age=0",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Robots-Tag": "noindex, nofollow, noarchive",
    });
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.status(405).send("Méthode non autorisée.");
      return;
    }
    const match = TICKET_PATH.exec(request.path);
    if (!match) {
      response.status(404).send("Document introuvable.");
      return;
    }
    try {
      const ticket = await ticketRef(match[1]).get();
      const data = ticket.data();
      const expiresAt = data?.expiresAt;
      if (!data || !(expiresAt instanceof Timestamp) ||
          expiresAt.toMillis() <= Date.now()) {
        response.status(404).send("Lien expiré.");
        return;
      }
      const ownerUid = String(data.ownerUid ?? "");
      const viewerUid = String(data.viewerUid ?? "");
      const userRecord = await auth.getUser(viewerUid);
      if (userRecord.disabled) {
        response.status(404).send("Document indisponible.");
        return;
      }
      const path = await authorizedPassportPath(
        ownerUid, viewerUid, userRecord.customClaims ?? null,
      );
      if (!path || path !== data.path) {
        response.status(404).send("Document indisponible.");
        return;
      }

      const [contents] = await storage.bucket().file(path).download();
      const size = contents.length;
      const contentType = contentTypeForFileName(path);
      if (size < 1 || size > MAX_PASSPORT_BYTES ||
          !hasExpectedMagicBytes(contents, contentType)) {
        response.status(404).send("Document indisponible.");
        return;
      }
      response.set({
        "Content-Type": contentType,
        "Content-Disposition": "inline; filename=\"passeport-adfoot" +
          (contentType === "image/png" ? ".png" : ".jpg") + "\"",
        "Accept-Ranges": "bytes",
      });

      const range = request.get("range");
      if (range) {
        const parsed = parsePassportByteRange(range, size);
        if (parsed) {
          const {start, end} = parsed;
          response.set({
            "Content-Range": `bytes ${start}-${end}/${size}`,
            "Content-Length": String(end - start + 1),
          });
          response.status(206);
          response.end(request.method === "HEAD" ? undefined :
            contents.subarray(start, end + 1));
          return;
        }
      }
      response.set("Content-Length", String(size));
      response.status(200);
      response.end(request.method === "HEAD" ? undefined : contents);
    } catch (error) {
      logger.error("Passport view failed", {error});
      if (!response.headersSent) response.status(404).send("Document indisponible.");
    }
  },
);

export const cleanupExpiredPassportViewTickets = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const expired = await db.collection("passport_view_tickets")
      .where("expiresAt", "<=", Timestamp.now()).limit(500).get();
    if (expired.empty) return;
    const batch = db.batch();
    for (const ticket of expired.docs) batch.delete(ticket.ref);
    await batch.commit();
  },
);
