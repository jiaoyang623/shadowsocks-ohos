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

import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { vpnExtension } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { setAbilityContext, setPendingImport } from '../model/AppContext';
import { ACTION_DISCONNECT, ACTION_OPEN } from '../model/ConnectionNotification';
import { settleSessionTraffic } from '../model/SessionTraffic';
import {
  CONNECT_TIMEOUT_MS, isStale, STATS_STALE_MS, VPN_STATE_RUNNING, VPN_STATE_STARTING,
} from '../model/Diagnostics';
import { VpnStatusStore } from '../model/VpnStatus';
import { TrafficStatsStore } from '../model/TrafficStats';

const TAG = 'EntryAbility';

/** How long a notification stop waits for the extension to report `stopped`. */
const VPN_STOP_TIMEOUT_MS = 5000;

/** Resolves after `ms` milliseconds. */
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/**
 * True while the extension that a start or stop is about should still exist.
 *
 * The status file only changes on transitions, so a `running` record from a
 * long-lived tunnel is old and perfectly normal. Liveness therefore comes from
 * the traffic record, which the extension refreshes every second (the record
 * also carries the heartbeat a session without a stat endpoint writes). The
 * fallback is the status timestamp, which is fresh right after a transition.
 */
async function extensionAlive(context: common.UIAbilityContext): Promise<boolean> {
  const status = await VpnStatusStore.load(context);
  if (status === null ||
    (status.state !== VPN_STATE_STARTING && status.state !== VPN_STATE_RUNNING)) {
    return false;
  }
  const record = await TrafficStatsStore.load(context);
  const countersLive = record !== null && !record.settled &&
    !isStale(record.timestamp, Date.now(), STATS_STALE_MS);
  const statusRecent = !isStale(status.timestamp, Date.now(),
    CONNECT_TIMEOUT_MS + STATS_STALE_MS);
  return countersLive || statusRecent;
}

/**
 * Waits until the extension no longer exists. The status turns `stopped`
 * before its process is gone (the extension stops the core first), and a
 * crashed extension writes nothing at all, so a stale record with a stale
 * status counts as stopped too.
 */
async function waitForVpnStopped(context: common.UIAbilityContext): Promise<boolean> {
  const deadline = Date.now() + VPN_STOP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (!(await extensionAlive(context))) {
      return true;
    }
    await sleep(100);
  }
  return false;
}

/** Handles either way the ability is entered: fresh, or already running. */
function takeImportUri(want: Want): void {
  const uri = want.uri;
  if (uri !== undefined && uri.startsWith('ss://')) {
    hilog.info(0x0000, TAG, 'received a profile link');
    setPendingImport(uri);
  }
}

/** The VPN extension this app runs; the same want the list page starts it with. */
const VPN_ABILITY: Want = {
  deviceId: '',
  bundleName: 'com.xbt.project',
  abilityName: 'SsVpnExtensionAbility',
};

/**
 * Stops the tunnel when the notification's button asked for it. This is the
 * ability rather than the extension because a notification's action can only
 * bring up an ability, and an ability is what can stop the extension.
 */
async function handleAction(want: Want, context: common.UIAbilityContext): Promise<void> {
  if (want.action !== ACTION_DISCONNECT) {
    return;
  }
  hilog.info(0x0000, TAG, 'disconnect requested from the notification');
  // Stop first, settle after. The extension stops its core and writes the
  // session's final traffic record before it records `stopped` (see
  // SsVpnExtensionAbility.onDestroy), so the settlement below cannot race a
  // live writer and cannot lose the record to a teardown clear. The stop call
  // only asks for the stop. The status says when it happened.
  try {
    await vpnExtension.stopVpnExtensionAbility(VPN_ABILITY);
  } catch (e) {
    hilog.warn(0x0000, TAG, 'could not stop the VPN extension: %{public}s',
      (e as BusinessError).message ?? '');
  }
  const stopped = await waitForVpnStopped(context);
  if (!stopped) {
    hilog.warn(0x0000, TAG, 'the VPN did not report stopped before the deadline');
  }
  // the extension's own teardown is cut off by the platform, so the session's
  // counters are written here, after its last record. A failed write must not
  // undo the stop that already happened.
  try {
    await settleSessionTraffic(context);
  } catch (e) {
    hilog.warn(0x0000, TAG, 'session traffic settle failed: %{public}s', JSON.stringify(e));
  }
}

export default class EntryAbility extends UIAbility {
  /** The stage that holds the main screen, kept for a warm-start body tap. */
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    setAbilityContext(this.context);
    // A session that ended while this process was not there leaves an
    // unclaimed traffic record. An extension crash and a stop by the system
    // both do this. Settling it now is safe: a live session's record stays
    // fresh and is left alone (see SessionTraffic).
    settleSessionTraffic(this.context).catch((e: Object) => {
      hilog.warn(0x0000, TAG, 'session traffic settle failed: %{public}s', JSON.stringify(e));
    });
    handleAction(want, this.context);
    takeImportUri(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // the ability is already up: a link from a browser, or the notification's
    // button, arrives here
    handleAction(want, this.context);
    takeImportUri(want);
    if (want.action === ACTION_OPEN) {
      this.showMainScreen();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
      // The window refuses bar changes before its content exists
      // (1300002), so the colours are set once the page is loaded.
      this.applySystemBars(windowStage);
    });
  }

  /**
   * Paints the system bars the way Android does: the status bar takes the app
   * bar's darker shade, and the navigation bar the same shade, with white
   * content. The colours come from resources, so the dark theme gets its own.
   * A refused call is logged and leaves the platform's colours in place.
   *
   * The window background takes the page colour. The gesture bar sits on a
   * system surface outside the page, and without this the platform paints it
   * black, which reads as a black bar under the content.
   */
  private applySystemBars(windowStage: window.WindowStage): void {
    try {
      const resources = this.context.resourceManager;
      const status = resources.getColorSync($r('app.color.main_status_bar').id);
      const page = resources.getColorSync($r('app.color.main_page').id);
      const hex = (color: number): string =>
        `#${(color & 0xFFFFFF).toString(16).padStart(6, '0')}`;
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowBackgroundColor(hex(page));
      // The platform paints both bars once the page exists. The window stays
      // in the safe-area layout, so pages keep clear of the bars by
      // themselves; only the bar colours change.
      const r = (page >> 16) & 0xFF;
      const g = (page >> 8) & 0xFF;
      const b = page & 0xFF;
      const navContent = (0.299 * r + 0.587 * g + 0.114 * b) < 128 ? '#FFFFFF' : '#000000';
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: hex(status),
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: hex(page),
        navigationBarContentColor: navContent,
      }).catch((e: BusinessError) => {
        hilog.warn(0x0000, TAG, 'system bar colours: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.warn(0x0000, TAG, 'system bar colours: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * Brings the main screen back on a notification body tap.
   *
   * A cold start already loads it from `onWindowStageCreate`. A warm start can
   * be showing another page, and the tap asks for the screen that holds the
   * connect control.
   */
  private showMainScreen(): void {
    if (this.windowStage === null) {
      return;
    }
    this.windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }
}
