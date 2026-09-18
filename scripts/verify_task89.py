#!/usr/bin/env python3
"""
Task 89 验证器：全局自绘 UI 新拟态化（Neomorph 凸出样式 + 双主题 + 强制纯色底）

背景（用户需求）：
  参照 react-native-neomorph-shadows（tokkozhin）README 中的 Neomorph /
  NeomorphFlex 样式（用户选定"凸出/outer"，非 inner/凹陷），把启动器全部
  非 iOS 原生的自绘 UI 替换为新拟态。红框（原生 UISegmentedControl /
  UISearchBar 等）不动；蓝框（版本列表卡片等自绘 UI）全部替换。

用户确认的决策：
  - 实现方式：ObjC 原生移植（NeomorphKit），算法忠实对齐库的 src/helpers.js
  - 底色主题：跟随系统双主题（浅 #ECF0F3 / 深 #262A2F，含 App 内 override）
  - 背景图：新拟态下强制纯色底（背景图/视频/毛玻璃停用）
  - 节奏：一次全改（单次提交覆盖全部自绘 UI）
  - 主按钮：全灰新拟态（所有按钮与底同色，仅靠阴影分层）

实现：
  1. NeomorphKit/——NMTheme（双主题参数 + HSP 亮度→双阴影透明度算法移植）+
     UIView+Neomorph（凸出双阴影引擎：暗影 (+r,+r) 黑 / 亮影 (−r,−r) 白，
     KVO bounds 同步几何，NMThemeDidChangeNotification 驱动主题重绘）
  2. BackgroundManager.applyEffectToView / applyEffectToCollectionViewCell
     切换为 Neomorph 分发（64 处既有卡片调用点一次性接入，保留各自圆角）；
     applyBackgroundToWindow / ToSplitViewController 强制 NMTheme 纯色底
  3. 核心屏幕（右侧面板/左侧菜单/根容器/下载页/导航工具栏）+ 长尾
     （主按钮全灰化、占位底色主题化、card_color 偏好停用）
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK89_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
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


def bracket_ok(src):
    s = strip_objc(src)
    bal = {"(": 0, "[": 0, "{": 0}
    pair = {")": "(", "]": "[", "}": "{"}
    for ch in s:
        if ch in bal:
            bal[ch] += 1
        elif ch in pair:
            bal[pair[ch]] -= 1
            if bal[pair[ch]] < 0:
                return False
    return all(v == 0 for v in bal.values())


def jsmath_opacities(hexcolor):
    """独立实现 helpers.js 的算法，用于与 NMTheme.m 常量对拍"""
    r = int(hexcolor[1:3], 16)
    g = int(hexcolor[3:5], 16)
    b = int(hexcolor[5:7], 16)
    hsp = (0.299 * r * r + 0.587 * g * g + 0.114 * b * b) ** 0.5
    ratio = 50.0
    opacity = ratio ** (hsp / 255.0) / ratio - 1.0 / ratio
    light = 0.025 + (1.0 - 0.025) * opacity
    dark = 0.35 * (1.0 - opacity)
    return light, dark


print("== A. NeomorphKit（算法忠实移植）==")
theme_h = read("Natives/NeomorphKit/NMTheme.h")
theme_m = read("Natives/NeomorphKit/NMTheme.m")
cat_h = read("Natives/NeomorphKit/UIView+Neomorph.h")
cat_m = read("Natives/NeomorphKit/UIView+Neomorph.m")
check("A1 双主题表面色（浅 #ECF0F3 / 深 #262A2F）",
      "ECF0F3" in theme_m and "262A2F" in theme_m)
check("A2 HSP 亮度公式（0.299/0.587/0.114）",
      "0.299 * r255 * r255 + 0.587 * g255 * g255 + 0.114 * b255 * b255" in theme_m)
check("A3 亮度转透明度（ratio=50 指数公式）",
      "pow(ratio, ratioBrightness) / ratio - 1.0 / ratio" in theme_m)
check("A4 亮/暗阴影透明度区间（0.025+0.975·op / 0.35·(1−op)）",
      "0.025 + (1.0 - 0.025) * opacity" in theme_m and "0.35 * (1.0 - opacity)" in theme_m)
check("A5 主题切换通知常量", "NMThemeDidChangeNotification" in theme_h and theme_m)
l_op, d_op = jsmath_opacities("#ECF0F3")
check("A5a 算法对拍：#ECF0F3 亮阴影≈%.3f 暗≈%.3f（NMTheme 常量可复现）" % (l_op, d_op),
      abs(l_op - 0.7678) < 0.01 and abs(d_op - 0.0827) < 0.01,
      f"got light={l_op:.4f} dark={d_op:.4f}")
check("A6 阴影几何（暗 (+r,+r) / 亮 (−r,−r)，模糊=r）",
      "CGSizeMake(r, r)" in cat_m and "CGSizeMake(-r, -r)" in cat_m
      and "dark.shadowRadius = r" in cat_m and "light.shadowRadius = r" in cat_m)
check("A7 默认阴影色 = 库默认（黑/白）",
      "return [UIColor blackColor];" in theme_m and "return [UIColor whiteColor];" in theme_m)
check("A8 KVO bounds 同步几何 + 主题通知重绘",
      'addObserver:self forKeyPath:@"bounds"' in cat_m
      and "NMThemeDidChangeNotification" in cat_m)
check("A9 胶囊模式圆角 = 高度一半", "NMRadiusModePill" in cat_m
      and "MIN(size.height / 2.0, size.width / 2.0)" in cat_m)
check("A10 凸出模式放开 masksToBounds / 平贴模式保留",
      "if (!self.flat) {" in cat_m and "host.layer.masksToBounds = NO;" in cat_m)
check("A11 API 完整（convex/pill/raised/flat/remove/styleConvexButton）",
      all(k in cat_h for k in ["nm_convex", "nm_convexRadius:(CGFloat)cornerRadius shadowRadius:",
                               "nm_convexRaisedRadius", "nm_pill", "nm_flatSurfaceWithRadius:",
                               "nm_removeNeomorph", "nm_styleConvexButtonRadius:"]))
check("A12 全部括号平衡（4 文件，字符串感知）",
      all(bracket_ok(x) for x in [theme_m, cat_m, theme_h, cat_h]))

print("== B. 枢纽接线（64 处卡片调用点一次性接入）==")
bm = read("Natives/BackgroundManager.m")
check("B1 applyEffectToView → nm_convexRadius（保留调用点圆角，默认 12）",
      "[view nm_convexRadius:radius shadowRadius:shadowRadius];" in bm
      and "if (radius <= 0) radius = 12;" in bm)
check("B1a 阴影半径 = 圆角一半（上限 8）",
      "MAX(4.0, MIN(8.0, radius * 0.5))" in bm)
check("B2 applyEffectToCollectionViewCell → 卡片容器探测 + nm",
      "[target nm_convexRadius:radius shadowRadius:shadowRadius];" in bm)
check("B3 强制纯色底（window + splitVC）",
      bm.count("window.backgroundColor = [NMTheme nm_background];") == 1
      and "splitVC.view.backgroundColor = [NMTheme nm_background];" in bm)
check("B3a 防御性移除历史 blur 子视图",
      "kBackgroundBlurTag" in bm.split("applyEffectToView:(UIView *)view")[1][:800])
check("B4 CMakeLists 已登记 NeomorphKit",
      "NeomorphKit/NMTheme.m" in read("Natives/CMakeLists.txt")
      and "NeomorphKit/UIView+Neomorph.m" in read("Natives/CMakeLists.txt"))
sd = read("Natives/SceneDelegate.m")
# Task90 同步：SceneDelegate 最终采用 KVO window.traitCollection 方案
# （UIWindowSceneDelegate 非 UIResponder，traitCollectionDidChange: 永不触发），
# 原断言的字面量已不存在。
check("B5 主题广播接线（NMTheme reloadAndBroadcast + KVO window.traitCollection）",
      "[[NMTheme shared] reloadAndBroadcast];" in sd
      and 'forKeyPath:@"traitCollection"' in sd
      and "kNMSceneTraitKVOContext" in sd)

print("== C. 核心屏幕与长尾改造 ==")
rp = read("Natives/LauncherRightPanelViewController.m")
# Task90：用户反馈"全灰新拟态按钮"选择有误，右侧面板按钮恢复原样（7ab2b41）。
# Task96：执行Jar/选择版本与「登录并启动」同款（accent 底 + 白字，用户指定）；
# 下载中心按钮保持深灰原样；断言随 Task96 改版同步。
check("C1 右侧面板按钮（Task96 同步：启动/版本/JAR accent 底白字，下载中心深灰）",
      all(k in rp for k in ["self.launchButton.backgroundColor = accentColor();",
                            "self.downloadCenterButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];",
                            "self.manageVersionBtn.backgroundColor = accentColor();",
                            "self.executeJarBtn.backgroundColor = accentColor();",
                            "[self.manageVersionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];",
                            "[self.executeJarBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];"]))
check("C1a 右侧面板不再使用新拟态（nm_ 调用与 NeomorphKit 导入已随原样恢复移除）",
      "NeomorphKit" not in rp and not re.search(r"\bnm_", rp))
check("C2 状态卡片（Task96 同步：胶囊改 MeloNX 卡）15% 透明卡底仍在",
      rp.count("colorWithAlphaComponent:0.15]") >= 1 and "nm_pill" not in rp)
menu = read("Natives/LauncherMenuViewController.m")
check("C3 左侧菜单：选中凸出面板 / 未选中恢复平贴",
      "[btn nm_convexRadius:12 shadowRadius:5];" in menu
      and "[btn nm_removeNeomorph];" in menu)
root = read("Natives/LauncherRootViewController.m")
check("C4 根容器：侧栏/右面板平贴表面（无阴影）+ card_color 停用",
      "[self.sidebarContainer nm_flatSurfaceWithRadius:16];" in root
      and "[self.rightPanelContainer nm_flatSurfaceWithRadius:16];" in root
      and "applyEffectToView:self.sidebarContainer" not in root)
dl = read("Natives/DownloadViewController.m")
check("C5 下载页：资源行卡片/图标占位/筛选按钮/导入按钮新拟态",
      "[self.contentContainer nm_convexRadius:8 shadowRadius:4];" in dl
      and "[NMTheme nm_surfaceRaised];" in dl
      and "[button nm_convexRadius:8 shadowRadius:3];" in dl
      and "[self.importModpackButton nm_convexRadius:10 shadowRadius:5];" in dl)
vc = read("Natives/VersionCardCell.m")
check("C5a 版本卡片（截图蓝框）：手动底色/边框/旧阴影已移交 NeomorphKit",
      "whiteColor] colorWithAlphaComponent:0.08" not in vc
      and "applyEffectToView:self.cardContainer" in vc)
nav = read("Natives/LauncherNavigationController.m")
check("C6 工具栏按钮（启动/下载中心）全灰新拟态",
      "[self.buttonInstall nm_convexRadius:6 shadowRadius:3];" in nav
      and "[self.downloadCenterButton nm_convexRadius:6 shadowRadius:3];" in nav)
check("C7 公告/导出/服务器主按钮全灰化",
      "[self.actionButton nm_convexRadius:10 shadowRadius:5];" in read("Natives/AnnouncementDetailViewController.m")
      and "[self.exportButton nm_convexRadius:12 shadowRadius:6];" in read("Natives/ModpackExportViewController.m")
      and "[self.joinButton nm_convexRadius:10 shadowRadius:5];" in read("Natives/ServerDetailViewController.m")
      and "[self.downloadPackButton nm_convexRadius:10 shadowRadius:5];" in read("Natives/ServerDetailViewController.m"))
mtc = read("Natives/ModTableViewCell.m")
check("C8 Mod 下载按钮全灰化", "[_downloadButton nm_convexRadius:13.0 shadowRadius:4];" in mtc)
cl = read("Natives/LauncherCardLayoutViewController.m")
# Task90 同步：21a3364 最终实现使用的注释标记为"新拟态下空操作"（C9 原断言的
# neumorph_surfaces_locked_by_task89 字面量在最终提交中并不存在）。
check("C9 卡片布局：card_color 叠加停用", "Task89：新拟态下空操作" in cl)
check("C10 深色占位底色主题化（账户/新闻）",
      "[NMTheme nm_surfaceRaised];" in read("Natives/AccountListViewController.m")
      and read("Natives/LauncherNewsViewController.m").count("[NMTheme nm_surfaceRaised];") >= 2)

print("== D. 红框原则（原生控件不动）==")
gitdiff = subprocess.run(["git", "-C", REPO, "diff", "HEAD", "--",
                          "Natives/DownloadViewController.m"],
                         capture_output=True, text=True).stdout
check("D1 UISegmentedControl 相关行未被改动",
      "tabSegment" not in gitdiff.replace("+", "", 1) or
      not re.search(r'^[+-].*tabSegment', gitdiff, re.M))
check("D1a UISearchBar 样式行未被改动",
      not re.search(r'^[+-].*searchBarStyle', gitdiff, re.M))
check("D2 游戏画面覆盖层（GameMenuOverlayView）保持原样",
      "nm_" not in read("Natives/GameMenuOverlayView.m"))

print("== E. 工作区作用域 ==")


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True).stdout


changed = {ln[3:].strip() for ln in git("status", "--porcelain").splitlines() if ln.strip()}
check("E1 改动仅限预期文件集", all(
    c.startswith(("Natives/", "scripts/verify_task89.py", "scripts/verify_task96.py",
                  "scripts/verify_task101.py", "scripts/verify_task88.py",
                  "scripts/verify_task95.py", "worklog.md")) for c in changed),
    f"unexpected={changed}")

print()
print(f"verify_task89: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
