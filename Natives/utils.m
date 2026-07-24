#import <SafariServices/SafariServices.h>

#include "jni.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/sysctl.h>

#include "utils.h"

CFTypeRef SecTaskCopyValueForEntitlement(void* task, NSString* entitlement, CFErrorRef  _Nullable *error);
void* SecTaskCreateFromSelf(CFAllocatorRef allocator);

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf(NULL), key, nil);
    if (value != nil) {
        CFRelease(value);
    }
    CFRelease(secTask);

    return value != nil && [(__bridge id)value boolValue];
}

BOOL isJITEnabled(BOOL checkCSFlags) {
    if (!checkCSFlags && (getEntitlementValue(@"dynamic-codesigning") || isJailbroken)) {
        return YES;
    }

    // 路径 1：csops 检查 CS_DEBUGGED 标志位
    // 覆盖 PojavLauncher 自身 ptrace(PT_TRACE_ME) / TrollStore JIT / 越狱场景
    int flags = 0;
    if (csops(getpid(), 0, &flags, sizeof(flags)) == 0) {
        if (flags & CS_DEBUGGED) {
            // iOS 26+ TXM 检查：设备处于 iOS 26+ 且具备 TXM 时，
            // 需要 JIT 脚本绕过 TXM 限制，此时调试器必须保持附加。
            // Device below iOS 26 or without TXM is sufficient at this point.
            if (!DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
                return YES;
            }
            // Device with iOS 26+ and TXM requires a debugger attached for JIT script to bypass TXM restrictions
            return JIT26IsLikelyDebuggerKeepAttached();
        }
        // 部分工具（SideStore 等）通过 get-task-allow + dynamic-codesigning 启用 JIT，
        // 某些设备上 CS_DEBUGGED 未置位但 CS_GET_TASK_ALLOW 已置位。
        if (flags & 0x00000004 /* CS_GET_TASK_ALLOW */) {
            return YES;
        }
    }

    // 路径 2：sysctl KERN_PROC 检查 P_TRACED 标志位
    // 覆盖 NB 助手 / SideStore / Stikdebug / JitStream 等"外部调试器附加"型 JIT 工具。
    // 这些工具通过 ptrace(PT_TRACE_ATTACH) 或 task_for_pid 附加到本进程，
    // 进程的 kinfo_proc.kp_proc.p_flag 会被置上 P_TRACED，而 csops 不一定同步置 CS_DEBUGGED。
    // P_TRACED 在 <sys/proc.h> 中定义为 0x800，部分 iOS SDK 未自动引入该头文件，
    // 这里直接使用数值避免依赖头文件可见性。
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &info, &size, NULL, 0) == 0 && size == sizeof(info)) {
        if (info.kp_proc.p_flag & 0x800 /* P_TRACED */) {
            // iOS 26+ TXM 检查（重制版增强：P_TRACED 路径同样需要 TXM workaround 判定）
            if (!DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
                return YES;
            }
            return JIT26IsLikelyDebuggerKeepAttached();
        }
    }

    return NO;
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
    NSString *value = NSLocalizedString(key, nil);
    if (![NSLocale.preferredLanguages[0] isEqualToString:@"en"] && [value isEqualToString:key]) {
        NSString* path = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
        NSBundle* languageBundle = [NSBundle bundleWithPath:path];
        value = [languageBundle localizedStringForKey:key value:nil table:nil];

        if ([value isEqualToString:key]) {
            value = [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:key value:nil table:nil];
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

BOOL JIT26IsLikelyDebuggerKeepAttached(void) {
    // getppid() always return launchd PID (1) unless debugger is actively attached
    return getppid() != 1;
}

BOOL DeviceCanCreateRXMap(void) {
    // This is only guaranteed to be accurate when JIT is already enabled. Obviously this is only useful for vphone and similar internal environments where JIT is always enabled.
    uint32_t *map = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0);
    assert(map != MAP_FAILED);
    *map = 0xFFFFFFFF;
    int ret = mprotect(map, getpagesize(), PROT_READ | PROT_EXEC) | mprotect(map, getpagesize(), PROT_READ | PROT_EXEC);
    munmap(map, getpagesize());
    return ret == 0;
}

BOOL DeviceHasTXMReal(void) {
    // TXM（Trusted Execution Monitor）仅在 iOS 16+ 设备上存在。
    // 旧版 DeviceRequiresTXMWorkaround 有 @available(iOS 16.0, *) 保护，
    // 移植到 DeviceHasTXMReal 时遗漏了此保护。低版本（如 iOS 15）上调用
    // MGGetSInt64Answer 私有 API不安全，且 /private/preboot 目录不存在，
    // 故低版本直接返回 NO。
    if (@available(iOS 16.0, *)) {
        DIR *d = opendir("/private/preboot");
        if(!d) {
            // /private/preboot is not accessible in 27.0 and 26.6?, fallback to speculation
            NSUInteger (*MGGetSInt64Answer)(NSString *) = dlsym(RTLD_DEFAULT, "MGGetSInt64Answer");
            NSUInteger chipID = MGGetSInt64Answer(@"ChipID");
            switch(chipID) {
                case 0x8020: // A12
                case 0x8027: // A12X/Z
                    return NO;
                case 0x8030: // A13
                case 0x8101: // A14
                case 0x8103: // M1
                    if (@available(iOS 27.0, *)) return YES; return NO;
                default:
                    if (@available(iOS 19.0, *)) return YES; return NO;
            }
        }
        // deterministically detect TXM for 17.0-26.5?
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
    return NO;
}

// Thin wrapper of DeviceHasJITFlags to respect overriden flag
__exported BOOL DeviceHasTXM(void) {
    return DeviceHasJITFlags(JIT_FLAG_HAS_TXM);
}

JITFlags DeviceGetJITFlags(BOOL refresh) {
    static JITFlags cachedFlags = 0;
    static dispatch_once_t onceToken;
    if (refresh) onceToken = 0;
    dispatch_once(&onceToken, ^{
        const char *s = getenv("JIT_FLAGS");
        if (s) {
            if (s[0] == '0' && tolower(s[1]) == 'b') {
                cachedFlags = strtoul(s + 2, NULL, 2);
            } else {
                cachedFlags = strtoul(s, NULL, 0);
            }
            NSLog(@"[JIT] Using overridden JIT flags: 0x%X", cachedFlags);
            return;
        }

        if (@available(iOS 26.0, *)) {
            cachedFlags |= JIT_FLAG_IS_IOS_26;
            if (!DeviceCanCreateRXMap()) {
                cachedFlags |= JIT_FLAG_FORCE_MIRRORED;
            }
        }
        if (DeviceHasTXMReal()) {
            cachedFlags |= JIT_FLAG_HAS_TXM;
        }

        if (refresh) NSLog(@"[JIT] Using computed JIT flags: 0x%X", cachedFlags);
    });
    return cachedFlags;
}

BOOL DeviceHasJITFlags(JITFlags flags) {
    return (DeviceGetJITFlags(NO) & flags) == flags;
}

// 兼容性别名：保留旧 API，内部委托给 DeviceHasJITFlags
BOOL DeviceRequiresTXMWorkaround(void) {
    return DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM);
}

void dismissModalViewController(UIViewController *viewController) {
    [viewController.navigationController dismissViewControllerAnimated:YES completion:nil];
}
