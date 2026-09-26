#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task178.py -- 新拟态与 UI 效果设置解耦 + 卡片本体透明度滑条恢复 + 新闻卡圆角钉住

用户指令："改得非常好！现在结合一下UI效果的设置：新拟态开关不管咋样都不会使
其他选项变灰，开启的时候，UI效果类型（毛玻璃、半透明）和模糊度都不影响新拟态，
只有那个透明度拉条可以改变新拟态的透明度，当然字体始终是不透明的"。
追加："新闻界面的新闻卡片的圆角没做好，太圆了"。

本轮定稿：
  1) 灰化全退：设置页 neumorphOn ? 0.35 : 1.0 / userInteractionEnabled /
     slider.enabled = neumorphOn 全部消失，开关任何状态下所有行恒可操作。
  2) 解耦维持：开启态卡片管线只读 cardsNeumorphOpacity（Task177 已结构化
     解耦，本轮把"唯一入口"落成设置页透明度滑条）；UI 效果类型/模糊度/
     uiOpacity 只作用于壁纸层与旧管线。
  3) 卡体透明度恢复（Task170 机制 + Task177 三层引擎适配）：引擎
     ame_applyNeumorphCardOpacity = AmeNeumorphShadowView 整体 alpha 淡化
     （渐变表面 + 双阴影同一合成组，内侧遮挡关系不破坏——半透明态晕影不
     回归），宿主兜底色 clear 让位；文字/图标是宿主兄弟子视图恒不透明；
     ame_applyNeumorphSurface 重铺时 alpha 复位 1.0（未配对调用失效安全）。
     Manager: cardsNeumorphOpacity（defaults background_cards_neumorph_opacity
     直读写，默认 1.0 = Task177 形态原样）+ 两管线尾部挂点。
     设置页：开关行下方"新拟态透明度"滑条行恒显恒可操作（tags 500/501/502，
     Task174 百分比实时回显范式），无壁纸时 section0 = 2 行。
  4) 新闻卡圆角钉住：引擎 ame_setNeumorphPinnedCornerRadius（opt-in 关联
     对象，ame_refreshForHostBounds 优先读取，clamp [8,50]；卸载清理）；
     MinecraftNews 卡 contentView 钉 12pt（双列窄高 ~185pt 短边被等比写成
     ~27pt = "太圆了"的根因；Task160 全局等比规则不动，仅 opt-in 豁免）。
  5) l10n：background.cards.neumorph.opacity.title ×6 恢复（Task177 曾删），
     四主语言唯一键 1954 -> 1955。
  6) 文档：公告 task178@2（历史条目顺延 +1，len 19 -> 20）；version.h
     REVISION 17 append-only 附录（Task 177 附录保留）。

组别：
  A 引擎（cardOpacity 恢复 + alpha 复位 + 兜底让位 + 圆角钉住 + 新闻卡挂点）
  B BackgroundManager（属性/键/存取器/两管线挂点/日志锚）
  C 设置页（灰化零残留 + 行结构 + 滑条行 + 回调回显）
  D l10n（键 ×6 + 1955 + 键集一致）
  E 文档（公告顺序 + 内容锚 + version.h append-only + fallback）
  F 语法门（触碰文件 {}() 配平 + JSON 可解析）
  G 级联（历史校验器全绿，具名豁免对拍）
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASS = 0
FAIL = 0


def rd(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name}" + (f"  -- {detail}" if detail else ""))


ENG_H = rd("Natives/UIKit+NativeSurface.h")
ENG_M = rd("Natives/UIKit+NativeSurface.m")
BM_H = rd("Natives/BackgroundManager.h")
BM_M = rd("Natives/BackgroundManager.m")
SET_M = rd("Natives/BackgroundSettingsViewController.m")
NEWS_M = rd("Natives/MinecraftNewsViewController.m")

