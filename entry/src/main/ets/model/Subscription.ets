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

import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { JsonStore } from './JsonStore';
import {
  DEFAULT_REMOTE_DNS, STATUS_ACTIVE, STATUS_OBSOLETE, STATUS_USER_CONFIGURED,
  newProfileId, nextUserOrder, Profile,
} from './Profile';
import { addressKey } from './ProfilesFile';
import { isValidRoute } from './Routes';

const STORE_SUBSCRIPTIONS = 'subscriptions';

/** How deep a JSON body may nest before the parser stops. */
const MAX_BODY_DEPTH = 8;

/** A remote profile subscription (a URL serving ss:// links). */
export class Subscription {
  id: string = '';
  url: string = '';
  /** Last successful update, milliseconds since epoch; 0 = never. */
  updatedAt: number = 0;

  ensureId(): void {
    if (this.id.length === 0) {
      this.id = newProfileId();
    }
  }
}

/* ---- URL rules ---- */

/** The parts of a subscription URL that the sort order uses. */
export interface ParsedSubscriptionUrl {
  /** Lower-case, as `java.net.URL.getProtocol` reports it. */
  protocol: string;
  /** Host as written. Empty when the URL has no authority. */
  host: string;
  /** Port, or -1 when the URL has none. */
  port: number;
  /** Path plus query, without the fragment. Empty when absent. */
  file: string;
}

export type SubscriptionUrlError = '' | 'no_protocol' | 'unknown_protocol';

/** The result of a URL check. */
export interface SubscriptionUrlCheck {
  valid: boolean;
  /** True when the scheme is `http`. */
  cleartext: boolean;
  /** Lower-case scheme, or '' when the text has no scheme. */
  scheme: string;
  error: SubscriptionUrlError;
}

/** The lower-case scheme of a URL, or '' when the text has no scheme. */
function schemeOf(text: string): string {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(text);
  return match === null ? '' : match[1].toLowerCase();
}

/** True when every character is a decimal digit. */
function isNumericText(text: string): boolean {
  return /^[0-9]+$/.test(text);
}

/**
 * Splits a subscription URL into the parts the sort order uses. The rules
 * follow `java.net.URL` on the Android side: the scheme is lower-case, the
 * host keeps its case, and the file part carries the query.
 *
 * Returns null when the text has no scheme.
 */
export function parseSubscriptionUrl(text: string): ParsedSubscriptionUrl | null {
  const trimmed = text.trim();
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(trimmed);
  if (match === null) {
    return null;
  }
  const protocol = match[1].toLowerCase();
  const rest = trimmed.substring(match[0].length);
  let host = '';
  let port = -1;
  let file = '';
  if (rest.startsWith('//')) {
    const after = rest.substring(2);
    let end = after.length;
    for (let i = 0; i < after.length; i++) {
      const c = after.charAt(i);
      if (c === '/' || c === '?' || c === '#') {
        end = i;
        break;
      }
    }
    const authority = after.substring(0, end);
    let tail = after.substring(end);
    const hash = tail.indexOf('#');
    if (hash >= 0) {
      tail = tail.substring(0, hash);
    }
    file = tail;
    let hostPort = authority;
    const at = hostPort.lastIndexOf('@');
    if (at >= 0) {
      hostPort = hostPort.substring(at + 1);
    }
    if (hostPort.startsWith('[')) {
      const close = hostPort.indexOf(']');
      if (close >= 0) {
        host = hostPort.substring(1, close);
        const afterHost = hostPort.substring(close + 1);
        if (afterHost.startsWith(':')) {
          const portText = afterHost.substring(1);
          if (isNumericText(portText)) {
            port = Number.parseInt(portText, 10);
          }
        }
      } else {
        host = hostPort;
      }
    } else {
      const colon = hostPort.lastIndexOf(':');
      if (colon >= 0) {
        const portText = hostPort.substring(colon + 1);
        if (isNumericText(portText)) {
          port = Number.parseInt(portText, 10);
          host = hostPort.substring(0, colon);
        } else {
          host = hostPort;
        }
      } else {
        host = hostPort;
      }
    }
  } else {
    file = rest;
    const hash = file.indexOf('#');
    if (hash >= 0) {
      file = file.substring(0, hash);
    }
  }
  return { protocol: protocol, host: host, port: port, file: file };
}

