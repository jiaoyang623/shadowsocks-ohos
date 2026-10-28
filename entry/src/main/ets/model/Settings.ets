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
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JsonStore } from './JsonStore';
import {
  AppSettings, AppSettingsJson, settingsFromJson, settingsJsonFrom, settingsNeedSeed,
} from './Diagnostics';

const TAG = 'Settings';
const STORE_SETTINGS = 'settings';

/**
 * Persists the app-wide settings: the two diagnostic endpoints, the service
 * mode, the two port texts, and the two switches.
 *
 * Reading never fails. An absent or corrupt file yields the defaults, so the
 * UI can always render something usable. The VPN extension reads the local DNS
 * port through `load` before a start. Only the UI process calls `loadSeeded`,
 * because the extension must not write the store.
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

  /**
   * Loads the settings and writes the keys the file lacks. This is the
   * settings page path only. The VPN extension calls `load`.
   *
   * A file that exists but cannot be read or parsed is left alone. Writing the
   * defaults over it would destroy the values it holds.
   */
  static async loadSeeded(context: common.Context): Promise<AppSettings> {
    const present = JsonStore.exists(context, STORE_SETTINGS);
    const raw = await JsonStore.read(context, STORE_SETTINGS);
    let parsed: AppSettingsJson | null = null;
    let parseFailed = false;
    if (raw.length > 0) {
      try {
        parsed = JSON.parse(raw) as AppSettingsJson;
      } catch (e) {
        parseFailed = true;
      }
    }
    const settings = settingsFromJson(parsed);
    const seed = !present || (raw.length > 0 && !parseFailed && settingsNeedSeed(parsed));
    if (seed) {
      try {
        await JsonStore.write(context, STORE_SETTINGS, JSON.stringify(settingsJsonFrom(settings)));
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(0x0000, TAG, 'seed failed: %{public}s', err.message ?? String(e));
      }
    }
    return settings;
  }

  static async save(context: common.Context, settings: AppSettings): Promise<void> {
    await JsonStore.write(context, STORE_SETTINGS, JSON.stringify(settings));
  }
}
