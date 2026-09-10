#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include <string.h>
#include <time.h>
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
// Task 50：GL 呈现层所有权标志（跨线程）。
//
// currentBundle（bridge_tbl.h）是 __thread 的——只在渲染线程非空，
// 主线程（updateSavedResolution）读它永远得到 NULL。因此需要一个跨线程
// 的原子标志：GL 路径在 gl_init_context 成功创建 surface 后置位，
// gl_terminate 清零。SurfaceViewController 据此判断"GL 拥有呈现层"，
// 并把 layer 对齐到 1x 点数（Task 50 单一事实源几何，详见 gl_init_context
// 内的 Task50 大注释）。Vulkan 路径不创建 EGL surface → 标志恒 0 →
// 主线程保持旧的 2x 行为（MoltenVK 自管 drawableSize，互不干扰）。
// ============================================================================
static _Atomic int g_ame50_gl_owns_layer = 0;

bool ame_gl_surface_owns_layer(void) {
    return atomic_load(&g_ame50_gl_owns_layer) != 0;
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
typedef void (*ame_es_bindtex_t)(unsigned int, unsigned int);
typedef void (*ame_es_texparami_t)(unsigned int, unsigned int, int);
typedef void (*ame_es_gentex_t)(int, unsigned int *);
typedef void (*ame_es_deltex_t)(int, const unsigned int *);
typedef void (*ame_es_teximg2d_t)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *);
typedef void (*ame_es_genfb_t)(int, unsigned int *);
typedef void (*ame_es_delfb_t)(int, const unsigned int *);
typedef void (*ame_es_fbtex2d_t)(unsigned int, unsigned int, unsigned int, unsigned int, int);
typedef unsigned int (*ame_es_checkfb_t)(unsigned int);

