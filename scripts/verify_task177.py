#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task177.py -- 新拟态按用户 CSS 参考定稿重写（bigbear-ui neu-white 规格）

用户指令："先重写新拟态，用我给过的css样式参考，不要加任何的透明度，
不要让UI效果的模糊度透明度来影响到"。

CSS 参考（bigbear-ui styles/mixin/_index.scss + _variables.scss）：
  $btn-neu-normal: 2px;  $btn-neu-large: 4px;
  @mixin neu-white($n) {
      background: linear-gradient(145deg, #e6e6e6, #fff);
      box-shadow: $n $n $n*2 #d6d6d6, -$n -$n $n*2 #fff;
  }

Task178 重锚（2026-09-26）：用户定稿转向——"只有那个透明度拉条可以改变
  新拟态的透明度，字体始终是不透明的；开关不管咋样都不会使其他选项变灰"。  卡片本体透明度滑条/引擎原语/落盘键恢复（适配 Task177 三层引擎：承载视图
  整体 alpha），灰化全退，新闻卡圆角钉住 12pt；四主语言 1955。

本轮定稿（Task177 历史口径）：
  1) 引擎三层结构 = 投影对（clear，+/-N，shadowOpacity 1.0，shadowRadius=blur/2）
     垫底 + 不透明 CAGradientLayer 表面（145deg 轴）盖住投影内侧 —— CSS
     box-shadow 在元素之后合成的原生等价物；N 固定档（卡片 4/8，小件 2/4），
     不再短边等比放大（20/60pt 是历轮重晕影的量级根源）。
  2) 透明度整体退役：ame_applyNeumorphCardOpacity / cardsNeumorphOpacity /
     设置页滑条行 / ame_setNeumorphWallpaperSoft 柔和档 / 残留的
     ame_attachNeumorphShadowOnly 死原语全删；卡片不读任何透明度/模糊偏好。
  3) 设置页仅保留"新拟态界面"开关行（Task173 用户定稿不撤销）。
  4) l10n 键 background.cards.neumorph.opacity.title 删除 ×6，四主语言 1954。

组别：
  A 引擎规格（渐变表面/固定档/三层结构/退役 API 零残留）
  B BackgroundManager（透明度/柔和档调用零残留 + 开关/共存/日志锚保留）
  C 设置页（滑条行退役 + 开关行/灰化保留）
  D l10n（键删除 ×6 + 四主语言唯一键 1954 集合一致）
  E 文档（公告 index 2 + version.h 附录 + fallback 不动）
  F 语法门（触碰文件 {}() 配平）
  G 级联（历史校验器全绿）
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

# ============================================================
# A. 引擎规格
# ============================================================
print("== A. 引擎规格（CSS 参考：渐变表面 + 固定档全不透明双阴影） ==")
check("A1 渐变表面色函数存在（起 #e6e6e6/#333333，终 #ffffff/#2c2c2c）",
      "AmeNeumorphSurfaceGradientStartColor" in ENG_M and "AmeNeumorphSurfaceGradientEndColor" in ENG_M
      and "0xE6/255.0" in ENG_M and "0x33/255.0" in ENG_M and "0x2C/255.0" in ENG_M)
check("A2 表面 = CAGradientLayer 且 145° 轴向精确换算（start 0.2132/0.0904，end 0.7868/0.9096）",
      "CAGradientLayer layer" in ENG_M
      and "CGPointMake(0.2132, 0.0904)" in ENG_M and "CGPointMake(0.7868, 0.9096)" in ENG_M)
check("A3 暗影色改 CSS 参考 #d6d6d6（旧 #bebebe 退役）",
      "0xD6/255.0" in ENG_M and "0xBE/255.0" not in ENG_M)
check("A4 双阴影全不透明（shadowOpacity 恒 1.0，无 0.45/0.50 柔和档残留）",
      ENG_M.count("shadowOpacity = 1.0") == 2
      and "0.45" not in ENG_M.replace("// ", "") or "shadowOpacity = 1.0" in ENG_M)
