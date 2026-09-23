#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task147.py —— Task 149 校验器

用户六项返工需求（Task 141 实装后的实测反馈）：
  1. 欢迎卡头像首帧即默认头像（DefaultAccount），不再"点击后才加载"——
     cell init 直接呈现 DefaultAccount + viewWillAppear 刷新双保险。
  2. 欢迎卡删掉更新语句（公告标题行）及查看详情按钮；第二行回归灰字问候语；
     头像等边距：到左边缘 = 到上/下边缘（layoutSubviews 按 side/2 动态刷新
     左边距与文字间距，卡片/头像尺寸均不变）。
  3. 更新卡片（公告磁贴）与 MC 新闻磁贴高度与"最新正式版"磁贴等高（100pt）：
     高度不够简介优先截断；公告卡喇叭图标垂直居中、标题/简介样式对齐新闻卡、
     查看详情按钮内联到标题后（缩小）；新闻卡缩略图等边距居中、文字相对缩略图
     居中；版本号核查结论 = announcements.json 驱动（保持，无代码改动）；
     新闻页恢复双列并列排 + 简介全部显示（自 sizing 高度）+ 禁横向滑保留。
  4. 主页面所有卡片取消阴影（HomeTileBaseCell 阴影四件套退役）。
  5. 公告列表页公告卡周围蓝色圆角矩形边边删除（priorityBarView 整体退役，
     priority=high 蓝条逻辑一并删除）。
  6. 内存分配弹窗改 iOS 原生底部面板：Ame149MemoryAllocatorController +
     UISheetPresentationController（iOS 15+ medium 档 + 抓手；更低版本回退
     formSheet），写回链路不变。

分节：A 欢迎卡(1,2) / B 主页卡片高度与阴影(3,4) / C 更新卡与新闻卡重排(3) /
      D 公告列表蓝条(5) / E 内存弹窗(6) / F 新闻页双列(3尾) / G 语法配平
