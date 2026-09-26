#!/usr/bin/env python3
# Task 176 docs: insert announcement at index 2 + append version.h addendum.
import json, io, sys

ROOT = __file__.rsplit("/scripts/", 1)[0]

# ---------- announcements.json: task177 at index 2 ----------
APATH = ROOT + "/announcements.json"
d = json.load(open(APATH, encoding="utf-8"))
anns = d["announcements"]
if any(a.get("id") == "task177-neumorph-css-spec-2026-09-26" for a in anns):
    print("announcement already present, skip")
else:
    entry = {
        "id": "task177-neumorph-css-spec-2026-09-26",
        "title": "新拟态按 CSS 参考定稿重写：全不透明渐变表面 + 固定档微阴影，透明度机制退役",
        "date": "2026-09-26",
        "priority": "normal",
        "summary": "按用户给过的 CSS 样式参考（bigbear-ui neu-white）对新拟态做定稿重写：卡片表面 = linear-gradient(145deg,#e6e6e6,#ffffff)（深色 #333333→#2c2c2c 同构），双阴影 = 固定 4pt 偏移 / 8pt 模糊（小元素 2/4pt）全不透明纯色（浅 #d6d6d6+#ffffff / 深 #1e1e1e+#3a3a3a）。晕影根因定稿：旧引擎的透明投影承载层把阴影直接叠染在卡面内侧，配合 20/60pt 短边等比放大与 0.45/0.5 柔和档透明度，任何壁纸/开关状态下都是重晕影。本轮改为「投影对垫底 + 不透明渐变表面盖住内侧」的 CSS box-shadow 原生等价结构，卡面恒全不透明。同时按「不要加任何的透明度」定稿：新拟态透明度滑条整体退役，卡片不再读任何透明度/模糊偏好（设置页仅保留新拟态界面开关）。",
        "content": "## 新拟态 CSS 参考定稿重写（Task 176）\n\n**规格来源 = 你给过的 CSS 样式参考（bigbear-ui neu-white mixin）**\n\n- `background: linear-gradient(145deg, #e6e6e6, #fff)` → 卡片表面原生渐变（CAGradientLayer，145° 轴向精确换算）；深色模式同构 #333333→#2c2c2c。\n- `box-shadow: 2px 2px 4px #d6d6d6, -2px -2px 4px #fff` → 双阴影固定档：卡片 4pt 偏移 / 8pt 模糊，小元素 2pt / 4pt，颜色全不透明（浅 #d6d6d6 右下暗影 + #ffffff 左上高光；深 #1e1e1e / #3a3a3a）。\n\n**晕影根因（为什么之前每轮都在）**\n\n- 旧引擎的阴影承载层是【透明投影层】，阴影直接画在卡面内侧之上——20/60pt 的等比模糊把整卡罩进晕影，壁纸模式下再叠 0.45/0.5 柔和档，怎么调都是晕影。\n- 本轮结构改为「两层纯投影垫底 + 不透明渐变表面盖住投影内侧」，即 CSS `box-shadow` 在元素之后合成的原生等价物：投影只剩边界外侧 2~4pt 微晕，卡面恒全不透明。\n\n**透明度机制退役（不要加任何的透明度）**\n\n- 新拟态透明度滑条整体移除，`background_cards_neumorph_opacity` 不再读取；卡片不再读 uiOpacity / blurIntensity——UI 效果的模糊度/透明度与新拟态彻底解耦。\n- 设置→外观仅保留「新拟态界面」开关：开启 = CSS 规格卡片（其余 UI 效果选项置灰），关闭 = 旧壁纸管线。\n- 圆角沿用短边等比 clamp[8,50]，尺寸位置零变化；壁纸共存语义不变（壁纸照常显示，卡片浮于其上）。\n\nEN: Neumorphism finalized rewrite per the user-provided CSS reference (bigbear-ui neu-white): opaque linear-gradient(145deg) surface (#e6e6e6->#ffffff, dark #333333->#2c2c2c) over a pair of fully-opaque fixed-tier dual shadows (4pt offset / 8pt blur, small elements 2/4pt; light #d6d6d6+#ffffff, dark #1e1e1e+#3a3a3a). Root cause of the persistent halos: the old transparent shadow-casting layers painted shadows on top of the card interior, amplified by 20/60pt size-scaled blur and the 0.45/0.5 wallpaper-soft opacities. The new layering (shadow pair behind, opaque gradient surface in front) mirrors CSS box-shadow compositing: cards stay fully opaque with only a 2-4pt outer micro-halo. The neumorphism opacity slider is retired entirely and cards no longer read any transparency/blur preferences. [Task177]",
    }
    anns.insert(2, entry)
    json.dump(d, open(APATH, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(APATH, "a", encoding="utf-8").write("\n")
    print("announcement inserted at index 2, total", len(anns))

# ---------- version.h addendum ----------
VPATH = ROOT + "/Natives/external/MobileGlues/MobileGlues-cpp/version.h"
vh = open(VPATH, encoding="utf-8").read()
if "Amethyst Task 176" in vh:
    print("version.h addendum already present, skip")
else:
    addendum = """
// REVISION 17 addendum (Amethyst Task 176, no bump): neumorphism finalized
// rewrite per the user-provided CSS reference (bigbear-ui neu-white mixin:
// background linear-gradient(145deg,#e6e6e6,#fff); box-shadow N N 2N
// #d6d6d6 / -N -N 2N #fff with N=2px normal / 4px large). Native equivalent
// shipped in AmeNeumorphShadowView: a shadow PAIR (clear layers, offsets
// +/-N, shadowOpacity 1.0, shadowRadius = blur/2; light #d6d6d6/#ffffff,
// dark #1e1e1e/#3a3a3a) BEHIND an opaque CAGradientLayer surface
// (145deg axis start (0.2132,0.0904) end (0.7868,0.9096); light
// #e6e6e6->#ffffff, dark #333333->#2c2c2c) -- the surface occludes the
// shadow pair's inner spill, mirroring CSS box-shadow compositing behind
// the element. Root cause this kills: the Task160/175 transparent shadow
// carriers painted the blurred silhouettes ON TOP of the card interior
// (whole-card tint) and metrics scaled offset/blur to 20/60pt with the
// short side; fixed tiers now: cards 4/8pt, small elements 2/4pt, radius
// scaling unchanged. Transparency retired per the user's "no transparency
// at all": ame_applyNeumorphCardOpacity + cardsNeumorphOpacity + the
// settings slider row + ame_setNeumorphWallpaperSoft/soft profile are
// deleted; cards no longer read uiOpacity/blurIntensity. Device anchor:
// one-shot "[Task177] neumorph UI spec rewrite" log.
"""
    vh = vh.rstrip("\n") + "\n" + addendum
    open(VPATH, "w", encoding="utf-8").write(vh)
    print("version.h addendum appended")

print("OK")
