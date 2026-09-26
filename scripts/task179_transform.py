#!/usr/bin/env python3
"""Task179: transform tinygl4angle.c into harness-compilable plain C.
ObjC blocks (dispatch_once + NSArray literals) in ame173_forensics /
ame173_log_once are stubbed; everything else is verbatim."""
import re, sys, os, os

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Natives/external/gl4es/tinygl4angle.c")
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "task179_inc/tinygl4angle_harness.c")

src = open(SRC).read()

# 1) import -> include
src = src.replace("#import <Foundation/Foundation.h>", "#include <Foundation/Foundation.h>")

# 2) stub ame173_forensics body (the dispatch_once + NSArray block)
pat_forensics = re.compile(
    r"(static void ame173_forensics\(void\) \{).*?(\n\}\n)", re.S)
src, n1 = pat_forensics.subn(r"\1\n    (void)0; /* harness: forensics stubbed */\n\2", src)

# 3) stub ame173_log_once body
pat_logonce = re.compile(
    r"(static void ame173_log_once\(const char \*fn\) \{).*?(\n\}\n)", re.S)
src, n2 = pat_logonce.subn(r"\1\n    (void)fn; /* harness: log stubbed */\n\2", src)

assert n1 == 1, f"forensics stub count {n1}"
assert n2 == 1, f"log_once stub count {n2}"


# 4) neutralize ARM64 AliasDecl asm (x86-64 harness can't assemble `b _sym`)
src = src.replace(
    '''#define AliasDecl(NAME, EXT) \\
    asm(".global _"# NAME "\\n_" #NAME ": b _" #NAME #EXT);''',
    '''#define AliasDecl(NAME, EXT)''')
src = src.replace(
    '''#define AliasDeclPriv(NAME) \\
    asm(".global _gl"# NAME "\\n_gl" #NAME ": b _GL_" #NAME);''',
    '''#define AliasDeclPriv(NAME)''')
assert "#define AliasDecl(NAME, EXT)" in src, "alias neutralization failed"

os.makedirs(os.path.dirname(DST), exist_ok=True)
open(DST, "w").write(src)
print(f"transformed -> {DST} (forensics={n1}, log_once={n2})")
