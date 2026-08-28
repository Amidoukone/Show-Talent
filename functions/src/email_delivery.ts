/* eslint-disable linebreak-style */

import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import nodemailer from "nodemailer";
import type {Transporter} from "nodemailer";

/**
 * Outbound e-mail for the one thing Firebase Auth will never send by itself.
 *
 * There is no self-signup on this platform: every account is created by an
 * admin through the web portal, which calls `provisionManagedAccount`. That
 * callable already mints a password-setup link — and then handed it back to
 * the admin to copy out of a dialog and paste into their own mail client. An
 * account whose invitation was never pasted anywhere is an account nobody can
 * sign in to, and nothing in the system says so.
 *
 * Password *reset* is deliberately not routed through here. Firebase Auth
 * composes and sends that message itself; pointing the project's SMTP
 * settings at the same Brevo relay fixes its deliverability without a single
 * line of code and without a mobile release. See
 * AUTH_EMAIL_DELIVERABILITY_RUNBOOK.md.
 *
 * Two rules govern everything below, because this runs inside the callable
 * that provisions an account:
 *
 * 1. **It never throws.** A refused SMTP login must not roll back an account
 *    that was already created in Auth and Firestore, and must not surface to
 *    the admin as a failed provisioning. Every path returns a result; the
 *    callable keeps returning `passwordSetupLink` either way, so an admin can
 *    always fall back to what they do today.
 * 2. **It is bounded.** SMTP hangs are common on a misconfigured relay, and
 *    an unbounded connect would hold the callable open until the platform
 *    timeout — the admin would watch "Créer le compte" spin for a minute and
 *    retry, creating a second invitation for the same person.
 */

/**
 * The Brevo SMTP key, held in Secret Manager rather than in the function's
 * environment: unlike every other value in `.env.production`, this one is a
 * credential that can send mail as `adfoot.org`, and env vars are readable by
 * anyone who can describe the function.
 *
 * Callables that send mail must list this in their `secrets` option, or the
 * value is simply absent at runtime and delivery is skipped.
 */
const BREVO_SMTP_KEY = defineSecret("BREVO_SMTP_KEY");

/**
 * Bind this into a callable's options to give it access to the SMTP key.
 *
 * This was conditional on `SMTP_USER`, on the assumption that the CLI loads
 * `.env.<project>` before it discovers function definitions. Production
 * disproved it twice. The deploy log for adfoot-production reads
 * `Loaded environment variables from .env, .env.production` *after*
 * `Loading and analyzing source code`, and the discovery pass that evaluates
 * this line runs without `SMTP_USER` in its environment — so the array was
 * empty, the secret was never bound, and every invitation reported
 * `{"event":"account_invite_email_skipped","reason":"not_configured"}` next
 * to a runtime warning saying the secret was not in the dependency array.
 * Nothing about that was visible at deploy time: it deployed cleanly and
 * sent nothing.
 *
 * So the binding is unconditional, and the switch stays where it can be read
 * reliably — at runtime, in `resolveSmtpSettings`, which still returns null
 * on a blank `SMTP_USER` and still degrades to "the portal shows the link".
 *
 * The cost is real and worth stating: a secret listed here must exist in
 * **every** project this codebase is deployed to, or that deploy is rejected
 * outright. `BREVO_SMTP_KEY` therefore has to exist in staging too — any
 * value will do, since a blank `SMTP_USER` there means it is never read.
 */
const EMAIL_SECRETS = [BREVO_SMTP_KEY];

const DEFAULT_SMTP_HOST = "smtp-relay.brevo.com";
const DEFAULT_SMTP_PORT = 587;
const DEFAULT_FROM_NAME = "Adfoot";

// Ten seconds each. The callable's own budget is what is being protected:
// provisioning has already committed to Auth and Firestore by the time we get
// here, so the worst acceptable outcome is a fast, logged "not sent".
const SMTP_CONNECTION_TIMEOUT_MS = 10_000;
const SMTP_GREETING_TIMEOUT_MS = 10_000;
const SMTP_SOCKET_TIMEOUT_MS = 20_000;

type EmailDeliveryOutcome = {
  /** Whether the relay accepted the message. */
  sent: boolean;
  /**
   * Why it was not sent, when it was not. Stable, coarse tokens meant for
   * logs and for the admin portal — never a raw SMTP error, which can carry
   * the credential in some relay implementations.
   */
  reason?: "not_configured" | "invalid_recipient" | "send_failed";
};

type SmtpSettings = {
  host: string;
  port: number;
  user: string;
  pass: string;
  fromAddress: string;
  fromName: string;
  replyTo: string | null;
};

/**
 * Reads an environment value, treating blank as absent.
 *
 * @param {string} name Environment variable name.
 * @return {string} Trimmed value, or an empty string.
 */
function readEnv(name: string): string {
  return (process.env[name] ?? "").trim();
}

