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

/**
 * Pure decision logic for connection diagnostics: no kit imports, no I/O, no
 * timers. Everything here is exercised by entry/src/test (the host-side test
 * runtime has no native codecs, so the logic must be loadable on its own).
 * The I/O that feeds these functions lives in ConnectivityProbe/Latency/
 * Throughput, and the cross-process file they read lives in VpnStatus.
 *
 * `./Routes` and `./Profile` are imported because they need no kit API. The
 * rules that read a profile stay in this module, so the host runner can test
 * them.
 */

import { Profile } from './Profile';
import {
  ROUTE_ALL, ROUTE_BYPASS_CHINA, ROUTE_BYPASS_LAN, ROUTE_BYPASS_LAN_CHINA,
} from './Routes';

/* ---- VPN extension states, as persisted in the status file ---- */
export const VPN_STATE_STARTING: string = 'starting';
export const VPN_STATE_RUNNING: string = 'running';
export const VPN_STATE_FAILED: string = 'failed';
export const VPN_STATE_STOPPED: string = 'stopped';

/* ---- phases the UI derives from that file ---- */
export const PHASE_IDLE: string = 'idle';
export const PHASE_CONNECTING: string = 'connecting';
export const PHASE_VERIFYING: string = 'verifying';
export const PHASE_CONNECTED: string = 'connected';
export const PHASE_PROBE_FAILED: string = 'probe-failed';
export const PHASE_FAILED: string = 'failed';
/** The extension says `running` but stopped refreshing its timestamp. */
export const PHASE_LOST: string = 'lost';
/** The tunnel is tearing down. No row accepts input. */
export const PHASE_STOPPING: string = 'stopping';

/* ---- probe verdicts ---- */
export const PROBE_OK: string = 'ok';
export const PROBE_NO_INTERNET: string = 'no-internet';
export const PROBE_NOT_TUNNELLED: string = 'not-tunnelled';

/**
 * How long the traffic-stat file may go unwritten before the tunnel is presumed
 * dead. The core reports every 500 ms and the extension persists at most once a
 * second, so a healthy tunnel never comes close to this.
 *
 * Liveness is read off the *stats* file, not the status file: the status file
 * is written only on transitions, so its timestamp is a record of when the
 * transition happened, not a heartbeat — treating it as one would declare every
 * healthy connection lost a few seconds after it came up.
 */
export const STATS_STALE_MS: number = 6000;
/** How long a start may sit in `starting` before the UI gives up on it. */
export const CONNECT_TIMEOUT_MS: number = 20000;
/** Wait for the core's 500 ms report and the extension's 1 s save to land. */
export const STATS_SETTLE_MS: number = 1500;

/**
 * Default connectivity probe: Android's canonical captive-portal endpoint. It
 * answers 204 with an empty body, and outside a tunnel it is unreachable from
 * the networks where this app is normally used — which is what makes a success
 * here evidence rather than a tautology. Overridable in Settings, because no
 * single URL is proxied under every policy route (see routeProxiesByDefault).
 *
 * These two live here, in the dependency-free module, rather than next to the
 * I/O that uses them, so the settings store can reference the defaults without
 * pulling `@kit.NetworkKit` into the host-side test runtime.
 */
export const DEFAULT_PROBE_URL: string = 'http://connectivitycheck.gstatic.com/generate_204';

/**
 * Default download for the throughput test: Cloudflare's speed-test endpoint,
 * which serves a fixed-size body over TLS. Overridable in Settings — a 10 MB
 * download is not always appropriate.
 */
export const DEFAULT_SPEED_URL: string = 'https://speed.cloudflare.com/__down?bytes=10000000';

/**
 * How the tunnel is applied, mirroring shadowsocks-android's service modes.
 *
 * `vpn` takes over the device through the VPN extension. `proxy` runs the core
 * as a local SOCKS5 listener and lets apps be pointed at it, which is the only
 * option on a device where the VPN consent is refused, and what "share over
 * LAN" needs: with the listener on all interfaces, other devices can use it.
 * Android's transparent proxy has no equivalent here and is not offered.
 */
export const MODE_VPN: string = 'vpn';
export const MODE_PROXY: string = 'proxy';

/** Default local SOCKS5 port for proxy mode, the same one Android uses. */
export const DEFAULT_PROXY_PORT: number = 1080;

/**
 * Default port of the core's local DNS resolver in tun mode. The core binds it
 * on loopback and answers the tun's port 53 through it. Android uses the same
 * default.
 */
export const DEFAULT_LOCAL_DNS_PORT: number = 5450;

/** The row summary of a port that has no stored value. */
export const PORT_UNSET: string = 'not-set';

