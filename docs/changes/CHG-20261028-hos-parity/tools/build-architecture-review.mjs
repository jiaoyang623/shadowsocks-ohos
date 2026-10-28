#!/usr/bin/env node
// Build the architecture-layer review snapshot and brief.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const dir = path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/architecture');
fs.mkdirSync(dir, { recursive: true });

const reqSnap = JSON.parse(fs.readFileSync(path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/requirements/review-snapshot.json'), 'utf8'));
const seams = ['S1 Profile and selection store', 'S2 Native start and stop', 'S3 Tun and stats', 'S4 Cross-process state', 'S5 Remote lists', 'S6 Platform surfaces', 'S7 VPN consent', 'S8 Plugin transport'];

const design = reqSnap.design.concat(seams.map((label, i) => ({
  id: `ARCH-S${i + 1}`,
  layer: 'architecture',
  title: label,
  status: 'ready',
  depends_on: [],
  content: [label],
  sources: ['docs/changes/CHG-20261028-hos-parity/architecture.md'],
})));

const oracles = reqSnap.oracles.concat(seams.map((label, i) => ({
  id: `O-SEAM-${String(i + 1).padStart(2, '0')}`,
  level: 'seam',
  introduced_at: 'architecture',
  title: label,
  status: 'ready',
  parent_ids: ['O-JOURNEY-01'],
  design_ids: [`ARCH-S${i + 1}`],
  trigger: `A provider and a consumer exchange data through ${label}.`,
  observe: 'The exchanged data, the return value and the visible state.',
  expected: ['The provider hands over the documented data.', 'The consumer reports a failure to the owner.'],
  failure_message: 'The seam drops data or reports success after a failure.',
  sources: ['docs/changes/CHG-20261028-hos-parity/architecture.md'],
})));

const snapshot = {
  ...reqSnap,
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · architecture',
  stage: 'architecture',
  design,
  oracles,
};
fs.writeFileSync(path.join(dir, 'review-snapshot.json'), JSON.stringify(snapshot, null, 2) + '\n');

const figures = [
  {
    id: 'F-01',
    kind: 'module',
    decision_id: 'D-01',
    title: 'Subsystem split',
    caption: 'Pages use the model. The model uses the native bridge. The extension owns the tun.',
    source: 'flowchart TB\n  P[Pages] --> M[Model]\n  M --> N[Native bridge]\n  N --> C[Rust core]\n  V[VPN extension] --> M\n  V --> N\n  M --> F[Platform adapters]',
    focus: 'Does the module split cover every journey?',
    omitted: 'The 11 pages and 30 model files are grouped by subsystem.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-02',
    kind: 'flow',
    decision_id: 'D-01',
    title: 'Connect journey',
    caption: 'The UI asks the model, the model starts the core, the extension creates the tun.',
    source: 'flowchart LR\n  U[User] --> P[Pages]\n  P --> M[Model]\n  M --> V[VPN extension]\n  V --> N[Native bridge]\n  N --> S[Server]',
    focus: 'Where does a failed connect stop?',
    omitted: 'DNS resolution and the notification step are omitted.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-03',
    kind: 'flow',
    decision_id: 'D-03',
    title: 'Subscription refresh journey',
    caption: 'The model fetches, parses and merges. A failure keeps the old list.',
    source: 'flowchart LR\n  U[User] --> P[Subscription page]\n  P --> M[Model]\n  M --> R[Remote endpoint]\n  M --> S[Profile store]',
    focus: 'What happens when the endpoint fails?',
    omitted: 'The merge key and the obsolete rule are described in the requirements.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-04',
    kind: 'sequence',
    decision_id: 'D-01',
    title: 'Start sequence',
    caption: 'Seven calls from the tap to the running tunnel.',
    source: 'sequenceDiagram\n  participant U as User\n  participant P as Pages\n  participant M as Model\n  participant V as VPN extension\n  participant N as Native bridge\n  U->>P: Tap Connect\n  P->>M: start(profile)\n  M->>V: startExtension()\n  V->>N: startTunFd(config, fd)\n  N-->>V: return code\n  V-->>M: status\n  M-->>P: phase',
    focus: 'Is the failure return path visible?',
    omitted: 'The consent dialog and the notification permission are omitted.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-05',
    kind: 'data',
    decision_id: 'D-02',
    title: 'Cross-process data',
    caption: 'Four stores cross the process boundary.',
    source: 'flowchart LR\n  UI[UI process] --> PF[Profile store]\n  UI --> SF[Status file]\n  V[VPN extension] --> SF\n  V --> TF[Traffic sample]\n  UI --> TF',
    focus: 'Does each store have one writer?',
    omitted: 'File formats are in the requirements and the specs.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-06',
    kind: 'state',
    decision_id: 'D-01',
    title: 'Service state',
    caption: 'Five states and the stop path.',
    source: 'stateDiagram-v2\n  [*] --> Idle\n  Idle --> Connecting: start\n  Connecting --> Connected: ready\n  Connecting --> Stopping: stop\n  Connected --> Stopping: stop\n  Stopping --> Stopped: teardown\n  Stopped --> Connecting: start\n  Stopping --> Idle: connection drop',
    focus: 'Can every state be left?',
    omitted: 'The two HttpsTest machines are omitted.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-07',
    kind: 'change-map',
    decision_id: 'D-04',
    title: 'Change map',
    caption: 'One new seam, two modified subsystems, three unchanged.',
    source: 'flowchart LR\n  A[Pages: modified] --> B[Model: modified]\n  B --> C[Native bridge: unchanged]\n  B --> D[Platform adapters: modified]\n  C --> E[Rust core: unchanged]\n  F[VPN extension: unchanged]',
    focus: 'Is the code change limited to the parity gaps?',
    omitted: 'File-level changes are listed in the change map table.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
];

const brief = {
  schema_version: 'a01-review-brief/1',
  layer: 'architecture',
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · architecture',
  conclusion: 'The existing subsystem split carries the parity work. Review the seam ownership and the platform decisions.',
  baseline: 'e123804+dirty',
  abbreviations: {
    UI: 'User interface',
    VPN: 'Virtual private network',
    DNS: 'Domain name system',
    ACL: 'Access control list',
    SDK: 'Software development kit',
    API: 'Application programming interface',
    E2E: 'End-to-end',
    QR: 'Quick response',
    NAPI: 'Native application programming interface',
    ABI: 'Application binary interface',
  },
  decisions: [
    {
      id: 'D-01',
      priority: 'P0',
      question: 'Does the existing module split carry every parity journey?',
      reason: 'The app already separates pages, model, native bridge, core and platform adapters.',
      options: [
        { id: 'A', label: 'Keep the split', description: 'Add the parity work inside the existing subsystems.', consequences: 'No large refactor. The seams stay as documented.', recommended: true },
        { id: 'B', label: 'Add a new service layer', description: 'Insert a service layer between pages and model.', consequences: 'More indirection and a larger change for the same behavior.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['ARCH-S1', 'ARCH-S2', 'ARCH-S3', 'ARCH-S4', 'ARCH-S5', 'ARCH-S6', 'ARCH-S7', 'ARCH-S8'],
    },
    {
      id: 'D-02',
      priority: 'P1',
      question: 'Should per-app proxy use the VPN application lists?',
      reason: 'The platform exposes trusted and blocked application lists.',
      options: [
        { id: 'A', label: 'Use the platform lists', description: 'Add an app picker and pass the lists to the VPN config.', consequences: 'Per-app proxy becomes reachable. The picker needs a query permission decision.', recommended: true },
        { id: 'B', label: 'Defer per-app proxy', description: 'Keep the feature missing for 5.4.0.', consequences: 'The per-app proxy cases stay missing.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['ARCH-S1'],
    },
    {
      id: 'D-03',
      priority: 'P1',
      question: 'How should subscriptions refresh?',
      reason: 'A background scheduler needs system approval and may not run.',
      options: [
        { id: 'A', label: 'Manual and connect-time refresh', description: 'Refresh on user action and when a subscription profile is selected.', consequences: 'Predictable and testable. No silent refresh.', recommended: true },
        { id: 'B', label: 'Background schedule', description: 'Add a periodic background task.', consequences: 'Needs a system grant and is hard to test.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['ARCH-S5'],
    },
    {
      id: 'D-04',
      priority: 'P1',
      question: 'Do the platform decisions cover the Android-only cases?',
      reason: 'Some surfaces have no public HarmonyOS API.',
      options: [
        { id: 'A', label: 'Accept the exclusions', description: 'Record each Android-only case with a reason and a HarmonyOS alternative where one exists.', consequences: 'The release scope stays bounded.', recommended: true },
        { id: 'B', label: 'Build substitutes', description: 'Design a new surface for each exclusion.', consequences: 'The scope grows and needs new product decisions.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['ARCH-S6'],
    },
  ],
  figures,
  change_map: [
    { location: 'Pages', now: '11 pages', after: 'Parity behavior on the same pages', type: 'modified', design_ids: ['ARCH-S1'] },
    { location: 'Model', now: '30 model files', after: 'New parity paths, same stores', type: 'modified', design_ids: ['ARCH-S2'] },
    { location: 'Native bridge', now: 'NAPI and C ABI', after: 'No change', type: 'unchanged', design_ids: ['ARCH-S2'] },
    { location: 'Rust core', now: 'Vendored service', after: 'No change', type: 'unchanged', design_ids: ['ARCH-S3'] },
    { location: 'VPN extension', now: 'Tun and stats host', after: 'No change', type: 'unchanged', design_ids: ['ARCH-S3'] },
    { location: 'Platform adapters', now: 'Notification, task, picker', after: 'App picker and notification actions', type: 'modified', design_ids: ['ARCH-S6'] },
    { location: 'App picker seam', now: 'None', after: 'New seam between model and VPN config', type: 'new', design_ids: ['ARCH-S1'] },
  ],
  technical_notes: [
    { item: 'Baseline', value: 'e123804+dirty', reason: 'Current app' },
    { item: 'Seams', value: '8', reason: 'One per cross-boundary collaboration' },
    { item: 'Seam oracles', value: '8', reason: 'All pending-test' },
    { item: 'Platform decisions', value: '4 open questions', reason: 'Owner named in the architecture document' },
  ],
  diff_from_last_review: { first_review: true },
  trace: {
    architecture: 'docs/changes/CHG-20261028-hos-parity/architecture.md',
    requirements: 'docs/versions/5.4.0/requirements/requirements.md',
    oracles: 'docs/oracles/91-seams/seams.md',
  },
};
fs.writeFileSync(path.join(dir, 'review-brief.json'), JSON.stringify(brief, null, 2) + '\n');
console.log('wrote architecture review snapshot and brief');
