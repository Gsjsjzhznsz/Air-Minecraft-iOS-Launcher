// ============================================================================
// Task 119：MobileGL（DirectVulkan / DirectGLES）路径的 FSR1 EASU 预交换升采样。
//
// 背景（5.1.0 用户实测："mg 的 vulkan 路径，fsr 没有放大，又蜷缩"）：
//   updateSavedResolution 的 Task83 FSR 联动把 MC 告知窗口缩到 surface/fsr_scale
//   （渲染分辨率），期望渲染器侧把帧升采样回全表面再呈现。zink 走 osm_bridge
//   的 EASU（Task83-85/99-106），MobileGlues 有内置 FSR1（Task78-82）——但
//   MobileGL 路径此前【没有任何升采样钩子】：MC 以半分辨率渲染进全幅
//   swapchain image 的左下角区域，eglSwapBuffers 直呈 → 画面蜷缩 + 无放大。
//   旧 ame83_fsr_capable_renderer 甚至不认 MobileGL，蜷缩来自 Task113 开关
//   覆盖渲染器后联动表仍按 profile 渲染器缩窗的错位（Task120 已改为
//   ame_effective_renderer 单一事实源）。
//
// 本模块（与 osm_bridge Task83 EASU 同构，呈现端不同）：
//   - zink：EASU 画进 OSMesa client buffer -> glFinish 回读 -> CGImage 上屏；
//   - MobileGL：EASU 画进【默认帧缓冲】（= MobileGL 内部 swapchain image）
//     -> eglSwapBuffers 直呈。全程 GPU 侧，零 CPU 回读——正是 MobileGL
//     Vulkan 路径流畅度优势的口径（不引入 zink 路径的回读常数）。
//
// 调用点：gl_bridge.m 的 gl_swap_buffers()，在 ame48 几何卫兵之后、
// handle.eglSwapBuffers 之前（卫兵可能重建表面，EASU 必须画进最终表面）。
//
// 门控（全部惰性、零锁）：
//   AMETHYST_RENDERER ∈ {libMobileGL.dylib, libMobileGL-gles.dylib}
//   && ame_surfaceWidth/Height 已初始化（updateSavedResolution 单点写入）
//   && 输入区域 < 表面（FSR 关闭/已恢复全分辨率时零开销跳过）。
//
// GL 符号解析：eglGetProcAddress(libMobileGL.dylib)——上游 caf6822 会话
// 实证 LWJGL GL$1 mirror 正是以此加载全部 GL 函数；直连 dlsym 作回退
// （egl_bridge 预装载已把 dylib 挂进进程，dlopen 同句柄返回）。
//
// 兜底（与 osm_bridge Task83b 同款自愈）：shader 编译/链接失败 → 一次性回调
// nativeSendScreenSize(surface) —— MC 下一帧起以全分辨率直渲，画面退出
// 蜷缩；DirectGLES 后端编不了 #version 450 桌面 GLSL 时也走这条路径
// （FSR 在 GLES 档自动停用，功能不缺失，仅画质档不可用，日志留痕）。
//
// 与 zink 路径的差异（刻意省略的机制）：
//   - Task99-106 的双哨兵/权威回读/bundle-direct 呈现：那是 OSMesa 回读
//     契约下的"蜷角取证战争"（驱动回读不可信）。MobileGL 路径无回读、
//     无 CGImage 包装——EASU 画完 eglSwapBuffers 即是地面真值，不需要
//     哨兵验证链。
// ============================================================================

#include <string>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Task 122 链接修复：FSRShaderSource.h 里的 FSR_VSSource/FSR_FSSource 是
// 非 static 全局【定义】（每个包含它的 TU 都产出一份强符号；此前 osm_bridge.mm
// 是唯一包含者，本文件加入后链接期重复符号）。改为 extern 借用 osm_bridge.mm
// 的定义（同一份 shader 源，字面单一事实源）。
extern const char* FSR_VSSource;
extern const char* FSR_FSSource;
// Task 130：RCAS 锐化 pass 2 源（static const internal linkage，本 TU 私有
// 副本——与 osm_bridge.mm 各持一份，无跨 TU 符号冲突，bd71210 教训口径）。
#include "FSRRCASSource.h"
#include "../environ.h"
#include "../utils.h"

// ============================================================================
// GL 2.0+ 枚举（与 osm_bridge 同款防御性定义；MobileGL 是桌面 GL 4.6 实现，
// 全量支持这些入口）。
#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER    0x8B31
#endif
// Task 143 勘误：GL_FRAGMENT_SHADER 规范值是 0x8B30（35632，mesa
// glext.h:599 同款；Task119 从 osm_bridge 的 Task84 错误"勘误"复制了
// 0x8B92——那是 GL_PALETTE4_R5_G6_B5_OES，GLES1 调色板纹理格式，根本
// 不是 shader 类型）。装机日志 4ecc256 实锤：MobileGL 顶点着色器
// （0x8B31）创建成功、片元（0x8B92）glCreateShader 返回 0 +
// glGetError=0x500（GL_INVALID_ENUM）→ EASU 链初始化失败 → 恒自愈回
// 全分辨率 → 用户反馈"fsr没有生效"（FSR 预设 4 的半分辨率渲染从未被
// 上采样，Task83 联动几何每次都白白触发一轮 heal）。
#ifndef GL_FRAGMENT_SHADER
#define GL_FRAGMENT_SHADER  0x8B30
#endif
#ifndef GL_COMPILE_STATUS
#define GL_COMPILE_STATUS   0x8B81
#endif
#ifndef GL_LINK_STATUS
#define GL_LINK_STATUS      0x8B82
#endif
#ifndef GL_CURRENT_PROGRAM
#define GL_CURRENT_PROGRAM  0x8B8D
#endif
#ifndef GL_TEXTURE_BINDING_2D
#define GL_TEXTURE_BINDING_2D 0x8069
#endif
#ifndef GL_ARRAY_BUFFER
#define GL_ARRAY_BUFFER     0x8892
#endif
// Task 143：0x8B8C 实为 GL_SHADING_LANGUAGE_VERSION（本文件 ame119_
// adapt_shader_version 的版本查询用的正是它）；GL_ARRAY_BUFFER_BINDING
// 规范值 0x8894。旧错值并非死定义——RCAS 路径 ame119_rcas_engage 的
// glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saveVbo) 实际引用了它，查询
// 到的是 GLSL 版本语义的 pname（恒 0/错误），VBO 绑定保存静默失效。
#ifndef GL_ARRAY_BUFFER_BINDING
#define GL_ARRAY_BUFFER_BINDING 0x8894
#endif
#ifndef GL_VERTEX_ARRAY_BINDING
#define GL_VERTEX_ARRAY_BINDING 0x85B5
#endif
#ifndef GL_STATIC_DRAW
#define GL_STATIC_DRAW      0x88E4
#endif
#ifndef GL_TEXTURE_MAX_LEVEL
#define GL_TEXTURE_MAX_LEVEL 0x813D
#endif
#ifndef GL_TEXTURE_2D
#define GL_TEXTURE_2D         0x0DE1
#endif
#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE    0x812F
#endif
#ifndef GL_DRAW_FRAMEBUFFER_BINDING
#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA9
#endif
#ifndef GL_READ_FRAMEBUFFER_BINDING
#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA
#endif
#ifndef GL_DEPTH_TEST
#define GL_DEPTH_TEST       0x0B71
#endif
#ifndef GL_SCISSOR_TEST
#define GL_SCISSOR_TEST     0x0C11
#endif
#ifndef GL_STENCIL_TEST
#define GL_STENCIL_TEST     0x0B90
#endif
#ifndef GL_BLEND
#define GL_BLEND            0x0BE2
#endif
#ifndef GL_CULL_FACE
#define GL_CULL_FACE        0x0B44
#endif
#ifndef GL_TRIANGLES
#define GL_TRIANGLES        0x0004
#endif
#ifndef GL_TEXTURE0
#define GL_TEXTURE0         0x84C0
#endif
#ifndef GL_ACTIVE_TEXTURE
#define GL_ACTIVE_TEXTURE   0x84E0
#endif
#ifndef GL_RGBA
#define GL_RGBA             0x1908
#endif
#ifndef GL_UNSIGNED_BYTE
#define GL_UNSIGNED_BYTE    0x1401
#endif
#ifndef GL_FLOAT
#define GL_FLOAT            0x1406
#endif
#ifndef GL_VIEWPORT
#define GL_VIEWPORT         0x0BA2
#endif
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER      0x8D40
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif
#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CAA
#endif

