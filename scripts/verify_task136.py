#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task136.py —— Task 136 校验器
用户八项 UI 需求（新闻卡新拟态+固定高度 / 主页顶卡头像交换 / 列表右侧小字框 /
深浅色动态检测 / 下载页模组加载器卡片化 / 设置页图标本体 / 全局新拟态新色板）+
历史校验器重锚自检。
口径护栏（Task93 检测链）零变化断言保留。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK136_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
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
print("A. NMTheme Task136 新色板（用户指定 CSS 色板忠实落地）")
print("=" * 72)
theme_m = read("Natives/NeomorphKit/NMTheme.m")
theme_h = read("Natives/NeomorphKit/NMTheme.h")
cat_m = read("Natives/NeomorphKit/UIView+Neomorph.m")
cat_h = read("Natives/NeomorphKit/UIView+Neomorph.h")

check("A1  浅色 surface #E0E0E0（+raised #E8E8E8 / bg #D6D6D6）",
      "kLightSurface        = @\"#E0E0E0\"" in theme_m
      and "kLightSurfaceRaised  = @\"#E8E8E8\"" in theme_m
      and "kLightBackground     = @\"#D6D6D6\"" in theme_m)
check("A2  深色 surface #2C2C2C（+raised #333333 / bg #252525）",
      "kDarkSurface         = @\"#2C2C2C\"" in theme_m
      and "kDarkSurfaceRaised   = @\"#333333\"" in theme_m
      and "kDarkBackground      = @\"#252525\"" in theme_m)
check("A3  主文字色 浅 #333333 / 深 #F5F5F5（0x33/0xF5 直写）",
      "0x33 / 255.0" in theme_m and "0xF5 / 255.0" in theme_m)
check("A4  次要文字色 浅 #888888 / 深 #A0A0A0",
      "0x88 / 255.0" in theme_m and "0xA0 / 255.0" in theme_m)
check("A5  阴影色 浅 #BEBEBE/#FFFFFF、深 #1E1E1E/#3A3A3A",
      all(h in theme_m for h in ["#BEBEBE", "#FFFFFF", "#1E1E1E", "#3A3A3A"]))
check("A6  阴影透明度固定 1.0（CSS 全 alpha 直绘，旧亮度换算退役）",
      theme_m.count("return 1.0;") >= 2
      and "0.025 + (1.0 - 0.025) * opacity" not in theme_m
      and "0.35 * (1.0 - opacity)" not in theme_m)
check("A7  旧色板残留清零（ECF0F3/262A2F/222222/EEEEEE 不在实现中）",
      all(k not in theme_m for k in ["ECF0F3", "262A2F"])
      and "0x22 / 255.0" not in theme_m and "0xEE / 255.0" not in theme_m)
check("A8  引擎默认凸出样式 = 圆角 50 / 阴影 10（nm_convex）",
      "[self nm_convexRadius:50 shadowRadius:10];" in cat_m)
check("A9  按钮默认样式 = 圆角 50 / 阴影 10（nm_styleConvexButton）",
      "[self nm_styleConvexButtonRadius:50 shadowRadius:10];" in cat_m)
check("A10 夹断规则保留（radius = MIN(radius, w/2, h/2)，50px 超尺寸自动夹断）",
      "MIN(size.height / 2.0, size.width / 2.0)" in cat_m
      and "MIN(radius, size.width / 2.0)" in cat_m)
check("A11 NeomorphKit 全文件括号配平",
      all(balanced(x) for x in [theme_m, cat_m, theme_h, cat_h,
                                read("Natives/NeomorphKit/NMToast.m"),
                                read("Natives/NeomorphKit/NMContrast.m")]))

print()
print("=" * 72)
print("B. NMContrast 动态文字对比度修复器（Item 4a：深浅色动态检测）")
print("=" * 72)
nc_m = read("Natives/NeomorphKit/NMContrast.m")
nc_h = read("Natives/NeomorphKit/NMContrast.h")
cmake = read("Natives/CMakeLists.txt")
check("B1  NMContrast.{h,m} 存在并登记 CMakeLists",
      "NeomorphKit/NMContrast.m" in cmake)
check("B2  WCAG 对比度阈值 2.0 + 饱和表面跳过 0.35",
      "kNMContrastFixThreshold = 2.0" in nc_m
      and "kNMSaturationSkipThreshold = 0.35" in nc_m)
