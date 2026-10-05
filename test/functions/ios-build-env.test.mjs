import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const script = fileURLToPath(new URL('../../scripts/check-ios-build-env.mjs', import.meta.url));
const valid = {APP_ENV: 'staging', FIREBASE_PROJECT_ID: 'adfoot-staging',
  FIREBASE_IOS_BUNDLE_ID: 'org.adfoot.app.staging', FIREBASE_MESSAGING_SENDER_ID: '123',
  FIREBASE_IOS_APP_ID: '1:123:ios:abcdef', FIREBASE_IOS_API_KEY: 'test-key',
  FIREBASE_STORAGE_BUCKET: 'adfoot-staging.firebasestorage.app',
  VIDEO_SHARE_BASE_URL: 'https://adfoot-staging.firebaseapp.com'};
const run = (overrides) => spawnSync(process.execPath, [script, 'staging'], {
  env: {...process.env, ...valid, ...overrides}, encoding: 'utf8',
});
test('staging iOS build accepts a coherent configuration', () => assert.equal(run({}).status, 0));
test('staging iOS build rejects cross-platform or cross-project settings', () => {
  for (const override of [{FIREBASE_IOS_APP_ID: '1:123:android:abcdef'},
    {FIREBASE_PROJECT_ID: 'adfoot-production'}, {VIDEO_SHARE_BASE_URL: 'https://adfoot.org'},
    {FIREBASE_MESSAGING_SENDER_ID: '999'}, {FIREBASE_IOS_API_KEY: ''}]) {
    assert.notEqual(run(override).status, 0);
  }
});

test('production iOS build validates its own target and sharing domain', () => {
  const production = {...valid, APP_ENV: 'production', FIREBASE_PROJECT_ID: 'adfoot-production',
    FIREBASE_IOS_BUNDLE_ID: 'org.adfoot.app', FIREBASE_STORAGE_BUCKET: 'adfoot-production.firebasestorage.app',
    VIDEO_SHARE_BASE_URL: 'https://adfoot.org'};
  const check = (overrides = {}) => spawnSync(process.execPath, [script, 'production'], {
    env: {...process.env, ...production, ...overrides}, encoding: 'utf8',
  });
  assert.equal(check().status, 0);
  for (const override of [{APP_ENV: 'staging'}, {FIREBASE_IOS_BUNDLE_ID: 'org.adfoot.app.staging'},
    {FIREBASE_IOS_APP_ID: '1:123:android:abcdef'}, {VIDEO_SHARE_BASE_URL: valid.VIDEO_SHARE_BASE_URL},
    {FIREBASE_STORAGE_BUCKET: valid.FIREBASE_STORAGE_BUCKET}]) assert.notEqual(check(override).status, 0);
});
