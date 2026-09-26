#!/usr/bin/env python3
# Task178：l10n 恢复 background.cards.neumorph.opacity.title（Task177 曾删）。
# 插入位置 = 各语言 background.cards.neumorph.interface.title 行之后。
# 四主语言（en/zh-Hans/zh-CN/zh-Hant）计数 1954 -> 1955；ja/km 同步补键。
import sys, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = {
    "en":      "Neumorphism Opacity",
    "zh-Hans": "新拟态透明度",
    "zh-CN":   "新拟态透明度",
    "zh-Hant": "新擬態透明度",
    "ja":      "ニューモーフィズム透明度",
    "km":      "តម្លាភាព Neumorphism",
}
KEY = "background.cards.neumorph.opacity.title"
ANCHOR = "background.cards.neumorph.interface.title"

def count_keys(text: str) -> int:
    # 与历史校验器同口径：统计 "key" = "value" 行
    return len(re.findall(r'^\s*"[^"]+"\s*=\s*"', text, re.M))

ok = True
for lang, value in LANGS.items():
    p = ROOT / "Natives" / "resources" / f"{lang}.lproj" / "Localizable.strings"
    text = p.read_text(encoding="utf-8")
    if f'"{KEY}"' in text:
        print(f"[skip] {lang}: key already present")
        continue
    lines = text.splitlines(keepends=True)
    anchor_idx = None
    for i, ln in enumerate(lines):
        if f'"{ANCHOR}"' in ln:
            anchor_idx = i
            break
    if anchor_idx is None:
        print(f"[FAIL] {lang}: anchor {ANCHOR} not found"); ok = False; continue
    newline = f'"{KEY}" = "{value}";\n'
    lines.insert(anchor_idx + 1, newline)
    new_text = "".join(lines)
    p.write_text(new_text, encoding="utf-8")
    print(f"[ok] {lang}: inserted after line {anchor_idx+1}; count {count_keys(text)} -> {count_keys(new_text)}")

sys.exit(0 if ok else 1)
