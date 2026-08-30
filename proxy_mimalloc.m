// proxy_mimalloc.m — proxy libmimalloc.3.dylib with FPS unlock + HWID spoof
//
// Replaces Roblox's libmimalloc.3.dylib. All mimalloc symbols are re-exported
// from the original (renamed to libmimalloc.3_original.dylib). Our constructor
// runs at dylib load time, before Roblox's main().
//
// Features:
//   1. Writes FFlags (TaskScheduler uncapped)
//   2. Forces Metal vsync off via direct property writes (no swizzling)
//   3. Spoofs HWID by intercepting IOPlatformUUID + sysctlbyname
//   4. Rotates local device ID storage on each launch

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>

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

// ──────────────────────── HWID spoofing ────────────────────────
//
// Roblox reads IOPlatformUUID via IOKit and hw.* via sysctlbyname to build
// a machine fingerprint. We intercept both:
//
//   1. IORegistryEntryCreateCFProperty — return a fake UUID when the key is
//      "IOPlatformUUID" and the entry is IOPlatformExpertDevice
//   2. sysctlbyname — return fake values for hw.model, hw.machine, hw.memsize
//
// The fake values are deterministic per-user (hashed from a random seed
// stored in ~/Library/Roblox/hwid_seed) so they're stable across launches
// but don't match the real hardware. Delete hwid_seed to rotate.

static NSString *g_spoofedUUID = nil;
static NSString *g_spoofedModel = nil;
static NSString *g_spoofedMachine = nil;
static NSNumber *g_spoofedMemSize = nil;

// Original function pointers
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(CFTypeRef, CFStringRef, CFAllocatorRef, IOOptionBits) = NULL;
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;

