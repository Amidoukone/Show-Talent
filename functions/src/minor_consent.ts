/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */

import {HttpsError} from "firebase-functions/v2/https";
import {MIN_BIRTH_YEAR} from "./user_search_fields";

export const MINIMUM_PLAYER_AGE = 12;

export function isBelowMinimumPlayerAge(date: Date): boolean {
  const now = new Date();
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  if (
    now.getUTCMonth() < date.getUTCMonth() ||
    (now.getUTCMonth() === date.getUTCMonth() &&
      now.getUTCDate() < date.getUTCDate())
  ) age--;
  return age < MINIMUM_PLAYER_AGE;
}

export type ValidatedGuardianConsent = {
  guardianName: string;
  relationship: "parent" | "legal_guardian";
  method: "oral_confirmation" | "written_confirmation";
  evidenceReference: string;
  jurisdictionCountryCode?: string;
  consentTextVersion?: string;
  consentText?: string;
  mediaAllowed: boolean;
};

export const MINOR_CONSENT_POLICY_VERSION = "minor-profile-consent-v2";
const MINOR_CONSENT_TEXT =
  "Le parent ou tuteur accepte la création d’une fiche football visible aux " +
  "recruteurs vérifiés. Les demandes de contact seront examinées par " +
  "l’administration. Les photos, vidéos et CV ne seront pas publiés sans un " +
  "accord média distinct.";

export function parseManagedBirthDate(value: unknown): Date | null {
  let date: Date | null = null;
  if (value && typeof (value as {toDate?: unknown}).toDate === "function") {
    date = (value as {toDate: () => Date}).toDate();
  } else if (value instanceof Date) {
    date = value;
  } else if (typeof value === "string" && value.trim()) {
    const parsed = new Date(value.trim());
    if (!Number.isNaN(parsed.getTime())) date = parsed;
  } else if (typeof value === "number" && Number.isFinite(value)) {
    date = new Date(value);
  }
  if (!date || Number.isNaN(date.getTime())) return null;
  const now = new Date();
  if (date.getUTCFullYear() < MIN_BIRTH_YEAR || date > now) return null;
  return date;
}

export function isUnderEighteen(date: Date): boolean {
  const now = new Date();
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  if (
    now.getUTCMonth() < date.getUTCMonth() ||
    (now.getUTCMonth() === date.getUTCMonth() &&
      now.getUTCDate() < date.getUTCDate())
  ) age--;
  return age < 18;
}

export function validateGuardianConsent(
  value: unknown,
): ValidatedGuardianConsent {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError(
      "failed-precondition",
      "L’accord parental doit être enregistré avant d’activer la fiche mineur.",
    );
  }
  const consent = value as Record<string, unknown>;
  const guardianName = typeof consent.guardianName === "string" ?
    consent.guardianName.trim() : "";
  const relationship = consent.relationship;
  const method = consent.method;
  const evidenceReference = typeof consent.evidenceReference === "string" ?
    consent.evidenceReference.trim() : "";
  const countryCode = typeof consent.jurisdictionCountryCode === "string" ?
    consent.jurisdictionCountryCode.trim().toUpperCase() : "";
  if (
    guardianName.length < 2 || guardianName.length > 120 ||
    (relationship !== "parent" && relationship !== "legal_guardian") ||
    (method !== "oral_confirmation" && method !== "written_confirmation") ||
    evidenceReference.length > 120 ||
    (countryCode !== "" && !/^[A-Z]{2}$/.test(countryCode)) ||
    typeof consent.mediaAllowed !== "boolean" ||
    consent.confirmed !== true
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Vérifiez le représentant, le mode d’accord et les autorisations.",
    );
  }
  return {
    guardianName,
    relationship,
    method,
    evidenceReference,
    ...(countryCode ? {jurisdictionCountryCode: countryCode} : {}),
    consentTextVersion: MINOR_CONSENT_POLICY_VERSION,
    consentText: MINOR_CONSENT_TEXT,
    mediaAllowed: consent.mediaAllowed,
  };
}
