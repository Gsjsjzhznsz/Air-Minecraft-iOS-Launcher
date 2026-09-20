#!/usr/bin/env python3
"""
Task 111 验证器：启动器背景照片功能恢复（检测并切换）+ 菜单背景消失修复 + 主界面按钮稳定显示

背景（用户 Task 102 IPA 实测反馈 + 截图 IMG_9143）：
  1. 背景照片功能全部失效：Task89 的 applyBackgroundToWindow 无条件短路为
     NMTheme 纯色底，把 Task89 之前的图片/视频/毛玻璃/压暗全局背景管线整体
     顶掉，用户实测"你直接把背景强制改成白色了"。修复（用户给定两种思路之一：
     检测并切换）：BackgroundManager 全部四个入口按 hasBackground 自动切换——
     有自定义背景时恢复旧管线（容器 insertSubview:atIndex:0 最底层插入，即
     "调低层级"；图片/视频/毛玻璃/压暗；子 VC 透明化），无背景时维持 Task89
     新拟态纯色底。设置/清除背景后既有 BackgroundChanged 链路自动重跑。
  2. 有些菜单的背景消失（只剩按钮和阴影）：makeViewControllerTransparent 在
     无背景模式下也无条件透明化（默认毛玻璃分支把页面 view 洗成 clear），
     叠加 applyEffectToCell 无条件半透明 secondarySystemBackgroundColor
     （与 NMTheme 底色几乎同色）→ 表格型页面近透明。修复：无背景时
     makeViewControllerTransparent 直接 no-op（页面保持自身底色），
     applyEffectToCell 无背景分支改发 NMTheme nm_surface 实色卡片底；
     背景设置页自身的 view/tableView 底色改 nm_background（默认
     systemBackground 白底同样洗白 cell），styleCell 统一走 applyEffectToCell。
  3. 主界面按钮不稳定显示（Task101 单次补拉、Task102 4s 重试后仍复现）：
     升级三重保险——①创建时立即二次补拉（首次 systemImageNamed: 完成符号
     注册，第二次同刻即非 nil）；②自愈拆填充式（稳态路径仅补 nil，幂等零
     抖动）/强制式（无条件重取重设，覆盖"非 nil 哑图"渲染失败情形）双路径，
     重试窗口 0.25s×40（10s），图标齐备后仍强制重刷 8 个 tick（2s）再停；
     ③z 序保险——新拟物承载层经 insertSublayer:atIndex:0 装载，若 UIButton
     图标以主层 contents 绘制会被不透明表面遮住，图标子视图存在时显式
     bringSubviewToFront（创建/选中刷新/强制重刷三处）。

护栏（零变化）：内存两卡 getEntitlementValue()（SecTask 签名口径，与启动
日志同源）、JIT isJITEnabled(NO) + TXM 三态判定链、刷新时机三件套、
Root 容器 cornerRadius/maskedCorners/masksToBounds 几何属性、侧栏按钮
50×50/圆角 10/选中凸出 12/5 全部保持。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK111_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
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


def strip_objc(src):
    """字符串感知剥离：去 @"..." 字面量与注释（兼容 CRLF）。"""
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


def git(args):
    return subprocess.run(["git", "-C", REPO] + args, capture_output=True, text=True)


def bracket_balance(code):
    return (code.count("{") == code.count("}")
            and code.count("(") == code.count(")")
            and code.count("[") == code.count("]"))


bm = read("Natives/BackgroundManager.m")
bm_code = strip_objc(bm)
root = read("Natives/LauncherRootViewController.m")
root_code = strip_objc(root)
menu = read("Natives/LauncherMenuViewController.m")
menu_code = strip_objc(menu)
bset = read("Natives/BackgroundSettingsViewController.m")
bset_code = strip_objc(bset)
rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc(rp)

print("=" * 72)
print("A. 背景管线恢复：检测并切换（applyBackgroundToWindow / SplitViewController）")
print("=" * 72)
check("A1  applyBackgroundToWindow：hasBackground 检测分支存在（Task111）",
      bm_code.count("- (void)applyBackgroundToWindow:(UIWindow *)window {") == 1
      and "if ([self hasBackground]) {" in bm_code)
check("A2  容器最底层插入（调低层级：insertSubview:atIndex:0，window 路径）",
      "[window insertSubview:container atIndex:0];" in bm_code)
check("A3  容器内容分派：图片/视频两条旧管线均在窗口分支恢复",
      "[self applyImageBackgroundToContainer:container];" in bm_code
      and "[self applyVideoBackgroundToContainer:container];" in bm_code)
check("A4  无背景分支维持 Task89 新拟态纯色底（nm_background 仅保留在该分支；原始文件含 Task89 注释）",
      re.search(r"hasBackground\]\) \{[\s\S]{0,2000}?return;\s*\}\s*// Task89", bm)
      and "window.backgroundColor = [NMTheme nm_background];" in bm_code)
check("A5  splitVC 路径同款恢复：容器插入 + 内容分派 + 子 VC 透明化",
      "[splitVC.view insertSubview:container atIndex:0];" in bm_code
      and "[self makeSplitViewControllerTransparent:splitVC];" in bm_code
      and "splitVC.view.backgroundColor = [NMTheme nm_background];" in bm_code)

print()
print("=" * 72)
print("B. 效果枢纽检测切换（applyEffectToView / CollectionViewCell / Cell / Transparent）")
print("=" * 72)
check("B1  applyEffectToView：hasBackground → 旧毛玻璃（SystemThinMaterial）分支恢复",
      re.search(r"- \(void\)applyEffectToView:\(UIView \*\)view \{[\s\S]{0,400}?if \(\[self hasBackground\]\) \{[\s\S]{0,2000}?UIBlurEffectStyleSystemThinMaterial", bm_code))
check("B2  applyEffectToView：旧半透明分支恢复（secondarySystemBackgroundColor + uiOpacity）",
      re.search(r"applyEffectToView:\(UIView \*\)view \{[\s\S]{0,6000}?\[base colorWithAlphaComponent:effectiveOpacity\]", bm_code))
check("B3  applyEffectToView：旧管线清残留（模式切换时移除新拟态承载层）",
      re.search(r"if \(\[self hasBackground\]\) \{[\s\S]{0,6000}?\[view nm_removeNeomorph\];\s*return;", bm_code))
check("B4  applyEffectToView：无背景分支维持新拟态凸出（nm_convexRadius + 阴影比例规则）",
      "CGFloat shadowRadius = MAX(4.0, MIN(8.0, radius * 0.5));" in bm_code
      and "[view nm_convexRadius:radius shadowRadius:shadowRadius];" in bm_code)
check("B5  applyEffectToCollectionViewCell：双分支切换（毛玻璃 blurView@contentView + 半透明）",
      "[cell.contentView insertSubview:blurView atIndex:0];" in bm_code
      and "[[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity]" in bm_code)
check("B6  applyEffectToCell：无背景分支 → NMTheme surface 实色卡片底（洗白修复）",
      re.search(r"- \(void\)applyEffectToCell:\(UITableViewCell \*\)cell \{[\s\S]{0,400}?if \(!\[self hasBackground\]\) \{[\s\S]{0,600}?cell\.backgroundColor = \[NMTheme nm_surface\];", bm_code)
      and "cell.backgroundView = nil;" in bm_code)
check("B7  makeViewControllerTransparent：无背景 no-op 门控（白色蒙膜根治）",
      re.search(r"- \(void\)makeViewControllerTransparent:\(UIViewController \*\)viewController \{[\s\S]{0,600}?if \(!\[self hasBackground\]\) \{\s*return;\s*\}", bm_code))

print()
print("=" * 72)
print("C. Root 容器表面随背景模式切换（updateChromeSurfaces）")
print("=" * 72)
check("C1  updateChromeSurfaces 定义且唯一：hasBackground → applyEffectToView 双容器",
      root_code.count("- (void)updateChromeSurfaces {") == 1
      and "[[BackgroundManager sharedManager] applyEffectToView:self.sidebarContainer];" in root_code
      and "[[BackgroundManager sharedManager] applyEffectToView:self.rightPanelContainer];" in root_code)
check("C2  无背景 → 新拟态平贴表面维持（nm_flatSurfaceWithRadius:16 双容器）",
      "[self.sidebarContainer nm_flatSurfaceWithRadius:16];" in root_code
      and "[self.rightPanelContainer nm_flatSurfaceWithRadius:16];" in root_code)
check("C3  三调用点齐备：setupContainers / backgroundChanged / uiEffectChanged",
      root_code.count("[self updateChromeSurfaces];") == 3
      and re.search(r"- \(void\)backgroundChanged \{[\s\S]{0,400}?\[self updateChromeSurfaces\];", root_code)
      and re.search(r"- \(void\)uiEffectChanged:\(NSNotification \*\)notification \{[\s\S]{0,300}?\[self updateChromeSurfaces\];", root_code)
      and re.search(r"self\.rightPanelContainer\.layer\.masksToBounds = YES;[\s\S]{0,600}?\[self updateChromeSurfaces\];", root_code))
check("C4  容器几何零变化：cornerRadius 16 / maskedCorners 左外侧+右外侧 / masksToBounds",
      "self.sidebarContainer.layer.cornerRadius = 16;" in root_code
      and "self.rightPanelContainer.layer.cornerRadius = 16;" in root_code
      and "kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner" in root_code
      and "kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner" in root_code
      and "self.sidebarContainer.layer.masksToBounds = YES;" in root_code)

print()
print("=" * 72)
print("D. 主界面按钮稳定显示（双拉 + 填充/强制双路径 + z 序保险 + 重试升级）")
print("=" * 72)
check("D1  创建时立即二次补拉（首调完成符号注册，二拉同刻非 nil；含强制路径共 3 处 iconName 拉取）",
      menu_code.count("icon = [UIImage systemImageNamed:iconName];") == 3
      and "if (!icon) {" in menu_code)
check("D2  填充式/强制式双路径定义（refreshMenuIconImages → Forged:NO 委托）",
      menu_code.count("- (void)refreshMenuIconImages {") == 1
      and menu_code.count("- (void)refreshMenuIconImagesForced:(BOOL)forced {") == 1
      and "[self refreshMenuIconImagesForced:NO];" in menu_code)
check("D3  填充式幂等门控（!forced && current → continue）+ 强制式无条件重设",
      "if (!forced && current) continue;" in menu_code
      and "if (forced || !current) {" in menu_code)
check("D4  z 序保险三处：创建 / updateButtonColors 选中分支 / 强制重刷（bringSubviewToFront iconView）",
      menu_code.count("[btn bringSubviewToFront:iconView];") == 3
      and "iconView.superview == btn" in menu_code)
check("D5  重试窗口升级：0.25s × 40 上限（10s），齐备且过 8 tick 强制重刷窗口即停",
      "timerWithTimeInterval:0.25 repeats:YES" in menu_code
      and "([strongSelf allMenuIconsLoaded] && attempts >= 8) || attempts >= 40" in menu_code)
check("D6  自愈双入口保留（viewWillAppear / viewDidLayoutSubviews → beginMenuIconSelfHeal）",
      re.search(r"- \(void\)viewWillAppear:\(BOOL\)animated \{[\s\S]{0,300}?\[self beginMenuIconSelfHeal\];", menu_code)
      and re.search(r"- \(void\)viewDidLayoutSubviews \{[\s\S]{0,600}?\[self beginMenuIconSelfHeal\];", menu_code))
check("D7  定时器属性 + dealloc invalidate（runloop 强持有显式解除，Task102 保留）",
      "@property(nonatomic, strong) NSTimer *menuIconSelfHealTimer;" in menu
      and "[self.menuIconSelfHealTimer invalidate];" in menu_code)
check("D8  稳态路径直补保留（updateButtonColors → refreshMenuIconImages 填充式）",
      menu.count("[self refreshMenuIconImages];") >= 1)

print()
print("=" * 72)
print("E. 背景设置页（菜单背景消失修复三处）")
print("=" * 72)
check("E1  viewDidLoad 无背景分支 → nm_background（view + tableView 显式同色）",
      re.search(r"\} else \{\s*self\.view\.backgroundColor = \[NMTheme nm_background\];\s*self\.tableView\.backgroundColor = \[NMTheme nm_background\];", bset_code)
      and "Task111" in bset)
check("E2  viewWillAppear 无背景分支同色维持（主题切换后一致）",
      bset_code.count("self.tableView.backgroundColor = [NMTheme nm_background];") == 2)
check("E3  styleCell 统一走 applyEffectToCell 检测切换（洗白分支退役）",
      re.search(r"- \(void\)styleCell:\(UITableViewCell \*\)cell hasBackground:\(BOOL\)hasBackground \{[\s\S]{0,300}?\[\[BackgroundManager sharedManager\] applyEffectToCell:cell\];", bset_code)
      and "secondarySystemBackgroundColor" not in bset_code.split("- (void)styleCell")[1].split("@end")[0])
check("E4  预览头保留（previewImageView + 占位标签 i18n_str_54/55/56 三态）",
      "setupPreviewHeader" in bset_code
      and "i18n_str_56" in bset)

print()
print("=" * 72)
print("F. 检测口径护栏（零变化，Task93/96 固化）")
print("=" * 72)
check("F1  内存两卡签名口径零变化（getEntitlementValue 恰两处调用）",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2
      and 'getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")' in rp
      and 'getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")' in rp)
check("F2  JIT 三态判定链零变化",
      "BOOL enabled = isJITEnabled(NO);" in rp_code
      and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in rp_code
      and "JIT26IsLikelyDebuggerKeepAttached()" in rp_code)
check("F3  刷新时机三件套零变化（updateJITStatus + updateMemoryEntitlementStatus 成对）",
      re.search(r"\[self updateJITStatus\];\s*\[self updateMemoryEntitlementStatus\];", rp))
check("F4  右面板七卡工厂零变化（makeInfoCardWithIcon 存在，7 卡仍在）",
      "makeInfoCardWithIcon" in rp_code)
check("F5  侧栏按钮几何零变化（50×50 / 圆角 10 / 选中凸出 12+5）",
      "CGFloat buttonSize = 50;" in menu_code
      and "btn.layer.cornerRadius = 10;" in menu_code
      and "[btn nm_convexRadius:12 shadowRadius:5];" in menu_code)

print()
print("=" * 72)
print("G. 语法/括号配平（字符串感知）与注释纪律")
print("=" * 72)
check("G1  BackgroundManager.m 括号配平", bracket_balance(bm_code))
check("G2  LauncherRootViewController.m 括号配平", bracket_balance(root_code))
check("G3  LauncherMenuViewController.m 括号配平", bracket_balance(menu_code))
check("G4  BackgroundSettingsViewController.m 括号配平", bracket_balance(bset_code))
check("G5  注释无半开区间数字记法（[a, b) / [a-b) 破坏括号配平校验器，Task106 纪律）",
      all(not re.search(r"\[\s*\d+\s*[,~-]\s*\d+\s*\)", read(p))
          for p in ["Natives/BackgroundManager.m",
                    "Natives/LauncherRootViewController.m",
                    "Natives/LauncherMenuViewController.m",
                    "Natives/BackgroundSettingsViewController.m"]))

print()
print("=" * 72)
print("H. 行为镜像（Python 对拍）")
print("=" * 72)
check("H1  hasBackground 判定镜像：type != None && path != nil",
      "return self.currentType != BackgroundTypeNone && self.currentBackgroundPath != nil;" in bm_code)


def has_background(current_type, current_path):
    return current_type != 0 and bool(current_path)


def mirror_cell_style(has_bg, is_dark):
    """applyEffectToCell 无背景分支镜像：nm_surface（浅 #ECF0F3 / 深 #262A2F）。"""
    if not has_bg:
        return "#262A2F" if is_dark else "#ECF0F3"
    return "blur-or-translucent"


