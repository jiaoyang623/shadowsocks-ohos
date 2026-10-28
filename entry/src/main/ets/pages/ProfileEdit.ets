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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEFAULT_REMOTE_DNS, Profile, newManualProfile, normalizeRemotePort } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { abilityContext, takePendingFallback } from '../model/AppContext';
import { ALL_ROUTES, ROUTE_ALL } from '../model/Routes';
import { AppSettings, MODE_VPN, ipv6SwitchEnabled } from '../model/Diagnostics';
import { SettingsStore } from '../model/Settings';
import { PerAppDraft, namesOf } from '../model/PerApp';
import {
  PLUGIN_OBFS_LOCAL, PLUGIN_OPTIONS_CONTROL, PLUGIN_OPTIONS_OBFS_MODE,
  PLUGIN_OPTIONS_OK, PLUGIN_OPTIONS_V2RAY_MODE, PLUGIN_STATE_KNOWN,
  PLUGIN_STATE_UNKNOWN, PLUGIN_V2RAY, PluginChoice, PluginDefinition, PluginOptions,
  findPlugin, pluginChoices, pluginStateOf,
} from '../model/PluginOptions';
import { fallbackSummary } from '../model/UdpFallback';
import { EditParams, ROUTE_LABELS } from './Index';
import { QrParams } from './ProfileQr';
import { AppPickerParams } from './AppPicker';
import { UdpFallbackParams } from './UdpFallback';

/** The AEAD methods the native core accepts, in the picker order. */
const METHODS: string[] = [
  'aes-128-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
];

/**
 * Profile editor, reached from the profile list and from the manual settings
 * item. The page edits one draft. Save writes the draft into the stored
 * profile. The close glyph discards the draft. The Back label and the system
 * back gesture ask before they discard.
 */
@Entry
@Component
struct ProfileEdit {
  @State profileId: string = '';
  @State name: string = '';
  @State host: string = '';
  @State remotePort: string = '8388';
  @State password: string = '';
  @State methodIndex: number = 1;
  @State methodCustom: string = '';
  @State routeIndex: number = 0;
  @State plugin: string = '';
  @State pluginOpts: string = '';
  @State pluginPickerShown: boolean = false;
  @State optionsDraft: string = '';
  @State remoteDns: string = DEFAULT_REMOTE_DNS;
  @State ipv6: boolean = false;
  @State metered: boolean = false;
  @State udpFallbackId: string = '';
  @State fallbackName: string = '';
  @State serviceMode: string = MODE_VPN;
  @State ready: boolean = false;
  @State proxyAppsEnabled: boolean = false;
  @State proxyAppsBypass: boolean = false;
  @State proxyAppsList: string = '';
  /**
   * Fields the form does not expose but that must survive an edit. Losing
   * `subscriptionId` would detach the profile from its subscription, and the
   * next subscription update would then re-add it as a duplicate.
   */
  private editedProfile: Profile | null = null;
  /**
   * A profile a subscription owns is read-only in the server fields, as in
   * Android: an update rewrites those fields, so an edit made here would be
   * lost without a word at the next refresh. Route, remote DNS, IPv6, and the
   * per-app settings stay editable.
   */
  @State readOnly: boolean = false;
  /** The form as it was loaded, to tell whether the user changed anything. */
  private initialForm: string = '';
  /**
   * True after the chooser hands back a choice. A tap on the checked row still
   * makes the draft dirty, as Android does.
   */
  @State fallbackTouched: boolean = false;
  /** The stored list, for the fallback summary and the chooser gate. */
  private allProfiles: Profile[] = [];
  /** The options of every plugin, keyed by plugin id. */
  private pluginConfigs: Record<string, string> = {};
  private optionsDialog: CustomDialogController = new CustomDialogController({
    builder: PluginOptionsDialog({
      draft: $optionsDraft,
      onCommit: (text: string) => this.commitPluginOptions(text),
    }),
    autoCancel: true,
  });

