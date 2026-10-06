import {readFile, readdir} from 'node:fs/promises';
import {extname, resolve, relative} from 'node:path';
import {pathToFileURL} from 'node:url';

// Match corrupted UTF-8/Windows-1252 pairs, not legitimate French "Âge".
const suspicious = /\u00c3[\u0080-\u00bf\u0152\u0153\u0160\u0161\u0178\u017d\u017e\u0192\u02c6\u02dc\u2013-\u2026\u2030\u2039\u203a\u20ac\u2122]|\u00c2[\u0080-\u00bf]|\u00e2[\u0080\u0082\u20ac\u201a]|\u00f0[\u009f\u0178]|[\u0080-\u009f\ufffd]/u;
const extensions = new Set(['.dart', '.ts', '.js', '.mjs', '.ps1', '.html', '.css', '.arb', '.json', '.xml', '.plist', '.strings', '.xcconfig']);
const ignored = new Set(['node_modules', 'build', '.dart_tool', '.git', '.credentials']);

export async function auditEncoding(roots) {
  const findings = [];
  let files = 0;
  async function visit(directory, root) {
    for (const entry of await readdir(directory, {withFileTypes: true})) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory() && !ignored.has(entry.name)) await visit(path, root);
      if (!entry.isFile() || (!extensions.has(extname(entry.name)) && entry.name !== 'apple-app-site-association')) continue;
      files++;
      const label = `${root}/${relative(root, path).replaceAll('\\', '/')}`;
      let text;
      try {
        text = new TextDecoder('utf-8', {fatal: true}).decode(await readFile(path));
      } catch {
        findings.push({file: label, kind: 'invalid-utf8'});
        continue;
      }
      text.split(/\r?\n/).forEach((line, index) => {
        if (suspicious.test(line)) findings.push({file: label, line: index + 1, kind: 'mojibake-or-control'});
      });
      if (['.arb', '.json'].includes(extname(entry.name)) || entry.name === 'apple-app-site-association') {
        try { JSON.parse(text); } catch { findings.push({file: label, kind: 'invalid-json'}); }
      }
    }
  }
  for (const root of roots) await visit(resolve(root), root);
  return {files, roots, findings};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const roots = process.argv.slice(2);
  if (!roots.length) throw new Error('Pass the source directories to inspect');
  const report = await auditEncoding(roots);
  console.log(JSON.stringify(report, null, 2));
  if (report.findings.length) process.exitCode = 1;
}
