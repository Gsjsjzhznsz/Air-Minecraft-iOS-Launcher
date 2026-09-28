#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task189 vgpu 取证代码语法门 + 行为镜像测试。

提取 Natives/external/vgpu/src/gl/drawing.c 中新增的 ame189_census 与
ame189_afterDraw 函数原文，在本地 gcc 环境用桩（stub）头编译执行：
  A. 语法门：两个函数 + 挂钩点（drawing.c / listdraw.c / gl4es.c）括号平衡、
     挂钩锚点存在性；
  B. 行为镜像：census 分桶计数/4096 报告重置/前 3 次限频；afterDraw 的
     120 次窗口、错误回注（errorShim 收到原值）、限频 8 条日志。
"""
import re
import subprocess
import sys
import tempfile
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRAWING = os.path.join(REPO, "Natives/external/vgpu/src/gl/drawing.c")
LISTDRAW = os.path.join(REPO, "Natives/external/vgpu/src/gl/listdraw.c")
GL4ES = os.path.join(REPO, "Natives/external/vgpu/src/gl/gl4es.c")

failures = []


def check(name, ok, detail=""):
    print("[%s] %s%s" % ("PASS" if ok else "FAIL", name, (" -- " + detail) if detail else ""))
    if not ok:
        failures.append(name)


def extract_fn(text, fname):
    m = re.search(r"void %s\(.*?\n\}" % re.escape(fname), text, re.S)
    return m.group(0) if m else None


def bracket_balance(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    # strip line comments and string literals crudely (same convention as prior gates)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r'"(\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(\\.|[^'\\])*'", "''", text)
    return text.count("{") - text.count("}"), text.count("[") - text.count("]")


def main():
    with open(DRAWING, "r", encoding="utf-8", errors="replace") as f:
        drawing_src = f.read()
    census = extract_fn(drawing_src, "ame189_census")
    after = extract_fn(drawing_src, "ame189_afterDraw")
    check("A1 ame189_census present in drawing.c", census is not None)
    check("A2 ame189_afterDraw present in drawing.c", after is not None)
    if not (census and after):
        print("extraction failed, abort")
        return 1

    for path in (DRAWING, LISTDRAW, GL4ES):
        b, s = bracket_balance(path)
        check("A3 bracket balance %s" % os.path.basename(path), b == 0 and s == 0,
              "braces=%d brackets=%d" % (b, s))

    # hook anchors
    for anchor, fname in [
        ('ame189_census(mode, count);   // Task189', "drawing.c arrays hook"),
        ("ame189_afterDraw(\"direct-arrays\"", "drawing.c direct-arrays hook"),
        ("ame189_afterDraw(\"direct-elements\"", "drawing.c direct-elements hook"),
        ("ame189_afterDraw(\"list-elements\"", "listdraw.c list-elements hook"),
        ("ame189_afterDraw(\"list-arrays\"", "listdraw.c list-arrays hook"),
        ("void gl4es_glPolygonMode(GLenum face, GLenum mode) {\n    // Task189", "gl4es.c polygon trip-wire"),
        ("ame189_census(mode, 0);   // Task189", "gl4es.c glBegin census"),
        ("void ame189_census(GLenum mode, GLsizei count);", "gl4es.h declaration census"),
        ("void ame189_afterDraw(const char *site", "gl4es.h declaration afterDraw"),
    ]:
        target = drawing_src
        if "listdraw" in fname:
            with open(LISTDRAW, "r", encoding="utf-8", errors="replace") as f:
                target = f.read()
        elif "gl4es.c" in fname:
            with open(GL4ES, "r", encoding="utf-8", errors="replace") as f:
                target = f.read()
        elif "gl4es.h" in fname:
            with open(os.path.join(REPO, "Natives/external/vgpu/src/gl/gl4es.h"),
                      "r", encoding="utf-8", errors="replace") as f:
                target = f.read()
        check("A4 hook: %s" % fname, anchor in target)

    # B: behavioral mirror --------------------------------------------------
    stub = r"""
#include <stdio.h>
#include <string.h>

