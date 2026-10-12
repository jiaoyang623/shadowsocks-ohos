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
import { JsonStore } from './JsonStore';
import { VpnStatus, VPN_STATE_FAILED, VPN_STATE_RUNNING, VPN_STATE_STARTING, VPN_STATE_STOPPED } from './Diagnostics';

const STORE_STATUS = 'vpn_status';

/**
 * Cross-process bridge for the VPN extension's own view of what happened,
 * mirroring TrafficStatsStore. Before this existed the UI inferred "connected"
 * from `startVpnExtensionAbility` merely resolving, while every interesting
 * failure inside the extension (no profile, `VpnConnection.create()` throwing,
 * `sslocal.startTunFd()` returning non-zero) was logged to hilog and lost. The
 * extension writes here and the UI process polls the same file.
 *
 * The file is deliberately **never removed** — not even by the extension's
 * teardown. That is what lets the UI tell a clean stop (`stopped`) apart from a
 * startup failure (`failed`, with a reason) and from a crash (still `running`
 * but with a stale timestamp, see Diagnostics.summarizeStatus). Clearing it
 * alongside the traffic stats on teardown would silently erase that
 * distinction. The traffic stats file is cleared there instead, because those
 * counters are per-connection.
 */
export class VpnStatusStore {
  static async save(context: common.Context, status: VpnStatus): Promise<void> {
    await JsonStore.write(context, STORE_STATUS, JSON.stringify(status));
  }

  static async load(context: common.Context): Promise<VpnStatus | null> {
    const raw = await JsonStore.read(context, STORE_STATUS);
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as VpnStatus;
    } catch (e) {
      return null;
    }
  }

  /**
   * Records where the extension currently is. Kept to one call site per
   * transition so the timestamp doubles as a liveness heartbeat.
   */
  static async mark(context: common.Context, state: string, profileId: string,
    profileName: string, reason: string, detail: string): Promise<void> {
    const status: VpnStatus = {
      state: state,
      reason: reason,
      detail: detail,
      profileId: profileId,
      profileName: profileName,
      timestamp: Date.now(),
    };
    await VpnStatusStore.save(context, status);
  }

  static async markStarting(context: common.Context, profileId: string,
    profileName: string): Promise<void> {
    await VpnStatusStore.mark(context, VPN_STATE_STARTING, profileId, profileName, '', '');
  }

  static async markRunning(context: common.Context, profileId: string,
    profileName: string): Promise<void> {
    await VpnStatusStore.mark(context, VPN_STATE_RUNNING, profileId, profileName, '', '');
  }

  static async markFailed(context: common.Context, profileId: string, profileName: string,
    reason: string, detail: string): Promise<void> {
    await VpnStatusStore.mark(context, VPN_STATE_FAILED, profileId, profileName, reason, detail);
  }

  static async markStopped(context: common.Context): Promise<void> {
    await VpnStatusStore.mark(context, VPN_STATE_STOPPED, '', '', '', '');
  }
}
