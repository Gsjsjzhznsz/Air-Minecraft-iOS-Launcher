#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task154.py —— Task 157 校验器

用户两项返工需求（Task 149/150 实装后的实测反馈）：
  1. 实例设置 > 内存分配：
     - 行右侧去掉"最大可分配内存"（只显示当前分配值），加与 Java 版本同款
       右箭头（DisclosureIndicator）；
     - 点击后的弹窗改为居中卡片（类放大 alert，右上角✕ = 实例页同款关闭
       语义），自绘缩放+淡入出入场；"当前内存"升为标题字号、"内存分配"
       标题删除；拉条下保持间距新增"自动分配内存"开关（用户定稿）；
     - 开关开启：拉条置灰并显示自动比例实值（与 ame141_currentLaunchAllocMem
       同口径 0.5/0.25）；行右侧显示"自动分配内存"；
     - 保存语义 = 即改即存（滑条松手/拨开关当下写回，✕/点外部仅关闭）；
     - 持久化 = profile memoryAuto 标记（仅显式拨过为 YES——用户定稿
       "默认手动"）；开启时 allocatedMemory 落 0 → 启动链原版自动比例。
  2. 组件安装 Sodium → Sodium + Iris Shaders：
     - 行名/映射/图标（火焰不变）同步；一键装 Sodium + Iris + Podium
       三 jar（Modrinth 精确标题 sodium / iris shaders→iris 回退 / podium，
       fabric + 游戏版本双过滤，串行下载进 mods/）；
     - "仅 Fabric 有效"门槛弹窗改为 Fabric API 同文案结构（换模组名，
       新键 component.sodium.fabric_only）；
     - 组件安装区灰字 footer 加行（用户原文）；
     - 统一下载任务显示名 Sodium + Iris Shaders + Podium（用户定稿）。

分节：A 内存行 / B Ame157 卡片弹窗 / C 持久化与启动链 / D Sodium + Iris /
      E l10n（Task157 后基线 1947）/ F 发布资产 / G 配平+白名单 / H 回归锚点
