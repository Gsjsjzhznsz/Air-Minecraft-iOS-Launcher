#!/usr/bin/env python3
"""Task106 stale-sync: FAQ 计数锚点 33 -> 34（+sparkProfiler）跨 13 个校验器
+ verify_task105 E2 重锚（Task105 负载判读句被 Task106 判读修正取代）
+ verify_task103 F1 标签同步。遵循 task103_faq_sync.py 同款机械替换约定。"""
import io

EDITS = [
    ('scripts/verify_task83.py', [
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task84.py', [
        ('D1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task85 时为 24）',
         'D1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task106 +sparkProfiler，Task85 时为 24）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task85.py', [
        ('C1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task85 时为 24）',
         'C1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task106 +sparkProfiler，Task85 时为 24）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task86.py', [
        ('C1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +1，Task87 +1，Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1）',
         'C1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +1，Task87 +1，Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1，Task106 +1）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task87.py', [
        ('E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl）',
         'E1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task106 +sparkProfiler）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task94.py', [
        ('E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1）',
         'E1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1，Task106 +1）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task95.py', [
        ('E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl）',
         'E1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task106 +sparkProfiler）'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
        ('计数已 sync 33', '计数已 sync 34'),
    ]),
    ('scripts/verify_task97.py', [
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task98.py', [
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task99.py', [
        ('len(items) == 33', 'len(items) == 34'),
        ('E1 FAQ 33 条目', 'E1 FAQ 34 条目'),
        ('计数已 sync 33', '计数已 sync 34'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task100.py', [
        ('len(items) == 33', 'len(items) == 34'),
        ('len(faq_items) == 33', 'len(faq_items) == 34'),
    ]),
    ('scripts/verify_task103.py', [
        ('F. FAQ 33 条目 + version.h 附录', 'F. FAQ 34 条目 + version.h 附录'),
        ("check('F1 FAQ 33 条目（Task100 32 + Task103 sodiumGlsl）', len(items) == 33, f'got {len(items)}')",
         "check('F1 FAQ 34 条目（Task103 33 + Task106 sparkProfiler）', len(items) == 34, f'got {len(items)}')"),
    ]),
    ('scripts/verify_task105.py', [
        # E2 重锚：Task105 的“视距 32→16 恢复 44+”判读被 Task106 修正（44 实为暂停菜单
        # 瞬时读数；preset 1.3x 与 2.0x 同帧率实锤呈现常数主导）。新锚 = Task106 判读句。
        ("check('E2 fpsUnlock 补负载判读实证（视距 32→16 的 fps 恢复）',\n"
         "      '实测（Task105 判读）视距 32' in faq and '重整合包建议视距 ≤16' in faq)",
         "check('E2 fpsUnlock 负载判读（Task106 修正：呈现常数 + bundle-direct + 相位计时）',\n"
         "      'Task106 判读修正' in faq and '重整合包建议视距 ≤16' in faq and 'bundle-direct present engaged' in faq)"),
    ]),
]

for path, pairs in EDITS:
    s = io.open(path, encoding='utf-8').read()
    orig = s
    for old, new in pairs:
        s = s.replace(old, new)
    if s != orig:
        io.open(path, 'w', encoding='utf-8').write(s)
        print(f'{path}: updated')
    else:
        print(f'{path}: NO CHANGE (manual check needed)')
