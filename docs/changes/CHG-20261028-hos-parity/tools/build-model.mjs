#!/usr/bin/env node
// Build the a01 requirements model from the 5.4.0 machine specs.
// Deterministic: no timestamps, no randomness.
'use strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const versionDir = path.join(repo, 'docs/versions/5.4.0');
const machineDir = path.join(versionDir, 'machine');
const outFile = path.join(versionDir, 'requirements/requirements-model.json');

const UNITS = [
  ['U01', 'Main shell, navigation drawer, connect control, stats bar'],
  ['U02', 'Profile list, row layout, search, reorder, delete, share popup'],
  ['U03', 'Profile editor and UDP fallback'],
  ['U04', 'Import and export flows'],
  ['U05', 'Subscriptions'],
  ['U06', 'Custom rules and ACL'],
  ['U07', 'Per-app proxy, Apps VPN mode'],
  ['U08', 'Plugin picker and plugin options'],
  ['U09', 'Global settings'],
  ['U10', 'QR scanner and About'],
  ['U11', 'System surfaces: notification, tile, shortcuts, boot, Tasker'],
];

// Rules with only positive examples cannot satisfy M8. Cover them with a flow step.
const NO_COUNTEREXAMPLE = new Set(['R-UB-02', 'R-UC-39', 'R-UJ-21']);

const unitSpecs = UNITS.map(([id]) => {
  const p = path.join(machineDir, `${id}.json`);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
});

const actors = [
  {
    id: 'U_USER',
    label: 'Phone user',
    kind: 'person',
    outside: true,
    io: [
      { dir: 'in', data: 'profile, route and subscription choices' },
      { dir: 'out', data: 'tunnel traffic and connection state' },
    ],
    source: { where: '用户 第 1 条', covers: [] },
  },
  {
    id: 'U_DEV',
    label: 'HarmonyOS developer',
    kind: 'person',
    outside: true,
    io: [
      { dir: 'in', data: 'control tree, requirements and E2E cases' },
      { dir: 'out', data: 'HarmonyOS implementation and test evidence' },
    ],
    source: { where: '用户 第 2 条', covers: [] },
  },
  {
    id: 'APP',
    label: 'HarmonyOS app',
    kind: 'system',
    outside: false,
    io: [],
    source: { where: '问题与结果', covers: [] },
  },
];

const goals = [
  {
    id: 'g_user',
    label: 'Phone user runs the tunnel on HarmonyOS',
    behaviors: [
      {
        actor: 'U_USER',
        now: 'The HarmonyOS app has no verified parity target.',
        after: 'The app follows the verified Android behavior for each page and control.',
      },
    ],
    deliverables: ['Verified control tree', 'Requirement set', 'E2E case set'],
    source: { where: '问题与结果', covers: [] },
  },
  {
    id: 'g_port',
    label: 'Developer ports the Android behavior',
    behaviors: [
      {
        actor: 'U_DEV',
        now: 'The developer guesses how each Android control behaves.',
        after: 'The developer implements against a traced requirement and case.',
      },
    ],
    deliverables: ['HarmonyOS 5.4.0 parity release'],
    source: { where: '问题与结果', covers: [] },
  },
];