/**
 * Checks a subscription URL. `http`, `https`, `ftp` and `file` pass without a
 * handler query. Any other scheme asks `canOpen`. A false answer or a throw
 * reports an unknown protocol.
 *
 * The text is trimmed first, as `java.net.URL` does.
 */
export function validateSubscriptionUrl(
  text: string, canOpen: (link: string) => boolean): SubscriptionUrlCheck {
  const trimmed = text.trim();
  const scheme = schemeOf(trimmed);
  if (parseSubscriptionUrl(trimmed) === null) {
    return { valid: false, cleartext: false, scheme: scheme, error: 'no_protocol' };
  }
  if (scheme === 'http') {
    return { valid: true, cleartext: true, scheme: scheme, error: '' };
  }
  if (scheme === 'https' || scheme === 'ftp' || scheme === 'file') {
    return { valid: true, cleartext: false, scheme: scheme, error: '' };
  }
  let open = false;
  try {
    open = canOpen(trimmed);
  } catch (e) {
    open = false;
  }
  if (!open) {
    return { valid: false, cleartext: false, scheme: scheme, error: 'unknown_protocol' };
  }
  return { valid: true, cleartext: false, scheme: scheme, error: '' };
}

/** Compares two strings by UTF-16 code unit, as Java's `String.compareTo`. */
function compareText(first: string, second: string): number {
  if (first < second) {
    return -1;
  }
  if (first > second) {
    return 1;
  }
  return 0;
}

/**
 * Orders two subscription URLs by host, then port, then file, then protocol.
 * This is `URLSorter` on the Android side.
 *
 * An unparseable URL compares by its raw text.
 */
export function compareSubscriptionUrls(first: string, second: string): number {
  const left = parseSubscriptionUrl(first);
  const right = parseSubscriptionUrl(second);
  if (left === null || right === null) {
    return compareText(first, second);
  }
  let result = compareText(left.host, right.host);
  if (result !== 0) {
    return result;
  }
  if (left.port !== right.port) {
    return left.port < right.port ? -1 : 1;
  }
  result = compareText(left.file, right.file);
  if (result !== 0) {
    return result;
  }
  return compareText(left.protocol, right.protocol);
}

/** One subscription and its input position, for the stable sort. */
interface OrderedSubscription {
  subscription: Subscription;
  index: number;
}

/** Returns a new list, sorted by URL. Equal URLs keep their input order. */
export function sortSubscriptions(list: Subscription[]): Subscription[] {
  const ordered: OrderedSubscription[] = [];
  for (let i = 0; i < list.length; i++) {
    ordered.push({ subscription: list[i], index: i });
  }
  ordered.sort((a: OrderedSubscription, b: OrderedSubscription): number => {
    const compared = compareSubscriptionUrls(a.subscription.url, b.subscription.url);
    return compared !== 0 ? compared : a.index - b.index;
  });
  const result: Subscription[] = [];
  for (const item of ordered) {
    result.push(item.subscription);
  }
  return result;
}

/** The record with a comparator-equal URL, or null. */
export function findSubscriptionByUrl(list: Subscription[], url: string): Subscription | null {
  for (const subscription of list) {
    if (compareSubscriptionUrls(subscription.url, url) === 0) {
      return subscription;
    }
  }
  return null;
}

/* ---- Dialog result and list transforms ---- */

export type SubscriptionDialogButton = 'ok' | 'cancel' | 'remove';

/** What the edit dialog asks the page to do. */
export interface SubscriptionEditResult {
  /** The text of OK, or null for Remove. */
  edited: string | null;
  /** The stored URL under edit, or null for Add. */
  replacing: string | null;
}

/**
 * Turns one dialog answer into a list action. Cancel returns null. Remove of
 * an unsaved URL returns null, because there is nothing to remove.
 */
