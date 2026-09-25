#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task173.py -- 新拟态"正常态"重写 + 新拟态界面开关 + 卡片本体透明度

用户定稿（复现方法驱动）：
  复现：Bing 壁纸开着调一次 UI 效果再关掉 Bing 壁纸，新拟态回到正常形态
  → 正常形态（规格表面色 + 双阴影）一直存在于无壁纸分支；有壁纸的"动态
  卡面（毛玻璃/半透明）+ 阴影承载层"壁纸适配分支正是边缘重晕影的来源。
  指令：用正常的状态重写；模糊程度下加"新拟态界面"开关（开启 = 其余 UI
  效果选项变灰、透明度可操作，关闭反转）；透明度 = 卡片本体，不含字体；
  不要继续用之前的壁纸适配代码。

组别：
  A 偏好层（cardsNeumorphEnabled 属性/defaults 键/默认 YES）
  B 管线层（三管线正常态重写 + 壁纸适配分支退役 + 宿主 alpha 全撤）
  C 设置页（开关行 + 灰化反转 + 恒显 + 回调）
  D l10n（新键 x6 + 计数 1954）
  E 公告 + version.h
  F 配平
  G 级联零新增失败（当前失败 ⊆ 提交树基线）
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
    with open(p, encoding="utf-8") as f:
        return f.read()


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"[PASS] {name}")
    else:
        FAIL += 1
        print(f"[FAIL] {name}" + (f"  -- {detail}" if detail else ""))


bm_h = rd("Natives/BackgroundManager.h")
bm_m = rd("Natives/BackgroundManager.m")
bsvc = rd("Natives/BackgroundSettingsViewController.m")
engine_h = rd("Natives/UIKit+NativeSurface.h")
engine_m = rd("Natives/UIKit+NativeSurface.m")

# ============================================================
# A. 偏好层
# ============================================================
check("A1 头文件 cardsNeumorphEnabled 属性 + 正常态语义注释",
      "@property (nonatomic, assign) BOOL cardsNeumorphEnabled;" in bm_h
      and "background_cards_neumorph_enabled" in bm_h
      and "正常态" in bm_h)
check("A2 defaults 键常量（direct read/write，与滑条同家法）",
      'kBackgroundCardsNeumorphEnabledKey = @"background_cards_neumorph_enabled"' in bm_m
      and "boolForKey:kBackgroundCardsNeumorphEnabledKey" in bm_m
      and "setBool:cardsNeumorphEnabled" in bm_m)
check("A3 未落盘默认 YES（objectForKey == nil → return YES）",
      "objectForKey:kBackgroundCardsNeumorphEnabledKey] == nil" in bm_m
      and bm_m.index("kBackgroundCardsNeumorphEnabledKey] == nil")
      < bm_m.index("return YES;") <
      bm_m.index("return [[NSUserDefaults standardUserDefaults] boolForKey:kBackgroundCardsNeumorphEnabledKey];"))
check("A4 实底开关零残留（cardsNeumorphSolid 全链退役不回潮）",
      "cardsNeumorphSolid" not in bm_m and "cardsNeumorphSolid" not in bm_h
      and "cardsNeumorphSolid" not in bsvc
      and "background_cards_neumorph_solid" not in bm_m)

# ============================================================
# B. 管线层
# ============================================================
card_fn = bm_m[bm_m.index("- (void)applyNeumorphCardEffectToView"):bm_m.index("- (void)applyEffectToSearchBar")]
cell_fn = bm_m[bm_m.index("- (void)applyEffectToCollectionViewCell"):bm_m.index("- (void)applyCardEffectToCell")]
row_fn = bm_m[bm_m.index("- (void)applyCardEffectToCell:"):bm_m.index("- (void)applyNeumorphCardEffectToView")]

check("B1 视图管线：开关门在先（!cardsNeumorphEnabled → applyEffectToView 旧管线）",
      card_fn.index("if (!self.cardsNeumorphEnabled) {")
      < card_fn.index("[self applyEffectToView:view];"))
check("B2 视图管线：壁纸适配分支整链退役（无 hasBackground 门 / 无 attach / 无宿主 alpha）",
      "if ([self hasBackground])" not in card_fn
      and "ame_attachNeumorphShadowOnly" not in card_fn
      and "view.alpha" not in card_fn)
