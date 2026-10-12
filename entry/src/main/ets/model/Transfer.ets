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

import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * The file name offered when exporting. shadowsocks-android writes the same
 * one, so a file from either client can be handed to the other.
 */
export const EXPORT_FILE_NAME = 'profiles.json';

/**
 * Reads the text of a file the user picks, or '' when they cancel.
 *
 * The document picker is what makes a file reachable at all: an app on this
 * platform cannot read outside its own sandbox without the user choosing the
 * file, which is the same bargain Android's storage access framework makes.
 */
export async function pickTextFile(context: common.Context): Promise<string> {
  const view = new picker.DocumentViewPicker(context);
  const uris = await view.select(new picker.DocumentSelectOptions());
  if (uris.length === 0) {
    return '';
  }
  return fs.readTextSync(uris[0]);
}

/** Writes `text` to a file the user picks, or returns '' when they cancel. */
export async function saveTextFile(context: common.Context, name: string, text: string): Promise<string> {
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = [name];
  const view = new picker.DocumentViewPicker(context);
  const uris = await view.save(options);
  if (uris.length === 0) {
    return '';
  }
  const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  return uris[0];
}

/**
 * The clipboard's text, or '' when it holds nothing readable.
 *
 * A profile carries a password, and the clipboard is readable by every other
 * app on the device. Both the copy and the paste are therefore explicit menu
 * actions rather than something that happens on its own.
 */
export async function readClipboard(): Promise<string> {
  const board = pasteboard.getSystemPasteboard();
  if (!await board.hasData()) {
    return '';
  }
  const data = await board.getData();
  return data.getPrimaryText();
}

export async function writeClipboard(text: string): Promise<void> {
  const board = pasteboard.getSystemPasteboard();
  await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
}