/* ---- settings row keys, in display order ---- */
export const SETTINGS_ROW_AUTO_CONNECT: string = 'auto-connect';
export const SETTINGS_ROW_SERVICE_MODE: string = 'service-mode';
export const SETTINGS_ROW_PROXY_PORT: string = 'proxy-port';
export const SETTINGS_ROW_LOCAL_DNS_PORT: string = 'local-dns-port';

/** The mode entries of the service mode menu, in the Android menu order. */
export const SERVICE_MODE_CHOICES: string[] = [MODE_PROXY, MODE_VPN];

/**
 * The IPv6 switch applies to tun mode only. Proxy mode creates no tunnel, so
 * the flag would have nothing to act on.
 */
export function ipv6SwitchEnabled(serviceMode: string): boolean {
  return serviceMode === MODE_VPN;
}

/** The endpoint settings the user can override, and how the tunnel is applied. */
export interface AppSettings {
  probeUrl: string;
  speedTestUrl: string;
  /** A stored mode value. A value other than MODE_VPN or MODE_PROXY is kept. */
  serviceMode: string;
  /** The port text as the user typed it. '' means Not set. */
  proxyPort: string;
  /** The local DNS port text as the user typed it. '' means Not set. */
  localDnsPort: string;
  /** Stored for a future startup hook. No HarmonyOS hook exists yet. */
  autoConnect: boolean;
  /** Bind proxy mode's listener on all interfaces rather than loopback only. */
  shareOverLan: boolean;
}

/** The on-disk shape. A 5.3.5 file stores the two ports as numbers. */
export interface AppSettingsJson {
  probeUrl?: string;
  speedTestUrl?: string;
  serviceMode?: string;
  proxyPort?: string | number;
  localDnsPort?: string | number;
  autoConnect?: boolean;
  shareOverLan?: boolean;
}

/**
 * The text form of a stored port value. Returns '' for a missing value and for
 * a value that is neither a string nor a number. A number becomes decimal text.
 */
function portText(value: string | number | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return `${value}`;
  }
  return '';
}

/**
 * Coerces a parsed settings file into a complete AppSettings, filling in the
 * defaults for anything missing or blank. Tolerates a null (absent or corrupt
 * file) so a first run needs no special case at the call site.
 */
export function settingsFromJson(parsed: AppSettingsJson | null): AppSettings {
  const settings: AppSettings = {
    probeUrl: DEFAULT_PROBE_URL,
    speedTestUrl: DEFAULT_SPEED_URL,
    serviceMode: MODE_VPN,
    proxyPort: `${DEFAULT_PROXY_PORT}`,
    localDnsPort: `${DEFAULT_LOCAL_DNS_PORT}`,
    autoConnect: false,
    shareOverLan: false,
  };
  if (parsed === null) {
    return settings;
  }
  const probe = parsed.probeUrl;
  if (typeof probe === 'string' && probe.length > 0) {
    settings.probeUrl = probe;
  }
  const speed = parsed.speedTestUrl;
  if (typeof speed === 'string' && speed.length > 0) {
    settings.speedTestUrl = speed;
  }
  // A stored mode other than the two the app offers is kept. The summary shows
  // Not set for it, and the main page starts VPN mode.
  if (typeof parsed.serviceMode === 'string' && parsed.serviceMode.length > 0) {
    settings.serviceMode = parsed.serviceMode;
  }
  if (parsed.proxyPort !== undefined) {
    settings.proxyPort = portText(parsed.proxyPort);
  }
  if (parsed.localDnsPort !== undefined) {
    settings.localDnsPort = portText(parsed.localDnsPort);
  }
  settings.autoConnect = parsed.autoConnect === true;
  settings.shareOverLan = parsed.shareOverLan === true;
  return settings;
}

/** The row keys the screen shows. The collapsed view shows Auto Connect only. */
export function settingsRows(expanded: boolean): string[] {
  if (!expanded) {
    return [SETTINGS_ROW_AUTO_CONNECT];
  }
  return [
    SETTINGS_ROW_AUTO_CONNECT,
    SETTINGS_ROW_SERVICE_MODE,
    SETTINGS_ROW_PROXY_PORT,
    SETTINGS_ROW_LOCAL_DNS_PORT,
  ];
}

/** The hidden row keys, in display order, for the Advanced summary. */
export function advancedSummaryRows(): string[] {
  return [SETTINGS_ROW_SERVICE_MODE, SETTINGS_ROW_PROXY_PORT, SETTINGS_ROW_LOCAL_DNS_PORT];
}

/** The menu entry that matches a stored mode. '' when no entry matches. */
export function serviceModeEntry(serviceMode: string): string {
  if (serviceMode === MODE_VPN) {
    return MODE_VPN;
  }
  if (serviceMode === MODE_PROXY) {
    return MODE_PROXY;
  }
  return '';
}

/** The row summary of a stored port text. */
export function portSummary(text: string): string {
  return text.length > 0 ? text : PORT_UNSET;
}

