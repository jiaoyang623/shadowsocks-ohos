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
import {
  AppSettings, DEFAULT_LOCAL_DNS_PORT, DEFAULT_PROBE_URL, DEFAULT_PROXY_PORT,
  DEFAULT_SPEED_URL, advancedSummaryRows, isServiceStopped, MODE_PROXY, MODE_VPN,
  portSummary, PORT_UNSET, sanitizePortInput, serviceModeEntry,
  SETTINGS_ROW_AUTO_CONNECT, SETTINGS_ROW_LOCAL_DNS_PORT, SETTINGS_ROW_PROXY_PORT,
  SETTINGS_ROW_SERVICE_MODE, VpnStatus,
} from '../model/Diagnostics';
import { ProxyService } from '../model/ProxyService';
import { SettingsStore } from '../model/Settings';
import { TrafficStatsStore } from '../model/TrafficStats';
import { VpnStatusStore } from '../model/VpnStatus';

const TAG = 'Settings';
/** The gating poll period, in milliseconds. */
const STATE_POLL_INTERVAL_MS: number = 1000;

/**
 * Global settings: the service rows of the Android settings screen, then the
 * diagnostics endpoints.
 *
 * A row writes the store as soon as it changes. One write stores the current
 * page state of every field, so an unsaved URL edit is stored by the next
 * control write. The rows that a live service locks follow a poll of the VPN
 * status file, the traffic sample, and the proxy state.
 *
 * The diagnostics fields stay below the settings rows. Both endpoints are
 * editable because neither default is right in every situation. Under the
 * `gfwlist` and `china-list` routes a foreign host is reached directly rather
 * than through the tunnel, so a user on those routes needs to point the probe
 * at something their route actually proxies.
 */
@Entry
@Component
struct Settings {
  @State probeUrl: string = '';
  @State speedTestUrl: string = '';
  @State serviceMode: string = MODE_VPN;
  @State proxyPort: string = `${DEFAULT_PROXY_PORT}`;
  @State localDnsPort: string = `${DEFAULT_LOCAL_DNS_PORT}`;
  @State autoConnect: boolean = false;
  @State shareOverLan: boolean = false;
  @State expanded: boolean = false;
  @State serviceStopped: boolean = false;