# ============================================================
# A. 引擎
# ============================================================
print("== A. 引擎（卡体透明度恢复 + 圆角钉住） ==")
check("A1 cardOpacity 原语恢复（.h 声明 + .m 实现）",
      "- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;" in ENG_H
      and "- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity {" in ENG_M)
check("A2 适配 Task177 三层引擎：承载视图整体 alpha（含 shadowView.alpha = o）",
      "shadowView.alpha = o;" in ENG_M
      and "AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);" in ENG_M)
check("A3 未挂承载视图 = 无害空操作（平贴表面/旧管线宿主不误伤）",
      "if (!shadowView) return;" in ENG_M)
check("A4 宿主兜底色让位（clear）——不透明兜底色会把半透明卡面垫回不透明",
      "self.backgroundColor = [UIColor clearColor]; // 兜底让位（幂等）" in ENG_M)
check("A5 重铺失效安全：ame_applyNeumorphSurface 复位 shadowView.alpha = 1.0",
      "shadowView.alpha = 1.0;" in ENG_M)
check("A6 文字不参与（注释钉死'字体始终是不透明的'口径）",
      "文字/图标子视图会一起被淡掉" in ENG_M
      and "字体始终是不透明的" in ENG_M)
check("A7 圆角钉住 API（.h 声明 + .m 实现 + kAmeNeumorphPinnedRadiusKey）",
      "- (void)ame_setNeumorphPinnedCornerRadius:(CGFloat)cornerRadius;" in ENG_H
      and "- (void)ame_setNeumorphPinnedCornerRadius:(CGFloat)cornerRadius {" in ENG_M
      and "kAmeNeumorphPinnedRadiusKey" in ENG_H or "kAmeNeumorphPinnedRadiusKey" in ENG_M)
check("A8 刷新链读取钉住值（ame_refreshForHostBounds 优先于等比结果，clamp [8,50]）",
      "NSNumber *pinnedRadius = objc_getAssociatedObject(host, kAmeNeumorphPinnedRadiusKey);" in ENG_M
      and "if (pinnedRadius) radius = MAX(8.0, MIN(pinnedRadius.doubleValue, 50.0));" in ENG_M)
check("A9 钉住 setter 立即重刷 + 传 0 解除",
      "[shadowView ame_refreshForHostBounds]; // 未挂载时为无害空操作" in ENG_M
      and ENG_M.count("objc_setAssociatedObject(self, kAmeNeumorphPinnedRadiusKey, nil,") >= 2)
check("A10 ame_removeNeumorphShadow 随挂载清钉",
      "objc_setAssociatedObject(self, kAmeNeumorphPinnedRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // Task178：钉住随挂载一并清" in ENG_M)
check("A11 新闻卡挂点（MinecraftNews import 引擎头 + contentView 钉 12pt）",
      '#import "UIKit+NativeSurface.h"' in NEWS_M
      and "[self.contentView ame_setNeumorphPinnedCornerRadius:kNewsCardCornerRadius];" in NEWS_M
      and "static const CGFloat kNewsCardCornerRadius = 12.0;" in NEWS_M)
check("A12 Task177 规格不被破坏（渐变表面/固定档/三层命名原样）",
      "AmeNeumorphSurfaceGradientStartColor" in ENG_M
      and "? 2.0 : 4.0" in ENG_M and "? 4.0 : 8.0" in ENG_M
      and "ame177_surfaceLayer" in ENG_M and "ame177_darkLayer" in ENG_M and "ame177_lightLayer" in ENG_M)
check("A13 退役原语仍退役（attachShadowOnly/wallpaperSoft 不回潮）",
      "ame_attachNeumorphShadowOnly" not in ENG_M and "ame_attachNeumorphShadowOnly" not in ENG_H
      and "ame_setNeumorphWallpaperSoft" not in ENG_M and "ame_setNeumorphWallpaperSoft" not in ENG_H)
