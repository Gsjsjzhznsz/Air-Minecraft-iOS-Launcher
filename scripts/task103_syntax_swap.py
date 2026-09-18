#!/usr/bin/env python3
"""Task103: osm_swap_buffers 呈现/投票段独立语法门（g++，task85 D1 变换约定）

覆盖本任务新增的哨兵票/翻转判决/心跳扩展 + Task99/100 既有呈现逻辑的
完整 osm_swap_buffers 函数体。ObjC 结构按 D1 惯例变换：
  NSLog(@"...") -> printf("...")   @"..." -> "..."
  dispatch_async(q, ^{...}) -> dispatch_async(q, [&]() { ... })
  (__bridge id)x -> (id)x
CG/Surface/桥接符号用桩（语法门只验 C/C++ 语义结构；行为断言由
verify_task103 的文本锚点覆盖）。
"""
import re, subprocess, tempfile, os, sys

SRC = 'Natives/ctxbridges/osm_bridge.mm'
src = open(SRC, encoding='utf-8').read()

seg = src[src.index('void osm_swap_buffers() {'):]
seg = seg[:seg.index('void osm_swap_interval')]

# ObjC -> C++ 变换
seg = seg.replace('NSLog(@"', 'printf("')
seg = re.sub(r'@"((?:[^"\\]|\\.)*)"', r'"\1"', seg)
seg = seg.replace('(__bridge id)', '(id)')
seg = seg.replace('dispatch_async(dispatch_get_main_queue(), ^{',
                  'dispatch_async(dispatch_get_main_queue(), [&]() {')

header = r'''
#include <stdint.h>
#include <stddef.h>
#include <cstdio>
#include <cstring>
#include <string>
// ---- 桩：类型/枚举（与 osm_bridge.h 语义等价的最小面）----
typedef unsigned int uint32_t_bogus_unused;
typedef int GLsizei;
typedef unsigned int GLenum;
typedef void *id;
typedef void *CGDataProviderRef;
typedef void *CGImageRef;
typedef void *CGColorSpaceRef;
#define kCGImageAlphaNoneSkipLast 0
#define kCGBitmapByteOrderDefault 0
#define kCGRenderingIntentDefault 0
#define FALSE 0
// ---- 桩：桥接全局（osm_bridge 真实符号的声明面）----
extern int windowWidth, windowHeight;
typedef struct osm_render_window_stub {
    uint32_t width, height;
    void *buffer;
    void *color_space;
} osm_render_window_t;
struct basic_render_window_stub { osm_render_window_t osm; };
extern basic_render_window_stub *currentBundle;
static struct { void (*glFinish)(void); } handle_stub;
#define handle handle_stub
static void CallbackBridge_nativeSendScreenSize(int, int) {}
// ---- 桩：Task 83/99/100/103 状态（真实定义在文件前段的语法等价物）----
struct ame83_stub {
    bool markerArmed; unsigned markerCode; long frames; bool healed;
};
static ame83_stub ame83_fsr;
struct ame99_stub {
    long swaps; int probeHits, probeFrames; int verdict; bool gpuProbed;
    int mkHits, mkState, mkConsecM, mkConsecMiss; bool final90Logged;
};
static ame99_stub ame99_fsrdiag;
#define kAme99ProbeFrames 90
static struct {
    unsigned char *scratch; unsigned char *present;
    int bufW, bufH; bool engaged, broken; int drvHits, drvFrames;
} ame100_present;
struct osm_bundle_t { uint32_t width, height; void *buffer; void *color_space; };
// ---- 桩：CG / Surface / dispatch ----
static void *dispatch_get_main_queue(void) { return (void *)1; }
template <typename F> static void dispatch_async(void *, F) {}
static CGDataProviderRef CGDataProviderCreateWithData(void *, const void *, size_t, void *) { return 0; }
static CGImageRef CGImageCreate(uint32_t, uint32_t, int, int, size_t, void *, int, CGDataProviderRef, void *, int, int) { return 0; }
static void CGImageRelease(CGImageRef) {}
static void CGDataProviderRelease(CGDataProviderRef) {}
static struct { struct { struct { id contents; } layer; } surface; } SurfaceViewController;
// ---- osm_apply_current_ll / ame83_fsr_upscale / ame100_present_frame 桩 ----
static void osm_apply_current_ll(void) {}
static bool ame83_fsr_upscale(int, int, int, int) { return true; }
static bool ame100_present_frame(int, int) { return true; }
'''

footer = '''
int main(void) { osm_swap_buffers(); return 0; }
'''

with tempfile.NamedTemporaryFile('w', suffix='.cpp', delete=False) as f:
    f.write(header + seg + footer)
    tmp = f.name
r = subprocess.run(['g++', '-std=gnu++17', '-fsyntax-only', '-Wall', tmp],
                   capture_output=True, text=True)
os.unlink(tmp)
if r.returncode != 0:
    print('SYNTAX FAIL:\n' + r.stderr)
    sys.exit(1)
print('osm_bridge.mm osm_swap_buffers section (Task103 vote/present): syntax OK')