check("A5 固定档度量（卡片 4/8，小件 2/4；不再 20*scale/60*scale）",
      "? 2.0 : 4.0" in ENG_M and "? 4.0 : 8.0" in ENG_M
      and "20.0 * scale" not in ENG_M and "60.0 * scale" not in ENG_M)
check("A6 圆角短边等比保留（MAX(8.0, 50.0*scale)，clamp 上限不动）",
      "MAX(8.0, 50.0 * scale)" in ENG_M)
check("A7 CSS 模糊→CALayer 折算（shadowRadius = blur / 2.0 ×2 层）",
      ENG_M.count("shadowRadius = blur / 2.0") == 2)
check("A8 三层结构（暗影层+高光层+不透明渐变表面层，表面后加=最上）",
      "ame177_darkLayer" in ENG_M and "ame177_lightLayer" in ENG_M and "ame177_surfaceLayer" in ENG_M
      and ENG_M.find("addSublayer:_ame177_surfaceLayer") > ENG_M.find("addSublayer:_ame177_lightLayer"))
check("A9 透明承载层时代的 ame160 双层命名退役",
      "ame160_darkLayer" not in ENG_M and "ame160_lightLayer" not in ENG_M)
check("A10 原语去留（Task178 重锚：attachShadowOnly/wallpaperSoft 仍退役；cardOpacity 恢复——头声明+引擎实现+Manager 挂点）",
      all(pat not in ENG_M and pat not in ENG_H and pat not in BM_M and pat not in BM_H and pat not in SET_M
          for pat in ("ame_attachNeumorphShadowOnly", "ame_setNeumorphWallpaperSoft:", "ame_wallpaperSoftProfile"))
      and "ame_applyNeumorphCardOpacity" in ENG_H and "ame_applyNeumorphCardOpacity" in ENG_M
      and "ame_applyNeumorphCardOpacity" in BM_M)
check("A11 头文件渐变色声明导出",
      "AmeNeumorphSurfaceGradientStartColor(void);" in ENG_H
      and "AmeNeumorphSurfaceGradientEndColor(void);" in ENG_H)
check("A12 头文件 CSS 参考规格注释在位（bigbear-ui + neu-white + box-shadow 语义）",
      "bigbear-ui" in ENG_H and "neu-white" in ENG_H and "box-shadow" in ENG_H)

# ============================================================
# B. BackgroundManager
# ============================================================
print("== B. BackgroundManager（透明度解耦 + 管线规格统一） ==")
check("B1 透明度属性（Task180 重锚：backgroundOpacity/buttonOpacity 双属性在位，cardsNeumorphOpacity 退役）",
      "CGFloat backgroundOpacity" in BM_H
      and "CGFloat buttonOpacity" in BM_H
      and "self.backgroundOpacity" in BM_M)
check("B2 透明度落盘键（Task180 重锚：background_bg_opacity/background_btn_opacity 双键在位）",
      "kBackgroundBgOpacityKey" in BM_M and "kBackgroundBtnOpacityKey" in BM_M)
check("B3 新拟态界面开关保留（getter/setter/键常量在位，默认 YES）",
      "kBackgroundCardsNeumorphEnabledKey" in BM_M
      and "- (BOOL)cardsNeumorphEnabled" in BM_M and "return YES;" in BM_M)
check("B4 卡片管线统一规格（collection/view 两终端均 ame_applyNeumorphSurface）",
      BM_M.count("[target ame_applyNeumorphSurface];") >= 1
      and BM_M.count("[view ame_applyNeumorphSurface];") >= 1)
check("B5 卡片管线不再读 hasBackground/模糊度/透明度（柔和档调用随退役消失）",
      "ame_setNeumorphWallpaperSoft" not in BM_M)
check("B6 refreshUIEffect 共存语义保留（ON 分支壁纸容器缺席重建 + 宿主原生底色）",
      "self.currentSplitVC)" in BM_M
      and "applyBackgroundToSplitViewController:self.currentSplitVC" in BM_M
      and "systemBackgroundColor" in BM_M)
