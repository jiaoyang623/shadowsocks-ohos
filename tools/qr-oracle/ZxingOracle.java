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

import com.google.zxing.EncodeHintType;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import com.google.zxing.qrcode.decoder.Version;
import com.google.zxing.qrcode.encoder.ByteMatrix;
import com.google.zxing.qrcode.encoder.Encoder;
import com.google.zxing.qrcode.encoder.QRCode;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The verification oracle for the ArkTS QR encoder: zxing itself.
 *
 * shadowsocks-android shows a profile's QR code by handing the `ss://` URL to
 * zxing's `MultiFormatWriter`, so zxing is the definition of what the code has
 * to contain. Running the same library here, rather than an independent
 * encoder, is what makes a mismatch a real defect instead of a difference of
 * opinion.
 *
 * Three subcommands:
 *
 *   tables          print the per-version tables as the ArkTS source of
 *                   `entry/src/main/ets/model/QrTables.ets`
 *   matrix EC MODE TEXT
 *                   one matrix as text, for looking at by hand
 *   vectors FILE    read a corpus, encode every entry, and print the ArkTS
 *                   source of `entry/src/test/QrVectors.ets`
 *
 * MODE selects the charset hint, which is what decides whether an ECI segment
 * goes into the bit stream:
 *
 *   android   what the Android client does: hint UTF-8 only when the text does
 *             not fit ISO-8859-1 (default)
 *   none      no hint at all, so ISO-8859-1 and no ECI
 *   utf8      always hint UTF-8
 *
 * The corpus format is one entry per line:
 *
 *   name <TAB> EC <TAB> TEXT
 *
 * where EC is one of L, M, Q, H, blank lines and lines starting with # are
 * skipped, and TEXT understands the escapes \n, \t, \\ and \e for the empty
 * string.
 */
public final class ZxingOracle {

    private static final ErrorCorrectionLevel[] LEVELS = {
        ErrorCorrectionLevel.L, ErrorCorrectionLevel.M,
        ErrorCorrectionLevel.Q, ErrorCorrectionLevel.H,
    };
    private static final String[] LEVEL_NAMES = {"L", "M", "Q", "H"};
    private static final String HEX = "0123456789ABCDEF";

    private static final Charset LATIN1 = StandardCharsets.ISO_8859_1;

