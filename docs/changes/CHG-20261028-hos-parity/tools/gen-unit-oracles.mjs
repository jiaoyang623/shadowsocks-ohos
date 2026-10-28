#!/usr/bin/env node
// Generate HLD-layer unit oracles, one per unit.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const versionDir = path.join(repo, 'docs/versions/5.4.0');
const outDir = path.join(repo, 'docs/oracles/92-units');
fs.mkdirSync(outDir, { recursive: true });

const units = [
  ['U01', ['O-SEAM-02', 'O-SEAM-03'], 'C-02, C-03, C-04'],
  ['U02', ['O-SEAM-01'], 'C-01'],
  ['U03', ['O-SEAM-01', 'O-SEAM-02'], 'C-01, C-02'],
  ['U04', ['O-SEAM-01'], 'C-01'],
  ['U05', ['O-SEAM-05'], 'C-05'],
  ['U06', ['O-SEAM-05'], 'C-06'],
  ['U07', ['O-SEAM-06'], 'C-08'],
  ['U08', ['O-SEAM-08'], 'C-02'],
  ['U09', ['O-SEAM-06'], 'C-01'],
  ['U10', ['O-SEAM-06'], 'C-01'],
  ['U11', ['O-SEAM-03', 'O-SEAM-06'], 'C-07'],
];

let out = '# HLD-layer unit oracles\n\nEach oracle covers one unit behavior cluster. The anchors point to planned unit tests.\n\n';
for (const [u, parents, contracts] of units) {
  const spec = JSON.parse(fs.readFileSync(path.join(versionDir, 'machine', `${u}.json`), 'utf8'));
  const rules = spec.rules.map((r) => r.id);
  const first = rules[0];
  const mid = rules[Math.floor(rules.length / 2)];
  const last = rules[rules.length - 1];
  const id = `O-UNIT-${u.slice(1)}`;
  out += `### ${id} ${spec.title}\n`;
  out += `- 层级：单点\n`;
  out += `- 父判据：${parents.join('、')}\n`;
  out += `- 强度：强\n`;
  out += `- 设计依据：HLD ${contracts}；LLD ${u}\n`;
  out += `- 触发与前置条件：The user operates the ${spec.title} controls on HarmonyOS.\n`;
  out += `- 可观测点：The control state, the screen text, the persisted store and the service state.\n`;
  out += `- 期望：Every rule in ${u} behaves as the Android baseline. A failed action shows a message and keeps the screen usable. The store keeps the committed state.\n`;
  out += `- 失败信息：Expected the Android behavior for ${spec.title}; the HarmonyOS screen or store differs.\n`;
  out += `- 来源：HLD ${contracts}；需求 ${first}、${mid}、${last}\n`;
  out += `- 上游：${first}、${mid}、${last}\n`;
  out += `- 待建测试：[单元] entry/src/test/UnitParity.test.ets::${u}#behaviors\n`;
  out += `- 状态：pending-test\n`;
  out += `- 不确定特征：none\n`;
  out += `- 归属：owner=red 接收批次=CHG-20261028-hos-parity\n`;
  out += `- 复核：待复核\n\n`;
}
fs.writeFileSync(path.join(outDir, 'units.md'), out);
console.log(`wrote ${path.join(outDir, 'units.md')}`);
