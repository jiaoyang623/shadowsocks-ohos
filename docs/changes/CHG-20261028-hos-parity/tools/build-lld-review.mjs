#!/usr/bin/env node
// Build the LLD-layer review snapshot and brief.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const changeDir = path.join(repo, 'docs/changes/CHG-20261028-hos-parity');
const dir = path.join(changeDir, 'review/lld');
fs.mkdirSync(dir, { recursive: true });

const hldSnap = JSON.parse(fs.readFileSync(path.join(changeDir, 'review/hld/review-snapshot.json'), 'utf8'));
const units = [
  ['U01', 'Main shell'],
  ['U02', 'Profile list'],
  ['U03', 'Profile editor'],
  ['U04', 'Import and export'],
  ['U05', 'Subscriptions'],
  ['U06', 'Custom rules'],
  ['U07', 'Per-app proxy'],
  ['U08', 'Plugins'],
  ['U09', 'Settings'],
  ['U10', 'QR and About'],
  ['U11', 'System surfaces'],
];

const unitDesign = units.map(([u, title]) => ({
  id: `LLD-${u}`,
  layer: 'lld',
  title: `${u} ${title}`,
  status: 'ready',
  depends_on: ['HLD-C01'],
  content: [`${u} ${title} implementation plan`],
  sources: [`docs/changes/CHG-20261028-hos-parity/lld/${u}.md`],
}));

const design = hldSnap.design.concat(unitDesign);
const allDesignIds = design.map((d) => d.id);
const snapshot = {
  ...hldSnap,
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · LLD',
  stage: 'lld',
  design,
};
fs.writeFileSync(path.join(dir, 'review-snapshot.json'), JSON.stringify(snapshot, null, 2) + '\n');

