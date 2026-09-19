#import "config.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "UIKit+hook.h"
#import <CoreFoundation/CoreFoundation.h>

static PLPreferences* pref;

void loadPreferences(BOOL reset) {
    assert(getenv("POJAV_HOME"));
    if (reset) {
        [pref reset];
    } else {
        pref = [[PLPreferences alloc] initWithAutomaticMigrator];
    }
}

void toggleIsolatedPref(BOOL forceEnable) {
    // 总是基于当前 POJAV_GAME_DIR 重新计算 instancePath。
    // POJAV_GAME_DIR 是符号链接（指向 $POJAV_HOME/instances/<current>），
    // 切换游戏目录时 changeSelectionTo 已更新该符号链接的目标。
    // 之前用 `if (!pref.instancePath)` 缓存了第一次设置的旧路径，
    // 导致切换目录后仍读取旧实例的 launcher_preferences.plist，
    // 用户必须重启启动器才能让 instancePath 重新计算。这里改为每次都刷新。
    pref.instancePath = [NSString stringWithFormat:@"%s/launcher_preferences.plist", getenv("POJAV_GAME_DIR")];
    [pref toggleIsolationForced:forceEnable];
}

#pragma mark Download source migration

/// 一次性迁移：旧键 general.download_source → 新版 4 个分类镜像策略键
///
/// 迁移规则：
///   official            → 4 键全部 official_first（官方优先）
///   bmclapi / mcim      → 4 键全部 mirror_first（镜像优先）
///     （bmclapi 与 mcim 都是"走国内镜像"的用户意愿：bmclapi 覆盖文件/加载器、
///       mcim 覆盖资源搜索/下载，新模型中 PLMirrorCenter 已按资源类型把
///       mirror_first 映射到对应镜像体系，故统一保留"走镜像"意愿）
///
/// 执行条件：旧键存在 且 未迁移过（哨兵键 download.sourceMigrated）。
/// 说明：4 个新键在 PLPreferences defaults 中注册了默认值 official_first，
/// 加载后无法通过"键是否为 nil"区分默认值与用户设置，故用哨兵键保证一次性；
/// 哨兵也避免了"用户手动把新键改回 official_first 后，下次启动被旧键再次覆盖"。
///
/// 迁移完成后保留旧键不删（向后兼容：尚未切换到 PLMirrorCenter 的旧读取方仍可使用）。
void migrateDownloadSourcePreferences(void) {
    if ([getPrefObject(@"download.sourceMigrated") boolValue]) return;

    NSString *legacy = getPrefObject(@"general.download_source");
    if (![legacy isKindOfClass:[NSString class]] || legacy.length == 0) return;

    // bmclapi / mcim 均视为镜像意图，其余值（official / 未知）按官方优先处理
    BOOL mirrorFirst = [legacy isEqualToString:@"bmclapi"] || [legacy isEqualToString:@"mcim"];
    NSString *value = mirrorFirst ? @"mirror_first" : @"official_first";

    NSArray<NSString *> *newKeys = @[
        @"download.fileSource",
        @"download.assetSearchSource",
        @"download.assetDownloadSource",
        @"download.modLoaderSource"
    ];
    for (NSString *key in newKeys) {
        setPrefObject(key, value);
    }
    setPrefObject(@"download.sourceMigrated", @YES);
    NSLog(@"[Preferences] Migrated general.download_source(%@) -> %@ for 4 mirror policy keys", legacy, value);
}

#pragma mark Task 77 default control migration

