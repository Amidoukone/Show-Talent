import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {normalizeNotificationText} = require('../../functions/lib/notification_text.js');

test('accented French text survives untouched', () => {
  assert.equal(
    normalizeNotificationText('Une nouvelle offre a été publiée à Abidjan', 300),
    'Une nouvelle offre a été publiée à Abidjan',
  );
  assert.equal(normalizeNotificationText('Évènement à Yopougon : café offert', 300), 'Évènement à Yopougon : café offert');
});

test('double-encoded mojibake is cleaned up to plain ASCII', () => {
  // The literal bytes a UTF-8 "été publiée" turns into when misread as
  // Latin-1 and re-encoded -- the historical bug this table exists for.
  const mojibake = 'Ã©tÃ© publiÃ©e';
  assert.equal(normalizeNotificationText(mojibake, 300), 'ete publiee');
});

test('zero-width and bidi-override characters are stripped, not just collapsed', () => {
  const zeroWidthSpace = String.fromCharCode(0x200b);
  const bidiOverride = String.fromCharCode(0x202e);
  const text = `Offre${zeroWidthSpace}normale${bidiOverride}`;
  assert.equal(normalizeNotificationText(text, 300), 'Offrenormale');
});

test('control bytes are stripped while real whitespace is only collapsed', () => {
  const nul = String.fromCharCode(0x00);
  const verticalTab = String.fromCharCode(0x0b);
  const text = `Ligne 1${nul}\nLigne 2${verticalTab}\tfin`;
  assert.equal(normalizeNotificationText(text, 300), 'Ligne 1 Ligne 2 fin');
});

test('multi-line descriptions keep a separating space, never glued words', () => {
  assert.equal(
    normalizeNotificationText('Premier paragraphe.\n\nDeuxième paragraphe.', 300),
    'Premier paragraphe. Deuxième paragraphe.',
  );
});

test('result is capped at maxLength after normalization', () => {
  const long = 'é'.repeat(10);
  assert.equal(normalizeNotificationText(long, 5), 'ééééé');
});
