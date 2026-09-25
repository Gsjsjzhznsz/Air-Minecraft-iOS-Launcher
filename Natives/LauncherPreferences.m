#import "config.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "PLProfiles.h"   // Task120: ame_effective_renderer 需要（CI 35458985232 教训：此前从别处传递可见）
#import "PLMirrorCenter.h"  // Task138: loadPreferences 末尾的测速预热
#import "NMToast.h"    // Task138: 渲染器 dylib 缺失回退的用户提示
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
    // Task138：偏好就绪后预热测速引擎——任意镜像策略为 speed_first 且
    // 缓存缺失/过期时异步发起官方 vs 镜像竞速（幂等，无网络阻塞）。
    // 首次下载前结果大概率已落地，"加载速度快优先"从第一个请求起生效。
    [PLMirrorCenter startSpeedProbesIfNeeded];
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

// Task 130：MobileGlues 性能默认值治愈迁移（见 LauncherPreferences.h 的根因注释）。
// 装机证据（7a680d1 会话，2026-09-20 12:10 上传）：日志显示
//   mobileglues.enable_ext_direct_state_access = 0
//   mobileglues.max_glsl_cache_size = 64
// 前者 = v5.1.0 持久化旧默认（新默认 1 被压制，DSA 是 MC/sodium/
// ImmediatelyFast 低开销路径的探测点）；后者 = 用户滑条自选（旧默认是
// 32，64 从未当过默认——保留不动，缓存大小非性能主因）。仅匹配旧默认
// 值才迁移，哨兵保证一次性；用户此后仍可自由改回。
//
// Task 166（修订）：DSA 分支整段停用——后续三会话 A/B 实锤 DSA=1 是
// MG GLES/4.0 黑屏的唯一配置差异（9e6fc27 两档 DSA=0 全程可玩；Task158
// 后 DSA=1 黑屏，render-texture 探针全零 + 首秒 10 次一次性 No-context）。
// MobileGlues 2.0.17 的 DSAWrapper 模拟层在 FSR1 fb0 重定向下自洽性
// 不足；Task129d 的性能依据来自 zink（Mesa 原生 DSA）。取而代之：
// Task166 反向迁移（持久化 1 → 0，仅一次，新哨兵），之后用户仍可自由
// 开回。GLSL 缓存 32→128 分支保留（良性，与黑屏无关）。
void ame130_migrateMgPerfDefaults(void) {
    if ([getPrefObject(@"mobileglues.task130_perf_defaults_migrated") boolValue]) {
        // Task130 哨兵已置位的老设备：Task130 当年可能已把 DSA 翻成 1——
        // 走 Task166 反向迁移补课。
        ame166_migrateMgDsaBlackScreen();
        return;
    }

    // Task166：DSA 0→1 迁移停用（原分支在此，见上方修订注释）。
    id cache = getPrefObject(@"mobileglues.max_glsl_cache_size");
    if ([cache isKindOfClass:NSNumber.class] && [(NSNumber *)cache intValue] == 32) {
        setPrefObject(@"mobileglues.max_glsl_cache_size", @(128));
        NSLog(@"[Preferences] Task130 migrated MG GLSL cache default: 32 -> 128");
    }
    setPrefObject(@"mobileglues.task130_perf_defaults_migrated", @YES);
    NSLog(@"[Preferences] Task130 MG perf defaults migration checked (dsa branch retired by Task166; cache=%@)",
          cache);
    ame166_migrateMgDsaBlackScreen();
}

