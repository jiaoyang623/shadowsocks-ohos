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
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import sslocal from 'libsslocal.so';

const TAG = 'About';

/** What the page shows when the bundle will not say. */
interface Versions {
  app: string;
  core: string;
}

/**
 * Version and licence, the two things a user is told when they ask what they
 * are running. shadowsocks-android has the same screen; the version numbers are
 * worth showing separately here because the native core is patched, so it can
 * differ from any released shadowsocks-rust build.
 */
@Entry
@Component
struct AboutPage {
  @State versions: Versions = { app: '', core: '' };

  aboutToAppear(): void {
    this.versions = AboutPage.read();
  }

  private static read(): Versions {
    let app = '';
    try {
      app = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not read the bundle version');
    }
    let core = '';
    try {
      core = sslocal.version();
    } catch (e) {
      hilog.warn(0x0000, TAG, 'could not read the core version');
    }
    return { app: app, core: core };
  }

  @Builder
  Line(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#616161')
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ Back')
          .fontSize(16)
          .fontColor('#3F51B5')
          .onClick(() => router.back())
        Text('About')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(' ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Column() {
        this.Line('Shadowsocks', this.versions.app)
        this.Line('Native core', this.versions.core)
        this.Line('Licence', 'GPL-3.0-or-later')
      }
      .width('100%')
      .padding(12)
      .borderRadius(8)
      .backgroundColor('#FFFFFF')

      Text('A client for HarmonyOS NEXT, built on the same Rust core as the Android client. It is free software: you may redistribute and modify it under the terms of the GNU General Public License, version 3 or later, as published by the Free Software Foundation.')
        .fontSize(13)
        .fontColor('#616161')

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
