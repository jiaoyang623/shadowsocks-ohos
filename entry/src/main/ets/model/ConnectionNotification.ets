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
import { NotificationText, notificationText } from './NotificationContent';

const TAG = 'ConnectionNotification';

/** Fixed, so that publishing again replaces what is there. */
const NOTIFICATION_ID = 1;

const BUNDLE = 'com.xbt.project';
const ENTRY_ABILITY = 'EntryAbility';

/** The action the notification body carries. `EntryAbility` opens the main screen. */
export const ACTION_OPEN = 'com.xbt.project.open';

/**
 * The action the notification's button carries. It is read back by
 * `EntryAbility`, which is the process that can stop the extension.
 */
export const ACTION_DISCONNECT = 'com.xbt.project.disconnect';

/** The body tap's action, built once and kept. */
let cachedOpenAgent: WantAgent | undefined = undefined;

/**
 * The body tap. The notification opens the app.
 *
 * The agent is cached because the traffic line publishes every two seconds. A
 * new agent per publish would allocate for no reason.
 */
async function openAgent(): Promise<WantAgent> {
  if (cachedOpenAgent === undefined) {
    cachedOpenAgent = await wantAgent.getWantAgent({
      wants: [{
        bundleName: BUNDLE,
        abilityName: ENTRY_ABILITY,
        action: ACTION_OPEN,
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
  }
  return cachedOpenAgent;
}

/** The button's action, built once and kept. */
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
 * The Stop button, or no button when its agent cannot be built.
 *
 * The public SDK has no static subscriber ability for an app-scoped broadcast.
 * The button therefore starts `EntryAbility`. The app opens, and the ability
 * stops the extension.
 */
async function stopButtons(context: common.Context):
    Promise<notificationManager.NotificationActionButton[]> {
  try {
    const title: string =
      context.resourceManager.getStringSync($r('app.string.notification_stop').id);
    const button: notificationManager.NotificationActionButton = {
      title: title,
      wantAgent: await disconnectAgent(),
    };
    return [button];
  } catch (e) {
    const err = e as BusinessError;
    hilog.warn(0x0000, TAG, 'could not build the notification stop button: %{public}s',
      err.message ?? '');
    return [];
  }
}

/**
 * Publishes one request. A platform that reports notifications off answers
 * 110004, so the function asks for them once and tries again.
 */
async function publishRequest(context: common.Context,
                              request: notificationManager.NotificationRequest): Promise<void> {
  try {
    await notificationManager.publish(request);
  } catch (e) {
    const err = e as BusinessError;
    // 110004 means notifications are off. A fresh install starts that way.
    if (err.code !== 110004) {
      hilog.warn(0x0000, TAG, 'could not publish the connection notification: %{public}s',
        err.message ?? JSON.stringify(e));
      return;
    }
    // Ask once, then try once. Log only when the retry also fails.
    await ensureEnabled(context as common.UIAbilityContext);
    try {
      await notificationManager.publish(request);
    } catch (e2) {
      const retry = e2 as BusinessError;
      hilog.warn(0x0000, TAG, 'could not publish the connection notification: %{public}s',
        retry.message ?? JSON.stringify(e2));
    }
  }
}

/**
 * Publishes the connection notification under one fixed id.
 *
 * A failed publish is logged and does not stop the tunnel. The notification is
 * a convenience. A user who turned notifications off still gets the tunnel.
 *
 * The body tap and the Stop button are each optional. A failed agent call
 * removes its field, and the notification still publishes.
 */
async function publish(context: common.Context, title: string, text: string,
                       totals: string): Promise<void> {
  try {
    let tapAgent: WantAgent | undefined = undefined;
    try {
      tapAgent = await openAgent();
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'could not build the notification body tap: %{public}s',
        err.message ?? '');
    }
    const buttons: notificationManager.NotificationActionButton[] = await stopButtons(context);
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
          additionalText: totals,
        },
      },
      tapDismissed: false,
      isOngoing: true,
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      actionButtons: buttons,
    };
    if (tapAgent !== undefined) {
      request.wantAgent = tapAgent;
    }
    // A publish with the same id replaces the old notification. That is how
    // the traffic line stays current.
    await publishRequest(context, request);
  } catch (e) {
    // A user who disabled notifications, or a platform that refuses them,
    // must not stop the tunnel working. The notification is a convenience.
    const err = e as BusinessError;
    hilog.warn(0x0000, TAG, 'could not build the connection notification: %{public}s',
      err.message ?? JSON.stringify(e));
  }
}

