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
import {
  isStale, STATS_STALE_MS, VPN_STATE_FAILED, VPN_STATE_STOPPED,
} from './Diagnostics';
import { ProfileStore } from './ProfileStore';
import { TrafficStats, TrafficStatsStore } from './TrafficStats';
import { VpnStatusStore } from './VpnStatus';

/**
 * Adds a finished session's counters to the profile that ran it, then marks
 * the record settled so the same traffic cannot be counted twice.
 *
 * The extension cannot do this itself. The platform tears its process down at
 * the first `await` in `onDestroy`, so a teardown that reads the record never
 * gets to write it, and every session's counters were lost. Each stop this app
 * starts passes through the UI process, which outlives the extension.
 *
 * Ownership: the extension writes the record and may move it to the pending
 * slot. Only this function adds the counters. The token in the record names
 * the session. The settlement receipt
 * (`TrafficStatsStore.lastSettledToken`) is the durable proof that the token
 * was counted, and the extension never writes the receipt. A late write from
 * the dying extension can therefore not resurrect counters the profile holds.
 *
 * The profile is named by the record, falling back to the status file for a
 * record written before 5.4.0. The status file is not the primary source: a
 * profile switch selects the new profile before the old session is stopped,
 * and the counters belong to the one that carried the traffic.
 */

/** Serializes settlements in the UI process, so two callers cannot both add. */
let settleChain: Promise<void> = Promise.resolve();

/** A thrown value as an Error, so `throw` accepts it under ArkTS rules. */
function asError(value: Object): Error {
  return value instanceof Error ? value : new Error(String(value));
}

/**
 * Settles one finished session. The call is idempotent and safe to make at any
 * time: a record that belongs to a live session is left alone.
 */
export function settleSessionTraffic(context: common.Context): Promise<void> {
  const next = settleChain.then(() => settleOnce(context));
  settleChain = next.catch(() => {
  });
  return next;
}

async function settleOnce(context: common.Context): Promise<void> {
  const status = await VpnStatusStore.load(context);
  // A terminal status says the extension is done, so its record is finished
  // even when it was written a moment ago (the core-death path).
  const terminal = status !== null &&
    (status.state === VPN_STATE_FAILED || status.state === VPN_STATE_STOPPED);
  // A record a later start moved aside belongs to a session that is over. Its
  // age says nothing, because the move can happen right after a crash. Clear
  // it only after the counters were handled. A failed write leaves it for a
  // retry.
  const pending = await TrafficStatsStore.loadPending(context);
  if (pending !== null) {
    await settleSample(context, pending, true, '');
    await TrafficStatsStore.clearPending(context);
  }
  const sample = await TrafficStatsStore.load(context);
  if (sample === null) {
    return;
  }
  // A live session must keep its record: the extension is still counting. A
  // record is finished when the extension wrote its last entry, when the status
  // is terminal, or when no writer has refreshed it for a whole staleness
  // window (the extension died without a teardown).
  if (!sample.closed && !terminal &&
    !isStale(sample.timestamp, Date.now(), STATS_STALE_MS)) {
    return;
  }
  const fallbackProfileId = status !== null ? status.profileId : '';
  await settleSample(context, sample, false, fallbackProfileId);
}

/** The same record with its settled flag set. */
function claimedRecord(sample: TrafficStats): TrafficStats {
  const claimed: TrafficStats = {
    tx: sample.tx,
    rx: sample.rx,
    timestamp: sample.timestamp,
    profileId: sample.profileId,
    token: sample.token,
    stats: sample.stats,
    closed: sample.closed,
    settled: true,
  };
  return claimed;
}

/**
 * Adds one record's counters, at most once.
 *
 * `isPending` is true for a record a later start moved aside: it has no live
 * record to mark, and the settlement receipt is its only state. Such a record
 * never falls back to the status file, because the status may already name the
 * session that moved it aside.
 */
async function settleSample(context: common.Context, sample: TrafficStats,
  isPending: boolean, fallbackProfileId: string): Promise<void> {
  // A record written before 5.4.0 has no token. As a live record, its own flag
  // is the only receipt, because only the extension can overwrite it and it
  // moves such a record aside instead. As a pending record, a derived token
  // keeps the settlement idempotent.
  let token: string = sample.token;
  if (token.length === 0 && isPending) {
    token = `legacy-${sample.timestamp}-${sample.tx}-${sample.rx}`;
  }
  if (token.length === 0 && sample.settled) {
    return;
  }
  const profileId = sample.profileId.length > 0 ? sample.profileId : fallbackProfileId;
  if (token.length > 0) {
    const receipt = await TrafficStatsStore.lastSettledToken(context);
    if (receipt === token) {
      // The counters are already in the profile. If a late extension write
      // reset the live record's flag, put it back so the page ignores it.
      if (!isPending && !sample.settled) {
        await TrafficStatsStore.save(context, claimedRecord(sample));
      }
      return;
    }
  }
  if (!isPending) {
    await TrafficStatsStore.save(context, claimedRecord(sample));
  }
  if (profileId.length === 0 || (sample.tx <= 0 && sample.rx <= 0)) {
    return;
  }
  // The receipt is written before the counters, so a crash in between loses
  // the counters once rather than counting them twice. A failed write is
  // reverted below, so a retry can still add them.
  if (token.length > 0) {
    try {
      await TrafficStatsStore.markSettled(context, token);
    } catch (e) {
      if (!isPending) {
        await TrafficStatsStore.save(context, sample).catch(() => {
        });
      }
      throw asError(e);
    }
  }
  try {
    await ProfileStore.addTraffic(context, profileId, sample.tx, sample.rx);
  } catch (e) {
    // The counters are not in the profile, so the receipt is a lie. Release
    // both marks and let the caller retry.
    if (token.length > 0) {
      await TrafficStatsStore.markSettled(context, '').catch(() => {
      });
    }
    if (!isPending) {
      await TrafficStatsStore.save(context, sample).catch(() => {
      });
    }
    throw asError(e);
  }
}
