/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */
/* eslint-disable max-len */

import type {Request, Response} from "express";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {db} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";

const DEFAULT_SHARE_BASE_URL = "https://adfoot.org";
const DEFAULT_ANDROID_PACKAGE_NAME = "org.adfoot.app";
const DEFAULT_ANDROID_DOWNLOAD_PATH = "/download/android/";
const VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{6,80}$/;

type VideoShareViewModel = {
  id: string;
  canonicalUrl: string;
  title: string;
  description: string;
  caption: string;
  videoUrl: string;
  /** Playable URLs, lightest first. Empty when nothing is playable. */
  playbackUrls: string[];
  thumbnailUrl: string;
  authorName: string;
  authorRole: string;
  androidIntentUrl: string;
  androidDownloadUrl: string;
};

function getString(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  return typeof value === "string" ? value.trim() : "";
}

function getFirstString(data: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = getString(data, key);
    if (value) return value;
  }
  return "";
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ?
    value as Record<string, unknown> :
    null;
}

function isHttpUrl(value: string): boolean {
  return value.startsWith("https://") || value.startsWith("http://");
}

function firstSourceUrl(rawSources: unknown): string {
  if (!Array.isArray(rawSources)) return "";
  for (const source of rawSources) {
    const sourceRecord = asRecord(source);
    if (!sourceRecord) continue;
    const url = getFirstString(sourceRecord, ["url", "videoUrl"]);
    if (isHttpUrl(url)) return url;
  }
  return "";
}

function resolveVideoUrl(data: Record<string, unknown>): string {
  const direct = getString(data, "videoUrl");
  if (isHttpUrl(direct)) return direct;

  const playback = asRecord(data["playback"]);
  if (playback) {
    const fallback = asRecord(playback["fallback"]);
    const fallbackUrl = fallback ?
      getFirstString(fallback, ["url", "videoUrl"]) :
      "";
    if (isHttpUrl(fallbackUrl)) return fallbackUrl;

    const sourceAsset = asRecord(playback["sourceAsset"]);
    const sourceAssetUrl = sourceAsset ?
      getFirstString(sourceAsset, ["url", "videoUrl"]) :
      "";
    if (isHttpUrl(sourceAssetUrl)) return sourceAssetUrl;

    const playbackSourceUrl = firstSourceUrl(playback["sources"]);
    if (playbackSourceUrl) return playbackSourceUrl;
  }

  return firstSourceUrl(data["sources"]);
}

/**
 * Every playable source, lightest first.
 *
 * The page used to hand the browser one URL, and always the full-quality
 * master: a 1080p at 5-10 Mb/s, offered to whoever opened a shared link,
 * typically a recruiter on mobile data. The app has arbitrated quality since
 * the companion renditions shipped; this page never did, which made it the one
 * surface of the product that ignored the viewer's connection.
 *
 * Ordering by height ascending and emitting them all as `<source>` lets the
 * browser take the first it can play — the 480p when one exists — while
 * leaving the master reachable. `og:video` deliberately keeps pointing at the
 * master (see renderVideoPage): social previews want the best asset, and they
 * do not stream it to a phone.
 *
 * @param {Record<string, unknown>} data Video document.
 * @return {string[]} Distinct playable URLs, lightest first.
 */
