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

import { joinNames, namesOf } from './PerApp';
import {
  DEFAULT_REMOTE_DNS, Profile, STATUS_OBSOLETE, copyFeatureSettings, nextUserOrder,
} from './Profile';

/**
 * One profile in the shape shadowsocks-android exports, which is also the
 * SIP008 server entry shape. The first four fields are the SIP008 minimum and
 * are always written; the rest are optional there, so an export meant for
 * another shadowsocks client writes only those four.
 */
export interface ProfileJson {
  server: string;
  server_port: number;
  password: string;
  method: string;
  plugin?: string;
  plugin_opts?: string;
  remarks?: string;
  route?: string;
  remote_dns?: string;
  ipv6?: boolean;
  metered?: boolean;
  udpdns?: boolean;
  proxy_apps?: ProxyAppsJson;
  udp_fallback?: UdpFallbackJson;
}

/**
 * Android's per-app settings block. `android_list` holds Android package names
 * as a JSON array, which is the shape Android writes and reads.
 */
export interface ProxyAppsJson {
  enabled: boolean;
  bypass?: boolean;
  android_list?: string[];
}

/** The nested profile Android writes for a UDP fallback. */
export interface UdpFallbackJson {
  server: string;
  server_port: number;
  password: string;
  method: string;
}

/** One parsed entry: the profile and, when the entry carries one, its fallback. */
interface ParsedEntry {
  profile: Profile;
  fallback: Profile | null;
}

/** The result of one import batch: the profiles and the first error message. */
export interface ImportBatch {
  profiles: Profile[];
  error: string;
}

/** How deep the importer walks before deciding a file is not a profile list. */
const MAX_DEPTH = 8;

/**
 * The key that decides whether two profiles describe the same server, the same
 * one shadowsocks-android uses.
 */
export function addressKey(profile: Profile): string {
  return `${profile.host}:${profile.remotePort}`;
}

/** A boolean field, or null when the value is absent or is not a boolean. */
function booleanField(record: Record<string, Object>, key: string): boolean | null {
  const value = record[key];
  if (typeof value === 'boolean') {
    return value;
  }
  return null;
}

/**
 * A bundle list from the `android_list` array. Items that are not strings are
 * ignored, and the result drops blank lines and duplicates.
 */
function bundleListFromItems(items: Object[]): string {
  const lines: string[] = [];
  for (const item of items) {
    if (typeof item === 'string') {
      lines.push(item);
    }
  }
  return joinNames(lines);
}

/**
 * One profile from a parsed JSON object, or null when it is not one.
 *
 * `feature` supplies the feature settings of the selected profile, which the
 * entry inherits. A JSON boolean overrides an inherited boolean. A
 * non-boolean value keeps the inherited value. `remote_dns`, the plugin and
 * the name are never inherited.
 *
 * A `fallback` entry reads only the plugin, the remarks and the route. The
 * caller reads the nested `udp_fallback` object.
 */
export function profileFromJson(record: Record<string, Object>,
  feature: Profile | null, fallback: boolean = false): Profile | null {
  const server = record['server'];
  const port = record['server_port'];
  const password = record['password'];
  const method = record['method'];

  if (typeof server !== 'string' || server.length === 0) {
    return null;
  }
  // providers write the port as a number and, less often, as a string
  const remotePort = typeof port === 'number' ? port : Number.parseInt(`${port}`, 10);
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
  copyFeatureSettings(feature, profile);
  profile.host = server;
  profile.remotePort = remotePort;
  profile.password = password;
  profile.method = method;

  const remarks = record['remarks'];
  profile.name = typeof remarks === 'string' && remarks.length > 0 ? remarks : server;

  const plugin = record['plugin'];
  if (typeof plugin === 'string' && plugin.length > 0) {
    profile.plugin = plugin;
    const opts = record['plugin_opts'];
    profile.pluginOpts = typeof opts === 'string' ? opts : '';
  }
  // A non-empty `plugin_opts` seeds the map. An empty one takes the default.
  profile.normalizePluginOptions();

  const route = record['route'];
  if (typeof route === 'string' && route.length > 0) {
    profile.route = route;
  }
  if (fallback) {
    return profile;
  }

  const remoteDns = record['remote_dns'];
  profile.remoteDns =
    typeof remoteDns === 'string' && remoteDns.length > 0 ? remoteDns : DEFAULT_REMOTE_DNS;

  const ipv6 = booleanField(record, 'ipv6');
  if (ipv6 !== null) {
    profile.ipv6 = ipv6;
  }
  const metered = booleanField(record, 'metered');
  if (metered !== null) {
    profile.metered = metered;
  }
  const udpdns = booleanField(record, 'udpdns');
  if (udpdns !== null) {
    profile.udpdns = udpdns;
  }

  const proxyApps = record['proxy_apps'];
  if (proxyApps !== null && proxyApps !== undefined && typeof proxyApps === 'object'
    && !Array.isArray(proxyApps)) {
    const block = proxyApps as Record<string, Object>;
    const enabled = booleanField(block, 'enabled');
    if (enabled !== null) {
      profile.proxyAppsEnabled = enabled;
    }
    // A disabled block ignores the bypass flag and the list. A stored list is
    // meaningful only while the mode is on.
    if (profile.proxyAppsEnabled) {
      const bypass = booleanField(block, 'bypass');
      if (bypass !== null) {
        profile.proxyAppsBypass = bypass;
      }
      const list = block['android_list'];
      if (Array.isArray(list)) {
        profile.proxyAppsList = bundleListFromItems(list as Object[]);
      } else {
        // `individual` is not an Android key. It is read as a legacy text
        // input so a file that carries it still yields a list.
        const legacy = block['individual'];
        if (typeof legacy === 'string') {
          profile.proxyAppsList = joinNames(namesOf(legacy));
        }
      }
    }
  }
  // `udp_fallback` is read by the entry parser, which links the two rows.
  return profile;
}

