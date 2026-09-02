/* eslint-disable linebreak-style */

import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {LOW_CPU_REGION_OPTIONS} from "./function_runtime";
import {db} from "./firebase";
import {MAX_POSITION_CODES, POSITION_CODES} from "./football_vocabulary";

/**
 * Derives the two search fields no client is allowed to write.
 *
 * `birthYear` and `isSearchable` are absent from the `canUpdateOwnProfile`
 * whitelist in firestore.rules on purpose, and this is what fills them.
 *
 * `birthYear` because the full date of birth lives in
 * `users/{uid}/private/contact` and must stay there: a recruiter filters an
 * age bracket, which the year alone answers, and exposing a complete date of
 * birth on a public document is a different decision that nobody made.
 *
 * `isSearchable` because a file does not get to decide on its own that it
 * deserves to be shown to a recruiter.
 */

/**
 * True when the document carries at least one usable position code.
 *
 * @param {unknown} value Raw `positionCodes` field.
 * @return {boolean} Whether a known code is present.
 */
function hasPositionCode(value: unknown): boolean {
  if (!Array.isArray(value)) return false;
  return value
    .slice(0, MAX_POSITION_CODES)
    .some((entry) =>
      (POSITION_CODES as readonly string[])
        .includes(String(entry ?? "").trim().toUpperCase()));
}

/**
 * True when the document carries at least one ISO country code.
 *
 * @param {unknown} value Raw `nationalities` field.
 * @return {boolean} Whether a two-letter code is present.
 */
function hasNationality(value: unknown): boolean {
  if (!Array.isArray(value)) return false;
  return value.some((entry) =>
    /^[A-Za-z]{2}$/.test(String(entry ?? "").trim()));
}

/**
 * Oldest year of birth this project treats as describing a living player.
 *
 * Exported so the message the administration portal shows cannot state a bound
 * different from the one actually applied -- a number written twice is a
 * number that will eventually disagree with itself.
 */
export const MIN_BIRTH_YEAR = 1930;

/**
 * Converts a stored birth date to its year.
 *
 * Tolerant on purpose: the field has been written as a Firestore Timestamp
 * and as an ISO string over the life of this project, and a profile must not
 * lose its year because of which one it happens to hold.
 *
 * Exported because it is also the judge of what the administration portal may
 * write into `birthDate` (`admin_account_actions.ts`). One function decides
 * both questions on purpose: a date the callable accepted but this one refused
 * would derive no year, and the profile would sit in no recruiter search at
 * all -- invisible, with nothing anywhere saying why.
 *
 * @param {unknown} value Raw `birthDate` field from the private document.
 * @return {number | null} Four-digit year, or null when unreadable.
 */
export function toBirthYear(value: unknown): number | null {
  let date: Date | null = null;

  if (value && typeof (value as {toDate?: unknown}).toDate === "function") {
    date = (value as {toDate: () => Date}).toDate();
  } else if (value instanceof Date) {
    date = value;
  } else if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) date = parsed;
  }

  if (!date) return null;

  const year = date.getUTCFullYear();
  // Une annee hors de ces bornes ne decrit aucun joueur vivant : mieux vaut
  // aucune valeur qu'une valeur qui fausserait un filtre par tranche d'age.
  if (year < MIN_BIRTH_YEAR || year > new Date().getUTCFullYear()) return null;
  return year;
}

/**
 * Whether this file carries what a recruiter filters on.
 *
 * **Deliberately narrower than the client's `hasScoutReadyProfile`.** That one
 * also demands a piece of evidence — a published video or a CV — and answers
 * "may this file be advertised as Élite". This one answers "can this file be
 * found by a filtered search", which is a different question with a different
 * cost: checking for a published video means a second query on every write to
 * every user document, and a result that lacks a CV is still useful to a
 * recruiter, whereas one that lacks a position cannot be filtered at all.
 *
 * The two must not be merged. If they ever have to agree, it is this one that
 * moves — the client's judgement is what a player is told about their own
 * file, and it must stay explainable to them.
 *
 * @param {FirebaseFirestore.DocumentData} data The public user document.
 * @param {number | null} birthYear The derived year of birth.
 * @return {boolean} Whether the file belongs in recruiter search results.
 */
function computeIsSearchable(
  data: FirebaseFirestore.DocumentData,
  birthYear: number | null,
): boolean {
  const role = String(data.role ?? "").trim().toLowerCase();
  if (role !== "joueur") return false;

  // Un compte desactive ou suspendu ne doit pas remonter : il ne peut pas
  // repondre.
  if (data.estActif === false) return false;
  if (data.authDisabled === true) return false;

  // Un profil prive a explicitement demande a ne pas etre vu.
  if (data.profilePublic === false) return false;

  if (birthYear === null) return false;
  if (!hasPositionCode(data.positionCodes)) return false;
  if (!hasNationality(data.nationalities)) return false;

  return true;
}

/**
 * Recomputes the derived fields for one account and writes them if changed.
 *
 * The equality check is not an optimisation, it is what stops the recursion:
 * this function writes to the very document whose writes trigger it, so it
 * must become a no-op on its own output after exactly one pass.
 *
 * @param {string} uid The account to refresh.
 * @return {Promise<void>} Resolves once the document is up to date.
 */
export async function refreshUserSearchFields(uid: string): Promise<void> {
  const userRef = db.collection("users").doc(uid);

  const [userSnapshot, contactSnapshot] = await Promise.all([
    userRef.get(),
    userRef.collection("private").doc("contact").get(),
  ]);

  if (!userSnapshot.exists) return;

  const data = userSnapshot.data() ?? {};
  const birthYear = toBirthYear(contactSnapshot.data()?.birthDate);
  const isSearchable = computeIsSearchable(data, birthYear);

  const currentBirthYear =
    typeof data.birthYear === "number" ? data.birthYear : null;
  const currentIsSearchable = data.isSearchable === true;

  if (currentBirthYear === birthYear && currentIsSearchable === isSearchable) {
    return;
  }

  await userRef.update({birthYear, isSearchable});
}

/**
 * Refreshes the derived fields when the public document changes.
 */
export const deriveUserSearchFields = onDocumentWritten(
  {
    ...LOW_CPU_REGION_OPTIONS,
    document: "users/{uid}",
  },
  async (event) => {
    // Une suppression n'a rien a deriver, et refreshUserSearchFields
    // sortirait de toute facon sur `!exists` : autant epargner deux lectures.
    if (!event.data?.after?.exists) return;

    await refreshUserSearchFields(event.params.uid);
  },
);

/**
 * Refreshes them when the private contact document changes.
 *
 * Without this one `birthYear` would go stale the moment a player edits their
 * date of birth: that write lands on `users/{uid}/private/contact`, a
 * different path, and never fires the trigger above. The profile editor writes
 * both documents in the same batch, so in practice both fire — but a birth
 * date changed on its own, from the admin portal or a script, would leave the
 * public year behind for ever.
 */
export const deriveUserSearchFieldsFromContact = onDocumentWritten(
  {
    ...LOW_CPU_REGION_OPTIONS,
    document: "users/{uid}/private/contact",
  },
  async (event) => {
    await refreshUserSearchFields(event.params.uid);
  },
);
