#!/bin/bash
# Task 83: g++ (ObjC++-equivalent) syntax check for the ame83 (zink FSR EASU) C section of
# osm_bridge.mm. ObjC-only constructs are stripped/transformed; the C body
# (function-pointer table, shader compile, upscale pass) is fully checked.
set -e
SRC=/home/z/my-project/Amethyst-iOS-MyRemastered/Natives/ctxbridges/osm_bridge.mm
TMP=$(mktemp /tmp/osm83_XXXX.c)
trap "rm -f $TMP $TMP2" EXIT

python3 - "$SRC" "$TMP" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()

# 提取 ame83 区块（从 GL 枚举定义到 ame83_fsr_upscale 结束）
start = s.index('#ifndef GL_VERTEX_SHADER')
end_marker = 'void osm_apply_current_ll() {'
end = s.index(end_marker)
block = s[start:end]

# ObjC -> C 变换
block = block.replace('NSLog(@"', 'AME83_LOG("')          # @"..." -> "..."
block = re.sub(r'@"((?:[^"\\]|\\.)*)"', r'"\1"', block)     # 其余 @ 字符串
block = block.replace('AME83_LOG(', 'printf(')

header = r'''
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <dlfcn.h>
#include <string.h>
// GL 1.1 类型与枚举桩（osmesa_internal.h 经 osm_bridge.h 引入的真实头等价物）
typedef unsigned int GLenum; typedef unsigned char GLboolean; typedef int GLint;
typedef int GLsizei; typedef float GLfloat; typedef float GLclampf;
typedef unsigned int GLbitfield; typedef unsigned char GLubyte;
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FLOAT 0x1406
#define GL_FALSE 0
#define GL_TRIANGLES 0x0004
#define GL_NEAREST 0x2600
#define GL_LINEAR 0x2601
// Task138 stub: the real definition of FSR_RCAS_FSSource is in FSRRCASSource.h (outside the extraction block,
// introduced by Task130 RCAS — satisfying the syntax-check semantics in declaration form).
extern const char *const FSR_RCAS_FSSource;
#define GL_TEXTURE_2D 0x0DE1
#define GL_VIEWPORT 0x0BA2
#define GL_DEPTH_TEST 0x0B71
#define GL_SCISSOR_TEST 0x0C11
#define GL_BLEND 0x0BE2
#define GL_CULL_FACE 0x0B44
#define GL_LINEAR 0x2601
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
// ame83 依赖的外部符号桩
static void *s_osmDL = (void*)1;
// Task 83b：ame83_probe_glsl_version 引用的 osmesa_library 桩（真实定义在
// 提取区块之外的 osmesa_internal.h，此处只补本段用到的 glGetString 成员）
static struct ame83_stub_osmesa_library { unsigned char *(*glGetString)(unsigned int); } handle = { 0 };
// 注：与真实 osm_bridge.h 签名一致（GLubyte* 返回）——CI run 35096621923 教训：
// 桩写成 const char* 会让本地语法检查漏掉 C++ 的指针类型不兼容错误。
static int windowWidth = 1572, windowHeight = 1092;
static void CallbackBridge_nativeSendScreenSize(int w, int h) { (void)w; (void)h; }
// Task 106 桩：提取区块内的 ame103_marker_vote 形参类型 + ame106_us 的
// mach 计时（真实来自 osm_bridge.h / <mach/mach_time.h>，Linux 语法门等价物）
typedef struct { uint32_t width, height; void *buffer; void *color_space; void *context; } osm_render_window_t;
typedef struct { uint32_t numer, denom; } mach_timebase_info_data_t;
typedef int kern_return_t_ignored;
static int mach_timebase_info(mach_timebase_info_data_t *t) { t->numer = 1; t->denom = 1; return 0; }
'''
# 真实 shader 字符串（raw string literal，gcc C 模式接受）
shader_h = '/home/z/my-project/Amethyst-iOS-MyRemastered/Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h'
header += '#include "%s"\n' % shader_h
open(dst, 'w').write(header + block)
EOF

g++ -fsyntax-only -std=gnu++17 -Wall -Wextra -Wno-unused-function "$TMP"

echo "osm_bridge.mm ame83 section: syntax OK"

# 第二段：dlsym_OSMesa 函数（CI run 34993498502 教训：C++ 禁止 void*→函数指针
# 隐式转换，AME83_DLSYM_SLOT 宏的 __typeof__ 转型必须双侧验证）
TMP2=$(mktemp /tmp/osm83b_XXXX.cpp)
python3 - "$SRC" "$TMP2" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
start = s.index('#define AME83_DLSYM_SLOT')
end_marker = 'bool osm_init() {'
end = s.index(end_marker)
block = s[start:end]
# ObjC dlopen 调用 -> C 桩
block = re.sub(r'dlopen\(\[NSString.*?RTLD_GLOBAL\)', 'dlopen(getenv("AMETHYST_RENDERER"), RTLD_GLOBAL)', block, flags=re.S)
header = r'''
#include <dlfcn.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
typedef unsigned int GLenum; typedef unsigned char GLboolean; typedef int GLint;
typedef int GLsizei; typedef float GLclampf; typedef unsigned int GLbitfield;
typedef unsigned char GLubyte;
typedef struct osmesa_context OSMesaContext;
typedef struct {
    GLboolean (*OSMesaMakeCurrent)(OSMesaContext, void*, GLenum, GLsizei, GLsizei);
    OSMesaContext (*OSMesaGetCurrentContext)(void);
    OSMesaContext (*OSMesaCreateContext)(GLenum, OSMesaContext);
    void (*OSMesaDestroyContext)(OSMesaContext);
    void (*OSMesaPixelStore)(GLint, GLint);
    GLubyte* (*glGetString)(GLenum);
    void (*glClearColor)(GLclampf, GLclampf, GLclampf, GLclampf);
    void (*glClear)(GLbitfield);
    void (*glFinish)(void);
} osmesa_library;
// Task138 补桩：FSR_RCAS_FSSource 真实定义位于 FSRRCASSource.h（提取块外），
// Task130 的 RCAS 代码引用它——语法门以声明形态满足链接语义即可。
extern const char *const FSR_RCAS_FSSource;
static osmesa_library handle;
static void *s_osmDL = NULL;
'''
open(dst, 'w').write(header + block)
EOF
g++ -fsyntax-only -std=gnu++17 -Wall -Wextra "$TMP2"
echo "osm_bridge.mm dlsym section (C++ strict pointer casts): syntax OK"
