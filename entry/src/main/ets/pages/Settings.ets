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

import { promptAction, router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityContext } from '../model/AppContext';
import { AppSettings, DEFAULT_PROBE_URL, DEFAULT_SPEED_URL } from '../model/Diagnostics';
import { SettingsStore } from '../model/Settings';

const TAG = 'Settings';

/**
 * Diagnostics settings: the two endpoints the connection test and the speed
 * test talk to. Both are editable because neither default is right in every
 * situation — under the `gfwlist` and `china-list` routes a foreign host is
 * reached directly rather than through the tunnel, so a user on those routes
 * needs to point the probe at something their route actually proxies.
 */
@Entry
@Component
struct Settings {
  @State probeUrl: string = '';
  @State speedTestUrl: string = '';

  aboutToAppear(): void {
    SettingsStore.load(abilityContext()).then((settings: AppSettings) => {
      this.probeUrl = settings.probeUrl;
      this.speedTestUrl = settings.speedTestUrl;
    });
  }

  private async save(): Promise<void> {
    const settings: AppSettings = {
      // a blank field means "use the default", not "probe nothing"
      probeUrl: this.probeUrl.trim().length > 0 ? this.probeUrl.trim() : DEFAULT_PROBE_URL,
      speedTestUrl: this.speedTestUrl.trim().length > 0 ? this.speedTestUrl.trim() : DEFAULT_SPEED_URL,
    };
    try {
      await SettingsStore.save(abilityContext(), settings);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save failed: %{public}s', err.message ?? String(e));
      promptAction.showToast({ message: `Save failed: ${err.message ?? String(e)}` });
      return;
    }
    router.back();
  }

  @Builder
  Field(label: string, hint: string, value: string, onEdit: (text: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#616161')
        .width('100%')
      TextInput({ placeholder: hint, text: value })
        .fontSize(14)
        .onChange((text: string) => onEdit(text))
      Text(hint)
        .fontSize(11)
        .fontColor('#9E9E9E')
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('‹ Back')
          .fontSize(16)
          .fontColor('#3F51B5')
          .onClick(() => router.back())
        Text('Settings')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      this.Field('Connection test URL',
        'Must return 2xx; used to confirm traffic really reaches the internet '
          + 'through the tunnel. Default: ' + DEFAULT_PROBE_URL,
        this.probeUrl, (text: string) => {
          this.probeUrl = text;
        })

      this.Field('Speed test URL',
        'Downloaded in full and timed. Default: ' + DEFAULT_SPEED_URL,
        this.speedTestUrl, (text: string) => {
          this.speedTestUrl = text;
        })

      Row({ space: 12 }) {
        Button('Reset to defaults')
          .backgroundColor('#9E9E9E')
          .layoutWeight(1)
          .onClick(() => {
            this.probeUrl = DEFAULT_PROBE_URL;
            this.speedTestUrl = DEFAULT_SPEED_URL;
          })
        Button('Save')
          .layoutWeight(1)
          .onClick(() => this.save())
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
