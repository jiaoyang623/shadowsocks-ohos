/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AclDocument, emptyAcl, parseAcl, serializeAcl } from './Acl';
import { VPN_STATE_RUNNING, VPN_STATE_STARTING } from './Diagnostics';
import { ROUTE_CUSTOM_RULES } from './Routes';

/**
 * The rules the user writes, and the file the core is given for them.
 *
 * The presets ship as files. These do not: the user writes them in the app, and
 * what the core reads is composed from what they wrote. The composition is
 * small but it decides what the route means, so it lives here, where the host
 * specs can reach it, rather than inside the page that edits it.
 *
 * The editor offers the same three templates as shadowsocks-android: Generic,
 * Domain, and URL. The helpers below validate one rule, pick the template that
 * matches a stored rule, build the list rows, and keep the undo bin.
 */

/** The file holding what the user wrote, under the app's files directory. */
export const USER_RULES_FILE: string = 'custom-rules-user.acl';

/** The kinds of rule the editor and the list use, as shadowsocks-android does. */
export const RULE_KIND_DOMAIN: string = 'domain';
export const RULE_KIND_SUBNET: string = 'subnet';
export const RULE_KIND_URL: string = 'url';
/** The Generic template: a subnet or a regular expression. */
export const RULE_KIND_GENERIC: string = 'generic';

/** The template selector order: Generic, Domain, URL. */
export const TEMPLATE_ORDER: string[] = [RULE_KIND_GENERIC, RULE_KIND_DOMAIN, RULE_KIND_URL];

/** A regular-expression syntax error. */
export const RULE_ERROR_PATTERN: string = 'pattern';
/** A domain form error. */
export const RULE_ERROR_DOMAIN: string = 'domain';
/** A URL form error. */
export const RULE_ERROR_URL: string = 'url';
/** A cleartext HTTP warning. */
export const RULE_WARNING_CLEARTEXT: string = 'cleartext';

/** One rule as the list shows it, with the editor template that matches it. */
export interface RuleRow {
  value: string;
  kind: string;
}

/** The outcome of validating one rule for one template. */
export interface RuleCheck {
  valid: boolean;
  error: string;
  warning: string;
  detail: string;
}

function userRulesPath(context: common.Context): string {
  return `${context.filesDir}/${USER_RULES_FILE}`;
}

/** What the user wrote, or '' when they have written nothing yet. */
export function readUserRules(context: common.Context): string {
  try {
    return fs.readTextSync(userRulesPath(context));
  } catch (e) {
    return '';
  }
}

/**
 * Keeps what the user wrote.
 *
 * The write goes to a temporary file in the same directory, which is renamed
 * over the real file once it is complete. The VPN extension reads this file at
 * every start, in another process, while the page may be saving. A rename is
 * atomic, so the reader sees the old rules or the new rules and never a
 * truncated file. A crash during the write leaves the old file in place; the
 * temporary one is overwritten by the next save.
 *
 * An absent file and an empty file both mean "no rules". `composeCustomRules`
 * turns either into `[bypass_all]` with no lists, which the core reads as
 * "proxy nothing", not "proxy everything": on this route the listed rules are
 * the destinations that go through the proxy.
 */
export function writeUserRules(context: common.Context, text: string): void {
  const path = userRulesPath(context);
  const tmp = `${path}.tmp`;
  const file = fs.openSync(tmp,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  fs.renameSync(tmp, path);
}

/* ---- address and URL forms ---- */

/** True for a decimal IPv4 address. */
function isIpv4(value: string): boolean {
  const parts = value.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) {
      return false;
    }
    if (Number(part) > 255) {
      return false;
    }
  }
  return true;
}

/** True when the last group of a colon-separated list is an IPv4 address. */
function hasIpv4Tail(groups: string[]): boolean {
  if (groups.length === 0) {
    return false;
  }
  return groups[groups.length - 1].indexOf('.') >= 0;
}

/** True when every group is a hex group, with an IPv4 address allowed last. */
function validGroups(groups: string[]): boolean {
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    const last = i === groups.length - 1;
    if (last && group.indexOf('.') >= 0) {
      if (!isIpv4(group)) {
        return false;
      }
    } else if (!/^[0-9A-Fa-f]{1,4}$/.test(group)) {
      return false;
    }
  }
  return true;
}