  aboutToAppear(): void {
    PerAppDraft.clear();
    const params = router.getParams() as EditParams | null;
    const id = params?.id ?? '';
    SettingsStore.load(abilityContext()).then((settings: AppSettings) => {
      this.serviceMode = settings.serviceMode;
    }).catch(() => {
      // Keep the VPN default. The IPv6 switch stays enabled.
    });
    if (id.length === 0) {
      // A launch without an id creates a manual profile form. The row is
      // written on Save.
      const manual = newManualProfile(null);
      this.applyProfile(manual);
      PerAppDraft.open(manual);
      this.syncPerApp();
      this.ready = true;
      this.initialForm = this.formSnapshot();
      return;
    }
    this.profileId = id;
    this.loadProfile(id);
  }

  /**
   * Loads the stored profile. A missing id closes the page before the form
   * draws. A failed read shows a message and closes the page.
   */
  private async loadProfile(id: string): Promise<void> {
    let profiles: Profile[] = [];
    try {
      profiles = await ProfileStore.getAll(abilityContext());
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.profile_edit_load_failed') });
      router.back();
      return;
    }
    this.allProfiles = profiles;
    const profile = profiles.find((candidate: Profile) => candidate.id === id);
    if (profile === undefined) {
      router.back();
      return;
    }
    this.editedProfile = profile;
    profile.normalizePluginOptions();
    this.applyProfile(profile);
    PerAppDraft.open(profile);
    this.syncPerApp();
    this.fallbackName = fallbackSummary(this.allProfiles, this.udpFallbackId);
    this.ready = true;
    this.initialForm = this.formSnapshot();
  }

  /** Copies a profile into the form fields. The id stays with the caller. */
  private applyProfile(profile: Profile): void {
    this.name = profile.name;
    this.host = profile.host;
    this.remotePort = profile.remotePort.toString();
    this.password = profile.password;
    const methodIndex = METHODS.indexOf(profile.method);
    this.methodIndex = methodIndex >= 0 ? methodIndex : -1;
    this.methodCustom = methodIndex >= 0 ? '' : profile.method;
    this.routeIndex = Math.max(0, ALL_ROUTES.indexOf(profile.route));
    this.plugin = profile.plugin;
    this.pluginOpts = profile.pluginOpts;
    this.pluginConfigs = this.copyConfigs(profile.pluginConfigs);
    this.remoteDns = profile.remoteDns;
    this.ipv6 = profile.ipv6;
    this.metered = profile.metered;
    this.udpFallbackId = profile.udpFallbackId;
    this.readOnly = profile.isSubscriptionLocked();
  }

  onPageShow(): void {
    // The stored profile load sets the form first. The chooser always follows
    // a loaded form, so a choice waits until the form is ready.
    if (this.ready && this.profileId.length > 0) {
      const choice = takePendingFallback(this.profileId);
      if (choice !== null) {
        this.udpFallbackId = choice;
        this.fallbackTouched = true;
        this.fallbackName = fallbackSummary(this.allProfiles, this.udpFallbackId);
      }
    }
    this.syncPerApp();
  }

  aboutToDisappear(): void {
    PerAppDraft.clear();
  }

  /** Every value the form can change, as one string to compare against. */
  private formSnapshot(): string {
    return [this.name, this.host, this.remotePort, this.password,
      this.selectedMethod(), this.routeIndex.toString(), this.plugin,
      this.pluginOpts, this.remoteDns, this.ipv6 ? '1' : '0', this.metered ? '1' : '0',
      this.udpFallbackId, this.pluginConfigSnapshot(), PerAppDraft.snapshot()].join('\u0001');
  }

  private isDirty(): boolean {
    return this.fallbackTouched || this.formSnapshot() !== this.initialForm;
  }

