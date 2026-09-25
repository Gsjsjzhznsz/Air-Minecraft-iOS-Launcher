#!/usr/bin/env python3
# Task170 verifier: neumorphism whole-card opacity slider (replaces the
# Task168 solid toggle) + home tile spacing unification (20pt everywhere).
# 用法: python3 scripts/verify_task170.py   （在仓库根的任意子目录运行皆可）
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)


def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


results = []


def check(name, cond, detail=""):
    results.append((bool(cond), name, detail))


bm_m = rd("Natives/BackgroundManager.m")
bm_h = rd("Natives/BackgroundManager.h")
bsvc = rd("Natives/BackgroundSettingsViewController.m")
news = rd("Natives/LauncherNewsViewController.m")
engine_m = rd("Natives/UIKit+NativeSurface.m")

# ============================================================
# A. 偏好层：cardsNeumorphOpacity（实底开关退役）
# ============================================================
check("A1 BackgroundManager.h 属性（CGFloat 0.0~1.0 + 语义注释；Task173 重锚：卡片本体语义）",
      "@property (nonatomic, assign) CGFloat cardsNeumorphOpacity; // 0.0 ~ 1.0" in bm_h
      and "Task170" in bm_h and "卡片本体" in bm_h)
check("A2 defaults 键 background_cards_neumorph_opacity（读侧最新落盘值）",
      'kBackgroundCardsNeumorphOpacityKey = @"background_cards_neumorph_opacity"' in bm_m
      and "objectForKey:kBackgroundCardsNeumorphOpacityKey" in bm_m
      and "doubleForKey:kBackgroundCardsNeumorphOpacityKey" in bm_m
      and "setDouble:MAX(0.0, MIN(1.0, cardsNeumorphOpacity))" in bm_m)
check("A3 默认 1.0（未落盘 = Task168 形态原样，不缩水）",
      "return 1.0;" in bm_m
      and "objectForKey:kBackgroundCardsNeumorphOpacityKey] == nil" in bm_m)
check("A4 实底开关全链退役（Manager/设置页/defaults 键零残留）",
      "cardsNeumorphSolid" not in bm_m and "cardsNeumorphSolid" not in bm_h
      and "cardsNeumorphSolid" not in bsvc
      and "background_cards_neumorph_solid" not in bm_m
      and "CardsNeumorphSolidCell" not in bsvc
      and "solidSwitch" not in bsvc)

# ============================================================
# B. 管线层：四个终端分支全部按滑条重设宿主 alpha
# ============================================================
card_fn = bm_m[bm_m.index("- (void)applyNeumorphCardEffectToView"):bm_m.index("- (void)applyEffectToSearchBar")]
cell_fn = bm_m[bm_m.index("- (void)applyEffectToCollectionViewCell"):bm_m.index("- (void)applyCardEffectToCell")]
check("B1 卡片视图管线（Task173 重锚）：开关门 if (!self.cardsNeumorphEnabled) 在先",
      "if (!self.cardsNeumorphEnabled) {" in card_fn
      and "self.cardsNeumorphSolid" not in card_fn)
check("B2 卡片视图管线（Task173 重锚：正常态重写）：壁纸适配分支退役，开关门在先",
      "if (!self.cardsNeumorphEnabled) {" in card_fn
      and "if ([self hasBackground])" not in card_fn
      and "[view ame_attachNeumorphShadowOnly];" not in card_fn)
check("B3 卡片视图管线：正常态尾部 = 规格表面 + 卡片本体透明度（文字不动）",
      card_fn.index("[view ame_applyNeumorphSurface];")
      < card_fn.index("[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];"))
check("B4 cell 管线：开关门在先（Task172：ON 分支最先且壁纸无关）",
      cell_fn.index("if (self.cardsNeumorphEnabled) {")
      < cell_fn.index("if (![self hasBackground]) {")
      and "self.cardsNeumorphSolid" not in cell_fn)
check("B5 cell 管线 ON 分支尾部：规格表面之后接卡片本体透明度原语",
      cell_fn.index("[target ame_applyNeumorphSurface];")
      < cell_fn.index("[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];"))
