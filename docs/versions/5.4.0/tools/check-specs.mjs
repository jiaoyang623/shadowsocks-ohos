#!/usr/bin/env node
// check-specs.mjs: deterministic validator for the 5.4.0 machine specs.
// Usage: node tools/check-specs.mjs [--root VERSION_DIR] [--android-root REPO]
//        node tools/check-specs.mjs --self-test
// Exit 0: no failure. Exit 1: at least one failure. Exit 2: missing input.
// A step next target exists when a label matches it exactly, by prefix, or by
// containing all its significant tokens.
// A decision has two labeled exits when next lists two labeled exits, when the
// label has two branch tags, or when one branch label has a resolvable target.
// Branch tags: yes/true/ok, no/false, error/cancel/else.
// A case references a rule when a case value contains the rule ID, when the
// case source file equals the rule source file, or when a control in the case
// control_path has the same source file.
// A state is terminal when its name is a known terminal name, or when the
// machine lists it in terminal_states. Other states need an outgoing edge.
// Check 11 applies to every "source" field, not to sources_read paths.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const UNIT_IDS = Array.from({ length: 11 }, (_, i) => `U${String(i + 1).padStart(2, '0')}`);
const RES_GROUPS = ['layout', 'menu', 'xml'];
const CONTROL_TYPES = new Set(('screen dialog button text input switch checkbox list row image ' +
  'menu_item preference snackbar notification tile shortcut').split(' '));
const CONTROL_FIELDS = 'id type label android_id parent visible_when enabled_when action navigates_to source'.split(' ');
const RULE_KINDS = new Set('interaction validation state display persistence'.split(' '));
const POLARITIES = new Set('positive negative boundary'.split(' '));
const PARITIES = new Set(['implemented', 'partial', 'missing', 'android-only']);
const PARITY_KEYS = [['implemented', 'implemented'], ['partial', 'partial'], ['missing', 'missing'], ['android_only', 'android-only']];
const STEP_TYPES = new Set('start step decision end'.split(' '));
const TERMINALS = new Set('stopped disconnected destroyed terminated finished closed done complete completed end exited released unbound off dismissed cancelled canceled hidden gone failed failure success succeeded absent none unavailable removed unset unknown'.split(' '));

class InputError extends Error {}
const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v) => (Array.isArray(v) ? v : []);
const badSource = (s) => !(s.endsWith('/') || /^.+:\d+$/.test(s));

