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
 * `./Routes` is imported because it is itself dependency-free — it only holds
 * string constants.
 */

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

/** The two endpoint settings the user can override. */
export interface AppSettings {
  probeUrl: string;
  speedTestUrl: string;
}

/** The on-disk shape, with every field optional so a partial file still loads. */
export interface AppSettingsJson {
  probeUrl?: string;
  speedTestUrl?: string;
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
  };
  if (parsed === null) {
    return settings;
  }
  const probe = parsed.probeUrl;
  if (probe !== undefined && probe.length > 0) {
    settings.probeUrl = probe;
  }
  const speed = parsed.speedTestUrl;
  if (speed !== undefined && speed.length > 0) {
    settings.speedTestUrl = speed;
  }
  return settings;
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
