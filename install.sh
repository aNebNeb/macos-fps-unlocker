#!/usr/bin/env bash
# install.sh — macOS Roblox FPS Unlocker (experimental)
#
# WARNING: This modifies your Roblox.app bundle by replacing libmimalloc.3.dylib
# with a proxy that injects FPS unlock code. This is detectable by Roblox's
# anti-cheat and MAY result in a ban. Use at your own risk.
#
# What it does:
#   1. Backs up the original libmimalloc.3.dylib
#   2. Installs a proxy dylib that re-exports mimalloc + forces vsync off
#   3. Writes FFlags (ClientAppSettings.json) to uncap TaskScheduler FPS
#   4. Sets FramerateCap in GlobalBasicSettings to 10000
#   5. Re-signs the bundle ad-hoc (strips hardened runtime)
#
# To uninstall: run uninstall.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ROBLOX_APP="/Applications/Roblox.app"
MACOS_DIR="$ROBLOX_APP/Contents/MacOS"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}${CYAN}===[ macOS Roblox FPS Unlocker (experimental) ]===${NC}"
echo -e "${YELLOW}⚠  WARNING: This modifies Roblox.app and is detectable by anti-cheat.${NC}"
echo -e "${YELLOW}⚠  This MAY result in a ban. Use at your own risk.${NC}"
echo
read -p "Continue? (y/N) " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "Aborted."; exit 0; }

# ── Check Roblox exists ──
if [ ! -d "$ROBLOX_APP" ]; then
    echo -e "${RED}Roblox.app not found at $ROBLOX_APP${NC}"
    exit 1
fi

# ── Kill Roblox if running ──
echo -e "${CYAN}[...] Killing Roblox${NC}"
killall -9 RobloxPlayer 2>/dev/null || true
echo -e "${GREEN}✔ Roblox killed${NC}"

# ── Write FFlags ──
echo -e "${CYAN}[...] Writing FFlags${NC}"
mkdir -p "$MACOS_DIR/ClientSettings"
cat > "$MACOS_DIR/ClientSettings/ClientAppSettings.json" <<'FFLAGS'
{
    "DFIntTaskSchedulerTargetFps": "10000",
    "FFlagTaskSchedulerLimitTargetFpsTo2402": "False"
}
FFLAGS
echo -e "${GREEN}✔ FFlags written${NC}"

# ── Set FramerateCap in GlobalBasicSettings ──
echo -e "${CYAN}[...] Setting FramerateCap${NC}"
SETTINGS_XML="$HOME/Library/Roblox/GlobalBasicSettings_13.xml"
if [ -f "$SETTINGS_XML" ]; then
    sed -i '' -E 's/<int name="FramerateCap">[0-9]+<\/int>/<int name="FramerateCap">10000<\/int>/g' "$SETTINGS_XML"
    echo -e "${GREEN}✔ FramerateCap set to 10000${NC}"
else
    echo -e "${YELLOW}⚠ GlobalBasicSettings not found, skipping FramerateCap${NC}"
fi

# ── Install proxy mimalloc ──
echo -e "${CYAN}[...] Installing proxy libmimalloc.3.dylib${NC}"

if [ ! -f "$MACOS_DIR/libmimalloc.3.dylib" ]; then
    echo -e "${RED}libmimalloc.3.dylib not found in Roblox bundle${NC}"
    exit 1
fi

# Backup original if not already backed up
if [ ! -f "$MACOS_DIR/libmimalloc.3_original.dylib" ]; then
    cp "$MACOS_DIR/libmimalloc.3.dylib" "$MACOS_DIR/libmimalloc.3_original.dylib"
fi

# Install the proxy
if [ -f "$SCRIPT_DIR/proxy_mimalloc.dylib" ]; then
    cp "$SCRIPT_DIR/proxy_mimalloc.dylib" "$MACOS_DIR/libmimalloc.3.dylib"
elif [ -f "$SCRIPT_DIR/proxy_mimalloc.m" ] && [ -f "$SCRIPT_DIR/reexport.map" ]; then
    # Build from source
    echo -e "${CYAN}[...] Building proxy from source${NC}"
    clang -dynamiclib -arch arm64 \
        -fobjc-arc \
        -framework Foundation \
        -framework QuartzCore \
        -framework AppKit \
        -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
        -mmacosx-version-min=11.0 \
        -O2 \
        -install_name @rpath/libmimalloc.3.dylib \
        -Xlinker -reexport_library \
        -Xlinker "$MACOS_DIR/libmimalloc.3_original.dylib" \
        -o "$MACOS_DIR/libmimalloc.3.dylib" \
        "$SCRIPT_DIR/proxy_mimalloc.m"
else
    echo -e "${RED}No proxy dylib or source found${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Proxy installed${NC}"

# ── Re-sign bundle ──
echo -e "${CYAN}[...] Re-signing Roblox.app (ad-hoc)${NC}"
codesign --force --sign - "$MACOS_DIR/libmimalloc.3_original.dylib"
codesign --force --sign - "$MACOS_DIR/libmimalloc.3.dylib"
codesign --force --deep --sign - "$ROBLOX_APP"
echo -e "${GREEN}✔ Re-signed${NC}"

echo
echo -e "${GREEN}${BOLD}Done! Launch Roblox normally — FPS is uncapped.${NC}"
echo -e "${YELLOW}⚠ To uninstall, run uninstall.sh${NC}"