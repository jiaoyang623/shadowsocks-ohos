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

import { encodeQr, QrCode } from '../model/QrCode';
import { QR_EC_L } from '../model/QrTables';

/**
 * Modules of empty space around the code. Four is what the specification asks
 * for and what zxing draws, and a scanner needs it to find the code at all.
 */
const QUIET_ZONE: number = 4;

/** Side of the drawn code in vp, the size the Android client draws at. */
const CODE_SIZE: number = 264;

/**
 * A profile as a QR code, shown as a dialog.
 *
 * The profile list shares a profile by showing its code, as the Android list
 * does. The code holds the same `ss://` URL as `ProfileQr.ets`, and the
 * drawing is the same. The dialog owns no state that the page must keep: when
 * the URL does not encode, it reports the failure and closes, so the page
 * that stays open can show the message.
 */
@CustomDialog
export struct ShareQrDialog {
  controller: CustomDialogController;
  url: string = '';
  name: string = '';
  /** Reports a failure to the page that opened the dialog. */
  onError: (message: ResourceStr) => void = () => {
  };
  @State hasError: boolean = false;
  private code: QrCode | null = null;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  // not named `context`: that collides with the component framework's own field
  // and silently reads back undefined (see AGENTS.md)
  private painter: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    if (this.url.length === 0) {
      // an empty input is an encode failure: there is nothing to draw
      this.fail($r('app.string.qr_too_long'));
      return;
    }
    try {
      this.code = encodeQr(this.url, QR_EC_L);
    } catch (e) {
      // only reachable with a name long enough to push the URL past what a
      // version 40 code holds, which is close to three thousand characters
      const message = e instanceof Error ? e.message : '';
      this.fail(message.length > 0 ? message : $r('app.string.qr_too_long'));
      return;
    }
    this.draw();
  }

  /**
   * Reports the failure and closes the dialog. The zero-delay timer lets the
   * opener show its message before the dialog goes away.
   */
  private fail(message: ResourceStr): void {
    this.hasError = true;
    this.onError(message);
    // close() has no declared return type, so a block body keeps the arrow's
    // return type out of inference (arkts-no-implicit-return-types)
    setTimeout(() => {
      this.controller.close();
    }, 0);
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

  build() {
    Column({ space: 12 }) {
      Text($r('app.string.qr_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      if (this.hasError) {
        Text($r('app.string.qr_too_long'))
          .fontSize(14)
          .fontColor($r('app.color.error'))
      } else {
        Canvas(this.painter)
          .width(CODE_SIZE)
          .height(CODE_SIZE)
          .backgroundColor($r('app.color.surface'))
          .onReady(() => this.draw())
      }
      Text(this.name)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
      Button($r('app.string.common_ok'))
        .backgroundColor($r('app.color.accent_container'))
        .fontColor($r('app.color.on_container'))
        .onClick(() => this.controller.close())
    }
    .padding(20)
  }
}
