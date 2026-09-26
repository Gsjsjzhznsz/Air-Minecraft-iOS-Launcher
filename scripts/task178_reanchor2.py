#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task178 重锚工具（阶段 2）：verify_task170 / 173b / 174 / 175 / 177 语义反转。
每个替换强制精确匹配 expected 次，任何偏差即中止退出。"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

JOBS = [
    # ---------- verify_task170 ----------
    ("scripts/verify_task170.py", [
        ('check("A1 透明度属性退役（Task177 重锚：cardsNeumorphOpacity 从 .h 全退）",\n      "cardsNeumorphOpacity" not in bm_h)',
         'check("A1 透明度属性恢复（Task178 重锚：cardsNeumorphOpacity 回归 .h）",\n      "cardsNeumorphOpacity" in bm_h)', 1),
        ('check("A2 落盘键退役（Task177 重锚：kBackgroundCardsNeumorphOpacityKey 常量/读写全退）",\n      "kBackgroundCardsNeumorphOpacityKey" not in bm_m)',
         'check("A2 落盘键恢复（Task178 重锚：kBackgroundCardsNeumorphOpacityKey 常量/读写回归）",\n      "kBackgroundCardsNeumorphOpacityKey" in bm_m)', 1),
        ('check("A3 透明度默认值分支随原语退役（Task177 重锚：OpacityKey 判空分支消失）",\n      "objectForKey:kBackgroundCardsNeumorphOpacityKey] == nil" not in bm_m)',
         'check("A3 透明度默认值分支恢复（Task178 重锚：OpacityKey 判空默认 1.0 回归）",\n      "objectForKey:kBackgroundCardsNeumorphOpacityKey] == nil" in bm_m)', 1),
        ('and "[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" not in card_fn)',
         'and "[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" in card_fn)', 1),
        ('and "[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" not in cell_fn)',
         'and "[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" in cell_fn)', 1),
        ('check("B7 引擎透明度原语退役（Task177 重锚：ame_applyNeumorphCardOpacity/shadowView.alpha 全退，规格恒全不透明）",\n      "ame_applyNeumorphCardOpacity" not in engine_m\n      and "shadowView.alpha = o;" not in engine_m\n      and "shadowOpacity = 1.0" in engine_m)',
         'check("B7 引擎透明度原语恢复（Task178 重锚：ame_applyNeumorphCardOpacity/shadowView.alpha 回归；重铺复位 1.0 兜底）",\n      "ame_applyNeumorphCardOpacity" in engine_m\n      and "shadowView.alpha = o;" in engine_m\n      and "shadowOpacity = 1.0" in engine_m)', 1),
        ('check("C1 滑条标题键随行退役（Task177 重锚：interface.title 开关键仍在）",\n      \'localize(@"background.cards.neumorph.opacity.title", nil)\' not in bsvc',
         'check("C1 滑条标题键恢复（Task178 重锚：opacity.title 开关键均在）",\n      \'localize(@"background.cards.neumorph.opacity.title", nil)\' in bsvc', 1),
        ('check("C2 滑条行接线退役（Task177 重锚：行/tags/复用标识全退，开关行保留）",\n      \'"CardsNeumorphOpacityCell"\' not in bsvc\n      and "slider.tag = 500;" not in bsvc\n      and "cardsNeumorphOpacitySliderChanged" not in bsvc\n      and \'"CardsNeumorphToggleCell"\' in bsvc)',
         'check("C2 滑条行接线恢复（Task178 重锚：行/tags/复用标识回归，开关行保留）",\n      \'"CardsNeumorphOpacityCell"\' in bsvc\n      and "slider.tag = 500;" in bsvc\n      and "cardsNeumorphOpacitySliderChanged" in bsvc\n      and \'"CardsNeumorphToggleCell"\' in bsvc)', 1),
        ('check("C3 回调退役（Task177 重锚：滑条回调消失，统一刷新链仍在开关/壁纸行）",\n      "- (void)cardsNeumorphOpacitySliderChanged:" not in bsvc',
         'check("C3 回调恢复（Task178 重锚：滑条回调回归，统一刷新链仍在开关/壁纸行）",\n      "- (void)cardsNeumorphOpacitySliderChanged:" in bsvc', 1),
        ('check("E1 六语言新键全部退役（Task177 重锚）", all(v is None for v in vals.values()), str(vals))',
         'check("E1 六语言新键全部恢复（Task178 重锚）", all(v is not None for v in vals.values()), str(vals))', 1),
        ('check("E3 四主语言键集一致且计数 = 1954（换名净变化 0）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1954',
         'check("E3 四主语言键集一致且计数 = 1955（Task178 重锚：opacity.title 键恢复）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1955', 1),
        ('check("F1 公告（Task177 重锚：task177@2 插入，task175/174 顺延 anns[3]/[4]，双 task173 顺延 anns[5]/[6]，task172/171/170/168 顺延 anns[7]/[8]/[9]/[10]；anns[1] task169 pin 不动）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[3]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[4]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[5]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[6]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[7]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[8]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[9]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[10]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt170 = anns[9]',
         'check("F1 公告（Task178 重锚：task178@2 插入，task177/175/174 顺延 anns[3]/[4]/[5]，双 task173 顺延 anns[6]/[7]，task172/171/170/168 顺延 anns[8]/[9]/[10]/[11]；anns[1] task169 pin 不动）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n      and anns[3]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[4]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[5]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[6]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[7]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[8]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[9]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[10]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[11]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt170 = anns[10]', 1),
    ]),

    # ---------- verify_task173b_neumorph ----------
    ("scripts/verify_task173b_neumorph.py", [
        ('and "[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" not in card_fn)',
         'and "[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" in card_fn)', 1),
        ('and "[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" not in cell_fn',
         'and "[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];" in cell_fn', 1),
        ('check("B9 引擎原语退役（Task177 重锚：透明度原语/声明/阴影层 alpha 全退；规格恒全不透明 shadowOpacity 1.0）",\n      "- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;" not in engine_h\n      and "ame_applyNeumorphCardOpacity:(CGFloat)opacity {" not in engine_m',
         'check("B9 引擎原语恢复（Task178 重锚：透明度原语/声明/承载视图 alpha 回归；shadowOpacity 1.0 规格不变）",\n      "- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;" in engine_h\n      and "ame_applyNeumorphCardOpacity:(CGFloat)opacity {" in engine_m', 1),
        ('check("C1 section0 四标题序（Task177 重锚：opacity 标题随滑条退役，开关为末项 sections[0][3]）",\n      \'localize(@"background.cards.neumorph.interface.title", nil)\' in bsvc\n      and "background.cards.neumorph.opacity.title" not in bsvc\n      and \'self.sections[0][3]; // background.cards.neumorph.interface.title\' in bsvc)',
         'check("C1 section0 五标题序（Task178 重锚：opacity 标题恢复为末项 sections[0][4]，开关 sections[0][3]）",\n      \'localize(@"background.cards.neumorph.interface.title", nil)\' in bsvc\n      and "background.cards.neumorph.opacity.title" in bsvc\n      and \'self.sections[0][3]; // background.cards.neumorph.interface.title\' in bsvc)', 1),
        ('check("C3 灰化反转：开关开启时旧选项行变灰关交互（Task177 重锚：滑条随行退役，灰化表达式维持 2 处）",\n      bsvc.count("cell.contentView.alpha = neumorphOn ? 0.35 : 1.0;") == 2\n      and bsvc.count("cell.userInteractionEnabled = !neumorphOn;") == 2\n      and "slider.enabled = neumorphOn;" not in bsvc\n      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" not in bsvc)',
         'check("C3 灰化退役（Task178 重锚：开关不管开还是关都不变灰——0.35 表达式与 neumorphOn 全退）",\n      bsvc.count("cell.contentView.alpha = neumorphOn ? 0.35 : 1.0;") == 0\n      and bsvc.count("cell.userInteractionEnabled = !neumorphOn;") == 0\n      and "neumorphOn" not in bsvc\n      and "slider.enabled = neumorphOn;" not in bsvc\n      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" not in bsvc)', 1),
        ('check("C4 开关行恒显（Task177 重锚：无壁纸时 section0 返回 1，滑条行号断言退役）",\n      "return 1;" in bsvc\n      and "indexPath.row == (hasBackground ? 3 : 0)" in bsvc\n      and "indexPath.row == (hasBackground ? 4 : 1)" not in bsvc)',
         'check("C4 开关行恒显 + 滑条行恢复（Task178 重锚：无壁纸时 section0 返回 2，滑条行号 (hasBackground ? 4 : 1) 回归）",\n      re.search(r"hasBackground\\]\\) \\{\\s*\\n\\s*return 2;", bsvc) is not None\n      and "indexPath.row == (hasBackground ? 3 : 0)" in bsvc\n      and "indexPath.row == (hasBackground ? 4 : 1)" in bsvc)', 1),
        ('check("D2 四主语言键集一致且计数 = 1954（净增 1）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1954',
         'check("D2 四主语言键集一致且计数 = 1955（Task178 重锚：opacity.title 键恢复）",\n      all(len(set(re.findall(r\'^"([^"]+)"\\s*=\', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1955', 1),
        ('check("D4 opacity 键随滑条退役（Task177 重锚：六语言全退，interface 开关键保留）",\n      all("background.cards.neumorph.opacity.title" not in\n          rd(f"Natives/resources/{lg}.lproj/Localizable.strings")\n          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"])',
         'check("D4 opacity 键随滑条恢复（Task178 重锚：六语言全在，interface 开关键保留）",\n      all("background.cards.neumorph.opacity.title" in\n          rd(f"Natives/resources/{lg}.lproj/Localizable.strings")\n          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"])', 1),
        ('check("E1 公告（Task177 重锚：task177@2 插入，task175/174 顺延 anns[3]/[4]，本条（新拟态 task173）顺延 anns[5]，十症状 task173@6；server/task169 pin 不动，172/171/170/168 顺延 anns[7]/[8]/[9]/[10]）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[3]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[4]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[5]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[6]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[7]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[8]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[9]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[10]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt173 = anns[5]',
         'check("E1 公告（Task178 重锚：task178@2 插入，task177/175/174 顺延 anns[3]/[4]/[5]，本条（新拟态 task173）顺延 anns[6]，十症状 task173@7；server/task169 pin 不动，172/171/170/168 顺延 anns[8]/[9]/[10]/[11]）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n      and anns[3]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[4]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[5]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[6]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[7]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[8]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[9]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[10]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[11]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt173 = anns[6]', 1),
    ]),
]

def apply_job(path, replacements):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    for old, new, expected in replacements:
        n = text.count(old)
        if n != expected:
            print(f"[FAIL] {path}: pattern matched {n}x (expect {expected}):\n  {old[:150]}...")
            return False
        text = text.replace(old, new)
    p.write_text(text, encoding="utf-8")
    print(f"[ok] {path}: {len(replacements)} replacement(s)")
    return True

ok = all(apply_job(path, reps) for path, reps in JOBS)
sys.exit(0 if ok else 1)