/**
 * One entry from a parsed JSON object. The name falls back to the server
 * address, because a row renders the name without a fallback.
 */
function entryFromJson(record: Record<string, Object>, feature: Profile | null): ParsedEntry | null {
  const profile = profileFromJson(record, feature, false);
  if (profile === null) {
    return null;
  }
  let fallback: Profile | null = null;
  const nested = record['udp_fallback'];
  if (nested !== null && nested !== undefined && typeof nested === 'object'
    && !Array.isArray(nested)) {
    fallback = profileFromJson(nested as Record<string, Object>, feature, true);
  }
  return { profile: profile, fallback: fallback };
}

/**
 * Every entry anywhere inside a parsed JSON value, however it is nested. A
 * recognized profile stops the search inside that object.
 */
function entriesInValue(value: Object | null | undefined, depth: number,
  feature: Profile | null): ParsedEntry[] {
  const found: ParsedEntry[] = [];
  if (value === null || value === undefined || depth > MAX_DEPTH) {
    return found;
  }
  if (Array.isArray(value)) {
    for (const item of value as Object[]) {
      for (const entry of entriesInValue(item, depth + 1, feature)) {
        found.push(entry);
      }
    }
    return found;
  }
  if (typeof value !== 'object') {
    return found;
  }
  const record = value as Record<string, Object>;
  const entry = entryFromJson(record, feature);
  if (entry !== null) {
    found.push(entry);
    return found;
  }
  // not a server entry itself, so it is a container: SIP008 wraps its servers
  // in `servers`, and other providers use `configs` or an unnamed array
  for (const key of Object.keys(record)) {
    for (const nested of entriesInValue(record[key], depth + 1, feature)) {
      found.push(nested);
    }
  }
  return found;
}

/**
 * Profiles from text that is a list of `ss://` URLs, one per whitespace
 * token. This is the URL-only parser the QR import uses: Android imports only
 * `ss://` URLs from a scan.
 */
export function parseProfileUrls(text: string): Profile[] {
  const profiles: Profile[] = [];
  for (const token of text.split(/\s+/)) {
    if (!token.startsWith('ss://')) {
      continue;
    }
    const profile = Profile.parseUrl(token);
    if (profile !== null) {
      profiles.push(profile);
    }
  }
  return profiles;
}

/** Entries from `ss://` URLs, with the feature settings applied. */
function entriesFromUrls(text: string, feature: Profile | null): ParsedEntry[] {
  const entries: ParsedEntry[] = [];
  for (const token of text.split(/\s+/)) {
    if (!token.startsWith('ss://')) {
      continue;
    }
    const profile = Profile.parseUrl(token, feature);
    if (profile !== null) {
      entries.push({ profile: profile, fallback: null });
    }
  }
  return entries;
}

/**
 * The main profiles and their fallbacks as rows. Every row takes an id, and a
 * main profile points at its fallback.
 */
function flattenEntries(entries: ParsedEntry[]): Profile[] {
  for (const entry of entries) {
    entry.profile.ensureId();
    if (entry.fallback !== null) {
      entry.fallback.ensureId();
    }
  }
  // A fallback that is also a top-level entry is one row, not two. Android
  // sees every created row and points the main profile at the standalone one.
  const standalone: Profile[] = [];
  for (const entry of entries) {
    if (entry.fallback === null) {
      standalone.push(entry.profile);
    }
  }
  const profiles: Profile[] = [];
  for (const entry of entries) {
    profiles.push(entry.profile);
    const fallback = entry.fallback;
    if (fallback === null) {
      continue;
    }
    const match = findFallbackMatch(standalone, fallback, entry.profile);
    if (match !== null) {
      entry.profile.udpFallbackId = match.id;
      continue;
    }
    entry.profile.udpFallbackId = fallback.id;
    profiles.push(fallback);
  }
  return profiles;
}

