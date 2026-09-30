/* eslint-disable linebreak-style */
/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

import {FieldPath, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {db, fieldValue, messaging} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
import {normalizeNotificationText} from "./notification_text";
import {isUnregisteredTokenError, pruneUnregisteredToken, pushTokenRef} from "./push_delivery";

type CampaignParams = {
  senderUid: string;
  title: string;
  body: string;
  contextType: "offre" | "event";
  contextData: string;
};

export async function enqueueFanoutCampaign(params: CampaignParams): Promise<void> {
  const campaignId = `${params.contextType}_${params.contextData}`;
  const ref = db.collection("push_campaigns").doc(campaignId);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    transaction.create(ref, {
      ...params,
      title: normalizeNotificationText(params.title, 120),
      body: normalizeNotificationText(params.body, 300),
      status: "queued",
      targeted: 0,
      sent: 0,
      failed: 0,
      createdAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    });
  });
}

async function claimCampaign(ref: FirebaseFirestore.DocumentReference): Promise<boolean> {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    if (!data || data.status === "completed") return false;
    const leaseUntil = data.leaseUntil instanceof Timestamp ?
      data.leaseUntil.toMillis() : 0;
    if (data.status === "processing" && leaseUntil > Date.now()) return false;
    transaction.update(ref, {
      status: "processing",
      leaseUntil: Timestamp.fromMillis(Date.now() + 5 * 60_000),
      updatedAt: fieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function processCampaign(ref: FirebaseFirestore.DocumentReference): Promise<void> {
  if (!await claimCampaign(ref)) return;
  try {
    const snapshot = await ref.get();
    const data = snapshot.data() ?? {};
    let playersQuery: FirebaseFirestore.Query = db.collection("public_profiles")
      .where("isSearchable", "==", true)
      .orderBy(FieldPath.documentId())
      .limit(400);
    if (typeof data.cursor === "string" && data.cursor) {
      playersQuery = playersQuery.startAfter(data.cursor);
    }
    const players = await playersQuery.get();
    const eligible = players.docs.filter((player) => player.id !== data.senderUid);
    const tokenSnapshots = eligible.length > 0 ? await db.getAll(
      ...eligible.map((player) => pushTokenRef(player.id)),
    ) : [];
    const targets = eligible.map((player, index) => ({
      uid: player.id,
      token: String(tokenSnapshots[index]?.data()?.token ?? "").trim(),
    })).filter((target) => target.token);

    let sent = 0;
    let failed = 0;
    if (targets.length > 0) {
      const response = await messaging.sendEachForMulticast({
        tokens: targets.map((target) => target.token),
        notification: {title: String(data.title ?? ""), body: String(data.body ?? "")},
        data: {
          type: String(data.contextType ?? ""),
          id: String(data.contextData ?? ""),
          senderId: String(data.senderUid ?? ""),
        },
        android: {priority: "high", notification: {channelId: "high_importance_channel", sound: "default"}},
        apns: {payload: {aps: {sound: "default"}}},
      });
      sent = response.successCount;
      failed = response.failureCount;
      await Promise.all(response.responses.map(async (result, index) => {
        if (result.success || !isUnregisteredTokenError(result.error)) return;
        const target = targets[index];
        if (target) {
          await pruneUnregisteredToken({
            uid: target.uid,
            token: target.token,
            reason: `fanout_${String(data.contextType ?? "unknown")}`,
          });
        }
      }));
    }

    const completed = players.size < 400;
    await ref.update({
      status: completed ? "completed" : "queued",
      cursor: players.empty ? data.cursor ?? null : players.docs[players.docs.length - 1].id,
      targeted: fieldValue.increment(targets.length),
      sent: fieldValue.increment(sent),
      failed: fieldValue.increment(failed),
      leaseUntil: fieldValue.delete(),
      updatedAt: fieldValue.serverTimestamp(),
      ...(completed ? {completedAt: fieldValue.serverTimestamp()} : {}),
    });
  } catch (error) {
    logger.error("push campaign page failed", {campaignId: ref.id, error});
    await ref.set({
      status: "queued",
      retryCount: fieldValue.increment(1),
      leaseUntil: fieldValue.delete(),
      lastErrorAt: fieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

export const drainPushCampaigns = onSchedule(
  {
    ...LOW_CPU_REGION_OPTIONS,
    schedule: "every 1 minutes",
    timeZone: "UTC",
    memory: "256MiB",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const [queued, processing] = await Promise.all([
      db.collection("push_campaigns").where("status", "==", "queued").limit(5).get(),
      db.collection("push_campaigns").where("status", "==", "processing").limit(5).get(),
    ]);
    const unique = new Map([...queued.docs, ...processing.docs].map((doc) => [doc.id, doc]));
    for (const campaign of unique.values()) await processCampaign(campaign.ref);
  },
);
