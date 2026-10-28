#!/usr/bin/env node
// Build the legacy review snapshot from the requirements model and journey oracles.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const versionDir = path.join(repo, 'docs/versions/5.4.0');
const model = JSON.parse(fs.readFileSync(path.join(versionDir, 'requirements/requirements-model.json'), 'utf8'));

const design = model.rules.map((r) => ({
  id: r.source.covers[0],
  layer: 'requirements',
  title: r.label,
  status: 'ready',
  depends_on: [],
  content: [r.label],
  sources: [r.source.where],
}));

const oracles = model.flows
  .filter((f) => f.id !== 'f_port')
  .map((f, i) => ({
    id: `O-JOURNEY-${String(i + 1).padStart(2, '0')}`,
    level: 'journey',
    introduced_at: 'requirements',
    title: f.label,
    status: 'ready',
    parent_ids: [],
    design_ids: (() => {
      const letter = 'ABCDEFGHIJK'[i];
      const first = model.rules.find((r) => r.id.startsWith(`R_U${letter}_`));
      return first ? [first.source.covers[0]] : [];
    })(),
    trigger: `The phone user opens ${f.label} on HarmonyOS.`,
    observe: 'Visible controls, screen text, persisted state and service state.',
    expected: [
      'The HarmonyOS screen matches the Android baseline.',
      'Each operation produces the expected result.',
      'A failure shows a message and leaves the screen usable.',
    ],
    failure_message: 'The screen differs from the Android baseline or an operation fails silently.',
    sources: ['docs/versions/5.4.0/requirements/requirements.md'],
  }));

const snapshot = {
  skill_version: 'a01',
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · requirements',
  scope: 'Reverse-engineered requirements, control tree and E2E cases for the Android mobile module at v5.3.5-nightly.',
  baseline: 'e123804+dirty',
  stage: 'requirements',
  design,
  oracles,
  tests: [],
  open_questions: [],
};

const out = path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/requirements/review-snapshot.json');
fs.writeFileSync(out, JSON.stringify(snapshot, null, 2) + '\n');
console.log(`wrote ${out}: design=${design.length} oracles=${oracles.length}`);
