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

import { DEFAULT_REMOTE_DNS, Profile, nextUserOrder } from './Profile';
import { ROUTE_ALL } from './Routes';

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
}

/** Android's per-app settings block. Carried for the shape, never enabled. */
export interface ProxyAppsJson {
  enabled: boolean;
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

/** One profile from a parsed JSON object, or null when it is not one. */
export function profileFromJson(record: Record<string, Object>): Profile | null {
  const server = record['server'];
  const port = record['server_port'];
  const password = record['password'];
  const method = record['method'];

  if (typeof server !== 'string' || server.length === 0) {
    return null;
  }
  // providers write the port as a number and, less often, as a string
  const remotePort = typeof port === 'number' ? port : Number.parseInt(`${port}`, 10);
  if (Number.isNaN(remotePort) || remotePort <= 0 || remotePort > 65535) {
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

  const remarks = record['remarks'];
  profile.name = typeof remarks === 'string' && remarks.length > 0 ? remarks : server;

  const plugin = record['plugin'];
  if (typeof plugin === 'string' && plugin.length > 0) {
    profile.plugin = plugin;
    const opts = record['plugin_opts'];
    profile.pluginOpts = typeof opts === 'string' ? opts : '';
  }

  const route = record['route'];
  profile.route = typeof route === 'string' && route.length > 0 ? route : ROUTE_ALL;

  const remoteDns = record['remote_dns'];
  profile.remoteDns =
    typeof remoteDns === 'string' && remoteDns.length > 0 ? remoteDns : DEFAULT_REMOTE_DNS;

  profile.ipv6 = record['ipv6'] === true;
  profile.udpdns = record['udpdns'] === true;
  // `metered`, `proxy_apps` and `udp_fallback` are read and dropped: the first
  // two describe Android behaviour this platform has no equivalent for, and the
  // third needs a second core instance. Importing a file from Android therefore
  // loses per-app settings, which is the honest outcome rather than a silent
  // claim to have honoured them.
  return profile;
}

/** Every profile anywhere inside a parsed JSON value, however it is nested. */
function profilesInValue(value: Object | null | undefined, depth: number): Profile[] {
  const found: Profile[] = [];
  if (value === null || value === undefined || depth > MAX_DEPTH) {
    return found;
  }
  if (Array.isArray(value)) {
    for (const item of value as Object[]) {
      for (const profile of profilesInValue(item, depth + 1)) {
        found.push(profile);
      }
    }
    return found;
  }
  if (typeof value !== 'object') {
    return found;
  }
  const record = value as Record<string, Object>;
  const profile = profileFromJson(record);
  if (profile !== null) {
    found.push(profile);
    return found;
  }
  // not a server entry itself, so it is a container: SIP008 wraps its servers
  // in `servers`, and other providers use `configs` or an unnamed array
  for (const key of Object.keys(record)) {
    for (const nested of profilesInValue(record[key], depth + 1)) {
      found.push(nested);
    }
  }
  return found;
}

/** Profiles from text that is a list of `ss://` URLs, one per token. */
function profilesFromUrls(text: string): Profile[] {
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

/**
 * Reads profiles from text, in any of the shapes a user or a provider can
 * produce: an exported file, a SIP008 document, a nested provider document,
 * a list of `ss://` URLs, or a base64 blob of them — which is how most
 * subscriptions are served.
 */
export function parseProfilesText(text: string): Profile[] {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return [];
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      const parsed = profilesInValue(JSON.parse(trimmed) as Object, 0);
      if (parsed.length > 0) {
        return parsed;
      }
    } catch (e) {
      // not JSON after all: the scan below may still find URLs in it
    }
  }
  const direct = profilesFromUrls(trimmed);
  if (direct.length > 0) {
    return direct;
  }
  try {
    return profilesFromUrls(Profile.decodeBase64(trimmed));
  } catch (e) {
    return [];
  }
}

/**
 * Folds an imported batch into the stored list, following shadowsocks-android's
 * importer: a replace drops what is there and keeps the identity and counters
 * of profiles with the same address, while an import appends. The address is
 * the same key Android uses, so the two clients agree on what "the same
 * profile" means.
 */
export function applyImport(existing: Profile[], imported: Profile[], replace: boolean): Profile[] {
  if (!replace) {
    const appended = existing.slice();
    let order = nextUserOrder(appended);
    for (const profile of imported) {
      profile.subscriptionId = '';
      profile.ensureId();
      profile.userOrder = order;
      order++;
      appended.push(profile);
    }
    return appended;
  }
  const result: Profile[] = [];
  let order = 1;
  for (const profile of imported) {
    for (const previous of existing) {
      if (addressKey(previous) !== addressKey(profile)) {
        continue;
      }
      // the same server, so what identifies it locally is kept: its id, which
      // the selected-profile setting points at, and the traffic it has carried
      profile.id = previous.id;
      profile.tx = previous.tx;
      profile.rx = previous.rx;
      if (profile.name.length === 0 || profile.name === profile.host) {
        profile.name = previous.name;
      }
      break;
    }
    profile.ensureId();
    profile.userOrder = order;
    order++;
    result.push(profile);
  }
  return result;
}

/**
 * The stored list as an exported file: a JSON array, pretty-printed, in the
 * shape shadowsocks-android's `serializeToJson` writes. `sip008` restricts it
 * to the four fields that format defines, for handing to another client.
 */
export function exportProfiles(profiles: Profile[], sip008: boolean = false): string {
  const entries: ProfileJson[] = [];
  for (const profile of profiles) {
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
    entry.udpdns = profile.udpdns;
    entry.metered = false;
    entry.proxy_apps = { enabled: false };
    entries.push(entry);
  }
  return JSON.stringify(entries, null, 2);
}