/// 一次性迁移：默认触控布局出厂值 default.json -> custom.json（用户需求
/// "默认控件选择 custom"）。
///
/// 背景：PLPreferences 的 defaults 只在键缺失时回填，而 preferences plist
/// 在任意一次保存时会整字典落盘——老安装的 control.default_ctrl 早已以
/// "default.json" 物化到磁盘，仅改 defaults 无法让存量设备拿到新出厂值。
///
/// 迁移规则（哨兵键 control.default_ctrl_migrated_custom 保证一次性）：
///   当前有效值 == "default.json"（旧出厂值，无论物化还是显式选择）
///     -> 改写为 "custom.json"（新出厂值；唯一受影响的"显式选择"组合是
///        刻意选回 default.json 的用户，可在选择器一键改回，符合"改默认"
///        的语义）
///   当前有效值 == "custom.json"（全新安装 defaults 或已自选）-> 无事可做
///   当前有效值为其他布局（用户自建布局名）-> 不动，尊重用户选择
///
/// 判定用 getPrefObject 读"合并 defaults 后的有效值"：本函数在 AppDelegate
/// 启动早期调用，defaults 已就位；新 defaults 出厂值已是 custom.json，故
/// 读到 default.json 必然来自磁盘存储的旧值。
void migrateDefaultControlPref(void) {
    if ([getPrefObject(@"control.default_ctrl_migrated_custom") boolValue]) return;

    NSString *current = getPrefObject(@"control.default_ctrl");
    if ([current isEqualToString:@"default.json"]) {
        setPrefObject(@"control.default_ctrl", @"custom.json");
        NSLog(@"[Preferences] Task77 migrated default control layout: default.json -> custom.json");
    }
    setPrefObject(@"control.default_ctrl_migrated_custom", @YES);
}

id getPrefObject(NSString *key) {
    return [pref getObject:key];
}
BOOL getPrefBool(NSString *key) {
    return [getPrefObject(key) boolValue];
}
float getPrefFloat(NSString *key) {
    return [getPrefObject(key) floatValue];
}
NSInteger getPrefInt(NSString *key) {
    return [getPrefObject(key) intValue];
}

void setPrefObject(NSString *key, id value) {
    [pref setObject:key value:value];
}
void setPrefBool(NSString *key, BOOL value) {
    setPrefObject(key, @(value));
}
void setPrefFloat(NSString *key, float value) {
    setPrefObject(key, @(value));
}
void setPrefInt(NSString *key, NSInteger value) {
    setPrefObject(key, @(value));
}
void setPrefString(NSString *key, NSString *value) {  // 新增
    setPrefObject(key, value);
}

void resetWarnings() {
    for (int i = 0; i < pref.globalPref[@"warnings"].count; i++) {
        NSString *key = pref.globalPref[@"warnings"].allKeys[i];
        pref.globalPref[@"warnings"][key] = @YES;
    }
}

#pragma mark Accent Color

/// 将 hex 字符串（如 "429CF5" 或 "#429CF5"）解析为 UIColor，失败返回 nil
static UIColor *colorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) return nil;
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

UIColor *accentColor(void) {
    // 优先读取用户自定义主题强调色，未设置则回退到默认蓝 #429CF5
    NSString *hex = getPrefObject(@"general.accent_color");
    UIColor *custom = colorFromHex(hex);
    if (custom) return custom;
    // 默认蓝 RGB(0.26, 0.63, 0.96) = #429CF5
    return [UIColor colorWithRed:0.26 green:0.63 blue:0.96 alpha:1.0];
}

#pragma mark Safe area

CGRect getSafeArea(CGRect screenBounds) {
    UIEdgeInsets safeArea = UIEdgeInsetsFromString(getPrefObject(@"control.control_safe_area"));
    if (screenBounds.size.width < screenBounds.size.height) {
        safeArea = UIEdgeInsetsMake(safeArea.right, safeArea.top, safeArea.left, safeArea.bottom);
    }
    return UIEdgeInsetsInsetRect(screenBounds, safeArea);
}

void setSafeArea(CGSize screenSize, CGRect frame) {
    UIEdgeInsets safeArea;
    // TODO: make safe area consistent across opposite orientations?
    if (screenSize.width < screenSize.height) {
        safeArea = UIEdgeInsetsMake(
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame),
            frame.origin.y);
    } else {
        safeArea = UIEdgeInsetsMake(
            frame.origin.y,
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame));
    }
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(safeArea));
}

UIEdgeInsets getDefaultSafeArea() {
    UIEdgeInsets safeArea = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    if (screenSize.width < screenSize.height) {
        safeArea.left = safeArea.top;
        safeArea.right = safeArea.bottom;
    }
    safeArea.top = safeArea.bottom = 0;
    return safeArea;
}

