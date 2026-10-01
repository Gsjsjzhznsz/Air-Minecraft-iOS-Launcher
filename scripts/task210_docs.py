#!/usr/bin/env python3
"""Task210 docs cascade: announcement insert @2 + re-anchor family + version.h.

1. announcements.json: 31 -> 32, task210-neumorph-retirement @2 (tail task206-nggl4es stays last)
2. Mechanical +1 shift of absolute announcement anchors in verify_task*.py
   (anns[N]/ann[N]/["announcements"][N], N>=2; ann[-1] untouched).
   EXCLUDED: verify_task168.py / verify_task170.py (already re-anchored to the
   post-insert baseline during the Task210 code round).
3. len(ann) == 31 -> 32 across verifiers (incl. 207's string-literal gates).
4. Window constants: verify_task165 min24->25, verify_task167 min22->23.
5. version.h: Task210 addendum (REVISION 18, no bump) + trailing SEP close.
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

done = []


def step(msg):
    done.append(msg)
    print("[docs]", msg)


# ---------- 1. announcements.json ----------
ann_path = "announcements.json"
doc = json.load(open(ann_path, encoding="utf-8"))
anns = doc["announcements"]
assert len(anns) == 31, f"expected 31 announcements, got {len(anns)}"
assert anns[2]["id"] == "task209-krypton-rename-2026-10-01"
new_entry = {
    "id": "task210-neumorph-retirement-card-fixes-2026-10-02",
    "date": "2026-10-02",
    "title": "新拟态全面退役 + 实例卡修复（Task 210）",
    "summary": "应用户定稿删除全部新拟态代码与选项；实例卡修复高度裁剪/省略号比例/深浅模式字体/选中描边。",
    "content": (
        "Task 210 双主题。\n\n"
        "一、新拟态全面退役（用户定稿：检索并删除所有新拟态代码和其选项和设置，维护过于麻烦）。\n"
        "删除范围：AmeNeumorphShadowView 三层承载引擎（暗影/高光投影 + 渐变表面）、"
        "AmeNeumorph 规格色族与度量、ame_applyNeumorphSurface/FlatWithRadius/removeNeumorphShadow/"
        "CardOpacity/PinnedCornerRadius 全部原语、BackgroundManager 的 cardsNeumorphEnabled 开关与 "
        "cardsNeumorphOpacity 透明度偏好（defaults 键 background_cards_neumorph_enabled/_opacity 一并退役）、"
        "壁纸设置页「新拟态界面」开关行与「新拟态透明度」滑条行（无壁纸时该区段整段隐藏）、"
        "六语言 background.cards.neumorph.* 双键（四主语言键集 2419 -> 2417）。\n"
        "保留（用户定稿「保留平贴灰面」）：无壁纸时卡面 = 平贴灰面（浅色 #e0e0e0 / 深色 #2c2c2c），"
        "无任何自绘阴影；有壁纸时毛玻璃/半透明管线原样；卡面文字色族改名 AmeCardPrimary/SecondaryTextColor "
        "（浅 #333333/#888888、深 #f5f5f5/#a0a0a0），深浅自适应。\n\n"
        "二、实例卡（快捷指令样）修复（七问定稿）。\n"
        "1. 卡底 = 深浅自适应平贴灰面（accent 渐变卡底退役——它跟随新拟态透明度滑条导致「卡片平时透明」）；\n"
        "2. 图标 = 原始彩色直出（白色模板渲染退役，PNG 不着色 / SF 用品牌色，cube 兜底用主题强调色）；\n"
        "3. 选中 = 纯 2pt 原蓝内缩描边（内缩距仍 = 省略号间距 × 1/3；柔光光晕、整卡变色、按压弹簧缩放全部退役——"
        "全部磁贴统一即时响应）；\n"
        "4. 字体 = 深浅模式自适应（名称 #333333/#f5f5f5，版本 #888888/#a0a0a0，白字退役）；\n"
        "5. 高度 = 104pt（84pt 时代 iPad 满档字号内容 86pt 被裁，用户实测「字体被裁减」）；\n"
        "6. 省略号 = 圆底 24 -> 28pt、三点 12 Bold -> 16 Black（用户定稿「加大加粗两档」），"
        "配色改自适应（labelColor 12% 底 + labelColor 三点，浅色平贴灰面上不再隐形）；\n"
        "7. 交互不变：点卡片 = 选用实例，⋯ = 纯编辑，长按菜单三件套保留。\n\n"
        "EN: Task 210 retires the entire neumorphism engine per user order (code, toggle and opacity slider, "
        "defaults keys, six-language keys; wallpaper blur/translucent untouched; flat gray surface kept). "
        "Instance cards: height 84->104pt (fixes clipped labels at full iPad font scale), original-color icons, "
        "mode-adaptive text colors, pure 2pt accent selection border (glow/tint/press-spring all retired), "
        "larger ellipsis button (28pt circle, 16pt Black glyph). Interaction unchanged: tap to use, ... to edit.\n\n"
        "维护路径：settings -> 壁纸设置（无壁纸时 UI 效果区段自动隐藏）；实例卡样式由 "
        "VersionManagerViewController VMVersionCardCell 统一承载。"
    ),
}
anns.insert(2, new_entry)
json.dump(doc, open(ann_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
step(f"announcements.json 31 -> {len(anns)} (task210 @2, tail = {anns[-1]['id']})")

# ---------- 2/3. mechanical re-anchor ----------
EXCLUDE = {"verify_task168.py", "verify_task170.py", "verify_task210.py"}
shifted = {}
for fn in sorted(os.listdir("scripts")):
    if not (fn.startswith("verify_task") and fn.endswith(".py")) or fn in EXCLUDE:
        continue
    path = os.path.join("scripts", fn)
    src = open(path, encoding="utf-8").read()
    orig = src

    def bump(m):
        n = int(m.group(2))
        if n >= 2:
            return m.group(1) + str(n + 1)
        return m.group(0)

    patterns = [
        (r'(anns\[)(\d+)\]', bump),
        (r'(\bann\[)(\d+)\]', bump),
        (r'(\["announcements"\]\[)(\d+)\]', bump),
        (r'(len\(anns?\) == )(\d+)', lambda m: m.group(1) + (str(int(m.group(2)) + 1) if m.group(2) == "31" else m.group(2))),
    ]
    for pat, fn_rep in patterns:
        src = re.sub(pat, fn_rep, src)
    if src != orig:
        open(path, "w", encoding="utf-8").write(src)
        n_sites = sum(1 for a, b in zip(orig.split("\n"), src.split("\n")) if a != b)
        shifted[fn] = n_sites
step("mechanical +1 shift: " + (", ".join(f"{k}({v} lines)" for k, v in sorted(shifted.items())) or "no sites"))

# ---------- 4. window constants ----------
w165 = "scripts/verify_task165.py"
s = open(w165, encoding="utf-8").read()
if "range(min(24, len(anns)))" in s:
    s = s.replace("range(min(24, len(anns)))", "range(min(25, len(anns)))")
    open(w165, "w", encoding="utf-8").write(s)
    step("verify_task165 window 24 -> 25")
w167 = "scripts/verify_task167.py"
s = open(w167, encoding="utf-8").read()
if "range(min(22, len(anns)))" in s:
    s = s.replace("range(min(22, len(anns)))", "range(min(23, len(anns)))")
    open(w167, "w", encoding="utf-8").write(s)
    step("verify_task167 window 22 -> 23")

# ---------- 5. version.h ----------
vh_path = "Natives/external/MobileGlues/MobileGlues-cpp/version.h"
vh = open(vh_path, encoding="utf-8").read()
ADDENDUM = """
// -----------------------------------------------------------------------------
// REVISION 18 addendum (Task 210, no bump)
// -----------------------------------------------------------------------------
// Task 210 -- neumorphism full retirement + instance-card fixes (user freeze).
// [Neumorph] AmeNeumorphShadowView three-layer engine (shadow pair + gradient
//   surface), the AmeNeumorph* palette/metrics, and the ame_applyNeumorph*/
//   removeNeumorphShadow/CardOpacity/PinnedCornerRadius primitives are DELETED.
//   BackgroundManager loses cardsNeumorphEnabled/cardsNeumorphOpacity (defaults
//   keys background_cards_neumorph_enabled/_opacity retired); the wallpaper
//   settings page drops the toggle + opacity slider rows (section collapses to
//   zero rows without wallpaper). Six-language keys background.cards.neumorph.*
//   removed (4 main languages 2419 -> 2417). Kept per user freeze: the flat
//   gray surface (#e0e0e0 / #2c2c2c, renamed AmeCardSurfaceColor) with NO
//   self-drawn shadows; wallpaper blur/translucent pipeline untouched; text
//   palette renamed AmeCardPrimary/SecondaryTextColor (#333333/#888888 light,
//   #f5f5f5/#a0a0a0 dark).
// [Cards] VMVersionCardCell: height 84 -> 104pt (clipped labels at iPad full
//   font scale: content needed 86pt), original-color icons (white-template
//   rendering retired; PNG un-tinted / SF brand color / cube fallback accent),
//   mode-adaptive name/version colors, selection = pure 2pt accent inset border
//   (glow, whole-card tint and the tile-wide press spring-scale all retired),
//   ellipsis button 24 -> 28pt circle with 16pt Black glyph in adaptive
//   labelColor (12% plate). Interaction unchanged: tap = use, ... = edit,
//   long-press menu intact.
"""
if "REVISION 18 addendum (Task 210, no bump)" not in vh:
    vh = vh.rstrip("\n") + "\n" + ADDENDUM
open(vh_path, "w", encoding="utf-8").write(vh)
step("version.h Task210 addendum appended")
if not vh.rstrip().endswith("// -----------------------------------------------------------------------------"):
    with open(vh_path, "a", encoding="utf-8") as f:
        f.write("// -----------------------------------------------------------------------------\n")
    step("version.h trailing SEP close restored")

print("\n[docs] ALL DONE:", len(done), "steps")