/**
 * An ongoing notification while the tunnel is up.
 *
 * The tunnel outlives the app's window. A user who has left the app needs a
 * control that stops the tunnel. This notification is that control. The title
 * is the profile name. `detail` is the live traffic line. `totals` is the
 * session counters line. A later call with new values replaces the old
 * notification because the id is fixed.
 *
 * The body tap opens the main screen. The Stop button starts `EntryAbility`
 * with `ACTION_DISCONNECT`. The ability stops the extension, and the extension
 * removes the notification in `onDestroy`.
 *
 * The notification fields take plain strings. A page would be handed a
 * resource and let the framework resolve it. The context is here for that
 * reason.
 */
export async function showConnected(context: common.Context, profileName: string,
                                    detail: ResourceStr = '',
                                    totals: ResourceStr = ''): Promise<void> {
  const strings = context.resourceManager;
  const appName: string = strings.getStringSync($r('app.string.app_name').id);
  const connected: string = strings.getStringSync($r('app.string.index_connected').id);
  const content: NotificationText = notificationText(profileName, appName, connected,
    resolve(context, detail), resolve(context, totals));
  await publish(context, content.title, content.text, content.totals);
}

/**
 * The notification of a start that has no profile yet.
 *
 * A start can fail before it reads a profile. The user sees that the start is
 * in progress. A failure removes the notification at once.
 */
export async function showStarting(context: common.Context): Promise<void> {
  const strings = context.resourceManager;
  const appName: string = strings.getStringSync($r('app.string.app_name').id);
  const connecting: string = strings.getStringSync($r('app.string.index_connecting').id);
  await publish(context, appName, connecting, '');
}

/**
 * A resource as the text it stands for, for a field that takes a string.
 *
 * The parameters go with the id. A formatted resource such as the traffic
 * line would otherwise come out as its raw `%s` template.
 */
function resolve(context: common.Context, value: ResourceStr): string {
  if (typeof value === 'string') {
    return value;
  }
  const params: Array<string | number> | undefined = value.params;
  if (params === undefined) {
    return context.resourceManager.getStringSync(value.id);
  }
  const args: string[] = [];
  for (const param of params) {
    args.push(`${param}`);
  }
  return context.resourceManager.getStringSync(value.id, ...args);
}

/**
 * Asks for leave to show notifications, once, before the tunnel starts.
 *
 * A freshly installed app has notifications disabled. The platform then drops
 * every publish without a word. The notification is the only control that
 * stops the tunnel after the app's window is gone. A dropped publish removes
 * that control without a message.
 *
 * The answer decides nothing here. A user who refuses still gets the tunnel.
 * The user must open the app to stop it.
 */
export async function ensureEnabled(context: common.UIAbilityContext): Promise<void> {
  try {
    if (await notificationManager.isNotificationEnabled()) {
      return;
    }
    await notificationManager.requestEnableNotification(context);
  } catch (e) {
    // The request is refused when the user has already answered it. A second
    // ask is not an error worth reporting.
    hilog.info(0x0000, TAG, 'notifications are not enabled');
  }
}

/** Takes the notification away, whether or not one was published. */
export async function clear(): Promise<void> {
  try {
    await notificationManager.cancel(NOTIFICATION_ID);
  } catch (e) {
    hilog.warn(0x0000, TAG, 'could not cancel the connection notification');
  }
}
