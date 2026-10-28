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

import { DEFAULT_LOCAL_DNS_PORT } from './Diagnostics';
import {
  PLUGIN_STATE_KNOWN, pluginDefaultOptions, pluginStateOf, samePlugin,
} from './PluginOptions';
import { ROUTE_ALL } from './Routes';

const DEFAULT_SOCKS_PORT = 1080;

/**
 * Remote resolver for names this profile sends through the proxy. A hostname
 * is fine: the core hands the name to the proxy, which resolves it there.
 * shadowsocks-android's default is the same.
 */
export const DEFAULT_REMOTE_DNS = 'dns.google';

/**
 * Resolver for names the route sends directly. Only consulted when an ACL is
 * deployed, since every name goes to the remote resolver otherwise.
 */
const LOCAL_DNS_ADDRESS = '1.1.1.1';

/**
 * The values a new manual profile starts with. shadowsocks-android writes the
 * same host and password. The method differs: the core refuses the Android
 * default `aes-256-cfb`, so a manual profile starts with an AEAD cipher.
 */
const MANUAL_HOST = 'example.shadowsocks.org';
const MANUAL_PASSWORD = 'u1rRWTssNv0p';
const MANUAL_METHOD = 'aes-256-gcm';

/**
 * Subscription states, mirroring shadowsocks-android's SubscriptionStatus.
 * A user-configured profile is never touched by a subscription update; an
 * active one belongs to a subscription that still lists it; an obsolete one
 * belonged to a subscription that no longer does, and is kept so it can come
 * back.
 */
export const STATUS_USER_CONFIGURED = 0;
export const STATUS_ACTIVE = 1;
export const STATUS_OBSOLETE = 2;

/** A resolver address, split into the two fields the core's dns local wants. */
export interface DnsAddress {
  host: string;
  port: number;
}

/**
 * Random UUIDv4-shaped id for profiles and subscriptions. Implemented with
 * Math.random (uniqueness only, not security) because util.generateRandomUUID
 * is unavailable in the host-side unit-test runtime.
 */
export function newProfileId(): string {
  const HEX = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      out += '-';
      continue;
    }
    if (i === 14) {
      out += '4';
      continue;
    }
    if (i === 19) {
      out += HEX.charAt(8 + Math.floor(Math.random() * 4));
      continue;
    }
    out += HEX.charAt(Math.floor(Math.random() * 16));
  }
  return out;
}

/** One past the highest sort key in use, so a new profile lands at the end. */
export function nextUserOrder(profiles: Profile[]): number {
  let highest = 0;
  for (const profile of profiles) {
    if (profile.userOrder > highest) {
      highest = profile.userOrder;
    }
  }
  return highest + 1;
}

/**
 * Reads a port the user typed. The value 8388 replaces a value outside the
 * range 1 through 65535, including text that is not a number.
 */
export function normalizeRemotePort(text: string): number {
  const parsed = Number.parseInt(text, 10);
  if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535) {
    return 8388;
  }
  return parsed;
}

/**
 * Copies the feature settings that describe how this device uses a server.
 *
 * The copy covers `route`, `ipv6`, `udpdns`, `metered`, `proxyAppsEnabled`,
 * `proxyAppsBypass` and `proxyAppsList`. Android's `copyFeatureSettingsTo`
 * copies the same set. It does not copy the server, the transport, the name,
 * the resolver, or the UDP fallback.
 *
 * @param from the profile to read, or null to keep the target defaults.
 * @param to the profile to write.
 */
export function copyFeatureSettings(from: Profile | null, to: Profile): void {
  if (from === null) {
    return;
  }
  to.route = from.route;
  to.ipv6 = from.ipv6;
  to.udpdns = from.udpdns;
  to.metered = from.metered;
  to.proxyAppsEnabled = from.proxyAppsEnabled;
  to.proxyAppsBypass = from.proxyAppsBypass;
  to.proxyAppsList = from.proxyAppsList;
}

/**
 * A new profile with the manual defaults. The row exists before the editor
 * opens, so the name takes the host: an empty name draws a blank row.
 *
 * @param current the profile in use, whose feature settings the new profile
 *   takes, or null for a plain default profile.
 */