function resolvePlaybackUrls(data: Record<string, unknown>): string[] {
  const playback = asRecord(data["playback"]);
  const rawSources = playback ? playback["sources"] : data["sources"];
  if (!Array.isArray(rawSources)) return [];

  const scored: {url: string; height: number}[] = [];
  for (const source of rawSources) {
    const record = asRecord(source);
    if (!record) continue;
    const url = getFirstString(record, ["url", "videoUrl"]);
    if (!isHttpUrl(url)) continue;

    const rawHeight = record["height"];
    // No height means no way to rank it: send it to the back rather than
    // letting an unlabelled source outrank a known-light one.
    const height = typeof rawHeight === "number" && Number.isFinite(rawHeight) ?
      rawHeight :
      Number.MAX_SAFE_INTEGER;
    scored.push({url, height});
  }

  scored.sort((left, right) => left.height - right.height);

  const seen = new Set<string>();
  const ordered: string[] = [];
  for (const entry of scored) {
    if (seen.has(entry.url)) continue;
    seen.add(entry.url);
    ordered.push(entry.url);
  }
  return ordered;
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function truncate(value: string, maxLength: number): string {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trim()}...`;
}

function extractVideoId(path: string): string | null {
  const cleanPath = path.split("?")[0] || "";
  const segments = cleanPath.split("/").filter(Boolean);
  if (segments.length < 2 || segments[0] !== "v") return null;

  const videoId = decodeURIComponent(segments[1]).trim();
  return VIDEO_ID_PATTERN.test(videoId) ? videoId : null;
}

function normalizedBaseUrl(
  raw: string | undefined,
  fallback = DEFAULT_SHARE_BASE_URL
): string {
  const value = (raw || "").trim();
  if (!value) return fallback;

  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || !url.hostname) {
      return fallback;
    }
    url.pathname = url.pathname.replace(/\/+$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/+$/, "");
  } catch (_) {
    return fallback;
  }
}

function resolveRequestPath(request: Request): string {
  return request.path || request.originalUrl || request.url || "/";
}

function resolveRequestBaseUrl(request: Request): string {
  const configuredBaseUrl = process.env.VIDEO_SHARE_BASE_URL;
  if (configuredBaseUrl && configuredBaseUrl.trim()) {
    return normalizedBaseUrl(configuredBaseUrl);
  }

  const forwardedHost = request.get("x-forwarded-host") || request.get("host");
  const host = (forwardedHost || "").split(",")[0].trim();
  if (!host) return DEFAULT_SHARE_BASE_URL;

  return normalizedBaseUrl(`https://${host}`);
}

function resolveCanonicalUrl(request: Request, videoId: string): string {
  const baseUrl = resolveRequestBaseUrl(request);
  return `${baseUrl}/v/${encodeURIComponent(videoId)}`;
}

function resolveAndroidPackageName(): string {
  const configured = (process.env.ANDROID_PACKAGE_NAME || "").trim();
  return configured || DEFAULT_ANDROID_PACKAGE_NAME;
}

function resolveAndroidDownloadUrl(request: Request): string {
  const configured = (process.env.ANDROID_APP_DOWNLOAD_URL || "").trim();
  const baseUrl = resolveRequestBaseUrl(request);

  if (configured.startsWith("https://")) {
    return configured;
  }

  const path = configured.startsWith("/") ?
    configured :
    DEFAULT_ANDROID_DOWNLOAD_PATH;
  return new URL(path, `${baseUrl}/`).toString();
}

function buildAndroidIntentUrl(
  canonicalUrl: string,
  fallbackUrl: string
): string {
  const target = new URL(canonicalUrl);
  const packageName = resolveAndroidPackageName();
  const pathAndQuery = `${target.pathname}${target.search}`;
  return `intent://${target.host}${pathAndQuery}#Intent;scheme=https;package=${packageName};S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`;
}

async function resolveAuthor(uid: string): Promise<{name: string; role: string}> {
  if (!uid) return {name: "", role: ""};

  try {
    const snap = await db.collection("users").doc(uid).get();
    const data = snap.data() as Record<string, unknown> | undefined;
    if (!data) return {name: "", role: ""};

    return {
      name: getFirstString(data, ["displayName", "nom", "nomClub"]),
      role: getString(data, "role"),
    };
  } catch (error) {
    logger.warn("video share author lookup failed", {uid, error});
    return {name: "", role: ""};
  }
}

async function buildViewModel(
  videoId: string,
  canonicalUrl: string,
  androidDownloadUrl: string
): Promise<VideoShareViewModel | null> {
  const snap = await db.collection("videos").doc(videoId).get();
  const data = snap.data() as Record<string, unknown> | undefined;
  if (!snap.exists || !data || getString(data, "status") !== "ready") {
    return null;
  }

  const videoUrl = resolveVideoUrl(data);
  const playbackUrls = resolvePlaybackUrls(data);
  const caption = getFirstString(
    data,
    ["caption", "captionText", "legend", "legende"]
  );
  const description = getFirstString(data, ["description", "songName", "title"]);
  const thumbnailUrl = getFirstString(data, ["thumbnail", "thumbnailUrl"]);
  const uid = getString(data, "uid");
  const author = await resolveAuthor(uid);
  const primaryText = caption || description;
  const title = primaryText ?
    `${truncate(primaryText, 72)} | Adfoot` :
    author.name ?
      `Vidéo de ${author.name} sur Adfoot` :
      "Vidéo Adfoot";
  const shareDescription = primaryText ?
    truncate(primaryText, 155) :
    "Regarde cette vidéo de talent football sur Adfoot.";

  return {
    id: videoId,
    canonicalUrl,
    title,
    description: shareDescription,
    caption: primaryText,
    videoUrl: isHttpUrl(videoUrl) ? videoUrl : "",
    // The master stays in the list as the last resort, for a document whose
    // `sources` array is missing or unusable but whose `videoUrl` is fine.
    playbackUrls: playbackUrls.length ?
      playbackUrls :
      isHttpUrl(videoUrl) ? [videoUrl] : [],
    thumbnailUrl: isHttpUrl(thumbnailUrl) ? thumbnailUrl : "",
    authorName: author.name,
    authorRole: author.role,
    androidIntentUrl: buildAndroidIntentUrl(canonicalUrl, androidDownloadUrl),
    androidDownloadUrl,
  };
}

