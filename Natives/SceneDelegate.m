#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "LauncherRootViewController.h"
#import "LauncherCardLayoutViewController.h"
#import "LauncherPreferences.h"
#import "BackgroundManager.h"
#import "BingWallpaperManager.h" // Task151
// Terracotta 暂时移除（排查启动崩溃）
// #import "TerracottaManager.h"
// #import "TerracottaBridge.h"

extern __weak UIWindow *mainWindow;

@interface SceneDelegate ()
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    // Task189：异常处理器晚装复挂（AppDelegate 挂载点之后 LC 若再覆盖，
    // 此处再抢回一次——场景连接是 UI 阶段最后的稳定挂载点）。
    {
        extern void uncaughtExceptionHandler(NSException *exception);
        NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    }

    // 强制横屏 (iOS 16+)
    // Task188：窗口模式（iPadOS 26+ 多窗口/LiveContainer 宿主）下系统持有
    // 几何、本请求预期被拒（Code=101）——Info.plist 的 UIRequiresFullScreen=true
    // 才是主修复；此请求仅在全屏模式下作纵深防御，失败为预期态降级为单次
    // 提示（不再每次启动刷一条 Failed 日志）。
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *geometryPreferences = [[UIWindowSceneGeometryPreferencesIOS alloc] init];
        geometryPreferences.interfaceOrientations = UIInterfaceOrientationMaskLandscape;
        [windowScene requestGeometryUpdateWithPreferences:geometryPreferences errorHandler:^(NSError *error) {
            static BOOL s_task188_logged = NO;
            if (!s_task188_logged) {
                s_task188_logged = YES;
                NSLog(@"[SceneDelegate] Task188: geometry request declined (expected in window mode; Info.plist UIRequiresFullScreen is the primary fix): %@", error.localizedDescription);
            }
        }];
    }
    
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    // Task137：窗口底色回归 iOS 原生系统底色（深浅色由语义色自动适配）；
    // 用户设置自定义壁纸时仍由 BackgroundManager.applyBackgroundToWindow
    // 接管（Task111 检测并切换）。
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    mainWindow = self.window;

    // 根据设置选择布局：Task180 用户定稿默认 = 卡片式便当盒布局；显式选择
    // 过 "vs"（写盘）的设备保持三栏布局（未写盘 = 从未选择 → 走新默认 card）
    NSString *layout = getPrefObject(@"general.ui_layout");
    UIViewController *rootVC;
    if ([layout isEqualToString:@"vs"]) {
        rootVC = [[LauncherRootViewController alloc] init];
    } else {
        rootVC = [[LauncherCardLayoutViewController alloc] init];
    }
    self.window.rootViewController = rootVC;

    // 外观模式（浅色/深色/跟随系统）：读 general.ui_theme 偏好。
    //   light  -> UIUserInterfaceStyleLight
    //   dark   -> UIUserInterfaceStyleDark（Task160 前的历史默认）
    //   auto   -> UIUserInterfaceStyleUnspecified（跟随系统；Task161 起为默认）
    // iOS 13+ 支持 overrideUserInterfaceStyle。仅设置 window 级别，不触碰账号/偏好。
    if (@available(iOS 13.0, *)) {
        // Task161：一次性迁移——外观默认值改为"跟随系统"（用户指令）。历史
        // 版本的默认合并曾把 dark（Task160 前）/ light（Task160）静默写盘，
        // 只改默认表对这些设备无效；未显式选择过的设备（无
        // general.ui_theme_explicit 标记）若还停在两个历史默认值上，迁移到
        // auto。显式选过的设备永不覆盖（标记在设置页 pick 的 action 里置位）。
        if (!getPrefBool(@"general.ui_theme_explicit")) {
            NSString *ame161_legacy = getPrefObject(@"general.ui_theme");
            if ([ame161_legacy isEqualToString:@"auto"] ||
                [ame161_legacy isEqualToString:@"light"]) {
                // Task180：用户定稿默认初始值 = 深色模式——未显式选择过的设备
                // （停在 auto（Task161 迁移值）/ light 历史默认上）迁移到 dark；
                // 显式选择过的设备永不覆盖（Task161 家法不变）。
                setPrefObject(@"general.ui_theme", @"dark");
                NSLog(@"[SceneDelegate] Task180: ui_theme '%@' was never explicitly chosen -> migrated to 'dark' (user-specified default)", ame161_legacy);
            }
        }
        NSString *theme = getPrefObject(@"general.ui_theme");
        if ([theme isEqualToString:@"light"]) {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        } else if ([theme isEqualToString:@"auto"]) {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        } else {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }

    [self.window makeKeyAndVisible];

    // Task189（强制横屏第三轮）：窗口内容旋转兜底。Task187 移除 Portrait、
    // Task188 声明 UIRequiresFullScreen=true 均在真机无效——LiveContainer 宿主
    // 下窗口模式由【宿主】的 plist 决定，来宾 plist 的方向列表与全屏声明不被
    // 系统采纳（几何请求 Code=101 拒绝 + 仍处窗口模式双证）。本轮不再依赖
    // 系统honoring任何声明：窗口为竖向时直接对 UIWindow 施加 90° transform，
    // 把内容坐标系换为横屏（bounds 高宽互换 + center 对齐窗口中心）——UI、
    // 游戏、触控（UIKit 命中测试自动走逆变换）全部一致，物理窗口形状不变、
    // 内容铺满无黑边。横屏窗口零变化（transform 恒等）。场景尺寸变化（用户
    // 调整窗口大小 / 旋转设备）经 didUpdateCoordinateSpace 重评估。
    [self ame189_applyLandscapeWindowTransform];
    NSLog(@"[SceneDelegate] Task189: landscape window transform evaluated (bounds=%@ rotated=%d)",
          NSStringFromCGRect(self.window.windowScene.coordinateSpace.bounds),
          (int)!CGAffineTransformIsIdentity(self.window.transform));

    // Task137：Task136 的 NMContrast 动态文字对比度扫描器随新拟态一并退役。
    // 深底深字问题改为直接修复（各元素使用系统语义色/动态色自动适配，
    // 例：右侧栏下载中心按钮 Task137 已改 secondarySystemGroupedBackground
    // 底 + labelColor 字，深浅色下对比度均由系统保证）。

    // 立即应用背景（移除原来的 0.1s 延迟）：
    // 延迟会在启动时露出窗口底色形成"黑条"或"黑闪"。BackgroundManager 在其 init
    // 中已 loadSavedBackground/loadUISettings，单例首次访问即完成初始化，无需延迟。
    [[BackgroundManager sharedManager] applyBackgroundToWindow:self.window];

    // Task151：Bing 每日壁纸自动刷新与应用（默认开启；全异步不阻塞启动：
    // 有缓存今日图直接登记背景，否则联网拉取后换图；用户自定义壁纸优先）。
    [[BingWallpaperManager sharedManager] autoRefreshAndApplyIfEnabled];

    [self showTranslationNoticeIfNeeded];

    // Terracotta 暂时移除（排查启动崩溃）
    // if ([TerracottaBridge isAvailable]) {
    //     TerracottaManager *mgr = [TerracottaManager shared];
    //     NSLog(@"[SceneDelegate] Terracotta manager initialized: %d", mgr.initialized);
    // } else {
    //     NSLog(@"[SceneDelegate] libterracotta not linked, multiplayer disabled");
    // }
    NSLog(@"[SceneDelegate] Terracotta temporarily disabled for crash investigation");

    // 监听主题切换通知（设置页"外观模式"切换时实时应用，无需重启）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyUITheme:)
                                                 name:@"UIThemeChanged"
                                               object:nil];
    // 监听语言切换通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyLanguageChange:)
                                                 name:@"AppLanguageChanged"
                                               object:nil];
}