#pragma mark Java runtime

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion) {
    NSDictionary *pref = getPrefObject(@"java.java_homes");
    NSDictionary<NSString *, NSString *> *selected = pref[@"0"];
    NSString *selectedVer = selected[defaultJRETag];
    if (minVersion > selectedVer.intValue) {
        NSArray *sortedVersions = [pref.allKeys valueForKeyPath:@"self.integerValue"];
        sortedVersions = [sortedVersions sortedArrayUsingSelector:@selector(compare:)];
        BOOL found = NO;
        for (NSNumber *version in sortedVersions) {
            if (version.intValue >= minVersion) {
                selectedVer = version.stringValue;
                found = YES;
                break;
            }
        }
        // 修复：原代码在找不到满足 minVersion 的 runtime 时 selectedVer 仍为初始值（如 "17"），
        // 导致 if (!selectedVer) 永远为假，静默降级到 Java 17 启动 26.x 等新版本时必然崩溃。
        if (!found) {
            NSLog(@"Error: requested Java >= %d was not installed! (available: %@)", minVersion, sortedVersions);
            return nil;
        }
    }

    id selectedDir = pref[selectedVer];
    if ([selectedDir isEqualToString:@"internal"]) {
        selectedDir = [NSString stringWithFormat:@"%@/java_runtimes/java-%@-openjdk", NSBundle.mainBundle.bundlePath, selectedVer];
    } else {
        selectedDir = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("POJAV_HOME"), selectedDir];
    }

    if ([NSFileManager.defaultManager fileExistsAtPath:selectedDir]) {
        return selectedDir;
    } else {
        NSLog(@"Error: selected runtime for %@ does not exist: %@", defaultJRETag, selectedDir);
        return nil;
    }
}

#pragma mark Renderer

