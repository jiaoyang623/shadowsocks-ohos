#!/usr/bin/env bash
#
# Regenerate the QR tables and the golden matrices from zxing.
#
# The ArkTS QR encoder in entry/src/main/ets/model/QrCode.ets has to agree with
# the encoder shadowsocks-android uses, which is zxing. This runs zxing itself
# and writes down what it produces, so the ArkTS specs compare against the
# library rather than against a second implementation of the same idea.
#
# Not part of CI: it needs a JDK and network access. Run it by hand after
# changing QrCode.ets, corpus.txt, or the zxing version, then commit the two
# generated files.
#
# Usage:
#   tools/qr-oracle/run.sh tables       # rewrite model/QrTables.ets
#   tools/qr-oracle/run.sh vectors      # rewrite test/QrVectors.ets
#   tools/qr-oracle/run.sh matrix L android 'HELLO'   # print one matrix
#
# JAVA_HOME, JAVA and JAVAC override the tools it looks for.
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
CACHE="$DIR/.cache"

# Pinned: a zxing upgrade can change which mask pattern wins, which changes
# every matrix here. Bumping this is a decision, not maintenance.
ZXING_VERSION=3.5.3
JAR="$CACHE/core-$ZXING_VERSION.jar"
JAR_URL="https://repo1.maven.org/maven2/com/google/zxing/core/$ZXING_VERSION/core-$ZXING_VERSION.jar"

find_tool() {
    local name="$1" override="$2"
    if [[ -n "$override" ]]; then
        printf '%s' "$override"
        return
    fi
    if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/$name" ]]; then
        printf '%s' "$JAVA_HOME/bin/$name"
        return
    fi
    command -v "$name" || true
}

JAVA_BIN="$(find_tool java "${JAVA:-}")"
JAVAC_BIN="$(find_tool javac "${JAVAC:-}")"
[[ -n "$JAVA_BIN" ]] || { echo "java not found; install a JDK 11 or newer" >&2; exit 1; }
[[ -n "$JAVAC_BIN" ]] || { echo "javac not found; install a JDK, not just a JRE" >&2; exit 1; }

mkdir -p "$CACHE"
if [[ ! -f "$JAR" ]]; then
    echo "fetching zxing $ZXING_VERSION" >&2
    curl -fsSL -o "$JAR.part" "$JAR_URL"
    mv "$JAR.part" "$JAR"
fi

CLASSES="$CACHE/classes"
mkdir -p "$CLASSES"
"$JAVAC_BIN" -cp "$JAR" -d "$CLASSES" "$DIR/ZxingOracle.java"

oracle() {
    "$JAVA_BIN" -cp "$CLASSES:$JAR" ZxingOracle "$@"
}

# Both generated files carry the same licence block as the rest of the sources.
emit() {
    local target="$1"
    shift
    {
        cat "$DIR/license-header.txt"
        echo
        oracle "$@"
    } > "$target"
    echo "wrote $target"
}

case "${1:-}" in
    tables)
        emit "$ROOT/entry/src/main/ets/model/QrTables.ets" tables
        ;;
    vectors)
        emit "$ROOT/entry/src/test/QrVectors.ets" vectors "$DIR/corpus.txt"
        ;;
    matrix)
        shift
        oracle matrix "$@"
        ;;
    *)
        sed -n '2,20p' "$0" | sed 's|^# \{0,1\}||'
        exit 1
        ;;
esac
