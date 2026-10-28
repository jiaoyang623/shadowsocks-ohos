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

import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ABOUT_LINK_EMAIL, ABOUT_LINK_OSS, classifyAboutLink } from './AboutLinks';

/**
 * The About page link opener.
 *
 * The adapter starts the app that handles a web or mail link. The About page
 * classifies the link first, so an in-page anchor never reaches this file.
 */

const TAG = 'AboutOpener';

/** The system accepted the link and opened a handler for it. */
export const ABOUT_OPENED: string = 'opened';
/** No installed app can open the link. */
export const ABOUT_NO_HANDLER: string = 'no_handler';
/** The link points into a screen this app does not have. */
export const ABOUT_UNSUPPORTED: string = 'unsupported';

/**
 * Opens one About page link and reports what happened.
 *
 * The caller shows the raw URL when no handler answers. The action strings
 * are the documented Want actions, written out so the code also runs on
 * API 12.
 */
export async function openAboutLink(context: common.UIAbilityContext,
                                    url: string): Promise<string> {
  const kind: string = classifyAboutLink(url);
  if (kind === ABOUT_LINK_OSS) {
    return ABOUT_UNSUPPORTED;
  }
  const want: Want = kind === ABOUT_LINK_EMAIL
    ? { action: 'ohos.want.action.sendToData', uri: url }
    : { action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url };
  try {
    await context.startAbility(want);
    return ABOUT_OPENED;
  } catch (e) {
    const err = e as Error;
    hilog.warn(0x0000, TAG, 'could not open %{public}s: %{public}s', url, err.message ?? '');
    return ABOUT_NO_HANDLER;
  }
}
