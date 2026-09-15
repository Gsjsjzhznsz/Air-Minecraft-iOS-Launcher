#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include "environ.h"
#include "utils.h"

#include "bridge_tbl.h"
#include "osm_bridge.h"
#include "osmesa_internal.h"

// Task 83（FSR 独立化）：复用 MobileGlues 的 FSR1 EASU shader（#version 450，
// zink = Mesa GL 4.6 compat 原生编译，无需降级）。该头是纯字符串字面量
// （clang/gcc 的 C/ObjC 模式均接受 raw string 字面量），每个包含它的 TU
// 各持一份私有拷贝——启动器主二进制与 libmobileglues.dylib 互不可见，
// 无符号冲突。
#include "../external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h"

static osmesa_library handle;
static void *s_osmDL = NULL;   // libOSMesa 句柄（dlsym_OSMesa 保存，FSR GL 惰性解析用）

void dlsym_OSMesa() {
    void* dl_handle = dlopen([NSString stringWithFormat:@"@rpath/%s", getenv("AMETHYST_RENDERER")].UTF8String, RTLD_GLOBAL);
    assert(dl_handle);
    s_osmDL = dl_handle;
    handle.OSMesaMakeCurrent = dlsym(dl_handle,"OSMesaMakeCurrent");
    handle.OSMesaGetCurrentContext = dlsym(dl_handle,"OSMesaGetCurrentContext");
    handle.OSMesaCreateContext = dlsym(dl_handle, "OSMesaCreateContext");
    handle.OSMesaDestroyContext = dlsym(dl_handle, "OSMesaDestroyContext");
    handle.OSMesaPixelStore = dlsym(dl_handle,"OSMesaPixelStore");
    handle.glGetString = dlsym(dl_handle,"glGetString");
    handle.glClearColor = dlsym(dl_handle, "glClearColor");
    handle.glClear = dlsym(dl_handle, "glClear");
    handle.glFinish = dlsym(dl_handle, "glFinish");
}

bool osm_init() {
    dlsym_OSMesa();
    return true; // no more specific initialization required
}

osm_render_window_t* osm_init_context(osm_render_window_t* share) {
    osm_render_window_t* render_window = calloc(1, sizeof(osm_render_window_t));
    OSMesaContext context = handle.OSMesaCreateContext(GL_RGBA, share ? share->context : NULL);
    if(!context) {
        NSLog(@"OSMBridge: FAILED to create context");
        free(render_window);
        return NULL;
    }
    render_window->context = context;
    return render_window;
}

// ============================================================================
// Task 83（FSR 独立化）：zink 通用 FSR1 EASU——呈现前升采样
//
// 语义（与 MG 内置 FSR1 的 Task78 联动同构）：
//   - MC 窗口信念 windowWidth×windowHeight = surface / fsr_scale（渲染分辨率），
//     由 SurfaceViewController 的 Task83 联动下发；
//   - OSMesa 缓冲 = 全尺寸表面（ame_surfaceWidth×Height，全局单点写入），
//     MC 以自己的视口把帧画进缓冲的 window 尺寸区域（GL 原点左下）；
//   - 本 pass 在 osm_swap_buffers（glFinish 之后）把该区域 EASU 升采样
//     铺满整个缓冲，CGImage 上屏即全幅。EASU shader 与 MobileGlues 逐字
//     相同（uniform：uInputTex/uViewportSize/uTargetSize）。
//
// 逐帧成本：glCopyTexSubImage2D（GPU 侧拷贝，zink 映射为 Vulkan 图像拷贝）
// + 一次全屏 EASU 绘制。窗口==缓冲（FSR 关）时零开销跳过。
//
// 兜底：shader 编译失败（exotic Mesa）→ 一次性回调 nativeSendScreenSize
// 恢复窗口=表面（MC 下一帧起全分辨率直渲，画面不再缩角），日志留痕。
// ============================================================================

// GL 2.0+ 枚举（GL/gl.h 只有 1.1；OSMesa 桌面 GL 4.6 全量支持）
#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER    0x8B31
#endif
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

typedef unsigned int ame83_gluint;
typedef int ame83_glint;
typedef char ame83_glchar;
typedef void (*ame83_glshaderfn)(unsigned int, GLsizei, const char* const*, const GLint*);
typedef void (*ame83_glgetshaderiv)(unsigned int, unsigned int, int*);
typedef void (*ame83_gllogfn)(unsigned int, GLsizei, GLsizei*, char*);