export function newManualProfile(current: Profile | null): Profile {
  const profile = new Profile();
  profile.host = MANUAL_HOST;
  // Android's Profile default has an empty name, so the row title is the
  // address and no second line is drawn.
  profile.name = '';
  profile.remotePort = 8388;
  profile.password = MANUAL_PASSWORD;
  profile.method = MANUAL_METHOD;
  copyFeatureSettings(current, profile);
  profile.ensureId();
  return profile;
}

/**
 * True when the profile belongs to an active subscription, which locks the
 * server fields in the editor. The rule uses the status alone, as Android does.
 */
export function isSubscriptionLocked(profile: Profile): boolean {
  return profile.subscriptionStatus === STATUS_ACTIVE;
}

/**
 * A shadowsocks server profile, parseable from SIP002 `ss://` URLs and
 * serializable into the JSON config consumed by the native sslocal core.
 */
export class Profile {
  id: string = '';
  name: string = 'Default';
  host: string = '';
  remotePort: number = 8388;
  password: string = '';
  method: string = 'aes-256-gcm';
  /** Policy route, one of the ROUTE_* constants in Routes.ets. */
  route: string = ROUTE_ALL;
  /** Owning subscription id, or '' for manually-added profiles. */
  subscriptionId: string = '';
  localAddress: string = '127.0.0.1';
  localPort: number = DEFAULT_SOCKS_PORT;
  /**
   * SIP003 plugin name ('' = no plugin), e.g. `obfs-local` or `v2ray-plugin`.
   * The native core runs known plugins in-process (see native/sslocal-ffi).
   */
  plugin: string = '';
  /** SIP003 plugin options (`k=v;...`), e.g. `obfs=tls;obfs-host=example.com`. */
  pluginOpts: string = '';
  /**
   * Options per plugin id, so a switch away from a plugin and back keeps its
   * options. The selected entry agrees with `pluginOpts`. A missing entry means
   * the plugin default applies. The field never goes to an ss URL or to an
   * exported JSON file.
   */
  pluginConfigs: Record<string, string> = {};
  /** Remote resolver for proxied names, as `host`, `host:port` or `dns://…`. */
  remoteDns: string = DEFAULT_REMOTE_DNS;
  /** Carried for import and export only, as Android carries it. */
  udpdns: boolean = false;
  /**
   * Route IPv6 as well as IPv4. Recorded now and not yet acted on: the tun is
   * configured for IPv4 only.
   */
  ipv6: boolean = false;
  /** Android metered-network hint. Stored and exported; no platform behavior. */
  metered: boolean = false;
  /** Apps VPN mode: the profile proxies selected bundle names, or all but them. */
  proxyAppsEnabled: boolean = false;
  /** True means Bypass: the selected apps skip the tunnel. False means On. */
  proxyAppsBypass: boolean = false;
  /** Newline-joined bundle names. Android stores package names here. */
  proxyAppsList: string = '';
  /** Profile used for UDP when this one cannot carry it. Stored only. */
  udpFallbackId: string = '';
  /** One of the STATUS_* constants above. */
  subscriptionStatus: number = STATUS_USER_CONFIGURED;
  /** Cumulative counters in bytes, kept per profile as Android keeps them. */
  tx: number = 0;
  rx: number = 0;
  /** Sort key for the list; ascending, ties in file order. */
  userOrder: number = 0;

  /** Assigns a fresh random id if this profile does not have one yet. */
  ensureId(): void {
    if (this.id.length === 0) {
      this.id = newProfileId();
    }
  }

  /* ---- row display ---- */

  /** The row title: the name, or host:port when the name is empty. */
  displayName(): string {
    if (this.name.length > 0) {
      return this.name;
    }
    return `${this.host}:${this.remotePort}`;
  }

  /**
   * The row's second line: the address when a name exists, then the plugin.
   * An empty string means the line is hidden.
   */
  displaySecondary(): string {
    const parts: string[] = [];
    if (this.name.length > 0) {
      parts.push(`${this.host}:${this.remotePort}`);
    }
    if (this.plugin.length > 0) {
      parts.push(`Plugin: ${this.plugin}`);
    }
    return parts.join('\n');
  }

  /* ---- plugin state and options ---- */

  /** `disabled`, `known` or `unknown`, as PluginOptions.ets defines them. */
  pluginState(): string {
    return pluginStateOf(this.plugin);
  }

  /** True when a plugin id is selected. */
  hasPlugin(): boolean {
    return this.plugin.length > 0;
  }

