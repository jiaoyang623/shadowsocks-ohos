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
import { parseAcl } from '../model/Acl';
import {
  RULE_KIND_DOMAIN,
  RULE_KIND_SUBNET,
  RULE_KIND_URL,
  addRule,
  addRulesFromText,
  readUserRules,
  removeRules,
  writeUserRules,
} from '../model/CustomRules';
import { readClipboard, writeClipboard } from '../model/Transfer';

const TAG = 'CustomRules';

/** One rule as the list shows it, with the kind it was added as. */
interface RuleRow {
  value: string;
  kind: string;
}

/**
 * The rules for the `custom-rules` route, which is the one route with nothing
 * shipped behind it: what the core reads is composed from what is written here.
 *
 * shadowsocks-android edits the same rules with the same three templates. A
 * press opens nothing here — a row is a rule, and the only things to do with it
 * are copy it or delete it — so a long press starts a selection, as it does
 * there, and the bar above the list acts on all of it.
 */
@Entry
@Component
struct CustomRulesPage {
  @State rows: RuleRow[] = [];
  @State draft: string = '';
  /** The rules picked out by a long press, by value. */
  @State selected: string[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.rows = CustomRulesPage.rows(readUserRules(abilityContext()));
  }

  /** The rules in a file, in the order the file lists them. */
  private static rows(text: string): RuleRow[] {
    const doc = parseAcl(text);
    const rows: RuleRow[] = [];
    for (const entry of doc.proxyEntries) {
      rows.push({ value: entry, kind: RULE_KIND_DOMAIN });
    }
    for (const entry of doc.bypassEntries) {
      rows.push({ value: entry, kind: RULE_KIND_DOMAIN });
    }
    for (const url of doc.urls) {
      rows.push({ value: url, kind: RULE_KIND_URL });
    }
    return rows;
  }

  private async change(next: string): Promise<void> {
    try {
      writeUserRules(abilityContext(), next);
      this.rows = CustomRulesPage.rows(next);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save failed: %{public}s', err.message ?? String(e));
      promptAction.showToast({ message: $r('app.string.common_save_failed', err.message ?? String(e)) });
    }
  }

  private async add(kind: string): Promise<void> {
    const value = this.draft.trim();
    if (value.length === 0) {
      promptAction.showToast({ message: $r('app.string.custom_rules_enter_rule_first') });
      return;
    }
    await this.change(addRule(readUserRules(abilityContext()), kind, value));
    this.draft = '';
  }

  /**
   * Takes the rules out of a list on the clipboard, which is how a list from
   * another client or from the project's gfwlist gets in.
   */
  private async importFromClipboard(): Promise<void> {
    let text = '';
    try {
      text = await readClipboard();
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.custom_rules_nothing_to_import') });
      return;
    }
    const before = this.rows.length;
    await this.change(addRulesFromText(readUserRules(abilityContext()), text));
    const added = this.rows.length - before;
    if (added === 0) {
      promptAction.showToast({ message: $r('app.string.custom_rules_nothing_to_import') });
      return;
    }
    promptAction.showToast({ message: $r('app.string.custom_rules_imported_n', added) });
  }

  /**
   * Removes the named rules and offers them back, as the profile list does with
   * a profile it has just deleted.
   */
  private async remove(values: string[]): Promise<void> {
    if (values.length === 0) {
      return;
    }
    const before = readUserRules(abilityContext());
    await this.change(removeRules(before, values));
    this.selected = [];
    const answer = await promptAction.showDialog({
      title: $r('app.string.custom_rules_removed_n', values.length),
      buttons: [
        { text: $r('app.string.common_undo'), color: $r('app.color.accent') },
        { text: $r('app.string.common_ok'), color: $r('app.color.text_body') },
      ],
    });
    if (answer.index === 0) {
      await this.change(before);
    }
  }

  private toggle(value: string): void {
    const at = this.selected.indexOf(value);
    if (at < 0) {
      this.selected = this.selected.concat([value]);
    } else {
      const rest = this.selected.slice();
      rest.splice(at, 1);
      this.selected = rest;
    }
  }

  private isSelected(value: string): boolean {
    return this.selected.indexOf(value) >= 0;
  }

  /** Everything picked out, one to a line, which is the form it can come back in. */
  private async copySelected(): Promise<void> {
    try {
      await writeClipboard(this.selected.join('\n'));
      promptAction.showToast({ message: $r('app.string.qr_copied') });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.qr_could_not_copy') });
    }
  }

  private kindLabel(kind: string): Resource {
    return kind === RULE_KIND_URL
      ? $r('app.string.custom_rules_list')
      : $r('app.string.custom_rules_rule');
  }

  @Builder
  SelectionBar() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.custom_rules_selected_n', this.selected.length))
          .fontSize(14)
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
          .onClick(() => this.selected = this.rows.map((row) => row.value))
        Button($r('app.string.common_copy'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .onClick(() => this.copySelected())
        Button($r('app.string.custom_rules_cut'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_neutral'))
          .onClick(async () => {
            await this.copySelected();
            await this.remove(this.selected);
          })
        Button($r('app.string.common_delete'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.error'))
          .onClick(() => this.remove(this.selected))
      }
      .width('100%')
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
      .fontColor('#FFFFFF')
      .backgroundColor($r('app.color.error'))
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .borderRadius(8)
      .onClick(() => this.remove([row.value]))
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.common_back'))
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .onClick(() => router.back())
        Text($r('app.string.settings_custom_rules'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Text($r('app.string.custom_rules_explainer'))
        .fontSize(13)
        .fontColor($r('app.color.text_body'))

      TextInput({ placeholder: $r('app.string.custom_rules_draft_hint'), text: this.draft })
        .onChange((value) => this.draft = value)

      Row({ space: 8 }) {
        Button($r('app.string.custom_rules_kind_domain'))
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_DOMAIN))
        Button($r('app.string.custom_rules_kind_subnet'))
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_SUBNET))
        Button($r('app.string.custom_rules_kind_url'))
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_URL))
      }
      .width('100%')

      Button($r('app.string.custom_rules_import_clipboard'))
        .width('100%')
        .backgroundColor($r('app.color.button_neutral'))
        .onClick(() => this.importFromClipboard())

      if (this.selected.length > 0) {
        this.SelectionBar()
      }

      if (this.rows.length === 0) {
        Text($r('app.string.custom_rules_no_rules'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
      } else {
        List({ space: 6 }) {
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
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.isSelected(row.value)) {
                  Text('✓')
                    .fontSize(16)
                    .fontColor($r('app.color.accent'))
                } else {
                  Text('✕')
                    .fontSize(16)
                    .fontColor($r('app.color.text_secondary'))
                    .onClick(() => this.remove([row.value]))
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor(this.isSelected(row.value)
                ? $r('app.color.surface_selected')
                : $r('app.color.surface'))
              .gesture(LongPressGesture().onAction(() => this.toggle(row.value)))
            }
            // a row cannot be swiped away while a selection is up: the two are
            // different ways of saying the same thing and Android disables one
            // while the other is in force
            .swipeAction(this.selected.length === 0
              ? { end: () => {
                this.SwipeDelete(row);
              } }
              : {})
          }, (row: RuleRow) => row.kind + ':' + row.value)
        }
        .layoutWeight(1)
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}
