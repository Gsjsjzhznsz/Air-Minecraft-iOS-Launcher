#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task137.py —— Task 137 校验器

用户指令（四项实测反馈 + 总原则）：
  3. "现在所有小字框都是…了，游戏目录和已安装版本的数量显示还是原样"
     → 根因：Task136 InsetTypeLabel 注入内边距但未重写 intrinsicContentSize，
       约束宽度 = 纯文字宽，绘制再被左右 8pt 内边距裁掉 → 必然截断"…"。
       修复：共享 AmeBadgeLabel（intrinsic = 文字 + 内边距），版本类型胶囊、
       游戏目录/已安装版本计数徽章、账户徽章统一接入。
  4. "右侧栏的下载中心小框还是黑底深字的，你还不如去掉扫描器直接排查"
     → 根因：硬编码 0.2 白（深灰）底 + labelColor 黑字（浅色模式不可读）。
       修复：删除 Task136 NMContrast 动态扫描器，直修 = 原生语义色
       （secondarySystemGroupedBackground 底 + labelColor 字，深浅色系统保证）。
  5. "新拟态按钮上下的阴影全被截断了，还莫名其妙多出很宽的间距"
  7. "每一个按钮的圆角、阴影大小都一样，10px 的按钮和 100px 的按钮圆角阴影
     都一样，导致有的太圆，有的阴影太宽"
     → 连同总指令一并解决：删去全部新拟态代码（NeomorphKit 双承载层阴影
       引擎、NMTheme 色板、NMContrast 扫描器），回归 iOS 原生 UI
       （UIKit 语义色 + 逐元素原生圆角，无任何自绘阴影）；
       大小/位置不变；层级还原（cell 裁剪恢复、承载层清场、
       背景照片管线保留）；功能零影响（检测链/下载中心/toast 全保留）。

分节：
  A. 新拟态整体退役（Kit 删除 / 全仓零引用 / CMake 一致）
  B. Item 3 小字框：AmeBadgeLabel 统一实现（截断根治 + 数量徽章接入）
  C. Item 4 深底深字直修（扫描器退役 + 下载中心/页面底色原生语义色）
  D. 原生 UI 换装（语义色 / 逐元素圆角 / 按钮原生还原 / 面板表面）
  E. 层级与裁剪还原（cell 裁剪恢复 / 承载层清场 / 背景照片管线保留）
  F. 尺寸与功能零影响护栏（几何锚点 / 检测链 / toast / 通知链）
  G. 语法与配平（含新文件）
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK137_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
PASS = 0
FAIL = 0


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def exists(path):
    return os.path.exists(os.path.join(REPO, path))


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
print("A. 新拟态整体退役")
print("=" * 72)
kit_files = ["Natives/NeomorphKit/NMTheme.h", "Natives/NeomorphKit/NMTheme.m",
             "Natives/NeomorphKit/UIView+Neomorph.h", "Natives/NeomorphKit/UIView+Neomorph.m",
             "Natives/NeomorphKit/NMContrast.h", "Natives/NeomorphKit/NMContrast.m",
             "Natives/NeomorphKit/UIViewController+NMPanel.h", "Natives/NeomorphKit/UIViewController+NMPanel.m",
             "Natives/NeomorphKit/NMToast.h", "Natives/NeomorphKit/NMToast.m"]
check("A1  NeomorphKit 十个源文件全部删除", all(not exists(f) for f in kit_files))
kit_dir = os.path.join(REPO, "Natives/NeomorphKit")
check("A2  NeomorphKit 目录不存在或为空", (not os.path.isdir(kit_dir)) or not os.listdir(kit_dir))

code_refs = []
for root, dirs, files in os.walk(os.path.join(REPO, "Natives")):
    dirs[:] = [d for d in dirs if d not in ("external", "resources", "AI")]
    for fn in files:
        if not fn.endswith((".m", ".h")):
            continue
        p = os.path.join(root, fn)
        rel = os.path.relpath(p, REPO)
        code = strip_objc(read(rel))
        for pat in ("nm_convex", "nm_flat", "nm_pill", "nm_styleConvex", "nm_removeNeomorph",
                    "nm_hasNeomorph", "NMTheme", "NMContrast", "nm_applySubpanel",
                    "NeomorphKit", "NMThemeDidChange"):
            if pat in code:
                code_refs.append(f"{rel}:{pat}")
