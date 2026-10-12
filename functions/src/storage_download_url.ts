/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {randomUUID} from "crypto";

import {db, storage} from "./firebase";

type GcsUserMetadata = Record<string, string | undefined>;
type GcsFileMetadata = {metadata?: GcsUserMetadata};

/**
 * Gives an object a Firebase download token, reusing the one it already has.
 *
 * A Firebase Storage download URL is the object path plus a token held in the
 * object's own user metadata. Minting one is idempotent by construction: the
 * token is read back before a new one is written, so calling this twice on the
 * same object yields the same URL and never invalidates a link already handed
 * out.
 *
 * @param {string} bucketName Bucket the object lives in.
 * @param {string} objectPath Full object path inside that bucket.
 * @return {Promise<string>} The object's download token.
 */
export async function ensureDownloadToken(
  bucketName: string,
  objectPath: string,
): Promise<string> {
  const file = storage.bucket(bucketName).file(objectPath);

  const [metaRaw] = await file.getMetadata().catch((): [null] => [null]);
  const meta: GcsFileMetadata | null =
    metaRaw && typeof metaRaw === "object" ?
      (metaRaw as unknown as GcsFileMetadata) :
      null;

  const md: GcsUserMetadata = meta?.metadata ?? {};
  let token =
    typeof md["firebaseStorageDownloadTokens"] === "string" ?
      md["firebaseStorageDownloadTokens"].trim() :
      "";

  if (!token) {
    token = randomUUID();
    await file.setMetadata({
      metadata: {...md, firebaseStorageDownloadTokens: token},
    });
  }

  return token;
}

/**
 * The public download URL for a tokenized object.
 *
 * @param {string} bucketName Bucket the object lives in.
 * @param {string} objectPath Full object path inside that bucket.
 * @param {string} token Download token from {@link ensureDownloadToken}.
 * @return {string} A URL any client can fetch.
 */
export function buildStorageDownloadUrl(
  bucketName: string,
  objectPath: string,
  token: string,
): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${
    encodeURIComponent(objectPath)
  }?alt=media&token=${token}`;
}

/**
 * Locates a video's still, wherever it ended up.
 *
 * The document's own `thumbnailPath` is authoritative when the object is
 * really there; the three conventional names are tried after it, because a
 * legacy upload may predate the field.
 *
 * @param {string} bucketName Bucket to search.
 * @param {string} videoId Video document id, which is also the session id.
 * @param {string | undefined} thumbnailPath Path recorded on the document.
 * @return {Promise<string>} The object path, or `""` when no still exists.
 */
export async function resolveThumbnailObjectPath(
  bucketName: string,
  videoId: string,
  thumbnailPath?: string,
): Promise<string> {
  const bucket = storage.bucket(bucketName);

  if (typeof thumbnailPath === "string" && thumbnailPath.trim()) {
    const recorded = thumbnailPath.trim();
    const [exists] = await bucket.file(recorded).exists();
    if (exists) return recorded;
  }

  for (const candidate of [
    `thumbnails/thumbnail_${videoId}.jpg`,
    `thumbnails/thumbnail_${videoId}.jpeg`,
    `thumbnails/thumbnail_${videoId}.png`,
  ]) {
    const [exists] = await bucket.file(candidate).exists();
    if (exists) return candidate;
  }

  return "";
}

/**
 * The download URL for a video's still, or `""` when there is no still yet.
 *
 * Shared between the two functions that can write it, which is the point.
 *
 * There used to be exactly one moment in a video's life when this could be
 * written: inside `optimizeMp4Video`, after FFmpeg. That function is triggered
 * by the *video* object landing in Storage, and the client uploads the still
 * only afterwards — so the two race. On a weak connection, or a clip light
 * enough to remux in seconds, the optimizer reached the thumbnail lookup
 * before the still existed, wrote nothing, and nothing ever looked again:
 * `onObjectFinalized` never fires for `thumbnails/`, and `finalizeUpload` only
 * recorded the *path*. The video shipped with no still for the rest of its
 * life, and every profile grid showed a placeholder icon instead of a frame.
 *
 * It is the same race the comment on `isFinalizedUploadSession` describes for
 * description and caption. That one was closed from the finalize side; this
 * one was not.
 *
 * Now both writers call this: the optimizer when it finishes, and
 * `finalizeUpload` which by definition runs after the client has uploaded the
 * still. Whichever runs last fills the gap, and the token is idempotent so
 * they cannot disagree.
 *
 * @param {object} params Bucket, video id, and the recorded thumbnail path.
 * @return {Promise<string>} A fetchable URL, or `""`.
 */
export async function resolveThumbnailDownloadUrl(params: {
  bucketName: string;
  videoId: string;
  thumbnailPath?: string;
}): Promise<string> {
  let recorded = params.thumbnailPath;

  if (!recorded) {
    try {
      const snap = await db.collection("videos").doc(params.videoId).get();
      const value = snap.data()?.thumbnailPath;
      if (typeof value === "string") recorded = value;
    } catch {
      // The conventional names below still cover it. A document read that
      // fails here must not cost the video its still.
    }
  }

  const objectPath = await resolveThumbnailObjectPath(
    params.bucketName,
    params.videoId,
    recorded,
  );
  if (!objectPath) return "";

  const token = await ensureDownloadToken(params.bucketName, objectPath);
  return buildStorageDownloadUrl(params.bucketName, objectPath, token);
}
