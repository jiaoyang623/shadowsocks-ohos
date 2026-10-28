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
import { JsonStore } from './JsonStore';

const STORE_STATS = 'traffic_stats';
const STORE_SETTLED = 'traffic_settled';
const STORE_PENDING = 'traffic_pending';

/**
 * One session's traffic record.
 *
 * The VPN extension writes it and the UI process settles it. `token` names the
 * extension start that produced the counters, `closed` says the extension
 * wrote its last record, and `settled` says the counters are already in
 * profiles.json. The settlement receipt (`lastSettledToken`) is the durable
 * proof: the extension may overwrite this record, but it never writes the
 * receipt, so a second settle cannot add the same counters twice.
 *
 * A record that predates 5.4.0 has only tx, rx and timestamp. It loads with an
 * empty profile id, an empty token, `stats = true`, `closed = false` and
 * `settled = false`, so the first settlement still counts it.
 */
export interface TrafficStats {
  /** Bytes sent through the tunnel (uplink), cumulative since connect. */
  tx: number;
  /** Bytes received through the tunnel (downlink), cumulative since connect. */
  rx: number;
  /** When the sample was taken, milliseconds since epoch. */
  timestamp: number;
  /** The profile that ran the session. Empty for a record made before 5.4.0. */
  profileId: string;
  /** Unique for each extension start. It identifies the session. */
  token: string;
  /** False when the stat endpoint is unavailable. tx and rx are then not live. */
  stats: boolean;
  /** True when the extension wrote the last record of the session. */
  closed: boolean;
  /** True when the counters in this record are already in profiles.json. */
  settled: boolean;
}

/** The record's file path. This is JsonStore's layout, under its own store name. */
function statsPath(context: common.Context): string {
  return `${context.filesDir}/store/${STORE_STATS}.json`;
}

/** One record from its stored text, or null when the text is not a record. */
function fromJson(raw: string): TrafficStats | null {
  if (raw.length === 0) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw) as TrafficStats;
    return {
      tx: parsed.tx ?? 0,
      rx: parsed.rx ?? 0,
      timestamp: parsed.timestamp ?? 0,
      profileId: parsed.profileId ?? '',
      token: parsed.token ?? '',
      stats: parsed.stats !== false,
      closed: parsed.closed === true,
      settled: parsed.settled === true,
    };
  } catch (e) {
    return null;
  }
}

/**
 * Cross-process bridge for traffic stats. The VPN extension ability hosts the
 * native core (which reports counters to a loopback TCP endpoint, see
 * `sslocal.setStatAddress`) and writes the latest sample here; the UI process
 * polls it. Both abilities belong to the same HAP, so JsonStore resolves to
 * the same file in both processes (writes are atomic — see JsonStore).
 *
 * Records are not deleted to mark settlement. The extension writes the live
 * record and may move it to the pending slot. Only the settler removes a
 * pending copy, after it added the counters. A deleted record could not say
 * that its counters were already added.
 */
export class TrafficStatsStore {
  static async save(context: common.Context, sample: TrafficStats): Promise<void> {
    await JsonStore.write(context, STORE_STATS, JSON.stringify(sample));
  }

  static async load(context: common.Context): Promise<TrafficStats | null> {
    return fromJson(await JsonStore.read(context, STORE_STATS));
  }

  /**
   * The record without yielding.
   *
   * The extension's teardown needs this answer before its first await: the
   * platform can tear the process down there, and a final record that
   * overwrote a settled one would resurrect counters the profile already
   * holds. `JsonStore.read` is asynchronous by signature, so it cannot serve.
   */
  static loadSync(context: common.Context): TrafficStats | null {
    try {
      return fromJson(fs.readTextSync(statsPath(context)));
    } catch (e) {
      // absent or unreadable: there is no record to protect
      return null;
    }
  }

  static async clear(context: common.Context): Promise<void> {
    await JsonStore.remove(context, STORE_STATS);
  }

  /**
   * The session token whose counters are already in profiles.json.
   *
   * The receipt is a file of its own, written only by the settler. The record
   * cannot serve as its own receipt: the extension may overwrite the record
   * between the settle and a later read, which would resurrect counters the
   * profile already holds. The extension never writes this file.
   */
  static async lastSettledToken(context: common.Context): Promise<string> {
    const raw = await JsonStore.read(context, STORE_SETTLED);
    if (raw.length === 0) {
      return '';
    }
    try {
      return (JSON.parse(raw) as SettledToken).token ?? '';
    } catch (e) {
      return '';
    }
  }

  /** Records that a session's counters are in profiles.json. */
  static async markSettled(context: common.Context, token: string): Promise<void> {
    const receipt: SettledToken = { token: token };
    await JsonStore.write(context, STORE_SETTLED, JSON.stringify(receipt));
  }

  /**
   * Moves the record of another session aside so this start can write its own.
   *
   * The core is single-instance, so an unsettled record found here belongs to
   * a session that is over: it ended without a teardown, or its settler has
   * not run yet. The settler reads the pending record before the live one, so
   * those counters still reach the profile. A pending record from an earlier
   * start is not merged. Settlement runs before every start in the normal
   * paths, and two consecutive unsettled crashes are the only way to lose one.
   */
  static async archivePending(context: common.Context): Promise<void> {
    const current = await TrafficStatsStore.load(context);
    if (current === null || current.settled) {
      return;
    }
    await JsonStore.write(context, STORE_PENDING, JSON.stringify(current));
    await JsonStore.remove(context, STORE_STATS);
  }

  /** The record a later start moved aside, or null. */
  static async loadPending(context: common.Context): Promise<TrafficStats | null> {
    return fromJson(await JsonStore.read(context, STORE_PENDING));
  }

  static async clearPending(context: common.Context): Promise<void> {
    await JsonStore.remove(context, STORE_PENDING);
  }
}

/** The settlement receipt: the last session token the UI process added. */
interface SettledToken {
  token: string;
}

/**
 * The record the page may use for live counters and rates. A settled record
 * belongs to a finished session, and a record whose stat endpoint was missing
 * carries no counters.
 */
export function liveCounters(sample: TrafficStats | null): TrafficStats | null {
  if (sample === null || sample.settled || !sample.stats) {
    return null;
  }
  return sample;
}

/** Human-readable byte count, e.g. `1.5 MB`. */
export function formatBytes(n: number): string {
  if (n < 1024) {
    return `${n} B`;
  }
  if (n < 1024 * 1024) {
    return `${(n / 1024).toFixed(1)} KB`;
  }
  if (n < 1024 * 1024 * 1024) {
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
  }
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** Human-readable rate, e.g. `128.0 KB/s`. */
export function formatRate(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

/** The traffic line of a profile row, or '' when both counters are zero. */
export function formatTraffic(tx: number, rx: number): string {
  if (tx <= 0 && rx <= 0) {
    return '';
  }
  return `↑ ${formatBytes(tx)}  ↓ ${formatBytes(rx)}`;
}

/**
 * The stored counter plus the live counter, for the running profile only. The
 * stored value includes every finished session.
 */
export function withLive(stored: number, live: number, isLive: boolean): number {
  return isLive ? stored + live : stored;
}