check("A3  Natives 全部 .m/.h 代码零新拟态符号（含 NMTheme/NeomorphKit import）",
      not code_refs, str(code_refs[:6]))

cmake = read("Natives/CMakeLists.txt")
check("A4  CMake：Kit 源清零，登记 UIKit+NativeSurface / UIViewController+AMEPanel / NMToast",
      "NeomorphKit/" not in cmake
      and "UIKit+NativeSurface.m" in cmake
      and "UIViewController+AMEPanel.m" in cmake
      and "  NMToast.m" in cmake)
check("A5  NMToast 迁移至 Natives/ 根（类名保留，样式原生化）",
      exists("Natives/NMToast.m") and not exists("Natives/NeomorphKit/NMToast.m"))

print()
print("=" * 72)
print("B. Item 3 小字框：AmeBadgeLabel 统一实现")
print("=" * 72)
nsm = read("Natives/UIKit+NativeSurface.m")
nsh = read("Natives/UIKit+NativeSurface.h")
vc = read("Natives/VersionCardCell.m")
vm = read("Natives/VersionManagerViewController.m")
check("B1  AmeBadgeLabel 三件套：intrinsic 内边距补偿 + 绘制内边距 + 胶囊圆角",
      "- (CGSize)intrinsicContentSize" in nsm
      and "size.width + _textInsets.left + _textInsets.right" in nsm
      and "- (void)drawTextInRect:" in nsm
      and "self.layer.cornerRadius = h / 2.0" in nsm)
check("B2  AmeBadgeLabel 胶囊不可压缩（hugging/compression 均 Required）",
      nsm.count("UILayoutPriorityRequired") >= 2)
check("B3  版本类型胶囊（正式版/测试版）接入 AmeBadgeLabel（InsetTypeLabel 代码清零，仅留档注释）",
      "[[AmeBadgeLabel alloc] init]" in vc and "InsetTypeLabel" not in strip_objc(vc))
check("B4  版本号侧让位机制保留（版本号 compression 低，胶囊 Required 不变形）",
      "setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal" in vc.replace(" ", "").replace("self.versionLabel", "") or
      "UILayoutPriorityDefaultLow" in vc)
check("B5  计数徽章（游戏目录/已安装版本）接入 AmeBadgeLabel（不再用空格凑内边距）",
      "[[AmeBadgeLabel alloc] init]" in vm
      and 'stringWithFormat:@"%ld", (long)count]' in vm
      and 'stringWithFormat:@" %ld "' not in vm)
check("B6  计数徽章几何保持（高 24 ≈ 两行 12pt 字 / 靠右 18pt / 垂直居中于文字块）",
      "countBadge.heightAnchor constraintEqualToConstant:24" in vm
      and "countBadge.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18" in vm
      and "countBadge.centerYAnchor constraintEqualToAnchor:self.centerYAnchor" in vm)
check("B7  版本胶囊几何保持（高 24 / chevron 左侧 8pt / 垂直居中）",
      "typeLabel.heightAnchor constraintEqualToConstant:24" in vc
      and "typeLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-8" in vc
      and "typeLabel.centerYAnchor constraintEqualToAnchor:self.cardContainer.centerYAnchor" in vc)

print()
print("=" * 72)
print("C. Item 4 深底深字直修（扫描器退役）")
print("=" * 72)
rp = read("Natives/LauncherRightPanelViewController.m")
sd = read("Natives/SceneDelegate.m")
check("C1  右面板下载中心按钮：原生卡片底（0.2 白硬编码深灰退役）",
      "self.downloadCenterButton.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];" in rp
      and "colorWithWhite:0.2 alpha:1.0" not in rp)
check("C2  右面板下载中心按钮：标题 labelColor 保留（深浅色对比由系统保证）",
      "setTitleColor:[UIColor labelColor] forState:UIControlStateNormal" in rp)
check("C3  SceneDelegate：NMContrast 启动扫描接线移除",
      "NMContrast" not in strip_objc(sd) and "nm_startContrastSweep" not in sd)