typedef struct {
    ame_es_getint_t    getIntegerv;
    ame_es_bindfb_t    bindFramebuffer;
    ame_es_readpx_t    readPixels;
    ame_es_geterr_t    getError;
    ame_es_isenabled_t isEnabled;
    ame_es_enable_t    enable;
    ame_es_blitfb_t    blitFramebuffer;
    EGLBoolean (*querySurface)(EGLDisplay, EGLSurface, EGLint, EGLint *);
    ame_es_bindtex_t   bindTexture;        // Task 49 几何自愈
    ame_es_texparami_t texParameteri;      // Task 49 几何自愈
    ame_es_gentex_t    genTextures;        // Task 49 几何自愈
    ame_es_deltex_t    deleteTextures;     // Task 49 几何自愈
    ame_es_teximg2d_t  texImage2D;         // Task 49 几何自愈
    ame_es_genfb_t     genFramebuffers;    // Task 49 几何自愈
    ame_es_delfb_t     deleteFramebuffers; // Task 49 几何自愈
    ame_es_fbtex2d_t   framebufferTexture2D; // Task 49 几何自愈
    ame_es_checkfb_t   checkFramebufferStatus; // Task 49 几何自愈
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
    // Task 49：几何自愈 blit 需要的 FBO/纹理管理函数（同源 libGLESv2/ANGLE）
    s_es.bindTexture     = (ame_es_bindtex_t)dlsym(h, "glBindTexture");
    s_es.texParameteri   = (ame_es_texparami_t)dlsym(h, "glTexParameteri");
    s_es.genTextures     = (ame_es_gentex_t)dlsym(h, "glGenTextures");
    s_es.deleteTextures  = (ame_es_deltex_t)dlsym(h, "glDeleteTextures");
    s_es.texImage2D      = (ame_es_teximg2d_t)dlsym(h, "glTexImage2D");
    s_es.genFramebuffers = (ame_es_genfb_t)dlsym(h, "glGenFramebuffers");
    s_es.deleteFramebuffers = (ame_es_delfb_t)dlsym(h, "glDeleteFramebuffers");
    s_es.framebufferTexture2D = (ame_es_fbtex2d_t)dlsym(h, "glFramebufferTexture2D");
    s_es.checkFramebufferStatus = (ame_es_checkfb_t)dlsym(h, "glCheckFramebufferStatus");
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

// ============================================================================
// Task 49：几何自愈 blit（scratch-FBO 两段中转）
//
// latestlog 53febda（d11eb66）铁证：MC 的帧确实在后缓冲里，但只覆盖
// viewport 区域（1180x820，SDL3 点数），而表面是 2x 像素（2360x1640 或
// 1640x2360）——帧占后缓冲左上 ~25%，其余永远平坦暗色（corner=27，近乎黑）。
// 用户看到的就是"黑屏"。旧版 mode-2 blit 直接 READ=drawFb → DRAW=0，
// 但实测 drawFb==0（MC 交换时刻绑定回默认帧缓冲）→ blit 变成 FBO0→FBO0
// 自拷贝，矩形重叠 = ES 非法/无操作，且旧 latch 判据永不满足 → 自愈从未
// 启动。
//
// 新设计（几何判定，零回读、每帧确定性）：
//   viewport 维度 != surface 维度 → 帧无法覆盖后缓冲 → 启用两段 blit：
//     段1: READ = (drawFb ? drawFb : 0) 的 viewport 区域 → scratch（缩放到 surface 尺寸）
//     段2: READ = scratch → DRAW = FBO 0 全表面（1:1）
//   两段各自无矩形重叠，ES3 合法。帧被放大铺满整个后缓冲 = 全屏可见，
//   无论 1x/2x 尺寸单位失配、竖横转置、创建竞态还是旋转残留。
//   表面尺寸变化时 scratch 懒重建（glTexImage2D 同名重分配）。
// ============================================================================
static unsigned int g_ame49_scratch_fb = 0;
static unsigned int g_ame49_scratch_tex = 0;
static int g_ame49_scratch_w = 0, g_ame49_scratch_h = 0;
static int g_ame49_heal_disabled = 0;   // scratch FBO 完整性失败后的永久熔断
// Task51：呈现 layer 引用（CFBridgingRetain）。声明前置——swap 诊断函数
//（Fix F' 钉扎与 hierarchy dump）在本文件更早处使用，原声明位置（Task48
// 段内）在使用点之后，b9634f4 CI 实测报 undeclared identifier。
static void *g_ame48_layer_cf = NULL;

// Task52：来自 sdl3_hook.m —— 嵌入的 SDL 触摸视图（可见性卫兵 z 序执法用）。
// 返回值是 __bridge 裸指针，只做同一性比较，不得解引用为 ARC 对象持有。
extern void *ame_hook_getEmbeddedSDLView(void);

static void ame_task49_geo_heal_blit(ame_es_t es, int drawFb, int readFb,
                                     int vw, int vh, int sw, int sh) {
    if (g_ame49_heal_disabled) return;
    if (es.genFramebuffers == NULL || es.genTextures == NULL ||
        es.texImage2D == NULL || es.framebufferTexture2D == NULL ||
        es.checkFramebufferStatus == NULL || es.bindTexture == NULL ||
        es.texParameteri == NULL || es.blitFramebuffer == NULL) {
        g_ame49_heal_disabled = 1;   // 函数指针不全：熔断（创建执法/卫兵钉扎仍在）
        return;
    }
    // 1) scratch 尺寸跟随 surface（懒创建 / 尺寸变化时重分配）
    if (g_ame49_scratch_fb == 0 || g_ame49_scratch_w != sw || g_ame49_scratch_h != sh) {
        if (g_ame49_scratch_fb == 0) {
            es.genFramebuffers(1, &g_ame49_scratch_fb);
            es.genTextures(1, &g_ame49_scratch_tex);
        }
        es.bindTexture(0x0DE1 /*GL_TEXTURE_2D*/, g_ame49_scratch_tex);
        es.texImage2D(0x0DE1, 0, 0x8058 /*GL_RGBA8*/, sw, sh, 0,
                      0x1908 /*GL_RGBA*/, 0x1401 /*GL_UNSIGNED_BYTE*/, NULL);
        es.texParameteri(0x0DE1, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
        es.texParameteri(0x0DE1, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601 /*GL_LINEAR*/);
        es.bindFramebuffer(0x8D40 /*GL_FRAMEBUFFER*/, g_ame49_scratch_fb);
        es.framebufferTexture2D(0x8D40, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/,
                                0x0DE1, g_ame49_scratch_tex, 0);
        if (es.checkFramebufferStatus(0x8D40) != 0x8CD5 /*GL_FRAMEBUFFER_COMPLETE*/) {
            NSLog(@"[RenderDiag] Task49 scratch FBO incomplete %dx%d -- geo-heal fused off", sw, sh);
            es.bindFramebuffer(0x8D40, (unsigned)drawFb);
            while (es.getError() != 0) {}
            if (g_ame49_scratch_fb != 0) es.deleteFramebuffers(1, &g_ame49_scratch_fb);
            if (g_ame49_scratch_tex != 0) es.deleteTextures(1, &g_ame49_scratch_tex);
            g_ame49_scratch_fb = 0; g_ame49_scratch_tex = 0;
            g_ame49_scratch_w = 0; g_ame49_scratch_h = 0;
            g_ame49_heal_disabled = 1;
            return;
        }
        g_ame49_scratch_w = sw; g_ame49_scratch_h = sh;
        NSLog(@"[RenderDiag] Task49 scratch FBO ready %dx%d", sw, sh);
    }
    // 2) scissor 保存/关闭 + 两段 blit
    int scissorWasOn = es.isEnabled(0x0C11 /*GL_SCISSOR_TEST*/);
    if (scissorWasOn) es.enable(0x0C11, 0 /*GL_FALSE*/);
    // 段1：MC 帧（viewport 区域，源 = MC 当前 FBO 或 FBO 0）→ scratch 全尺寸缩放
    es.bindFramebuffer(0x8CA8 /*GL_READ_FRAMEBUFFER*/, (unsigned)(drawFb != 0 ? drawFb : 0));
    es.bindFramebuffer(0x8CA9 /*GL_DRAW_FRAMEBUFFER*/, g_ame49_scratch_fb);
    es.blitFramebuffer(0, 0, vw, vh, 0, 0, sw, sh,
                       0x4000 /*GL_COLOR_BUFFER_BIT*/, 0x2601 /*GL_LINEAR*/);
    // 段2：scratch → FBO 0 全表面 1:1
    es.bindFramebuffer(0x8CA8, g_ame49_scratch_fb);
    es.bindFramebuffer(0x8CA9, 0);
    es.blitFramebuffer(0, 0, sw, sh, 0, 0, sw, sh,
                       0x4000, 0x2601 /*GL_LINEAR*/);
    unsigned int blitErr = es.getError();
    // 3) 状态恢复
    es.bindFramebuffer(0x8CA8, (unsigned)readFb);
    es.bindFramebuffer(0x8CA9, (unsigned)drawFb);
    if (scissorWasOn) es.enable(0x0C11, 1 /*GL_TRUE*/);
    while (es.getError() != 0) {}
    static unsigned long s_blitLogs = 0;
    s_blitLogs++;
    if (s_blitLogs <= 3 || s_blitLogs % 300 == 0 || blitErr != 0) {
        NSLog(@"[RenderDiag] geo-heal blit #%lu (Task49): srcFb=%d %dx%d -> scratch %dx%d -> FBO0 %dx%d blitErr=0x%x",
              s_blitLogs, drawFb, vw, vh, sw, sh, sw, sh, blitErr);
    }
}

// ============================================================================
// Task 53：EGL 表面重对齐（画面分裂 + 输入异常根因根治）
//
// 设备铁证（latestlog f4ab8e3，iPad Air M4 / iPadOS 26.6，Task52 修复黑屏
// 后的首轮真机日志）：
//   - 表面创建时 1180x820（eglQuerySurface 双确认），但首次交换时已转置为
//     820x1180 且 1400+ 帧锁死永不恢复（转置发生在加载期"无 swap 的盲窗"
//     ——窗口事件/UIKit 布局瞬时竖屏，ANGLE 随 layer 重读几何时捕获转置
//     值，Task48 已证其转置后不随 layer 回横屏）；
//   - MC viewport 恒 1180x820：帧被裁到转置后缓冲左侧 820 列，Task49
//     geo-heal blit 再把整帧压扁铺进 820x1180；
//   - drawableSize 拉锯战：updateSavedResolution（写 bounds 横屏 1180x820）
//     vs Task52 guard（写 surface 转置值 820x1180，每 200 帧互覆）→
//     drawable 为横屏的帧：blit 只覆盖左侧 820x820，右侧 360 列残留原始
//     帧内容 = 用户看到的"画面分裂"（左半压扁 + 右半残影）；
//   - 触摸按全窗口 1180x820 点空间映射（Task51 px->pt 换算本身正确），
//     所见画面却错位/压扁 → 点不中所见按钮 = "输入异常"。
//
// 修复（治本——消灭转置本身，让全部补偿机制回到无害 no-op）：
//   几何失配首检出时销毁优先重建 EGL window surface。Task48 重建恒败
//   （EGL_BAD_ALLOC 0x3003）的根因是"先建后毁"——同 layer 双 surface
//   并存；销毁优先（先 MakeCurrent 解绑再销毁）则层自由，创建必成：
//     1) 主线程 dispatch_sync 钉扎 layer（contentsScale=1.0、drawableSize=
//        bounds 点数）——Task50 已证主线程写是唯一可靠写入路径；
//     2) eglMakeCurrent(无表面) 解绑 → eglDestroySurface(旧) →
//        eglCreateWindowSurface（读钉扎后的横屏 layer）→ eglMakeCurrent
//        (新表面)（经 Task36 前端路由，MGContext 跟踪保持；前端
//        MakeCurrent 对 EGL_NO_SURFACE 纯透传，安全）；
//     3) 成功后 surface == viewport == drawable == bounds：几何失配判定
//        不再触发、geo-heal 自动退出（Task50 latch 恢复分支）、拉锯战
//        自然终止（两写者写同值）、画面 1:1 全屏、触摸坐标与所见画面对齐
//        （输入随几何自愈）；
//     4) 失败兜底：预算 3 次 + 2s 限速 + 链路任一步失败即永久熔断，回退
//        Task49/51/52 既有补偿路径（行为不劣于修复前，零回归）。
// ============================================================================
static int      g_ame53_attempts = 0;    // 已消耗的重试预算
static uint64_t g_ame53_last_ms = 0;     // 上次尝试时刻（2s 限速）
static int      g_ame53_disabled = 0;    // 熔断：预算耗尽或链路失败
static int      g_ame53_transposed = 0;  // surface 与 MC viewport 失配标志
//（供 updateSavedResolution 判断停火——失配未治愈期间让 Task52 guard
//  独占 drawableSize 写权，终结拉锯战；由交换路径逐帧刷新）

bool ame_gl_surface_transposed(void) {
    return g_ame53_transposed != 0;
}

static uint64_t ame53_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)ts.tv_nsec / 1000000ull;
}