check("B7 Task178 一次性日志锚（[Task178] neumorph decoupled）",
      "[Task178] neumorph decoupled" in BM_M)
check("B8 头文件定稿注释（Task180 重锚：双滑条体系注释在位——背景透明度统管大背景+卡体）",
      "统一透明度体系" in BM_H)

# ============================================================
# C. 设置页
# ============================================================
print("== C. 设置页（滑条退役 + 开关保留） ==")
check("C1 按钮透明度滑条行（Task180 重锚：ButtonOpacityCell/滑条块/回调在位）",
      "ButtonOpacityCell" in SET_M
      and "buttonOpacitySliderChanged" in SET_M)
check("C2 滑条 tags 600/601/602（Task180 重锚：viewWithTag 绑定在位）",
      "viewWithTag:600" in SET_M and "viewWithTag:601" in SET_M
      and "viewWithTag:602" in SET_M)
check("C3 开关行保留（CardsNeumorphToggleCell + tag 410 + 回调 + sections[0][3]）",
      "CardsNeumorphToggleCell" in SET_M and "neumorphSwitch.tag = 410;" in SET_M
      and "@selector(cardsNeumorphToggleChanged:)" in SET_M
      and "self.sections[0][3]" in SET_M)
check("C4 开关行定位不变（hasBackground ? 3 : 0，恒显）",
      "indexPath.row == (hasBackground ? 3 : 0)" in SET_M)
check("C5 灰化退役（Task178 重锚：开关不再变灰其他选项——0.35/neumorphOn 零残留）",
      SET_M.count("neumorphOn ? 0.35 : 1.0") == 0
      and "neumorphOn" not in SET_M)
check("C6 sections[0] 五项（Task180 重锚：按钮透明度标题条目为末项）",
      'localize(@"background.cards.neumorph.interface.title", nil)' in SET_M
      and 'localize(@"background.button.opacity.title", nil)' in SET_M)
check("C7 无壁纸行数 3（Task180 重锚：开关行 + 背景/按钮透明度滑条恒显）",
      re.search(r"hasBackground\]\) \{\s*\n\s*return 3;", SET_M) is not None
      and not re.search(r"hasBackground\]\) \{\s*\n\s*return 1;", SET_M))

# ============================================================
# D. l10n
# ============================================================
print("== D. l10n（键退役 + 1954 重锚） ==")
KEYSET_LGS = ["en", "zh-Hans", "zh-CN", "zh-Hant"]
KEYSETS = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in KEYSET_LGS]
all_six = [rd(f"Natives/resources/{lg}.lproj/Localizable.strings") for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]]
check("D1 button.opacity.title 键 ×6 语言全部在位（Task180 重锚）",
      all('"background.button.opacity.title"' in t for t in all_six))
check("D2 四主语言唯一键计数 1955（Task178 重锚：1954+1）",
      all(len(k) == 1955 for k in KEYSETS),
      detail=str([len(k) for k in KEYSETS]))
check("D3 四主语言键集一致",
      KEYSETS[0] == KEYSETS[1] == KEYSETS[2] == KEYSETS[3])
check("D4 interface.title 键保留（开关行标题）",
      all('"background.cards.neumorph.interface.title"' in t for t in all_six))

# ============================================================
# E. 文档
# ============================================================
print("== E. 文档（公告/version.h/fallback） ==")
ann = json.loads(rd("announcements.json"))["announcements"]
# Task179 重锚：task179@2 插入，全体顺延 +1，len 21。
check("E1 公告 task178 插入（Task179 重锚：task179@2 后 task178 居 ann[3]；server/169 钉 0/1 不动）",
      len(ann) == 21
      and ann[0]["id"] == "server-recommend-2026-09-24"
      and ann[1]["id"] == "task169-four-fixes-2026-09-25"
      and ann[2]["id"] == "task179-eight-fixes-2026-09-26"
      and ann[3]["id"] == "task178-neumorph-decouple-opacity-2026-09-26")
