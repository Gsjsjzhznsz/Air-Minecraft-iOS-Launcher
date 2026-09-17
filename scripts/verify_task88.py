#!/usr/bin/env python3
"""
Task 88 验证器：主界面右侧面板新增"扩展内存限制/扩展虚拟内存"状态标识（参照 MeloNX）

背景（用户需求）：
  MeloNX（Ryujinx iOS 移植）在设置页通过 SecTask 私有 API 读取本进程 entitlement，
  展示 "Increased Memory Limit"（扩展内存限制）与 "Extended Virtual Addressing"
  （扩展虚拟内存）两项的开启状态。本仓库（JavaMC 模拟器）主界面右侧偏下已有 JIT
  状态胶囊标签（LauncherRightPanelViewController.jitStatusLabel），需求为按其原样式
  在上方新增两个同款标识，显示两项内存 entitlement 的状态。

实现（三处，全启动器侧）：
  1. LauncherRightPanelViewController.m——新增 memLimitStatusLabel/extVMStatusLabel
     两个属性；makeJITStyleStatusLabel 工厂（与 JIT 标签字号/对齐/圆角完全一致）；
     约束自下而上排列：扩展内存限制 → 扩展虚拟内存 → JIT（间距 4pt，标签高 20pt）；
     updateMemoryEntitlementStatus 复用 utils.m 的 getEntitlementValue()（SecTask）；
     刷新时机与 updateJITStatus 对齐（viewWillAppear + DidBecomeActive 通知）；
     applyCustomAppearance 与 JIT 标签同策略（自定义字体色时覆盖文字色）。
     附带调整：进度条间距约束设为 999 优先级，成为真正的"弱约束"，小屏放不下
     更高的状态堆栈时优先断开此条，避免不可满足的约束冲突。
  2. utils.m——getEntitlementValue() 原实现 SecTaskCreateFromSelf 被调用两次但只
     释放一次（每次调用泄漏一个 SecTaskRef），改为单次创建 + nil 守卫 + 判断后释放，
     对外行为完全不变（非 NSNumber 非 nil → YES；NSNumber → boolValue；nil → NO）。
  3. 本地化——新增 4 个 key（i18n_str_mem_limit_enabled/disabled、
     i18n_str_ext_vm_enabled/disabled），覆盖 en/zh-CN/zh-Hans/zh-Hant/ja
     （与 i18n_str_421 的覆盖范围一致，其余语言经 localize() 回退英文）。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK88_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
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


def strip_objc_strings_comments(src):
    """字符串感知的 ObjC 源码剥离：去掉 @"..." 字面量与 // /* */ 注释，保留结构。"""
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


def bracket_balance(stripped):
    counts = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    for ch in stripped:
        if ch in counts:
            counts[ch] += 1
        elif ch in pairs:
            counts[pairs[ch]] -= 1
            if counts[pairs[ch]] < 0:
                return False
    return all(v == 0 for v in counts.values())


def strings_file_balanced(src):
    """逐行检查 .strings 引号闭合（每条记录单行，忽略注释行）。"""
    for line in src.splitlines():
        s = line.strip()
        if not s or s.startswith("/*") or s.startswith("*"):
            continue
        if s.count('"') % 2 != 0:
            return False
    return True


print("== A. LauncherRightPanelViewController.m（UI 标识 + 检测 + 刷新时机）==")
rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc_strings_comments(rp)

check("A1 两个新属性已声明", "UILabel *memLimitStatusLabel" in rp and "UILabel *extVMStatusLabel" in rp)
check("A2 makeJITStyleStatusLabel 工厂存在", "- (UILabel *)makeJITStyleStatusLabel" in rp_code)
helper = rp[rp.find("- (UILabel *)makeJITStyleStatusLabel"):rp.find("- (void)updateMemoryEntitlementStatus")]
check("A2a 工厂样式与 JIT 标签一致（字号11/圆角8/masksToBounds）",
      all(k in helper for k in ["systemFontOfSize:11 weight:UIFontWeightMedium",
                                "cornerRadius = 8", "masksToBounds = YES",
                                "translatesAutoresizingMaskIntoConstraints = NO"]))