typedef unsigned int ame119_gluint;
typedef int ame119_glint;
typedef void (*ame119_glshaderfn)(unsigned int, int, const char* const*, const int*);
typedef void (*ame119_glgetiv)(unsigned int, unsigned int, int*);
typedef void (*ame119_gllogfn)(unsigned int, int, int*, char*);

typedef struct {
    // shader/program
    ame119_gluint (*glCreateShader)(unsigned int);
    ame119_glshaderfn glShaderSource;
    void (*glCompileShader)(unsigned int);
    ame119_glgetiv glGetShaderiv;
    ame119_gllogfn glGetShaderInfoLog;
    ame119_gluint (*glCreateProgram)(void);
    void (*glAttachShader)(unsigned int, unsigned int);
    void (*glLinkProgram)(unsigned int);
    ame119_glgetiv glGetProgramiv;
    ame119_gllogfn glGetProgramInfoLog;
    void (*glDeleteShader)(unsigned int);
    int (*glGetUniformLocation)(unsigned int, const char*);
    void (*glUseProgram)(unsigned int);
    void (*glUniform2f)(unsigned int, float, float);
    void (*glUniform1f)(unsigned int, float);   // Task 130：RCAS uSharpness
    void (*glUniform1i)(int, int);
    // texture
    void (*glGenTextures)(int, unsigned int*);
    // Task 130：RCAS 离屏目标尺寸变更重建时需要删除旧纹理（CI run 35492554181
    // 教训：结构体漏字段直接编译错误——补齐字段 + kSym 表项）
    void (*glDeleteTextures)(int, const unsigned int*);
    void (*glBindTexture)(unsigned int, unsigned int);
    void (*glTexParameteri)(unsigned int, unsigned int, int);
    void (*glTexImage2D)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*);  // Task 130：RCAS 离屏目标
    void (*glCopyTexImage2D)(unsigned int, int, unsigned int, int, int, int, int, int);
    void (*glCopyTexSubImage2D)(unsigned int, int, int, int, int, int, int, int);
    void (*glActiveTexture)(unsigned int);
    // vertex
    void (*glGenVertexArrays)(int, unsigned int*);
    void (*glBindVertexArray)(unsigned int);
    void (*glGenBuffers)(int, unsigned int*);
    void (*glBindBuffer)(unsigned int, unsigned int);
    void (*glBufferData)(unsigned int, long, const void*, unsigned int);
    void (*glVertexAttribPointer)(unsigned int, int, unsigned int, unsigned char, int, const void*);
    void (*glEnableVertexAttribArray)(unsigned int);
    // draw/state
    void (*glBindFramebuffer)(unsigned int, unsigned int);
    // Task 130：RCAS ping-pong（EASU -> 离屏 -> RCAS -> fb0）FBO 入口
    void (*glGenFramebuffers)(int, unsigned int*);
    void (*glDeleteFramebuffers)(int, const unsigned int*);
    void (*glFramebufferTexture2D)(unsigned int, unsigned int, unsigned int, unsigned int, int);
    int  (*glCheckFramebufferStatus)(unsigned int);
    void (*glDrawArrays)(unsigned int, int, int);
    void (*glViewport)(int, int, int, int);
    void (*glDisable)(unsigned int);
    void (*glGetIntegerv)(unsigned int, int*);
    // Task 148：内置 FSR1 仲裁探测——GL_DRAW_FRAMEBUFFER_BINDING 的 getter 会
    // 隐藏 fb0 重定向（getter.cpp 特意回 0），只能走附件查询看 DRAW 目标上
    // 是否挂了真实颜色对象。
    void (*glGetFramebufferAttachmentParameteriv)(unsigned int, unsigned int, unsigned int, int*);
    unsigned int (*glGetError)(void);
} ame119_gl_t;

static struct {
    ame119_gl_t gl;
    void *mgHandle;         // Task 140：libMobileGL.dylib 句柄（符号直连源）
    int srcHandle, srcProc, srcDefault;  // Task 140：解析来源计数（装机取证）
    void *(*eglGetProcAddress)(const char *);
    bool resolved;      // 符号表已解析（无论成败不再重试）
    bool initFailed;    // shader/program 初始化失败（不再每帧重试编译）
    bool ready;         // program+VAO+texture 就绪
    unsigned int program, vao, vbo, tex;
    int uViewportSize, uTargetSize, uInputTex;
    int texW, texH;     // 纹理存储尺寸（变更时重建）
    bool engaged;       // 首帧一次性日志
    bool healed;        // 兜底恢复已触发（nativeSendScreenSize 全分辨率）
    long frames;        // 升采样帧计数（低频日志用）
    // ---- Task 130：RCAS 锐化 pass 2（mpv FSR.glsl 参照，同款管线变更）----
    unsigned int rcasProgram;      // RCAS program（0 = 未建/失败 → 仅 EASU）
    unsigned int easuTex, easuFBO; // EASU 离屏输出（RCAS 读它画 fb0）
    int easuW, easuH;              // 离屏目标存储尺寸（变更时重建）
    int uRcasInputTex, uRcasSharpness;
    bool rcasFailed;               // RCAS 不可用 → EASU 直画 fb0（旧路径）
    bool rcasEngaged;              // RCAS 首帧一次性日志
    long rcasFrames;               // RCAS 帧计数（低频日志）
    // ---- Task 148：内置 FSR1 仲裁 ----
    bool ame148_arbitrated;        // 已执行过仲裁探测（首帧日志）
    bool ame148_builtin_owns;      // 渲染器内置 FSR1 接管 → 启动器链退休
    // ---- Task 153：真实后缓冲几何仲裁 ----
    bool ame153_geoLogged;         // 几何仲裁首帧一次性日志（engage/retire 翻转各自打印）
    bool ame153_retired;           // 后缓冲装不下升采样 → 本链退休（直呈 + CA 缩放）
} ame119_fsr = {0};

// Task 153：渲染器侧 EGL 入口（后缓冲真实尺寸查询）。
// 病历（d36a24f 构建双会话，Vulkan 花屏 / ES 方块不渲染实锤）：MobileGL
// 渲染器把 EGL window surface 尺寸【钉在 MC 窗口信念上】（Task83 FSR
// 联动把 windowWidth 缩到 surface/fsr_scale=1180x820 → 后缓冲就是
// 1180x820），而本链一直按启动器信念 ame_surfaceWidth（2360x1640）画
// RCAS——全屏四边形按 2360x1640 视口栅格化进 1180x820 的后缓冲，
// 只有左下四分之一落图，其余区域残留旧帧 = 每帧花屏/错位拼图。
// ES 会话同根（方块不渲染 = 毁帧链的另一种呈现）。修复：目标尺寸改读
// 渲染器自己的 eglQuerySurface（eglGetCurrentDisplay/CurrentSurface 同源
// 本线程 current 上下文，绝不外溢到 ANGLE——Task140 窃符号教训同款纪律）。
typedef void *ame153_egldisplay_t;
typedef void *ame153_eglsurface_t;
// EGL 基础类型与常量（防御性本地定义，与 egl.h 口径一致——本 TU 无 EGL 头）
typedef unsigned int ame153_eglbool_t;   // EGLBoolean
typedef int ame153_eglint_t;             // EGLint
#define AME153_EGL_WIDTH   0x3057
#define AME153_EGL_HEIGHT  0x3056
#define AME153_EGL_DRAW    0x3059
static struct {
    ame153_egldisplay_t (*eglGetCurrentDisplay)(void);
    ame153_eglsurface_t (*eglGetCurrentSurface)(unsigned int readdraw);
    ame153_eglbool_t (*eglQuerySurface)(ame153_egldisplay_t, ame153_eglsurface_t,
                                        ame153_eglint_t, ame153_eglint_t *);
} ame153_egl = {NULL, NULL, NULL};