typedef struct {
    // shader/program
    ame83_gluint (*glCreateShader)(unsigned int);
    ame83_glshaderfn glShaderSource;
    void (*glCompileShader)(unsigned int);
    ame83_glgetshaderiv glGetShaderiv;
    ame83_gllogfn glGetShaderInfoLog;
    ame83_gluint (*glCreateProgram)(void);
    void (*glAttachShader)(unsigned int, unsigned int);
    void (*glLinkProgram)(unsigned int);
    ame83_glgetshaderiv glGetProgramiv;
    ame83_gllogfn glGetProgramInfoLog;
    void (*glDeleteShader)(unsigned int);
    ame83_glint (*glGetUniformLocation)(unsigned int, const char*);
    void (*glUseProgram)(unsigned int);
    void (*glUniform2f)(unsigned int, float, float);
    // texture
    void (*glGenTextures)(GLsizei, unsigned int*);
    void (*glDeleteTextures)(GLsizei, const unsigned int*);
    void (*glBindTexture)(unsigned int, unsigned int);
    void (*glTexParameteri)(unsigned int, unsigned int, int);
    void (*glCopyTexImage2D)(unsigned int, int, unsigned int, int, int, GLsizei, GLsizei, int);
    void (*glCopyTexSubImage2D)(unsigned int, int, int, int, int, int, GLsizei, GLsizei);
    // vertex
    void (*glGenVertexArrays)(GLsizei, unsigned int*);
    void (*glBindVertexArray)(unsigned int);
    void (*glGenBuffers)(GLsizei, unsigned int*);
    void (*glBindBuffer)(unsigned int, unsigned int);
    void (*glBufferData)(unsigned int, long, const void*, unsigned int);
    void (*glVertexAttribPointer)(unsigned int, int, unsigned int, unsigned char, GLsizei, const void*);
    void (*glEnableVertexAttribArray)(unsigned int);
    // draw/state
    void (*glDrawArrays)(unsigned int, int, GLsizei);
    void (*glViewport)(int, int, GLsizei, GLsizei);
    void (*glDisable)(unsigned int);
    void (*glGetIntegerv)(unsigned int, int*);
} ame83_gl_t;

static struct {
    ame83_gl_t gl;
    bool resolved;      // 函数表已解析（无论成败不再重试）
    bool initFailed;    // shader/program 初始化失败（不再每帧重试编译）
    bool ready;         // program+VAO+texture 就绪
    unsigned int program, vao, vbo, tex;
    int uViewportSize, uTargetSize;
    int texW, texH;     // 当前纹理存储尺寸（变更时重建）
    bool engaged;       // 至少跑过一次升采样（一次性日志用）
    bool healed;        // 兜底窗口恢复已触发
    long frames;        // 升采样帧计数（低频日志用）
} ame83_fsr = {0};

