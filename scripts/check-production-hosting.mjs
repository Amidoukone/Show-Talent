// Read-only: compare the public bytes with the exact local release files.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const environment = process.argv[2] ?? 'production';
assert.ok(['staging', 'production'].includes(environment), 'Expected staging or production');
const publicOrigins = environment === 'production'
  ? ['https://adfoot-production.web.app', 'https://adfoot.org']
  : ['https://adfoot-staging.web.app'];
const adminOrigin = environment === 'production' ? 'https://adfoot-admin.web.app' : 'https://adfoot-admin-staging.web.app';
const adminBuild = resolve('../..', 'WEB/Show_talent_web/build/web');
const checks = [];
for (const origin of publicOrigins) {
  for (const file of ['index.html', 'auth-action.js', 'legal/privacy-policy.html', 'legal/account-deletion.html',
    '.well-known/assetlinks.json', '.well-known/apple-app-site-association']) {
    checks.push([`${origin}/${file}`, resolve('site_pub', file)]);
  }
}
for (const file of ['index.html', 'main.dart.js', 'flutter_bootstrap.js']) {
  checks.push([`${adminOrigin}/${file}`, resolve(adminBuild, file)]);
}
for (const [url, path] of checks) {
  const response = await fetch(url, {signal: AbortSignal.timeout(60000), headers: {'Cache-Control': 'no-cache'}});
  assert.equal(response.status, 200, url);
  const remote = Buffer.from(await response.arrayBuffer());
  const local = await readFile(path);
  assert.equal(digest(remote), digest(local), `Deployed content differs: ${url}`);
  console.log(JSON.stringify({url, status: response.status, bytes: remote.length, sha256: digest(remote)}));
}
for (const path of ['/account/reset', '/account/verify', '/cv/view/invalid', '/legal/terms.draft.html']) {
  const expected = path.includes('invalid') || path.includes('.draft.') ? 404 : 200;
  const url = `${publicOrigins.at(-1)}${path}`;
  const response = await fetch(url, {signal: AbortSignal.timeout(30000)});
  assert.equal(response.status, expected, path);
  console.log(JSON.stringify({url, status: response.status}));
}
