import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {passportObjectPath, parsePassportByteRange} =
  require('../../functions/lib/passport_view.js');

test('passport references are confined to the owner and the configured bucket', () => {
  const bucket = 'adfoot-production.firebasestorage.app';
  const path = 'identityDocuments/player-1/passport_1720000000.jpg';
  assert.equal(passportObjectPath(`gs://${bucket}/${path}`, 'player-1', bucket), path);
  assert.equal(
    passportObjectPath(
      `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
        'identityDocuments%2Fplayer-1%2Fpassport_1720000000.jpg?alt=media&token=old',
      'player-1', bucket,
    ),
    path,
  );
  assert.equal(passportObjectPath(`gs://other-bucket/${path}`, 'player-1', bucket), null);
  assert.equal(passportObjectPath(`gs://${bucket}/${path}`, 'player-2', bucket), null);
  assert.equal(
    passportObjectPath(`gs://${bucket}/identityDocuments/player-1/other.jpg`, 'player-1', bucket),
    null,
  );
  assert.equal(passportObjectPath('https://example.org/passport.jpg', 'player-1', bucket), null);
  assert.equal(
    passportObjectPath(
      `gs://${bucket}/identityDocuments/player-1/%2e%2e/passport_1.jpg`, 'player-1', bucket,
    ),
    null,
  );
  // PNG is also accepted, same as the file-name regex in storage.rules.
  const pngPath = 'identityDocuments/player-1/passport_1720000000.png';
  assert.equal(passportObjectPath(`gs://${bucket}/${pngPath}`, 'player-1', bucket), pngPath);
});

test('passport byte ranges cover preview requests without serving outside the file', () => {
  assert.deepEqual(parsePassportByteRange('bytes=0-', 100), {start: 0, end: 99});
  assert.deepEqual(parsePassportByteRange('bytes=10-19', 100), {start: 10, end: 19});
  assert.deepEqual(parsePassportByteRange('bytes=90-200', 100), {start: 90, end: 99});
  assert.deepEqual(parsePassportByteRange('bytes=-10', 100), {start: 90, end: 99});
  assert.equal(parsePassportByteRange('bytes=100-', 100), null);
  assert.equal(parsePassportByteRange('bytes=20-10', 100), null);
  assert.equal(parsePassportByteRange('bytes=0-9,20-29', 100), null);
});

test('the passport viewer is hosted on the domain and excluded from iOS app links', () => {
  const hosting = JSON.parse(readFileSync(
    new URL('../../firebase.json', import.meta.url), 'utf8',
  )).hosting;
  assert.ok(hosting.rewrites.some(
    (rewrite) => rewrite.source === '/passport/view/**' &&
      rewrite.function?.functionId === 'passportViewPage',
  ));
  const association = JSON.parse(readFileSync(
    new URL('../../site_pub/.well-known/apple-app-site-association', import.meta.url),
    'utf8',
  ));
  const components = association.applinks.details[0].components;
  assert.ok(components.some(
    (component) => component['/'] === '/passport/view/*' && component.exclude === true,
  ));
  assert.ok(association.applinks.details[0].paths.includes('NOT /passport/view/*'));
});