/**
 * The number of 16-bit groups a colon-separated list covers. An IPv4 tail
 * stands for two groups, so it adds one to the list length.
 */
function groupSpan(groups: string[]): number {
  if (groups.length === 0) {
    return 0;
  }
  return hasIpv4Tail(groups) ? groups.length + 1 : groups.length;
}

/** True for a full IPv6 address, including the compressed and mapped forms. */
function isIpv6(value: string): boolean {
  if (value.indexOf(':') < 0) {
    return false;
  }
  const halves = value.split('::');
  if (halves.length > 2) {
    return false;
  }
  const head = halves[0].length === 0 ? [] : halves[0].split(':');
  const tail = halves.length === 2 && halves[1].length > 0 ? halves[1].split(':') : [];
  if (!validGroups(head) || !validGroups(tail)) {
    return false;
  }
  if (halves.length === 2 && hasIpv4Tail(head)) {
    // An IPv4 tail belongs at the end of the whole address.
    return false;
  }
  const span = groupSpan(head) + groupSpan(tail);
  if (halves.length === 2) {
    // The `::` stands for at least one group.
    return span < 8;
  }
  return span === 8;
}

/**
 * True for an IPv4 or IPv6 address or subnet. The prefix is optional and its
 * range follows the address family: 0 to 32 for IPv4, 0 to 128 for IPv6.
 */
export function isSubnet(value: string): boolean {
  if (value.length === 0) {
    return false;
  }
  const parts = value.split('/');
  if (parts.length > 2) {
    return false;
  }
  const address = parts[0];
  const ipv6 = address.indexOf(':') >= 0;
  if (ipv6 ? !isIpv6(address) : !isIpv4(address)) {
    return false;
  }
  if (parts.length === 1) {
    return true;
  }
  const prefix = parts[1];
  if (!/^\d+$/.test(prefix)) {
    return false;
  }
  return Number(prefix) <= (ipv6 ? 128 : 32);
}

/** True for an `http` or `https` URL with a host. */
export function isUrlRule(value: string): boolean {
  if (/\s/.test(value)) {
    return false;
  }
  const match = /^https?:\/\/([^/?#]+)/i.exec(value);
  if (match === null) {
    return false;
  }
  return match[1].length > 0;
}

/* ---- Punycode, RFC 3492 ---- */

const PUNYCODE_BASE: number = 36;
const PUNYCODE_TMIN: number = 1;
const PUNYCODE_TMAX: number = 26;
const PUNYCODE_SKEW: number = 38;
const PUNYCODE_DAMP: number = 700;
const PUNYCODE_INITIAL_BIAS: number = 72;
const PUNYCODE_INITIAL_N: number = 128;

/** The code points of a string, with surrogate pairs joined. */
function codePointsOf(text: string): number[] {
  const points: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const high = text.charCodeAt(i);
    if (high >= 0xd800 && high <= 0xdbff && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        points.push((high - 0xd800) * 0x400 + (low - 0xdc00) + 0x10000);
        i++;
        continue;
      }
    }
    points.push(high);
  }
  return points;
}

/** The digit for one Punycode value: `a` to `z`, then `0` to `9`. */
function punycodeDigit(value: number): string {
  return String.fromCharCode(value < 26 ? value + 97 : value + 22);
}

/** The value of one Punycode digit, or -1 when the character is not one. */
function punycodeValue(code: number): number {
  if (code >= 48 && code <= 57) {
    return code - 22;
  }
  if (code >= 65 && code <= 90) {
    return code - 65;
  }
  if (code >= 97 && code <= 122) {
    return code - 97;
  }
  return -1;
}

/** The bias adaptation of RFC 3492 section 6.1. */
function punycodeAdapt(delta: number, points: number, first: boolean): number {
  let value = first ? Math.floor(delta / PUNYCODE_DAMP) : Math.floor(delta / 2);
  value += Math.floor(value / points);
  let k = 0;
  while (value > Math.floor(((PUNYCODE_BASE - PUNYCODE_TMIN) * PUNYCODE_TMAX) / 2)) {
    value = Math.floor(value / (PUNYCODE_BASE - PUNYCODE_TMIN));
    k += PUNYCODE_BASE;
  }
  return k + Math.floor(((PUNYCODE_BASE - PUNYCODE_TMIN + 1) * value) / (value + PUNYCODE_SKEW));
}

