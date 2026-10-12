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

import { Profile } from './Profile';
import {
  QR_ALIGNMENT_CENTERS, QR_EC_BITS, QR_EC_BLOCKS, QR_EC_CODEWORDS, QR_EC_L,
  QR_TOTAL_CODEWORDS,
} from './QrTables';

/**
 * A QR Code encoder: byte, alphanumeric and numeric modes.
 *
 * shadowsocks-android shows a profile's QR code by handing the `ss://` URL to
 * zxing, and a Java library cannot be linked into the app. This is that encoder
 * translated, so a code shown here scans as the same code. The specs in
 * `entry/src/test/QrCode.test.ets` compare it against zxing's own output, which
 * `tools/qr-oracle/` regenerates.
 *
 * Where a choice could go either way it goes zxing's way. That includes the
 * mask penalty rules, which are not quite the ones in the specification and
 * decide which of the eight masks every code uses.
 */

/** Encoding modes, in the order the mode indicator bits are indexed. */
const MODE_NUMERIC: number = 0;
const MODE_ALPHANUMERIC: number = 1;
const MODE_BYTE: number = 2;

/** Mode indicator, four bits each. */
const MODE_BITS: number[] = [0x1, 0x2, 0x4];

/** Character count width by mode and version group (1-9, 10-26, 27-40). */
const MODE_COUNT_BITS: number[][] = [
  [10, 12, 14],  // numeric
  [9, 11, 13],   // alphanumeric
  [8, 16, 16],   // byte
];

// --------------------------------------------------------------- bit buffer

/**
 * A stream of bits, most significant bit first. It holds the two operations the
 * encoder needs: append n bits of a value, and append another buffer. Bytes are
 * packed as they are written, because the interleaving step reads the data back
 * eight bits at a time.
 */
class BitBuffer {
  private bytes: number[] = [];
  private bits: number = 0;

  append(value: number, count: number): void {
    for (let i = count - 1; i >= 0; i--) {
      this.appendBit(((value >> i) & 1) === 1);
    }
  }

  appendBit(bit: boolean): void {
    const index = this.bits >> 3;
    if (index === this.bytes.length) {
      this.bytes.push(0);
    }
    if (bit) {
      this.bytes[index] |= 0x80 >> (this.bits & 7);
    }
    this.bits++;
  }

  appendBuffer(other: BitBuffer): void {
    const size = other.size();
    for (let i = 0; i < size; i++) {
      this.appendBit(other.bitAt(i));
    }
  }

  size(): number {
    return this.bits;
  }

  /** Whole bytes the bits occupy, the last one padded with zeroes. */
  sizeInBytes(): number {
    return (this.bits + 7) >> 3;
  }

  bitAt(index: number): boolean {
    return ((this.bytes[index >> 3] >> (7 - (index & 7))) & 1) === 1;
  }

  byteAt(index: number): number {
    return this.bytes[index];
  }
}

// ------------------------------------------------------------- galois field

/**
 * GF(256) with the QR Code primitive polynomial x^8 + x^4 + x^3 + x^2 + 1.
 *
 * The tables are built on first use rather than at module load, so that nothing
 * depends on the order an ArkTS module's top-level statements run in.
 */
let gfExp: number[] = [];
let gfLog: number[] = [];

function initGaloisField(): void {
  if (gfExp.length > 0) {
    return;
  }
  const exp: number[] = [];
  const log: number[] = [];
  for (let i = 0; i < 256; i++) {
    log.push(0);
  }
  let x = 1;
  for (let i = 0; i < 255; i++) {
    exp.push(x);
    log[x] = i;
    x <<= 1;
    if ((x & 0x100) !== 0) {
      x ^= 0x11d;
    }
  }
  // Doubled, so that a multiplication can add the two logs without a modulo step.
  for (let i = 255; i < 512; i++) {
    exp.push(exp[i - 255]);
  }
  gfExp = exp;
  gfLog = log;
}

function gfMultiply(a: number, b: number): number {
  if (a === 0 || b === 0) {
    return 0;
  }
  return gfExp[gfLog[a] + gfLog[b]];
}

/**
 * The generator polynomial of the given degree: the product of (x - a^i) for i
 * from 0 to degree - 1. Coefficients run from the highest power down, and the
 * leading one is 1.
 */