static bool ame83_resolve_gl(void) {
    if (ame83_fsr.resolved) return ame83_fsr.gl.glCreateShader != NULL;
    ame83_fsr.resolved = true;
    if (s_osmDL == NULL) return false;
    static const struct { const char *name; void **slot; } kSyms[] = {
        {"glCreateShader",            (void**)&ame83_fsr.gl.glCreateShader},
        {"glShaderSource",            (void**)&ame83_fsr.gl.glShaderSource},
        {"glCompileShader",           (void**)&ame83_fsr.gl.glCompileShader},
        {"glGetShaderiv",             (void**)&ame83_fsr.gl.glGetShaderiv},
        {"glGetShaderInfoLog",        (void**)&ame83_fsr.gl.glGetShaderInfoLog},
        {"glCreateProgram",           (void**)&ame83_fsr.gl.glCreateProgram},
        {"glAttachShader",            (void**)&ame83_fsr.gl.glAttachShader},
        {"glLinkProgram",             (void**)&ame83_fsr.gl.glLinkProgram},
        {"glGetProgramiv",            (void**)&ame83_fsr.gl.glGetProgramiv},
        {"glGetProgramInfoLog",       (void**)&ame83_fsr.gl.glGetProgramInfoLog},
        {"glDeleteShader",            (void**)&ame83_fsr.gl.glDeleteShader},
        {"glGetUniformLocation",      (void**)&ame83_fsr.gl.glGetUniformLocation},
        {"glUseProgram",              (void**)&ame83_fsr.gl.glUseProgram},
        {"glUniform2f",               (void**)&ame83_fsr.gl.glUniform2f},
        {"glGenTextures",             (void**)&ame83_fsr.gl.glGenTextures},
        {"glDeleteTextures",          (void**)&ame83_fsr.gl.glDeleteTextures},
        {"glBindTexture",             (void**)&ame83_fsr.gl.glBindTexture},
        {"glTexParameteri",           (void**)&ame83_fsr.gl.glTexParameteri},
        {"glCopyTexImage2D",          (void**)&ame83_fsr.gl.glCopyTexImage2D},
        {"glCopyTexSubImage2D",       (void**)&ame83_fsr.gl.glCopyTexSubImage2D},
        {"glGenVertexArrays",         (void**)&ame83_fsr.gl.glGenVertexArrays},
        {"glBindVertexArray",         (void**)&ame83_fsr.gl.glBindVertexArray},
        {"glGenBuffers",              (void**)&ame83_fsr.gl.glGenBuffers},
        {"glBindBuffer",              (void**)&ame83_fsr.gl.glBindBuffer},
        {"glBufferData",              (void**)&ame83_fsr.gl.glBufferData},
        {"glVertexAttribPointer",     (void**)&ame83_fsr.gl.glVertexAttribPointer},
        {"glEnableVertexAttribArray", (void**)&ame83_fsr.gl.glEnableVertexAttribArray},
        {"glDrawArrays",              (void**)&ame83_fsr.gl.glDrawArrays},
        {"glViewport",                (void**)&ame83_fsr.gl.glViewport},
        {"glDisable",                 (void**)&ame83_fsr.gl.glDisable},
        {"glGetIntegerv",             (void**)&ame83_fsr.gl.glGetIntegerv},
    };
    int missing = 0;
    for (size_t i = 0; i < sizeof(kSyms)/sizeof(kSyms[0]); ++i) {
        *kSyms[i].slot = dlsym(s_osmDL, kSyms[i].name);
        if (*kSyms[i].slot == NULL) {
            ++missing;
            NSLog(@"[OSMBridge] Task83 FSR: missing GL symbol %s", kSyms[i].name);
        }
    }
    return missing == 0;
}

static unsigned int ame83_compile(ame83_gl_t *g, unsigned int stage, const char *src) {
    unsigned int sh = g->glCreateShader(stage);
    g->glShaderSource(sh, 1, &src, NULL);
    g->glCompileShader(sh);
    int ok = 0;
    g->glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        g->glGetShaderInfoLog(sh, sizeof(log), NULL, log);
        NSLog(@"[OSMBridge] Task83 FSR shader compile FAILED (stage=%u): %s", stage, log);
        g->glDeleteShader(sh);
        return 0;
    }
    return sh;
}

static bool ame83_fsr_init(void) {
    if (ame83_fsr.ready) return true;
    if (ame83_fsr.initFailed) return false;
    if (!ame83_resolve_gl()) { ame83_fsr.initFailed = true; return false; }
    ame83_gl_t *g = &ame83_fsr.gl;

    unsigned int vs = ame83_compile(g, GL_VERTEX_SHADER, FSR_VSSource);
    if (vs == 0) { ame83_fsr.initFailed = true; return false; }
    unsigned int fs = ame83_compile(g, GL_FRAGMENT_SHADER, FSR_FSSource);
    if (fs == 0) { g->glDeleteShader(vs); ame83_fsr.initFailed = true; return false; }

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
        g->glGetProgramInfoLog(prog, sizeof(log), NULL, log);
        NSLog(@"[OSMBridge] Task83 FSR program link FAILED: %s", log);
        ame83_fsr.initFailed = true;
        return false;
    }

    // 全屏四边形（与 MG InitFullscreenQuad 同款布局：pos(2f)+uv(2f)×6 顶点）
    static const float quad[] = {
        -1.0f,  1.0f, 0.0f, 1.0f,
        -1.0f, -1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
        -1.0f,  1.0f, 0.0f, 1.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
    };
    g->glGenVertexArrays(1, &ame83_fsr.vao);
    g->glBindVertexArray(ame83_fsr.vao);
    g->glGenBuffers(1, &ame83_fsr.vbo);
    g->glBindBuffer(GL_ARRAY_BUFFER, ame83_fsr.vbo);
    g->glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    g->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    g->glEnableVertexAttribArray(0);
    g->glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    g->glEnableVertexAttribArray(1);
    g->glBindBuffer(GL_ARRAY_BUFFER, 0);
    g->glBindVertexArray(0);

    g->glGenTextures(1, &ame83_fsr.tex);
    ame83_fsr.program = prog;
    ame83_fsr.uViewportSize = g->glGetUniformLocation(prog, "uViewportSize");
    ame83_fsr.uTargetSize = g->glGetUniformLocation(prog, "uTargetSize");
    ame83_fsr.ready = true;
    NSLog(@"[OSMBridge] Task83 FSR1 EASU ready (zink): program=%u uViewportSize=%d uTargetSize=%d -- same EASU shader as MobileGlues",
          ame83_fsr.program, ame83_fsr.uViewportSize, ame83_fsr.uTargetSize);
    return true;
}

