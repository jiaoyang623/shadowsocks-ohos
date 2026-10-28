#!/usr/bin/env node
// Fill the review brief decisions and top-level fields after model figure generation.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = process.argv[2] || path.resolve(here, '../../../..');
const briefPath = path.join(repo, 'docs/changes/CHG-20261028-hos-parity/review/requirements/review-brief.json');
const brief = JSON.parse(fs.readFileSync(briefPath, 'utf8'));

brief.conclusion = 'The Android mobile app at v5.3.5-nightly is the parity target. Review the scope, the journey set and the acceptance bar.';
brief.baseline = 'e123804+dirty';
brief.abbreviations = {
  R: 'Requirement item',
  E2E: 'End-to-end',
  SDK: 'Software development kit',
  UI: 'User interface',
  API: 'Application programming interface',
  VPN: 'Virtual private network',
  CLOSE: 'Stop broadcast action',
  RELOAD: 'Restart action',
  QR: 'Quick response',
  PASS: 'Validation result',
  HTTP: 'Hypertext transfer protocol',
  TLS: 'Transport layer security',
  SOCKS: 'SOCKS proxy protocol',
  URL: 'Uniform resource locator',
  JSON: 'JavaScript object notation',
  DNS: 'Domain name system',
  UDP: 'User datagram protocol',
  TCP: 'Transmission control protocol',
  ACL: 'Access control list',
  SOCKS5: 'SOCKS version 5 proxy protocol',
  CAMERA: 'Camera permission',
  OSS: 'Open source software',
  GONE: 'Hidden view state',
  KB: 'Kilobyte',
  MB: 'Megabyte',
  ID: 'Identifier',
  IP: 'Internet protocol',
  APK: 'Android application package',
  ABI: 'Application binary interface',
  MTU: 'Maximum transmission unit',
  FAQ: 'Frequently asked questions',
  NFC: 'Near field communication',
  TV: 'Television',
  SS: 'Shadowsocks',
  INTERNET: 'Internet permission',
  UID: 'User identifier',
  UH: 'Unavailable host state',
  OK: 'Accepted result',
  XML: 'Extensible markup language',
  YAML: 'YAML markup language',
  URI: 'Uniform resource identifier',
  AES: 'Advanced encryption standard',
  GCM: 'Galois counter mode',
  BLAKE3: 'BLAKE3 hash function',
  AEAD: 'Authenticated encryption with associated data',
  CFB: 'Cipher feedback mode',
  CTR: 'Counter mode',
  RC4: 'Rivest cipher 4',
  BF: 'Blowfish cipher',
  MD5: 'Message digest 5',
  IDN: 'Internationalized domain name',
  ASCII: 'American standard code for information interchange',
  START: 'Start command',
  GFW: 'Great firewall',
  IO: 'Input and output',
  REPLACE: 'Replace import mode',
  ACTION_VIEW: 'Android view action',
  BOOT_COMPLETED: 'Android boot completed event',
  LOCKED_BOOT_COMPLETED: 'Android locked boot completed event',
  MY_PACKAGE_REPLACED: 'Android package replaced event',
  CLIPBOARD: 'System clipboard',
  BIND: 'Service binding',
  UNBIND: 'Service unbinding',
  ISO: 'International organization for standardization',
  SIP002: 'Shadowsocks SIP002 URL format',
  VIEW: 'View intent action',
  ABORT: 'Abort result',
  PCRE: 'Perl compatible regular expression',
  UTF: 'Unicode transformation format',
  EXAM: 'Example host prefix',
  CAMELLIA: 'Camellia cipher',
  UC: 'Upper case',
  SQL: 'Structured query language',
  HTTPS: 'Hypertext transfer protocol secure',
  INDEX: 'Index file',
  FAB: 'Floating action button',
};

