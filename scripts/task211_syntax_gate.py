#!/usr/bin/env python3
"""Task211 语法门：本轮改动的 C/ObjC 区域独立语法检查（g++，D1 变换约定）。

覆盖：
  A. tinygl4angle.c —— 三个 MultiDraw 拆解 + glDrawArrays 全屏四边形普查
     （Task209 探针段 → glMultiDrawElements 结束 + glDrawArrays 函数体）
  B. gl_bridge.m —— ame_task41_swap_forensics 的 Task211 五点回读块
     （ObjC→C++ 变换：NSLog→printf、@""→""、(__bridge id)→(id)）
  C. 括号平衡门：本轮触碰的全部源文件（含 CF 家族 .m）
语法门只验语义结构；行为断言由 verify_task211 的文本锚点覆盖。
"""
import re, subprocess, tempfile, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

fails = []

# ---------- A. tinygl4angle.c ----------
src = open('Natives/external/gl4es/tinygl4angle.c', encoding='utf-8').read()

seg_a = src[src.index('// ---- Task209（ANGLE 方块透明四叉取证）----'):]
seg_a = seg_a[:seg_a.index('typedef void (*ame173_fn_glColorMaski)')]

seg_b = src[src.index('typedef void (*ame203_fn_glDrawArrays)'):]
seg_b = seg_b[:seg_b.index('typedef void (*ame203_fn_glDrawElementsInstanced)')]

tu = r'''
#include <stdio.h>
#include <stddef.h>
#include <pthread.h>
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLsizei;
typedef int GLint;
typedef unsigned char GLboolean;
typedef char GLchar;
#define GL_BLEND 0x0BE2
#define GL_BLEND_SRC_RGB 0x80C8
#define GL_BLEND_DST_RGB 0x80C9
#define GL_DEPTH_TEST 0x0B71
#define GL_DEPTH_FUNC 0x0B74
#define GL_COLOR_WRITEMASK 0x0C23
#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA6
#define GL_ACTIVE_TEXTURE 0x84E0
#define GL_TEXTURE_BINDING_2D 0x8069
#define GL_TEXTURE0 0x84C0
static void *ame173_gpa_multi(const char *n) { (void)n; return 0; }
static pthread_mutex_t ame173_mtx;
#define AME173_RESOLVE(var, name) \
    do { \
        if (!(var)) { \
            pthread_mutex_lock(&ame173_mtx); \
            if (!(var)) { (var) = ame173_gpa_multi(name); } \
            pthread_mutex_unlock(&ame173_mtx); \
        } \
    } while (0)
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount);
'''
tu += seg_a + "\n" + seg_b

with tempfile.NamedTemporaryFile('w', suffix='.c', delete=False) as f:
    f.write(tu); path_a = f.name
r = subprocess.run(['gcc', '-fsyntax-only', '-std=c17', '-Wall', '-Wno-unused-variable',
                    '-Wno-unused-function', '-Wno-format', path_a],
                   capture_output=True, text=True)
print(f"A tinygl4angle regions: exit={r.returncode}")
if r.returncode != 0:
    print(r.stderr[:3000]); fails.append('A')
else:
    if r.stderr.strip():
        print("  [warnings]\n" + r.stderr[:1500])

# ---------- B. gl_bridge.m ----------
src_b = open('Natives/ctxbridges/gl_bridge.m', encoding='utf-8').read()
seg = src_b[src_b.index('static void ame_task41_swap_forensics(EGLSurface surface, unsigned long swapIndex) {'):]
# 只取探针段（Task146 dispatch → Task187/188 状态与回读 → Task211 五点回读），
# 到 Task76 注释为止——后面的 geo-heal/FSR 尾段本轮未触碰（@try/CG 桩面大）
cut = seg.index('    // Task 76：退役 while(es.getError() != 0)')
seg = seg[:cut] + '}\n'

seg = seg.replace('NSLog(@"', 'printf("')
seg = re.sub(r'@"((?:[^"\\]|\\.)*)"', r'"\1"', seg)
seg = seg.replace('(__bridge id)', '(id)')
seg = seg.replace('dispatch_async(dispatch_get_main_queue(), ^{',
                  'dispatch_async(dispatch_get_main_queue(), [&]() {')