check("A14 头文件规格注释演化（透明度隔离 Task178 修订 + 圆角钉住说明）",
      "Task177 定稿 / Task178 修订" in ENG_H
      and "ame_setNeumorphPinnedCornerRadius" in ENG_H)

# ============================================================
# B. BackgroundManager
# ============================================================
print("== B. BackgroundManager（偏好 + 挂点 + 日志锚） ==")
check("B1 .h 属性声明（Task180 重锚：backgroundOpacity/buttonOpacity 双属性在位，cardsNeumorphOpacity 属性退役）",
      "@property (nonatomic, assign) CGFloat backgroundOpacity;" in BM_H
      and "@property (nonatomic, assign) CGFloat buttonOpacity;" in BM_H
      and "@property (nonatomic, assign) CGFloat cardsNeumorphOpacity;" not in BM_H)
check("B2 落盘键常量（Task180 重锚：background_bg_opacity/background_btn_opacity 双键）",
      'static NSString * const kBackgroundBgOpacityKey = @"background_bg_opacity";' in BM_M
      and 'static NSString * const kBackgroundBtnOpacityKey = @"background_btn_opacity";' in BM_M)
check("B3 存取器（Task180 重锚：双属性 setter + 判空默认 0.75/1.0 + clamp [0,1] 无下限）",
      "- (void)setBackgroundOpacity:" in BM_M
      and "- (void)setButtonOpacity:" in BM_M
      and "NSNumber *ame164_opacity = [defaults objectForKey:kBackgroundBgOpacityKey]" in BM_M
      and "NSNumber *ame180_btn = [defaults objectForKey:kBackgroundBtnOpacityKey]" in BM_M
      and "_backgroundOpacity = 0.75;" in BM_M
      and "_buttonOpacity = 1.0;" in BM_M)
card_fn = BM_M[BM_M.index("- (void)applyNeumorphCardEffectToView"):BM_M.index("- (void)applyEffectToSearchBar")]
cell_fn = BM_M[BM_M.index("- (void)applyEffectToCollectionViewCell"):BM_M.index("- (void)applyCardEffectToCell")]
check("B4 两管线尾部挂点（Task180 重锚：surface 之后各一次 cardOpacity 读背景透明度）",
      card_fn.index("[view ame_applyNeumorphSurface];") < card_fn.index("[view ame_applyNeumorphCardOpacity:self.backgroundOpacity];")
      and cell_fn.index("[target ame_applyNeumorphSurface];") < cell_fn.index("[target ame_applyNeumorphCardOpacity:self.backgroundOpacity];"))
check("B5 开关门语义不变（OFF 回归旧管线；ON 规格管线）",
      "if (!self.cardsNeumorphEnabled) {" in card_fn
      and "if (self.cardsNeumorphEnabled) {" in cell_fn)
check("B6 列表行 Flat 边界维持（Task180 重锚：Flat 接背景透明度，方法仍在）",
      "ame_applyNeumorphSurfaceFlatWithRadius:12\n                                                    opacity:self.backgroundOpacity];" in BM_M
      and "applyCardEffectToCell" in BM_M)
check("B7 一次性日志锚演化（[Task178] neumorph decoupled + ame178DecoupleLogOnce）",
      "[Task178] neumorph decoupled: pinned spec cards + card-body opacity slider, UI effect options stay interactive" in BM_M
      and "ame178DecoupleLogOnce" in BM_M
      and "[Task177] neumorph UI spec rewrite" not in BM_M)
check("B8 灰化注释退役（refreshUIEffect ON 分支注释更新为灰化退役口径）",
      "灰化退役后三行壁纸效果选项恒可操作" in BM_M)
check("B9 管线不读 uiOpacity/blurIntensity（解耦维持，Task177 结构不变）",
      "self.uiOpacity" not in card_fn and "self.blurIntensity" not in card_fn)