"""
import os
import re
import sys

REPO = os.environ.get("TASK149_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
PASS = 0
FAIL = 0


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
        print(f"  FAIL  {name}  {detail}")


print("=" * 72)
print("A. 欢迎卡：首帧默认头像 + 问候语回归 + 头像等边距（Item 1 + 2）")
print("=" * 72)
home = read("Natives/LauncherNewsViewController.m")
home_code = strip_objc(home)
check("A1  首帧默认头像：cell init 直接呈现 DefaultAccount（缺失回退 SF 占位）",
      'UIImage *ame149_defaultAvatar = [UIImage imageNamed:@"DefaultAccount"];' in home
      and "self.avatarImageView.image = ame149_defaultAvatar;" in home
      and "self.avatarImageView.contentMode = UIViewContentModeScaleAspectFill;" in home.split("if (ame149_defaultAvatar)")[1].split("} else")[0])
check("A2  viewWillAppear 刷新保险（updateSkinDisplay 二次补齐账号态）",
      "- (void)viewWillAppear:(BOOL)animated {" in home
      and "[self updateSkinDisplay];" in home.split("- (void)viewWillAppear:(BOOL)animated")[1].split("- (void)dealloc")[0])
check("A3  公告标题行退役（announceIconView/announceLabel/detailButton/announceRowStack 引用清零）",
      all(x not in home for x in ["announceIconView", "announceLabel", "detailButton", "announceRowStack"]))
check("A4  问候语行回归（greetingLabel 14pt medium secondary + festivalGreeting）",
      "self.greetingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];" in home
      and "self.greetingLabel.textColor = [UIColor secondaryLabelColor];" in home
      and "cell.greetingLabel.text = festivalGreeting();" in home)
check("A5  欢迎堆叠 = [welcomeLabel, greetingLabel]（相对头像纵轴居中保留）",
      "initWithArrangedSubviews:@[self.welcomeLabel, self.greetingLabel]" in home
      and "welcomeStack.centerYAnchor constraintEqualToAnchor:self.avatarImageView.centerYAnchor" in home)
check("A6  头像等边距：动态约束在位（avatarLeadingConstraint/textLeadingConstraint）",
      "avatarLeadingConstraint" in home and "textLeadingConstraint" in home)
check("A7  等边距刷新：layoutSubviews 按 side/2 同步左边距与文字间距",
      "self.avatarLeadingConstraint.constant = side / 2.0;" in home
      and "self.textLeadingConstraint.constant = side / 2.0;" in home
      and "avatarImageView.layer.cornerRadius = side / 2.0" in home)
check("A8  尺寸零变化：头像仍为卡高 0.5 倍正圆（width=height）",
      "heightAnchor constraintEqualToAnchor:self.contentContainer.heightAnchor multiplier:0.5" in home
      and "avatarImageView.widthAnchor constraintEqualToAnchor:self.avatarImageView.heightAnchor" in home)

print()
print("=" * 72)
print("B. 主页卡片高度与阴影（Item 3 高度 + Item 4）")
print("=" * 72)
check("B1  主页卡片阴影退役（shadowColor/Offset/Opacity/Radius 引用清零）",
      all(x not in home for x in [
          "self.layer.shadowColor",
          "self.layer.shadowOffset",
          "self.layer.shadowOpacity",
          "self.layer.shadowRadius"]))
check("B2  公告/新闻磁贴与最新正式版磁贴等高（Task149 固定 100）",
      home.count("Task149：与最新正式版卡片等高") == 2)
check("B3  自适应高度函数退役（ame138_announcementTileHeight 代码引用清零）",
      "ame138_announcementTileHeight" not in home_code
      and "boundingRectWithSize" not in home_code)
check("B4  版本磁贴高度仍为 100（等高基准不变）",
      re.search(r"case HomeTileTypeVersionRelease:\s*\n\s*case HomeTileTypeVersionSnapshot:\s*\n\s*return 100;", home) is not None)

print()
print("=" * 72)
print("C. 更新卡片（公告磁贴）重排（Item 3）")
print("=" * 72)
check("C1  喇叭图标垂直居中（centerY = contentContainer.centerY）",
      re.search(r"HomeAnnouncementTileCell[\s\S]*?iconView\.centerYAnchor constraintEqualToAnchor:self\.contentContainer\.centerYAnchor", home) is not None)
ann_impl = home.split("@implementation HomeAnnouncementTileCell")[1].split("\n@end")[0]
check("C2  标题/简介样式对齐新闻卡片（标题 15pt semibold / 简介 12pt tertiary）",
      "self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];" in ann_impl
      and "self.summaryLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];" in ann_impl
      and "self.summaryLabel.textColor = [UIColor tertiaryLabelColor];" in ann_impl)
check("C3  查看详情按钮内联标题后（titleRowStack 横向栈 + 缩小 12pt/28pt 高）",
      "initWithArrangedSubviews" not in home.split("self.titleRowStack = ")[1].split("];")[0]
      and "[self.titleRowStack addArrangedSubview:self.titleLabel];" in home
      and "[self.titleRowStack addArrangedSubview:self.actionButton];" in home
      and "self.actionButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];" in home
      and "[self.actionButton.heightAnchor constraintEqualToConstant:28].active = YES;" in home)
check("C4  简介优先截断（750 < 标题行 998 的压缩序）",
      "[self.summaryLabel setContentCompressionResistancePriority:750 forAxis:UILayoutConstraintAxisVertical];" in ann_impl
      and "[self.titleRowStack setContentCompressionResistancePriority:998 forAxis:UILayoutConstraintAxisVertical];" in ann_impl)
check("C5  预览档位语义收敛（title_only 隐藏简介；公告卡 cellForItem 标题/简介分离）",
      "cell.titleLabel.text = ann.title;" in home
      and "ame149_showSummary" in home
      and "cell.summaryLabel.hidden = !ame149_showSummary;" in home)
check("C6  公告卡 cellForItem 不再使用 messageLabel（旧多行消息体退役）",
      "messageLabel" not in home)

print()
print("=" * 72)
print("D. 公告列表蓝条删除（Item 5）")
print("=" * 72)
annlist = read("Natives/AnnouncementListViewController.m")
annlist_code = strip_objc(annlist)
check("D1  priorityBarView 整体退役（属性/创建/约束/配置代码引用清零）",
      "priorityBarView" not in annlist_code
      and "kAnnHighPriorityBarWidth" not in annlist_code)
check("D2  其余卡片结构零变化（标题 16pt semibold / 日期 11pt / 简介 13pt + 圆角 14）",
      "_titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];" in annlist
      and "_dateLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];" in annlist
      and "_summaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];" in annlist
      and "kAnnCardCornerRadius = 14.0" in annlist)

print()
print("=" * 72)
print("E. 内存分配原生底部面板（Item 6）")
print("=" * 72)
ps = read("Natives/ProfileSettingsViewController.m")
ps_code = strip_objc(ps)
check("E1  原生面板控制器（Ame149MemoryAllocatorController 定义 + 实现）",
      "@interface Ame149MemoryAllocatorController : UIViewController" in ps_code
      and "@implementation Ame149MemoryAllocatorController" in ps_code)
check("E2  UISheetPresentationController 呈现（iOS 15+ medium 档 + 抓手）",
      "UISheetPresentationControllerDetent.mediumDetent" in ps_code
      and "prefersGrabberVisible = YES" in ps_code
      and "if (@available(iOS 15.0, *)) {" in ps_code)
check("E3  低版本兼容回退（formSheet）",
      "ame149_vc.modalPresentationStyle = UIModalPresentationFormSheet;" in ps_code)
check("E4  旧遮罩自绘弹窗退役（UIControl *dimming / 0.4 黑遮罩 / 关联对象键清零）",
      "UIControl *dimming" not in ps_code
      and "colorWithWhite:0 alpha:0.4" not in ps_code
      and "kAme141MemorySliderKey" not in ps_code
      and "- (void)dismissMemoryAllocator" not in ps_code
      and "- (void)applyMemoryAllocation" not in ps_code)
check("E5  拉条区间与写回链路不变（512 → maxMemory；ameOnApply → allocatedMemory → saveSettings）",
      "self.ameSlider.minimumValue = 512;" in ps_code
      and "self.ameSlider.maximumValue = (float)MAX(1024, self.ameMaxMemory);" in ps_code
      and "strongSelf.allocatedMemory = memoryMB;" in ps_code
      and "[strongSelf saveSettings];" in ps_code
      and "[strongSelf reloadAllTableViews];" in ps_code)
check("E6  当前内存灰字实时刷新（memory.current + ame147SliderChanged）",
      'localize(@"memory.current", nil)' in ps
      and "- (void)ame147SliderChanged:(UISlider *)sender" in ps_code)

print()
print("=" * 72)
print("F. MC 新闻页：双列恢复 + 简介完整 + 禁横向滑（Item 3 尾）")
print("=" * 72)
mcnews = read("Natives/MinecraftNewsViewController.m")
mcnews_code = strip_objc(mcnews)
check("F1  恢复双列并列排（每组两个 0.5 宽子项 + interItemSpacing 12）",
      "fractionalWidthDimension:0.5]" in mcnews_code
      and "subitems:@[ame149_itemA, ame149_itemB]" in mcnews_code
      and "fixedSpacing:kNewsCardSpacing]" in mcnews_code)
check("F2  简介全部显示（numberOfLines = 0）+ 高度自 sizing（estimated 280；固定机制代码清零）",
      "_summaryLabel.numberOfLines = 0;" in mcnews
      and "estimatedDimension:280" in mcnews_code
      and "newsCardFixedHeight" not in mcnews_code)
check("F3  禁横向滑动保留（alwaysBounceHorizontal = NO）",
      "self.collectionView.alwaysBounceHorizontal = NO;" in mcnews)
check("F4  侧边距（8,8,8,8，公告列表页同款语言；单列时代的 (8,0,8,0) 退役）",
      "UIEdgeInsetsMake(8, 8, 8, 8)" in mcnews
      and "UIEdgeInsetsMake(8, 0, 8, 0)" not in mcnews)

print()
print("=" * 72)
print("G. 语法配平 + UIColor 白名单抽查")
print("=" * 72)
for name, path in [
    ("LauncherNewsViewController.m", "Natives/LauncherNewsViewController.m"),
    ("MinecraftNewsViewController.m", "Natives/MinecraftNewsViewController.m"),
    ("AnnouncementListViewController.m", "Natives/AnnouncementListViewController.m"),
    ("ProfileSettingsViewController.m", "Natives/ProfileSettingsViewController.m"),
]:
    check(f"G  {name} 括号配平", balanced(read(path)))

ulu = read("Natives/UIKit+NativeSurface.h")
ALLOWED_UICOLOR = [
    "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
    "systemBackgroundColor", "secondarySystemBackgroundColor", "tertiarySystemBackgroundColor",
    "secondarySystemGroupedBackgroundColor", "tertiarySystemGroupedBackgroundColor",
    "systemGroupedBackgroundColor", "tertiarySystemFillColor", "separatorColor",
    "systemRedColor", "systemBlueColor", "systemOrangeColor", "systemGreenColor",
    "systemGrayColor", "systemTealColor", "whiteColor", "clearColor", "blackColor",
]
bad = []
for m in re.finditer(r"\[UIColor ([A-Za-z]+(?:Color|Fill)?)\]", read("Natives/LauncherNewsViewController.m")):
    if m.group(1) not in ALLOWED_UICOLOR:
        bad.append(m.group(1))
check("G  LauncherNewsViewController UIColor 白名单审计（无硬编码异常色）", not bad, str(bad[:6]))

print()
print("=" * 72)
total = PASS + FAIL
print(f"==== RESULT: {'PASSED' if FAIL == 0 else 'FAILED'} ({PASS}/{total}) ====")
sys.exit(0 if FAIL == 0 else 1)
