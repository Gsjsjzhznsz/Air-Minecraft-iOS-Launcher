#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include <string.h>
#include <stdatomic.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;

// ============================================================================
// 黑屏取证（Task 32）：eglSwapBuffers 成功/失败原子计数器
//
// 背景（latestlog b199c07 设备实测）：游戏完整启动（390 shader 全部转换成功、
// 资源/图集/声音加载完毕、SDL 事件循环存活、MC 事件被推入队列），但屏幕全黑。
// 旧版 gl_swap_buffers 只在 eglGetError()==EGL_BAD_SURFACE 时才打日志，
// 其余错误码（EGL_BAD_NATIVE_WINDOW / EGL_CONTEXT_LOST / EGL_BAD_ALLOC 等）
// 完全静默；而 pojavSwapBuffers 的 "First frame rendered" 又是无条件打印的，
// 无法证明首帧真的上屏。这两个计数器 + SurfaceVC 的 5 秒心跳日志
// （[RenderDiag] fps= swapOK= swapFail=）可以一锤定音地判断：
//   - swapFail 持续增长 → 呈现路径断了（layer/surface 生命周期问题）
//   - swapOK 增长但黑屏 → 帧被换入了错误的目标（覆盖/尺寸/scale 问题）
//   - 两个都不动 → 渲染线程已卡死（渲染循环在启动后期被阻塞）
// ============================================================================
static _Atomic unsigned long g_eglSwapOK = 0;
static _Atomic unsigned long g_eglSwapFail = 0;

void ame_egl_swap_stats(unsigned long *ok, unsigned long *fail) {
    if (ok) *ok = atomic_load(&g_eglSwapOK);
    if (fail) *fail = atomic_load(&g_eglSwapFail);
}

// ============================================================================
// Task 41：交换时刻 GL 状态取证 + 自愈呈现（GL 路径黑屏定位）
//
// 现状（latestlog d638c22）：swapOK=529、fps=57、390 编译零崩溃、图集/音效
// 全齐、遮罩正常移除——但画面全黑。MC RenderPearl GL 后端自建 1180x820 双
// 缓冲交换链 FBO（[MG] depth alloc #1/#2 两个 D32F 1180x820）。最后疑点：
// MC 的合成画面从未进入 FBO 0（ANGLE 窗口后缓冲），或进入后被翻译层丢弃。
//
// 本块在每次 eglSwapBuffers 之前（MC 渲染线程、MC 上下文 current）：
//   1) 探针帧（#1-#5 + 每 200 帧）：glGetIntegerv 查 DRAW/READ binding +
//      viewport；readback 当前 FBO 中心 8x8（UBYTE 失败换 FLOAT，覆盖 HDR
//      浮点格式）；readback FBO 0 中心 + 远角 8x8；全部记日志。
//   2) 自愈 latch：FBO 0 平坦且当前 FBO 有内容 → mode=blit：此后每帧
//      swap 前 raw ANGLE glBlitFramebuffer(viewport -> 表面实际尺寸)，
//      scissor 保存/恢复、read/draw binding 恢复。FBO 0 有内容 →
//      mode=normal 永不干预。unknown 保持探针。
//
// ES 指针从 MG 同款 pin 路径解析（@executable_path/Frameworks/
// libGLESv2.framework/libGLESv2），指向同一 ANGLE 镜像；对 gl4es 等
// 渲染器同样适用（它们的底层同为 ANGLE ES 上下文）。
// ============================================================================
typedef void (*ame_es_getint_t)(unsigned int, int *);
typedef void (*ame_es_bindfb_t)(unsigned int, unsigned int);
typedef void (*ame_es_readpx_t)(int, int, int, int, unsigned int, unsigned int, void *);
typedef unsigned int (*ame_es_geterr_t)(void);
typedef unsigned char (*ame_es_isenabled_t)(unsigned int);
typedef void (*ame_es_enable_t)(unsigned int, unsigned char);
typedef void (*ame_es_blitfb_t)(int, int, int, int, int, int, int, int, unsigned int, unsigned int);