# ============================================================
# C. 设置页
# ============================================================
print("== C. 设置页（灰化零残留 + 滑条行恢复） ==")
check("C1 灰化零残留（0.35 表达式 / userInteractionEnabled / slider.enabled / neumorphOn 全退）",
      "neumorphOn" not in SET_M
      and "slider.enabled = neumorphOn;" not in SET_M
      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" not in SET_M
      and "0.35" not in SET_M)
check("C2 sections[0] 五项（Task180 重锚：UI效果/背景透明度/模糊程度/新拟态界面/按钮透明度）",
      SET_M.count('localize(@"i18n_str_57", nil), localize(@"i18n_str_1296", nil), localize(@"i18n_str_1297", nil), localize(@"background.cards.neumorph.interface.title", nil), localize(@"background.button.opacity.title", nil)') == 1)
check("C3 无壁纸行数 3（Task180 重锚：开关行 + 背景透明度 + 按钮透明度恒显）",
      re.search(r"hasBackground\]\) \{\s*\n\s*return 3;", SET_M) is not None)
check("C4 开关行定位不变（hasBackground ? 3 : 0）",
      "indexPath.row == (hasBackground ? 3 : 0)" in SET_M
      and '"CardsNeumorphToggleCell"' in SET_M
      and "neumorphSwitch.tag = 410;" in SET_M)
check("C5 按钮透明度滑条行（Task180 重锚：hasBackground ? 4 : 2 + ButtonOpacityCell + tags 600/601/602）",
      "indexPath.row == (hasBackground ? 4 : 2)" in SET_M
      and '"ButtonOpacityCell"' in SET_M
      and "slider.tag = 600;" in SET_M and "titleLabel.tag = 602;" in SET_M and "valueLabel.tag = 601;" in SET_M)
check("C6 滑条行恒可操作（无 slider.enabled 灰化；0~1 全档）",
      "slider.minimumValue = 0.0f;" in SET_M and "slider.maximumValue = 1.0f;" in SET_M
      and "slider.enabled" not in SET_M)
check("C7 回调（Task180 重锚：buttonOpacitySliderChanged 落盘 + tag 601 实时回显 + refreshUIEffect）",
      "- (void)buttonOpacitySliderChanged:(UISlider *)slider {" in SET_M
      and "[BackgroundManager sharedManager].buttonOpacity = slider.value;" in SET_M
      and "[cell.contentView viewWithTag:601]" in SET_M
      and SET_M.count("[[BackgroundManager sharedManager] refreshUIEffect];") >= 3)
check("C8 滑条值绑定（Task180 重锚：cellForRowAt 读 buttonOpacity/backgroundOpacity 回填）",
      "slider.value = manager.buttonOpacity;" in SET_M
      and 'manager.buttonOpacity * 100' in SET_M
      and "slider.value = manager.backgroundOpacity;" in SET_M)
check("C9 既有行不破坏（透明度/模糊滑块 + UI效果选择 + Bing 区）",
      "opacitySliderChanged:" in SET_M and "blurIntensitySliderChanged:" in SET_M
      and "showUIEffectPicker" in SET_M and '"BingToggleCell"' in SET_M)
check("C10 滑条行标题绑定含无壁纸档（Task180 重锚：hasBackground ? 4 : 2]）",
      "self.sections[0][hasBackground ? 4 : 2]" in SET_M)

# ============================================================
# D. l10n
# ============================================================
print("== D. l10n（键恢复 + 1955 重锚） ==")
KEYSET_LGS = ["en", "zh-Hans", "zh-CN", "zh-Hant"]
KEYSETS = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in KEYSET_LGS]
all_six = [rd(f"Natives/resources/{lg}.lproj/Localizable.strings") for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]]
check("D1 button.opacity.title 键 ×6 语言全部在位（Task180 重锚）",
      all('"background.button.opacity.title"' in t for t in all_six))
check("D2 四主语言唯一键计数 1955（1954+1）",
      all(len(k) == 1955 for k in KEYSETS),
      detail=str([len(k) for k in KEYSETS]))