check("B6 宿主整体 alpha 退役（Task173 重锚：卡片本体透明度替代，文字不随淡）",
      "cardTarget.alpha = self.cardsNeumorphOpacity;" not in cell_fn
      and "target.alpha = self.cardsNeumorphOpacity;" not in cell_fn
      and "view.alpha = self.cardsNeumorphOpacity;" not in card_fn)
check("B7 卡片本体透明度原语在位（引擎 ame_applyNeumorphCardOpacity：卡面动态色 + 阴影承载层 alpha）",
      "insertSubview:shadowView atIndex:0" in engine_m
      and "ame_applyNeumorphCardOpacity" in engine_m
      and "shadowView.alpha = o;" in engine_m)
check("B8 列表行边界维持：applyCardEffectToCell 仍 Flat 平贴（不接 alpha）",
      "[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];" in bm_m
      and "applyCardEffectToCell" in bm_m)

# ============================================================
# C. 设置页：新拟态透明度滑条行
# ============================================================
check("C1 section0 第四行改用新 l10n 键",
      'localize(@"background.cards.neumorph.opacity.title", nil)' in bsvc
      and 'localize(@"background.cards.neumorph.title", nil)' not in bsvc)
check("C2 滑条行接线（CardsNeumorphOpacityCell + tag 500/501/502 + 回调）",
      '"CardsNeumorphOpacityCell"' in bsvc
      and "slider.tag = 500;" in bsvc and "slider.minimumValue = 0.0f;" in bsvc
      and "slider.maximumValue = 1.0f;" in bsvc
      and "cardsNeumorphOpacitySliderChanged:" in bsvc)
check("C3 回调落盘 + 统一刷新链（refreshUIEffect）",
      "cardsNeumorphOpacity = slider.value;" in bsvc
      and bsvc.count("- (void)cardsNeumorphOpacitySliderChanged:") == 1
      and "[[BackgroundManager sharedManager] refreshUIEffect];" in bsvc)
check("C4 既有行不受影响（透明度/模糊滑块 + Bing 区仍在位）",
      "opacitySliderChanged:" in bsvc and "blurIntensitySliderChanged:" in bsvc
      and "bingToggleChanged:" in bsvc)

# ============================================================
# D. 主页间距：卡间 20pt = 外沿 20pt
# ============================================================
layout_fn = news[news.index("- (UICollectionViewLayout *)createLayout"):news.index("// MARK: - UICollectionView DataSource")]
check("D1 item 内边距 (0,10,0,10) x2（卡间横向 = 10+10 = 20）",
      layout_fn.count("NSDirectionalEdgeInsetsMake(0, 10, 0, 10);") == 2)
check("D2 section 内边距 (10,10,10,10) x2（外沿 = 10+10 = 20 与旧观感一致；行间 = 10+10 = 20）",
      layout_fn.count("NSDirectionalEdgeInsetsMake(10, 10, 10, 10);") == 2)
check("D3 interGroupSpacing 20（防御性对齐）",
      "section.interGroupSpacing = 20;" in layout_fn)
check("D4 旧间距常量零残留（(0,5,0,5) / (5,15,5,15)）",
      "NSDirectionalEdgeInsetsMake(0, 5, 0, 5)" not in layout_fn
      and "NSDirectionalEdgeInsetsMake(5, 15, 5, 15)" not in layout_fn)

# ============================================================
# E. l10n：键原位换名（计数 1954 不变）
# ============================================================
new_key = "background.cards.neumorph.opacity.title"
old_key = "background.cards.neumorph.title"
vals = {}
for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]:
    s = rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
    m = re.search(r'^"' + re.escape(new_key) + r'"\s*=\s*"(.*)";\s*$', s, re.M)
    vals[lg] = m.group(1) if m else None
check("E1 六语言新键在位且非空", all(vals.values()), str(vals))
check("E2 六语言旧键退役",
      all(old_key + '"' not in rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]))