function renderNotFoundPage(): string {
  const title = "Vidéo introuvable | Adfoot";
  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <meta name="robots" content="noindex">
  <style>${baseStyles()}</style>
</head>
<body>
  <main class="page page--center">
    <section class="empty">
      <p class="eyebrow">Adfoot</p>
      <h1>Vidéo indisponible</h1>
      <p>Cette vidéo n’est plus disponible ou n’est pas encore prête.</p>
      <a class="button" href="/">Aller sur Adfoot</a>
    </section>
  </main>
</body>
</html>`;
}

function renderVideoPage(view: VideoShareViewModel): string {
  const title = htmlEscape(view.title);
  const description = htmlEscape(view.description);
  const canonicalUrl = htmlEscape(view.canonicalUrl);
  const thumbnailMeta = view.thumbnailUrl ?
    `<meta property="og:image" content="${htmlEscape(view.thumbnailUrl)}">
  <meta name="twitter:image" content="${htmlEscape(view.thumbnailUrl)}">` :
    "";
  const videoMeta = view.videoUrl ?
    `<meta property="og:video" content="${htmlEscape(view.videoUrl)}">
  <meta property="og:video:type" content="video/mp4">` :
    "";
  const posterAttr = view.thumbnailUrl ?
    ` poster="${htmlEscape(view.thumbnailUrl)}"` :
    "";
  // Lightest source first: the browser picks the first it can play, so a
  // video with a 480p companion streams that instead of the 1080p master.
  const sourceMarkup = view.playbackUrls
    .map(
      (url) => `<source src="${htmlEscape(url)}" type="video/mp4">`,
    )
    .join("");
  const videoMarkup = view.playbackUrls.length ?
    `<video class="player" controls playsinline preload="metadata"${posterAttr}>${sourceMarkup}</video>` :
    "<div class=\"player player--empty\">Lecture indisponible</div>";
  const author = view.authorName ? htmlEscape(view.authorName) : "Adfoot";
  const role = view.authorRole ? htmlEscape(view.authorRole) : "Talent";
  const caption = view.caption ?
    htmlEscape(view.caption) :
    "Regarde cette vidéo sur Adfoot.";
  const androidIntentUrl = htmlEscape(view.androidIntentUrl);
  const androidDownloadUrl = htmlEscape(view.androidDownloadUrl);

  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <meta name="description" content="${description}">
  <link rel="canonical" href="${canonicalUrl}">
  <!--
    Shareable, not indexable.

    This page carries a named young player, their role and their video, and it
    is reachable without signing in. That is what makes a shared link work, and
    it is exactly what must not end up in a search index: a minor's footage
    sitting in Google results, permanently, is not something a federation, an
    agent or a parent will accept from a platform that means to be the
    professional route into the game.

    "noindex" keeps the link fully functional — anyone the player sends it to
    can open it, and og:* below still renders a rich preview in a chat app,
    because social crawlers read the meta tags rather than the index.
    "noarchive" stops cached copies outliving a deletion.
  -->
  <meta name="robots" content="noindex, noarchive">
  <meta property="og:type" content="video.other">
  <meta property="og:site_name" content="Adfoot">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:url" content="${canonicalUrl}">
  ${thumbnailMeta}
  ${videoMeta}
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${description}">
  <meta name="theme-color" content="#2ED573">
  <link rel="icon" href="/favicon.ico">
  <style>${baseStyles()}</style>
</head>
<body>
  <main class="page">
    <section class="watch">
      <div class="media">
        ${videoMarkup}
      </div>
      <aside class="details">
        <p class="eyebrow">Adfoot</p>
        <h1>Vidéo de talent</h1>
        <p class="caption">${caption}</p>
        <div class="author">
          <span>${author}</span>
          <small>${role}</small>
        </div>
        <div class="actions">
          <a class="button" href="${androidIntentUrl}">Ouvrir dans l'application</a>
          <a class="button button--secondary" href="${androidDownloadUrl}">Télécharger l’application</a>
        </div>
        <p class="hint">Si Adfoot est installée sur ce téléphone, la vidéo s’ouvre directement dans l’application.</p>
      </aside>
    </section>
  </main>
</body>
</html>`;
}

