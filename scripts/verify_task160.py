#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task160 -- 新拟态 UI 回归 + 初次使用默认配置 + 弹窗背景回归 +
分辨率缩放行样式统一（25~150）+ 设置页文字重影修复。

分块：
  A 分辨率缩放行（Task160 需求1）
  B 初次使用默认配置（需求2）
  C 弹窗背景回归 + 标题背景移除（需求3）
  D 新拟态引擎与替换面（需求4）
  E 设置页文字重影/布局（需求5）
  F 发布资产
  G 语法配平 + UIColor 白名单
  H 回归锚点
"""
import os
import re
import subprocess
import sys

# Task161：ROOT 环境注入（沿用 TASK150_REPO 惯例）——原硬编码另一会话沙箱
# 路径 /home/z/my-project/workspace/...，本仓库运行直接 FileNotFoundError。
ROOT = os.environ.get('TASK160_REPO', '/home/z/my-project/Amethyst-iOS-MyRemastered')
PASS, FAIL = 0, 0


def read(rel):
    return open(f'{ROOT}/{rel}', encoding='utf-8').read()


def check(name, cond, detail=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def balanced(rel):
    """字符状态机版配平检查（单遍扫描：注释/字符串/字符字面量按出现顺序判定，
    避免正则先剥注释误伤字符串内的 // 或注释内的引号）"""
    text = read(rel)
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c == '"':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == "'":
                    break
                j += 1
            i = j + 1
        else:
            out.append(c)
            i += 1
    code = ''.join(out)
    return code.count('{') == code.count('}') and code.count('(') == code.count(')')


print("=" * 72)
print("A. 分辨率缩放行（per-instance，样式统一 + 25~150）")
print("=" * 72)
ps = read('Natives/ProfileSettingsViewController.m')
check("A1  输入框灰字 + 系统 detail 字号（内存分配行同款）",
      "textField.font = [UIFont systemFontOfSize:17];" in ps
      and "textField.textColor = [UIColor secondaryLabelColor];" in ps)
check("A2  独立 % 标签保留（17pt 同字号，不在输入框内）",
      'percentLabel.text = @"%";' in ps
      and "percentLabel.font = [UIFont systemFontOfSize:17];" in ps)
check("A3  容器尾端仿系统 chevron（accessoryView 占位后补齐向右箭头）",
      '[UIImage systemImageNamed:@"chevron.right"]' in ps
      and "chevronView.tintColor = [UIColor tertiaryLabelColor];" in ps)
check("A4  容器宽度扩至 96（输入框 56 + % + 箭头）",
      "CGRectMake(0, 0, 96, 30)" in ps)
check("A5  clamp 放宽到 [25, 150]（旧全局滑条口径）",
      "if (ame159_value > 150) ame159_value = 150;" in ps
      and "ame159_value > 100" not in ps)
check("A6  行内输入保留（NumberPad + Done 条 + DidEnd 落盘）",
      "textField.keyboardType = UIKeyboardTypeNumberPad;" in ps
      and "UIBarButtonSystemItemDone target:textField action:@selector(resignFirstResponder)" in ps
      and "- (void)resolutionScaleDidEnd:(UITextField *)textField {" in ps)
check("A7  行注释口径同步（25~150 + 内存分配同款）",
      "Task160：per-instance 分辨率缩放（25~150）" in ps)

print()
print("=" * 72)
print("B. 初次使用默认配置（仅新装/重置生效）")
print("=" * 72)
plp = read('Natives/PLPreferences.m')
bm = read('Natives/BackgroundManager.m')
check("B1  ui_theme 默认（Task161 重锚：用户指令“外观模式默认跟随系统”，推翻 Task160 的 light 缺省 → auto + 迁移）",
      '@"ui_theme": @"auto",' in plp
      and 'ui_theme_explicit' in plp)