/// 销毁优先的表面重对齐。调用方：MC 渲染线程（swap 路径、上下文 current）。
/// 返回 YES = 表面已重建对齐（调用方把 latch mode 复位为 0，下一帧重评）。
static BOOL ame_task53_realign_surface(void) {
    if (g_ame53_disabled) return NO;
    if (g_ame53_attempts >= 3) {
        g_ame53_disabled = 1;
        NSLog(@"[GLGeo] Task53 realign: budget exhausted after %d attempts -- fused off, compensation path continues", g_ame53_attempts);
        return NO;
    }
    uint64_t now = ame53_now_ms();
    if (g_ame53_last_ms != 0 && now - g_ame53_last_ms < 2000) return NO;
    g_ame53_last_ms = now;
    g_ame53_attempts++;

    basic_render_window_t *bundle = currentBundle;
    CALayer *layer = (__bridge CALayer *)g_ame48_layer_cf;
    if (bundle == NULL || layer == nil || ![layer isKindOfClass:CAMetalLayer.class]) {
        NSLog(@"[GLGeo] Task53 realign: prerequisites missing (bundle/layer) -- fused off");
        g_ame53_disabled = 1;
        return NO;
    }

    NSLog(@"[GLGeo] Task53 realign: attempt %d/3 (destroy-first recreate, locked transposed surface)", g_ame53_attempts);

    // 1) 主线程钉扎（Task50 同款可靠路径）：contentsScale=1.0 +
    //    drawableSize=bounds 点数。重建的表面读此值 → 横屏尺寸。
    __block CGSize pin53 = CGSizeZero;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            CAMetalLayer *ml53 = (CAMetalLayer *)layer;
            CGFloat w53 = MAX(1.0, round(layer.bounds.size.width));
            CGFloat h53 = MAX(1.0, round(layer.bounds.size.height));
            layer.contentsScale = 1.0;
            ml53.drawableSize = CGSizeMake(w53, h53);
            pin53 = CGSizeMake(w53, h53);
        } @catch (NSException *e) {
            NSLog(@"[GLGeo] Task53 pin exception: %@", e);
        }
    });
    if (pin53.width < 1 || pin53.height < 1) {
        NSLog(@"[GLGeo] Task53 realign FAILED: layer pin unavailable -- fused off, compensation continues");
        g_ame53_disabled = 1;
        return NO;
    }

    // 2) 销毁优先重建：同一时刻至多一个 surface 拥有 layer。
    //    先 MakeCurrent 解绑——EGL 的销毁是延迟语义（surface 不再 current
    //    才真正释放对 layer 的占用；跳过这步=Task48 的 EGL_BAD_ALLOC）。
    EGLSurface oldSurface = bundle->gl.surface;
    EGLContext ctx53 = bundle->gl.context;
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx53);
    handle.eglDestroySurface(g_EglDisplay, oldSurface);
    while (handle.eglGetError() != EGL_SUCCESS) {}

    // 3) 重建（与 gl_init_context 同参：MobileGL 需显式宽高，其余传 NULL
    //    让 ANGLE 读 layer；首轮 NULL 失败再试显式宽高兜底）。
    const BOOL mobileGL53 = isMobileGLRenderer(getenv("AMETHYST_RENDERER"));
    EGLSurface newSurface = EGL_NO_SURFACE;
    for (int try53 = 0; try53 < 2 && newSurface == EGL_NO_SURFACE; try53++) {
        const EGLint attribs53[] = {
            EGL_WIDTH,  (EGLint)pin53.width,
            EGL_HEIGHT, (EGLint)pin53.height,
            EGL_NONE
        };
        newSurface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->gl.config,
            (__bridge EGLNativeWindowType)layer,
            (mobileGL53 || try53 > 0) ? attribs53 : NULL);
        if (newSurface == EGL_NO_SURFACE) {
            NSLog(@"[GLGeo] Task53 create attempt %d failed: eglError=0x%x", try53 + 1,
                  (unsigned int)(uintptr_t)handle.eglGetError());
        }
    }
    if (newSurface == EGL_NO_SURFACE) {
        NSLog(@"[GLGeo] Task53 realign FAILED: surface recreation refused after destroy -- fused off (watch [RenderDiag] eglSwapBuffers FAILED lines)");
        g_ame53_disabled = 1;
        return NO;
    }

    // 4) 绑定新表面（Task36 前端路由保持 MGContext 跟踪）并更新 bundle。
    if (!handle.eglMakeCurrent(g_EglDisplay, newSurface, newSurface, ctx53)) {
        NSLog(@"[GLGeo] Task53 realign FAILED: eglMakeCurrent error 0x%x -- fused off",
              (unsigned int)(uintptr_t)handle.eglGetError());
        handle.eglDestroySurface(g_EglDisplay, newSurface);
        g_ame53_disabled = 1;
        return NO;
    }
    bundle->gl.surface = newSurface;
    while (handle.eglGetError() != EGL_SUCCESS) {}

    // 5) 验证（es.querySurface 与交换探针同源，权威值）。
    ame_es_t es53 = ame_es();
    EGLint qw53 = 0, qh53 = 0;
    if (es53.querySurface != NULL &&
        es53.querySurface(g_EglDisplay, newSurface, 0x3056 /*EGL_WIDTH*/, &qw53) &&
        es53.querySurface(g_EglDisplay, newSurface, 0x3057 /*EGL_HEIGHT*/, &qh53)) {
        NSLog(@"[GLGeo] Task53 realign SUCCESS: surface %p -> %p, eglQuerySurface=%dx%d (transposed lock cured; layer bounds %.0fx%.0f)",
              (void *)oldSurface, (void *)newSurface, qw53, qh53, pin53.width, pin53.height);
    } else {
        NSLog(@"[GLGeo] Task53 realign SUCCESS (query unavailable): surface %p -> %p, expected %.0fx%.0f",
              (void *)oldSurface, (void *)newSurface, pin53.width, pin53.height);
    }
    return YES;
}