"""
import json
import os
import re
import sys

REPO = os.environ.get("TASK157_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
PASS = 0
FAIL = 0
FAILED = []


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_objc(s):
    s = re.sub(r'@"(?:[^"\\]|\\.)*"', '""', s)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r'//.*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return s


def balanced(s):
    s = strip_objc(s)
    return all(s.count(a) == s.count(b) for a, b in [("{", "}"), ("(", ")"), ("[", "]")])


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        FAILED.append(name)
        print(f"  FAIL  {name}  {detail}")


ps = read("Natives/ProfileSettingsViewController.m")
ps_code = strip_objc(ps)

print()
print("=" * 72)
print("A. 内存分配行（去最大值 + 右箭头 + 自动态显示）")
print("=" * 72)
check("A1  行箭头与 Java 版本同款（DisclosureIndicator）",
      'cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;\n                cell.detailTextLabel.text = self.memoryAutoEnabled' in ps)
check("A2  右侧只显示当前值（%ld MB），自动态显示 memory.auto_row",
      'cell.detailTextLabel.text = self.memoryAutoEnabled\n                    ? localize(@"memory.auto_row", nil)\n                    : [NSString stringWithFormat:@"%ld MB", (long)self.allocatedMemory];' in ps)
check("A3  旧'当前/最大'双值显示清零（MB / %ld MB 不复存在）",
      "MB / %ld MB" not in ps
      and "UITableViewCellAccessoryNone;\n                cell.detailTextLabel.text = [NSString stringWithFormat:@\"%ld MB" not in ps)

print()
print("=" * 72)
print("B. Ame157 居中卡片弹窗（✕/大标题/自动开关/自绘转场/即改即存）")
print("=" * 72)
check("B1  Ame157MemoryAllocatorCard 定义 + 实现",
      "@interface Ame157MemoryAllocatorCard : UIViewController <UIViewControllerTransitioningDelegate>" in ps_code
      and "@implementation Ame157MemoryAllocatorCard" in ps_code)
check("B2  Ame157CardTransitionAnimator 定义 + 实现（缩放 1.14→1 入场 / 1.08 淡出）",
      "@interface Ame157CardTransitionAnimator : NSObject <UIViewControllerAnimatedTransitioning>" in ps_code
      and "@implementation Ame157CardTransitionAnimator" in ps_code
      and "CGAffineTransformMakeScale(1.14, 1.14)" in ps_code
      and "CGAffineTransformMakeScale(1.08, 1.08)" in ps_code)
check("B3  右上角✕（xmark.circle.fill）+ 点外部关闭（ame157Close）",
      '[ame157_close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];' in ps
      and "[self.ameDimmingView addTarget:self action:@selector(ame157Close) forControlEvents:UIControlEventTouchUpInside];" in ps
      and "- (void)ame157Close {" in ps_code)
check("B4  '当前内存'升为标题字号（17 semibold），弹窗内'内存分配'标题退役（仅保留表格行名映射）",
      "self.ameTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];" in ps_code
      and ps.count('@"i18n_str_2037"') == 1)
check("B5  自动分配开关在拉条下方（memory.auto_row + UISwitch + ame157AutoSwitchChanged）",
      'ame157_autoTitle.text = localize(@"memory.auto_row", nil);' in ps
      and "[self.ameAutoSwitch addTarget:self action:@selector(ame157AutoSwitchChanged:) forControlEvents:UIControlEventValueChanged];" in ps)
check("B6  自动态拉条置灰（enabled = !on）+ 显示自动实值（MAX(512, ameAutoMemory)）",
      "self.ameSlider.enabled = !ame157_on;" in ps_code
      and "self.ameSlider.value = (float)MAX(512, self.ameAutoMemory);" in ps_code)
check("B7  即改即存：滑条松手（TouchUpInside|UpOutside）与拨开关当下回调 ameOnChange",
      "forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];" in ps
      and "- (void)ame157SliderReleased {" in ps_code
      and "if (self.ameOnChange) self.ameOnChange(self.ameCurrentManual, NO);" in ps_code
      and "if (self.ameOnChange) self.ameOnChange((NSInteger)lroundf(self.ameSlider.value), self.ameAutoEnabled);" in ps_code)
check("B8  取消/确认按钮退役（memory.apply 不再被引用，卡片内无 cancelButton）",
      "memory.apply" not in ps
      and "[cancelButton setTitle" not in ps
      and "[applyButton setTitle" not in ps)
check("B9  窗口式阴影卡片（圆角 18 + masksToBounds NO + shadow 四件套）+ 0.4 点外部遮罩",
      "self.ameCardView.layer.cornerRadius = 18.0;" in ps_code
      and "self.ameCardView.layer.masksToBounds = NO;" in ps_code
      and "self.ameCardView.layer.shadowOpacity = 0.3;" in ps_code
      and "[[UIColor blackColor] colorWithAlphaComponent:0.4];" in ps)
check("B10 Task149 sheet 呈现链退役（mediumDetent/grabber/formSheet 回退清零）",
      "UISheetPresentationControllerDetent.mediumDetent" not in ps_code
      and "prefersGrabberVisible" not in ps_code
      and "UIModalPresentationFormSheet" not in ps_code)

print()
print("=" * 72)
print("C. 持久化与启动链（memoryAuto 标记 / 0 = 原版自动比例）")
print("=" * 72)
check("C1  loadSettings 读 memoryAuto 标记（缺省 NO = 用户定稿'默认手动'）",
      'self.memoryAutoEnabled = [self.profile[@"memoryAuto"] boolValue];' in ps)
check("C2  saveSettings 分支：自动 = 落 0 + memoryAuto@YES；手动 = 数值 + 清标记",
      'if (self.memoryAutoEnabled) {\n        existing[@"allocatedMemory"] = @(0);\n        existing[@"memoryAuto"] = @YES;\n    } else {\n        existing[@"allocatedMemory"] = @(self.allocatedMemory);\n        [existing removeObjectForKey:@"memoryAuto"];\n    }' in ps)
check("C3  ameOnChange 写回链（memoryAutoEnabled/allocatedMemory → saveSettings → reloadAllTableViews）",
      "strongSelf.memoryAutoEnabled = autoEnabled;" in ps_code
      and "strongSelf.allocatedMemory = autoEnabled ? 0 : memoryMB;" in ps_code
      and "[strongSelf saveSettings];" in ps_code
      and "[strongSelf reloadAllTableViews];" in ps_code)
check("C4  自动实值与启动链同口径（getEntitlementValue memorystatus ? 0.5 : 0.25 × 物理 MB）",
      'CGFloat ame157_ratio = getEntitlementValue(@"com.apple.private.memorystatus") ? 0.5 : 0.25;' in ps
      and "(NSProcessInfo.processInfo.physicalMemory >> 20) * ame157_ratio" in ps)
utils_m = read("Natives/utils.m")
check("C5  启动链 ame141_currentLaunchAllocMem 零改动（0 = 自动比例语义幸存）",
      "int ame141_currentLaunchAllocMem(void)" in utils_m
      and 'CGFloat autoRatio = getEntitlementValue(@"com.apple.private.memorystatus") ? 0.5 : 0.25;' in utils_m
      and "[profile[@\"allocatedMemory\"] integerValue]" in utils_m)
check("C6  自绘转场接线（UIModalPresentationCustom + 自持 transitioningDelegate）",
      "ame157_vc.modalPresentationStyle = UIModalPresentationCustom;" in ps_code
      and "ame157_vc.transitioningDelegate = ame157_vc;" in ps_code)

print()
print("=" * 72)
print("D. Sodium + Iris Shaders（行名 / 三 jar / Iris Shaders 回退 / 同款门槛）")
print("=" * 72)
check("D1  组件区行名升级（Fabric API / Sodium + Iris Shaders / OptiFine）",
      '@[@"Fabric API", @"Sodium + Iris Shaders", @"OptiFine"]' in ps)
check("D2  l10n 映射同步（Sodium + Iris Shaders 键）+ 行配置改用新名",
      '@"Sodium + Iris Shaders": @"Sodium + Iris Shaders",' in ps
      and ps.count('[title isEqualToString:@"Sodium + Iris Shaders"]') == 2)
check("D3  旧 Sodium 短名锚清零（map/行配置/didSelect 不再引用）",
      '@"Sodium": @"Sodium",' not in ps
      and '[title isEqualToString:@"Sodium"]' not in ps)
check("D4  门槛弹窗 = Fabric API 同文案结构（i18n_str_899 + component.sodium.fabric_only）",
      '[self showComponentAlert:localize(@"i18n_str_899", nil)\n                          message:localize(@"component.sodium.fabric_only", nil)];' in ps)
check("D5  统一任务 = Sodium + Iris Shaders + Podium（displayName + sodium-iris-podium- 前缀）",
      'displayName:@"Sodium + Iris Shaders + Podium"' in ps
      and 'resourceName:[NSString stringWithFormat:@"sodium-iris-podium-%@", gameVersion]' in ps)
check("D6  三模组取文件链（sodium → iris shaders→iris 回退 → podium）",
      'exactTitle:@"sodium"' in ps
      and 'exactTitle:@"iris shaders"' in ps
      and 'exactTitle:@"iris"' in ps
      and 'exactTitle:@"podium"' in ps
      and "ame157_fetchPodium" in ps_code)
check("D7  三 jar 串行下载 + 三文件落盘（dlError1/2/3 与 ok1/2/3 级联守卫）",
      "[strongSelf downloadDataWithURL:[NSURL URLWithString:sodiumURL] error:&dlError1];" in ps
      and "[strongSelf downloadDataWithURL:[NSURL URLWithString:irisURL] error:&dlError2] : nil;" in ps
      and "[strongSelf downloadDataWithURL:[NSURL URLWithString:podiumURL] error:&dlError3] : nil;" in ps
      and "BOOL ok3 = ok2 ? [podiumData writeToFile:podiumPath options:NSDataWritingAtomic error:&writeError3] : NO;" in ps)
check("D8  成功提示三文件并列 + 失败链码扩展（code 11/12）",
      'sodiumFile ?: @"sodium.jar",\n                                                 irisFile ?: @"iris.jar",\n                                                 podiumFile ?: @"podium.jar"' in ps
      and "code:11 userInfo" in ps_code and "code:12 userInfo" in ps_code)
check("D9  火焰图标保留（flame.fill，Task150 视觉不变）",
      '[UIImage systemImageNamed:@"flame.fill"]' in ps)

print()
print("=" * 72)
print("E. l10n：Task157 后基线 1948（四语言一致 + 新键/改写在位）")
print("=" * 72)
langs = ["en.lproj", "zh-Hans.lproj", "zh-CN.lproj", "zh-Hant.lproj"]
base = "Natives/resources/"
sets = []
for lg in langs:
    s = read(base + lg + "/Localizable.strings")
    k = set(re.findall(r'^"([^"]+)"\s*=', s, re.M))
    sets.append(k)
    ok_new = 'memory.auto_row' in k and 'component.sodium.fabric_only' in k
    ok_iris = "Sodium / Iris / Podium" in s and "Sodium + Iris Shaders" in s
    check(f"E[{lg}] 新键 2 + Iris 文案在位", ok_new and ok_iris,
          f"auto_row={'memory.auto_row' in k} fabric_only={'component.sodium.fabric_only' in k}")
zh = read(base + "zh-CN.lproj/Localizable.strings")
check("E5  footer 用户原文行（Sodium + Iris Shaders：优化模组 + 光影加载器 (附带安装Podium)）",
      "Sodium + Iris Shaders：优化模组 + 光影加载器 (附带安装Podium)" in zh)
check("E6  确认弹窗标题升级（安装 Sodium + Iris Shaders）",
      '"component.sodium.confirm_title" = "安装 Sodium + Iris Shaders";' in zh
      and '"component.sodium.confirm_title" = "Install Sodium + Iris Shaders";' in read(base + "en.lproj/Localizable.strings"))
check("E7  四语言键集一致（1948 = Task156 基线 1946 + Task157 组件键 2）",
      sets[0] == sets[1] == sets[2] == sets[3] and len(sets[0]) == 1948,
      f"counts={[len(x) for x in sets]}")

print()
print("=" * 72)
print("F. 发布资产（announcements.json 同步）")
print("=" * 72)
ann = json.loads(read("announcements.json"))
e = ann["announcements"][0]
check("F1  summary 口径（Sodium+Iris+Podium 一键安装）",
      "Sodium+Iris+Podium 一键安装" in e["summary"])
check("F2  content bullet（Sodium + Iris Shaders 组件安装 + Iris 光影加载器）",
      "Sodium + Iris Shaders 组件安装" in e["content"]
      and "Iris 为光影加载器" in e["content"])
check("F3  英文尾段同步（Sodium + Iris Shaders component install / Sodium + Iris + Podium）",
      "Sodium + Iris Shaders component install" in e["content"]
      and "Sodium + Iris + Podium" in e["content"])
check("F4  内存分配口径更新（居中卡片弹窗 + 自动分配内存开关）",
      "居中卡片弹窗" in e["content"] and "自动分配内存开关" in e["content"])

print()
print("=" * 72)
print("G. 语法配平 + UIColor 白名单抽查")
print("=" * 72)
check("G  ProfileSettingsViewController.m 括号配平", balanced(ps))
ALLOWED_UICOLOR = [
    "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
    "systemBackgroundColor", "secondarySystemBackgroundColor", "tertiarySystemBackgroundColor",
    "secondarySystemGroupedBackgroundColor", "tertiarySystemGroupedBackgroundColor",
    "systemGroupedBackgroundColor", "tertiarySystemFillColor", "separatorColor",
    "systemRedColor", "systemBlueColor", "systemOrangeColor", "systemGreenColor",
    "systemGrayColor", "systemTealColor", "whiteColor", "clearColor", "blackColor",
]
bad = []
for m in re.finditer(r"\[UIColor ([A-Za-z]+(?:Color|Fill)?)\]", ps):
    if m.group(1) not in ALLOWED_UICOLOR:
        bad.append(m.group(1))
check("G  ProfileSettingsViewController UIColor 白名单审计（无硬编码异常色）", not bad, str(bad[:6]))

print()
print("=" * 72)
print("H. 回归锚点")
print("=" * 72)
check("H1  Ame149 符号全仓清零（类名/回调/选择器）",
      "Ame149MemoryAllocatorController" not in ps
      and "ame147SliderChanged" not in ps
      and "ameOnApply" not in ps)
check("H2  JavaLauncher 启动内存链零改动（Task141 契约幸存）",
      "int allocmem = ame141_currentLaunchAllocMem();" in read("Natives/JavaLauncher.m"))
check("H3  组件区 footer/其余行零意外（Fabric API 与 OptiFine 行原样）",
      ps.count('cell.detailTextLabel.text = [self isFabricProfile] ? localize(@"i18n_str_2043", nil) : localize(@"i18n_str_885", nil);') == 2
      and '[UIImage systemImageNamed:@"speedometer"]' in ps)

print()
print("=" * 40)
total = PASS + FAIL
print(f"{PASS} passed, {len(FAILED)} failed")
if FAILED:
    for f in FAILED:
        print(f"  FAILED: {f}")
    sys.exit(1)
print("==== RESULT: PASSED ====")
sys.exit(0)
