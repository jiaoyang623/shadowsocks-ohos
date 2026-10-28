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
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * The QR scanner adapter.
 *
 * The public SDK has no barcode decoder. Scan Kit supplies the system scanner
 * UI and an image decoder, so the app writes neither a camera preview nor a
 * decoder. The scanner UI owns the camera and its permission, and the app
 * adds no camera permission to the manifest.
 */

/** The documented Scan Kit code for a cancelled scan. */
const SCAN_CANCELLED: number = 1000500002;

/** The upper bound for one image batch. */
const MAX_IMAGES: number = 20;

/** The text of one scan, and whether the user cancelled the scan. */
export interface ScanText {
  text: string;
  cancelled: boolean;
}

/** The texts of a batch of images, and the first error the batch met. */
export interface ImageScan {
  texts: string[];
  error: string;
}

/**
 * One scan through the system scanner UI.
 *
 * The system UI owns the camera preview, the camera permission, the up
 * action, and the album entry. The function reports a cancel as a normal
 * result.
 */
export async function scanWithSystemUi(context: common.Context): Promise<ScanText> {
  const options: scanBarcode.ScanOptions = {
    scanTypes: [scanCore.ScanType.QR_CODE],
    enableMultiMode: false,
    enableAlbum: true,
  };
  try {
    const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
    return { text: result.originalValue, cancelled: false };
  } catch (e) {
    const err = e as BusinessError;
    if (err.code === SCAN_CANCELLED) {
      return { text: '', cancelled: true };
    }
    throw err as Error;
  }
}

/** The image URIs the user picks, or an empty list when they cancel. */
export async function pickQrImages(): Promise<string[]> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = MAX_IMAGES;
  const result: photoAccessHelper.PhotoSelectResult =
    await new photoAccessHelper.PhotoViewPicker().select(options);
  return result.photoUris;
}

/**
 * The texts of the QR codes in the chosen images, in pick order.
 *
 * One unreadable image does not stop the rest. The first error message is
 * kept, and the page shows it after the readable images import.
 */
export async function decodeQrImages(uris: string[]): Promise<ImageScan> {
  const texts: string[] = [];
  let error: string = '';
  for (const uri of uris) {
    const input: detectBarcode.InputImage = { uri: uri };
    const options: scanBarcode.ScanOptions = { scanTypes: [scanCore.ScanType.QR_CODE] };
    try {
      const found: scanBarcode.ScanResult[] = await detectBarcode.decode(input, options);
      if (found.length > 0) {
        texts.push(found[0].originalValue);
      }
    } catch (e) {
      if (error.length === 0) {
        error = messageOf(e as BusinessError);
      }
    }
  }
  return { texts: texts, error: error };
}

/** The first readable part of an error, or a stand-in when it has none. */
function messageOf(err: BusinessError): string {
  const message: string = err.message ?? '';
  if (message.length > 0) {
    return message;
  }
  return 'decode failed';
}