// 探针 + 自愈主入口。swapIndex 从 1 计。
// 0 = undecided, 1 = normal, 2 = geo-heal blit
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

    // Task 49：几何失配判定（每帧、零回读、确定性）。
    // viewport 维度 != surface 维度 → MC 的帧无法铺满后缓冲（1x/2x 尺寸单位
    // 失配或竖横转置——latestlog 53febda 的确切形态）→ 立即启用 geo-heal。
    // 此判定优先于一切 latch：几何不匹配时“FBO 0 有内容”也不等于可见。
    const BOOL geoMismatch = (viewport[2] > 0 && viewport[3] > 0 &&
                              surfW > 0 && surfH > 0 &&
                              (viewport[2] != surfW || viewport[3] != surfH));
    g_ame53_transposed = geoMismatch ? 1 : 0;
    if (!geoMismatch) {
        // Task53：对齐帧重置冷却——下一个失配剧集（几何从对齐转为失配）立即可
        // 重试。否则冷却期被跳过的尝试会让 mode 卡在 2（补偿态不重入分支），
        // realign 永远失去重臂机会（逻辑测试 S3 场景实测暴露）。
        g_ame53_last_ms = 0;
    }
    if (geoMismatch && s_mode != 2) {
        // Task 53（画面分裂根治）：几何失配首检出时先治本——销毁优先重建
        // 被转置锁死的 EGL surface。成功后 surface==viewport==drawable==
        // bounds，Task49 heal / Task51 present-align / Task52 guard 的补偿
        // 全部回到 no-op，drawableSize 拉锯战自然终止（两写者写同值）。
        if (ame_task53_realign_surface()) {
            // 表面已对齐：mode 复位，下一帧重新 latch（几何对齐 + FBO0 有
            // 内容 → NORMAL，geo-heal 经 Task50 恢复分支自动退出）。
            s_mode = 0;
            g_ame53_transposed = 0;
            // 刷新本地 surfW/surfH：下方探针 / hierarchy / guard 全部输出新
            // 表面的真实状态。surface 形参此时是已销毁的旧句柄，改查
            // currentBundle 里的新表面。
            basic_render_window_t *b53 = currentBundle;
            if (b53 != NULL && es.querySurface != NULL && b53->gl.surface != EGL_NO_SURFACE) {
                EGLint sw53 = 0, sh53 = 0;
                if (es.querySurface(g_EglDisplay, b53->gl.surface, 0x3056 /*EGL_WIDTH*/, &sw53) &&
                    es.querySurface(g_EglDisplay, b53->gl.surface, 0x3057 /*EGL_HEIGHT*/, &sh53)) {
                    surfW = sw53;
                    surfH = sh53;
                }
            }
            NSLog(@"[RenderDiag] Task53 realign applied: viewport=%dx%d surface=%dx%d (mode reset; expect NORMAL latch next frame)",
                  viewport[2], viewport[3], surfW, surfH);
        } else {
        NSLog(@"[RenderDiag] Task49 geo mismatch ENGAGED: viewport=%dx%d surface=%dx%d (was mode=%d) -- frame covers only %.0f%% of backbuffer",
              viewport[2], viewport[3], surfW, surfH, s_mode,
              100.0 * (double)viewport[2] * (double)viewport[3] / ((double)surfW * (double)surfH));
        s_mode = 2;
        // Task51 Fix F'：转置固化时让 drawable 跟随 surface（present 自洽）。
        // 证据链：622166a 证伪渲染线程写 drawableSize（CA 提交树分叉，全日志
        // 0 条 "Task48 pin" 生效）；e6886e2 证明主线程写有效（Task50 对齐即
        // 主线程写、eglQuerySurface 立即确认）。故 dispatch_async 主线程
        // 一次性把 drawableSize 钉成 surface 实际尺寸：drawable == backbuffer
        // 纹理 → Metal present 无条件匹配 → 内容上屏。contentsGravity 把
        // surface 尺寸内容拉伸铺 layer bounds，blit 的 squash 与 bounds 拉伸
        // 互逆 → 1:1 无变形显示（仅中间分辨率 1x 软化）。
        // 触发条件 s_mode != 2 保证整个生命周期至多执行一次，无逐帧开销。
        void *ame51_layer_ref = g_ame48_layer_cf;
        if (ame51_layer_ref != NULL) {
            int pw = surfW, ph = surfH;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    CALayer *l = (__bridge CALayer *)ame51_layer_ref;
                    if ([l isKindOfClass:CAMetalLayer.class]) {
                        CAMetalLayer *ml = (CAMetalLayer *)l;
                        CGSize old = ml.drawableSize;
                        if ((int)round(old.width) != pw || (int)round(old.height) != ph) {
                            ml.drawableSize = CGSizeMake((CGFloat)pw, (CGFloat)ph);
                            NSLog(@"[GLGeo] Task51 present-align (main thread): drawableSize %.0fx%.0f -> %dx%d == surface (drawable==backbuffer, present self-consistent)",
                                  old.width, old.height, pw, ph);
                        } else {
                            NSLog(@"[GLGeo] Task51 present-align: already aligned %dx%d (drawable==surface)", pw, ph);
                        }
                    }
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task51 present-align exception: %@", e);
                }
            });
        }
        }  // Task53 else：重对齐不可用/失败 → 既有补偿路径（行为不变）
    }

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

        // FBO 0 readback：Task 49 修正探针位置——改探 viewport 中心（MC 帧
        // 实际所在区域；53febda 铁证：旧探 surface 中心/远角落在帧区域之外，
        // 把“帧在左上 25%”误诊成“FBO 0 全平坦”），远角保留作覆盖率诊断。
        es.bindFramebuffer(0x8D40 /*GL_FRAMEBUFFER*/, 0);
        unsigned char fb0[8 * 8 * 4];
        int fb0Uniq = 0, fb0Err = 0;
        int fx = viewport[0] + viewport[2] / 2 - 4;
        int fy = viewport[1] + viewport[3] / 2 - 4;
        if (fx < 0) fx = 0;
        if (fy < 0) fy = 0;
        if (fx + 8 > surfW) fx = (surfW > 8) ? (surfW - 8) : 0;
        if (fy + 8 > surfH) fy = (surfH > 8) ? (surfH - 8) : 0;
        es.readPixels(fx, fy, 8, 8, 0x1908, 0x1401, fb0);
        fb0Err = (int)es.getError();
        if (fb0Err == 0) fb0Uniq = ame_count_unique_rgba(fb0, 64);
        unsigned char corner[8 * 8 * 4];
        int cornerUniq = 0;
        es.readPixels((surfW > 12) ? (surfW - 12) : 0, (surfH > 12) ? (surfH - 12) : 0,
                      8, 8, 0x1908, 0x1401, corner);
        if (es.getError() == 0) cornerUniq = ame_count_unique_rgba(corner, 64);
        es.bindFramebuffer(0x8D40, (unsigned)drawFb);   // 恢复
        while (es.getError() != 0) {}

        NSLog(@"[RenderDiag] swap#%lu (Task41): drawFb=%d readFb=%d viewport=%d,%d %dx%d surface=%dx%d cur=(uniq=%d err=0x%x) fbo0vp=(uniq=%d corner=%d err=0x%x) mode=%d",
              swapIndex, drawFb, readFb, viewport[0], viewport[1], viewport[2], viewport[3],
              surfW, surfH, curUniq, curErr, fb0Uniq, cornerUniq, fb0Err, s_mode);

        // Task51 取证：呈现层可见性全量 dump（首帧 + 每 500 帧，主线程执行）。
        // 动机：连续四轮日志（48/49/50/51 基线）都显示"GL 全绿 + present 成功"
        // 但用户黑屏——断点极可能在 UIKit 呈现层（layer 不在树 / 被遮挡 /
        // hidden / transform 旋转 / window 不显示）。本 dump 一次打印全部
        // 可见性关键状态，下轮日志无论好坏都能一锤定音。
        if (swapIndex == 1 || (swapIndex > 0 && swapIndex % 500 == 0)) {
            void *ame51_h_layer = g_ame48_layer_cf;
            int h_sw = surfW, h_sh = surfH;
            unsigned long h_idx = swapIndex;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    CALayer *l = (__bridge CALayer *)ame51_h_layer;
                    if (l == nil) {
                        NSLog(@"[GLGeo] Task51 hierarchy #%lu: render layer is NIL", h_idx);
                        return;
                    }
                    NSMutableString *chain = [NSMutableString stringWithCapacity:256];
                    CALayer *cur = l;
                    int depth = 0;
                    while (cur != nil && depth < 10) {
                        [chain appendFormat:@" -> [%@ %dx%d pos=(%d,%d) hid=%d op=%.2f%@]",
                            NSStringFromClass(cur.class),
                            (int)round(cur.bounds.size.width), (int)round(cur.bounds.size.height),
                            (int)round(cur.position.x), (int)round(cur.position.y),
                            (int)cur.hidden, (double)cur.opacity,
                            CATransform3DIsIdentity(cur.transform) ? @"" : @" ROT"];
                        cur = (CALayer *)cur.superlayer;
                        depth++;
                    }
                    NSString *dw = @"n/a";
                    if ([l isKindOfClass:CAMetalLayer.class]) {
                        CAMetalLayer *ml = (CAMetalLayer *)l;
                        dw = [NSString stringWithFormat:@"%.0fx%.0f",
                              ml.drawableSize.width, ml.drawableSize.height];
                    }
                    BOOL inTree = (l.superlayer != nil);
                    NSLog(@"[GLGeo] Task51 hierarchy #%lu: layer=%p drawable=%@ scale=%.2f surface=%dx%d inTree=%d chain=%@",
                          h_idx, ame51_h_layer, dw, (double)l.contentsScale,
                          h_sw, h_sh, (int)inTree, chain);
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task51 hierarchy exception: %@", e);
                }
            });
        }

        // ====================================================================
        // Task 52：呈现层可见性卫兵（每 50 帧一次，主线程异步执行，零渲染阻塞）。
        //
        // 根因（hierarchy dump 实锤，b805f51 日志 8967 行）：CAMetalLayer
        //   hid=1 —— 供应商 libSDL3.dylib 的 Zalith 同源嵌入补丁在每次真实
        //   SDL_CreateWindow / SDL_Metal_CreateView 时按类名查找并
        //   [GameSurfaceView setHidden:YES]（反汇编 @0x152e6c）。GL 帧全部
        //   呈现进这个被隐藏的 layer → 渲染全绿 + 黑屏。
        // 本卫兵持续执法三不变量（嵌入层的步骤 3.5 负责首拍，这里兜住
        //   MetalCreate/后续嵌入重跑/任何外部隐藏者的复发）：
        //   1) 渲染 layer 可见；2) SDL 触摸视图 z 序高于画面层；3)
        //   drawableSize == surface 尺寸（present 自洽，接替一次性 Fix F'，
        //   对抗宿主 updateSavedResolution 的周期性写回）。
        // ====================================================================
        if (swapIndex == 1 || (swapIndex > 0 && swapIndex % 50 == 0)) {
            int g52_sw = surfW, g52_sh = surfH;
            unsigned long g52_idx = swapIndex;
            void *g52_layer = g_ame48_layer_cf;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    // 1) 揭开渲染层（主线程读写，权威值）
                    UIView *g52_gs = [SurfaceViewController surface];
                    if (g52_gs != nil && (g52_gs.hidden || g52_gs.layer.hidden)) {
                        g52_gs.hidden = NO;
                        g52_gs.layer.hidden = NO;
                        NSLog(@"[GLGeo] Task52 guard #%lu: render layer was HIDDEN by external code -- UN-HIDDEN (surface=%dx%d)",
                              g52_idx, g52_sw, g52_sh);
                    }
                    // 2) z 序：SDL 触摸视图必须在画面层之上（否则触摸被画面层截走）
                    UIView *g52_sdl = (__bridge UIView *)ame_hook_getEmbeddedSDLView();
                    if (g52_gs != nil && g52_sdl != nil && g52_gs.superview != nil &&
                        g52_sdl.superview == g52_gs.superview) {
                        NSArray *g52_subs = g52_gs.superview.subviews;
                        NSUInteger g52_gi = [g52_subs indexOfObjectIdenticalTo:g52_gs];
                        NSUInteger g52_si = [g52_subs indexOfObjectIdenticalTo:g52_sdl];
                        if (g52_gi != NSNotFound && g52_si != NSNotFound && g52_gi > g52_si) {
                            [g52_gs.superview insertSubview:g52_gs belowSubview:g52_sdl];
                            NSLog(@"[GLGeo] Task52 guard #%lu: z-order re-pinned (GameSurfaceView below SDL touch view)",
                                  g52_idx);
                        }
                    }
                    // 3) present 自洽：drawableSize == surface 尺寸（持续执法）
                    CALayer *g52_l = (__bridge CALayer *)g52_layer;
                    if (g52_l != nil && [g52_l isKindOfClass:CAMetalLayer.class] &&
                        g52_sw > 0 && g52_sh > 0) {
                        CAMetalLayer *g52_ml = (CAMetalLayer *)g52_l;
                        CGSize g52_old = g52_ml.drawableSize;
                        if (fabs(g52_old.width - (double)g52_sw) > 0.5 ||
                            fabs(g52_old.height - (double)g52_sh) > 0.5) {
                            g52_ml.drawableSize = CGSizeMake(g52_sw, g52_sh);
                            NSLog(@"[GLGeo] Task52 guard #%lu: present-align drawable %.0fx%.0f -> %dx%d (== surface, self-consistent present)",
                                  g52_idx, g52_old.width, g52_old.height, g52_sw, g52_sh);
                        }
                    }
                } @catch (NSException *e) {
                    NSLog(@"[GLGeo] Task52 guard exception: %@", e);
                }
            });
        }

        // latch 判定（Task 49 重写：几何优先，允许降级）
        BOOL fbo0Flat = (fb0Err == 0 && fb0Uniq <= 1);
        BOOL fbo0Content = (fb0Err == 0 && fb0Uniq > 1);
        if (s_mode == 0 && fbo0Content && !geoMismatch) {
            s_mode = 1;
            NSLog(@"[RenderDiag] Task41 latch: NORMAL present (FBO 0 has content at viewport center, geometry aligned)");
        } else if (s_mode == 0 && fbo0Flat && curContent && drawFb != 0) {
            s_mode = 2;
            NSLog(@"[RenderDiag] Task41 latch: GEO-HEAL (MC frame lives in FBO %d, FBO 0 is flat -- blitting every swap)", drawFb);
        } else if (s_mode == 1 && fbo0Flat && curContent && drawFb != 0) {
            // Task 49：降级——曾判 NORMAL，但现在帧从未进后缓冲（留在 MC 自己
            // 的 FBO）→ 重新启用自愈。旧版单向 latch 是自愈永不启动的原因之一。
            s_mode = 2;
            NSLog(@"[RenderDiag] Task41 latch DEMOTED to GEO-HEAL (FBO 0 went flat while MC FBO %d has content)", drawFb);
        } else if (s_mode == 2 && !geoMismatch && fbo0Content) {
            // Task 50：反向恢复——几何已对齐（viewport==surface）且 FBO 0 有
            // 内容 → 退出 geo-heal，停止逐帧 scratch 中转。旧版一旦进入
            // mode=2 便永不退出（几何修复后仍每帧 blit，白耗带宽且状态机
            // 无法回到正常呈现路径）。
            s_mode = 1;
            NSLog(@"[RenderDiag] Task50 heal disengaged: geometry aligned (viewport==surface) and FBO 0 has content -- back to normal present");
        }
    }

    if (s_mode == 2) {
        // Task 49：两段 scratch-FBO blit（源=MC 帧 viewport 区域，缩放铺满 FBO 0）
        ame_task49_geo_heal_blit(es, drawFb, readFb, viewport[2], viewport[3], surfW, surfH);
    }
}

