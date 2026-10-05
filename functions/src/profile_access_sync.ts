/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */

import {isDeepStrictEqual} from "node:util";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";

// List rules cannot look up an unknown document owner. These server-maintained
// fields let queries prove their audience before Firestore reads any results.
export async function readProfileAccess(
  tx: FirebaseFirestore.Transaction,
  uid: string,
) {
  const videos = await tx.get(db.collection("videos").where("uid", "==", uid));
  const conversations = await tx.get(db.collection("conversations")
    .where("utilisateurIds", "array-contains", uid));
  const peerIds = new Set<string>();
  for (const doc of conversations.docs) {
    for (const id of doc.data().utilisateurIds ?? []) {
      if (typeof id === "string" && id !== uid) peerIds.add(id);
    }
  }
  const peers = peerIds.size ? await tx.getAll(
    ...[...peerIds].map((id) => db.collection("users").doc(id)),
  ) : [];
  return {videos, conversations, peers};
}

export function writeProfileAccess(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  profile: FirebaseFirestore.DocumentData,
  related: Awaited<ReturnType<typeof readProfileAccess>>,
) {
  const publicFeedVisible = profile.isMinorProfile === false;
  for (const doc of related.videos.docs) {
    if (doc.data().publicFeedVisible !== publicFeedVisible) {
      tx.update(doc.ref, {publicFeedVisible});
    }
  }
  const adults = new Set(related.peers.filter((peer) =>
    peer.exists && peer.data()?.isMinorProfile === false,
  ).map((peer) => peer.id));
  if (profile.isMinorProfile === false) adults.add(uid);
  for (const doc of related.conversations.docs) {
    const ids = doc.data().utilisateurIds;
    const readableBy = Array.isArray(ids) && ids.length === 2 &&
      ids.every((id) => adults.has(id)) ? ids : [];
    if (!isDeepStrictEqual(doc.data().readableBy, readableBy)) {
      tx.update(doc.ref, {readableBy});
    }
  }
}

export const syncVideoAudience = onDocumentWritten(
  {...LOW_CPU_REGION_OPTIONS, document: "videos/{videoId}"},
  async (event) => {
    if (!event.data?.after.exists) return;
    const ref = db.collection("videos").doc(event.params.videoId);
    await db.runTransaction(async (tx) => {
      const video = await tx.get(ref);
      if (!video.exists) return;
      const uid = video.data()?.uid;
      if (typeof uid !== "string" || !uid) return;
      const owner = await tx.get(db.collection("users").doc(uid));
      const publicFeedVisible = owner.data()?.isMinorProfile === false;
      if (video.data()?.publicFeedVisible !== publicFeedVisible) {
        tx.update(ref, {publicFeedVisible});
      }
    });
  },
);