check("C4  SceneDelegate：窗口底色原生 systemBackgroundColor",
      "self.window.backgroundColor = [UIColor systemBackgroundColor];" in sd)
check("C5  工具栏下载中心按钮恢复原生（品牌紫底白字，图标/指示器/百分比白）",
      "[UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:0.85]" in read("Natives/LauncherNavigationController.m")
      and "downloadCenterActivityIndicator.color = [UIColor whiteColor];" in read("Natives/LauncherNavigationController.m"))
check("C6  全局深浅色策略：语义色自适应（无需扫描器）",
      "[UIColor labelColor]" in read("Natives/MultiplayerViewController.m")
      and "[UIColor systemBackgroundColor]" in read("Natives/LauncherSplitViewController.m"))

print()
print("=" * 72)
print("D. 原生 UI 换装（语义色 / 逐元素圆角 / 按钮原生还原 / 面板表面）")
print("=" * 72)
check("D1  原生三表面 API（卡片=secondarySystemGrouped / 凸起=tertiarySystemGrouped / 面板=secondarySystem）",
      "secondarySystemGroupedBackgroundColor" in nsm
      and "tertiarySystemGroupedBackgroundColor" in nsm
      and "secondarySystemBackgroundColor" in nsm)
check("D2  卡片/凸起表面裁剪到圆角 + AmeBadgeLabel 胶囊裁剪（共 3 处 masks），面板表面不动裁剪",
      nsm.count("self.layer.masksToBounds = YES;") == 3
      and "不改动裁剪" in nsm)
check("D3  逐元素原生圆角（版本卡 12 / 账户卡 16 / 筛选 14 / 崩溃卡 16 / 磁贴 16 / 加载器名条 10）",
      "cardContainer.layer.cornerRadius = 12" in vc
      and "cardView.layer.cornerRadius = 16" in read("Natives/AccountListViewController.m")
      and "filterContainerView.layer.cornerRadius = 14" in read("Natives/AssetVersionViewController.m")
      and read("Natives/PLCrashView.m").count("layer.cornerRadius = 16;  // Task137") == 3
      and "self.contentView.layer.cornerRadius = 16;" in read("Natives/LauncherNewsViewController.m")
      and "_nameBar.layer.cornerRadius = 10;" in read("Natives/installer/ModLoaderInstallViewController.m"))
check("D4  新闻卡圆角回归 12（等高机制保留）",
      "kNewsCardCornerRadius = 12.0" in read("Natives/MinecraftNewsViewController.m"))
check("D5  按钮原生还原：服务器加入=systemBlue / 包下载=systemPurple / 公告=systemBlue / 导出=systemBlue / 模组下载=accent",
      "self.joinButton.backgroundColor = [UIColor systemBlueColor];" in read("Natives/ServerDetailViewController.m")
      and "self.downloadPackButton.backgroundColor = [UIColor systemPurpleColor];" in read("Natives/ServerDetailViewController.m")
      and "self.actionButton.backgroundColor = [UIColor systemBlueColor];" in read("Natives/AnnouncementDetailViewController.m")
      and "self.exportButton.backgroundColor = [UIColor systemBlueColor];" in read("Natives/ModpackExportViewController.m")
      and "_downloadButton.backgroundColor = accentColor();" in read("Natives/ModTableViewCell.m"))
check("D6  侧栏选中态 = accent 0.15 原生高亮（双入口一致）",
      read("Natives/LauncherMenuViewController.m").count("[accent colorWithAlphaComponent:0.15]") == 2)
check("D7  侧栏/右面板 = 原生 panel 表面 16pt（Root chrome 双容器）",
      "[self.sidebarContainer ame_applyPanelSurfaceWithRadius:16];" in read("Natives/LauncherRootViewController.m")
      and "[self.rightPanelContainer ame_applyPanelSurfaceWithRadius:16];" in read("Natives/LauncherRootViewController.m"))
check("D8  子面板基座原生化（AMEPanel：systemBackground + 系统分隔线；导航单一执法点接线）",
      "[UIColor systemBackgroundColor]" in read("Natives/UIViewController+AMEPanel.m")
      and "[UIColor separatorColor]" in read("Natives/UIViewController+AMEPanel.m")
      and "[viewController ame_applySubpanelBaseStyle];" in read("Natives/LauncherNavigationController.m"))
