#!/usr/bin/env python3
"""
Task 91 验证器：双主题主文字色统一（浅 #222222 / 深 #EEEEEE）+ 内存标识根因修复
（entitlements.sideload.xml 预写内核权限移除）+ JIT 路径纠正与 SIGTRAP 安全网

背景（用户实测反馈）：
  1. 部分 UI 基于深色模式设计、字体写死白色——Task89 强制新拟态纯色底后，浅色
     模式下这些文字不可读。用户要求：所有字体（彩色语义色除外）浅色模式统一
     #222222，深色模式 #EEEEEE。
  2. 内存状态标识仍显示"全开启"。MeloNX 源码复核（EntitlementChecker.swift）：
     其检测与仓库一致（SecTaskCopyValueForEntitlement），并非更聪明的方案——
     真正根因是 CI 侧载工件预签的 entitlements.sideload.xml 预写了两项 kernel
     entitlement，签名里必然携带。修复 = 从 sideload 模板移除（TrollStore 工件
     保留，其 entitlement 真实生效），标识逻辑（签名+描述文件双确认）不变。
  3. 开启 JIT 后闪退。根因 A：jb.pmap_cs.custom_trust 假标记（sideload 模板同样
     预写）使普通侧载误判 TrollStore → 走 apple-magnifier:// 死路，JIT 无法自动
     开启。根因 B：TXM 设备 brk #0x69 无人应答时 JIT26CreateRegionLegacy 裸函数
     SIGTRAP 必死（代码注释记载的致命点）。修复 = isTrollStoreInstall() 双确认 +
     SIGTRAP 安全网（无应答时优雅报错而非闪退）。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK91_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_objc(src):
    """字符串感知剥离：去 @"..." 字面量与注释，保留结构（兼容 CRLF）。"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == '\\' else 1
            i += 1
            out.append('""')
        elif src.startswith("//", i):
            while i < n and src[i] != '\n':
                i += 1
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def balanced(src):
    counts = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    for ch in src:
        if ch in counts:
            counts[ch] += 1
        elif ch in pairs:
            counts[pairs[ch]] -= 1
            if counts[pairs[ch]] < 0:
                return False
    return all(v == 0 for v in counts.values())


print("=" * 72)
print("C1. NMTheme 主文字色精确值：浅 #222222 / 深 #EEEEEE")
print("=" * 72)
nm = read("Natives/NeomorphKit/NMTheme.m")
check("label 深色 0xEE/0xEE/0xEE", "0xEE / 255.0" in nm)
check("label 浅色 0x22/0x22/0x22", "0x22 / 255.0" in nm)
check("Task91 标记注释存在", "Task91" in nm)
check("NMTheme.m 花括号配平", balanced(strip_objc(nm)))

print()
print("=" * 72)
print("C2. 字体清扫：自适应表面上写死白色 → nm_label / nm_secondaryLabel")
print("=" * 72)
# 改造文件：全部原白字站点已主题化（文件内不应再有 text 白色直写）
changed_to_theme = {
    "Natives/AccountLoginViewController.m": 0,
    "Natives/LauncherPrefManageJREViewController.m": 0,
    "Natives/LauncherPreferencesViewController.m": 0,
    "Natives/BackgroundSettingsViewController.m": 0,
    "Natives/MultiplayerViewController.m": 0,
    "Natives/VersionManagerViewController.m": 2,  # isolatedBadge/countBadge 彩色底有意保留
    "Natives/CustomControlsViewController.m": 0,
}
for path, allowed in changed_to_theme.items():
    src = read(path)
    plain = re.findall(r"textColor(?:\[?\(?)?\s*=\s*\[?UIColor\s+whiteColor\]?", src)
    check(f"{os.path.basename(path)} 文字白色直写清零", len(plain) == allowed, str(plain[:3]))
    check(f"{os.path.basename(path)} 引入 NMTheme",
          '#import "NeomorphKit/NMTheme.h"' in src)
    check(f"{os.path.basename(path)} 花括号配平", balanced(strip_objc(src)))

# 重点文件的具体改造点
al = read("Natives/AccountLoginViewController.m")
check("登录页标题/副标题/卡片标题/描述四处主题化",
      al.count("[NMTheme nm_label]") >= 2 and al.count("[NMTheme nm_secondaryLabel]") >= 2)