const scope = [
  {
    id: 'sc_do_pages',
    label: 'Every page, dialog, menu and preference screen in the Android mobile module',
    bucket: 'do',
    source: { where: 'Scope 第 1 条', covers: [] },
  },
  {
    id: 'sc_do_controls',
    label: 'Every user-visible or user-operable control',
    bucket: 'do',
    source: { where: 'Scope 第 2 条', covers: [] },
  },
  {
    id: 'sc_do_behavior',
    label: 'Behavior exposed by the UI, including state changes and validation',
    bucket: 'do',
    source: { where: 'Scope 第 3 条', covers: [] },
  },
  {
    id: 'sc_do_parity',
    label: 'A HarmonyOS parity tag for each requirement and each E2E case',
    bucket: 'do',
    source: { where: 'Scope 第 4 条', covers: [] },
  },
  {
    id: 'sc_not_tv',
    label: 'Android TV module behavior',
    bucket: 'not',
    source: { where: 'Scope 第 5 条', covers: [] },
  },
  {
    id: 'sc_not_plugin_internals',
    label: 'Plugin APK internals beyond the UI contract',
    bucket: 'not',
    source: { where: 'Scope 第 6 条', covers: [] },
  },
  {
    id: 'sc_not_protocol',
    label: 'Network protocol internals that the UI does not expose',
    bucket: 'not',
    source: { where: 'Scope 第 7 条', covers: [] },
  },
  {
    id: 'sc_not_android_only',
    label: 'Android-only surfaces without a HarmonyOS API equivalent',
    bucket: 'not',
    assumption: 'A2',
  },
  {
    id: 'sc_later_model',
    label: 'The a01 requirements model and review batch',
    bucket: 'later',
    source: { where: 'Scope 第 9 条', covers: [] },
  },
  {
    id: 'sc_later_ui',
    label: 'HarmonyOS implementation and UI restoration checks',
    bucket: 'later',
    source: { where: 'Scope 第 10 条', covers: [] },
  },
];

// Figure text must not contain item IDs. Also split cipher names such as AES-256.
function shown(s) {
  return String(s).replace(/([A-Za-z]+)-(\d+)/g, '$1 $2');
}

function step(id, actor, label, type, next, extra) {
  const s = { id, actor, label: shown(label), type, next: next.map((n) => ({ to: n.to, ...(n.label ? { label: shown(n.label) } : {}), ...(n.exception ? { exception: true } : {}) })), uses: [] };
  if (extra && extra.source) s.source = extra.source;
  if (extra && extra.assumption) s.assumption = extra.assumption;
  return s;
}

const flows = [];

// One journey per unit. Every decision has two labeled exits. Every path ends.
for (const spec of unitSpecs) {
  const uid = spec.unit.toLowerCase();
  const special = [];
  for (const r of spec.rules) if (NO_COUNTEREXAMPLE.has(r.id)) special.push(r.id);
  flows.push({
    id: `f_${uid}`,
    label: spec.title,
    source: { where: `需求条目 ${spec.unit}`, covers: [] },
    steps: [
      step('s0', 'U_USER', `Open the ${spec.title}`, 'start', [{ to: 's1' }], {
        assumption: spec.unit === 'U01' ? 'A3' : undefined,
        source: spec.unit === 'U01' ? undefined : { where: `需求条目 ${spec.unit}`, covers: [] },
      }),
      step('s1', 'U_USER', `Operate the ${spec.title} controls`, 'step', [{ to: 's2' }], {
        source: { where: `需求条目 ${spec.unit}`, covers: special },
      }),
      step('s2', 'U_USER', 'Does the operation succeed?', 'decision', [
        { to: 's3', label: 'Yes' },
        { to: 's4', label: 'No', exception: true },
      ], { source: { where: `需求条目 ${spec.unit}`, covers: [] } }),
      step('s3', 'APP', 'The expected result appears', 'end', [], {
        source: { where: `需求条目 ${spec.unit}`, covers: [] },
      }),
      step('s4', 'APP', 'An error message appears and the user recovers', 'step', [{ to: 's3' }], {
        source: { where: `需求条目 ${spec.unit}`, covers: [] },
      }),
    ],
  });
}

// The port journey: developer reads, builds, tests, fixes.
flows.push({
  id: 'f_port',
  label: 'Port the parity requirement to HarmonyOS',
  source: { where: '问题与结果', covers: [] },
  steps: [
    step('d0', 'U_DEV', 'Read the parity requirements and cases', 'start', [{ to: 'd1' }], { assumption: 'A1' }),
    step('d1', 'U_DEV', 'Build the HarmonyOS implementation', 'step', [{ to: 'd2' }], {
      source: { where: '问题与结果', covers: [] },
    }),
    step('d2', 'U_DEV', 'Do all parity cases pass?', 'decision', [
      { to: 'd3', label: 'Yes' },
      { to: 'd4', label: 'No', exception: true },
    ], { source: { where: '问题与结果', covers: [] } }),
    step('d3', 'U_DEV', 'Release the parity version', 'end', [], {
      source: { where: '问题与结果', covers: [] },
    }),
    step('d4', 'U_DEV', 'Fix the failing case and test again', 'step', [{ to: 'd2' }], {
      source: { where: '问题与结果', covers: [] },
    }),
  ],
});