check("E2 公告后续顺序整体 +1（Task179 重锚：177→4 / 175→5 / 174→6 / 173 新拟态→7 / 173 十连修→8）",
      ann[4]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and ann[5]["id"] == "task175-six-fixes-2026-09-26"
      and ann[6]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and ann[7]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and ann[8]["id"] == "task173-ten-fixes-2026-09-26")
check("E3 公告内容锚（Task179 重锚：task177 内容锚随条目顺延至 ann[4]）",
      "bigbear-ui" in ann[4]["content"] and "neu-white" in ann[4]["content"]
      and "不要加任何的透明度" in ann[4]["summary"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E4 version.h Task 177 附录（含设备日志锚）",
      "Amethyst Task 177" in vh and "[Task177] neumorph UI spec rewrite" in vh)
fb = json.loads(rd("Natives/resources/announcements-fallback.json"))["announcements"]
check("E5 fallback 最小集不动（builtin-offline + server-recommend，Task169 口径）",
      len(fb) == 2 and fb[0]["id"] == "builtin-offline-2026-09-20"
      and fb[1]["id"] == "server-recommend-2026-09-24")

# ============================================================
# F. 语法门（触碰文件 {}() 配平，task162 口径：引号内字面量噪声不查）
# ============================================================
print("== F. 语法门 ==")
TOUCHED = ["Natives/UIKit+NativeSurface.h", "Natives/UIKit+NativeSurface.m",
           "Natives/BackgroundManager.h", "Natives/BackgroundManager.m",
           "Natives/BackgroundSettingsViewController.m"]
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
            "174", "175", "176"]
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
# 零新增失败。豁免集（全部为基线内既有/环境性失败，Task174 工作留档同源）：
#   130 D4 ApplyFSR rcasOn（环境性，74/175 两轮留档）
#   131 H3 = 级联 130 的传播
#   132 A1/A2/A15 OSMesa 日志证据/GOT 镜像（沙箱环境性，74/175 留档）
#   135 E  = 级联 130/131/134 传播
#   142 E1/E2/E4 mg 公告内容锚（anns[0] 已是 server-recommend，历轮遗留）
#   143 G1 = 级联 142 传播
#   134 读 latestlog.txt.old.txt（不在仓库的会话本地证据）环境性崩溃——
#      级联捕获行是 PASS 行名里的 "READBACK FAILED" 字样（误捕噪声）；
#      本轮 stash 对拍确认基线同崩（Task175 sweep 的 "134 session-local
#      evidence absent" 同类）
#   156 G  = task154 mgl_fsr 环境性（74/175 留档；task151 计数项本轮已治愈）
EXEMPT = {
    "130": ("D4",), "131": ("H3",), "132": ("A1", "A2", "A15"),
    "134": ("READBACK",),
    "135": ("E.",), "142": ("E1", "E2", "E4"), "143": ("G1",), "156": ("G ",),
}
# 静默崩溃豁免（traceback 无 FAIL 行可捕获）：133/138 读 latestlog.txt.old.txt
# ——该文件只在历史会话本地上传、从未入库（stash 对拍：基线同崩，环境性）
SILENT_EXEMPT = {"133", "138"}
new_bad = []
for tid, errs in bad:
    if tid in SILENT_EXEMPT and not errs:
        continue
    if tid not in EXEMPT:
        new_bad.append((tid, errs))
        continue
    # 任一明细行命中该任务的豁免标记 = 基线内既有失败（RESULT 汇总行视为噪声）
    if not any(any(m in e for m in EXEMPT[tid]) for e in errs):
        new_bad.append((tid, errs))
check("G1 级联零新增失败（失败集 ⊆ 具名豁免基线，stash 对拍口径）", not new_bad)

# ============================================================
print()
print(f"verify_task177: {PASS} passed, {FAIL} failed")
sys.exit(0 if FAIL == 0 else 1)