export function editResult(button: SubscriptionDialogButton, text: string,
  original: string): SubscriptionEditResult | null {
  if (button === 'cancel') {
    return null;
  }
  if (button === 'remove') {
    if (original.length === 0) {
      return null;
    }
    return { edited: null, replacing: original };
  }
  return { edited: text, replacing: original.length > 0 ? original : null };
}

export interface SubscriptionListChange {
  list: Subscription[];
  changed: boolean;
}

/**
 * Appends one URL to the list. An equal URL is not added again, and the list
 * comes back unchanged in that case.
 */
export function addSubscriptionUrl(list: Subscription[],
  subscription: Subscription): SubscriptionListChange {
  if (findSubscriptionByUrl(list, subscription.url) !== null) {
    return { list: list, changed: false };
  }
  const result = list.slice();
  result.push(subscription);
  return { list: sortSubscriptions(result), changed: true };
}

/**
 * Replaces the record with `oldUrl` by `subscription`. When the new URL equals
 * a record that stays in the list, the new record is not added.
 */
export function replaceSubscriptionUrl(list: Subscription[], oldUrl: string,
  subscription: Subscription): Subscription[] {
  const result: Subscription[] = [];
  for (const record of list) {
    if (compareSubscriptionUrls(record.url, oldUrl) !== 0) {
      result.push(record);
    }
  }
  let exists = false;
  for (const record of result) {
    if (compareSubscriptionUrls(record.url, subscription.url) === 0) {
      exists = true;
      break;
    }
  }
  if (!exists) {
    result.push(subscription);
  }
  return sortSubscriptions(result);
}

/**
 * Puts removed records back. A restored record wins over an equal record that
 * is already in the list.
 */
export function restoreSubscriptions(list: Subscription[],
  removed: Subscription[]): Subscription[] {
  const result: Subscription[] = [];
  for (const record of list) {
    let restore = false;
    for (const candidate of removed) {
      if (compareSubscriptionUrls(record.url, candidate.url) === 0) {
        restore = true;
        break;
      }
    }
    if (!restore) {
      result.push(record);
    }
  }
  for (const record of removed) {
    let index = -1;
    for (let i = 0; i < result.length; i++) {
      if (compareSubscriptionUrls(result[i].url, record.url) === 0) {
        index = i;
        break;
      }
    }
    if (index >= 0) {
      result[index] = record;
    } else {
      result.push(record);
    }
  }
  return sortSubscriptions(result);
}

/** Persists the subscription list as a JSON file via JsonStore. */
export class SubscriptionStore {
  /**
   * Rebuilds a Subscription from a parsed JSON object. JSON.parse yields
   * plain objects, so the class methods (`ensureId`) are absent until the
   * fields are copied onto a real instance. ProfileStore has a `fromJson` for
   * the same reason.
   */
  static fromJson(parsed: Subscription): Subscription {
    const subscription = new Subscription();
    subscription.id = parsed.id ?? '';
    subscription.url = parsed.url ?? '';
    subscription.updatedAt = parsed.updatedAt ?? 0;
    return subscription;
  }

  /**
   * Drops an unparseable URL, drops comparator-equal duplicates (the last
   * record wins), and sorts by URL. The host tests call this directly.
   */
  static normalize(records: Subscription[]): Subscription[] {
    const kept: Subscription[] = [];
    for (const record of records) {
      if (parseSubscriptionUrl(record.url) === null) {
        continue;
      }
      let replaced = false;
      for (let i = 0; i < kept.length; i++) {
        if (compareSubscriptionUrls(kept[i].url, record.url) === 0) {
          kept[i] = record;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        kept.push(record);
      }
    }
    return sortSubscriptions(kept);
  }

  /**
   * The list from one stored text. An empty text gives an empty list. A JSON
   * error gives null, so a caller can tell a corrupt file from an empty one.
   */
  static parseStored(raw: string): Subscription[] | null {
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Subscription[];
      const records = parsed.map((s) => SubscriptionStore.fromJson(s));
      return SubscriptionStore.normalize(records);
    } catch (e) {
      return null;
    }
  }

