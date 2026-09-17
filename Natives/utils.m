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
#include <setjmp.h>
#include <signal.h>
#include <sys/sysctl.h>

#include "utils.h"
#import "LauncherPreferences.h"

CFTypeRef SecTaskCopyValueForEntitlement(void* task, NSString* entitlement, CFErrorRef  _Nullable *error);
void* SecTaskCreateFromSelf(CFAllocatorRef allocator);

BOOL getEntitlementValue(NSString *key) {
    // Task88 修复：原实现 SecTaskCreateFromSelf 被调用了两次（secTask 与内联各一次）
    // 但只释放其中之一，每次调用泄漏一个 SecTaskRef。主界面状态标签（Task88）会在
    // 每次回到前台时调用本函数，故顺手收紧：单次创建 + nil 守卫 + 判断后释放。
    void *secTask = SecTaskCreateFromSelf(NULL);
    if (!secTask) {
        return NO;
    }
    CFTypeRef value = SecTaskCopyValueForEntitlement(secTask, key, nil);
    CFRelease(secTask);
    if (value == nil) {
        return NO;
    }
    BOOL result = ![(__bridge id)value isKindOfClass:NSNumber.class] || [(__bridge id)value boolValue];
    CFRelease(value);
    return result;
}

// Task93：Task90 的"签名+描述文件双确认"方案已整体移除（getEffectiveEntitlementValue /
// CopyEmbeddedProfileEntitlements）——用户实测双确认在重签工具同时写入描述文件时
// 依然误报。内存标识现与启动日志 [Pre-init] Entitlements availability 完全同源，
// 均直接使用上方 getEntitlementValue()（SecTask 签名口径）。

// ============================================================================
// Task96：MeloNX 风格信息卡数据源（右面板「设备」「系统」卡片）。
// hw.machine（如 iPad15,3）→ Apple 营销名（如 "iPad Air 11-inch (M3)"）。
// 未收录机型如实回退原始标识，宁缺毋错（错名比原名更有害）。
// 标识符对照已联网核实（Apple 支持文档 / 机型选型库，2026-09 核对）：
//   iPad15,3 / iPad15,4 = iPad Air 11/13-inch (M3)
//   iPad15,7 / iPad15,8 = iPad (11th generation, A16)
//   iPad16,1 / iPad16,2 = iPad mini (A17 Pro)
//   iPad16,3-16,6       = iPad Pro 11/13-inch (M4)
// ============================================================================
static NSString *ame96_machineIdentifier(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t len = 0;
        if (sysctlbyname("hw.machine", NULL, &len, NULL, 0) != 0 || len == 0) return;
        char *buf = malloc(len);
        if (!buf) return;
        if (sysctlbyname("hw.machine", buf, &len, NULL, 0) != 0) {
            free(buf);
            return;
        }
        cached = [NSString stringWithUTF8String:buf];
        free(buf);
    });
    return cached;
}

