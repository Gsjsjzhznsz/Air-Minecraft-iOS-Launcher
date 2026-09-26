#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task178 重锚工具（阶段 3）：verify_task174 / 175 / 177 语义反转。
每个替换强制精确匹配 expected 次，任何偏差即中止退出。"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

JOBS = [
    # ---------- verify_task174 ----------
    ("scripts/verify_task174.py", [
        ('check("A5 柔和档挂载点退役（Task177 重锚：管线双点调用随透明度定稿消失）",\n      bm_m.count("ame_setNeumorphWallpaperSoft") == 0\n      and bm_m.count("ame_applyNeumorphCardOpacity") == 0)',
         'check("A5 卡片本体透明度挂载点恢复（Task178 重锚：柔和档仍退役，引擎原语两管线挂点回归）",\n      bm_m.count("ame_setNeumorphWallpaperSoft") == 0\n      and bm_m.count("ame_applyNeumorphCardOpacity") == 2)', 1),
        ('check("B1 滑条回调实时重写范式幸存（blur 行 viewWithTag:301；opacity 滑条整链退役）",\n      "viewWithTag:301" in blur_handler\n      and "viewWithTag:501" not in bsvc\n      and "cardsNeumorphOpacitySliderChanged" not in bsvc)',
         'check("B1 滑条回调实时回显恢复（Task178 重锚：opacity 行 viewWithTag:501 + 回调回归；blur 行 301 范式不变）",\n      "viewWithTag:301" in blur_handler\n      and "viewWithTag:501" in bsvc\n      and "cardsNeumorphOpacitySliderChanged" in bsvc)', 1),
        ('check("B4 既有刷新链不破坏（refreshUIEffect 仍在；透明度落盘链退役）",\n      "refreshUIEffect" in blur_handler\n      and ".cardsNeumorphOpacity = slider.value;" not in bsvc)',
         'check("B4 既有刷新链不破坏（Task178 重锚：refreshUIEffect 仍在；透明度落盘链恢复）",\n      "refreshUIEffect" in blur_handler\n      and ".cardsNeumorphOpacity = slider.value;" in bsvc)', 1),
        ('check("C2 灰化反转逻辑在位（Task177 重锚：旧选项 0.35 关交互两处；滑条启停表达式随行退役）",\n      bsvc.count("neumorphOn ? 0.35 : 1.0") == 2\n      and "slider.enabled = neumorphOn;" not in bsvc\n      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" not in bsvc)',
         'check("C2 灰化退役（Task178 重锚：开关不变灰任何选项——0.35/neumorphOn 全退，交互恒开）",\n      bsvc.count("neumorphOn ? 0.35 : 1.0") == 0\n      and "neumorphOn" not in bsvc\n      and "slider.enabled = neumorphOn;" not in bsvc\n      and "cell.contentView.alpha = neumorphOn ? 1.0 : 0.35;" not in bsvc)', 1),
        ('check("C4 卡片本体透明度原语退役（Task177 重锚：管线/引擎零残留，规格恒全不透明）",\n      bm_m.count("ame_applyNeumorphCardOpacity") == 0\n      and "ame_applyNeumorphCardOpacity" not in rd("Natives/UIKit+NativeSurface.m"))',
         'check("C4 卡片本体透明度原语恢复（Task178 重锚：管线双挂点 + 引擎原语在位）",\n      bm_m.count("ame_applyNeumorphCardOpacity") == 2\n      and "ame_applyNeumorphCardOpacity" in rd("Natives/UIKit+NativeSurface.m"))', 1),
        ('      all(len(k) == 1954 for k in KEYSETS) and KEYSETS[0] == KEYSETS[1] == KEYSETS[2] == KEYSETS[3])',
         '      all(len(k) == 1955 for k in KEYSETS) and KEYSETS[0] == KEYSETS[1] == KEYSETS[2] == KEYSETS[3])', 1),
        ('check("D2 开关键六语言在位（Task177 重锚：opacity.title 随滑条退役，interface.title 保留）",\n      "background.cards.neumorph.interface.title" in KEYSETS[0]\n      and "background.cards.neumorph.opacity.title" not in KEYSETS[0]',
         'check("D2 开关键六语言在位（Task178 重锚：opacity.title 恢复，interface.title 保留）",\n      "background.cards.neumorph.interface.title" in KEYSETS[0]\n      and "background.cards.neumorph.opacity.title" in KEYSETS[0]', 1),
        ('check("E1 公告（Task177 重锚：task177@2 插入，task175 顺延 anns[3]，本条（task174）顺延 anns[4]，双 task173 顺延 anns[5]/[6]，172/171/170/168 顺延 anns[7]/[8]/[9]/[10]；server/task169 pin 不动）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[3]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[4]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[5]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[6]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[7]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[8]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[9]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[10]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt174 = anns[4]',
         'check("E1 公告（Task178 重锚：task178@2 插入，task177/175 顺延 anns[3]/[4]，本条（task174）顺延 anns[5]，双 task173 顺延 anns[6]/[7]，172/171/170/168 顺延 anns[8]/[9]/[10]/[11]；server/task169 pin 不动）且 id 唯一",\n      len(ids) == len(set(ids))\n      and anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n      and anns[3]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[4]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[5]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[6]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and anns[7]["id"] == "task173-ten-fixes-2026-09-26"\n      and anns[8]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[9]["id"] == "task171-seven-fixes-2026-09-25"\n      and anns[10]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"\n      and anns[11]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt174 = anns[5]', 1),
    ]),

    # ---------- verify_task175 ----------
    ("scripts/verify_task175.py", [
        ('check("F2 refreshUIEffect ON 分支：容器缺席重建 + 双宿主原生底色 + blur 重挂 + 规格定稿日志（Task177 重锚）",\n      "if (self.cardsNeumorphEnabled) {" in rui\n      and "if ([self hasBackground] && !self.globalBackgroundContainer) {" in rui\n      and "ame177CoexistLogOnce" in rui\n      and "[Task177] neumorph UI spec rewrite" in rui\n      and "[self addBlurEffectToContainer:self.globalBackgroundContainer];" in rui)',
         'check("F2 refreshUIEffect ON 分支：容器缺席重建 + 双宿主原生底色 + blur 重挂 + 解耦定稿日志（Task178 重锚：日志锚演化）",\n      "if (self.cardsNeumorphEnabled) {" in rui\n      and "if ([self hasBackground] && !self.globalBackgroundContainer) {" in rui\n      and "ame178DecoupleLogOnce" in rui\n      and "[Task178] neumorph decoupled" in rui\n      and "[self addBlurEffectToContainer:self.globalBackgroundContainer];" in rui)', 1),
        ('check("G1 公告 task175@3（Task177 重锚：task177@2 插入；server/task169 pin 不动；174/双173/172/171/170/168 顺延 4-10）",\n      anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[3]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[4]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[7]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[10]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt175 = anns[3]',
         'check("G1 公告 task175@4（Task178 重锚：task178@2 插入；server/task169 pin 不动；177/174/双173/172/171/170/168 顺延 3-11）",\n      anns[0]["id"] == "server-recommend-2026-09-24"\n      and anns[1]["id"] == "task169-four-fixes-2026-09-25"\n      and anns[2]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n      and anns[3]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and anns[4]["id"] == "task175-six-fixes-2026-09-26"\n      and anns[5]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and anns[8]["id"] == "task172-six-fixes-2026-09-25"\n      and anns[11]["id"] == "task168-neumorph-faq-json-2026-09-25")\nt175 = anns[4]', 1),
        ('check("G4 l10n 零新增（Task177 重锚：neumorph.opacity.title 键退役后 1954）",\n      all(len(k) == 1954 for k in KEYSETS)',
         'check("G4 l10n 计数（Task178 重锚：neumorph.opacity.title 键恢复后 1955）",\n      all(len(k) == 1955 for k in KEYSETS)', 1),
    ]),

    # ---------- verify_task177 ----------
    ("scripts/verify_task177.py", [
        ('本轮定稿：\n  1) 引擎三层结构',
         'Task178 重锚（2026-09-26）：用户定稿转向——"只有那个透明度拉条可以改变\n  新拟态的透明度，字体始终是不透明的；开关不管咋样都不会使其他选项变灰"。\
  卡片本体透明度滑条/引擎原语/落盘键恢复（适配 Task177 三层引擎：承载视图\n  整体 alpha），灰化全退，新闻卡圆角钉住 12pt；四主语言 1955。\n\n本轮定稿（Task177 历史口径）：\n  1) 引擎三层结构', 1),
        ('check("A10 退役原语零残留（attachShadowOnly/wallpaperSoft/cardOpacity 三 API 全仓 Natives 无代码调用）",\n      all(pat not in ENG_M and pat not in ENG_H and pat not in BM_M and pat not in BM_H and pat not in SET_M\n          for pat in ("ame_attachNeumorphShadowOnly", "ame_setNeumorphWallpaperSoft:",\n                      "ame_applyNeumorphCardOpacity", "ame_wallpaperSoftProfile")))',
         'check("A10 原语去留（Task178 重锚：attachShadowOnly/wallpaperSoft 仍退役；cardOpacity 恢复——头声明+引擎实现+Manager 挂点）",\n      all(pat not in ENG_M and pat not in ENG_H and pat not in BM_M and pat not in BM_H and pat not in SET_M\n          for pat in ("ame_attachNeumorphShadowOnly", "ame_setNeumorphWallpaperSoft:", "ame_wallpaperSoftProfile"))\n      and "ame_applyNeumorphCardOpacity" in ENG_H and "ame_applyNeumorphCardOpacity" in ENG_M\n      and "ame_applyNeumorphCardOpacity" in BM_M)', 1),
        ('check("B1 cardsNeumorphOpacity 属性/存取器退役（.h 无声明，.m 无 getter/setter）",\n      "CGFloat cardsNeumorphOpacity" not in BM_H\n      and "- (CGFloat)cardsNeumorphOpacity" not in BM_M\n      and "self.cardsNeumorphOpacity" not in BM_M)',
         'check("B1 cardsNeumorphOpacity 属性/存取器恢复（Task178 重锚：.h 声明 + .m getter/setter + 管线读取）",\n      "CGFloat cardsNeumorphOpacity" in BM_H\n      and "- (CGFloat)cardsNeumorphOpacity" in BM_M\n      and "self.cardsNeumorphOpacity" in BM_M)', 1),
        ('check("B2 透明度落盘键不再读取（kBackgroundCardsNeumorphOpacityKey 常量删除）",\n      "kBackgroundCardsNeumorphOpacityKey" not in BM_M)',
         'check("B2 透明度落盘键恢复（Task178 重锚：kBackgroundCardsNeumorphOpacityKey 常量在位）",\n      "kBackgroundCardsNeumorphOpacityKey" in BM_M)', 1),
        ('check("B7 Task177 一次性日志锚（[Task177] neumorph UI spec rewrite）",\n      "[Task177] neumorph UI spec rewrite" in BM_M)',
         'check("B7 Task178 一次性日志锚（[Task178] neumorph decoupled）",\n      "[Task178] neumorph decoupled" in BM_M)', 1),
        ('check("B8 头文件定稿注释（不读任何透明度/模糊偏好）",\n      "不读任何透明度/模糊偏好" in BM_H)',
         'check("B8 头文件定稿注释（Task178 重锚：卡体透明度唯一入口 = 本偏好）",\n      "入口 = 本偏好" in BM_H)', 1),
        ('check("C1 透明度滑条行整体删除（CellsNeumorphOpacityCell/滑条块零残留）",\n      "CardsNeumorphOpacityCell" not in SET_M\n      and "cardsNeumorphOpacitySliderChanged" not in SET_M)',
         'check("C1 透明度滑条行恢复（Task178 重锚：CellsNeumorphOpacityCell/滑条块/回调在位）",\n      "CardsNeumorphOpacityCell" in SET_M\n      and "cardsNeumorphOpacitySliderChanged" in SET_M)', 1),
        ('check("C2 滑条 tags 500/501/502 退役（无残留 viewWithTag/target 绑定）",\n      "viewWithTag:500" not in SET_M and "viewWithTag:501" not in SET_M\n      and "viewWithTag:502" not in SET_M)',
         'check("C2 滑条 tags 500/501/502 恢复（Task178 重锚：viewWithTag 绑定在位）",\n      "viewWithTag:500" in SET_M and "viewWithTag:501" in SET_M\n      and "viewWithTag:502" in SET_M)', 1),
        ('check("C5 灰化逻辑保留（其余 UI 效果选项 neumorphOn ? 0.35 : 1.0 ×2 行）",\n      SET_M.count("neumorphOn ? 0.35 : 1.0") == 2)',
         'check("C5 灰化退役（Task178 重锚：开关不再变灰其他选项——0.35/neumorphOn 零残留）",\n      SET_M.count("neumorphOn ? 0.35 : 1.0") == 0\n      and "neumorphOn" not in SET_M)', 1),
        ('check("C6 sections[0] 四项（透明度标题条目删除）",\n      \'localize(@"background.cards.neumorph.interface.title", nil)\' in SET_M\n      and \'localize(@"background.cards.neumorph.opacity.title", nil)\' not in SET_M)',
         'check("C6 sections[0] 五项（Task178 重锚：透明度标题条目恢复为末项）",\n      \'localize(@"background.cards.neumorph.interface.title", nil)\' in SET_M\n      and \'localize(@"background.cards.neumorph.opacity.title", nil)\' in SET_M)', 1),
        ('check("C7 无壁纸行数 1（仅开关行；旧值 2 随滑条退役）",\n      re.search(r"hasBackground\\]\\) \\{\\s*\\n\\s*return 1;", SET_M) is not None\n      and not re.search(r"hasBackground\\]\\) \\{\\s*\\n\\s*return 2;", SET_M))',
         'check("C7 无壁纸行数 2（Task178 重锚：开关行 + 透明度滑条行恒显）",\n      re.search(r"hasBackground\\]\\) \\{\\s*\\n\\s*return 2;", SET_M) is not None\n      and not re.search(r"hasBackground\\]\\) \\{\\s*\\n\\s*return 1;", SET_M))', 1),
        ('check("D1 opacity.title 键 ×6 语言全部删除",\n      all(\'"background.cards.neumorph.opacity.title"\' not in t for t in all_six))',
         'check("D1 opacity.title 键 ×6 语言全部恢复（Task178 重锚）",\n      all(\'"background.cards.neumorph.opacity.title"\' in t for t in all_six))', 1),
        ('check("D2 四主语言唯一键计数 1954（1955-1）",\n      all(len(k) == 1954 for k in KEYSETS),',
         'check("D2 四主语言唯一键计数 1955（Task178 重锚：1954+1）",\n      all(len(k) == 1955 for k in KEYSETS),', 1),
        ('check("E1 公告 task177 插入 index 2（server/169 钉 0/1 不动）",\n      len(ann) == 19\n      and ann[0]["id"] == "server-recommend-2026-09-24"\n      and ann[1]["id"] == "task169-four-fixes-2026-09-25"\n      and ann[2]["id"] == "task177-neumorph-css-spec-2026-09-26")',
         'check("E1 公告 task178 插入 index 2（Task178 重锚：server/169 钉 0/1 不动）",\n      len(ann) == 20\n      and ann[0]["id"] == "server-recommend-2026-09-24"\n      and ann[1]["id"] == "task169-four-fixes-2026-09-25"\n      and ann[2]["id"] == "task178-neumorph-decouple-opacity-2026-09-26")', 1),
        ('check("E2 公告后续顺序整体 +1（175→3 / 174→4 / 173 新拟态→5 / 173 十连修→6）",\n      ann[3]["id"] == "task175-six-fixes-2026-09-26"\n      and ann[4]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and ann[5]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and ann[6]["id"] == "task173-ten-fixes-2026-09-26")',
         'check("E2 公告后续顺序整体 +1（Task178 重锚：177→3 / 175→4 / 174→5 / 173 新拟态→6 / 173 十连修→7）",\n      ann[3]["id"] == "task177-neumorph-css-spec-2026-09-26"\n      and ann[4]["id"] == "task175-six-fixes-2026-09-26"\n      and ann[5]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n      and ann[6]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n      and ann[7]["id"] == "task173-ten-fixes-2026-09-26")', 1),
        ('check("E3 公告内容锚（CSS 参考/全不透明/滑条退役三关键词）",\n      "bigbear-ui" in ann[2]["content"] and "neu-white" in ann[2]["content"]\n      and "不要加任何的透明度" in ann[2]["summary"])',
         'check("E3 公告内容锚（Task178 重锚：task177 内容锚随条目顺延至 ann[3]）",\n      "bigbear-ui" in ann[3]["content"] and "neu-white" in ann[3]["content"]\n      and "不要加任何的透明度" in ann[3]["summary"])', 1),
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