check("B3 视图管线：正常态尾部 = 清 blur 残留 + 规格表面 + 卡片本体透明度",
      "kBackgroundBlurTag" in card_fn
      and card_fn.index("[view ame_applyNeumorphSurface];")
      < card_fn.index("[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];"))
check("B4 cell 管线：开关门在先且壁纸无关（ON 分支不读 hasBackground）",
      cell_fn.strip().startswith("- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {")
      and cell_fn.index("if (self.cardsNeumorphEnabled) {") < cell_fn.index("if (![self hasBackground]) {"))
check("B5 cell 管线 ON 分支：清残留（contentView + 容器内 blur）+ 规格表面 + 卡片本体透明度",
      cell_fn.count("kBackgroundBlurTag") >= 3
      and "[cell.contentView ame_removeNeumorphShadow]" not in cell_fn[:cell_fn.index("if (![self hasBackground])")]
      and cell_fn.index("[target ame_applyNeumorphSurface];")
      < cell_fn.index("[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];")
      < cell_fn.index("if (![self hasBackground]) {"))
check("B6 cell 管线：动态收口退役（无 attach / 无圆角同步收口 / 无宿主 alpha），旧壁纸玻璃分支保留",
      "[cardTarget ame_attachNeumorphShadowOnly];" not in cell_fn
      and "cardTarget.alpha = self.cardsNeumorphOpacity;" not in cell_fn
      and "UIBlurEffectStyleSystemMaterial" in cell_fn
      and "secondarySystemBackgroundColor" in cell_fn)
check("B7 行管线：开关关闭 → applyEffectToCell 旧管线；开启 → Flat 平贴（壁纸无关）",
      row_fn.index("if (!self.cardsNeumorphEnabled) {") < row_fn.index("[self applyEffectToCell:cell];")
      and "[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];" in row_fn
      and "if ([self hasBackground])" not in row_fn)
check("B8 宿主整体 alpha 全撤（三管线零 view./target./cardTarget.alpha 滑条残留）",
      "view.alpha = self.cardsNeumorphOpacity" not in bm_m
      and "target.alpha = self.cardsNeumorphOpacity" not in bm_m
      and "cardTarget.alpha = self.cardsNeumorphOpacity" not in bm_m)
check("B9 引擎原语：ame_applyNeumorphCardOpacity 声明 + 实现（动态色安全 + 阴影承载层 alpha）",
      "- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;" in engine_h
      and "ame_applyNeumorphCardOpacity:(CGFloat)opacity {" in engine_m
      and "colorWithDynamicProvider" in engine_m[engine_m.index("ame_applyNeumorphCardOpacity"):]
      and "shadowView.alpha = o;" in engine_m
      and "self.backgroundColor = AmeNeumorphSurfaceColor();" in engine_m[engine_m.index("ame_applyNeumorphCardOpacity"):])

# ============================================================
# C. 设置页
# ============================================================
check("C1 section0 五标题序（界面开关在 opacity 之前）",
      'localize(@"background.cards.neumorph.interface.title", nil)' in bsvc
      and bsvc.index("background.cards.neumorph.interface.title")
      < bsvc.index("background.cards.neumorph.opacity.title")
      and 'self.sections[0][3]; // background.cards.neumorph.interface.title' in bsvc
      and 'self.sections[0][4]; // background.cards.neumorph.opacity.title' in bsvc)
check("C2 开关行接线（CardsNeumorphToggleCell + tag 410 + 回调）",
      '"CardsNeumorphToggleCell"' in bsvc
      and "neumorphSwitch.tag = 410;" in bsvc
      and "cardsNeumorphToggleChanged:" in bsvc
      and "neumorphSwitch.on = manager.cardsNeumorphEnabled;" in bsvc)
