#import <SafariServices/SafariServices.h>

#include "jni.h"
#include <dlfcn.h>
#include <mach/mach.h>
#include <os/lock.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <sys/sysctl.h>

#include "utils.h"
#import "LauncherPreferences.h"

CFTypeRef SecTaskCopyValueForEntitlement(void* task, NSString* entitlement, CFErrorRef  _Nullable *error);
void* SecTaskCreateFromSelf(CFAllocatorRef allocator);

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf(NULL), key, nil);
    CFRelease(secTask);
    if (value == nil) {
        return NO;
    }
    CFRelease(value);
    return ![(__bridge id)value isKindOfClass:NSNumber.class] || [(__bridge id)value boolValue];
}

#ifndef P_TRACED
#define P_TRACED 0x00000800 /* process is being traced by a debugger (ptrace) */
#endif

// Ask the kernel whether a ptrace relationship is currently alive for this
// process.  P_TRACED is set in kinfo_proc for the entire lifetime of a
// debugger attach and is cleared the moment the debugger detaches, so it is
// the accurate "debugger still here" signal for debuggers that attach to an
// already-running process.
BOOL JIT26DebuggerAttachedViaPtrace(void) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return NO;
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

// Detect a debugger that holds this task via Mach exception ports instead of
// (or in addition to) ptrace.  lldb/debugserver on iOS attach with
// ptrace(PT_ATTACH) to obtain the task port and then PT_DETACH while KEEPING
// the port -- after that P_TRACED reads 0 even though the debugger is fully
// alive and still receiving EXC_BREAKPOINT (which is exactly how the JIT26
// brk #0x69 / brk #0xf00d breakpoints get serviced).  A live task-level
// handler for BREAKPOINT/SOFTWARE is therefore the reliable "JIT26 debugger
// in place" signal once CS_DEBUGGED is set.
// NOTE: this only reports TASK-level ports.  The in-process hardware-breakpoint
// dlopen redirect (main_hook.m, non-TXM path) registers THREAD-level ports,
// which do not show up here -- so this cannot mistake our own handler for an
// external debugger.  And JIT26IsLikelyDebuggerKeepAttached() is only ever
// consulted on TXM devices, where main_hook's path is not used at all.
BOOL JIT26DebuggerViaExceptionPorts(void) {
    exception_mask_t masks[EXC_TYPES_COUNT];
    exception_handler_t handlers[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count = EXC_TYPES_COUNT;
    kern_return_t kr = task_get_exception_ports(mach_task_self(),
                                                EXC_MASK_BREAKPOINT | EXC_MASK_SOFTWARE,
                                                masks, &count, handlers, behaviors, flavors);
    if (kr != KERN_SUCCESS) {
        return NO;
    }
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        if (handlers[i] != MACH_PORT_NULL) {
            return YES;
        }
    }
    return NO;
}

BOOL JIT26IsLikelyDebuggerKeepAttached(void) {
    // getppid() returns launchd's PID (1) unless a debugger SPAWNED this
    // process (debugserver-style parent).  This is the check Hynis-JE uses.
    if (getppid() != 1) {
        return YES;
    }
    // StikJIT / SideJIT instead attach to an ALREADY-RUNNING app by pid
    // (the launcher hands its own getpid() over via the stikjit:// URL),
    // which leaves ppid == 1 for the whole session even though the debugger
    // is actively attached and handling JIT26 breakpoints.  Worse, the
    // enabler may exit after enabling, getting the app re-parented to
    // launchd (ppid 1) while CS_DEBUGGED stays set -- so ppid alone
    // misclassifies a fully working JIT session as "no debugger attached".
    // That caused the permanent "JIT not enabled" status label and a
    // redundant stikjit:// script round trip on every game launch.
    // Fall back to the live ptrace flag: it is set exactly while a debugger
    // is attached, so this neither misses the attach flow nor weakens the
    // "debugger really detached" case (P_TRACED returns to 0 on detach).
    if (JIT26DebuggerAttachedViaPtrace()) {
        return YES;
    }
    // lldb/debugserver detach (PT_DETACH) as soon as it holds the task port
    // and then keep serving EXC_BREAKPOINT through Mach exception ports with
    // P_TRACED == 0 -- measured on-device as CS_DEBUGGED=1 ppid=1 traced=0
    // with the JIT26 mapping request succeeding moments later.  Treat a live
    // task-level BREAKPOINT/SOFTWARE handler as "debugger attached": it is
    // the entity that must service the brk #0x69 traps, which is the whole
    // point of this check.  See JIT26DebuggerViaExceptionPorts() for why the
    // app's own handlers cannot false-positive here.
    return JIT26DebuggerViaExceptionPorts();
}