static NSString *getHWIDSeed(void) {
    NSString *seedPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Roblox/hwid_seed"];
    NSString *seed = [NSString stringWithContentsOfFile:seedPath encoding:NSUTF8StringEncoding error:nil];
    if (!seed || seed.length == 0) {
        // Generate a random seed
        uuid_t uuid;
        uuid_generate_random(uuid);
        uuid_string_t uuidStr;
        uuid_unparse(uuid, uuidStr);
        seed = [NSString stringWithFormat:@"%s", uuidStr];
        [seed writeToFile:seedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return seed;
}

static NSString *hashString(NSString *input) {
    const char *cstr = [input UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

static void initSpoofedValues(void) {
    if (g_spoofedUUID) return;

    NSString *seed = getHWIDSeed();
    NSString *hash = hashString(seed);

    // Format like a real IOPlatformUUID: 8-4-4-4-12
    g_spoofedUUID = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
        [hash substringToIndex:8],
        [hash substringWithRange:NSMakeRange(8, 4)],
        [hash substringWithRange:NSMakeRange(12, 4)],
        [hash substringWithRange:NSMakeRange(16, 4)],
        [hash substringWithRange:NSMakeRange(20, 12)]];

    // Fake model — looks like a real Mac model identifier
    g_spoofedModel = [NSString stringWithFormat:@"Mac%lu,1", (unsigned long)([hash hash] % 20 + 10)];
    g_spoofedMachine = [NSString stringWithFormat:@"arm64"];

    // Fake memsize — 8GB, 16GB, or 32GB
    NSArray *memSizes = @[@8589934592, @17179869184, @34359738368];
    g_spoofedMemSize = memSizes[[hash hash] % 3];
}

// ── Hook IORegistryEntryCreateCFProperty ──

static CFTypeRef hook_IORegistryEntryCreateCFProperty(CFTypeRef entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    initSpoofedValues();

    if (key && CFStringCompare(key, CFSTR("IOPlatformUUID"), 0) == kCFCompareEqualTo) {
        return (__bridge CFTypeRef)g_spoofedUUID;
    }

    return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}

// ── Hook sysctlbyname ──

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    initSpoofedValues();

    if (strcmp(name, "hw.model") == 0) {
        const char *model = [g_spoofedModel UTF8String];
        size_t len = strlen(model) + 1;
        if (oldp && oldlenp) {
            size_t copyLen = MIN(len, *oldlenp);
            memcpy(oldp, model, copyLen);
            *oldlenp = copyLen;
        } else if (oldlenp) {
            *oldlenp = len;
        }
        return 0;
    }

    if (strcmp(name, "hw.machine") == 0) {
        const char *machine = [g_spoofedMachine UTF8String];
        size_t len = strlen(machine) + 1;
        if (oldp && oldlenp) {
            size_t copyLen = MIN(len, *oldlenp);
            memcpy(oldp, machine, copyLen);
            *oldlenp = copyLen;
        } else if (oldlenp) {
            *oldlenp = len;
        }
        return 0;
    }

    if (strcmp(name, "hw.memsize") == 0) {
        if (oldp && oldlenp && *oldlenp >= sizeof(uint64_t)) {
            *(uint64_t *)oldp = g_spoofedMemSize.unsignedLongLongValue;
            *oldlenp = sizeof(uint64_t);
        } else if (oldlenp) {
            *oldlenp = sizeof(uint64_t);
        }
        return 0;
    }

    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// ── Install hooks via fishhook-style rebinding ──

#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

static void rebindSymbol(const char *name, void *replacement, void **original) {
    // Use fishhook-style rebinding: walk all loaded images and replace
    // the lazy/non-lazy symbol pointer for the given symbol.
    uint32_t c = _dyld_image_count();
    for (uint32_t i = 0; i < c; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (header->magic != MH_MAGIC_64) continue;

        struct segment_command_64 *seg = (struct segment_command_64 *)((uint8_t *)header + sizeof(struct mach_header_64));
        struct section_64 *sections = NULL;
        int nsections = 0;

        for (uint32_t j = 0; j < header->ncmds; j++, seg = (struct segment_command_64 *)((uint8_t *)seg + seg->cmdsize)) {
            if (seg->cmd == LC_SEGMENT_64 && strcmp(seg->segname, "__DATA") == 0) {
                sections = (struct section_64 *)((uint8_t *)seg + sizeof(struct segment_command_64));
                nsections = seg->nsects;
                break;
            }
        }

        if (!sections) continue;

        for (int s = 0; s < nsections; s++) {
            if (strcmp(sections[s].sectname, "__la_symbol_ptr") != 0 && strcmp(sections[s].sectname, "__nl_symbol_ptr") != 0)
                continue;

            uint8_t **ptr = (uint8_t **)(sections[s].addr + slide);
            uint32_t count = sections[s].size / sizeof(void *);

            for (uint32_t k = 0; k < count; k++) {
                // Get the symbol name for this slot
                // We need the indirect symbol table
                // Simplified: just check if the pointed-to function matches
                // For now, use dlsym to find the original and compare
                void *sym = dlsym(NULL, name);
                if (ptr[k] == sym) {
                    if (original && !*original) {
                        *original = ptr[k];
                    }
                    ptr[k] = (uint8_t *)replacement;
                }
            }
        }
    }
}

// ── Rotate local device ID storage ──

static void rotateDeviceStorage(void) {
    NSString *robloxDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Roblox"];

    // Rotate rbx-storage.id
    NSString *storageId = [robloxDir stringByAppendingPathComponent:@"rbx-storage.id"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:storageId]) {
        uuid_t uuid;
        uuid_generate_random(uuid);
        NSData *idData = [NSData dataWithBytes:uuid length:8];
        [idData writeToFile:storageId atomically:YES];
    }

    // Clean appStorage.json device-related keys
    NSString *appStorage = [robloxDir stringByAppendingPathComponent:@"LocalStorage/appStorage.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:appStorage]) {
        NSData *data = [NSData dataWithContentsOfFile:appStorage];
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            if (json && [json isKindOfClass:[NSMutableDictionary class]]) {
                NSMutableDictionary *dict = (NSMutableDictionary *)json;
                // Remove device-enrollment related keys
                for (NSString *key in [dict allKeys]) {
                    if ([key.lowercaseString containsString:@"deviceid"] ||
                        [key.lowercaseString containsString:@"machineid"] ||
                        [key.lowercaseString containsString:@"hwid"]) {
                        [dict removeObjectForKey:key];
                    }
                }
                NSData *out = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
                if (out) [out writeToFile:appStorage atomically:YES];
            }
        }
    }
}

// ──────────────────────────── entry point ────────────────────────────

__attribute__((constructor))
static void fpsunlock_init(void) {
    @autoreleasepool {
        // 1) FFlags
        writeFFlags();

        // 2) Vsync off
        dispatch_async(dispatch_get_main_queue(), ^{
            forceVsyncOffAllWindows();
        });

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            forceVsyncOffAllWindows();
        });
        dispatch_resume(timer);

        // 3) HWID spoof — install hooks before Roblox reads hardware info
        initSpoofedValues();
        rotateDeviceStorage();

        orig_IORegistryEntryCreateCFProperty = dlsym(RTLD_DEFAULT, "IORegistryEntryCreateCFProperty");
        orig_sysctlbyname = dlsym(RTLD_DEFAULT, "sysctlbyname");

        if (orig_IORegistryEntryCreateCFProperty) {
            rebindSymbol("IORegistryEntryCreateCFProperty", (void *)hook_IORegistryEntryCreateCFProperty, (void **)&orig_IORegistryEntryCreateCFProperty);
        }
        if (orig_sysctlbyname) {
            rebindSymbol("sysctlbyname", (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
        }
    }
}