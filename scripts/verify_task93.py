#!/usr/bin/env python3
"""
Task 93 验证器：内存标识抛弃 MeloNX 双确认方案，回归启动日志同源的签名口径

背景（用户第三次反馈）：
  - UI 没问题了，但内存标识仍显示"已开启"。
  - 用户指示：抛弃 MeloNX 的检测方式。启动日志最开头 [Pre-init] Entitlements
    availability 记录的两行（extended-virtual-addressing: NO /
    increased-memory-limit: YES）才是用户认可的结果，要求"研究启动器是如何
    检测这两项的，显示在原来的地方"。
  - 源码分析结论：日志那两行 = main.m printEntitlementAvailability() →
    utils.m getEntitlementValue()（SecTaskCopyValueForEntitlement，SecTask
    私有 API 读签名 entitlement）。右面板 Task90 起用的
    getEffectiveEntitlementValue（签名+embedded.mobileprovision 描述文件
    Entitlements 交叉校验）比日志多一层；用户实测重签工具会把 entitlement
    同时写入描述文件 → 双确认放行 → 面板仍显示"已开启"。
  - 修复：右面板两项改回 getEntitlementValue（与启动日志同一函数、同一口径）；
    getEffectiveEntitlementValue / CopyEmbeddedProfileEntitlements /
    LauncherPreferences.h 声明 / main.m 生效口径日志块全部移除（用户明确
    "抛弃"），全仓库只保留一种内存 entitlement 口径。
  - 用户同时指示 JIT/JS 方向停止（Task92 成果保留在库，不再继续开发）。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK93_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
MEM_KEY = "com.apple.developer.kernel.increased-memory-limit"
VM_KEY = "com.apple.developer.kernel.extended-virtual-addressing"
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
    """字符串感知剥离：去 @"..." 字面量与注释（兼容 CRLF）。"""
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


def git(args):
    return subprocess.run(["git", "-C", REPO] + args, capture_output=True, text=True)


def bracket_balance(code):
    return code.count("{") == code.count("}")


print("=" * 72)
print("A. LauncherRightPanelViewController.m：标识改回签名口径（与日志同源）")
print("=" * 72)
rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc(rp)

check("A1  扩展内存限制 → getEntitlementValue（签名口径）",
      f'getEntitlementValue(@"{MEM_KEY}")' in rp)
check("A2  扩展虚拟内存 → getEntitlementValue（签名口径）",
      f'getEntitlementValue(@"{VM_KEY}")' in rp)
check("A3  双确认调用已无残留（原始文本含 getEffectiveEntitlementValue(@）",
      "getEffectiveEntitlementValue(@" not in rp)
check("A4  两处判定仍位于 updateMemoryEntitlementStatus（原位置）",
      rp_code.count("- (void)updateMemoryEntitlementStatus") == 1
      and rp_code.find("- (void)updateMemoryEntitlementStatus") < rp.find(f'getEntitlementValue(@"{MEM_KEY}")'))
check("A5  注释标注 Task93 且说明与启动日志同源",
      "Task93" in rp and "Entitlements availability" in rp)
check("A6  配色与文案键未变（绿/红 + i18n_str_mem_limit/ext_vm）",
      "i18n_str_mem_limit_enabled" in rp and "i18n_str_ext_vm_enabled" in rp
      and "colorWithAlphaComponent:0.15" in rp)
check("A7  JIT 状态刷新不受影响（isJITEnabled(NO) 仍在）",
      "BOOL enabled = isJITEnabled(NO);" in rp_code)
check("A8  花括号配平", bracket_balance(rp_code))

print()
print("=" * 72)
print("B. 双确认方案整体移除（utils.m / LauncherPreferences.h / main.m）")
print("=" * 72)
utils = read("Natives/utils.m")
utils_code = strip_objc(utils)
lph = read("Natives/LauncherPreferences.h")
mainm = read("Natives/main.m")

check("B1  utils.m：getEffectiveEntitlementValue 实现已删除",
      "BOOL getEffectiveEntitlementValue(NSString *key) {" not in utils_code)
check("B2  utils.m：CopyEmbeddedProfileEntitlements 实现已删除",
      "CopyEmbeddedProfileEntitlements(void)" not in utils_code)
check("B3  utils.m：描述文件解析痕迹清除（NSPropertyListSerialization/mobileprovision）",
      "NSPropertyListSerialization" not in utils_code
      and "mobileprovision" not in utils_code)
check("B4  utils.m：删除处留 Task93 废弃标记注释",
      "Task93" in utils and "完全同源" in utils)
check("B5  utils.m：getEntitlementValue（签名口径）原样保留",
      "BOOL getEntitlementValue(NSString *key) {" in utils_code
      and "SecTaskCopyValueForEntitlement(secTask, key, nil)" in utils_code)
check("B6  LauncherPreferences.h：声明已删除，原签名口径声明保留",
      "getEffectiveEntitlementValue" not in lph
      and "BOOL getEntitlementValue(NSString *key);" in lph)
check("B7  main.m：生效口径日志块已删除（effectiveness profile-granted）",
      "profile-granted" not in mainm)
check("B8  main.m：签名口径日志块完整保留（availability 3+2 项）",
      "[Pre-init] Entitlements availability:" in mainm
      and mainm.count("printEntitlementAvailability(@") == 5)
check("B9  main.m：无 getEffectiveEntitlementValue 残留",
      "getEffectiveEntitlementValue" not in mainm)
check("B10 全仓库代码无 getEffectiveEntitlementValue 调用残留（Task93 注释除外）",
      all("getEffectiveEntitlementValue(@" not in read(p)
          for p in ["Natives/utils.m", "Natives/main.m",
                    "Natives/LauncherRightPanelViewController.m",
                    "Natives/LauncherPreferences.h"]))
check("B11 utils.m 花括号配平", bracket_balance(utils_code))

print()
print("=" * 72)
print("C. 与启动日志的口径一致性（用户验收基准）")
print("=" * 72)

check("C1  日志与面板共用同一函数 getEntitlementValue（printEntitlementAvailability 实现）",
      "void printEntitlementAvailability(NSString *key) {" in mainm
      and "getEntitlementValue(key)" in strip_objc(mainm))
check("C2  日志两个 key 与面板两个 key 完全一致",
      f'printEntitlementAvailability(@"{VM_KEY}")' in mainm
      and f'printEntitlementAvailability(@"{MEM_KEY}")' in mainm)
check("C3  isTrollStoreInstall / JIT 路径不受影响（Task91 成果保留）",
      "BOOL isTrollStoreInstall(void) {" in utils_code
      and "JIT26CreateRegionLegacySafe" in utils_code)
check("C4  entitlements 模板三向状态不变（sideload 已清理/trollstore+codesign 保留）",
      ('<key>' + MEM_KEY + '</key>' not in read("entitlements.sideload.xml"))
      and MEM_KEY in read("entitlements.trollstore.xml")
      and MEM_KEY in read("entitlements.codesign.xml"))

print()
print("=" * 72)
print("D. 仓库卫生")
print("=" * 72)

check("D1  无未提交改动（提交后自然通过）",
      git(["status", "--porcelain"]).stdout.strip() == "",
      git(["status", "--porcelain"]).stdout.strip()[:200])
check("D2  仓库 worklog 含 Task 93 条目",
      os.path.exists(os.path.join(REPO, "worklog.md")) and "Task ID: 93" in read("worklog.md"))

print()
print("=" * 72)
print(f"RESULT: {PASS} passed, {FAIL} failed, total {PASS + FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
