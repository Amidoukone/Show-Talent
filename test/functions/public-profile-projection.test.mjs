import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  buildPublicProfileProjection,
  publicProfileChanged,
} = require('../../functions/lib/public_profile_projection.js');

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
