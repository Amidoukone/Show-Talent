/* eslint-disable linebreak-style */

import {isDeepStrictEqual} from "node:util";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

import {db} from "./firebase";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
import {deriveBirthYearAndMinorStatus} from "./user_search_fields";
import {readProfileAccess, writeProfileAccess} from "./profile_access_sync";

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
 * Reads the stored birth date without exposing it. A malformed supplied date
 * is treated conservatively as a protected profile as well.
 * @param {unknown} value Private birth date.
 * @return {boolean} Whether the profile must be withheld as a minor/unknown.
 */
export function requiresMinorProtection(value: unknown): boolean {
  let date: Date | null = null;
  if (value && typeof (value as {toDate?: unknown}).toDate === "function") {
    date = (value as {toDate: () => Date}).toDate();
  } else if (value instanceof Date) {
    date = value;
  } else if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) date = parsed;
  }
  if (!date || Number.isNaN(date.getTime())) return value != null;

  const now = new Date();
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  const beforeBirthday = now.getUTCMonth() < date.getUTCMonth() ||
    (now.getUTCMonth() === date.getUTCMonth() &&
      now.getUTCDate() < date.getUTCDate());
  if (beforeBirthday) age--;
  return age < 18;
}

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
 * @param {boolean} isMinor Whether the private birth date requires protection.
 * @return {FirebaseFirestore.DocumentData|null} Projection or null if hidden.
 */
export function buildPublicProfileProjection(
  uid: string,
  source: FirebaseFirestore.DocumentData,
  isMinor = false,
): FirebaseFirestore.DocumentData | null {
  if (source.authDisabled === true || source.estActif === false) return null;
  if (isMinor) {
    if (
      source.minorProfileApproved !== true || source.profilePublic === false
    ) {
      return null;
    }
    const minorProjection: FirebaseFirestore.DocumentData = {
      uid,
      nom: source.nom,
      role: "joueur",
      profilePublic: true,
      isMinorProfile: true,
      allowMessages: false,
      profileVerified: false,
      profileVerificationStatus: "unverified",
      isSearchable: source.isSearchable === true,
      openToOpportunities: source.openToOpportunities === true,
      directoryPrefixes: [],
    };
    for (const field of [
      "positionCodes",
      "nationalities",
      "birthYear",
      "clubLevel",
    ]) copyField(source, minorProjection, field);
    if (
      source.minorMediaConsentApproved === true &&
      source.minorMediaPurgePending !== true
    ) {
      copyField(source, minorProjection, "photoProfil");
      copyField(source, minorProjection, "cvUrl");
    }
    minorProjection.searchPrefixes = buildSearchPrefixes({
      positionCodes: source.positionCodes,
      nationalities: source.nationalities,
    });
    return minorProjection;
  }

  const projection: FirebaseFirestore.DocumentData = {uid};
  for (const field of DIRECTORY_FIELDS) copyField(source, projection, field);
  projection.isMinorProfile = false;

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
  const newProjection = after ?
    buildPublicProfileProjection(uid, after) : null;
  const oldProtectionState = before ? [
    before.minorProfileApproved === true,
    before.isMinorProfile === true,
    before.minorProtectionRequired === true,
    before.minorMediaConsentApproved === true,
    before.minorMediaPurgePending === true,
  ] : null;
  const newProtectionState = after ? [
    after.minorProfileApproved === true,
    after.isMinorProfile === true,
    after.minorProtectionRequired === true,
    after.minorMediaConsentApproved === true,
    after.minorMediaPurgePending === true,
  ] : null;
  return !isDeepStrictEqual(oldProjection, newProjection) ||
    !isDeepStrictEqual(oldProtectionState, newProtectionState);
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
    const contact = await tx.get(userRef.collection("private").doc("contact"));
    const userData = user.data() ?? {};
    const related = await readProfileAccess(tx, uid);
    const birthDate = contact.data()?.birthDate;
    const age = deriveBirthYearAndMinorStatus(birthDate);
    const isMinor = age?.isMinor === true ||
      (age == null && (birthDate != null ||
        userData.isMinorProfile === true ||
        userData.minorProtectionRequired === true));
    const projection = user.exists ?
      buildPublicProfileProjection(
        uid,
        userData,
        isMinor,
      ) : null;
    if (user.exists && userData.isMinorProfile !== isMinor) {
      // The scheduled v5 backfill also materializes this marker on legacy
      // user documents. Storage and CV access fail closed until it is set.
      tx.set(userRef, {isMinorProfile: isMinor}, {merge: true});
    }
    if (projection) tx.set(ref, projection);
    else tx.delete(ref);
    writeProfileAccess(tx, uid, {
      ...userData, isMinorProfile: user.exists ? isMinor : true,
    }, related);
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

/** Re-evaluates visibility whenever the private birth date changes. */
export const syncPublicProfileOnContactWrite = onDocumentWritten(
  {
    ...LOW_CPU_REGION_OPTIONS,
    document: "users/{uid}/private/contact",
  },
  async (event) => {
    if (!event.data?.after?.exists && !event.data?.before?.exists) return;
    const beforeBirthDate = event.data?.before?.get("birthDate");
    const wasBirthDateRecorded = beforeBirthDate != null;
    const userRef = db.collection("users").doc(event.params.uid);
    await db.runTransaction(async (tx) => {
      const user = await tx.get(userRef);
      const contact = await tx.get(
        userRef.collection("private").doc("contact"),
      );
      const birthDate = contact.data()?.birthDate;
      const protectionRequired = requiresMinorProtection(birthDate) ||
      (birthDate == null && (wasBirthDateRecorded ||
        user.data()?.minorProtectionRequired === true));
      if (
        user.exists &&
      user.data()?.minorProtectionRequired !== protectionRequired
      ) {
        tx.update(userRef, {minorProtectionRequired: protectionRequired});
      }
    });
    await syncPublicProfile(event.params.uid);
  },
);