mp = read("Natives/MultiplayerViewController.m")
check("联机页 cell 文字全部主题化（含 CRLF 文件）",
      "[NMTheme nm_label]; // Task91" in mp and mp.count("// Task91") >= 15)
vp = read("Natives/LauncherPreferencesViewController.m")
check("偏好页 cell/textField/label/header 四处主题化", vp.count("[NMTheme nm_") >= 5)
check("偏好页 textField 底色同步主题化（nm_surfaceRaised）",
      "textField.backgroundColor = [NMTheme nm_surfaceRaised];" in vp)

# 保留项：彩色底/游戏内/终端等场景的白字必须原样保留
keep_checks = [
    ("Natives/LauncherRightPanelViewController.m", "self.launchButton setTitleColor:[UIColor whiteColor]", None),
    ("Natives/VersionCardCell.m", "self.typeLabel.textColor = [UIColor whiteColor];", None),
    ("Natives/VersionManagerViewController.m", "self.isolatedBadge.textColor = [UIColor whiteColor];", None),
    ("Natives/GameMenuOverlayView.m", "self.statsLabel.textColor = [UIColor whiteColor];", None),
    ("Natives/PLLogOutputView.m", "cell.textLabel.textColor = UIColor.whiteColor;", None),
    ("Natives/CurseForgeAPIKeyViewController.m", "return [UIColor whiteColor];", None),
    ("Natives/DownloadViewController.m", "label.textColor = [UIColor whiteColor];", None),
]
for path, needle, _ in keep_checks:
    check(f"保留（彩色底/游戏内/终端）: {os.path.basename(path)}:{needle[:28]}", needle in read(path))

print()
print("=" * 72)
print("C3. JIT 路径纠正：isTrollStoreInstall 双确认")
print("=" * 72)
utils_m = read("Natives/utils.m")
utils_h = read("Natives/utils.h")
check("isTrollStoreInstall 实现（entitlement AND _TrollStore 目录）",
      "BOOL isTrollStoreInstall(void) {" in utils_m
      and 'stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath' in utils_m
      and "access(tsPath.UTF8String, F_OK) == 0" in utils_m)
check("isTrollStoreInstall 在 utils.h 声明", "BOOL isTrollStoreInstall(void);" in utils_h)
check("实现内先做 entitlement 快速否决",
      re.search(r"isTrollStoreInstall\(void\) \{\s*\n\s*if \(!getEntitlementValue\(@\"jb\.pmap_cs\.custom_trust\"\)\) return NO;", utils_m))

for path in ["Natives/LauncherNavigationController.m", "Natives/DownloadViewController.m",
             "Natives/LauncherRightPanelViewController.m"]:
    src = read(path)
    check(f"{os.path.basename(path)} hasTrollStoreJIT 双确认",
          'getEntitlementValue(@"jb.pmap_cs.custom_trust") && isTrollStoreInstall()' in src)
    check(f"{os.path.basename(path)} 花括号配平", balanced(strip_objc(src)))

print()
print("=" * 72)
print("C4. SIGTRAP 安全网：brk 无应答时优雅报错而非闪退")
print("=" * 72)
check("JIT26CreateRegionLegacySafe 实现存在", "void* JIT26CreateRegionLegacySafe(size_t len) {" in utils_m)
check("sigsetjmp/siglongjmp 成对使用",
      "sigsetjmp(g_jit26TrapEnv, 1)" in utils_m and "siglongjmp(g_jit26TrapEnv, 1)" in utils_m)
check("sigaction 保存并恢复旧处理器", "sigaction(SIGTRAP, &sa, &oldsa);" in utils_m
      and "sigaction(SIGTRAP, &oldsa, NULL);" in utils_m)
check("非安全网窗口的 SIGTRAP 恢复默认语义（不吞异常）",
      "signal(sig, SIG_DFL);" in utils_m and "raise(sig);" in utils_m)
check("volatile sig_atomic_t 武器位", "volatile sig_atomic_t g_jit26TrapArmed" in utils_m)
check("utils.h 声明 Safe 包装", "void* JIT26CreateRegionLegacySafe(size_t len);" in utils_h)