brief.decisions = [
  {
    id: 'D-01',
    priority: 'P0',
    question: 'Is the Android v5.3.5-nightly mobile app the correct parity target?',
    reason: 'The reversed requirements, the control tree and the 348 cases come from this baseline.',
    options: [
      {
        id: 'A',
        label: 'Use this baseline',
        description: 'Keep Android v5.3.5-nightly as the target for 5.4.0.',
        consequences: 'The requirement set and all cases stay valid. A later Android change needs a new baseline.',
        recommended: true,
      },
      {
        id: 'B',
        label: 'Move to another baseline',
        description: 'Pick a different Android commit or version.',
        consequences: 'The extraction, the control tree and the case set must be rerun.',
        recommended: false,
      },
    ],
    recommendation: 'A',
    affected_design_ids: ['R-UA-01', 'R-UK-43'],
  },
  {
    id: 'D-02',
    priority: 'P0',
    question: 'Should the 56 Android-only cases stay out of the HarmonyOS port?',
    reason: 'Some surfaces depend on Android platform APIs that the public HarmonyOS SDK does not expose.',
    options: [
      {
        id: 'A',
        label: 'Keep them out',
        description: 'Record each case as android-only with the platform reason.',
        consequences: 'The port does not spend time on surfaces it cannot ship. A HarmonyOS equivalent can be added later.',
        recommended: true,
      },
      {
        id: 'B',
        label: 'Find equivalents',
        description: 'Design a HarmonyOS substitute for each Android-only surface.',
        consequences: 'The scope grows. Some substitutes need product decisions and extra design work.',
        recommended: false,
      },
    ],
    recommendation: 'A',
    affected_design_ids: ['R-UK-28', 'R-UG-04'],
  },
  {
    id: 'D-03',
    priority: 'P1',
    question: 'Do the 11 unit journeys match how a phone user works?',
    reason: 'Each journey drives one unit of implementation and its E2E cases.',
    options: [
      {
        id: 'A',
        label: 'Accept the journeys',
        description: 'Use the 11 unit journeys as the requirement-layer journeys.',
        consequences: 'Implementation and E2E can start per unit.',
        recommended: true,
      },
      {
        id: 'B',
        label: 'Rework named journeys',
        description: 'List the journeys that do not match real use.',
        consequences: 'The affected unit and its cases return to the requirement layer.',
        recommended: false,
      },
    ],
    recommendation: 'A',
    affected_design_ids: ['R-UA-01', 'R-UK-43'],
  },
  {
    id: 'D-04',
    priority: 'P1',
    question: 'Is the 348-case set the right acceptance bar for 5.4.0?',
    reason: 'Every requirement item has at least one case, and every case has a parity tag.',
    options: [
      {
        id: 'A',
        label: 'Use all 348 cases',
        description: 'Treat every case as an acceptance check for the release.',
        consequences: 'The release is complete only when the portable cases pass and the android-only cases have a recorded decision.',
        recommended: true,
      },
      {
        id: 'B',
        label: 'Trim the set',
        description: 'Drop cases that are not worth automating or checking by hand.',
        consequences: 'The dropped requirements lose their acceptance evidence.',
        recommended: false,
      },
    ],
    recommendation: 'A',
    affected_design_ids: (() => {
      const model = JSON.parse(fs.readFileSync(path.join(repo, 'docs/versions/5.4.0/requirements/requirements-model.json'), 'utf8'));
      return model.rules.map((r) => r.source.covers[0]);
    })(),
  },
];

brief.change_map = [
  {
    location: 'Requirements document',
    now: 'None',
    after: '412 requirement items, 51 state machines, open items',
    type: 'new',
    design_ids: ['R-UA-01'],
  },
  {
    location: 'Control tree',
    now: 'None',
    after: '340 controls in 11 units',
    type: 'new',
    design_ids: ['R-UA-01'],
  },
  {
    location: 'E2E cases',
    now: 'None',
    after: '348 cases with HarmonyOS parity tags',
    type: 'new',
    design_ids: ['R-UA-01'],
  },
  {
    location: 'HarmonyOS app code',
    now: '5.3.5 behavior',
    after: 'No code change in the requirements layer',
    type: 'unchanged',
    design_ids: ['R-UA-01'],
  },
  {
    location: 'Case parity tags',
    now: 'No HarmonyOS mapping',
    after: 'Every case carries implemented, partial, missing or android-only',
    type: 'modified',
    design_ids: ['R-UA-01'],
  },
];

brief.technical_notes = [
  { item: 'Android baseline', value: 'v5.3.5-nightly, commit ae28fd9', reason: 'Pinned parity target' },
  { item: 'HarmonyOS baseline', value: '5.3.5, commit e123804', reason: 'Current app state' },
  { item: 'Requirement items', value: '412', reason: 'One row per Android rule' },
  { item: 'E2E cases', value: '348', reason: 'Every requirement has at least one case' },
  { item: 'Parity split', value: '63 implemented, 93 partial, 136 missing, 56 android-only', reason: 'Current HarmonyOS state' },
  { item: 'Spec validator', value: 'PASS, 0 failures, 3 warnings', reason: 'Deterministic gate' },
];

brief.diff_from_last_review = { first_review: true };
brief.trace = {
  requirements: 'docs/versions/5.4.0/requirements/requirements.md',
  model: 'docs/versions/5.4.0/requirements/requirements-model.json',
  control_tree: 'docs/versions/5.4.0/android/INDEX.md',
  cases: 'docs/versions/5.4.0/e2e/INDEX.md',
  oracles: 'docs/oracles/90-journeys/journeys.md',
};

fs.writeFileSync(briefPath, JSON.stringify(brief, null, 2) + '\n');
console.log(`updated ${briefPath}: decisions=${brief.decisions.length} figures=${brief.figures.length}`);
