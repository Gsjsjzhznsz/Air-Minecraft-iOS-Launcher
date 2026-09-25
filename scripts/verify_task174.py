#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task174.py -- 新拟态画布接管（晕影根修）+ 透明度百分比实时回显

用户装机反馈（Task173 构建）：
  "现在是怎么都无法复现正常的新拟态了，全都是晕影的"
  "新拟态透明度的百分比没有正确显示"

根因定稿：
  1) Task173 只把卡片重写为"正常态"，壁纸层仍垫在卡片底下——规格双阴影
     （20pt 偏移 / 60pt 模糊 / opacity 1.0）投在照片上必然读作边缘晕影；
     复现方法（Bing 开→调→关）的终态是壁纸被取消后的整体形态，背景本身
     就是"正常态"的一部分。
  2) cardsNeumorphOpacitySliderChanged 从 Task170 起从不更新数值标签——
     拖动全程冻结在上一次 cellForRow 的读数。

组别：
  A 画布接管（applyBackgroundToWindow/SplitVC 顶部开关门 + refreshUIEffect
    双分支 + 一次性取证日志）
  B 百分比实时回显（slider→contentView→cell→tag501）
  C 既有语义不回潮（开关门/灰化反转/卡片管线/回调链）
  D l10n 零新增（四主语言计数 1955 = 十症状并行会话并入后 1954->1955）
  E 公告 + version.h
  F 配平
  G 级联零新增失败（当前失败 ⊆ 基线 ∪ 具名沙箱传播簇）
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


bm_m = rd("Natives/BackgroundManager.m")
bsvc = rd("Natives/BackgroundSettingsViewController.m")

# ============================================================
# A. 画布接管（晕影根修：开关开启 = 壁纸层整层退出）
# ============================================================
check("A1 applyBackgroundToWindow 顶部开关门（cardsNeumorphEnabled → 原生底色 + return，壁纸容器不铺）",
      "if (self.cardsNeumorphEnabled) {" in bm_m
      and "window.backgroundColor = [UIColor systemBackgroundColor];" in bm_m
      and bm_m.index("Task174：新拟态界面开关 = 全局画布接管") < bm_m.index("// Task111：检测并切换")
      and "画布接管门" in bm_m)
check("A2 applyBackgroundToSplitViewController 同款门（splitVC.view 原生底色 + return）",
      bm_m.count("if (self.cardsNeumorphEnabled) {") >= 2
      and "splitVC.view.backgroundColor = [UIColor systemBackgroundColor];" in bm_m
      and bm_m.index("splitVC.view.backgroundColor = [UIColor systemBackgroundColor];")
      < bm_m.index("if ([self hasBackground]) {", bm_m.index("- (void)applyBackgroundToSplitViewController")))
check("A3 refreshUIEffect ON 分支：壁纸容器收起 + 双宿主底色原生 + 一次性取证日志",
      "if (self.cardsNeumorphEnabled) {" in bm_m[bm_m.index("- (void)refreshUIEffect"):]
      and "[self removeGlobalBackground];" in bm_m[bm_m.index("- (void)refreshUIEffect"):]
      and "ame174CanvasLogOnce" in bm_m
      and "[Task174] neumorph UI canvas active" in bm_m)
check("A4 refreshUIEffect OFF 分支：被收起的壁纸容器原位重建（hasBackground && !container）",
      "if ([self hasBackground] && !self.globalBackgroundContainer) {" in bm_m
      and "[self applyBackgroundToSplitViewController:self.currentSplitVC];" in bm_m
      and "[self applyBackgroundToWindow:self.currentWindow];" in bm_m)
check("A5 壁纸状态保留（gate 块仅赋底色+return，零清除/零重建调用——Bing 落盘照旧，关闭即回归）",
      "clearBackground" not in bm_m[bm_m.index("if (self.cardsNeumorphEnabled) {"):
                                    bm_m.index("// Task111：检测并切换")]
      and "applyImageBackground" not in bm_m[bm_m.index("if (self.cardsNeumorphEnabled) {"):
                                             bm_m.index("// Task111：检测并切换")])
check("A5b 门内零副作用（两处门体均为 赋底色+return 两行，无 blur/透明化调用）",
      all("addBlurEffectToContainer" not in seg and "makeSplitViewControllerTransparent" not in seg
          for seg in [bm_m[bm_m.index("if (self.cardsNeumorphEnabled) {"):bm_m.index("// Task111：检测并切换")],
                      bm_m[bm_m.rindex("if (self.cardsNeumorphEnabled) {", 0, bm_m.index("// Task111：同 applyBackgroundToWindow")):bm_m.index("// Task111：同 applyBackgroundToWindow")]]))

# ============================================================
# B. 百分比实时回显
# ============================================================
handler = bsvc[bsvc.index("- (void)cardsNeumorphOpacitySliderChanged"):]
handler = handler[:handler.index("\n}", 1) + 2]
check("B1 回调含标签实时重写（viewWithTag:501）",
      "viewWithTag:501" in handler)
