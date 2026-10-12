import { describe, expect, it } from '@ohos/hypium';
import { encodeQr, QrCode } from '../main/ets/model/QrCode';
import { QR_EC_H, QR_EC_L, QR_EC_M, QR_EC_Q } from '../main/ets/model/QrTables';
import { QR_SIZE_ENTRIES, QR_VECTORS } from './QrVectors';

/**
 * The encoder is checked against zxing, which is what shadowsocks-android
 * encodes its QR codes with, so a failure here means the code would scan as
 * something other than what the Android client would have shown.
 *
 * `QR_VECTORS` carries whole matrices for the small versions. `QR_SIZE_ENTRIES`
 * pins the version, the mask and a checksum of the matrix at both sides of
 * every version boundary, because a version 40 matrix is 177 rows of hex and
 * the encoder is the same code at every version.
 *
 * The golden data comes from tools/qr-oracle/run.sh. Regenerate it rather than
 * editing it.
 */

const HEX = '0123456789ABCDEF';

/** One row of a matrix as hex, four modules to a digit, as the vectors store it. */
function rowHex(qr: QrCode, y: number): string {
  let out = '';
  let nibble = 0;
  let count = 0;
  for (let x = 0; x < qr.size; x++) {
    nibble = (nibble << 1) | (qr.isDark(x, y) ? 1 : 0);
    count++;
    if (count === 4) {
      out += HEX.charAt(nibble);
      nibble = 0;
      count = 0;
    }
  }
  return count > 0 ? out + HEX.charAt(nibble << (4 - count)) : out;
}

/**
 * The checksum tools/qr-oracle writes, over the modules row by row. A modulus
 * keeps the running value below 2^53, where Java's wrapping int would not agree
 * with a JavaScript number.
 */
function digest(qr: QrCode): number {
  let hash = 0;
  for (let y = 0; y < qr.size; y++) {
    for (let x = 0; x < qr.size; x++) {
      hash = (hash * 131 + (qr.isDark(x, y) ? 1 : 0)) % 2147483647;
    }
  }
  return hash;
}

function repeated(character: string, count: number): string {
  let out = '';
  for (let i = 0; i < count; i++) {
    out += character;
  }
  return out;
}

export default function qrCodeTest() {
  describe('QrCodeTest', () => {
    for (const vector of QR_VECTORS) {
      it(`matches zxing for ${vector.name}`, 0, () => {
        const qr = encodeQr(vector.text, vector.ec);
        expect(qr.version).assertEqual(vector.version);
        expect(qr.maskPattern).assertEqual(vector.mask);
        expect(qr.size).assertEqual(vector.rows.length);
        for (let y = 0; y < vector.rows.length; y++) {
          const found = rowHex(qr, y);
          if (found !== vector.rows[y]) {
            throw new Error(`row ${y}: got ${found}, want ${vector.rows[y]}`);
          }
        }
      });
    }

    for (const entry of QR_SIZE_ENTRIES) {
      it(`matches zxing at level ${entry.ec}, ${entry.length} bytes`, 0, () => {
        const qr = encodeQr(repeated('a', entry.length), entry.ec);
        expect(qr.version).assertEqual(entry.version);
        expect(qr.maskPattern).assertEqual(entry.mask);
        expect(digest(qr)).assertEqual(entry.digest);
      });
    }

    it('sizes the matrix from the version', 0, () => {
      for (const ec of [QR_EC_L, QR_EC_M, QR_EC_Q, QR_EC_H]) {
        const qr = encodeQr('ss://YWVzLTI1Ni1nY206cHc@example.com:8388#Node', ec);
        expect(qr.size).assertEqual(qr.version * 4 + 17);
        expect(qr.modules.length).assertEqual(qr.size * qr.size);
      }
    });

    it('refuses an empty string', 0, () => {
      let threw = false;
      try {
        encodeQr('');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('refuses more than version 40 holds', 0, () => {
      let threw = false;
      try {
        encodeQr(repeated('a', 2954), QR_EC_L);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
