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
import { ACTION_DISCONNECT } from '../model/ConnectionNotification';
import { settleSessionTraffic } from '../model/SessionTraffic';

const TAG = 'EntryAbility';

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
  // the extension's own teardown is cut off by the platform, so the session's
  // counters are written here before the process that sampled them goes away
  await settleSessionTraffic(context);
  vpnExtension.stopVpnExtensionAbility(VPN_ABILITY).catch((e: BusinessError) => {
    hilog.warn(0x0000, TAG, 'could not stop the VPN extension: %{public}s', e.message ?? '');
  });
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    setAbilityContext(this.context);
    handleAction(want, this.context);
    takeImportUri(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // the ability is already up: a link from a browser, or the notification's
    // button, arrives here
    handleAction(want, this.context);
    takeImportUri(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
      }
    });
  }
}
