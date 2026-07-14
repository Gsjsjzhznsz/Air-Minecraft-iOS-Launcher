#import <mach-o/dyld.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#import "customcontrols/CustomControlsUtils.h"
#import "HostManagerBridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
#import "config.h"

#include <libgen.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include "utils.h"
#include "codesign.h"

#define CS_PLATFORM_BINARY 0x4000000
#define PT_TRACE_ME 0
#define PT_DETACH 11 
int ptrace(int, pid_t, caddr_t, int);
#define fm NSFileManager.defaultManager
extern char** environ;

void printEntitlementAvailability(NSString *key) {
    NSLog(@"* %@: %@", key, getEntitlementValue(key) ? @"YES" : @"NO");
}

void uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"Uncaught exception: %@", exception.description);
    NSLog(@"Call stack: %@", exception.callStackSymbols);
    usleep(10000);
}

bool init_checkForsubstrated() {
    // Please kindly tell pwn20wnd that he sucks
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    do {
        size += size / 10;
        newprocess = realloc(process, size);
        if (!newprocess){
            if (process){
                free(process);
            }
            return nil;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    } while (st == -1 && errno == ENOMEM);
    if (st == 0){
        if (size % sizeof(struct kinfo_proc) == 0){
            int nprocess = size / sizeof(struct kinfo_proc);
            if (nprocess){
                for (int i = nprocess - 1; i >= 0; i--){
                    if(strcmp(process[i].kp_proc.p_comm,"substrated") == 0) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

bool init_checkForJailbreak() {
    if (NSProcessInfo.processInfo.macCatalystApp) {
        // macOS doesn't automatically enable JIT.
        return false;
    } else if (init_checkForsubstrated()) {
        return true;
    }

    // Check if posix_spawn is hooked
    for (int i=0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i),"/usr/lib/pspawn_payload-stg2.dylib") == 0) {
            return true;
        }
    }

    // Check if we have platform bit set
    uint32_t flags;
    csops(0, CS_OPS_STATUS, &flags, sizeof(flags));
    if ((flags & CS_PLATFORM_BINARY) != 0) {
        return true;
    }

    return opendir("/Applications") != NULL;
}

void init_logDeviceAndVer(char *argument) {
    // Amethyst version
    NSLog(@"[Pre-Init] Amethyst iOS Remastered INIT!");
    NSLog(@"[Pre-Init] GitHub: https://github.com/herbrine8403/Amethyst-iOS-MyRemastered");
    NSLog(@"[Pre-Init] Please try not to post this log of the remastered launcher to the original GitHub Issues for help.");
    NSLog(@"[Pre-Init] Version: %@", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], CONFIG_TYPE);
    NSLog(@"[Pre-Init] Commit: %s (%s)", CONFIG_COMMIT, CONFIG_BRANCH);
    
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    const char *type;
    if (!access(tsPath.UTF8String, F_OK)) {
        type = "TrollStore";
    } else if (isJailbroken) {
        type = "Jailbroken";
    } else {
        type = "Unjailbroken";
    }
    setenv("POJAV_DETECTEDINST", type, 1);
    
    NSLog(@"[Pre-Init] Device: %@", [HostManager GetModelName]);
    NSLog(@"[Pre-Init] %@ (%s)", UIDevice.currentDevice.completeOSVersion, type);
    
    NSLog(@"[Pre-init] Entitlements availability:");
    printEntitlementAvailability(@"com.apple.developer.kernel.extended-virtual-addressing");
    printEntitlementAvailability(@"com.apple.developer.kernel.increased-memory-limit");
    printEntitlementAvailability(@"com.apple.private.security.no-sandbox");
    //printEntitlementAvailability(@"dynamic-codesigning");
}

void init_redirectStdio() {
    if (getenv("LOG_TO_CONSOLE") != NULL) {
        NSLog(@"[Pre-init] LOG_TO_CONSOLE is set, not logging to latestlog.txt");
        return;
    }

    NSLog(@"[Pre-init] Starting logging STDIO to latestlog.txt\n");

    NSString *home = @(getenv("POJAV_HOME"));
    NSString *currName = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSString *oldName = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];

    if (!file) {
        NSLog(@"[Pre-init] Error: failed to open %@", currName);
        assert(0 && "Failed to open latestlog.txt. Check oslog for more details.");
    }

    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered

    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));

    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static BOOL filteredSessionID;
        ssize_t rsize;
        char buf[2048];
        // 行缓冲区修复：read() 不保证按行返回，当 MC 输出日志频繁时
        // pipe 缓冲区会积累多个不完整行。之前直接对 read 返回的块按行分割，
        // 不完整的行片段（如 "Local game hoste" + "d on port 54321"）被当作
        // 独立行发送给 LanPortDetector，导致正则无法匹配，"对局域网开放"
        // 端口检测失败。现在维护行缓冲区，遇到 \n 才提取完整行。
        NSMutableData *lineBuffer = [NSMutableData data];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            // Filter out Session ID here
            int index;
            if (!filteredSessionID) {
                char *sessionStr = strstr(buf, "(Session ID is ");
                if (sessionStr) {
                    char *censorStr = "(Session ID is <censored>)\n\0";
                    strcpy(sessionStr, censorStr);
                    rsize = strlen(buf);
                    filteredSessionID = true;
                }
            }
            // 写入 latestlog.txt（保持原始字节流，不依赖行切片）
            [file writeData:[NSData dataWithBytes:buf length:rsize]];
            [file synchronizeFile];

            // 累积到行缓冲区，按 \n 提取完整行
            [lineBuffer appendBytes:buf length:rsize];
            const char *rawBytes = lineBuffer.bytes;
            NSUInteger rawLength = lineBuffer.length;
            NSUInteger lineStart = 0;
            for (NSUInteger i = 0; i < rawLength; i++) {
                if (rawBytes[i] == '\n') {
                    NSUInteger lineLen = i - lineStart;
                    if (lineLen > 0) {
                        NSString *line = [[NSString alloc] initWithBytes:rawBytes + lineStart
                                                                   length:lineLen
                                                                 encoding:NSUTF8StringEncoding];
                        if (line) {
                            if (canAppendToLog) {
                                // canAppendToLog=YES：通过 appendToLog: 同时更新 UI 和发送通知
                                // PLLogOutputView._appendToLog 内部会发送 PLLogOutputLineNotification
                                [PLLogOutputView appendToLog:line];
                            } else {
                                // canAppendToLog=NO：直接在后台线程发送通知给 LanPortDetector
                                // LanPortDetector.processLogLine: 是无状态的，setPort:source:
                                // 内部 dispatch_async 到主线程，线程安全
                                [[NSNotificationCenter defaultCenter] postNotificationName:@"PLLogOutputLineNotification"
                                                                                    object:nil
                                                                                  userInfo:@{@"line": line}];
                            }
                        }
                    }
                    lineStart = i + 1;
                }
            }
            // 移除已处理的字节，保留未结尾 \n 的残留部分（下次 read 继续累积）
            if (lineStart > 0) {
                [lineBuffer replaceBytesInRange:NSMakeRange(0, lineStart) withBytes:NULL length:0];
            }
        }
        // 处理残留的最后一行（没有 \n 结尾）
        if (lineBuffer.length > 0) {
            NSString *line = [[NSString alloc] initWithData:lineBuffer encoding:NSUTF8StringEncoding];
            if (line.length > 0) {
                if (canAppendToLog) {
                    [PLLogOutputView appendToLog:line];
                } else {
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"PLLogOutputLineNotification"
                                                                        object:nil
                                                                      userInfo:@{@"line": line}];
                }
            }
        }
        [file closeFile];
    });

    // We can start catching exception right now
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
}

