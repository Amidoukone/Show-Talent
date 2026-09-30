import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {cvObjectPath, parseCvByteRange} = require('../../functions/lib/cv_view.js');

test('CV references are confined to the owner and the configured bucket', () => {
  const bucket = 'adfoot-production.firebasestorage.app';
  const path = 'cvs/player-1/cv_1720000000.pdf';
  assert.equal(cvObjectPath(`gs://${bucket}/${path}`, 'player-1', bucket), path);
  assert.equal(
    cvObjectPath(
      `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
        'cvs%2Fplayer-1%2Fcv_1720000000.pdf?alt=media&token=old',
      'player-1', bucket,
    ),
    path,
  );
  assert.equal(cvObjectPath(`gs://other-bucket/${path}`, 'player-1', bucket), null);
  assert.equal(cvObjectPath(`gs://${bucket}/${path}`, 'player-2', bucket), null);
  assert.equal(cvObjectPath(`gs://${bucket}/cvs/player-1/other.pdf`, 'player-1', bucket), null);
  assert.equal(cvObjectPath('https://example.org/cv.pdf', 'player-1', bucket), null);
  assert.equal(cvObjectPath(`gs://${bucket}/cvs/player-1/%2e%2e/cv_1.pdf`, 'player-1', bucket), null);
});

test('PDF byte ranges cover iOS preview requests without serving outside the file', () => {
  assert.deepEqual(parseCvByteRange('bytes=0-', 100), {start: 0, end: 99});
  assert.deepEqual(parseCvByteRange('bytes=10-19', 100), {start: 10, end: 19});
  assert.deepEqual(parseCvByteRange('bytes=90-200', 100), {start: 90, end: 99});
  assert.deepEqual(parseCvByteRange('bytes=-10', 100), {start: 90, end: 99});
  assert.equal(parseCvByteRange('bytes=100-', 100), null);
  assert.equal(parseCvByteRange('bytes=20-10', 100), null);
  assert.equal(parseCvByteRange('bytes=0-9,20-29', 100), null);
});

test('the CV viewer is hosted on the domain and excluded from iOS app links', () => {
  const hosting = JSON.parse(readFileSync(
    new URL('../../firebase.json', import.meta.url), 'utf8',
  )).hosting;
  assert.ok(hosting.rewrites.some(
    (rewrite) => rewrite.source === '/cv/view/**' &&
      rewrite.function?.functionId === 'cvViewPage',
  ));
  const association = JSON.parse(readFileSync(
    new URL('../../site_pub/.well-known/apple-app-site-association', import.meta.url),
    'utf8',
  ));
  const components = association.applinks.details[0].components;
  assert.ok(components.some(
    (component) => component['/'] === '/cv/view/*' && component.exclude === true,
  ));
});