function rsGenerator(degree: number): number[] {
  let generator: number[] = [1];
  for (let i = 0; i < degree; i++) {
    const next: number[] = [];
    for (let j = 0; j <= generator.length; j++) {
      next.push(0);
    }
    for (let j = 0; j < generator.length; j++) {
      next[j] ^= generator[j];
      next[j + 1] ^= gfMultiply(generator[j], gfExp[i]);
    }
    generator = next;
  }
  return generator;
}

/**
 * The error correction codewords of one block: the remainder of the data
 * shifted up by `degree` places, divided by the generator polynomial.
 */
function rsRemainder(data: number[], degree: number): number[] {
  const generator = rsGenerator(degree);
  const remainder: number[] = [];
  for (let i = 0; i < data.length + degree; i++) {
    remainder.push(i < data.length ? data[i] : 0);
  }
  for (let i = 0; i < data.length; i++) {
    const factor = remainder[i];
    if (factor === 0) {
      continue;
    }
    for (let j = 1; j <= degree; j++) {
      remainder[i + j] ^= gfMultiply(generator[j], factor);
    }
  }
  return remainder.slice(data.length);
}

// ------------------------------------------------------------------ encoder

/** Which version group a version belongs to, which picks the count width. */
function versionGroup(version: number): number {
  if (version <= 9) {
    return 0;
  }
  return version <= 26 ? 1 : 2;
}

/**
 * The alphanumeric value of a character, or -1. The set is the one in the
 * specification: digits, capitals, then space and six punctuation marks.
 */
function alphanumericCode(c: string): number {
  const DIGITS = '0123456789';
  const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const PUNCTUATION = ' $%*+-./:';
  const digit = DIGITS.indexOf(c);
  if (digit >= 0) {
    return digit;
  }
  const letter = LETTERS.indexOf(c);
  if (letter >= 0) {
    return 10 + letter;
  }
  const punctuation = PUNCTUATION.indexOf(c);
  return punctuation >= 0 ? 36 + punctuation : -1;
}

/**
 * The most compact mode that holds the whole text, picked the way zxing picks
 * it: one mode for the string, never a mix of segments.
 */
function chooseMode(text: string): number {
  let hasNumeric = false;
  let hasAlphanumeric = false;
  for (let i = 0; i < text.length; i++) {
    const c = text.charAt(i);
    if (c >= '0' && c <= '9') {
      hasNumeric = true;
    } else if (alphanumericCode(c) >= 0) {
      hasAlphanumeric = true;
    } else {
      return MODE_BYTE;
    }
  }
  if (hasAlphanumeric) {
    return MODE_ALPHANUMERIC;
  }
  return hasNumeric ? MODE_NUMERIC : MODE_BYTE;
}

/** True when every character fits in one byte of ISO-8859-1. */
function isLatin1(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) > 0xff) {
      return false;
    }
  }
  return true;
}

function appendNumeric(text: string, bits: BitBuffer): void {
  let i = 0;
  while (i < text.length) {
    const first = text.charCodeAt(i) - 0x30;
    if (i + 2 < text.length) {
      bits.append(first * 100 + (text.charCodeAt(i + 1) - 0x30) * 10
        + (text.charCodeAt(i + 2) - 0x30), 10);
      i += 3;
    } else if (i + 1 < text.length) {
      bits.append(first * 10 + (text.charCodeAt(i + 1) - 0x30), 7);
      i += 2;
    } else {
      bits.append(first, 4);
      i += 1;
    }
  }
}

function appendAlphanumeric(text: string, bits: BitBuffer): void {
  let i = 0;
  while (i < text.length) {
    const first = alphanumericCode(text.charAt(i));
    if (i + 1 < text.length) {
      bits.append(first * 45 + alphanumericCode(text.charAt(i + 1)), 11);
      i += 2;
    } else {
      bits.append(first, 6);
      i += 1;
    }
  }
}

function appendBytes(bytes: number[], bits: BitBuffer): void {
  for (const byte of bytes) {
    bits.append(byte, 8);
  }
}

/** Data capacity of a version at a level: total codewords less correction. */
function dataCodewords(version: number, ecLevel: number): number {
  return QR_TOTAL_CODEWORDS[version]
    - QR_EC_CODEWORDS[ecLevel][version] * QR_EC_BLOCKS[ecLevel][version];
}

