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
