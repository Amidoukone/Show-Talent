/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */

const NOTIFICATION_TEXT_REPLACEMENTS: ReadonlyArray<
  readonly [string, string]
> = [
  ["\u00c3\u00a9", "e"],
  ["\u00c3\u00a8", "e"],
  ["\u00c3\u00aa", "e"],
  ["\u00c3\u00ab", "e"],
  ["\u00c3\u0020", "a"],
  ["\u00c3\u00a2", "a"],
  ["\u00c3\u00a4", "a"],
  ["\u00c3\u00b4", "o"],
  ["\u00c3\u00b6", "o"],
  ["\u00c3\u00b9", "u"],
  ["\u00c3\u00bb", "u"],
  ["\u00c3\u00bc", "u"],
  ["\u00c3\u00a7", "c"],
  ["\u00c3\u2021", "C"],
  ["\u00c3\u2030", "E"],
  ["\u00c3\u20ac", "A"],
  ["\u00e2\u20ac\u2122", "'"],
  ["\u00e2\u20ac\u02dc", "'"],
  ["\u00e2\u20ac\u0153", "\""],
  ["\u00e2\u20ac\u009d", "\""],
  ["\u00e2\u20ac\u201c", "-"],
  ["\u00e2\u20ac\u201d", "-"],
  ["\u00e2\u20ac\u00a6", "..."],
  ["\u2019", "'"],
  ["‘", "'"],
  ["“", "\""],
  ["”", "\""],
  ["–", "-"],
  ["—", "-"],
  ["…", "..."],
  ["œ", "oe"],
  ["Œ", "OE"],
  ["æ", "ae"],
  ["Æ", "AE"],
  ["Â", ""],
  ["\ufffd", ""],
];

// Built from numeric code points, never written as escape literals in a
// regex, so this file can never itself contain a raw control byte.
function charRange(
  startCodePoint: number,
  endCodePointInclusive: number,
): string {
  let chars = "";
  for (let code = startCodePoint; code <= endCodePointInclusive; code++) {
    chars += String.fromCharCode(code);
  }
  return chars;
}

// Invisible/control characters only -- NUL..BS, SO..US, the C1 range, the
// zero-width spacing marks, and the bidi-override/isolate characters
// sometimes used to spoof notification text. Deliberately excludes codes
// 9-13 (TAB, LF, VT, FF, CR): those are left for the whitespace collapse
// below, which turns a run of them into a single space instead of deleting
// them outright -- two lines of a description must not end up glued into
// one word.
const INVISIBLE_CHARACTERS = new RegExp(
  "[" +
    charRange(0x00, 0x08) +
    charRange(0x0e, 0x1f) +
    charRange(0x7f, 0x9f) +
    charRange(0x200b, 0x200f) +
    charRange(0x202a, 0x202e) +
    charRange(0x2066, 0x2069) +
    "]",
  "g",
);

export function normalizeNotificationText(
  value: string,
  maxLength: number,
): string {
  let text = value;
  for (const [needle, replacement] of NOTIFICATION_TEXT_REPLACEMENTS) {
    text = text.split(needle).join(replacement);
  }

  return text
    .replace(INVISIBLE_CHARACTERS, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}
