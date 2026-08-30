#!/bin/bash
# unlockfpsmac.command — macOS Roblox FPS Unlocker (experimental)
#
# WARNING: This modifies your Roblox.app bundle and is detectable by
# anti-cheat. This MAY result in a ban. Use at your own risk.
#
# What it does:
#   1. Builds a proxy libmimalloc.3.dylib from source that re-exports the
#      original mimalloc and forces Metal vsync off (no swizzling, just
#      direct property writes on a timer)
#   2. Replaces Roblox's libmimalloc.3.dylib with the proxy
#   3. Writes FFlags to uncap TaskScheduler FPS
#   4. Sets FramerateCap to 10000 in GlobalBasicSettings
#   5. Re-signs the bundle ad-hoc (strips hardened runtime)
#
# To revert: run this script again and choose "revert"

set -euo pipefail

ROBLOX_APP="/Applications/Roblox.app"
MACOS_DIR="$ROBLOX_APP/Contents/MacOS"
MIMALLOC="$MACOS_DIR/libmimalloc.3.dylib"
MIMALLOC_ORIG="$MACOS_DIR/libmimalloc.3_original.dylib"
SETTINGS_XML="$HOME/Library/Roblox/GlobalBasicSettings_13.xml"

# ── Colors ──
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

How do you want to unlock FPS?" buttons {"Unlock FPS (Metal vsync off)","Revert to stock","Cancel"} default button "Unlock FPS (Metal vsync off)" with title "Roblox FPS Unlocker" with icon caution' 2>/dev/null)

if [[ "$type" == *"Cancel"* ]]; then
    echo "Cancelled."
    exit 0
fi

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

# ── Write FFlags ──
run_step "Writing FFlags (TaskScheduler uncapped)" bash -c "
    mkdir -p '$MACOS_DIR/ClientSettings'
    cat > '$MACOS_DIR/ClientSettings/ClientAppSettings.json' <<'FFLAGS'
{
    \"DFIntTaskSchedulerTargetFps\": \"10000\",
    \"FFlagTaskSchedulerLimitTargetFpsTo2402\": \"False\"
}
FFLAGS
"

# ── Set FramerateCap ──
if [ -f "$SETTINGS_XML" ]; then
    run_step "Setting FramerateCap to 10000" sed -i '' -E 's/<int name="FramerateCap">[0-9]+<\/int>/<int name="FramerateCap">10000<\/int>/g' "$SETTINGS_XML"
else
    echo -e "${WARN} GlobalBasicSettings not found — set FramerateCap manually in-game${NC}"
fi

# ── Build proxy mimalloc ──
TEMP="$(mktemp -d)"
trap "rm -rf $TEMP" EXIT

cat > "$TEMP/proxy_mimalloc.m" <<'PROXY'
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>

static BOOL writeFFlags(void) {
    char path[4096] = {0};
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) {
        NSBundle *main = [NSBundle mainBundle];
        NSString *exePath = main.executablePath;
        if (!exePath) return NO;
        strcpy(path, [exePath UTF8String]);
    }
    NSString *exe = [NSString stringWithUTF8String:path];
    NSString *macosDir = [exe stringByDeletingLastPathComponent];
    NSString *csDir = [macosDir stringByAppendingPathComponent:@"ClientSettings"];
    NSString *csFile = [csDir stringByAppendingPathComponent:@"ClientAppSettings.json"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:csDir])
        [fm createDirectoryAtPath:csDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *flags = [NSMutableDictionary dictionary];
    NSData *existing = [NSData dataWithContentsOfFile:csFile];
    if (existing) {
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil];
        if (parsed && [parsed isKindOfClass:[NSDictionary class]])
            [flags addEntriesFromDictionary:parsed];
    }
    flags[@"DFIntTaskSchedulerTargetFps"] = @"10000";
    flags[@"FFlagTaskSchedulerLimitTargetFpsTo2402"] = @"False";
    NSData *out = [NSJSONSerialization dataWithJSONObject:flags options:0 error:nil];
    return out ? [out writeToFile:csFile atomically:YES] : NO;
}

static void forceVsyncOffLayer(CALayer *layer) {
    if (!layer) return;
    if ([layer isKindOfClass:[CAMetalLayer class]])
        @try { ((CAMetalLayer *)layer).displaySyncEnabled = NO; } @catch (__unused id e) {}
    for (CALayer *sub in layer.sublayers) forceVsyncOffLayer(sub);
}

static void walkViews(NSView *view) {
    if (!view) return;
    if (view.layer) forceVsyncOffLayer(view.layer);
    for (NSView *sub in view.subviews) walkViews(sub);
}

static void forceVsyncOffAllWindows(void) {
    NSApplication *app = [NSApplication sharedApplication];
    for (NSWindow *win in app.windows) walkViews(win.contentView);
}

__attribute__((constructor))
static void fpsunlock_init(void) {
    @autoreleasepool {
        writeFFlags();
        dispatch_async(dispatch_get_main_queue(), ^{ forceVsyncOffAllWindows(); });
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ forceVsyncOffAllWindows(); });
        dispatch_resume(timer);
    }
}
PROXY

# Backup original if not already backed up
if [ ! -f "$MIMALLOC_ORIG" ]; then
    cp "$MIMALLOC" "$MIMALLOC_ORIG"
fi

# Change install name of the backup so it doesn't collide
install_name_tool -id @rpath/libmimalloc.3_original.dylib "$MIMALLOC_ORIG" 2>/dev/null || true

run_step "Building proxy libmimalloc from source" clang -dynamiclib -arch arm64 \
    -fobjc-arc \
    -framework Foundation \
    -framework QuartzCore \
    -framework AppKit \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -mmacosx-version-min=11.0 \
    -O2 \
    -install_name @rpath/libmimalloc.3.dylib \
    -Xlinker -reexport_library \
    -Xlinker "$MIMALLOC_ORIG" \
    -o "$MIMALLOC" \
    "$TEMP/proxy_mimalloc.m"

run_step "Re-signing bundle (ad-hoc)" codesign --force --deep --sign - "$ROBLOX_APP"

echo
echo -e "${GREEN}${BOLD}Done! Launch Roblox normally — FPS is uncapped.${NC}"
echo -e "${YELLOW}⚠ To revert, run this script again and choose 'Revert to stock'${NC}"
echo
echo -e "${CYAN}Re-launching Roblox...${NC}"
open "$ROBLOX_APP"