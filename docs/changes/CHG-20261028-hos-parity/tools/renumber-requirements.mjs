#!/usr/bin/env node
// Renumber requirement IDs to the a01 item-ID grammar: R-UA-01 -> R-UA-01.
// The grammar is [A-Z]+(-[A-Z]+)*-\d{2,3}, so the unit segment must be letters.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const roots = [
  path.join(repo, 'docs/versions/5.4.0'),
  path.join(repo, 'docs/changes/CHG-20261028-hos-parity'),
];
const letters = 'ABCDEFGHIJK';
const map = {};
for (let i = 1; i <= 11; i += 1) {
  const unit = `U${String(i).padStart(2, '0')}`;
  map[unit] = `U${letters[i - 1]}`;
}

const exts = new Set(['.md', '.json', '.mjs', '.js', '.txt', '.yaml', '.yml']);
let files = 0;
let hits = 0;
function walk(dir) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) { walk(p); continue; }
    if (!exts.has(path.extname(ent.name))) continue;
    let text = fs.readFileSync(p, 'utf8');
    let changed = false;
    for (const [unit, letter] of Object.entries(map)) {
      const re = new RegExp(`R-${unit}-(\\d{2})`, 'g');
      const next = text.replace(re, (m, n) => { hits += 1; changed = true; return `R-${letter}-${n}`; });
      text = next;
    }
    if (changed) { fs.writeFileSync(p, text); files += 1; }
  }
}
for (const r of roots) if (fs.existsSync(r)) walk(r);

// Update the validator grammar so it accepts the new IDs.
const check = path.join(repo, 'docs/versions/5.4.0/tools/check-specs.mjs');
if (fs.existsSync(check)) {
  let text = fs.readFileSync(check, 'utf8');
  const before = text;
  text = text.replace(/R-U\\d\{2\}-\\d\{2\}/g, 'R-U[A-K]-\\d{2}');
  text = text.replace(/\\^R-U\\\\d\{2\}-\\\\d\{2\}\\\$/g, '^R-U[A-K]-\\\\d{2}$');
  if (text !== before) fs.writeFileSync(check, text);
}

console.log(JSON.stringify({ files, replacements: hits, map }, null, 2));
