import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {toBirthYear} = require('../../functions/lib/user_search_fields.js');
const {
  isUnderEighteen,
  parseManagedBirthDate,
  validateGuardianConsent,
} = require('../../functions/lib/minor_consent.js');

test('managed birth date parsing returns null for invalid or future dates', () => {
  assert.equal(parseManagedBirthDate('not-a-date'), null);
  assert.equal(parseManagedBirthDate('2999-01-01'), null);
  assert.equal(toBirthYear(new Date('invalid')), null);
});

test('age is computed from the complete UTC date', () => {
  const today = new Date();
  const under18 = new Date(Date.UTC(
    today.getUTCFullYear() - 17,
    today.getUTCMonth(),
    today.getUTCDate(),
  ));
  const just18 = new Date(Date.UTC(
    today.getUTCFullYear() - 18,
    today.getUTCMonth(),
    today.getUTCDate(),
  ));
  assert.equal(isUnderEighteen(under18), true);
  assert.equal(isUnderEighteen(just18), false);
});

test('guardian agreement records an identified representative without handwriting', () => {
  assert.throws(() => validateGuardianConsent(null));
  assert.deepEqual(validateGuardianConsent({
    guardianName: 'Parent Guardian',
    relationship: 'parent',
    method: 'oral_confirmation',
    evidenceReference: '',
    mediaAllowed: false,
    confirmed: true,
  }), {
    guardianName: 'Parent Guardian',
    relationship: 'parent',
    method: 'oral_confirmation',
    evidenceReference: '',
    consentTextVersion: 'minor-profile-consent-v2',
    consentText: 'Le parent ou tuteur accepte la création d’une fiche football visible aux recruteurs vérifiés. Les demandes de contact seront examinées par l’administration. Les photos, vidéos et CV ne seront pas publiés sans un accord média distinct.',
    mediaAllowed: false,
  });
  assert.throws(() => validateGuardianConsent({
    guardianName: 'Parent Guardian',
    relationship: 'parent',
    method: 'electronic_signature',
    mediaAllowed: false,
    confirmed: true,
  }));
});

test('guardian media permission is independently recorded', () => {
  const consent = validateGuardianConsent({
    guardianName: 'Parent Guardian',
    relationship: 'parent',
    method: 'written_confirmation',
    evidenceReference: 'appel parent 12/10',
    jurisdictionCountryCode: 'ci',
    mediaAllowed: true,
    confirmed: true,
  });
  assert.equal(consent.jurisdictionCountryCode, 'CI');
  assert.equal(consent.method, 'written_confirmation');
  assert.equal(consent.mediaAllowed, true);
  assert.throws(() => validateGuardianConsent({
    guardianName: 'Parent Guardian',
    relationship: 'parent',
    method: 'oral_confirmation',
    mediaAllowed: 'yes',
    confirmed: true,
  }));
});
