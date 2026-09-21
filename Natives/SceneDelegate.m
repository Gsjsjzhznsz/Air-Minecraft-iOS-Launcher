#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "LauncherRootViewController.h"
#import "LauncherCardLayoutViewController.h"
#import "LauncherPreferences.h"
#import "BackgroundManager.h"
#import "NeomorphKit/NMTheme.h"
#import "NeomorphKit/NMContrast.h"
// Terracotta 暂时移除（排查启动崩溃）
// #import "TerracottaManager.h"
// #import "TerracottaBridge.h"

// Task89：window.traitCollection KVO 上下文（见 willConnect 处注释）
static void *kNMSceneTraitKVOContext = &kNMSceneTraitKVOContext;

extern __weak UIWindow *mainWindow;

@interface SceneDelegate ()
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    
    // 强制横屏 (iOS 16+)
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *geometryPreferences = [[UIWindowSceneGeometryPreferencesIOS alloc] init];
        geometryPreferences.interfaceOrientations = UIInterfaceOrientationMaskLandscape;
        [windowScene requestGeometryUpdateWithPreferences:geometryPreferences errorHandler:^(NSError *error) {
            NSLog(@"[SceneDelegate] Failed to update geometry: %@", error);
        }];
    }
    
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    // Task136：窗口底色改用 NMTheme 背景色（浅 #D6D6D6 / 深 #252525，随深浅色
    // 自动切换），与新拟态表面同族保证阴影可读；用户设置自定义壁纸时仍由
    // BackgroundManager.applyBackgroundToWindow 接管（Task111 检测并切换）。
    self.window.backgroundColor = [NMTheme nm_background];
    mainWindow = self.window;

    // 根据设置选择布局：默认 VS 三栏布局，可切换为卡片式便当盒布局
    NSString *layout = getPrefObject(@"general.ui_layout");
    UIViewController *rootVC;
    if ([layout isEqualToString:@"card"]) {
        rootVC = [[LauncherCardLayoutViewController alloc] init];
    } else {
        rootVC = [[LauncherRootViewController alloc] init];
    }
    self.window.rootViewController = rootVC;

    // Task89：KVO 监听 window.traitCollection——SceneDelegate 遵循
    // UIWindowSceneDelegate（非 UIResponder），traitCollectionDidChange:
    // 永远不会被调用，故用 KVO 捕获系统深浅色变化（auto 模式）与
    // 设置页外观切换（applyUITheme 内也会广播，双重触发幂等无害）。
    [self.window addObserver:self
                  forKeyPath:@"traitCollection"
                     options:NSKeyValueObservingOptionNew
                     context:kNMSceneTraitKVOContext];

    // 外观模式（浅色/深色/跟随系统）：读 general.ui_theme 偏好。
    //   light  -> UIUserInterfaceStyleLight
    //   dark   -> UIUserInterfaceStyleDark（默认，保持与原行为一致）
    //   auto   -> UIUserInterfaceStyleUnspecified（跟随系统）
    // iOS 13+ 支持 overrideUserInterfaceStyle。仅设置 window 级别，不触碰账号/偏好。
    if (@available(iOS 13.0, *)) {
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

    // Task136：启动动态文字对比度修复器（监听主题/背景效果广播自动扫描；
    // 幂等，只拦截黑字深底等不可读组合）
    [NMContrast nm_startContrastSweep];

    // 立即应用背景（移除原来的 0.1s 延迟）：
    // 延迟会在启动时露出窗口底色形成"黑条"或"黑闪"。BackgroundManager 在其 init
    // 中已 loadSavedBackground/loadUISettings，单例首次访问即完成初始化，无需延迟。
    [[BackgroundManager sharedManager] applyBackgroundToWindow:self.window];

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
    // Task89：新拟态主题跟随有效外观（含 override），切换时广播重绘全部
    // Neomorph 附件（表面色/阴影透明度按新主题重算）。
    [[NMTheme shared] reloadAndBroadcast];
}

// Task89：auto 模式下跟随系统深浅色切换（KVO window.traitCollection，见 willConnect 处注释）
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == kNMSceneTraitKVOContext && [keyPath isEqualToString:@"traitCollection"]) {
        [[NMTheme shared] reloadAndBroadcast];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
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
    // Task89：摘除 window traitCollection KVO
    if (self.window) {
        [self.window removeObserver:self forKeyPath:@"traitCollection" context:kNMSceneTraitKVOContext];
    }
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

@end