- (void)showTranslationNoticeIfNeeded {
    // 仅当实际显示语言为英文时提示（包括系统英文和手动选择英文）。
    // 用户选择“不再提醒”后通过偏好持久化，下次不再弹出。
    NSString *lang = getPrefObject(@"general.app_language");
    BOOL isEnglish;
    if (lang && ![lang isEqualToString:@"system"]) {
        isEnglish = [lang isEqualToString:@"en"];
    } else {
        isEnglish = [NSLocale.preferredLanguages.firstObject hasPrefix:@"en"];
    }
    if (!isEnglish) {
        return;
    }
    if (getPrefBool(@"general.translation_notice_dismissed")) {
        return;
    }

    UIViewController *presenter = self.window.rootViewController;
    if (presenter == nil) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_2000", nil)
                                                                   message:localize(@"i18n_str_2001", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *gotItAction = [UIAlertAction actionWithTitle:localize(@"i18n_str_2002", nil)
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil];
    [alert addAction:gotItAction];

    UIAlertAction *dontAskAction = [UIAlertAction actionWithTitle:localize(@"i18n_str_2003", nil)
                                                            style:UIAlertActionStyleCancel
                                                          handler:^(UIAlertAction *action) {
        setPrefBool(@"general.translation_notice_dismissed", YES);
    }];
    [alert addAction:dontAskAction];

    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)applyUITheme:(NSNotification *)notification {
    // 实时切换外观模式。仅修改 window.overrideUserInterfaceStyle，
    // 不触碰 PLPreferences 重置逻辑、不读写账号数据，确保切换主题不会导致账号退出。
    NSString *theme = notification.object ?: getPrefObject(@"general.ui_theme");
    if (@available(iOS 13.0, *)) {
        if ([theme isEqualToString:@"light"]) {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        } else if ([theme isEqualToString:@"auto"]) {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        } else {
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
    }
    // Task137：新拟态退役，无需主题广播重绘——外观切换由语义色动态适配。
}

- (void)applyLanguageChange:(NSNotification *)notification {
    // 语言切换后重建根视图控制器以应用新语言
    NSString *layout = getPrefObject(@"general.ui_layout");
    UIViewController *rootVC;
    if ([layout isEqualToString:@"card"]) {
        rootVC = [[LauncherCardLayoutViewController alloc] init];
    } else {
        rootVC = [[LauncherRootViewController alloc] init];
    }
    [UIView transitionWithView:self.window duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.window.rootViewController = rootVC;
    } completion:nil];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"UIThemeChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"AppLanguageChanged" object:nil];
    // Task137：window traitCollection KVO 已随 NMTheme 退役（注册与摘除同步移除）
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Task 62（窗口模式平反）：Task 56 曾以 UIRequiresFullScreen 灭小窗来断
    // "几何失控→表面转置→画面分裂"链条，但后续取证（Task 58-61）证明真凶
    // 另有其人——EGL 查询常量对调（58）、输入 px÷2（59）、1x 钉扎模糊（60）、
    // SDL3 点/像素分裂（61），窗口模式从未是肇因，且 Info.plist 已改回
    // UIRequiresFullScreen=false（恢复 iPadOS 26 多任务/窗口化）。本重试保留作
    // 纵深防御：窗口模式下系统拥有几何，requestGeometryUpdate 可能被拒
    // （Code=101 为良性噪声，旧日志全屏下也出现）；后台崩溃链的真正修复
    // （sdl3_hook 吞噬 MINIMIZED 事件）与呈现模式无关，继续生效。
    if (@available(iOS 16.0, *)) {
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIInterfaceOrientation orient = windowScene.interfaceOrientation;
        if (UIInterfaceOrientationIsLandscape(orient)) {
            return;  // 已横屏，无需重试
        }
        UIWindowSceneGeometryPreferencesIOS *geometryPreferences = [[UIWindowSceneGeometryPreferencesIOS alloc] init];
        geometryPreferences.interfaceOrientations = UIInterfaceOrientationMaskLandscape;
        [windowScene requestGeometryUpdateWithPreferences:geometryPreferences errorHandler:^(NSError *error) {
            NSLog(@"[SceneDelegate] Task56 geometry retry on becomeActive failed: %@", error);
        }];
        NSLog(@"[SceneDelegate] Task56 geometry retry on becomeActive (orientation=%ld not landscape)",
              (long)orient);
    }
    // Task189：激活时兜底重评估一次内容旋转（willConnect 时场景 bounds 尚未
    // 最终确定、且 didUpdateCoordinateSpace 不保证必有回调的窗口场景）。
    [self ame189_applyLandscapeWindowTransform];
}

- (void)sceneWillResignActive:(UIScene *)scene {
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    CallbackBridge_pauseGameIfNeed();
}

#pragma mark - Orientation Support (iOS 16+)

- (UIInterfaceOrientationMask)scene:(UIScene *)scene supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)windowScene API_AVAILABLE(ios(16.0)) {
    return UIInterfaceOrientationMaskLandscape;
}

