/* eslint-disable linebreak-style */
/* eslint-disable require-jsdoc */

const NOTIFICATION_TEXT_REPLACEMENTS: ReadonlyArray<
  readonly [string, string]
> = [
  ["\u00c3\u00a9", "e"],
  ["\u00c3\u00a8", "e"],
  ["\u00c3\u00aa", "e"],
  ["\u00c3\u00ab", "e"],
  ["\u00c3\u00a0", "a"],
  ["\u00c3 ", "a"],
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
  ["\u2018", "'"],
  ["\u201c", "\""],
  ["\u201d", "\""],
  ["\u2013", "-"],
  ["\u2014", "-"],
  ["\u2026", "..."],
  ["\u0153", "oe"],
  ["\u0152", "OE"],
  ["\u00e6", "ae"],
  ["\u00c6", "AE"],
  ["\u00c2", ""],
  ["\ufffd", ""],
];

export function normalizeNotificationText(
  value: string,
  maxLength: number,
): string {
  let text = value;
  for (const [needle, replacement] of NOTIFICATION_TEXT_REPLACEMENTS) {
    text = text.split(needle).join(replacement);
  }

  return text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\x20-\x7E]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}