const figures = [
  {
    id: 'F-01',
    kind: 'class',
    decision_id: 'D-01',
    title: 'Shared model',
    caption: 'Four shared records carry the work of several units. One owner sets the fields.',
    source: 'classDiagram\n  class Profile\n  class ProfileStore\n  class Diagnostics\n  class Settings\n  class Subscription\n  class PluginOptions\n  class Acl\n  ProfileStore --> Profile\n  Subscription --> Profile\n  Subscription --> PluginOptions\n  Acl --> Profile\n  Diagnostics --> Profile\n  Settings --> Diagnostics',
    focus: 'Does one field set serve every unit that reads a profile?',
    omitted: 'Methods and the new pure modules are omitted. The full API is in the unit plans.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-02',
    kind: 'flow',
    decision_id: 'D-02',
    title: 'Implementation order',
    caption: 'The model lands first. The pages consume the final API.',
    source: 'flowchart LR\n  A[Model wave] --> B[Page wave]\n  B --> C[Test wave]\n  C --> D[Build and fix]\n  A --> E[Resources and manifest]',
    focus: 'Can a page start before its model API is final?',
    omitted: 'The per-unit dependencies are in the unit plans.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-03',
    kind: 'change-map',
    decision_id: 'D-03',
    title: 'File change map',
    caption: 'The model and the pages change. The bridge and the core stay.',
    source: 'flowchart LR\n  M[model: 8 modified, 10 new] --> P[pages: 6 modified, 3 new]\n  P --> R[resources and manifest]\n  V[vpnability: modified] --> M\n  C[cpp and native: unchanged]',
    focus: 'Is the change limited to the app layer?',
    omitted: 'The exact file list is in the unit plans.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-04',
    kind: 'acceptance',
    decision_id: 'D-04',
    title: 'Test acceptance',
    caption: 'Pure logic runs on the host. Device surfaces run on hardware.',
    source: 'flowchart TB\n  H[Host specs] --> P[Pass on every model change]\n  D[Device specs] --> R[Require a real device]\n  E[Emulator] --> S[Proxy mode only]\n  P --> G[Green before completion]\n  R --> G',
    focus: 'Is every portable behavior covered by a host spec?',
    omitted: 'The per-unit test tables are in the unit plans.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
  {
    id: 'F-05',
    kind: 'contract',
    decision_id: 'D-01',
    title: 'Page to model contract',
    caption: 'A page reads a record and calls one model entry for each action.',
    source: 'flowchart LR\n  U[User] --> P[Page]\n  P -->|read| M[Model record]\n  P -->|action| F[Model function]\n  F -->|result or error| P\n  F --> S[Store]',
    focus: 'Does every page action have one model entry and one error path?',
    omitted: 'The native start path is in the earlier layers.',
    markers: [],
    interactions: ['filter', 'detail'],
  },
];

const brief = {
  schema_version: 'a01-review-brief/1',
  layer: 'lld',
  title: 'Shadowsocks HarmonyOS 5.4.0 Android parity · LLD',
  conclusion: 'The unit plans share a small model surface. Review the field reconciliation, the build order and the test split.',
  baseline: 'e123804+dirty',
  abbreviations: {
    LLD: 'Low-level design',
    HLD: 'High-level design',
    API: 'Application programming interface',
    VPN: 'Virtual private network',
    ACL: 'Access control list',
    JSON: 'JavaScript object notation',
    QR: 'Quick response',
    E2E: 'End-to-end',
    SDK: 'Software development kit',
    UI: 'User interface',
    DNS: 'Domain name system',
    UDP: 'User datagram protocol',
    TCP: 'Transmission control protocol',
    HTTP: 'Hypertext transfer protocol',
    HTTPS: 'Hypertext transfer protocol secure',
    TLS: 'Transport layer security',
    SIP: 'Simple internet protocol',
    UID: 'User identifier',
    GFW: 'Great firewall',
    APK: 'Android package',
    URL: 'Uniform resource locator',
    URI: 'Uniform resource identifier',
    ID: 'Identifier',
    OK: 'Approved',
    KB: 'Kilobyte',
    MB: 'Megabyte',
  },
  decisions: [
    {
      id: 'D-01',
      priority: 'P0',
      question: 'Does one shared field set serve every unit that changes a profile?',
      reason: 'Five units change the profile record and the settings record.',
      options: [
        { id: 'A', label: 'One reconciled record', description: 'One owner sets the fields and every unit uses them.', consequences: 'The export keeps the Android shape. No unit invents a second name for one value.', recommended: true },
        { id: 'B', label: 'One record per unit', description: 'Each unit adds its own fields and helpers.', consequences: 'Two fields would carry one Android value and the export would drift.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: allDesignIds,
    },
    {
      id: 'D-02',
      priority: 'P0',
      question: 'Should the model land before the pages?',
      reason: 'Pages call model functions. A page written against a guessed signature fails at build time.',
      options: [
        { id: 'A', label: 'Model first, pages second', description: 'Finish the model wave, then start the page wave.', consequences: 'Pages compile against the real API. One extra wave of wall time.', recommended: true },
        { id: 'B', label: 'One unit at a time', description: 'Build each unit from model to page in sequence.', consequences: 'Shared files would be edited by many owners in turn and conflicts would repeat.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['HLD-C01', 'HLD-C02', 'HLD-C05', 'HLD-C06', 'HLD-C07', 'HLD-C08'],
    },
    {
      id: 'D-03',
      priority: 'P1',
      question: 'Is one owner per shared file enough to prevent conflicting edits?',
      reason: 'Several units change the same page, the same model file and the same manifest.',
      options: [
        { id: 'A', label: 'One owner per file', description: 'The owner reads every unit plan for that file and reconciles them.', consequences: 'The edits apply once and in one order. Each owner must read more context.', recommended: true },
        { id: 'B', label: 'One owner per unit', description: 'Each unit edits its files directly.', consequences: 'Concurrent writes to the same file overwrite each other.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: allDesignIds,
    },
    {
      id: 'D-04',
      priority: 'P1',
      question: 'Are the platform limits acceptable for this release?',
      reason: 'Some Android surfaces have no public HarmonyOS API.',
      options: [
        { id: 'A', label: 'Accept the limits', description: 'Record each limit and implement the closest behavior.', consequences: 'The release can ship. A few app-picker and system-surface cases stay partial.', recommended: true },
        { id: 'B', label: 'Block on the platform', description: 'Wait for a public API for every gap.', consequences: 'The release waits with no end date.', recommended: false },
      ],
      recommendation: 'A',
      affected_design_ids: ['LLD-U07', 'LLD-U10', 'LLD-U11', 'HLD-C07', 'HLD-C08'],
    },
  ],
  figures,
  change_map: [
    { location: 'model', now: '30 files', after: '8 modified, 10 new', type: 'modified', design_ids: ['LLD-U01'] },
    { location: 'pages', now: '7 pages', after: '6 modified, 3 new', type: 'modified', design_ids: ['LLD-U02'] },
    { location: 'resources and manifest', now: 'strings, colours, routes', after: 'New keys and two routes', type: 'new', design_ids: ['LLD-U09'] },
    { location: 'vpnability', now: 'one extension', after: 'App lists, notification and DNS port', type: 'modified', design_ids: ['LLD-U07'] },
    { location: 'cpp and native', now: 'bridge and core', after: 'No change', type: 'unchanged', design_ids: ['LLD-U08'] },
    { location: 'tests', now: '10 host suites', after: '11 host parity suites', type: 'new', design_ids: ['LLD-U04'] },
  ],
  technical_notes: [
    { item: 'Units', value: '11', reason: 'One plan per unit' },
    { item: 'Shared files', value: '6', reason: 'Profile, store, diagnostics, subscription, main page, editor' },
    { item: 'Platform limits', value: '4', reason: 'App list, barcode decode, boot, system tile' },
  ],
  diff_from_last_review: { first_review: true },
  trace: {
    lld: 'docs/changes/CHG-20261028-hos-parity/lld.md',
    hld: 'docs/changes/CHG-20261028-hos-parity/hld.md',
    requirements: 'docs/versions/5.4.0/requirements/requirements.md',
  },
};
fs.writeFileSync(path.join(dir, 'review-brief.json'), JSON.stringify(brief, null, 2) + '\n');
console.log('wrote LLD review snapshot and brief');