  /**
   * Leaving throws the form away, so anything typed is confirmed first, as
   * Android's unsaved-changes dialog does. Also used by the back arrow, which
   * would otherwise bypass `onBackPress`.
   */
  private async confirmLeave(): Promise<void> {
    if (!this.isDirty()) {
      PerAppDraft.clear();
      router.back();
      return;
    }
    try {
      // the promise overload does not survive the ArkTS checker when the
      // module is imported through @kit.ArkUI, so the callback form is wrapped
      const answer = await new Promise<promptAction.ShowDialogSuccessResponse>((resolve, reject) => {
        promptAction.showDialog({
          title: $r('app.string.profile_edit_unsaved_title'),
          message: $r('app.string.profile_edit_unsaved_message'),
          buttons: [
            { text: $r('app.string.common_cancel'), color: $r('app.color.text_body') },
            { text: $r('app.string.profile_edit_discard'), color: $r('app.color.error') },
            { text: $r('app.string.common_save'), color: $r('app.color.accent') },
          ],
        }, (err, data) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      if (answer.index === 1) {
        PerAppDraft.clear();
        router.back();
      } else if (answer.index === 2) {
        await this.save();
      }
    } catch (e) {
      // The dialog was dismissed. Stay on the form.
    }
  }

  onBackPress(): boolean {
    if (!this.isDirty()) {
      return false;
    }
    this.confirmLeave();
    return true;
  }

  private selectedMethod(): string {
    return this.methodIndex >= 0 ? METHODS[this.methodIndex] : this.methodCustom.trim();
  }

  /** True when the form holds enough to describe a server at all. */
  private isComplete(): boolean {
    return this.host.trim().length > 0 && this.password.length > 0
      && this.selectedMethod().length > 0;
  }

  /**
   * The profile the form describes, saved or not.
   *
   * An existing profile is edited in place. Every field that this form does not
   * show therefore survives instead of being reset. Those fields are the
   * subscription, the list position, and the counters.
   */
  private buildProfile(): Profile {
    const profile = this.editedProfile !== null ? this.editedProfile : new Profile();
    profile.id = this.profileId;
    profile.name = this.name.trim().length > 0 ? this.name.trim() : this.host.trim();
    profile.host = this.host.trim();
    profile.remotePort = normalizeRemotePort(this.remotePort);
    profile.password = this.password;
    profile.method = this.selectedMethod();
    profile.route = ALL_ROUTES[this.routeIndex] ?? ROUTE_ALL;
    profile.plugin = this.plugin;
    profile.pluginConfigs = this.pluginConfigs;
    profile.pluginOpts = this.plugin.length > 0 ? this.pluginOpts : '';
    const remoteDns = this.remoteDns.trim();
    profile.remoteDns = remoteDns.length > 0 ? remoteDns : DEFAULT_REMOTE_DNS;
    profile.ipv6 = this.ipv6;
    // The profile is edited in place, but this line states the intent: the
    // switch writes the profile field.
    profile.metered = this.metered;
    profile.udpFallbackId = this.udpFallbackId;
    profile.proxyAppsEnabled = PerAppDraft.enabled;
    profile.proxyAppsBypass = PerAppDraft.bypass;
    profile.proxyAppsList = PerAppDraft.list;
    profile.ensureId();
    return profile;
  }

  private async save(): Promise<void> {
    if (!this.isComplete()) {
      promptAction.showToast({ message: $r('app.string.profile_edit_required_fields') });
      return;
    }
    const profile = this.buildProfile();
    try {
      await ProfileStore.upsert(abilityContext(), profile);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'ProfileEdit', 'save failed: %{public}s %{public}s',
        err.code?.toString() ?? '', err.message ?? String(e));
      promptAction.showToast({ message: $r('app.string.common_save_failed', err.message ?? String(e)) });
      return;
    }
    PerAppDraft.clear();
    router.back();
  }

  /** Confirms the removal, then deletes the stored profile and closes. */
  private async confirmRemove(): Promise<void> {
    if (this.profileId.length === 0) {
      return;
    }
    let index = -1;
    try {
      const answer = await new Promise<promptAction.ShowDialogSuccessResponse>((resolve, reject) => {
        promptAction.showDialog({
          title: $r('app.string.profile_edit_remove_confirm'),
          buttons: [
            { text: $r('app.string.common_cancel'), color: $r('app.color.text_body') },
            { text: $r('app.string.profile_edit_remove'), color: $r('app.color.error') },
          ],
        }, (err, data) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      index = answer.index;
    } catch (e) {
      // The dialog was dismissed. Change nothing.
      return;
    }
    if (index !== 1) {
      return;
    }
    try {
      await ProfileStore.remove(abilityContext(), this.profileId);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, 'ProfileEdit', 'remove failed: %{public}s %{public}s',
        err.code?.toString() ?? '', err.message ?? String(e));
      promptAction.showToast({
        message: $r('app.string.profile_edit_remove_failed', err.message ?? String(e)),
      });
      return;
    }
    router.back();
  }

  /** Opens the UDP fallback chooser for this profile. */
  private openUdpFallback(): void {
    if (this.profileId.length === 0 || this.readOnly) {
      return;
    }
    const params: UdpFallbackParams = {
      profileId: this.profileId,
      currentId: this.udpFallbackId,
    };
    router.pushUrl({ url: 'pages/UdpFallback', params: params });
  }

  /* ---- apps VPN mode ---- */

  /** Copies the per-app draft into the page state. */
  private syncPerApp(): void {
    this.proxyAppsEnabled = PerAppDraft.enabled;
    this.proxyAppsBypass = PerAppDraft.bypass;
    this.proxyAppsList = PerAppDraft.list;
  }

  /** Opens the app picker. The mode turns on when it was off. */
  private openAppPicker(): void {
    if (this.serviceMode !== MODE_VPN) {
      return;
    }
    PerAppDraft.ensureEnabled();
    this.syncPerApp();
    const params: AppPickerParams = { profileId: this.profileId };
    router.pushUrl({ url: 'pages/AppPicker', params: params });
  }

  /** The second line of the Apps VPN mode row. */
  private proxyAppsSummary(): ResourceStr {
    if (this.serviceMode !== MODE_VPN) {
      return $r('app.string.profile_edit_proxy_apps_vpn_only');
    }
    if (!this.proxyAppsEnabled) {
      return $r('app.string.profile_edit_proxy_apps_off');
    }
    const count = namesOf(this.proxyAppsList).length;
    return this.proxyAppsBypass
      ? $r('app.string.profile_edit_proxy_apps_bypass', count)
      : $r('app.string.profile_edit_proxy_apps_on', count);
  }

  /* ---- plugin state and options ---- */

  /** A copy of a plugin map, so the page state stays separate from a profile. */
  private copyConfigs(source: Record<string, string>): Record<string, string> {
    const copy: Record<string, string> = {};
    for (const key of Object.keys(source)) {
      copy[key] = source[key];
    }
    return copy;
  }

  /** The resource label of a plugin id. An unknown id reads Disabled. */
  private pluginLabel(id: string): Resource {
    const definition: PluginDefinition | null = findPlugin(id);
    if (definition !== null && definition.id === PLUGIN_OBFS_LOCAL) {
      return $r('app.string.plugin_label_simple_obfs');
    }
    if (definition !== null && definition.id === PLUGIN_V2RAY) {
      return $r('app.string.plugin_label_v2ray');
    }
    return $r('app.string.profile_edit_plugin_disabled');
  }

  /** The Plugin row summary. */
  private pluginSummary(): ResourceStr {
    if (this.plugin.length === 0) {
      return $r('app.string.profile_edit_plugin_disabled');
    }
    if (pluginStateOf(this.plugin) === PLUGIN_STATE_UNKNOWN) {
      return $r('app.string.profile_edit_plugin_unknown', this.plugin);
    }
    return this.pluginLabel(this.plugin);
  }

  /** The Configure... row summary. A locked row still shows its text. */
  private pluginOptionsSummary(): string {
    return pluginStateOf(this.plugin) === PLUGIN_STATE_KNOWN ? this.pluginOpts : '';
  }

  /** True when the options editor may open. */
  private canOpenOptions(): boolean {
    return !this.readOnly && pluginStateOf(this.plugin) === PLUGIN_STATE_KNOWN;
  }

  /** The plugin map as one comparable string, with sorted keys. */
  private pluginConfigSnapshot(): string {
    const keys: string[] = Object.keys(this.pluginConfigs);
    keys.sort();
    const parts: string[] = [];
    for (const key of keys) {
      parts.push(`${key}=${this.pluginConfigs[key]}`);
    }
    return parts.join('\u0002');
  }

  /** A draft profile that carries the plugin fields of the page state. */
  private pluginDraft(): Profile {
    const draft = new Profile();
    draft.plugin = this.plugin;
    draft.pluginOpts = this.pluginOpts;
    draft.pluginConfigs = this.copyConfigs(this.pluginConfigs);
    return draft;
  }

  /** Selects a plugin through the model rule, then closes the sheet. */
  private pickPlugin(id: string): void {
    this.pluginPickerShown = false;
    const draft = this.pluginDraft();
    draft.selectPlugin(id);
    this.plugin = draft.plugin;
    this.pluginOpts = draft.pluginOpts;
    this.pluginConfigs = draft.pluginConfigs;
  }

  /** Opens the options editor for the selected plugin. */
  private openOptionsEditor(): void {
    if (!this.canOpenOptions()) {
      return;
    }
    this.optionsDraft = this.pluginOpts;
    this.optionsDialog.open();
  }

  /** Validates the typed options. A bad text shows a message and writes nothing. */
  private commitPluginOptions(text: string): void {
    const draft = this.pluginDraft();
    const code = PluginOptions.validate(draft.plugin, text);
    if (code !== PLUGIN_OPTIONS_OK) {
      promptAction.showToast({ message: this.optionsErrorText(code), duration: 3000 });
      return;
    }
    draft.setPluginOptions(draft.plugin, PluginOptions.canonical(text));
    this.pluginOpts = draft.pluginOpts;
    this.pluginConfigs = draft.pluginConfigs;
  }

  /** The message of a validation code. */
  private optionsErrorText(code: string): ResourceStr {
    if (code === PLUGIN_OPTIONS_CONTROL) {
      return $r('app.string.plugin_options_control_chars');
    }
    if (code === PLUGIN_OPTIONS_OBFS_MODE) {
      return $r('app.string.plugin_options_obfs_mode');
    }
    if (code === PLUGIN_OPTIONS_V2RAY_MODE) {
      return $r('app.string.plugin_options_v2ray_mode');
    }
    return '';
  }

  /**
   * Shows the code for the profile the form describes, not for the one that was
   * last saved, so a name changed here is the name in the code.
   */
  private showQrCode(): void {
    if (!this.isComplete()) {
      promptAction.showToast({ message: $r('app.string.profile_edit_required_fields') });
      return;
    }
    const profile = this.buildProfile();
    const params: QrParams = { url: profile.toUri(), name: profile.name };
    router.pushUrl({ url: 'pages/ProfileQr', params: params });
  }

  @Builder
  PluginPickerSheet() {
    Column() {
      ForEach(pluginChoices(this.plugin), (choice: PluginChoice) => {
        Row() {
          Text(this.pluginLabel(choice.id))
            .fontSize(16)
            .fontColor($r('app.color.text_body'))
            .fontWeight(choice.current ? FontWeight.Bold : FontWeight.Normal)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => this.pickPlugin(choice.id))
      }, (choice: PluginChoice) => `${choice.id}:${choice.current}`)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => this.confirmLeave())
        Text($r('app.string.profile_edit_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('✕')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => router.back())
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      if (this.ready) {
        Scroll() {
          Column({ space: 12 }) {
            if (this.readOnly) {
              Text($r('app.string.profile_edit_subscription_readonly'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }

            TextInput({ placeholder: $r('app.string.profile_edit_profile_name'), text: this.name })
              .enabled(!this.readOnly)
              .onChange((value: string) => this.name = value)
            TextInput({ placeholder: $r('app.string.profile_edit_server_host'), text: this.host })
              .enabled(!this.readOnly)
              .onChange((value: string) => this.host = value)
            TextInput({ placeholder: $r('app.string.profile_edit_server_port'), text: this.remotePort })
              .enabled(!this.readOnly)
              .type(InputType.Number)
              .maxLength(5)
              .onChange((value: string) => this.remotePort = value)
            TextInput({ placeholder: $r('app.string.profile_edit_password'), text: this.password })
              .enabled(!this.readOnly)
              .type(InputType.Password)
              .onChange((value: string) => this.password = value)

            LabeledSelect({
              label: $r('app.string.profile_edit_encryption_method'),
              options: [...METHODS, $r('app.string.profile_edit_custom')],
              selected: this.methodIndex >= 0 ? this.methodIndex : METHODS.length,
              interactive: !this.readOnly,
              onSelect: (index: number) => {
                this.methodIndex = index < METHODS.length ? index : -1;
              },
            })
            if (this.methodIndex < 0) {
              TextInput({ placeholder: $r('app.string.profile_edit_method_custom'), text: this.methodCustom })
                .enabled(!this.readOnly)
                .onChange((value: string) => this.methodCustom = value)
            }

            TextInput({ placeholder: $r('app.string.remote_dns', DEFAULT_REMOTE_DNS), text: this.remoteDns })
              .onChange((value: string) => this.remoteDns = value)

            LabeledSelect({
              label: $r('app.string.profile_edit_route'),
              options: ROUTE_LABELS,
              selected: this.routeIndex,
              onSelect: (index: number) => {
                this.routeIndex = index;
              },
            })

            Row() {
              Text($r('app.string.profile_edit_ipv6'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.ipv6 })
                .enabled(ipv6SwitchEnabled(this.serviceMode))
                .onChange((isOn: boolean) => {
                  this.ipv6 = isOn;
                })
            }
            .width('100%')
            Text($r('app.string.profile_edit_ipv6_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            Row() {
              Text($r('app.string.profile_edit_metered'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.metered })
                .onChange((isOn: boolean) => {
                  this.metered = isOn;
                })
            }
            .width('100%')
            Text($r('app.string.profile_edit_metered_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.profile_edit_proxy_apps'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_body'))
                Text(this.proxyAppsSummary())
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.proxyAppsEnabled })
                .selectedColor($r('app.color.accent_container'))
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .enabled(this.serviceMode === MODE_VPN)
            .onClick(() => this.openAppPicker())

            Text($r('app.string.profile_edit_plugin_category'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.profile_edit_plugin'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_body'))
                Text(this.pluginSummary())
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .enabled(!this.readOnly)
            .onClick(() => {
              this.pluginPickerShown = true;
            })
            .bindSheet(this.pluginPickerShown, this.PluginPickerSheet(), {
              height: SheetSize.FIT_CONTENT,
              onDisappear: () => {
                this.pluginPickerShown = false;
              },
            })

            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.profile_edit_plugin_configure'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_body'))
                Text(this.pluginOptionsSummary())
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .enabled(this.canOpenOptions())
            .onClick(() => this.openOptionsEditor())

            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.profile_edit_udp_fallback'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_body'))
                Text(this.fallbackName.length > 0
                  ? this.fallbackName
                  : $r('app.string.profile_edit_disabled'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .enabled(!this.readOnly && this.profileId.length > 0)
            .onClick(() => this.openUdpFallback())

            if (this.profileId.length > 0) {
              Button($r('app.string.profile_edit_remove'))
                .width('100%')
                .height(48)
                .backgroundColor($r('app.color.error_container'))
                .fontColor($r('app.color.on_container'))
                .onClick(() => this.confirmRemove())
            }

            if (this.profileId.length > 0) {
              Button($r('app.string.profile_edit_show_qr_code'))
                .width('100%')
                .height(48)
                .backgroundColor($r('app.color.button_neutral'))
                .fontColor($r('app.color.on_neutral'))
                .onClick(() => this.showQrCode())
            }

            Button($r('app.string.common_save'))
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.accent_container'))
              .fontColor($r('app.color.on_container'))
              .margin({ bottom: 24 })
              .onClick(() => this.save())
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}

/** The plugin options editor. Only OK with a valid text writes to the page. */
@CustomDialog
struct PluginOptionsDialog {
  controller: CustomDialogController;
  @Link draft: string;
  onCommit: (text: string) => void = () => {
  };

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.profile_edit_plugin_configure'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_body'))
      TextInput({ placeholder: $r('app.string.profile_edit_plugin_options'), text: this.draft })
        .fontFamily('monospace')
        .onChange((value: string) => this.draft = value)
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
            this.onCommit(this.draft);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
  }
}

@Component
struct LabeledSelect {
  label: ResourceStr = '';
  options: ResourceStr[] = [];
  selected: number = 0;
  interactive: boolean = true;
  onSelect: (index: number) => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Select(this.options.map((option) => {
        return { value: option } as SelectOption;
      }))
        .selected(this.selected)
        .value(this.options[this.selected] ?? '')
        .enabled(this.interactive)
        .onSelect((index: number) => this.onSelect(index))
    }
    .width('100%')
  }
}
