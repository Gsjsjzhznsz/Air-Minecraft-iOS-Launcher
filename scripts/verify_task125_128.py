#!/usr/bin/env python3
"""verify_task125_128.py -- Tasks 125-128（5.1.0 第三轮用户反馈）验证器。

任务对照：
  A. Task125  启动时自动检测更新（NMToast 非侵入提示 + 偏好开关）
  B. Task126  正版登录系统弹窗根治（showDialog window 回收 + toast 化）
  C. Task127  子级面板新拟物基底（NMPanel 单一执法点）
  D. Task128  第三方登录修复（zl2 参照：jar 随包 / 优雅回退 / accountType）
  E. 语法门 + 级联
"""
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PASS, FAIL = 0, 0

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

def rd(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()

root = rd("Natives/LauncherRootViewController.m")
uc = rd("Natives/UpdateChecker.m")
lpvc = rd("Natives/LauncherPreferencesViewController.m")
plp = rd("Natives/PLPreferences.m")
bridge = rd("Natives/ios_uikit_bridge.m")
acc = rd("Natives/AccountListViewController.m")
nav = rd("Natives/LauncherNavigationController.m")
# Task138 重锚：Task137 将 NMToast 迁出 NeomorphKit 至 Natives/ 根
toast = rd("Natives/NMToast.m")
# Task138 重锚：Task137 将 NMPanel 原生化重写为 UIViewController+AMEPanel
panel = rd("Natives/UIViewController+AMEPanel.m")
tp = rd("Natives/authenticator/ThirdPartyAuthenticator.m")
ba = rd("Natives/authenticator/BaseAuthenticator.m")
ms = rd("Natives/authenticator/MicrosoftAuthenticator.m")
lo = rd("Natives/authenticator/LocalAuthenticator.m")
cml = rd("Natives/CMakeLists.txt")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("== A. Task125 启动自动检测更新 ==")
check("A1 NMToast 组件存在（Task137 迁至 Natives/ 根）",
      os.path.exists(os.path.join(REPO, "Natives/NMToast.m")) and
      os.path.exists(os.path.join(REPO, "Natives/NMToast.h")))
check("A2 NMToast 无新建 window（挂 mainWindow，Task126 教训）",
      "UIWindow.mainWindow" in toast and "windowLevel = 1000" not in toast)
check("A3 自动检测一次性守卫 + 偏好开关（general.auto_update_check）",
      "ame125_autoUpdateCheckOnce" in root and
      'general.auto_update_check' in root)
check("A4 非侵入呈现（toast + 查看动作，无 AlertDialog）",
      "NMToast showMessage:msg" in root and "openReleasePage" in root)
check("A5 冷启动延迟 1.5s（避开启动期 UI 竞争）",
      "1.5 * NSEC_PER_SEC" in root)
check("A6 设置行 + 默认值（默认开）",
      '"key": @"auto_update_check"' in lpvc and
      '"auto_update_check": @YES' in plp)
check("A7 l10n 四语言齐备（toast 文案 + 设置 title/detail）",
      all(f'"preference.title.auto_update_check"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          and '"auto_update.toast.view"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          for l in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
check("A8 静默口径（无更新/出错不打扰：hasUpdate 才提示）",
      "if (!info.hasUpdate) return;" in root)

print("== B. Task126 正版登录弹窗根治 ==")
check("B1 showDialog OK 后回收 window（隐藏 + 归还 key window）",
      "w.hidden = YES;" in bridge and "makeKeyAndVisible" in bridge and
      "previousKeyWindow" in bridge)
check("B2 MS 登录成功/状态提示走 NMToast（不再系统弹窗）",
      "NMToast showMessage:" in acc and "ame126_msg" in acc)
check("B3 错误分支保留弹窗（可阅读，且已修回收）",
      acc.find("认证失败：恢复交互并展示错误") > 0)

print("== C. Task127 子面板基底（Task138 重锚：Task137 新拟态退役后的原生化继任形态） ==")
# Task137 按用户指令删除全部新拟态代码，NMPanel 重写为 AMEPanel；
# Task127 的四条语义保证（幂等/透明跳过/深度限界/单一执法点）在继任者
# 中原样保留，断言改钉继任符号。
check("C1 UIViewController+AMEPanel 存在（幂等语义保留）",
      "ame_applySubpanelBaseStyle" in panel and
      "幂等：每个 VC 实例只应用一次" in panel)
check("C2 透明定制面板跳过（背景照片功能不破坏，语义保留）",
      "clearColor" in panel)
check("C3 表格深度限界遍历（不深入 cell，语义保留）",
      "depth > 3" in panel)
check("C4 单一执法点（push + 根面板，语义保留）",
      "pushViewController:(UIViewController *)viewController" in nav and
      "ame_applySubpanelBaseStyle" in nav)
check("C5 CMakeLists 收录继任组件（Natives/NMToast.m + AMEPanel）",
      "NMToast.m" in cml and "UIViewController+AMEPanel.m" in cml)

print("== D. Task128 第三方登录修复（zl2 参照）==")
check("D1 authlib-injector jar 随包（Task132 升级 1.2.8：349681B，sha256 9c7f4343...）",
      os.path.getsize(os.path.join(REPO, "Natives/resources/authlib-injector-1.2.8.jar")) == 349681)
check("D2 bundled 路径解析（NSBundle pathForResource）",
      "bundledAuthlibInjectorPath" in tp and "pathForResource" in tp)
check("D3 ensure 优先包内复制（零网络依赖），在线下载降为回退",
      "Task128: authlib-injector installed from bundled copy" in tp and
      tp.find("bundled copy failed") > tp.find("bundledAuthlibInjectorPath"))
check("D4 启动时 agent 兜底（POJAV_HOME 副本缺失 -> 包内 jar）",
      "using bundled authlib-injector at launch" in tp)
check("D5 accountType 显式标记（thirdparty/microsoft/local 三处写入）",
      '"accountType"] = @"thirdparty"' in tp and
      '"accountType"] = @"microsoft"' in ms and
      '"accountType"] = @"local"' in lo)
check("D6 BaseAuthenticator 判别器 accountType 优先（嗅探回退）",
      "ame128_type" in ba and
      ba.find('isEqualToString:@"thirdparty"') < ba.find('longValue] == 0'))
check("D7 选择回退：refresh 失败仍选中（不再硬阻断）",
      "Task128: refresh failed" in acc and
      "selecting with stale token" in acc and
      "setPrefObject(@\"internal.selected_account\", loadKey)" in acc)
check("D8 会话级已验证标志（重复选择不打 refresh）",
      "ame128_sessionValidated" in acc and "ame128_validatedSet" in acc)
check("D9 过期提示 toast 文案四语言",
      all('"login.3rdparty.stale.message"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          for l in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
check("D10 version.h addendum 记录 Tasks 125-128",
      all(f"Task {n}" in vh for n in [119, 120, 121, 124, 125, 126, 127, 128]))

print("== E. 语法门 + 级联 ==")
def balance(src):
    state = depth = i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if state == 0:
            if c == '"': state = 1
            elif c == '/' and i + 1 < n and src[i+1] == '/': state = 3
            elif c == '/' and i + 1 < n and src[i+1] == '*': state = 4
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
        elif state == 1:
            if c == '\\': i += 1
            elif c == '"': state = 0
        elif state == 3:
            if c == '\n': state = 0
        elif state == 4:
            if c == '*' and i + 1 < n and src[i+1] == '/': state = 0; i += 1
        i += 1
    return depth
TOUCHED = ["Natives/NMToast.m", "Natives/UIViewController+AMEPanel.m",
           "Natives/LauncherRootViewController.m", "Natives/LauncherNavigationController.m",
           "Natives/ios_uikit_bridge.m", "Natives/AccountListViewController.m",
           "Natives/authenticator/ThirdPartyAuthenticator.m", "Natives/authenticator/BaseAuthenticator.m",
           "Natives/authenticator/MicrosoftAuthenticator.m", "Natives/authenticator/LocalAuthenticator.m",
           "Natives/LauncherPreferencesViewController.m", "Natives/PLPreferences.m"]
for p in TOUCHED:
    check(f"E1 {os.path.basename(p)} 大括号平衡", balance(rd(p)) == 0)
for p in TOUCHED:
    cur = rd(p)
    head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{p}"],
                          capture_output=True, text=True).stdout
    ok = all(cur.count(a) - cur.count(b) == head.count(a) - head.count(b)
             for a, b in [("{", "}"), ("(", ")"), ("[", "]")])
    check(f"E2 {os.path.basename(p)} 裸括号 delta 与 HEAD 一致", ok)
# mgl_fsr GL 守卫全覆盖（774fa7871 CI 失败教训：GL_TEXTURE_2D 裸用）
fsr = rd("Natives/ctxbridges/mgl_fsr.mm")
used = set(re.findall(r'\bGL_[A-Z0-9_]+\b', re.sub(r'/\*.*?\*/', '', re.sub(r'//[^\n]*', '', fsr))))
guarded = set(re.findall(r'#ifndef\s+(GL_[A-Z0-9_]+)', fsr))
check("E3 mgl_fsr.mm 代码用 GL 枚举全部有 #ifndef 守卫（CI 教训）",
      not (used - guarded), f"unguarded={sorted(used - guarded)}")
r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/verify_task119_124.py")],
                   capture_output=True, text=True)
check("E4 级联 verify_task119_124 ALL PASS", r.returncode == 0,
      r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr[:200])

print(f"\n==== RESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}) ====")
sys.exit(0 if FAIL == 0 else 1)
