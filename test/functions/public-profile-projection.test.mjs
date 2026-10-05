import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  buildPublicProfileProjection,
  publicProfileChanged,
  requiresMinorProtection,
} = require('../../functions/lib/public_profile_projection.js');

test('minor birth dates cannot produce any public directory projection', () => {
  const profile = {
    nom: 'Joueur mineur', role: 'joueur', profilePublic: true,
    allowMessages: true, city: 'Bamako', photoProfil: 'photo.jpg',
  };
  const birthdayToday = new Date();
  birthdayToday.setUTCFullYear(birthdayToday.getUTCFullYear() - 17);

  assert.equal(requiresMinorProtection(birthdayToday), true);
  assert.equal(buildPublicProfileProjection('minor-1', profile, true), null);
  assert.equal(requiresMinorProtection('not-a-date'), true);
  assert.equal(requiresMinorProtection(undefined), false);
});

test('approved minor projection is football-only and cannot be messaged', () => {
  const profile = buildPublicProfileProjection('minor-2', {
    nom: 'Joueur mineur', role: 'joueur', profilePublic: true,
    minorProfileApproved: true, isSearchable: true,
    allowMessages: true, photoProfil: 'private-photo.jpg',
    positionCodes: ['ST'], nationalities: ['ML'], birthYear: 2010,
    city: 'Bamako', bio: 'bio privee', cvUrl: 'gs://private/cv.pdf',
    videosPubliees: ['video-1'],
  }, true);

  assert.equal(profile.isMinorProfile, true);
  assert.equal(profile.allowMessages, false);
  assert.equal(profile.isSearchable, true);
  assert.deepEqual(profile.positionCodes, ['ST']);
  for (const field of [
    'photoProfil', 'city', 'bio', 'cvUrl', 'videosPubliees',
  ]) assert.equal(field in profile, false, `${field} leaked`);
});

test('adult birth date remains eligible for the existing projection', () => {
  const birthday = new Date();
  birthday.setUTCFullYear(birthday.getUTCFullYear() - 18);
  assert.equal(requiresMinorProtection(birthday), false);
  assert.ok(buildPublicProfileProjection('adult-1', {
    nom: 'Joueur adulte', role: 'joueur',
  }, false));
});

test('search index retains complete football terms after a long name and bio', () => {
  const profile = buildPublicProfileProjection('player-1', {
    nom: 'Alexandre Jean Baptiste Moussa Camara',
    role: 'joueur',
    position: 'Milieu offensif',
    city: 'Ouagadougou',
    country: 'Burkina Faso',
    currentClubName: 'Étoile Sportive de Ouagadougou',
    positionCodes: ['AM', 'CM', 'RW'],
    nationalities: ['BF', 'CI'],
    bio: Array.from({length: 50}, (_, i) => `performance${i}`).join(' '),
    isSearchable: true,
  });

  assert.ok(profile);
  assert.ok(profile.searchPrefixes.length <= 200);
  for (const term of ['ouagadougou', 'milieu', 'ci']) {
    assert.ok(profile.searchPrefixes.includes(term), `Missing ${term}`);
  }
});

test('chat presence does not rewrite the public profile', () => {
  const before = {nom: 'Awa', role: 'joueur', activeAt: 1};
  const after = {...before, activeAt: 2, activeConversationId: 'chat-1'};
  assert.equal(publicProfileChanged('player-1', before, after), false);
  assert.equal(publicProfileChanged('player-1', before, {...after, city: 'Bamako'}), true);
  assert.equal(publicProfileChanged('player-1', before, null), true);
});