check("B2  uiOpacity 默认 0.6（Task162 重锚：用户定稿“毛玻璃，60% 的透明度，100% 的模糊”，推翻 Task160 的 0.1 缺省）",
      "_uiOpacity = 0.6;" in bm and "_uiOpacity = 0.1;" not in bm and "_uiOpacity = 0.7;" not in bm)
check("B3  blurIntensity 默认 1.0（Task162 重锚：100%）",
      "_blurIntensity = 1.0;" in bm and "_blurIntensity = 0.75;" not in bm and "_blurIntensity = 0.7; //" not in bm)
check("B4  默认效果仍为毛玻璃（BackgroundUIEffectBlur）",
      "_uiEffect = BackgroundUIEffectBlur;" in bm)
check("B5  仅初次使用语义注释（存量用户设置不变；Task161 补充：未显式选择的设备历史默认迁移到 auto；Task162 重锚：透明度/模糊注释改口径；Task164 重锚：nil 判定后病历注释承载首次语义）",
      "仅新装/重置偏好生效，存量用户已保存的值不变" in plp
      and "从未保存" in bm)

print()
print("=" * 72)
print("C. 弹窗背景回归 + 标题背景移除")
print("=" * 72)
check("C1  毛玻璃底方法存在且被 makeViewControllerTransparent 调用",
      "- (void)ame160_applyGlassBackdropIfModal:(UIViewController *)viewController {" in bm
      and "[self ame160_applyGlassBackdropIfModal:viewController];" in bm)
check("C2  弹窗判定：presenting 链（直接 present 或弹窗 nav 内 push）",
      "viewController.presentingViewController != nil" in bm
      and "viewController.navigationController.presentingViewController != nil" in bm)
check("C3  页面级 SystemThinMaterial 毛玻璃 + tag 防重复",
      "UIBlurEffectStyleSystemThinMaterial" in bm
      and "kAme160GlassBackdropTag = 99994" in bm
      and "[viewController.view insertSubview:glass atIndex:0];" in bm)
check("C4  仅毛玻璃分支铺设（半透明模式走既有底色逻辑）",
      bm.count("ame160_applyGlassBackdropIfModal") == 2)  # 声明+调用
check("C5  VMSectionHeader 毛玻璃块整块移除（blurView 引用清零）",
      "blurView" not in read('Natives/VersionManagerViewController.m'))
check("C6  VM 标题直接浮在壁纸上（退役注释留档）",
      "SystemMaterial 毛玻璃块整块退役" in read('Natives/VersionManagerViewController.m'))

print()
print("=" * 72)
print("D. 新拟态引擎（Task160 CSS 规格原生实现）")
print("=" * 72)
nsm = read('Natives/UIKit+NativeSurface.m')
nsh = read('Natives/UIKit+NativeSurface.h')
check("D1  规格动态色五件套（表面/暗影/高光/主文字/次文字）",
      all(f"AmeNeumorph{x}Color(void)" in nsm for x in
          ["Surface", "Shadow", "Highlight", "PrimaryText", "SecondaryText"]))
check("D2  CSS 色值核对（Task177 重锚：暗影 bebebe -> bigbear-ui d6d6d6；渐变端 e6e6e6/ffffff 入列）",
      all(hexv in nsm for hexv in
          ["0xE0/255.0", "0x2C/255.0", "0xD6/255.0", "0x1E/255.0", "0x3A/255.0",
           "0x33/255.0", "0xF5/255.0", "0x88/255.0", "0xA0/255.0", "0xE6/255.0"]))
check("D3  度量（Task177 重锚：圆角仍 340 基准等比 clamp[8,50]；偏移/模糊改固定档 4/8（小件 2/4）——20/60 等比放大退役）",
      "AmeNeumorphBaseDimension = 340.0" in nsm
      and "MAX(8.0, 50.0 * scale)" in nsm
      and "? 2.0 : 4.0" in nsm
      and "? 4.0 : 8.0" in nsm)