NSString *getDeviceMarketingName(void) {
    NSString *machine = ame96_machineIdentifier();
    if (machine.length == 0) {
        return [UIDevice currentDevice].model ?: @"未知设备";
    }
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            // iPad（新→旧）
            @"iPad16,1": @"iPad mini (A17 Pro)",
            @"iPad16,2": @"iPad mini (A17 Pro)",
            @"iPad16,3": @"iPad Pro 11-inch (M4)",
            @"iPad16,4": @"iPad Pro 11-inch (M4)",
            @"iPad16,5": @"iPad Pro 13-inch (M4)",
            @"iPad16,6": @"iPad Pro 13-inch (M4)",
            @"iPad15,3": @"iPad Air 11-inch (M3)",
            @"iPad15,4": @"iPad Air 13-inch (M3)",
            @"iPad15,7": @"iPad (11th generation)",
            @"iPad15,8": @"iPad (11th generation)",
            @"iPad14,8": @"iPad Air 11-inch (M2)",
            @"iPad14,9": @"iPad Air 13-inch (M2)",
            @"iPad14,3": @"iPad Pro 11-inch (M2)",
            @"iPad14,4": @"iPad Pro 11-inch (M2)",
            @"iPad14,5": @"iPad Pro 12.9-inch (M2)",
            @"iPad14,6": @"iPad Pro 12.9-inch (M2)",
            @"iPad14,1": @"iPad mini (6th generation)",
            @"iPad14,2": @"iPad mini (6th generation)",
            @"iPad13,16": @"iPad Air (5th generation)",
            @"iPad13,17": @"iPad Air (5th generation)",
            @"iPad13,18": @"iPad (10th generation)",
            @"iPad13,19": @"iPad (10th generation)",
            @"iPad13,1": @"iPad Air (4th generation)",
            @"iPad13,2": @"iPad Air (4th generation)",
            @"iPad13,4": @"iPad Pro 11-inch (M1)",
            @"iPad13,5": @"iPad Pro 11-inch (M1)",
            @"iPad13,6": @"iPad Pro 11-inch (M1)",
            @"iPad13,7": @"iPad Pro 11-inch (M1)",
            @"iPad13,8": @"iPad Pro 12.9-inch (M1)",
            @"iPad13,9": @"iPad Pro 12.9-inch (M1)",
            @"iPad13,10": @"iPad Pro 12.9-inch (M1)",
            @"iPad13,11": @"iPad Pro 12.9-inch (M1)",
            @"iPad12,1": @"iPad (9th generation)",
            @"iPad12,2": @"iPad (9th generation)",
            @"iPad11,6": @"iPad (8th generation)",
            @"iPad11,7": @"iPad (8th generation)",
            @"iPad11,1": @"iPad mini (5th generation)",
            @"iPad11,2": @"iPad mini (5th generation)",
            @"iPad8,1": @"iPad Pro 11-inch (1st generation)",
            @"iPad8,2": @"iPad Pro 11-inch (1st generation)",
            @"iPad8,3": @"iPad Pro 11-inch (1st generation)",
            @"iPad8,4": @"iPad Pro 11-inch (1st generation)",
            @"iPad8,5": @"iPad Pro 12.9-inch (3rd generation)",
            @"iPad8,6": @"iPad Pro 12.9-inch (3rd generation)",
            @"iPad8,7": @"iPad Pro 12.9-inch (3rd generation)",
            @"iPad8,8": @"iPad Pro 12.9-inch (3rd generation)",
            @"iPad8,9": @"iPad Pro 11-inch (2nd generation)",
            @"iPad8,10": @"iPad Pro 11-inch (2nd generation)",
            @"iPad8,11": @"iPad Pro 12.9-inch (4th generation)",
            @"iPad8,12": @"iPad Pro 12.9-inch (4th generation)",
            @"iPad7,11": @"iPad (7th generation)",
            @"iPad7,12": @"iPad (7th generation)",
            @"iPad6,11": @"iPad (5th generation)",
            @"iPad6,12": @"iPad (5th generation)",
            @"iPad5,3": @"iPad Air 2",
            @"iPad5,4": @"iPad Air 2",
            @"iPad5,1": @"iPad mini 4",
            @"iPad5,2": @"iPad mini 4",
            // iPhone
            @"iPhone17,1": @"iPhone 16 Pro",
            @"iPhone17,2": @"iPhone 16 Pro Max",
            @"iPhone17,3": @"iPhone 16",
            @"iPhone17,4": @"iPhone 16 Plus",
            @"iPhone17,5": @"iPhone 16e",
            @"iPhone16,1": @"iPhone 15 Pro",
            @"iPhone16,2": @"iPhone 15 Pro Max",
            @"iPhone15,4": @"iPhone 15",
            @"iPhone15,5": @"iPhone 15 Plus",
            @"iPhone15,2": @"iPhone 14 Pro",
            @"iPhone15,3": @"iPhone 14 Pro Max",
            @"iPhone14,7": @"iPhone 14",
            @"iPhone14,8": @"iPhone 14 Plus",
            @"iPhone14,6": @"iPhone SE (3rd generation)",
            @"iPhone14,2": @"iPhone 13 Pro",
            @"iPhone14,3": @"iPhone 13 Pro Max",
            @"iPhone14,4": @"iPhone 13 mini",
            @"iPhone14,5": @"iPhone 13",
            @"iPhone13,1": @"iPhone 12 mini",
            @"iPhone13,2": @"iPhone 12",
            @"iPhone13,3": @"iPhone 12 Pro",
            @"iPhone13,4": @"iPhone 12 Pro Max",
            @"iPhone12,8": @"iPhone SE (2nd generation)",
            @"iPhone12,1": @"iPhone 11",
            @"iPhone12,3": @"iPhone 11 Pro",
            @"iPhone12,5": @"iPhone 11 Pro Max",
            @"iPhone11,8": @"iPhone XR",
            @"iPhone11,2": @"iPhone XS",
            @"iPhone11,4": @"iPhone XS Max",
            @"iPhone11,6": @"iPhone XS Max",
            @"iPhone10,1": @"iPhone 8",
            @"iPhone10,2": @"iPhone 8 Plus",
            @"iPhone10,3": @"iPhone X",
            @"iPhone10,6": @"iPhone X",
            @"iPhone9,1": @"iPhone 7",
            @"iPhone9,3": @"iPhone 7",
            @"iPhone9,2": @"iPhone 7 Plus",
            @"iPhone9,4": @"iPhone 7 Plus",
            @"iPhone8,1": @"iPhone 6s",
            @"iPhone8,2": @"iPhone 6s Plus",
            @"iPhone8,4": @"iPhone SE (1st generation)",
        };
    });
    NSString *name = table[machine];
    return name ?: machine;
}