function willFit(numInputBits: number, version: number, ecLevel: number): boolean {
  return dataCodewords(version, ecLevel) >= ((numInputBits + 7) >> 3);
}

/** The smallest version that holds the bits, or an error past version 40. */
function chooseVersion(numInputBits: number, ecLevel: number): number {
  for (let version = 1; version <= 40; version++) {
    if (willFit(numInputBits, version, ecLevel)) {
      return version;
    }
  }
  throw new Error('the text is too long for a QR code');
}

/** Pads the bit stream out to the whole data capacity, as 8.4.8 and 8.4.9 say. */
function terminateBits(numDataBytes: number, bits: BitBuffer): void {
  const capacity = numDataBytes * 8;
  if (bits.size() > capacity) {
    throw new Error('the data bits do not fit the chosen version');
  }
  for (let i = 0; i < 4 && bits.size() < capacity; i++) {
    bits.appendBit(false);
  }
  const inLastByte = bits.size() & 7;
  if (inLastByte > 0) {
    for (let i = inLastByte; i < 8; i++) {
      bits.appendBit(false);
    }
  }
  const paddingBytes = numDataBytes - bits.sizeInBytes();
  for (let i = 0; i < paddingBytes; i++) {
    bits.append((i & 1) === 0 ? 0xec : 0x11, 8);
  }
}

/**
 * Data bytes of one block and the correction bytes that go with them.
 *
 * Blocks come in two sizes when the data does not divide evenly: the first
 * `numBlocks - remainder` hold one byte fewer than the rest.
 */
function blockDataBytes(version: number, ecLevel: number, index: number): number {
  const numTotalBytes = QR_TOTAL_CODEWORDS[version];
  const numRsBlocks = QR_EC_BLOCKS[ecLevel][version];
  const numDataBytes = dataCodewords(version, ecLevel);
  const blocksInGroup1 = numRsBlocks - (numTotalBytes % numRsBlocks);
  const bytesInGroup1 = Math.floor(numDataBytes / numRsBlocks);
  return index < blocksInGroup1 ? bytesInGroup1 : bytesInGroup1 + 1;
}

/**
 * Splits the data into blocks, adds the correction bytes, and reads the two
 * sets back out interleaved, which is the order the matrix takes them in.
 */
function interleaveWithEcBytes(bits: BitBuffer, version: number, ecLevel: number): BitBuffer {
  const numTotalBytes = QR_TOTAL_CODEWORDS[version];
  const numDataBytes = dataCodewords(version, ecLevel);
  const numRsBlocks = QR_EC_BLOCKS[ecLevel][version];
  const ecBytesPerBlock = QR_EC_CODEWORDS[ecLevel][version];
  if (bits.sizeInBytes() !== numDataBytes) {
    throw new Error('the bit stream is not the size the version calls for');
  }

  const dataBlocks: number[][] = [];
  const ecBlocks: number[][] = [];
  let offset = 0;
  let maxDataBytes = 0;
  let maxEcBytes = 0;
  for (let i = 0; i < numRsBlocks; i++) {
    const size = blockDataBytes(version, ecLevel, i);
    const data: number[] = [];
    for (let j = 0; j < size; j++) {
      data.push(bits.byteAt(offset + j));
    }
    const ec = rsRemainder(data, ecBytesPerBlock);
    dataBlocks.push(data);
    ecBlocks.push(ec);
    offset += size;
    maxDataBytes = Math.max(maxDataBytes, data.length);
    maxEcBytes = Math.max(maxEcBytes, ec.length);
  }
  if (offset !== numDataBytes) {
    throw new Error('the blocks do not add up to the data size');
  }

  const result = new BitBuffer();
  for (let i = 0; i < maxDataBytes; i++) {
    for (const block of dataBlocks) {
      if (i < block.length) {
        result.append(block[i], 8);
      }
    }
  }
  for (let i = 0; i < maxEcBytes; i++) {
    for (const block of ecBlocks) {
      if (i < block.length) {
        result.append(block[i], 8);
      }
    }
  }
  if (result.sizeInBytes() !== numTotalBytes) {
    throw new Error('the interleaved blocks are not the size the version calls for');
  }
  return result;
}

