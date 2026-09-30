/* eslint-disable linebreak-style */

import {isDeepStrictEqual} from "node:util";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

import {db} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";

const DIRECTORY_FIELDS = [
  "nom",
  "role",
  "photoProfil",
  "profilePublic",
  "allowMessages",
  "profileVerified",
  "profileVerificationStatus",
  "followers",
  "followings",
] as const;

const PUBLIC_PROFILE_FIELDS = [
  "country",
  "city",
  "region",
  "languages",
  "openToOpportunities",
  "bio",
  "position",
  "clubActuel",
  "nombreDeMatchs",
  "buts",
  "assistances",
  "performances",
  "nationalities",
  "positionCodes",
  "strongFoot",
  "heightCm",
  "weightKg",
  "contractStatus",
  "contractEndDate",
  "currentClubName",
  "currentClubLevel",
  "currentSeason",
  "seasonHistory",
  "birthYear",
  "isSearchable",
  "clubLevel",
  "clubAgeCategories",
  "clubFederationId",
  "agentLicenceNumber",
  "agentLicenceCountry",
  "agentCountries",
  "playerProfile",
  "clubProfile",
  "agentProfile",
  "eventOrganizerProfile",
  "nomClub",
  "ligue",
  "entreprise",
  "nombreDeRecrutements",
  "team",
  "cvUrl",
] as const;

const POSITION_SEARCH_LABELS: Record<string, string> = {
  GK: "gardien goalkeeper",
  CB: "defenseur central centre back",
  LB: "lateral gauche left back",
  RB: "lateral droit right back",
  DM: "milieu defensif defensive midfielder",
  CM: "milieu central central midfielder",
  AM: "milieu offensif attacking midfielder",
  LW: "ailier gauche left winger",
  RW: "ailier droit right winger",
  ST: "attaquant striker",
};

/**
 * Normalizes a value for prefix search.
 * @param {unknown} value Raw value.
 * @return {string} Search text.
 */
function normalizeSearchText(value: unknown): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Builds bounded word prefixes.
 * @param {FirebaseFirestore.DocumentData} source User data.
 * @return {string[]} Prefixes.
 */
function buildSearchPrefixes(source: FirebaseFirestore.DocumentData): string[] {
  const searchableValues = [
    source.nom,
    source.role,
    source.position,
    source.team,
    source.clubActuel,
    source.currentClubName,
    source.city,
    source.region,
    source.country,
    source.bio,
    ...(Array.isArray(source.positionCodes) ? source.positionCodes : []),
    ...(Array.isArray(source.positionCodes) ? source.positionCodes
      .map((code: unknown) => POSITION_SEARCH_LABELS[String(code)] ?? "") : []),
    ...(Array.isArray(source.nationalities) ? source.nationalities : []),
  ];
  const tokens = [...new Set(searchableValues.flatMap((value) =>
    normalizeSearchText(value).split(" ").filter(Boolean)))];
  const prefixes = new Set<string>();
  // Keep each complete searchable word first. Previously long names and the
  // first profile fields could consume all 200 slots before a club, locality
  // or football position label got even one entry.
  for (const token of tokens) {
    prefixes.add(token.slice(0, 24));
    if (prefixes.size >= 200) return [...prefixes];
  }
  // Distribute partial prefixes across all fields instead of exhausting the
  // budget one word at a time. Short queries remain useful for later fields.
  for (let length = 1; length <= 24; length++) {
    for (const token of tokens) {
      if (length > token.length) continue;
      prefixes.add(token.slice(0, length));
      if (prefixes.size >= 200) return [...prefixes];
    }
  }
  return [...prefixes];
}

/**
 * Copies an allow-listed field when it exists on the source document.
 * @param {FirebaseFirestore.DocumentData} source Full internal user document.
 * @param {FirebaseFirestore.DocumentData} target Public projection.
 * @param {string} field Field to copy.
 */
function copyField(
  source: FirebaseFirestore.DocumentData,
  target: FirebaseFirestore.DocumentData,
  field: string,
): void {
  if (Object.prototype.hasOwnProperty.call(source, field) &&
      source[field] !== undefined) {
    target[field] = source[field];
  }
}

/**
 * Builds the only user shape mobile clients may read for another account.
 * Private profiles keep a small messaging directory identity; their profile,
 * CV reference, social graph and account administration data are omitted.
 *
 * @param {string} uid User ID.
 * @param {FirebaseFirestore.DocumentData} source Full internal user document.
 * @return {FirebaseFirestore.DocumentData|null} Projection or null if hidden.
 */
export function buildPublicProfileProjection(
  uid: string,
  source: FirebaseFirestore.DocumentData,
): FirebaseFirestore.DocumentData | null {
  if (source.authDisabled === true || source.estActif === false) return null;

  const projection: FirebaseFirestore.DocumentData = {uid};
  for (const field of DIRECTORY_FIELDS) copyField(source, projection, field);

  const isPublic = source.profilePublic !== false;
  projection.profilePublic = isPublic;
  projection.allowMessages = source.allowMessages !== false;
  projection.directoryPrefixes = buildSearchPrefixes({nom: source.nom});
  if (isPublic) {
    for (const field of PUBLIC_PROFILE_FIELDS) {
      copyField(source, projection, field);
    }
    projection.searchPrefixes = buildSearchPrefixes(source);
  } else {
    projection.isSearchable = false;
  }
  return projection;
}

/**
 * Whether a user write changes any value visible in the projection.
 * @param {string} uid User ID.
 * @param {FirebaseFirestore.DocumentData|null} before Previous user data.
 * @param {FirebaseFirestore.DocumentData|null} after Current user data.
 * @return {boolean} Whether the public projection changed.
 */
export function publicProfileChanged(
  uid: string,
  before: FirebaseFirestore.DocumentData | null,
  after: FirebaseFirestore.DocumentData | null,
): boolean {
  const oldProjection = before ?
    buildPublicProfileProjection(uid, before) : null;
  const newProjection = after ? buildPublicProfileProjection(uid, after) : null;
  return !isDeepStrictEqual(oldProjection, newProjection);
}

/**
 * Synchronizes one projection from the internal user document.
 * @param {string} uid User ID.
 */
export async function syncPublicProfile(
  uid: string,
): Promise<void> {
  const userRef = db.collection("users").doc(uid);
  const ref = db.collection("public_profiles").doc(uid);
  await db.runTransaction(async (tx) => {
    // Reading the current user in the same transaction prevents an older
    // trigger or backfill page from restoring stale public data.
    const user = await tx.get(userRef);
    const projection = user.exists ?
      buildPublicProfileProjection(uid, user.data() ?? {}) : null;
    if (projection) tx.set(ref, projection);
    else tx.delete(ref);
  });
}

/** Keeps the public projection synchronized with every internal user write. */
export const syncPublicProfileOnUserWrite = onDocumentWritten(
  {
    ...LOW_CPU_REGION_OPTIONS,
    document: "users/{uid}",
  },
  async (event) => {
    if (!publicProfileChanged(
      event.params.uid,
      event.data?.before.data() ?? null,
      event.data?.after.data() ?? null,
    )) return;
    await syncPublicProfile(event.params.uid);
  },
);