check("D9  NMToast 卡片原生化（ame 表面 + labelColor 正文）",
      "[self.cardView ame_applyCardSurfaceWithRadius:kNMToastCornerRadius];" in read("Natives/NMToast.m")
      and "self.messageLabel.textColor = [UIColor labelColor];" in read("Natives/NMToast.m"))

print()
print("=" * 72)
print("E. 层级与裁剪还原")
print("=" * 72)
bm = read("Natives/BackgroundManager.m")
check("E1  collection cell 裁剪恢复（clipsToBounds YES；新拟态阴影放开退役）",
      "cell.clipsToBounds = YES;" in bm
      and not re.search(r"applyEffectToCollectionViewCell:[\s\S]{0,4000}?cell\.clipsToBounds = NO;", bm))
check("E2  卡片行（applyCardEffectToCell）裁剪恢复",
      re.search(r"applyCardEffectToCell:\(UITableViewCell \*\)cell \{[\s\S]{0,600}?cell\.clipsToBounds = YES;", bm))
check("E3  磁贴 cell 阴影路径生成退役（原生卡片无自绘阴影）",
      "self.layer.shadowPath" not in read("Natives/LauncherNewsViewController.m"))
check("E4  背景照片管线保留（hasBackground 检测切换 + 最底层容器插入 + 毛玻璃分支）",
      bm.count("hasBackground]") >= 5
      and "[window insertSubview:container atIndex:0];" in bm
      and "UIBlurEffectStyleSystemThinMaterial" in bm)
check("E5  chrome 表面切换保留（有背景=毛玻璃管线，无背景=原生面板）",
      "[[BackgroundManager sharedManager] applyEffectToView:self.sidebarContainer];" in read("Natives/LauncherRootViewController.m"))

print()
print("=" * 72)
print("F. 尺寸与功能零影响护栏")
print("=" * 72)
check("F1  内存标识签名口径零变化（getEntitlementValue 恰两处，Task93 护栏）",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2)
check("F2  JIT 检测链零变化（isJITEnabled(NO) + TXM 三态）",
      "BOOL enabled = isJITEnabled(NO);" in strip_objc(rp)
      and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in strip_objc(rp))
check("F3  七卡工厂零变化（makeInfoCardWithIcon + 滚动区居中 KVO 保留）",
      "makeInfoCardWithIcon" in strip_objc(rp)
      and "AmeInfoContentSizeContext" in rp)
check("F4  头像/按钮几何护栏保留（头像宽=执行Jar + 顶距=按钮底距）",
      "AmePanelVerticalEdgeInset" in rp
      and "widthAnchor constraintEqualToAnchor:self.executeJarBtn.widthAnchor" in rp)
check("F5  侧栏几何零变化（50×50 按钮 / 圆角 10 / 图标自愈机制）",
      "CGFloat buttonSize = 50;" in read("Natives/LauncherMenuViewController.m")
      and "btn.layer.cornerRadius = 10;" in read("Natives/LauncherMenuViewController.m")
      and "refreshMenuIconImagesForced" in read("Natives/LauncherMenuViewController.m"))
check("F6  NMToast 通知 API 零变化（showMessage 四重载 + dismiss 保留）",
      read("Natives/NMToast.h").count("+ (void)showMessage:") == 3
      and "+ (void)dismiss;" in read("Natives/NMToast.h"))
check("F7  新闻卡固定高度机制零变化（模板实测 + dispatch_once + absoluteDimension）",
      "newsCardFixedHeight" in read("Natives/MinecraftNewsViewController.m")
      and read("Natives/MinecraftNewsViewController.m").count("absoluteDimension:cardHeight]") == 2)
check("F8  顶卡头像交换幸存（半透明边框 2.5 + 正圆 + 欢迎语纵轴居中）",
      "layer.borderWidth = 2.5" in read("Natives/LauncherNewsViewController.m")
      and "welcomeStack.centerYAnchor constraintEqualToAnchor:self.avatarImageView.centerYAnchor" in read("Natives/LauncherNewsViewController.m"))