// 可选渲染器是否真的可用：对应的 dylib 必须已经打进 app 的 Frameworks 目录。
//
// 为什么需要这个判断：Mithril 的 libmithril.dylib 是预编译产物（需另外下载），
// MobileGL 的 libMobileGL.dylib 默认不构建（源码体积大、编译慢，属可选依赖）。
// 若把不存在的渲染器列进选择器，用户选中后 dlopen 失败，gl_bridge.m 的
// dlsym_EGL() 直接返回 false，启动器弹不出有意义的错误，排查成本很高。
// 因此按实际存在与否过滤：缺哪个 dylib 就不显示哪个选项。
static BOOL rendererLibraryExists(NSString *fileName) {
    if (fileName.length == 0) return NO;
    NSString *path = [NSBundle.mainBundle.bundlePath
        stringByAppendingPathComponent:[@"Frameworks" stringByAppendingPathComponent:fileName]];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

// 候选渲染器表：key / 显示名 / 对应的 dylib 文件（为空表示始终可用）。
// keys 与 names 由同一份表生成，避免两处手改导致下标错位。
static NSArray<NSDictionary *> *rendererCandidates(void) {
    return @[
        @{@"key": @"auto",
          @"name": localize(@"preference.title.renderer.debug.auto", nil),
          @"file": @""},
        @{@"key": @ RENDERER_NAME_GL4ES,
          @"name": localize(@"preference.title.renderer.debug.gl4es", nil),
          @"file": @ RENDERER_NAME_GL4ES},
        @{@"key": @ RENDERER_NAME_MTL_ANGLE,
          @"name": localize(@"preference.title.renderer.debug.angle", nil),
          @"file": @ RENDERER_NAME_MTL_ANGLE},
        @{@"key": @ RENDERER_NAME_MOBILEGLUES,
          @"name": localize(@"preference.title.renderer.debug.mg", nil),
          @"file": @ RENDERER_NAME_MOBILEGLUES},
        @{@"key": @ RENDERER_NAME_VK_ZINK,
          @"name": localize(@"preference.title.renderer.debug.zink", nil),
          @"file": @ RENDERER_NAME_VK_ZINK},
        @{@"key": @ RENDERER_NAME_LTW,
          @"name": localize(@"preference.title.renderer.debug.ltw", nil),
          @"file": @ RENDERER_NAME_LTW},
        @{@"key": @ RENDERER_NAME_VULKAN,
          @"name": localize(@"preference.title.renderer.debug.vulkan", nil),
          @"file": @ RENDERER_NAME_VULKAN}
    ];
}

// Task 113 -> Task 120（重构）：MobileGL 渲染器不进主渲染器列表（用户要求：
// 列表太占空间）。上游的三个 MobileGL 家族列表条目（MobileGL / MobileGL-gles /
// Mithril）合并为设置页"视频"分区里的单一选项 mobilegl_backend（与"ANGLE ES
// 驱动"并排），默认 Vulkan；GLES 与 MobileGL 共用同一个 libMobileGL.dylib
// （运行时由 MOBILEGL_BACKEND_TYPE 选择后端），Mithril 需 libmithril.dylib
// 随包存在（当前未附带，选项存在但启动时守卫回落 auto 并留日志）。
// 旧的 mobilegl_vulkan 布尔开关（Task113）已退役：它无条件覆盖任何显式渲染器
// 选择，1d4ff3a9 会话用户选 zink 被静默换成 MobileGL Vulkan（"用了 zink 却回
// 退 vk"）——Task120 起【显式渲染器选择永远优先】，后端选项仅在 auto 时生效。

// Task 120：有效渲染器解析（单一事实源，见 LauncherPreferences.h 头注释）。
// 注意与 JavaLauncher.m 的 AMETHYST_RENDERER 解析点保持逐字一致——两处任何
// 分叉都会复刻 Task124 的事故形态（layerClass 按旧渲染器建了普通 CALayer，
// 实际渲染器却是 MobileGL DirectVulkan，其内部 MoltenVK 在 swapchain 创建时
// 向普通 CALayer 发送 naturalDrawableSizeMVK -> unrecognized selector 崩溃）。
NSString *ame_effective_renderer(void) {
    NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
    if (![renderer isKindOfClass:NSString.class] || renderer.length == 0) {
        renderer = @"auto";
    }
    // (1) 显式渲染器选择优先：zink/ANGLE/MobileGlues/LTW/MoltenVK/Mithril
    //     等任何非 auto 选择都原样生效，MobileGL 后端选项不干预。
    if (![renderer isEqualToString:@"auto"]) {
        return renderer;
    }
    // (2) auto + MobileGL 后端选项：按档位覆盖（dylib 缺失时守卫回落）。
    NSInteger backend = getPrefInt(@"mobileglues.mobilegl_backend");
    if (backend == 1 || backend == 2) {
        if (rendererLibraryExists(@ RENDERER_NAME_MOBILEGL)) {
            return @ RENDERER_NAME_MOBILEGL;
        }
    } else if (backend == 3) {
        if (rendererLibraryExists(@ RENDERER_NAME_MITHRIL)) {
            return @ RENDERER_NAME_MITHRIL;
        }
    }
    // (3) 关闭 / dylib 缺失：维持 auto（egl_bridge 按版本解析 gl4es/ANGLE）。
    return renderer;
}

// 当前选中的渲染器（可能已不在候选表里，见下方说明）
static NSString *currentRendererKey(void) {
    NSString *value = getPrefObject(@"video.renderer");
    return [value isKindOfClass:NSString.class] ? value : nil;
}

// 过滤规则：
//   1. dylib 不存在的候选不显示（Task120 起 MobileGL 家族全部移出本表，此规则
//      仅剩通用防御意义：防换构建/删 dylib 后列表出现死条目）
//   2. 但当前已选中的值永远保留 —— 否则用户选了某个渲染器、之后该 dylib 被移除
//      （例如换了个不含 MobileGL 的构建），设置页会失去这一项，pick 控件拿不到
//      对应下标，显示为空白或错选中第一项，用户无从察觉当前到底是什么渲染器。
static NSArray<NSDictionary *> *availableRendererCandidates(void) {
    NSString *current = currentRendererKey();
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *entry in rendererCandidates()) {
        NSString *file = entry[@"file"];
        NSString *key = entry[@"key"];
        if (file.length > 0 && !rendererLibraryExists(file) && ![key isEqualToString:current]) {
            continue;
        }
        [result addObject:entry];
    }
    return result;
}

NSArray* getRendererKeys(BOOL containsDefault) {
    NSMutableArray *array = [NSMutableArray array];
    for (NSDictionary *entry in availableRendererCandidates()) {
        [array addObject:entry[@"key"]];
    }
    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    return array;
}

NSArray* getRendererNames(BOOL containsDefault) {
    NSMutableArray *array = [NSMutableArray array];
    for (NSDictionary *entry in availableRendererCandidates()) {
        [array addObject:entry[@"name"]];
    }
    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    return array;
}
