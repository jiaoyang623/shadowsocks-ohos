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

import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ConnectionNotification';

/** Fixed, so that publishing again replaces what is there. */
const NOTIFICATION_ID = 1;

const BUNDLE = 'com.xbt.project';
const ENTRY_ABILITY = 'EntryAbility';

/**
 * The action the notification's button carries. It is read back by
 * `EntryAbility`, which is the process that can stop the extension.
 */
export const ACTION_DISCONNECT = 'com.xbt.project.disconnect';

/**
 * The button's action, built once and kept. Rebuilding it on every traffic
 * update would allocate a want agent per second for no reason.
 */
let cachedAgent: WantAgent | undefined = undefined;

async function disconnectAgent(): Promise<WantAgent> {
  if (cachedAgent === undefined) {
    cachedAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: BUNDLE,
        abilityName: ENTRY_ABILITY,
        action: ACTION_DISCONNECT,
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
  }
  return cachedAgent;
}

/**
 * An ongoing notification while the tunnel is up, with a way out of it.
 *
 * The tunnel outlives the app's window, so a user who has left the app has no
 * way back to the disconnect button without this. `detail` carries the live
 * traffic, as shadowsocks-android's notification does; calling again with the
 * same profile and a new detail is how that line is kept current.
 *
 * The context is here because the notification's fields take plain strings,
 * where a page would be handed a resource and let the framework resolve it.
 */
export async function showConnected(context: common.Context, profileName: string,
                                    detail: ResourceStr = ''): Promise<void> {
  try {
    const strings = context.resourceManager;
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: strings.getStringSync($r('app.string.app_name').id),
          text: profileName.length > 0
            ? strings.getStringSync($r('app.string.notification_connected_to').id, profileName)
            : strings.getStringSync($r('app.string.index_connected').id),
          additionalText: resolve(context, detail),
        },
      },
      // no slotType: the field is typed as the pre-9 `notification.SlotType`,
      // a different enum from `notificationManager.SlotType` even though the
      // values match, and leaving it out uses the app's default slot
      isOngoing: true,
      actionButtons: [{
        title: strings.getStringSync($r('app.string.index_disconnect').id),
        wantAgent: await disconnectAgent(),
      }],
    };
    // publishing again with the same id replaces what is there, which is how
    // the traffic line is kept up to date
    await notificationManager.publish(request);
  } catch (e) {
    // the notification is a convenience: a user who has turned notifications
    // off, or a platform that refuses them, must not stop the tunnel working
    const err = e as BusinessError;
    hilog.warn(0x0000, TAG, 'could not publish the connection notification: %{public}s',
      err.message ?? JSON.stringify(e));
  }
}

/** A resource as the text it stands for, for a field that takes a string. */
function resolve(context: common.Context, value: ResourceStr): string {
  return typeof value === 'string'
    ? value
    : context.resourceManager.getStringSync(value.id);
}

/** Takes the notification away, whether or not one was published. */
export async function clear(): Promise<void> {
  try {
    await notificationManager.cancel(NOTIFICATION_ID);
  } catch (e) {
    hilog.warn(0x0000, TAG, 'could not cancel the connection notification');
  }
}