// ============================================================================
// Task 48：呈现几何卫兵（GL 路径黑屏根因修复）
//
// 设备铁证（latestlog 1518ce1，iPad Air M4 / iPadOS 26.6）：
//   - 渲染管线 100% 健康：1032 帧 swap 全成功、fps=57、swapFail=0、GL 零错误、
//     MC 26.3 到标题画面（图集/音效全载入）、fbo 内容探针 uniq=44-49；
//   - [RenderDiag] EGL surface 创建时 = 2360x1640（layer 当时正确，eglQuerySurface
//     证实），但到交换时 surface = 1640x2360（竖屏转置）且 1032 帧永不恢复；
//   - CAMetalLayer 心跳报 drawable=2360x1640（横屏正确）、bounds=1180x820；
//   - MC 的 glViewport = 1180x820（SDL3-on-iOS 以"点"而非"像素"回报窗口尺寸，
//     MC 请求 2360x1640 被钳到 1180x820 → MC 实际以 1x 渲染）。
// 三者互相失配 → 呈现的 backbuffer 维度与 drawable 维度对不上 → 屏幕全黑。
//
// 修复策略（对"谁转置了 surface"不做任何单一假设，全部自愈）：
//   1) 创建钉扎：MobileGlues 渲染器在 eglCreateWindowSurface 前把
//      drawableSize 钉到 layer.bounds（点数）——即 MC 将要渲染的真实尺寸
//      （1180x820）。ANGLE 在创建时刻会读 layer（本日志已证实此读取可靠），
//      于是 surface == MC viewport == drawable，三者一致，画面 1:1 全屏。
//   2) 交换卫兵：每次 eglSwapBuffers 前核对 surface 实际尺寸 vs layer
//      drawableSize，不等则立刻把 drawableSize 钉回 surface 尺寸
//      （drawable 必须等于将要呈现的 backbuffer 尺寸——这是"帧能上屏"的
//      硬约束，无论 ANGLE/MG/旋转把哪边改了都能收敛）。
//   3) 重建升级：若 surface 偏离创建时的期望尺寸并稳定持续 30+ 帧，
//      限速（5s）重建 EGL window surface（先钉 layer，再创建，MG 前端
//      MakeCurrent 重绑，销毁旧表面）——重建是重置 ANGLE 内部表面尺寸的
//      唯一可靠手段。最多 3 次，避免无限循环。
//
// 线程安全：卫兵在 MC 渲染线程（上下文 current）运行；只触碰 CALayer/
// CAMetalLayer API（Apple 明确支持渲染线程驱动 CAMetalLayer），不碰 UIKit。
// layer 指针在创建时以 CFBridgingRetain 缓存，避免渲染线程访问 UIView。
// Vulkan 路径完全不受影响（本文件仅 GL 桥）。
// ============================================================================
//（声明已前置至 Task49 静态区——见 g_ame48_layer_cf）
static int   g_ame48_expected_w = 0;         // 期望表面宽（创建钉扎值）
static int   g_ame48_expected_h = 0;         // 期望表面高
static long  g_ame48_drift_swaps = 0;        // surface != drawable 的连续帧数（纯取证）
static int   g_ame48_recreates = 0;          // 历史保留（Task50 起不再重建）
static uint64_t g_ame48_last_recreate_ms = 0;