// 查询当前线程 EGL 绘制表面的真实后缓冲尺寸（渲染器自己的 EGL 实现）。
// 返回 false = 无 current 上下文/表面或查询失败（此帧不 engage，安全跳过）。
static bool ame153_query_backbuffer(int *outW, int *outH) {
    if (ame153_egl.eglGetCurrentDisplay == NULL ||
        ame153_egl.eglGetCurrentSurface == NULL ||
        ame153_egl.eglQuerySurface == NULL) return false;
    ame153_egldisplay_t dpy = ame153_egl.eglGetCurrentDisplay();
    if (dpy == (ame153_egldisplay_t)0 /*EGL_NO_DISPLAY*/) return false;
    ame153_eglsurface_t surf = ame153_egl.eglGetCurrentSurface(AME153_EGL_DRAW);
    if (surf == (ame153_eglsurface_t)0 /*EGL_NO_SURFACE*/) return false;
    ame153_eglint_t w = 0, h = 0;
    if (!ame153_egl.eglQuerySurface(dpy, surf, AME153_EGL_WIDTH, &w)) return false;
    if (!ame153_egl.eglQuerySurface(dpy, surf, AME153_EGL_HEIGHT, &h)) return false;
    if (w <= 0 || h <= 0) return false;
    *outW = (int)w;
    *outH = (int)h;
    return true;
}

// Task 130：RCAS 锐化强度（mpv 口径 [0,1] 越大越锐，默认 0.2；负值 = 关闭
// RCAS，仅 EASU）。环境变量 AMETHYST_FSR_RCAS_SHARPNESS 由 JavaLauncher
// 启动前从偏好 mobileglues.fsr_rcas_sharpness 写入（与 MobileGlues 渲染器
// 读 config.json 的 fsr1RcasSharpness 同源——两类渲染器一个偏好键）。
static float ame130_rcas_sharpness(void) {
    const char *s = getenv("AMETHYST_FSR_RCAS_SHARPNESS");
    if (s == NULL || s[0] == 0) return 0.2f;
    float v = atof(s);
    if (v < 0.0f) return v;                      // 负值 = off（原样传递）
    if (!(v >= 0.0f && v <= 1.0f)) return 0.2f;  // NaN/越界回默认
    return v;
}

// 符号解析（Task 140 重写）。
//
// 病历（ab9670d GLES 会话 latestlog.txt 07:30:57 实锤）：旧顺序
// eglGetProcAddress 优先 + dlsym(RTLD_DEFAULT) 兜底，实测 FSR 从未在
// MobileGL 两后端上成功初始化——resolve 41/41 全非空却 "upscale
// unavailable"，且 init 链上唯一无日志的失败点是 glCreateShader()==0。
// 根因：MobileGL 的 eglGetProcAddress 对核心 gl* 名称返回 NULL（它只服务
// 扩展入口），兜底 dlsym(RTLD_DEFAULT) 在平命名空间全局搜索里【先命中
// app 自动链接的 ANGLE】（libGLESv2.framework 由 Makefile 链入主程序，
// 进程启动即入全局符号表，早于 egl_bridge 对 libMobileGL 的 RTLD_GLOBAL
// dlopen）——全部 41 个入口实际是 ANGLE 的实现，而当前上下文是
// MobileGL 的，ANGLE 侧无 current context，glCreateShader 返回 0，
// 静默失败 → FSR 永远不可用。
//
// 修复：直接从 libMobileGL.dylib 的 dlopen 句柄 dlsym（其 LC_DYLD_EXPORTS
//_TRIE 已逐一验证导出全部所需 gl* 符号——2851 个 _gl* / 45 个 _egl*），
// dyld 对句柄 dlsym 先查镜像自身 trie，绝不外溢到 ANGLE。
// eglGetProcAddress 降为次选（仅 handle 缺失时），RTLD_DEFAULT 保底末位，
// 并记录每个符号的解析来源（handle/proc/default），装机日志一眼判读。
static void *ame119_resolve(const char *name) {
    if (ame119_fsr.mgHandle != NULL) {
        void *p = dlsym(ame119_fsr.mgHandle, name);
        if (p != NULL) return p;
    }
    if (ame119_fsr.eglGetProcAddress != NULL) {
        void *p = ame119_fsr.eglGetProcAddress(name);
        if (p != NULL) return p;
    }
    return dlsym(RTLD_DEFAULT, name);
}

