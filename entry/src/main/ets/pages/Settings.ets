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
import { AppSettings, DEFAULT_PROBE_URL, DEFAULT_PROXY_PORT, DEFAULT_SPEED_URL, MODE_PROXY, MODE_VPN } from '../model/Diagnostics';
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
  @State serviceMode: string = MODE_VPN;
  @State proxyPort: string = `${DEFAULT_PROXY_PORT}`;
  @State shareOverLan: boolean = false;

  aboutToAppear(): void {
    SettingsStore.load(abilityContext()).then((settings: AppSettings) => {
      this.probeUrl = settings.probeUrl;
      this.speedTestUrl = settings.speedTestUrl;
      this.serviceMode = settings.serviceMode;
      this.proxyPort = `${settings.proxyPort}`;
      this.shareOverLan = settings.shareOverLan;
    });
  }

  private async save(): Promise<void> {
    const port = Number.parseInt(this.proxyPort, 10);
    const settings: AppSettings = {
      // a blank field means "use the default", not "probe nothing"
      probeUrl: this.probeUrl.trim().length > 0 ? this.probeUrl.trim() : DEFAULT_PROBE_URL,
      speedTestUrl: this.speedTestUrl.trim().length > 0 ? this.speedTestUrl.trim() : DEFAULT_SPEED_URL,
      serviceMode: this.serviceMode,
      proxyPort: Number.isNaN(port) || port <= 0 || port > 65535 ? DEFAULT_PROXY_PORT : port,
      shareOverLan: this.shareOverLan,
    };
    try {
      await SettingsStore.save(abilityContext(), settings);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save failed: %{public}s', err.message ?? String(e));
      promptAction.showToast({ message: $r('app.string.common_save_failed', err.message ?? String(e)) });
      return;
    }
    router.back();
  }

  @Builder
  Field(label: ResourceStr, hint: ResourceStr, value: string, onEdit: (text: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_body'))
        .width('100%')
      TextInput({ placeholder: hint, text: value })
        .fontSize(14)
        .onChange((text: string) => onEdit(text))
      Text(hint)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => router.back())
        Text($r('app.string.settings_settings'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Column({ space: 8 }) {
        Text($r('app.string.settings_service_mode'))
          .fontSize(13)
          .fontColor($r('app.color.text_body'))
        Row({ space: 8 }) {
          Button($r('app.string.settings_vpn'))
            .layoutWeight(1)
            .backgroundColor(this.serviceMode === MODE_VPN
              ? $r('app.color.accent_container')
              : $r('app.color.button_neutral'))
            .fontColor(this.serviceMode === MODE_VPN
              ? $r('app.color.on_container')
              : $r('app.color.on_neutral'))
            .onClick(() => this.serviceMode = MODE_VPN)
          Button($r('app.string.settings_proxy'))
            .layoutWeight(1)
            .backgroundColor(this.serviceMode === MODE_PROXY
              ? $r('app.color.accent_container')
              : $r('app.color.button_neutral'))
            .fontColor(this.serviceMode === MODE_PROXY
              ? $r('app.color.on_container')
              : $r('app.color.on_neutral'))
            .onClick(() => this.serviceMode = MODE_PROXY)
        }
        .width('100%')
        if (this.serviceMode === MODE_PROXY) {
          Text($r('app.string.settings_proxy_explainer'))
            .fontSize(12)
            .fontColor($r('app.color.text_body'))
          TextInput({ placeholder: $r('app.string.settings_socks_port', DEFAULT_PROXY_PORT), text: this.proxyPort })
            .type(InputType.Number)
            .onChange((value) => this.proxyPort = value)
          Row() {
            Text($r('app.string.settings_allow_other_devices'))
              .fontSize(14)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.shareOverLan })
              .onChange((on: boolean) => this.shareOverLan = on)
          }
          .width('100%')
          if (this.shareOverLan) {
            Text($r('app.string.settings_share_warning'))
              .fontSize(12)
              .fontColor($r('app.color.error_strong'))
          }
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor($r('app.color.surface'))

      this.Field($r('app.string.settings_connection_test_url'),
        $r('app.string.settings_connection_test_url_hint', DEFAULT_PROBE_URL),
        this.probeUrl, (text: string) => {
          this.probeUrl = text;
        })

      this.Field($r('app.string.settings_speed_test_url'),
        $r('app.string.settings_speed_test_url_hint', DEFAULT_SPEED_URL),
        this.speedTestUrl, (text: string) => {
          this.speedTestUrl = text;
        })

      Row({ space: 12 }) {
        Button($r('app.string.settings_custom_rules'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/CustomRules' });
          })
        Button($r('app.string.about_about'))
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .layoutWeight(1)
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
        Button($r('app.string.settings_reset_to_defaults'))
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .layoutWeight(1)
          .onClick(() => {
            this.probeUrl = DEFAULT_PROBE_URL;
            this.speedTestUrl = DEFAULT_SPEED_URL;
          })
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .onClick(() => this.save())
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}