/** True when the text holds ASCII digits only. */
function isDigitText(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/**
 * The port a stored text means. Returns the fallback for an empty text, a text
 * with a non-digit, a value below 1025, and a value above 65535.
 */
export function portNumber(text: string, fallback: number): number {
  if (!isDigitText(text)) {
    return fallback;
  }
  const value = Number.parseInt(text, 10);
  if (Number.isNaN(value) || value < 1025 || value > 65535) {
    return fallback;
  }
  return value;
}

/** The digits of a port input, at most five. */
export function sanitizePortInput(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    if (out.length >= 5) {
      break;
    }
    const code = text.charCodeAt(i);
    if (code >= 48 && code <= 57) {
      out += text.charAt(i);
    }
  }
  return out;
}

/**
 * Whether the stored file lacks a key the current shape needs. An absent file
 * (null) always needs a seed. An empty stored port is a deliberate clear.
 */
export function settingsNeedSeed(parsed: AppSettingsJson | null): boolean {
  if (parsed === null) {
    return true;
  }
  return parsed.serviceMode === undefined || parsed.proxyPort === undefined ||
    parsed.localDnsPort === undefined || parsed.autoConnect === undefined;
}

/** The store shape of a complete settings object. The ports stay text. */
export function settingsJsonFrom(settings: AppSettings): AppSettingsJson {
  const json: AppSettingsJson = {
    probeUrl: settings.probeUrl,
    speedTestUrl: settings.speedTestUrl,
    serviceMode: settings.serviceMode,
    proxyPort: settings.proxyPort,
    localDnsPort: settings.localDnsPort,
    autoConnect: settings.autoConnect,
    shareOverLan: settings.shareOverLan,
  };
  return json;
}

/** Cross-process status of the VPN extension, written by the extension ability. */
export interface VpnStatus {
  /** One of the VPN_STATE_* constants. */
  state: string;
  /** Short human-readable summary, '' unless the state is `failed`. */
  reason: string;
  /** Underlying detail (native error text), '' unless the state is `failed`. */
  detail: string;
  profileId: string;
  profileName: string;
  /** When the transition was recorded, milliseconds since epoch. */
  timestamp: number;
}

/** Result of one TCP-connect latency measurement against a profile's server. */
export interface LatencyEntry {
  ok: boolean;
  /** Round-trip time in milliseconds; meaningless unless `ok`. */
  ms: number;
  detail: string;
}

/** What one connectivity probe concluded. */
export interface ProbeVerdict {
  /** One of the PROBE_* constants. */
  verdict: string;
  reason: string;
}

/** Starting a measurement that has not produced a value yet. */
export function latencyPending(): LatencyEntry {
  return { ok: false, ms: 0, detail: 'pending' };
}

/**
 * Maps the persisted status file to the phase the UI should render.
 *
 * Returns PHASE_IDLE for `stopped` and for a missing file (never connected, or
 * a build predating this feature). It deliberately says nothing about
 * liveness — a `running` status stays `running` however old it is, because this
 * file only changes on transitions. Use isStale against the traffic-stat
 * timestamp for that.
 */
export function summarizeStatus(status: VpnStatus | null): string {
  if (status === null) {
    return PHASE_IDLE;
  }
  if (status.state === VPN_STATE_STARTING) {
    return PHASE_CONNECTING;
  }
  if (status.state === VPN_STATE_RUNNING) {
    return PHASE_CONNECTED;
  }
  if (status.state === VPN_STATE_FAILED) {
    return PHASE_FAILED;
  }
  return PHASE_IDLE;
}

/** Whether a sample taken at `timestamp` has gone stale by `nowMs`. */
export function isStale(timestamp: number, nowMs: number, staleMs: number): boolean {
  return (nowMs - timestamp) > staleMs;
}

/**
 * Whether the service is stopped, for the settings rows that a live service
 * locks. A recent status record or a live traffic sample means the tunnel is
 * still up.
 */
export function isServiceStopped(status: VpnStatus | null, statsTimestamp: number,
  nowMs: number, proxyUp: boolean): boolean {
  if (proxyUp) {
    return false;
  }
  if (status === null) {
    return true;
  }
  if (status.state === VPN_STATE_STOPPED || status.state === VPN_STATE_FAILED) {
    return true;
  }
  const statusRecent = !isStale(status.timestamp, nowMs, CONNECT_TIMEOUT_MS + STATS_STALE_MS);
  const statsLive = statsTimestamp > 0 && !isStale(statsTimestamp, nowMs, STATS_STALE_MS);
  return !(statusRecent || statsLive);
}

/** Whether a profile row accepts a tap or a drag. Every phase but STOPPING. */
export function isEnabled(phase: string): boolean {
  return phase !== PHASE_STOPPING;
}