static bool ame119_resolve_gl(void) {
    if (ame119_fsr.resolved) return ame119_fsr.gl.glCreateShader != NULL;
    ame119_fsr.resolved = true;
    // libMobileGL.dylib 已由 egl_bridge 预装载（RTLD_GLOBAL）；dlopen 同名
    // 返回既有句柄，仅作符号直连源 + 拿 eglGetProcAddress 备用入口。
    // Task 140：句柄存进 ame119_fsr.mgHandle，ame119_resolve 优先从它
    // dlsym（见该函数注释的 ANGLE 窃符号病历）。
    void *mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGL, RTLD_NOW | RTLD_NOLOAD);
    if (mg == NULL) {
        mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGL, RTLD_NOW | RTLD_LOCAL);
    }
    ame119_fsr.mgHandle = mg;
    if (mg != NULL) {
        ame119_fsr.eglGetProcAddress =
            (void *(*)(const char *))dlsym(mg, "eglGetProcAddress");
    }
    struct { const char *name; void **slot; } kSym[] = {
        {"glCreateShader",            (void **)&ame119_fsr.gl.glCreateShader},
        {"glShaderSource",            (void **)&ame119_fsr.gl.glShaderSource},
        {"glCompileShader",           (void **)&ame119_fsr.gl.glCompileShader},
        {"glGetShaderiv",             (void **)&ame119_fsr.gl.glGetShaderiv},
        {"glGetShaderInfoLog",        (void **)&ame119_fsr.gl.glGetShaderInfoLog},
        {"glCreateProgram",           (void **)&ame119_fsr.gl.glCreateProgram},
        {"glAttachShader",            (void **)&ame119_fsr.gl.glAttachShader},
        {"glLinkProgram",             (void **)&ame119_fsr.gl.glLinkProgram},
        {"glGetProgramiv",            (void **)&ame119_fsr.gl.glGetProgramiv},
        {"glGetProgramInfoLog",       (void **)&ame119_fsr.gl.glGetProgramInfoLog},
        {"glDeleteShader",            (void **)&ame119_fsr.gl.glDeleteShader},
        {"glGetUniformLocation",      (void **)&ame119_fsr.gl.glGetUniformLocation},
        {"glUseProgram",              (void **)&ame119_fsr.gl.glUseProgram},
        {"glUniform2f",               (void **)&ame119_fsr.gl.glUniform2f},
        {"glUniform1i",               (void **)&ame119_fsr.gl.glUniform1i},
        // Task 130：RCAS ping-pong 所需（uSharpness 下发 + 离屏目标 + FBO）
        {"glUniform1f",               (void **)&ame119_fsr.gl.glUniform1f},
        {"glTexImage2D",              (void **)&ame119_fsr.gl.glTexImage2D},
        {"glGenFramebuffers",         (void **)&ame119_fsr.gl.glGenFramebuffers},
        {"glDeleteFramebuffers",      (void **)&ame119_fsr.gl.glDeleteFramebuffers},
        {"glFramebufferTexture2D",    (void **)&ame119_fsr.gl.glFramebufferTexture2D},
        {"glCheckFramebufferStatus",  (void **)&ame119_fsr.gl.glCheckFramebufferStatus},
        {"glGenTextures",             (void **)&ame119_fsr.gl.glGenTextures},
        {"glDeleteTextures",            (void **)&ame119_fsr.gl.glDeleteTextures},
        {"glBindTexture",             (void **)&ame119_fsr.gl.glBindTexture},
        {"glTexParameteri",           (void **)&ame119_fsr.gl.glTexParameteri},
        {"glCopyTexImage2D",          (void **)&ame119_fsr.gl.glCopyTexImage2D},
        {"glCopyTexSubImage2D",       (void **)&ame119_fsr.gl.glCopyTexSubImage2D},
        {"glActiveTexture",           (void **)&ame119_fsr.gl.glActiveTexture},
        {"glGenVertexArrays",         (void **)&ame119_fsr.gl.glGenVertexArrays},
        {"glBindVertexArray",         (void **)&ame119_fsr.gl.glBindVertexArray},
        {"glGenBuffers",              (void **)&ame119_fsr.gl.glGenBuffers},
        {"glBindBuffer",              (void **)&ame119_fsr.gl.glBindBuffer},
        {"glBufferData",              (void **)&ame119_fsr.gl.glBufferData},
        {"glVertexAttribPointer",     (void **)&ame119_fsr.gl.glVertexAttribPointer},
        {"glEnableVertexAttribArray", (void **)&ame119_fsr.gl.glEnableVertexAttribArray},
        {"glBindFramebuffer",         (void **)&ame119_fsr.gl.glBindFramebuffer},
        {"glDrawArrays",              (void **)&ame119_fsr.gl.glDrawArrays},
        {"glViewport",                (void **)&ame119_fsr.gl.glViewport},
        {"glDisable",                 (void **)&ame119_fsr.gl.glDisable},
        {"glGetIntegerv",             (void **)&ame119_fsr.gl.glGetIntegerv},
        // Task 148：内置 FSR1 仲裁探测入口（MobileGL 导出表核心项，
        // gl_native.cpp NATIVE_FUNCTION_HEAD 已验证存在）
        {"glGetFramebufferAttachmentParameteriv",
                                      (void **)&ame119_fsr.gl.glGetFramebufferAttachmentParameteriv},
        {"glGetError",                (void **)&ame119_fsr.gl.glGetError},
        // Task 153：后缓冲真实尺寸查询（libMobileGL.dylib 导出表实锤
        // _eglGetCurrentDisplay/_eglGetCurrentSurface/_eglQuerySurface）
        {"eglGetCurrentDisplay",      (void **)&ame153_egl.eglGetCurrentDisplay},
        {"eglGetCurrentSurface",      (void **)&ame153_egl.eglGetCurrentSurface},
        {"eglQuerySurface",           (void **)&ame153_egl.eglQuerySurface},
    };
    int ok = 0;
    ame119_fsr.srcHandle = ame119_fsr.srcProc = ame119_fsr.srcDefault = 0;
    for (auto &s : kSym) {
        *s.slot = ame119_resolve(s.name);
        if (*s.slot != NULL) {
            ++ok;
            // 解析来源分桶计数（Task 140 取证：handle 应独占全部 41 项）
            if (mg != NULL && dlsym(mg, s.name) == *s.slot) {
                ++ame119_fsr.srcHandle;
            } else if (ame119_fsr.eglGetProcAddress != NULL &&
                       ame119_fsr.eglGetProcAddress(s.name) == *s.slot) {
                ++ame119_fsr.srcProc;
            } else {
                ++ame119_fsr.srcDefault;
            }
        }
    }
    NSLog(@"[MGLFSR] Task119 GL resolve: %d/%zu symbols (mgHandle=%p eglGetProcAddress=%p; sources: handle=%d proc=%d default=%d)",
          ok, sizeof(kSym) / sizeof(kSym[0]), mg, (void *)ame119_fsr.eglGetProcAddress,
          ame119_fsr.srcHandle, ame119_fsr.srcProc, ame119_fsr.srcDefault);
    return ok == (int)(sizeof(kSym) / sizeof(kSym[0]));
}

// 着色器版本自适应（移植自 osm_bridge Task83b）：#version 450 源在
// GLSL 上限更低的上下文（如 DirectGLES 暴露的 ES GLSL）降版本重写；
// <400 改了也编不过，保留原样让编译器给出明确错误（走兜底）。
static std::string ame119_adapt_shader_version(const char *src, const char *stageName) {
    std::string out(src);
    if (ame119_fsr.gl.glGetIntegerv == NULL) return out;
    int ver = 0;
    // GL_SHADING_LANGUAGE_VERSION 0x8B8C 需要当前上下文——解析期在首个
    // swap 前调用，MC 上下文已 current（gl_swap_buffers 运行于渲染线程）。
    ame119_fsr.gl.glGetIntegerv(0x8B8C, &ver);
    if (ver == 0) {
        // Task 140：ver==0 曾是无日志静默路径（源保持 #version 450 直接编）。
        // 现在留痕：ver==0 意味着查询未写入（无当前上下文或 pname 不支持），
        // 装机日志可直接判读上下文状态。
        static bool s_logged = false;
        if (!s_logged) {
            s_logged = true;
            NSLog(@"[MGLFSR] Task140 GLSL version query (pname 0x8B8C) returned 0 (%s stage) -- no current context on this thread or unsupported pname", stageName);
        }
        return out;   // 查询失败：原样（编译错误走兜底）
    }
    if (ver >= 450) return out;
    if (ver < 400) {
        static bool s_logged = false;
        if (!s_logged) {
            s_logged = true;
            NSLog(@"[MGLFSR] Task119 context GLSL %d < 400 (%s stage) -- desktop EASU unavailable on this backend, falling back to full-res", ver, stageName);
        }
        return out;
    }
    const char *nl = strchr(src, '\n');
    if (!nl || strncmp(src, "#version", 8) != 0) return out;
    static bool s_logged = false;
    if (!s_logged) {
        s_logged = true;
        NSLog(@"[MGLFSR] Task119 FSR shader #version adapted: 450 -> %d (context GLSL cap, %s stage)", ver, stageName);
    }
    out = "#version ";
    out += std::to_string(ver);
    out += '\n';
    out += (nl + 1);
    return out;
}

static unsigned int ame119_compile(unsigned int stage, const std::string &src) {
    ame119_gl_t *g = &ame119_fsr.gl;
    unsigned int sh = g->glCreateShader(stage);
    if (sh == 0) {
        // Task 140：glCreateShader()==0 曾是全链唯一无日志的静默失败点
        //（ab9670d GLES 会话 "resolve 41/41 后直接 unavailable" 实锤）。
        // 现在带 glGetError 留痕——0x3006 无当前上下文 = 符号解析命中了
        // 错误镜像（ANGLE 窃符号病历，见 ame119_resolve 注释）。
        unsigned int err = g->glGetError != NULL ? g->glGetError() : 0;
        NSLog(@"[MGLFSR] Task140 glCreateShader(stage=%u) returned 0, glGetError=0x%x -- no current context on the resolved image? (symbol-theft check: sources handle=%d proc=%d default=%d)",
              stage, err, ame119_fsr.srcHandle, ame119_fsr.srcProc, ame119_fsr.srcDefault);
        return 0;
    }
    const char *p = src.c_str();
    int len = (int)src.size();
    g->glShaderSource(sh, 1, &p, &len);
    g->glCompileShader(sh);
    int ok = 0;
    g->glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        int used = 0;
        g->glGetShaderInfoLog(sh, sizeof(log) - 1, &used, log);
        log[used > 0 && used < 1024 ? used : 0] = 0;
        NSLog(@"[MGLFSR] Task119 shader compile FAILED (stage=%u): %s", stage, log);
        g->glDeleteShader(sh);
        return 0;
    }
    return sh;
}