hdr = r'''
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <dlfcn.h>
typedef int EGLBoolean; typedef void *EGLSurface; typedef int EGLint; typedef void *EGLDisplay;
#define EGL_NO_SURFACE ((EGLSurface)0)
typedef unsigned int GLenum; typedef unsigned int GLuint; typedef int GLsizei; typedef int GLint;
typedef unsigned char GLboolean; typedef float GLfloat;
#define GL_VIEWPORT 0x0BA2
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#define GL_COLOR_CLEAR_VALUE 0x0C22
#define GL_COLOR_WRITEMASK 0x0C23
#define GL_SCISSOR_BOX 0x0C10
#define GL_SCISSOR_TEST 0x0C11
#define GL_DEPTH_TEST 0x0B71
#define GL_BLEND 0x0BE2
#define GL_STENCIL_TEST 0x0B90
#define GL_ALPHA_BITS 0x0D55
#define GL_DEPTH_BITS 0x0D56
#define GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT 0x8A34
#define GL_UNIFORM_BUFFER_BINDING 0x8A28
#define EGL_HEIGHT 0x3056
#define EGL_WIDTH 0x3057
#define NO 0
#define YES 1
typedef int BOOL;
// ---- ame_es_t 桩（与 gl_bridge.m 原定义同构的最小面）----
typedef void (*ame_es_getint_t)(unsigned int, int *);
typedef void (*ame_es_bindfb_t)(unsigned int, unsigned int);
typedef unsigned int (*ame_es_geterr_t)(void);
typedef unsigned char (*ame_es_isenabled_t)(unsigned int);
typedef void (*ame_es_enable_t)(unsigned int, unsigned char);
typedef void (*ame_es_blitfb_t)(int, int, int, int, int, int, int, int, unsigned int, unsigned int);
typedef void (*ame_es_getfloat_t)(unsigned int, float *);
typedef void (*ame_es_getbool_t)(unsigned int, unsigned char *);
typedef void (*ame_es_readpx_t)(int, int, int, int, unsigned int, unsigned int, void *);
typedef struct {
    ame_es_getint_t    getIntegerv;
    ame_es_bindfb_t    bindFramebuffer;
    ame_es_geterr_t    getError;
    ame_es_isenabled_t isEnabled;
    ame_es_enable_t    enable;
    ame_es_blitfb_t    blitFramebuffer;
    ame_es_getfloat_t  getFloatv;
    ame_es_getbool_t   getBooleanv;
    ame_es_readpx_t    readPixels;
    EGLBoolean (*querySurface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
} ame_es_t;
static ame_es_t ame_es(void) { ame_es_t e = {}; return e; }
static int isSelfEglRenderer(const char *r) { (void)r; return 0; }
static void *ame145_rendererHandle = 0;
static void ame_geo_check_and_heal(EGLSurface s) { (void)s; }
'''
tu_b = hdr + "\n" + seg
with tempfile.NamedTemporaryFile('w', suffix='.cpp', delete=False) as f:
    f.write(tu_b); path_b = f.name
r = subprocess.run(['g++', '-fsyntax-only', '-std=c++17', '-Wno-unused-variable',
                    '-Wno-unused-function', '-Wno-format-overflow', '-Wno-format', path_b],
                   capture_output=True, text=True)
print(f"B gl_bridge swap forensics: exit={r.returncode}")
if r.returncode != 0:
    print(r.stderr[:3000]); fails.append('B')
else:
    if r.stderr.strip():
        print("  [warnings]\n" + r.stderr[:1500])

# ---------- C. 括号平衡 ----------
files = [
    'Natives/external/gl4es/tinygl4angle.c',
    'Natives/ctxbridges/gl_bridge.m',
    'Natives/installer/modpack/CurseForgeAPI.m',
    'Natives/installer/modpack/CurseForgeAPI.h',
    'Natives/installer/CurseForgeAPIKeyViewController.m',
    'Natives/CurseForgeAPIKeyViewController.m',
    'Natives/PLPreferences.m',
    'Natives/LauncherPreferences.m',
    'Natives/LauncherPreferences.h',
    'Natives/main.m',
    # Task211 stage 2 (gl4eszl2 移植触碰面)
    'Natives/egl_bridge.m',
    'Natives/utils.h',
    'Natives/LauncherPreferences.m',
    'Natives/VersionManagerViewController.m',
    'Natives/AI/AiSettingsTools.m',
    'ThirdParty/gl4es_extra_extra/src/glx/hardext.c',
    'ThirdParty/gl4es_extra_extra/src/gl/init.c',
    'ThirdParty/gl4es_extra_extra/src/gl/wrap/gl4eszl2_darwin_aliases.c',
]
for fp in files:
    txt = open(fp, encoding='utf-8', errors='replace').read()
    # 剥离顺序（避免撇号陷阱——Task211 实战教训：注释里的 host's...NG's
    # 会被字符字面量近似当成 '...' 吞掉中间的括号）：
    #   ① 块注释 /* */（非贪婪、跨行） ② 整行 // 注释 ③ 字符串 ④ 字符
    txt_nc = re.sub(r'/\*.*?\*/', ' ', txt, flags=re.S)
    txt_nc = '\n'.join(l for l in txt_nc.split('\n') if not l.strip().startswith('//'))
    txt_nc = re.sub(r'"(?:[^"\\]|\\.)*"', '""', txt_nc)
    txt_nc = re.sub(r"'(?:[^'\\]|\\.)*'", "''", txt_nc)
    for op, cl, name in (('{', '}', 'braces'), ('(', ')', 'parens')):
        if txt_nc.count(op) != txt_nc.count(cl):
            print(f"C {fp}: {name} UNBALANCED {txt_nc.count(op)}/{txt_nc.count(cl)}")
            fails.append(f'C:{fp}:{name}')
        else:
            print(f"C {fp}: {name} {txt_nc.count(op)}/{txt_nc.count(cl)} OK")

os.unlink(path_a); os.unlink(path_b)
print("\nRESULT:", "FAIL " + ",".join(fails) if fails else "ALL PASS")
sys.exit(1 if fails else 0)