  static async getAll(context: common.Context): Promise<Subscription[]> {
    return (await SubscriptionStore.getAllOrNull(context)) ?? [];
  }

  /**
   * The stored list, or null when the file is present and cannot be read.
   * `getAll` returns an empty list for an absent file and for a corrupt file
   * alike. A caller that writes back what it read must tell the two apart, or
   * it replaces every stored URL with the empty list it read.
   */
  static async getAllOrNull(context: common.Context): Promise<Subscription[] | null> {
    const raw = await JsonStore.read(context, STORE_SUBSCRIPTIONS);
    if (raw.length === 0) {
      return JsonStore.exists(context, STORE_SUBSCRIPTIONS) ? null : [];
    }
    return SubscriptionStore.parseStored(raw);
  }

  static async saveAll(context: common.Context, subscriptions: Subscription[]): Promise<void> {
    await JsonStore.write(context, STORE_SUBSCRIPTIONS,
      JSON.stringify(sortSubscriptions(subscriptions)));
  }

  /**
   * Inserts one record. A store that cannot be read is left alone, because a
   * write built on the empty read would drop every stored URL.
   */
  static async upsert(context: common.Context, subscription: Subscription): Promise<void> {
    subscription.ensureId();
    const all = await SubscriptionStore.getAllOrNull(context);
    if (all === null) {
      return;
    }
    const index = all.findIndex((s) => s.id === subscription.id);
    if (index >= 0) {
      all[index] = subscription;
    } else {
      all.push(subscription);
    }
    await SubscriptionStore.saveAll(context, all);
  }

  /** Removes one record. An unreadable store is left alone. */
  static async remove(context: common.Context, id: string): Promise<void> {
    const all = await SubscriptionStore.getAllOrNull(context);
    if (all === null) {
      return;
    }
    await SubscriptionStore.saveAll(context, all.filter((s) => s.id !== id));
  }
}

/* ---- Body parsing ---- */

/** A JSON body that cannot be parsed. The page reports it as a parse error. */
export class SubscriptionParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SubscriptionParseError';
  }
}

/**
 * Parses a subscription response body into profiles. Two formats are
 * supported, matching what shadowsocks providers serve:
 *
 * - a base64 blob of newline-separated `ss://` URLs (the common case).
 * - a JSON document with a server entry anywhere inside it, such as a SIP008
 *   online config (`{"servers": [...]}`).
 *
 * A body that starts with `{` or `[` is JSON. A JSON syntax error throws
 * `SubscriptionParseError`. Other text that yields no `ss://` line returns an
 * empty list, so a bare `Not Found` page is not an error.
 *
 * When `feature` is not null, every new profile copies its feature settings
 * from it. The body or the default supplies every transport field.
 */
export function parseSubscriptionBody(body: string, subscriptionId: string,
  feature: Profile | null = null): Profile[] {
  const trimmed = body.trim();
  if (trimmed.length === 0) {
    return [];
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return parseJsonBody(trimmed, subscriptionId, feature);
  }
  let text = trimmed;
  if (trimmed.indexOf('ss://') < 0) {
    try {
      text = Profile.decodeBase64(trimmed);
    } catch (e) {
      return [];
    }
  }
  const decoded = text.trim();
  if (decoded.startsWith('{') || decoded.startsWith('[')) {
    return parseJsonBody(decoded, subscriptionId, feature);
  }
  const profiles: Profile[] = [];
  for (const line of decoded.split(/\r?\n/)) {
    const entry = line.trim();
    if (entry.length === 0) {
      continue;
    }
    const profile = Profile.parseUrl(entry);
    if (profile === null) {
      continue;
    }
    if (feature !== null) {
      profile.copyFeatureSettingsFrom(feature);
    }
    profile.subscriptionId = subscriptionId;
    profile.ensureId();
    profiles.push(profile);
  }
  return profiles;
}

