#!/usr/bin/env python3
"""Task172 验证器：六症状修复的代码锚点 + 日志取证 + 行为镜像。

A. 日志取证（git 钉 760c07c 上传的三个日志）
B. ANGLE 镜像链（sdl3_hook.m）
C. JIT 三文件（断言 + 存活性复查 + 重挂助手）
D. 键盘路由（sdl3_hook.m + SurfaceViewController.m）
E. 头像（AvatarManager.m + LauncherNewsViewController.m）
F. TouchController 版本级（ProfileSettingsViewController.m + ios_uikit_bridge.m）
G. CF 5xx 重试（CurseForgeAPI.m）
H. 文档（version.h + announcements）
I. 级联（171 验证器关键锚不回退）
"""
import os, re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
results = []

def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))

def read(p):
    return open(f"{REPO}/{p}", encoding="utf-8", errors="replace").read()

def git_show(rev, p):
    return subprocess.run(["git", "-C", REPO, "show", f"{rev}:{p}"],
                          capture_output=True, text=True).stdout

# ---------- A. 日志取证 ----------
log_new = git_show("760c07c", "latestlog.txt")          # JIT 卡死会话
log_angle = git_show("760c07c", "latestlog.old")         # ANGLE 崩溃会话
log_mg = git_show("760c07c", "latestlog.old.txt")        # mg 多人会话（键盘证据）

check("A1 ANGLE 会话桥接已接管但仍 mismatch（Task171 修复未根治的证据链）",
      "hooked SDL_GL_LoadLibrary -> EGL bridge" in log_angle
      and "pojavInitOpenGLForSDL3()=0 (EGL bridge)" in log_angle
      and "glGetError mismatch" in log_angle
      and "No GLCapabilities" in log_angle)
check("A2 ANGLE 会话零 eglGetProcAddress 导出证据（libtinygl4angle 路径 + provider NOLOAD）",
      "libtinygl4angle.dylib" in log_angle
      and "renderer handle <- LWJGL provider path (NOLOAD)" in log_angle)
check("A3 JIT 卡死会话：0s 心跳后再无心跳/无超时（进程冻结证据）",
      "[JIT] Task169 isJITEnabled: still waiting after 0s" in log_new
      and "still waiting after 10s" not in log_new
      and "TIMED OUT" not in log_new)
check("A4 JIT 卡死会话：后台进入后再无前台恢复（BingWallpaper 只在 WillEnterForeground 同步）",
      "App entered background" in log_new.split("invokeAfterJITEnabled")[-1]
      and "Task151 metadata synced" not in log_new.split("invokeAfterJITEnabled")[-1])
check("A5 成功会话对照组：JIT 等待后紧接前台恢复 + SurfaceVC 生命周期",
      "still waiting after 0s" in log_angle
      and "Task151 metadata synced" in log_angle.split("still waiting after 0s")[-1]
      and "SurfaceViewController] FPS counter setup" in log_angle)
check("A6 键盘证据：✎ 每次都是 becomeFirstResponder=1（字段反复丢 FR）且零 re-arm 触发",
      log_mg.count("Keyboard widget: becomeFirstResponder=1") >= 4
      and "Keyboard widget: dismissing" not in log_mg
      and "keyboard auto re-arm" not in log_mg)
check("A7 键盘证据：字符全部经启动器字段（Task82 路径）到达",
      "Task82 SDL text input #" in log_mg)
check("A8 CF 502 证据：classId=4471 请求 502 后用户手动重试成功",
      "classId=4471" in log_new and "502 Bad Gateway" in log_new
      and log_new.count("classId=4471") >= 2)

# ---------- B. ANGLE 镜像链 ----------
sdl = read("Natives/sdl3_hook.m")
check("B1 镜像链只查 OSMesaGetProcAddress（eglGetProcAddress 退役）",
      'g_lwjglMirrorGPA = dlsym(h, "OSMesaGetProcAddress");' in sdl
      and 'dlsym(h, "eglGetProcAddress")' not in sdl)
check("B2 Task172 取证日志锚点",
      "Task172 GL$1 mirror: OSMesaGetProcAddress=" in sdl)
check("B3 反编译依据注释（GL$1 macOS 分支 switch 无 macOS case）",
      "case LINUX: glXGetProcAddress / ARB" in sdl
      and "从不查询 eglGetProcAddress" in sdl)