static bool ame119_fsr_init(void) {
    if (ame119_fsr.ready) return true;
    if (ame119_fsr.initFailed) return false;
    if (!ame119_resolve_gl()) { ame119_fsr.initFailed = true; return false; }
    ame119_gl_t *g = &ame119_fsr.gl;

    std::string vsSrc = ame119_adapt_shader_version(FSR_VSSource, "vertex");
    std::string fsSrc = ame119_adapt_shader_version(FSR_FSSource, "fragment");
    unsigned int vs = ame119_compile(GL_VERTEX_SHADER, vsSrc);
    if (vs == 0) { ame119_fsr.initFailed = true; return false; }
    unsigned int fs = ame119_compile(GL_FRAGMENT_SHADER, fsSrc);
    if (fs == 0) { g->glDeleteShader(vs); ame119_fsr.initFailed = true; return false; }

    unsigned int prog = g->glCreateProgram();
    g->glAttachShader(prog, vs);
    g->glAttachShader(prog, fs);
    g->glLinkProgram(prog);
    int ok = 0;
    g->glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    g->glDeleteShader(vs);
    g->glDeleteShader(fs);
    if (!ok) {
        char log[1024];
        int used = 0;
        g->glGetProgramInfoLog(prog, sizeof(log) - 1, &used, log);
        log[used > 0 && used < 1024 ? used : 0] = 0;
        NSLog(@"[MGLFSR] Task119 program link FAILED: %s", log);
        ame119_fsr.initFailed = true;
        return false;
    }

    // 全屏四边形（与 osm_bridge/MG InitFullscreenQuad 同款布局）
    static const float quad[] = {
        -1.0f,  1.0f, 0.0f, 1.0f,
        -1.0f, -1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
        -1.0f,  1.0f, 0.0f, 1.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
    };
    g->glGenVertexArrays(1, &ame119_fsr.vao);
    g->glBindVertexArray(ame119_fsr.vao);
    g->glGenBuffers(1, &ame119_fsr.vbo);
    g->glBindBuffer(GL_ARRAY_BUFFER, ame119_fsr.vbo);
    g->glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    g->glVertexAttribPointer(0, 2, GL_FLOAT, 0, 4 * sizeof(float), (void *)0);
    g->glEnableVertexAttribArray(0);
    g->glVertexAttribPointer(1, 2, GL_FLOAT, 0, 4 * sizeof(float), (void *)(2 * sizeof(float)));
    g->glEnableVertexAttribArray(1);
    g->glBindBuffer(GL_ARRAY_BUFFER, 0);
    g->glBindVertexArray(0);

    g->glGenTextures(1, &ame119_fsr.tex);
    ame119_fsr.program = prog;
    ame119_fsr.uViewportSize = g->glGetUniformLocation(prog, "uViewportSize");
    ame119_fsr.uTargetSize = g->glGetUniformLocation(prog, "uTargetSize");
    ame119_fsr.uInputTex = g->glGetUniformLocation(prog, "uInputTex");
    if (g->glGetError) g->glGetError();   // 清掉初始化期间的残留错误
    ame119_fsr.ready = true;
    NSLog(@"[MGLFSR] Task119 FSR1 EASU ready (MobileGL): program=%u uViewportSize=%d uTargetSize=%d uInputTex=%d -- same EASU shader as zink/MobileGlues",
          ame119_fsr.program, ame119_fsr.uViewportSize, ame119_fsr.uTargetSize, ame119_fsr.uInputTex);

    // ---- Task 130：RCAS 锐化 pass（独立 program，失败不拖 EASU 下水）----
    // 任何一步失败 → rcasFailed=true，本会话仅 EASU（EASU 直画 fb0 旧路径）
    // + 日志留痕（用户要求的不支持回退口径）。GLSL<400 的上下文（DirectGLES
    // / Mithril 档）EASU 本就编不过、走全分辨率自愈，到不了这里；能到这里
    // 的（DirectVulkan 等 GLSL>=410）EASU 编过而 RCAS 编不过时回退仅 EASU。
    do {
        if (g->glGenFramebuffers == NULL || g->glFramebufferTexture2D == NULL) {
            NSLog(@"[MGLFSR] Task130 RCAS unavailable: FBO entry points missing -- EASU-only (MobileGL)");
            break;
        }
        std::string rcasVs = ame119_adapt_shader_version(FSR_VSSource, "rcas-vertex");
        std::string rcasFs = ame119_adapt_shader_version(FSR_RCAS_FSSource, "rcas-fragment");
        unsigned int rvs = ame119_compile(GL_VERTEX_SHADER, rcasVs);
        if (rvs == 0) {
            NSLog(@"[MGLFSR] Task130 RCAS vertex compile FAILED -- falling back to EASU-only (MobileGL)");
            break;
        }
        unsigned int rfs = ame119_compile(GL_FRAGMENT_SHADER, rcasFs);
        if (rfs == 0) {
            g->glDeleteShader(rvs);
            NSLog(@"[MGLFSR] Task130 RCAS fragment compile FAILED -- falling back to EASU-only (MobileGL)");
            break;
        }
        unsigned int rprog = g->glCreateProgram();
        g->glAttachShader(rprog, rvs);
        g->glAttachShader(rprog, rfs);
        g->glLinkProgram(rprog);
        int rok = 0;
        g->glGetProgramiv(rprog, GL_LINK_STATUS, &rok);
        g->glDeleteShader(rvs);
        g->glDeleteShader(rfs);
        if (!rok) {
            char log[1024];
            int used = 0;
            g->glGetProgramInfoLog(rprog, sizeof(log) - 1, &used, log);
            log[used > 0 && used < 1024 ? used : 0] = 0;
            NSLog(@"[MGLFSR] Task130 RCAS program link FAILED: %s -- EASU-only (MobileGL)", log);
            break;
        }
        ame119_fsr.rcasProgram = rprog;
        ame119_fsr.uRcasInputTex = g->glGetUniformLocation(rprog, "uInputTex");
        ame119_fsr.uRcasSharpness = g->glGetUniformLocation(rprog, "uSharpness");
        NSLog(@"[MGLFSR] Task130 RCAS ready (MobileGL): program=%u sharpness=%.3f (mpv-scale [0,1], default 0.2) -- EASU now draws offscreen, RCAS presents",
              ame119_fsr.rcasProgram, (double)ame130_rcas_sharpness());
    } while (false);
    if (ame119_fsr.rcasProgram == 0) ame119_fsr.rcasFailed = true;
    return true;
}

