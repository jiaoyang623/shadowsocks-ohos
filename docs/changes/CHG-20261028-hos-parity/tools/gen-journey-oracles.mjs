#!/usr/bin/env node
// Generate the requirements-layer journey oracles from the unit specs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const versionDir = path.join(repo, 'docs/versions/5.4.0');
const outDir = path.join(repo, 'docs/oracles/90-journeys');
fs.mkdirSync(outDir, { recursive: true });

const units = ['U01', 'U02', 'U03', 'U04', 'U05', 'U06', 'U07', 'U08', 'U09', 'U10', 'U11'];
const code = { U01: 'UA', U02: 'UB', U03: 'UC', U04: 'UD', U05: 'UE', U06: 'UF', U07: 'UG', U08: 'UH', U09: 'UI', U10: 'UJ', U11: 'UK' };
const A = { U01: 'A', U02: 'B', U03: 'C', U04: 'D', U05: 'E', U06: 'F', U07: 'G', U08: 'H', U09: 'I', U10: 'J', U11: 'K' };

let out = '# Requirements-layer journey oracles\n\n';
out += 'Each journey follows one unit flow from the requirements model.\n\n';

for (const u of units) {
  const spec = JSON.parse(fs.readFileSync(path.join(versionDir, 'machine', `${u}.json`), 'utf8'));
  const rules = spec.rules.map((r) => r.id);
  const first = rules[0];
  const mid = rules[Math.floor(rules.length / 2)];
  const last = rules[rules.length - 1];
  const id = `O-JOURNEY-${String(units.indexOf(u) + 1).padStart(2, '0')}`;
  const slug = spec.title.replace(/[^A-Za-z0-9]+/g, ' ').trim();
  out += `### ${id} ${slug}\n`;
  out += `- 层级：旅程\n`;
  out += `- 父判据：无（旅程层没有父判据）\n`;
  out += `- 强度：强\n`;
  out += `- 设计依据：需求 ${first}、${mid}、${last}；需求模型 flow f_${u.toLowerCase()}\n`;
  out += `- 触发与前置条件：The phone user opens the ${spec.title} screen on HarmonyOS with at least one profile.\n`;
  out += `- 可观测点：The visible controls, the text on the screen, the persisted state, and the service state.\n`;
  out += `- 期望：The screen shows the same controls and labels as the Android baseline. Each operation produces the expected result. A failure shows a message and leaves the screen usable.\n`;
  out += `- 失败信息：Expected the Android behavior for ${spec.title}; the HarmonyOS screen differs or the operation fails silently.\n`;
  out += `- 来源：需求 ${first}、${mid}、${last}\n`;
  out += `- 上游：${first}、${mid}、${last}\n`;
  out += `- 待建测试：[E2E] entry/src/ohosTest/ets/test/ParityE2e.test.ets::${u}Journey#flow\n`;
  out += `- 状态：pending-test\n`;
  out += `- 不确定特征：NOT-EVALUATED\n`;
  out += `- 归属：owner=red 接收批次=CHG-20261028-hos-parity\n`;
  out += `- 复核：待复核\n\n`;
}

fs.writeFileSync(path.join(outDir, 'journeys.md'), out);
console.log(`wrote ${path.join(outDir, 'journeys.md')}`);