check("B4 dlsym 回退保持（对齐 GL$1 library.getFunctionAddress）",
      "// 对齐 GL$1 的回退：dlsym(lib, name)" in sdl)

# ---------- C. JIT 三文件 ----------
for f, tag in [("Natives/LauncherRightPanelViewController.m", "RightPanel"),
               ("Natives/LauncherNavigationController.m", "NavCtrl"),
               ("Natives/DownloadViewController.m", "DownloadVC")]:
    src = read(f)
    check(f"C1-{tag} 后台任务断言（begin/endBackgroundTask 成对）",
          src.count("beginBackgroundTaskWithName:@\"ame172-jit-wait\"") == 1
          and src.count("beginBackgroundTaskWithName:@\"ame172-jit26-reattach\"") == 1
          and src.count("endBackgroundTask:ame172_bgt") >= 2)
    check(f"C2-{tag} 等待成功后的 TXM 存活性复查",
          "Task172 wait satisfied but JIT26 debugger is gone" in src
          and src.count("ame172_reattachJIT26ThenLaunch") >= 3)  # 分支调用 + 复查调用 + 定义
    check(f"C3-{tag} 重挂助手：前台等待 + 10s 兜底 + 双 nil 防护",
          "UIApplicationDidBecomeActiveNotification" in src
          and src.count("ame172_obs = nil") == 3)
    check(f"C4-{tag} stikjit:// 重挂日志锚点",
          "Task172 stikjit:// re-attach fired" in src)

# ---------- D. 键盘路由 ----------
check("D1 Start 钩子真实调用后派发通知",
      "AME172_SDLStartTextInput" in sdl
      and sdl.count("postNotificationName:@\"AME172_SDLStartTextInput\"") == 2)
check("D2 Stop 钩子派发收起通知",
      'postNotificationName:@"AME172_SDLStopTextInput"' in sdl)
check("D3 病历注释（SDL UIKit textField 抢占 + 投递链不可靠）",
      "抢走启动器字段" in sdl and "稳赢 first responder 竞争" in sdl)
svc = read("Natives/SurfaceViewController.m")
check("D4 SurfaceVC 双观察者注册 + dealloc 清理",
      svc.count("AME172_SDLStartTextInput") == 2
      and svc.count("AME172_SDLStopTextInput") == 2)
check("D5 路由处理器：已是 FR 不动 + Task171 哨兵同序 + re-arm",
      "ame172_sdlStartTextInput:(NSNotification" in svc
      and "isFirstResponder) return;" in svc
      and svc.count("self.inputTextField.text = @\" \";") >= 3)
check("D6 Stop 处理器：代数计数器递增（作废在飞重挂）",
      "ame172_sdlStopTextInput:(NSNotification" in svc
      and "ame171_keyboardDismissGeneration++;" in svc.split("ame172_sdlStopTextInput")[-1])

# ---------- E. 头像 ----------
am = read("Natives/AvatarManager.m")
check("E1 失败路径回主线程",
      am.count("dispatch_async(dispatch_get_main_queue(), ^{\n                if (completion) completion(nil);\n            });") >= 1
      or ("if (completion) completion(nil);" in am and am.count("dispatch_async(dispatch_get_main_queue()") >= 3))
check("E2 坏 URL 路径回主线程",
      "坏 URL 路径也必须回主线程" in am)
news = read("Natives/LauncherNewsViewController.m")
check("E3 updateSkinDisplay 四分支取证日志",
      all(k in news for k in ["branch: AvatarManager local hit",
                              "branch: session cache hit",
                              "branch: network fetch started",
                              "auth present but profilePicURL is MISSING"]))
check("E4 直刷 helper 取证（可见卡计数 + 图片尺寸 + nil 分支）",
      "Task172 direct-sync:" in news and "sync skipped: currentAvatar is nil" in news)
check("E5 viewDidAppear 延迟补刷（0.35s）",
      "0.35 * NSEC_PER_SEC" in news and news.count("ame171_syncVisibleProfileAvatar") >= 4)