  private stateTimer: number = -1;
  private polling: boolean = false;
  private portDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.refresh();
    this.startStatePolling();
  }

  onPageShow(): void {
    this.startStatePolling();
    this.pollServiceState();
  }

  onPageHide(): void {
    this.stopStatePolling();
  }

  aboutToDisappear(): void {
    this.stopStatePolling();
  }

  /** Loads the store and seeds the keys an older file lacks. */
  private async refresh(): Promise<void> {
    const settings = await SettingsStore.loadSeeded(abilityContext());
    this.probeUrl = settings.probeUrl;
    this.speedTestUrl = settings.speedTestUrl;
    this.serviceMode = settings.serviceMode;
    this.proxyPort = settings.proxyPort;
    this.localDnsPort = settings.localDnsPort;
    this.autoConnect = settings.autoConnect;
    this.shareOverLan = settings.shareOverLan;
  }

  private startStatePolling(): void {
    this.stopStatePolling();
    this.stateTimer = setInterval(async () => {
      if (this.polling) {
        return;
      }
      this.polling = true;
      try {
        await this.pollServiceState();
      } finally {
        this.polling = false;
      }
    }, STATE_POLL_INTERVAL_MS);
  }

  private stopStatePolling(): void {
    if (this.stateTimer >= 0) {
      clearInterval(this.stateTimer);
      this.stateTimer = -1;
    }
  }

  /**
   * Reads the service state. A recent status record, a live sample, or a
   * running proxy keeps the service rows locked.
   */
  private async pollServiceState(): Promise<void> {
    const context = abilityContext();
    const status: VpnStatus | null = await VpnStatusStore.load(context);
    const stats = await TrafficStatsStore.load(context);
    const statsTimestamp = stats !== null ? stats.timestamp : 0;
    this.serviceStopped = isServiceStopped(status, statsTimestamp, Date.now(),
      ProxyService.isRunning());
  }

  /** The settings object the page would store now. */
  private settingsValue(): AppSettings {
    const settings: AppSettings = {
      // a blank field selects the default endpoint
      probeUrl: this.probeUrl.trim().length > 0 ? this.probeUrl.trim() : DEFAULT_PROBE_URL,
      speedTestUrl: this.speedTestUrl.trim().length > 0 ?
        this.speedTestUrl.trim() : DEFAULT_SPEED_URL,
      serviceMode: this.serviceMode,
      proxyPort: this.proxyPort,
      localDnsPort: this.localDnsPort,
      autoConnect: this.autoConnect,
      shareOverLan: this.shareOverLan,
    };
    return settings;
  }

  /** Writes the page state. Returns false and shows a toast on failure. */
  private async persist(): Promise<boolean> {
    try {
      await SettingsStore.save(abilityContext(), this.settingsValue());
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save failed: %{public}s', err.message ?? String(e));
      promptAction.showToast({
        message: $r('app.string.common_save_failed', err.message ?? String(e)),
      });
      return false;
    }
  }

  private async save(): Promise<void> {
    const ok = await this.persist();
    if (ok) {
      router.back();
    }
  }

  /** Stores a new service mode. A failed write restores the old one. */
  private async chooseMode(mode: string): Promise<void> {
    if (mode === this.serviceMode) {
      return;
    }
    const previous = this.serviceMode;
    this.serviceMode = mode;
    const ok = await this.persist();
    if (!ok) {
      this.serviceMode = previous;
    }
  }

  /** Stores the Auto Connect switch. A failed write restores the old value. */
  private async toggleAutoConnect(on: boolean): Promise<void> {
    if (on === this.autoConnect) {
      return;
    }
    const previous = this.autoConnect;
    this.autoConnect = on;
    const ok = await this.persist();
    if (!ok) {
      this.autoConnect = previous;
    }
  }

  /** Stores the share-over-LAN switch. A failed write restores the old value. */
  private async toggleShareOverLan(on: boolean): Promise<void> {
    if (on === this.shareOverLan) {
      return;
    }
    const previous = this.shareOverLan;
    this.shareOverLan = on;
    const ok = await this.persist();
    if (!ok) {
      this.shareOverLan = previous;
    }
  }

  /**
   * Stores a port text. The text stays as typed, so an empty text means Not
   * set. A failed write restores the old text.
   */
  private async applyPort(row: string, text: string): Promise<void> {
    if (row !== SETTINGS_ROW_PROXY_PORT && row !== SETTINGS_ROW_LOCAL_DNS_PORT) {
      return;
    }
    const next = sanitizePortInput(text);
    const isProxy = row === SETTINGS_ROW_PROXY_PORT;
    const current = isProxy ? this.proxyPort : this.localDnsPort;
    if (next === current) {
      return;
    }
    if (isProxy) {
      this.proxyPort = next;
    } else {
      this.localDnsPort = next;
    }
    const ok = await this.persist();
    if (!ok) {
      if (isProxy) {
        this.proxyPort = current;
      } else {
        this.localDnsPort = current;
      }
    }
  }

  /** Opens the port dialog. A locked row does not open it. */
  private openPortDialog(row: string): void {
    if (!this.serviceStopped) {
      return;
    }
    const initial = row === SETTINGS_ROW_PROXY_PORT ? this.proxyPort : this.localDnsPort;
    const dialog = new CustomDialogController({
      builder: PortDialog({
        title: this.rowTitle(row),
        initial: initial,
        onConfirm: (text: string) => {
          this.applyPort(row, text);
        },
      }),
      autoCancel: true,
    });
    this.portDialog = dialog;
    dialog.open();
  }

  /** The plain text of a resource, for the strings the page joins. */
  private text(value: ResourceStr): string {
    return typeof value === 'string'
      ? value
      : abilityContext().resourceManager.getStringSync(value.id);
  }

  private rowTitle(row: string): ResourceStr {
    if (row === SETTINGS_ROW_AUTO_CONNECT) {
      return $r('app.string.settings_auto_connect');
    }
    if (row === SETTINGS_ROW_SERVICE_MODE) {
      return $r('app.string.settings_service_mode');
    }
    if (row === SETTINGS_ROW_PROXY_PORT) {
      return $r('app.string.settings_socks_port');
    }
    if (row === SETTINGS_ROW_LOCAL_DNS_PORT) {
      return $r('app.string.settings_local_dns_port');
    }
    return '';
  }

  /** The summaries of the hidden rows, joined for the Advanced row. */
  private advancedSummary(): string {
    const rows = advancedSummaryRows();
    return rows.map((row: string) => this.text(this.rowTitle(row))).join(', ');
  }

  /** The summary of the service mode row. */
  private modeSummary(): ResourceStr {
    const entry = serviceModeEntry(this.serviceMode);
    if (entry === MODE_VPN) {
      return $r('app.string.settings_vpn');
    }
    if (entry === MODE_PROXY) {
      return $r('app.string.settings_proxy');
    }
    return $r('app.string.settings_not_set');
  }

  /** The summary of a port row. */
  private portSummaryText(text: string): ResourceStr {
    return text === PORT_UNSET ? $r('app.string.settings_not_set') : text;
  }

  /** A menu label with a check mark on the stored entry. */
  private modeMenuLabel(mode: string): string {
    const label = mode === MODE_VPN
      ? this.text($r('app.string.settings_vpn'))
      : this.text($r('app.string.settings_proxy'));
    return mode === serviceModeEntry(this.serviceMode) ? `✓ ${label}` : label;
  }

  /** Whether a summary holds no text. */
  private isEmptyText(value: ResourceStr): boolean {
    return typeof value === 'string' && value.length === 0;
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

  /** One settings row with a title, a summary, and a chevron. */
  @Builder
  SettingsRow(title: ResourceStr, summary: ResourceStr, enabled: boolean,
    onTap: () => void) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor(enabled ? $r('app.color.text_body') : $r('app.color.text_secondary'))
          .width('100%')
        Text(summary)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
    .enabled(enabled)
    .onClick(onTap)
  }

  /** One settings row with a switch. A row tap flips the switch. */
  @Builder
  SwitchRow(title: ResourceStr, summary: ResourceStr, isOn: boolean, enabled: boolean,
    onChange: (on: boolean) => void) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor(enabled ? $r('app.color.text_body') : $r('app.color.text_secondary'))
          .width('100%')
        if (!this.isEmptyText(summary)) {
          Text(summary)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .enabled(enabled)
        .onChange((on: boolean) => onChange(on))
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
    .enabled(enabled)
    .onClick(() => onChange(!isOn))
  }

  /** The service mode row. A tap opens the mode menu. */
  @Builder
  ModeRow(title: ResourceStr, summary: ResourceStr, enabled: boolean) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor(enabled ? $r('app.color.text_body') : $r('app.color.text_secondary'))
          .width('100%')
        Text(summary)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
    .enabled(enabled)
    .bindMenu(this.ModeMenu())
  }

  /** The two service modes, in the Android menu order. */
  @Builder
  ModeMenu() {
    Menu() {
      MenuItem({ content: this.modeMenuLabel(MODE_PROXY) })
        .onClick(() => {
          this.chooseMode(MODE_PROXY);
        })
      MenuItem({ content: this.modeMenuLabel(MODE_VPN) })
        .onClick(() => {
          this.chooseMode(MODE_VPN);
        })
    }
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
        this.SwitchRow($r('app.string.settings_auto_connect'),
          $r('app.string.settings_auto_connect_summary'),
          this.autoConnect, true, (on: boolean) => {
            this.toggleAutoConnect(on);
          })

        if (!this.expanded) {
          this.SettingsRow($r('app.string.settings_advanced'), this.advancedSummary(), true,
            () => {
              this.expanded = true;
            })
        }

        if (this.expanded) {
          this.ModeRow($r('app.string.settings_service_mode'), this.modeSummary(),
            this.serviceStopped)
          this.SettingsRow($r('app.string.settings_socks_port'),
            this.portSummaryText(portSummary(this.proxyPort)), this.serviceStopped, () => {
              this.openPortDialog(SETTINGS_ROW_PROXY_PORT);
            })
          this.SettingsRow($r('app.string.settings_local_dns_port'),
            this.portSummaryText(portSummary(this.localDnsPort)), this.serviceStopped, () => {
              this.openPortDialog(SETTINGS_ROW_LOCAL_DNS_PORT);
            })
        }

        if (this.expanded && this.serviceMode === MODE_PROXY) {
          Text($r('app.string.settings_proxy_explainer'))
            .fontSize(12)
            .fontColor($r('app.color.text_body'))
          this.SwitchRow($r('app.string.settings_allow_other_devices'), '',
            this.shareOverLan, this.serviceStopped, (on: boolean) => {
              this.toggleShareOverLan(on);
            })
          if (this.shareOverLan) {
            Text($r('app.string.settings_share_warning'))
              .fontSize(12)
              .fontColor($r('app.color.error_strong'))
          }
        }
      }
      .width('100%')

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

/**
 * The port editor. The input keeps digits only and at most five of them.
 * OK stores the text. Cancel writes nothing.
 */
@CustomDialog
struct PortDialog {
  controller: CustomDialogController;
  title: ResourceStr = '';
  initial: string = '';
  onConfirm: (text: string) => void = () => {
  };
  @State text: string = '';

  aboutToAppear(): void {
    this.text = this.initial;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      TextInput({ placeholder: $r('app.string.settings_port_number'), text: this.text })
        .type(InputType.Number)
        .maxLength(5)
        .onChange((value: string) => this.text = sanitizePortInput(value))
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .onClick(() => {
            this.onConfirm(this.text);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
  }
}
