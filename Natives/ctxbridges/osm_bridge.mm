#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include "environ.h"
#include "utils.h"

#include "bridge_tbl.h"
#include "osm_bridge.h"
#include "osmesa_internal.h"

// Task 83（FSR 独立化）：复用 MobileGlues 的 FSR1 EASU shader（#version 450，
// MG 上下文原生编译）。Task 83b 修正：zink 经 MoltenVK 的 GLSL 上限只有
// 4.10（装机日志实锤），需版本自适应后才能编过（见 ame83_adapt_shader_version）。
// 该头是纯字符串字面量（clang/gcc 的 C/ObjC 模式均接受 raw string 字面量），
// 每个包含它的 TU 各持一份私有拷贝——启动器主二进制与 libmobileglues.dylib
// 互不可见，无符号冲突。
#include "../external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h"

static osmesa_library handle;
static void *s_osmDL = NULL;   // libOSMesa 句柄（dlsym_OSMesa 保存，FSR GL 惰性解析用）

// Task 83（ObjC++ 化）：C++ 禁止 void* → 函数指针的隐式转换（C 放行，
// CI run 34993498502 报 "converts between void pointer and function pointer"）。
// 用 __typeof__ 显式转型（clang GNU 扩展，C/C++ 双模式可用），零行为变化。
#define AME83_DLSYM_SLOT(slot, sym) (slot) = (__typeof__(slot))dlsym(dl_handle, (sym))

void dlsym_OSMesa() {
    void* dl_handle = dlopen([NSString stringWithFormat:@"@rpath/%s", getenv("AMETHYST_RENDERER")].UTF8String, RTLD_GLOBAL);
    assert(dl_handle);
    s_osmDL = dl_handle;
    AME83_DLSYM_SLOT(handle.OSMesaMakeCurrent, "OSMesaMakeCurrent");
    AME83_DLSYM_SLOT(handle.OSMesaGetCurrentContext, "OSMesaGetCurrentContext");
    AME83_DLSYM_SLOT(handle.OSMesaCreateContext, "OSMesaCreateContext");
    AME83_DLSYM_SLOT(handle.OSMesaDestroyContext, "OSMesaDestroyContext");
    AME83_DLSYM_SLOT(handle.OSMesaPixelStore, "OSMesaPixelStore");
    AME83_DLSYM_SLOT(handle.glGetString, "glGetString");
    AME83_DLSYM_SLOT(handle.glClearColor, "glClearColor");
    AME83_DLSYM_SLOT(handle.glClear, "glClear");
    AME83_DLSYM_SLOT(handle.glFinish, "glFinish");
}

bool osm_init() {
    dlsym_OSMesa();
    return true; // no more specific initialization required
}

