#!/usr/bin/env python3
# Task170: announcement insertion (index 2, task169 anns[1] pin preserved,
# task168 shifted to anns[3]) + version.h REVISION 17 addendum (no bump).
# Idempotent: re-running detects the existing entry and exits clean.
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

ANN_ID = "task170-neumorph-opacity-spacing-2026-09-25"

SUMMARY = ("卡片新拟态整体透明度滑条（替换 Task168 实底开关——设置→外观，"
           "0%~100% 调节整个卡片含边缘阴影的透明度，晕影重就调低）"
           "+ 主页卡片间距统一 20pt（卡间 = 卡到侧边栏外沿）。"
           " EN: whole-card neumorphism opacity slider replaces the solid "
           "toggle; home tile gaps unified to the 20pt outer margin.")

CONTENT = "\n".join([
    "【更新】卡片新拟态透明度滑条 + 主页卡片间距统一（Task 170）",
    "",
    "一、新拟态透明度（替换上一版的「卡片新拟态（实底）」开关）",
    "· 位置：设置 → 外观 → 「新拟态透明度」拉条（0% ~ 100%）",
    "· 语义：调节「整个卡片」的透明度——卡面、新拟态双阴影、卡片内容作为一个整体按比例淡化",
    "· 100% = 上一版形态原样；觉得卡片边缘晕影太重就往低调（比如 60%~80%），阴影会跟着变淡",
    "· 0% = 卡片整体不可见（极端档位，一般用不到）",
    "",
    "二、主页卡片间距",
    "· 主页面卡片之间的横向/纵向间距统一为 20pt，与外围卡片到侧边栏的距离一致",
    "",
    "三、说明",
    "· 沿用毛玻璃/半透明卡面与壁纸透明度、模糊程度两个滑条的既有行为，本次不改动",
    "· 维护入口：启动器公告 = 仓库根 announcements.json；使用问题 = 仓库根 help-faq.json（随包副本 Natives/resources/，两文件保持一致）",
    "",
    "EN: Task 170 -- \"Neumorphism Opacity\" slider (0%~100%) replaces the solid-card toggle; it scales the whole card (face + dual shadows + content) as one unit, so heavy edge halos can be dialed down directly. Home tile spacing unified to 20pt, equal to the card-to-sidebar margin.",
])

# ---- announcements.json ----
with open("announcements.json", encoding="utf-8") as f:
    doc = json.load(f)
anns = doc["announcements"]

if any(a.get("id") == ANN_ID for a in anns):
    print("[task170] announcement already present -- skip insert")
else:
    # 保护位：anns[1] = task169 pin（Task169 F5 家法）
    assert anns[1]["id"] == "task169-four-fixes-2026-09-25", \
        f"anns[1] drifted: {anns[1]['id']}"
    entry = {
        "id": ANN_ID,
        "date": "2026-09-25",
        "title": "卡片新拟态透明度滑条 + 主页卡片间距统一",
        "summary": SUMMARY,
        "content": CONTENT,
    }
    anns.insert(2, entry)
    with open("announcements.json", "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("[task170] announcement inserted at index 2")

# ---- version.h addendum ----
VH = "Natives/external/MobileGlues/MobileGlues-cpp/version.h"
vh = open(VH, encoding="utf-8").read()
MARKER = "Task 170"
if MARKER in vh:
    print("[task170] version.h addendum already present -- skip")
else:
    addendum = (
        "\n// Task 170 (2026-09-25): user followup on Task 168 -- the binary\n"
        "// cardsNeumorphSolid toggle is retired in favor of a continuous\n"
        "// \"Neumorphism Opacity\" slider (defaults key\n"
        "// background_cards_neumorph_opacity, 0.0~1.0, default 1.0 = Task 168\n"
        "// form untouched). The slider scales the WHOLE card as one unit\n"
        "// (face + dual-shadow carrier + content) via the host view alpha,\n"
        "// set in every terminal branch of applyNeumorphCardEffectToView /\n"
        "// applyEffectToCollectionViewCell, so heavy edge halos reported on\n"
        "// device can be dialed down directly. Home tile collection layout\n"
        "// gaps unified to 20pt (item insets 10 + section insets 10), equal\n"
        "// to the card-to-sidebar outer margin. l10n key renamed in place\n"
        "// (background.cards.neumorph.opacity.title x6, count 1953). No\n"
        "// engine (UIKit+NativeSurface) changes.\n"
    )
    with open(VH, "a", encoding="utf-8") as f:
        f.write(addendum)
    print("[task170] version.h addendum appended")

print("[task170] done")
