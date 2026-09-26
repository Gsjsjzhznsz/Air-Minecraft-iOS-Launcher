#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task178 文档工具：announcements task178@2 插入 + version.h 附录（append-only）。"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ANN_ID = "task178-neumorph-decouple-opacity-2026-09-26"
ANN = {
    "id": ANN_ID,
    "title": "新拟态与 UI 效果设置解耦：开关不再变灰其他选项 + 新拟态透明度滑条回归 + 新闻卡圆角修复",
    "date": "2026-09-26",
    "priority": "normal",
    "summary": "按用户定稿结合 UI 效果设置：新拟态界面开关不管开还是关，都不会使其他选项变灰（灰化逻辑整体退役，恒可操作）；开启时 UI 效果类型（毛玻璃/半透明）和模糊程度只作用于壁纸/旧管线，完全不影响新拟态卡片；新拟态透明度滑条恢复（模糊程度下方），它改变新拟态的透明度——只淡卡片本体（渐变表面+双阴影整体淡化），字体/图标始终不透明，默认 100% 即上轮认可的形态；UI 效果里的透明度（壁纸材质）与卡片无关。另修复新闻界面新闻卡片圆角太圆（引擎短边等比把 12pt 卡改写成 ~27pt，现钉住卡片自定圆角）。",
    "content": (
        "本轮按用户定稿把新拟态和 UI 效果设置正确地\"结合\"起来：\n\n"
        "1) 开关不再变灰任何选项：新拟态界面开关无论开还是关，UI 效果类型、透明度、模糊程度三行恒可操作（旧版开启时变灰的逻辑退役）。\n"
        "2) 解耦定稿：新拟态开启时，UI 效果类型（毛玻璃/半透明）和模糊程度只影响壁纸层（背景的模糊/材质），对卡片零影响——两套渲染管线并行共存，各读各的偏好。\n"
        "3) 新拟态透明度滑条回归（开关行下方，无壁纸时也有）：只有它可以改变新拟态的透明度。0%~100% 全档，只淡卡片本体（渐变表面+双阴影整体淡化，半透明态下投影内侧与表面同步衰减，晕影不随透明度回归），字体/图标始终不透明；默认 100% = 上一轮认可的白瓷形态原样，未拖动过滑条不会有任何变化。\n"
        "4) 新闻卡圆角修复：新闻页卡片自定 12pt 圆角此前被引擎按卡片短边等比改写成 ~27pt（\"太圆了\"）；现在钉住卡片自定圆角，投影/表面/宿主三者同步。\n\n"
        "装机锚点：设置 → 外观 → \"新拟态界面\"开关（恒显）+ \"新拟态透明度\"滑条（恒显）；拖动滑条卡片实时跟随、百分比实时回显、文字始终清晰；开启开关后拖\"模糊程度\"可见壁纸变化而卡片纹丝不动。EN: Decoupled neumorphism from UI-effect settings — the toggle never grays out other options; effect type & blur affect only the wallpaper; the dedicated Neumorphism Opacity slider (default 100%) is the sole control of card-body translucency, fonts always opaque; news cards keep their intended 12pt corner radius."
    ),
}

ann_path = ROOT / "announcements.json"
data = json.loads(ann_path.read_text(encoding="utf-8"))
anns = data["announcements"]
if any(a["id"] == ANN_ID for a in anns):
    print("[skip] announcement already present")
else:
    assert anns[0]["id"] == "server-recommend-2026-09-24", "anns[0] pin drifted"
    assert anns[1]["id"] == "task169-four-fixes-2026-09-25", "anns[1] pin drifted"
    anns.insert(2, ANN)
    ann_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[ok] announcements: task178@2 inserted, count {len(anns)-1} -> {len(anns)}")

fb_path = ROOT / "Natives" / "resources" / "announcements-fallback.json"
fb = json.loads(fb_path.read_text(encoding="utf-8"))
print(f"[info] fallback count = {len(fb['announcements'])} (不动，Task169 口径)")

vh_path = ROOT / "Natives" / "external" / "MobileGlues" / "MobileGlues-cpp" / "version.h"
vh = vh_path.read_text(encoding="utf-8")
if "Amethyst Task 178" in vh:
    print("[skip] version.h addendum already present")
else:
    addendum = """
// REVISION 17 addendum (Amethyst Task 178, no bump): neumorphism / UI-effect
// settings decoupling per the user's final spec. (1) The neumorphic toggle
// NEVER grays out the other options in either state -- the Task172/173
// graying blocks (contentView.alpha 0.35 + userInteractionEnabled) are gone;
// effect-type / uiOpacity / blur rows stay interactive at all times.
// (2) With the toggle ON, UI effect type (blur/translucent) and blur level
// only affect the wallpaper layer; cards are rendered by the Task177 spec
// pipeline which reads none of them. (3) Card-body opacity slider RESTORED
// (Task170 mechanism): BackgroundManager.cardsNeumorphOpacity
// (defaults background_cards_neumorph_opacity, default 1.0 = Task177 look
// untouched) -> engine ame_applyNeumorphCardOpacity adapted to the three-
// layer engine: the whole AmeNeumorphShadowView (opaque gradient surface +
// shadow pair) fades as ONE composite so the inner-spill occlusion survives
// translucency (no haze returns at partial opacity); host fallback color
// steps aside (clear); labels/icons are sibling subviews and stay fully
// opaque. ame_applyNeumorphSurface re-pins shadowView.alpha = 1.0 so an
// unpaired re-apply fails safe toward the approved opaque look. Settings:
// "Neumorphism Opacity" row (tags 500/501/502, always visible, below the
// toggle; no-wallpaper section0 = 2 rows) + Task174 live percentage label.
// (4) News card corner pin: ame_setNeumorphPinnedCornerRadius (opt-in
// associated flag read by ame_refreshForHostBounds) -- MinecraftNews cards
// keep their explicit 12pt radius instead of the short-side proportional
// ~27pt override ("太圆了"). l10n: background.cards.neumorph.opacity.title
// restored x6 (four main languages 1954 -> 1955). Device anchor: one-shot
// "[Task178] neumorph decoupled: pinned spec cards + card-body opacity
// slider, UI effect options stay interactive" log.
"""
    vh_path.write_text(vh + addendum, encoding="utf-8")
    print("[ok] version.h: Task 178 addendum appended")

sys.exit(0)