/**
 * The selected profile id and its UDP fallback id, when both have a profile.
 * An absent selection falls back to the first profile, as ProfileStore does.
 */
export function activeProfileIds(profiles: Profile[], currentId: string): string[] {
  if (profiles.length === 0) {
    return [];
  }
  let selected: Profile = profiles[0];
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].id === currentId) {
      selected = profiles[i];
      break;
    }
  }
  const ids: string[] = [selected.id];
  const fallbackId = selected.udpFallbackId;
  if (fallbackId.length === 0 || fallbackId === selected.id) {
    return ids;
  }
  for (let i = 0; i < profiles.length; i++) {
    if (profiles[i].id === fallbackId) {
      ids.push(fallbackId);
      break;
    }
  }
  return ids;
}

/**
 * Whether the edit icon and the swipe are available. A profile that carries
 * the live tunnel stays locked until the tunnel stops.
 */
export function isProfileEditable(phase: string, activeIds: string[], profileId: string): boolean {
  if (phase === PHASE_IDLE || phase === PHASE_FAILED) {
    return true;
  }
  return phase !== PHASE_STOPPING && activeIds.indexOf(profileId) < 0;
}

/**
 * Whether a route sends a *foreign* destination through the tunnel by default.
 *
 * Read off the shipped ACL files: `bypass-*` routes use `[proxy_all]` plus a
 * `[bypass_list]`, so they proxy unless the destination is listed; `gfwlist`
 * and `china-list` use `[bypass_all]` plus a `[proxy_list]`, so they connect
 * directly unless the destination is listed. That distinction is what makes a
 * non-moving traffic counter meaningful on some routes and meaningless on
 * others — see interpretProbe.
 */
export function routeProxiesByDefault(route: string): boolean {
  return route === ROUTE_ALL || route === ROUTE_BYPASS_LAN ||
    route === ROUTE_BYPASS_CHINA || route === ROUTE_BYPASS_LAN_CHINA;
}

/**
 * Decides what a probe result means.
 *
 * An HTTP success alone is not proof the tunnel works: with a default route and
 * no trusted applications the UI process normally reaches the network through
 * the tun, but under `gfwlist`/`china-list` a foreign host is deliberately sent
 * direct, and on the public emulator image guest traffic never reaches the tun
 * at all. So when the route proxies by default (`requireTunnel`) and the core's
 * byte counters did not move across the probe, the request must have bypassed
 * the tunnel — reported as PROBE_NOT_TUNNELLED rather than success.
 *
 * `statsAvailable` false means the counters could not be read at all (no stats
 * endpoint); that is reported as success rather than as a false failure.
 */
export function interpretProbe(httpOk: boolean, httpCode: number,
  rxBefore: number, rxAfter: number, statsAvailable: boolean,
  requireTunnel: boolean, failureReason: string): ProbeVerdict {
  if (!httpOk) {
    let reason = failureReason;
    if (reason.length === 0) {
      reason = httpCode > 0 ? `HTTP ${httpCode}` : 'no response';
    }
    const verdict: ProbeVerdict = {
      verdict: PROBE_NO_INTERNET,
      reason: reason,
    };
    return verdict;
  }
  if (requireTunnel && statsAvailable && rxAfter <= rxBefore) {
    const verdict: ProbeVerdict = {
      verdict: PROBE_NOT_TUNNELLED,
      reason: 'traffic did not go through the tunnel',
    };
    return verdict;
  }
  const ok: ProbeVerdict = { verdict: PROBE_OK, reason: '' };
  return ok;
}

/**
 * Megabits per second over a transfer window. Returns 0 rather than NaN or
 * Infinity for the degenerate inputs a failed or instant transfer produces.
 */
export function computeMbps(bytes: number, elapsedMs: number): number {
  if (bytes <= 0 || elapsedMs <= 0) {
    return 0;
  }
  return (bytes * 8) / (elapsedMs / 1000) / 1000000;
}

/** Human-readable throughput, e.g. `42.3 Mbps`. `—` when there is no result. */
export function formatMbps(mbps: number): string {
  if (mbps <= 0) {
    return '—';
  }
  return mbps < 10 ? `${mbps.toFixed(2)} Mbps` : `${mbps.toFixed(1)} Mbps`;
}

/** Human-readable latency, e.g. `42 ms` / `1.5 s`. `—` before any measurement. */
export function formatLatency(entry: LatencyEntry | null): string {
  if (entry === null) {
    return '—';
  }
  if (!entry.ok) {
    return 'fail';
  }
  return entry.ms < 1000 ? `${entry.ms} ms` : `${(entry.ms / 1000).toFixed(1)} s`;
}

/** Human-readable round-trip time for a probe result. '' when unknown. */
export function formatRtt(ms: number): string {
  return ms > 0 ? `${ms} ms` : '';
}
