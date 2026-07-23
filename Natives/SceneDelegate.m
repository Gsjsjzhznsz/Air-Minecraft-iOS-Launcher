#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "LauncherRootViewController.h"
#import "LauncherCardLayoutViewController.h"
#import "LauncherPreferences.h"
#import "BackgroundManager.h"
#import "TerracottaManager.h"
#import "TerracottaBridge.h"

extern UIWindow *mainWindow;

@interface SceneDelegate ()
// 记录 requestGeometryUpdateWithPreferences 是否失败
// iOS 16+ 在 willConnectToSession 阶段调用 requestGeometryUpdateWithPreferences
// 可能因窗口场景尚未完全 attach 而失败（error code=101）。
// 失败后在 sceneDidBecomeActive 中重试，确保横屏几何生效。
@property (nonatomic, assign) BOOL geometryUpdateFailed;
@property (nonatomic, assign) BOOL geometryUpdateRetried;
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
    // 修复：使用 systemBackgroundColor 自适应浅色/深色模式。
    // 之前硬编码深灰（0.08）在浅色模式下导致"中间一片黑"。
    // systemBackgroundColor 在浅色模式为白、深色模式为黑，自动适配。
    // BackgroundManager.applyBackgroundToWindow 会根据用户是否设置自定义壁纸覆盖此颜色。
    if (@available(iOS 13.0, *)) {
        self.window.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.window.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    }
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

    // 立即应用背景（移除原来的 0.1s 延迟）：
    // 延迟会在启动时露出窗口底色形成"黑条"或"黑闪"。BackgroundManager 在其 init
    // 中已 loadSavedBackground/loadUISettings，单例首次访问即完成初始化，无需延迟。
    [[BackgroundManager sharedManager] applyBackgroundToWindow:self.window];

    // 初始化陶瓦联机（Terracotta）：访问 shared 单例会触发 init，init 内部自动调用
    // initializeTerracotta（terracotta_ios_start 一次性初始化，工作目录 Documents/terracotta）。
    // libterracotta.a 未链接时 isAvailable=NO，init 内部跳过初始化，initialized 保持 NO。
    if ([TerracottaBridge isAvailable]) {
        TerracottaManager *mgr = [TerracottaManager shared];
        NSLog(@"[SceneDelegate] Terracotta manager initialized: %d", mgr.initialized);
    } else {
        NSLog(@"[SceneDelegate] libterracotta not linked, multiplayer disabled");
    }

    // 监听主题切换通知（设置页"外观模式"切换时实时应用，无需重启）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyUITheme:)
                                                 name:@"UIThemeChanged"
                                               object:nil];
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
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"UIThemeChanged" object:nil];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // 横屏几何更新失败兜底（修复 Bug 1：启动1.17及以上时崩溃）
    //
    // iOS 16+ 在 willConnectToSession 阶段调用 requestGeometryUpdateWithPreferences
    // 可能失败（error code=101，窗口场景尚未完全 attach）。
    // 如果首次失败，在 sceneDidBecomeActive（窗口场景已激活）时重试一次。
    // 重试只执行一次，避免无限循环。
    if (@available(iOS 16.0, *)) {
        if (self.geometryUpdateFailed && !self.geometryUpdateRetried) {
            self.geometryUpdateRetried = YES;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            UIWindowSceneGeometryPreferencesIOS *geometryPreferences = [[UIWindowSceneGeometryPreferencesIOS alloc] init];
            geometryPreferences.interfaceOrientations = UIInterfaceOrientationMaskLandscape;
            __weak typeof(self) weakSelf = self;
            [windowScene requestGeometryUpdateWithPreferences:geometryPreferences errorHandler:^(NSError *error) {
                NSLog(@"[SceneDelegate] Geometry retry also failed: %@", error);
                // 重试仍失败，通知系统刷新支持的方向作为最终兜底
                [windowScene setNeedsUpdateOfSupportedInterfaceOrientations];
            }];
            NSLog(@"[SceneDelegate] Retried geometry update after initial failure");
        }
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
