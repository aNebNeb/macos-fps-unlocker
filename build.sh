#!/usr/bin/env bash
# build.sh — compile + sign fpsunlock.dylib
set -euo pipefail

cd "$(dirname "$0")"

OUT="fpsunlock.dylib"

# Compile as a dylib for arm64, linking the frameworks we use.
clang -dynamiclib -arch arm64e \
    -fobjc-arc \
    -framework Foundation \
    -framework QuartzCore \
    -framework AppKit \
    -framework Metal \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -mmacosx-version-min=11.0 \
    -O2 \
    -o "$OUT" \
    fpsunlock.m

# Ad-hoc sign so it loads under the patched (re-signed) Roblox.
codesign --force --sign - "$OUT"

echo
echo "Built: $OUT"
file "$OUT"
otool -L "$OUT" | head
echo
echo "Signed:"
codesign -dv "$OUT" 2>&1 | head