// 把默认帧缓冲 (0,0)-(srcW,srcH) 区域 EASU 升采样铺满 (dstW,dstH)。
// 返回 false = 不可用（调用方走兜底）。
static bool ame83_fsr_upscale(int srcW, int srcH, int dstW, int dstH) {
    if (srcW <= 0 || srcH <= 0 || dstW <= srcW || dstH <= srcH) return false;
    if (!ame83_fsr_init()) return false;
    ame83_gl_t *g = &ame83_fsr.gl;

    // 最小状态保存（MC 每帧重设自己的管线状态；这里只还回关键绑定）
    GLint saveVp[4] = {0}, saveTex = 0, saveProg = 0, saveVao = 0, saveVbo = 0;
    g->glGetIntegerv(GL_VIEWPORT, saveVp);
    g->glGetIntegerv(GL_TEXTURE_BINDING_2D, &saveTex);
    g->glGetIntegerv(GL_CURRENT_PROGRAM, &saveProg);
    g->glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &saveVao);
    g->glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saveVbo);

    g->glDisable(GL_DEPTH_TEST);
    g->glDisable(GL_SCISSOR_TEST);
    g->glDisable(GL_BLEND);
    g->glDisable(GL_CULL_FACE);

    // (1) 帧的区域 → 纹理（GPU 侧拷贝；存储尺寸变化时重建）
    g->glBindTexture(GL_TEXTURE_2D, ame83_fsr.tex);
    if (ame83_fsr.texW != srcW || ame83_fsr.texH != srcH) {
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, 0x812F /*GL_CLAMP_TO_EDGE*/);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, 0x812F);
        g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
        g->glCopyTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 0, 0, srcW, srcH, 0);
        ame83_fsr.texW = srcW;
        ame83_fsr.texH = srcH;
    } else {
        g->glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, srcW, srcH);
    }

    // (2) EASU 全屏绘制 → 默认帧缓冲全幅
    g->glUseProgram(ame83_fsr.program);
    g->glUniform2f(ame83_fsr.uViewportSize, (float)srcW, (float)srcH);
    g->glUniform2f(ame83_fsr.uTargetSize, (float)dstW, (float)dstH);
    g->glBindVertexArray(ame83_fsr.vao);
    g->glViewport(0, 0, dstW, dstH);
    g->glDrawArrays(GL_TRIANGLES, 0, 6);

    // (3) 还原
    g->glBindVertexArray((unsigned int)saveVao);
    g->glBindBuffer(GL_ARRAY_BUFFER, (unsigned int)saveVbo);
    g->glUseProgram((unsigned int)saveProg);
    g->glBindTexture(GL_TEXTURE_2D, (unsigned int)saveTex);
    g->glViewport(saveVp[0], saveVp[1], saveVp[2], saveVp[3]);

    ame83_fsr.frames++;
    if (!ame83_fsr.engaged) {
        ame83_fsr.engaged = true;
        NSLog(@"[OSMBridge] Task83 FSR1 upscale engaged (zink): render %dx%d -> surface %dx%d (EASU, same shader as MobileGlues)",
              srcW, srcH, dstW, dstH);
    } else if (ame83_fsr.frames == 600) {
        NSLog(@"[OSMBridge] Task83 FSR1 upscale steady: 600 frames upsampled (zink)");
    }
    return true;
}

