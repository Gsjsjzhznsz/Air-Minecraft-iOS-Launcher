#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task163 -- 新拟态范围修正（用户装机实测反馈）：

  1. "我根本就没看到你改了UI，主页的卡片一点没改，下载页面版本选项一点没改，
     倒是把左侧栏和右侧栏改了，这两个栏的阴影直接影响了旁边的卡片，不该改的
     你改了，该改的你就是不改。"
  2. "实例设置页面的渲染器右侧的灰色箭头与其他选项样式不匹配，十分突兀"

根因与修复：
  A 侧栏/右面板退役阴影（ame_applyPanelSurfaceWithRadius -> Flat 路由）
  B 主页磁贴/下载版本卡挂新拟态双阴影（CollectionViewCell 无壁纸分支 +
    applyNeumorphCardEffectToView 新管线 + ame_removeNeumorphShadow 清理）
  C 实例设置页箭头统一（13 处系统 DisclosureIndicator -> 自绘 chevron）
  D 回归锚点（applyCardEffectToCell/Card/Raised 幸存、引擎契约幸存）
  E 语法配平
"""
import os
import sys

ROOT = os.environ.get('TASK163_REPO',
                      '/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher')
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
    """字符状态机版配平检查（与 task160 口径一致：单遍扫描，注释/字符串/
    字符字面量按出现顺序判定，避免字符串内 // 被误当注释）"""
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
            out.append('"')
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
            out.append("'")
            i = j + 1
        else:
            i += 1
    s = ''.join(out)
    # 与 task160 配平口径一致：只查大括号/圆括号平衡（引号奇偶在含转义
    # 字面量的 ObjC 源码上属基线噪声，不做判定）
    return s.count('{') == s.count('}') and s.count('(') == s.count(')')


print("=" * 72)
print("A. 侧栏/右面板阴影退役（不该改的改回去）")
print("=" * 72)
nsm = read('Natives/UIKit+NativeSurface.m')
nsh = read('Natives/UIKit+NativeSurface.h')
root = read('Natives/LauncherRootViewController.m')

check("A1  Panel 方法转 Flat 路由（表面+圆角，不挂阴影承载层）",
      "[self ame_applyNeumorphSurfaceFlatWithRadius:cornerRadius];" in nsm
      and nsm.count("[self ame_applyNeumorphSurface];") == 2,
      "Panel 实现必须走 Flat；NeumorphSurface 直调仅剩 Card/Raised 两处")
check("A2  Panel 注释留档（Task177 重锚：退役阴影语义延续到新注释——全屏大容器不挂阴影承载层）",
      "平贴面板退役阴影" in nsm
      and "ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {" in nsm)
check("A3  调用点保持 Panel 语义（LauncherRoot 无壁纸分支两行不变）",
      "[self.sidebarContainer ame_applyPanelSurfaceWithRadius:16];" in root
      and "[self.rightPanelContainer ame_applyPanelSurfaceWithRadius:16];" in root)
check("A4  maskedCorners/创建态裁剪不被触碰（侧栏外侧两角圆角保留）",
      "kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner" in root
      and "kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner" in root
      and "self.sidebarContainer.layer.masksToBounds = YES;" in root)
check("A5  头文件 Panel 契约注释更新（Task163 语义修订）",
      "ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius;" in nsh
      and "Task163 语义修订" in nsh)

print()
print("=" * 72)
print("B. 主页磁贴/下载版本卡新拟态凸起（该改的改）")
print("=" * 72)
bm = read('Natives/BackgroundManager.m')
bh = read('Natives/BackgroundManager.h')
vcc = read('Natives/VersionCardCell.m')

check("B1  引擎新增 ame_removeNeumorphShadow（h 声明 + m 实现）",
      "- (void)ame_removeNeumorphShadow;" in nsh
      and "- (void)ame_removeNeumorphShadow {" in nsm
      and "objc_setAssociatedObject(self, kAmeNeumorphShadowViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);" in nsm)
check("B2  CollectionViewCell 无壁纸分支挂双阴影（Flat -> NeumorphSurface）",
      "[target ame_applyNeumorphSurface];" in bm
      and "[target ame_applyNeumorphSurfaceFlatWithRadius:radius];" not in bm)
check("B3  宿主链放行裁剪（无壁纸分支 cell.clipsToBounds=NO + contentView masks=NO）",
      "cell.clipsToBounds = NO;" in bm
      and "cell.contentView.layer.masksToBounds = NO;" in bm)
check("B3b 表格卡片行的 Flat 形态裁剪不受影响（applyCardEffectToCell 保留自身 clips=YES）",
      "cell.clipsToBounds = YES;" in bm
      and "[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];" in bm)
check("B4  壁纸分支清残留阴影（applyEffectToView + CollectionViewCell 双入口）",
      bm.count("[view ame_removeNeumorphShadow];") >= 1
      and "[cell.contentView ame_removeNeumorphShadow];" in bm
      and "[cardTarget ame_removeNeumorphShadow];" in bm)
check("B5  新管线 applyNeumorphCardEffectToView（h 声明 + m 实现）",
      "- (void)applyNeumorphCardEffectToView:(UIView *)view;" in bh
      and "- (void)applyNeumorphCardEffectToView:(UIView *)view {" in bm)
check("B6  新管线分支语义（有壁纸转调旧管线，无壁纸挂凸起表面）",
      "if (view.layer.cornerRadius <= 0) view.layer.cornerRadius = 12;" in bm
      and bm.count("ame_applyNeumorphSurface];") >= 1)
