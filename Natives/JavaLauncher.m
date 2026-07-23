#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <mach/mach.h>
#include "utils.h"
#include "ZinkConfig.h"

// god knows why Copilot was trying to add this.
#import "authenticator/BaseAuthenticator.h"
#import "authenticator/ThirdPartyAuthenticator.h"
// 鬼知道为什么copilot要把这玩意加里头……

#import "ios_uikit_bridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "MinecraftOptionUtils.h"
#import "PLProfiles.h"

#define fm NSFileManager.defaultManager

extern char **environ;

BOOL validateVirtualMemorySpace(size_t size) {
    size <<= 20; // convert to MB
    void *map = mmap(0, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    // check if process successfully maps and unmaps a contiguous range
    if(map == MAP_FAILED || munmap(map, size) != 0)
        return NO;
    return YES;
}

/// 检测 MC 版本是否使用 SDL3 窗口后端
/// MC 26.3-snapshot-4 首次从 GLFW 切换到 SDL3（Mojang 官方公告）。
/// 规则：
///   - 26.3-snapshot-4 及以上 → SDL3
///   - 26.3-snapshot-3 及以下 → GLFW
///   - 26.3 pre/rc/release 及 26.4+ → SDL3
///
/// 修复字典序比较 bug：
///   旧代码 `[versionId compare:@"26.4"] != NSOrderedAscending` 对所有
///   字典序 >= "26.4" 的字符串返回 YES。但 NSString compare 是按字符 ASCII
///   比较，"fabric-loader-0.18.4-1.21.1" 的首字符 'f'(102) > '2'(50)，
///   导致 1.21.1 Fabric 被误判为 SDL3 版本。
///   修复：仅对首字符为数字的版本字符串做 >= "26.4" 比较。
BOOL amethyst_isSDL3Version(NSString *versionId) {
    if (!versionId || versionId.length == 0) return NO;

    // 26.3-snapshot-N：N >= 4 用 SDL3
    if ([versionId hasPrefix:@"26.3-snapshot-"]) {
        NSString *numStr = [versionId substringFromIndex:@"26.3-snapshot-".length];
        NSInteger n = numStr.integerValue;
        return n >= 4;
    }
    // 26.3 pre/rc/release 用 SDL3
    if ([versionId hasPrefix:@"26.3-pre"] || [versionId hasPrefix:@"26.3-rc"]
        || [versionId isEqualToString:@"26.3"]) {
        return YES;
    }
    // 26.4+ 用 SDL3（仅对数字开头的版本字符串做比较，避免 "fabric-loader-..." 误判）
    unichar firstChar = [versionId characterAtIndex:0];
    if (firstChar >= '0' && firstChar <= '9'
        && [versionId compare:@"26.4"] != NSOrderedAscending) {
        return YES;
    }
    return NO;
}

void init_loadDefaultEnv() {
    /* Define default env */

    // Silent Caciocavallo NPE error in locating Android-only lib
    setenv("LD_LIBRARY_PATH", "", 1);

    // Ignore mipmap for performance(?) seems does not affect iOS
    //setenv("LIBGL_MIPMAP", "3", 1);

    // Disable overloaded functions hack for Minecraft 1.17+
    setenv("LIBGL_NOINTOVLHACK", "1", 1);

    // Fix white color on banner and sheep, since GL4ES 1.1.5
    setenv("LIBGL_NORMALIZE", "1", 1);

    // Override OpenGL version to 4.1 for Zink
    setenv("MESA_GL_VERSION_OVERRIDE", "4.1", 1);

    // Suppress [mvk-info] log spam (swapchain creation, etc.)
    // 对齐 Ynnyny 仓库：抑制 MoltenVK 日志刷屏，便于诊断启动问题
    // 但当帧率解锁开启时，临时启用性能跟踪以诊断 present mode 问题
    if (getPrefBool(@"video.disable_game_vsync")) {
        // 帧率解锁诊断：启用 MoltenVK 性能跟踪，输出帧率和 swapchain 信息
        // 有助于确认 Vulkan 模式下 present mode 是否为 IMMEDIATE
        setenv("MVK_CONFIG_PERFORMANCE_TRACKING", "1", 1);
        setenv("MVK_CONFIG_LOG_LEVEL", "2", 1); // 仍然抑制 info 级别，但 performance log 会输出
        // 尝试强制 present mode 为 IMMEDIATE（不等 vsync）。
        // MoltenVK 1.2.5+ 支持 MVK_CONFIG_SWAPCHAIN_PRESENT_MODE 环境变量：
        //   0 = VK_PRESENT_MODE_IMMEDIATE_KHR（不等 vsync，帧率可超屏幕刷新率）
        //   1 = VK_PRESENT_MODE_MAILBOX_KHR
        //   2 = VK_PRESENT_MODE_FIFO_KHR（默认，等 vsync）
        // 实际运行的 MoltenVK 版本为 1.2.9（从 libMoltenVK.dylib 二进制确认），
        // 支持此环境变量。仓库中的 vk_mvk_moltenvk.h 头文件是旧版本（1.1.2），
        // 但实际 dylib 已是 1.2.9，环境变量会生效。
        // 这是 Vulkan 模式帧率解锁的关键：present mode 完全由 vkCreateSwapchainKHR
        // 选择，而 MC 26.2 的 Vulkan 渲染器可能未正确响应 enableVsync=false。
        // MoltenVK 1.2.9 在 vkCreateSwapchainKHR 时会读取此环境变量覆盖应用的 presentMode。
        setenv("MVK_CONFIG_SWAPCHAIN_PRESENT_MODE", "0", 1);
        NSLog(@"[JavaLauncher] MoltenVK performance tracking + IMMEDIATE present mode requested for VSync diagnosis");
    } else {
        setenv("MVK_CONFIG_LOG_LEVEL", "2", 1);
    }

    // SDL3 诊断日志（临时）：启用 verbose 级别，输出 SDL3 内部初始化/窗口创建流程
    // 用于诊断 MC 26.3-snapshot-4 SDL3 窗口创建阻塞问题
    // 格式：*=verbose 表示所有 category 都用 verbose 级别
    setenv("SDL_LOGGING", "*=verbose", 1);

    // Runs JVM in a separate thread
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);

    // 解锁帧率（关闭垂直同步）：读取启动器偏好，通过环境变量传递给 Java 层和 native 桥接层。
    //
    // 帧率解锁的三层机制（各层独立生效，互为兜底）：
    //
    // 1. Java 层（PojavLauncher.java）读取 POJAV_DISABLE_VSYNC=1 后：
    //    a) 强制写 enableVsync=false → MC 不再调用 glfwSwapInterval(1)
    //    b) 强制写 maxFps=260 → MC 1.16+ 源码中 maxFps>=260 视为"无限制"
    //       （之前用 maxFps=0 会被 MC 当作无效值忽略，导致帧率仍被 maxFps=120 限制）
    //
    // 2. native 桥接层（egl_bridge.m pojavSwapInterval）读取 POJAV_DISABLE_VSYNC=1 后：
    //    拦截 MC 的 glfwSwapInterval(1) 请求，强制改为 interval=0
    //    （会记录每次拦截，帮助诊断 mod 运行时重新启用 VSync 的情况）
    //
    // 3. EGL 初始化层（gl_bridge.m gl_make_current）读取 POJAV_DISABLE_VSYNC=1 后：
    //    在 eglMakeCurrent 成功后立即调用 eglSwapInterval(0)。
    //    这是 zink 渲染器帧率解锁的关键——Mesa 21.0 的 zink 在延迟创建 Vulkan swapchain
    //    时根据当前 eglSwapInterval 选择 present mode：
    //      interval=0 → VK_PRESENT_MODE_IMMEDIATE_KHR（不等 vsync，帧率可超 60）
    //      interval=1 → VK_PRESENT_MODE_FIFO_KHR（等 vsync，锁在屏幕刷新率）
    //    如果等 MC 调用 glfwSwapInterval 时才设置，swapchain 可能已用 FIFO 创建，
    //    Mesa 21.0 的 zink 不会动态重建 swapchain，导致帧率锁死在屏幕刷新率。
    //
    // 关于 MoltenVK 配置与 Vulkan 帧率解锁研究：
    //   实际运行的 MoltenVK 版本为 1.2.9（从 libMoltenVK.dylib 二进制确认）。
    //   仓库中的 vk_mvk_moltenvk.h 头文件是旧版本（1.1.2, spec 30），
    //   但实际 dylib 已是 1.2.9，支持 MVK_CONFIG_SWAPCHAIN_PRESENT_MODE 环境变量。
    //   MoltenVK 1.2.9 在 vkCreateSwapchainKHR 时会读取此环境变量覆盖应用的 presentMode，
    //   这是 Vulkan 模式帧率解锁的关键机制。
    //   设备是否支持 IMMEDIATE present mode 由 MVKPhysicalDeviceMetalFeatures.presentModeImmediate
    //   自动检测（大多数 iOS 设备支持）。
    //
    //   Vulkan 模式帧率解锁的多层机制：
    //   1. MC 选项层：enableVsync=false + maxFps=260（MC 1.16+ 视 260 为 unlimited）
    //   2. MoltenVK 配置层：MVK_CONFIG_SWAPCHAIN_PRESENT_MODE=0 → IMMEDIATE present mode
    //      （MoltenVK 1.2.9 支持，覆盖应用在 vkCreateSwapchainKHR 选择的 presentMode）
    //   3. MC 26.2 兼容：同时写入 maxFps/maxFramerate/framerateLimit 多种选项名
    //
    // 各渲染器的帧率解锁效果：
    // - zink（GL→Vulkan）：通过 eglSwapInterval(0) → IMMEDIATE present mode 完全解锁
    // - Vulkan（LWJGL3）：MVK_CONFIG_SWAPCHAIN_PRESENT_MODE=0 → IMMEDIATE present mode 完全解锁
    // - ANGLE Metal：eglSwapInterval(0) 让 ANGLE 不等 vsync，渲染线程不阻塞
    // - ProMotion 设备：通过 CADisableMinimumFrameDurationOnPhone + preferredFrameRateRange 启用 120Hz
    setenv("POJAV_DISABLE_VSYNC", getPrefBool(@"video.disable_game_vsync") ? "1" : "0", 1);

    // 帧率解锁诊断日志：记录关键环境变量和偏好设置
    NSLog(@"[JavaLauncher] Framerate unlock configuration:");
    NSLog(@"[JavaLauncher]   video.disable_game_vsync=%d", getPrefBool(@"video.disable_game_vsync"));
    NSLog(@"[JavaLauncher]   POJAV_DISABLE_VSYNC=%s", getenv("POJAV_DISABLE_VSYNC"));
    NSLog(@"[JavaLauncher]   UIScreen.maximumFramesPerSecond=%d", (int)UIScreen.mainScreen.maximumFramesPerSecond);
}