function parseArgs(argv) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const opts = { root: path.resolve(here, '..'), androidRoot: '', selfTest: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--self-test') opts.selfTest = true;
    else if (a === '--root' || a === '--android-root') {
      const v = argv[i + 1];
      if (!v || v.startsWith('--')) throw new InputError(`${a} needs a directory.`);
      opts[a === '--root' ? 'root' : 'androidRoot'] = path.resolve(v);
      i += 1;
    } else if (a.startsWith('--root=')) opts.root = path.resolve(a.slice(7));
    else if (a.startsWith('--android-root=')) opts.androidRoot = path.resolve(a.slice(15));
    else throw new InputError(`Unknown argument: ${a}`);
  }
  return opts;
}
function walkFiles(dir, base = dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    return e.isDirectory() ? walkFiles(full, base)
      : e.isFile() ? [path.relative(base, full).split(path.sep).join('/')] : [];
  }).sort();
}
function resolveAndroidRoot(root, explicit) {
  let dir = explicit;
  if (!dir) {
    const meta = path.join(root, 'context/meta.json');
    try {
      dir = fs.existsSync(meta) ? JSON.parse(fs.readFileSync(meta, 'utf8'))?.android_baseline?.repo || '' : '';
    } catch { dir = ''; }
  }
  dir = dir || '/opt/git/github/shadowsocks-android';
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) throw new InputError(`Android source root is missing: ${dir}`);
  return path.resolve(dir);
}
function discoverResources(androidRoot) {
  const resDir = path.join(androidRoot, 'mobile/src/main/res');
  const out = [];
  for (const group of RES_GROUPS) {
    const dir = path.join(resDir, group);
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) throw new InputError(`Android resource directory is missing: ${dir}`);
    for (const rel of walkFiles(dir)) out.push(path.posix.join('mobile/src/main/res', group, rel));
  }
  return out;
}
function parseUnitMap(file) {
  const byUnit = new Map();
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (!line.startsWith('|')) continue;
    const cells = line.split('|').slice(1, -1).map((s) => s.trim());
    if (cells.length >= 3 && /^U\d{2}$/.test(cells[0])) byUnit.set(cells[0], cells[2].split(';').map((s) => s.trim()).filter(Boolean));
  }
  const kt = new Set();
  for (const files of byUnit.values()) for (const f of files) if (f.endsWith('.kt')) kt.add(f);
  return { byUnit, kt };
}
function loadUnits(root, fail) {
  const dir = path.join(root, 'machine');
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) throw new InputError(`Machine directory is missing: ${dir}`);
  return UNIT_IDS.map((id) => {
    const rec = { id, file: path.join(dir, `${id}.json`), data: null, controls: [], rules: [], states: [], flows: [], cases: [], parent: new Map(), controlIds: new Set(), casePaths: new Map() };
    if (!fs.existsSync(rec.file)) fail(id, 1, `Unit file ${id}.json is missing.`);
    else {
      try { rec.data = JSON.parse(fs.readFileSync(rec.file, 'utf8')); }
      catch (e) { fail(id, 1, `Unit file ${id}.json does not parse: ${e.message}`); }
    }
    return rec;
  });
}
function requireStringFields(obj, names, label, unit, check, fail) {
  for (const f of names) {
    if (!(f in obj)) fail(unit, check, `${label} misses field ${f}.`);
    else if (typeof obj[f] !== 'string') fail(unit, check, `${label} field ${f} must be a string.`);
  }
}
function requireTypedFields(obj, types, label, unit, check, fail) {
  for (const [f, t] of Object.entries(types)) {
    if (!(t === 'array' ? Array.isArray(obj[f]) : typeof obj[f] === t)) fail(unit, check, `${label} misses field ${f} or its type is wrong.`);
  }
}
const STOP_WORDS = new Set('the a an of to in on and or for is are was with by then from at as it that this be'.split(' '));
const normTokens = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter((w) => w.length > 2 && !STOP_WORDS.has(w));
function matchStep(ref, labels) {
  if (typeof ref !== 'string' || !ref.trim()) return false;
  const tokens = normTokens(ref);
  return labels.some((l) => l === ref || l.startsWith(ref) || ref.startsWith(l) || (tokens.length > 0 && tokens.every((t) => normTokens(l).includes(t))));
}
function branchTags(text) {
  const out = new Set();
  const family = (w) => (/^(yes|true|ok)$/i.test(w) ? 'yes' : /^(no|false)$/i.test(w) ? 'no' : 'other');
  for (const m of String(text).matchAll(/\b(yes|true|ok|no|false|error|cancel(?:led|ed)?|otherwise|else|fail(?:ed)?)\b\s*(?:→|->|=>|:)/gi)) out.add(family(m[1]));
  for (const m of String(text).matchAll(/(?:—|–)\s*(yes|true|ok|no|false|error|cancel(?:led|ed)?|otherwise|else|fail(?:ed)?)\b/gi)) out.add(family(m[1]));
  return out;
}
function parseExitList(next) {
  const parts = String(next).split(/[;|\n]|\s+\/\s+/).map((s) => s.trim()).filter(Boolean);
  if (parts.length !== 2) return null;
  const exits = parts.map((s) => {
    const m = /^(.+?)\s*(?:->|=>|→|:)\s*(.+)$/.exec(s);
    return m ? { label: m[1].trim(), target: m[2].trim() } : null;
  });
  return exits.every((e) => e && e.label && e.target) ? exits : null;
}
function ancestors(rec, id) {
  const out = new Set();
  for (let cur = rec.parent.get(id) || ''; cur && !out.has(cur); cur = rec.parent.get(cur) || '') out.add(cur);
  return out;
}
function checkControls(rec, fail, warn) {
  const u = rec.id, list = arr(rec.data.controls);
  rec.controls = list.filter(isObj);
  if (rec.controls.length !== list.length) fail(u, 2, 'controls contains a non-object entry.');
  if (!list.length) fail(u, 2, 'Unit has no control.');
  for (const c of rec.controls) {
    const id = typeof c.id === 'string' && c.id ? c.id : '?';
    requireStringFields(c, CONTROL_FIELDS, `Control ${id}`, u, 2, fail);
    if (typeof c.id === 'string') {
      if (rec.controlIds.has(c.id)) fail(u, 2, `Duplicate control ID ${c.id}.`);
      rec.controlIds.add(c.id);
      if (!/^C-U\d{2}-\d{3}$/.test(c.id)) fail(u, 2, `Control ID ${c.id} does not match C-Uxx-nnn.`);
    }
    if (typeof c.type === 'string' && !CONTROL_TYPES.has(c.type)) fail(u, 2, `Control ${id} type ${c.type} is not in the enum.`);
    if (typeof c.label === 'string' && !c.label.trim()) warn(u, 2, `Control ${id} has an empty label.`);
    if (typeof c.source === 'string' && badSource(c.source)) fail(u, 11, `Control ${id} source is not file:line or a directory: ${JSON.stringify(c.source)}.`);
  }
  for (const c of rec.controls) if (typeof c.id === 'string' && typeof c.parent === 'string' && c.parent) rec.parent.set(c.id, c.parent);
  for (const [id, parent] of rec.parent) {
    if (!rec.controlIds.has(parent)) fail(u, 2, `Control ${id} parent ${parent} does not exist.`);
    const seen = new Set();
    for (let cur = parent; cur; cur = rec.parent.get(cur) || '') {
      if (cur === id || seen.has(cur)) { fail(u, 2, `Control parent cycle at ${id}.`); break; }
      seen.add(cur);
    }
  }
  if (!rec.controls.some((c) => c.type === 'screen')) fail(u, 2, 'Unit has no screen control.');
}
function checkRules(rec, fail, warn) {
  const u = rec.id;
  rec.rules = arr(rec.data.rules).filter(isObj);
  const ids = new Set();
  for (const r of rec.rules) {
    const id = typeof r.id === 'string' && r.id ? r.id : '?';
    requireStringFields(r, ['id', 'statement', 'kind', 'source'], `Rule ${id}`, u, 3, fail);
    if (typeof r.id === 'string') {
      if (ids.has(r.id)) fail(u, 3, `Duplicate rule ID ${r.id}.`);
      ids.add(r.id);
      if (!/^R-U[A-K]-\d{2}$/.test(r.id)) fail(u, 3, `Rule ID ${r.id} does not match R-Uxx-nn.`);
    }
    if (typeof r.kind === 'string' && !RULE_KINDS.has(r.kind)) fail(u, 3, `Rule ${id} kind ${r.kind} is not in the enum.`);
    if (typeof r.statement === 'string' && !r.statement.trim()) fail(u, 3, `Rule ${id} statement is empty.`);
    if (typeof r.source === 'string' && badSource(r.source)) fail(u, 11, `Rule ${id} source is not file:line or a directory: ${JSON.stringify(r.source)}.`);
    if (!Array.isArray(r.examples)) { fail(u, 3, `Rule ${id} misses the examples array.`); continue; }
    if (!r.examples.length) fail(u, 3, `Rule ${id} has no example.`);
    r.examples.forEach((e, i) => {
      if (!isObj(e)) { fail(u, 3, `Rule ${id} example ${i + 1} is not an object.`); return; }
      requireStringFields(e, ['given', 'when', 'then', 'polarity'], `Rule ${id} example ${i + 1}`, u, 3, fail);
      if (typeof e.polarity === 'string' && !POLARITIES.has(e.polarity)) fail(u, 3, `Rule ${id} example ${i + 1} polarity ${e.polarity} is not in the enum.`);
    });
    if (r.examples.length && !r.examples.some((e) => isObj(e) && e.polarity !== 'positive')) warn(u, 3, `Rule ${id} has only positive examples.`);
  }
}
function checkStates(rec, fail, warn) {
  const u = rec.id, list = arr(rec.data.states);
  for (const m of list) {
    if (!isObj(m)) { fail(u, 4, 'State machine is not an object.'); continue; }
    const name = typeof m.object === 'string' && m.object.trim() ? m.object : '?';
    if (typeof m.object !== 'string' || !m.object.trim()) fail(u, 4, 'State machine object is empty.');
    if (!Array.isArray(m.states) || !m.states.length) { fail(u, 4, `State machine ${name} has no states array or no state.`); continue; }
    const set = new Set();
    for (const s of m.states) {
      if (typeof s !== 'string' || !s.trim()) { fail(u, 4, `State machine ${name} has an empty state.`); continue; }
      if (set.has(s)) fail(u, 4, `State machine ${name} repeats state ${s}.`);
      set.add(s);
    }
    if (!Array.isArray(m.transitions) || !m.transitions.length) { fail(u, 4, `State machine ${name} has no transitions array or no transition.`); continue; }
    const outgoing = new Map();
    for (const t of m.transitions) {
      if (!isObj(t)) { fail(u, 4, `State machine ${name} has a non-object transition.`); continue; }
      requireStringFields(t, ['from', 'to', 'event', 'producer', 'source'], `Transition in ${name}`, u, 4, fail);
      if (typeof t.from === 'string' && !set.has(t.from)) fail(u, 4, `Transition from ${t.from} is not a state of ${name}.`);
      if (typeof t.to === 'string' && !set.has(t.to)) fail(u, 4, `Transition to ${t.to} is not a state of ${name}.`);
      for (const f of ['event', 'producer']) if (typeof t[f] === 'string' && !t[f].trim()) fail(u, 4, `Transition ${t.from}->${t.to} has an empty ${f}.`);
      if (typeof t.source === 'string' && badSource(t.source)) fail(u, 11, `Transition ${t.from}->${t.to} source is not file:line or a directory: ${JSON.stringify(t.source)}.`);
      if (typeof t.from === 'string') outgoing.set(t.from, (outgoing.get(t.from) || 0) + 1);
    }
    const explicit = new Set([...arr(m.terminal_states), ...arr(m.terminal)]);
    for (const s of set) if (!outgoing.has(s) && !explicit.has(s) && !TERMINALS.has(s.toLowerCase().trim())) fail(u, 4, `State ${s} has no outgoing transition and is not a terminal state.`);
  }
}
function checkFlows(rec, fail) {
  const u = rec.id;
  rec.flows = arr(rec.data.flows).filter(isObj);
  for (const f of rec.flows) {
    const id = typeof f.id === 'string' && f.id ? f.id : '?';
    requireTypedFields(f, { id: 'string', name: 'string', steps: 'array', exceptions: 'array' }, `Flow ${id}`, u, 5, fail);
    if (typeof f.name === 'string' && !f.name.trim()) fail(u, 5, `Flow ${id} name is empty.`);
    const steps = arr(f.steps);
    if (!steps.length) { fail(u, 5, `Flow ${id} has no step.`); continue; }
    const labels = new Set();
    for (const s of steps) {
      if (!isObj(s)) { fail(u, 5, `Flow ${id} has a non-object step.`); continue; }
      requireStringFields(s, ['label', 'type', 'next'], `Flow ${id} step`, u, 5, fail);
      if (typeof s.label === 'string') {
        if (!s.label.trim()) fail(u, 5, `Flow ${id} has a step with an empty label.`);
        else if (labels.has(s.label)) fail(u, 5, `Flow ${id} repeats step label ${s.label}.`);
        else labels.add(s.label);
      }
      if (typeof s.type === 'string' && !STEP_TYPES.has(s.type)) fail(u, 5, `Flow ${id} step ${s.label} type ${s.type} is not in the enum.`);
      if (!('exception' in s) || typeof s.exception !== 'boolean') fail(u, 5, `Flow ${id} step ${s.label} field exception must be a boolean.`);
    }
    const typed = steps.filter((s) => isObj(s) && typeof s.type === 'string');
    const starts = typed.filter((s) => s.type === 'start').length;
    if (starts !== 1) fail(u, 5, `Flow ${id} must have exactly one start. Found ${starts}.`);
    if (!typed.some((s) => s.type === 'end')) fail(u, 5, `Flow ${id} has no end.`);
    const labelList = [...labels], flowTags = new Set();
    for (const s of typed) for (const t of branchTags(s.label)) flowTags.add(t);
    for (const s of typed) {
      if (typeof s.label !== 'string' || typeof s.next !== 'string' || s.type === 'end') continue;
      if (s.type !== 'decision') {
        if (!matchStep(s.next, labelList)) fail(u, 5, `Flow ${id} step ${s.label} next target ${s.next || '(empty)'} does not exist.`);
        continue;
      }
      if (!s.next.trim()) { fail(u, 5, `Decision ${s.label} has no next target.`); continue; }
      const tags = branchTags(s.label);
      if (!(parseExitList(s.next) || parseExitList(s.label) || tags.size >= 2 || (matchStep(s.next, labelList) && (tags.size >= 1 || flowTags.size >= 2)))) {
        fail(u, 5, `Decision ${s.label} must have two labeled exits. Use "Yes -> A | No -> B" or tag both branches.`);
      }
    }
  }
}
function checkCases(rec, fail) {
  const u = rec.id;
  rec.cases = arr(rec.data.cases).filter(isObj);
  const ids = new Set();
  for (const c of rec.cases) {
    const id = typeof c.id === 'string' && c.id ? c.id : '?';
    requireTypedFields(c, { id: 'string', title: 'string', preconditions: 'array', steps: 'array', expected: 'array', control_path: 'string', parity: 'string', source: 'string' }, `Case ${id}`, u, 6, fail);
    if (typeof c.id === 'string') {
      if (ids.has(c.id)) fail(u, 6, `Duplicate case ID ${c.id}.`);
      ids.add(c.id);
      if (!/^TC-U\d{2}-\d{2}$/.test(c.id)) fail(u, 6, `Case ID ${c.id} does not match TC-Uxx-nn.`);
    }
    if (typeof c.title === 'string' && !c.title.trim()) fail(u, 6, `Case ${id} title is empty.`);
    const steps = arr(c.steps), expected = arr(c.expected);
    if (!steps.length || !expected.length) fail(u, 6, `Case ${id} has no step or no expected result.`);
    if ([...steps, ...expected].some((s) => typeof s !== 'string' || !s.trim())) fail(u, 6, `Case ${id} has an empty step or expected entry.`);
    if (typeof c.parity === 'string' && !PARITIES.has(c.parity)) fail(u, 6, `Case ${id} parity ${c.parity} is not in the enum.`);
    if (typeof c.source === 'string' && badSource(c.source)) fail(u, 11, `Case ${id} source is not file:line or a directory: ${JSON.stringify(c.source)}.`);
    const pathIds = typeof c.control_path === 'string' ? c.control_path.split('>').map((s) => s.trim()).filter(Boolean) : [];
    if (!pathIds.length) fail(u, 6, `Case ${id} has an empty control_path.`);
    for (const ref of pathIds) if (!rec.controlIds.has(ref)) fail(u, 6, `Case ${id} control_path references unknown control ${ref}.`);
    if (typeof c.id === 'string') rec.casePaths.set(c.id, pathIds);
  }
}
function checkRefs(rec, fail) {
  const u = rec.id, blob = rec.cases.map((c) => JSON.stringify(c)).join('\n');
  const fileOf = (s) => (typeof s === 'string' ? s.replace(/:\d+$/, '') : '');
  const files = new Set(rec.cases.map((c) => fileOf(c.source)).filter(Boolean));
  const byId = new Map(rec.controls.map((c) => [c.id, c]));
  for (const ids of rec.casePaths.values()) for (const ref of ids) {
    const ctl = byId.get(ref);
    if (ctl) files.add(fileOf(ctl.source));
  }
  for (const r of rec.rules) {
    const file = fileOf(r.source);
    if (typeof r.id === 'string' && r.id && !(blob.includes(r.id) || (file && files.has(file)))) {
      fail(u, 7, `Rule ${r.id} is unreferenced by any case.`);
    }
  }
  for (const s of rec.controls.filter((c) => c.type === 'screen')) {
    if (typeof s.id !== 'string' || !s.id) continue;
    const hit = [...rec.casePaths.values()].some((ids) => ids.some((id) => id === s.id || ancestors(rec, id).has(s.id)));
    if (!hit) fail(u, 8, `Screen ${s.id} is unreferenced by any case control_path.`);
  }
  const actual = { implemented: 0, partial: 0, missing: 0, android_only: 0 };
  for (const c of rec.cases) {
    const pair = PARITY_KEYS.find(([, v]) => v === c.parity);
    if (pair) actual[pair[0]] += 1;
  }
  if (isObj(rec.data.parity_summary)) for (const k of Object.keys(actual)) {
    const got = rec.data.parity_summary[k];
    if (typeof got !== 'number') fail(u, 9, `parity_summary.${k} is missing or not a number.`);
    else if (got !== actual[k]) fail(u, 9, `parity_summary.${k} is ${got}, expected ${actual[k]}.`);
  }
}
function validateUnit(rec, fail, warn) {
  const u = rec.id, data = rec.data;
  if (!isObj(data)) { fail(u, 1, 'Unit file is not a JSON object.'); return; }
  if (data.unit !== u) fail(u, 1, `Field unit is ${JSON.stringify(data.unit)}, expected ${u}.`);
  const types = { unit: 'string', title: 'string', sources_read: 'array', controls: 'array', rules: 'array', states: 'array', flows: 'array', cases: 'array', parity_summary: 'object', notes: 'string' };
  for (const [key, type] of Object.entries(types)) {
    const v = data[key];
    const ok = type === 'array' ? Array.isArray(v) : type === 'object' ? isObj(v) : typeof v === type;
    if (!ok) fail(u, 1, `Field ${key} is missing or has the wrong type.`);
  }
  if (Array.isArray(data.sources_read) && data.sources_read.some((s) => typeof s !== 'string')) fail(u, 1, 'sources_read contains a non-string entry.');
  checkControls(rec, fail, warn);
  checkRules(rec, fail, warn);
  checkStates(rec, fail, warn);
  checkFlows(rec, fail);
  checkCases(rec, fail);
  checkRefs(rec, fail);
}
function checkCoverage(units, required, map, fail, warn) {
  const sourcesOf = (rec) => (isObj(rec.data) ? arr(rec.data.sources_read).filter((s) => typeof s === 'string') : []);
  const all = units.flatMap(sourcesOf);
  for (const p of [...new Set(required)].sort()) if (!all.some((s) => s.includes(p))) fail('GLOBAL', 10, `Source file ${p} is absent from every sources_read entry.`);
  const warned = new Set();
  for (const [unit, files] of map.byUnit) for (const f of files.filter((x) => x.endsWith('.kt'))) {
    if (warned.has(f)) continue;
    const listed = [...map.byUnit].filter(([, list]) => list.includes(f)).map(([u2]) => u2);
    const found = units.filter((rec) => sourcesOf(rec).some((s) => s.includes(f))).map((rec) => rec.id);
    if (found.length && !found.some((u2) => listed.includes(u2))) {
      warned.add(f);
      warn(unit, 10, `Source file ${f} is listed for ${listed.join('/')} but appears in ${found.join('/')}.`);
    }
  }
}
function runChecks({ root, androidRoot }) {
  const rootDir = path.resolve(root);
  if (!fs.existsSync(rootDir) || !fs.statSync(rootDir).isDirectory()) throw new InputError(`Version root is missing: ${rootDir}`);
  const mapFile = path.join(rootDir, 'context/unit-map.md');
  if (!fs.existsSync(mapFile)) throw new InputError(`Unit map is missing: ${mapFile}`);
  const android = resolveAndroidRoot(rootDir, androidRoot);
  const required = discoverResources(android);
  const map = parseUnitMap(mapFile);
  if (!map.byUnit.size) throw new InputError(`Unit map has no unit row: ${mapFile}`);
  required.push(...map.kt);
  const failures = [], warnings = [];
  const fail = (unit, check, msg) => failures.push({ unit, check, msg });
  const warn = (unit, check, msg) => warnings.push({ unit, check, msg });
  const units = loadUnits(rootDir, fail);
  for (const rec of units) validateUnit(rec, fail, warn);
  checkCoverage(units, required, map, fail, warn);
  return { code: failures.length ? 1 : 0, failures, warnings, units };
}
function printReport({ code, failures, warnings, units }) {
  const header = ['Unit', 'Controls', 'Rules', 'States', 'Flows', 'Cases', 'FAIL', 'WARN'];
  const rows = [];
  const total = { controls: 0, rules: 0, states: 0, flows: 0, cases: 0, fail: 0, warn: 0 };
  const addRow = (name, c, f, w) => {
    rows.push([name, c.controls, c.rules, c.states, c.flows, c.cases, f, w]);
    for (const k of Object.keys(c)) total[k] += c[k];
    total.fail += f;
    total.warn += w;
  };
  for (const rec of units) {
    const d = isObj(rec.data) ? rec.data : {};
    addRow(rec.id, { controls: arr(d.controls).length, rules: arr(d.rules).length, states: arr(d.states).length, flows: arr(d.flows).length, cases: arr(d.cases).length }, failures.filter((f) => f.unit === rec.id).length, warnings.filter((w) => w.unit === rec.id).length);
  }
  addRow('GLOBAL', { controls: 0, rules: 0, states: 0, flows: 0, cases: 0 }, failures.filter((f) => f.unit === 'GLOBAL').length, warnings.filter((w) => w.unit === 'GLOBAL').length);
  rows.push(['TOTAL', total.controls, total.rules, total.states, total.flows, total.cases, total.fail, total.warn]);
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)));
  const line = (r) => r.map((v, i) => (i === 0 ? String(v).padEnd(widths[i]) : String(v).padStart(widths[i]))).join('  ');
  console.log(line(header));
  console.log(widths.map((w) => '-'.repeat(w)).join('  '));
  for (const row of rows) console.log(line(row));
  console.log('');
  for (const f of failures) console.log(`FAIL [check ${f.check}] ${f.unit}: ${f.msg}`);
  for (const w of warnings) console.log(`WARN [check ${w.check}] ${w.unit}: ${w.msg}`);
  console.log(`\nResult: ${code === 0 ? 'PASS' : 'FAIL'}.\nFailures: ${failures.length}.\nWarnings: ${warnings.length}.`);
}
function fixtureUnit(id, sources) {
  const kt = sources[sources.length - 1], screen = `C-${id}-001`, button = `C-${id}-002`, rule = `R-${id}-01`;
  return {
    unit: id, title: `Fixture ${id}`, sources_read: sources.slice(),
    controls: [
      { id: screen, type: 'screen', label: 'Main screen', android_id: '', parent: '', visible_when: 'always', enabled_when: 'always', action: '', navigates_to: '', source: `${kt}:1` },
      { id: button, type: 'button', label: 'Open', android_id: 'open', parent: screen, visible_when: 'always', enabled_when: 'always', action: 'open', navigates_to: '', source: `${kt}:2` },
    ],
    rules: [{ id: rule, statement: 'The button opens the dialog.', kind: 'interaction', source: `${kt}:3`, examples: [
      { given: 'The screen shows.', when: 'The user taps Open.', then: 'The dialog shows.', polarity: 'positive' },
      { given: 'The dialog shows.', when: 'The user taps Open.', then: 'One dialog shows.', polarity: 'boundary' },
    ] }],
    states: [{ object: 'screen', states: ['idle', 'stopped'], transitions: [{ from: 'idle', to: 'stopped', event: 'open', producer: 'ui', source: `${kt}:4` }] }],
    flows: [{ id: `F-${id}-01`, name: 'Open flow', steps: [
      { label: 'Start', type: 'start', next: 'Check', exception: false },
      { label: 'Check', type: 'decision', next: 'Yes -> Done | No -> End', exception: false },
      { label: 'Done', type: 'end', next: '', exception: false },
      { label: 'End', type: 'end', next: '', exception: false },
    ], exceptions: [] }],
    cases: [{ id: `TC-${id}-01`, title: 'Open the dialog', preconditions: [], steps: ['Tap Open.'], expected: ['The dialog shows.'], control_path: `${screen} > ${button}`, parity: 'implemented', source: `${kt}:5`, rules: [rule] }],
    parity_summary: { implemented: 1, partial: 0, missing: 0, android_only: 0 },
    notes: 'Fixture unit.',
  };
}
function writeFixture(work) {
  const root = path.join(work, 'fixture'), androidRoot = path.join(root, 'android');
  const rows = ['# Fixture unit map', '', '| Unit | Title | Android files |', '| --- | --- | --- |'];
  const resFor = { U01: 'mobile/src/main/res/layout/layout_fixture.xml', U02: 'mobile/src/main/res/menu/menu_fixture.xml', U03: 'mobile/src/main/res/xml/pref_fixture.xml' };
  for (const d of ['context', 'machine']) fs.mkdirSync(path.join(root, d), { recursive: true });
  for (const rel of Object.values(resFor)) {
    const file = path.join(androidRoot, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, '<fixture/>\n');
  }
  for (const id of UNIT_IDS) {
    const kt = `mobile/src/main/java/com/github/shadowsocks/${id}Screen.kt`;
    fs.mkdirSync(path.dirname(path.join(androidRoot, kt)), { recursive: true });
    fs.writeFileSync(path.join(androidRoot, kt), `// ${id}\n`);
    const files = resFor[id] ? [resFor[id], kt] : [kt];
    rows.push(`| ${id} | Fixture ${id} | ${files.join('; ')} |`);
    fs.writeFileSync(path.join(root, 'machine', `${id}.json`), `${JSON.stringify(fixtureUnit(id, files), null, 2)}\n`);
  }
  fs.writeFileSync(path.join(root, 'context/unit-map.md'), `${rows.join('\n')}\n`);
  return { root, androidRoot };
}
function selfTest() {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'check-specs-'));
  let ok = true;
  const log = (name, result, want, pattern) => {
    const hit = result.code === want && (!pattern || result.failures.some((f) => pattern.test(f.msg)));
    console.log(`self-test: ${name}: ${hit ? 'ok' : 'FAIL'} (exit ${result.code})`);
    if (!hit) ok = false;
  };
  const run = (opts) => {
    try { return runChecks(opts); }
    catch (e) { console.log(`self-test: error: ${e.message}`); return { code: 2, failures: [] }; }
  };
  try {
    const fixture = writeFixture(work);
    log('valid fixture', run(fixture), 0);
    const mutate = (name, unit, edit, pattern) => {
      const root = path.join(work, `mut-${unit}-${name.replace(/\W+/g, '-')}`);
      fs.cpSync(fixture.root, root, { recursive: true });
      const file = path.join(root, 'machine', `${unit}.json`);
      const data = JSON.parse(fs.readFileSync(file, 'utf8'));
      edit(data);
      fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
      log(name, run({ root, androidRoot: path.join(root, 'android') }), 1, pattern);
    };
    mutate('duplicate ID', 'U04', (d) => { d.controls[1].id = d.controls[0].id; }, /duplicate/i);
    mutate('dangling parent', 'U05', (d) => { d.controls[1].parent = 'C-U05-999'; }, /parent/i);
    mutate('unreferenced rule', 'U06', (d) => { delete d.cases[0].rules; d.rules[0].source = 'mobile/src/main/java/com/github/shadowsocks/Orphan.kt:1'; }, /unreferenced/i);
  } finally {
    if (ok) fs.rmSync(work, { recursive: true, force: true });
    else console.log(`self-test: kept ${work}`);
  }
  console.log(ok ? 'self-test: PASS' : 'self-test: FAIL');
  return ok ? 0 : 1;
}
function main() {
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); }
  catch (e) { console.error(`error: ${e.message}`); process.exitCode = 2; return; }
  if (opts.selfTest) { process.exitCode = selfTest(); return; }
  try {
    const result = runChecks(opts);
    printReport(result);
    process.exitCode = result.code;
  } catch (e) {
    if (e instanceof InputError) { console.error(`error: ${e.message}`); process.exitCode = 2; return; }
    throw e;
  }
}
main();