/// 创建时调用：缓存呈现 layer、记录期望尺寸、复位卫兵状态。
static void ame48_record_creation(CALayer *layer, EGLDisplay dpy, EGLSurface surface) {
    if (g_ame48_layer_cf != NULL) {
        CFRelease(g_ame48_layer_cf);
        g_ame48_layer_cf = NULL;
    }
    if (layer != nil) {
        g_ame48_layer_cf = (void *)CFBridgingRetain(layer);
    }
    g_ame48_drift_swaps = 0;
    g_ame48_recreates = 0;
    g_ame48_last_recreate_ms = 0;
    g_ame48_expected_w = 0;
    g_ame48_expected_h = 0;
    // 期望值 = 创建完成时 ANGLE 报告的表面实际尺寸（创建钉扎生效后
    // 即 MC 的渲染尺寸）。查询失败则保持 0（卫兵漂移检测停用，
    // 但"drawable == surface"的逐帧钉扎仍然全程有效）。
    ame_es_t es = ame_es();
    if (es.querySurface != NULL && surface != EGL_NO_SURFACE) {
        EGLint sw = 0, sh = 0;
        if (es.querySurface(dpy, surface, EGL_WIDTH, &sw) &&
            es.querySurface(dpy, surface, EGL_HEIGHT, &sh) && sw > 0 && sh > 0) {
            g_ame48_expected_w = sw;
            g_ame48_expected_h = sh;
        }
    }
    NSLog(@"[GLGeo] Task48 creation recorded: layer=%p expectedSurface=%dx%d",
          g_ame48_layer_cf, g_ame48_expected_w, g_ame48_expected_h);
}