/**
 * The strict document parser.
 *
 * A document that starts with `{` or `[` is JSON, and a syntax error escapes
 * to the caller. Any other text is a list of `ss://` URLs, or a base64 blob of
 * them. An empty text gives an empty list.
 */
export function parseProfileDocument(text: string, feature: Profile | null): Profile[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return [];
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    const parsed = JSON.parse(trimmed) as Object;
    return flattenEntries(entriesInValue(parsed, 0, feature));
  }
  const entries = entriesFromUrls(trimmed, feature);
  if (entries.length > 0) {
    return flattenEntries(entries);
  }
  try {
    return flattenEntries(entriesFromUrls(Profile.decodeBase64(trimmed), feature));
  } catch (e) {
    return [];
  }
}

/**
 * Reads profiles from text, in any of the shapes a user or a provider can
 * produce: an exported file, a SIP008 document, a nested provider document,
 * a list of `ss://` URLs, or a base64 blob of them, which is how most
 * subscriptions are served.
 *
 * This is the lenient parser. A malformed JSON body does not throw from here:
 * the scan for `ss://` URLs still runs. The subscription and file paths use
 * the strict parser when they must report a syntax error.
 */
export function parseProfilesText(text: string, feature: Profile | null = null): Profile[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return [];
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const parsed = parseProfileDocument(trimmed, feature);
      if (parsed.length > 0) {
        return parsed;
      }
    } catch (e) {
      // not JSON after all: the scan below may still find URLs in it
    }
  }
  const direct = flattenEntries(entriesFromUrls(trimmed, feature));
  if (direct.length > 0) {
    return direct;
  }
  try {
    return flattenEntries(entriesFromUrls(Profile.decodeBase64(trimmed), feature));
  } catch (e) {
    return [];
  }
}

/** The message of an error, or the text of any other thrown value. */
function errorText(e: Object): string {
  if (e instanceof Error) {
    return e.message;
  }
  return String(e);
}

/**
 * Profiles from a batch of documents. A document that throws contributes its
 * message and no profile. The other documents still parse, and the first
 * message is kept.
 */
export function collectProfiles(texts: string[], feature: Profile | null): ImportBatch {
  const profiles: Profile[] = [];
  let error = '';
  for (const text of texts) {
    try {
      const parsed = parseProfileDocument(text, feature);
      for (const profile of parsed) {
        profiles.push(profile);
      }
    } catch (e) {
      if (error.length === 0) {
        error = errorText(e as Object);
      }
    }
  }
  return { profiles: profiles, error: error };
}

/** A stored profile with the same address as the imported one, or null. */
function findAddressMatch(existing: Profile[], profile: Profile): Profile | null {
  const key = addressKey(profile);
  for (const stored of existing) {
    if (addressKey(stored) === key) {
      return stored;
    }
  }
  return null;
}

/**
 * A stored profile that a parsed fallback can reuse: same host, port,
 * password and method, and no plugin. Android uses the same test.
 */
function findFallbackMatch(existing: Profile[], fallback: Profile,
  exclude: Profile | null = null): Profile | null {
  for (const stored of existing) {
    // The fallback itself is not a match, and neither is the profile that
    // names it: both can share the same address.
    if (stored === exclude || stored.udpFallbackId === fallback.id) {
      continue;
    }
    if (stored.host === fallback.host
      && stored.remotePort === fallback.remotePort
      && stored.password === fallback.password
      && stored.method === fallback.method
      && stored.plugin.length === 0) {
      return stored;
    }
  }
  return null;
}

/**
 * Folds an imported batch into the stored list, following shadowsocks-android's
 * importer: a replace drops what is there and keeps the identity and counters
 * of profiles with the same address, while an import appends. The address is
 * the same key Android uses, so the two clients agree on what "the same
 * profile" means.
 *
 * An imported fallback that names a stored profile reuses that row in import
 * mode. Both modes keep the main profile and its fallback as two rows, and the
 * main profile points at its fallback with `udpFallbackId`.
 *
 * A replace with no parsed profile changes nothing.
 */