// 把默认帧缓冲 (0,0)-(srcW,srcH) 区域 EASU 升采样铺满 (dstW,dstH)。
static bool ame119_fsr_upscale(int srcW, int srcH, int dstW, int dstH) {
    if (srcW <= 0 || srcH <= 0 || dstW <= srcW || dstH <= srcH) return false;
    if (!ame119_fsr_init()) return false;
    ame119_gl_t *g = &ame119_fsr.gl;

    // 最小状态保存（MC 每帧重设管线状态；口径对齐 osm_bridge Task99 修复B：
    // FBO 双通道 + 纹理单元0 显式管理，防 MC/模组遗留非对称绑定）。
    GLint saveVp[4] = {0}, saveProg = 0, saveVao = 0, saveVbo = 0;
    GLint saveDrawFbo = 0, saveReadFbo = 0, saveActiveTex = 0, saveTexUnit0 = 0;
    g->glGetIntegerv(GL_VIEWPORT, saveVp);
    g->glGetIntegerv(GL_CURRENT_PROGRAM, &saveProg);
    g->glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &saveVao);
    g->glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saveVbo);
    g->glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saveDrawFbo);
    g->glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saveReadFbo);
    g->glGetIntegerv(GL_ACTIVE_TEXTURE, &saveActiveTex);
    g->glActiveTexture(GL_TEXTURE0);
    g->glGetIntegerv(GL_TEXTURE_BINDING_2D, &saveTexUnit0);

    g->glDisable(GL_DEPTH_TEST);
    g->glDisable(GL_SCISSOR_TEST);
    g->glDisable(GL_STENCIL_TEST);
    g->glDisable(GL_BLEND);
    g->glDisable(GL_CULL_FACE);

    g->glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // (1) 帧的区域 -> 纹理（GPU 侧拷贝；存储尺寸变化时重建）
    g->glBindTexture(GL_TEXTURE_2D, ame119_fsr.tex);
    if (ame119_fsr.texW != srcW || ame119_fsr.texH != srcH) {
        g->glTexParameteri(GL_TEXTURE_2D, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2802 /*GL_TEXTURE_WRAP_S*/, GL_CLAMP_TO_EDGE);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2803 /*GL_TEXTURE_WRAP_T*/, GL_CLAMP_TO_EDGE);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
        g->glCopyTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 0, 0, srcW, srcH, 0);
        ame119_fsr.texW = srcW;
        ame119_fsr.texH = srcH;
    } else {
        g->glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, srcW, srcH);
    }

    // ---- Task 130：RCAS ping-pong 目标惰性建/重建（尺寸=dstW×dstH）----
    // 失败（FBO 不完整等）→ rcasFailed=true，EASU 走旧直画 fb0 路径。
    // sharpness < 0 = 用户关闭（仅 EASU，与 MobileGlues 侧同语义）。
    float ame130_sharp = ame130_rcas_sharpness();
    bool ame130_rcasOn = ame130_sharp >= 0.0f &&
                         !ame119_fsr.rcasFailed && ame119_fsr.rcasProgram != 0;
    if (ame130_rcasOn && (ame119_fsr.easuW != dstW || ame119_fsr.easuH != dstH)) {
        if (ame119_fsr.easuTex != 0) g->glDeleteTextures(1, &ame119_fsr.easuTex);
        if (ame119_fsr.easuFBO != 0) g->glDeleteFramebuffers(1, &ame119_fsr.easuFBO);
        ame119_fsr.easuTex = ame119_fsr.easuFBO = 0;
        ame119_fsr.easuW = ame119_fsr.easuH = 0;
        unsigned int tex = 0, fbo = 0;
        g->glGenTextures(1, &tex);
        g->glBindTexture(GL_TEXTURE_2D, tex);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2801, 0x2600 /*GL_NEAREST*/);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2800, 0x2600);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2802, GL_CLAMP_TO_EDGE);
        g->glTexParameteri(GL_TEXTURE_2D, 0x2803, GL_CLAMP_TO_EDGE);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
        g->glTexImage2D(GL_TEXTURE_2D, 0, 0x8058 /*GL_RGBA8*/, dstW, dstH, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        g->glGenFramebuffers(1, &fbo);
        g->glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        g->glFramebufferTexture2D(GL_FRAMEBUFFER, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/, GL_TEXTURE_2D, tex, 0);
        if (g->glCheckFramebufferStatus != NULL &&
            g->glCheckFramebufferStatus(GL_FRAMEBUFFER) != 0x8CD5 /*GL_FRAMEBUFFER_COMPLETE*/) {
            NSLog(@"[MGLFSR] Task130 RCAS offscreen target incomplete (%dx%d) -- falling back to EASU-only (MobileGL)", dstW, dstH);
            g->glDeleteTextures(1, &tex);
            g->glDeleteFramebuffers(1, &fbo);
            g->glBindFramebuffer(GL_FRAMEBUFFER, 0);
            ame119_fsr.rcasFailed = true;
            ame130_rcasOn = false;
        } else {
            ame119_fsr.easuTex = tex;
            ame119_fsr.easuFBO = fbo;
            ame119_fsr.easuW = dstW;
            ame119_fsr.easuH = dstH;
            g->glBindFramebuffer(GL_FRAMEBUFFER, 0);
        }
    }

    // (2) EASU 全屏绘制：RCAS 就绪时 → 离屏 easuTex；否则直画默认帧缓冲
    //     （= MobileGL swapchain image，旧路径）。
    if (ame130_rcasOn) {
        g->glBindFramebuffer(GL_FRAMEBUFFER, ame119_fsr.easuFBO);
    }
    g->glUseProgram(ame119_fsr.program);
    if (ame119_fsr.uInputTex >= 0) g->glUniform1i(ame119_fsr.uInputTex, 0);
    g->glUniform2f(ame119_fsr.uViewportSize, (float)srcW, (float)srcH);
    g->glUniform2f(ame119_fsr.uTargetSize, (float)dstW, (float)dstH);
    g->glBindVertexArray(ame119_fsr.vao);
    g->glViewport(0, 0, dstW, dstH);
    g->glDrawArrays(GL_TRIANGLES, 0, 6);

    // (2z) Task 130：RCAS 锐化 —— easuTex -> fb0（1:1，5-tap 十字）。
    //     画进 fb0 = MobileGL 内部 swapchain image，eglSwapBuffers 直呈
    //     （保持 Task119 的 GPU 侧零回读优势）。开销口径同 zink：<0.5ms
    //     全屏 5-tap + 纯 ALU，无回读无同步。
    if (ame130_rcasOn) {
        g->glBindFramebuffer(GL_FRAMEBUFFER, 0);
        g->glActiveTexture(GL_TEXTURE0);
        g->glBindTexture(GL_TEXTURE_2D, ame119_fsr.easuTex);
        g->glUseProgram(ame119_fsr.rcasProgram);
        if (ame119_fsr.uRcasInputTex >= 0) g->glUniform1i(ame119_fsr.uRcasInputTex, 0);
        if (ame119_fsr.uRcasSharpness >= 0) {
            g->glUniform1f(ame119_fsr.uRcasSharpness, ame130_sharp);
        }
        g->glViewport(0, 0, dstW, dstH);
        g->glDrawArrays(GL_TRIANGLES, 0, 6);
        ame119_fsr.rcasFrames++;
        if (!ame119_fsr.rcasEngaged) {
            ame119_fsr.rcasEngaged = true;
            NSLog(@"[MGLFSR] Task130 RCAS engaged (MobileGL): EASU %dx%d -> offscreen %dx%d -> RCAS -> swapchain, sharpness=%.3f",
                  srcW, srcH, dstW, dstH, (double)ame130_sharp);
        } else if (ame119_fsr.rcasFrames == 600) {
            NSLog(@"[MGLFSR] Task130 RCAS steady: 600 frames sharpened (MobileGL)");
        }
    }

    // (3) 还原（口径对齐 osm_bridge：FBO 双通道分别还回；纹理先还单元0
    //     绑定再还原活动单元）
    g->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (unsigned int)saveDrawFbo);
    g->glBindFramebuffer(GL_READ_FRAMEBUFFER, (unsigned int)saveReadFbo);
    g->glBindVertexArray((unsigned int)saveVao);
    g->glBindBuffer(GL_ARRAY_BUFFER, (unsigned int)saveVbo);
    g->glUseProgram((unsigned int)saveProg);
    g->glBindTexture(GL_TEXTURE_2D, (unsigned int)saveTexUnit0);
    g->glActiveTexture((unsigned int)saveActiveTex);
    g->glViewport(saveVp[0], saveVp[1], saveVp[2], saveVp[3]);

    ame119_fsr.frames++;
    if (!ame119_fsr.engaged) {
        ame119_fsr.engaged = true;
        NSLog(@"[MGLFSR] Task119 FSR1 upscale engaged (MobileGL): render %dx%d -> surface %dx%d (pre-swap EASU, GPU-direct present, RCAS=%d)",
              srcW, srcH, dstW, dstH, ame130_rcasOn ? 1 : 0);
    } else if (ame119_fsr.frames == 600) {
        NSLog(@"[MGLFSR] Task119 FSR1 upscale steady: 600 frames upsampled (MobileGL)");
    }
    return true;
}

