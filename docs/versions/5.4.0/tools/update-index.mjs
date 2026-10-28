#!/usr/bin/env node
// Rebuild the E2E case index from the machine specs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.argv[2] || path.resolve(here, '..');
const units = Array.from({ length: 11 }, (_, i) => `U${String(i + 1).padStart(2, '0')}`);
const titles = {
  U01: 'Main shell, navigation drawer, connect control, stats bar',
  U02: 'Profile list, row layout, search, reorder, delete, share popup',
  U03: 'Profile editor and UDP fallback',
  U04: 'Import and export flows',
  U05: 'Subscriptions: URL list, add/edit/remove dialog, refresh service and profile merge',
  U06: 'Custom rules and ACL',
  U07: 'Per-app proxy, Apps VPN mode',
  U08: 'Plugin picker and plugin options',
  U09: 'Global settings',
  U10: 'QR scanner and About',
  U11: 'System surfaces: notification, tile, shortcuts, boot, Tasker',
};

const specs = units.map((u) => JSON.parse(fs.readFileSync(path.join(root, 'machine', `${u}.json`), 'utf8')));
const totals = { implemented: 0, partial: 0, missing: 0, android_only: 0 };
let totalCases = 0;

let unitTable = '| Unit | Title | Cases | Implemented | Partial | Missing | Android only | Doc link |\n';
unitTable += '| --- | --- | --- | --- | --- | --- | --- | --- |\n';
for (const spec of specs) {
  const s = spec.parity_summary;
  const n = spec.cases.length;
  totalCases += n;
  for (const k of Object.keys(totals)) totals[k] += s[k] || 0;
  unitTable += `| ${spec.unit} | ${titles[spec.unit]} | ${n} | ${s.implemented} | ${s.partial} | ${s.missing} | ${s.android_only} | [${spec.unit}](${spec.unit}.md) |\n`;
}
unitTable += `| Total | ${specs.length} units | ${totalCases} | ${totals.implemented} | ${totals.partial} | ${totals.missing} | ${totals.android_only} | |\n`;

const order = ['missing', 'partial', 'android-only', 'implemented'];
let caseTable = '| Parity | Case | Title | Unit |\n| --- | --- | --- | --- |\n';
for (const parity of order) {
  for (const spec of specs) {
    for (const c of spec.cases) {
      if (c.parity === parity) {
        caseTable += `| ${parity} | ${c.id} | ${c.title} | ${spec.unit} |\n`;
      }
    }
  }
}

const current = fs.readFileSync(path.join(root, 'e2e/INDEX.md'), 'utf8');
const tailStart = current.indexOf('## How to run a case');
const tail = tailStart >= 0 ? current.slice(tailStart) : '';
const head = `# E2E case index\n\nThe baseline pairs Android shadowsocks-android v5.3.5-nightly (commit ae28fd9) with HarmonyOS 5.3.5 (commit e123804) and has ${totalCases} E2E cases in ${specs.length} units.\n\n## Cases per unit\n\n${unitTable}\nCounts come from the unit JSON files in \`machine/\`.\n\n## Coverage of the HarmonyOS port\n\nMissing cases are what the port must add. Partial cases are what the port must finish. Android-only cases cannot be ported as they are. Implemented cases are the current baseline.\n\n${caseTable}\n`;
fs.writeFileSync(path.join(root, 'e2e/INDEX.md'), head + tail);
console.log(`wrote e2e/INDEX.md: ${totalCases} cases, ${JSON.stringify(totals)}`);
