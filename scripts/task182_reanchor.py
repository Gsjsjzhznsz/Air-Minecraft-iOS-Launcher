#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task182 公告锚移位重锚：task180@2 插入后，四个下游验证器的非钉位索引全体 +1。
当前实际（announcements.json）：[2]=180 [3]=179 [4]=178 [5]=177 [6]=175 [7]=174
[8]=toggle173 [9]=ten173 [10]=172 [11]=171 [12]=170 [13]=168
"""
import re

BASE = "/home/z/my-project/Amethyst-iOS-MyRemastered/scripts/"

# 每个文件: (锚段定位串, 替换规则列表[(旧行, 新行)], 附加裸索引替换)
JOBS = {
    "verify_task170.py": {
        "old_block": '''      and anns[3]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[4]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[5]["id"] == "task175-six-fixes-2026-09-26"
      and anns[6]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[7]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[8]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[9]["id"] == "task172-six-fixes-2026-09-25"
      and anns[10]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[11]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[12]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "new_block": '''      and anns[3]["id"] == "task179-eight-fixes-2026-09-26"
      and anns[4]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[5]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[6]["id"] == "task175-six-fixes-2026-09-26"
      and anns[7]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[8]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[9]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[10]["id"] == "task172-six-fixes-2026-09-25"
      and anns[11]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[12]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[13]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "title_old": 'check("F1 公告（Task178 重锚：task178@2 插入，task177/175/174 顺延 anns[4]/[4]/[5]，双 task173 顺延 anns[7]/[7]，task172/171/170/168 顺延 anns[9]/[9]/[10]/[11]；anns[1] task169 pin 不动）且 id 唯一",',
        "title_new": 'check("F1 公告（Task182 重锚：task180@2 插入后全体非钉位 +1；179@3、178@4、177@5、175@6、174@7、toggle173@8、ten173@9、172@10、171@11、170@12、168@13；anns[1] task169 pin 不动）且 id 唯一",',
        "bare": [("t170 = anns[11]", "t170 = anns[12]")],
    },
    "verify_task171.py": {
        "old_block": '''      anns[10]["id"] == "task171-seven-fixes-2026-09-25"''',
        "new_block": '''      anns[11]["id"] == "task171-seven-fixes-2026-09-25"''',
        "title_old": 'check("D2 公告（Task178 重锚）：task171 在 index 9（task178/177/175/174/双 task173/172 相继插入后）；置顶服务器推荐仍在 anns[0]；task169 仍在 anns[1]",',
        "title_new": 'check("D2 公告（Task182 重锚：task180@2 插入后 +1）：task171 在 index 11；置顶服务器推荐仍在 anns[0]；task169 仍在 anns[1]",',
        "bare": [('anns[10]["content"]', 'anns[11]["content"]')],
    },
    "verify_task174.py": {
        "old_block": '''      and anns[3]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[4]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[5]["id"] == "task175-six-fixes-2026-09-26"
      and anns[6]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[7]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[8]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[9]["id"] == "task172-six-fixes-2026-09-25"
      and anns[10]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[11]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[12]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "new_block": '''      and anns[3]["id"] == "task179-eight-fixes-2026-09-26"
      and anns[4]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[5]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[6]["id"] == "task175-six-fixes-2026-09-26"
      and anns[7]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[8]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[9]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[10]["id"] == "task172-six-fixes-2026-09-25"
      and anns[11]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[12]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[13]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "title_old": 'check("E1 公告（Task178 重锚：task178@2 插入，task177/175 顺延 anns[4]/[4]，本条（task174）顺延 anns[6]，双 task173 顺延 anns[7]/[7]，172/171/170/168 顺延 anns[9]/[9]/[10]/[11]；server/task169 pin 不动）且 id 唯一",',
        "title_new": 'check("E1 公告（Task182 重锚：task180@2 插入后全体非钉位 +1；本条（task174）顺延 anns[7]；server/task169 pin 不动）且 id 唯一",',
        "bare": [("t174 = anns[6]", "t174 = anns[7]")],
    },
    "verify_task173b_neumorph.py": {
        "old_block": '''      and anns[3]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[4]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[5]["id"] == "task175-six-fixes-2026-09-26"
      and anns[6]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[7]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[8]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[9]["id"] == "task172-six-fixes-2026-09-25"
      and anns[10]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[11]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[12]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "new_block": '''      and anns[3]["id"] == "task179-eight-fixes-2026-09-26"
      and anns[4]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"
      and anns[5]["id"] == "task177-neumorph-css-spec-2026-09-26"
      and anns[6]["id"] == "task175-six-fixes-2026-09-26"
      and anns[7]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"
      and anns[8]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"
      and anns[9]["id"] == "task173-ten-fixes-2026-09-26"
      and anns[10]["id"] == "task172-six-fixes-2026-09-25"
      and anns[11]["id"] == "task171-seven-fixes-2026-09-25"
      and anns[12]["id"] == "task170-neumorph-opacity-spacing-2026-09-25"
      and anns[13]["id"] == "task168-neumorph-faq-json-2026-09-25")''',
        "title_old": 'check("E1 公告（Task178 重锚：task178@2 插入，task177/175/174 顺延 anns[4]/[4]/[5]，本条（新拟态 task173）顺延 anns[7]，十症状 task173@7；server/task169 pin 不动，172/171/170/168 顺延 anns[9]/[9]/[10]/[11]）且 id 唯一",',
        "title_new": 'check("E1 公告（Task182 重锚：task180@2 插入后全体非钉位 +1；本条（新拟态 task173）顺延 anns[8]；server/task169 pin 不动）且 id 唯一",',
        "bare": [("t173 = anns[7]", "t173 = anns[8]")],
    },
}

for fname, job in JOBS.items():
    p = BASE + fname
    s = open(p, encoding="utf-8").read()
    for old, new in [(job["old_block"], job["new_block"]),
                     (job["title_old"], job["title_new"])] + job["bare"]:
        if old not in s:
            print(f"[{fname}] MISS: {old[:60]}...")
            continue
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
    print(f"[{fname}] re-anchored")