// Task 166：MobileGlues DSA 黑屏反向迁移——把 Task129d/130 时代持久化的
// enable_ext_direct_state_access=1 一次性归 0（新默认 @NO 只对未设键生效，
// 存量 1 会经 getPrefObject 覆盖链继续压制新默认，必须显式翻转）。
// 仅匹配 1；用户此后手动开回的 1 不再被动（哨兵只跑一次）。
void ame166_migrateMgDsaBlackScreen(void) {
    if ([getPrefObject(@"mobileglues.task166_dsa_blackscreen_migrated") boolValue]) return;
    id dsa = getPrefObject(@"mobileglues.enable_ext_direct_state_access");
    if ([dsa isKindOfClass:NSNumber.class] && [(NSNumber *)dsa boolValue] == YES) {
        setPrefObject(@"mobileglues.enable_ext_direct_state_access", @NO);
        NSLog(@"[Preferences] Task166 migrated MG DSA default: 1 -> 0 (DSAWrapper under FSR1 redirect = MG GLES/4.0 black screen; see Task166 forensics)");
    }
    setPrefObject(@"mobileglues.task166_dsa_blackscreen_migrated", @YES);
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
        // Task 142：MobileGL 家族的唯一渲染器层入口 "mg"（用户明令"渲染器
        // 选择只有一个 mg，不写什么后端"）。file 留空 = 永远列出：默认
        // 后端 libMobileGL.dylib 随包，家族变体的 dylib 缺失守卫在
        // ame_effective_renderer 的 mg 分支处理（缺失回落默认后端）。
        @{@"key": @ RENDERER_KEY_MG,
          @"name": localize(@"preference.title.renderer.debug.mgfamily", nil),
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
          @"file": @ RENDERER_NAME_VULKAN},
        // Task 132（MG 三端合并，用户明令）：MobileGL 家族三后端条目从本表
        // 退役，合并为 MobileGlues 分区的单一 pick 行（typePickField 悬浮
        // 浮窗，选项 MobileGlues (Vulkan 直连) / (GLES 后端) / (OpenGL 4.0
        // 实验性)，默认 Vulkan 直连）——见 getRendererFamilyKeys/Names 与
        // LauncherPreferencesViewController 的 renderer_backend 行。
        // 严禁再拆回三条独立条目或改成二级菜单页面（用户四次否决）。
        // 渲染器悬浮菜单/版本管理器/Profile 编辑器自此共享七项列表
        // （auto/gl4es/angle/mg/zink/ltw/vulkan），与
        // VersionManagerViewController 硬编码的七个短名重新对齐（Task131
        // 在本表加三后端时该表 10 vs 7 的潜在错位随之消失）。
    ];
}

// Task 113 -> Task 120 -> Task 131 -> Task 132（再次重构）：MobileGL 三后端的
// 入口形态变迁：
// - Task113：mobilegl_vulkan 布尔开关（无条件覆盖任何显式渲染器，1d4ff3a9
//   "选 zink 被静默换成 vk"事故源，已退役）；
// - Task120：合并为 MobileGlues 分区的独立设置行 mobilegl_backend，且仅
//   renderer=auto 时生效——装机实测被用户四次否决："设置项还是分开的"，
//   且其仅 renderer=auto 生效的门控让显式选了 MobileGlues/zink 的
//   设备切了也无效；
// - Task131：三后端条目回到渲染器悬浮菜单（rendererCandidates 表），
//   mobilegl_backend 独立设置行退役——仍被否决：用户要求【合并为一个
//   统一入口 + 原地悬浮浮窗】，菜单里三个独立条目还是"分开的"；
// - Task132（现行）：三后端从渲染器菜单退役，合并为 MobileGlues 分区的
//   单一 pick 行 renderer_backend（typePickField 原地悬浮浮窗，三选项
//   默认 Vulkan 直连）；选择直接写渲染器键（与渲染器行同一存储层，
//   显式选择永远优先）。legacy：存量设备 renderer=auto +
//   mobilegl_backend=1/2/3 的解析路径保留在 ame_effective_renderer
//   （行为不变，直到用户在新浮窗里显式改选）。