/**
 * Resolves the SMTP settings, or null when delivery is not configured.
 *
 * Absent configuration is the expected state until Brevo is set up, and it is
 * not an error: the portal keeps showing the link and the admin keeps sending
 * it by hand, exactly as before. That is what makes turning this on — and
 * turning it back off — a zero-risk operation.
 *
 * @return {SmtpSettings | null} Settings when complete, otherwise null.
 */
function resolveSmtpSettings(): SmtpSettings | null {
  // `.value()` throws if the secret was never bound to this function. Treat
  // that exactly like an unset credential rather than letting it escape into
  // a callable that has already created an account.
  let pass = "";
  try {
    pass = (BREVO_SMTP_KEY.value() ?? "").trim();
  } catch (_) {
    pass = "";
  }

  const user = readEnv("SMTP_USER");
  const fromAddress = readEnv("MAIL_FROM_ADDRESS");

  if (!user || !pass || !fromAddress) {
    return null;
  }

  const rawPort = Number(readEnv("SMTP_PORT"));
  const port = Number.isFinite(rawPort) && rawPort > 0 ?
    Math.round(rawPort) :
    DEFAULT_SMTP_PORT;

  return {
    host: readEnv("SMTP_HOST") || DEFAULT_SMTP_HOST,
    port,
    user,
    pass,
    fromAddress,
    fromName: readEnv("MAIL_FROM_NAME") || DEFAULT_FROM_NAME,
    replyTo: readEnv("MAIL_REPLY_TO") || null,
  };
}

let cachedTransporter: Transporter | null = null;
let cachedTransporterKey = "";

/**
 * Builds — and reuses across invocations — the SMTP transport.
 *
 * Cached per instance because a warm Cloud Run instance handles many
 * provisions, and each fresh transport is a fresh TLS handshake with the
 * relay. Keyed on the settings so a credential rotation between deploys
 * cannot be served from a stale connection pool.
 *
 * @param {SmtpSettings} settings Resolved SMTP settings.
 * @return {Transporter} A transport bound to those settings.
 */
function getTransporter(settings: SmtpSettings): Transporter {
  const key = [
    settings.host,
    settings.port,
    settings.user,
    settings.pass,
  ].join("|");

  if (cachedTransporter && cachedTransporterKey === key) {
    return cachedTransporter;
  }

  cachedTransporter = nodemailer.createTransport({
    host: settings.host,
    port: settings.port,
    // Port 587 is the STARTTLS submission port: the session opens in clear
    // and is upgraded. `secure: true` would attempt implicit TLS and hang.
    // Port 465 is the implicit-TLS port, so honour that if it is configured.
    secure: settings.port === 465,
    requireTLS: settings.port !== 465,
    auth: {
      user: settings.user,
      pass: settings.pass,
    },
    connectionTimeout: SMTP_CONNECTION_TIMEOUT_MS,
    greetingTimeout: SMTP_GREETING_TIMEOUT_MS,
    socketTimeout: SMTP_SOCKET_TIMEOUT_MS,
  });
  cachedTransporterKey = key;

  return cachedTransporter;
}

/**
 * Whether outbound e-mail is configured for this deployment.
 *
 * @return {boolean} True when a message would actually be attempted.
 */
function isEmailDeliveryConfigured(): boolean {
  return resolveSmtpSettings() !== null;
}

/**
 * Basic recipient sanity, so a malformed address is reported rather than
 * spent as a relay error.
 *
 * @param {string} email Candidate address.
 * @return {boolean} True when the address is plausibly deliverable.
 */
function isPlausibleEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
}

/**
 * Escapes text for inclusion in the HTML part.
 *
 * The display name comes from the admin portal's form, so it is operator
 * input reaching an HTML document.
 *
 * @param {string} value Raw text.
 * @return {string} HTML-safe text.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

type InviteEmailInput = {
  to: string;
  displayName: string;
  passwordSetupLink: string;
  /** True when this is a re-send rather than a first invitation. */
  resend?: boolean;
};

/**
 * The invitation body, in both parts.
 *
 * Deliberately one message with one action. The callable also mints an
 * e-mail-verification link, and it is not in here: completing a password
 * reset proves control of the mailbox, so Firebase marks the address verified
 * on its own. A second link would give the recipient two things to choose
 * between, and two links plus a mixed message is also what spam filters score
 * hardest.
 *
 * Plain text is not a courtesy: a message with an HTML part and no text part
 * is a well-known spam signal, and this one has to land in an inbox.
 *
 * @param {InviteEmailInput} input Recipient and link.
 * @return {{subject: string, text: string, html: string}} Message parts.
 */
