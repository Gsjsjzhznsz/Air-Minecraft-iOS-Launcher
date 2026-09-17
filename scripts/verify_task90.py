#!/usr/bin/env python3
"""
Task 90 验证器：右侧面板按钮恢复原样 + 主界面卡片顶部色条移除 + 内存权限误报修复

背景（用户实测反馈，截图 IMG_9106）：
  1. 蓝框（右侧面板按钮）：Task89 的"全灰新拟态按钮"选择有误，要求恢复
     Task88 时点（7ab2b41）的原样，此后不再改动该面板按钮样式；
  2. 红框（主界面卡片顶部 3pt 渐变色条）：全部移除（HomeTileBaseCell.accentBar）；
  3. 内存权限标识误报：用户未开内存权限，"扩展内存限制/扩展虚拟内存"却显示
     已开启。根因：仓库自带 entitlements.*.xml 模板把两项 kernel entitlement
     预写为 true，侧载工具合并模板后签名里确实携带，SecTask 如实报告"有"，
     但描述文件未授权时内核并不真正兑现。

修复实现（四处）：
  1. utils.m——新增 CopyEmbeddedProfileEntitlements()（按字节定位
     embedded.mobileprovision 的 "<?xml ... </plist>" 载荷并解析 Entitlements）
     与 getEffectiveEntitlementValue()（签名 + 描述文件授权双确认；无描述文件
     的 TrollStore 场景回退为签名判定）；
  2. LauncherPreferences.h——声明 getEffectiveEntitlementValue；
  3. LauncherRightPanelViewController.m——整体回退到 7ab2b41（按钮原样：
     下载/管理/执行按钮深灰底、启动按钮 accentColor 底、三枚胶囊恢复同色
     15% 透明度底），仅 updateMemoryEntitlementStatus 改用生效判定；
  4. main.m——latestlog 增加"描述文件授权口径"的生效状态输出，便于区分
     "签名携带"与"实际生效"。
  另：LauncherNewsViewController.m——HomeTileBaseCell 移除 accentBar 渐变
  装饰条（保留 setAccentColor: 空操作以兼容 6 处调用点；磁贴图标语义色不受
  影响）；Task89 的占位底色（nm_surfaceRaised）保持不变。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK90_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
PASS, FAIL = 0, 0

MEM_KEY = "com.apple.developer.kernel.increased-memory-limit"
VM_KEY = "com.apple.developer.kernel.extended-virtual-addressing"


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


def git_file_at(commit, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{commit}:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def git_diff_stat(commit, path):
    r = subprocess.run(["git", "-C", REPO, "diff", "--unified=0", commit, "--", path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


print("=" * 72)
print("C1. utils.m：getEffectiveEntitlementValue（签名 + 描述文件授权双确认）")
print("=" * 72)
utils = read("Natives/utils.m")
utils_code = strip_objc_strings_comments(utils)
check("getEntitlementValue（签名口径）保留且未删除", "BOOL getEntitlementValue(NSString *key) {" in utils_code)
check("Task93：getEffectiveEntitlementValue 双确认实现已整体移除",
      "BOOL getEffectiveEntitlementValue(NSString *key) {" not in utils_code)
check("Task93：CopyEmbeddedProfileEntitlements 已整体移除",
      "CopyEmbeddedProfileEntitlements(void)" not in utils_code)
check("Task93：移除处留有标记注释（双确认方案废弃原因）",
      "Task93" in utils and "完全同源" in utils)
check("SecTask 私有 API 声明仍在（SecTaskCopyValueForEntitlement）",
      "SecTaskCopyValueForEntitlement" in utils)
check("utils.m 花括号配平", bracket_balance(utils_code))

print()
print("=" * 72)
print("C2. LauncherPreferences.h：生效判定声明已随 Task93 移除")
print("=" * 72)
lph = read("Natives/LauncherPreferences.h")
check("Task93：getEffectiveEntitlementValue 声明已移除", "BOOL getEffectiveEntitlementValue(NSString *key);" not in lph)
check("原 getEntitlementValue 声明保留", "BOOL getEntitlementValue(NSString *key);" in lph)

print()
print("=" * 72)
print("C3. LauncherRightPanelViewController.m：按钮恢复原样（7ab2b41）+ 生效判定")
print("=" * 72)
rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc_strings_comments(rp)
base = git_file_at("7ab2b41", "Natives/LauncherRightPanelViewController.m")
base_code = strip_objc_strings_comments(base)

# —— 按钮原样（与 7ab2b41 逐项对拍）——
for tag, needle in [
    ("下载中心按钮深灰底（原样）", "self.downloadCenterButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];"),
    ("启动按钮 accentColor 底（原样）", "self.launchButton.backgroundColor = accentColor();"),
    ("启动按钮原圆角+阴影注释（masksToBounds）", "self.launchButton.layer.masksToBounds = YES;"),
    ("管理版本按钮深灰底（原样）", "self.manageVersionBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];"),
    ("执行 Jar 按钮深灰底（原样）", "self.executeJarBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];"),
    ("applyCustomAppearance 恢复 accentColor 刷新启动按钮", "self.launchButton.backgroundColor = accentColor();"),
]:
    check(tag, needle in rp_code)
check("启动按钮阴影（Task89 前的 elevation 代码恢复）",
      "self.launchButton.layer.shadowColor = [UIColor blackColor].CGColor;" in rp_code)
check("三枚胶囊恢复同色 15% 透明度底（JIT）",
      "self.jitStatusLabel.backgroundColor = [[UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0] colorWithAlphaComponent:0.15];" in rp)
check("胶囊底色三处（memLimit/extVM/jit）与 7ab2b41 一致",
      rp.count("colorWithAlphaComponent:0.15]") == base.count("colorWithAlphaComponent:0.15]"))
check("文件不含 NeomorphKit 导入（原样）", "NeomorphKit" not in rp)
check("文件不含任何 nm_ 新拟态调用（原样）", not re.search(r"\bnm_", rp))
check("未引入 NMTheme（原样）", "NMTheme" not in rp)

# —— 相对 7ab2b41 的增量必须仅限检测修复 ——
diff = git_diff_stat("7ab2b41", "Natives/LauncherRightPanelViewController.m")
changed = [ln for ln in diff.splitlines()
           if (ln.startswith("+") or ln.startswith("-")) and not ln.startswith(("+++", "---"))]
allowed = re.compile(
    r"getEntitlementValue|getEffectiveEntitlementValue|Task90|Task93|描述文件|双确认|生效|误报|"
    r"检测方式与 MeloNX|本进程 entitlement|交叉校验|entitlement 运行期不会变化|刷新时机|"
    r"TrollStore 无描述文件|签名判定|避免|预写|内核并不真正兑现|普通侧载签名里也带着|配色沿用|"
    r"共用同一入口|entitlement 由签名时的|这里与 JIT 标识|com\.apple\.developer\.kernel|"
    r"启动日志|同源|同一函数|排查混乱|实测|重签工具|SecTask 私有 API|扩内存限制|扩展虚拟内存")
suspicious = [ln for ln in changed if not allowed.search(ln)]
check("相对 7ab2b41 的差异仅限内存检测修复（无其他视觉改动）", not suspicious, str(suspicious[:6]))
check("Task93：两项均改回签名口径 getEntitlementValue（与启动日志同源）",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2)
check("生效判定调用已无残留",
      "getEffectiveEntitlementValue(@" not in rp_code)
check("生效判定调用使用正确的两个 key", MEM_KEY in rp and VM_KEY in rp)
check("JIT 状态刷新仍用签名口径 getEntitlementValue（不受影响）",
      "BOOL enabled = isJITEnabled(NO);" in rp_code)
check("花括号配平", bracket_balance(rp_code))

print()
print("=" * 72)
print("C4. LauncherNewsViewController.m：主界面卡片顶部色条移除")
print("=" * 72)
news = read("Natives/LauncherNewsViewController.m")
news_code = strip_objc_strings_comments(news)
check("accentBar 属性已删除", "CAGradientLayer *accentBar" not in news_code)
check("不再创建渐变装饰条", "accentBar = [CAGradientLayer layer]" not in news_code)
check("不再 addSublayer 挂载色条", "addSublayer:self.accentBar" not in news_code)
check("layoutSubviews 不再更新色条 frame",
      "self.accentBar.frame" not in news_code)
check("layoutSubviews 保留阴影路径（卡片阴影不受影响）",
      "self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.contentView.bounds cornerRadius:16].CGPath;" in news_code)
check("setAccentColor: 声明保留（兼容 6 处调用点）",
      "- (void)setAccentColor:(UIColor *)color;" in news_code)
check("setAccentColor: 实现保留（空操作）",
      "- (void)setAccentColor:(UIColor *)color {" in news_code)
call_sites = len(re.findall(r"\[cell setAccentColor:\[config accentColor\]\]", news_code))
check("数据源 6 处调用点原样保留", call_sites == 6, f"实际 {call_sites} 处")
check("磁贴图标配色不受影响（iconView.tintColor = config accentColor）",
      "cell.iconView.tintColor = [config accentColor];" in news_code)
check("Task89 成果保留：头像占位底色仍为 nm_surfaceRaised",
      "self.avatarImageView.backgroundColor = [NMTheme nm_surfaceRaised];" in news_code)
check("Task89 成果保留：新闻缩略图占位底色仍为 nm_surfaceRaised",
      "self.thumbnailView.backgroundColor = [NMTheme nm_surfaceRaised];" in news_code)
check("卡片 contentView 圆角 16 保留（新拟态枢纽依赖）",
      "self.contentView.layer.cornerRadius = 16;" in news_code)
check("BackgroundManager 枢纽调用保留（applyEffectToCollectionViewCell）",
      "applyEffectToCollectionViewCell:self]" in news_code)
check("花括号配平", bracket_balance(news_code))

print()
print("=" * 72)
print("C5. main.m：生效口径日志块已随 Task93 移除，仅保留签名口径日志")
print("=" * 72)
mainm = read("Natives/main.m")
check("Task93：生效口径日志标题已移除", "Entitlements effectiveness (profile-granted):" not in mainm)
check("Task93：main.m 无 getEffectiveEntitlementValue 残留",
      "getEffectiveEntitlementValue" not in mainm)
check("签名口径可用性日志保留（printEntitlementAvailability）",
      mainm.count("printEntitlementAvailability(@") == 5)
check("main.m 已导入 LauncherPreferences.h（声明可见）", '#import "LauncherPreferences.h"' in mainm)

print()
print("=" * 72)
print("C6. 根因留档：entitlements 模板（Task91 同步——sideload 模板预写已移除）")
print("=" * 72)
# Task91：sideload 工件的签名即用户最终签名，预写的 kernel entitlement 使
# 内存标识对所有人显示"已开启"，已从 sideload 模板移除；
# TrollStore 工件（真实生效）与开发者签名模板（描述文件背书）保留。
ts_tpl = read("entitlements.trollstore.xml")
cs_tpl = read("entitlements.codesign.xml")
check("entitlements.trollstore.xml 含 increased-memory-limit（真实生效场景）", MEM_KEY in ts_tpl)
check("entitlements.trollstore.xml 含 extended-virtual-addressing", VM_KEY in ts_tpl)
check("entitlements.codesign.xml 含 increased-memory-limit（描述文件背书场景）", MEM_KEY in cs_tpl)
check("entitlements.codesign.xml 含 extended-virtual-addressing", VM_KEY in cs_tpl)

print()
print("=" * 72)
print("C7. 生效判定决策表——已随 Task93 移除双确认方案而作废")
print("=" * 72)
check("Task93：决策表镜像的 getEffectiveEntitlementValue 已不存在于 utils.m",
      "BOOL getEffectiveEntitlementValue(NSString *key) {" not in utils_code)

print()
print("=" * 72)
print(f"Task 90 验证结果：PASS {PASS} / FAIL {FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
