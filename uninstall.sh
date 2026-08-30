#!/usr/bin/env bash
# uninstall.sh — revert proxy mimalloc FPS unlock
#
# Restores the original libmimalloc.3.dylib, removes FFlags,
# and resets FramerateCap to default (120).

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROBLOX_APP="/Applications/Roblox.app"
MACOS_DIR="$ROBLOX_APP/Contents/MacOS"

echo -e "${CYAN}===[ Uninstalling FPS Unlocker ]===${NC}"

killall -9 RobloxPlayer 2>/dev/null || true

# Restore original mimalloc
if [ -f "$MACOS_DIR/libmimalloc.3_original.dylib" ]; then
    cp "$MACOS_DIR/libmimalloc.3_original.dylib" "$MACOS_DIR/libmimalloc.3.dylib"
    rm -f "$MACOS_DIR/libmimalloc.3_original.dylib"
    echo -e "${GREEN}✔ Restored original libmimalloc.3.dylib${NC}"
else
    echo -e "${YELLOW}⚠ No backup found, reinstall Roblox to restore${NC}"
fi

# Remove FFlags file
if [ -f "$MACOS_DIR/ClientSettings/ClientAppSettings.json" ]; then
    rm -f "$MACOS_DIR/ClientSettings/ClientAppSettings.json"
    echo -e "${GREEN}✔ Removed FFlags${NC}"
fi

# Reset FramerateCap
SETTINGS_XML="$HOME/Library/Roblox/GlobalBasicSettings_13.xml"
if [ -f "$SETTINGS_XML" ]; then
    sed -i '' -E 's/<int name="FramerateCap">[0-9]+<\/int>/<int name="FramerateCap">120<\/int>/g' "$SETTINGS_XML"
    echo -e "${GREEN}✔ Reset FramerateCap to 120${NC}"
fi

# Re-sign
codesign --force --deep --sign - "$ROBLOX_APP" 2>/dev/null || true
echo -e "${GREEN}✔ Re-signed${NC}"

echo
echo -e "${GREEN}Done! Roblox is back to stock.${NC}"