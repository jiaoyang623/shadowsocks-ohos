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
import { ProfileStore } from './ProfileStore';
import { TrafficStatsStore } from './TrafficStats';
import { VpnStatusStore } from './VpnStatus';

/**
 * Adds a finished session's counters to the profile that ran it, then clears
 * the sample so the same traffic cannot be counted twice.
 *
 * The extension cannot do this itself. The platform tears its process down at
 * the first `await` in `onDestroy`, so a teardown that reads the sample never
 * gets to write it, and every session's counters were lost. Each stop this app
 * starts passes through the UI process, which outlives the extension.
 *
 * The profile is named by the status file rather than by the current
 * selection: a profile switch selects the new profile before the old session
 * is stopped, and the counters belong to the one that carried the traffic.
 */
export async function settleSessionTraffic(context: common.Context): Promise<void> {
  const stats = await TrafficStatsStore.load(context);
  if (stats === null) {
    return;
  }
  const status = await VpnStatusStore.load(context);
  if (status !== null && status.profileId.length > 0 && (stats.tx > 0 || stats.rx > 0)) {
    await ProfileStore.addTraffic(context, status.profileId, stats.tx, stats.rx);
  }
  await TrafficStatsStore.clear(context);
}
