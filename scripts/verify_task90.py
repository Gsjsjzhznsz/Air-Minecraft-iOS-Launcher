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
check("新增 getEffectiveEntitlementValue 实现", "BOOL getEffectiveEntitlementValue(NSString *key) {" in utils_code)
check("描述文件解析辅助函数存在（static）",
      "static NSDictionary *CopyEmbeddedProfileEntitlements(void)" in utils_code)
check("读取 embedded.mobileprovision",
      'URLForResource:@"embedded" withExtension:@"mobileprovision"' in utils)
check("按字节定位 plist 载荷（rangeOfData 起止标记）",
      'rangeOfData:startMarker' in utils and 'rangeOfData:endMarker' in utils)
check("NSPropertyListSerialization 解析描述文件", "NSPropertyListSerialization" in utils_code)
check("提取 Entitlements 字典", '[@"Entitlements"]' in utils)
check("生效判定：签名不含 key → NO",
      re.search(r"getEffectiveEntitlementValue[\s\S]{0,600}?if \(!getEntitlementValue\(key\)\) return NO;", utils_code))
check("生效判定：无描述文件 → 回退签名判定",
      re.search(r"if \(!profileEnts\) return YES;", utils_code))
check("生效判定：描述文件未列出该 key → NO",
      "if (value == nil) return NO;" in utils_code)
check("生效判定：NSNumber → boolValue",
      re.search(r"NSNumber class\]\]\) return \[value boolValue\]", utils_code))
check("生效判定：字符串 true/1 容错",
      "caseInsensitiveCompare:@\"true\"" in utils and '@"1"' in utils)
check("SecTask 私有 API 声明仍在（SecTaskCopyValueForEntitlement）",
      "SecTaskCopyValueForEntitlement" in utils)
check("utils.m 花括号配平", bracket_balance(utils_code))

print()
print("=" * 72)
print("C2. LauncherPreferences.h：生效判定对外声明")
print("=" * 72)
lph = read("Natives/LauncherPreferences.h")
check("声明 getEffectiveEntitlementValue", "BOOL getEffectiveEntitlementValue(NSString *key);" in lph)
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
    r"getEntitlementValue|getEffectiveEntitlementValue|Task90|描述文件|双确认|生效|误报|"
    r"检测方式与 MeloNX|本进程 entitlement|交叉校验|entitlement 运行期不会变化|刷新时机|"
    r"TrollStore 无描述文件|签名判定|避免|预写|内核并不真正兑现|普通侧载签名里也带着|配色沿用|"
    r"共用同一入口|entitlement 由签名时的|这里与 JIT 标识")
suspicious = [ln for ln in changed if not allowed.search(ln)]
check("相对 7ab2b41 的差异仅限内存检测修复（无其他视觉改动）", not suspicious, str(suspicious[:6]))
check("updateMemoryEntitlementStatus 两项均改用生效判定",
      rp_code.count("getEffectiveEntitlementValue(@") == 2)
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
print("C5. main.m：latestlog 输出生效口径，便于区分签名携带与实际生效")
print("=" * 72)
mainm = read("Natives/main.m")
check("生效口径日志标题存在", "Entitlements effectiveness (profile-granted):" in mainm)
check("两项 kernel entitlement 均输出生效状态",
      mainm.count("getEffectiveEntitlementValue(@") == 2)
check("签名口径可用性日志保留（printEntitlementAvailability）",
      mainm.count("printEntitlementAvailability(@") == 5)
check("main.m 已导入 LauncherPreferences.h（声明可见）", '#import "LauncherPreferences.h"' in mainm)

print()
print("=" * 72)
print("C6. 根因留档：entitlements 模板仍预写两项（TrollStore 需要它们，修复在检测侧）")
print("=" * 72)
for tpl in ["entitlements.codesign.xml", "entitlements.sideload.xml", "entitlements.trollstore.xml"]:
    t = read(tpl)
    check(f"{tpl} 含 increased-memory-limit", MEM_KEY in t)
    check(f"{tpl} 含 extended-virtual-addressing", VM_KEY in t)

print()
print("=" * 72)
print("C7. 生效判定决策表（Python 对拍镜像 ObjC 实现）")
print("=" * 72)


def effective(sig_has, profile):
    """镜像 getEffectiveEntitlementValue 的决策逻辑。
    profile: None（无描述文件）/ dict（Entitlements）"""
    if not sig_has:
        return False
    if profile is None:
        return True
    v = profile.get(MEM_KEY)
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        return v.lower() == "true" or v == "1"
    return True


cases = [
    ("签名无 + 无描述文件（未签名权限）", effective(False, None), False),
    ("签名有 + 无描述文件（TrollStore）", effective(True, None), True),
    ("签名有 + 描述文件未授权（普通侧载误报场景）", effective(True, {}), False),
    ("签名有 + 描述文件 true（已授权）", effective(True, {MEM_KEY: True}), True),
    ("签名有 + 描述文件 false", effective(True, {MEM_KEY: False}), False),
    ("签名有 + 描述文件字符串 true", effective(True, {MEM_KEY: "true"}), True),
    ("签名有 + 描述文件字符串 True", effective(True, {MEM_KEY: "True"}), True),
    ("签名有 + 描述文件字符串 1", effective(True, {MEM_KEY: "1"}), True),
    ("签名有 + 描述文件字符串 false", effective(True, {MEM_KEY: "false"}), False),
    ("签名有 + 描述文件数组类型（列出即授权）", effective(True, {MEM_KEY: ["x"]}), True),
]
for name, got, want in cases:
    check(name, got == want, f"got={got} want={want}")

print()
print("=" * 72)
print(f"Task 90 验证结果：PASS {PASS} / FAIL {FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