  /**
   * True when the profile belongs to an active subscription. This is the
   * instance form of the module function above, with the same rule.
   */
  isSubscriptionLocked(): boolean {
    return this.subscriptionStatus === STATUS_ACTIVE;
  }

  /** True when the editor may change the plugin selection. */
  canEditPlugin(): boolean {
    return !this.isSubscriptionLocked();
  }

  /** True when the editor may open the options editor. */
  canConfigurePlugin(): boolean {
    return this.canEditPlugin() && this.pluginState() === PLUGIN_STATE_KNOWN;
  }

  /**
   * The reason the core refuses this profile, or '' when the plugin is empty
   * or known. The native core stays the final authority.
   */
  pluginError(): string {
    if (this.plugin.length === 0 || this.pluginState() === PLUGIN_STATE_KNOWN) {
      return '';
    }
    return `Unknown plugin ${this.plugin}`;
  }

  /**
   * The stored options of a plugin id, or its catalogue default when the map
   * has no entry. A stored empty entry wins over the default.
   */
  pluginOptionsFor(id: string): string {
    if (id.length === 0) {
      return '';
    }
    if (Object.keys(this.pluginConfigs).indexOf(id) >= 0) {
      return this.pluginConfigs[id];
    }
    return pluginDefaultOptions(id);
  }

  /**
   * Stores the options of a plugin id. The selected plugin takes the text as
   * its effective options. An empty id changes nothing.
   */
  setPluginOptions(id: string, text: string): void {
    if (id.length === 0) {
      return;
    }
    this.pluginConfigs[id] = text;
    if (id === this.plugin) {
      this.pluginOpts = text;
    }
  }

  /**
   * Selects a plugin id.
   *
   * An empty id disables the plugin and keeps the stored entries. The same
   * plugin as the current one changes nothing, so an alias keeps its options.
   * A stored alias entry is selected when the user picks the canonical id.
   */
  selectPlugin(id: string): void {
    if (id.length === 0) {
      this.plugin = '';
      this.pluginOpts = '';
      return;
    }
    if (samePlugin(id, this.plugin)) {
      return;
    }
    const existing = this.existingPluginKey(id);
    const selected = existing.length > 0 ? existing : id;
    const options = this.pluginOptionsFor(selected);
    this.plugin = selected;
    this.pluginOpts = options;
    this.pluginConfigs[selected] = options;
  }

  /**
   * Records the selected plugin options in the map. A bare plugin URL keeps an
   * empty `pluginOpts`, so no entry is written for it.
   */
  seedPluginConfigs(): void {
    if (this.plugin.length > 0 && this.pluginOpts.length > 0) {
      this.pluginConfigs[this.plugin] = this.pluginOpts;
    }
  }

  /**
   * Makes `pluginOpts` agree with the map.
   *
   * A selected plugin with options writes its entry. Empty options take the
   * stored entry. `applyDefault` fills the catalogue default when no entry
   * exists. A caller passes false for a record that stores its plugin
   * configuration, because an explicit empty text there is a choice and must
   * stay empty.
   */
  normalizePluginOptions(applyDefault: boolean = true): void {
    if (this.plugin.length === 0) {
      this.pluginOpts = '';
      return;
    }
    if (this.pluginOpts.length > 0) {
      this.pluginConfigs[this.plugin] = this.pluginOpts;
      return;
    }
    if (Object.keys(this.pluginConfigs).indexOf(this.plugin) >= 0) {
      this.pluginOpts = this.pluginConfigs[this.plugin];
      return;
    }
    if (applyDefault) {
      this.pluginOpts = pluginDefaultOptions(this.plugin);
    }
  }

  /** The stored key that means the same plugin, or '' when none exists. */
  private existingPluginKey(id: string): string {
    const keys = Object.keys(this.pluginConfigs);
    if (keys.indexOf(id) >= 0) {
      return id;
    }
    for (const key of keys) {
      if (samePlugin(key, id)) {
        return key;
      }
    }
    return '';
  }

  /* ---- feature and transport copies ---- */

  /**
   * Copies the feature settings of another profile onto this one. The set is
   * the same as `copyFeatureSettings`.
   */
  copyFeatureSettingsFrom(source: Profile): void {
    copyFeatureSettings(source, this);
  }

