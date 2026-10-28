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

import { router } from '@kit.ArkUI';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { abilityContext, setPendingFallback } from '../model/AppContext';
import { eligibleFallbacks, fallbackDisplayName, fallbackRowIndex } from '../model/UdpFallback';

/** What the profile editor hands this page. */
export interface UdpFallbackParams {
  profileId: string;
  currentId: string;
}

/**
 * The UDP fallback chooser.
 *
 * Row 0 is Disabled. The other rows are the stored profiles that can carry a
 * fallback for the profile under edit. A tap writes the choice to AppStorage
 * and closes the page. The editor takes the choice on its next show. The
 * close control and the system back gesture store nothing.
 */
@Entry
@Component
struct UdpFallback {
  @State rows: Profile[] = [];
  @State currentId: string = '';
  @State ready: boolean = false;
  private editedId: string = '';
  private allProfiles: Profile[] = [];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const params = router.getParams() as UdpFallbackParams | null;
    const profileId = params?.profileId ?? '';
    if (profileId.length === 0) {
      // no edited profile means no choice to make
      router.back();
      return;
    }
    this.editedId = profileId;
    this.currentId = params?.currentId ?? '';
    this.load();
  }

  /** Loads the eligible rows. A missing or unreadable list closes the page. */
  private async load(): Promise<void> {
    let profiles: Profile[] = [];
    try {
      profiles = await ProfileStore.getAll(abilityContext());
    } catch (e) {
      router.back();
      return;
    }
    const edited = profiles.find((profile: Profile) => profile.id === this.editedId);
    if (edited === undefined) {
      router.back();
      return;
    }
    this.allProfiles = profiles;
    this.rows = eligibleFallbacks(profiles, this.editedId);
    if (this.currentId.length === 0) {
      this.currentId = edited.udpFallbackId;
    }
    this.ready = true;
  }

  /** Stores one choice. An empty id is the Disabled row. */
  private choose(fallbackId: string): void {
    setPendingFallback(this.editedId, fallbackId);
    router.back();
  }

  @Builder
  ChoiceRow(label: ResourceStr, id: string, checked: boolean) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_body'))
        .layoutWeight(1)
      Blank()
      if (checked) {
        Text('✓')
          .fontSize(16)
          .fontColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => this.choose(id))
  }

  build() {
    Column() {
      Row() {
        Text(' ')
          .fontSize(18)
        Text($r('app.string.profile_edit_udp_fallback'))
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
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.ready) {
        List({ scroller: this.scroller }) {
          ListItem() {
            this.ChoiceRow($r('app.string.profile_edit_disabled'), '', this.currentId.length === 0)
          }
          ForEach(this.rows, (profile: Profile) => {
            ListItem() {
              this.ChoiceRow(fallbackDisplayName(profile), profile.id, this.currentId === profile.id)
            }
          }, (profile: Profile) => profile.id)
        }
        .width('100%')
        .layoutWeight(1)
        .onAppear(() => {
          if (this.currentId.length > 0) {
            this.scroller.scrollToIndex(fallbackRowIndex(this.rows, this.currentId));
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