BOOL isJITEnabled(BOOL checkCSFlags) {
    // Fast path: these entitlements/policies mean JIT is available without
    // needing CS_DEBUGGED:
    // - dynamic-codesigning: per-app JIT entitlement
    // - jb.pmap_cs.custom_trust: TrollStore pmap trust chain — grants
    //   kernel-level JIT on unjailbroken devices with NO debugger attached,
    //   so CS_DEBUGGED is NOT set and must not be required (this is what
    //   made isJITEnabled() return NO on TrollStore installs and trigger
    //   unnecessary stikjit:// / apple-magnifier:// redirects)
    // - isJailbroken: jailbroken devices
    if (!checkCSFlags && (getEntitlementValue(@"dynamic-codesigning") ||
                          getEntitlementValue(@"jb.pmap_cs.custom_trust") ||
                          isJailbroken)) {
        return YES;
    }

    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    if ((flags & CS_DEBUGGED) == 0) {
        return NO;
    }
    // On iOS 26+ with FORCE_MIRRORED + HAS_TXM, CS_DEBUGGED alone is not
    // sufficient — the brk #0x69 in JavaLauncher.m needs a debugger that is
    // STILL attached.  CS_DEBUGGED can remain set after the debugger
    // detaches, so we verify with getppid().
    if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
        return JIT26IsLikelyDebuggerKeepAttached();
    }
    return YES;
}

void openLink(UIViewController* sender, NSURL* link) {
    if (NSClassFromString(@"SFSafariViewController") == nil) {
        NSData *data = [link.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [filter setValue:data forKey:@"inputMessage"];
        UIImage *image = [UIImage imageWithCIImage:filter.outputImage scale:1.0 orientation:UIImageOrientationUp];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(300, 300), NO, 0.0);
        CGRect frame = CGRectMake(0, 0, 300, 300);
        [image drawInRect:frame];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:frame];
        imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
            message:link.absoluteString
            preferredStyle:UIAlertControllerStyleAlert];

        UIViewController *vc = UIViewController.new;
        vc.view = imageView;
        [alert setValue:vc forKey:@"contentViewController"];

        UIAlertAction* doneAction = [UIAlertAction actionWithTitle:localize(@"Done", nil) style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:doneAction];
        [sender presentViewController:alert animated:YES completion:nil];
    } else {
        SFSafariViewController *vc = [[SFSafariViewController alloc] initWithURL:link];
        [sender presentViewController:vc animated:YES completion:nil];
    }
}

NSMutableDictionary* parseJSONFromFile(NSString *path) {
    NSError *error;

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (content == nil) {
        NSLog(@"[ParseJSON] Error: could not read %@: %@", path, error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }

    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        NSLog(@"[ParseJSON] Error: could not parse JSON: %@", error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }
    return dict;
}

NSError* saveJSONToFile(NSDictionary *dict, NSString *path) {
    // TODO: handle rename
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData == nil) {
        return error;
    }
    BOOL success = [jsonData writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        return error;
    }
    return nil;
}

NSString* localize(NSString* key, NSString* comment) {
    // 检查用户是否在设置中手动选择了语言
    NSString *langOverride = getPrefObject(@"general.app_language");
    NSBundle *targetBundle = nil;

    if (langOverride && ![langOverride isEqualToString:@"system"]) {
        // 用户手动选择了特定语言，使用对应的 .lproj bundle
        NSString *lprojPath = [NSBundle.mainBundle pathForResource:langOverride ofType:@"lproj"];
        if (lprojPath) {
            targetBundle = [NSBundle bundleWithPath:lprojPath];
        }
    }

    NSString *value;
    if (targetBundle) {
        value = [targetBundle localizedStringForKey:key value:key table:nil];
        // 如果用户选择的语言缺少该 key，回退到英文
        if ([value isEqualToString:key]) {
            NSString *enPath = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
            NSBundle *enBundle = [NSBundle bundleWithPath:enPath];
            value = [enBundle localizedStringForKey:key value:nil table:nil];
            if ([value isEqualToString:key]) {
                // 英文也没有，尝试 UIKit 系统翻译
                value = [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:key value:nil table:nil];
            }
        }
    } else {
        // 跟随系统语言（默认行为）
        value = NSLocalizedString(key, nil);
        if (![NSLocale.preferredLanguages[0] isEqualToString:@"en"] && [value isEqualToString:key]) {
            NSString* path = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
            NSBundle* languageBundle = [NSBundle bundleWithPath:path];
            value = [languageBundle localizedStringForKey:key value:nil table:nil];
            if ([value isEqualToString:key]) {
                value = [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:key value:nil table:nil];
            }
        }
    }

    return value;
}

void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...)
{
    va_list ap; 
    va_start (ap, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:ap];
    printf("%s", [body UTF8String]);
    if (![format hasSuffix:@"\n"]) {
        printf("\n");
    }
    va_end (ap);
}

CGFloat MathUtils_dist(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    const CGFloat x = (x2 - x1);
    const CGFloat y = (y2 - y1);
    return (CGFloat) hypot(x, y);
}

//Ported from https://www.arduino.cc/reference/en/language/functions/math/map/
CGFloat MathUtils_map(CGFloat x, CGFloat in_min, CGFloat in_max, CGFloat out_min, CGFloat out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

CGFloat dpToPx(CGFloat dp) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return dp * screenScale;
}

