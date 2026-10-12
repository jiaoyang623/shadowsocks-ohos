#!/usr/bin/env bash
#
# Refresh the vendored shadowsocks-service from the pinned core checkout.
#
# The crate is vendored so that the tun can answer DNS itself — see
# native/sslocal-ffi/vendor/shadowsocks-service.PATCH.md — and vendoring is
# only honest if it is reproducible. This re-copies the crate from the sibling
# checkout and re-applies the patch, so bumping the core's pin (the `ref` in
# .github/actions/rust-core/action.yml) is one command plus a rebase of the
# patch, rather than a hand-merge of two divergent trees.
#
# The patch and its write-up deliberately live *beside* the crate directory,
# not inside it: everything inside is replaced wholesale, and a file that
# documents the change should not be destroyed by the change being reapplied.
#
# Usage:  native/vendor-shadowsocks-service.sh [path-to-core-checkout]
#
# The default assumes the layout AGENTS.md describes: a shadowsocks-android
# checkout one level above this repository.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CORE_ROOT="${1:-$(cd "$REPO_ROOT/.." && pwd)/core}/src/main/rust/shadowsocks-rust"
SOURCE="$CORE_ROOT/crates/shadowsocks-service"

VENDOR_DIR="$REPO_ROOT/native/sslocal-ffi/vendor/shadowsocks-service"
PATCH="$REPO_ROOT/native/sslocal-ffi/vendor/shadowsocks-service.patch"

if [[ ! -d "$SOURCE" ]]; then
    echo "no shadowsocks-service at $SOURCE" >&2
    echo "pass the path to a core checkout if it is not a sibling of this repo" >&2
    exit 1
fi

if [[ ! -s "$PATCH" ]]; then
    echo "no patch at $PATCH; refusing to replace the vendored copy" >&2
    exit 1
fi

EXPECTED=$(grep -c '^diff --git' "$PATCH")

# The copy is patched somewhere outside any repository on purpose. Inside one,
# `git apply` resolves the patch's paths against the repository root rather
# than the working directory, so it finds nothing to patch and — this is the
# part that costs an afternoon — exits 0 having done nothing at all.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/shadowsocks-service"
cp -a "$SOURCE/." "$WORK/shadowsocks-service/"

(
    cd "$WORK/shadowsocks-service"
    git apply --check "$PATCH"
    git apply "$PATCH"
)

# Trust the count, not the exit status: a patch that silently patches nothing
# is the failure this script exists to rule out. `git diff --no-index` exits 1
# whenever there is a difference, which is always here, so its status has to be
# swallowed before `set -e` sees it.
ACTUAL=$(git diff --no-index --numstat "$SOURCE" "$WORK/shadowsocks-service" | wc -l | tr -d ' ' || true)
if [[ "$ACTUAL" -ne "$EXPECTED" ]]; then
    echo "error: the patch changed $ACTUAL file(s), expected $EXPECTED" >&2
    exit 1
fi

rm -rf "$VENDOR_DIR"
mkdir -p "$(dirname "$VENDOR_DIR")"
mv "$WORK/shadowsocks-service" "$VENDOR_DIR"

echo "vendored $SOURCE -> $VENDOR_DIR ($ACTUAL file(s) from the patch)"
