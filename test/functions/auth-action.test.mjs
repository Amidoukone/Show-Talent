import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../../site_pub/auth-action.js', import.meta.url), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));
function page(fetch) {
  const nodes = new Map();
  let timeout;
  let cleared = false;
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {textContent: '', hidden: true, className: '',
      addEventListener() {}, value: ''});
    return nodes.get(id);
  };
  vm.runInNewContext(source, {window: {location: {pathname: '/account/verify',
    origin: 'https://adfoot.org', host: 'adfoot.org',
    href: 'https://adfoot.org/account/verify?oobCode=test&apiKey=test'}},
    document: {getElementById: node}, URL, URLSearchParams, AbortController, fetch,
    setTimeout: (callback, milliseconds) => {assert.equal(milliseconds, 15000); timeout = callback; return 1;},
    clearTimeout: () => {cleared = true;},
  });
  return {node, expire: () => timeout(), cleared: () => cleared};
}

test('auth action exposes timeout instead of hanging on verification', async () => {
  const fixture = page((_url, options) => new Promise((_resolve, reject) => {
    options.signal.addEventListener('abort', () => reject(Object.assign(new Error('timeout'), {name: 'AbortError'})));
  }));
  fixture.expire();
  await flush();
  assert.match(fixture.node('action-status').textContent, /trop de temps/);
  assert.equal(fixture.node('success-panel').hidden, true);
  assert.equal(fixture.cleared(), true);
});

test('auth action only shows success after Firebase confirmation and clears timeout', async () => {
  const fixture = page(async () => ({ok: true, json: async () => ({})}));
  await flush();
  assert.match(fixture.node('action-status').textContent, /succès/);
  assert.equal(fixture.node('success-panel').hidden, false);
  assert.equal(fixture.cleared(), true);
});
