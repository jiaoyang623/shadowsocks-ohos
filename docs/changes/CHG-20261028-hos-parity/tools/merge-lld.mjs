#!/usr/bin/env node
// Merge the per-unit LLD files into one LLD document.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const changeDir = path.join(repo, 'docs/changes/CHG-20261028-hos-parity');
const lldDir = path.join(changeDir, 'lld');
const units = ['U01', 'U02', 'U03', 'U04', 'U05', 'U06', 'U07', 'U08', 'U09', 'U10', 'U11'];

const titles = {
  U01: 'Main shell',
  U02: 'Profile list',
  U03: 'Profile editor',
  U04: 'Import and export',
  U05: 'Subscriptions',
  U06: 'Custom rules',
  U07: 'Per-app proxy',
  U08: 'Plugins',
  U09: 'Settings',
  U10: 'QR and About',
  U11: 'System surfaces',
};

let out = `# LLD — HarmonyOS 5.4.0 Android parity\n\nThis document is the merged low-level design for the parity batch.\nEach unit plan lists the files, the code changes, the state, the validation rules and the planned tests.\n\n## Units\n\n| Unit | Area | Plan |\n| --- | --- | --- |\n`;
for (const u of units) {
  out += `| ${u} | ${titles[u]} | [${u}](#${u.toLowerCase()}) |\n`;
}
out += '\n';

for (const u of units) {
  const text = fs.readFileSync(path.join(lldDir, `${u}.md`), 'utf8');
  const body = text.replace(/^# .*\n+/, '').replace(/^## /gm, '### ');
  out += `\n<a id="${u.toLowerCase()}"></a>\n## ${u} ${titles[u]}\n\n${body.trim()}\n`;
}

fs.writeFileSync(path.join(changeDir, 'lld.md'), out);
console.log(`wrote ${path.join(changeDir, 'lld.md')}`);