# ---------- F. TouchController 版本级 ----------
ps = read("Natives/ProfileSettingsViewController.m")
check("F1 组件安装区新增行（Task173 重锚：开关式高级区行已迁往组件区）",
      '@[@"Fabric API", @"Sodium + Iris Shaders", @"TouchController", @"OptiFine"]' in ps)
check("F2 属性 + 读写（loadSettings boolValue / saveSettings YES+删键）",
      "BOOL touchControllerEnabled;" in ps
      and 'self.touchControllerEnabled = [self.profile[@"touchController"] boolValue];' in ps
      and 'existing[@"touchController"] = @YES;' in ps
      and '[existing removeObjectForKey:@"touchController"];' in ps)
check("F3 行渲染 + 安装流程（Task173 重锚：Sodium 同款组件，不再有开关式 picker）",
      'systemImageNamed:@"hand.tap.fill"' in ps
      and "installTouchControllerStandalone" in ps
      and 'exactTitle:@"touchcontroller"' in ps)
check("F4 复用既有 l10n 键（Task173 重锚：udp 键沿用，disabled 键随开关退役）",
      'localize(@"preference.touchcontroller.mode.udp", nil)' in ps)
bridge = read("Natives/ios_uikit_bridge.m")
check("F5 启动时自动配置（换根前调用 + 三键落值 + 关不碰全局）",
      "ame172_applyProfileTouchController();" in bridge
      and 'setPrefObject(@"control.mod_touch_mode", @1)' in bridge
      and 'setPrefBool(@"control.mod_touch_hide_controls", YES)' in bridge
      and "global settings untouched" in bridge)
check("F6 PLProfiles 导入补齐",
      '#import "PLProfiles.h"' in bridge)

# ---------- G. CF 5xx 重试 ----------
cf = read("Natives/installer/modpack/CurseForgeAPI.m")
check("G1 5xx 判定助手（>= 500，4xx 不重试）",
      "ame172_isTransientServerStatus" in cf
      and "statusCode >= 500" in cf)
check("G2 异步搜索两分支重试（空体 + JSON 解析失败）",
      cf.count("ame172_retrySearchRequest:request") == 2)
check("G3 重试上限 attempt < 2 + 2s 退避",
      "attempt < 2" in cf and "2.0 * NSEC_PER_SEC" in cf)
check("G4 同步 getEndpoint failure 分支 5xx 包装 code 543（既有重试循环接管）",
      "getEndpoint mirror %ld server error" in cf and "code:543" in cf)
check("G5 CRLF 保持",
      open(f"{REPO}/Natives/installer/modpack/CurseForgeAPI.m","rb").read().count(b"\r\n") > 1000)

# ---------- H. 文档 ----------
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("H1 version.h REVISION 17 addendum (Task 172)",
      "REVISION 17 addendum (Amethyst Task 172, no bump)" in vh
      and "six-symptom round" in vh)
import os
import json
anns = json.load(open(f"{REPO}/announcements.json"))["announcements"]
# Task175 重锚：task175@2 插入，task172 顺延 anns[5] -> anns[6]。
check("H2 announcements task172@6（task175/174/双 task173 后；server-pin/task169 钉 0/1）",
      anns[6].get("id") == "task172-six-fixes-2026-09-25"
      and anns[0].get("id") == "server-recommend-2026-09-24"
      and "task169" in anns[1].get("id", ""))

# ---------- I. 级联（Task171 关键锚不回退） ----------
sdl_head = git_show("HEAD", "Natives/sdl3_hook.m")
check("I1 Task171 ANGLE 接管列表不回退",
      'strstr(renderer, "libtinygl4angle") != NULL' in sdl
      and 'AMETHYST_ANGLE_GL_BRIDGE' in sdl)
check("I2 Task171 键盘哨兵机制不回退（become 前写哨兵 + re-arm 仍在）",
      "ame171_armKeyboardRecheck" in svc and "Task171" in svc)
check("I3 Task169 有界等待不回退（120s + 心跳）",
      "120.0, @\"isJITEnabled\"" in read("Natives/LauncherRightPanelViewController.m"))

# ---------- 汇总 ----------
fails = [n for n, ok, _ in results if not ok]
print(f"\n===== {len(results)-len(fails)}/{len(results)} PASS =====")
if fails:
    print("FAILED:", *fails, sep="\n  - ")
    sys.exit(1)
