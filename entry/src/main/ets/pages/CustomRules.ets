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
  readUserRules,
  removeRule,
  writeUserRules,
} from '../model/CustomRules';

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
 * shadowsocks-android edits the same rules with a list and three templates, and
 * this does the same, minus the multi-select and the swipe gestures.
 */
@Entry
@Component
struct CustomRulesPage {
  @State rows: RuleRow[] = [];
  @State draft: string = '';

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
      promptAction.showToast({ message: `Save failed: ${err.message ?? String(e)}` });
    }
  }

  private async add(kind: string): Promise<void> {
    const value = this.draft.trim();
    if (value.length === 0) {
      promptAction.showToast({ message: 'Enter a rule first' });
      return;
    }
    await this.change(addRule(readUserRules(abilityContext()), kind, value));
    this.draft = '';
  }

  private kindLabel(kind: string): string {
    if (kind === RULE_KIND_URL) {
      return 'list';
    }
    return 'rule';
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ Back')
          .fontSize(16)
          .fontColor('#3F51B5')
          .onClick(() => router.back())
        Text('Custom rules')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Text('Destinations listed here go through the proxy. Profiles using the custom-rules route apply them.')
        .fontSize(13)
        .fontColor('#616161')

      TextInput({ placeholder: 'example.com, 10.0.0.0/8, or a list URL', text: this.draft })
        .onChange((value) => this.draft = value)

      Row({ space: 8 }) {
        Button('Domain')
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_DOMAIN))
        Button('Subnet')
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_SUBNET))
        Button('List URL')
          .layoutWeight(1)
          .onClick(() => this.add(RULE_KIND_URL))
      }
      .width('100%')

      if (this.rows.length === 0) {
        Text('No rules yet.')
          .fontSize(14)
          .fontColor('#9E9E9E')
          .margin({ top: 16 })
      } else {
        List({ space: 6 }) {
          ForEach(this.rows, (row: RuleRow) => {
            ListItem() {
              Row() {
                Text(this.kindLabel(row.kind))
                  .fontSize(11)
                  .fontColor('#616161')
                  .backgroundColor('#EEEEEE')
                  .borderRadius(4)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .margin({ right: 8 })
                Text(row.value)
                  .fontSize(14)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('✕')
                  .fontSize(16)
                  .fontColor('#9E9E9E')
                  .onClick(() => this.change(removeRule(readUserRules(abilityContext()), row.value)))
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor('#FFFFFF')
            }
          })
        }
        .layoutWeight(1)
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