osm_render_window_t* osm_init_context(osm_render_window_t* share) {
    // Task 83（ObjC++ 化）：calloc 返回 void*，C++ 禁止隐式转结构体指针（显式转型）
    osm_render_window_t* render_window = (osm_render_window_t*)calloc(1, sizeof(osm_render_window_t));
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

// GL 2.0+ 枚举（GL/gl.h 只有 1.1；OSMesa 桌面 GL 4.6 全量支持）。
// Task 84 勘误：GL_FRAGMENT_SHADER 的规范值是 0x8B92（35730）——Task83
// 误写 0x8B30（35632，非任何 shader 类型枚举；75c5e14 装机日志的
// stage=35632 实锤此错值在跑）。虽然该会话的编译链仍产出了真实的编译
// 错误信息（MobileGlues 封装层对未知枚举的容错），规范错值不可依赖。
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
// Task 85（画面分裂修复）：EASU pass 的封闭性保障——显式绑回默认帧缓冲。
// MC 26.x+Sodium 在 swap 时通常已绑 fb0（Task 75 取证），但任何模组/路径
// 留下 FBO 绑定时，拷贝源与绘制目标都必须强制指向即将上屏的默认帧缓冲，
// 否则升采样写进离屏 FBO，上屏画面维持分裂。
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER            0x8D40
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER       0x8CA6
#endif
#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER       0x8CA9
#endif
#ifndef GL_DRAW_FRAMEBUFFER_BINDING
#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA6
#endif
#ifndef GL_READ_FRAMEBUFFER_BINDING
#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA
#endif
#ifndef GL_STENCIL_TEST
#define GL_STENCIL_TEST           0x0B90
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
    void (*glBindFramebuffer)(unsigned int, unsigned int);
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
        {"glBindFramebuffer",          (void**)&ame83_fsr.gl.glBindFramebuffer},
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

// Task 83b（zink 绿屏根治）：FSR 着色器版本自适应。
//
// 背景（be276a0 装机日志实锤）：zink 经 MoltenVK 只给出 GLSL 4.10 上限
// （MoltenVK = Vulkan 1.1 → zink 桌面 GL 4.1），而 FSRShaderSource.h 声明
// #version 450 → 两个 stage 全部编译失败（错误信息为 GLSL 4.50 is not
// supported，注意此处不引用原文以免 ASCII 引号破坏历史括号校验器）
// → 兜底路径触发。而旧兜底只在 GLFW 通道下才能把窗口恢复成表面尺寸
// （26.3 下恒 NULL）→ MC 永远按小窗渲染，全尺寸 OSMesa 缓冲的未写区域
// = 未初始化堆内存上屏 = 用户看到的"FSR 提升部分绿色"。
//
// 着色器主体只需 GLSL 4.00（uintBitsToFloat 是 3.30 内建，
// packUnorm2x16/packUnorm4x8 是 4.00 内建），唯独 packHalf2x16/
// unpackHalf2x16 是 4.20 核心（Task83b 注释称 4.00 内建有误——75c5e14
// 装机日志实锤：适配到 4.10 后编译倒在 no function with name
// packHalf2x16）。Task 84 已把位运算手写回退（RNE/次正规/Inf/NaN，
// 位级对照 numpy float16 验证）烘焙进 FSRShaderSource.h 的
// __VERSION__ < 420 守卫，4.20+ 上下文零变化。因此当上下文版本落在
// 400 以上、450 以下时，用上下文自己的版本号替换首行 #version 即可。
// >= 450 原样；< 400 无法适配（体依赖 3.30+ 位操作内建），保持原样让它
// 以明确的版本错误日志失败。
//
// 探测：glGetString(GL_SHADING_LANGUAGE_VERSION)（dlsym_OSMesa 已解析，
// 本函数在 osm_swap_buffers 调用链上，OSMesaMakeCurrent 已生效）。
// Mesa 桌面版本串形如 "4.10"（十进制两位小数），解析成 410。
static int ame83_probe_glsl_version(void) {
    static int s_probed = -1;
    if (s_probed != -1) return s_probed;
    s_probed = 0;
    if (handle.glGetString) {
        // 真实签名 GLubyte* glGetString(GLenum)（osm_bridge.h）——C++ 下
        // 不能隐式转 const char*，显式转型后 sscanf。
        const GLubyte *gv = handle.glGetString(0x8B8C /* GL_SHADING_LANGUAGE_VERSION */);
        if (gv && gv[0] >= '0' && gv[0] <= '9') {
            int maj = 0, min = 0;
            if (sscanf((const char *)gv, "%d.%d", &maj, &min) == 2) {
                int ver = maj * 100 + (min < 10 ? min * 10 : min);
                if (ver >= 100 && ver <= 999) s_probed = ver;
            }
        }
    }
    return s_probed;
}

// 返回适配后的着色器源（首行 #version 替换为上下文版本；不适用则原样）。
static std::string ame83_adapt_shader_version(const char *src, const char *stageName) {
    std::string out(src);
    int ver = ame83_probe_glsl_version();
    if (ver >= 450 || ver < 400) return out;   // 原样（≥4.5 无需改；<4.0 改了也编不过，保留明确报错）
    const char *nl = strchr(src, '\n');
    if (!nl || strncmp(src, "#version", 8) != 0) return out;
    static bool s_logged = false;
    if (!s_logged) {
        s_logged = true;
        NSLog(@"[OSMBridge] Task83b FSR shader #version adapted: 450 -> %d (context GLSL cap %d, zink/MoltenVK path) -- first %s stage", ver, ver, stageName);
    }
    out = "#version ";
    out += std::to_string(ver);
    out += '\n';
    out += (nl + 1);
    return out;
}

static bool ame83_fsr_init(void) {
    if (ame83_fsr.ready) return true;
    if (ame83_fsr.initFailed) return false;
    if (!ame83_resolve_gl()) { ame83_fsr.initFailed = true; return false; }
    ame83_gl_t *g = &ame83_fsr.gl;

    // Task 83b：版本自适应后再缩（zink/GLSL 4.10 上限下也能编过）。
    std::string vsSrc = ame83_adapt_shader_version(FSR_VSSource, "vertex");
    std::string fsSrc = ame83_adapt_shader_version(FSR_FSSource, "fragment");
    unsigned int vs = ame83_compile(g, GL_VERTEX_SHADER, vsSrc.c_str());
    if (vs == 0) { ame83_fsr.initFailed = true; return false; }
    unsigned int fs = ame83_compile(g, GL_FRAGMENT_SHADER, fsSrc.c_str());
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

    // 最小状态保存（MC 每帧重设自己的管线状态；这里只还回关键绑定）。
    // Task 85：新增 draw/read FBO 绑定保存（EASU 强制绑 fb0，见下）。
    GLint saveVp[4] = {0}, saveTex = 0, saveProg = 0, saveVao = 0, saveVbo = 0;
    GLint saveDrawFbo = 0, saveReadFbo = 0;
    g->glGetIntegerv(GL_VIEWPORT, saveVp);
    g->glGetIntegerv(GL_TEXTURE_BINDING_2D, &saveTex);
    g->glGetIntegerv(GL_CURRENT_PROGRAM, &saveProg);
    g->glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &saveVao);
    g->glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saveVbo);
    g->glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saveDrawFbo);
    g->glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saveReadFbo);

    g->glDisable(GL_DEPTH_TEST);
    g->glDisable(GL_SCISSOR_TEST);
    g->glDisable(GL_STENCIL_TEST);
    g->glDisable(GL_BLEND);
    g->glDisable(GL_CULL_FACE);

    // Task 85：拷贝源与绘制目标都锁定默认帧缓冲（读窗口区域、写全幅）。
    g->glBindFramebuffer(GL_FRAMEBUFFER, 0);

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

    // (3) 还原（FBO 双通道分别还回，模组的非对称 read/draw 绑定不受扰动）
    g->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (unsigned int)saveDrawFbo);
    g->glBindFramebuffer(GL_READ_FRAMEBUFFER, (unsigned int)saveReadFbo);
    g->glBindVertexArray((unsigned int)saveVao);
    g->glBindBuffer(GL_ARRAY_BUFFER, (unsigned int)saveVbo);
    g->glUseProgram((unsigned int)saveProg);
    g->glBindTexture(GL_TEXTURE_2D, (unsigned int)saveTex);
    g->glViewport(saveVp[0], saveVp[1], saveVp[2], saveVp[3]);

    ame83_fsr.frames++;
    if (!ame83_fsr.engaged) {
        ame83_fsr.engaged = true;
        NSLog(@"[OSMBridge] Task83 FSR1 upscale engaged (zink): render %dx%d -> surface %dx%d (EASU pre-readback ordering, Task 85)",
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
    // Task 85（画面分裂根治）：EASU 必须在 glFinish 之前执行。
    //
    // OSMesa 契约：glFinish 触发 GPU→CPU 回读（zink 下本帧数据在 Vulkan
    // image 里，须回读进下方 CGImage 包装的 client buffer；swrast 则本就
    // 同步写入）。Task 83 的旧序是 glFinish → EASU——升采样画在回读之后，
    // 永远到不了 client buffer。真机视觉 = 画面分裂：左下角窗口区域是
    // 本帧原始低清画面，其余区域是上一帧 EASU 输出的残影（Task 84 修齐
    // 编译链后 EASU 首次真跑，本缺陷随之暴露）。
    //
    // 正序：EASU 先把窗口区域升采样铺满 GPU 侧帧缓冲 → glFinish 一次性
    // 回读完整升采样结果 → CGImage 上屏即全幅。
    if (currentBundle->osm.width > 0 && currentBundle->osm.height > 0 &&
        (windowWidth > 0 && windowHeight > 0) &&
        ((uint32_t)windowWidth < currentBundle->osm.width || (uint32_t)windowHeight < currentBundle->osm.height)) {
        bool ok = ame83_fsr_upscale(windowWidth, windowHeight,
                                    (int)currentBundle->osm.width, (int)currentBundle->osm.height);
        if (!ok && !ame83_fsr.healed) {
            ame83_fsr.healed = true;
            NSLog(@"[OSMBridge] Task83 FSR upscale unavailable -- restoring MC window to surface %ux%u (direct full-res render)",
                  currentBundle->osm.width, currentBundle->osm.height);
            // Task 83b：nativeSendScreenSize 现已带 SDL3 路径（推 0x207 窗口
            // 尺寸事件）——MC 会真正切回全分辨率渲染，不再出现"小窗渲染 +
            // 未初始化缓冲区域上屏"的绿色花屏。
            CallbackBridge_nativeSendScreenSize((int)currentBundle->osm.width, (int)currentBundle->osm.height);
        }
    }
    handle.glFinish(); // this will force osmesa to write the last rendered image into the buffer
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