// ------------------------------------------------------------------- matrix

/** One module: not written yet, light, or dark. */
const UNSET = -1;
const LIGHT = 0;
const DARK = 1;

const POSITION_DETECTION_PATTERN: number[][] = [
  [1, 1, 1, 1, 1, 1, 1],
  [1, 0, 0, 0, 0, 0, 1],
  [1, 0, 1, 1, 1, 0, 1],
  [1, 0, 1, 1, 1, 0, 1],
  [1, 0, 1, 1, 1, 0, 1],
  [1, 0, 0, 0, 0, 0, 1],
  [1, 1, 1, 1, 1, 1, 1],
];

const POSITION_ADJUSTMENT_PATTERN: number[][] = [
  [1, 1, 1, 1, 1],
  [1, 0, 0, 0, 1],
  [1, 0, 1, 0, 1],
  [1, 0, 0, 0, 1],
  [1, 1, 1, 1, 1],
];

/** Where each bit of the format information goes, around the top-left finder. */
const TYPE_INFO_COORDINATES: number[][] = [
  [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
  [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
];

/** The generator polynomials of the two BCH codes, and the format mask. */
const VERSION_INFO_POLY = 0x1f25;
const TYPE_INFO_POLY = 0x537;
const TYPE_INFO_MASK = 0x5412;

/** The position of the highest set bit, counting from one, and zero for zero. */
function findMsb(value: number): number {
  let msb = 0;
  let rest = value;
  while (rest !== 0) {
    msb++;
    rest >>= 1;
  }
  return msb;
}

/** The BCH remainder that turns a format or version number into its code. */
function bchCode(value: number, poly: number): number {
  const msbInPoly = findMsb(poly);
  let remainder = value << (msbInPoly - 1);
  while (findMsb(remainder) >= msbInPoly) {
    remainder ^= poly << (findMsb(remainder) - msbInPoly);
  }
  return remainder;
}

/** The fifteen format bits: level and mask, with their error correction. */
function typeInfoBits(ecLevel: number, maskPattern: number): number[] {
  const typeInfo = (QR_EC_BITS[ecLevel] << 3) | maskPattern;
  const value = ((typeInfo << 10) | bchCode(typeInfo, TYPE_INFO_POLY)) ^ TYPE_INFO_MASK;
  const bits: number[] = [];
  for (let i = 14; i >= 0; i--) {
    bits.push((value >> i) & 1);
  }
  return bits;
}

/** The eighteen version bits, present from version 7 up. */
function versionInfoBits(version: number): number[] {
  const value = (version << 12) | bchCode(version, VERSION_INFO_POLY);
  const bits: number[] = [];
  for (let i = 17; i >= 0; i--) {
    bits.push((value >> i) & 1);
  }
  return bits;
}

/** The mask rule of a pattern, from 8.8 of the specification. */
function dataMaskBit(maskPattern: number, x: number, y: number): boolean {
  let intermediate = 0;
  switch (maskPattern) {
    case 0:
      intermediate = (y + x) & 1;
      break;
    case 1:
      intermediate = y & 1;
      break;
    case 2:
      intermediate = x % 3;
      break;
    case 3:
      intermediate = (y + x) % 3;
      break;
    case 4:
      intermediate = (Math.floor(y / 2) + Math.floor(x / 3)) & 1;
      break;
    case 5: {
      const temp = y * x;
      intermediate = (temp & 1) + (temp % 3);
      break;
    }
    case 6: {
      const temp = y * x;
      intermediate = ((temp & 1) + (temp % 3)) & 1;
      break;
    }
    default: {
      const temp = y * x;
      intermediate = ((temp % 3) + ((y + x) & 1)) & 1;
      break;
    }
  }
  return intermediate === 0;
}

/** Rule 1: runs of five or more modules of one colour. */
function penaltyForRuns(matrix: number[], size: number, horizontal: boolean): number {
  let penalty = 0;
  for (let i = 0; i < size; i++) {
    let runLength = 0;
    let previous = -1;
    for (let j = 0; j < size; j++) {
      const bit = horizontal ? matrix[i * size + j] : matrix[j * size + i];
      if (bit === previous) {
        runLength++;
      } else {
        if (runLength >= 5) {
          penalty += 3 + (runLength - 5);
        }
        runLength = 1;
        previous = bit;
      }
    }
    if (runLength >= 5) {
      penalty += 3 + (runLength - 5);
    }
  }
  return penalty;
}

/** Rule 2: every two by two block of one colour. */
function penaltyForBlocks(matrix: number[], size: number): number {
  let blocks = 0;
  for (let y = 0; y < size - 1; y++) {
    for (let x = 0; x < size - 1; x++) {
      const value = matrix[y * size + x];
      if (value === matrix[y * size + x + 1] && value === matrix[(y + 1) * size + x]
        && value === matrix[(y + 1) * size + x + 1]) {
        blocks++;
      }
    }
  }
  return 3 * blocks;
}

/** True when the cells from `from` up to `to` are all light. */
function rowIsLight(matrix: number[], size: number, y: number, from: number, to: number): boolean {
  if (from < 0 || size < to) {
    return false;
  }
  for (let i = from; i < to; i++) {
    if (matrix[y * size + i] === DARK) {
      return false;
    }
  }
  return true;
}

function columnIsLight(matrix: number[], size: number, x: number, from: number, to: number): boolean {
  if (from < 0 || size < to) {
    return false;
  }
  for (let i = from; i < to; i++) {
    if (matrix[i * size + x] === DARK) {
      return false;
    }
  }
  return true;
}

/**
 * Rule 3: the finder-like pattern 1:1:3:1:1 with four light cells beside it.
 *
 * zxing looks for the light cells on one side only, where the specification
 * asks for either side, so a code can hold a pattern the specification would
 * have penalised and still wear the mask zxing gives it. The mask has to come
 * out the same for the two encoders to agree, so the narrower rule is the one
 * that is copied.
 */
function penaltyForFinderLike(matrix: number[], size: number): number {
  let count = 0;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (x + 6 < size
        && matrix[y * size + x] === DARK
        && matrix[y * size + x + 1] === LIGHT
        && matrix[y * size + x + 2] === DARK
        && matrix[y * size + x + 3] === DARK
        && matrix[y * size + x + 4] === DARK
        && matrix[y * size + x + 5] === LIGHT
        && matrix[y * size + x + 6] === DARK
        && (rowIsLight(matrix, size, y, x - 4, x) || rowIsLight(matrix, size, y, x + 7, x + 11))) {
        count++;
      }
      if (y + 6 < size
        && matrix[y * size + x] === DARK
        && matrix[(y + 1) * size + x] === LIGHT
        && matrix[(y + 2) * size + x] === DARK
        && matrix[(y + 3) * size + x] === DARK
        && matrix[(y + 4) * size + x] === DARK
        && matrix[(y + 5) * size + x] === LIGHT
        && matrix[(y + 6) * size + x] === DARK
        && (columnIsLight(matrix, size, x, y - 4, y)
          || columnIsLight(matrix, size, x, y + 7, y + 11))) {
        count++;
      }
    }
  }
  return 40 * count;
}

