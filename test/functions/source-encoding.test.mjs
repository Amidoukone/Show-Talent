import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, unlink, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {auditEncoding} from '../../scripts/audit-source-encoding.mjs';

test('encoding audit accepts accents and finds corrupt ARB, XML and invalid UTF-8', async () => {
  const root = await mkdtemp(join(tmpdir(), 'adfoot-encoding-'));
  const fixtures = {
    'good.dart': '// Âge, Côte, Équipe, cœur, français, €',
    'bad.arb': JSON.stringify({label: 'Cr\u00c3\u00a9er'}),
    'bad.xml': '<label>\u00e2\u20ac\u2122</label>',
    'bad.html': Buffer.from([0xc3, 0x28]),
  };
  try {
    for (const [name, text] of Object.entries(fixtures)) await writeFile(join(root, name), text);
    const result = await auditEncoding([root]);
    assert.equal(result.files, 4);
    assert.equal(result.findings.length, 3);
    assert.ok(result.findings.every(item => !item.file.endsWith('good.dart')));
  } finally {
    for (const name of Object.keys(fixtures)) await unlink(join(root, name));
    await rmdir(root);
  }
});