function buildInviteEmail(
  input: InviteEmailInput,
): {subject: string; text: string; html: string} {
  const name = input.displayName.trim();
  const greeting = name ? `Bonjour ${name},` : "Bonjour,";
  const subject = input.resend ?
    "Votre accès Adfoot — nouveau lien" :
    "Votre compte Adfoot est prêt";

  const intro = input.resend ?
    "Voici un nouveau lien pour définir le mot de passe de votre compte " +
      "Adfoot." :
    "Un compte Adfoot vient d’être créé pour vous. Il ne reste qu’à " +
      "définir votre mot de passe.";

  const text = [
    greeting,
    "",
    intro,
    "",
    input.passwordSetupLink,
    "",
    "Ce lien est valable une heure. Passé ce délai, utilisez « Mot de " +
      "passe oublié ? » sur l’écran de connexion de l’application pour en " +
      "recevoir un nouveau.",
    "",
    "Si vous n’attendiez pas ce message, ignorez-le : aucun accès n’est " +
      "ouvert tant que le mot de passe n’a pas été défini.",
    "",
    "L’équipe Adfoot",
  ].join("\n");

  const html = [
    "<div style=\"font-family:Arial,Helvetica,sans-serif;font-size:15px;" +
      "line-height:1.5;color:#1b1b1b\">",
    `<p>${escapeHtml(greeting)}</p>`,
    `<p>${escapeHtml(intro)}</p>`,
    "<p style=\"margin:24px 0\">" +
      `<a href="${escapeHtml(input.passwordSetupLink)}" ` +
      "style=\"background:#e2001a;color:#ffffff;text-decoration:none;" +
      "padding:12px 20px;border-radius:6px;display:inline-block;" +
      "font-weight:bold\">Définir mon mot de passe</a>" +
      "</p>",
    "<p style=\"font-size:13px;color:#555\">Si le bouton ne fonctionne " +
      "pas, copiez cette adresse dans votre navigateur :<br>" +
      "<span style=\"word-break:break-all\">" +
      `${escapeHtml(input.passwordSetupLink)}</span></p>`,
    "<p style=\"font-size:13px;color:#555\">Ce lien est valable une heure. " +
      "Passé ce délai, utilisez « Mot de passe oublié ? » sur l’écran de " +
      "connexion de l’application pour en recevoir un nouveau.</p>",
    "<p style=\"font-size:13px;color:#555\">Si vous n’attendiez pas ce " +
      "message, ignorez-le : aucun accès n’est ouvert tant que le mot de " +
      "passe n’a pas été défini.</p>",
    "<p>L’équipe Adfoot</p>",
    "</div>",
  ].join("");

  return {subject, text, html};
}

/**
 * Sends the account invitation, and reports what happened without throwing.
 *
 * @param {InviteEmailInput} input Recipient, display name and setup link.
 * @return {Promise<EmailDeliveryOutcome>} Delivery outcome.
 */
async function sendAccountInviteEmail(
  input: InviteEmailInput,
): Promise<EmailDeliveryOutcome> {
  const to = input.to.trim().toLowerCase();

  if (!to || !isPlausibleEmail(to) || !input.passwordSetupLink.trim()) {
    logger.warn("account invite not sent: invalid recipient or link");
    return {sent: false, reason: "invalid_recipient"};
  }

  const settings = resolveSmtpSettings();
  if (!settings) {
    // Info, not warn: this is the configured-off state, and it is the state
    // the project ships in until Brevo is live. See the runbook.
    logger.info(
      JSON.stringify({
        event: "account_invite_email_skipped",
        reason: "not_configured",
      }),
    );
    return {sent: false, reason: "not_configured"};
  }

  const {subject, text, html} = buildInviteEmail({...input, to});

  try {
    await getTransporter(settings).sendMail({
      from: {name: settings.fromName, address: settings.fromAddress},
      to,
      subject,
      text,
      html,
      ...(settings.replyTo ? {replyTo: settings.replyTo} : {}),
    });

    logger.info(
      JSON.stringify({
        event: "account_invite_email_sent",
        resend: input.resend === true,
      }),
    );
    return {sent: true};
  } catch (error) {
    // The address is not logged: these lines are readable by anyone with
    // Logs Viewer, and an invitation log would otherwise become a list of
    // every member's e-mail. The Firestore write already records who was
    // invited, gated by rules.
    logger.error("account invite e-mail failed", {
      event: "account_invite_email_failed",
      message: error instanceof Error ? error.message : String(error),
    });

    // A transport that failed may be holding a poisoned connection pool —
    // a rotated key, a relay that closed the socket. Drop it so the next
    // provision starts a clean session rather than repeating the failure.
    cachedTransporter = null;
    cachedTransporterKey = "";

    return {sent: false, reason: "send_failed"};
  }
}

export {
  EMAIL_SECRETS,
  buildInviteEmail,
  isEmailDeliveryConfigured,
  sendAccountInviteEmail,
};
export type {EmailDeliveryOutcome};