/// 交换卫兵：gl_swap_buffers 每帧调用（渲染线程、上下文 current）。
/// Task 50：本函数已降级为**纯取证**（只读 + 日志，零写入）。
///
/// 622166a 设备日志证明旧卫兵的全部三个自愈动作无效且有害：
///   1. 跨线程写 drawableSize（渲染线程 vs 主线程 CA 提交树状态分叉：
///      心跳读到 drawable=2360x1640 而卫兵读到 1640x2360，全日志 0 条
///      "Task48 pin" = 逐帧钉扎从未生效）；
///   2. 同 layer 二次 eglCreateWindowSurface 恒 EGL_BAD_ALLOC 0x3003；
///   3. 钉扎与 updateSavedResolution（旋转时主线程写 2x）互相打架。
/// Task50 之后几何由"1x 单一事实源"保证一致（gl_init_context 创建时对齐 +
/// updateSavedResolution GL 分支跟随 bounds），本函数只保留漂移取证。
/// ANGLE 会随 layer 自然 resize（622166a 的 surface 转置事件即实证），
/// 瞬态失配由 Task49 geo-heal blit 兜底（双向 latch，几何恢复即退出）。
static void ame48_swap_geometry_guard(basic_render_window_t *bundle) {
    if (bundle == NULL || bundle->gl.surface == EGL_NO_SURFACE) return;
    CALayer *layer = (__bridge CALayer *)g_ame48_layer_cf;
    if (layer == nil || ![layer isKindOfClass:CAMetalLayer.class]) return;
    ame_es_t es = ame_es();
    if (es.querySurface == NULL) return;

    EGLint sw = 0, sh = 0;
    if (!es.querySurface(g_EglDisplay, bundle->gl.surface, EGL_WIDTH, &sw) ||
        !es.querySurface(g_EglDisplay, bundle->gl.surface, EGL_HEIGHT, &sh)) {
        return;  // 查询失败（EGL 错误）不干预
    }
    if (sw <= 0 || sh <= 0) return;

    CAMetalLayer *ml = (CAMetalLayer *)layer;
    CGSize d = ml.drawableSize;
    int dw = (int)round(d.width), dh = (int)round(d.height);

    if (dw != sw || dh != sh) {
        g_ame48_drift_swaps++;
        if (g_ame48_drift_swaps == 1 || g_ame48_drift_swaps % 200 == 0) {
            NSLog(@"[GLGeo] Task50 drift (info only): surface=%dx%d drawable=%dx%d bounds=%.0fx%.0f (consecutive=%ld) -- ANGLE resizes with layer; transient mismatch covered by geo-heal blit",
                  (int)sw, (int)sh, dw, dh,
                  layer.bounds.size.width, layer.bounds.size.height,
                  g_ame48_drift_swaps);
        }
    } else {
        g_ame48_drift_swaps = 0;
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
    // ============================================================================
    // Task 50（黑屏根因修复）：呈现几何单一事实源 —— 1x 点数对齐。
    //
    // latestlog 622166a 铁证链（本块取代 Task48 创建钉扎 + Task49 重试环，
    // 二者被同份日志证明无效且有害）：
    //   1. 全日志 0 条 "Task48 pin"（卫兵逐帧钉扎从未生效）——渲染线程读
    //      layer 属性与主线程心跳读到不同值（CALayer 跨线程状态分叉），
    //      跨线程写 drawableSize 打不进主线程的 CA 提交树；
    //   2. Task49 重试环 5 连败：pin 写 1180x820 后 ANGLE 仍建出 2360x1640
    //      —— ANGLE 读的是 bounds×contentsScale（=1180x820×2.0），不是
    //      drawableSize；
    //   3. 卫兵重建表面恒 EGL_BAD_ALLOC 0x3003（同 layer 二次建 window
    //      surface 必败），重建失败 → surface 被锁死在转置态 1640x2360，
    //      而 drawable/viewport 是横屏 2360x1640 —— 600+ 帧 present 尺寸
    //      失配 = 用户看到的全黑。
    //
    // 根因是结构性的：MC 26.3+SDL3 以"点"回报窗口尺寸（viewport=1180x820），
    // 而本层 contentsScale=2.0、drawableSize=2360x1640（像素）。MC 的帧只
    // 覆盖后缓冲左上 25%；方向翻转时 drawable/surface/viewport 各随其主，
    // 永不重合。
    //
    // 修复：把呈现层对齐到 MC 的真实渲染分辨率（点数）：
    //   contentsScale = 1.0 且 drawableSize = bounds（点）。此后无论 ANGLE
    //   读 bounds×scale 还是 drawableSize，surface 都 == MC viewport ==
    //   drawable；CoreAnimation 把 1x 帧最近邻放大到物理屏（MC 像素风格
    //   下视觉无损）；旋转时三者随 bounds 同步翻转，ANGLE 自然跟随 resize
    //   （622166a 中 surface 2360x1640→1640x2360 的转置正是 ANGLE 跟随
    //   layer 的实证——能力一直在，只是此前三套尺寸互相打架）。
    //   Vulkan 路径不受影响：gl_init_context 只在 GL 路径执行；Vulkan 下
    //   本标志恒 0，updateSavedResolution 保持旧行为，MoltenVK 自管层。
    // ============================================================================
    // Task50 对齐写 layer 必须发生在主线程：旧代码的致命伤之一就是从渲染线程
    // 写 drawableSize（CALayer 跨线程状态分叉：渲染线程读到一套、主线程的
    // CA 提交树另一套——622166a 心跳 drawable=2360x1640 与卫兵读取 1640x2360
    // 的矛盾即其表现）。单一写入者纪律：本块与 updateSavedResolution（主线程，
    // 旋转时）是 layer 尺寸仅有的两个写入者，且都在主线程。
    if ([layer isKindOfClass:CAMetalLayer.class]) {
        __block CGSize oldDrawable50 = CGSizeZero;
        __block CGFloat oldScale50 = 0.0;
        void (^align50)(void) = ^{
            CAMetalLayer *ml50 = (CAMetalLayer *)layer;
            CGFloat w50 = MAX(1.0, round(layer.bounds.size.width));
            CGFloat h50 = MAX(1.0, round(layer.bounds.size.height));
            oldDrawable50 = ml50.drawableSize;
            oldScale50 = layer.contentsScale;
            layer.contentsScale = 1.0;
            ml50.drawableSize = CGSizeMake(w50, h50);
        };
        if ([NSThread isMainThread]) {
            align50();
        } else {
            // gl_init_context 运行于 JVM 渲染线程；此刻主线程处于空闲 runloop
            // （launchJVM 在后台线程，主线程无任何等待渲染线程的锁——同窗口期
            // ame_embedSDLViewIntoHost 的 dispatch_sync 已在设备上验证安全）。
            dispatch_sync(dispatch_get_main_queue(), align50);
        }
        NSLog(@"[GLGeo] Task50 1x alignment (main thread): bounds=%.0fx%.0f drawableSize %.0fx%.0f scale %.2f -> drawableSize %.0fx%.0f scale 1.00 (surface==viewport==drawable, single source of truth)",
              layer.bounds.size.width, layer.bounds.size.height,
              oldDrawable50.width, oldDrawable50.height, oldScale50,
              MAX(1.0, round(layer.bounds.size.width)),
              MAX(1.0, round(layer.bounds.size.height)));
    }
    // MobileGL 的 eglCreateWindowSurface 不会从 CALayer 推断尺寸，必须显式给出
    // 宽高（读取已对齐 1x 的 layer，与 drawableSize 保持一致），否则 surface 会按
    // 1x1 创建，进世界后画面异常。其余渲染器从 layer 自行推断，传 NULL。
    const EGLint mobileGLSurfaceAttribs[] = {
        EGL_WIDTH, (EGLint)MAX(1.0, round(layer.bounds.size.width * layer.contentsScale)),
        EGL_HEIGHT, (EGLint)MAX(1.0, round(layer.bounds.size.height * layer.contentsScale)),
        EGL_NONE
    };
    // 单次创建（无重试环）：1x 对齐后 ANGLE 无论读 bounds×scale 还是
    // drawableSize 都得到与 MC viewport 相同的尺寸，无需执法。
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
        // Task 48：记录呈现 layer（CFBridgingRetain）与期望表面尺寸，
        // 供 ame48_swap_geometry_guard 逐帧自愈使用。
        ame48_record_creation(layer, g_EglDisplay, bundle->surface);
        // Task 50：GL 拥有呈现层（跨线程标志）——此后主线程
        // updateSavedResolution 走 1x 对齐分支（bounds 跟随旋转）。
        atomic_store(&g_ame50_gl_owns_layer, 1);
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
    // Task 48 呈现几何卫兵：先于一切交换动作执行（可能在内部重建表面，
    // 重建后 currentBundle->gl.surface 已更新，后续探针/交换都作用于新表面）。
    ame48_swap_geometry_guard(currentBundle);
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
    // Task 50：GL 不再拥有呈现层（下次 updateSavedResolution 回到 2x 默认）。
    atomic_store(&g_ame50_gl_owns_layer, 0);
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