void init_setupAccounts() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"accounts"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
}

void init_setupCustomControls() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"controlmap"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControl();
    generateAndSaveCustomControl();
    NSString *gamepadControlPath = [controlPath stringByAppendingPathComponent:@"gamepads"];
    [fm createDirectoryAtPath:gamepadControlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControlForGamepad();
}

void init_setupMultiDir() {
    NSString *multidir = getPrefObject(@"general.game_directory");
    if (multidir.length == 0) {
        multidir = @"default";
        setPrefObject(@"general.game_directory", multidir);
        NSLog(@"[Pre-init] Game directory was not set. Defaulting to %@ for future use.\n", multidir);
    } else {
        NSLog(@"[Pre-init] Restored game directory preference (%@)\n", multidir);
    }

    const char *home = getenv("POJAV_HOME");
    NSString *lasmPath = [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", home];
    NSString *multidirPath = [NSString stringWithFormat:@"%s/instances/%@", home, multidir];


    NSArray *dirsToCreate = @[
        [NSString stringWithFormat:@"%s/.demo", home],
        [NSString stringWithFormat:@"%s/java_runtimes", home],
        lasmPath.stringByDeletingLastPathComponent,
        multidirPath
    ];
    for (NSString *dir in dirsToCreate) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [fm removeItemAtPath:lasmPath error:nil];
    [fm createSymbolicLinkAtPath:lasmPath withDestinationPath:multidirPath error:nil];
    [fm changeCurrentDirectoryPath:lasmPath];
    setenv("POJAV_GAME_DIR", lasmPath.UTF8String, 1);
}

void init_setupResolvConf() {
    // Write known DNS servers to the config
    NSString *path = [NSString stringWithFormat:@"%s/resolv.conf", getenv("POJAV_HOME")];
    if (![fm fileExistsAtPath:path]) {
        [@"nameserver 8.8.8.8\n"
         @"nameserver 8.8.4.4"
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void init_setupHomeDirectory() {
    setenv("HOME", [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path.stringByDeletingLastPathComponent.UTF8String, 1);
    NSString *homeDir;
    NSError *homeError;
    
    BOOL isNotSandboxed = [@(getenv("HOME")).lastPathComponent isEqualToString:NSUserName()];
    homeDir = [NSString stringWithFormat:@"%s/Documents%@", getenv("HOME"),
        isNotSandboxed ? @"/AngelAuraAmethyst":@""];

    if (![fm fileExistsAtPath:homeDir] ) {
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:NO attributes:nil error:&homeError];
    }
    
    if(homeError != nil) {
        // TODO: Persistent storage
        homeError = nil;
        homeDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&homeError];
    }
    
    setenv("POJAV_HOME", realpath(homeDir.UTF8String, NULL), 1);
}

int main(int argc, char *argv[]) {
    if (pJLI_Launch) {
        return pJLI_Launch(argc, (const char **)argv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
    }

    if (!isJITEnabled(true) && argc == 2) {
        NSLog(@"calling ptrace(PT_TRACE_ME)");
        // Child process can call to PT_TRACE_ME
        // then both parent and child processes get CS_DEBUGGED
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    setenv("BUNDLE_PATH", dirname(argv[0]), 1);
    isJailbroken = init_checkForJailbreak();
    init_setupHomeDirectory();
    init_redirectStdio();
    init_logDeviceAndVer(argv[0]);

    loadPreferences(NO);
    init_hookFunctions();
    init_hookUIKitConstructor();

    debugLogEnabled = getPrefBool(@"general.debug_logging");
    NSLog(@"[Debugging] Debug log enabled: %@", debugLogEnabled ? @"YES" : @"NO");

    init_setupResolvConf();
    init_setupMultiDir();
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];
    init_setupAccounts();
    init_setupCustomControls();

    // If sandbox is disabled, W^X JIT can be enabled by Amethyst itself
    if (!isJITEnabled(true) && getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        NSLog(@"[Pre-init] no-sandbox: YES, trying to enable JIT");
        int pid;
        int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
        if (ret == 0) {
            // Cleanup child process
            waitpid(pid, NULL, WUNTRACED);
            ptrace(PT_DETACH, pid, NULL, 0);
            kill(pid, SIGTERM);
            wait(NULL);

            if (isJITEnabled(true)) {
                NSLog(@"[Pre-init] JIT has been enabled with PT_TRACE_ME");
            } else {
                NSLog(@"[Pre-init] Failed to enable JIT: unknown reason");
            }
        } else {
            NSLog(@"[Pre-init] Failed to enable JIT: posix_spawn() failed errno %d", errno);
        }
    }

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