// Task 120：有效渲染器解析（单一事实源，见 LauncherPreferences.h 头注释）。
// 注意与 JavaLauncher.m 的 AMETHYST_RENDERER 解析点保持逐字一致——两处任何
// 分叉都会复刻 Task124 的事故形态（layerClass 按旧渲染器建了普通 CALayer，
// 实际渲染器却是 MobileGL DirectVulkan，其内部 MoltenVK 在 swapchain 创建时
// 向普通 CALayer 发送 naturalDrawableSizeMVK -> unrecognized selector 崩溃）。
NSString *ame_effective_renderer(void) {
    // Task 142：读前迁移（幂等，进程内哨兵）——把旧版直写的家族键
    // 分层入位（video.renderer/profile → "mg"，家族键 → 后端键）。
    ame142_migrateRendererStorage();
    // Task 150（[可撤销] 删除渲染器全局控制）：解析链改为
    // 【profile 键 → auto】——resolveKeyForCurrentProfile 的全局
    // video.renderer 回退已在 PLProfiles prefDefaults 退役，实例无
    // renderer 键即落 "auto"（用户确认的缺省；1.17+ 经 Task144 升级
    // 解析为 MobileGL Vulkan 直连）。撤销 = 恢复 prefDefaults 映射行。
    NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
    if (![renderer isKindOfClass:NSString.class] || renderer.length == 0) {
        renderer = @"auto";
    }
    // (1a) Task 142："mg" 逻辑键 —— 渲染器层不写后端，后端按 mg 设置
    // （mobileglues.renderer_backend，默认 Vulkan 直连）在启动时解析。
    if ([renderer isEqualToString:@ RENDERER_KEY_MG]) {
        NSString *ame142_backend = ame142_effective_backend_key();
        // Task 158（mg 后端重映射）：GLES / OpenGL 4.0 两档改走 MobileGlues
        //（libmobileglues.dylib）——即 5.1.0 正式版用户实际可玩的两条路径
        //（9e6fc27 装机日志 latestlog.es / latestlog.4.0 实证：前者
        // enableANGLE=3+customGLVersion=32，后者 customGLVersion=40，均
        // fsr1Setting=4、MC 26.2 全程可玩、swap 链健康、exit(0) 正常退出）。
        // Task131 起这两档被接到 MobileGL-Espryt(DirectGLES) / libmithril
        // 两个上游二进制后：ES 档方块不可见（Task140/153/154 清完启动器侧
        // 全部嫌疑、Task156 强制 drawelements 档位实测仍不渲染——上游翻译层
        // 缺陷，启动器不可修），4.0 档 Mithril 管线着色器编译崩溃
        //（Sampler0Smplr 未声明 → MoltenVK pipeline 创建失败 → 重试路径
        // commit_frame SIGSEGV，10cee5d 装机日志实锤）。两档回接 MobileGlues：
        //   - ame83_fsr_capable_renderer(libmobileglues)=YES → FSR 档位联动
        //     随 mobileglues.fsr1_setting 恢复（5.1.0 同款 MobileGlues FSR1，
        //     窗口=表面/档位系数 + 渲染器侧升采样，输入换算同口径）；
        //   - MobileGlues config 由 init_loadMobileGluesConfig 按
        //     ame158_mg_mobileglues_mode() 强制 5.1.0 语义（GLES：ANGLE
        //     ForceEnable+GL3.2；4.0：GL4.0+ANGLE off）；
        //   - Vulkan 直连（默认）保持 libMobileGL.dylib 不变——da5918a 语义
        //     与 Task154 的 mgl_fsr 退休链零回退（MobileGL 的 EGL 是伪 EGL，
        //     无 FSR 升采样钩子，强行联动=输入错位+毁帧，见 Task154 病历）。
        // 本函数为纯解析器（layerClass/显示层高频调用），不打日志；一次性
        // 装机锚点在 init_loadMobileGluesConfig 的 Task158 行。
        if ([ame142_backend isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES] ||
            [ame142_backend isEqualToString:@ RENDERER_NAME_MITHRIL]) {
            if (rendererLibraryExists(@ RENDERER_NAME_MOBILEGLUES)) {
                return @ RENDERER_NAME_MOBILEGLUES;
            }
            // libmobileglues.dylib 缺失（非常规构建）→ 落回下方守卫链
            //（libMobileGL → auto），行为与后端 dylib 缺失一致。
        }
        NSString *ame142_physical = @(ame_physical_renderer_dylib(ame142_backend.UTF8String));
        if ([ame142_physical hasSuffix:@".dylib"] && rendererLibraryExists(ame142_physical)) {
            return ame142_backend;
        }
        // 守卫回落：所选后端 dylib 缺失（现实命中 = Mithril 需另外下载）
        // → 默认 Vulkan 直连（libMobileGL.dylib 随包）→ 仍缺才 auto。
        static BOOL ame142_warned = NO;
        NSLog(@"[Amethyst] Task142: mg backend %@ unavailable (%@ missing from bundle) -- falling back",
              ame142_backend, ame142_physical);
        if (!ame142_warned) {
            ame142_warned = YES;
            // 提示里显示后端真实名（家族键 → 三后端文案；不能用
            // ame_renderer_display_name——Task142 起它把家族键显示为 "mg"）
            NSString *ame142_bname = ame142_backend;
            NSArray *ame142_fk = getRendererFamilyKeys();
            NSArray *ame142_fn = getRendererFamilyNames();
            NSUInteger ame142_bi = [ame142_fk indexOfObject:ame142_backend];
            if (ame142_bi != NSNotFound && ame142_bi < ame142_fn.count) {
                ame142_bname = ame142_fn[ame142_bi];
            }
            NSString *ame142_msg = [NSString stringWithFormat:
                localize(@"preference.warning.mg_backend_missing_dylib", nil),
                ame142_bname];
            dispatch_async(dispatch_get_main_queue(), ^{
                [NMToast showMessage:ame142_msg];
            });
        }
        if (rendererLibraryExists(@ RENDERER_NAME_MOBILEGL)) {
            return @ RENDERER_NAME_MOBILEGL;
        }
        return @"auto";
    }
    // (1) 显式渲染器选择优先：zink/ANGLE/MobileGlues/LTW/MoltenVK/Mithril
    //     等任何非 auto 选择都原样生效，MobileGL 后端选项不干预。
    // （legacy 家族键在此路径原样返回——迁移后不再出现，未迁移安装
    // 保持 Task132-140 行为，与 Task138 dylib 守卫同构。）
    if (![renderer isEqualToString:@"auto"]) {
        // Task 138：dylib 缺失守卫。显式选中的渲染器物理文件不在 app
        // Frameworks 时回落 auto（当前唯一现实命中 = Mithril——
        // libmithril.dylib 是需另外下载的预编译产物，而 Task132 按用户
        // 指令在悬浮菜单无条件列出 MobileGL 家族三选项，缺文件时选中
        // 即必崩：本轮 26.2 会话实证 LWJGL 侧 "Failed to locate
        // library: libmithril.dylib" 的 UnsatisfiedLinkError 闪退）。
        // -gles 逻辑键先经 ame_physical_renderer_dylib 映射到共享
        // libMobileGL.dylib（随包存在，不会误伤）。回落带主线程 NMToast
        // 明示 + 日志留档；每进程只提示一次（本函数会被显示层高频
        // 调用）。layerClass 与 JavaLauncher 均以本函数为单一事实源，
        // 回落后两端一致（Task124 的同源纪律）。
        NSString *ame138_physical = @(ame_physical_renderer_dylib(renderer.UTF8String));
        if ([ame138_physical hasSuffix:@".dylib"] && !rendererLibraryExists(ame138_physical)) {
            static BOOL ame138_warned = NO;
            NSLog(@"[Amethyst] Task138: renderer %@ selected but %@ is missing from the app "
                  @"bundle -- falling back to auto (ANGLE). Install the dylib into Frameworks "
                  @"to use this renderer.", renderer, ame138_physical);
            if (!ame138_warned) {
                ame138_warned = YES;
                NSString *ame138_name = [ame138_physical isEqualToString:@ RENDERER_NAME_MITHRIL]
                    ? localize(@"preference.title.renderer_backend-mithril", nil)
                    : renderer;
                NSString *ame138_msg = [NSString stringWithFormat:
                    localize(@"preference.warning.renderer_missing_dylib", nil), ame138_name];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NMToast showMessage:ame138_msg];
                });
            }
            return @"auto";
        }
        return renderer;
    }
    // (2) auto + MobileGL 后端选项：按档位覆盖（dylib 缺失时守卫回落）。
    // Task161（auto 跟随后端键——"3 端都可以了但没有 FSR"根修）：
    //   用户明令"后端是根据 mg 设置选择的后端启动，默认 vulkan"。Task150
    //   起 profile 无 renderer 键即落 auto（新建整合包实例、Task158 重映射
    //   前的老实例都是这个形态），而 auto 原先只认 legacy 整数档位键
    //   （mobileglues.mobilegl_backend 1/2/3）——设置页 MobileGlues 分区
    //   的新后端 pick（mobileglues.renderer_backend）对 auto 实例完全无效：
    //   用户选了 4.0 后端，实际仍解析为 auto → JavaLauncher 按 MC 版本落
    //   libMobileGL.dylib（Vulkan 直连，Task154 FSR 退休链）→ "怎么都
    //   没有 fsr 放大和锐化"。修复：auto 与 mg 同源消费
    //   ame142_effective_backend_key（新键优先 + legacy 档位兜底）——
    //   GLES / OpenGL 4.0 后端 → libmobileglues.dylib（Task158 重映射 +
    //   ame158_mg_mobileglues_mode 的 5.1.0 配置强制，FSR1 联动随
    //   mobileglues.fsr1_setting 恢复）；Vulkan 直连（默认）→ 维持返回
    //   "auto" 原样（JavaLauncher 的 auto 解析点按 MC 版本决定
    //   libMobileGL / ANGLE——旧 MC 的 ANGLE 回退语义保持不变）。
    {
        NSString *ame161_backend = ame142_effective_backend_key();
        if ([ame161_backend isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES] ||
            [ame161_backend isEqualToString:@ RENDERER_NAME_MITHRIL]) {
            if (rendererLibraryExists(@ RENDERER_NAME_MOBILEGLUES)) {
                return @ RENDERER_NAME_MOBILEGLUES;
            }
            // libmobileglues.dylib 缺失（非常规构建）→ 落回 auto（下方
            // legacy 档位检查后原样返回）。
        }
    }
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
//   3. Task 143：独立 MobileGlues 条目（libmobileglues.dylib，Task 131 时代
//      的经典渲染器）从选择列表隐退，仅当它是当前选中值时保留可见——用户
//      装机反馈"mg 是 MobileGlues，为什么列表有个 mg 又有个 MobileGlues"：
//      Task142 的单一 mg 入口（MobileGL 家族）与经典 libmobileglues 条目
//      并列，命名撞车让用户无从分辨。现行语义：渲染器层的 MG 语义由 "mg"
//      独占；libmobileglues 降级为存量兼容项（已选设备照常显示/启动，
//      ame_effective_renderer 的 legacy 显式键路径不变，dylib 仍随包构建），
//      新选择一律走七项列表（auto/mg/gl4es/angle/zink/ltw/vulkan）。
static NSArray<NSDictionary *> *availableRendererCandidates(void) {
    NSString *current = currentRendererKey();
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *entry in rendererCandidates()) {
        NSString *file = entry[@"file"];
        NSString *key = entry[@"key"];
        if (file.length > 0 && !rendererLibraryExists(file) && ![key isEqualToString:current]) {
            continue;
        }
        if ([key isEqualToString:@ RENDERER_NAME_MOBILEGLUES] &&
            ![key isEqualToString:current]) {
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

// Task 140：统一渲染器显示名——设置页两行（video.renderer 主行 +
// mobileglues.renderer_backend 后端行）与实例设置页（ProfileSettings
// 渲染器行）共用。家族键 → 三后端文案；经典键（auto/gl4es/zink/...）
// → rendererCandidates 表的显示名（getRendererKeys/Names 同源配对）；
// 未知值原样返回。
//
// 病历：Task139 让设置行 profile 优先显示后，两行与实例页互相"扮演"
// 对方层级的状态（mg 行对非家族值还无条件显示"Vulkan 直连"假默认），
// 用户看到"改了实例渲染器，设置 mg 行没变 / 改了设置，实例页被覆写"。
// Task140 起分层明确：设置页 = 全局默认（本函数显示全局值），实例页 =
// 该游戏自己的值（含"跟随全局"态），互不伪装。
NSString *ame_renderer_display_name(NSString *renderer) {
    if (![renderer isKindOfClass:NSString.class] || renderer.length == 0) {
        return localize(@"preference.title.renderer.debug.auto", nil);
    }
    // Task 142："mg" 逻辑键与 legacy 家族键统一显示 "mg"——渲染器层不
    // 呈现后端（后端由 MobileGlues 分区 renderer_backend 行显示与选择，
    // 用户明令"渲染器选择只有一个 mg，而且不写什么后端"）。
    if ([renderer isEqualToString:@ RENDERER_KEY_MG] ||
        [renderer isEqualToString:@ RENDERER_NAME_MOBILEGL] ||
        [renderer isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES] ||
        [renderer isEqualToString:@ RENDERER_NAME_MITHRIL]) {
        return localize(@"preference.title.renderer.debug.mgfamily", nil);
    }
    if ([renderer isEqualToString:@"auto"]) {
        return localize(@"preference.title.renderer.debug.auto", nil);
    }
    // Task 143：独立 MobileGlues（libmobileglues.dylib）自选择列表隐退
    // （见 availableRendererCandidates 规则 3）后，存量 profile 存储值不再
    // 出现在 getRendererKeys 里，此处若走"未命中原样返回"会裸显 dylib 键名。
    // 显式映射回它的既有文案（preference.title.renderer.debug.mg，四语言
    // 现成键，零 l10n 变更）——存量设备行显示与迁移前完全一致。
    if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        return localize(@"preference.title.renderer.debug.mg", nil);
    }
    NSArray *keys = getRendererKeys(NO);
    NSArray *names = getRendererNames(NO);
    NSUInteger idx = [keys indexOfObject:renderer];
    if (idx != NSNotFound && idx < names.count) {
        return names[idx];
    }
    return renderer;
}

// Task 132（MG 三端合并）：MobileGL 家族三后端的统一浮窗数据源。
// keys 为逻辑键（与 ame_effective_renderer / egl_bridge / JavaLauncher 的
// 渲染器值同一命名空间，直接写入 video.renderer 即生效）；names 为用户
// 指定的三选项文案（本地化键见四语言 Localizable.strings）。
// 无条件列出三项（用户明令浮窗列出三选项；Mithril 的 dylib 缺失与否
// 不再作为隐藏条件——渲染器菜单时代的老过滤已随条目退役）。
// Task 142：mg 后端解析（单一事实源，供 ame_effective_renderer 的 mg 分支
// 与设置页 renderer_backend 行的读取显示共用）。优先级：
//   (a) mobileglues.renderer_backend（合法家族键——新版独立后端存储）；
//   (b) legacy：全局 video.renderer 直接存家族键（Task132-140 形态；
//       迁移前的瞬态/跨进程竞态兜底）；
//   (c) legacy：renderer 为 auto/"mg" 且 mobileglues.mobilegl_backend 档位
//       （Task120 形态）——老安装上档位代表用户的后端选择，如实抬升；
//   (d) 默认 Vulkan 直连（libMobileGL.dylib，用户指定"默认vulkan"）。
// 返回值恒为家族物理键；dylib 存在性守卫由调用方负责。
NSString* ame142_effective_backend_key(void) {
    NSArray *ame142_family = getRendererFamilyKeys();
    id ame142_be = getPrefObject(@"mobileglues.renderer_backend");
    if ([ame142_be isKindOfClass:NSString.class] && [ame142_family containsObject:ame142_be]) {
        return ame142_be;
    }
    id ame142_vr = getPrefObject(@"video.renderer");
    if ([ame142_vr isKindOfClass:NSString.class] && [ame142_family containsObject:ame142_vr]) {
        return ame142_vr;
    }
    if (![ame142_vr isKindOfClass:NSString.class] ||
        [ame142_vr isEqualToString:@"auto"] ||
        [ame142_vr isEqualToString:@ RENDERER_KEY_MG]) {
        NSInteger ame142_legacy = getPrefInt(@"mobileglues.mobilegl_backend");
        if (ame142_legacy == 2) return @ RENDERER_NAME_MOBILEGL_GLES;
        if (ame142_legacy == 3) return @ RENDERER_NAME_MITHRIL;
        if (ame142_legacy == 1) return @ RENDERER_NAME_MOBILEGL;
    }
    return @ RENDERER_NAME_MOBILEGL;
}

// Task 158：mg 家族 GLES / OpenGL 4.0 后端重映射（ame_effective_renderer 的
// mg 分支）到 MobileGlues 后，该会话应使用的 MobileGlues 配置模式。
// 返回值：
//   0 = 非 mg-remap 会话——独立 MobileGlues 渲染器（存量 profile 直选
//       libmobileglues.dylib）或 mg+Vulkan 直连（config.json 照写但
//       libMobileGL 不读它，Task153 strings 实证），用户 MobileGlues 分区
//       偏好原样透传（5.1.0 语义，含 enable_angle / custom_gl_version 档位）；
//   1 = mg GLES 后端——强制 enableANGLE=3 (ForceEnable) + customGLVersion=32
//      （ANGLE 在 iOS 的 GLES 上限；5.1.0 latestlog.es 同款形态）；
//   2 = mg OpenGL 4.0 后端——强制 enableANGLE=0 + customGLVersion=40
//      （MobileGlues 2.0.16 默认 GL 档；5.1.0 latestlog.4.0 同款形态）。
// 消费者：JavaLauncher.init_loadMobileGluesConfig（配置强制点，唯一调用方）。
// 模式判定只看存储层（profile renderer 键 + mobileglues.renderer_backend），
// 与 ame_effective_renderer 的解析结果天然一致（mg+gles/mithril 恒解析为
// libmobileglues.dylib；mg+vulkan 恒解析为 libMobileGL.dylib）。
int ame158_mg_mobileglues_mode(void) {
    ame142_migrateRendererStorage();
    NSString *ame158_pr = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
    // Task161：auto（含无键缺省）与 mg 同源跟随 mg 后端键。ame_effective_renderer
    // 的 auto 分支现在会把 GLES / OpenGL 4.0 后端解析为 libmobileglues.dylib，
    // 本判定必须同步——否则 auto+GLES 会话拿到 mode 0（customGLVersion 默认
    // 40，桌面 GLSL #version 400 被 ANGLE 拒收）→ ES 方块不渲染回归
    // （5.1.0 时代的同款修复缺失，Task158 病历）。
    BOOL ame161_autoProfile = (![ame158_pr isKindOfClass:NSString.class] ||
                               ame158_pr.length == 0 ||
                               [ame158_pr isEqualToString:@"auto"]);
    if (!ame161_autoProfile &&
        ![ame158_pr isEqualToString:@ RENDERER_KEY_MG]) {
        // legacy：未迁移进程态的家族键直选（ame142_migrateRendererStorage 正常
        // 已在首次读取时把它迁成 "mg"；此处防御首读竞态。独立 MobileGlues
        // 直选（libmobileglues.dylib）不在此列——它走用户自有设置）。
        if (![ame158_pr isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES] &&
            ![ame158_pr isEqualToString:@ RENDERER_NAME_MITHRIL]) {
            return 0;
        }
    }
    NSString *ame158_backend = ame142_effective_backend_key();
    if ([ame158_backend isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES]) return 1;
    if ([ame158_backend isEqualToString:@ RENDERER_NAME_MITHRIL]) return 2;
    return 0;
}

// Task 142：一次性存储分层迁移（幂等；进程内 static 哨兵，可被任何读前
// 路径安全重入——ame_effective_renderer / 设置页 / 实例页均会先行触达）。
// 旧版（Task132-140）家族键直写 video.renderer 与 profile 的 renderer 键；
// 新版渲染器层只存 "mg"，后端独立存 mobileglues.renderer_backend：
//   - 全局：家族键 → 后端键（若未设）+ video.renderer = "mg"；
//   - 各 profile：家族键 → "mg"（后端自此统一由 mg 设置决定）；
//   - 迁移落位的同时退役 legacy 档位键 mobileglues.mobilegl_backend
//     （写入后端键即"用户显式改选"，Task132 承诺的 legacy 终点），
//     避免 JavaLauncher 的档位环境变量分支与新后端键互相矛盾。
void ame142_migrateRendererStorage(void) {
    static BOOL ame142_done = NO;
    if (ame142_done) return;
    ame142_done = YES;
    NSArray *ame142_family = getRendererFamilyKeys();
    // (1) 全局层
    id ame142_vr = getPrefObject(@"video.renderer");
    if ([ame142_vr isKindOfClass:NSString.class] && [ame142_family containsObject:ame142_vr]) {
        id ame142_be = getPrefObject(@"mobileglues.renderer_backend");
        if (![ame142_be isKindOfClass:NSString.class] ||
            ![ame142_family containsObject:ame142_be]) {
            setPrefObject(@"mobileglues.renderer_backend", ame142_vr);
        }
        setPrefObject(@"video.renderer", @ RENDERER_KEY_MG);
        setPrefInt(@"mobileglues.mobilegl_backend", 0);
        NSLog(@"[Amethyst] Task142: global renderer %@ migrated to 'mg' (backend key set, legacy tier retired)",
              ame142_vr);
    }
    // (2) profile 层：逐个把家族键替换为 "mg"。
    // profiles getter 返回 profileDict 内的活字典（非副本，VersionManager
    // 同款口径）——原地改写后 [PLProfiles.current save] 一次落盘。
    @try {
        NSMutableDictionary *ame142_profiles = PLProfiles.current.profiles;
        BOOL ame142_dirty = NO;
        if ([ame142_profiles isKindOfClass:NSMutableDictionary.class]) {
            for (NSString *ame142_name in ame142_profiles.allKeys.copy) {
                NSMutableDictionary *ame142_prof =
                    [ame142_profiles[ame142_name] isKindOfClass:NSDictionary.class]
                        ? [ame142_profiles[ame142_name] mutableCopy] : nil;
                if (!ame142_prof) continue;
                id ame142_pr = ame142_prof[@"renderer"];
                if ([ame142_pr isKindOfClass:NSString.class] &&
                    [ame142_family containsObject:ame142_pr]) {
                    ame142_prof[@"renderer"] = @ RENDERER_KEY_MG;
                    ame142_profiles[ame142_name] = ame142_prof;
                    ame142_dirty = YES;
                    NSLog(@"[Amethyst] Task142: profile '%@' renderer %@ migrated to 'mg' (backend now follows mg settings)",
                          ame142_name, ame142_pr);
                }
            }
            if (ame142_dirty) {
                [PLProfiles.current save];
            }
        }
    } @catch (NSException *ame142_e) {
        // profiles 文件异常时静默跳过（resolution 层仍兼容家族键原样返回）
        NSLog(@"[Amethyst] Task142: profile migration skipped (%@)", ame142_e);
    }
}

NSArray* getRendererFamilyKeys(void) {
    return @[
        @ RENDERER_NAME_MOBILEGL,
        @ RENDERER_NAME_MOBILEGL_GLES,
        @ RENDERER_NAME_MITHRIL
    ];
}

NSArray* getRendererFamilyNames(void) {
    return @[
        localize(@"preference.title.renderer_backend-mobilegl", nil),
        localize(@"preference.title.renderer_backend-mobilegl_gles", nil),
        localize(@"preference.title.renderer_backend-mithril", nil)
    ];
}