/** The threshold at one position of the variable-length integer. */
function punycodeThreshold(k: number, bias: number): number {
  if (k <= bias) {
    return PUNYCODE_TMIN;
  }
  if (k >= bias + PUNYCODE_TMAX) {
    return PUNYCODE_TMAX;
  }
  return k - bias;
}

/** Encodes one label with Punycode, without the `xn--` prefix. */
function punycodeEncode(text: string): string {
  const points = codePointsOf(text);
  let output = '';
  let handled = 0;
  for (const point of points) {
    if (point < 0x80) {
      output += String.fromCharCode(point);
      handled++;
    }
  }
  const basic = handled;
  if (basic > 0) {
    output += '-';
  }
  let n = PUNYCODE_INITIAL_N;
  let delta = 0;
  let bias = PUNYCODE_INITIAL_BIAS;
  while (handled < points.length) {
    let next = Number.MAX_SAFE_INTEGER;
    for (const point of points) {
      if (point >= n && point < next) {
        next = point;
      }
    }
    delta += (next - n) * (handled + 1);
    n = next;
    for (const point of points) {
      if (point < n) {
        delta++;
      }
      if (point === n) {
        let q = delta;
        for (let k = PUNYCODE_BASE; ; k += PUNYCODE_BASE) {
          const t = punycodeThreshold(k, bias);
          if (q < t) {
            break;
          }
          output += punycodeDigit(t + (q - t) % (PUNYCODE_BASE - t));
          q = Math.floor((q - t) / (PUNYCODE_BASE - t));
        }
        output += punycodeDigit(q);
        bias = punycodeAdapt(delta, handled + 1, handled === basic);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return output;
}

/** Decodes one Punycode label, or returns null when the text is not valid. */
function punycodeDecode(text: string): string | null {
  const output: number[] = [];
  const delimiter = text.lastIndexOf('-');
  let index = 0;
  if (delimiter >= 0) {
    for (let i = 0; i < delimiter; i++) {
      const code = text.charCodeAt(i);
      if (code >= 0x80) {
        return null;
      }
      output.push(code);
    }
    index = delimiter + 1;
  }
  let n = PUNYCODE_INITIAL_N;
  let i = 0;
  let bias = PUNYCODE_INITIAL_BIAS;
  while (index < text.length) {
    const previous = i;
    let weight = 1;
    for (let k = PUNYCODE_BASE; ; k += PUNYCODE_BASE) {
      if (index >= text.length) {
        return null;
      }
      const digit = punycodeValue(text.charCodeAt(index));
      index++;
      if (digit < 0) {
        return null;
      }
      i += digit * weight;
      if (i > 0x10ffff) {
        return null;
      }
      const t = punycodeThreshold(k, bias);
      if (digit < t) {
        break;
      }
      weight *= PUNYCODE_BASE - t;
      if (weight > 0x10ffff) {
        return null;
      }
    }
    const points = output.length + 1;
    bias = punycodeAdapt(i - previous, points, previous === 0);
    n += Math.floor(i / points);
    if (n > 0x10ffff) {
      return null;
    }
    i %= points;
    output.splice(i, 0, n);
    i++;
  }
  let result = '';
  for (const point of output) {
    if (point > 0xffff) {
      const value = point - 0x10000;
      result += String.fromCharCode(0xd800 + (value >> 10), 0xdc00 + (value & 0x3ff));
    } else {
      result += String.fromCharCode(point);
    }
  }
  return result;
}

/* ---- domain rules ---- */

/** Escapes every regular-expression metacharacter in one label. */
function escapeRegExp(text: string): string {
  const special = '\\^$.*+?()[]{}|';
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const character = text.charAt(i);
    if (special.indexOf(character) >= 0) {
      out += '\\';
    }
    out += character;
  }
  return out;
}

/**
 * Converts a domain to its ASCII form, or returns null when it is not a domain.
 * An empty text returns ''.
 *
 * An ASCII label holds letters, digits, and inner hyphens. A Unicode label is
 * encoded with Punycode and gets the `xn--` prefix. A label is at most 63
 * characters, and a name is at most 253.
 */
export function toAsciiDomain(text: string): string | null {
  if (text.length === 0) {
    return '';
  }
  const labels = text.split('.');
  const out: string[] = [];
  for (const label of labels) {
    if (label.length === 0) {
      return null;
    }
    const ascii = toAsciiLabel(label);
    if (ascii === null || ascii.length > 63) {
      return null;
    }
    out.push(ascii);
  }
  const name = out.join('.');
  if (name.length > 253) {
    return null;
  }
  return name;
}

/** Converts one label to ASCII, or returns null when it is not a label. */
function toAsciiLabel(label: string): string | null {
  let ascii = true;
  for (let i = 0; i < label.length; i++) {
    if (label.charCodeAt(i) >= 0x80) {
      ascii = false;
      break;
    }
  }
  if (ascii) {
    if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label)) {
      return null;
    }
    return label;
  }
  return `xn--${punycodeEncode(label.toLowerCase())}`;
}