void osm_apply_current_ll() {
    // Task 83：缓冲 = 全尺寸表面（FSR 联动下 MC 窗口 < 表面，MC 把帧画进
    // 区域，osm_swap_buffers 再 EASU 铺满）。ame_surfaceWidth==0（启动极早期/
    // 异常路径）回退旧口径 windowWidth（此时二者本就相等，零回归）。
    int bufW = (ame_surfaceWidth > 0) ? ame_surfaceWidth : windowWidth;
    int bufH = (ame_surfaceHeight > 0) ? ame_surfaceHeight : windowHeight;
    if (bufW <= 0 || bufH <= 0) return;
    if (currentBundle->osm.width == (uint32_t)bufW && currentBundle->osm.height == (uint32_t)bufH) {
        return;
    }

    currentBundle->osm.width = bufW;
    currentBundle->osm.height = bufH;
    currentBundle->osm.buffer = reallocf(currentBundle->osm.buffer, bufW * bufH * 4);

    handle.OSMesaMakeCurrent(currentBundle->osm.context, currentBundle->osm.buffer, GL_UNSIGNED_BYTE, bufW, bufH);
    handle.OSMesaPixelStore(OSMESA_ROW_LENGTH, bufW);
    handle.OSMesaPixelStore(OSMESA_Y_UP, 0);
}

void osm_make_current(osm_render_window_t* bundle) {
    if(!bundle) {
        free(currentBundle->osm.buffer);
        CGColorSpaceRelease(currentBundle->osm.color_space);
        currentBundle->osm.buffer = NULL;
        currentBundle->osm.color_space = NULL;
        currentBundle->osm.width = currentBundle->osm.height = 0;
        currentBundle = NULL;
        //technically this does nothing as its not possible to unbind a context in OSMesa
        handle.OSMesaMakeCurrent(NULL, NULL, 0, 0, 0);
        return;
    }

    currentBundle = (basic_render_window_t *)bundle;
    currentBundle->osm.color_space = CGColorSpaceCreateDeviceRGB();
    osm_apply_current_ll();
}

void osm_swap_buffers() {
    osm_apply_current_ll();
    handle.glFinish(); // this will force osmesa to write the last rendered image into the buffer
    // Task 83：FSR 联动下 MC 窗口 < 表面缓冲 → EASU 升采样铺满（zink 通用
    // FSR）。失败兜底：恢复 MC 窗口=表面（下一帧起全分辨率直渲），画面
    // 不会停留在"缩在角落"的状态。
    if (currentBundle->osm.width > 0 && currentBundle->osm.height > 0 &&
        (windowWidth > 0 && windowHeight > 0) &&
        ((uint32_t)windowWidth < currentBundle->osm.width || (uint32_t)windowHeight < currentBundle->osm.height)) {
        bool ok = ame83_fsr_upscale(windowWidth, windowHeight,
                                    (int)currentBundle->osm.width, (int)currentBundle->osm.height);
        if (!ok && !ame83_fsr.healed) {
            ame83_fsr.healed = true;
            NSLog(@"[OSMBridge] Task83 FSR upscale unavailable -- restoring MC window to surface %ux%u (direct full-res render)",
                  currentBundle->osm.width, currentBundle->osm.height);
            CallbackBridge_nativeSendScreenSize((int)currentBundle->osm.width, (int)currentBundle->osm.height);
        }
    }
    osm_render_window_t bundle = currentBundle->osm;
    dispatch_async(dispatch_get_main_queue(), ^{
    // Task 83：CGImage 尺寸 = 表面缓冲尺寸（旧代码用 windowWidth——FSR
    // 联动下窗口<表面，会把整幅升采样结果再裁一遍）。
    CGDataProviderRef bitmapProvider = CGDataProviderCreateWithData(NULL, bundle.buffer, bundle.width * bundle.height * 4, NULL);
    CGImageRef bitmap = CGImageCreate(bundle.width, bundle.height, 8, 32, 4 * bundle.width, bundle.color_space, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault, bitmapProvider, NULL, FALSE, kCGRenderingIntentDefault);
    SurfaceViewController.surface.layer.contents = (__bridge id)bitmap;
    CGImageRelease(bitmap);
    CGDataProviderRelease(bitmapProvider);
    });
}

void osm_swap_interval(int swapInterval) {
    // Nothing to do here
}

void osm_terminate() {
    // Nothing to do here
}

void set_osm_bridge_tbl() {
    br_init = osm_init;
    br_init_context = (br_init_context_t) osm_init_context;
    br_make_current = (br_make_current_t) osm_make_current;
    br_swap_buffers = osm_swap_buffers;
    br_swap_interval = osm_swap_interval;
    br_terminate = osm_terminate;
}