check("B7  VersionCardCell 换调新管线",
      "applyNeumorphCardEffectToView:self.cardContainer];" in vcc
      and "applyEffectToView:self.cardContainer];" not in vcc)
check("B8  HomeTileBaseCell 基类结构未动（磁贴圆角/容器创建保持）",
      "self.contentView.layer.cornerRadius = 16;" in read('Natives/LauncherNewsViewController.m')
      and "applyEffectToCollectionViewCell:self];" in read('Natives/LauncherNewsViewController.m'))
check("B9  表格卡片行 applyCardEffectToCell 保持 Flat（用户未点名，不扩散）",
      "[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];" in bm)
check("B10 引擎凸起契约幸存（Task177 重锚：双阴影方向维持；透明承载层改投影对+不透明渐变表面三层结构）",
      "CGSizeMake(offset, offset)" in nsm
      and "CGSizeMake(-offset, -offset)" in nsm
      and "ame177_darkLayer" in nsm and "ame177_surfaceLayer" in nsm)

print()
print("=" * 72)
print("C. 实例设置页箭头统一（渲染器行突兀修复）")
print("=" * 72)
ps = read('Natives/ProfileSettingsViewController.m')

check("C1  系统 DisclosureIndicator 代码清零（注释除外）",
      "cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;" not in ps)
# Task173 重锚：并行 Task172（six-fix）新增 TouchController 行后，自绘箭头
# 行数 13 -> 14（新增行复用同款 chevron helper，视觉语义不变）。
check("C2  helper ame163_disclosureChevron 存在（同款 chevron.right；Task172 触控行并入后 14）",
      "- (UIView *)ame163_disclosureChevron {" in ps
      and ps.count("[self ame163_disclosureChevron];") == 14)
check("C3  helper 视觉规格（tertiaryLabel 灰 + 8x13 + 容器 14x30）",
      "chevron.tintColor = [UIColor tertiaryLabelColor];" in ps
      and "chevron.frame = CGRectMake(0, 8.5, 8, 13);" in ps
      and "initWithFrame:CGRectMake(0, 0, 14, 30)]" in ps)
check("C4  分辨率行容器尾端 chevron 保持（整页统一基准）",
      "UIImage *chevronImage = [UIImage systemImageNamed:@\"chevron.right\"];" in ps
      and "chevronView.frame = CGRectMake(82, 9, 8, 13);" in ps)
check("C5  渲染器行换用自绘箭头（用户点名行；Task172 触控行并入后 14）",
      ps.count("cell.accessoryView = [self ame163_disclosureChevron];") == 14
      and "[self rendererDisplayName:self.selectedRenderer];" in ps)
check("C6  复用重置逻辑幸存（accessoryView/accessoryType 复位不动）",
      "cell.accessoryView = nil;" in ps
      and "cell.accessoryType = UITableViewCellAccessoryNone;" in ps)

print()
print("=" * 72)
print("D. 回归锚点")
print("=" * 72)

check("D1  引擎五色动态函数幸存（Task160 规格）",
      all(f"AmeNeumorph{x}Color" in nsm for x in
          ["Surface", "Shadow", "Highlight", "PrimaryText", "SecondaryText"]))
check("D2  度量幸存（Task177 重锚：340 基准圆角等比保留；偏移/模糊改固定档 4/8（小件 2/4））",
      "AmeNeumorphBaseDimension = 340.0" in nsm
      and "MAX(8.0, 50.0 * scale)" in nsm
      and "? 2.0 : 4.0" in nsm
      and "? 4.0 : 8.0" in nsm)
check("D3  traitCollectionDidChange 深浅色重刷幸存",
      "traitCollectionDidChange:" in nsm)
check("D4  NMToast/DownloadVC 的 Card 表面不受影响（仍凸起）",
      "[self.cardView ame_applyCardSurfaceWithRadius:kNMToastCornerRadius];"
      in read('Natives/NMToast.m')
      and "[self.contentContainer ame_applyCardSurfaceWithRadius:8];"
      in read('Natives/DownloadViewController.m'))
check("D5  版本卡文字色规格化幸存（Task160 D9 口径）",
      "AmeNeumorphPrimaryTextColor(); // Task160 规格主文字" in vcc)
check("D6  分辨率行 clamp 25~150 幸存（Task160/159 口径）",
      "if (ame159_value > 150) ame159_value = 150;" in ps
      and "if (ame159_value < 25) ame159_value = 25;" in ps)
check("D7  版本 addendum 落档（REVISION 17 addendum Task 163）",
      "REVISION 17 addendum (Task 163, no bump)" in read(
          'Natives/external/MobileGlues/MobileGlues-cpp/version.h'))

print()
print("=" * 72)
print("E. 语法配平（本批触碰文件）")
print("=" * 72)
for rel in ['Natives/UIKit+NativeSurface.m', 'Natives/UIKit+NativeSurface.h',
            'Natives/BackgroundManager.m', 'Natives/BackgroundManager.h',
            'Natives/VersionCardCell.m', 'Natives/LauncherRootViewController.m',
            'Natives/ProfileSettingsViewController.m']:
    check(f"E   {rel}", balanced(rel))

print()
print("=" * 72)
print(f"{PASS} passed, {FAIL} failed")
print("=" * 72)
print(f"==== RESULT: {'PASSED' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}) ====")
sys.exit(0 if FAIL == 0 else 1)