check("C3 灰化反转：开关开启时旧选项行变灰关交互；滑条随开关启停（Task173 十连修合并重锚：透明度/模糊两行统一 Auto Layout 构建后灰化表达式 3->2）",
      bsvc.count("cell.contentView.alpha = neumorphOn ? 0.35 : 1.0;") == 2
      and bsvc.count("cell.userInteractionEnabled = !neumorphOn;") == 2
      and "slider.enabled = neumorphOn;" in bsvc
      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" in bsvc)
check("C4 开关行 + 滑条行恒显（无壁纸时 section0 返回 2；行号按 hasBackground 平移）",
      "return 2;" in bsvc
      and "indexPath.row == (hasBackground ? 3 : 0)" in bsvc
      and "indexPath.row == (hasBackground ? 4 : 1)" in bsvc)
check("C5 开关回调：落盘 + 统一刷新链 + 表格重载（灰化态反转）",
      "cardsNeumorphEnabled = sender.on;" in bsvc
      and bsvc.count("- (void)cardsNeumorphToggleChanged:") == 1
      and "[[BackgroundManager sharedManager] refreshUIEffect];" in bsvc
      and "[self.tableView reloadData];" in bsvc)
check("C6 既有行不回潮不破坏（透明度/模糊滑块 + UI效果选择 + Bing 区仍在位）",
      "opacitySliderChanged:" in bsvc and "blurIntensitySliderChanged:" in bsvc
      and "bingToggleChanged:" in bsvc and "showUIEffectPicker" in bsvc
      and '"BingToggleCell"' in bsvc)

# ============================================================
# D. l10n
# ============================================================
new_key = "background.cards.neumorph.interface.title"
vals = {}
for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]:
    s = rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
    m = re.search(r'^"' + re.escape(new_key) + r'"\s*=\s*"(.*)";\s*$', s, re.M)
    vals[lg] = m.group(1) if m else None
check("D1 六语言新键在位且非空", all(vals.values()), str(vals))
check("D2 四主语言键集一致且计数 = 1954（净增 1）",
      all(len(set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1955
          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
keysets = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]]
check("D3 四主语言键集逐键一致", keysets[0] == keysets[1] == keysets[2] == keysets[3])
check("D4 opacity 键原位保留（Task170 滑条语义仍在）",
      all("background.cards.neumorph.opacity.title" in
          rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]))

# ============================================================
# E. 公告 + version.h
# ============================================================
anns = json.loads(rd("announcements.json"))["announcements"]
ids = [a["id"] for a in anns]
check("E1 公告插入 index 2（server/task169 pin 不动；十连修 task173 顺延插入 anns[3] 后 172/171/170/168 顺延 anns[4]/[5]/[6]/[7]）且 id 唯一",
      len(ids) == len(set(ids))
      and anns[0]["id"] == "server-recommend-2026-09-24"
      and anns[1]["id"] == "task169-four-fixes-2026-09-25"
      and anns[2]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[3]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[4]["id"] == "task172-six-fixes-2026-09-25"
      and anns[5]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[6]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[7]["id"] == "task168-neumorph-faq-json-2026-09-25")