check("D4  双阴影承载视图（Task177 重锚：暗影右下 + 高光左上维持；透明承载层改三层结构——投影对垫底 + 不透明渐变表面盖内侧）",
      "AmeNeumorphShadowView : UIView" in nsh
      and "CGSizeMake(offset, offset)" in nsm
      and "CGSizeMake(-offset, -offset)" in nsm
      and "ame177_surfaceLayer" in nsm and "shadowOpacity = 1.0" in nsm)
check("D5  深浅色切换自动重刷（traitCollectionDidChange）",
      "traitCollectionDidChange:" in nsm
      and "AmeNeumorphDynamicColor" in nsm)
check("D6  表面方法路由（Task163 重锚：Panel 退役阴影转 Flat——侧栏/右面板全屏大容器等比阴影溢出压到中央卡片，用户指令；Card/Raised 仍走新拟态）",
      nsm.count("[self ame_applyNeumorphSurface];") == 2
      and "[self ame_applyNeumorphSurfaceFlatWithRadius:cornerRadius];" in nsm)
check("D7  cell 平贴版（无阴影层，防列表裁剪互叠）",
      "- (void)ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius {" in nsm
      and "self.layer.masksToBounds = YES;" in nsm)
check("D8  宿主放行阴影（masksToBounds = NO，Task137 裁剪教训）",
      "self.layer.masksToBounds = NO; // Task137 教训：YES 会裁掉外阴影" in nsm)
