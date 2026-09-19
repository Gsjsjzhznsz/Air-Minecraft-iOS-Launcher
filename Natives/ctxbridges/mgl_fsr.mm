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

#include "../external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h"
#include "../environ.h"
#include "../utils.h"

// ============================================================================
// GL 2.0+ 枚举（与 osm_bridge 同款防御性定义；MobileGL 是桌面 GL 4.6 实现，
// 全量支持这些入口）。
#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER    0x8B31
#endif
#ifndef GL_FRAGMENT_SHADER
#define GL_FRAGMENT_SHADER  0x8B92
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
#ifndef GL_ARRAY_BUFFER_BINDING
#define GL_ARRAY_BUFFER_BINDING 0x8B8C
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
    void (*glUniform1i)(int, int);
    // texture
    void (*glGenTextures)(int, unsigned int*);
    void (*glBindTexture)(unsigned int, unsigned int);
    void (*glTexParameteri)(unsigned int, unsigned int, int);
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
    void (*glDrawArrays)(unsigned int, int, int);
    void (*glViewport)(int, int, int, int);
    void (*glDisable)(unsigned int);
    void (*glGetIntegerv)(unsigned int, int*);
    unsigned int (*glGetError)(void);
} ame119_gl_t;

static struct {
    ame119_gl_t gl;
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
} ame119_fsr = {0};

// 符号解析：优先 eglGetProcAddress（上游实证路径），失败回退 dlsym 直连。
static void *ame119_resolve(const char *name) {
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
    // 返回既有句柄，仅为拿 eglGetProcAddress 的稳定入口。
    void *mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGL, RTLD_NOW | RTLD_NOLOAD);
    if (mg == NULL) {
        mg = dlopen("@rpath/" RENDERER_NAME_MOBILEGL, RTLD_NOW | RTLD_LOCAL);
    }
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
        {"glGenTextures",             (void **)&ame119_fsr.gl.glGenTextures},
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
        {"glGetError",                (void **)&ame119_fsr.gl.glGetError},
    };
    int ok = 0;
    for (auto &s : kSym) {
        *s.slot = ame119_resolve(s.name);
        if (*s.slot != NULL) ++ok;
    }
    NSLog(@"[MGLFSR] Task119 GL resolve: %d/%zu symbols (eglGetProcAddress=%p via %s)",
          ok, sizeof(kSym) / sizeof(kSym[0]), (void *)ame119_fsr.eglGetProcAddress,
          mg != NULL ? "libMobileGL handle" : "RTLD_DEFAULT");
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
    if (ver == 0) return out;   // 查询失败：原样（编译错误走兜底）
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
    if (sh == 0) return 0;
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

    // (2) EASU 全屏绘制 -> 默认帧缓冲全幅（= MobileGL swapchain image）
    g->glUseProgram(ame119_fsr.program);
    if (ame119_fsr.uInputTex >= 0) g->glUniform1i(ame119_fsr.uInputTex, 0);
    g->glUniform2f(ame119_fsr.uViewportSize, (float)srcW, (float)srcH);
    g->glUniform2f(ame119_fsr.uTargetSize, (float)dstW, (float)dstH);
    g->glBindVertexArray(ame119_fsr.vao);
    g->glViewport(0, 0, dstW, dstH);
    g->glDrawArrays(GL_TRIANGLES, 0, 6);

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
        NSLog(@"[MGLFSR] Task119 FSR1 upscale engaged (MobileGL): render %dx%d -> surface %dx%d (pre-swap EASU, GPU-direct present)",
              srcW, srcH, dstW, dstH);
    } else if (ame119_fsr.frames == 600) {
        NSLog(@"[MGLFSR] Task119 FSR1 upscale steady: 600 frames upsampled (MobileGL)");
    }
    return true;
}

// ============================================================================
// 对外入口（gl_bridge.m 调用）。
// ============================================================================

// 预交换 FSR 升采样：当前渲染器是 MobileGL 且几何满足 FSR 形态时执行一次
// EASU pass。返回 true = 本帧已升采样（gl_bridge 无需其他动作，仅日志用途）。
extern "C" bool ame_mgl_fsr_before_swap(void) {
    const char *renderer = getenv("AMETHYST_RENDERER");
    // MobileGlues 有自己的内置 FSR1（Task78-82）；zink 走 osm_bridge；
    // 这里只服务 MobileGL 两后端（DirectVulkan / DirectGLES 共体二进制）。
    if (!isMobileGLRenderer(renderer)) return false;

    int surfW = ame_surfaceWidth, surfH = ame_surfaceHeight;
    if (surfW <= 0 || surfH <= 0) return false;   // 表面未初始化（非 FSR 场景）

    // 输入区域：优先 MC 真实呈现视口（Task105 同款自适应——BMC2 类模组
    // 铺进 fb0 的区域可能小于告知窗口），闸门不符则回退 windowWidth 信仰。
    int inW = windowWidth, inH = windowHeight;
    if (ame119_fsr.ready || ame119_resolve_gl()) {
        GLint vp[4] = {0, 0, 0, 0};
        ame119_fsr.gl.glGetIntegerv(GL_VIEWPORT, vp);
        long vpArea = (long)vp[2] * (long)vp[3];
        long beliefArea = (long)windowWidth * (long)windowHeight;
        if (vp[0] == 0 && vp[1] == 0 && vp[2] > 0 && vp[3] > 0 &&
            vp[2] <= surfW && vp[3] <= surfH &&
            (beliefArea <= 0 || vpArea * 4 >= beliefArea)) {
            inW = vp[2];
            inH = vp[3];
        }
    }

    // 无需升采样：输入已达表面（FSR 关闭 / 兜底已恢复全分辨率）→ 零开销跳过。
    if (inW <= 0 || inH <= 0 || inW >= surfW || inH >= surfH) return false;

    bool ok = ame119_fsr_upscale(inW, inH, surfW, surfH);
    if (!ok && !ame119_fsr.healed) {
        ame119_fsr.healed = true;
        NSLog(@"[MGLFSR] Task119 FSR upscale unavailable -- restoring MC window to surface %dx%d (direct full-res render)",
              surfW, surfH);
        // 与 osm_bridge Task83b 同款自愈：MC 切回全分辨率渲染，画面退出蜷缩。
        CallbackBridge_nativeSendScreenSize(surfW, surfH);
    }
    return ok;
}

// 上下文重建时的复位（gl_init_context 成功后调用）：程序/纹理属于旧上下文，
// 必须重编； healed 标志保留（会话级语义——本会话已回退全分辨率）。
extern "C" void ame_mgl_fsr_context_reset(void) {
    if (!ame119_fsr.ready && !ame119_fsr.initFailed && ame119_fsr.frames == 0) return;
    ame119_fsr.ready = false;
    ame119_fsr.initFailed = false;
    ame119_fsr.program = ame119_fsr.vao = ame119_fsr.vbo = ame119_fsr.tex = 0;
    ame119_fsr.texW = ame119_fsr.texH = 0;
    ame119_fsr.engaged = false;
    NSLog(@"[MGLFSR] Task119 FSR state reset for new context (healed=%d, frames=%ld)",
          ame119_fsr.healed ? 1 : 0, ame119_fsr.frames);
}