/** Parses one JSON body, and throws when the text is not JSON. */
function parseJsonBody(text: string, subscriptionId: string,
  feature: Profile | null): Profile[] {
  let value: Object | null;
  try {
    value = JSON.parse(text) as Object;
  } catch (e) {
    const err = e as Error;
    const message = typeof err.message === 'string' ? err.message : text;
    throw new SubscriptionParseError(`Invalid subscription JSON: ${message}`);
  }
  return profilesInJson(value, subscriptionId, feature, 0);
}

/** Every server entry inside a parsed JSON value, however it is nested. */
function profilesInJson(value: Object | null | undefined, subscriptionId: string,
  feature: Profile | null, depth: number): Profile[] {
  const found: Profile[] = [];
  if (value === null || value === undefined || depth > MAX_BODY_DEPTH) {
    return found;
  }
  if (Array.isArray(value)) {
    for (const item of value as Object[]) {
      for (const profile of profilesInJson(item, subscriptionId, feature, depth + 1)) {
        found.push(profile);
      }
    }
    return found;
  }
  if (typeof value !== 'object') {
    return found;
  }
  const record = value as Record<string, Object>;
  const profile = profileFromBody(record, subscriptionId, feature);
  if (profile !== null) {
    found.push(profile);
    return found;
  }
  // not a server entry, so it is a container: SIP008 wraps its servers in
  // `servers`, other providers use `configs` or an unnamed array
  for (const key of Object.keys(record)) {
    for (const nested of profilesInJson(record[key], subscriptionId, feature, depth + 1)) {
      found.push(nested);
    }
  }
  return found;
}

/**
 * One profile from a JSON server entry, or null when the record lacks the
 * four fields that make it one or carries an unusable value.
 */
function profileFromBody(record: Record<string, Object>, subscriptionId: string,
  feature: Profile | null): Profile | null {
  const server = record['server'];
  const portValue = record['server_port'];
  const password = record['password'];
  const method = record['method'];
  if (typeof server !== 'string' || server.length === 0) {
    return null;
  }
  let remotePort = Number.NaN;
  if (typeof portValue === 'number') {
    remotePort = portValue;
  } else if (typeof portValue === 'string') {
    remotePort = Number.parseInt(portValue, 10);
  }
  if (Number.isNaN(remotePort) || !Number.isInteger(remotePort)
    || remotePort <= 0 || remotePort > 65535) {
    return null;
  }
  if (typeof password !== 'string' || password.length === 0) {
    return null;
  }
  if (typeof method !== 'string' || method.length === 0) {
    return null;
  }

  const profile = new Profile();
  profile.host = server;
  profile.remotePort = remotePort;
  profile.password = password;
  profile.method = method;
  if (feature !== null) {
    profile.copyFeatureSettingsFrom(feature);
  }

  const remarks = record['remarks'];
  profile.name = typeof remarks === 'string' && remarks.length > 0 ? remarks : server;

  const plugin = record['plugin'];
  if (typeof plugin === 'string' && plugin.length > 0) {
    profile.plugin = plugin;
    const opts = record['plugin_opts'];
    profile.pluginOpts = typeof opts === 'string' ? opts : '';
  }

  const route = record['route'];
  if (typeof route === 'string' && isValidRoute(route)) {
    profile.route = route;
  }

  const remoteDns = record['remote_dns'];
  profile.remoteDns = typeof remoteDns === 'string' && remoteDns.length > 0
    ? remoteDns : DEFAULT_REMOTE_DNS;

  const ipv6 = record['ipv6'];
  if (typeof ipv6 === 'boolean') {
    profile.ipv6 = ipv6;
  }
  const udpdns = record['udpdns'];
  if (typeof udpdns === 'boolean') {
    profile.udpdns = udpdns;
  }

  profile.subscriptionId = subscriptionId;
  profile.ensureId();
  return profile;
}

/* ---- Batch merge ---- */

/** The outcome of one merge over every subscription body. */
export interface SubscriptionMergeResult {
  profiles: Profile[];
  /** The current profile id, or '' when the merge deleted that profile. */
  currentId: string;
  /** How many stored duplicate records the merge dropped. */
  deleted: number;
}

