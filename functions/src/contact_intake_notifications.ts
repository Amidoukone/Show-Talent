/* eslint-disable linebreak-style */

import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import {EMAIL_SECRETS, sendOperationsEmail} from "./email_delivery";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";

/**
 * Human labels for the reasons the mobile app offers.
 *
 * Falls back to the raw value rather than dropping it: an unknown reason is
 * still information, and a notice that silently omits why someone got in touch
 * is worse than one carrying a slug.
 */
const CONTACT_REASON_LABELS: Record<string, string> = {
  opportunity: "Opportunité",
  follow_up: "Suivi du joueur",
  information: "Demande d’information",
  trial: "Essai / détection",
  representation: "Représentation",
};

/**
 * Reads a string field, trimmed, or an empty string.
 *
 * @param {Record<string, unknown> | undefined} source Source map.
 * @param {string} key Field name.
 * @return {string} The trimmed value, or "".
 */
function readString(
  source: Record<string, unknown> | undefined,
  key: string,
): string {
  const value = source?.[key];
  return typeof value === "string" ? value.trim() : "";
}

/**
 * The display name recorded in a party snapshot.
 *
 * Only the name and the role are read. The snapshots also carry an `email`,
 * and it is deliberately left out: this notice leaves the platform over SMTP,
 * and an operator needs to know *that* someone asked and *who* to open in the
 * portal, never a copy of their contact details in an inbox.
 *
 * @param {unknown} snapshot Party snapshot from the intake document.
 * @param {string} fallbackUid Uid to show when no name was recorded.
 * @return {string} A label safe to put in an e-mail.
 */
function describeParty(snapshot: unknown, fallbackUid: string): string {
  if (!snapshot || typeof snapshot !== "object") {
    return fallbackUid || "inconnu";
  }

  const source = snapshot as Record<string, unknown>;
  const name =
    readString(source, "displayName") || readString(source, "nom");
  const role = readString(source, "role");

  if (!name) return fallbackUid || "inconnu";
  return role ? `${name} (${role})` : name;
}

/**
 * Escapes text for inclusion in the HTML part.
 *
 * @param {string} value Raw text.
 * @return {string} Escaped text.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Tells the platform team that somebody asked to be put in touch.
 *
 * Nothing watched `contact_intakes` before this. A recruiter, a club or an
 * agent could file a request and the only way anyone learned of it was by
 * opening the admin portal and looking. adfoot-production held three requests,
 * all still `status: "new"`, the oldest from 2026-06-02 — eighty-eight days
 * with no reply. That is the exact promise of the product ("tout le monde
 * passe par nous") failing quietly, and it costs one trigger to close.
 *
 * Deliberately e-mail and not a push: the recipient is the operations team,
 * which reads a mailbox, not a phone with the mobile app installed. And
 * deliberately best-effort — a relay outage must never fail the write that
 * already recorded the request. The Firestore document remains the source of
 * truth; this only shortens the time before a human sees it.
 */
export const notifyContactIntakeCreated = onDocumentCreated(
  {
    ...LOW_CPU_REGION_OPTIONS,
    document: "contact_intakes/{intakeId}",
    secrets: EMAIL_SECRETS,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data() ?? {};
    const intakeId = event.params.intakeId;

    const requester = describeParty(
      data.requesterSnapshot,
      readString(data, "requesterUid"),
    );
    const target = describeParty(
      data.targetSnapshot,
      readString(data, "targetUid"),
    );

    const rawReason = readString(data, "contactReason");
    const reason =
      CONTACT_REASON_LABELS[rawReason] || rawReason || "non précisé";
    const context = readString(data, "contextTitle");
    const message = readString(data, "introMessage").slice(0, 800);

    const lines = [
      "Une nouvelle demande de mise en relation vient d’arriver sur Adfoot.",
      "",
      `Demandeur : ${requester}`,
      `Joueur ciblé : ${target}`,
      `Motif : ${reason}`,
      ...(context ? [`Contexte : ${context}`] : []),
      "",
      ...(message ? ["Message :", message, ""] : []),
      `Référence : ${intakeId}`,
      "",
      "Ouvrez le portail d’administration pour y répondre.",
    ];

    const cell = "padding:2px 12px 2px 0";
    const muted = "font-size:13px;color:#555";
    const row = (label: string, value: string): string =>
      "<tr><td style=\"" + cell + "\"><strong>" + label +
      "</strong></td><td>" + escapeHtml(value) + "</td></tr>";

    const html = [
      "<div style=\"font-family:Arial,Helvetica,sans-serif;font-size:15px;" +
        "line-height:1.5;color:#1b1b1b\">",
      "<p>Une nouvelle demande de mise en relation vient d’arriver sur " +
        "Adfoot.</p>",
      "<table style=\"border-collapse:collapse;font-size:15px\">",
      row("Demandeur", requester),
      row("Joueur ciblé", target),
      row("Motif", reason),
      ...(context ? [row("Contexte", context)] : []),
      "</table>",
      ...(message ?
        [
          "<p style=\"margin-top:16px;padding:12px;background:#f4f5f6;" +
            "border-radius:6px\">" + escapeHtml(message) + "</p>",
        ] :
        []),
      "<p style=\"" + muted + "\">Référence : " +
        escapeHtml(intakeId) + "</p>",
      "<p style=\"" + muted + "\">Ouvrez le portail " +
        "d’administration pour y répondre.</p>",
      "</div>",
    ].join("");

    try {
      const outcome = await sendOperationsEmail({
        subject: `Adfoot — nouvelle demande de contact (${reason})`,
        text: lines.join("\n"),
        html,
        event: "contact_intake_notification",
      });

      if (!outcome.sent) {
        logger.warn(
          JSON.stringify({
            event: "contact_intake_notification_not_delivered",
            reason: outcome.reason ?? "unknown",
            intakeId,
          }),
        );
      }
    } catch (error) {
      // Belt and braces: sendOperationsEmail already swallows its failures,
      // so reaching here means something unforeseen. It still must not turn a
      // recorded request into a failed trigger with retries.
      logger.error("contact intake notification failed", {
        event: "contact_intake_notification_error",
        message: error instanceof Error ? error.message : String(error),
        intakeId,
      });
    }
  },
);