// ============================================================================
// Task 148：内置 FSR1 仲裁探测。
//
// 病机（Run #356 Vulkan 花屏+倒转实锤）：libMobileGL 两后端是 MobileGlues-cpp
// 共体构建，config.json 的 fsr1Setting（Task78/130 每次启动写入）令渲染器
// 内置 FSR1 生效——glBindFramebuffer(fb0) 的 DRAW 绑定被重定向到 FSR1 渲染
// 目标（framebuffer.cpp:186），呈现由 presentSurface→ApplyFSR 在
// eglSwapBuffers 内收口。启动器侧预交换链此时若照跑，RCAS 的"画进 fb0"
// 会经同一重定向灌进 FSR1 目标，每帧摧毁 MC 刚渲染好的帧——这正是 Run #356
// 双会话（EASU/RCAS 全部就绪、600 帧稳定运行）却输出花屏+倒转的完整机理。
//
// 探测原理：GL_DRAW_FRAMEBUFFER_BINDING 的 getter 会隐藏重定向
// （getter.cpp:147 特意回 0，防应用保存重定向句柄），改走附件查询——
// 把 DRAW 绑定显式指回 fb0（重定向生效时后端真实绑定 = FSR1 渲染目标），
// 查其 COLOR_ATTACHMENT0 的 OBJECT_NAME：重定向时非零（FSR1 目标的颜色
// 纹理）；无重定向（真默认帧缓冲）时按规范拒绝 NAME 查询（报错）且名字
// 保持 0。探测开销 ≈ 4 次状态查询，仅在启动器链仍活跃时逐帧执行；
// 一旦判内置接管，本链永久退休、探测停止。错误位读走不留痕。
// ============================================================================
static bool ame148_detect_builtin_fsr_redirect(void) {
    if (!ame119_resolve_gl()) return false;   // 符号不可用：链无从服务，也探不到重定向
    ame119_gl_t *g = &ame119_fsr.gl;
    if (g->glGetFramebufferAttachmentParameteriv == NULL) {
        // 导出表缺失 = 渲染器过旧。保守判内置接管：宁可退休（半分辨率直呈
        // 下一轮可诊断），不可重演每帧毁帧。
        NSLog(@"[MGLFSR] Task148 arbitration: attachment-query entry missing -- assuming builtin FSR1 owns fb0 (chain retired)");
        return true;
    }
    GLint saveDraw = 0;
    g->glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saveDraw);
    if (g->glGetError) g->glGetError();   // 清残留错误位，保证探测结果干净
    g->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);   // fb0 的 DRAW 绑定（重定向生效点）
    GLint objType = 0, objName = 0;
    g->glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER,
                                             0x8CE0 /*GL_COLOR_ATTACHMENT0*/,
                                             0x8210 /*GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE*/, &objType);
    g->glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER,
                                             0x8CE0 /*GL_COLOR_ATTACHMENT0*/,
                                             0x8C66 /*GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME*/, &objName);
    unsigned int err = g->glGetError ? g->glGetError() : 0;
    g->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (unsigned int)saveDraw);   // saveDraw=0 时重定向照常重放，状态无损
    bool owns = (objName != 0);
    // 兜底模式下本函数逐帧复探——明细行只在首探或判定翻转时打印，防刷屏。
    if (!ame119_fsr.ame148_arbitrated || owns != ame119_fsr.ame148_builtin_owns) {
        NSLog(@"[MGLFSR] Task148 builtin-FSR1 arbitration: fb0 draw color0 type=0x%x name=%u err=0x%x -> %s",
              (unsigned)objType, (unsigned)objName, err,
              owns ? "REDIRECTED -- builtin FSR1 owns upscale+present, launcher chain RETIRED"
                   : "no redirect -- launcher chain stays as fallback");
    }
    return owns;
}

// ============================================================================
// 对外入口（gl_bridge.m 调用）。
// ============================================================================