CGFloat pxToDp(CGFloat px) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return px / screenScale;
}

void setButtonPointerInteraction(UIButton *button) {
    button.pointerInteractionEnabled = YES;
    button.pointerStyleProvider = ^ UIPointerStyle* (UIButton* button, UIPointerEffect* proposedEffect, UIPointerShape* proposedShape) {
        UITargetedPreview *preview = [[UITargetedPreview alloc] initWithView:button];
        return [NSClassFromString(@"UIPointerStyle") styleWithEffect:[NSClassFromString(@"UIPointerHighlightEffect") effectWithPreview:preview] shape:proposedShape];
    };
}

__attribute__((noinline,optnone,naked))
void* JIT26CreateRegionLegacy(size_t len) {
    asm("brk #0x69 \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void* JIT26PrepareRegion(void *addr, size_t len) {
    asm("mov x16, #1 \n"
        "brk #0xf00d \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void BreakSendJITScript(char* script, size_t len) {
   asm("mov x16, #2 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26SetDetachAfterFirstBr(BOOL value) {
   asm("mov x16, #3 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26PrepareRegionForPatching(void *addr, size_t size) {
   asm("mov x16, #4 \n"
       "brk #0xf00d \n"
       "ret");
}
void JIT26SendJITScript(NSString* script) {
    NSCAssert(script, @"Script must not be nil");
    BreakSendJITScript((char*)script.UTF8String, script.length);
}

BOOL DeviceCanCreateRXMap(void) {
    uint32_t *map = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0);
    if (map == MAP_FAILED) {
        NSLog(@"DeviceCanCreateRXMap: mmap failed: %s", strerror(errno));
        return NO;
    }
    *map = 0xFFFFFFFF;
    int ret = mprotect(map, getpagesize(), PROT_READ | PROT_EXEC) | mprotect(map, getpagesize(), PROT_READ | PROT_EXEC);
    munmap(map, getpagesize());
    return ret == 0;
}

static BOOL DeviceHasTXMReal(void) {
    DIR *d = opendir("/private/preboot");
    if (!d) {
        // /private/preboot is no longer readable on iOS 26.6 and iOS 27.
        // Fall back to a conservative hardware/OS heuristic.
        NSUInteger (*MGGetSInt64Answer)(NSString *) = dlsym(RTLD_DEFAULT, "MGGetSInt64Answer");
        if (MGGetSInt64Answer == NULL) {
            if (@available(iOS 19.0, *)) return YES;
            return NO;
        }
        NSUInteger chipID = MGGetSInt64Answer(@"ChipID");
        switch (chipID) {
            case 0x8020: // A12
            case 0x8027: // A12X/Z
                return NO;
            case 0x8030: // A13
            case 0x8101: // A14
            case 0x8103: // M1
                if (@available(iOS 27.0, *)) return YES;
                return NO;
            default:
                if (@available(iOS 19.0, *)) return YES;
                return NO;
        }
    }
    struct dirent *dir;
    char txmPath[PATH_MAX];
    while ((dir = readdir(d)) != NULL) {
        if(strlen(dir->d_name) == 96) {
            snprintf(txmPath, sizeof(txmPath), "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
            break;
        }
    }
    closedir(d);
    return access(txmPath, F_OK) == 0;
}

BOOL DeviceHasTXM(void) {
    return DeviceHasJITFlags(JIT_FLAG_HAS_TXM);
}

JITFlags DeviceGetJITFlags(BOOL refresh) {
    static os_unfair_lock cacheLock = OS_UNFAIR_LOCK_INIT;
    static JITFlags cachedFlags = 0;
    static BOOL cacheInitialized = NO;

    os_unfair_lock_lock(&cacheLock);
    if (refresh || !cacheInitialized) {
        JITFlags flags = 0;
        const char *s = getenv("JIT_FLAGS");
        if (s) {
            if (s[0] == '0' && tolower(s[1]) == 'b') {
                flags = strtoul(s + 2, NULL, 2);
            } else {
                flags = strtoul(s, NULL, 0);
            }
            NSLog(@"[JIT] Using overridden JIT flags: 0x%X", flags);
        } else {
            if (@available(iOS 26.0, *)) {
                flags |= JIT_FLAG_IS_IOS_26;
                if (!DeviceCanCreateRXMap()) {
                    flags |= JIT_FLAG_FORCE_MIRRORED;
                }
            }
            if (DeviceHasTXMReal()) {
                flags |= JIT_FLAG_HAS_TXM;
            }
        }

        cachedFlags = flags;
        cacheInitialized = YES;
    }
    JITFlags result = cachedFlags;
    os_unfair_lock_unlock(&cacheLock);
    return result;
}

BOOL DeviceHasJITFlags(JITFlags flags) {
    return (DeviceGetJITFlags(NO) & flags) == flags;
}

void dismissModalViewController(UIViewController *viewController) {
    [viewController.navigationController dismissViewControllerAnimated:YES completion:nil];
}