void init_loadCustomEnv() {
    NSString *envvars = getPrefObject(@"java.env_variables");
    if (envvars == nil) return;
    NSLog(@"[JavaLauncher] Reading custom environment variables");
    for (NSString *line in [envvars componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (![line containsString:@"="]) {
            NSLog(@"[JavaLauncher] Warning: skipped empty value custom env variable: %@", line);
            continue;
        }
        NSRange range = [line rangeOfString:@"="];
        NSString *key = [line substringToIndex:range.location];
        NSString *value = [line substringFromIndex:range.location+range.length];
        setenv(key.UTF8String, value.UTF8String, 1);
        NSLog(@"[JavaLauncher] Added custom env variable: %@", line);
    }
}

/// 加载 MobileGlues 配置并写入 config.json
///
/// 将用户偏好设置写入 <POJAV_HOME>/MG/config.json，供 MobileGlues 渲染器读取。
///
/// 渲染器与 MobileGlues 的关系（重要）：
/// - MobileGlues 渲染器（libmobileglues.dylib）：直接加载 MobileGlues，config.json 生效。
/// - Auto 渲染器：在 launchJVM 中被解析为 ANGLE（libtinygl4angle.dylib），MobileGlues 不会被加载，
///   config.json 虽然会写入但不会被读取。用户需显式选择 MobileGlues 渲染器才能让设置生效。
/// - Vulkan 渲染器：Vulkan 模式下 OpenGL 回退库使用 MobileGlues（对齐 Ynnyny 仓库），
///   config.json 会被 MobileGlues 读取并生效。
void init_loadMobileGluesConfig() {
    NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
    NSLog(@"[JavaLauncher] init_loadMobileGluesConfig: renderer=%@", renderer);

    BOOL usesMobileGlues = [renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES] ||
        [renderer isEqualToString:@"auto"] ||
        [renderer isEqualToString:@ RENDERER_NAME_VULKAN];

    if (!usesMobileGlues) {
        NSLog(@"[JavaLauncher] MobileGlues config not written (renderer is not mobileglues/auto/vulkan)");
        return;
    }

    // 警告：auto 渲染器实际不会加载 MobileGlues，设置不会生效
    if ([renderer isEqualToString:@"auto"]) {
        NSLog(@"[JavaLauncher] WARNING: renderer is 'auto', will be resolved to ANGLE. "
              @"MobileGlues settings will NOT take effect. "
              @"Please explicitly select 'MobileGlues' renderer to use these settings.");
    } else if ([renderer isEqualToString:@ RENDERER_NAME_VULKAN]) {
        NSLog(@"[JavaLauncher] Vulkan renderer detected, MobileGlues used as GL fallback. Config will take effect.");
    } else {
        NSLog(@"[JavaLauncher] MobileGlues renderer detected, config will take effect.");
    }

    NSString *mgDirPath = [NSString stringWithFormat:@"%s/MG", getenv("POJAV_HOME")];
    setenv("MG_DIR_PATH", mgDirPath.UTF8String, 1);

    NSMutableDictionary *config = [NSMutableDictionary dictionary];

    // 安全默认值
    // 注意：MobileGlues 的 Version(int code) 构造函数把数字转为字符串后取前 3 位
    // 作为 Major.Minor.Patch（settings.h 第 102-116 行）。例如 40 → "40" → 4.0.0。
    // customGLVersion 约束（settings.cpp 第 71-79 行）：>46 截断为 46，<32 且非 0 截断为 32，
    // 33-39 截断为 33，0 使用默认值 40。
    // 因此必须写入十进制数（40, 41, 42, ..., 46），不能写入十六进制 0x040000。
    config[@"enableExtGL43"] = @1;
    config[@"enableExtDirectStateAccess"] = @1;
    config[@"maxGlslCacheSize"] = @128;
    config[@"customGLVersion"] = @40;  // 十进制 40 = GL 4.0

    id enableAngle = getPrefObject(@"mobileglues.enable_angle");
    if (enableAngle) {
        // MobileGlues AngleConfig 枚举（settings.h）：
        //   0 = DisableIfPossible
        //   1 = EnableIfPossible  ← iOS 上 hasVulkan12() 永远返回 0（#ifndef __APPLE__
        //                            块被跳过），导致 checkIfANGLESupported 返回 false，
        //                            ANGLE 被禁用。不能使用此值。
        //   2 = ForceDisable
        //   3 = ForceEnable       ← 强制启用，绕过 GPU 检测
        // 用户启用 enable_angle 时写入 3 (ForceEnable)，禁用时写入 0 (DisableIfPossible)
        config[@"enableANGLE"] = [enableAngle boolValue] ? @3 : @0;
        NSLog(@"[JavaLauncher]   mobileglues.enable_angle = %@ -> enableANGLE = %@ (3=ForceEnable, 0=DisableIfPossible)",
              enableAngle, config[@"enableANGLE"]);
    }

    id enableNoError = getPrefObject(@"mobileglues.enable_no_error");
    if (enableNoError) {
        config[@"enableNoError"] = @([enableNoError intValue]);
        NSLog(@"[JavaLauncher]   mobileglues.enable_no_error = %@ -> enableNoError = %@", enableNoError, config[@"enableNoError"]);
    }

    id enableExtTimerQuery = getPrefObject(@"mobileglues.enable_ext_timer_query");
    if (enableExtTimerQuery) {
        config[@"enableExtTimerQuery"] = [enableExtTimerQuery boolValue] ? @1 : @0;
        NSLog(@"[JavaLauncher]   mobileglues.enable_ext_timer_query = %@ -> enableExtTimerQuery = %@", enableExtTimerQuery, config[@"enableExtTimerQuery"]);
    }

    id enableExtComputeShader = getPrefObject(@"mobileglues.enable_ext_compute_shader");
    if (enableExtComputeShader) {
        config[@"enableExtComputeShader"] = [enableExtComputeShader boolValue] ? @1 : @0;
        NSLog(@"[JavaLauncher]   mobileglues.enable_ext_compute_shader = %@ -> enableExtComputeShader = %@", enableExtComputeShader, config[@"enableExtComputeShader"]);
    }

    id enableExtDirectStateAccess = getPrefObject(@"mobileglues.enable_ext_direct_state_access");
    if (enableExtDirectStateAccess) {
        config[@"enableExtDirectStateAccess"] = [enableExtDirectStateAccess boolValue] ? @1 : @0;
        NSLog(@"[JavaLauncher]   mobileglues.enable_ext_direct_state_access = %@ -> enableExtDirectStateAccess = %@", enableExtDirectStateAccess, config[@"enableExtDirectStateAccess"]);
    }

    id maxGlslCacheSize = getPrefObject(@"mobileglues.max_glsl_cache_size");
    if (maxGlslCacheSize) {
        config[@"maxGlslCacheSize"] = @([maxGlslCacheSize intValue]);
        NSLog(@"[JavaLauncher]   mobileglues.max_glsl_cache_size = %@ -> maxGlslCacheSize = %@", maxGlslCacheSize, config[@"maxGlslCacheSize"]);
    }

    id multidrawMode = getPrefObject(@"mobileglues.multidraw_mode");
    if (multidrawMode) {
        config[@"multidrawMode"] = @([multidrawMode intValue]);
        NSLog(@"[JavaLauncher]   mobileglues.multidraw_mode = %@ -> multidrawMode = %@", multidrawMode, config[@"multidrawMode"]);
    }

    id angleDepthClearFixMode = getPrefObject(@"mobileglues.angle_depth_clear_fix_mode");
    if (angleDepthClearFixMode) {
        config[@"angleDepthClearFixMode"] = [angleDepthClearFixMode boolValue] ? @1 : @0;
        NSLog(@"[JavaLauncher]   mobileglues.angle_depth_clear_fix_mode = %@ -> angleDepthClearFixMode = %@", angleDepthClearFixMode, config[@"angleDepthClearFixMode"]);
    }

    id customGlVersion = getPrefObject(@"mobileglues.custom_gl_version");
    if (customGlVersion) {
        NSString *verStr = [customGlVersion description];
        NSLog(@"[JavaLauncher]   mobileglues.custom_gl_version = %@ (raw)", customGlVersion);
        // MobileGlues 期望十进制数：Version(int code) 把 code 转字符串后取前 3 位作为
        // Major.Minor.Patch。例如 40 → "40" → 4.0.0，46 → "46" → 4.6.0。
        // 不能用十六进制 0x040000（=262144），会被截断为 46（4.6.0）。
        if ([verStr isEqualToString:@"3.0"]) config[@"customGLVersion"] = @30;
        else if ([verStr isEqualToString:@"3.1"]) config[@"customGLVersion"] = @31;
        else if ([verStr isEqualToString:@"3.2"]) config[@"customGLVersion"] = @32;
        else if ([verStr isEqualToString:@"3.3"]) config[@"customGLVersion"] = @33;
        else if ([verStr isEqualToString:@"4.0"]) config[@"customGLVersion"] = @40;
        else if ([verStr isEqualToString:@"4.1"]) config[@"customGLVersion"] = @41;
        else if ([verStr isEqualToString:@"4.2"]) config[@"customGLVersion"] = @42;
        else if ([verStr isEqualToString:@"4.3"]) config[@"customGLVersion"] = @43;
        else if ([verStr isEqualToString:@"4.4"]) config[@"customGLVersion"] = @44;
        else if ([verStr isEqualToString:@"4.5"]) config[@"customGLVersion"] = @45;
        else if ([verStr isEqualToString:@"4.6"]) config[@"customGLVersion"] = @46;
        // verStr == @"0" 时不匹配任何条件，保留默认值 @40（即 GL 4.0）
        NSLog(@"[JavaLauncher]   -> customGLVersion = %d (decimal, MobileGlues Version(int) format)",
              [config[@"customGLVersion"] intValue]);
    }

    id fsr1Setting = getPrefObject(@"mobileglues.fsr1_setting");
    if (fsr1Setting) {
        config[@"fsr1Setting"] = @([fsr1Setting intValue]);
        NSLog(@"[JavaLauncher]   mobileglues.fsr1_setting = %@ -> fsr1Setting = %@", fsr1Setting, config[@"fsr1Setting"]);
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [fm createDirectoryAtPath:mgDirPath withIntermediateDirectories:YES attributes:nil error:nil];
        [jsonString writeToFile:[mgDirPath stringByAppendingPathComponent:@"config.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[JavaLauncher] MobileGlues config written to %@/config.json", mgDirPath);
        NSLog(@"[JavaLauncher] config.json content:\n%@", jsonString);
    } else {
        NSLog(@"[JavaLauncher] Failed to serialize MobileGlues config: %@", error);
    }
}

void init_loadCustomJvmFlags(int* argc, const char** argv) {
    NSString *jvmargs = [PLProfiles resolveKeyForCurrentProfile:@"javaArgs"];
    if (jvmargs == nil) return;
    // Make the separator happy
    jvmargs = [jvmargs stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    jvmargs = [@" " stringByAppendingString:jvmargs];

    // 关键修复（N3+N4）：retainedCustomFlags 强引用所有自定义 JVM flag 字符串，
    // 防止 [@"-" stringByAppendingString:jvmarg].UTF8String 返回的 C 字符串悬垂。
    //
    // 之前 argv[*argc] = [@"-" stringByAppendingString:jvmarg].UTF8String 直接取临时
    // NSString 的 UTF8String，autoreleased NSString 在 runloop drain 后会释放，
    // 导致 argv 中的指针悬垂。虽然 launchJava 通常在 JVM 启动前不会 drain autoreleasepool，
    // 但这是脆弱的隐式依赖。retainedCustomFlags 作为静态变量，生命周期覆盖整个进程，
    // 保证字符串在 pJLI_Launch 调用期间有效。
    static NSMutableArray<NSString *> *retainedCustomFlags = nil;
    if (retainedCustomFlags == nil) {
        retainedCustomFlags = [NSMutableArray array];
    }
    // 注意：不清空 retainedCustomFlags，因为 launchJava 在进程生命周期内只调用一次。
    // 如果未来变为可多次调用，需要在调用前清空。

    NSLog(@"[JavaLauncher] Reading custom JVM flags");
    NSArray *argsToPurge = @[@"Xms", @"Xmx", @"d32", @"d64"];
    for (NSString *arg in [jvmargs componentsSeparatedByString:@" -"]) {
        NSString *jvmarg = [arg stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (jvmarg.length == 0) continue;
        BOOL ignore = NO;
        for (NSString *argToPurge in argsToPurge) {
            if ([jvmarg hasPrefix:argToPurge]) {
                NSLog(@"[JavaLauncher] Ignored JVM flag: -%@", jvmarg);
                ignore = YES;
                break;
            }
        }
        if (ignore) continue;

        // N3 边界检查：argv 数组大小由调用方决定（margv[1000]），这里做防御性检查
        if (*argc + 1 >= 1000) {
            NSLog(@"[JavaLauncher] 警告：margv 已达上限（1000），丢弃自定义 JVM flag：-%@", jvmarg);
            continue;
        }
        NSString *flagStr = [@"-" stringByAppendingString:jvmarg];
        [retainedCustomFlags addObject:flagStr];
        ++*argc;
        argv[*argc] = flagStr.UTF8String;

        NSLog(@"[JavaLauncher] Added custom JVM flag: %s", argv[*argc]);
    }
}

int launchJVM(NSString *accountId, id launchTarget, int width, int height, int minVersion) {
    NSLog(@"[JavaLauncher] Beginning JVM launch");

    BOOL jit26UniversalScript = getPrefBool(@"debug.debug_universal_script_jit");
    BOOL jit26AlwaysAttached = getPrefBool(@"debug.debug_always_attached_jit");
    if(jit26UniversalScript) {
        JIT26SendJITScript([NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"JIT26Script" ofType:@"js"]]);
        JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached);
        // make sure we don't get stuck in EXC_BAD_ACCESS
        task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, 0, EXCEPTION_DEFAULT, MACHINE_THREAD_STATE);
    }

    if ([NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"]] && !@available(iOS 26.0, *)) {
        NSDebugLog(@"[JavaLauncher] Running in LiveContainer, skipping dyld patch");
    } else if(!@available(iOS 26.0, *) || jit26AlwaysAttached) {
        // Activate Library Validation bypass for external runtime and dylibs (JNA, etc)
        init_bypassDyldLibValidation();
    } else {
        // iOS 26 上 JIT 更严格，默认不启用 dyld 验证 bypass。
        // 但 MobileGlues / libjnidispatch / JNA 等外部 dylib 若未同团队签名会加载失败，
        // 此处仍尝试 bypass 以保证渲染器与依赖加载，失败则忽略（TXM 模式下可由 entitlement 兜底）。
        @try {
            init_bypassDyldLibValidation();
            NSLog(@"[JavaLauncher] iOS 26: dyld library validation bypass attempted for external dylibs");
        } @catch (NSException *exception) {
            NSLog(@"[JavaLauncher] iOS 26: dyld bypass skipped (%@)", exception.reason);
        }
    }


    init_loadDefaultEnv();
    init_loadCustomEnv();
    // 加载 MobileGlues 配置（仅当用户手动选择 MobileGlues 渲染器时生效）
    init_loadMobileGluesConfig();

    // --- [更新] TouchController 通信方式支持 ---
    // 检查是否启用了 TouchController 以及选择的通信方式
    if (getPrefBool(@"control.mod_touch_enable")) {
        NSInteger mode = [getPrefObject(@"control.mod_touch_mode") integerValue];
        if (mode == 1) { // UDP 模式
            setenv("TOUCH_CONTROLLER_PROXY", "12450", 1);
            NSLog(@"[JavaLauncher] Enabled TouchController with UDP mode");
        } else if (mode == 2) { // 静态库模式
            // 设置 Unix Domain Socket 路径
            setenv("TOUCH_CONTROLLER_PROXY_SOCKET", "/tmp/touchcontroller.sock", 1);
            NSLog(@"[JavaLauncher] Enabled TouchController with Static Library mode");
        }
    }
    // ------------------------------------------

    BOOL launchJar = NO;
    NSString *gameDir;
    NSString *defaultJRETag;
    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        // Get preferred Java version from current profile
        // 26.x 官方强制要求 Java 25（Mojang 自 26.x 起将 javaVersion.majorVersion 设为 25），
        // 不再对 preferredJavaVersion 做任何钳制，直接采纳 Profile 指定的 Java 版本。
        // caciocavallo 三路切换会根据实际 Java 版本选择对应 jar（三个独立文件夹）：
        // - Java 8     → libs_caciocavallo（1.10-SNAPSHOT）
        // - Java 17/21 → libs_caciocavallo17（1.18-SNAPSHOT 纯 Java 17 编译）
        // - Java 25    → libs_caciocavallo25（1.18-SNAPSHOT 含 Java 24 class，catsruledogs iOS）
        int preferredJavaVersion = [PLProfiles resolveKeyForCurrentProfile:@"javaVersion"].intValue;
        if (preferredJavaVersion > 0) {
            if (minVersion > preferredJavaVersion) {
                NSLog(@"[JavaLauncher] Profile's preferred Java version (%d) does not meet the minimum version (%d), dropping request", preferredJavaVersion, minVersion);
            } else {
                NSDebugLog(@"[PLProfiles] Applying javaVersion (%d)", preferredJavaVersion);
                minVersion = preferredJavaVersion;
            }
        }
        if (minVersion <= 8) {
            defaultJRETag = @"1_16_5_older";
        } else {
            defaultJRETag = @"1_17_newer";
        }

        // Setup AMETHYST_RENDERER
        NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
        NSLog(@"[JavaLauncher] RENDERER is set to %@\n", renderer);
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);

        // Apply Zink-specific environment variables if Zink renderer is selected
        // Mesa 25.0.7 zink 升级配套：根据设备 GPU 代际自动调优 MESA_GL_VERSION_OVERRIDE、
        // MESA_GLSL_VERSION_OVERRIDE、MESA_EXTENSION_OVERRIDE、mesa_glthread、shader cache 等。
        // ZinkConfig 默认 Auto 级别会保留所有光影所需的 GL 扩展（compute/tessellation/geometry
        // shader 等），仅禁用 MoltenVK 支持不佳的 Transform Feedback，不影响 Iris/OptiFine。
        if ([renderer hasPrefix:@"libOSMesa"]) {
            [ZinkConfig applyZinkEnvironmentFromPreferences];
            NSString *configSummary = [ZinkConfig activeConfigSummary];
            NSLog(@"[ZinkConfig] ========== Zink Renderer Active (Mesa 25) ==========");
            NSLog(@"[ZinkConfig] %@", configSummary);
            setenv("ZINK_ACTIVE_CONFIG", configSummary.UTF8String, 1);

            // 安装 zink vertex stride 4 字节对齐 fix
            // 修复 Mesa 25.0.7 zink + MoltenVK 在启用光影时因 stride 未 4 字节对齐
            // 导致 vkCreateGraphicsPipelines 失败 → SIGSEGV 的崩溃（详见 main_hook.m）
            // 必须在 libOSMesa 被 dlopen 之前调用，确保 fishhook 能拦截后续符号引用
            installZinkStrideFix();
        }

        // Apply LTW-specific environment variables if LTW renderer is selected
        // LTW (Large Thin Wrapper) OpenGL Core 3.3 → ES 3 转译层
        // 不设置 LTW_* 环境变量，使用 LTW main.c constructor 的默认值（与 Android 端一致）
        //   - LIBGL_ES：LTW 自动检测 ES 版本
        //   - LTW_NEVER_FLUSH_BUFFERS：默认 true
        //   - LTW_COHERENT_DYNAMIC_STORAGE：默认 true
        // 仅设置 POJAVEXEC_EGL 标识 EGL 由 LTW 提供（对齐 Android 端语义）
        if ([renderer isEqualToString:@ RENDERER_NAME_LTW]) {
            setenv("POJAVEXEC_EGL", RENDERER_NAME_LTW, 1);
            NSLog(@"[JavaLauncher] LTW renderer active: using LTW defaults (same as Android)");
        }
        // Setup AMETHYST_GRAPHICS_API（MC 26.2+ Graphics API：default/vulkan/opengl）
        // 仅 MC 26.2+ 识别此选项，旧版本 MC 会忽略 options.txt 中的 graphicsApi 字段。
        //
        // 关键修复（更改图形 API 无效）：
        //   之前仅当 graphicsApi 非空时才设置环境变量，导致：
        //   1. 用户从未设置过 graphicsApi 时环境变量缺失，Java 端无法清除旧值
        //   2. 环境变量缺失时 Java 端完全跳过 graphicsApi 处理逻辑
        //   现在始终设置环境变量（缺省为 "default"），让 Java 端每次启动都能正确处理：
        //   - "default"：清除 options.txt 中的 graphicsApi 行
        //   - prefer_vulkan/prefer_opengl：写入对应值
        NSString *graphicsApi = [PLProfiles resolveKeyForCurrentProfile:@"graphicsApi"];
        if (!graphicsApi || graphicsApi.length == 0) {
            graphicsApi = @"default";
        }
        setenv("AMETHYST_GRAPHICS_API", graphicsApi.UTF8String, 1);
        NSLog(@"[JavaLauncher] GRAPHICS_API is set to %@\n", graphicsApi);

        // ============================================================================
        // GLFW/SDL3 窗口后端版本适配
        // ============================================================================
        // MC 26.3-snapshot-4 首次从 GLFW 切换到 SDL3（Mojang 官方公告）：
        //   "In today's snapshot we have switched the library used for window
        //    management, input and platform integration from GLFW to SDL3."
        //
        // 规则：
        //   - 26.3-snapshot-4 及以上 → SDL3（MC 加载 libSDL3.dylib）
        //   - 26.3-snapshot-3 及以下 → GLFW（MC 加载主二进制 pojav* 函数）
        //   - 26.3 pre/rc/release 及 26.4+ → SDL3
        //
        // 启动器无法强制 MC 切换后端（MC 自己决定加载哪个 LWJGL 模块），
        // 但可以检测版本并设置环境变量，供 native 层和 Java 层做相应适配。
        NSString *mcVersionId = [launchTarget isKindOfClass:NSDictionary.class]
            ? launchTarget[@"id"] : [launchTarget lastPathComponent];
        BOOL useSDL3 = amethyst_isSDL3Version(mcVersionId);
        NSString *windowingBackend = useSDL3 ? @"sdl" : @"glfw";
        setenv("AMETHYST_WINDOWING_BACKEND", windowingBackend.UTF8String, 1);
        NSLog(@"[JavaLauncher] WINDOWING_BACKEND is set to %@ (version=%@, useSDL3=%d)",
            windowingBackend, mcVersionId, useSDL3);
        // Setup gameDir
        gameDir = [NSString stringWithFormat:@"%s/instances/%@/%@",
            getenv("POJAV_HOME"), getPrefObject(@"general.game_directory"),
            [PLProfiles resolveKeyForCurrentProfile:@"gameDir"]]
            .stringByStandardizingPath;
    } else {
        defaultJRETag = @"execute_jar";
        gameDir = @(getenv("POJAV_GAME_DIR"));
        launchJar = YES;
        // execute_jar 路径（如 OptiFine 安装器）的 caciocavallo 由三路切换自动处理：
        // 实际选中的 Java 运行时是哪个版本，就用对应目录的 caciocavallo jar。
        // 不再在此处对 minVersion 做任何强制提升或钳制。
    }

    // 26.x 版本官方强制要求 Java 25（Mojang 自 26.x 起将 javaVersion.majorVersion 设为 25）。
    // 不再钳制 Profile 的 javaVersion，26.x 必须使用 Java 25 启动。
    // caciocavallo 三路切换（参照 FCL/ZalithLauncher2 二元思路，扩展为三路以兼容 Java 25）：
    // 三个独立的平级文件夹，按实际 Java 版本选择：
    // - Java 8     → libs_caciocavallo（1.10-SNAPSHOT，包名 net.java.openjdk.cacio，bootclasspath/p）
    // - Java 17/21 → libs_caciocavallo17（1.18-SNAPSHOT 纯 Java 17 编译，包名 com.github.caciocavallosilano.cacio，bootclasspath/a）
    // - Java 25    → libs_caciocavallo25（1.18-SNAPSHOT 含 Java 24 class，包名 com.github.caciocavallosilano.cacio，bootclasspath/a）
    //   来自 catsruledogs/Amethyst-iOS-25。其 CTCGraphicsEnvironment 是 Java 24 class（class version 68），
    //   含 Java 25 兼容修复，纯 Java 17 编译版本会在 get_method_id 阶段 SIGSEGV。
    //   class version 68 仅 Java 24+ 可加载，故 Java 17/21 不能共用，需用 caciocavallo17 目录的纯 Java 17 jar。

    NSLog(@"[JavaLauncher] Looking for Java %d or later", minVersion);
    NSString *javaHome = getSelectedJavaHome(defaultJRETag, minVersion);

    if (javaHome == nil) {
        UIKit_returnToSplitView();
        BOOL isExecuteJar = [defaultJRETag isEqualToString:@"execute_jar"];
        showDialog(localize(@"Error", nil), [NSString stringWithFormat:localize(@"java.error.missing_runtime", nil),
            isExecuteJar ? [launchTarget lastPathComponent] : PLProfiles.current.selectedProfile[@"lastVersionId"], minVersion]);
        return 1;
    } else if ([javaHome hasPrefix:@(getenv("POJAV_HOME"))]) {
        // Copy libawt_xawt.dylib（对齐原版：硬拷贝而非符号链接）
        // 符号链接在某些 iOS 版本上会导致 AWT 加载失败（dyld 解析符号链接时机问题）
        NSString *dest = [NSString stringWithFormat:@"%@/lib/libawt_xawt.dylib", javaHome];
        NSString *source = [NSString stringWithFormat:@"%@/Frameworks/libawt_xawt.dylib", NSBundle.mainBundle.bundlePath];
        NSError *error;
        [fm removeItemAtPath:dest error:nil];
        [fm copyItemAtPath:source toPath:dest error:&error];
        if (error) {
            NSLog(@"[JavaLauncher] Copy libawt_xawt.dylib failed: %@", error.localizedDescription);
        }
    }

    setenv("JAVA_HOME", javaHome.UTF8String, 1);
    NSLog(@"[JavaLauncher] JAVA_HOME has been set to %@", javaHome);

    int allocmem;
    if (getPrefBool(@"java.auto_ram")) {
        CGFloat autoRatio = getEntitlementValue(@"com.apple.private.memorystatus") ? 0.4 : 0.25;
        allocmem = roundf((NSProcessInfo.processInfo.physicalMemory >> 20) * autoRatio);
    } else {
        allocmem = getPrefInt(@"java.allocated_memory");
    }
    NSLog(@"[JavaLauncher] Max RAM allocation is set to %d MB", allocmem);
    if (!validateVirtualMemorySpace(allocmem)) {
        UIKit_returnToSplitView();
        showDialog(localize(@"Error", nil), @"Insufficient contiguous virtual memory space. Lower memory allocation and try again.");
        return 1;
    }

    // Setup options.txt（对齐原版 L229）
    // 在 JVM 启动前写入 options.txt，设置 fullscreen=false、overrideWidth/Height、
    // 默认 mipmapLevels/particles/renderDistance/simulationDistance 等性能选项，
    // 并计算合适的 guiScale。缺少此调用会导致 MC 启动时使用默认 guiScale，
    // 在高分屏上界面元素过小，且 overrideWidth/overrideHeight 不生效。
    [MinecraftOptionUtils setupOptionsAtGameDir:gameDir];

    int margc = -1;
    const char *margv[1000];

    // 关键修复（N3+N4）：margv 边界检查 + 字符串生命周期管理
    //
    // N3（边界检查）：
    //   margv[1000] 是固定大小数组，每次 margv[++margc] = ... 都没有检查 margc 是否越界。
    //   如果未来扩展参数可能造成栈缓冲区溢出。这里通过 PUSH_MARGV_* 宏做防御性边界检查。
    //
    // N4（悬垂指针）：
    //   [NSString stringWithFormat:...].UTF8String 返回的 C 字符串指针依赖 autoreleased NSString
    //   的生命周期。当前 launchJVM 函数没有显式 @autoreleasepool 包裹整个函数体，autoreleased
    //   对象进入当前线程的 autorelease pool，到下一次 runloop drain 时才释放。由于函数末尾立即
    //   调用 pJLI_Launch(margc, margv, ...)，期间没有显式 drain，所以暂时安全。
    //   但这是脆弱的隐式依赖：如果将来有人在中间插入 @autoreleasepool 块或调用 drain，
    //   所有 margv 中由 stringWithFormat: 生成的指针会立即悬垂，导致 JVM 启动崩溃。
    //
    //   修复方案：用 retainedStrings 数组强引用所有通过 stringWithFormat: 创建的 NSString，
    //   确保其生命周期覆盖 pJLI_Launch 调用。retainedStrings 是局部 strong 引用，随函数
    //   退出自动释放，无需手动管理。
    NSMutableArray<NSString *> *retainedStrings = [NSMutableArray array];

    // 宏：安全地添加一个字面量参数到 margv
    // 字符串字面量（如 "-XstartOnFirstThread"）是静态存储期的 const char*，永不失效
    // 边界检查：margc 达到上限时停止添加，避免栈溢出
    #define PUSH_MARGV_LITERAL(literal) do { \
        if (margc + 1 < 1000) { \
            margv[++margc] = (literal); \
        } else { \
            NSLog(@"[JavaLauncher] 警告：margv 已达上限（1000），丢弃字面量参数 %s", (literal)); \
        } \
    } while (0)

    // 宏：通过 stringWithFormat: 构造参数并添加到 margv
    // 创建的 NSString 会被 retainedStrings 强引用，直到函数返回才释放，
    // 保证 margv 中保存的 UTF8String 指针在 pJLI_Launch 调用期间有效。
    // 注意：NSLog 警告消息不直接用 fmt 作为格式串（避免 % 被错误解析），仅打印字面量提示。
    #define PUSH_MARGV_FORMAT(ns_fmt, ...) do { \
        if (margc + 1 < 1000) { \
            NSString *_tmpStr = [NSString stringWithFormat:(ns_fmt), ##__VA_ARGS__]; \
            [retainedStrings addObject:_tmpStr]; \
            margv[++margc] = _tmpStr.UTF8String; \
        } else { \
            NSLog(@"[JavaLauncher] 警告：margv 已达上限（1000），丢弃格式化参数"); \
        } \
    } while (0)

    PUSH_MARGV_FORMAT(@"%@/bin/java", javaHome);
    PUSH_MARGV_LITERAL("-XstartOnFirstThread");
    if (!launchJar) {
        PUSH_MARGV_LITERAL("-Djava.system.class.loader=net.kdt.pojavlaunch.PojavClassLoader");
    }
    PUSH_MARGV_LITERAL("-Xms128M");
    PUSH_MARGV_FORMAT(@"-Xmx%dM", allocmem);
    // library.path: 单一 Frameworks 路径（对齐 Ynnyny 仓库）
    //
    // 关键修复（26.2 启动崩溃）：之前 workspace 将 LWJGL dylib 分裂为 lwjgl33/ 和 lwjgl34/ 子目录，
    // 并通过扫描版本 JSON 的 LWJGL 声明来选择路径。但 Ynnyny 仓库用单一 Frameworks 路径就能正常
    // 启动 26.2，证明分裂路径是多余的，且若 dylib 未按子目录正确摆放会导致加载错误版本 native 库。
    //
    // 现对齐 Ynnyny：所有 native dylib（含 LWJGL 专属和共享库）统一放在 Frameworks/ 根目录，
    // library.path = Frameworks。定制版 root lwjgl.jar（含 iOS 专用 LWJGL 补丁）通过 JavaApp/Makefile
    // 合并进最终 lwjgl.jar，确保 LWJGL 在 iOS 上能正确加载 GL 实现。
    NSString *frameworksPath = [NSString stringWithFormat:@"%@/Frameworks", NSBundle.mainBundle.bundlePath];
    PUSH_MARGV_FORMAT(@"-Djava.library.path=%@", frameworksPath);
    NSLog(@"[JavaLauncher] library.path = %@", frameworksPath);
    PUSH_MARGV_FORMAT(@"-Duser.dir=%@", gameDir);
    PUSH_MARGV_FORMAT(@"-Duser.home=%s", getenv("POJAV_HOME"));
    PUSH_MARGV_FORMAT(@"-Duser.timezone=%@", NSTimeZone.localTimeZone.name);
    PUSH_MARGV_FORMAT(@"-DUIScreen.maximumFramesPerSecond=%d", (int)UIScreen.mainScreen.maximumFramesPerSecond);

    // 发布 GameSurfaceView 指针，供 Metallum Metal 后端使用
    // +[SurfaceViewController surface] 返回静态变量 pojavWindow，该变量在
    // -[SurfaceViewController viewDidLoad] 中被赋值（早于 launchMinecraft 派发到本后台线程）。
    // 通过系统属性传递指针，可避免 JVM 渲染线程通过 ObjC runtime 查找 UIView 的不确定性。
    Class surfaceVCClass = NSClassFromString(@"SurfaceViewController");
    if (surfaceVCClass && [surfaceVCClass respondsToSelector:@selector(surface)]) {
        id surfaceView = [surfaceVCClass performSelector:@selector(surface)];
        if (surfaceView) {
            PUSH_MARGV_FORMAT(@"-Dmetallum.ios.view.pointer=%p", surfaceView);
            PUSH_MARGV_FORMAT(@"-Dmetallum.ios.screen.scale=%g", (double)UIScreen.mainScreen.scale);
            NSLog(@"[JavaLauncher] 已发布 Metallum surface view 指针: %p (scale=%g)", surfaceView, (double)UIScreen.mainScreen.scale);
        } else {
            NSLog(@"[JavaLauncher] 警告：+[SurfaceViewController surface] 返回 nil，Metallum 将回退到 ObjC runtime 查找");
        }
    } else {
        NSLog(@"[JavaLauncher] 警告：SurfaceViewController 类不可用，Metallum 将回退到 ObjC runtime 查找");
    }

    PUSH_MARGV_LITERAL("-Dorg.lwjgl.glfw.checkThread0=false");
    PUSH_MARGV_LITERAL("-Dorg.lwjgl.system.allocator=system");
    //PUSH_MARGV_LITERAL("-Dorg.lwjgl.util.NoChecks=true");
    PUSH_MARGV_LITERAL("-Dlog4j2.formatMsgNoLookups=true");

    // ============================================================================
    // JNA 加载路径
    // ============================================================================
    // JNA 5.13.0 的 darwin-aarch64 libjnidispatch 从 JAR 中提取后能正常加载。
    // Tools.java / MinecraftResourceUtils.m 已强制将 JNA 替换为 5.13.0
    // （MC 26.3+ 要求的 5.17.0 在 iOS 上会导致 native crash）。
    // 保留 boot.library.path 以便未来内置 iOS arm64 版 libjnidispatch。
    PUSH_MARGV_FORMAT(@"-Djna.boot.library.path=%@", frameworksPath);

    // ============================================================================
    // 帧率解锁第四层：JVM 系统属性
    // ============================================================================
    // 某些 MC 版本/mod 可能通过 System.getProperty 读取帧率限制。
    // 设置 -Dmax.fps=260 作为 options.txt 之外的额外兜底层。
    // 不影响不读取此属性的版本。
    if (getPrefBool(@"video.disable_game_vsync")) {
        PUSH_MARGV_LITERAL("-Dmax.fps=260");
        NSLog(@"[JavaLauncher] Added JVM property -Dmax.fps=260 (frame rate unlock layer 4)");
    }

    // ============================================================================
    // ZeroTier 联机 SOCKS5 代理注入
    // ============================================================================
    // 当用户在联机界面连接到 ZeroTier 房间后，MultiplayerManager 会启动一个本地
    // SOCKS5 代理（127.0.0.1:1080），并通过环境变量 AMETHYST_SOCKS5_PROXY 传递
    // 代理地址（格式："127.0.0.1:port"）。
    //
    // 这里检测该环境变量，如果存在，则注入 JVM 的 SOCKS5 代理参数：
    //   -DsocksProxyHost=127.0.0.1
    //   -DsocksProxyPort=<port>
    //
    // Java 的 Socket 网络栈会自动走 SOCKS5 代理，所有 Minecraft 的 TCP 流量
    // （包括登录、世界加载、区块同步、聊天等）都会经过本地 SOCKS5 代理，再由
    // SOCKS5Proxy 通过 libzt 的 BSD socket API 转发到 ZeroTier 虚拟网络中，
    // 最终到达房主的 Minecraft 服务器。
    //
    // 参照 FCL (FoldCraftLauncher) 和 ZL2 (ZalithLauncher) 的实现：
    //   - FCL 在 LaunchPlugin 中注入 socksProxyHost/socksProxyPort 参数
    //   - ZL2 在 ZTLaunchPlugin 中做相同的事情
    //   - 本实现直接在 JVM 参数构建阶段注入，效果一致
    //
    // 注意：
    //   1. 仅当 AMETHYST_SOCKS5_PROXY 环境变量存在且格式正确时才注入
    //   2. 不影响非联机场景下的正常网络访问（环境变量不存在时跳过）
    //   3. 此参数对 Java 的所有 Socket 连接生效，包括第三方库的网络请求
    // ============================================================================
    const char *socks5ProxyEnv = getenv("AMETHYST_SOCKS5_PROXY");
    if (socks5ProxyEnv && socks5ProxyEnv[0] != '\0') {
        NSString *proxyStr = [NSString stringWithUTF8String:socks5ProxyEnv];
        // 解析 "host:port" 格式
        NSRange colonRange = [proxyStr rangeOfString:@":"];
        if (colonRange.location != NSNotFound && colonRange.location > 0 &&
            colonRange.location + 1 < proxyStr.length) {
            NSString *proxyHost = [proxyStr substringToIndex:colonRange.location];
            NSString *proxyPortStr = [proxyStr substringFromIndex:colonRange.location + 1];

            // 校验端口为纯数字且在有效范围
            NSInteger portValue = [proxyPortStr integerValue];
            if (portValue > 0 && portValue <= 65535) {
                PUSH_MARGV_FORMAT(@"-DsocksProxyHost=%@", proxyHost);
                PUSH_MARGV_FORMAT(@"-DsocksProxyPort=%@", proxyPortStr);

                // 关键修复（C4/H13）：注入 -DsocksNonProxyHosts 参数，让 Minecraft 登录、
                // 认证、皮肤、披风、版本库、Mod 下载等官方/第三方服务请求绕过 SOCKS5 代理。
                //
                // 问题描述：
                //   仅注入 socksProxyHost/socksProxyPort 后，Java 的所有 Socket 连接默认都会
                //   走 SOCKS5 代理，包括 Microsoft 登录、Mojang 认证、Yggdrasil 验证、
                //   皮肤/披风资源加载、Mojang 版本库元数据、Modrinth/CurseForge Mod 下载、
                //   GitHub 资源下载、AWS S3 资源下载等。这些服务走 ZeroTier 虚拟网络会被
                //   路由到错误的目标，导致登录失败、皮肤丢失、Mod 无法下载，进而影响联机体验。
                //
                // 修复方案：
                //   通过 socksNonProxyHosts JVM 参数指定不走代理的主机名模式列表，
                //   多个模式用 "|" 分隔，支持 * 通配符（如 *.mojang.com）。
                //
                // 主机名列表说明：
                //   - localhost / 127.* / [::1]：本地回环，绝不应走代理
                //   - *.minecraft.net：Minecraft 官方服务（会话、会话服务器、皮肤服务）
                //   - *.mojang.com：Mojang 服务（认证、皮肤、披风、版本库）
                //   - *.microsoft.com：Microsoft 在线服务（账号、Xbox Live 元数据）
                //   - *.microsoftonline.com：Microsoft 在线认证
                //   - *.xboxlive.com：Xbox Live 认证（Mojang 与 MS 账号互通）
                //   - *.modrinth.com：Modrinth Mod 下载
                //   - *.curseforge.com：CurseForge Mod 下载
                //   - *.githubusercontent.com：GitHub 资源（部分 Mod/资源/raw 文件）
                //   - *.github.com：GitHub API
                //   - *.amazonaws.com：AWS S3（Mojang/MS 资源、皮肤 CDN）
                //   - *.cloudfront.net：CloudFront（部分资源 CDN）
                //   - *.akamaihd.net：Akamai（部分资源 CDN）
                //   - 10.* / 192.168.* / 172.16-31.*：本地局域网，绝不应走代理
                //     注意：10.* 与 ZeroTier 默认子网 10.147.17.x 重叠，但我们用 SOCKS5
                //     而非系统路由，因此本地 10.* 仍走系统路由。Minecraft 房主的
                //     ZeroTier IP 是通过 SOCKS5 转发的，不会受 socksNonProxyHosts 影响。
                //
                // 重要：房主在 ZeroTier 网络中的 IP（如 10.147.17.x）走 SOCKS5 代理时是
                // 直接通过 ZeroTierBridge 的 libzt socket 转发到 ZeroTier 网络的，
                // 不依赖 socksNonProxyHosts 的设置，所以即使 10.* 在不代理列表里，
                // Minecraft 仍能正确连接房主服务器。
                NSString *nonProxyHosts = @"localhost|127.*|[::1]|"
                                          @"*.minecraft.net|*.mojang.com|"
                                          @"*.microsoft.com|*.microsoftonline.com|"
                                          @"*.xboxlive.com|*.modrinth.com|"
                                          @"*.curseforge.com|*.githubusercontent.com|"
                                          @"*.github.com|*.amazonaws.com|"
                                          @"*.cloudfront.net|*.akamaihd.net|"
                                          @"10.*|192.168.*|172.16.*|172.17.*|172.18.*|"
                                          @"172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|"
                                          @"172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|"
                                          @"172.29.*|172.30.*|172.31.*";
                PUSH_MARGV_FORMAT(@"-DsocksNonProxyHosts=%@", nonProxyHosts);

                NSLog(@"[JavaLauncher] 已注入 ZeroTier SOCKS5 代理：%@:%@（同时注入 socksNonProxyHosts 让登录/皮肤/Mod 下载绕过代理）",
                      proxyHost, proxyPortStr);
            } else {
                NSLog(@"[JavaLauncher] AMETHYST_SOCKS5_PROXY 端口无效：%@", proxyPortStr);
            }
        } else {
            NSLog(@"[JavaLauncher] AMETHYST_SOCKS5_PROXY 格式无效（应为 host:port）：%@", proxyStr);
        }
    }

    // Preset OpenGL libname
    const char *glLibName = getenv("AMETHYST_RENDERER");
    if (glLibName) {
        if (!strcmp(glLibName, "auto")) {
            // 关键修复（26.2 启动崩溃）：Auto 渲染器始终选 ANGLE（对齐 Ynnyny 仓库）
            //
            // 之前 workspace 在 Java 21+ 优先选 MobileGlues，但 Ynnyny 仓库用 ANGLE 就能正常启动 26.2。
            // workspace 选 MobileGlues 后又缺少 init_loadMobileGluesConfig() 写 config.json，
            // 导致 MobileGlues 用不安全默认值初始化 GL 上下文可能崩溃。现对齐 Ynnyny 始终选 ANGLE。
            // MobileGlues 仍保留为手动选项（用户可在设置中显式选择）。
            glLibName = RENDERER_NAME_MTL_ANGLE;
            setenv("AMETHYST_RENDERER", glLibName, 1);
            NSLog(@"[JavaLauncher] Auto renderer resolved to %s (always ANGLE)", glLibName);
        }
        if (strcmp(glLibName, RENDERER_NAME_VULKAN) == 0) {
            // 对齐 Ynnyny 仓库：Vulkan 模式下 OpenGL 回退库使用 MobileGlues
            //
            // libMoltenVK 是 Vulkan loader，不是 GL 实现；绑定它为 opengl.libname 会导致
            // LWJGL 查找 GL 符号失败。但 MC 26.2 的 NativeLibrariesBootstrap.loadOpenGL()
            // 在启动时会初始化 org.lwjgl.opengl.GL（无论游戏最终用哪个渲染器）。
            // 若 opengl.libname 未设置，LWJGL 回退到 MacOSXLibraryBundle.getWithIdentifier
            // ("com.apple.opengl")，iOS 上无系统 OpenGL framework 会失败 →
            //   UnsatisfiedLinkError: Failed to retrieve bundle with identifier: com.apple.opengl
            // 指向 libmobileglues.dylib：MobileGlues 专为 GL-on-Metal/Vulkan 设计，
            // 已使用 shipped libspirv-cross.dylib 做着色器翻译。GL.create() 能找到 GL 函数指针；
            // 若 MC 调用 GL 入口（compat 代码、着色器构建等），MobileGlues 能通过 Vulkan 路由，
            // 而非像无上下文的 gl4es 那样崩溃。
            //
            // 注意：vulkan.libname 不在此设置（对齐 Ynnyny），由 PojavLauncher.java 通过
            // System.setProperty("org.lwjgl.vulkan.libname", "MoltenVK") 设置。
            // 若在此用 -D 传 "libMoltenVK.dylib"，LWJGL Library.loadNative 会加 "lib" 前缀和
            // ".dylib" 后缀，得到 "liblibMoltenVK.dylib.dylib"（错误文件名）。
            //
            // MoltenVK 配置（对齐 Ynnyny）：
            // - RESUME_LOST_DEVICE=1：设备丢失后自动恢复
            // - SYNCHRONOUS_QUEUE_SUBMITS=1：同步队列提交（更稳定，避免竞争）
            // - PREFILL_METAL_COMMAND_BUFFERS=1：预填充 Metal 命令缓冲区（减少 GPU 等待，性能优化）
            setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "1", 1);
            setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1);
            setenv("MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS", "1", 1);
        }
        // 对齐 Ynnyny：使用独立变量 openglLibName，不修改 glLibName（保持原值用于后续判断）
        const char *openglLibName = (strcmp(glLibName, RENDERER_NAME_VULKAN) == 0)
            ? RENDERER_NAME_MOBILEGLUES
            : glLibName;

        PUSH_MARGV_FORMAT(@"-Dorg.lwjgl.opengl.libname=%s", openglLibName);

        // 关键修复（参照 FCL，阶段4：26.2 图形 API 切换无效）：
        // 之前仅在 renderer=libMoltenVK.dylib 时由 PojavLauncher.java 通过 System.setProperty 设置
        // org.lwjgl.vulkan.libname，导致用户保留默认 renderer=auto（解析为 ANGLE）并切换
        // graphicsApi=prefer_vulkan 时，LWJGL 找不到 Vulkan 库 → MC 静默回退 OpenGL。
        //
        // FCL 做法：在 JVM 启动前通过 -D 系统属性同时确定 OpenGL 和 Vulkan 两条路径的 native 库，
        // 无论 MC 最终选哪条路都能找到对应的库。
        //
        // 传裸名 "MoltenVK"，LWJGL Library.loadNative 会自动加 "lib" 前缀和 ".dylib" 后缀，
        // 得到 "libMoltenVK.dylib"（正确文件名）。若传 "libMoltenVK.dylib" 会被包装成
        // "liblibMoltenVK.dylib.dylib"（错误文件名）。
        //
        // 安全性：即使 MC 最终走 GL 路径，加载 MoltenVK 也无副作用（GL 路径不调用 Vulkan 入口）。
        PUSH_MARGV_LITERAL("-Dorg.lwjgl.vulkan.libname=MoltenVK");

        // 显式指定 spirv-cross 库名（参照 catsruledogs/Amethyst-iOS-25）：
        // LWJGL spvc 模块默认查找 "spirv-cross" -> 加载 libspirv-cross.dylib（macOS 标准名），
        // 但实际文件名为 libspirv-cross-c-shared.0.dylib（带版本后缀的 SO 名）。
        // 显式设置 -Dorg.lwjgl.spvc.libname=spirv-cross-c-shared.0，LWJGL 的 Library.loadNative
        // 会对 libname 加 "lib" 前缀和 ".dylib" 后缀，得到 "libspirv-cross-c-shared.0.dylib"，
        // 从 library.path（Frameworks）找到该文件。
        PUSH_MARGV_LITERAL("-Dorg.lwjgl.spvc.libname=spirv-cross-c-shared.0");

        // ============================================================================
        // SDL3 GL/EGL 库重定向（关键修复 26.3-snapshot-4+ SDL3 启动失败）
        // ============================================================================
        // 参照 AngelAuraMC/Amethyst-Android feat/lwjgl3ify-sdl-support 分支
        // (commit 2ebbb3442f "fix(SDL): Set SDL env vars for renderer")：
        //
        //   Os.setenv("SDL_OPENGL_LIBRARY", graphicsLib, true);
        //   Os.setenv("SDL_EGL_LIBRARY", NATIVE_LIB_DIR+"/"+Os.getenv("POJAVEXEC_EGL"), true);
        //
        // MC 26.3-snapshot-4+ 使用 SDL3 替代 GLFW。SDL3 的 SDL_GL_CreateContext 会
        // dlopen 默认的 GL/EGL 库（iOS 上不存在），导致 GL 上下文创建失败。
        //
        // 必须在 JVM 启动前设置（早于 MC 调用 SDL_GL_CreateContext）：
        //   - pojavInitOpenGL() 仅在 MC 走 GLFW 路径（glfwCreateWindow→pojavCreateContext）
        //     时被调用。SDL3 模式下 MC 不调用 glfwCreateWindow，pojavInitOpenGL 不会执行，
        //     故 env vars 必须在此处（JVM 启动前）设置。
        //
        // 仅对 GL 类渲染器设置：
        //   - gl4es/ANGLE/MobileGlues: 设置 SDL_OPENGL_LIBRARY + SDL_EGL_LIBRARY
        //   - Vulkan: 不设置（clientAPI=GLFW_NO_API，SDL3 用 SDL_Vulkan_CreateSurface，
        //     不走 GL context 路径）
        //   - OSMesa: 不设置（OSMesa 用自己的 context，不走 EGL）
        //
        // SDL3 通过 dlopen(env_var_value, RTLD_GLOBAL|RTLD_NOW) 加载库。iOS 上 dylib
        // 位于 Frameworks 目录，需用 @rpath/ 前缀（@executable_path/Frameworks 已在
        // 二进制 LC_RPATH 中）。
        //
        // 重要：仅在 SDL3 模式下设置。GLFW 模式下 MC 不走 SDL3 路径，
        // 设置这些环境变量会干扰 LWJGL 的 GLFW 加载（日志会显示矛盾的
        // "WINDOWING_BACKEND=glfw but SDL3 GL/EGL redirect"）。
        // GLFW 路径下的渲染器/EGL 加载由 egl_bridge.m 的 pojavInitOpenGL 负责。
        // 注意：useSDL3 变量定义在外层作用域（line ~537），此处访问不到，
        // 改为读取 AMETHYST_WINDOWING_BACKEND 环境变量（由外层设置）。
        const char *windowingBackendEnv = getenv("AMETHYST_WINDOWING_BACKEND");
        BOOL isSDL3Backend = (windowingBackendEnv != NULL && strcmp(windowingBackendEnv, "sdl") == 0);
        if (isSDL3Backend &&
            strcmp(glLibName, RENDERER_NAME_VULKAN) != 0 &&
            strcmp(glLibName, RENDERER_NAME_VK_ZINK) != 0 &&
            strstr(glLibName, "libOSMesa") == NULL) {
            char sdlGlLib[256];
            snprintf(sdlGlLib, sizeof(sdlGlLib), "@rpath/%s", glLibName);
            char sdlEglLib[256];
            // LTW 模式下，SDL3 的 EGL 必须从 libltw.dylib 加载（LTW 实现了自己的 EGL wrapper：
            // eglCreateContext/eglDestroyContext/eglMakeCurrent，会在内部转发到 ANGLE ES3 context）
            // 其他 GL 渲染器（gl4es/ANGLE/MobileGlues）直接使用 ANGLE 的 EGL
            if (strcmp(glLibName, RENDERER_NAME_LTW) == 0) {
                snprintf(sdlEglLib, sizeof(sdlEglLib), "@rpath/%s", RENDERER_NAME_LTW);
            } else {
                snprintf(sdlEglLib, sizeof(sdlEglLib), "@rpath/%s", RENDERER_NAME_MTL_ANGLE);
            }
            setenv("SDL_OPENGL_LIBRARY", sdlGlLib, 1);
            setenv("SDL_EGL_LIBRARY", sdlEglLib, 1);
            NSLog(@"[JavaLauncher] SDL3 GL/EGL library redirect (early): SDL_OPENGL_LIBRARY=%s, SDL_EGL_LIBRARY=%s",
                  sdlGlLib, sdlEglLib);
            // 预加载渲染器库（RTLD_GLOBAL），让后续 dlopen 找到符号。
            // SDL3 路径不会经过 pojavInitOpenGL，故在此预加载一次确保 SDL3 dlopen 时库已在内存中。
            char preloadPath[256];
            snprintf(preloadPath, sizeof(preloadPath), "@rpath/%s", glLibName);
            dlopen(preloadPath, RTLD_NOW | RTLD_GLOBAL);
            // LTW 模式下还需要预加载 ANGLE（作为 LTW 的 host EGL，LTW constructor 会
            // 通过 dlopen("@rpath/libtinygl4angle.dylib") 查找 eglGetProcAddress）
            if (strcmp(glLibName, RENDERER_NAME_LTW) == 0) {
                char anglePath[256];
                snprintf(anglePath, sizeof(anglePath), "@rpath/%s", RENDERER_NAME_MTL_ANGLE);
                dlopen(anglePath, RTLD_NOW | RTLD_GLOBAL);
            }
        } else if (!isSDL3Backend) {
            NSLog(@"[JavaLauncher] GLFW mode detected, skipping SDL3 GL/EGL library redirect");
        }
    }

      // 添加authlib-injector参数以支持第三方认证账户的皮肤显示
    if ([accountId length] > 0 && [BaseAuthenticator.current isKindOfClass:[ThirdPartyAuthenticator class]]) {
        BaseAuthenticator *currentAuth = BaseAuthenticator.current;
        if (currentAuth.authData[@"authserver"] != nil) {
            NSLog(@"[JavaLauncher] Adding authlib-injector arguments for third party account");
            NSArray *authlibArgs = [(ThirdPartyAuthenticator *)currentAuth getJvmArgsForAuthlib];
            if (authlibArgs.count > 0) {
                for (NSString *arg in authlibArgs) {
                    // arg 来自 authlibArgs 数组，是 strong 引用；但数组本身可能在循环外
                    // 被释放，为防止悬垂，通过 PUSH_MARGV_FORMAT 持久化
                    PUSH_MARGV_FORMAT(@"%@", arg);
                    NSLog(@"[JavaLauncher] Added authlib-injector arg: %s", arg.UTF8String);
                }     
            } else {
                NSLog(@"[JavaLauncher] Warning: No authlib-injector arguments available");
            }
        }
    }
  
    NSString *librariesPath = [NSString stringWithFormat:@"%@/libs", NSBundle.mainBundle.bundlePath];
    PUSH_MARGV_FORMAT(@"-javaagent:%@/patchjna_agent.jar=", librariesPath);
    if(getPrefBool(@"general.cosmetica")) {
        PUSH_MARGV_FORMAT(@"-javaagent:%@/arc_dns_injector.jar=23.95.137.176", librariesPath);
    }
    if(getPrefBool(@"video.fix_simple_voice_chat_mod")) {
        PUSH_MARGV_FORMAT(@"-javaagent:%@/patchsvc.jar=", librariesPath);
    }

    // Workaround random stack guard allocation crashes
    PUSH_MARGV_LITERAL("-XX:+UnlockExperimentalVMOptions");
    PUSH_MARGV_LITERAL("-XX:+DisablePrimordialThreadGuardPages");

    // 关键修复（liblwjgl_stb SIGILL 崩溃，CodeCache 满）：
    //   崩溃日志显示 "CodeCache is full. Compiler has been disabled." 紧接 SIGILL
    //   at liblwjgl_stb.dylib+0x4d26c。复现路径包括：
    //   - 1.16.5 + libOSMesa + zink + MoltenVK（Java 8）
    //   - 1.20.1 + Forge + mobileglues（Java 17）
    //   说明根因与渲染器无关，是 CodeCache 容量不足。
    //
    //   项目从未设置 CodeCache 参数，完全依赖 JVM 默认值：
    //   - Java 8 默认 ReservedCodeCacheSize=48MB
    //   - Java 17+ 默认 240MB（仍可能在大量 native 加载下紧张）
    //
    //   CodeCache 满后 JIT 编译中的方法被部分无效化，CPU 执行到损坏的指令序列
    //   → SIGILL（崩溃点落在 liblwjgl_stb 是因为 stb_truetype 字体光栅化是首个
    //   大量 JIT 的 native wrapper，与渲染器无关）。
    //
    //   修复：统一显式设置为 256m（Java 17+ 默认值），对 Java 8/17/21/25 全部生效。
    //   - InitialCodeCacheSize=32m 避免启动时立即触发 CodeCache 扩容（默认 2.25m
    //     会多次扩容，每次扩容都触发全局锁）
    //   - CodeCacheExpansionSize=4m 减少扩容次数（默认 64K 太小）
    //   - +UnlockExperimentalVMOptions 已在上一行启用，无需重复
    PUSH_MARGV_LITERAL("-XX:ReservedCodeCacheSize=256m");
    PUSH_MARGV_LITERAL("-XX:InitialCodeCacheSize=32m");
    PUSH_MARGV_LITERAL("-XX:CodeCacheExpansionSize=4m");

    // On iOS 26, use mirror mapped JIT by default
    if (@available(iOS 26.0, *)) {
        PUSH_MARGV_LITERAL("-XX:+MirrorMappedCodeCache");
    }

    // Disable Forge 1.16.x early progress window
    PUSH_MARGV_LITERAL("-Dfml.earlyprogresswindow=false");

    // Load java
    NSString *libjlipath8 = [NSString stringWithFormat:@"%@/lib/jli/libjli.dylib", javaHome]; // java 8
    NSString *libjlipath11 = [NSString stringWithFormat:@"%@/lib/libjli.dylib", javaHome]; // java 11+
    BOOL isJava8 = [fm fileExistsAtPath:libjlipath8];

    // 检测 Java 25：通过读取 JRE 目录下的 release 文件确定实际版本
    // 用于条件化 Java 25 不兼容的 JVM 参数（如 sun.security.action 导出、UseCompressedClassPointers）
    // release 文件格式：JAVA_VERSION="25"
    BOOL isJava25 = NO;
    NSString *releasePath = [javaHome stringByAppendingPathComponent:@"release"];
    NSString *releaseContent = [NSString stringWithContentsOfFile:releasePath encoding:NSUTF8StringEncoding error:nil];
    if (releaseContent) {
        NSRange range = [releaseContent rangeOfString:@"JAVA_VERSION=\"25"];
        isJava25 = range.location != NSNotFound;
    }
    NSLog(@"[JavaLauncher] Java version detection: isJava8=%d isJava25=%d javaHome=%@", isJava8, isJava25, javaHome.lastPathComponent);

    // ============================================================================
    // JVM 性能优化（保守参数，不影响启动稳定性）
    // ============================================================================
    // 仅对 Java 17+ 启用 G1GC 调优。Java 8 的 G1GC 不够成熟，保持默认 SerialGC。
    // 不添加 -XX:+AlwaysPreTouch（延长启动时间）、-XX:TieredStopAtLevel=1（降低 JIT 性能）、
    // -XX:CICompilerCount=1（减少编译线程）等可能影响游戏体验的参数。
    // -XX:+UnlockExperimentalVMOptions 已在上方添加，UseStringDeduplication 需要实验模式。
    if (!isJava8) {
        // G1GC：Java 9+ 默认 GC，显式启用确保一致性。
        // 适合大堆内存（MC 通常分配 2-4GB），减少 Full GC 停顿。
        PUSH_MARGV_LITERAL("-XX:+UseG1GC");
        // 目标 GC 停顿 50ms（默认 200ms）。
        // 这是一个软目标，JVM 会尽量满足但不强制，不会导致 OOM。
        // 对 MC 的实时渲染有益，减少 GC 引起的卡顿。
        PUSH_MARGV_LITERAL("-XX:MaxGCPauseMillis=50");
        // 字符串去重：G1GC 特性，自动去重老年代中相同值的 String 对象。
        // MC 有大量重复字符串（方块名、物品名、I18N key 等），可节省 5-10% 堆内存。
        // 仅在 G1GC 下生效，开销极小。
        PUSH_MARGV_LITERAL("-XX:+UseStringDeduplication");
        NSLog(@"[JavaLauncher] JVM GC optimization: G1GC + MaxGCPauseMillis=50 + StringDeduplication (Java 17+)");
    } else {
        NSLog(@"[JavaLauncher] Java 8 detected, skipping G1GC tuning (using default GC)");
    }

    setenv("INTERNAL_JLI_PATH", (isJava8 ? libjlipath8 : libjlipath11).UTF8String, 1);
    void* libjli = dlopen(getenv("INTERNAL_JLI_PATH"), RTLD_GLOBAL);

    if (!libjli) {
        const char *error = dlerror();
        NSLog(@"[Init] JLI lib = NULL: %s", error);
        UIKit_returnToSplitView();
        showDialog(localize(@"Error", nil), @(error));
        return 1;
    }

    // Setup Caciocavallo
    PUSH_MARGV_LITERAL("-Djava.awt.headless=false");
    PUSH_MARGV_LITERAL("-Dcacio.font.fontmanager=sun.awt.X11FontManager");
    PUSH_MARGV_LITERAL("-Dcacio.font.fontscaler=sun.font.FreetypeFontScaler");
    PUSH_MARGV_FORMAT(@"-Dcacio.managed.screensize=%dx%d", width, height);
    PUSH_MARGV_LITERAL("-Dswing.defaultlaf=javax.swing.plaf.metal.MetalLookAndFeel");
    if (isJava8) {
        // Setup Caciocavallo
        PUSH_MARGV_LITERAL("-Dawt.toolkit=net.java.openjdk.cacio.ctc.CTCToolkit");
        PUSH_MARGV_LITERAL("-Djava.awt.graphicsenv=net.java.openjdk.cacio.ctc.CTCGraphicsEnvironment");
    } else {
        // 启用 native access（Java 17+ 支持，Java 25 强制要求）。
        // 参照 catsruledogs/Amethyst-iOS-25：Java 25 对受限方法（@Restricted，含 JNI、
        // sun.misc.Unsafe、Foreign API）的限制更严格，缺失此参数会导致 caciocavallo/LWJGL/JNA
        // 的 native access 触发警告路径，在 bootclasspath/a 未命名模块类上可能引发
        // get_method_id 访问不一致的类元数据导致 SIGSEGV（26.2 启动崩溃的根因）。
        // 日志中 "WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning"
        // 也明确提示需要此参数。Java 17/21 添加此参数无副作用，统一在非 Java 8 分支添加。
        // 关键修复（26.2 启动崩溃）：删除 --enable-native-access=ALL-UNNAMED（对齐 Ynnyny 仓库）
        // Ynnyny 仓库不添加此参数也能正常启动 26.2，证明之前的诊断（Java 25 必需）是错误的。
        // 该参数会改变未命名模块的受限方法警告路径，可能干扰 bootclasspath/a 上 caciocavallo
        // 类的初始化顺序。

        // Required by Cosmetica to inject DNS
        PUSH_MARGV_LITERAL("--add-opens=java.base/java.net=ALL-UNNAMED");

        // Setup Caciocavallo
        PUSH_MARGV_LITERAL("-Dawt.toolkit=com.github.caciocavallosilano.cacio.ctc.CTCToolkit");
        PUSH_MARGV_LITERAL("-Djava.awt.graphicsenv=com.github.caciocavallosilano.cacio.ctc.CTCGraphicsEnvironment");

        // Required by Caciocavallo17 to access internal API
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/java.awt=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/java.awt.peer=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.awt.image=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.java2d=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/java.awt.dnd.peer=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.awt=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.awt.event=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.awt.datatransfer=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-exports=java.desktop/sun.font=ALL-UNNAMED");
        // sun.security.action 导出：仅 Java < 25 添加
        // Java 25 已移除 sun.security.action 包（GetPropertyAction 等类被删除），
        // 在 Java 25 上添加此导出会导致 JVM 警告："module java.base does not export sun.security.action"
        // Java 17/21 的 caciocavallo 可能引用 sun.security.action.GetPropertyAction，需要此导出。
        if (!isJava25) {
            PUSH_MARGV_LITERAL("--add-exports=java.base/sun.security.action=ALL-UNNAMED");
        }
        PUSH_MARGV_LITERAL("--add-opens=java.base/java.util=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-opens=java.desktop/java.awt=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-opens=java.desktop/sun.font=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-opens=java.desktop/sun.java2d=ALL-UNNAMED");
        PUSH_MARGV_LITERAL("--add-opens=java.base/java.lang.reflect=ALL-UNNAMED");
        // 参照 catsruledogs/Amethyst-iOS-25：不添加 sun.awt / sun.awt.image / java.awt.peer 的
        // add-opens。catsruledogs 不加这些 opens 也能正常启动 26.2 + Java 25。
        // workspace 之前多加这 3 条 opens 会导致 Java 25 上 GE 提前初始化，
        // 在 caciocavallo25 的 CTCGraphicsEnvironment 注册完成前触发 get_method_id → SIGSEGV。
        // 纯 Java 17 编译版 caciocavallo17（Java 17/21 用）不依赖这些 opens，
        // 其 CTCGraphicsEnvironment 通过 --add-exports（上方已添加）即可访问所需内部 API。

        // cpw.mods.bootstraplauncher 模块导出：所有 Java 版本均添加（参照 catsruledogs/Amethyst-iOS-25）。
        // 之前仅对 Java 17/21 添加、Java 25 跳过，导致 26.2 + Java 25 启动时类加载混乱，
        // 最终在 get_method_id 阶段 SIGSEGV。catsruledogs 对所有版本统一添加此导出且能正常启动 26.2。
        // TODO: workaround, will be removed once the startup part works without PLaunchApp
        PUSH_MARGV_LITERAL("--add-exports=cpw.mods.bootstraplauncher/cpw.mods.bootstraplauncher=ALL-UNNAMED");
    }

    // Add Caciocavallo bootclasspath
    // 关键修复（26.2 启动崩溃）：caciocavallo 二元切换（对齐 Ynnyny 仓库）
    //
    // 之前 workspace 误判"纯 Java 17 编译版会在 Java 25 上 get_method_id SIGSEGV"，
    // 引入了 caciocavallo25（catsruledogs Java 24 class jar）三路切换。
    // 但 Ynnyny 仓库用纯 Java 17 编译版 caciocavallo17 启动 26.2 完全正常，
    // 证明该诊断是错误的。catsruledogs jar 的 Java 24 class 反而可能是真正的崩溃源。
    //
    // 现对齐 Ynnyny：二元切换
    //   - Java 8     → libs_caciocavallo（1.10-SNAPSHOT，bootclasspath/p）
    //   - Java 17/21/25 → libs_caciocavallo17（1.18-SNAPSHOT 纯 Java 17 编译，bootclasspath/a）
    const char *cacio_bootclasspath_mode;
    NSString *cacio_libs_path;
    if (isJava8) {
        // Java 8: 1.10-SNAPSHOT，bootclasspath/p（前置，覆盖 java.awt 实现）
        cacio_bootclasspath_mode = "p";
        cacio_libs_path = [NSString stringWithFormat:@"%@/libs_caciocavallo", NSBundle.mainBundle.bundlePath];
    } else {
        // Java 17/21/25: 1.18-SNAPSHOT 纯 Java 17 编译（class version 61），bootclasspath/a
        cacio_bootclasspath_mode = "a";
        cacio_libs_path = [NSString stringWithFormat:@"%@/libs_caciocavallo17", NSBundle.mainBundle.bundlePath];
    }
    NSLog(@"[JavaLauncher] Caciocavallo: isJava8=%d libs=%@ mode=/%s",
          isJava8, cacio_libs_path.lastPathComponent, cacio_bootclasspath_mode);

    NSString *cacio_classpath = [NSString stringWithFormat:@"-Xbootclasspath/%s", cacio_bootclasspath_mode];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacio_libs_path error:nil];
    for(NSString *file in files) {
        // 所有 cacio jar 均放入 -Xbootclasspath/a（或 /p for Java 8）。
        // 参照 catsruledogs/Amethyst-iOS-25：不使用 --patch-module，不使用 stub-surface-manager.jar。
        // 之前用 --patch-module 或 stub jar 注入 sun.java2d.SurfaceManagerFactory，
        // 会破坏 java.desktop 模块封装，导致 get_method_id SIGSEGV。
        if ([file hasSuffix:@".jar"]) {
            cacio_classpath = [NSString stringWithFormat:@"%@:%@/%@", cacio_classpath, cacio_libs_path, file];
        }
    }
    PUSH_MARGV_FORMAT(@"%@", cacio_classpath);

    // stub-surface-manager.jar 已删除（见上方注释）。不再使用 --patch-module。
    // CTCPreloadClassLoader.<clinit> 抛出的 ClassNotFoundException 被吞掉，不影响启动。

    if (!getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing") && !isJava25) {
        // In jailed environment, where extended virtual addressing entitlement isn't
        // present (for free dev account), allocating compressed space fails.
        // FIXME: does extended VA allow allocating compressed class space?
        // Java 25 已弃用 UseCompressedClassPointers 参数（JEP 471），
        // 在 Java 25 上添加会导致 "Ignoring option UseCompressedClassPointers" 警告。
        // Java 25 默认使用 64-bit pointer，不再需要此参数。
        PUSH_MARGV_LITERAL("-XX:-UseCompressedClassPointers");
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        for (NSString *arg in launchTarget[@"arguments"][@"jvm_processed"]) {
            // arg 来自 launchTarget[@"arguments"][@"jvm_processed"] 数组，是 strong 引用；
            // 但 launchTarget 可能在循环结束后被释放，为防止悬垂，通过 PUSH_MARGV_FORMAT 持久化
            PUSH_MARGV_FORMAT(@"%@", arg);
        }
    }

    init_loadCustomJvmFlags(&margc, (const char **)margv);
    NSLog(@"[Init] Found JLI lib");

    // 关键修复（26.2 启动崩溃）：单一 lwjgl.jar（对齐 Ynnyny 仓库）
    // 之前 workspace 分裂为 lwjgl.jar 和 lwjgl33.jar，现对齐 Ynnyny 用单一合并 jar。
    // 定制版 root lwjgl.jar（含 iOS 专用 LWJGL 补丁）已通过 JavaApp/Makefile 合并进 lwjgl.jar。
    NSString *lwjglJar = [NSString stringWithFormat:@"%@/lwjgl.jar", librariesPath];
    NSLog(@"[JavaLauncher] Using LWJGL jar at %@", lwjglJar);

    // 校验目标 LWJGL jar 是否存在，避免静默崩溃
    if (![fm fileExistsAtPath:lwjglJar]) {
        UIKit_returnToSplitView();
        showDialog(localize(@"Error", nil), [NSString stringWithFormat:@"LWJGL jar missing: %@", [lwjglJar lastPathComponent]]);
        return 1;
    }

    NSMutableString *classpathBuilder = [NSMutableString string];
    NSArray *libFiles = [fm contentsOfDirectoryAtPath:librariesPath error:nil];
    for (NSString *libFile in libFiles) {
        // 精确排除合并后的 LWJGL jar，避免重复；保留其他以 lwjgl 开头的依赖 jar
        if ([libFile hasSuffix:@".jar"] &&
            ![libFile isEqualToString:@"lwjgl.jar"]) {
            [classpathBuilder appendFormat:@"%@/%@:", librariesPath, libFile];
        }
    }
    [classpathBuilder appendString:lwjglJar];
    NSString *classpath = classpathBuilder;
    if (launchJar) {
        // JAR 放在 classpath 最前面，避免 bundle libs 中的同名类（gson/guava/kotlin-stdlib 等）
        // 优先加载，导致 installer 自带依赖被遮蔽引发 NoSuchMethodError/LinkageError
        // 标准 `java -jar` 语义下 JAR 本应是唯一 classpath，此处保留 bundle libs 仅因 PojavLauncher
        // 与 UIKit bridge 类需要加载，但 installer 自身依赖应优先
        classpath = [NSString stringWithFormat:@"%@:%@", launchTarget, classpath];
    }
    PUSH_MARGV_LITERAL("-cp");
    PUSH_MARGV_FORMAT(@"%@", classpath);
    PUSH_MARGV_LITERAL("net.kdt.pojavlaunch.PojavLauncher");

    if (launchJar) {
        PUSH_MARGV_LITERAL("-jar");
    } else {
        PUSH_MARGV_FORMAT(@"%@", accountId);
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        PUSH_MARGV_FORMAT(@"%@", launchTarget[@"id"]);
        // 传递服务器地址给 PojavLauncher（FCL 风格）：
        // 留空传 @"", Java 端据此判断不追加任何参数；非空则由 Java 端按 MC 版本
        // 解析为 --server/--port 或 --quickPlayMultiplayer
        NSString *serverIp = [PLProfiles.current serverIpForCurrentProfile] ?: @"";
        PUSH_MARGV_FORMAT(@"%@", serverIp);
    } else {
        PUSH_MARGV_FORMAT(@"%@", launchTarget);
    }
    //PUSH_MARGV_LITERAL("ghidra.GhidraRun");

    pJLI_Launch = (JLI_Launch_func *)dlsym(libjli, "JLI_Launch");

    if (NULL == pJLI_Launch) {
        NSLog(@"[Init] JLI_Launch = NULL");
        return -2;
    }

    NSLog(@"[Init] Calling JLI_Launch");

    // Cr4shed known issue: exit after crash dump,
    // reset signal handler so that JVM can catch them
    signal(SIGSEGV, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGFPE, SIG_DFL);

    // Free split VC
    tmpRootVC = nil;

    return pJLI_Launch(++margc, margv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   // These values are ignored in Java 17, so keep it anyways
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
}