    private ZxingOracle() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            usage();
            return;
        }
        switch (args[0]) {
            case "tables":
                tables();
                break;
            case "matrix":
                matrix(args);
                break;
            case "vectors":
                vectors(Path.of(args[1]));
                break;
            default:
                usage();
        }
    }

    private static void usage() {
        System.err.println("usage: ZxingOracle tables");
        System.err.println("       ZxingOracle matrix <L|M|Q|H> <android|none|utf8> <text>");
        System.err.println("       ZxingOracle vectors <corpus-file>");
    }

    private static int levelIndex(String name) {
        for (int i = 0; i < LEVEL_NAMES.length; i++) {
            if (LEVEL_NAMES[i].equalsIgnoreCase(name)) {
                return i;
            }
        }
        throw new IllegalArgumentException("no such error correction level: " + name);
    }

    /** Encodes with the hint rule the caller selected. */
    private static QRCode encode(String text, ErrorCorrectionLevel level, String mode)
            throws Exception {
        Map<EncodeHintType, Object> hints = null;
        switch (mode) {
            case "none":
                break;
            case "utf8":
                hints = new HashMap<>();
                hints.put(EncodeHintType.CHARACTER_SET, StandardCharsets.UTF_8.name());
                break;
            case "android":
                // Profile.toUri()'s output is Latin-1 unless the name carries
                // something outside it, and the client hints UTF-8 exactly then.
                if (!LATIN1.newEncoder().canEncode(text)) {
                    hints = new HashMap<>();
                    hints.put(EncodeHintType.CHARACTER_SET, StandardCharsets.UTF_8.name());
                }
                break;
            default:
                throw new IllegalArgumentException("no such hint mode: " + mode);
        }
        return Encoder.encode(text, level, hints);
    }

    /** One row of the matrix as hex, four modules to a digit, x ascending. */
    private static String rowHex(ByteMatrix matrix, int y) {
        StringBuilder out = new StringBuilder();
        int nibble = 0;
        int count = 0;
        for (int x = 0; x < matrix.getWidth(); x++) {
            nibble = (nibble << 1) | (matrix.get(x, y) == 1 ? 1 : 0);
            if (++count == 4) {
                out.append(HEX.charAt(nibble));
                nibble = 0;
                count = 0;
            }
        }
        if (count > 0) {
            out.append(HEX.charAt(nibble << (4 - count)));
        }
        return out.toString();
    }

    // ---------------------------------------------------------------- tables

    private static void tables() {
        StringBuilder sb = new StringBuilder();
        sb.append("""
                /**
                 * Per-version QR Code tables, in the shape zxing uses them.
                 *
                 * Generated from zxing 3.5.3 by tools/qr-oracle/run.sh. Do not edit:
                 * change the generator and run it again, so the numbers come from
                 * the same library the Android client encodes with.
                 */

                /** Error-correction levels; the row index into the tables below. */
                export const QR_EC_L: number = 0;
                export const QR_EC_M: number = 1;
                export const QR_EC_Q: number = 2;
                export const QR_EC_H: number = 3;

                /**
                 * Level indicator as it appears in the format information. This is
                 * not the row index: L is 1, M is 0, Q is 3, H is 2.
                 */
                export const QR_EC_BITS: number[] = [1, 0, 3, 2];

                /** Total codewords of the version, data and error correction together. */
                """);
        sb.append("export const QR_TOTAL_CODEWORDS: number[] = [0");
        for (int v = 1; v <= 40; v++) {
            sb.append(", ").append(Version.getVersionForNumber(v).getTotalCodewords());
        }
        sb.append("];\n\n");

        sb.append("/** Error correction codewords in each block, by level and version. */\n");
        sb.append("export const QR_EC_CODEWORDS: number[][] = [\n");
        for (int i = 0; i < 4; i++) {
            sb.append("  [0");
            for (int v = 1; v <= 40; v++) {
                sb.append(", ")
                  .append(Version.getVersionForNumber(v).getECBlocksForLevel(LEVELS[i])
                                     .getECCodewordsPerBlock());
            }
            sb.append(i == 3 ? "],\n" : "],\n");
        }
        sb.append("];\n\n");

        sb.append("/** Blocks the data is split into, by level and version. */\n");
        sb.append("export const QR_EC_BLOCKS: number[][] = [\n");
        for (int i = 0; i < 4; i++) {
            sb.append("  [0");
            for (int v = 1; v <= 40; v++) {
                sb.append(", ")
                  .append(Version.getVersionForNumber(v).getECBlocksForLevel(LEVELS[i]).getNumBlocks());
            }
            sb.append("],\n");
        }
        sb.append("];\n\n");

        sb.append("""
                /**
                 * Centres of the alignment patterns. Version 1 has none, and the
                 * entry at index 0 is a filler so that a version indexes its own row.
                 */
                """);
        sb.append("export const QR_ALIGNMENT_CENTERS: number[][] = [\n  [],\n");
        for (int v = 1; v <= 40; v++) {
            int[] centers = Version.getVersionForNumber(v).getAlignmentPatternCenters();
            sb.append("  [");
            for (int j = 0; j < centers.length; j++) {
                if (j > 0) {
                    sb.append(", ");
                }
                sb.append(centers[j]);
            }
            sb.append(v == 40 ? "],\n" : "],\n");
        }
        sb.append("];\n");
        System.out.print(sb);
    }

    // ---------------------------------------------------------------- matrix

    private static void matrix(String[] args) throws Exception {
        if (args.length < 4) {
            usage();
            return;
        }
        QRCode qr = encode(unescape(args[3]), LEVELS[levelIndex(args[1])], args[2]);
        ByteMatrix matrix = qr.getMatrix();
        System.out.printf("version %d, mask %d, size %d%n",
                qr.getVersion().getVersionNumber(), qr.getMaskPattern(), matrix.getWidth());
        for (int y = 0; y < matrix.getHeight(); y++) {
            StringBuilder row = new StringBuilder();
            for (int x = 0; x < matrix.getWidth(); x++) {
                row.append(matrix.get(x, y) == 1 ? '#' : '.');
            }
            System.out.println(row);
        }
    }

    // --------------------------------------------------------------- vectors

    /**
     * A checksum of the whole matrix, so a high version can be compared without
     * carrying 177 rows of hex through the corpus.
     *
     * Deliberately not FNV: Java ints wrap and JavaScript numbers do not, and
     * the ArkTS side has to compute the same value. `h * 131` stays far below
     * 2^53, so this is exact on both.
     */
    private static long digest(ByteMatrix matrix) {
        long h = 0;
        for (int y = 0; y < matrix.getHeight(); y++) {
            for (int x = 0; x < matrix.getWidth(); x++) {
                h = (h * 131 + (matrix.get(x, y) == 1 ? 1 : 0)) % 2147483647L;
            }
        }
        return h;
    }

    /**
     * The lengths at which the chosen version changes, one step either side of
     * every boundary.
     *
     * A full matrix for version 40 is 177 rows of hex, and the encoder is the
     * same code at every version — what changes is the tables. Pinning the
     * version and the mask at both sides of every boundary checks those, and
     * the checksum catches a matrix that is wrong in a way the mask does not.
     */
    private static List<String> sizeSweep() throws Exception {
        List<String> entries = new ArrayList<>();
        for (int level = 0; level < 4; level++) {
            // Levels other than L stop at version 10: past that they repeat what
            // L already covers, at a length that costs the ArkTS encoder seconds.
            int lastVersion = level == 0 ? 40 : 10;
            int previousVersion = 0;
            for (int n = 1; ; n++) {
                QRCode qr;
                try {
                    qr = Encoder.encode("a".repeat(n), LEVELS[level], null);
                } catch (Exception e) {
                    break;  // past the largest version there is
                }
                int version = qr.getVersion().getVersionNumber();
                if (version > lastVersion) {
                    break;
                }
                if (version == previousVersion) {
                    continue;
                }
                // n is the first length that needs `version`, so n - 1 is the
                // last one that fits the version below it.
                if (previousVersion > 0) {
                    entries.add(sizeEntry(level, n - 1, previousVersion));
                }
                entries.add(sizeEntry(level, n, version));
                previousVersion = version;
            }
        }
        return entries;
    }

    private static String sizeEntry(int level, int length, int version) throws Exception {
        QRCode qr = Encoder.encode("a".repeat(length), LEVELS[level], null);
        return "  new QrSizeEntry(%d, %d, %d, %d, %d),\n".formatted(
                level, length, version, qr.getMaskPattern(), digest(qr.getMatrix()));
    }

    private static void vectors(Path corpus) throws IOException {
        List<String> lines = Files.readAllLines(corpus, StandardCharsets.UTF_8);
        List<String> entries = new ArrayList<>();
        int index = 0;
        for (String raw : lines) {
            String line = raw;
            if (line.isBlank() || line.startsWith("#")) {
                continue;
            }
            String[] parts = line.split("\t", -1);
            if (parts.length != 3) {
                throw new IllegalArgumentException("corpus line " + (index + 1)
                        + ": expected name, level and text separated by tabs");
            }
            String name = parts[0];
            ErrorCorrectionLevel level = LEVELS[levelIndex(parts[1])];
            String text = unescape(parts[2]);
            QRCode qr;
            try {
                qr = encode(text, level, "android");
            } catch (Exception e) {
                throw new IllegalStateException("corpus entry '" + name + "' does not encode: "
                        + e.getMessage(), e);
            }
            ByteMatrix m = qr.getMatrix();
            StringBuilder rows = new StringBuilder();
            for (int y = 0; y < m.getHeight(); y++) {
                if (y > 0) {
                    rows.append(", ");
                }
                rows.append('\'').append(rowHex(m, y)).append('\'');
            }
            entries.add("""
                      new QrVector(%s, %s, %d, %d, %s, [
                    %s,
                  ]),
                """.formatted(
                    quote(name), levelIndex(parts[1]) + "",
                    qr.getVersion().getVersionNumber(), qr.getMaskPattern(),
                    quote(text), rows.toString()));
            index++;
        }

        StringBuilder sb = new StringBuilder();
        sb.append("""
                /**
                 * Golden QR matrices, produced by zxing 3.5.3 — the encoder
                 * shadowsocks-android uses — through tools/qr-oracle/run.sh.
                 *
                 * Do not edit by hand: add a line to tools/qr-oracle/corpus.txt and
                 * regenerate. Each row is one line of the module matrix, packed four
                 * modules to a hex digit, x ascending, the last digit padded with
                 * zeroes.
                 */
                export class QrVector {
                  name: string;
                  ec: number;
                  version: number;
                  mask: number;
                  text: string;
                  rows: string[];

                  constructor(name: string, ec: number, version: number, mask: number,
                              text: string, rows: string[]) {
                    this.name = name;
                    this.ec = ec;
                    this.version = version;
                    this.mask = mask;
                    this.text = text;
                    this.rows = rows;
                  }
                }

                /**
                 * A length at which the version changes, and what zxing makes of it.
                 * This is how the versions whose matrices are too large to carry
                 * around are still pinned.
                 */
                export class QrSizeEntry {
                  ec: number;
                  length: number;
                  version: number;
                  mask: number;
                  digest: number;

                  constructor(ec: number, length: number, version: number, mask: number,
                              digest: number) {
                    this.ec = ec;
                    this.length = length;
                    this.version = version;
                    this.mask = mask;
                    this.digest = digest;
                  }
                }

                """);
        sb.append("export const QR_VECTORS: QrVector[] = [\n");
        for (String entry : entries) {
            sb.append(entry);
        }
        sb.append("];\n\n");

        sb.append("export const QR_SIZE_ENTRIES: QrSizeEntry[] = [\n");
        List<String> sizes;
        try {
            sizes = sizeSweep();
        } catch (Exception e) {
            throw new IllegalStateException("the size sweep failed", e);
        }
        for (String entry : sizes) {
            sb.append(entry);
        }
        sb.append("];\n");
        System.out.print(sb);
        System.err.printf("%d vectors, %d size entries%n", entries.size(), sizes.size());
    }

    /** An ArkTS single-quoted literal for the text. */
    private static String quote(String text) {
        StringBuilder out = new StringBuilder("'");
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '\\': out.append("\\\\"); break;
                case '\'': out.append("\\'"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default: out.append(c);
            }
        }
        return out.append('\'').toString();
    }

    /** The corpus escapes: \\n, \\t, \\\\ and \\e for nothing at all. */
    private static String unescape(String text) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c != '\\' || i + 1 >= text.length()) {
                out.append(c);
                continue;
            }
            char next = text.charAt(++i);
            switch (next) {
                case 'n': out.append('\n'); break;
                case 't': out.append('\t'); break;
                case '\\': out.append('\\'); break;
                case 'e': break;
                default:
                    out.append('\\').append(next);
            }
        }
        return out.toString();
    }
}