NSString *getSystemVersionDisplay(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIDevice *device = [UIDevice currentDevice];
        NSString *prefix = [device userInterfaceIdiom] == UIUserInterfaceIdiomPad
            ? @"iPadOS" : @"iOS";
        // 构建号（如 22D2082）：kern.osbuildversion，读不到时只显示系统版本
        NSString *build = nil;
        size_t len = 0;
        if (sysctlbyname("kern.osbuildversion", NULL, &len, NULL, 0) == 0 && len > 0) {
            char *buf = malloc(len);
            if (buf) {
                if (sysctlbyname("kern.osbuildversion", buf, &len, NULL, 0) == 0) {
                    build = [NSString stringWithUTF8String:buf];
                }
                free(buf);
            }
        }
        if (build.length > 0) {
            cached = [NSString stringWithFormat:@"%@ %@ (%@)", prefix, device.systemVersion, build];
        } else {
            cached = [NSString stringWithFormat:@"%@ %@", prefix, device.systemVersion];
        }
    });
    return cached;
}

// Task91：TrollStore 真实安装判定——签名标记 AND 磁盘标记（bundle 旁的
// _TrollStore 目录，与 main.m 的 POJAV_DETECTEDINST 判定同源）。
// 背景：entitlements.sideload.xml 模板给普通侧载包也预写了
// jb.pmap_cs.custom_trust 字符串，SecTask 如实报告"有"，导致非 TrollStore
// 环境的 invokeAfterJITEnabled 误走 apple-magnifier://（TrollStore JIT）
// 死路——JIT 永远无法自动开启。此处做 AND 确认后该路径只在真实
// TrollStore 安装上生效，普通侧载回到 stikjit:// 正常流程。
BOOL isTrollStoreInstall(void) {
    if (!getEntitlementValue(@"jb.pmap_cs.custom_trust")) return NO;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    return access(tsPath.UTF8String, F_OK) == 0;
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

    // NOTE: the tail below deliberately matches upstream semantics exactly
    // (cf. 31d83637 which first simplified it this way): CS_DEBUGGED alone
    // decides.  A TXM "debugger keep-attached" gate reintroduced by 9c6cdb53
    // broke status display AND the launch path on StikJIT/SideJIT/NB-style
    // tools: they attach externally (ppid stays 1, P_TRACED unset by the
    // time we look, no task-level exception ports), yet the JIT26 mapping
    // service keeps working -- measured on-device as CS_DEBUGGED=1 ppid=1
    // traced=0 exn=0 with "[JIT26] Got JIT mapping from debugger" succeeding
    // right after.  Gating on debugger-attach state misreported such fully
    // working sessions as "JIT not enabled" and forced a redundant
    // stikjit:// round trip on every launch.  The helpers
    // JIT26IsLikelyDebuggerKeepAttached() / JIT26DebuggerAttachedViaPtrace()
    // / JIT26DebuggerViaExceptionPorts() are still exported for diagnostics.
    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
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

// Task91：SIGTRAP 安全网。见 utils.h 注释——brk #0x69 无人应答时裸函数
// 直接 SIGTRAP 致死（用户实测"开启 JIT 后闪退"），这里在调用窗口内捕获
// 并返回 NULL，把必死崩溃转成调用方的优雅报错；调试器正常应答时走
// 调试器例外端口/ptrace，本信号处理器不会被触发，行为不变。
static sigjmp_buf g_jit26TrapEnv;
static volatile sig_atomic_t g_jit26TrapArmed = 0;

static void JIT26TrapCatch(int sig) {
    if (!g_jit26TrapArmed) {
        // 不属于本安全网的 SIGTRAP：恢复默认语义原样致死，不吞异常
        signal(sig, SIG_DFL);
        raise(sig);
        return;
    }
    g_jit26TrapArmed = 0;
    siglongjmp(g_jit26TrapEnv, 1);
}

void* JIT26CreateRegionLegacySafe(size_t len) {
    struct sigaction sa, oldsa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = JIT26TrapCatch;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NODEFER;
    sigaction(SIGTRAP, &sa, &oldsa);

    void *result = NULL;
    if (sigsetjmp(g_jit26TrapEnv, 1) == 0) {
        g_jit26TrapArmed = 1;
        result = JIT26CreateRegionLegacy(len);
        g_jit26TrapArmed = 0;
    } else {
        result = NULL;
    }
    sigaction(SIGTRAP, &oldsa, NULL);
    return result;
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
