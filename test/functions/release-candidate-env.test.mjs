import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync, rmdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
const run = (name, args) => spawnSync(process.execPath, [join(root, 'scripts', name), ...args], {
  cwd: root, encoding: 'utf8', timeout: 10000,
});

test('release tools reject missing target and mismatched credentials before any cloud call', () => {
  const directory = mkdtempSync(join(tmpdir(), 'adfoot-target-'));
  const credentials = join(directory, 'account.json');
  writeFileSync(credentials, JSON.stringify({type: 'service_account', project_id: 'adfoot-staging'}));
  try {
    for (const name of ['prepare', 'smoke']) {
      for (const args of [[], ['--credentials', credentials, '--environment', 'production']]) {
        const result = run(`${name}-release-candidate.mjs`, args);
        assert.equal(result.status, 1, result.stderr);
        assert.match(result.stderr, /required|Expected|mismatch/);
      }
      const result = run(`${name}-staging-candidate.mjs`, ['--environment', 'production']);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /staging-only/);
    }
  } finally {
    rmSync(credentials);
    rmdirSync(directory);
  }
});
