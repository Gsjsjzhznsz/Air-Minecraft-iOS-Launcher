#!/usr/bin/env python3
"""
Task 85 验证器：zink FSR“画面分裂”根治（EASU/回读顺序）+ FSR1 替代方案调研入库

背景（真机现象）：
  * Task 84 修齐 zink FSR 编译链（#version 410 适配 + packHalf2x16 手写回退 +
    GL_FRAGMENT_SHADER 枚举 0x8B92）后，EASU 在 zink 上首次真正运行；
  * 用户随即报告“画面分裂”。
  * 根因：osm_swap_buffers 旧序 = glFinish（触发 OSMesa GPU→CPU 回读）→ EASU
    （画进 GPU 侧帧缓冲）——升采样结果永远到不了 CGImage 包装的 client buffer。
    真机视觉 = 左下角窗口区域为本帧原始低清画面 + 其余区域为上一帧 EASU 残影。

修复指纹：
  A. osm_swap_buffers 顺序反转：EASU 块在 handle.glFinish() 之前（回读包含
     升采样结果）；
  B. ame83_fsr_upscale 封闭性：显式 glBindFramebuffer(GL_FRAMEBUFFER, 0)
     + draw/read FBO 绑定保存/还原 + GL_STENCIL_TEST 关闭；
  C. engaged 日志带 Task 85 标记（真机判读锚点）；
  D. FAQ 24 条（fsr 条目 zink 病史补“画面分裂”已修 + 新增 upscalerAlt
     替代方案调研条目：NIS/GSR/MetalFX Spatial/Anime4K/时域家族）；
  E. 语法门：osm_swap_buffers + osm_apply_current_ll 段 g++（ObjC→C 变换）；
  F. 级联：verify_task83 / verify_task84 全绿。
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
SCRIPTS = os.path.join(REPO, "scripts")
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8") as f:
        return f.read()


print("===== A. osm_swap_buffers 顺序反转（根因修复） =====")
osm = read("Natives/ctxbridges/osm_bridge.mm")
swap_start = osm.index("void osm_swap_buffers() {")
swap_end = osm.index("void osm_swap_interval(", swap_start)
swap = osm[swap_start:swap_end]
check("A1 EASU 块在 glFinish 之前（upscale 先于回读）",
      swap.index("ame83_fsr_upscale(") < swap.index("handle.glFinish()"))
check("A2 glFinish 仍在 CGImage 构造之前（回读先于上屏）",
      swap.index("handle.glFinish()") < swap.index("CGDataProviderCreateWithData"))
check("A3 顺序修复注释在位（画面分裂根治说明）",
      "Task 85（画面分裂根治）：EASU 必须在 glFinish 之前执行" in swap)
check("A4 兜底逻辑原样保留（unavailable → nativeSendScreenSize）",
      "Task83 FSR upscale unavailable" in swap
      and "CallbackBridge_nativeSendScreenSize" in swap)
check("A5 旧序已绝迹（glFinish 不再是 swap 的第一条实质语句）",
      not re.search(r"void osm_swap_buffers\(\) \{\s*osm_apply_current_ll\(\);\s*handle\.glFinish\(\);", osm))

print("===== B. ame83_fsr_upscale 封闭性 =====")
up_start = osm.index("static bool ame83_fsr_upscale(")
up_end = osm.index("void osm_apply_current_ll() {")
upscale = osm[up_start:up_end]
check("B1 显式绑定默认帧缓冲（拷贝源/绘制目标锁定 fb0）",
      "g->glBindFramebuffer(GL_FRAMEBUFFER, 0);" in upscale)
check("B2 draw/read FBO 双通道保存",
      "glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saveDrawFbo)" in upscale
      and "glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saveReadFbo)" in upscale)
check("B3 draw/read FBO 双通道还原（非对称绑定不受扰动）",
      "glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (unsigned int)saveDrawFbo)" in upscale
      and "glBindFramebuffer(GL_READ_FRAMEBUFFER, (unsigned int)saveReadFbo)" in upscale)
check("B4 还原在绘制之后（先画后还）",
      upscale.index("glDrawArrays(GL_TRIANGLES, 0, 6)")
      < upscale.index("glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (unsigned int)saveDrawFbo)"))
check("B5 stencil 测试也关闭（与 depth/scissor/blend/cull 同列）",
      "g->glDisable(GL_STENCIL_TEST);" in upscale)
check("B6 glBindFramebuffer 进 dlsym 表（缺失符号时整链熔断）",
      '{"glBindFramebuffer",          (void**)&ame83_fsr.gl.glBindFramebuffer},' in osm)
check("B7 GL 枚举六件套在位（FRAMEBUFFER/DRAW/READ×值+绑定+STENCIL）",
      all(k in osm for k in (
          "#define GL_FRAMEBUFFER            0x8D40",
          "#define GL_DRAW_FRAMEBUFFER       0x8CA6",
          "#define GL_READ_FRAMEBUFFER       0x8CA9",
          "#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA6",
          "#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA",
          "#define GL_STENCIL_TEST           0x0B90")))
check("B8 枚举定义不重复（MultiEdit 事故防护）",
      osm.count("#define GL_FRAMEBUFFER ") == 1
      and osm.count("#define GL_STENCIL_TEST ") == 1)
check("B9 engaged 日志带 Task 85 判读标记",
      "(EASU pre-readback ordering, Task 85)" in osm)

print("===== C. FAQ（fsr 病史修订 + upscalerAlt 条目） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("C1 33 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task85 时为 24）", len(faq_items) == 33, f"got {len(faq_items)}")
check("C2 upscalerAlt 条目在位（问题 + 五类方案 + 结论）",
      "FSR 1.0 有哪些替代方案" in helpvc
      and "NVIDIA NIS（Image Scaling）" in helpvc
      and "Qualcomm GSR（Game Super Resolution）" in helpvc
      and "MetalFX 空间版】Digital Foundry" in helpvc
      and "Anime4K／FSRCNNX" in helpvc
      and "时域家族（DLSS／FSR 2-3／XeSS" in helpvc)
check("C3 upscalerAlt 已注册进渲染与性能分类",
      "armAsr, upscalerAlt, fpsUnlock" in helpvc)
check("C4 fsr 条目 zink 病史含画面分裂（绿色花屏/画面分裂均已修）",
      '绿色花屏和\\"画面分裂\\"两种显示异常，均已修复' in helpvc)
check("C5 fsr 条目闭环语（回读前放大 + 封闭链路）",
      "回读前放大、显式锁定默认帧缓冲" in helpvc)

print("===== D. osm_swap_buffers 段语法门（g++ ObjC→C 变换） =====")
with tempfile.NamedTemporaryFile(suffix=".cpp", delete=False, mode="w") as tf:
    tmp = tf.name
header = r'''
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <cstring>
typedef unsigned int GLenum; typedef unsigned char GLboolean; typedef int GLint;
typedef int GLsizei; typedef float GLfloat; typedef unsigned int GLbitfield;
typedef unsigned char GLubyte; typedef unsigned int GLuint;
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
// —— osm_bridge.h 等价桩（真实头引入会拉进 ObjC）——
typedef struct { uint32_t width, height; void *buffer; void *color_space; void *context; } osm_render_window_t;
typedef struct { uint32_t width, height; void *buffer; void *color_space; osm_render_window_t osm; } basic_render_window_t;
static basic_render_window_t *currentBundle = NULL;
static int windowWidth = 1572, windowHeight = 1092;
static int ame_surfaceWidth = 1814, ame_surfaceHeight = 1262;
typedef struct {
    void (*OSMesaMakeCurrent)(void*, void*, GLenum, GLsizei, GLsizei);
    void (*OSMesaPixelStore)(GLint, GLint);
    void (*glFinish)(void);
} osmesa_library;
static osmesa_library handle;
#define OSMESA_ROW_LENGTH 0x10
#define OSMESA_Y_UP 0x11
static void CallbackBridge_nativeSendScreenSize(int w, int h) { (void)w; (void)h; }
// —— ame83 段桩（本门只编 swap/apply 段；真实实现经指纹断言覆盖）——
static bool ame83_fsr_upscale(int a, int b, int c, int d) { (void)a;(void)b;(void)c;(void)d; return true; }
struct ame85_fsr_stub { bool healed; long frames; bool markerArmed; unsigned markerCode; };
static struct ame85_fsr_stub ame83_fsr;
// —— Task99 段桩（swap 段引用 ame99_fsrdiag / kAme99ProbeFrames；真实定义在文件前部）——
static struct { long swaps; int probeHits, probeFrames; int verdict; bool gpuProbed;
  int mkHits, mkState, mkConsecM, mkConsecMiss; int mkFarHits; bool final90Logged; } ame99_fsrdiag = {0,0,0,0,false,0,0,0,0,0,false};
#define kAme99ProbeFrames 90
// —— Task100 段桩（swap 段引用 ame100_present / ame100_present_frame；真实定义在文件前部，Task 100 权威呈现路径）——
static struct { unsigned char *scratch, *present; int bufW, bufH; bool engaged, broken; int drvHits, drvFrames; } ame100_present = {0,0,0,0,false,false,0,0};
static bool ame100_present_frame(int w, int h) { (void)w; (void)h; return true; }
// —— ObjC 桩（真实 TU 为 ObjC++；此处 C 变换验证 C 语义段）——
typedef void *CGColorSpaceRef; typedef void *CGDataProviderRef; typedef void *CGImageRef;
typedef void *dispatch_queue_t;
static dispatch_queue_t dispatch_get_main_queue(void) { return (dispatch_queue_t)1; }
template <typename F> static void dispatch_async(dispatch_queue_t q, F blk) { (void)q; (void)blk; }
static CGDataProviderRef CGDataProviderCreateWithData(void *a, const void *b, size_t c, void *d) { (void)a;(void)b;(void)c;(void)d; return NULL; }
static CGImageRef CGImageCreate(size_t a, size_t b, size_t c, size_t d, size_t e,
                                void *f, unsigned int g, CGDataProviderRef h, void *i, char j, int k)
        { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;(void)h;(void)i;(void)j;(void)k; return NULL; }
static void CGImageRelease(CGImageRef a) { (void)a; }
static void CGDataProviderRelease(CGDataProviderRef a) { (void)a; }
static CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void) { return NULL; }
static void CGColorSpaceRelease(CGColorSpaceRef a) { (void)a; }
static void *reallocf(void *p, size_t s) { (void)p; (void)s; return NULL; }
static void *SurfaceViewController_surface_layer_contents_set(void *v) { (void)v; return NULL; }
// Task104：滤镜属性赋值变换桩（kCAFilter* 归一为 set 调用）
static void SurfaceViewController_surface_layer_filter_set(int which) { (void)which; }
static bool ame104_filters_linear = false;   // Task104：块外定义的文件级旗标桩
struct ame85_surf_stub { struct { void *layer; } *surface; };
static struct ame85_surf_stub SurfaceViewController = { NULL };
#define kCGImageAlphaNoneSkipLast 0
#define kCGBitmapByteOrderDefault 0
#define kCGRenderingIntentDefault 0
#define FALSE 0
'''
block = osm[osm.index("void osm_apply_current_ll() {"):osm.index("void osm_swap_interval(")]
# ObjC → C 变换（dispatch block 尾随闭包改普通调用桩 + 属性访问展开）
block = block.replace("SurfaceViewController.surface.layer.contents = (__bridge id)bitmap;",
                      "SurfaceViewController_surface_layer_contents_set(bitmap);")
# Task99 兜底分支的第二处 contents 赋值（region 版）同款变换
block = block.replace("SurfaceViewController.surface.layer.contents = (__bridge id)region;",
                      "SurfaceViewController_surface_layer_contents_set(region);")
# Task100 权威呈现分支的第三处 contents 赋值（presentImg 版）同款变换
block = block.replace("SurfaceViewController.surface.layer.contents = (__bridge id)presentImg;",
                      "SurfaceViewController_surface_layer_contents_set(presentImg);")
# Task104：兜底/全幅分支的 layer 滤镜赋值（Linear/Nearest 四处）同款变换
block = block.replace("SurfaceViewController.surface.layer.magnificationFilter = kCAFilterLinear;",
                      "SurfaceViewController_surface_layer_filter_set(1);")
block = block.replace("SurfaceViewController.surface.layer.minificationFilter = kCAFilterLinear;",
                      "SurfaceViewController_surface_layer_filter_set(1);")
block = block.replace("SurfaceViewController.surface.layer.magnificationFilter = kCAFilterNearest;",
                      "SurfaceViewController_surface_layer_filter_set(2);")
block = block.replace("SurfaceViewController.surface.layer.minificationFilter = kCAFilterNearest;",
                      "SurfaceViewController_surface_layer_filter_set(2);")
# dispatch 尾随闭包 → 引用捕获 lambda（ObjC block 隐式捕获局部变量 bundle；
# g++ 无捕获 lambda 引用它编不过，[&] 等价还原语义）
block = block.replace("dispatch_async(dispatch_get_main_queue(), ^{",
                      "dispatch_async(dispatch_get_main_queue(), [&]() {")
block = re.sub(r'\[NSString stringWithFormat:@"@rpath/%s", getenv\("AMETHYST_RENDERER"\)\]',
               'getenv("AMETHYST_RENDERER")', block)
# NSLog + ObjC 字符串字面量 → printf（task83_syntax_osm.sh 同款变换）
block = block.replace('NSLog(@"', 'printf("')
block = re.sub(r'@"((?:[^"\\]|\\.)*)"', r'"\1"', block)
with open(tmp, "w") as f:
    f.write(header + "\n" + block)
r = subprocess.run(["g++", "-fsyntax-only", "-std=gnu++17", "-Wall", "-Wextra",
                    "-Wno-unused-function", "-Wno-unused-variable", tmp],
                   capture_output=True, text=True)
check("D1 osm_apply_current_ll + osm_swap_buffers 段 g++ 语法",
      r.returncode == 0, (r.stdout + r.stderr)[-300:])
os.unlink(tmp)

print("===== E. 括号平衡（编辑后文件自平衡） =====")
for path in ["Natives/ctxbridges/osm_bridge.mm", "Natives/LauncherHelpViewController.m"]:
    s = read(path)
    check(f"E {os.path.basename(path)} 括号自平衡",
          s.count("{") == s.count("}") and s.count("(") == s.count(")")
          and s.count("[") == s.count("]"),
          f"{{}} {s.count('{')}/{s.count('}')} () {s.count('(')}/{s.count(')')} [] {s.count('[')}/{s.count(']')}")

print("===== F. 级联回归 =====")
for v in ("verify_task83.py", "verify_task84.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=300)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln]
    ok = r.returncode == 0 and summary and "FAIL" not in summary[-1].upper().replace("FAILURES", "FAIL")
    check(f"F {v}", ok, (summary[-1] if summary else r.stdout[-150:] + r.stderr[-150:]))

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
