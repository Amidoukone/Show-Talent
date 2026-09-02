/* eslint-disable linebreak-style */

/**
 * Le vocabulaire du football, côté serveur.
 *
 * Miroir de `lib/models/football_vocabulary.dart`. Les deux listes doivent
 * rester identiques, et un test de garde-fou les compare — un code accepté ici
 * mais inconnu du client produirait un champ que le mobile lit comme nul, donc
 * une fiche qui perd son poste sans que rien ne le signale.
 *
 * Ce fichier existe parce que le SDK Admin **contourne entièrement
 * firestore.rules**. Pour tout ce que le portail d'administration écrit, le
 * callable est la seule validation qui subsiste : sans elle, une faute de
 * frappe côté admin devient une donnée silencieusement perdue.
 */

export const POSITION_CODES = [
  "GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST",
] as const;

export const STRONG_FOOT_CODES = ["left", "right", "both"] as const;

export const CONTRACT_STATUS_CODES = [
  "free", "under_contract", "on_loan", "amateur",
] as const;

export const CLUB_LEVEL_CODES = [
  "pro", "semi_pro", "academy", "amateur",
] as const;

export const AGE_CATEGORY_CODES = [
  "U15", "U17", "U19", "U21", "Senior",
] as const;

/** Au plus trois postes déclarés par un joueur. */
export const MAX_POSITION_CODES = 3;

/** Au plus trois nationalités. */
export const MAX_NATIONALITIES = 3;

/** Au plus dix pays d'intervention pour un agent. */
export const MAX_AGENT_COUNTRIES = 10;

/**
 * Resolves a raw value against a closed list, case-insensitively.
 *
 * @param {Array} codes The accepted codes.
 * @param {unknown} raw The candidate value.
 * @return {string | null} The canonical code, or null when unknown.
 */
export function toCode(
  codes: readonly string[],
  raw: unknown,
): string | null {
  const normalized = String(raw ?? "").trim().toLowerCase();
  if (!normalized) return null;

  for (const code of codes) {
    if (code.toLowerCase() === normalized) return code;
  }
  return null;
}

/**
 * Resolves a list of codes, dropping duplicates and unknowns.
 *
 * Silently dropping an unknown code is the right behaviour here: the caller is
 * an administrator correcting a file, and refusing the whole save because one
 * entry is unreadable would lose the corrections that were valid.
 *
 * @param {Array} codes The accepted codes.
 * @param {unknown} raw The candidate list.
 * @param {number} max Maximum number of entries kept.
 * @return {Array} The canonical codes, in declared order.
 */
export function toCodeList(
  codes: readonly string[],
  raw: unknown,
  max: number,
): string[] {
  if (!Array.isArray(raw)) return [];

  const resolved: string[] = [];
  for (const entry of raw) {
    const code = toCode(codes, entry);
    if (!code || resolved.includes(code)) continue;
    resolved.push(code);
    if (resolved.length === max) break;
  }
  return resolved;
}

/**
 * Resolves ISO 3166-1 alpha-2 country codes.
 *
 * Refuses anything that is not exactly two letters: a country name written out
 * in full is what the typed model replaces, and accepting it here would let
 * free text back in through the one door that skips the security rules.
 *
 * @param {unknown} raw The candidate list.
 * @param {number} max Maximum number of entries kept.
 * @return {Array} Upper-case codes, without duplicates.
 */
export function toCountryCodeList(raw: unknown, max: number): string[] {
  if (!Array.isArray(raw)) return [];

  const resolved: string[] = [];
  for (const entry of raw) {
    const code = String(entry ?? "").trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(code) || resolved.includes(code)) continue;
    resolved.push(code);
    if (resolved.length === max) break;
  }
  return resolved;
}

/**
 * Resolves a single ISO country code.
 *
 * @param {unknown} raw The candidate value.
 * @return {string | null} Upper-case code, or null.
 */
export function toCountryCode(raw: unknown): string | null {
  const code = String(raw ?? "").trim().toUpperCase();
  return /^[A-Z]{2}$/.test(code) ? code : null;
}

/** Au plus dix saisons archivées, comme `PlayerFootballProfile`. */
export const MAX_SEASON_HISTORY = 10;

/** Longueur retenue d'un libellé libre de saison, de compétition ou de club. */
const MAX_SEASON_TEXT = 120;

/**
 * Trims a free-text season field and bounds its length.
 *
 * @param {unknown} raw The candidate value.
 * @return {string | null} The trimmed text, or null when empty or not a string.
 */
function toSeasonText(raw: unknown): string | null {
  if (typeof raw !== "string") return null;

  const trimmed = raw.trim();
  return trimmed ? trimmed.slice(0, MAX_SEASON_TEXT) : null;
}

/**
 * Reads a non-negative count.
 *
 * @param {unknown} raw The candidate value.
 * @return {number | null} The whole count, or null when unusable.
 */
function toSeasonCount(raw: unknown): number | null {
  if (typeof raw !== "number") return null;
  if (!Number.isFinite(raw) || raw < 0) return null;

  return Math.trunc(raw);
}

/**
 * Sanitises one season, field by field, against the closed lists.
 *
 * The Admin SDK bypasses firestore.rules, so this is the only thing standing
 * between the portal and a season that says « Défense » where the mobile app
 * reads a code — which it would render as nothing at all.
 *
 * A season with nothing left in it comes back as null rather than as a shell
 * of null fields, which a profile would read as "filled in, but at zero".
 *
 * @param {unknown} raw The candidate season.
 * @return {Record<string, unknown> | null} The sanitised season, or null.
 */
export function toSeasonRecord(
  raw: unknown,
): Record<string, unknown> | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;

  const map = raw as Record<string, unknown>;
  const record: Record<string, unknown> = {
    season: toSeasonText(map["season"]),
    competition: toSeasonText(map["competition"]),
    ageCategory: toCode(AGE_CATEGORY_CODES, map["ageCategory"]),
    appearances: toSeasonCount(map["appearances"]),
    minutes: toSeasonCount(map["minutes"]),
    goals: toSeasonCount(map["goals"]),
    assists: toSeasonCount(map["assists"]),
    clubName: toSeasonText(map["clubName"]),
    clubLevel: toCode(CLUB_LEVEL_CODES, map["clubLevel"]),
  };

  const isEmpty = Object.values(record).every((value) => value === null);
  return isEmpty ? null : record;
}

/**
 * Sanitises a career, dropping what cannot be read and bounding the length.
 *
 * @param {unknown} raw The candidate list.
 * @return {Array} The sanitised seasons, in the order given.
 */
export function toSeasonHistory(
  raw: unknown,
): Array<Record<string, unknown>> {
  if (!Array.isArray(raw)) return [];

  const seasons: Array<Record<string, unknown>> = [];
  for (const entry of raw) {
    const record = toSeasonRecord(entry);
    if (!record) continue;

    seasons.push(record);
    if (seasons.length === MAX_SEASON_HISTORY) break;
  }
  return seasons;
}
