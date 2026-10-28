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
import { readAclText } from '../model/AclSync';
import { abilityContext } from '../model/AppContext';
import {
  RULE_ERROR_DOMAIN,
  RULE_ERROR_PATTERN,
  RULE_ERROR_URL,
  RULE_KIND_DOMAIN,
  RULE_KIND_GENERIC,
  RULE_KIND_SUBNET,
  RULE_KIND_URL,
  RULE_WARNING_CLEARTEXT,
  RuleRow,
  TEMPLATE_ORDER,
  aclTextForRules,
  addRule,
  addRulesFromText,
  canSwipe,
  checkRule,
  composeCustomRules,
  joinRemovals,
  readUserRules,
  removeRules,
  restoreRules,
  ruleEditorText,
  ruleRows,
  ruleTemplateFor,
  setRule,
  showRemove,
  storedRule,
  swipeBlocked as swipeGateClosed,
  toggleSelected,
  writeUserRules,
} from '../model/CustomRules';
import { VPN_STATE_STOPPED } from '../model/Diagnostics';
import { ProfileStore } from '../model/ProfileStore';
import { readClipboard, writeClipboard } from '../model/Transfer';
import { VpnStatusStore } from '../model/VpnStatus';

const TAG = 'CustomRules';

/** How long the undo bar stays after a removal. */
const UNDO_MILLIS: number = 4000;

/** The bundled list that the GFW List action reads after the cached copy. */
const GFW_LIST_FILE: string = 'gfwlist.acl';

/**
 * The rules for the `custom-rules` route, which is the one route with nothing
 * shipped behind it: what the core reads is composed from what is written here.
 *
 * shadowsocks-android edits the same rules with the same three templates. The
 * page shows the proxy entries and the import URLs. Bypass entries stay in the
 * file and do not become rows, as on Android.
 */
@Entry
@Component
struct CustomRulesPage {
  @State rows: RuleRow[] = [];
  /** The rules picked out by a tap or a long press, by value. */
  @State selected: string[] = [];
  /** True when the route runs and a swipe must not remove a row. */
  @State swipeBlocked: boolean = false;
  @State editorOpen: boolean = false;
  @State editorTemplate: string = RULE_KIND_GENERIC;
  @State editorText: string = '';
  @State editorValid: boolean = true;
  @State editorError: string = '';
  @State editorWarning: string = '';
  @State editorDetail: string = '';
  @State editorRemoveVisible: boolean = false;
  /** The values removed by the last actions, newest batch first. */
  @State removed: string[] = [];
  @State undoVisible: boolean = false;