/** Rule 4: how far the proportion of dark modules is from a half. */
function penaltyForBalance(matrix: number[], size: number): number {
  let dark = 0;
  for (const module of matrix) {
    if (module === DARK) {
      dark++;
    }
  }
  const total = size * size;
  return Math.floor(Math.abs(dark * 2 - total) * 10 / total) * 10;
}

function maskPenalty(matrix: number[], size: number): number {
  return penaltyForRuns(matrix, size, true) + penaltyForRuns(matrix, size, false)
    + penaltyForBlocks(matrix, size) + penaltyForFinderLike(matrix, size)
    + penaltyForBalance(matrix, size);
}

/** Writes the three finder patterns and the separators around them. */
function embedPositionDetectionPatterns(matrix: number[], size: number): void {
  const corners: number[][] = [[0, 0], [size - 7, 0], [0, size - 7]];
  for (const corner of corners) {
    for (let y = 0; y < 7; y++) {
      for (let x = 0; x < 7; x++) {
        matrix[(corner[1] + y) * size + corner[0] + x] = POSITION_DETECTION_PATTERN[y][x];
      }
    }
  }
  for (let x = 0; x < 8; x++) {
    matrix[7 * size + x] = LIGHT;
    matrix[7 * size + size - 8 + x] = LIGHT;
    matrix[(size - 8) * size + x] = LIGHT;
  }
  for (let y = 0; y < 7; y++) {
    matrix[y * size + 7] = LIGHT;
    matrix[y * size + size - 8] = LIGHT;
    matrix[(size - 7 + y) * size + 7] = LIGHT;
  }
}