check("B3  自管理扫描：监听主题切换 + 背景效果切换广播",
      "NMThemeDidChangeNotification" in nc_m
      and "BackgroundUIEffectChanged" in nc_m)
check("B4  修复动作：UIButton setTitleColor / UILabel textColor → [NMTheme nm_label]",
      "setTitleColor:[NMTheme nm_label]" in nc_m
      and "label.textColor = [NMTheme nm_label];" in nc_m)
check("B5  有效背景解析：不透明实色判定 + 无法解析时宁可不改",
      "NMEffectiveBackgroundColor" in nc_m and "a < 0.9" in nc_m)
check("B6  SceneDelegate 接线：启动扫描 + 窗口底色主题化",
      "[NMContrast nm_startContrastSweep];" in read("Natives/SceneDelegate.m")
      and "self.window.backgroundColor = [NMTheme nm_background];" in read("Natives/SceneDelegate.m"))

print()
print("=" * 72)
print("C. BackgroundManager 枢纽（阴影基准 10 / 卡片化方法 / 裁剪放开）")
print("=" * 72)
bm = read("Natives/BackgroundManager.m")
bmh = read("Natives/BackgroundManager.h")
check("C1  applyCardEffectToCell 新方法（h+m），无背景 → contentView 凸出 50/10",
      "applyCardEffectToCell" in bmh
      and "[cell.contentView nm_convexRadius:50 shadowRadius:10];" in bm)
check("C2  applyCardEffectToCell 有背景 → 与 applyEffectToCell 同管线",
      re.search(r"applyCardEffectToCell:\(UITableViewCell \*\)cell \{[\s\S]{0,400}?if \(\[self hasBackground\]\) \{\s*\[self applyEffectToCell:cell\];", bm))
check("C3  collection cell 无背景分支放开 cell 级裁剪（新拟物阴影可见）",
      "cell.clipsToBounds = NO;" in bm and "cell.layer.masksToBounds = NO;" in bm)
check("C4  collection cell 圆角来源升级：优先读 contentView 自身圆角",
      "cell.contentView.layer.cornerRadius > 0" in bm)
check("C5  applyEffectToView 阴影基准 10（旧 radius*0.5 上限 8 规则退役）",
      "[view nm_convexRadius:radius shadowRadius:10];" in bm
      and "MAX(4.0, MIN(8.0, radius * 0.5))" not in bm)
check("C6  检测并切换架构原样保留（hasBackground 双分支 + nm_removeNeomorph 清残留）",
      bm.count("[view nm_removeNeomorph];") >= 1
      and "SystemThinMaterial" in bm)

print()
print("=" * 72)
print("D. Item 1：MC 新闻卡新拟态 + 固定最低高度")
print("=" * 72)
mcnews = read("Natives/MinecraftNewsViewController.m")
check("D1  卡片圆角基准 50（kNewsCardCornerRadius = 50.0）",
      "kNewsCardCornerRadius = 50.0" in mcnews)
check("D2  固定高度 = 原样式最低高度（模板 cell 实测，dispatch_once 缓存）",
      "newsCardFixedHeight" in mcnews
      and "systemLayoutSizeFitting" in mcnews
      and "dispatch_once" in mcnews)
check("D3  布局改用绝对高度（absoluteDimension），旧 estimated 280 退役",
      mcnews.count("absoluteDimension:cardHeight]") == 2
      and "estimatedDimension:280" not in mcnews)
check("D4  正文纵向 stack + 截断优先级（摘要 750 先截断，标题/作者/查看详情保底）",
      "initWithArrangedSubviews:@[_titleLabel, _metaLabel, _summaryLabel, _readMoreLabel]" in mcnews
      and "setContentCompressionResistancePriority:750 forAxis:UILayoutConstraintAxisVertical" in mcnews
      and "setCustomSpacing:4 afterView:_titleLabel" in mcnews)
check("D5  新闻页底色主题化（nm_background）",
      "self.view.backgroundColor = [NMTheme nm_background];" in mcnews
      and "self.view.backgroundColor = [UIColor systemBackgroundColor];" not in mcnews)

print()
print("=" * 72)
print("E. Item 2：主页顶卡头像交换 + 欢迎语纵轴居中")
print("=" * 72)
home = read("Natives/LauncherNewsViewController.m")
check("E1  皮肤全身预览退场（skinImageView 代码引用清零，仅留档注释）",
      len(re.findall(r"self\.skinImageView", home)) == 0)
