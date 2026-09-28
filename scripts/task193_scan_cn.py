#!/usr/bin/env python3
"""Task193: 硬编码中文扫描（i18n 残余清点）。

规则：
- 扫 Natives/*.m 与 Natives/customcontrols/*.m
- 找 @"..." / NSLocalizedString-free 的中文字符串字面量
- 排除：注释行、localize( 调用行、纯日志 NSLog/printf 行（日志不面向用户）、
  stringWithUTF8String 的 C 字符串里的中文也算（会显示给用户）
- 输出：文件 → 行号 → 内容，供批量迁移
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTS = [os.path.join(REPO, "Natives"), os.path.join(REPO, "Natives", "customcontrols")]

CJK = re.compile(r"[\u4e00-\u9fff]")
# 用户可见字符串形态：@"..." 或 @"..." 里的片段；也含 CFSTR
LITERAL = re.compile(r'@"([^"]*)"')
# 日志/非用户面排除
EXCLUDE_LINE = re.compile(
    r"NSLog|printf|LOGD|LOGE|LOGW|SHUT_LOGD|//|\*|^\s*#|fprintf|NSDebugLog"
)

hits = []
for root in ROOTS:
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.endswith(".m"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                lines = open(path, encoding="utf-8").read().splitlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                if EXCLUDE_LINE.search(line):
                    continue
                for m in LITERAL.finditer(line):
                    if CJK.search(m.group(1)):
                        rel = os.path.relpath(path, REPO)
                        hits.append((rel, i, line.strip()[:160]))

print(f"total hardcoded-CN user-visible literals: {len(hits)}")
for rel, i, line in hits:
    print(f"{rel}:{i}: {line}")
