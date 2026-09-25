#pragma once
#import <UIKit/UIKit.h>
#include "jni.h"

#define CLIPBOARD_COPY 2000
#define CLIPBOARD_PASTE 2001

UIViewController* tmpRootVC;

void showDialog(NSString* title, NSString* message);
// Task173：gJvmUsedInProcess（安装器占用进程内 JVM）出路弹窗——「重启并启动」
// 写 internal.autolaunch_profile 后 exit(0)，下次冷启由 RightPanel 自动启动。
void ame173_showJvmUsedRestartDialog(NSString *profileName);
jstring UIKit_accessClipboard(JNIEnv* env, jint action, jstring copySrc);
void UIKit_launchMinecraftSurfaceVC(UIWindow *window, NSDictionary *metadata);
void UIKit_returnToSplitView();
void launchInitialViewController(UIWindow *window);

void AWTInputBridge_sendKey(int keycode);