check("B2 回调含百分比格式（%.0f%% × 100）",
      '@"%.0f%%", slider.value * 100' in handler)
check("B3 blur 滑条同款取回范式（slider→superview→superview + 类型守卫）",
      "slider.superview.superview" in handler
      and "[cell isKindOfClass:[UITableViewCell class]]" in handler)
check("B4 既有刷新链不破坏（落盘 + refreshUIEffect 仍在）",
      ".cardsNeumorphOpacity = slider.value;" in handler
      and "refreshUIEffect" in handler)

# ============================================================
# C. 既有语义不回潮（Task173 重写与灰化反转原样保留）
# ============================================================
check("C1 卡片管线开关门仍在（applyNeumorphCardEffectToView / applyEffectToCollectionViewCell / applyCardEffectToCell）",
      bm_m.count("self.cardsNeumorphEnabled") >= 6
      and "- (void)applyNeumorphCardEffectToView:" in bm_m
      and "- (void)applyEffectToCollectionViewCell:" in bm_m
      and "- (void)applyCardEffectToCell:" in bm_m)
check("C2 灰化反转逻辑在位（旧选项 0.35 关交互：picker 行 + 透明度/模糊共享滑块块两处覆盖三行 + 滑条随开关启停）",
      bsvc.count("neumorphOn ? 0.35 : 1.0") == 2
      and "slider.enabled = neumorphOn;" in bsvc
      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" in bsvc)
check("C3 开关回调链不回潮（落盘 + refreshUIEffect + reloadData）",
      "cardsNeumorphToggleChanged:" in bsvc
      and bsvc.index("- (void)cardsNeumorphToggleChanged:") < bsvc.index("refreshUIEffect", bsvc.index("- (void)cardsNeumorphToggleChanged:"))
      and "reloadData" in bsvc[bsvc.index("- (void)cardsNeumorphToggleChanged:"):bsvc.index("- (void)cardsNeumorphToggleChanged:") + 400])
check("C4 卡片本体透明度原语仍在（ame_applyNeumorphCardOpacity 三管线挂载）",
      bm_m.count("ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity") == 2
      and "ame_applyNeumorphCardOpacity" in rd("Natives/UIKit+NativeSurface.m"))

# ============================================================
# D. l10n 零新增（本轮无新键，计数不动）
# ============================================================
KEYSETS = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]]
check("D1 四主语言键集一致且计数 = 1955（Task174 零新增；十症状并行会话并入后 1954->1955）",
      all(len(k) == 1955 for k in KEYSETS) and KEYSETS[0] == KEYSETS[1] == KEYSETS[2] == KEYSETS[3])
check("D2 新拟态双键六语言仍在位（interface.title + opacity.title）",
      all(k in KEYSETS[0] for k in ["background.cards.neumorph.interface.title",
                                     "background.cards.neumorph.opacity.title"])
      and all("background.cards.neumorph.interface.title" in
              rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
              for lg in ["ja", "km"]))

# ============================================================
# E. 公告 + version.h
# ============================================================
anns = json.loads(rd("announcements.json"))["announcements"]
ids = [a["id"] for a in anns]
check("E1 公告插入 index 2（server/task169 pin 不动；本条@2 后双 task173 顺延 anns[3]/[4]，172/171/170/168 顺延 anns[5]/[6]/[7]/[8]）且 id 唯一",
      len(ids) == len(set(ids))
      and anns[0]["id"] == "server-recommend-2026-09-24"
      and anns[1]["id"] == "task169-four-fixes-2026-09-25"
      and anns[2]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[3]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[4]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[5]["id"] == "task172-six-fixes-2026-09-25"
      and anns[6]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[7]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[8]["id"] == "task168-neumorph-faq-json-2026-09-25")
t174 = anns[2]
check("E2 公告内容锚（晕影根因=壁纸垫底/画布接管/百分比实时回显 + EN 尾注）",
      "晕影" in t174["summary"] and "画布接管" in t174["summary"]
      and "壁纸" in t174["content"] and "实时回显" in t174["content"]
      and "EN:" in t174["content"] and "[Task174]" in t174["content"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E3 version.h Task 174 addendum（canvas takeover + label live echo）",
      "Task 174" in vh and "canvas takeover" in vh
      and "neumorph UI canvas active" in vh)
check("E4 历史 addendum 仍在（append-only 不回改）",
      all(f"Task {t}" in vh for t in (168, 169, 170, 171, 172, 173)))

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
check("F2 配平：BackgroundSettingsViewController.m", balance("Natives/BackgroundSettingsViewController.m"))
check("F3 announcements.json 合法 JSON 且新条目元数据齐备",
      "priority" in t174 and "date" in t174 and "title" in t174
      and t174["date"] == "2026-09-26")

# ============================================================
# G. 级联零新增失败（家法：当前失败 ⊆ 提交树基线 ∪ 具名沙箱传播簇）
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

print(f"\n===== verify_task174: {PASS} passed, {FAIL} failed =====")
sys.exit(1 if FAIL else 0)