export function applyImport(existing: Profile[], imported: Profile[], replace: boolean): Profile[] {
  if (replace && imported.length === 0) {
    return existing.slice();
  }

  // ids that imported profiles use as fallbacks
  const fallbackIds: string[] = [];
  for (const profile of imported) {
    if (profile.udpFallbackId.length > 0 && fallbackIds.indexOf(profile.udpFallbackId) < 0) {
      fallbackIds.push(profile.udpFallbackId);
    }
  }

  // an imported fallback that names a stored profile reuses that row
  const reusedIds = new Map<string, string>();
  const kept: Profile[] = [];
  for (const profile of imported) {
    if (!replace && fallbackIds.indexOf(profile.id) >= 0) {
      // The standalone fallback entry in the same batch is a row too, so the
      // batch is a candidate beside the stored list. Android sees every row
      // after the batch exists and reuses the same one.
      const match = findFallbackMatch(existing.concat(imported), profile, profile);
      if (match !== null) {
        reusedIds.set(profile.id, match.id);
        continue;
      }
    }
    kept.push(profile);
  }

  const result: Profile[] = replace ? [] : existing.slice();
  let order = replace ? 1 : nextUserOrder(result);
  const finalIds = new Map<string, string>();
  const keptProfiles: Profile[] = [];
  for (const profile of kept) {
    const parsedId = profile.id;
    // an imported profile belongs to no subscription, whatever it carried
    profile.subscriptionId = '';
    if (replace) {
      const previous = findAddressMatch(existing, profile);
      if (previous !== null) {
        // the same server, so what identifies it locally is kept: its id, the
        // name the user gave it, and the traffic it has carried
        profile.id = previous.id;
        profile.tx = previous.tx;
        profile.rx = previous.rx;
        profile.name = previous.name;
      }
    }
    profile.ensureId();
    profile.userOrder = order;
    order++;
    if (parsedId.length > 0) {
      finalIds.set(parsedId, profile.id);
    }
    keptProfiles.push(profile);
    result.push(profile);
  }

  // point every surviving main profile at its fallback's final id
  for (const profile of keptProfiles) {
    if (profile.udpFallbackId.length === 0) {
      continue;
    }
    const finalId = finalIds.get(profile.udpFallbackId);
    if (finalId !== undefined) {
      profile.udpFallbackId = finalId;
      continue;
    }
    const reused = reusedIds.get(profile.udpFallbackId);
    if (reused !== undefined) {
      profile.udpFallbackId = reused;
    }
  }
  return result;
}

/** The active profile with this id, or null. */
function findProfileById(profiles: Profile[], id: string): Profile | null {
  if (id.length === 0) {
    return null;
  }
  for (const profile of profiles) {
    if (profile.id === id) {
      return profile;
    }
  }
  return null;
}

/**
 * The stored list as an exported file: a JSON array, pretty-printed, in the
 * shape shadowsocks-android's `serializeToJson` writes. Obsolete profiles are
 * left out. `sip008` restricts it to the four fields that format defines, for
 * handing to another client.
 *
 * A null list gives null, which is the form a failed read takes.
 */
export function exportProfiles(profiles: Profile[] | null, sip008: boolean = false): string | null {
  if (profiles === null) {
    return null;
  }
  const active = profiles.filter((p) => p.subscriptionStatus !== STATUS_OBSOLETE);
  const entries: ProfileJson[] = [];
  for (const profile of active) {
    const entry: ProfileJson = {
      server: profile.host,
      server_port: profile.remotePort,
      password: profile.password,
      method: profile.method,
    };
    if (sip008) {
      entries.push(entry);
      continue;
    }
    if (profile.plugin.length > 0) {
      entry.plugin = profile.plugin;
      entry.plugin_opts = profile.pluginOpts;
    }
    entry.remarks = profile.name;
    entry.route = profile.route;
    entry.remote_dns = profile.remoteDns;
    entry.ipv6 = profile.ipv6;
    entry.metered = profile.metered;
    const proxyApps: ProxyAppsJson = { enabled: profile.proxyAppsEnabled };
    if (profile.proxyAppsEnabled) {
      proxyApps.bypass = profile.proxyAppsBypass;
      proxyApps.android_list = namesOf(profile.proxyAppsList);
    }
    entry.proxy_apps = proxyApps;
    entry.udpdns = profile.udpdns;
    const fallback = findProfileById(active, profile.udpFallbackId);
    if (fallback !== null && fallback.plugin.length === 0) {
      entry.udp_fallback = {
        server: fallback.host,
        server_port: fallback.remotePort,
        password: fallback.password,
        method: fallback.method,
      };
    }
    entries.push(entry);
  }
  return JSON.stringify(entries, null, 2);
}

/**
 * The active profiles as `ss://` URLs, one per line. This is the clipboard
 * export.
 */
export function exportProfileUrls(profiles: Profile[]): string {
  const urls: string[] = [];
  for (const profile of profiles) {
    if (profile.subscriptionStatus === STATUS_OBSOLETE) {
      continue;
    }
    urls.push(profile.toUri());
  }
  return urls.join('\n');
}
