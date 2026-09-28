#!/usr/bin/env bash
# Task193: tinygl4angle.c 真源码语法门。
# 真文件含 Apple 方言（#import / ObjC 块 / arm64 内联 asm 别名宏）——Linux gcc
# 无法直接编译。本门做三处【仅语法门内】的机械变换后编译其余全部代码：
#   1) #import → #include
#   2) ame173_forensics / ame173_log_once 函数体 → no-op（ObjC 块/字面量）
#   3) AliasDecl / AliasDeclPriv 宏定义 → 空宏（arm64 b 别名 asm）
# 其余代码（含 ame193 全部增量）逐字编译验证。真机构建不受本门影响。
set -e
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPTS")"
SRC="$REPO/Natives/external/gl4es/tinygl4angle.c"
TMPD="$(mktemp -d)"
TMP="$TMPD/tinygl4angle_real.c"

python3 - "$SRC" "$TMP" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
text = text.replace("#import ", "#include ", 1)

pat = re.compile(r"static void ame173_forensics\(void\) \{.*?\n\}", re.S)
m = pat.search(text)
assert m, "ame173_forensics not found"
text = text[:m.start()] + "static void ame173_forensics(void) { (void)0; /* task193 gate: ObjC stubbed */ }" + text[m.end():]
print("forensics stubbed:", len(m.group(0)))

pat2 = re.compile(r"static void ame173_log_once\(const char \*fn\) \{.*?\n\}", re.S)
m2 = pat2.search(text)
assert m2, "ame173_log_once not found"
text = text[:m2.start()] + "static void ame173_log_once(const char *fn) { (void)fn; /* task193 gate: ObjC stubbed */ }" + text[m2.end():]
print("log_once stubbed:", len(m2.group(0)))

stripped = 0
pat3 = re.compile(r'#define AliasDecl\(NAME, EXT\) \\\n\s*asm\(.*?\);')
if pat3.search(text):
    text = pat3.sub("#define AliasDecl(NAME, EXT)", text)
    stripped += 1
pat4 = re.compile(r'#define AliasDeclPriv\(NAME\) \\\n\s*asm\(.*?\);')
if pat4.search(text):
    text = pat4.sub("#define AliasDeclPriv(NAME)", text)
    stripped += 1
print("alias macros stripped:", stripped)
assert stripped == 2, "AliasDecl macros not fully stripped"

open(dst, "w", encoding="utf-8").write(text)
PYEOF

set +e
GCCOUT=$(gcc -I "$SCRIPTS/task179_inc" -c "$TMP" -o "$TMPD/tinygl4angle_real.o" -Wall -Wno-unused-variable -Wno-unused-function 2>&1)
GCCRC=$?
echo "$GCCOUT" | head -40
if [ $GCCRC -ne 0 ]; then
    echo "SYNTAX FAIL: tinygl4angle.c compile errors (rc=$GCCRC)"
    exit 1
fi
if echo "$GCCOUT" | grep -q "error:"; then
    echo "SYNTAX FAIL: error lines present despite rc=0"
    exit 1
fi
echo "SYNTAX OK: tinygl4angle.c compiled clean (task193 gate)"
