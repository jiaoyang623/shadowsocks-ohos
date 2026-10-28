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
import { abilityContext } from '../model/AppContext';
import {
  REASON_FAILED,
  REASON_NOT_FOUND,
  REASON_PERMISSION,
  REASON_UNAVAILABLE,
  ResolvedApp,
  queryAvailable,
  resolveName,
  resolveNames,
  selfBundleName,
} from '../model/AppCatalog';
import {
  APP_MODE_BYPASS,
  APP_MODE_OFF,
  APP_MODE_ON,
  AppEntry,
  PerAppDraft,
  PerAppState,
  appMode,
  applyToAll,
  exportText,
  isValidBundleName,
  namesOf,
  parseImportText,
  selectionCap,
  sortEntries,
  toggleName,
  visibleEntries,
} from '../model/PerApp';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { readClipboard, writeClipboard } from '../model/Transfer';

/** What the profile editor hands this page. */
export interface AppPickerParams {
  profileId?: string;
}

/**
 * The Apps VPN mode page.
 *
 * The page edits the in-memory draft of the profile that the editor has open.
 * The editor writes the draft into the profile on save. The VPN extension
 * reads the stored profile when the tunnel starts.
 *
 * The bundle query resolves a stored name. It does not list bundles, because
 * a public list needs a system permission. A name the query cannot resolve
 * stays in the list, and the user can type a name.
 */
