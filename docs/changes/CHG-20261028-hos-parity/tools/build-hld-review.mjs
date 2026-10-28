#!/usr/bin/env node
// Build the HLD-layer review snapshot and brief.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const dir = path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/hld');
fs.mkdirSync(dir, { recursive: true });

const archSnap = JSON.parse(fs.readFileSync(path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/architecture/review-snapshot.json'), 'utf8'));
const contracts = ['C-01 Profile record', 'C-02 Start request', 'C-03 Tun handover', 'C-04 Traffic sample', 'C-05 Subscription merge', 'C-06 ACL composition', 'C-07 Notification', 'C-08 App selection'];

const design = archSnap.design.concat(contracts.map((label, i) => ({
  id: `HLD-C${String(i + 1).padStart(2, '0')}`,
  layer: 'hld',
  title: label,
  status: 'ready',
  depends_on: [],
  content: [label],
  sources: ['docs/changes/CHG-20261028-hos-parity/hld.md'],
})));

const unitOracles = Array.from({ length: 11 }, (_, i) => ({
  id: `O-UNIT-${String(i + 1).padStart(2, '0')}`,
  level: 'unit',
  introduced_at: 'hld',
  title: `Unit ${String(i + 1).padStart(2, '0')} behaviors`,
  status: 'ready',
  parent_ids: ['O-SEAM-01'],
  design_ids: [`HLD-C01`],
  trigger: 'The user operates a unit control on HarmonyOS.',
  observe: 'Control state, screen text, persisted store and service state.',
  expected: ['The unit follows the Android baseline.', 'A failed action keeps the screen usable.'],
  failure_message: 'The HarmonyOS screen or store differs from the baseline.',
  sources: ['docs/oracles/point.md'],
}));

const snapshot = {
  ...archSnap,
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · HLD',
  stage: 'hld',
  design,
  oracles: archSnap.oracles.concat(unitOracles),
};
fs.writeFileSync(path.join(dir, 'review-snapshot.json'), JSON.stringify(snapshot, null, 2) + '\n');

const figures = [
  {
    id: 'F-01',
    kind: 'class',
    decision_id: 'D-01',
    title: 'Model classes',
    caption: 'Pages use the store and the profile model. The store owns the selection.',
    source: 'classDiagram\n  class Profile\n  class ProfileStore\n  class Settings\n  class Subscription\n  class Acl\n  class TrafficStats\n  ProfileStore --> Profile\n  Subscription --> Profile\n  Acl --> Profile\n  TrafficStats --> Profile',
    focus: 'Does every page have one model entry?',
    omitted: 'Fields and methods are omitted. The model has 30 files.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-02',
    kind: 'contract',
    decision_id: 'D-01',
    title: 'Start request contract',
    caption: 'One config JSON in, one code and one error out.',
    source: 'flowchart LR\n  M[Model] -->|config JSON| N[Native bridge]\n  N -->|code| M\n  N -->|lastError| M',
    focus: 'Is the error path enough for the page?',
    omitted: 'The tun fd path is in C-03.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-03',
    kind: 'data',
    decision_id: 'D-03',
    title: 'Store ownership',
    caption: 'Five stores, one writer each.',
    source: 'flowchart LR\n  UI[UI process] --> P[profiles.json]\n  UI --> S[subscriptions.json]\n  UI --> G[settings.json]\n  V[VPN extension] --> ST[status.json]\n  V --> T[traffic.json]',
    focus: 'Can two writers corrupt a store?',
    omitted: 'File formats are in the requirements.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-04',
    kind: 'ui',
    decision_id: 'D-04',
    title: 'Main screen regions',
    caption: 'Four regions carry the connect state.',
    source: 'flowchart TB\n  A[Toolbar] --> B[Profile list]\n  B --> C[Connect button]\n  C --> D[Stats bar]',
    focus: 'Is the connect state visible from one region?',
    omitted: 'The drawer and the dialogs are omitted.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-05',
    kind: 'sequence',
    decision_id: 'D-02',
    title: 'Profile switch sequence',
    caption: 'Stop, settle, start.',
    source: 'sequenceDiagram\n  participant U as User\n  participant P as Page\n  participant M as Model\n  participant V as VPN extension\n  U->>P: Select profile\n  P->>M: switch(profile)\n  M->>V: stop\n  V-->>M: stopped\n  M->>M: settle counters\n  M->>V: start new profile',
    focus: 'Can a start race a stop?',
    omitted: 'The retry path is in the requirements.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-06',
    kind: 'change-map',
    decision_id: 'D-04',
    title: 'File change map',
    caption: 'Model and pages change. The core and bridge do not.',
    source: 'flowchart LR\n  A[pages: modified] --> B[model: modified]\n  B --> C[cpp: unchanged]\n  C --> D[native: unchanged]\n  E[vpnability: unchanged]',
    focus: 'Is the change small enough to test?',
    omitted: 'Per-file changes are in the change map table.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
];

const brief = {
  schema_version: 'a01-review-brief/1',
  layer: 'hld',
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · HLD',
  conclusion: 'The eight contracts connect the pages to the model and the model to the core. Review the ownership and failure paths.',
  baseline: 'e123804+dirty',
  abbreviations: {
    UI: 'User interface',
    VPN: 'Virtual private network',
    ACL: 'Access control list',
    JSON: 'JavaScript object notation',
    API: 'Application programming interface',
    SDK: 'Software development kit',
    E2E: 'End-to-end',
    HLD: 'High-level design',
  },
  decisions: [
    {
      id: 'D-01',
      priority: 'P0',
      question: 'Do the eight contracts cover every page-to-core call?',
      reason: 'Every page behavior needs a model entry and a return path.',
      options: [
        { id: 'A', label: 'Accept the contracts', description: 'Implement against C-01 to C-08.', consequences: 'The pages and the model have a stable interface.', recommended: true },
        { id: 'B', label: 'Add more contracts', description: 'Split a contract further.', consequences: 'More interface work before code.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: contracts.map((_, i) => `HLD-C${String(i + 1).padStart(2, '0')}`),
    },
    {
      id: 'D-02',
      priority: 'P1',
      question: 'Is the stop-settle-start order safe for a profile switch?',
      reason: 'The core reads the profile once at start.',
      options: [
        { id: 'A', label: 'Keep the order', description: 'Stop, wait for stopped, settle, start.', consequences: 'No traffic leaves through the old server.', recommended: true },
        { id: 'B', label: 'Start in parallel', description: 'Start the new profile before the old one stops.', consequences: 'Two cores would run at once and the single-instance rule fails.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['HLD-C02'],
    },
    {
      id: 'D-03',
      priority: 'P1',
      question: 'Does each store have one writer?',
      reason: 'The UI and the extension run in different processes.',
      options: [
        { id: 'A', label: 'Keep one writer per store', description: 'The UI writes profiles, subscriptions and settings. The extension writes status and traffic.', consequences: 'No cross-process write race.', recommended: true },
        { id: 'B', label: 'Let both write', description: 'Allow either process to write any store.', consequences: 'Lost updates and unreadable files.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['HLD-C01', 'HLD-C04'],
    },
    {
      id: 'D-04',
      priority: 'P1',
      question: 'Are the platform gaps acceptable for this release?',
      reason: 'The barcode decoder, the app picker permission and the notification action depend on the platform.',
      options: [
        { id: 'A', label: 'Accept the gaps', description: 'Record each gap and implement an alternative where one exists.', consequences: 'The release can ship without the missing platform APIs.', recommended: true },
        { id: 'B', label: 'Block the release', description: 'Wait for a platform API for every gap.', consequences: 'No release until the platform changes.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['HLD-C07', 'HLD-C08'],
    },
  ],
  figures,
  change_map: [
    { location: 'pages/', now: '7 pages', after: 'Parity controls and flows', type: 'modified', design_ids: ['HLD-C01'] },
    { location: 'model/', now: '30 files', after: 'Parity paths and stores', type: 'modified', design_ids: ['HLD-C02'] },
    { location: 'vpnability/', now: 'VPN extension', after: 'No change unless the app lists need it', type: 'unchanged', design_ids: ['HLD-C03'] },
    { location: 'cpp/ and native/', now: 'Bridge and core', after: 'No change', type: 'unchanged', design_ids: ['HLD-C02'] },
    { location: 'App picker', now: 'None', after: 'New page and VPN app lists', type: 'new', design_ids: ['HLD-C08'] },
  ],
  technical_notes: [
    { item: 'Contracts', value: '8', reason: 'One per cross-boundary collaboration' },
    { item: 'Unit oracles', value: '11', reason: 'One per unit' },
    { item: 'Platform gaps', value: '3', reason: 'Barcode, app picker permission, notification action' },
  ],
  diff_from_last_review: { first_review: true },
  trace: {
    hld: 'docs/changes/CHG-20261028-hos-parity/hld.md',
    architecture: 'docs/changes/CHG-20261028-hos-parity/architecture.md',
    requirements: 'docs/versions/5.4.0/requirements/requirements.md',
  },
};
fs.writeFileSync(path.join(dir, 'review-brief.json'), JSON.stringify(brief, null, 2) + '\n');
console.log('wrote HLD review snapshot and brief');