/** The timing patterns, along row 6 and column 6. */
function embedTimingPatterns(matrix: number[], size: number): void {
  for (let i = 8; i < size - 8; i++) {
    const bit = (i + 1) % 2;
    if (matrix[6 * size + i] === UNSET) {
      matrix[6 * size + i] = bit;
    }
    if (matrix[i * size + 6] === UNSET) {
      matrix[i * size + 6] = bit;
    }
  }
}

/** The alignment patterns, on every version from 2 up. */
function embedAlignmentPatterns(matrix: number[], size: number, version: number): void {
  const centers = QR_ALIGNMENT_CENTERS[version];
  for (const cy of centers) {
    for (const cx of centers) {
      // The three that would land on a finder pattern are left out. The centre
      // of one of those is already set by then, which is the test for it.
      if (matrix[cy * size + cx] !== UNSET) {
        continue;
      }
      for (let y = 0; y < 5; y++) {
        for (let x = 0; x < 5; x++) {
          matrix[(cy - 2 + y) * size + cx - 2 + x] = POSITION_ADJUSTMENT_PATTERN[y][x];
        }
      }
    }
  }
}

/** The format information, in both of its copies, and the always-dark module. */
function embedTypeInfo(matrix: number[], size: number, ecLevel: number, maskPattern: number): void {
  const bits = typeInfoBits(ecLevel, maskPattern);
  for (let i = 0; i < 15; i++) {
    const bit = bits[14 - i];
    matrix[TYPE_INFO_COORDINATES[i][1] * size + TYPE_INFO_COORDINATES[i][0]] = bit;
    if (i < 8) {
      matrix[8 * size + size - i - 1] = bit;
    } else {
      matrix[(size - 7 + (i - 8)) * size + 8] = bit;
    }
  }
  matrix[(size - 8) * size + 8] = DARK;
}

/** The version information, in both of its copies, from version 7 up. */
function embedVersionInfo(matrix: number[], size: number, version: number): void {
  if (version < 7) {
    return;
  }
  const bits = versionInfoBits(version);
  let index = 17;
  for (let i = 0; i < 6; i++) {
    for (let j = 0; j < 3; j++) {
      const bit = bits[index];
      index--;
      matrix[(size - 11 + j) * size + i] = bit;
      matrix[i * size + size - 11 + j] = bit;
    }
  }
}

/**
 * Writes the codewords into the matrix, two columns at a time, up and down,
 * skipping the vertical timing pattern and every cell already written.
 */
function embedDataBits(matrix: number[], size: number, data: BitBuffer, maskPattern: number): void {
  let index = 0;
  let direction = -1;
  let x = size - 1;
  let y = size - 1;
  while (x > 0) {
    if (x === 6) {
      x -= 1;
    }
    while (y >= 0 && y < size) {
      for (let i = 0; i < 2; i++) {
        const column = x - i;
        if (matrix[y * size + column] !== UNSET) {
          continue;
        }
        let bit = false;
        if (index < data.size()) {
          bit = data.bitAt(index);
          index++;
        }
        // Past the end of the data the remaining cells stay light.
        if (dataMaskBit(maskPattern, column, y)) {
          bit = !bit;
        }
        matrix[y * size + column] = bit ? DARK : LIGHT;
      }
      y += direction;
    }
    direction = -direction;
    y += direction;
    x -= 2;
  }
  if (index !== data.size()) {
    throw new Error(`not every bit found a place: ${index} of ${data.size()}`);
  }
}

/** Lays out the whole matrix for one mask pattern. */
function buildMatrix(data: BitBuffer, ecLevel: number, version: number,
                     maskPattern: number): number[] {
  const size = version * 4 + 17;
  const matrix: number[] = [];
  for (let i = 0; i < size * size; i++) {
    matrix.push(UNSET);
  }
  embedPositionDetectionPatterns(matrix, size);
  embedAlignmentPatterns(matrix, size, version);
  embedTimingPatterns(matrix, size);
  embedTypeInfo(matrix, size, ecLevel, maskPattern);
  embedVersionInfo(matrix, size, version);
  embedDataBits(matrix, size, data, maskPattern);
  return matrix;
}