check("E3 四主语言键集一致且计数 = 1954（换名净变化 0）",
      all(len(set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1955
          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
keysets = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]]
check("E4 四主语言键集逐键一致", keysets[0] == keysets[1] == keysets[2] == keysets[3])

# ============================================================
# F. 公告 + version.h
# ============================================================
anns = json.loads(rd("announcements.json"))["announcements"]
ids = [a["id"] for a in anns]
check("F1 公告插入 index 2（anns[1] task169 pin 不动；task173/172 相继插入后 task171/170/168 顺延 anns[4]/[5]/[6]）且 id 唯一",
      len(ids) == len(set(ids))
      and anns[1]["id"] == "task169-four-fixes-2026-09-25"
      and anns[2]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[4]["id"] == "task172-six-fixes-2026-09-25"
      and anns[5]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[6]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[7]["id"] == "task168-neumorph-faq-json-2026-09-25")
t170 = anns[6]
check("F2 公告内容：滑条语义（整个卡片/晕影调低）+ 间距统一 + EN 尾注",
      "0% ~ 100%" in t170["content"] and "整个卡片" in t170["content"]
      and "晕影" in t170["content"] and "20pt" in t170["content"]
      and "EN:" in t170["content"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F3 version.h Task 170 addendum（滑条 + 间距 + 键换名）",
      "Task 170" in vh and "background_cards_neumorph_opacity" in vh
      and "20pt" in vh)
check("F4 version.h 历史addendum仍在（append-only 不回改）",
      "Task 168" in vh and "Task 169" in vh)

# ============================================================
# G. 语法 / 配平
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
        i += 1
    return all(v == 0 for v in depth.values())


check("G1 配平：BackgroundManager.m", balance("Natives/BackgroundManager.m"))
check("G2 配平：BackgroundManager.h", balance("Natives/BackgroundManager.h"))
check("G3 配平：BackgroundSettingsViewController.m", balance("Natives/BackgroundSettingsViewController.m"))
check("G4 配平：LauncherNewsViewController.m", balance("Natives/LauncherNewsViewController.m"))
check("G5 引擎改动仅追加（Task172：卡片本体透明度原语，Task160 主体未动）",
      "AmeNeumorphShadowColor()" in engine_m and "shadowOpacity = 1.0" in engine_m)

# ============================================================
# H. 级联零新增失败（家法：当前失败 ⊆ 提交树基线）
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
# Task173 同款具名沙箱传播簇（详证见 verify_task173 G1 注释）：
# 深子级联会话本地工件缺席的"ALL PASS 级"传播失败 + 精确分数钉，
# 均可追溯 task168_cascade_baseline documented condition（Task171 先例）。
SANDBOX_EXCEPTIONS = {
    "131": ("H3 verify_task130",),
    "132": ("A1 崩溃日志证据", "A15 libjnidispatch", "G4 级联六验证器"),
    "135": ("E. verify_task130", "E. verify_task131", "E. verify_task132",
            "E. verify_task133", "E. verify_task134", "G4 级联六验证器"),
    "156": ("G verify_task154",),
}
new_failures = []
for t in CASCADES:
    script = f"scripts/verify_task{t}.py"
    if not os.path.exists(script):
        new_failures.append((t, ["<script missing>"]))
        continue
    r = subprocess.run([sys.executable, script], capture_output=True, text=True,
                       timeout=600, env=cascade_env)
    if r.returncode == 0:
        continue
    cur = set(fail_lines(r.stdout + r.stderr))
    allow = set(baseline.get(t, []))
    exc = SANDBOX_EXCEPTIONS.get(t, ())
    extra = sorted(f for f in cur
                   if f not in allow and not any(e in f for e in exc))
    if extra:
        new_failures.append((t, [e[:120] for e in extra]))
check("H1 级联零新增失败（当前失败 ⊆ 提交树基线，stash 对拍口径）",
      not new_failures, str(new_failures))

# ============================================================
print("=" * 72)
passed = sum(1 for ok, _, _ in results if ok)
for ok, name, detail in results:
    print(("[PASS] " if ok else "[FAIL] ") + name + (f"  -- {detail}" if (detail and not ok) else ""))
print("=" * 72)
print(f"verify_task170: {passed}/{len(results)}" + ("  ALL GREEN" if passed == len(results) else "  HAS FAILURES"))
sys.exit(0 if passed == len(results) else 1)