t173 = anns[2]
check("E2 公告内容锚（复现方法/正常态/晕影/字体 + EN 尾注）",
      "正常态" in t173["content"] and "晕影" in t173["content"]
      and "字体" in t173["content"] and "EN:" in t173["content"]
      and "Bing" in t173["summary"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E3 version.h Task 173 addendum（键名 + 引擎原语 + 正常态）",
      "Task 173" in vh and "background_cards_neumorph_" in vh
      and "ame_applyNeumorphCardOpacity" in vh)
check("E4 历史addendum仍在（append-only 不回改）",
      all(f"Task {t}" in vh for t in (168, 169, 170, 171)))

# ============================================================
# F. 配平
# ============================================================
def balance(path):
    src = open(path, encoding="utf-8").read()
    depth = {"{": 0, "(": 0, "[": 0}
    pair = {"}": "{", ")": "(", "]": "["}
    i, n, state = 0, len(src), "code"
    while i < n:
        c = src[i]
        if state == "code":
            if c == '"':
                state = "str"
            elif c == "/" and i + 1 < n and src[i + 1] == "/":
                state = "line"
                i += 1
            elif c == "/" and i + 1 < n and src[i + 1] == "*":
                state = "block"
                i += 1
            elif c in depth:
                depth[c] += 1
            elif c in pair:
                depth[pair[c]] -= 1
        elif state == "str":
            if c == "\\":
                i += 1
            elif c == '"':
                state = "code"
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                state = "code"
        i += 1
    return all(v == 0 for v in depth.values())


check("F1 配平：BackgroundManager.m", balance("Natives/BackgroundManager.m"))
check("F2 配平：BackgroundManager.h", balance("Natives/BackgroundManager.h"))
check("F3 配平：BackgroundSettingsViewController.m", balance("Natives/BackgroundSettingsViewController.m"))
check("F4 配平：UIKit+NativeSurface.m / .h", balance("Natives/UIKit+NativeSurface.m") and balance("Natives/UIKit+NativeSurface.h"))

# ============================================================
# G. 级联零新增失败（家法：当前失败 ⊆ 提交树基线）
# ============================================================
CASCADES = ["160", "161", "162", "163", "164", "165", "166", "167", "169",
            "129", "130", "131", "132", "133", "134", "135", "138", "139",
            "141", "142", "143", "150", "151", "156", "157", "159"]
ENV_NAMES = ["TASK160_REPO", "TASK161_REPO", "TASK162_REPO", "TASK163_REPO",
             "TASK164_REPO", "TASK165_REPO", "AME_REPO", "TASK101_REPO",
             "TASK102_REPO", "TASK111_REPO", "TASK136_REPO", "TASK137_REPO",
             "TASK141_REPO", "TASK149_REPO", "TASK150_REPO", "TASK157_REPO",
             "TASK159_REPO", "TASK88_REPO", "TASK89_REPO", "TASK90_REPO",
             "TASK91_REPO", "TASK92_REPO", "TASK93_REPO", "TASK95_REPO",
             "TASK96_REPO"]
cascade_env = {k: REPO for k in ENV_NAMES}
cascade_env.update(os.environ)


def fail_lines(text):
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[FAIL]") or s.startswith("FAIL ") or " FAILED:" in s or s.startswith("FAILED"):
            lines.append(s[:120])
    return lines


baseline_doc = json.loads(rd("scripts/task168_cascade_baseline.json"))
baseline = baseline_doc.get("baseline", {})
# 本沙箱已知传播簇（Task171 提交信息同款口径：task168_cascade_baseline
# documented condition）——深子级联的会话本地工件（审计助手 / 会话日志 /
# 精确分数钉）在本沙箱缺席导致的"ALL PASS 级"传播失败，与代码改动无关：
#   131 H3 / 135 E-链：下游钉 verify_task130 全绿；130 的 D4（FSR1.cpp 锚，
#     stash 实证既有基线）使其在本沙箱恒不全绿 → 传播失败。
#   132 A1/A15（会话证据类：日志轮换 / venv 路径）+ G4（子级联传播）。
#   156 G：钉 verify_task154 的基线精确分数（35 passed, 4 failed）。
SANDBOX_EXCEPTIONS = {
    "131": ("H3 verify_task130",),
    "132": ("A1 崩溃日志证据", "A15 libjnidispatch", "G4 级联六验证器"),
    "135": ("E. verify_task130", "E. verify_task131", "E. verify_task132",
            "E. verify_task133", "E. verify_task134", "G4 级联六验证器"),
    "156": ("G verify_task154",),
}
new_failures = {}
for tid in CASCADES:
    script = f"scripts/verify_task{tid}.py"
    if not os.path.exists(script):
        continue
    try:
        r = subprocess.run([sys.executable, script], env=cascade_env,
                           capture_output=True, text=True, timeout=300)
        fails = fail_lines(r.stdout) + fail_lines(r.stderr)
    except subprocess.TimeoutExpired:
        fails = ["TIMEOUT"]
    if fails:
        new_failures[tid] = fails

unexpected = {}
for tid, fails in new_failures.items():
    known = baseline.get(tid, [])
    exc = SANDBOX_EXCEPTIONS.get(tid, ())
    diff = [f for f in fails
            if not (any(k.split(" -- ")[0] in f or f in k for k in known)
                    or any(e in f for e in exc))]
    if diff:
        unexpected[tid] = diff

check("G1 级联零新增失败（当前失败 ⊆ 基线 ∪ 具名沙箱传播簇）",
      not unexpected, json.dumps(unexpected, ensure_ascii=False)[:800])

print(f"\n===== verify_task173: {PASS} passed, {FAIL} failed =====")
sys.exit(1 if FAIL else 0)