/** Converts an ASCII domain to its Unicode form. A label that fails is kept. */
export function toUnicodeDomain(text: string): string {
  const labels = text.split('.');
  const out: string[] = [];
  for (const label of labels) {
    if (label.length > 4 && label.slice(0, 4).toLowerCase() === 'xn--') {
      const decoded = punycodeDecode(label.slice(4));
      out.push(decoded !== null ? decoded : label);
    } else {
      out.push(label);
    }
  }
  return out.join('.');
}

/**
 * The anchored pattern that stores a domain rule, for example
 * `(?:^|\.)example\.com$`.
 *
 * The trailing `$` is required. Without it the rule also matches
 * `example.com.evil.com` and `example.com.cn`.
 */
export function domainRule(text: string): string {
  const ascii = toAsciiDomain(text);
  const name = ascii !== null ? ascii : text;
  const labels = name.split('.');
  const escaped: string[] = [];
  for (const label of labels) {
    escaped.push(escapeRegExp(label));
  }
  return `(?:^|\\.)${escaped.join('\\.')}$`;
}

/** Reads the domain name from an anchored pattern, or returns null. */
export function domainFromRule(value: string): string | null {
  if (!value.endsWith('$')) {
    return null;
  }
  const prefixes: string[] = ['(?:^|\\.)', '(^|\\.)', '^(.*\\.)?'];
  for (const prefix of prefixes) {
    if (value.startsWith(prefix)) {
      const inner = value.slice(prefix.length, value.length - 1);
      return toUnicodeDomain(inner.split('\\.').join('.'));
    }
  }
  return null;
}

/* ---- validation and storage forms ---- */

/** A validation result with nothing to report. */
function validRule(): RuleCheck {
  return { valid: true, error: '', warning: '', detail: '' };
}

/**
 * Validates one rule for one template.
 *
 * A Generic rule is a subnet or any text that compiles as a regular expression.
 * A Domain rule is empty or a domain that `toAsciiDomain` accepts. A URL rule
 * is an `http` or `https` URL with a host. An `http` URL also carries the
 * cleartext warning.
 */
export function checkRule(template: string, text: string): RuleCheck {
  if (template === RULE_KIND_DOMAIN) {
    if (toAsciiDomain(text) !== null) {
      return validRule();
    }
    return { valid: false, error: RULE_ERROR_DOMAIN, warning: '', detail: '' };
  }
  if (template === RULE_KIND_URL) {
    if (!isUrlRule(text)) {
      return { valid: false, error: RULE_ERROR_URL, warning: '', detail: '' };
    }
    const warning = text.toLowerCase().startsWith('http://') ? RULE_WARNING_CLEARTEXT : '';
    return { valid: true, error: '', warning: warning, detail: '' };
  }
  if (isSubnet(text)) {
    return validRule();
  }
  try {
    new RegExp(text);
    return validRule();
  } catch (e) {
    const error = e as Error;
    return { valid: false, error: RULE_ERROR_PATTERN, warning: '', detail: error.message ?? String(e) };
  }
}