check("D9  文字色规格化落点（主页磁贴/公告卡/新闻卡/版本卡/VM header/Hero/Toast/右面板）",
      read('Natives/LauncherNewsViewController.m').count("AmeNeumorphSecondaryTextColor(); // Task160 新闻卡简介") == 1
      and "AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in read('Natives/VersionCardCell.m')
      and "AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in read('Natives/VersionManagerViewController.m')
      and "AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in read('Natives/NMToast.m')
      and "AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in read('Natives/LauncherRightPanelViewController.m')
      and "titleLabel.textColor = AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in read('Natives/ProfileSettingsViewController.m'))
check("D10 Hero 卡旧黑影/白边框/半透明白底移除",
      "heroCard.layer.shadowColor = [UIColor blackColor].CGColor;" not in read('Natives/ProfileSettingsViewController.m')
      and "heroCard.layer.shadowColor = [UIColor blackColor].CGColor;" not in read('Natives/LauncherPreferencesViewController.m'))

print()
print("=" * 72)
print("E. 设置页文字重影/布局修复")
print("=" * 72)
pref = read('Natives/LauncherPreferencesViewController.m')
plpt = read('Natives/PLPrefTableViewController.m')
mjre = read('Natives/LauncherPrefManageJREViewController.m')
check("E1  cell 文字阴影清零（重影来源移除）",
      "cell.textLabel.shadowColor = [UIColor blackColor];" not in pref
      and "cell.detailTextLabel.shadowColor = [UIColor blackColor];" not in pref)
check("E2  header/footer 文字阴影清零 + 原生色",
      "header.textLabel.shadowColor = nil;" in pref
      and "footer.textLabel.shadowColor = nil;" in pref
      and "footer.textLabel.textColor = [UIColor secondaryLabelColor]; // Task160：原生次要色" in pref)
check("E3  detail 写死 0.8 灰退役（原生 secondaryLabel）",
      "cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];" in pref
      and "cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];" not in pref)
check("E4  Subtitle 布局回归原生单行（换行不再压到小字）",
      plpt.count("cell.textLabel.numberOfLines = 1;") == 2
      and "cell.detailTextLabel.numberOfLines = 1;" in plpt)
check("E5  管理 JRE header 同口径去阴影",
      "header.textLabel.shadowColor = nil;" in mjre
      and "header.textLabel.shadowColor = [UIColor blackColor];" not in mjre)
check("E6  自定义 label 循环同步去阴影",
      "// Task160：同步去阴影（重影修复）" in pref)

print()
print("=" * 72)
print("F. 发布资产")
print("=" * 72)
ann = read('announcements.json')
import json
try:
    json.loads(ann)
    valid = True
except Exception:
    valid = False
check("F1  announcements.json 合法 + summary 尾追加（Task162 重锚：默认值文案改 60%/100% + 跟随系统）",
      valid and "新拟态 UI 回归（双阴影高光按 CSS 规格原生实现）、外观跟随系统与毛玻璃新默认（透明度 60%/模糊 100%）" in ann)
check("F2  content 新增「新拟态 UI 与默认体验」块（四 bullet）",
      "**新拟态 UI 与默认体验（本轮视觉大改）**" in ann
      and "**新拟态 UI 全面回归**" in ann
      and "**初次使用默认配置更新**" in ann
      and "**弹窗背景回归**" in ann
      and "**设置页文字重影修复**" in ann)
check("F3  分辨率 bullet 口径更新（灰字箭头样式 + 25~150）",
      "右侧参数改为与内存分配同款灰字+向右箭头样式" in ann
      and "可编辑 25~150" in ann)
check("F4  EN 尾段同步（Task162 重锚：opacity 60% / blur 100%）",
      "native Neumorphism per the user's CSS spec" in ann
      and "opacity 60% / blur 100%" in ann
      and "clamp widened to 25-150" in ann)
vh = read('Natives/external/MobileGlues/MobileGlues-cpp/version.h')
check("F5  version.h REVISION 17 addendum (Task 160)",
      "REVISION 17 addendum (Task 160, no bump): Neumorphism UI regression" in vh)

print()
print("=" * 72)
print("G. 语法配平 + UIColor 白名单")
print("=" * 72)
files = ['Natives/ProfileSettingsViewController.m', 'Natives/BackgroundManager.m',
         'Natives/PLPreferences.m', 'Natives/LauncherPreferencesViewController.m',
         'Natives/PLPrefTableViewController.m', 'Natives/LauncherPrefManageJREViewController.m',
         'Natives/VersionManagerViewController.m', 'Natives/VersionCardCell.m',
         'Natives/LauncherNewsViewController.m', 'Natives/UIKit+NativeSurface.m',
         'Natives/NMToast.m', 'Natives/LauncherRightPanelViewController.m']
ok = all(balanced(f) for f in files)
check("G  12 个改动文件括号配平", ok)
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
check("G  ProfileSettingsViewController UIColor 白名单审计", not bad, str(bad[:6]))

print()
print("=" * 72)
print("H. 回归锚点")
print("=" * 72)
check("H1  内存行口径幸存（Task157/159：auto_row + %ld MB；Task163 重锚：箭头统一为自绘 chevron，系统 disclosure 清零）",
      "localize(@\"memory.auto_row\", nil)" in ps
      and '[NSString stringWithFormat:@"%ld MB", (long)self.allocatedMemory]' in ps
      and "cell.accessoryView = [self ame163_disclosureChevron];" in ps)
check("H2  内存输入框弹窗幸存（Task159：adjust_title/adjust_message + clamp 512）",
      "localize(@\"memory.adjust_title\", nil)" in ps
      and "localize(@\"memory.adjust_message\", nil)," in ps)
check("H3  Sodium + Iris 行与三 jar 链幸存（Task157 契约）",
      "Sodium + Iris Shaders" in ps and "startInstallSodiumWithGameVersion" in ps)
check("H4  ui_theme 消费链未动（SceneDelegate 读 general.ui_theme）",
      "general.ui_theme" in read('Natives/SceneDelegate.m'))
check("H5  makeViewControllerTransparent 旧透明化契约幸存（无壁纸 return）",
      "if (![self hasBackground]) {" in bm)
check("H6  AmeBadgeLabel 三件套幸存（intrinsic + insets + 胶囊）",
      "intrinsicContentSize" in nsm and "textRectForBounds:" in nsm
      and "self.layer.cornerRadius = h / 2.0;" in nsm)

print()
print("=" * 72)
print(f"{PASS} passed, {FAIL} failed")
print("=" * 72)
print(f"==== RESULT: {'PASSED' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}) ====")
sys.exit(0 if FAIL == 0 else 1)
