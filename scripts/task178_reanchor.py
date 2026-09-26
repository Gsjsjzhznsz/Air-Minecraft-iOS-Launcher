#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task178 重锚工具：历史校验器诚实重锚（含 verify_task177 语义反转）。

本轮（Task178）用户定稿：
  1) 新拟态开关不管开还是关都不会使其他选项变灰（灰化全退）；
  2) UI 效果类型/模糊度不影响新拟态（结构本已解耦，断言维持）；
  3) 卡片本体透明度滑条恢复（Task170 机制）：引擎 ame_applyNeumorphCardOpacity
     适配 Task177 三层引擎（承载视图整体 alpha，文字不参与），
     cardsNeumorphOpacity 偏好/落盘键/设置页行恢复；
  4) 新闻卡圆角钉住 12pt（ame_setNeumorphPinnedCornerRadius，等比改写豁免）；
  5) l10n 恢复 background.cards.neumorph.opacity.title ×6（四主语言 1954->1955）；
  6) 公告 task178@2（历史条目整体顺延 +1）。

每个替换强制精确匹配 expected 次，任何偏差即中止退出（防误锚）。
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (相对路径, [(old, new, expected_count), ...])
JOBS = [
    # ---------- 计数锚（简单 +1） ----------
    ("scripts/verify_task129.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task130.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task131.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task132.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task133.py", [("len(ks[0]) == 1954", "len(ks[0]) == 1955", 1)]),
    ("scripts/verify_task134.py", [("len(ks[0]) == 1954", "len(ks[0]) == 1955", 1)]),
    ("scripts/verify_task135.py", [
        ('vals == {1954}', 'vals == {1955}', 1),
        ('D3 四语言唯一键集一致且为 Task151 基线 1954（Task150 的 1928 + Bing 组件 17）',
         'D3 四语言唯一键集一致且为 Task151 基线 1955（Task178 重锚：opacity.title 键恢复）', 1),
    ]),
    ("scripts/verify_task138.py", [("len(ks[0]) == 1954", "len(ks[0]) == 1955", 1)]),
    ("scripts/verify_task142.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task143.py", [("total == 1954", "total == 1955", 1)]),
    ("scripts/verify_task150.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task151.py", [
        ('counts["en"] == 1954', 'counts["en"] == 1955', 1),
        ('if m.group(1) != "1954":\n                stale.append(f"{fn}:{m.group(1)}")',
         'if m.group(1) != "1955":\n                stale.append(f"{fn}:{m.group(1)}")', 1),
        ('if m.group(1) != "1954":\n                stale.append(f"{fn}:vals{m.group(1)}")',
         'if m.group(1) != "1955":\n                stale.append(f"{fn}:vals{m.group(1)}")', 1),
        ('check("H no stale l10n anchors (expect 1954 everywhere (Task177 re-anchor), Task168 baseline)", not stale, str(stale))',
         'check("H no stale l10n anchors (expect 1955 everywhere (Task178 re-anchor), Task168 baseline)", not stale, str(stale))', 1),
    ]),
    ("scripts/verify_task156.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task157.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task159.py", [("len(sets[0]) == 1954", "len(sets[0]) == 1955", 1)]),
    ("scripts/verify_task137.py", [
        # 仅历史叙述注释，本轮不动（无活跃 1954 断言）
    ]),

    # ---------- verify_task168 ----------
    ("scripts/verify_task168.py", [
        ('check("A7b 透明度原语全链退役（Task177 重锚：宿主 alpha 与卡片本体透明度原语都成历史）",\n      "target.alpha = self.cardsNeumorphOpacity;" not in bm_m\n      and "cardTarget.alpha = self.cardsNeumorphOpacity;" not in bm_m\n      and bm_m.count("[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 0\n      and bm_m.count("[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 0)',
         'check("A7b 卡片本体透明度原语恢复（Task178 重锚：宿主 alpha 仍是历史，引擎原语两管线挂点回归）",\n      "target.alpha = self.cardsNeumorphOpacity;" not in bm_m\n      and "cardTarget.alpha = self.cardsNeumorphOpacity;" not in bm_m\n      and bm_m.count("[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 1\n      and bm_m.count("[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 1)', 1),
        ('check("B1 透明度属性退役（Task177 重锚：cardsNeumorphOpacity 从 .h/.m 全退）",\n      \'cardsNeumorphOpacity\' not in bm_h\n      and \'- (CGFloat)cardsNeumorphOpacity\' not in bm_m)',
         'check("B1 透明度属性恢复（Task178 重锚：cardsNeumorphOpacity .h 声明 + .m 存取器在位）",\n      \'cardsNeumorphOpacity\' in bm_h\n      and \'- (CGFloat)cardsNeumorphOpacity\' in bm_m)', 1),
        ('check("B2 落盘键退役（Task177 重锚：kBackgroundCardsNeumorphOpacityKey 常量与读写全退）",\n      \'kBackgroundCardsNeumorphOpacityKey\' not in bm_m\n      and "background_cards_neumorph_opacity =" not in bm_m)',
         'check("B2 落盘键恢复（Task178 重锚：kBackgroundCardsNeumorphOpacityKey 常量与 defaults 直读写回归）",\n      \'kBackgroundCardsNeumorphOpacityKey\' in bm_m\n      and \'setDouble:MAX(0.0, MIN(1.0, cardsNeumorphOpacity))\' in bm_m)', 1),
        ('check("B4 滑条行退役（Task177 重锚：行/回调/tags 500~502 全退，开关行保留）",\n      \'"CardsNeumorphOpacityCell"\' not in bsvc\n      and "slider.tag = 500;" not in bsvc\n      and "cardsNeumorphOpacitySliderChanged" not in bsvc\n      and \'"CardsNeumorphToggleCell"\' in bsvc)',
         'check("B4 滑条行恢复（Task178 重锚：行/回调/tags 500~502 回归，开关行保留）",\n      \'"CardsNeumorphOpacityCell"\' in bsvc\n      and "slider.tag = 500;" in bsvc\n      and "cardsNeumorphOpacitySliderChanged" in bsvc\n      and \'"CardsNeumorphToggleCell"\' in bsvc)', 1),
        ('check("B5 滑条回调退役（Task177 重锚）：落盘与刷新链随行消失，开关回调仍在",\n      "cardsNeumorphOpacity = slider.value;" not in bsvc\n      and "[[BackgroundManager sharedManager] refreshUIEffect];" in bsvc)',
         'check("B5 滑条回调恢复（Task178 重锚）：落盘 + 实时回显 + 刷新链齐备，开关回调仍在",\n      "cardsNeumorphOpacity = slider.value;" in bsvc\n      and "[[BackgroundManager sharedManager] refreshUIEffect];" in bsvc)', 1),
        ('l10n_key = "background.cards.neumorph.opacity.title"  # Task177：键随滑条退役（Task170 原位换名的历史就此终结）',
         'l10n_key = "background.cards.neumorph.opacity.title"  # Task178：键随滑条恢复（Task177 曾退役，沿用 Task170 键名）', 1),
        ('check("B7 六语言键全部退役（Task177 重锚）", all(v is None for v in l10n_vals.values()), str(l10n_vals))',
         'check("B7 六语言键全部恢复（Task178 重锚）", all(v is not None for v in l10n_vals.values()), str(l10n_vals))', 1),
        ('check("B8 四主语言键集一致且计数 = 1954（Task170 键原位换名，净变化 0）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1954',
         'check("B8 四主语言键集一致且计数 = 1955（Task178 重锚：opacity.title 键恢复，净增 1）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1955', 1),
    ]),
]

def apply_job(path, replacements):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    for old, new, expected in replacements:
        n = text.count(old)
        if n != expected:
            print(f"[FAIL] {path}: pattern matched {n}x (expect {expected}):\n  {old[:120]}...")
            return False
        text = text.replace(old, new)
    p.write_text(text, encoding="utf-8")
    print(f"[ok] {path}: {len(replacements)} replacement(s)")
    return True

ok = all(apply_job(path, reps) for path, reps in JOBS)
sys.exit(0 if ok else 1)
