#!/bin/bash
# unlockfpsmac.command — macOS Roblox FPS Unlocker (experimental)
#
# WARNING: This modifies your Roblox.app bundle and is detectable by
# anti-cheat. This MAY result in a ban. Use at your own risk.
#
# What it does:
#   1. Installs a prebuilt proxy libmimalloc.3.dylib that re-exports the
#      original mimalloc and forces Metal vsync off (no swizzling, just
#      direct property writes on a timer)
#   2. Writes FFlags to uncap TaskScheduler FPS
#   3. Sets FramerateCap to 10000 in GlobalBasicSettings
#   4. Re-signs the bundle ad-hoc (strips hardened runtime)
#
# No Xcode or compiler needed — uses prebuilt binaries from this repo.
#
# To revert: run this script again and choose "Revert to stock"

set -euo pipefail

ROBLOX_APP="/Applications/Roblox.app"
MACOS_DIR="$ROBLOX_APP/Contents/MacOS"
MIMALLOC="$MACOS_DIR/libmimalloc.3.dylib"
MIMALLOC_ORIG="$MACOS_DIR/libmimalloc.3_original.dylib"
SETTINGS_XML="$HOME/Library/Roblox/GlobalBasicSettings_13.xml"

# Script directory (where the prebuilt binaries live)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_DYLIB="$SCRIPT_DIR/proxy_mimalloc.dylib"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="${GREEN}✔${NC}"
CROSS="${RED}✖${NC}"
INFO="${CYAN}➜${NC}"
WARN="${YELLOW}⚠${NC}"

banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    cat <<'EOF'
  ╔══════════════════════════════════════════════════╗
  ║     macOS Roblox FPS Unlocker — experimental     ║
  ╚══════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

run_step() {
    local msg="$1"; shift
    echo -ne "${CYAN}[...]${NC} $msg\r"
    if "$@"; then
        printf "\r\033[K${GREEN}${CHECK} %s${NC}\n" "$msg"
    else
        printf "\r\033[K${RED}${CROSS} %s${NC}\n" "$msg"
        exit 1
    fi
}

# ── Check Roblox exists ──
if [ ! -d "$ROBLOX_APP" ]; then
    echo -e "${RED}Roblox.app not found. Install Roblox first.${NC}"
    exit 1
fi

# ── Main dialog ──
banner

type=$(osascript -e 'display dialog "⚠ WARNING: This modifies Roblox.app and is detectable by anti-cheat. This MAY result in a ban.

How do you want to proceed?" buttons {"Unlock FPS (Metal vsync off)","Revert to stock","Cancel"} default button "Unlock FPS (Metal vsync off)" with title "Roblox FPS Unlocker" with icon caution' 2>/dev/null)

if [[ "$type" == *"Cancel"* ]]; then
    echo "Cancelled."
    exit 0
fi

# ── Revert ──
if [[ "$type" == *"Revert to stock"* ]]; then
    echo -e "${INFO} Reverting to stock Roblox..."

    run_step "Killing Roblox" bash -c "killall -9 RobloxPlayer 2>/dev/null || true"

    if [ -f "$MIMALLOC_ORIG" ]; then
        run_step "Restoring original libmimalloc" cp "$MIMALLOC_ORIG" "$MIMALLOC"
        run_step "Removing backup" rm -f "$MIMALLOC_ORIG"
    else
        echo -e "${WARN} No backup found. Reinstall Roblox to restore.${NC}"
    fi

    run_step "Removing FFlags" bash -c "rm -f '$MACOS_DIR/ClientSettings/ClientAppSettings.json' 2>/dev/null || true"

    if [ -f "$SETTINGS_XML" ]; then
        run_step "Resetting FramerateCap to 120" sed -i '' -E 's/<int name="FramerateCap">[0-9]+<\/int>/<int name="FramerateCap">120<\/int>/g' "$SETTINGS_XML"
    fi

    run_step "Re-signing bundle" codesign --force --deep --sign - "$ROBLOX_APP"

    echo
    echo -e "${GREEN}${BOLD}Done! Roblox is back to stock.${NC}"
    exit 0
fi

# ── Unlock FPS ──
echo -e "${INFO} Unlocking FPS..."

run_step "Killing Roblox" bash -c "killall -9 RobloxPlayer 2>/dev/null || true"

# ── Check for prebuilt proxy ──
if [ ! -f "$PROXY_DYLIB" ]; then
    echo -e "${RED}proxy_mimalloc.dylib not found next to this script.${NC}"
    echo -e "${RED}Make sure you extracted the full zip, not just this file.${NC}"
    exit 1
fi

# ── Write FFlags ──
run_step "Writing FFlags (TaskScheduler uncapped)" bash -c "
    mkdir -p '$MACOS_DIR/ClientSettings'
    cat > '$MACOS_DIR/ClientSettings/ClientAppSettings.json' <<'FFLAGS'
{
    "DFIntTaskSchedulerTargetFps": "10000",
    "FFlagTaskSchedulerLimitTargetFpsTo2402": "False"
}
FFLAGS
"

# ── Set FramerateCap ──
if [ -f "$SETTINGS_XML" ]; then
    run_step "Setting FramerateCap to 10000" sed -i '' -E 's/<int name="FramerateCap">[0-9]+<\/int>/<int name="FramerateCap">10000<\/int>/g' "$SETTINGS_XML"
else
    echo -e "${WARN} GlobalBasicSettings not found — set FramerateCap manually in-game${NC}"
fi

# ── Install proxy mimalloc ──
# Backup original if not already backed up
if [ ! -f "$MIMALLOC_ORIG" ]; then
    run_step "Backing up original libmimalloc" cp "$MIMALLOC" "$MIMALLOC_ORIG"
fi

# Change install name of the backup so it doesn't collide with the proxy
install_name_tool -id @rpath/libmimalloc.3_original.dylib "$MIMALLOC_ORIG" 2>/dev/null || true

run_step "Installing proxy libmimalloc" cp "$PROXY_DYLIB" "$MIMALLOC"

run_step "Re-signing bundle (ad-hoc)" codesign --force --deep --sign - "$ROBLOX_APP"

echo
echo -e "${GREEN}${BOLD}Done! Launch Roblox normally — FPS is uncapped.${NC}"
echo -e "${YELLOW}⚠ To revert, run this script again and choose 'Revert to stock'${NC}"
echo
echo -e "${CYAN}Re-launching Roblox...${NC}"
open "$ROBLOX_APP"