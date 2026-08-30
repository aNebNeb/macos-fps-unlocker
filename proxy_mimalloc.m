// proxy_mimalloc.m — proxy libmimalloc.3.dylib with FPS unlock
//
// Replaces Roblox's libmimalloc.3.dylib. All mimalloc symbols are re-exported
// from the original (renamed to libmimalloc.3_original.dylib). Our constructor
// runs at dylib load time, before Roblox's main(), writing FFlags and starting
// the vsync timer.

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>

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
        [fm createDirectoryAtPath:csDir withIntermediateDirectories:YES attributes:nil error:nil];
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
    return [out writeToFile:csFile atomically:YES];
}

// ──────────────────────── vsync (no swizzle) ────────────────────────

static void forceVsyncOffLayer(CALayer *layer) {
    if (!layer) return;
    if ([layer isKindOfClass:[CAMetalLayer class]]) {
        @try { ((CAMetalLayer *)layer).displaySyncEnabled = NO; } @catch (__unused id e) {}
    }
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

// ──────────────────────────── entry point ────────────────────────────

__attribute__((constructor))
static void fpsunlock_init(void) {
    @autoreleasepool {
        writeFFlags();

        dispatch_async(dispatch_get_main_queue(), ^{
            forceVsyncOffAllWindows();
        });

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            forceVsyncOffAllWindows();
        });
        dispatch_resume(timer);
    }
}