  /**
   * Copies the transport fields that a re-listed subscription profile takes.
   * The local values stay: id, name, address, route, resolver, counters, order,
   * subscription state, and the plugin map for the other plugins.
   */
  copyTransportFrom(incoming: Profile): void {
    this.password = incoming.password;
    this.method = incoming.method;
    this.plugin = incoming.plugin;
    this.pluginOpts = incoming.pluginOpts;
    this.udpFallbackId = incoming.udpFallbackId;
  }

  /**
   * Decodes URL-safe or standard base64, with or without padding. Whitespace
   * is skipped; any other invalid character throws. Implemented in pure
   * ArkTS (no Base64Helper) so it also works in the host-side unit-test
   * runtime, where the native util codecs are unavailable.
   */
  static decodeBase64(text: string): string {
    const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const normalized = text.replaceAll('-', '+').replaceAll('_', '/');
    const bytes: number[] = [];
    let buffer = 0;
    let bits = 0;
    for (let i = 0; i < normalized.length; i++) {
      const c = normalized.charAt(i);
      if (c === '=') {
        break;
      }
      if (c === ' ' || c === '\t' || c === '\r' || c === '\n') {
        continue;
      }
      const value = ALPHABET.indexOf(c);
      if (value < 0) {
        throw new Error('invalid base64 input');
      }
      buffer = (buffer << 6) | value;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.push((buffer >> bits) & 0xff);
      }
    }
    return Profile.decodeUtf8(bytes);
  }

  /**
   * Encodes bytes as base64. `urlSafe` swaps the last two characters for the
   * URL-safe pair, and `pad` adds the `=` padding: gzip, and
   * shadowsocks-android's own `ss://` URLs, both want URL-safe without padding.
   * Pure ArkTS, for the same host-runtime reason as `decodeBase64`.
   */
  static encodeBase64(bytes: number[], urlSafe: boolean = false, pad: boolean = true): string {
    const STANDARD = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const URL_SAFE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    const table = urlSafe ? URL_SAFE : STANDARD;
    let out = '';
    for (let i = 0; i < bytes.length; i += 3) {
      const remaining = bytes.length - i;
      const second = remaining > 1 ? bytes[i + 1] : 0;
      const third = remaining > 2 ? bytes[i + 2] : 0;
      const triple = (bytes[i] << 16) | (second << 8) | third;
      out += table.charAt((triple >> 18) & 0x3f);
      out += table.charAt((triple >> 12) & 0x3f);
      if (remaining > 1) {
        out += table.charAt((triple >> 6) & 0x3f);
      } else if (pad) {
        out += '=';
      }
      if (remaining > 2) {
        out += table.charAt(triple & 0x3f);
      } else if (pad) {
        out += '=';
      }
    }
    return out;
  }

  /**
   * Encodes text as UTF-8 bytes without util.TextEncoder, which is unavailable
   * in the host-side unit-test runtime. A lone surrogate, which cannot be
   * encoded, becomes the replacement character, as TextEncoder does with it.
   */
  static encodeUtf8(text: string): number[] {
    const bytes: number[] = [];
    let i = 0;
    while (i < text.length) {
      let codePoint = text.charCodeAt(i);
      i++;
      if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
        const low = i < text.length ? text.charCodeAt(i) : 0;
        if (low >= 0xdc00 && low <= 0xdfff) {
          codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (low - 0xdc00);
          i++;
        } else {
          codePoint = 0xfffd;
        }
      } else if (codePoint >= 0xdc00 && codePoint <= 0xdfff) {
        codePoint = 0xfffd;
      }
      if (codePoint < 0x80) {
        bytes.push(codePoint);
      } else if (codePoint < 0x800) {
        bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
      } else if (codePoint < 0x10000) {
        bytes.push(0xe0 | (codePoint >> 12), 0x80 | ((codePoint >> 6) & 0x3f),
          0x80 | (codePoint & 0x3f));
      } else {
        bytes.push(0xf0 | (codePoint >> 18), 0x80 | ((codePoint >> 12) & 0x3f),
          0x80 | ((codePoint >> 6) & 0x3f), 0x80 | (codePoint & 0x3f));
      }
    }
    return bytes;
  }

  /**
   * Decodes UTF-8 bytes without util.TextDecoder, which is unavailable in the
   * host-side unit-test runtime. Invalid sequences are skipped.
   */
  static decodeUtf8(bytes: number[]): string {
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const lead = bytes[i];
      if (lead < 0x80) {
        out += String.fromCharCode(lead);
        i += 1;
        continue;
      }
      let codePoint = 0;
      let extra = 0;
      if ((lead & 0xe0) === 0xc0) {
        codePoint = lead & 0x1f;
        extra = 1;
      } else if ((lead & 0xf0) === 0xe0) {
        codePoint = lead & 0x0f;
        extra = 2;
      } else if ((lead & 0xf8) === 0xf0) {
        codePoint = lead & 0x07;
        extra = 3;
      } else {
        i += 1;
        continue;
      }
      if (i + extra >= bytes.length) {
        break;
      }
      for (let j = 1; j <= extra; j++) {
        codePoint = (codePoint << 6) | (bytes[i + j] & 0x3f);
      }
      if (codePoint <= 0xffff) {
        out += String.fromCharCode(codePoint);
      } else {
        // astral plane: encode as a surrogate pair
        const v = codePoint - 0x10000;
        out += String.fromCharCode(0xd800 + (v >> 10), 0xdc00 + (v & 0x3ff));
      }
      i += extra + 1;
    }
    return out;
  }

  /**
   * Percent-decodes a URL component, returning it unchanged when it contains
   * a malformed escape. decodeURIComponent throws on those, and a single bad
   * entry must not abort the parse of a whole subscription body.
   */
  static percentDecode(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (e) {
      return text;
    }
  }

  /**
   * Percent-encodes text, leaving alone the characters java.net.URI leaves
   * alone. This is the rule shadowsocks-android's `Uri.Builder` applies to the
   * name and the plugin query, so a URL written here matches one written there.
   */
  static percentEncode(text: string): string {
    const UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-!.~'()*";
    const HEX = '0123456789ABCDEF';
    let out = '';
    for (const byte of Profile.encodeUtf8(text)) {
      if (byte < 0x80 && UNRESERVED.indexOf(String.fromCharCode(byte)) >= 0) {
        out += String.fromCharCode(byte);
      } else {
        out += `%${HEX.charAt(byte >> 4)}${HEX.charAt(byte & 0xf)}`;
      }
    }
    return out;
  }

  /**
   * This profile as an `ss://` URL: the form shadowsocks-android writes when it
   * copies a profile or shows its QR code, and the form other clients import.
   *
   * The user information is base64url without padding, the host is bracketed
   * when it is an IPv6 literal, the plugin goes in the query, and the name goes
   * in the fragment. `parseUrl` reads all of it back.
   */
  toUri(): string {
    const userInfo = Profile.encodeBase64(
      Profile.encodeUtf8(`${this.method}:${this.password}`), true, false);
    const host = this.host.indexOf(':') >= 0 ? `[${this.host}]` : this.host;
    let url = `ss://${userInfo}@${host}:${this.remotePort}`;
    if (this.plugin.length > 0) {
      const options = this.pluginOpts.length > 0 ? `${this.plugin};${this.pluginOpts}` : this.plugin;
      url += `?plugin=${Profile.percentEncode(options)}`;
    }
    if (this.name.length > 0) {
      url += `#${Profile.percentEncode(this.name)}`;
    }
    return url;
  }

  /**
   * Parses an `ss://` URL in either SIP002 form
   * (`ss://base64(method:password)@host:port#name`) or legacy form
   * (`ss://base64(method:password@host:port)#name`). Returns null when the
   * text is not a valid shadowsocks URL.
   *
   * The URL owns the transport fields, the plugin and the name. A feature
   * profile, when given, supplies the feature settings that describe how this
   * device uses the server.
   */
  static parseUrl(url: string, feature: Profile | null = null): Profile | null {
    const trimmed = url.trim();
    if (!trimmed.startsWith('ss://')) {
      return null;
    }
    let body = trimmed.substring(5);
    let name = '';
    const hashIndex = body.indexOf('#');
    if (hashIndex >= 0) {
      name = Profile.percentDecode(body.substring(hashIndex + 1));
      body = body.substring(0, hashIndex);
    }
    // SIP002 query part: ?plugin=name%3Bopts (percent-encoded as a whole)
    let plugin = '';
    let pluginOpts = '';
    const queryIndex = body.indexOf('?');
    if (queryIndex >= 0) {
      const query = body.substring(queryIndex + 1);
      body = body.substring(0, queryIndex);
      const params = query.split('&');
      for (const param of params) {
        const eq = param.indexOf('=');
        if (eq > 0 && param.substring(0, eq) === 'plugin') {
          const decoded = Profile.percentDecode(param.substring(eq + 1));
          const semi = decoded.indexOf(';');
          plugin = semi >= 0 ? decoded.substring(0, semi) : decoded;
          pluginOpts = semi >= 0 ? decoded.substring(semi + 1) : '';
        }
      }
    }
    const atIndex = body.lastIndexOf('@');
    let method = '';
    let password = '';
    let hostPort = '';
    try {
      if (atIndex >= 0) {
        // SIP002: userinfo is base64(method:password)
        const userInfo = Profile.decodeBase64(body.substring(0, atIndex));
        hostPort = body.substring(atIndex + 1);
        const colon = userInfo.indexOf(':');
        if (colon < 0) {
          return null;
        }
        method = userInfo.substring(0, colon);
        password = userInfo.substring(colon + 1);
      } else {
        // legacy: whole body is base64(method:password@host:port)
        const decoded = Profile.decodeBase64(body);
        const at = decoded.lastIndexOf('@');
        if (at < 0) {
          return null;
        }
        const userInfo = decoded.substring(0, at);
        hostPort = decoded.substring(at + 1);
        const colon = userInfo.indexOf(':');
        if (colon < 0) {
          return null;
        }
        method = userInfo.substring(0, colon);
        password = userInfo.substring(colon + 1);
      }
    } catch (e) {
      return null;
    }
    const portColon = hostPort.lastIndexOf(':');
    if (portColon < 0) {
      return null;
    }
    const host = hostPort.substring(0, portColon).replace('[', '').replace(']', '');
    const port = Number.parseInt(hostPort.substring(portColon + 1), 10);
    if (host.length === 0 || Number.isNaN(port) || port <= 0 || port > 65535) {
      return null;
    }
    if (method.length === 0 || password.length === 0) {
      return null;
    }
    const profile = new Profile();
    profile.name = name.length > 0 ? name : host;
    profile.host = host;
    profile.remotePort = port;
    profile.method = method;
    profile.password = password;
    profile.plugin = plugin;
    profile.pluginOpts = pluginOpts;
    // The URL carries no options. A non-empty text seeds its map entry, and a
    // bare plugin keeps an empty pluginOpts.
    profile.seedPluginConfigs();
    copyFeatureSettings(feature, profile);
    return profile;
  }

  /**
   * Splits a resolver address into host and port, defaulting the port to 53.
   * Accepts `host`, `host:port`, `dns://host` and `dns://host:port`, which is
   * what shadowsocks-android's `URI("dns://${'$'}remoteDns")` accepts. Brackets
   * are stripped from an IPv6 literal.
   */
  static parseDnsAddress(text: string): DnsAddress {
    let rest = text.trim();
    if (rest.startsWith('dns://')) {
      rest = rest.substring(6);
    }
    let host = rest;
    let port = 53;
    const colon = rest.lastIndexOf(':');
    if (colon >= 0) {
      const parsed = Number.parseInt(rest.substring(colon + 1), 10);
      if (!Number.isNaN(parsed)) {
        host = rest.substring(0, colon);
        port = parsed;
      }
    }
    return { host: host.replace('[', '').replace(']', ''), port: port };
  }

  /**
   * JSON config for the native sslocal core with a local SOCKS5 service. This
   * is the proxy mode config, where nothing is routed and a client is pointed
   * at the listener instead.
   *
   * `shareOverLan` binds every interface rather than loopback, which lets other
   * devices on the network use the tunnel. That is a deliberate exposure: the
   * listener has no authentication, exactly as shadowsocks-android's has none.
   */
  toLocalConfig(port: number = 0, shareOverLan: boolean = false): string {
    const localPort = port > 0 ? port : this.localPort;
    const config: Record<string, Object> = {
      'locals': [Object({
        'protocol': 'socks',
        'local_address': shareOverLan ? '0.0.0.0' : this.localAddress,
        'local_port': localPort,
      })],
      'server': this.host,
      'server_port': this.remotePort,
      'password': this.password,
      'method': this.method,
    };
    if (this.plugin.length > 0) {
      config['plugin'] = this.plugin;
      config['plugin_opts'] = this.pluginOpts;
    }
    // Name the upstream resolver explicitly, as the tun config does: the
    // default is the system resolver, which means reading /etc/resolv.conf.
    // The app sandbox denies that read, and the failure is fatal rather than a
    // warning.
    config['dns'] = 'google';
    return JSON.stringify(config);
  }

  /**
   * JSON config for tun mode. The `tun` local's device fd is injected by the
   * native layer (`sslocal.startTunFd`). The mode is `tcp_and_udp` because both
   * protocols route through the tunnel. A plugin forwards TCP only, so a
   * profile with a plugin uses `tcp_only`.
   *
   * `tunAddress` is the interface address as `addr/prefix` (e.g. `172.19.0.1/30`)
   * and must match what the system VPN was configured with. It is not optional
   * in practice: the core refuses to serve a tun whose address it cannot read,
   * and on OpenHarmony the device can only report what the config states.
   *
   * When the profile's route is not `all`, `aclPath` must point at the
   * deployed ACL file for that route (see Routes.ets); it is injected as the
   * core's top-level `acl` field.
   *
   * `localDns` is the resolver for names the route sends directly (see
   * Network.ets). It only matters when an ACL is deployed, since without one
   * every name takes the remote resolver.
   *
   * `dnsPort` is the loopback port of the core's own resolver. The settings
   * store supplies it (see Settings.ets), and the value must be free on the
   * device. The default is the store default.
   */
  toTunConfig(aclPath: string = '', tunAddress: string = '',
    localDns: string = '', dnsPort: number = DEFAULT_LOCAL_DNS_PORT): string {
    const local: Record<string, Object> = { 'protocol': 'tun' };
    const locals: Object[] = [local];
    if (tunAddress.length > 0) {
      local['tun_interface_address'] = tunAddress;
      // Resolving names has to happen inside the tun, not by relaying UDP
      // through the server. A server that does not relay UDP (many do not) is
      // otherwise fatal to DNS, because clients which pick their own resolver
      // (browsers, above all) send their queries straight at it and wait
      // forever. The core answers port 53 itself when given a gateway, so the
      // resolver below is bound on loopback and handed to it. A tunnel built
      // from this config cannot have DNS depend on the server's UDP support.
      local['dns_gateway'] = `127.0.0.1:${dnsPort}`;
      const remoteDns = Profile.parseDnsAddress(this.remoteDns);
      const dnsLocal: Record<string, Object> = {
        'protocol': 'dns',
        'local_address': '127.0.0.1',
        'local_port': dnsPort,
        // Both are required: DnsBuilder takes them as arguments rather than
        // options and panics without them, which takes the whole local server
        // down before the tun ever serves. With no ACL deployed the local one
        // is never consulted, because every name goes to the remote resolver.
        // The address is the network's own resolver when one was found, since
        // a fixed public resolver is the kind of address a network can block.
        'local_dns_address': localDns.length > 0 ? localDns : LOCAL_DNS_ADDRESS,
        'local_dns_port': 53,
        'remote_dns_address': remoteDns.host,
        'remote_dns_port': remoteDns.port,
        // Resolving through the proxy over TCP only. The alternative races a
        // UDP query it cannot win against one sent 500 to 1500 ms later, so
        // every uncached lookup would pay that wait for nothing.
        'remote_dns_protocol': 'tcp_only',
      };
      locals.push(dnsLocal);
    }
    const config: Record<string, Object> = {
      'locals': locals,
      'server': this.host,
      'server_port': this.remotePort,
      'password': this.password,
      'method': this.method,
      'mode': this.plugin.length > 0 ? 'tcp_only' : 'tcp_and_udp',
      // Name the upstream resolver explicitly. The default is the system
      // resolver, and loading it means reading /etc/resolv.conf, which the app
      // sandbox denies. With a `dns` local enabled that turns into a fatal
      // `sslocal exited with error: Permission denied (os error 13)` instead of
      // the harmless warning it is otherwise.
      'dns': 'google',
    };
    if (this.plugin.length > 0) {
      config['plugin'] = this.plugin;
      config['plugin_opts'] = this.pluginOpts;
    }
    if (this.route !== ROUTE_ALL && aclPath.length > 0) {
      config['acl'] = aclPath;
    }
    return JSON.stringify(config);
  }
}
