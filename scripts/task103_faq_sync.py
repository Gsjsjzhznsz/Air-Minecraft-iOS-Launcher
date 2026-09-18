#!/usr/bin/env python3
"""Task103 stale-sync: FAQ 计数锚点 32 -> 33（+sodiumGlsl）跨 11 个校验器"""
import io

# (file, [(old, new), ...])
EDITS = [
    ('scripts/verify_task83.py', [
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
        ('FAQ 32', 'FAQ 33'),
    ]),
    ('scripts/verify_task84.py', [
        ('D1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task85 时为 24）',
         'D1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task85 时为 24）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task85.py', [
        ('C1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task85 时为 24）',
         'C1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task85 时为 24）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task86.py', [
        ('C1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +1，Task87 +1，Task94 +1，Task95 +1，Task97 +1，Task98 +1）',
         'C1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +1，Task87 +1，Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task87.py', [
        ('E1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl）',
         'E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task94.py', [
        ('E1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task94 +1，Task95 +1，Task97 +1，Task98 +1）',
         'E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task94 +1，Task95 +1，Task97 +1，Task98 +1，Task103 +1）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task95.py', [
        ('E1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl）',
         'E1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl）'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
        ('计数已 sync 32', '计数已 sync 33'),
    ]),
    ('scripts/verify_task97.py', [
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task98.py', [
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task99.py', [
        ('len(items) == 32', 'len(items) == 33'),
        ('E1 FAQ 32 条目', 'E1 FAQ 33 条目'),
        ('计数已 sync 32', '计数已 sync 33'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
    ]),
    ('scripts/verify_task100.py', [
        ('len(items) == 32', 'len(items) == 33'),
        ('len(faq_items) == 32', 'len(faq_items) == 33'),
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