// ============================================================================
// Task189（强制横屏第三轮）：窗口内容旋转兜底。
// 病历：Task187（plist 移除 Portrait）与 Task188（UIRequiresFullScreen=true）
// 双双真机无效——c3f4623 会话实测仍处窗口模式（geometry 请求 Code=101 拒绝），
// 根因 = LiveContainer 宿主流程里窗口化由宿主 app 的 plist/scene 清单决定，
// 来宾（本 app）的方向声明不被 UIKit 采纳。
// 方案：窗口 bounds 呈竖向（高 > 宽 * 1.02，留出近方形窗口的判定死区）时，
// 对 self.window 施加 90° 旋转 transform 并把窗口自身坐标系换为横屏
// （bounds 高宽互换、center 对齐场景中心）。效果：
//   - 全部 UI 与游戏内容横屏呈现，铺满窗口无黑边；
//   - 触控经 UIKit 逆变换自动映射到横屏坐标系（hit-testing 走 window 变换）；
//   - 安全区/刘海内缩在旋转坐标系内自动正确（Task187 的 inset 读取基于
//     view 层 safeAreaInsets，随坐标系平移）；
//   - 横屏窗口 transform 恒等，与既有行为零差异。
// 重评估时机：willConnect（首次）+ scene:didUpdateCoordinateSpace:（用户
// 调整窗口尺寸 / 设备旋转导致场景 bounds 变化时）。
// 逃生舱：偏好 general.disable_window_rotation_shim = true 可关闭（出现
// 触控/键盘错位等极端兼容问题时无需重编译即可回退）。
// ============================================================================
- (void)ame189_applyLandscapeWindowTransform {
    if (getPrefBool(@"general.disable_window_rotation_shim")) return;   // 逃生舱
    UIWindowScene *scene = self.window.windowScene;
    if (!scene || !self.window) return;

    CGRect sb = scene.coordinateSpace.bounds;
    if (sb.size.width <= 0 || sb.size.height <= 0) return;

    // 仅在"明显竖向"的窗口旋转（1.02 死区：近方形窗口旋转无收益反而扰动）
    BOOL portraitWindow = (sb.size.height > sb.size.width * 1.02);
    if (!portraitWindow) {
        if (!CGAffineTransformIsIdentity(self.window.transform)) {
            self.window.transform = CGAffineTransformIdentity;
            self.window.frame = sb;
            NSLog(@"[SceneDelegate] Task189: window is landscape -> rotation removed");
        }
        return;
    }

    // 旋转方向：跟随窗口当前报告的界面方向（PortraitUpsideDown 取反向，
    // 其余一律 +90°——窗口竖向时系统多报 Portrait，设备倒持时内容同样倒置
    // 可读）。M_PI_2 = 顺时针 90°。
    CGFloat angle = (scene.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
                        ? (CGFloat)(-M_PI_2) : (CGFloat)M_PI_2;
    CGAffineTransform rot = CGAffineTransformMakeRotation(angle);
    if (CGAffineTransformIsIdentity(self.window.transform) ||
        !CGAffineTransformEqualToTransform(self.window.transform, rot) ||
        !CGSizeEqualToSize(self.window.bounds.size, CGSizeMake(sb.size.height, sb.size.width))) {
        self.window.transform = rot;
        self.window.bounds = CGRectMake(0, 0, sb.size.height, sb.size.width);
        self.window.center = CGPointMake(sb.size.width / 2.0, sb.size.height / 2.0);
        NSLog(@"[SceneDelegate] Task189: portrait window -> content rotated 90deg (scene=%@ content=%@ angle=%+.0fdeg)",
              NSStringFromCGRect(sb), NSStringFromCGRect(self.window.bounds),
              (float)(angle * 180.0 / M_PI));
    }
}

- (void)scene:(UIScene *)scene didUpdateCoordinateSpace:(id<UICoordinateSpace>)coordinateSpace
                         interfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
                                        traitCollection:(UITraitCollection *)traitCollection {
    // Task189：窗口尺寸/方向变化（窗口模式下的拖拽调整、设备旋转）后
    // 重评估内容旋转。轻微去抖：下一帧执行，避开变更回调内的布局重入。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf ame189_applyLandscapeWindowTransform];
    });
}

@end