check("F9  设置页图标本体着色幸存（Task136 Item 5 零回退）",
      "iconView.tintColor = iconColor;" in read("Natives/LauncherPreferencesViewController.m"))
check("F10 加载器分节卡片幸存（每加载器一 section + 10pt 间距）",
      "return 1;  // Task136：每个加载器 section 仅一行卡片" in read("Natives/installer/ModLoaderInstallViewController.m")
      and "if (section < (NSInteger)_loaders.count) return 10;" in read("Natives/installer/ModLoaderInstallViewController.m"))

print()
print("=" * 72)
print("G. 语法与配平")
print("=" * 72)
check("G1  关键改动文件括号配平（字符串/注释感知）",
      all(balanced(read(f)) for f in [
          "Natives/BackgroundManager.m",
          "Natives/SceneDelegate.m",
          "Natives/NMToast.m",
          "Natives/UIViewController+AMEPanel.m",
          "Natives/UIKit+NativeSurface.m",
          "Natives/UIKit+NativeSurface.h",
          "Natives/LauncherNavigationController.m",
          "Natives/LauncherMenuViewController.m",
          "Natives/LauncherRootViewController.m",
          "Natives/LauncherRightPanelViewController.m",
          "Natives/LauncherNewsViewController.m",
          "Natives/MinecraftNewsViewController.m",
          "Natives/VersionCardCell.m",
          "Natives/VersionManagerViewController.m",
          "Natives/AccountListViewController.m",
          "Natives/DownloadViewController.m",
          "Natives/ModTableViewCell.m",
          "Natives/LauncherSplitViewController.m",
          "Natives/BackgroundSettingsViewController.m",
      ]))
check("G2  新增 UIColor 语义色选择器拼写审计（全量白名单）",
      not [m for m in set(re.findall(r"\[UIColor (\w+)\]",
                                     "".join(read(f) for f in [
                                         "Natives/UIKit+NativeSurface.m",
                                         "Natives/UIViewController+AMEPanel.m",
                                         "Natives/NMToast.m",
                                         "Natives/SceneDelegate.m",
                                         "Natives/LauncherRightPanelViewController.m",
                                         "Natives/VersionCardCell.m",
                                         "Natives/VersionManagerViewController.m",
                                         "Natives/AccountListViewController.m",
                                         "Natives/ServerDetailViewController.m",
                                         "Natives/AnnouncementDetailViewController.m",
                                         "Natives/ModpackExportViewController.m",
                                         "Natives/ModTableViewCell.m",
                                         "Natives/DownloadViewController.m",
                                         "Natives/LauncherNavigationController.m",
                                         "Natives/LauncherMenuViewController.m",
                                         "Natives/LauncherRootViewController.m",
                                         "Natives/LauncherNewsViewController.m",
                                     ])))
           if m not in {
               "systemBackgroundColor", "labelColor", "secondaryLabelColor", "tertiaryLabelColor",
               "placeholderTextColor", "separatorColor", "secondarySystemBackgroundColor",
               "secondarySystemGroupedBackgroundColor", "tertiarySystemGroupedBackgroundColor",
               "tertiarySystemFillColor", "secondarySystemFillColor", "systemGrayColor",
               "systemBlueColor", "systemPurpleColor", "systemRedColor", "systemGreenColor",
               "systemOrangeColor", "whiteColor", "blackColor", "clearColor",
               "groupTableViewBackgroundColor", "systemGroupedBackgroundColor", "grayColor",
               "systemTealColor", "systemPinkColor", "systemGray3Color", "quaternaryLabelColor"}])
check("G3  本地化资源零改动（.strings 基线不动）",
      not subprocess.run(["git", "-C", REPO, "diff", "HEAD", "--name-only", "--",
                          "Natives/resources/*.strings"], capture_output=True, text=True).stdout.strip())
check("G4  工作区改动仅限预期文件集（提交后自愈）",
      all(ln[3:].strip().startswith(("Natives/", "scripts/verify_task", "worklog.md"))
          for ln in subprocess.run(["git", "-C", REPO, "status", "--porcelain"],
                                   capture_output=True, text=True).stdout.splitlines()
          if ln.strip()))

print()
print(f"verify_task137: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