jl = read("Natives/JavaLauncher.m")
check("launchJVM 调用点改用 Safe 包装", "JIT26CreateRegionLegacySafe(getpagesize())" in jl)
check("裸函数直调在 JavaLauncher 已清零",
      "JIT26CreateRegionLegacy(getpagesize())" not in jl)
check("两处 NULL 分支均存在（launchJVM + headless）", jl.count("if (!result) {") >= 2)
check("NULL 分支走 i18n_str_jit26_not_ready 报错", "i18n_str_jit26_not_ready" in jl)
check("JavaLauncher.m 花括号配平", balanced(strip_objc(jl)))

print()
print("=" * 72)
print("C5. 根因修复：entitlements.sideload.xml 预写内核权限移除")
print("=" * 72)
sl = read("entitlements.sideload.xml")
check("increased-memory-limit 已从 sideload 模板移除",
      "<key>com.apple.developer.kernel.increased-memory-limit</key>" not in sl)
check("extended-virtual-addressing 已从 sideload 模板移除",
      "<key>com.apple.developer.kernel.extended-virtual-addressing</key>" not in sl)
check("memorystatus 保留（TrollStore jetsam 路径仍需要）", "com.apple.private.memorystatus" in sl)
check("pmap_cs 标记保留（由运行时 isTrollStoreInstall 把关）", "jb.pmap_cs.custom_trust" in sl)
check("Task91 说明注释存在", "Task91" in sl)
ts = read("entitlements.trollstore.xml")
check("TrollStore 模板保留两项（真实生效场景）",
      "increased-memory-limit" in ts and "extended-virtual-addressing" in ts)
cs = read("entitlements.codesign.xml")
check("开发者签名模板保留两项（描述文件背书场景）",
      "increased-memory-limit" in cs and "extended-virtual-addressing" in cs)

print()
print("=" * 72)
print("C6. 内存标识检测——Task93 已移除双确认，回归签名口径（与启动日志同源）")
print("=" * 72)
check("Task93：getEffectiveEntitlementValue 已整体移除（用户要求抛弃双确认）",
      "BOOL getEffectiveEntitlementValue(NSString *key) {" not in utils_m)
check("SecTask 检测仍在（MeloNX EntitlementChecker 同款机制）",
      "SecTaskCopyValueForEntitlement(secTask, key, nil)" in utils_m)
rp = read("Natives/LauncherRightPanelViewController.m")
check("Task93：内存标识改回签名口径 getEntitlementValue",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2)

print()
print("=" * 72)
print("C7. i18n：i18n_str_jit26_not_ready × 5 语言")
print("=" * 72)
expect_msgs = {
    "en": "JIT26 debugger is not ready",
    "zh-CN": "JIT26 调试器未就绪",
    "zh-Hans": "JIT26 调试器未就绪",
    "zh-Hant": "JIT26 偵錯器尚未就緒",
    "ja": "JIT26 デバッガーの準備ができていません",
}
for lang, msg in expect_msgs.items():
    p = f"Natives/resources/{lang}.lproj/Localizable.strings"
    src = read(p)
    check(f"{lang} 键存在且文案正确",
          re.search(r'"i18n_str_jit26_not_ready"\s*=\s*"[^"]*' + re.escape(msg), src))

print()
print("=" * 72)
print("C8. JIT 路径决策表（Python 对拍镜像 isTrollStoreInstall 双确认）")
print("=" * 72)


def trollstore_path(marker_ent, disk_marker):
    return bool(marker_ent and disk_marker)


cases = [
    ("真实 TrollStore（标记+目录）→ apple-magnifier 路径", trollstore_path(True, True), True),
    ("普通侧载（模板预写标记，无目录）→ stikjit 正常路径", trollstore_path(True, False), False),
    ("无标记（用户自定签名）→ stikjit 正常路径", trollstore_path(False, False), False),
    ("有目录但无标记（异常态）→ stikjit 正常路径", trollstore_path(False, True), False),
]
for name, got, want in cases:
    check(name, got == want, f"got={got} want={want}")

print()
print("=" * 72)
print(f"Task 91 验证结果：PASS {PASS} / FAIL {FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