check("E2  MC 头像接管最左位（leading 18 + 尺寸随卡高 0.5 倍 + 正圆 width=height）",
      "avatarImageView.leadingAnchor ... constant:18" not in home
      and re.search(r"avatarImageView\.leadingAnchor constraintEqualToAnchor:self\.contentContainer\.leadingAnchor constant:18\]", home)
      and "heightAnchor constraintEqualToAnchor:self.contentContainer.heightAnchor multiplier:0.5" in home
      and "avatarImageView.widthAnchor constraintEqualToAnchor:self.avatarImageView.heightAnchor" in home)
check("E3  半透明边框样式保留（2.5pt white@0.35）+ 圆形裁剪 masksToBounds",
      "layer.borderWidth = 2.5" in home
      and "colorWithWhite:1.0 alpha:0.35" in home
      and "avatarImageView.layer.masksToBounds = YES" in home)
check("E4  两行欢迎句 stack 相对头像纵轴居中（centerY = avatar.centerY）",
      "initWithArrangedSubviews:@[self.welcomeLabel, self.greetingLabel]" in home
      and re.search(r"welcomeStack\.centerYAnchor constraintEqualToAnchor:self\.avatarImageView\.centerYAnchor\]", home))
check("E5  头像圆角随尺寸取半（layoutSubviews 动态）",
      "avatarImageView.layer.cornerRadius = side / 2.0" in home)
check("E6  皮肤全身图请求退役（updateSkinDisplay 不再调用 loadSkinForUUID）",
      "[self loadSkinForUUID:" not in home.split("@implementation LauncherNewsViewController")[1])

print()
print("=" * 72)
print("F. Item 3：列表右侧小字框（动态宽度 / 防裁剪靠右 / 尺寸对齐两行字）")
print("=" * 72)
vc = read("Natives/VersionCardCell.m")
vm = read("Natives/VersionManagerViewController.m")
acct = read("Natives/AccountListViewController.m")
check("F1  版本类型胶囊（正式版/测试版）：12pt + 高 24 + 内边距 8 + 圆角随高取半",
      "systemFontOfSize:12 weight:UIFontWeightSemibold" in vc
      and "typeLabel.heightAnchor constraintEqualToConstant:24" in vc
      and "UIEdgeInsetsMake(0, 8, 0, 8)" in vc
      and "self.layer.cornerRadius = h / 2.0" in vc)
check("F2  版本类型胶囊靠右锚定 chevron 左侧 8pt（不贴卡片边缘）",
      "typeLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-8" in vc)
check("F3  版本类型胶囊移出顶行 stack（独立靠右，版本号侧留 8pt 间隙）",
      "initWithArrangedSubviews:@[self.versionLabel]]" in vc
      and "topRowStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.typeLabel.leadingAnchor constant:-8" in vc)
check("F4  计数徽章（游戏目录/已安装版本）：高 24 ≈ 两行字 + 圆角 12 + 垂直居中对齐文字块",
      "countBadge.heightAnchor constraintEqualToConstant:24" in vm
      and "countBadge.layer.cornerRadius = 12" in vm
      and "countBadge.centerYAnchor constraintEqualToAnchor:self.centerYAnchor" in vm
      and "sp:12" in vm)
check("F5  计数徽章右侧 18pt 安全边距保留",
      "countBadge.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18" in vm)
check("F6  账户类型徽章：高 24 + 圆角 12 + 12pt 字",
      "badgeLabel.heightAnchor constraintEqualToConstant:24" in acct
      and "badgeLabel.layer.cornerRadius = 12" in acct
      and "badgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]" in acct)
check("F7  模组下载列表的下载按钮不在小字框改造范围（ModTableViewCell 仅样式基准更新）",
      "nm_convexRadius:50 shadowRadius:10" in read("Natives/ModTableViewCell.m"))

print()
print("=" * 72)
print("G. Item 4b：下载页模组加载器与上级菜单样式统一（样式/间距/新拟态）")
print("=" * 72)
ml = read("Natives/installer/ModLoaderInstallViewController.m")
check("G1  每个加载器独立 section（insetGrouped 独立圆角卡）",
      "return _loaders.count + ([self currentOptions].count > 0 ? 1 : 0);" in ml
      and "return 1;  // Task136：每个加载器 section 仅一行卡片" in ml)