  /** The stored value that the editor opened for. */
  private editorOriginal: string = '';
  /** True when the editor opened for a rule that is already stored. */
  private editorEditing: boolean = false;
  private undoTimer: number = -1;
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
    this.refreshGate();
  }

  onPageShow(): void {
    this.reload();
    this.refreshGate();
  }

  aboutToDisappear(): void {
    this.commitRemovals();
    this.selected = [];
  }

  /** Back closes the editor first, then clears the selection. */
  onBackPress(): boolean {
    if (this.editorOpen) {
      this.closeEditor();
      return true;
    }
    if (this.selected.length > 0) {
      this.selected = [];
      return true;
    }
    return false;
  }

  /** The rules file as the core reads it. The default is forced to bypass. */
  private currentText(): string {
    return composeCustomRules(readUserRules(abilityContext()));
  }

  private reload(): void {
    this.rows = ruleRows(this.currentText());
  }

  /** Writes the user file and redraws the rows. A write error keeps the rows. */
  private async change(next: string): Promise<void> {
    try {
      writeUserRules(abilityContext(), next);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save failed: %{public}s', err.message ?? String(e));
      promptAction.showToast({ message: $r('app.string.common_save_failed', err.message ?? String(e)) });
      return;
    }
    this.reload();
  }

  /** Samples the current route and the VPN state for the swipe gate. */
  private async refreshGate(): Promise<void> {
    let route: string = '';
    let state: string = VPN_STATE_STOPPED;
    try {
      const profile = await ProfileStore.getCurrent(abilityContext());
      if (profile !== null) {
        route = profile.route;
      }
      const status = await VpnStatusStore.load(abilityContext());
      if (status !== null) {
        state = status.state;
      }
    } catch (e) {
      route = '';
      state = VPN_STATE_STOPPED;
    }
    this.swipeBlocked = swipeGateClosed(route, state);
  }

  private openAdd(): void {
    this.editorOriginal = '';
    this.editorEditing = false;
    this.editorTemplate = RULE_KIND_GENERIC;
    this.editorText = '';
    this.editorRemoveVisible = false;
    this.editorOpen = true;
    this.recheckEditor();
  }

  private openEdit(row: RuleRow): void {
    this.editorOriginal = row.value;
    this.editorEditing = true;
    this.editorTemplate = ruleTemplateFor(row.value);
    this.editorText = ruleEditorText(row.value);
    this.editorRemoveVisible = showRemove(row.value);
    this.editorOpen = true;
    this.recheckEditor();
  }

  private closeEditor(): void {
    this.editorOpen = false;
    this.editorOriginal = '';
    this.editorEditing = false;
    this.editorTemplate = RULE_KIND_GENERIC;
    this.editorText = '';
    this.editorValid = true;
    this.editorError = '';
    this.editorWarning = '';
    this.editorDetail = '';
    this.editorRemoveVisible = false;
  }

  private setEditorTemplate(template: string): void {
    this.editorTemplate = template;
    this.recheckEditor();
  }

  private recheckEditor(): void {
    const check = checkRule(this.editorTemplate, this.editorText);
    this.editorValid = check.valid;
    this.editorError = check.error;
    this.editorWarning = check.warning;
    this.editorDetail = check.detail;
  }

  /** The error or warning as display text. A pattern error shows the reason. */
  private editorMessage(): ResourceStr {
    if (this.editorError === RULE_ERROR_DOMAIN) {
      return $r('app.string.custom_rules_domain_invalid');
    }
    if (this.editorError === RULE_ERROR_URL) {
      return $r('app.string.custom_rules_url_invalid');
    }
    if (this.editorError === RULE_ERROR_PATTERN) {
      return this.editorDetail;
    }
    if (this.editorWarning === RULE_WARNING_CLEARTEXT) {
      return $r('app.string.custom_rules_cleartext_warning');
    }
    return '';
  }

  private editorMessageColor(): Resource {
    if (this.editorError.length > 0) {
      return $r('app.color.error_strong');
    }
    if (this.editorWarning.length > 0) {
      return $r('app.color.warning');
    }
    return $r('app.color.text_body');
  }

  /**
   * Stores the editor input and closes the overlay. An invalid input is
   * ignored, and the OK button is disabled for it.
   */
  private async saveEditor(): Promise<void> {
    if (!this.editorValid) {
      return;
    }
    const stored: string = storedRule(this.editorTemplate, this.editorText);
    const base: string = this.currentText();
    const next: string = this.editorEditing
      ? setRule(base, this.editorOriginal, this.editorTemplate, this.editorText)
      : addRule(base, this.editorTemplate, this.editorText);
    await this.change(next);
    // A failed write leaves the old file and the old rows in place.
    if (readUserRules(abilityContext()) !== next) {
      return;
    }
    this.closeEditor();
    // An empty Generic rule becomes an empty line. A reload drops that line
    // because the parser skips it, so the row is added for this session.
    if (stored.length === 0) {
      const emptyRow: RuleRow = { value: stored, kind: RULE_KIND_GENERIC };
      this.rows = this.rows.concat([emptyRow]);
    }
    this.scrollTo(stored);
  }

  private async removeEditor(): Promise<void> {
    const value: string = this.editorOriginal;
    this.closeEditor();
    await this.remove([value]);
  }

  /**
   * Takes the rules out of a list on the clipboard, which is how a list from
   * another client or from the project's gfwlist gets in.
   */
  private async importFromClipboard(): Promise<void> {
    let text: string = '';
    try {
      text = await readClipboard();
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.custom_rules_import_failed') });
      return;
    }
    const before: number = this.rows.length;
    await this.change(addRulesFromText(this.currentText(), text));
    const added: number = this.rows.length - before;
    if (added === 0) {
      promptAction.showToast({ message: $r('app.string.custom_rules_import_failed') });
      return;
    }
    promptAction.showToast({ message: $r('app.string.custom_rules_imported_n', added) });
  }

  /**
   * Adds the bundled or cached GFW List in one tap. A missing or empty file
   * changes nothing and reports nothing.
   */
  private async importGfwList(): Promise<void> {
    const text: string = await readAclText(abilityContext(), GFW_LIST_FILE);
    if (text.length === 0) {
      return;
    }
    const before: number = this.rows.length;
    await this.change(addRulesFromText(this.currentText(), text));
    const added: number = this.rows.length - before;
    if (added > 0) {
      promptAction.showToast({ message: $r('app.string.custom_rules_imported_n', added) });
    }
  }

  /** Removes the values, clears the selection, and fills the undo bin. */
  private async remove(values: string[]): Promise<void> {
    if (values.length === 0) {
      return;
    }
    await this.change(removeRules(this.currentText(), values));
    this.selected = [];
    this.removed = joinRemovals(this.removed, values);
    this.showUndo();
  }

  /** Shows the undo bar and restarts the four-second timer. */
  private showUndo(): void {
    this.undoVisible = true;
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer);
    }
    this.undoTimer = setTimeout(() => {
      this.commitRemovals();
    }, UNDO_MILLIS);
  }

  /** Drops the undo bin and hides the bar. The removal stays. */
  private commitRemovals(): void {
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
    this.removed = [];
    this.undoVisible = false;
  }

  private async undoRemovals(): Promise<void> {
    const values: string[] = this.removed;
    this.commitRemovals();
    if (values.length === 0) {
      return;
    }
    await this.change(restoreRules(this.currentText(), values));
    let hasEmpty: boolean = false;
    for (const value of values) {
      if (value.length === 0) {
        hasEmpty = true;
      }
    }
    if (hasEmpty) {
      const emptyRow: RuleRow = { value: '', kind: RULE_KIND_GENERIC };
      this.rows = this.rows.concat([emptyRow]);
    }
  }

  private toggle(value: string): void {
    this.selected = toggleSelected(this.selected, value);
  }

  private isSelected(value: string): boolean {
    return this.selected.indexOf(value) >= 0;
  }

  /**
   * Copies the selection as an ACL file, which is the form it can come back in.
   * Returns false when the clipboard write fails.
   */
  private async copySelected(): Promise<boolean> {
    try {
      await writeClipboard(aclTextForRules(this.selected));
      promptAction.showToast({ message: $r('app.string.custom_rules_exported') });
      return true;
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.custom_rules_export_failed') });
      return false;
    }
  }

  /** Copies the selection and removes it whatever the copy result. */
  private async cutSelected(): Promise<void> {
    await this.copySelected();
    await this.remove(this.selected.slice());
  }

  /** Scrolls the list to a row, after the redraw that follows a change. */
  private scrollTo(value: string): void {
    const index: number = this.rows.findIndex((row: RuleRow) => row.value === value);
    if (index < 0) {
      return;
    }
    setTimeout(() => {
      this.listScroller.scrollToIndex(index);
    }, 0);
  }

  private kindLabel(kind: string): Resource {
    if (kind === RULE_KIND_SUBNET) {
      return $r('app.string.custom_rules_kind_subnet');
    }
    if (kind === RULE_KIND_DOMAIN) {
      return $r('app.string.custom_rules_kind_domain');
    }
    if (kind === RULE_KIND_URL) {
      return $r('app.string.custom_rules_kind_url');
    }
    return $r('app.string.custom_rules_rule');
  }

  private templateLabel(template: string): Resource {
    if (template === RULE_KIND_DOMAIN) {
      return $r('app.string.custom_rules_template_domain');
    }
    if (template === RULE_KIND_URL) {
      return $r('app.string.custom_rules_template_url');
    }
    return $r('app.string.custom_rules_template_generic');
  }

  private templateOptions(): SelectOption[] {
    return TEMPLATE_ORDER.map((template: string) => {
      return { value: this.templateLabel(template) } as SelectOption;
    });
  }

  /** The swipe actions for one row, or an empty set when the gate is closed. */
  private swipeOptions(row: RuleRow): SwipeActionOptions {
    const allowed: boolean = canSwipe(this.selected.length, this.swipeBlocked);
    if (!allowed) {
      return {};
    }
    const deleteAction: SwipeActionItem = {
      builder: (): void => {
        this.SwipeDelete(row);
      },
      onAction: (): void => {
        this.remove([row.value]);
      },
    };
    const options: SwipeActionOptions = { end: deleteAction };
    return options;
  }

  @Builder
  AddRulesMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.custom_rules_manual_settings') })
        .onClick(() => {
          this.openAdd();
        })
      MenuItem({ content: $r('app.string.custom_rules_import_clipboard') })
        .onClick(() => {
          this.importFromClipboard();
        })
      MenuItem({ content: $r('app.string.custom_rules_gfw_list') })
        .onClick(() => {
          this.importGfwList();
        })
    }
  }

  @Builder
  SelectionBar() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.custom_rules_selected_n', this.selected.length))
          .fontSize(14)
          .fontColor($r('app.color.text_body'))
          .layoutWeight(1)
        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.selected = [])
      }
      .width('100%')

      Row({ space: 8 }) {
        Button($r('app.string.custom_rules_select_all'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .onClick(() => this.selected = this.rows.map((row: RuleRow) => row.value))
        Button($r('app.string.common_copy'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .onClick(() => this.copySelected())
        Button($r('app.string.custom_rules_cut'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .onClick(() => this.cutSelected())
        Button($r('app.string.common_delete'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.error_container'))
          .fontColor($r('app.color.on_container'))
          .onClick(() => this.remove(this.selected))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
  }

  /** The bar that offers the last removal back. */
  @Builder
  UndoBar() {
    Row({ space: 8 }) {
      Text($r('app.string.custom_rules_removed_n', this.removed.length))
        .fontSize(14)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
      Button($r('app.string.common_undo'))
        .backgroundColor($r('app.color.button_neutral'))
        .fontColor($r('app.color.on_neutral'))
        .onClick(() => this.undoRemovals())
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.surface'))
  }

  /** What a sideways swipe on a row reveals. */
  @Builder
  SwipeDelete(row: RuleRow) {
    Text($r('app.string.common_delete'))
      .fontSize(14)
      .fontColor($r('app.color.on_container'))
      .backgroundColor($r('app.color.error_container'))
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .borderRadius(8)
      .onClick(() => this.remove([row.value]))
  }

  /** The editor card and the scrim that closes it. */
  @Builder
  EditorOverlay() {
    Stack() {
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .opacity(0.85)
      .onClick(() => this.closeEditor())

      Column({ space: 12 }) {
        Text($r('app.string.custom_rules_edit_rule'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_body'))
          .width('100%')

        Select(this.templateOptions())
          .selected(TEMPLATE_ORDER.indexOf(this.editorTemplate))
          .value(this.templateLabel(this.editorTemplate))
          .width('100%')
          .onSelect((index: number) => this.setEditorTemplate(TEMPLATE_ORDER[index]))

        TextInput({ placeholder: $r('app.string.custom_rules_draft_hint'), text: this.editorText })
          .width('100%')
          .onChange((value: string) => {
            this.editorText = value;
            this.recheckEditor();
          })

        if (this.editorError.length > 0 || this.editorWarning.length > 0) {
          Text(this.editorMessage())
            .fontSize(12)
            .fontColor(this.editorMessageColor())
            .maxLines(3)
            .width('100%')
        }

        Row({ space: 8 }) {
          Button($r('app.string.common_cancel'))
            .layoutWeight(1)
            .backgroundColor($r('app.color.button_neutral'))
            .fontColor($r('app.color.on_neutral'))
            .onClick(() => this.closeEditor())
          if (this.editorRemoveVisible) {
            Button($r('app.string.common_delete'))
              .layoutWeight(1)
              .backgroundColor($r('app.color.error_container'))
              .fontColor($r('app.color.on_container'))
              .onClick(() => this.removeEditor())
          }
          Button($r('app.string.common_ok'))
            .layoutWeight(1)
            .enabled(this.editorValid)
            .backgroundColor($r('app.color.accent_container'))
            .fontColor($r('app.color.on_container'))
            .onClick(() => this.saveEditor())
        }
        .width('100%')
      }
      .width('90%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column({ space: 12 }) {
        Row() {
          Text($r('app.string.common_back'))
            .fontSize(16)
            .fontColor($r('app.color.accent'))
            .onClick(() => router.back())
          Text($r('app.string.settings_custom_rules'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_body'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          if (this.selected.length === 0) {
            Button($r('app.string.custom_rules_add_rules'))
              .fontSize(13)
              .backgroundColor($r('app.color.button_neutral'))
              .fontColor($r('app.color.on_neutral'))
              .bindMenu(this.AddRulesMenu())
          } else {
            Text(' ')
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })

        Text($r('app.string.custom_rules_explainer'))
          .fontSize(13)
          .fontColor($r('app.color.text_body'))

        if (this.undoVisible) {
          this.UndoBar()
        }

        if (this.selected.length > 0) {
          this.SelectionBar()
        }

        if (this.rows.length === 0) {
          Text($r('app.string.custom_rules_no_rules'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 16 })
        } else {
          List({ space: 6, scroller: this.listScroller }) {
            ForEach(this.rows, (row: RuleRow) => {
              ListItem() {
                Row() {
                  Text(this.kindLabel(row.kind))
                    .fontSize(11)
                    .fontColor($r('app.color.text_body'))
                    .backgroundColor($r('app.color.divider'))
                    .borderRadius(4)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .margin({ right: 8 })
                  Text(row.value)
                    .fontSize(14)
                    .fontColor($r('app.color.text_body'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.isSelected(row.value)) {
                    Text('✓')
                      .fontSize(16)
                      .fontColor($r('app.color.accent'))
                  }
                }
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor(this.isSelected(row.value)
                  ? $r('app.color.surface_selected')
                  : $r('app.color.surface'))
                .onClick(() => {
                  if (this.selected.length === 0) {
                    this.openEdit(row);
                  } else {
                    this.toggle(row.value);
                  }
                })
                .gesture(LongPressGesture().onAction(() => this.toggle(row.value)))
              }
              .swipeAction(this.swipeOptions(row))
            // The key carries the selection and the gate. ForEach reuses a
            // cached item when its key is unchanged, so the check mark and the
            // swipe action would otherwise freeze at their first values.
            }, (row: RuleRow) => `${row.kind}:${row.value}:${this.isSelected(row.value)}:${canSwipe(this.selected.length, this.swipeBlocked)}`)
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .backgroundColor($r('app.color.background'))

      if (this.editorOpen) {
        this.EditorOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
