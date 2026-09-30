/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {createHash, randomBytes} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {auth, db, fieldValue, storage} from "./firebase";
import {resolveCallableAuth} from "./callable_auth";
import {LOW_CPU_REGION_OPTIONS, MOBILE_CALLABLE_OPTIONS} from "./function_runtime";

const CV_TICKET_LIFETIME_MS = 5 * 60_000;
const MAX_CV_BYTES = 5 * 1024 * 1024;
const MAX_TICKETS_PER_MINUTE = 30;
const TICKET_PATH = /^\/cv\/view\/([0-9a-f]{64})\/?$/;
const CV_FILE_NAME = /^cv_[0-9]+\.pdf$/;

function ticketRef(token: string) {
  const digest = createHash("sha256").update(token).digest("hex");
  return db.collection("cv_view_tickets").doc(digest);
}

export function cvObjectPath(raw: unknown, uid: string, bucketName: string): string | null {
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
    const prefix = `cvs/${uid}/`;
    const fileName = path.startsWith(prefix) ? path.slice(prefix.length) : "";
    return CV_FILE_NAME.test(fileName) ? path : null;
  } catch {
    return null;
  }
}

function hasAdminClaim(claims: Record<string, unknown> | null | undefined): boolean {
  return claims?.admin === true ||
    claims?.platformAdmin === true || claims?.superAdmin === true;
}

async function authorizedCvPath(
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
  const mayRead = viewerUid === ownerUid || hasAdminClaim(claims) ||
    (ownerData.profilePublic === true &&
      ownerData.authDisabled !== true && ownerData.estActif !== false);
  if (!mayRead) return null;
  return cvObjectPath(ownerData.cvUrl, ownerUid, storage.bucket().name);
}

function cvBaseUrl(): string {
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

export function parseCvByteRange(
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
  const ref = db.collection("cv_view_limits").doc(uid);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const previous = snapshot.data() ?? {};
    const now = Date.now();
    const windowStart = Number(previous.windowStartMs ?? 0);
    const withinWindow = now - windowStart >= 0 && now - windowStart < 60_000;
    const count = withinWindow ? Number(previous.count ?? 0) : 0;
    if (count >= MAX_TICKETS_PER_MINUTE) {
      throw new HttpsError("resource-exhausted", "Trop de demandes de CV.");
    }
    tx.set(ref, {
      windowStartMs: withinWindow ? windowStart : now,
      count: count + 1,
    });
  });
}

export const createCvViewLink = onCall(
  MOBILE_CALLABLE_OPTIONS,
  async (request) => {
    const caller = await resolveCallableAuth(request);
    const ownerUid = typeof request.data?.ownerUid === "string" ?
      request.data.ownerUid.trim() : "";
    if (!ownerUid || ownerUid.length > 128 || ownerUid.includes("/")) {
      throw new HttpsError("invalid-argument", "Profil invalide.");
    }
    const path = await authorizedCvPath(ownerUid, caller.uid, caller.token);
    if (!path) throw new HttpsError("permission-denied", "CV indisponible.");
    await enforceTicketLimit(caller.uid);

    const file = storage.bucket().file(path);
    try {
      const [metadata] = await file.getMetadata();
      const size = Number(metadata.size);
      if (metadata.contentType !== "application/pdf" ||
          !Number.isFinite(size) || size < 1 || size > MAX_CV_BYTES) {
        throw new Error("invalid CV metadata");
      }
    } catch (error) {
      logger.warn("CV view unavailable", {ownerUid, error});
      throw new HttpsError("not-found", "CV indisponible.");
    }

    const token = randomBytes(32).toString("hex");
    await ticketRef(token).create({
      ownerUid,
      viewerUid: caller.uid,
      path,
      expiresAt: Timestamp.fromMillis(Date.now() + CV_TICKET_LIFETIME_MS),
      createdAt: fieldValue.serverTimestamp(),
    });
    return {url: `${cvBaseUrl()}/cv/view/${token}`};
  },
);

export const cvViewPage = onRequest(
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
      response.status(404).send("CV introuvable.");
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
        response.status(404).send("CV indisponible.");
        return;
      }
      const path = await authorizedCvPath(
        ownerUid, viewerUid, userRecord.customClaims ?? null,
      );
      if (!path || path !== data.path) {
        response.status(404).send("CV indisponible.");
        return;
      }

      const [contents] = await storage.bucket().file(path).download();
      const size = contents.length;
      if (size < 1 || size > MAX_CV_BYTES ||
          contents.subarray(0, 5).toString("ascii") !== "%PDF-") {
        response.status(404).send("CV indisponible.");
        return;
      }
      response.set({
        "Content-Type": "application/pdf",
        "Content-Disposition": "inline; filename=\"cv-adfoot.pdf\"",
        "Accept-Ranges": "bytes",
      });

      const range = request.get("range");
      if (range) {
        const parsed = parseCvByteRange(range, size);
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
        // An unsupported multi-range or malformed Range request can still
        // receive the complete PDF. Safari's preview then remains usable.
      }
      response.set("Content-Length", String(size));
      response.status(200);
      response.end(request.method === "HEAD" ? undefined : contents);
    } catch (error) {
      logger.error("CV view failed", {error});
      if (!response.headersSent) response.status(404).send("CV indisponible.");
    }
  },
);

export const cleanupExpiredCvViewTickets = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 hours",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const expired = await db.collection("cv_view_tickets")
      .where("expiresAt", "<=", Timestamp.now()).limit(500).get();
    if (expired.empty) return;
    const batch = db.batch();
    for (const ticket of expired.docs) batch.delete(ticket.ref);
    await batch.commit();
  },
);