/** The identity of a profile inside one merge. */
function profileKey(profile: Profile): string {
  return `${profile.name}\n${addressKey(profile)}`;
}

/**
 * Folds every freshly-fetched body into the stored list in one run, the way
 * shadowsocks-android's `createProfilesFromSubscription` does.
 *
 * A profile is the same profile when its name and its address match, which is
 * why Android warns that names matter: renaming a server in a subscription
 * makes a new profile here and leaves the old one behind as obsolete.
 *
 * The states are what make an update survivable. A profile this run lists
 * again keeps its id, its counters and its place in the list. One it no
 * longer lists becomes obsolete and stays visible, so a server that
 * disappears from a provider and comes back is not lost in between. What a
 * re-listed profile takes from the new copy is its transport: password,
 * method and plugin. It does not take its route or resolver, which are the
 * user's.
 *
 * A user-configured profile is left exactly as it is. A profile of another
 * subscription that this run does not list becomes obsolete.
 */
export function mergeSubscriptionRun(existing: Profile[], fresh: Profile[],
  currentId: string): SubscriptionMergeResult {
  const result: Profile[] = [];
  const byKey: Map<string, Profile> = new Map<string, Profile>();
  let selectedId = currentId;
  let deleted = 0;

  for (const stored of existing) {
    if (stored.subscriptionStatus === STATUS_USER_CONFIGURED) {
      result.push(stored);
      continue;
    }
    const key = profileKey(stored);
    if (byKey.get(key) !== undefined) {
      if (stored.id === selectedId) {
        selectedId = '';
      }
      deleted++;
      continue;
    }
    if (stored.subscriptionStatus === STATUS_ACTIVE) {
      stored.subscriptionStatus = STATUS_OBSOLETE;
    }
    result.push(stored);
    byKey.set(key, stored);
  }

  for (const incoming of fresh) {
    const key = profileKey(incoming);
    const matched = byKey.get(key);
    if (matched !== undefined && matched.subscriptionStatus === STATUS_ACTIVE) {
      // an already-active match is a duplicate inside the new list itself, and
      // the copy already kept is left alone
      continue;
    }
    if (matched !== undefined) {
      matched.copyTransportFrom(incoming);
      // keep the local entries for the other plugins and take the incoming
      // entry for the selected plugin. Fill the default when the URL has none.
      matched.seedPluginConfigs();
      matched.normalizePluginOptions();
      matched.subscriptionStatus = STATUS_ACTIVE;
      matched.subscriptionId = incoming.subscriptionId;
      continue;
    }
    incoming.subscriptionStatus = STATUS_ACTIVE;
    incoming.ensureId();
    incoming.userOrder = nextUserOrder(result);
    result.push(incoming);
    byKey.set(key, incoming);
  }

  return { profiles: result, currentId: selectedId, deleted: deleted };
}

/* ---- Body fetch ---- */

/**
 * Lets the refresh run track and cancel the requests it starts. The fetch
 * registers its request before the call and unregisters it in `finally`.
 */
export interface SubscriptionFetchControl {
  register(request: http.HttpRequest): void;
  unregister(request: http.HttpRequest): void;
  isCancelled(): boolean;
}

/**
 * Downloads a subscription body. Rejects on network errors, on a status code
 * outside 200 to 299, and when the control reports a cancel after the
 * response. The caller parses the text.
 */
export async function fetchSubscriptionBody(url: string,
  control?: SubscriptionFetchControl): Promise<string> {
  const request = http.createHttp();
  if (control !== undefined) {
    control.register(request);
  }
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 15000,
      readTimeout: 15000,
    });
    const code = response.responseCode;
    if (code < 200 || code >= 300) {
      throw new Error(`HTTP ${code}`);
    }
    if (control !== undefined && control.isCancelled()) {
      throw new Error('cancelled');
    }
    return response.result as string;
  } finally {
    if (control !== undefined) {
      control.unregister(request);
    }
    request.destroy();
  }
}
