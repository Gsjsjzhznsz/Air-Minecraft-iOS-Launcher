#import "authenticator/BaseAuthenticator.h"
#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherSplitViewController.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"

#include <objc/runtime.h>
#include "ios_uikit_bridge.h"
#include "utils.h"

void internal_showDialog(NSString* title, NSString* message) {
    NSLog(@"[UI] Dialog shown: %@: %@", title, message);

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    //text.dataDetectorTypes = UIDataDetectorTypeLink;
    // Task 126：OK 后必须回收承载 window。旧实现 handler 为 nil——alert 消失
    // 但 level-1000 的新 window 泄漏在场并占着 key window，用户被迫"手动删
    // 系统弹窗"（5.1.0 实测反馈：正版登录提示弹窗关不掉）。修复：记下原
    // key window，OK 时隐藏弹窗 window 并把 key 交还原窗口。
    UIWindow *previousKeyWindow = UIWindow.mainWindow;
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        UIWindow *w = objc_getAssociatedObject(alert, @selector(alertWindow));
        if (w) {
            w.hidden = YES;
            if (previousKeyWindow && previousKeyWindow != w) {
                [previousKeyWindow makeKeyAndVisible];
            }
        }
    }];
    [alert addAction:okAction];

    UIWindow *alertWindow = [[UIWindow alloc] initWithWindowScene:UIWindow.mainWindow.windowScene];
    alertWindow.frame = UIScreen.mainScreen.bounds;
    alertWindow.rootViewController = [UIViewController new];
    alertWindow.windowLevel = 1000;
    [alertWindow makeKeyAndVisible];
    objc_setAssociatedObject(alert, @selector(alertWindow), alertWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [alertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

void showDialog(NSString* title, NSString* message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        internal_showDialog(title, message);
    });
}

JNIEXPORT void JNICALL Java_net_kdt_pojavlaunch_uikit_UIKit_showError(JNIEnv* env, jclass clazz, jstring title, jstring message, jboolean exitIfOk) {
    const char *title_c = (*env)->GetStringUTFChars(env, title, 0);
    const char *message_c = (*env)->GetStringUTFChars(env, message, 0);
    NSString *title_o = @(title_c);
    NSString *message_o = @(message_c);
    (*env)->ReleaseStringUTFChars(env, title, title_c);
    (*env)->ReleaseStringUTFChars(env, message, message_c);

    if (SurfaceViewController.isRunning) {
        NSLog(@"%@\n%@", title_o, message_o);
        [PLLogOutputView handleExitCode:1];
        return;
    }

dispatch_async(dispatch_get_main_queue(), ^{

    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:title_o message:message_o
        preferredStyle:UIAlertControllerStyleAlert];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentLeft;

    NSMutableAttributedString *atrStr = [[NSMutableAttributedString alloc] initWithString:message_o attributes:@{NSParagraphStyleAttributeName:style,NSFontAttributeName:[UIFont systemFontOfSize:13.0]}];

    [alert setValue:atrStr forKey:@"attributedMessage"];

    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            if (exitIfOk == JNI_TRUE) {
                exit(-1);
            }
        }];
    [alert addAction:okAction];
    
    UIAlertAction* copyAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            UIPasteboard.generalPasteboard.string = message_o;
            if (exitIfOk == JNI_TRUE) {
                exit(-1);
            }
        }];
    [alert addAction:copyAction];
    
    [currentVC() presentViewController:alert animated:YES completion:nil];
});
}

jstring UIKit_accessClipboard(JNIEnv* env, jint action, jbyteArray copySrc) {
    if (action == CLIPBOARD_PASTE) {
        // paste request
        if (UIPasteboard.generalPasteboard.hasStrings) {
            return (*env)->NewStringUTF(env, [UIPasteboard.generalPasteboard.string UTF8String]);
        } else {
            return (*env)->NewStringUTF(env, "");
        }
    } else if (action == CLIPBOARD_COPY) {
        // copy request
        const char* copySrcC = (*env)->GetByteArrayElements(env, copySrc, 0);
        if (copySrcC) {
            UIPasteboard.generalPasteboard.string = @(copySrcC);
            (*env)->ReleaseByteArrayElements(env, copySrc, copySrcC, 0);
        }
        return NULL;
    } else {
        // unknown request
        NSLog(@"Warning: unknown clipboard action: %x", action);
        return NULL;
    }
}