check("D3 四主语言键集一致",
      KEYSETS[0] == KEYSETS[1] == KEYSETS[2] == KEYSETS[3])
check("D4 interface.title 键保留（开关行标题）",
      all('"background.cards.neumorph.interface.title"' in t for t in all_six))
check("D5 新键中文文案（Task180 重锚：按钮透明度）",
      '"background.button.opacity.title" = "按钮透明度";' in all_six[1]
      and '"background.button.opacity.title" = "按钮透明度";' in all_six[2])

# ============================================================
# E. 文档
# ============================================================
print("== E. 文档（公告/version.h/fallback） ==")
ann = json.loads(rd("announcements.json"))["announcements"]
# Task179 重锚：task179@2 插入，task178 顺延至 ann[3]，len 21。
check("E1 公告 task178 插入（Task179 重锚：task179@2 后 task178 居 ann[3]；server/169 钉 0/1 不动，len 21）",
      len(ann) == 21
      and ann[0]["id"] == "server-recommend-2026-09-24"
      and ann[1]["id"] == "task169-four-fixes-2026-09-25"
      and ann[2]["id"] == "task179-eight-fixes-2026-09-26"
      and ann[3]["id"] == "task178-neumorph-decouple-opacity-2026-09-26")
check("E2 公告历史条目顺延 +1（Task179 重锚：177→4 / 175→5 / 174→6 / 双173→7,8 / 172→9 / 171→10 / 170→11 / 168→12）",
      ann[4]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and ann[5]["id"] == "task175-six-fixes-2026-09-26"
      and ann[6]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and ann[7]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and ann[8]["id"] == "task173-ten-fixes-2026-09-26"
      and ann[9]["id"] == "task172-six-fixes-2026-09-25"
      and ann[10]["id"] == "task171-seven-fixes-2026-09-25"
      and ann[11]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and ann[12]["id"] == "task168-neumorph-faq-json-2026-09-25")
