// fpsunlock.m — Roblox FPS unlock dylib for macOS (Apple Silicon)
// Kills BOTH FPS caps from inside a single injected dylib:
//
//   1. TaskScheduler cap — written via FFlags (ClientAppSettings.json) before
//      Roblox's main() reads them. The constructor runs at dylib load time,
//      which precedes main(), so the file is in place when Roblox inits.
//      Sets DFIntTaskSchedulerTargetFps to a huge value (no frame budget).
//
//   2. Metal vsync cap — finds the live CAMetalLayer in the view hierarchy and
//      forces displaySyncEnabled = NO. A background timer keeps it off in case
//      Roblox re-enables it. No method swizzling — just direct property writes,
//      which is much harder for anti-cheat to detect (no exchanged IMPs).
//
// Build: ./build.sh

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// ───────────────────────────── FFlags ─────────────────────────────

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
    if (![fm fileExistsAtPath:csDir]) {
        if (![fm createDirectoryAtPath:csDir withIntermediateDirectories:YES attributes:nil error:nil]) {
            NSLog(@"[fpsunlock] could not create ClientSettings dir: %@", csDir);
            return NO;
        }
    }

    NSMutableDictionary *flags = [NSMutableDictionary dictionary];
    NSData *existing = [NSData dataWithContentsOfFile:csFile];
    if (existing) {
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil];
        if (parsed && [parsed isKindOfClass:[NSDictionary class]]) {
            [flags addEntriesFromDictionary:parsed];
        }
    }

    flags[@"DFIntTaskSchedulerTargetFps"] = @"10000";
    flags[@"FFlagTaskSchedulerLimitTargetFpsTo2402"] = @"False";

    NSData *out = [NSJSONSerialization dataWithJSONObject:flags options:0 error:nil];
    if (!out) return NO;
    BOOL ok = [out writeToFile:csFile atomically:YES];
    if (ok) {
        NSLog(@"[fpsunlock] wrote FFlags");
    }
    return ok;
}

// ──────────────────────── vsync (no swizzle) ────────────────────────

static void forceVsyncOffLayer(CALayer *layer) {
    if (!layer) return;
    if ([layer isKindOfClass:[CAMetalLayer class]]) {
        @try {
            ((CAMetalLayer *)layer).displaySyncEnabled = NO;
        } @catch (__unused id e) {}
    }
    for (CALayer *sub in layer.sublayers) {
        forceVsyncOffLayer(sub);
    }
}

static void walkViews(NSView *view) {
    if (!view) return;
    if (view.layer) forceVsyncOffLayer(view.layer);
    for (NSView *sub in view.subviews) walkViews(sub);
}

static void forceVsyncOffAllWindows(void) {
    NSApplication *app = [NSApplication sharedApplication];
    for (NSWindow *win in app.windows) {
        walkViews(win.contentView);
    }
}

// ──────────────────────────── entry point ────────────────────────────

__attribute__((constructor))
static void fpsunlock_init(void) {
    @autoreleasepool {
        writeFFlags();

        // Force vsync off now and keep it off with a lightweight timer.
        forceVsyncOffAllWindows();

        dispatch_async(dispatch_get_main_queue(), ^{
            forceVsyncOffAllWindows();
        });

        // Keep re-applying every 2s in case Roblox recreates the layer.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            forceVsyncOffAllWindows();
        });
        dispatch_resume(timer);

        NSLog(@"[fpsunlock] loaded — FFlags written + vsync forced OFF (no swizzle)");
    }
}