@Entry
@Component
struct AppPicker {
  @State mode: string = APP_MODE_ON;
  @State entries: AppEntry[] = [];
  @State selectedNames: string[] = [];
  @State missing: string[] = [];
  @State query: string = '';
  @State loading: boolean = true;
  @State reason: string = '';
  @State newBundle: string = '';
  private profileId: string = '';
  private clientBundle: string = '';
  /** The newest load owns the state. An older result is dropped. */
  private generation: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as AppPickerParams | null;
    this.profileId = params?.profileId ?? '';
    this.clientBundle = selfBundleName(abilityContext());
    if (PerAppDraft.profileId !== this.profileId) {
      this.openStoredProfile();
      return;
    }
    this.startDraft();
  }

  onPageShow(): void {
    this.syncFromDraft();
  }

  /**
   * Opens the draft from the stored profile when no editor holds the draft.
   * A missing or unknown profile starts from the defaults.
   */
  private async openStoredProfile(): Promise<void> {
    let stored: Profile | null = null;
    try {
      const profiles = await ProfileStore.getAll(abilityContext());
      stored = profiles.find((profile: Profile) => profile.id === this.profileId) ?? null;
    } catch (e) {
      stored = null;
    }
    PerAppDraft.open(stored ?? new Profile());
    this.startDraft();
  }

  /** Turns the mode on, copies the draft to the page, and loads the rows. */
  private startDraft(): void {
    PerAppDraft.ensureEnabled();
    this.syncFromDraft();
    this.load();
  }

  /**
   * Resolves the selected names into rows. A newer call owns the state, so an
   * older result is dropped.
   */
  private async load(): Promise<void> {
    this.loading = true;
    this.generation++;
    const generation = this.generation;
    try {
      const names = namesOf(PerAppDraft.list);
      const resolved = await resolveNames(names);
      if (generation !== this.generation) {
        return;
      }
      this.reason = AppPicker.reasonOf(resolved);
      this.entries = sortEntries(resolved.map((item: ResolvedApp) => item.entry), PerAppDraft.list);
      this.missing = resolved
        .filter((item: ResolvedApp) => item.reason === REASON_NOT_FOUND)
        .map((item: ResolvedApp) => item.entry.bundleName);
      this.loading = false;
    } catch (e) {
      if (generation === this.generation) {
        this.reason = REASON_FAILED;
        this.loading = false;
      }
    }
  }

  /** The one reason that every row shares, or '' when the rows differ. */
  private static reasonOf(resolved: ResolvedApp[]): string {
    if (resolved.length === 0) {
      return '';
    }
    const reasons: string[] = [REASON_UNAVAILABLE, REASON_PERMISSION, REASON_FAILED];
    for (const reason of reasons) {
      if (resolved.every((item: ResolvedApp) => item.reason === reason)) {
        return reason;
      }
    }
    return '';
  }

  private syncFromDraft(): void {
    this.mode = appMode(PerAppDraft.enabled, PerAppDraft.bypass);
    this.selectedNames = namesOf(PerAppDraft.list);
  }

  private chooseMode(mode: string): void {
    PerAppDraft.setMode(mode);
    this.syncFromDraft();
    if (mode === APP_MODE_OFF) {
      router.back();
    }
  }

  /** Toggles one name. The row order stays, so the list does not reload. */
  private toggle(entry: AppEntry): void {
    PerAppDraft.setList(toggleName(PerAppDraft.list, entry.bundleName));
    this.selectedNames = namesOf(PerAppDraft.list);
  }

  private isSelected(name: string): boolean {
    return this.selectedNames.indexOf(name) >= 0;
  }

  private visible(): AppEntry[] {
    return visibleEntries(this.entries, this.query);
  }

  /** Adds one typed bundle name, after the checks that guard the list. */
  private async addBundle(): Promise<void> {
    const name = this.newBundle.trim();
    if (!isValidBundleName(name)) {
      promptAction.showToast({ message: $r('app.string.app_picker_invalid_name') });
      return;
    }
    if (name === this.clientBundle) {
      promptAction.showToast({ message: $r('app.string.app_picker_client_app') });
      return;
    }
    if (this.isSelected(name)) {
      return;
    }
    const cap = selectionCap(PerAppDraft.bypass);
    if (namesOf(PerAppDraft.list).length >= cap) {
      promptAction.showToast({ message: $r('app.string.app_picker_limit', cap) });
      return;
    }
    if (queryAvailable()) {
      const resolved = await resolveName(name);
      if (resolved.reason === REASON_NOT_FOUND) {
        promptAction.showToast({ message: $r('app.string.app_picker_not_found') });
        return;
      }
    }
    PerAppDraft.setList(toggleName(PerAppDraft.list, name));
    this.newBundle = '';
    this.syncFromDraft();
    this.load();
  }

  /**
   * Copies the bypass flag and the list to every profile.
   * The enabled flag of each profile does not change.
   */
  private async applyToAllProfiles(): Promise<void> {
    try {
      const profiles = await ProfileStore.getAllOrNull(abilityContext());
      if (profiles === null) {
        promptAction.showToast({ message: $r('app.string.app_picker_export_fail') });
        return;
      }
      const updated = applyToAll(profiles, PerAppDraft.bypass, PerAppDraft.list);
      await ProfileStore.saveAll(abilityContext(), updated);
      promptAction.showToast({ message: $r('app.string.app_picker_apply_done') });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.app_picker_export_fail') });
    }
  }

  private async exportClipboard(): Promise<void> {
    try {
      await writeClipboard(exportText(PerAppDraft.bypass, PerAppDraft.list));
      promptAction.showToast({ message: $r('app.string.app_picker_export_ok') });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.app_picker_export_fail') });
    }
  }

  /** Replaces the draft with the mode and the list on the clipboard. */
  private async importClipboard(): Promise<void> {
    let text = '';
    try {
      text = await readClipboard();
    } catch (e) {
      text = '';
    }
    const parsed: PerAppState | null = parseImportText(text);
    if (parsed === null) {
      promptAction.showToast({ message: $r('app.string.app_picker_import_fail') });
      return;
    }
    PerAppDraft.setMode(parsed.bypass ? APP_MODE_BYPASS : APP_MODE_ON);
    PerAppDraft.setList(parsed.list);
    this.syncFromDraft();
    this.load();
    promptAction.showToast({ message: $r('app.string.app_picker_import_ok') });
  }

  /** The text beside the list when the bundle query did not work. */
  private summaryReason(): ResourceStr {
    if (this.reason === REASON_UNAVAILABLE) {
      return $r('app.string.app_picker_query_unavailable');
    }
    if (this.reason === REASON_PERMISSION) {
      return $r('app.string.app_picker_query_denied');
    }
    if (this.reason === REASON_FAILED) {
      return $r('app.string.app_picker_query_failed');
    }
    return '';
  }

  private overflowMenu(): MenuElement[] {
    return [
      {
        value: $r('app.string.app_picker_apply_all'),
        action: () => {
          this.applyToAllProfiles();
        },
      },
      {
        value: $r('app.string.app_picker_export'),
        action: () => {
          this.exportClipboard();
        },
      },
      {
        value: $r('app.string.app_picker_import'),
        action: () => {
          this.importClipboard();
        },
      },
    ];
  }

  @Builder
  ModeRow(mode: string, label: ResourceStr) {
    Row({ space: 8 }) {
      Radio({ value: mode, group: 'appMode' })
        .checked(this.mode === mode)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.chooseMode(mode);
          }
        })
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  /**
   * One app row. The row owns the tap, and the switch ignores taps, as the
   * Android row does.
   */
  @Builder
  AppRow(entry: AppEntry) {
    Row({ space: 8 }) {
      Text(entry.label)
        .fontSize(14)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.missing.indexOf(entry.bundleName) >= 0) {
        Text($r('app.string.app_picker_not_installed'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      Toggle({ type: ToggleType.Switch, isOn: this.isSelected(entry.bundleName) })
        .selectedColor($r('app.color.accent_container'))
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
    .onClick(() => this.toggle(entry))
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => router.back())
        Text($r('app.string.app_picker_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('⋮')
          .fontSize(20)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.surface'))
          .accessibilityText($r('app.string.app_picker_menu'))
          .bindMenu(this.overflowMenu())
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.app_picker_search'), text: this.query })
          .layoutWeight(1)
          .onChange((value: string) => this.query = value)
        if (this.query.length > 0) {
          Button($r('app.string.app_picker_clear'))
            .backgroundColor($r('app.color.button_neutral'))
            .fontColor($r('app.color.on_neutral'))
            .onClick(() => this.query = '')
        }
      }
      .width('100%')

      Text($r('app.string.app_picker_mode'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      this.ModeRow(APP_MODE_OFF, $r('app.string.app_picker_mode_off'))
      this.ModeRow(APP_MODE_ON, $r('app.string.app_picker_mode_on'))
      this.ModeRow(APP_MODE_BYPASS, $r('app.string.app_picker_mode_bypass'))

      if (this.reason.length > 0) {
        Text(this.summaryReason())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.entries.length === 0 && this.reason.length === 0) {
          Text($r('app.string.app_picker_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        List({ space: 6 }) {
          // The key carries the selected state. Without it, ArkUI reuses the
          // cached row and the switch stays at its first value.
          ForEach(this.visible(), (entry: AppEntry) => {
            ListItem() {
              this.AppRow(entry)
            }
          }, (entry: AppEntry) => `${entry.bundleName}#${this.isSelected(entry.bundleName) ? 1 : 0}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.app_picker_add_hint'), text: this.newBundle })
          .layoutWeight(1)
          .onChange((value: string) => this.newBundle = value)
        Button($r('app.string.app_picker_add'))
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
          .onClick(() => this.addBundle())
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}
