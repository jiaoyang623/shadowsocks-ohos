#!/usr/bin/env bash
#
# Run the model-layer ArkTS specs on the host.
#
# The ArkTS unit tests' own runner drives the SDK previewer, and its Linux build
# cannot execute the specs at all: it prints nothing and exits 0. AGENTS.md
# records the same finding for CI. Everything under entry/src/main/ets/model
# that needs no native API is plain logic, and this runs its specs in about a
# second, which is the difference between a test loop and a device round trip.
#
# The specs are the files DevEco runs, unchanged. tools/arkts-host supplies the
# stand-ins for @ohos/hypium and the @kit.* modules. The TypeScript compiler
# comes from the DevEco tools, so nothing is installed and nothing is added to
# the project's dependencies.
#
# Usage:  ./test-arkts-host.sh        (NODE=…, TSC=… to override either tool)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/entry/src/main/ets/model"
SPECS="$SCRIPT_DIR/entry/src/test"
SHIMS="$SCRIPT_DIR/tools/arkts-host"

NODE="${NODE:-node}"
command -v "$NODE" >/dev/null 2>&1 || {
    echo "node not found; install one or set NODE=/path/to/node" >&2
    exit 1
}

# tsc comes from the DevEco command-line tools: the SDK ships several copies
# and any of them will do. DEVECO_SDK_HOME points at <tools>/sdk, so the tools
# root is one level up.
find_tsc() {
    if [[ -n "${TSC:-}" ]]; then
        printf '%s' "$TSC"
        return
    fi
    if command -v tsc >/dev/null 2>&1; then
        command -v tsc
        return
    fi
    local root hit
    for root in "${DEVECO_TOOLS:-}" \
                "$(dirname "${DEVECO_SDK_HOME:-/nonexistent}")" \
                /opt/harmony/sdk \
                "$HOME/command-line-tools" \
                "$HOME/Downloads/command-line-tools"; do
        [[ -n "$root" && -d "$root" ]] || continue
        # The compiler itself rather than the launcher: a .bin/tsc in the DevEco
        # bundle can point at a file that is not in the bundle, fail to load, and
        # leave the run with no output and a success-looking exit.
        hit=$(find "$root" -maxdepth 6 -path '*/typescript/lib/tsc.js' -print -quit 2>/dev/null)
        if [[ -n "$hit" ]]; then
            printf '%s' "$hit"
            return
        fi
    done
}

TSC_BIN=$(find_tsc)
[[ -n "$TSC_BIN" ]] || {
    echo "tsc not found; set TSC=/path/to/tsc (it ships with the DevEco tools)" >&2
    exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/model" "$WORK/test"

# .ets is .ts with a different extension; the only change the sources need is
# the shims in place of the kits.
rewrite() {
    sed -E \
        -e "s|from '\.\./main/ets/model/([A-Za-z0-9_.]+)'|from '../model/\1'|g" \
        -e "s|from '@ohos/hypium'|from '../hypium'|g" \
        -e "s|from '@kit\.[A-Za-z0-9_]+'|from '../stubs'|g" \
        -e "s|from '@ohos\.[A-Za-z0-9_]+'|from '../stubs'|g" \
        "$1"
}

for file in "$SRC"/*.ets; do
    rewrite "$file" > "$WORK/model/$(basename "${file%.ets}").ts"
done
for file in "$SPECS"/*.ets; do
    rewrite "$file" > "$WORK/test/$(basename "${file%.ets}").ts"
done
cp "$SHIMS/hypium.ts" "$SHIMS/stubs.ts" "$SHIMS/run.ts" "$WORK/"

# Type errors are reported but do not stop the run: the model layer is checked
# by the ArkTS compiler in the build, and what matters here is that the logic
# behaves. A syntax error does stop it, with tsc's message and a non-zero exit.
set +e
# A .js path is run through node, because that is all TypeScript ships.
if [[ "$TSC_BIN" == *.js ]]; then
    TSC_CMD=("$NODE" "$TSC_BIN")
else
    TSC_CMD=("$TSC_BIN")
fi

"${TSC_CMD[@]}" --module node16 --target es2022 --moduleResolution node16 \
    --skipLibCheck --noImplicitAny false --outDir "$WORK/out" "$WORK/run.ts" > "$WORK/tsc.log" 2>&1
TSC_STATUS=$?
set -e
TSC_ERRORS=$(grep -c "error TS" "$WORK/tsc.log" || true)
if [[ "$TSC_STATUS" -ne 0 && "$TSC_ERRORS" -gt 0 && ! -f "$WORK/out/run.js" ]]; then
    echo "the sources did not compile:" >&2
    grep "error TS" "$WORK/tsc.log" | head -20 >&2
    exit 1
fi

echo "=== ArkTS model specs (host) ==="
"$NODE" "$WORK/out/run.js"
if [[ "$TSC_ERRORS" -gt 0 ]]; then
    echo "($TSC_ERRORS TypeScript diagnostic(s); the ArkTS compiler in the build is authoritative)"
    grep "error TS" "$WORK/tsc.log" | sed 's|^|    |' | head -10
fi
