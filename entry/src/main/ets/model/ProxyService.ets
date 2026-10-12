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

import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import sslocal from 'libsslocal.so';
import { Profile } from './Profile';

const TAG = 'ProxyService';

const BUNDLE = 'com.xbt.project';
const ENTRY_ABILITY = 'EntryAbility';

/**
 * Proxy mode: the core as a local SOCKS5 listener, without a tun.
 *
 * This is what shadowsocks-android calls its proxy service, and it is the mode
 * to use when the VPN consent is refused, or when another device on the network
 * should be able to use the tunnel. The core is the same one, started with a
 * `socks` local instead of a `tun` one.
 *
 * It runs in this process — the app's own — which the platform will freeze once
 * the app is in the background unless a continuous task is requested. That is
 * what the background task below is for, and it is why this mode cannot be
 * started from a notification action the way the VPN can: there is no separate
 * process to keep it alive.
 */
export class ProxyService {
  private static running: boolean = false;
  private static continuousTask: boolean = false;

  /** True while the core is serving as a proxy in this process. */
  static isRunning(): boolean {
    return ProxyService.running;
  }

  /**
   * Starts the core against `profile`, listening on loopback or, when
   * `shareOverLan` is set, on every interface.
   */
  static async start(context: common.Context, profile: Profile, port: number,
    shareOverLan: boolean): Promise<void> {
    if (ProxyService.running) {
      return;
    }
    const config = profile.toLocalConfig(port, shareOverLan);
    const code = sslocal.start(config);
    if (code !== 0) {
      const detail = sslocal.lastError() ?? `sslocal_start returned ${code}`;
      throw new Error(detail);
    }
    ProxyService.running = true;
    hilog.info(0x0000, TAG, 'proxy listening on %{public}s:%{public}d',
      shareOverLan ? '0.0.0.0' : '127.0.0.1', port);
    await ProxyService.holdProcess(context);
  }

  /** Stops the core and releases the continuous task. */
  static async stop(context: common.Context): Promise<void> {
    if (ProxyService.running) {
      sslocal.stop();
      ProxyService.running = false;
    }
    if (ProxyService.continuousTask) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(context);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'could not stop the continuous task');
      }
      ProxyService.continuousTask = false;
    }
  }

  /**
   * Asks to keep running in the background, which the platform grants with a
   * notification of its own. Failing to get it is not fatal: the proxy keeps
   * working while the app is in the foreground, so a refusal is logged and the
   * mode still starts.
   */
  private static async holdProcess(context: common.Context): Promise<void> {
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: BUNDLE,
          abilityName: ENTRY_ABILITY,
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      });
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      ProxyService.continuousTask = true;
      hilog.info(0x0000, TAG, 'continuous task granted');
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'continuous task refused: %{public}s', err.message ?? '');
    }
  }
}
