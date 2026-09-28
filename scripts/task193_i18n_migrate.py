#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task193: i18n 迁移执行器。

1. 读 task193_i18n_strings.json（范围） + task193_i18n_dict.py（翻译 + 显式键）
2. 生成 ame193.<组>.<序号> 键（组：mp/ai/crash/misc）
3. 追加 en / zh-Hans / zh-Hant(opencc s2t) / ru 四表
4. 源码行内替换：@"<escaped>" -> localize(@"key", @"<escaped>")
   （只动收集到的行；NSLog/注释/localize 行不碰）
5. 幂等：重复运行时跳过已注册键。
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from task193_i18n_dict import T

from opencc import OpenCC
s2t = OpenCC("s2t")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRINGS_JSON = os.path.join(REPO, "scripts", "task193_i18n_strings.json")
TABLES = {
    "en": os.path.join(REPO, "Natives/resources/en.lproj/Localizable.strings"),
    "zh-Hans": os.path.join(REPO, "Natives/resources/zh-Hans.lproj/Localizable.strings"),
    "zh-Hant": os.path.join(REPO, "Natives/resources/zh-Hant.lproj/Localizable.strings"),
    "ru": os.path.join(REPO, "Natives/resources/ru.lproj/Localizable.strings"),
}

data = json.load(open(STRINGS_JSON, encoding="utf-8"))
assert set(data.keys()) == set(T.keys()), "dict/collect mismatch"

# ---- 组前缀 ----
def group_of(files):
    f = files[0]
    if "Multiplayer" in f:
        return "mp"
    if "/AI/" in f:
        return "ai"
    if "PLCrashView" in f:
        return "crash"
    return "misc"

# ---- 键分配 ----
key_of = {}
counters = {}
for text, jmeta in data.items():
    meta = T[text]
    if "key" in meta and meta["key"]:
        key_of[text] = meta["key"]   # 复用既有键（不新增表项）
        continue
    g = group_of(jmeta["files"])
    counters[g] = counters.get(g, 0) + 1
    key_of[text] = f"ame193.{g}.{counters[g]}"

# ---- 写表 ----
def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

new_entries = {lang: [] for lang in TABLES}
for text, jmeta in data.items():
    meta = T[text]   # 翻译来自词典（json 只有位置信息）
    key = key_of[text]
    if "key" in meta and meta["key"]:
        continue   # 既有键：四表已有
    zh = text
    hans_val = zh
    hant_val = s2t.convert(zh)
    en_val = meta["en"]
    ru_val = meta["ru"]
    new_entries["zh-Hans"].append(f'"{key}" = "{esc(hans_val)}";')
    new_entries["zh-Hant"].append(f'"{key}" = "{esc(hant_val)}";')
    new_entries["en"].append(f'"{key}" = "{esc(en_val)}";')
    new_entries["ru"].append(f'"{key}" = "{esc(ru_val)}";')

for lang, path in TABLES.items():
    content = open(path, encoding="utf-8").read()
    added = 0
    for e in new_entries[lang]:
        key = e.split('"')[1]
        if f'"{key}" =' in content:
            continue
        if not content.endswith("\n"):
            content += "\n"
        content += e + "\n"
        added += 1
    open(path, "w", encoding="utf-8").write(content)
    print(f"{lang}: +{added} entries")

# ---- 源码替换 ----
LITERAL = re.compile(r'@"((?:[^"\\]|\\.)*)"')
CJK = re.compile(r"[\u4e00-\u9fff]")
EXCLUDE = re.compile(r"NSLog|printf|LOGD|LOGE|LOGW|SHUT_LOGD|//|^\s*\*|^\s*#|fprintf|NSDebugLog|localize\s*\(")

total_repl = 0
files_touched = set()
for text, jmeta in data.items():
    key = key_of[text]
    for loc in jmeta["lines"]:
        rel, lineno = loc.rsplit(":", 1) if ":" in loc else (loc, None)
        # lines 形如 "Natives/Xxx.m:123"
        m = re.match(r"^(.*\.m):(\d+)$", loc)
        if not m:
            continue
        rel, lineno = m.group(1), int(m.group(2))
        path = os.path.join(REPO, rel)
        lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
        if lineno > len(lines):
            continue
        line = lines[lineno - 1]
        if EXCLUDE.search(line):
            continue
        target = '@"' + text + '"'
        if target not in line:
            continue
        new_line = line.replace(target, f'localize(@"{key}", @"{text}")')
        if new_line != line:
            lines[lineno - 1] = new_line
            open(path, "w", encoding="utf-8").write("".join(lines))
            total_repl += 1
            files_touched.add(rel)

print(f"source replacements: {total_repl} across {len(files_touched)} files")
for f in sorted(files_touched):
    print("  ", f)