check("G2  卡片间距 10pt（无标题 section 头高 10 + footer 0.01）",
      "if (section < (NSInteger)_loaders.count) return 10;" in ml
      and "return 0.01;" in ml)
check("G3  两类 cell 均走 applyCardEffectToCell（新拟态凸出卡片）",
      ml.count("[[BackgroundManager sharedManager] applyCardEffectToCell:cell];") == 2)
check("G4  nameBar 与上级菜单同语言（圆角 50 + applyEffectToView，系统灰底退役）",
      "_nameBar.layer.cornerRadius = 50;" in ml
      and "secondarySystemGroupedBackgroundColor" not in ml)
check("G5  didSelect 按新 section 语义取行（_loaders[indexPath.section] + 越界守卫）",
      "ModLoaderRow *row = _loaders[indexPath.section];" in ml
      and "if (indexPath.section >= (NSInteger)_loaders.count) return;" in ml)
check("G6  选中态同步改整表重载（reloadSections(0) 退役）",
      "[self.tableView reloadData];" in ml
      and "reloadSections:[NSIndexSet indexSetWithIndex:0]" not in ml)
check("G7  分隔线关闭（卡片化后无系统分隔线）",
      "_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;" in ml)
check("G8  cellForRow 按新 section 语义取行",
      "ModLoaderRow *row = _loaders[indexPath.section];" in ml
      and "NSDictionary *opt = opts[indexPath.row];" in ml)

print()
print("=" * 72)
print("H. Item 5：设置页 SF 图标改图标本体（去彩底白标）")
print("=" * 72)
pref = read("Natives/LauncherPreferencesViewController.m")
seg = pref.split("applySettingsAppStyleToCell:(UITableViewCell *)cell")[1].split("@end")[0]
check("H1  白标渲染退役（imageWithTintColor:whiteColor 清零）",
      "imageWithTintColor:[UIColor whiteColor]" not in seg
      and "iconView.tintColor = [UIColor whiteColor];" not in seg)
check("H2  彩色圆角背景退役（clearColor + cornerRadius 0 + masksToBounds NO）",
      "iconView.backgroundColor = [UIColor clearColor];" in seg
      and "iconView.layer.cornerRadius = 0;" in seg
      and "iconView.layer.masksToBounds = NO;" in seg)
check("H3  图标本体着色（tintColor = 原 section 色，红/搜索模式映射保留）",
      "iconView.tintColor = iconColor;" in seg
      and "iconBackgroundColorForItem" in pref
      and "colorForPreferenceSection" in pref)
check("H4  section header 行仍为 accentColor",
      "iconView.tintColor = accentColor();" in seg)
check("H5  图标尺寸随本体渲染放大（pointSize 20）",
      "configurationWithPointSize:20" in seg)

print()
print("=" * 72)
print("I. Item 6：全局新拟态基准样式清扫（12 处按钮/凸出 + 卡片圆角 50）")
print("=" * 72)
convex_50 = "[CONV] nm_convexRadius:50 shadowRadius:10"
targets = {
    "Natives/LauncherMenuViewController.m": 2,
    "Natives/DownloadViewController.m": 4,
    "Natives/LauncherNavigationController.m": 2,
    "Natives/AnnouncementDetailViewController.m": 1,
    "Natives/ModpackExportViewController.m": 1,
    "Natives/ServerDetailViewController.m": 2,
    "Natives/ModTableViewCell.m": 1,
}
bad = {f: read(f).count("nm_convexRadius:50 shadowRadius:10") for f in targets}
check("I1  按钮凸出调用点全部 50/10（菜单×2/下载×4/工具栏×2/公告/导出/服务器×2/Mod下载）",
      all(bad[f] == n for f, n in targets.items()), f"got={bad}")
check("I2  旧小圆角凸出调用点清零（6/8/10/12/13 组合不再出现）",
      not re.search(r"nm_convexRadius:(6|8|10|12|13)(\.0)? shadowRadius:[0-9.]+",
                    "".join(read(f) for f in targets)))