check("A3 两个标签经工厂创建并 addSubview", rp_code.count("makeJITStyleStatusLabel") >= 3
      and "[self.view addSubview:self.memLimitStatusLabel];" in rp
      and "[self.view addSubview:self.extVMStatusLabel];" in rp)
check("A4 内存限制标签锚定在 JIT 标签上方(-4)",
      "self.memLimitStatusLabel.bottomAnchor constraintEqualToAnchor:self.jitStatusLabel.topAnchor constant:-4" in rp)
check("A4a 扩展虚拟内存标签锚定在内存限制标签上方(-4)",
      "self.extVMStatusLabel.bottomAnchor constraintEqualToAnchor:self.memLimitStatusLabel.topAnchor constant:-4" in rp)
check("A4b 两标签与 JIT 标签同宽同高（leading12/trailing-12/height20）",
      all(k in rp for k in [
          "self.memLimitStatusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12",
          "self.memLimitStatusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12",
          "self.memLimitStatusLabel.heightAnchor constraintEqualToConstant:20",
          "self.extVMStatusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12",
          "self.extVMStatusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12",
          "self.extVMStatusLabel.heightAnchor constraintEqualToConstant:20"]))
check("A5 updateMemoryEntitlementStatus 方法存在且唯一",
      rp_code.count("- (void)updateMemoryEntitlementStatus") == 1)
check("A5a 读取两个内核内存 entitlement key（Task93 改回签名口径，与启动日志同源）",
      'getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")' in rp
      and 'getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")' in rp)
check("A6 复用 utils 的 getEntitlementValue 入口（与 JIT/内存分配共用）",
      rp_code.count("getEntitlementValue") >= 2)
update_m = rp[rp.find("- (void)updateMemoryEntitlementStatus"):rp.find("#pragma mark - 自定义外观")]
check("A7 配色沿用 JIT 标识（绿0.2/0.7/0.3 红0.9/0.4/0.3，背景15%透明）",
      all(k in update_m for k in ["0.2 green:0.7 blue:0.3", "0.9 green:0.4 blue:0.3",
                                  "colorWithAlphaComponent:0.15"]))
check("A8 四个新 i18n key 均被引用",
      all(k in rp for k in ["i18n_str_mem_limit_enabled", "i18n_str_mem_limit_disabled",
                            "i18n_str_ext_vm_enabled", "i18n_str_ext_vm_disabled"]))
check("A9 viewWillAppear 刷新", "[self updateMemoryEntitlementStatus];" in rp
      and re.search(r"- \(void\)viewWillAppear:[\s\S]*?\[self updateMemoryEntitlementStatus\];[\s\S]*?\[self applyCustomAppearance\];", rp_code))
check("A9a DidBecomeActive 通知已注册", "selector:@selector(updateMemoryEntitlementStatus)" in rp
      and "UIApplicationDidBecomeActiveNotification" in rp)
check("A10 applyCustomAppearance 与 JIT 同策略（自定义色覆盖两个新标签）",
      re.search(r"self\.jitStatusLabel\.textColor = customColor;[\s\S]*?self\.memLimitStatusLabel\.textColor = customColor;[\s\S]*?self\.extVMStatusLabel\.textColor = customColor;", rp))
check("A11 进度条间距约束设为 999 优先级（真弱约束）",
      "progressSpacingConstraint.priority = 999" in rp)
check("A12 setupUI 创建后立即刷新一次", re.search(
      r"progressSpacingConstraint\.active = YES;[\s\S]{0,200}\[self updateMemoryEntitlementStatus\];", rp))
check("A13 括号平衡（字符串感知）", bracket_balance(rp_code))

print("== B. utils.m（getEntitlementValue 泄漏收紧，行为不变）==")
utils = read("Natives/utils.m")
utils_code = strip_objc_strings_comments(utils)
fn = utils[utils.find("BOOL getEntitlementValue"):utils.find("#ifndef P_TRACED")]
fn_code = strip_objc_strings_comments(fn)
check("B1 SecTaskCreateFromSelf 仅调用一次（注释剥离后计数）", fn_code.count("SecTaskCreateFromSelf") == 1)
check("B2 secTask/value nil 守卫", "if (!secTask)" in fn and "if (value == nil)" in fn)
check("B3 行为保持：非 NSNumber → YES；NSNumber → boolValue",
      "![(__bridge id)value isKindOfClass:NSNumber.class] || [(__bridge id)value boolValue]" in fn
      and "CFRelease(value);" in fn and "return result;" in fn)