/** The mask with the lowest penalty, which is the one zxing would choose. */
function chooseMaskPattern(data: BitBuffer, ecLevel: number, version: number): number {
  let best = 0;
  let bestPenalty = -1;
  for (let maskPattern = 0; maskPattern < 8; maskPattern++) {
    const penalty = maskPenalty(buildMatrix(data, ecLevel, version, maskPattern),
      version * 4 + 17);
    // Strictly less, so a tie keeps the lower-numbered pattern, as zxing does.
    if (bestPenalty < 0 || penalty < bestPenalty) {
      bestPenalty = penalty;
      best = maskPattern;
    }
  }
  return best;
}

// --------------------------------------------------------------------- API

/** An encoded QR Code. */
export class QrCode {
  /** Version 1 to 40. */
  version: number = 1;
  /** Modules a side: 21 for version 1, four more for each version after. */
  size: number = 21;
  /** The mask pattern that was chosen, 0 to 7. */
  maskPattern: number = 0;
  /** The error correction level it was encoded with. */
  ecLevel: number = QR_EC_L;
  /**
   * The modules, row by row, dark as 1 and light as 0. Read them through
   * `isDark`, which is what the renderer and the specs use.
   */
  modules: number[] = [];

  isDark(x: number, y: number): boolean {
    return this.modules[y * this.size + x] === DARK;
  }
}

/**
 * Encodes `text` as a QR Code at the given error correction level.
 *
 * Throws when the text does not fit in version 40, which at the default level
 * is a little under three thousand bytes.
 */
export function encodeQr(text: string, ecLevel: number = QR_EC_L): QrCode {
  if (text.length === 0) {
    throw new Error('there is nothing to encode');
  }
  initGaloisField();

  const mode = chooseMode(text);
  // shadowsocks-android hints UTF-8 only when the text does not fit
  // ISO-8859-1, and zxing writes an ECI segment only in byte mode under that
  // hint. So the two encoders agree on the bytes and on when to announce them.
  const utf8 = !isLatin1(text);
  const useEci = utf8 && mode === MODE_BYTE;
  const dataBytes: number[] = [];
  if (mode === MODE_BYTE) {
    if (utf8) {
      for (const byte of Profile.encodeUtf8(text)) {
        dataBytes.push(byte);
      }
    } else {
      for (let i = 0; i < text.length; i++) {
        dataBytes.push(text.charCodeAt(i) & 0xff);
      }
    }
  }

  const header = new BitBuffer();
  if (useEci) {
    // The ECI mode indicator, then the assignment number of UTF-8.
    header.append(0x7, 4);
    header.append(26, 8);
  }
  header.append(MODE_BITS[mode], 4);

  const data = new BitBuffer();
  if (mode === MODE_NUMERIC) {
    appendNumeric(text, data);
  } else if (mode === MODE_ALPHANUMERIC) {
    appendAlphanumeric(text, data);
  } else {
    appendBytes(dataBytes, data);
  }

  const countWidth = (version: number): number => MODE_COUNT_BITS[mode][versionGroup(version)];
  const bitsNeeded = (version: number): number => header.size() + countWidth(version) + data.size();

  // The count width depends on the version and the version on the count width,
  // so the first guess assumes the narrowest one and one more pass settles it.
  const provisional = chooseVersion(bitsNeeded(1), ecLevel);
  const version = chooseVersion(bitsNeeded(provisional), ecLevel);

  const bits = new BitBuffer();
  bits.appendBuffer(header);
  bits.append(mode === MODE_BYTE ? dataBytes.length : text.length, countWidth(version));
  bits.appendBuffer(data);

  terminateBits(dataCodewords(version, ecLevel), bits);
  const finalBits = interleaveWithEcBytes(bits, version, ecLevel);

  const qr = new QrCode();
  qr.version = version;
  qr.size = version * 4 + 17;
  qr.ecLevel = ecLevel;
  qr.maskPattern = chooseMaskPattern(finalBits, ecLevel, version);
  qr.modules = buildMatrix(finalBits, ecLevel, version, qr.maskPattern);
  return qr;
}