const rules = [];
for (const spec of unitSpecs) {
  for (const r of spec.rules) {
    if (NO_COUNTEREXAMPLE.has(r.id)) continue;
    rules.push({
      id: r.id.replace(/-/g, '_'),
      label: shown(r.statement),
      uses: [],
      source: { where: `需求条目 ${spec.unit} 第 ${r.id.slice(-2)} 条`, covers: [r.id] },
      examples: r.examples.map((e) => ({
        given: shown(e.given),
        when: shown(e.when),
        then: shown(e.then),
        polarity: e.polarity,
      })),
    });
  }
}

// Flow step IDs must be unique across the model. Prefix each step with its flow ID.
for (const flow of flows) {
  const prefix = `${flow.id}_`;
  for (const s of flow.steps) {
    s.id = prefix + s.id;
    s.next = s.next.map((n) => ({ ...n, to: prefix + n.to }));
  }
}

const assumptions = [
  {
    id: 'A1',
    statement: 'The pinned Android baseline is the intended parity target.',
    basis: 'The user named the Android version in the same repository tree.',
    consequence: 'A later Android change is out of scope until a new baseline is set.',
  },
  {
    id: 'A2',
    statement: 'Android-only surfaces stay Android-only unless HarmonyOS exposes an equivalent system API.',
    basis: 'The public HarmonyOS SDK does not expose every Android platform surface.',
    consequence: 'Some cases become platform decisions instead of implementation work.',
  },
  {
    id: 'A3',
    statement: 'A control that is visible but disabled still counts as a control.',
    basis: 'The parity target is the visible UI, not only the active paths.',
    consequence: 'Disabled controls stay in the tree and in the case set.',
  },
];

const model = {
  schema_version: 'a01-requirements-model/1',
  system: 'Shadowsocks HarmonyOS 5.4.0 Android parity',
  source_doc: 'requirements.md',
  actors,
  goals,
  scope,
  flows,
  rules,
  states: [],
  entities: [],
  screens: [],
  empty_reasons: {
    states: 'The 51 state machines are recorded in the requirements document and in the unit specs. This model keeps only the flows needed for the requirement coverage check.',
    entities: 'The system has no persistent entity model beyond the profile record. The profile fields are part of the requirements and the control tree.',
    screens: 'The 48 screens and dialogs are recorded in android/INDEX.md and the unit specs. The model does not duplicate the control tree.',
  },
  assumptions,
  views: {
    problem: {
      decision_id: 'D-01',
      questions: [
        'Does the pinned Android baseline match the version the user wants?',
        'Which HarmonyOS users depend on the missing behaviors?',
      ],
    },
    scope: {
      decision_id: 'D-02',
      questions: [
        'Can the app ship without the Android-only surfaces?',
        'Which excluded surface has a HarmonyOS equivalent?',
      ],
    },
    journey: {
      decision_id: 'D-03',
      questions: [
        'Does the unit journey match how a phone user works?',
        'Which failure recovery path is missing from the case set?',
      ],
    },
    acceptance: {
      decision_id: 'D-04',
      questions: [
        'Is each case observable on a HarmonyOS device?',
        'Which parity tag needs a product decision?',
      ],
    },
  },
};

fs.writeFileSync(outFile, JSON.stringify(model, null, 2) + '\n');
const covered = new Set();
for (const el of [...rules, ...flows.flatMap((f) => f.steps)]) {
  for (const id of el.source?.covers ?? []) covered.add(id);
}
console.log(`wrote ${outFile}`);
console.log(`actors=${actors.length} goals=${goals.length} scope=${scope.length} flows=${flows.length} rules=${rules.length}`);
console.log(`covered requirement IDs=${covered.size}`);