function baseStyles(): string {
  return `
    :root { color-scheme: dark; --brand: #2ed573; --bg: #0e1114; --panel: #171d22; --text: #f4f7f5; --muted: #aab4b0; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); }
    .page { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
    .page--center { text-align: center; }
    .watch { width: min(1120px, 100%); display: grid; grid-template-columns: minmax(280px, 420px) minmax(280px, 1fr); gap: 28px; align-items: center; }
    .media { aspect-ratio: 9 / 16; max-height: min(82vh, 760px); background: #050607; border-radius: 8px; overflow: hidden; box-shadow: 0 20px 70px rgba(0,0,0,.45); }
    .player { display: block; width: 100%; height: 100%; object-fit: contain; background: #050607; }
    .player--empty { display: grid; place-items: center; color: var(--muted); }
    .details, .empty { max-width: 560px; }
    .eyebrow { margin: 0 0 12px; color: var(--brand); font-weight: 800; letter-spacing: .08em; text-transform: uppercase; font-size: 12px; }
    h1 { margin: 0 0 16px; font-size: clamp(32px, 6vw, 64px); line-height: .95; letter-spacing: 0; }
    .caption, .empty p { margin: 0 0 22px; color: var(--muted); font-size: clamp(16px, 2vw, 20px); line-height: 1.5; }
    .author { display: flex; flex-direction: column; gap: 3px; margin-bottom: 28px; color: var(--text); font-weight: 800; }
    .author small { color: var(--muted); font-weight: 700; text-transform: capitalize; }
    .actions { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin-bottom: 14px; }
    .button { display: inline-flex; align-items: center; justify-content: center; min-height: 48px; padding: 0 22px; border-radius: 8px; background: var(--brand); color: #061009; font-weight: 900; text-decoration: none; }
    .button--secondary { background: transparent; color: var(--text); border: 1px solid rgba(244,247,245,.28); }
    .hint { margin: 0; color: var(--muted); font-size: 14px; line-height: 1.45; }
    @media (max-width: 760px) { .page { padding: 0; place-items: stretch; } .watch { min-height: 100vh; grid-template-columns: 1fr; gap: 0; } .media { width: 100%; max-height: 68vh; border-radius: 0; box-shadow: none; } .details { padding: 22px; } h1 { font-size: 34px; } }
  `;
}

function sendHtml(
  response: Response,
  statusCode: number,
  html: string,
  cacheControl: string,
  headOnly: boolean
): void {
  response.status(statusCode).set({
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": cacheControl,
    "X-Content-Type-Options": "nosniff",
    // Belt and braces alongside the <meta name="robots"> in the page head: a
    // crawler that never parses the body — or fetches with HEAD, which sends
    // no body at all — still sees the directive.
    "X-Robots-Tag": "noindex, noarchive",
  });

  if (headOnly) {
    response.end();
    return;
  }

  response.send(html);
}

export const videoSharePage = onRequest(
  {
    ...LOW_CPU_REGION_OPTIONS,
    invoker: "public",
    ingressSettings: "ALLOW_ALL",
  },
  async (request, response): Promise<void> => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.status(405).set("Allow", "GET, HEAD").send("Method not allowed");
      return;
    }

    const videoId = extractVideoId(resolveRequestPath(request));
    if (!videoId) {
      sendHtml(
        response,
        404,
        renderNotFoundPage(),
        "public, max-age=60",
        request.method === "HEAD"
      );
      return;
    }

    try {
      const view = await buildViewModel(
        videoId,
        resolveCanonicalUrl(request, videoId),
        resolveAndroidDownloadUrl(request)
      );
      if (!view) {
        sendHtml(
          response,
          404,
          renderNotFoundPage(),
          "public, max-age=60",
          request.method === "HEAD"
        );
        return;
      }

      sendHtml(
        response,
        200,
        renderVideoPage(view),
        "public, max-age=60, s-maxage=300",
        request.method === "HEAD"
      );
    } catch (error) {
      logger.error("video share page failed", {videoId, error});
      sendHtml(
        response,
        500,
        renderNotFoundPage(),
        "no-store",
        request.method === "HEAD"
      );
    }
  }
);