typedef struct {
    ame_es_getint_t    getIntegerv;
    ame_es_bindfb_t    bindFramebuffer;
    ame_es_readpx_t    readPixels;
    ame_es_geterr_t    getError;
    ame_es_isenabled_t isEnabled;
    ame_es_enable_t    enable;
    ame_es_blitfb_t    blitFramebuffer;
    EGLBoolean (*querySurface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
} ame_es_t;

static ame_es_t ame_es(void) {
    static ame_es_t s_es;
    static BOOL s_tried = NO;
    if (s_tried) return s_es;
    s_tried = YES;
    static const char *const kCandidates[] = {
        "@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
        "@rpath/libGLESv2.framework/libGLESv2",
        "libGLESv2",
        NULL,
    };
    void *h = NULL;
    for (int i = 0; kCandidates[i] != NULL; ++i) {
        h = dlopen(kCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (h != NULL) {
            NSLog(@"[RenderDiag] Task41 ES probe pinned to %s", kCandidates[i]);
            break;
        }
    }
    if (h == NULL) {
        NSLog(@"[RenderDiag] Task41 ES probe unavailable (libGLESv2 not loadable)");
        return s_es;
    }
    s_es.getIntegerv     = (ame_es_getint_t)dlsym(h, "glGetIntegerv");
    s_es.bindFramebuffer = (ame_es_bindfb_t)dlsym(h, "glBindFramebuffer");
    s_es.readPixels      = (ame_es_readpx_t)dlsym(h, "glReadPixels");
    s_es.getError        = (ame_es_geterr_t)dlsym(h, "glGetError");
    s_es.isEnabled       = (ame_es_isenabled_t)dlsym(h, "glIsEnabled");
    s_es.enable          = (ame_es_enable_t)dlsym(h, "glEnable");
    s_es.blitFramebuffer = (ame_es_blitfb_t)dlsym(h, "glBlitFramebuffer");
    // eglQuerySurface 在 libEGL（ANGLE EGL）里，与 libGLESv2 同一 ANGLE 家族，
    // 已加载镜像 dlopen 仅引用计数 +1。自行解析以避免前向依赖文件后部的
    // ame_raw_query_surface（static 声明位于本块之后，不可提前引用）。
    static const char *const kEglCandidates[] = {
        "@executable_path/Frameworks/libEGL.framework/libEGL",
        "@rpath/libEGL.framework/libEGL",
        "libEGL",
        NULL,
    };
    for (int i = 0; kEglCandidates[i] != NULL; ++i) {
        void *he = dlopen(kEglCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (he != NULL) {
            s_es.querySurface = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint, EGLint *))dlsym(he, "eglQuerySurface");
            break;
        }
    }
    return s_es;
}

// 统计 8x8 RGBA UBYTE 块里不同颜色的个数（1 = 平坦）
static int ame_count_unique_rgba(const unsigned char *buf, int n_px) {
    int uniq = 0;
    unsigned int seen[64];
    for (int i = 0; i < n_px; ++i) {
        unsigned int c = ((unsigned)buf[i*4] << 24) | ((unsigned)buf[i*4+1] << 16) |
                         ((unsigned)buf[i*4+2] << 8) | (unsigned)buf[i*4+3];
        BOOL found = NO;
        for (int j = 0; j < uniq; ++j) if (seen[j] == c) { found = YES; break; }
        if (!found && uniq < 64) seen[uniq++] = c;
    }
    return uniq;
}

// 浮点 readback 兜底：方差>阈值 = 有内容
static BOOL ame_float_readback_has_content(ame_es_t es, int x, int y) {
    float buf[8 * 8 * 4];
    es.readPixels(x, y, 8, 8, 0x1908 /*GL_RGBA*/, 0x1406 /*GL_FLOAT*/, buf);
    if (es.getError() != 0) return NO; // 未知
    float minv = 1e30f, maxv = -1e30f;
    for (int i = 0; i < 8 * 8 * 4; ++i) {
        if (buf[i] < minv) minv = buf[i];
        if (buf[i] > maxv) maxv = buf[i];
    }
    return (maxv - minv) > 0.001f;
}

// 探针 + 自愈主入口。swapIndex 从 1 计。
// 0 = undecided, 1 = normal, 2 = self-heal blit
static void ame_task41_swap_forensics(EGLSurface surface, unsigned long swapIndex) {
    ame_es_t es = ame_es();
    if (es.getIntegerv == NULL || es.bindFramebuffer == NULL || es.readPixels == NULL) return;

    static int s_mode = 0;          // 0 undecided / 1 normal / 2 blit
    const BOOL probe = (swapIndex <= 5) || (swapIndex % 200 == 0) || s_mode == 0;
    int drawFb = 0, readFb = 0, viewport[4] = {0, 0, 0, 0};
    es.getIntegerv(0x8CA9 /*GL_DRAW_FRAMEBUFFER_BINDING*/, &drawFb);
    es.getIntegerv(0x8CAA /*GL_READ_FRAMEBUFFER_BINDING*/, &readFb);
    es.getIntegerv(0x0BA2 /*GL_VIEWPORT*/, viewport);
    while (es.getError() != 0) {}   // 清残留错误

    int surfW = 0, surfH = 0;
    if (es.querySurface != NULL && surface != EGL_NO_SURFACE) {
        EGLint sw = 0, sh = 0;
        if (es.querySurface(g_EglDisplay, surface, 0x3056 /*EGL_WIDTH*/, &sw) &&
            es.querySurface(g_EglDisplay, surface, 0x3057 /*EGL_HEIGHT*/, &sh)) {
            surfW = sw; surfH = sh;
        }
    }
    if (surfW <= 0) surfW = viewport[2];
    if (surfH <= 0) surfH = viewport[3];

    if (probe) {
        unsigned char cur[8 * 8 * 4];
        int curUniq = 0, curErr = 0;
        int cx = viewport[0] + viewport[2] / 2 - 4;
        int cy = viewport[1] + viewport[3] / 2 - 4;
        es.readPixels(cx, cy, 8, 8, 0x1908, 0x1401 /*GL_UNSIGNED_BYTE*/, cur);
        curErr = (int)es.getError();
        if (curErr == 0) curUniq = ame_count_unique_rgba(cur, 64);
        BOOL curContent = (curErr == 0 && curUniq > 1);
        if (!curContent && curErr == 0) {
            // 64 像素全同色但非黑也可能是一帧纯色，浮点兜底区分方差
            curContent = ame_float_readback_has_content(es, cx, cy);
            if (curContent) curUniq = -1; // 标记浮点方差路径
        }

        // FBO 0 readback：中心 + 远角
        es.bindFramebuffer(0x8D40 /*GL_FRAMEBUFFER*/, 0);
        unsigned char fb0[8 * 8 * 4];
        int fb0Uniq = 0, fb0Err = 0;
        int fx = surfW / 2 - 4, fy = surfH / 2 - 4;
        es.readPixels(fx, fy, 8, 8, 0x1908, 0x1401, fb0);
        fb0Err = (int)es.getError();
        if (fb0Err == 0) fb0Uniq = ame_count_unique_rgba(fb0, 64);
        unsigned char corner[8 * 8 * 4];
        int cornerUniq = 0;
        es.readPixels(surfW - 12, surfH - 12, 8, 8, 0x1908, 0x1401, corner);
        if (es.getError() == 0) cornerUniq = ame_count_unique_rgba(corner, 64);
        es.bindFramebuffer(0x8D40, (unsigned)drawFb);   // 恢复
        while (es.getError() != 0) {}

        NSLog(@"[RenderDiag] swap#%lu (Task41): drawFb=%d readFb=%d viewport=%d,%d %dx%d surface=%dx%d cur=(uniq=%d err=0x%x) fbo0=(uniq=%d corner=%d err=0x%x) mode=%d",
              swapIndex, drawFb, readFb, viewport[0], viewport[1], viewport[2], viewport[3],
              surfW, surfH, curUniq, curErr, fb0Uniq, cornerUniq, fb0Err, s_mode);

        // latch 判定（只在确凿时）
        BOOL fbo0Flat = (fb0Err == 0 && fb0Uniq <= 1);
        BOOL fbo0Content = (fb0Err == 0 && fb0Uniq > 1);
        if (s_mode == 0 && fbo0Content) {
            s_mode = 1;
            NSLog(@"[RenderDiag] Task41 latch: NORMAL present (FBO 0 has content at swap time)");
        } else if (s_mode == 0 && fbo0Flat && curContent && drawFb != 0) {
            s_mode = 2;
            NSLog(@"[RenderDiag] Task41 latch: SELF-HEAL present blit (MC frame lives in FBO %d, FBO 0 is flat -- blitting every swap)", drawFb);
        }
    }

    if (s_mode == 2) {
        // 自愈：READ = MC 当前 FBO，DRAW = FBO 0，viewport -> surface 尺寸缩放 blit
        int scissorWasOn = es.isEnabled(0x0C11 /*GL_SCISSOR_TEST*/);
        if (scissorWasOn) es.enable(0x0C11, 0 /*GL_FALSE*/);
        es.bindFramebuffer(0x8CA8 /*GL_READ_FRAMEBUFFER*/, (unsigned)drawFb);
        es.bindFramebuffer(0x8CA9 /*GL_DRAW_FRAMEBUFFER*/, 0);
        es.blitFramebuffer(0, 0, viewport[2], viewport[3],
                           0, 0, surfW, surfH,
                           0x4000 /*GL_COLOR_BUFFER_BIT*/, 0x2601 /*GL_LINEAR*/);
        unsigned int blitErr = es.getError();
        es.bindFramebuffer(0x8CA8, (unsigned)readFb);
        es.bindFramebuffer(0x8CA9, (unsigned)drawFb);
        if (scissorWasOn) es.enable(0x0C11, 1 /*GL_TRUE*/);
        while (es.getError() != 0) {}
        static unsigned long s_blitLogs = 0;
        s_blitLogs++;
        if (s_blitLogs <= 3 || s_blitLogs % 300 == 0 || blitErr != 0) {
            NSLog(@"[RenderDiag] self-heal blit #%lu (Task41): src=%dx%d dst=%dx%d blitErr=0x%x",
                  s_blitLogs, viewport[2], viewport[3], surfW, surfH, blitErr);
        }
    }
}

static void* load_egl_symbol(void *dl_handle, const char *symbol) {
    dlerror();
    void *addr = dlsym(dl_handle, symbol);
    const char *error = dlerror();
    if (!addr || error) {
        NSLog(@"EGLBridge: failed to resolve %s: %s", symbol, error ?: "symbol not found");
    }
    return addr;
}

// ============================================================================
// Task 36：MobileGlues 前端 EGL 路由（GL 路径黑屏修复）
//
// 设备实测（latestlog e28e4c3 + libmobileglues.dylib）：MC 26.3 的 OpenGL
// 后端被接受（c71dcfa 的 glGetError 一致性检查已过），渲染循环全速运转
// （fps=57~58、eglSwapBuffers 成功 485 次、零失败、零 GL 错误），但屏幕全黑、
// 只有声音。日志里 MobileGlues 自己给出了三条铁证：
//
//   [MG] SYMBOL THEFT: ... （平坦命名空间把 gl* 解析给了别的镜像 —— 警告性）
//   [MG] depth filter scan: context untracked (EGL bypassed this layer)...
//   （深位查询返回 -1，每上下文状态全部落在 context-0 回退实例上）
//
// 根因：本 bridge 此前把 MobileGlues 的 EGL 符号从 libtinygl4angle.dylib
// （raw ANGLE）解析，上下文/MakeCurrent 全部绕过了 MobileGlues 2.0.16+ 的
// 前端 EGL。MobileGlues 的 egl/context.cpp 里 MGContext 虚拟上下文记录只能
// 由前端 eglCreateContext 创建、由前端 eglMakeCurrent 绑定（g_current_ctx +
// mg_framebuffer_bind_context(id) + gl_state 重指向）。被绕过时
// mg_context_make_current 走 “handle is not tracked, leaving no current
// record” 分支 —— g_current_ctx 永远为 NULL，FBO 转译/状态机全部退化为
// 进程级单例，MC 26.3 RenderPearl 的合成画面从未进入默认帧缓冲，
// eglSwapBuffers 呈现的是从未被画过的黑帧。
//
// 修复：生命周期函数（eglBindAPI/eglCreateContext/eglDestroyContext/
// eglMakeCurrent/eglSwapBuffers/eglSwapInterval）改经 libmobileglues.dylib
// 的前端 EGL；基础设施函数（display/config/surface 等 —— 前端本来就是纯
// 透传）保持 raw ANGLE，两者指向同一个 ANGLE 实例（tinygl4angle 只是
// libEGL/libGLESv2 framework 的别名垫片）。
//
// 时序约束：前端函数内部的 LOAD_EGL 静态指针是首次调用时一次性初始化的，
// 而后端句柄 `egl` 只在 mg_init_gles()（Apple 平台）里绑定；mg_init_gles
// 又需要“有当前上下文”才能做正确的 caps 检测。因此在首个前端调用之前，
// 用 raw ANGLE 建一个 16x16 pbuffer + 临时 ES 上下文 → eglMakeCurrent →
// 调 mg_init_gles()（真实上下文在场，caps 检测有效）→ 释放并销毁临时资源
// → 再把生命周期指针切换到前端。引导失败则保持旧行为（全 raw ANGLE），
// 不引入新风险。
// ============================================================================
static void *ame_mg_handle = NULL;        // libmobileglues.dylib（前端 EGL/GL）
static void *ame_mg_angle_handle = NULL;  // libtinygl4angle.dylib（raw ANGLE 垫片）
static BOOL  ame_mgFrontendActive = NO;   // 生命周期函数已切到前端
static BOOL  ame_mgBootstrapTried = NO;   // 引导只尝试一次

typedef void (*ame_mg_init_gles_t)(void);
static ame_mg_init_gles_t ame_mg_init_gles = NULL;

// 引导专用 raw ANGLE 指针（不进 handle 表：仅 bootstrap + 取证使用）
typedef EGLSurface (*ame_fn_create_pbuffer)(EGLDisplay, EGLConfig, const EGLint *);
typedef EGLBoolean (*ame_fn_egl_query_surface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
static ame_fn_create_pbuffer       ame_raw_create_pbuffer = NULL;
static ame_fn_egl_query_surface    ame_raw_query_surface = NULL;
static PFNEGLCREATECONTEXTPROC     ame_raw_create_context = NULL;
static PFNEGLMAKECURRENTPROC       ame_raw_make_current = NULL;
static PFNEGLDESTROYCONTEXTPROC    ame_raw_destroy_context = NULL;
static PFNEGLDESTROYSURFACEPROC    ame_raw_destroy_surface = NULL;

static bool dlsym_EGL() {
    // EGL 符号来源：
    //   - Mithril / MobileGL：自带完整 EGL 实现，必须从自身 dylib 解析。
    //     若复用 ANGLE 的 EGL，会创建 ANGLE 的 Metal 上下文而不是渲染器自己的
    //     surface，且 eglChooseConfig 在这些渲染器请求的属性组合下可能返回 0
    //     个配置，触发 gl_init_context 里的 assert(bundle->config) 崩溃。
    //   - MobileGlues：生命周期函数经其前端 EGL（Task 36，见上方大段注释），
    //     其余基础设施函数仍从 ANGLE 解析（前端本来就是透传，且必须在
    //     mg_init_gles 引导完成前避免触发前端内部的 LOAD_EGL 一次性初始化）。
    //   - 其余渲染器（gl4es / ANGLE / LTW）：全部从 ANGLE 解析。
    const char *renderer = getenv("AMETHYST_RENDERER");
    const char *eglLibrary = isSelfEglRenderer(renderer) ? renderer : RENDERER_NAME_MTL_ANGLE;
    NSString *eglPath = [NSString stringWithFormat:@"@rpath/%s", eglLibrary ?: ""];
    void* dl_handle = dlopen(eglPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!dl_handle) {
        NSLog(@"EGLBridge: failed to load %@ for renderer %s: %s",
            eglPath, renderer ?: "<unset>", dlerror() ?: "unknown dlopen error");
        return false;
    }

    // Task 36：MobileGlues 前端 EGL 准备（不改变任何行为，仅记录句柄/符号，
    // 真正的指针切换发生在 ame_mgBootstrap 成功之后）。
    if (renderer && strcmp(renderer, RENDERER_NAME_MOBILEGLUES) == 0 &&
        !isSelfEglRenderer(renderer)) {
        ame_mg_angle_handle = dl_handle;
        void *mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGLUES, RTLD_NOW | RTLD_LOCAL);
        if (!mg) {
            mg = dlopen(RENDERER_NAME_MOBILEGLUES, RTLD_NOW | RTLD_LOCAL);
        }
        if (mg) {
            ame_mg_handle = mg;
            ame_mg_init_gles = (ame_mg_init_gles_t)dlsym(mg, "mg_init_gles");
            NSLog(@"[MG-Bridge] MobileGlues frontend image loaded (%p, mg_init_gles=%p); "
                  @"lifecycle EGL will route through it after bootstrap",
                  mg, (void *)ame_mg_init_gles);
        } else {
            NSLog(@"[MG-Bridge] failed to load " RENDERER_NAME_MOBILEGLUES
                  @" (%s) -- EGL stays on raw ANGLE (legacy behavior)",
                  dlerror() ?: "unknown");
        }
        // 引导与取证用的 raw 指针（始终来自 ANGLE 垫片）
        ame_raw_create_pbuffer   = (ame_fn_create_pbuffer)load_egl_symbol(dl_handle, "eglCreatePbufferSurface");
        ame_raw_query_surface    = (ame_fn_egl_query_surface)load_egl_symbol(dl_handle, "eglQuerySurface");
        ame_raw_create_context   = (PFNEGLCREATECONTEXTPROC)load_egl_symbol(dl_handle, "eglCreateContext");
        ame_raw_make_current     = (PFNEGLMAKECURRENTPROC)load_egl_symbol(dl_handle, "eglMakeCurrent");
        ame_raw_destroy_context  = (PFNEGLDESTROYCONTEXTPROC)load_egl_symbol(dl_handle, "eglDestroyContext");
        ame_raw_destroy_surface  = (PFNEGLDESTROYSURFACEPROC)load_egl_symbol(dl_handle, "eglDestroySurface");
    }

    // NOTE: mg_init_gles() is called from gl_make_current() after the
    // EGL context is made current, because init_target_gles() queries
    // GL version/extensions which requires an active context.

    // LTW 模式：eglCreateContext / eglDestroyContext / eglMakeCurrent 三个函数
    // 必须从 libltw.dylib 直接 dlsym 解析，而非 ANGLE。
    //
    // 原因：LTW 是 OpenGL Core 3.3 → OpenGL ES 3 的转译层，它在这三个函数中
    // 注入 wrapper 逻辑（创建 ES3 上下文 + 安装 GL 函数指针转译表 + 伪装 ARB 扩展）。
    // 如果直接使用 ANGLE 的 eglCreateContext，创建的是原生 ES3 上下文，MC 1.17+
    // 检测到 GL_VERSION 不含 "Core Profile" 会拒绝启动；Sodium/Iris 的 ARB 扩展
    // 查询也会全部失败。LTW 的 wrapper 让 MC 看到的是 OpenGL 3.3 Core Profile，
    // 且主动声明 GL_ARB_buffer_storage 等 ARB 扩展，让 Sodium 的 persistent mapped
    // buffers / texture buffers 和 Iris 的 draw_buffers_blend 正常工作。
    //
    // 注意：不能用 RTLD_DEFAULT dlsym（iOS 的 flat namespace 中 ANGLE 符号会先命中），
    // 必须显式 dlopen libltw.dylib 后从其 handle dlsym。
    //
    // 其余 EGL 函数（eglChooseConfig / eglCreateWindowSurface / eglSwapBuffers 等）
    // LTW 不做 wrapper，直接从 ANGLE 解析。
    BOOL useLTW = renderer && strcmp(renderer, RENDERER_NAME_LTW) == 0;
    void *ltw_handle = NULL;
    if (useLTW) {
        ltw_handle = dlopen("@rpath/" RENDERER_NAME_LTW, RTLD_NOW | RTLD_LOCAL);
        if (!ltw_handle) {
            NSLog(@"EGLBridge: LTW renderer selected but failed to load libltw.dylib: %s",
                  dlerror() ?: "unknown dlopen error");
            // 致命错误：LTW 模式下没有 LTW 的 wrapper，MC 1.17+ 无法启动
            return false;
        }
        NSLog(@"EGLBridge: LTW mode active, eglCreateContext/Destroy/MakeCurrent resolved from libltw.dylib");
    }

    memset(&handle, 0, sizeof(handle));
    handle.eglBindAPI = load_egl_symbol(dl_handle, "eglBindAPI");
    handle.eglChooseConfig = load_egl_symbol(dl_handle, "eglChooseConfig");
    if (useLTW && ltw_handle) {
        // 从 LTW 解析三个 wrapper 函数（关键：让 LTW 的 GL Core→ES 转译逻辑生效）
        handle.eglCreateContext = load_egl_symbol(ltw_handle, "eglCreateContext");
        handle.eglDestroyContext = load_egl_symbol(ltw_handle, "eglDestroyContext");
        handle.eglMakeCurrent = load_egl_symbol(ltw_handle, "eglMakeCurrent");
    } else {
        handle.eglCreateContext = load_egl_symbol(dl_handle, "eglCreateContext");
        handle.eglDestroyContext = load_egl_symbol(dl_handle, "eglDestroyContext");
        handle.eglMakeCurrent = load_egl_symbol(dl_handle, "eglMakeCurrent");
    }
    handle.eglCreateWindowSurface = load_egl_symbol(dl_handle, "eglCreateWindowSurface");
    handle.eglDestroySurface = load_egl_symbol(dl_handle, "eglDestroySurface");
    handle.eglGetConfigAttrib = load_egl_symbol(dl_handle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = load_egl_symbol(dl_handle, "eglGetCurrentContext");
    handle.eglGetDisplay = load_egl_symbol(dl_handle, "eglGetDisplay");
    handle.eglGetError = load_egl_symbol(dl_handle, "eglGetError");
    handle.eglGetPlatformDisplay = load_egl_symbol(dl_handle, "eglGetPlatformDisplay");
    handle.eglInitialize = load_egl_symbol(dl_handle, "eglInitialize");
    handle.eglSwapBuffers = load_egl_symbol(dl_handle, "eglSwapBuffers");
    handle.eglReleaseThread = load_egl_symbol(dl_handle, "eglReleaseThread");
    handle.eglSwapInterval = load_egl_symbol(dl_handle, "eglSwapInterval");
    handle.eglTerminate = load_egl_symbol(dl_handle, "eglTerminate");
    handle.eglGetCurrentSurface = load_egl_symbol(dl_handle, "eglGetCurrentSurface");

    return handle.eglBindAPI && handle.eglChooseConfig && handle.eglCreateContext &&
        handle.eglCreateWindowSurface && handle.eglDestroyContext && handle.eglDestroySurface &&
        handle.eglGetConfigAttrib && handle.eglGetDisplay && handle.eglGetError &&
        handle.eglInitialize && handle.eglMakeCurrent && handle.eglSwapBuffers &&
        handle.eglReleaseThread && handle.eglSwapInterval && handle.eglTerminate;
}

// 只应在 gl_init_context（eglChooseConfig 之后、eglBindAPI/eglCreateContext 之前）
// 调用一次。返回 YES 表示生命周期 EGL 已切换到 MobileGlues 前端。
static BOOL ame_mgBootstrap(EGLDisplay dpy, EGLConfig config) {
    if (ame_mgBootstrapTried) return ame_mgFrontendActive;
    ame_mgBootstrapTried = YES;

    if (ame_mg_handle == NULL || ame_mg_init_gles == NULL) {
        NSLog(@"[MG-Bridge] bootstrap skipped: frontend image or mg_init_gles unavailable "
              @"-- EGL stays on raw ANGLE (legacy behavior)");
        return NO;
    }
    if (ame_raw_create_pbuffer == NULL || ame_raw_create_context == NULL ||
        ame_raw_make_current == NULL || ame_raw_destroy_context == NULL ||
        ame_raw_destroy_surface == NULL) {
        NSLog(@"[MG-Bridge] bootstrap skipped: raw ANGLE pointers incomplete -- EGL stays on raw ANGLE");
        return NO;
    }

    // 1) 临时 pbuffer + ES3 上下文（raw ANGLE）：唯一目的是让 mg_init_gles() 的
    //    caps 查询（glGetString 等）发生在"有当前上下文"的正确环境里。
    const EGLint pbAttribs[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface pb = ame_raw_create_pbuffer(dpy, config, pbAttribs);
    const EGLint tmpCtxAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext tmpCtx = (pb != EGL_NO_SURFACE)
        ? ame_raw_create_context(dpy, config, EGL_NO_CONTEXT, tmpCtxAttribs)
        : EGL_NO_CONTEXT;

    BOOL ok = NO;
    if (pb != EGL_NO_SURFACE && tmpCtx != EGL_NO_CONTEXT &&
        ame_raw_make_current(dpy, pb, pb, tmpCtx)) {
        // 2) 绑定 gles/egl 后端句柄 + 真实 caps 检测（MobileGlues 内部幂等）
        ame_mg_init_gles();
        ok = YES;
        NSLog(@"[MG-Bridge] bootstrap: mg_init_gles complete under throwaway ES context "
              @"(GLES/ANGLE handles bound, caps detected)");
    } else {
        NSLog(@"[MG-Bridge] bootstrap FAILED (pbuffer=%p ctx=%p, eglError=0x%x) "
              @"-- EGL stays on raw ANGLE (legacy behavior)",
              (void *)pb, (void *)tmpCtx,
              (unsigned int)(uintptr_t)handle.eglGetError());
    }

    // 3) 无论成败都释放临时资源（MobileGlues 从未见过它们，无残留状态）
    if (pb != EGL_NO_SURFACE || tmpCtx != EGL_NO_CONTEXT) {
        ame_raw_make_current(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (tmpCtx != EGL_NO_CONTEXT) ame_raw_destroy_context(dpy, tmpCtx);
        if (pb != EGL_NO_SURFACE) ame_raw_destroy_surface(dpy, pb);
    }
    if (!ok) return NO;

    // 4) 把生命周期 EGL 切换到 MobileGlues 前端（此后 eglCreateContext 会建立
    //    MGContext 记录、eglMakeCurrent 会绑定 g_current_ctx 与每上下文子系统，
    //    eglSwapBuffers 走 presentSurface）。任一符号缺失则单独回退 raw。
    void *fn = NULL;
    #define AME_MG_SWAP(field, name)                                                  \
        do {                                                                          \
            fn = dlsym(ame_mg_handle, name);                                          \
            if (fn != NULL) { handle.field = fn; }                                    \
            else NSLog(@"[MG-Bridge] frontend " name " missing -- raw ANGLE retained"); \
        } while (0)
    AME_MG_SWAP(eglBindAPI,        "eglBindAPI");
    AME_MG_SWAP(eglCreateContext,  "eglCreateContext");
    AME_MG_SWAP(eglDestroyContext, "eglDestroyContext");
    AME_MG_SWAP(eglMakeCurrent,    "eglMakeCurrent");
    AME_MG_SWAP(eglSwapBuffers,    "eglSwapBuffers");
    AME_MG_SWAP(eglSwapInterval,   "eglSwapInterval");
    #undef AME_MG_SWAP

    ame_mgFrontendActive = YES;
    NSLog(@"[MG-Bridge] EGL lifecycle routed through MobileGlues frontend "
          @"(MGContext tracking + presentSurface active)");
    return YES;
}

static bool gl_init() {
    if (!dlsym_EGL()) {
        return false;
    }

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
    // ANGLE / Mithril / MobileGL 导出的都是 desktop OpenGL，走 EGL_OPENGL_BIT +
    // eglBindAPI(EGL_OPENGL_API)；其余（gl4es / MobileGlues / LTW）是 OpenGL ES。
    BOOL desktopGL = isDesktopGLRenderer(renderer.UTF8String);
    BOOL mobileGL = isMobileGLRenderer(renderer.UTF8String);

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, desktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    // Task 36：在首个前端 EGL 调用（eglBindAPI）之前完成 MobileGlues 引导 ——
    // 绑定后端句柄 + caps 检测 + 把生命周期指针切到前端。
    // 必须位于此处：config 已可用（引导需要），eglBindAPI/eglCreateContext
    // 尚未发生（前端函数内部 LOAD_EGL 静态指针需要后端已绑定）。
    ame_mgBootstrap(g_EglDisplay, bundle->config);

    EGLBoolean bindResult;
    if (desktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: %p\n", handle.eglGetError());

    CALayer *layer = SurfaceViewController.surface.layer;
    // MobileGL 的 eglCreateWindowSurface 不会从 CALayer 推断尺寸，必须显式给出
    // 像素宽高（乘 contentsScale，与 drawableSize 保持一致），否则 surface 会按
    // 1x1 创建，进世界后画面异常。其余渲染器从 layer 自行推断，传 NULL。
    const EGLint mobileGLSurfaceAttribs[] = {
        EGL_WIDTH, (EGLint)MAX(1.0, round(layer.bounds.size.width * layer.contentsScale)),
        EGL_HEIGHT, (EGLint)MAX(1.0, round(layer.bounds.size.height * layer.contentsScale)),
        EGL_NONE
    };
    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config,
        (__bridge EGLNativeWindowType)layer, mobileGL ? mobileGLSurfaceAttribs : NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    // 黑屏取证（Task 32）：surface 创建成功时，把呈现目标的完整状态记入日志——
    // layer 指针/bounds/contentsScale/drawableSize/是否已在窗口层级。
    // 若后续黑屏，对照此处即可判断 layer 尺寸/层级在上下文创建时是否就已经不对。
    {
        BOOL isMetal = [layer isKindOfClass:CAMetalLayer.class];
        CGSize drawable = isMetal ? ((CAMetalLayer *)layer).drawableSize : CGSizeZero;
        UIView *layerView = layer.delegate;  // CALayer.delegate == owning UIView
        BOOL inWindow = (layerView != nil && [(UIView *)layerView window] != nil);
        NSLog(@"[RenderDiag] EGL window surface created: surface=%p layer=%p bounds=%.0fx%.0f contentsScale=%.2f drawableSize=%.0fx%.0f ownerInWindow=%d",
              (void *)bundle->surface, (__bridge void *)layer,
              layer.bounds.size.width, layer.bounds.size.height,
              (double)layer.contentsScale, drawable.width, drawable.height, (int)inWindow);
        // Task 36 取证：surface 在 EGL 侧的真实尺寸（MC RenderPearl 的表面配置
        // 报 1180x820，若此处 eglQuerySurface 报 2360x1640 则存在 2x 不匹配，
        // 下一轮设备日志可据此判断合成/缩放行为）。
        if (ame_raw_query_surface != NULL && bundle->surface != EGL_NO_SURFACE) {
            EGLint sw = 0, sh = 0;
            if (ame_raw_query_surface(g_EglDisplay, bundle->surface, EGL_WIDTH, &sw) &&
                ame_raw_query_surface(g_EglDisplay, bundle->surface, EGL_HEIGHT, &sh)) {
                NSLog(@"[RenderDiag] eglQuerySurface: %dx%d", sw, sh);
            }
        }
    }

    const EGLint gles_ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    // MobileGL 走真正的 desktop GL：要求 3.3 Core Profile。
    // Mithril 同样导出 desktop GL 3.3 Core，但其 EGLConfig 已同时声明
    // EGL_OPENGL_BIT | EGL_OPENGL_ES3_BIT，沿用 ES 版的 CLIENT_VERSION=3 即可
    // （与 Uniaball 官方 launcher-patch 中验证过的配置保持一致）。
    const EGLint desktop_ctx_attribs[] = {
        EGL_CONTEXT_MAJOR_VERSION, 3,
        EGL_CONTEXT_MINOR_VERSION, 3,
        EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT,
        mobileGL ? desktop_ctx_attribs : gles_ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
        if (ame_mgFrontendActive) {
            NSLog(@"[MG-Bridge] eglMakeCurrent via frontend OK (ctx=%p) -- "
                  @"MGContext tracked, per-context state bound",
                  (void *)bundle->context);
        }

        // MobileGlues 2.0: on Apple, init GL ES function pointers now that
        // we have a current context.  mg_init_gles() uses RTLD_DEFAULT to
        // resolve ANGLE's GLES symbols and queries GL version/extensions.
        // Only runs once; subsequent calls are a no-op.
        // (Task 36 引导成功后这里是无害的 no-op；引导失败时仍是原始兜底路径。)
        static BOOL mgInitialized = NO;
        if (!mgInitialized) {
            mgInitialized = YES;
            typedef void (*mg_init_gles_t)(void);
            mg_init_gles_t fn = (mg_init_gles_t)dlsym(RTLD_DEFAULT, "mg_init_gles");
            if (fn) {
                fn();
                NSLog(@"[gl_bridge] mg_init_gles() called after eglMakeCurrent");
            } else {
                NSLog(@"[gl_bridge] mg_init_gles not found (old MobileGlues?)");
            }
        }

        // 帧率解锁关键点：在 EGL context 首次变为 current 后立即设置 swap interval=0。
        //
        // 为什么必须在这里设置（而不是等 MC 调用 glfwSwapInterval 时才设置）：
        //
        // 对于 zink 渲染器（Mesa 21.0），Vulkan swapchain 是延迟创建的——
        // 在第一次 eglSwapBuffers 或需要 swapchain 时才创建。
        // zink 创建 swapchain 时会根据当前 eglSwapInterval 的值选择 present mode：
        //   - interval=0 → VK_PRESENT_MODE_IMMEDIATE_KHR（不等 vsync，帧率可超 60）
        //   - interval=1 → VK_PRESENT_MODE_FIFO_KHR（等 vsync，锁在屏幕刷新率）
        //
        // 如果等 MC 调用 glfwSwapInterval(1) → pojavSwapInterval(0) → eglSwapInterval(0)
        // 时才设置，swapchain 可能已经用默认的 FIFO 创建了。
        // Mesa 21.0 的 zink 不会在 eglSwapInterval 变化时重建 swapchain，
        // 导致 present mode 固定为 FIFO，帧率被锁死在屏幕刷新率（60Hz/120Hz）。
        //
        // 在 gl_make_current 中提前设置 eglSwapInterval(0)，可确保 zink 创建
        // swapchain 时读到 interval=0，从而选择 IMMEDIATE present mode。
        //
        // 这对 ANGLE Metal 后端也有效（ANGLE 在 interval=0 时不等 vsync）。
        if (getenv("POJAV_DISABLE_VSYNC") && strcmp(getenv("POJAV_DISABLE_VSYNC"), "1") == 0) {
            static BOOL s_loggedInitialSwapInterval = NO;
            handle.eglSwapInterval(g_EglDisplay, 0);
            if (!s_loggedInitialSwapInterval) {
                s_loggedInitialSwapInterval = YES;
                NSLog(@"[gl_bridge] eglSwapInterval(0) set immediately after eglMakeCurrent (POJAV_DISABLE_VSYNC=1, renderer=%s)", getenv("AMETHYST_RENDERER") ?: "<unset>");
            }
        }
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    // currentBundle 只在 eglMakeCurrent 成功后赋值。若 MC 在 MakeCurrent 之前
    // （或 MakeCurrent(NULL) 释放之后）调用 swap，这里解引用空指针会直接段错误。
    // SDL3 路径下 SDL_GL_SwapWindow 由我们接管，调用时机不再由 GLFW 约束，
    // 所以必须显式防护。
    if (currentBundle == NULL) {
        NSLog(@"EGLBridge: gl_swap_buffers called with no current context, ignored");
        return;
    }
    // 黑屏取证（Task 32）：记录每次 swap 的真实结果。
    // 成功：首次打一条日志（证明呈现路径至少活过一次）；之后交给原子计数器，
    // 由 SurfaceViewController 的 [RenderDiag] 5 秒心跳汇总上报。
    // 失败：任意错误码都打（去掉旧版 EGL_BAD_SURFACE 过滤），前 10 次逐条打，
    // 之后每 100 次打一条，避免日志爆炸。
    ame_task41_swap_forensics(currentBundle->gl.surface,
                              atomic_load(&g_eglSwapOK) + atomic_load(&g_eglSwapFail) + 1);
    EGLBoolean swapResult = handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface);
    if (!swapResult) {
        unsigned long fails = atomic_fetch_add(&g_eglSwapFail, 1) + 1;
        unsigned int eglErr = (unsigned int)(uintptr_t)handle.eglGetError();
        if (fails <= 10 || fails % 100 == 0) {
            NSLog(@"[RenderDiag] eglSwapBuffers FAILED #%lu eglError=0x%x surface=%p (render loop alive, presentation broken)",
                  fails, eglErr, (void *)currentBundle->gl.surface);
        }
        return;
    }
    unsigned long oks = atomic_fetch_add(&g_eglSwapOK, 1) + 1;
    if (oks == 1) {
        NSLog(@"[RenderDiag] first eglSwapBuffers OK surface=%p (presentation path confirmed)",
              (void *)currentBundle->gl.surface);
    }
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