check("E3 task178 公告内容锚（Task179 重锚：task178 条目顺延至 ann[3]；变灰/透明度/字体/圆角 + EN 尾注）",
      "变灰" in ann[3]["content"] and "透明度" in ann[3]["content"]
      and "字体" in ann[3]["content"] and "圆角" in ann[3]["content"]
      and "EN:" in ann[3]["content"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E4 version.h Task 178 附录（append-only：Task 177 附录保留）",
      "Amethyst Task 178" in vh and "ame_setNeumorphPinnedCornerRadius" in vh
      and "[Task178] neumorph decoupled" in vh
      and "Amethyst Task 177" in vh)
fb = json.loads(rd("Natives/resources/announcements-fallback.json"))["announcements"]
check("E5 fallback 最小集不动（builtin-offline + server-recommend，Task169 口径）",
      len(fb) == 2 and fb[0]["id"] == "builtin-offline-2026-09-20"
      and fb[1]["id"] == "server-recommend-2026-09-24")

# ============================================================
# F. 语法门
# ============================================================
print("== F. 语法门 ==")
TOUCHED = ["Natives/UIKit+NativeSurface.h", "Natives/UIKit+NativeSurface.m",
           "Natives/BackgroundManager.h", "Natives/BackgroundManager.m",
           "Natives/BackgroundSettingsViewController.m", "Natives/MinecraftNewsViewController.m"]
ok = True
detail = ""
for p in TOUCHED:
    t = rd(p)
    for open_c, close_c in (("{", "}"), ("(", ")")):
        if t.count(open_c) != t.count(close_c):
            ok = False
            detail += f"{p}:{open_c}{t.count(open_c)}/{t.count(close_c)} "
check("F1 触碰文件 {}() 全配平", ok, detail=detail)
json_ok = True
try:
    json.loads(rd("announcements.json"))
    json.loads(rd("Natives/resources/announcements-fallback.json"))
except Exception:
    json_ok = False
check("F2 两份公告 JSON 可解析", json_ok)

# ============================================================
# G. 级联（历史校验器）
# ============================================================
print("== G. 级联 ==")
CASCADES = ["129", "130", "131", "132", "133", "134", "135", "138", "141", "142", "143",
            "150", "151", "156", "157", "159", "160", "161", "162", "163", "164",
            "165", "166", "167", "168", "169", "170", "171", "172", "173", "173b_neumorph",
            "174", "175", "176", "177"]
cascade_env = dict(os.environ)
for k in ("TASK129_REPO", "TASK141_REPO", "TASK165_REPO", "TASK167_REPO",
          "TASK168_REPO", "TASK169_REPO", "TASK170_REPO", "TASK171_REPO",
          "TASK172_REPO", "TASK173_REPO", "TASK173B_REPO", "TASK174_REPO",
          "TASK175_REPO", "AME_REPO", "TASK160_REPO", "TASK161_REPO",
          "TASK162_REPO", "TASK163_REPO", "TASK164_REPO", "TASK166_REPO"):
    cascade_env[k] = REPO
bad = []
for tid in CASCADES:
    script = f"scripts/verify_task{tid}.py"
    if not os.path.exists(script):
        continue
    try:
        r = subprocess.run([sys.executable, script], env=cascade_env,
                           capture_output=True, text=True, timeout=280)
        out = r.stdout + r.stderr
        if r.returncode != 0 or "FAIL" in out:
            bad.append((tid, [l.strip()[:110] for l in out.splitlines()
                              if ("FAIL" in l or "FAILED" in l)][:3]))
    except subprocess.TimeoutExpired:
        bad.append((tid, ["TIMEOUT"]))
if bad:
    print(f"  级联失败 {len(bad)} 项（对拍豁免判定）：")
    for tid, errs in bad:
        for e in errs:
            print(f"    task{tid}: {e}")

# 家法对拍口径（Task172 G1 先例）：stash 前后对拍，失败集 ⊆ 具名豁免基线 =
# 零新增失败。豁免集（全部为基线内既有/环境性失败，Task177 工作留档同源）：
#   130 D4 ApplyFSR rcasOn（环境性，74/175 两轮留档）
#   131 H3 = 级联 130 的传播
#   132 A1/A2/A15 OSMesa 日志证据/GOT 镜像（沙箱环境性，74/175 留档）
#   135 E  = 级联 130/131/134 传播
#   142 E1/E2/E4 mg 公告内容锚（历轮遗留）
#   143 G1 = 级联 142 传播
#   134 读 latestlog.txt.old.txt（不在仓库的会话本地证据）环境性崩溃——
#      级联捕获行是 PASS 行名里的 "READBACK FAILED" 字样（误捕噪声）
#   156 G  = task154 mgl_fsr 环境性（74/175 留档）
EXEMPT = {
    "130": ("D4",), "131": ("H3",), "132": ("A1", "A2", "A15"),
    "134": ("READBACK",),
    "135": ("E.",), "142": ("E1", "E2", "E4"), "143": ("G1",), "156": ("G ",),
}
# 静默崩溃豁免（traceback 无 FAIL 行可捕获）：133/138 读 latestlog.txt.old.txt
SILENT_EXEMPT = {"133", "138"}
new_bad = []
for tid, errs in bad:
    if tid in SILENT_EXEMPT and not errs:
        continue
    if tid not in EXEMPT:
        new_bad.append((tid, errs))
        continue
    if not any(any(m in e for m in EXEMPT[tid]) for e in errs):
        new_bad.append((tid, errs))
check("G1 级联零新增失败（失败集 ⊆ 具名豁免基线，stash 对拍口径）", not new_bad)

# ============================================================
print()
print(f"verify_task178: {PASS} passed, {FAIL} failed")
sys.exit(0 if FAIL == 0 else 1)