/** The text a rule takes in the user file for one template. */
export function storedRule(template: string, text: string): string {
  if (template === RULE_KIND_DOMAIN) {
    return domainRule(text);
  }
  return text;
}

/** The template that matches a stored rule. */
export function ruleTemplateFor(value: string): string {
  if (isUrlRule(value)) {
    return RULE_KIND_URL;
  }
  if (domainFromRule(value) !== null) {
    return RULE_KIND_DOMAIN;
  }
  return RULE_KIND_GENERIC;
}

/** The text the editor shows for a stored rule. */
export function ruleEditorText(value: string): string {
  if (ruleTemplateFor(value) === RULE_KIND_DOMAIN) {
    const domain = domainFromRule(value);
    return domain !== null ? domain : value;
  }
  return value;
}

/**
 * True when the editor must show the Remove button. A new rule and an empty
 * rule hide it.
 */
export function showRemove(value: string): boolean {
  return value.length > 0;
}

/* ---- the list rows ---- */

/**
 * Builds the list rows from the composed text. Subnets come first, then
 * hostnames, then URLs. The file order holds inside each group, and a duplicate
 * value becomes one row.
 *
 * Bypass entries stay in the file but do not become rows, as on Android.
 */
export function ruleRows(text: string): RuleRow[] {
  const doc = parseAcl(text);
  const rows: RuleRow[] = [];
  const seen: string[] = [];
  const add = (value: string, kind: string): void => {
    if (seen.indexOf(value) >= 0) {
      return;
    }
    seen.push(value);
    rows.push({ value: value, kind: kind });
  };
  for (const entry of doc.proxyEntries) {
    if (isSubnet(entry)) {
      add(entry, RULE_KIND_SUBNET);
    }
  }
  for (const entry of doc.proxyEntries) {
    if (!isSubnet(entry)) {
      add(entry, ruleTemplateFor(entry));
    }
  }
  for (const url of doc.urls) {
    add(url, RULE_KIND_URL);
  }
  return rows;
}

/* ---- changes to the user file ---- */

/**
 * The rules file to hand the core: what the user wrote, with the default forced
 * to bypassing the proxy and the exceptions they listed going through it. A
 * list of "what should be proxied" is the only thing this route can sensibly
 * mean, so a file that says otherwise is turned round rather than obeyed.
 *
 * shadowsocks-android does the same. It also drops the subnets of a file whose
 * default it had to turn round, and this composition drops the subnet entries
 * of the bypass list for the same reason. Bypass hostnames stay in the file.
 *
 * An empty text composes to `[bypass_all]` with no lists. The core reads that
 * as "proxy nothing", so an absent or empty user file means "no user rules".
 * It does not mean "proxy everything": on this route the listed rules are the
 * destinations that go through the proxy.
 */
export function composeCustomRules(userText: string): string {
  const doc = parseAcl(userText, true);
  const defaultedToProxy = !doc.bypass;
  doc.bypass = true;
  if (defaultedToProxy) {
    doc.bypassEntries = doc.bypassEntries.filter((entry: string) => !isSubnet(entry));
  }
  return serializeAcl(doc);
}

/**
 * Adds one rule to what the user wrote and returns the new text. A URL is an
 * import rather than an entry, which is the one kind of rule that names another
 * list instead of a destination.
 *
 * An invalid rule returns the input unchanged. An empty Generic rule is stored
 * as an empty line.
 */
export function addRule(userText: string, kind: string, value: string): string {
  if (!checkRule(kind, value).valid) {
    return userText;
  }
  const doc = parseAcl(userText, true);
  if (kind === RULE_KIND_URL) {
    if (doc.urls.indexOf(value) < 0) {
      doc.urls.push(value);
    }
    return serializeAcl(doc);
  }
  const rule = storedRule(kind, value);
  if (doc.proxyEntries.indexOf(rule) < 0) {
    doc.proxyEntries.push(rule);
  }
  return serializeAcl(doc);
}

