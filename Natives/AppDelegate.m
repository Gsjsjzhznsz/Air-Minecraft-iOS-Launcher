#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "AFNetworking.h"
#import "MinecraftResourceDownloadTask.h"
#import "LauncherPreferences.h"

// SurfaceViewController
extern dispatch_group_t fatalExitGroup;

@interface AppDelegate ()
@property (nonatomic, copy) void (^backgroundURLSessionCompletionHandler)(void);
@end

@implementation AppDelegate

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // 一次性迁移旧版全局下载源偏好到分类镜像策略键（幂等，早于任何 UI 读取偏好）
    migrateDownloadSourcePreferences();

    // Task 144：旧包名并存检测（仅日志取证，零 UI 噪音）。
    // 用户报告设备上出现"2 个一模一样的版本"：commit 9659740a（2026-07-24）
    // 把包名从 org.angelauramcremastered.amethyst 改为 com.air-devs.air，
    // iOS 按包名视为两个不同 App —— 新 IPA 不再覆盖旧装，主屏并存双图标
    // （旧图标 = 迁移前的旧代码 + 旧偏好容器，行为自然不同）。此非本仓库
    // bug，检测到旧包时打日志便于装机日志分诊；删除旧图标即消除重复。
    {
        Class ame144_lsw = NSClassFromString(@"LSApplicationWorkspace");
        if (ame144_lsw) {
            @try {
                id ame144_ws = [(id)ame144_lsw performSelector:NSSelectorFromString(@"defaultWorkspace")];
                SEL ame144_sel = NSSelectorFromString(@"applicationIsInstalled:");
                if (ame144_ws && [ame144_ws respondsToSelector:ame144_sel]) {
                    BOOL ame144_old = (BOOL)[ame144_ws performSelector:ame144_sel
                                                            withObject:@"org.angelauramcremastered.amethyst"];
                    if (ame144_old) {
                        NSLog(@"[Amethyst] Task144: legacy bundle 'org.angelauramcremastered.amethyst' (pre-rename AngelAuraAmethyst) still installed alongside this app -- two identical-looking home-screen icons; the OLD icon can be deleted (its container is separate from this app's data)");
                    }
                }
            } @catch (NSException *ame144_e) {
                NSLog(@"[Amethyst] Task144: legacy bundle detection unavailable (%@)", ame144_e.name);
            }
        }
    }
    // Task 77：一次性迁移默认触控布局出厂值 default.json -> custom.json
    //（幂等，哨兵键保证只执行一次；用户自选的其他布局不受影响）
    migrateDefaultControlPref();
    // Task 130：一次性治愈 MobileGlues 性能默认值（v5.1.0 持久化的旧默认
    // 0/32 压制 Task129d 新默认 1/128；幂等，仅匹配旧默认值，自选值不动）
    ame130_migrateMgPerfDefaults();
    // Called when a new scene session is being created.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    if (fatalExitGroup != nil) {
        dispatch_group_leave(fatalExitGroup);
        fatalExitGroup = nil;
    }
}

#pragma mark - Background URL Session

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler {
    if (![identifier isEqualToString:kMinecraftResourceDownloadBackgroundSessionIdentifier]) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }

    self.backgroundURLSessionCompletionHandler = completionHandler;

    AFURLSessionManager *manager = [MinecraftResourceDownloadTask sharedBackgroundSessionManager];
    __weak typeof(self) weakSelf = self;
    [manager setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession *session) {
        if (weakSelf.backgroundURLSessionCompletionHandler) {
            weakSelf.backgroundURLSessionCompletionHandler();
            weakSelf.backgroundURLSessionCompletionHandler = nil;
        }
    }];
}

#pragma mark - Orientation Support

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    // Force landscape only
    return UIInterfaceOrientationMaskLandscape;
}

@end