check("B4 括号平衡（字符串感知）", bracket_balance(utils_code))

print("== C. 本地化（4 个新 key，5 个语言文件）==")
KEYS = ["i18n_str_mem_limit_enabled", "i18n_str_mem_limit_disabled",
        "i18n_str_ext_vm_enabled", "i18n_str_ext_vm_disabled"]
LANGS = {"en.lproj": None, "zh-CN.lproj": None, "zh-Hans.lproj": None,
         "zh-Hant.lproj": None, "ja.lproj": None}
strings_src = {}
for lang in LANGS:
    p = f"Natives/resources/{lang}/Localizable.strings"
    strings_src[lang] = read(p)
for lang, src in strings_src.items():
    check(f"C1 {lang}: 4 个新 key 全部存在",
          all(f'"{k}" =' in src for k in KEYS))
    check(f"C2 {lang}: 无重复 key", all(src.count(f'"{k}"') == 1 for k in KEYS))
    check(f"C3 {lang}: 引号闭合", strings_file_balanced(src))
zh_hans = strings_src["zh-Hans.lproj"]
check("C4 zh-Hans 文案=扩展内存限制/扩展虚拟内存 + 已开启/未开启",
      all(k in zh_hans for k in ["扩展内存限制: 已开启", "扩展内存限制: 未开启",
                                 "扩展虚拟内存: 已开启", "扩展虚拟内存: 未开启"]))
check("C5 zh-Hant 使用繁体（擴展記憶體限制/擴展虛擬記憶體/已開啟）",
      all(k in strings_src["zh-Hant.lproj"] for k in ["擴展記憶體限制: 已開啟", "擴展虛擬記憶體: 已開啟"]))
check("C6 en 使用 Ext. Memory Limit / Ext. Virtual Memory（回退兜底）",
      all(k in strings_src["en.lproj"] for k in
          ["Ext. Memory Limit: Enabled", "Ext. Memory Limit: Not Enabled",
           "Ext. Virtual Memory: Enabled", "Ext. Virtual Memory: Not Enabled"]))
check("C7 ja 使用日文（拡張メモリ上限/拡張仮想メモリ/有効/無効）",
      all(k in strings_src["ja.lproj"] for k in
          ["拡張メモリ上限: 有効", "拡張仮想メモリ: 無効"]))
check("C8 其余 45 语言可回退英文（localize 的 en lproj 回退路径仍在）",
      'pathForResource:@"en"' in utils)

print("== D. 一致性与作用域 ==")
jl = read("Natives/JavaLauncher.m")
check("D1 key 与 JavaLauncher 既有用法完全一致",
      "com.apple.developer.kernel.increased-memory-limit" in jl
      and "com.apple.developer.kernel.extended-virtual-addressing" in jl)
check("D2 注释标明 MeloNX 参照来源", "MeloNX" in rp)
ents = ["entitlements.sideload.xml", "entitlements.trollstore.xml", "entitlements.codesign.xml"]
ents_hit = sum(1 for e in ents if "increased-memory-limit" in read(e) or
               "extended-virtual-addressing" in read(e))
check("D2a entitlements 模板至少一个含相关 key（展示的是真实能力）", ents_hit >= 1,
      f"hit={ents_hit}")

print("== E. git 工作区作用域 ==")


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True).stdout


status = git("status", "--porcelain")
changed = {ln[3:].strip() for ln in status.splitlines() if ln.strip()}
expected = {
    "Natives/LauncherRightPanelViewController.m",
    "Natives/utils.m",
    "Natives/resources/en.lproj/Localizable.strings",
    "Natives/resources/zh-CN.lproj/Localizable.strings",
    "Natives/resources/zh-Hans.lproj/Localizable.strings",
    "Natives/resources/zh-Hant.lproj/Localizable.strings",
    "Natives/resources/ja.lproj/Localizable.strings",
    "scripts/verify_task88.py",
    "worklog.md",
}
check("E1 改动仅限预期文件", changed <= expected, f"extra={changed - expected}")

print()
print(f"verify_task88: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