// Task172：版本级 TouchController 自动配置（用户指令"顺便自动配置设置
//（udp 模式，屏蔽控件）"）。当前 profile 的 touchController 键为 YES 时，
// 启动前把全局三项自动配好：control.mod_touch_enable=YES、
// control.mod_touch_mode=1（UDP）、control.mod_touch_hide_controls=YES
//（Task140 语义：只隐藏启动器自身控件层，模组自己的虚拟按钮保留）。
// 键缺失/NO 时【不碰】全局设置（用户可能在全局 TouchController 页单独
// 配置过，关闭实例开关不应破坏它）。SurfaceViewController 的
// ame139_modControlsHidden 与 UDP 触摸转发在游戏进程内实时读这些键，
// 此处只需在换根 VC 前落值。
static void ame172_applyProfileTouchController(void) {
    @autoreleasepool {
        NSString *profName = PLProfiles.current.selectedProfileName;
        NSDictionary *prof = profName ? PLProfiles.current.profiles[profName] : nil;
        BOOL on = [prof isKindOfClass:NSDictionary.class] && [prof[@"touchController"] boolValue];
        if (on) {
            setPrefBool(@"control.mod_touch_enable", YES);
            setPrefObject(@"control.mod_touch_mode", @1);  // UDP 协议
            setPrefBool(@"control.mod_touch_hide_controls", YES);
            NSLog(@"[TouchController] Task172 profile auto-config applied for '%@' (enable=1 mode=UDP hideControls=1)",
                  profName);
        } else {
            NSLog(@"[TouchController] Task172 profile '%@' TouchController off -- global settings untouched",
                  profName);
        }
    }
}

void UIKit_launchMinecraftSurfaceVC(UIWindow* window, NSDictionary* metadata) {
    // Leave this pref, might be useful later for launching with Quick Actions/Shortcuts/URL Scheme
    //setPreference(@"internal_launch_on_boot", getPreference(@"restart_before_launch"));
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    // selected_account 存储 accountId（唯一标识），确保重启后能按 accountId 恢复登录状态
    setPrefObject(@"internal.selected_account", currentAuth.authData[@"accountId"]);
    // Task172：版本级 TouchController 自动配置（必须在 SurfaceViewController
    // 读控件/触摸偏好之前落值——本函数是两条启动路径共用的换根入口）
    ame172_applyProfileTouchController();
    dispatch_async(dispatch_get_main_queue(), ^{
        tmpRootVC = window.rootViewController;
        [UIView animateWithDuration:0.2 animations:^{
            window.alpha = 0;
        } completion:^(BOOL b){
            [window resignKeyWindow];
            window.alpha = 1;
            window.rootViewController = [[SurfaceViewController alloc] initWithMetadata:metadata];
            [window makeKeyAndVisible];
        }];
    });
}

void UIKit_returnToSplitView() {
    // Researching memory-safe ways to return from SurfaceViewController to the split view
    // so that the app doesn't close when quitting the game (similar behaviour to Android)
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIWindow.mainWindow;

        // Return from JavaGUIViewController
        if ([window.rootViewController isKindOfClass:LauncherSplitViewController.class]) {
            [currentVC() dismissViewControllerAnimated:YES completion:nil];
            return;
        }

        // Return from SurfaceViewController
        [UIView animateWithDuration:0.2 animations:^{
            window.alpha = 0;
        } completion:^(BOOL b){
            [window resignKeyWindow];
            window.alpha = 1;
            if (tmpRootVC) {
                window.rootViewController = tmpRootVC;
                tmpRootVC = nil;
            } else {
                window.rootViewController = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
            }
            [window makeKeyAndVisible];
        }];
    });
}

void launchInitialViewController(UIWindow *window) {
    window.rootViewController = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
#if 0
    if (getPrefBool(@"internal.internal_launch_on_boot")) {
        window.rootViewController = [[SurfaceViewController alloc] init];
    } else {
        window.rootViewController = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
    }
#endif
}
