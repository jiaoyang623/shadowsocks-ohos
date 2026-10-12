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
import { encodeQr, QrCode } from '../model/QrCode';
import { QR_EC_L } from '../model/QrTables';
import { writeClipboard } from '../model/Transfer';

const TAG = 'ProfileQr';

/**
 * Modules of empty space around the code. Four is what the specification asks
 * for and what zxing draws, and a scanner needs it to find the code at all.
 */
const QUIET_ZONE = 4;

/** Side of the drawn code in vp, the size the Android client draws at. */
const CODE_SIZE = 264;

/**
 * What the editor hands this page. The URL rather than a profile id, so that
 * the code matches the form as it stands: a profile edited but not saved still
 * shows what the user is looking at.
 */
export interface QrParams {
  url?: string;
  name?: string;
}

/**
 * A profile as a QR code, which is how a server is handed to another device
 * without anyone typing a password. shadowsocks-android has the same screen,
 * and the code holds the same `ss://` URL, so either app scans the other's.
 */
@Entry
@Component
struct ProfileQr {
  @State profileName: string = '';
  @State url: string = '';
  @State error: string = '';
  private code: QrCode | null = null;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  // not named `context`: that collides with the component framework's own field
  // and silently reads back undefined (see AGENTS.md)
  private painter: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    const params = router.getParams() as QrParams | null;
    this.url = params?.url ?? '';
    this.profileName = params?.name ?? '';
    if (this.url.length === 0) {
      this.error = 'There is no profile to show.';
      return;
    }
    try {
      this.code = encodeQr(this.url, QR_EC_L);
    } catch (e) {
      // only reachable with a name long enough to push the URL past what a
      // version 40 code holds, which is close to three thousand characters
      this.error = 'This profile is too long to show as a QR code.';
      hilog.warn(0x0000, TAG, 'the profile URL does not encode: %{public}s',
        e instanceof Error ? e.message : String(e));
      return;
    }
    this.draw();
  }

  /**
   * Paints the code as whole modules of at least one pixel, centred, with the
   * quiet zone around it. A module that is a fraction of a pixel would blur
   * into its neighbours and stop scanning.
   */
  private draw(): void {
    const code = this.code;
    if (code === null) {
      return;
    }
    const canvas = this.painter;
    const total = code.size + QUIET_ZONE * 2;
    const module = Math.max(1, Math.floor(CODE_SIZE / total));
    const offset = Math.floor((CODE_SIZE - module * total) / 2);
    canvas.fillStyle = '#FFFFFF';
    canvas.fillRect(0, 0, CODE_SIZE, CODE_SIZE);
    canvas.fillStyle = '#000000';
    for (let y = 0; y < code.size; y++) {
      for (let x = 0; x < code.size; x++) {
        if (code.isDark(x, y)) {
          canvas.fillRect(offset + (x + QUIET_ZONE) * module,
            offset + (y + QUIET_ZONE) * module, module, module);
        }
      }
    }
  }

  private async copyUrl(): Promise<void> {
    try {
      await writeClipboard(this.url);
      promptAction.showToast({ message: 'Copied' });
    } catch (e) {
      promptAction.showToast({ message: 'Could not copy' });
    }
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('‹ Back')
          .fontSize(16)
          .fontColor('#3F51B5')
          .onClick(() => router.back())
        Text('QR code')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        // holds the title centred against the back button
        Text(' ')
          .fontSize(16)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor('#F44336')
      } else {
        Canvas(this.painter)
          .width(CODE_SIZE)
          .height(CODE_SIZE)
          .backgroundColor('#FFFFFF')
          .onReady(() => this.draw())
      }

      Text(this.profileName)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)

      Text(this.url)
        .fontSize(12)
        .fontColor('#616161')
        .textAlign(TextAlign.Center)
        .copyOption(CopyOptions.LocalDevice)

      Button('Copy the URL')
        .onClick(() => this.copyUrl())

      Text('Point another Shadowsocks client at this code to add the profile. It carries the password, so do not show it to anyone you would not give the password to.')
        .fontSize(12)
        .fontColor('#9E9E9E')
        .textAlign(TextAlign.Center)

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }
}