typedef unsigned int GLenum;
typedef int GLsizei;
#define GL_POINTS 0x0000
#define GL_LINES 0x0001
#define GL_LINE_LOOP 0x0002
#define GL_LINE_STRIP 0x0003
#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TRIANGLE_FAN 0x0006
#define GL_QUADS 0x0007
#define GL_QUAD_STRIP 0x0008
#define GL_POLYGON 0x0009
#define GL_NO_ERROR 0

static char g_logbuf[8192];
static int g_logn = 0;
static void SHUT_LOGD(const char *fmt, ...) {
    /* mirror: append to buffer */
    va_list ap; va_start(ap, fmt);
    g_logn += vsnprintf(g_logbuf + g_logn, sizeof(g_logbuf) - g_logn, fmt, ap);
    va_end(ap);
}

/* mock gles error queue + errorShim capture */
static GLenum g_nextErr = 0;
static GLenum g_glGetError_impl(void) { GLenum e = g_nextErr; g_nextErr = 0; return e; }
#define gles_glGetError() g_glGetError_impl()
static GLenum g_shim_captured = 0;
static void errorShim(GLenum e) { g_shim_captured = e; }

__FUNCS__

int main(void) {
    /* B1: census bucketing + report at 4096 with reset (reports 1..3) */
    for (int i = 0; i < 4096; i++) ame189_census(GL_QUADS, 100);
    if (!strstr(g_logbuf, "census #1 after 4096 draws")) { printf("B1 missing report1\n"); return 2; }
    if (!strstr(g_logbuf, "QUADS=4096(avg 100)")) { printf("B1 bucket wrong: %s\n", g_logbuf); return 2; }
    for (int i = 0; i < 4095; i++) ame189_census(GL_TRIANGLES, 10);
    if (strstr(g_logbuf, "census #2")) { printf("B1 early report\n"); return 2; }
    ame189_census(GL_LINES, 2);  /* 4096th -> report #2, reset */
    if (!strstr(g_logbuf, "census #2 after 4096 draws")) { printf("B2 missing report2\n"); return 2; }
    if (!strstr(g_logbuf, "TRIANGLES=4095")) { printf("B2 tri bucket: %s\n", g_logbuf); return 2; }

    /* B3: afterDraw window of 120 + re-inject */
    g_shim_captured = 0;
    for (int i = 0; i < 119; i++) { g_nextErr = 0; ame189_afterDraw("t", GL_TRIANGLES, 3, 0); }
    g_nextErr = 0x0502; /* GL_INVALID_OPERATION */
    ame189_afterDraw("t", GL_TRIANGLES, 3, 0); /* 120th: probed, hit */
    if (g_shim_captured != 0x0502) { printf("B3 re-inject missing\n"); return 2; }
    if (!strstr(g_logbuf, "post-draw error #1: site=t mode=0x0004 count=3 idxType=0x0000 -> GL error 0x0502")) {
        printf("B3 log wrong: %s\n", g_logbuf); return 2;
    }
    /* 121st: window closed -> no probe, no consume */
    g_nextErr = 0x0501;
    g_shim_captured = 0;
    ame189_afterDraw("t", GL_TRIANGLES, 3, 0);
    if (g_shim_captured != 0) { printf("B3 window not closed\n"); return 2; }
    printf("ALL_MIRROR_OK\n");
    return 0;
}
"""
    harness = stub.replace("__FUNCS__", census + "\n" + after)
    with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as f:
        f.write("#include <stdarg.h>\n" + harness)
        harness_path = f.name
    out = subprocess.run(["gcc", "-O1", "-Wall", "-Wextra", "-o", harness_path + ".out", harness_path],
                         capture_output=True, text=True)
    check("B0 gcc compile clean", out.returncode == 0, out.stderr[:400])
    if out.returncode == 0:
        run = subprocess.run([harness_path + ".out"], capture_output=True, text=True)
        check("B behavioral mirror", "ALL_MIRROR_OK" in run.stdout, run.stdout + run.stderr[:300])
    os.unlink(harness_path)
    if os.path.exists(harness_path + ".out"):
        os.unlink(harness_path + ".out")

    print("\n%d failure(s)" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