cards_50 = {
    "Natives/VersionCardCell.m": "cardContainer.layer.cornerRadius = 50",
    "Natives/ResourceCardTableViewCell.m": "contentView.layer.cornerRadius = 50.0",
    "Natives/ModVersionTableViewCell.m": "cardContainer.layer.cornerRadius = 50",
    "Natives/AccountListViewController.m": "cardView.layer.cornerRadius = 50",
    "Natives/AssetVersionViewController.m": "filterContainerView.layer.cornerRadius = 50",
    "Natives/HomeCustomizeViewController.m": "contentView.layer.cornerRadius = 50",
    "Natives/PLCrashView.m": "layer.cornerRadius = 50",
}
check("I3  卡片圆角基准 50（版本卡/资源卡/Mod版本卡/账户卡/筛选容器/自定义行/崩溃卡×3）",
      all(k in read(f) for f, k in cards_50.items()))
check("I4  主页磁贴圆角 50（contentView + shadowPath）",
      "self.contentView.layer.cornerRadius = 50;" in home
      and "cornerRadius:50].CGPath" in home)
check("I5  NMToast 弹窗 = 凸出 raised 50/10",
      "[self.cardView nm_convexRaisedRadius:50 shadowRadius:10];" in read("Natives/NeomorphKit/NMToast.m"))
check("I6  平贴面板/胶囊不在基准清扫范围（侧栏/右面板 radius 16 保留）",
      "[self.sidebarContainer nm_flatSurfaceWithRadius:16];" in read("Natives/LauncherRootViewController.m"))

print()
print("=" * 72)
print("J. Item 4a：页面底色主题化清扫（12 文件 systemBackground 退役）")
print("=" * 72)
page_files = ["AssetVersionViewController.m", "AnnouncementDetailViewController.m",
              "MinecraftNewsViewController.m", "LauncherSplitViewController.m",
              "DownloadHistoryViewController.m", "ServerDetailViewController.m",
              "ResourceListViewController.m", "ShaderVersionViewController.m",
              "DownloadTasksViewController.m", "PLTaskProgressViewController.m",
              "AnnouncementListViewController.m", "ModVersionViewController.m",
              "BackgroundSettingsViewController.m"]
sweep_ok = all("self.view.backgroundColor = [NMTheme nm_background];" in read("Natives/" + f)
               for f in page_files)
check("J1  13 个页面 view 底色 = nm_background", sweep_ok)
check("J2  上述页面 view 底色 systemBackgroundColor 残留清零",
      all("self.view.backgroundColor = [UIColor systemBackgroundColor];" not in read("Natives/" + f)
          for f in page_files))
check("J3  LauncherSplitViewController 黑色兜底分支退役（nm_background 自适应替代）",
      read("Natives/LauncherSplitViewController.m").count("[NMTheme nm_background];") == 2
      and "self.view.backgroundColor = [UIColor blackColor];" not in read("Natives/LauncherSplitViewController.m"))
check("J4  BackgroundSettings 清除背景处理器同步主题化（tableView nm_background ×4）",
      read("Natives/BackgroundSettingsViewController.m").count(
          "self.tableView.backgroundColor = [NMTheme nm_background];") == 4)

print()
print("=" * 72)
print("K. 口径护栏（Task93 检测链零变化）与语法配平")
print("=" * 72)
rp = read("Natives/LauncherRightPanelViewController.m")
check("K1  内存标识仍走 getEntitlementValue（签名口径 ×2，Task93 护栏）",
      rp.count("getEntitlementValue(") >= 2)
check("K2  JIT 检测链不受影响（isJITEnabled(NO) 仍在）",
      "isJITEnabled(NO)" in rp)
check("K3  七卡工厂零变化（makeInfoCardWithIcon 仍在）",
      "makeInfoCardWithIcon" in rp)
check("K4  侧栏图标自愈机制不受影响（refreshMenuIconImagesForced 仍在）",
      "refreshMenuIconImagesForced" in read("Natives/LauncherMenuViewController.m"))
check("K5  关键改动文件括号配平",
      all(balanced(read(f)) for f in [
          "Natives/MinecraftNewsViewController.m",
          "Natives/LauncherNewsViewController.m",
          "Natives/VersionCardCell.m",
          "Natives/VersionManagerViewController.m",
          "Natives/AccountListViewController.m",
          "Natives/installer/ModLoaderInstallViewController.m",
          "Natives/LauncherPreferencesViewController.m",
          "Natives/BackgroundManager.m",
          "Natives/SceneDelegate.m",
          "Natives/LauncherSplitViewController.m",
      ]))

print()
print(f"verify_task136: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
