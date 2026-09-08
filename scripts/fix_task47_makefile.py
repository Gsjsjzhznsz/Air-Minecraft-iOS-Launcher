#!/usr/bin/env python3
# fix_task47_makefile.py — 字节级补丁：把 shaderc_include.c 加进 libshaderc.dylib
# 的源列表（保持 TAB 缩进，不动其它任何字节——Edit 工具会把全文 tab 规范化
# 成空格，破坏 make recipe 语法，故用字节级操作）。
import sys

PATH = "/home/z/my-project/Amethyst-iOS-MyRemastered/Makefile"
OLD = b"$(SOURCEDIR)/Natives/shaderc_shim.c \\\n\t\t$(SOURCEDIR)/Natives/shaderc_sandbox.m || exit 1\n"
NEW = b"$(SOURCEDIR)/Natives/shaderc_shim.c \\\n\t\t$(SOURCEDIR)/Natives/shaderc_include.c \\\n\t\t$(SOURCEDIR)/Natives/shaderc_sandbox.m || exit 1\n"

with open(PATH, "rb") as f:
    data = f.read()

if NEW in data:
    print("already patched (idempotent)")
    sys.exit(0)
count = data.count(OLD)
if count != 1:
    print(f"FATAL: anchor found {count} times (expected 1) — aborting")
    sys.exit(1)

data = data.replace(OLD, NEW, 1)
with open(PATH, "wb") as f:
    f.write(data)
print("patched: shaderc_include.c added to libshaderc.dylib sources (TAB preserved)")
