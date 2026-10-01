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

# Task185 治愈：默认路径曾是并行会话的检出目录（workspace/...），跨会话必崩；
# 改为本仓库相对路径（环境变量覆盖能力保留）。
ROOT = os.environ.get('TASK163_REPO',
                      os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PASS, FAIL = 0, 0


def _strip_lc(t):
    return "\n".join(l.split("//")[0] for l in t.split("\n"))

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

check("A1  Panel 方法转 Card 平贴路由（Task210 重锚：单签名转发回归；NeumorphSurface 零残留）",
      "[self ame_applyCardSurfaceWithRadius:cornerRadius];" in nsm
      and "opacity:(CGFloat)opacity;" not in open('Natives/UIKit+NativeSurface.h').read()
      and "ame_applyNeumorphSurface" not in nsm,
      "Panel 实现必须单签名转发 Card 平贴；NeumorphSurface 随 Task210 零残留")
check("A2  Panel 注释留档（Task210 重锚：平贴语义延续——全屏大容器不挂阴影承载层）",
      "大面板平贴" in nsm
      and "ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {" in nsm)
check("A3  调用点保持 Panel 语义（Task184 重锚：LauncherRoot 无壁纸分支回归单签名恒定底）",
      "[self.sidebarContainer ame_applyPanelSurfaceWithRadius:16];" in root
      and "[self.rightPanelContainer ame_applyPanelSurfaceWithRadius:16];" in root
      and "bgOpacity" not in root)
check("A4  maskedCorners/创建态裁剪不被触碰（侧栏外侧两角圆角保留）",
      "kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner" in root
      and "kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner" in root
      and "self.sidebarContainer.layer.masksToBounds = YES;" in root)
check("A5  头文件 Panel 契约在位（Task163 语义修订 + Task210 平贴注释）",
      "ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius;" in nsh
      and "平贴面板表面" in nsh)

print()
print("=" * 72)
print("B. 主页磁贴/下载版本卡新拟态凸起（该改的改）")
print("=" * 72)
bm = read('Natives/BackgroundManager.m')
bh = read('Natives/BackgroundManager.h')
vcc = read('Natives/VersionCardCell.m')

check("B1  Task210：ame_removeNeumorphShadow 随引擎退役（h/m 零残留）",
      "ame_removeNeumorphShadow" not in _strip_lc(nsh)
      and "ame_removeNeumorphShadow" not in _strip_lc(nsm))
check("B2  Task210：CollectionViewCell 无壁纸分支走平贴灰面（applyEffectToView 尾部 AmeCardSurfaceColor）",
      "view.backgroundColor = AmeCardSurfaceColor();" in bm
      and "ame_applyNeumorphSurface" not in _strip_lc(bm))
check("B3  Task210：阴影放行裁剪语义随双阴影退役（ON 分支整链删除，无 clips=NO 残留）",
      "contentView.clipsToBounds = NO;" not in bm
      and "contentView.layer.masksToBounds = NO;" not in bm)
check("B3b Task210：表格卡片行走单路径管线（applyEffectToCell 直转，Flat 特调退役）",
      "cell.clipsToBounds = YES;" not in bm.split("- (void)applyCardEffectToCell")[1].split("@end")[0] if "- (void)applyCardEffectToCell" in bm else False)
check("B4  Task210：残留阴影清理原语随引擎退役（零调用点）",
      "ame_removeNeumorphShadow" not in _strip_lc(bm))
check("B5  Task210：管线改名 applyCardEffectToView（h 声明 + m 实现）",
      "- (void)applyCardEffectToView:(UIView *)view;" in bh
      and "- (void)applyCardEffectToView:(UIView *)view {" in bm)
check("B6  Task210：管线单路径语义（恒转调 applyEffectToView，无开关无凸起）",
      bm.count("- (void)applyCardEffectToView:(UIView *)view {") == 1
      and "[self applyEffectToView:view];" in bm[bm.index("- (void)applyCardEffectToView"):bm.index("- (void)applyEffectToSearchBar")])
check("B7  VersionCardCell 换调改名后管线（Task210）",
      "applyCardEffectToView:self.cardContainer];" in vcc
      and "applyNeumorphCardEffectToView" not in vcc)
check("B8  HomeTileBaseCell 基类结构未动（磁贴圆角/容器创建保持）",
      "self.contentView.layer.cornerRadius = 16;" in read('Natives/LauncherNewsViewController.m')
      and "applyEffectToCollectionViewCell:self];" in read('Natives/LauncherNewsViewController.m'))
check("B9  Task210：表格卡片行恒走 applyEffectToCell（Flat 特调行退役）",
      "ame_applyNeumorphSurfaceFlatWithRadius" not in bm
      and "[self applyEffectToCell:cell];" in bm[bm.index("- (void)applyCardEffectToCell"):bm.index("- (void)applyCardEffectToView")])
check("B10 Task210：凸起契约退役（引擎/双阴影/三层结构零残留，平贴灰面接棒）",
      "ame177_darkLayer" not in nsm and "ame177_surfaceLayer" not in nsm
      and "AmeCardSurfaceColor" in nsm)

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

check("D1  Task210：三色动态函数幸存（Surface/PrimaryText/SecondaryText 改名保留）",
      all(f"AmeCard{x}Color" in nsm for x in ["Surface", "PrimaryText", "SecondaryText"]))
check("D2  Task210：等比度量退役，平贴 clamp[8,50] 幸存",
      "AmeNeumorphBaseDimension" not in nsm
      and "MAX(8.0, MIN(cornerRadius, 50.0))" in nsm)
check("D3  Task210：深浅自适应幸存（动态 provider，无需手动重刷）",
      "colorWithDynamicProvider" in nsm)
check("D4  NMToast/DownloadVC 的 Card 表面不受影响（仍凸起）",
      "[self.cardView ame_applyCardSurfaceWithRadius:kNMToastCornerRadius];"
      in read('Natives/NMToast.m')
      and "[self.contentContainer ame_applyCardSurfaceWithRadius:8];"
      in read('Natives/DownloadViewController.m'))
check("D5  Task210：版本卡（VMVersionCardCell）文字色深浅自适应（AmeCard 双色）",
      "AmeCardPrimaryTextColor();" in read('Natives/VersionManagerViewController.m')
      and "AmeCardSecondaryTextColor();" in read('Natives/VersionManagerViewController.m')
      and "[UIColor whiteColor]" not in read('Natives/VersionManagerViewController.m').split("@implementation VMVersionCardCell")[1].split("@end")[0])
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