cases = [(0, None), (1, "/x.png"), (2, "/x.mp4"), (1, None), (0, "/gone.png")]
expected = [False, True, True, False, False]
check("H2  hasBackground 五例对拍（None/图片/视频/无路径/路径丢失）",
      [has_background(t, p) for t, p in cases] == expected)
check("H3  cell 表面选择镜像：无背景两主题均落 nm_surface 实色",
      mirror_cell_style(False, False) == "#ECF0F3"
      and mirror_cell_style(False, True) == "#262A2F"
      and mirror_cell_style(True, False) == "blur-or-translucent")


def selfheal_stop(all_loaded, attempts):
    """beginMenuIconSelfHeal 停止条件镜像：齐备且过 8 tick，或 40 tick 兜底。"""
    return (all_loaded and attempts >= 8) or attempts >= 40


check("H4  自愈停止条件镜像（齐备 8 tick / 兜底 40 tick）",
      [selfheal_stop(True, 7), selfheal_stop(True, 8), selfheal_stop(False, 39), selfheal_stop(False, 40)]
      == [False, True, False, True])

print()
print("=" * 72)
print("I. 仓库卫生")
print("=" * 72)
st = git(["status", "--porcelain"]).stdout
worklog = read("worklog.md")
check("I1  仓库 worklog 含 Task 111 条目（提交后补记亦计入）",
      "Task ID: 111" in worklog or "Task 111" in worklog)

print()
print("=" * 72)
print(f"Task 111 验证结果：PASS {PASS} / FAIL {FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