/** Removes one rule, from whichever list holds it. Returns the new text. */
export function removeRule(userText: string, value: string): string {
  return removeRules(userText, [value]);
}

/**
 * Removes a set of rules in one write. The editor deletes a whole selection at
 * once, and removing them one at a time would rewrite the file once per rule
 * and leave the page with a stale row for every step.
 */
export function removeRules(userText: string, values: string[]): string {
  const doc = parseAcl(userText);
  const gone = values.map((value: string) => value.trim());
  const keep = (entry: string): boolean => gone.indexOf(entry) < 0;
  doc.bypassEntries = doc.bypassEntries.filter(keep);
  doc.proxyEntries = doc.proxyEntries.filter(keep);
  doc.urls = doc.urls.filter(keep);
  return serializeAcl(doc);
}

/**
 * Replaces one rule with another. The editor calls this for an edit of an
 * existing rule, and passes an empty old value for a new rule.
 */
export function setRule(userText: string, oldValue: string, template: string, text: string): string {
  const without = oldValue.length > 0 ? removeRule(userText, oldValue) : userText;
  return addRule(without, template, text);
}

/**
 * Adds the entries of another ACL, which is what importing from the clipboard
 * does: a list copied out of another client, or the project's own gfwlist.
 *
 * Only the proxy entries and the import URLs come across. A bypass entry
 * describes the route the list came from, not the user's own rules. A list
 * whose own default is proxy loses its subnet entries, as on Android, because
 * the meaning of such a subnet is tied to the file it came from.
 */
export function addRulesFromText(userText: string, aclText: string): string {
  const incoming = parseAcl(aclText, true);
  const doc = parseAcl(userText, true);
  const entries: string[] = incoming.bypass
    ? incoming.proxyEntries
    : incoming.proxyEntries.filter((entry: string) => !isSubnet(entry));
  for (const entry of entries) {
    if (entry.length === 0) {
      continue;
    }
    if (doc.proxyEntries.indexOf(entry) < 0) {
      doc.proxyEntries.push(entry);
    }
  }
  for (const url of incoming.urls) {
    if (doc.urls.indexOf(url) < 0) {
      doc.urls.push(url);
    }
  }
  return serializeAcl(doc);
}

/* ---- the undo bin ---- */

/** Puts the newest removal batch first, which is the order the bin holds. */
export function joinRemovals(existing: string[], added: string[]): string[] {
  return added.concat(existing);
}

/**
 * Adds removed rules back in list order. A URL goes back to the import list.
 * Every other value goes back as a Generic rule, because its stored form is
 * already the text the list shows.
 */
export function restoreRules(userText: string, removed: string[]): string {
  let text = userText;
  for (const value of removed) {
    const kind = isUrlRule(value) ? RULE_KIND_URL : RULE_KIND_GENERIC;
    text = addRule(text, kind, value);
  }
  return text;
}

/* ---- selection, copy, and the swipe gate ---- */

/** The ACL text for a selection: a bypass default with the values listed. */
export function aclTextForRules(values: string[]): string {
  const doc: AclDocument = emptyAcl();
  doc.bypass = true;
  for (const value of values) {
    if (isUrlRule(value)) {
      doc.urls.push(value);
    } else {
      doc.proxyEntries.push(value);
    }
  }
  return serializeAcl(doc);
}

/** Adds or removes one value from the selection and returns a new array. */
export function toggleSelected(selected: string[], value: string): string[] {
  const at = selected.indexOf(value);
  if (at < 0) {
    return selected.concat([value]);
  }
  const next = selected.slice();
  next.splice(at, 1);
  return next;
}

/**
 * True when the swipe gate is closed. The gate closes only on the custom-rules
 * route, and only while the service is starting or running. A failed state
 * leaves the gate open because no tunnel runs.
 */
export function swipeBlocked(route: string, state: string): boolean {
  if (route !== ROUTE_CUSTOM_RULES) {
    return false;
  }
  return state === VPN_STATE_STARTING || state === VPN_STATE_RUNNING;
}

/** True when a swipe may remove a row: nothing is selected and the gate is open. */
export function canSwipe(selectedCount: number, blocked: boolean): boolean {
  return selectedCount === 0 && !blocked;
}
