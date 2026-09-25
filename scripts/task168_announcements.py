#!/usr/bin/env python3
# Task168：公告插入（index 2，verify_task169 F5 钉死 anns[1]=task169）+ version.h addendum
import json

ANN = "announcements.json"
d = json.load(open(ANN, encoding="utf-8"))
anns = d["announcements"]

assert anns[1]["id"] == "task169-four-fixes-2026-09-25", anns[1]["id"]
assert not any(a["id"] == "task168-neumorph-faq-json-2026-09-25" for a in anns), "already inserted"

entry = {
    "id": "task168-neumorph-faq-json-2026-09-25",
    "title": "新拟态卡片形态修复（壁纸模式可见）+ 使用问题 JSON 化",
    "date": "2026-09-25",
    "summary": "修复「设了壁纸就看不到新拟态」的范围判定失误：全部卡片统一新拟态（动态=卡面随壁纸透明度/模糊+双阴影，可开「实底」开关）；「使用问题」34 条迁移 JSON 存储，公告/使用问题的维护路径见正文。",
    "content": (
        "## 新拟态修复（该改的这次真的改了）\n\n"
        "- **根因**：上一轮（Task163）的凸起管线只在**未设壁纸**时生效——设了壁纸的卡片仍走旧毛玻璃，所以你下载最新提交也看不到新拟态。代码一直在包里（提交 447a677），是范围判定失误，不是没提交。\n"
        "- **本轮修复**：主页卡片（新闻/功能磁贴）、下载页版本选项卡等全部卡片统一新拟态：\n"
        "  - **动态（默认）**：壁纸模式下卡面仍按你设置的**透明度/模糊**呈现（毛玻璃/半透明），叠加新拟态**双阴影凸起**——即「按壁纸设置的透明度和模糊程度动态调整新拟态」；\n"
        "  - **实底开关**：设置 → 外观 → 「卡片新拟态（实底）」。打开后卡片一律规格实底+双阴影，放弃壁纸透明度/模糊（壁纸从卡片间隙透出）。\n"
        "- 侧栏/右面板维持平贴（Task163 结论：大面板等比阴影会外溢压到相邻卡片）。\n\n"
        "## 使用问题 JSON 化\n\n"
        "- 「使用问题」全部 34 个条目迁移为 JSON 存储（与启动器公告同模式），字段：**标题 / 图标id / 简介**。\n"
        "- **维护路径（两个，改完重新构建生效）**：\n"
        "  - 启动器公告：仓库根 `announcements.json`（随包离线回退 = `Natives/resources/announcements-fallback.json`）\n"
        "  - 使用问题：仓库根 `help-faq.json`（维护源）+ `Natives/resources/help-faq.json`（随包，运行时读取）——两文件逐字节一致，校验脚本把守漂移\n"
        "- 顺带更新过时结论：FSR 条目改为**三后端均支持**（Vulkan 经 Metal 呈现层，Task166/167），MobileGlues 卡顿条目补 Vulkan+FSR 推荐路径。\n\n"
        "---\n\n"
        "Task 168: neumorphic cards are now visible in wallpaper mode too (dynamic = card face follows your opacity/blur settings + neumorphic dual shadows; a new Solid Card Neumorphism toggle in Settings -> Appearance forces the solid spec surface). The 34 FAQ entries moved to JSON storage like the announcements -- edit the repo-root files (announcements.json / help-faq.json) to maintain them."
    ),
    "priority": "normal",
    "action_url": "",
    "action_title": "",
    "image_url": "",
}

anns.insert(2, entry)
json.dump(d, open(ANN, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("announcement inserted at index 2; total =", len(anns))

# version.h addendum
VH = "Natives/external/MobileGlues/MobileGlues-cpp/version.h"
s = open(VH, encoding="utf-8").read()
assert "Task 168" not in s
addendum = """// Task 168 (2026-09-25): neumorphism wallpaper-mode visibility + FAQ JSON.
// (1) Root cause of "downloaded the latest commit but no neumorphism": the
// Task163 raised-card pipeline only engaged WITHOUT a custom wallpaper --
// with one set, cards fell back to the legacy frosted-glass branch and never
// showed the spec surface/shadows. Fix: applyNeumorphCardEffectToView: and
// applyEffectToCollectionViewCell: no longer early-return into the legacy
// pipeline. With a wallpaper the card FACE still follows the user's
// opacity/blur settings (dynamic neumorphism = face per wallpaper settings +
// dual-shadow overlay via the new ame_attachNeumorphShadowOnly, which keeps
// the face color untouched); the new "cardsNeumorphSolid" preference
// (BackgroundSettingsViewController switch, default OFF) forces the solid
// spec surface + dual shadows, giving up wallpaper transparency/blur.
// (2) The 34 help-FAQ entries moved out of hardcoded ObjC into a bundled
// JSON (help-faq.json, same pattern as announcements): repo root = editing
// source, Natives/resources/help-faq.json = bundled copy read at runtime,
// byte-identical, drift-guarded by verify_task168. LauncherHelpViewController
// now parses it (icon/title/description fields, empty-groups on parse
// failure). Stale FAQ conclusions updated in the same pass: FSR entry now
// states all three backends are supported (Vulkan via the Metal presentation
// layer, Task166/167), MobileGlues chunk-loading entry gains the
// Vulkan+FSR recommendation.
"""
s2 = s.rstrip("\n") + "\n" + addendum
open(VH, "w", encoding="utf-8").write(s2)
print("version.h addendum appended")