// 预交换 FSR 升采样：当前渲染器是 MobileGL 且几何满足 FSR 形态时执行一次
// EASU pass。返回 true = 本帧已升采样（gl_bridge 无需其他动作，仅日志用途）。
extern "C" bool ame_mgl_fsr_before_swap(void) {
    // ---- Task 154：整链退休（用户基准 da5918a 语义恢复）----
    // 7c32bc3 装机日志（3b35b26 构建，Vulkan 会话）三重实证：
    //   1. "Task153 backbuffer query unavailable (no current EGL surface on
    //      this thread?)" —— libMobileGL 的 EGL 是伪 EGL（surface/ctx 句柄
    //      恒 0x1、无 current 状态跟踪），eglGetCurrentDisplay/CurrentSurface
    //      返回空 → 后缓冲几何仲裁链从首帧起永久 idle；
    //   2. 延迟缩窗因此永不下发 → MC 窗口信念恒全尺寸（swap 探针 viewport
    //      2360x1640 实证），而 sendTouchPoint 仍除 mgFsrScale(2.0) →
    //      触点只落到 MC 坐标空间左下四分之一 = 用户实测"输入错位"；
    //   3. d36a24f 构建上链曾按启动器信念几何画 EASU/RCAS（2360x1640 视口
    //      栅格化进渲染器钉在窗口信念上的 1180x820 后缓冲）→ 每帧裁切毁帧
    //      = Vulkan 花屏 / ES "方块不渲染"。
    // da5918a（5.1.0 用户认可的正常态，9f32cb4/1d4ff3a 装机日志）上 MobileGL
    // 无任何启动器侧 FSR 介入、全分辨率直呈 = 正常。配合 ame83_fsr_capable_
    // renderer 对 MobileGL 的除名（mgFsrScale 恒 1.0，缩窗/输入除法/延迟武装
    // 天然失效），本入口直接返回 false：零绘制、零几何干预、零输入干预。
    // 代码体完整保留（Task119-153 的机制与病历存档）；未来若 MobileGL 提供
    // 真实 EGL current 跟踪或内置 FSR1，移除本门禁即可复用。
    static bool s_ame154_logged = false;
    if (!s_ame154_logged) {
        s_ame154_logged = true;
        const char *ame154_renderer = getenv("AMETHYST_RENDERER");
        if (isMobileGLRenderer(ame154_renderer)) {
            NSLog(@"[MGLFSR] Task154 MobileGL pre-swap FSR chain RETIRED (renderer=%s) -- full-res direct present, da5918a semantics restored; FSR remains available on MobileGlues/zink",
                  ame154_renderer ?: "<unset>");
        }
    }
    return false;
#if 0
    const char *renderer = getenv("AMETHYST_RENDERER");
    // MobileGlues 有自己的内置 FSR1（Task78-82）；zink 走 osm_bridge；
    // 这里只服务 MobileGL 两后端（DirectVulkan / DirectGLES 共体二进制）。
    if (!isMobileGLRenderer(renderer)) return false;

    int surfW = ame_surfaceWidth, surfH = ame_surfaceHeight;
    if (surfW <= 0 || surfH <= 0) return false;   // 表面未初始化（非 FSR 场景）

    // ---- Task 148：内置 FSR1 仲裁（见 ame148_detect_builtin_fsr_redirect）----
    // 判内置接管 → 永久退休（探测停止，零开销）；判无重定向 → 本链作为
    // 兜底继续活跃，且逐帧复探（渲染器侧 InitFSRResources 失败后会重试，
    // 重定向可能中途出现——出现即 Retirement，杜绝晚到毁帧）。
    if (!ame119_fsr.ame148_arbitrated || !ame119_fsr.ame148_builtin_owns) {
        bool owns = ame148_detect_builtin_fsr_redirect();
        if (!ame119_fsr.ame148_arbitrated || owns != ame119_fsr.ame148_builtin_owns) {
            NSLog(@"[MGLFSR] Task148 arbitration verdict: builtin FSR1 %s -- launcher pre-swap chain %s",
                  owns ? "OWNS fb0 (redirect detected)" : "not active (no fb0 redirect)",
                  owns ? "RETIRED" : "ACTIVE (fallback upscale)");
        }
        ame119_fsr.ame148_builtin_owns = owns;
        ame119_fsr.ame148_arbitrated = true;
    }
    if (ame119_fsr.ame148_builtin_owns) return false;

    // ---- Task 153：真实后缓冲几何仲裁 ----
    // 目标尺寸 = 渲染器自己的 eglQuerySurface 读数，绝不信启动器信念
    // ame_surfaceWidth（MobileGL 把 surface 钉在 MC 窗口信念上，见文件头
    // Task153 病历——旧代码按信念把 2360x1640 的 RCAS 画进 1180x820 的
    // 后缓冲，只有左下四分之一落图 = 每帧花屏）。查询失败 = 零开销跳过，
    // 绝不按信念盲画。
    int bbW = 0, bbH = 0;
    if (!ame153_query_backbuffer(&bbW, &bbH)) {
        static bool s_ame153_queryLogged = false;
        if (!s_ame153_queryLogged) {
            s_ame153_queryLogged = true;
            NSLog(@"[MGLFSR] Task153 backbuffer query unavailable (no current EGL surface on this thread?) -- chain idle this frame");
        }
        return false;
    }

    // 输入区域：优先 MC 真实呈现视口（Task105 同款自适应——BMC2 类模组
    // 铺进 fb0 的区域可能小于告知窗口），闸门不符则回退 windowWidth 信仰。
    int inW = windowWidth, inH = windowHeight;
    if (ame119_fsr.ready || ame119_resolve_gl()) {
        GLint vp[4] = {0, 0, 0, 0};
        ame119_fsr.gl.glGetIntegerv(GL_VIEWPORT, vp);
        long vpArea = (long)vp[2] * (long)vp[3];
        long beliefArea = (long)windowWidth * (long)windowHeight;
        if (vp[0] == 0 && vp[1] == 0 && vp[2] > 0 && vp[3] > 0 &&
            vp[2] <= bbW && vp[3] <= bbH &&
            (beliefArea <= 0 || vpArea * 4 >= beliefArea)) {
            inW = vp[2];
            inH = vp[3];
        }
    }

    // ---- Task 153：延迟缩窗（真 FSR 几何复位）----
    // SurfaceViewController 在 FSR 联动 + MobileGL 时不再预先把 MC 窗口缩到
    // surface/档位（那会让渲染器把后缓冲也钉成渲染尺寸），而是先按全尺寸
    // 窗口启动、由本链在确认后缓冲为全尺寸后再下发缩窗。装机观察证据
    //（403a459 会话）：窗口从 2360x1640 缩到 1180x820 后 surface 保持
    // 2360x1640 不缩——这正是 EASU/RCAS 需要的几何（渲染小帧 + 全尺寸
    // 后缓冲）。若个别构建/后端仍随窗口缩 surface：下方"无余量"判定接管
    //（后缓冲==窗口尺寸 → 直呈 + CA 缩放），画面保真不花屏。
    if (ame153_fsr_deferred_armed) {
        int believedW = ame153_fsr_believed_surface_w;
        int believedH = ame153_fsr_believed_surface_h;
        if (believedW > 0 && believedH > 0 &&
            bbW >= believedW - 8 && bbH >= believedH - 8) {
            ame153_fsr_deferred_armed = 0;   // 本帧消费；主线程重算联动时会重新武装
            NSLog(@"[MGLFSR] Task153 deferred shrink applied: backbuffer %dx%d >= believed surface %dx%d -> pushing MC render window %dx%d (chain engages EASU once MC's viewport settles)",
                  bbW, bbH, believedW, believedH,
                  ame153_fsr_pending_render_w, ame153_fsr_pending_render_h);
            CallbackBridge_nativeSendScreenSize(ame153_fsr_pending_render_w,
                                                ame153_fsr_pending_render_h);
            // 本帧让 MC 消化窗口变更（视口尚未收缩，此刻采样只会拿到局部帧）
            return false;
        }
        // 后缓冲未达全尺寸：保持武装继续观察（渲染器可能晚建/重建表面）。
    }

    // 无需/无法升采样：MC 的帧已铺满后缓冲（FSR 关闭 / 已恢复全分辨率 /
    // 后缓冲被渲染器钉在窗口尺寸=延迟缩窗未获得余量）→ 直呈零花屏，
    // 画面由 CAMetalLayer 按内容缩放铺满物理屏（画质=双线性，几何正确）。
    if (inW <= 0 || inH <= 0) return false;
    if (inW >= bbW || inH >= bbH) {
        if (ame153_fsr_deferred_armed) {
            // 延迟缩窗未换来全尺寸后缓冲（渲染器把 surface 钉在窗口尺寸的
            // 当前行为）：保持全尺寸窗口直呈（画面正确、性能=全分辨率渲染），
            // 并归一输入除数（窗口=全尺寸而 mgFsrScale>1 的口径错位——
            // Task139 heal 同款语义，触点只发一半的旧病历）。
            ame153_fsr_deferred_armed = 0;
            NSLog(@"[MGLFSR] Task153 geometry arbitration: backbuffer %dx%d == window %dx%d (renderer pinned surface to window size, no upscale headroom) -- full-res direct present, zero corruption, input scale normalized",
                  bbW, bbH, inW, inH);
            ame139_fsr_heal_reset_input_scale();
        }
        return false;
    }

    bool ok = ame119_fsr_upscale(inW, inH, bbW, bbH);
    if (!ok && !ame119_fsr.healed) {
        ame119_fsr.healed = true;
        NSLog(@"[MGLFSR] Task119 FSR upscale unavailable -- restoring MC window to backbuffer %dx%d (direct full-res render)",
              bbW, bbH);
        // 与 osm_bridge Task83b 同款自愈：MC 切回后缓冲真实尺寸渲染，画面
        // 退出蜷缩（Task153：用实测后缓冲而非信念，防再次溢出）。
        CallbackBridge_nativeSendScreenSize(bbW, bbH);
        // Task 139：输入侧同步复位 —— MC 窗口信念已变为全表面，
        // sendTouchPoint 的 mgFsrScale 除数若仍为档位系数，触点坐标
        // 只发一半（23:08 会话“mg 渲染器输入错位”实锤）。
        ame139_fsr_heal_reset_input_scale();
    }
    return ok;
#endif  // Task 154：#if 0 —— 旧链体（存档，见函数头退休说明）
}

// 上下文重建时的复位（gl_init_context 成功后调用）：程序/纹理属于旧上下文，
// 必须重编； healed 标志保留（会话级语义——本会话已回退全分辨率）。
// Task 130：RCAS 对象（rcasProgram/easuTex/easuFBO）同属旧上下文，一并清零；
// rcasFailed 不保留重置（新上下文可能支持——重试语义与 EASU initFailed 一致）。
extern "C" void ame_mgl_fsr_context_reset(void) {
    if (!ame119_fsr.ready && !ame119_fsr.initFailed && ame119_fsr.frames == 0) return;
    ame119_fsr.ready = false;
    ame119_fsr.initFailed = false;
    ame119_fsr.program = ame119_fsr.vao = ame119_fsr.vbo = ame119_fsr.tex = 0;
    ame119_fsr.texW = ame119_fsr.texH = 0;
    ame119_fsr.engaged = false;
    ame119_fsr.rcasProgram = 0;
    ame119_fsr.easuTex = ame119_fsr.easuFBO = 0;
    ame119_fsr.easuW = ame119_fsr.easuH = 0;
    ame119_fsr.rcasFailed = false;
    ame119_fsr.rcasEngaged = false;
    NSLog(@"[MGLFSR] Task119 FSR state reset for new context (healed=%d, frames=%ld, rcasFrames=%ld)",
          ame119_fsr.healed ? 1 : 0, ame119_fsr.frames, ame119_fsr.rcasFrames);
}
