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
import { AppSettings, AppSettingsJson, settingsFromJson } from './Diagnostics';

const STORE_SETTINGS = 'settings';

/**
 * Persists the two diagnostic endpoints the user can override. Kept in its own
 * file rather than folded into ProfileStore: these are app-wide, not per
 * profile, and the VPN extension process has no reason to read them.
 *
 * Reading never fails — an absent or corrupt file yields the defaults, so the
 * UI can always render something usable.
 */
export class SettingsStore {
  static async load(context: common.Context): Promise<AppSettings> {
    const raw = await JsonStore.read(context, STORE_SETTINGS);
    if (raw.length === 0) {
      return settingsFromJson(null);
    }
    try {
      return settingsFromJson(JSON.parse(raw) as AppSettingsJson);
    } catch (e) {
      return settingsFromJson(null);
    }
  }

  static async save(context: common.Context, settings: AppSettings): Promise<void> {
    await JsonStore.write(context, STORE_SETTINGS, JSON.stringify(settings));
  }
}
