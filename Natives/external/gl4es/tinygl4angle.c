#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <pthread.h>

#define GL_GLEXT_PROTOTYPES

#include "GL/gl.h"
#include "GL/glext.h"
//#include "GLES3/gl32.h"
// Task173：iOS SDK 不带 <EGL/egl.h>（libEGL.framework 是自定义产物）。
// eglGetProcAddress 手写 extern 声明（链接期由 -framework libEGL 解析）。
extern void *eglGetProcAddress(const char *procname);
#include "string_utils.h"

// ============================================================================
// Task182: gles_ 解析钉死（ANGLE 渲染器 pipeline/gui 崩溃根修——命名空间
// 分裂）。病历（bc1941b 装机 latestlog.txt，ANGLE 26.3 FO 会话，Task181
// 取证数据回收）：
//   [tinygl4angle] Task181 glShaderSource #1: len0=435 head48='#version 300 es...'
//   [tinygl4angle] Task181 glCompileShader #1: shader=1 COMPILE_STATUS=0 logHead=''
//   → MC 的 ES300 源【确实送达】本 dylib（Task175 重写链全程正常），
//     但编译后 status=0 且 infoLog 为空 = 典型 GL_INVALID_OPERATION
//     （shader id 在编译器所在的库里不存在）。
// 机制：本 dylib 的 gles_ 前缀函数此前用裸 dlsym(RTLD_NEXT) 解析——命中
// 全局搜索序里本 dylib 之后的【下一个提供者】，真机上那是系统
// /usr/lib/libGLESv2；而 MC 的 glCreateSymbol 走 dlsym(本 dylib handle)
// 的导出闭包（自身 + 依赖的 ANGLE libGLESv2 framework，见 Task173 注释）
// = app Frameworks 副本。两份 ANGLE = 两个 id 命名空间：
//   - 上一轮（afa23a6，glCompileSymbol 未导出）：MC compile 直连 Frameworks
//     副本（id=1 在那创建）而源码被本 dylib 上传到系统副本（无效丢弃）
//     → Frameworks 副本编译【空源码】 → "ERROR: 1:1: '' : syntax error"；
//   - 本轮（Task181 导出 glCompileShader 抢到符号）：编译也进了本 dylib
//     → LOOKUP_FUNC 落系统副本 → 那里 id=1 无效 → status=0 + 空 log。
// 两轮形态全部闭环，且 EGL 上下文（gl_bridge 从 ANGLE 框架解析）= Frameworks
// 副本——一切 gles_ 调用都必须落在它上面才对得上 current context。
// 修法（对齐 vgpu pack/load.c 的 Task173 先例 + ame173_gpa 同链）：
//   eglGetProcAddress（当前 client API 的入口，与上下文同源）→
//   显式 dlopen @rpath/libGLESv2.framework/libGLESv2（app 副本句柄）→
//   RTLD_NEXT / RTLD_DEFAULT 兜底。
// ============================================================================
static void *ame182_gles2 = NULL;  // Frameworks 副本句柄（dlopen 幂等，竞态无害）
static int ame182_pinLogs = 0;
static void *ame182_resolve(const char *name) {
    void *p = (void *)eglGetProcAddress(name);
    if (p != NULL) {
        if (ame182_pinLogs < 2) { ame182_pinLogs++; printf("[tinygl4angle] Task182 gles pin: %s via eglGetProcAddress (context-sourced)\n", name); }
        return p;
    }
    if (ame182_gles2 == NULL) {
        ame182_gles2 = dlopen("@rpath/libGLESv2.framework/libGLESv2", RTLD_LAZY | RTLD_LOCAL);
        if (ame182_gles2 == NULL) {
            ame182_gles2 = dlopen("@executable_path/Frameworks/libGLESv2.framework/libGLESv2", RTLD_LAZY | RTLD_LOCAL);
        }
    }
    if (ame182_gles2 != NULL) {
        p = dlsym(ame182_gles2, name);
        if (p != NULL) {
            if (ame182_pinLogs < 2) { ame182_pinLogs++; printf("[tinygl4angle] Task182 gles pin: %s via frameworks handle\n", name); }
            return p;
        }
    }
    p = dlsym(RTLD_NEXT, name);
    if (p != NULL) {
        if (ame182_pinLogs < 2) { ame182_pinLogs++; printf("[tinygl4angle] Task182 gles pin: %s via RTLD_NEXT (legacy)\n", name); }
        return p;
    }
    p = dlsym(RTLD_DEFAULT, name);
    return p;
}

#define LOOKUP_FUNC(func) \
    if (!gles_##func) { \
        gles_##func = ame182_resolve(#func); \
    }

#define AliasDecl(NAME, EXT) \
    asm(".global _"# NAME "\n_" #NAME ": b _" #NAME #EXT);

#define AliasDeclPriv(NAME) \
    asm(".global _gl"# NAME "\n_gl" #NAME ": b _GL_" #NAME);

// Core OpenGL 2.0
AliasDecl(glGetTexImage, ANGLE)
AliasDecl(glMapBuffer, OES)

// GL_KHR_debug
AliasDecl(glDebugMessageCallback, KHR)
AliasDecl(glDebugMessageControl, KHR)
AliasDecl(glDebugMessageInsert, KHR)
AliasDecl(glGetDebugMessageLog, KHR)
AliasDecl(glGetObjectLabel, KHR)
AliasDecl(glObjectLabel, KHR)
AliasDecl(glPopDebugGroup, KHR)
AliasDecl(glPushDebugGroup, KHR)

// GL_EXT_blend_func_extended
AliasDecl(glBindFragDataLocation, EXT)
AliasDecl(glBindFragDataLocationIndexed, EXT)

// Hidden functions
AliasDeclPriv(DrawBuffer)
AliasDeclPriv(PolygonMode)

int proxy_width, proxy_height, proxy_intformat, maxTextureSize;

void(*gles_glCopyTexSubImage2D)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height);
//void glGetBufferParameteriv(GLenum target, GLenum value, GLint * data);
void(*gles_glGetTexLevelParameteriv)(GLenum target, GLint level, GLenum pname, GLint *params);
void(*gles_glShaderSource)(GLuint shader, GLsizei count, const GLchar * const *string, const GLint *length);
// Task183：glBindTexture 转发（buffer 纹理目标重定向用）
void(*gles_glBindTexture)(GLenum target, GLuint texture);
void(*gles_glTexImage2D)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *data);
void(*gles_glTexSubImage2D)(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *data);
void(*gles_glTexParameterfv)(GLenum target, GLenum pname, const GLfloat *params);

void glClearDepth(GLdouble depth) {
    glClearDepthf(depth);
}

// ============================================================================
// Task173: 桌面 GL 补全层（ANGLE 渲染器 pipeline/gui 崩溃根修）。
//
// 病历（FO pack + libtinygl4angle 装机会话 latestlog.old.txt）：GL 后端
// 首次被接受（Task172 镜像链生效），但 MC 26.3 的 minecraft:pipeline/gui
// 预编译抛 IllegalStateException（LWJGL NULL 函数指针——“No context is
// current or a function that is not available...”）→ Failed to find or load
// pipeline → 崩溃。机制：LWJGL GL$1 的 macOS 分支（反编译实证）只做
// OSMesaGetProcAddress（本 dylib 无此导出，恒 0x0）→ dlsym 回退到本
// dylib 的导出闭包（自身 + 依赖的 ANGLE libGLESv2 framework）。ES 框架
// 的导出表是 ES API 集——桌面 GL 独有的名字（glDepthRange 双精度版/
// glQueryCounter/BaseVertex 绘制族/分槽 blend 族等）在闭包里恒 NULL，
// MC 26.3 的 GL 后端（renderpearl）直接调用这些 GL33 核心函数。
//
// 修复：在本 dylib 里实现这些桌面名（dlsym 因此命中我们），首调用时经
// eglGetProcAddress 解析真实指针（ANGLE 的 EGL 对当前绑定的 client API
// 提供桌面 GL 入口；上下文已建立时有效），EXT 后缀变体兜底；纯桌面语义
// 无 ES 对应（glLogicOp）时安全 no-op + 一次性日志。另附 Task173 取证：
// 首次 glGetString 时逐项记录解析结果（装机日志可直接钉死残余缺项）。
// ============================================================================

static pthread_mutex_t ame173_mtx = PTHREAD_MUTEX_INITIALIZER;

/// 单名字解析：eglGetProcAddress → RTLD_NEXT（跳过自身，防自递归）→ NULL
static void *ame173_gpa(const char *name) {
    void *p = (void *)eglGetProcAddress(name);
    if (!p) {
        p = dlsym(RTLD_NEXT, name);
    }
    return p;
}

/// 多名字解析：主名 + 后缀变体（EXT/OES/KHR/NV/ARB）依序尝试
static void *ame173_gpa_multi(const char *name) {
    static const char *ame173_suffixes[] = {"", "EXT", "OES", "KHR", "NV", "ARB"};
    char buf[128];
    for (size_t s = 0; s < sizeof(ame173_suffixes) / sizeof(ame173_suffixes[0]); s++) {
        if (s == 0) {
            void *p = ame173_gpa(name);
            if (p) return p;
        } else {
            snprintf(buf, sizeof(buf), "%s%s", name, ame173_suffixes[s]);
            void *p = ame173_gpa(buf);
            if (p) return p;
        }
    }
    return NULL;
}

#define AME173_RESOLVE(var, name) \
    do { \
        if (!(var)) { \
            pthread_mutex_lock(&ame173_mtx); \
            if (!(var)) { (var) = ame173_gpa_multi(name); } \
            pthread_mutex_unlock(&ame173_mtx); \
        } \
    } while (0)

// ---- 取证：Task173 解析结果一次性日志（首次 glGetString 时，上下文已就位）----
static void ame173_forensics(void) {
    static dispatch_once_t onceTok;
    dispatch_once(&onceTok, ^{
        NSArray *ame173_names = @[
            @"glQueryCounter", @"glDrawElementsBaseVertex", @"glDrawRangeElementsBaseVertex",
            @"glDrawElementsInstancedBaseVertex", @"glMultiDrawElementsBaseVertex",
            @"glMultiDrawArrays", @"glMultiDrawElements", @"glColorMaski", @"glEnablei",
            @"glDisablei", @"glBlendFuncSeparatei", @"glBlendEquationSeparatei",
            @"glFramebufferTexture", @"glTexBuffer", @"glTexBufferRange",
            @"glVertexAttribDivisor", @"glCopyImageSubData", @"glTexImage1D",
            @"glGetQueryObjectiv", @"glGetQueryObjecti64v"
        ];
        int ok = 0, miss = 0;
        NSMutableArray *misses = [NSMutableArray array];
        for (NSString *n in ame173_names) {
            if (ame173_gpa_multi(n.UTF8String)) { ok++; }
            else { miss++; [misses addObject:n]; }
        }
        NSLog(@"[TinyGL] Task173 desktop-GL completion layer: %d/%lu resolved via eglGetProcAddress%s",
              ok, (unsigned long)ame173_names.count,
              miss ? [NSString stringWithFormat:@", MISSING: %@", [misses componentsJoinedByString:@", "]] : @" (all present)");
    });
}

// ---- 桌面独有：类型适配（GLdouble → GLfloat / glGetFloatv 加宽）----

void glDepthRange(GLdouble nearVal, GLdouble farVal) {
    glDepthRangef((GLfloat)nearVal, (GLfloat)farVal);
}

void glGetDoublev(GLenum pname, GLdouble *params) {
    GLfloat fparams[64];
    int n = 1;
    // Task173：元素数表（欠拷贝安全——未列出的 pname 按 1 处理，绝不越界写）。
    switch (pname) {
        case 0x0BA6: case 0x0BA7: case 0x0BA8:          // MODELVIEW/PROJECTION/TEXTURE_MATRIX
        case 0x8659:                                    // GL_TEXTURE_MATRIX_ARRAY (GL_NV)
            n = 16; break;
        case 0x0BA2: n = 4; break;                      // VIEWPORT
        case 0x0C23: n = 4; break;                      // COLOR_WRITEMASK
        case 0x84E5: case 0x84E6: case 0x84E7:          // SECONDARY/FOG/TEXTURE_COLOR (1..4)
        case 0x0B52: case 0x0B53: case 0x0B54:          // 0x0B52..: 4 元
            n = 4; break;
        default: n = 1; break;
    }
    glGetFloatv(pname, fparams);
    for (int i = 0; i < n && i < 64; i++) params[i] = (GLdouble)fparams[i];
}

// ---- 取证 + GLSL 版本串规范化（Iris 兼容）----
// 病历：Iris StandardMacros.SEMVER_PATTERN 要求版本串以数字开头，而
// Apple ANGLE 返回 "OpenGL GLSL 3.30 (ANGLE ...)"——正则不匹配 →
// “Could not parse GL version from ...” → 光影包被跳过。这里把
// GL_SHADING_LANGUAGE_VERSION 的 "OpenGL GLSL " 前缀剥掉（返回指针后移）。
static const GLubyte * (*ame173_real_glGetString)(GLenum) = NULL;

// Task179：ES3 上下文的桌面身份伪装。
// 病历（9aacebb 装机 latestlog.old.txt）：ost ANGLE 的桌面 facade 上下文
// （eglBindAPI(EGL_OPENGL_API) + 3.3 Core）里用户着色器从未编译成功过
// ——Task175 的 ES300 重写已自证送达源合法，错误仍是空源特征的
// "ERROR: 1:1: '' : syntax error"；本地 harness 证明 tinygl4angle 上传链
// 逐字节无损。gl_init_context 已改为创建真 ES3 上下文（Task179），
// 但 MC 26.3 RenderPearl 的 GL 后端要求桌面 GL 3.3 身份（LWJGL caps 解析
// GL_VERSION 字符串）。这里把 ES 上下文的版本串改写回 facade 会话的同形
// 字串（装机验证过 caps 创建成功的那两串）：
//   GL_VERSION:                   "OpenGL ES 3.2.0 (ANGLE ...)" -> "3.3.0 (ANGLE ...)"
//   GL_SHADING_LANGUAGE_VERSION:  "OpenGL ES GLSL ES 3.20 (ANGLE ...)" -> "OpenGL GLSL 3.30 (ANGLE ...)"
// （后者接着走下方 Task173 的 Iris 规范化剥前缀 → "3.30 (ANGLE ...)"。）
// 任何形态不匹配返回原串（失败安全，不破坏非 ANGLE 会话——本函数只在
// tinygl4angle 镜像内存在，其它渲染器不经过这里）。
static const char *ame179_spoofDesktopVersion(const char *s) {
    static char ame179_buf[256];
    if (s == NULL) return NULL;
    if (strncmp(s, "OpenGL ES 3.", 12) == 0) {
        // s = "OpenGL ES <maj>.<min>.<patch> (ANGLE ...)"；取版本号后的首个空格
        const char *v = s + 10;                 // 跳过 "OpenGL ES "（10 字符）
        const char *sp = strchr(v, ' ');
        if (sp != NULL && strlen(sp) + 6 < sizeof(ame179_buf)) {
            snprintf(ame179_buf, sizeof(ame179_buf), "3.3.0%s", sp);
            return ame179_buf;
        }
    }
    return s;
}

static const char *ame179_spoofDesktopGlsl(const char *s) {
    static char ame179_buf[256];
    if (s == NULL) return NULL;
    if (strncmp(s, "OpenGL ES GLSL ES ", 18) == 0) {
        // s = "OpenGL ES GLSL ES <maj>.<min> (ANGLE ...)"
        const char *v = s + 18;
        const char *sp = strchr(v, ' ');
        if (sp != NULL && strlen(sp) + 19 < sizeof(ame179_buf)) {
            snprintf(ame179_buf, sizeof(ame179_buf), "OpenGL GLSL 3.30%s", sp);
            return ame179_buf;
        }
    }
    return s;
}

const GLubyte * glGetString(GLenum name) {
    AME173_RESOLVE(ame173_real_glGetString, "glGetString");
    const GLubyte *result = ame173_real_glGetString ? ame173_real_glGetString(name) : NULL;
    ame173_forensics();
    if (name == GL_VERSION && result) {
        const char *ame179_s = ame179_spoofDesktopVersion((const char *)result);
        if (ame179_s != (const char *)result) {
            NSLog(@"[TinyGL] Task179 desktop identity: GL_VERSION '%s' -> '%s' (ES3 context, facade-form spoof)",
                  (const char *)result, ame179_s);
            return (const GLubyte *)ame179_s;
        }
        return result;
    }
    if (name == GL_SHADING_LANGUAGE_VERSION && result) {
        // Task179：先做 ES->facade 伪装，再走 Task173 的 Iris 规范化（剥
        // "OpenGL GLSL " 前缀）——两步串联后 MC/Iris 拿到的最终串与 facade
        // 会话逐字相同（"3.30 (ANGLE ...)"），caps 与光影包解析双不受影响。
        const char *s = (const char *)result;
        const char *ame179_s = ame179_spoofDesktopGlsl(s);
        if (ame179_s != s) {
            NSLog(@"[TinyGL] Task179 desktop identity: GLSL '%s' -> '%s' (ES3 context, facade-form spoof)",
                  s, ame179_s);
            s = ame179_s;
        }
        size_t l = strlen(s);
        static char ame173_glslbuf[256];
        if (l > 12 && strncmp(s, "OpenGL GLSL ", 12) == 0 && l - 12 < sizeof(ame173_glslbuf)) {
            strlcpy(ame173_glslbuf, s + 12, sizeof(ame173_glslbuf));
            NSLog(@"[TinyGL] Task173 GLSL version string normalized: '%s' -> '%s' (Iris semver parse)", s, ame173_glslbuf);
            return (const GLubyte *)ame173_glslbuf;
        }
        return (const GLubyte *)s;
    }
    return result;
}

// ---- 同签名转发族：首调用解析 + EXT 变体兜底，解析失败安全 no-op ----

typedef void (*ame173_fn_glQueryCounter)(GLuint, GLenum);
static ame173_fn_glQueryCounter ame173_ptr_glQueryCounter;
void glQueryCounter(GLuint id, GLenum target) {
    AME173_RESOLVE(ame173_ptr_glQueryCounter, "glQueryCounter");
    if (ame173_ptr_glQueryCounter) ame173_ptr_glQueryCounter(id, target);
}

// ---- Task187：desktop-only glEnable 无害化（ANGLE 噪音静默）----
// 病历（8cca75a latestlog.txt，ANGLE 会话）：MC 26.3 RenderPearl 的 GlDevice
// 构造【无条件】调用 glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS=0x884F) 与
// glEnable(GL_PROGRAM_POINT_SIZE=0x8642)（26.3 client 反编译 GlDevice.java
// 第 147-148 行实证）。ES 3.0 上下文上 ANGLE 拒绝这两个 cap 并通过
// KHR_debug 回调打 "Enum 0x884F is currently not supported." HIGH 级错误
// （MC 全量记录 = 日志噪音 + 每 cap 一条假错误）。同会话的 MobileGlues
// 前端吞掉了这两个调用（0 条 debug message）= 上游同样视其为桌面门面噪音。
// 处理：两个 cap 本地 no-op + 一次性锚点日志，其余 cap 原样转发（零回归）。
// 功能影响：无——ES 3.0 上无缝立方图与程序点尺寸本来就不存在，MC 的
// fallback 路径已经跑了 8 轮日志（渲染循环 58fps 无任何相关副作用）。
typedef void (*ame187_fn_glEnable)(GLenum);
static ame187_fn_glEnable ame187_ptr_glEnable;
void glEnable(GLenum cap) {
    if (cap == 0x884Fu /* GL_TEXTURE_CUBE_MAP_SEAMLESS (desktop-only) */ ||
        cap == 0x8642u /* GL_PROGRAM_POINT_SIZE (desktop-only) */) {
        static int s_ame187_logged = 0;
        if (s_ame187_logged < 2) {
            ++s_ame187_logged;
            NSLog(@"[tinygl4angle] Task187: accepted desktop-only glEnable(0x%04X) as no-op (RenderPearl unconditional init; ES rejects with HIGH debug error)", (unsigned)cap);
        }
        return;
    }
    AME173_RESOLVE(ame187_ptr_glEnable, "glEnable");
    if (ame187_ptr_glEnable) ame187_ptr_glEnable(cap);
}

typedef void (*ame173_fn_glGetQueryObjectiv)(GLuint, GLenum, GLint *);
static ame173_fn_glGetQueryObjectiv ame173_ptr_glGetQueryObjectiv;
void glGetQueryObjectiv(GLuint id, GLenum pname, GLint *params) {
    AME173_RESOLVE(ame173_ptr_glGetQueryObjectiv, "glGetQueryObjectiv");
    if (ame173_ptr_glGetQueryObjectiv) ame173_ptr_glGetQueryObjectiv(id, pname, params);
}

typedef void (*ame173_fn_glGetQueryObjecti64v)(GLuint, GLenum, GLint64 *);
static ame173_fn_glGetQueryObjecti64v ame173_ptr_glGetQueryObjecti64v;
void glGetQueryObjecti64v(GLuint id, GLenum pname, GLint64 *params) {
    AME173_RESOLVE(ame173_ptr_glGetQueryObjecti64v, "glGetQueryObjecti64v");
    if (ame173_ptr_glGetQueryObjecti64v) ame173_ptr_glGetQueryObjecti64v(id, pname, params);
}

typedef void (*ame173_fn_glGetQueryObjectui64v)(GLuint, GLenum, GLuint64 *);
static ame173_fn_glGetQueryObjectui64v ame173_ptr_glGetQueryObjectui64v;
void glGetQueryObjectui64v(GLuint id, GLenum pname, GLuint64 *params) {
    AME173_RESOLVE(ame173_ptr_glGetQueryObjectui64v, "glGetQueryObjectui64v");
    if (ame173_ptr_glGetQueryObjectui64v) ame173_ptr_glGetQueryObjectui64v(id, pname, params);
}

typedef void (*ame173_fn_glDrawElementsBaseVertex)(GLenum, GLsizei, GLenum, const void *, GLint);
static ame173_fn_glDrawElementsBaseVertex ame173_ptr_glDrawElementsBaseVertex;
void glDrawElementsBaseVertex(GLenum mode, GLsizei count, GLenum type, const void *indices, GLint basevertex) {
    AME173_RESOLVE(ame173_ptr_glDrawElementsBaseVertex, "glDrawElementsBaseVertex");
    if (ame173_ptr_glDrawElementsBaseVertex) {
        ame173_ptr_glDrawElementsBaseVertex(mode, count, type, indices, basevertex);
    } else {
        glDrawElements(mode, count, type, indices);
    }
}

typedef void (*ame173_fn_glDrawRangeElementsBaseVertex)(GLenum, GLuint, GLuint, GLsizei, GLenum, const void *, GLint);
static ame173_fn_glDrawRangeElementsBaseVertex ame173_ptr_glDrawRangeElementsBaseVertex;
void glDrawRangeElementsBaseVertex(GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type, const void *indices, GLint basevertex) {
    AME173_RESOLVE(ame173_ptr_glDrawRangeElementsBaseVertex, "glDrawRangeElementsBaseVertex");
    if (ame173_ptr_glDrawRangeElementsBaseVertex) {
        ame173_ptr_glDrawRangeElementsBaseVertex(mode, start, end, count, type, indices, basevertex);
    } else {
        glDrawElements(mode, count, type, indices);
    }
}

typedef void (*ame173_fn_glDrawElementsInstancedBaseVertex)(GLenum, GLsizei, GLenum, const void *, GLsizei, GLint);
static ame173_fn_glDrawElementsInstancedBaseVertex ame173_ptr_glDrawElementsInstancedBaseVertex;
void glDrawElementsInstancedBaseVertex(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount, GLint basevertex) {
    AME173_RESOLVE(ame173_ptr_glDrawElementsInstancedBaseVertex, "glDrawElementsInstancedBaseVertex");
    if (ame173_ptr_glDrawElementsInstancedBaseVertex) {
        ame173_ptr_glDrawElementsInstancedBaseVertex(mode, count, type, indices, instancecount, basevertex);
    } else {
        glDrawElementsInstanced(mode, count, type, indices, instancecount);
    }
}

typedef void (*ame173_fn_glMultiDrawElementsBaseVertex)(GLenum, const GLsizei *, GLenum, const void *const *, GLsizei, const GLint *);
static ame173_fn_glMultiDrawElementsBaseVertex ame173_ptr_glMultiDrawElementsBaseVertex;
void glMultiDrawElementsBaseVertex(GLenum mode, const GLsizei *count, GLenum type, const void *const *indices, GLsizei drawcount, const GLint *basevertex) {
    AME173_RESOLVE(ame173_ptr_glMultiDrawElementsBaseVertex, "glMultiDrawElementsBaseVertex");
    if (ame173_ptr_glMultiDrawElementsBaseVertex) {
        ame173_ptr_glMultiDrawElementsBaseVertex(mode, count, type, indices, drawcount, basevertex);
    } else if (drawcount > 0) {
        // 降级：逐批 DrawElements（首批的 basevertex 应用于全部——极少路径）
        for (GLsizei i = 0; i < drawcount; i++) {
            glDrawElements(mode, count[i], type, indices[i]);
        }
    }
}

typedef void (*ame173_fn_glMultiDrawArrays)(GLenum, const GLint *, const GLsizei *, GLsizei);
static ame173_fn_glMultiDrawArrays ame173_ptr_glMultiDrawArrays;
void glMultiDrawArrays(GLenum mode, const GLint *first, const GLsizei *count, GLsizei drawcount) {
    AME173_RESOLVE(ame173_ptr_glMultiDrawArrays, "glMultiDrawArrays");
    if (ame173_ptr_glMultiDrawArrays) {
        ame173_ptr_glMultiDrawArrays(mode, first, count, drawcount);
    } else if (drawcount > 0) {
        for (GLsizei i = 0; i < drawcount; i++) {
            glDrawArrays(mode, first[i], count[i]);
        }
    }
}

typedef void (*ame173_fn_glMultiDrawElements)(GLenum, const GLsizei *, GLenum, const void *const *, GLsizei);
static ame173_fn_glMultiDrawElements ame173_ptr_glMultiDrawElements;
void glMultiDrawElements(GLenum mode, const GLsizei *count, GLenum type, const void *const *indices, GLsizei drawcount) {
    AME173_RESOLVE(ame173_ptr_glMultiDrawElements, "glMultiDrawElements");
    if (ame173_ptr_glMultiDrawElements) {
        ame173_ptr_glMultiDrawElements(mode, count, type, indices, drawcount);
    } else if (drawcount > 0) {
        for (GLsizei i = 0; i < drawcount; i++) {
            glDrawElements(mode, count[i], type, indices[i]);
        }
    }
}

typedef void (*ame173_fn_glColorMaski)(GLuint, GLboolean, GLboolean, GLboolean, GLboolean);
static ame173_fn_glColorMaski ame173_ptr_glColorMaski;
void glColorMaski(GLuint buf, GLboolean r, GLboolean g, GLboolean b, GLboolean a) {
    AME173_RESOLVE(ame173_ptr_glColorMaski, "glColorMaski");
    if (ame173_ptr_glColorMaski) {
        ame173_ptr_glColorMaski(buf, r, g, b, a);
    } else if (buf == 0) {
        glColorMask(r, g, b, a);
    }
}

typedef void (*ame173_fn_glEnablei)(GLenum, GLuint);
static ame173_fn_glEnablei ame173_ptr_glEnablei;
void glEnablei(GLenum cap, GLuint index) {
    AME173_RESOLVE(ame173_ptr_glEnablei, "glEnablei");
    if (ame173_ptr_glEnablei) {
        ame173_ptr_glEnablei(cap, index);
    } else if (index == 0) {
        glEnable(cap);
    }
}

typedef void (*ame173_fn_glDisablei)(GLenum, GLuint);
static ame173_fn_glDisablei ame173_ptr_glDisablei;
void glDisablei(GLenum cap, GLuint index) {
    AME173_RESOLVE(ame173_ptr_glDisablei, "glDisablei");
    if (ame173_ptr_glDisablei) {
        ame173_ptr_glDisablei(cap, index);
    } else if (index == 0) {
        glDisable(cap);
    }
}

typedef void (*ame173_fn_glBlendFuncSeparatei)(GLuint, GLenum, GLenum, GLenum, GLenum);
static ame173_fn_glBlendFuncSeparatei ame173_ptr_glBlendFuncSeparatei;
void glBlendFuncSeparatei(GLuint buf, GLenum sfRGB, GLenum dfRGB, GLenum sfA, GLenum dfA) {
    AME173_RESOLVE(ame173_ptr_glBlendFuncSeparatei, "glBlendFuncSeparatei");
    if (ame173_ptr_glBlendFuncSeparatei) {
        ame173_ptr_glBlendFuncSeparatei(buf, sfRGB, dfRGB, sfA, dfA);
    } else if (buf == 0) {
        glBlendFuncSeparate(sfRGB, dfRGB, sfA, dfA);
    }
}

typedef void (*ame173_fn_glBlendEquationSeparatei)(GLuint, GLenum, GLenum);
static ame173_fn_glBlendEquationSeparatei ame173_ptr_glBlendEquationSeparatei;
void glBlendEquationSeparatei(GLuint buf, GLenum modeRGB, GLenum modeAlpha) {
    AME173_RESOLVE(ame173_ptr_glBlendEquationSeparatei, "glBlendEquationSeparatei");
    if (ame173_ptr_glBlendEquationSeparatei) {
        ame173_ptr_glBlendEquationSeparatei(buf, modeRGB, modeAlpha);
    } else if (buf == 0) {
        glBlendEquationSeparate(modeRGB, modeAlpha);
    }
}

typedef void (*ame173_fn_glFramebufferTexture)(GLenum, GLenum, GLuint, GLint);
static ame173_fn_glFramebufferTexture ame173_ptr_glFramebufferTexture;
void glFramebufferTexture(GLenum target, GLenum attachment, GLuint texture, GLint level) {
    AME173_RESOLVE(ame173_ptr_glFramebufferTexture, "glFramebufferTexture");
    if (ame173_ptr_glFramebufferTexture) {
        ame173_ptr_glFramebufferTexture(target, attachment, texture, level);
    } else {
        // ES 降级：2D 纹理挂 2D 挂点（MC 主用 2D RT；cube/3D 场景罕见）
        glFramebufferTexture2D(target, attachment, GL_TEXTURE_2D, texture, level);
    }
}

// ---- Task183：buffer 纹理 -> 2D 纹理 PBO 桥（与 spvc-shim 的 C 族着色器
// 模拟配套）。病历（59d4b48 装机 latestlog.txt，ANGLE 26.3 FO 会话）：
// clouds.vsh 用 `uniform isamplerBuffer CloudFaces` + texelFetch 线性取数；
// spvc-shim 已把着色器侧换成 isampler2D + ivec2((idx) & 255, (idx) >> 8)
// 折叠坐标，本侧必须把 MC 的 glTexBuffer 数据按【固定宽 256】铺成 2D 纹理
// 才能对上。ANGLE ES 3.0 无 GL_TEXTURE_BUFFER 目标（glBindTexture 直接
// GL_INVALID_ENUM、绑定不成立），因此：
//   glBindTexture(GL_TEXTURE_BUFFER, t) -> 重定向为 GL_TEXTURE_2D 绑定；
//   glTexBuffer(GL_TEXTURE_BUFFER, fmt, buf) -> 绑 buf 为 PBO 查尺寸，
//   glTexImage2D(NULL) 零拷贝上传（宽 256，高 = ceil(元素数/256)）。
// texelFetch 不走采样器过滤，无需 filter；mip 0 完整即 texture complete。
#ifndef GL_TEXTURE_BUFFER
#define GL_TEXTURE_BUFFER 0x8C2A
#endif
#ifndef GL_PIXEL_UNPACK_BUFFER
#define GL_PIXEL_UNPACK_BUFFER 0x88EC
#endif
#ifndef GL_PIXEL_UNPACK_BUFFER_BINDING
#define GL_PIXEL_UNPACK_BUFFER_BINDING 0x88EF
#endif
#ifndef GL_BUFFER_SIZE
#define GL_BUFFER_SIZE 0x8764
#endif
#ifndef GL_R8I
#define GL_R8I 0x8231
#endif
#ifndef GL_R8UI
#define GL_R8UI 0x8232
#endif
#ifndef GL_R16I
#define GL_R16I 0x8233
#endif
#ifndef GL_R16UI
#define GL_R16UI 0x8234
#endif
#ifndef GL_R32I
#define GL_R32I 0x8235
#endif
#ifndef GL_R32UI
#define GL_R32UI 0x8236
#endif
#ifndef GL_R8
#define GL_R8 0x8229
#endif
#ifndef GL_R16
#define GL_R16 0x822A
#endif
#ifndef GL_R16F
#define GL_R16F 0x822D
#endif
#ifndef GL_R32F
#define GL_R32F 0x822E
#endif
#ifndef GL_RG
#define GL_RG 0x8227
#endif
#ifndef GL_RED_INTEGER
#define GL_RED_INTEGER 0x8D94
#endif
#ifndef GL_INT
#define GL_INT 0x1404
#endif

typedef void (*ame183_fn_glBindTexture)(GLenum, GLuint);
static ame183_fn_glBindTexture ame183_ptr_glBindTexture;
void glBindTexture(GLenum target, GLuint texture) {
    LOOKUP_FUNC(glBindTexture)
    // Task183：buffer 纹理目标重定向（ANGLE ES3 无此目标，原样转发只会
    // GL_INVALID_ENUM 且绑定不成立 -> 后续 glTexBuffer 桥拿不到纹理）。
    if (target == GL_TEXTURE_BUFFER) target = GL_TEXTURE_2D;
    gles_glBindTexture(target, texture);
}

/// Task183：内部状态查询/绑定助手（PBO 桥用，同样走钉死链）。
typedef void (*ame183_fn_glBindBuffer)(GLenum, GLuint);
static ame183_fn_glBindBuffer ame183_ptr_glBindBuffer;
typedef void (*ame183_fn_glGetIntegerv)(GLenum, GLint *);
static ame183_fn_glGetIntegerv ame183_ptr_glGetIntegerv;
typedef void (*ame183_fn_glGetBufferParameteriv)(GLenum, GLenum, GLint *);
static ame183_fn_glGetBufferParameteriv ame183_ptr_glGetBufferParameteriv;

typedef struct { GLenum ifmt; GLenum fmt; GLenum type; int px; } ame183_tbfmt_t;
static const ame183_tbfmt_t ame183_tbfmt_table[] = {
    { 0x8229 /*R8*/,    0x1903 /*RED*/,   0x1401 /*UBYTE*/,  1 },
    { 0x8231 /*R8I*/,   0x8D94 /*RED_INT*/, 0x1400 /*BYTE*/, 1 },
    { 0x8232 /*R8UI*/,  0x8D94,           0x1401,            1 },
    { 0x822A /*R16*/,   0x1903,           0x1403 /*USHORT*/, 2 },
    { 0x8233 /*R16I*/,  0x8D94,           0x1402 /*SHORT*/,  2 },
    { 0x8234 /*R16UI*/, 0x8D94,           0x1403,            2 },
    { 0x822D /*R16F*/,  0x1903,           0x140B /*HALF*/,   2 },
    { 0x822E /*R32F*/,  0x1903,           0x1406 /*FLOAT*/,  4 },
    { 0x8235 /*R32I*/,  0x8D94,           0x1404 /*INT*/,    4 },
    { 0x8236 /*R32UI*/, 0x8D94,           0x1405 /*UINT*/,   4 },
    { 0x8058 /*RGBA8*/, 0x1908 /*RGBA*/,  0x1401,            4 },
};

/// Task183：buffer 数据按固定宽 256 铺 2D 纹理（PBO 零拷贝）。
static void ame183_texbuffer_to_2d(GLenum internalformat, GLuint buffer) {
    if (buffer == 0) return;
    AME173_RESOLVE(ame183_ptr_glBindBuffer, "glBindBuffer");
    AME173_RESOLVE(ame183_ptr_glGetIntegerv, "glGetIntegerv");
    AME173_RESOLVE(ame183_ptr_glGetBufferParameteriv, "glGetBufferParameteriv");
    if (!ame183_ptr_glBindBuffer || !ame183_ptr_glGetIntegerv ||
        !ame183_ptr_glGetBufferParameteriv || !gles_glTexImage2D) {
        return;
    }
    GLint prevPB = 0;
    ame183_ptr_glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &prevPB);
    GLint size = 0;
    ame183_ptr_glBindBuffer(GL_PIXEL_UNPACK_BUFFER, buffer);
    ame183_ptr_glGetBufferParameteriv(GL_PIXEL_UNPACK_BUFFER, GL_BUFFER_SIZE, &size);
    ame183_ptr_glBindBuffer(GL_PIXEL_UNPACK_BUFFER, (GLuint)prevPB);
    if (size <= 0) return;
    const ame183_tbfmt_t *f = NULL;
    for (size_t i = 0; i < sizeof(ame183_tbfmt_table) / sizeof(ame183_tbfmt_table[0]); ++i) {
        if (ame183_tbfmt_table[i].ifmt == internalformat) { f = &ame183_tbfmt_table[i]; break; }
    }
    if (f == NULL) {
        static int s_ame183_tbUnknown = 0;
        if (s_ame183_tbUnknown < 2) {
            ++s_ame183_tbUnknown;
            printf("[tinygl4angle] Task183 texbuffer bridge: unknown internalformat 0x%X "
                   "(size=%d) -- skipping upload\n", (unsigned)internalformat, size);
        }
        return;
    }
    int elements = size / f->px;
    if (elements <= 0) return;
    int width = 256;
    int height = (elements + width - 1) / width;
    // PBO 源 = 刚才解绑了 —— 重新绑上再传（TexImage 从 PBO 读）
    ame183_ptr_glBindBuffer(GL_PIXEL_UNPACK_BUFFER, buffer);
    gles_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)internalformat, width, height, 0,
                      f->fmt, f->type, NULL);
    ame183_ptr_glBindBuffer(GL_PIXEL_UNPACK_BUFFER, (GLuint)prevPB);
    static int s_ame183_tbLogged = 0;
    if (s_ame183_tbLogged < 4) {
        ++s_ame183_tbLogged;
        printf("[tinygl4angle] Task183 texbuffer bridge: %d bytes -> 2D %dx%d "
               "(fmt 0x%X, px %d)\n", size, width, height, (unsigned)internalformat, f->px);
    }
}

typedef void (*ame173_fn_glTexBuffer)(GLenum, GLenum, GLuint);
static ame173_fn_glTexBuffer ame173_ptr_glTexBuffer;
void glTexBuffer(GLenum target, GLenum internalformat, GLuint buffer) {
    // Task183：ES3.0 无 texture buffer —— 先走 2D 桥；桥不认识再试原生
    //（未来 ES3.1+ 上下文可用原生路径）。
    if (target == GL_TEXTURE_BUFFER) {
        ame183_texbuffer_to_2d(internalformat, buffer);
        return;
    }
    AME173_RESOLVE(ame173_ptr_glTexBuffer, "glTexBuffer");
    if (ame173_ptr_glTexBuffer) {
        ame173_ptr_glTexBuffer(target, internalformat, buffer);
    }
}

typedef void (*ame173_fn_glTexBufferRange)(GLenum, GLenum, GLuint, GLintptr, GLsizeiptr);
static ame173_fn_glTexBufferRange ame173_ptr_glTexBufferRange;
void glTexBufferRange(GLenum target, GLenum internalformat, GLuint buffer, GLintptr offset, GLsizeiptr size) {
    AME173_RESOLVE(ame173_ptr_glTexBufferRange, "glTexBufferRange");
    if (ame173_ptr_glTexBufferRange) {
        ame173_ptr_glTexBufferRange(target, internalformat, buffer, offset, size);
    }
}

typedef void (*ame173_fn_glVertexAttribDivisor)(GLuint, GLuint);
static ame173_fn_glVertexAttribDivisor ame173_ptr_glVertexAttribDivisor;
void glVertexAttribDivisor(GLuint index, GLuint divisor) {
    AME173_RESOLVE(ame173_ptr_glVertexAttribDivisor, "glVertexAttribDivisor");
    if (ame173_ptr_glVertexAttribDivisor) {
        ame173_ptr_glVertexAttribDivisor(index, divisor);
    }
}

typedef void (*ame173_fn_glCopyImageSubData)(GLuint, GLenum, GLint, GLint, GLint, GLint, GLuint, GLenum, GLint, GLint, GLint, GLint, GLsizei, GLsizei, GLsizei);
static ame173_fn_glCopyImageSubData ame173_ptr_glCopyImageSubData;
void glCopyImageSubData(GLuint srcName, GLenum srcTarget, GLint srcLevel, GLint srcX, GLint srcY, GLint srcZ,
                        GLuint dstName, GLenum dstTarget, GLint dstLevel, GLint dstX, GLint dstY, GLint dstZ,
                        GLsizei srcWidth, GLsizei srcHeight, GLsizei srcDepth) {
    AME173_RESOLVE(ame173_ptr_glCopyImageSubData, "glCopyImageSubData");
    if (ame173_ptr_glCopyImageSubData) {
        ame173_ptr_glCopyImageSubData(srcName, srcTarget, srcLevel, srcX, srcY, srcZ,
                                      dstName, dstTarget, dstLevel, dstX, dstY, dstZ,
                                      srcWidth, srcHeight, srcDepth);
    }
}

typedef void (*ame173_fn_glTexImage1D)(GLenum, GLint, GLint, GLsizei, GLint, GLenum, GLenum, const void *);
static ame173_fn_glTexImage1D ame173_ptr_glTexImage1D;
void glTexImage1D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLint border, GLenum format, GLenum type, const void *pixels) {
    AME173_RESOLVE(ame173_ptr_glTexImage1D, "glTexImage1D");
    if (ame173_ptr_glTexImage1D) {
        ame173_ptr_glTexImage1D(target, level, internalformat, width, border, format, type, pixels);
    }
    // 解析失败：静默丢弃（ES 无 1D 纹理；调用方拿到 GL_INVALID_ENUM 走降级）
}

// ---- 纯桌面语义无 ES 对应：安全 no-op + 一次性日志 ----
static void ame173_log_once(const char *fn) {
    static dispatch_once_t ame173_once_guard; // 简化：首个触发者带名记录
    dispatch_once(&ame173_once_guard, ^{
        NSLog(@"[TinyGL] Task173 desktop-only function with no ES equivalent no-op'd (first: %s)", fn);
    });
}

void glLogicOp(GLenum opcode) {
    // ES 无逻辑运算（GL_LOGIC_OP 桌面 1.0 特性）。MC 的 hurt-flash 等
    // 特效依赖 GL_LOGIC_OP 的路径在现代 MC 已退役，安全 no-op。
    ame173_log_once("glLogicOp");
}

void glIndexMask(GLuint mask) {
    ame173_log_once("glIndexMask");
}


void glShaderSource(GLuint shader, GLsizei count, const GLchar * const *string, const GLint *length) {
    LOOKUP_FUNC(glShaderSource)

    // DBG(printf("glShaderSource(%d, %d, %p, %p)\n", shader, count, string, length);)
    char *source = NULL;
    char *converted;

    // Task181（ANGLE pipeline/gui "ERROR: 1:1: '' : syntax error" 取证）：
    // 反编译 26.3 client.jar 定案 MC 的上传形态 = GlStateManager.glShaderSource
    // （UTF-8 编码 + NUL 终止单段 + length=NULL → nglShaderSource）；spvc 出口
    // 已自证产出合法 "#version 300 es"（head48 日志），本地 harness（task179）
    // 也验证过 ES 直通可编译——中间必有一环没走通。本日志限 8 次，双重目的：
    // (a) 若日志出现 → tinygl4angle 的 glShaderSource 被 MC 命中，且能看到
    //     ANGLE 实收的源码头部（是否为 ES300/是否为空当场钉死）；
    // (b) 若崩溃复现而日志【不】出现 → MC 的 glShaderSource 解析到了本
    //     dylib 之外（Apple 系统 libGLESv2 或直连 ANGLE）——那才是断点。
    {
        static int s_ame181_srcLog = 0;
        if (s_ame181_srcLog < 8) {
            ++s_ame181_srcLog;
            size_t ame181_len0 = 0;
            if (string != NULL && count > 0 && string[0] != NULL) {
                ame181_len0 = (length != NULL && length[0] >= 0)
                    ? (size_t)length[0]
                    : strlen(string[0]);
            }
            const char *ame181_head = (string != NULL && count > 0 && string[0] != NULL) ? string[0] : "";
            printf("[tinygl4angle] Task181 glShaderSource #%d: shader=%u count=%d len0=%zu length=%s head48='%.48s'\n",
                   s_ame181_srcLog, shader, count, ame181_len0,
                   (length == NULL) ? "NULL" : "array", ame181_head);
        }
    }

    // get the size of the shader sources and than concatenate in a single string
    int l = 0;
    for (int i=0; i<count; i++) l+=(length && length[i] >= 0)?length[i]:strlen(string[i]);
    if (source) free(source);
    source = calloc(1, l+1);
    // Task183（A 族回归监测锚点）：桌面 GLSL（>=130 且非 es）到达本函数 =
    // spvc-shim 的 ES 重写漏网（59d4b48 病历：注册表 96 槽被 392 活 context
    // 打穿，584/782 静默拿到桌面源 -> ANGLE "ERROR: 0:1" -> 黑屏）。限频
    // 打点让下轮装机日志直接看到漏网量；spvc-shim 侧已配 Task183 跳过日志。
    {
        const char *ame183_h = (string != NULL && count > 0 && string[0] != NULL) ? string[0] : NULL;
        if (ame183_h != NULL && strncmp(ame183_h, "#version ", 9) == 0) {
            int ame183_isEs = (strncmp(&ame183_h[13], "es", 2) == 0);
            long ame183_ver = strtol(&ame183_h[9], NULL, 10);
            if (!ame183_isEs && ame183_ver >= 130) {
                static int s_ame183_desktopLeak = 0;
                ++s_ame183_desktopLeak;
                if (s_ame183_desktopLeak <= 4 || (s_ame183_desktopLeak % 64) == 0) {
                    printf("[tinygl4angle] Task183 DESKTOP source reached GLES upload "
                           "(spvc rewrite missed) #%d head48='%.48s'\n",
                           s_ame183_desktopLeak, ame183_h);
                }
            }
        }
    }
    if(length) {
        for (int i=0; i<count; i++) {
            if(length[i] >= 0)
                strncat(source, string[i], length[i]);
            else
                strcat(source, string[i]);
        }
    } else {
        for (int i=0; i<count; i++)
            strcat(source, string[i]);
    }
    
    char *source2 = strchr(source, '#');
    if (!source2) {
        source2 = source;
    }
    // are there #version?
    if (!strncmp(source2, "#version ", 9)) {
        if (!strncmp(&source2[13], "es", 2)) {
            // This is for gl4es. TODO: maybe remove 'es' aswell?
            // Task173 bug fix（潜伏雷）：旧代码在这里直接 return——shader 源码
            // 从未上传（gles_glShaderSource 没被调用），shader 保持未初始化
            // 源 → 编译出空程序 → 链接失败。ES 版本化着色器应原样上传。
            gles_glShaderSource(shader, 1, (const GLchar * const *)((source2) ? (&source2) : (&source)), NULL);
            free(source);
            return;
        }
        converted = strdup(source2);
        if (converted[9] == '1') {
            if (converted[10] - '0' < 2) {
                // 100, 110 -> 120
                //converted[10] = '2';
            } else if (converted[10] - '0' < 6) {
                // 130, 140, 150 -> 330
                converted[9] = converted[10] = '3';
            }
        }
        // remove "core", is it safe?
        if (!strncmp(&converted[13], "core", 4)) {
            strncpy(&converted[13], "\n//c", 4);
        }
    } else {
        converted = calloc(1, strlen(source) + 13);
        strcpy(converted, "#version 120\n");
        strcpy(&converted[13], strdup(source));
    }

    int convertedLen = strlen(converted);

#ifdef __APPLE__
    // patch OptiFine 1.17.x
    if (FindString(converted, "\nuniform mat4 textureMatrix = mat4(1.0);")) {
        InplaceReplace(converted, &convertedLen, "\nuniform mat4 textureMatrix = mat4(1.0);", "\n#define textureMatrix mat4(1.0)");
    }
#endif

    // Workaround unassigned outputs: use gl_FragData[] instead of separate color outputs
    char tmpOutFindLine[20];
    char tmpOutReplaceLine[33];
    strncpy(tmpOutFindLine, "out vec4 outColor0;", 20);
    strncpy(tmpOutReplaceLine, "#define outColor0 gl_FragData[0]", 33);
    for (int i = 0; i < 8; i++) {
        tmpOutFindLine[17] = '0'+i;
        if (FindString(converted, tmpOutFindLine)) {
            tmpOutReplaceLine[16] = '0'+i;
            tmpOutReplaceLine[30] = '0'+i;
            converted = InplaceReplace(converted, &convertedLen, tmpOutFindLine, tmpOutReplaceLine);
        }
    }

    // some needed exts
    const char* extensions =
        "#extension GL_EXT_blend_func_extended : enable\n"
        "#extension GL_EXT_draw_buffers : enable\n"
        // For OptiFine (see patch above)
        "#extension GL_EXT_shader_non_constant_global_initializers : enable\n";
    converted = InplaceInsert(GetLine(converted, 1), extensions, converted, &convertedLen);

    //printf("[tinygl4angle] glShaderSource: %s\n", converted);

    gles_glShaderSource(shader, 1, (const GLchar * const*)((converted)?(&converted):(&source)), NULL);

    free(source);
    free(converted);
}

// Task181（ANGLE 编译链取证，与上面 glShaderSource 取证同轮）：
// 本 dylib 之前不导出 glCompileShader/glCreateShader（直接走 ANGLE 原生）。
// 新增【纯转发】导出：行为不变（转发到 LOOKUP_FUNC 解析出的同一 ANGLE
// 函数），但让"MC 的编译调用是否/以何参数命中本 dylib"变得可观测——
// 每次编译后查一次 COMPILE_STATUS（35713），失败时打 infoLog 头 64 字节。
// 若装机日志里这些行【不】出现而崩溃复现 → MC 的编译链解析在本 dylib 之外。
void(*gles_glCompileShader)(GLuint shader);
void(*gles_glGetShaderiv)(GLuint shader, GLenum pname, GLint *params);
void(*gles_glGetShaderInfoLog)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
void glCompileShader(GLuint shader) {
    LOOKUP_FUNC(glCompileShader)
    if (gles_glCompileShader) {
        gles_glCompileShader(shader);
    }
    {
        static int s_ame181_compLog = 0;
        if (s_ame181_compLog < 32) {
            ++s_ame181_compLog;
            // Task182：查询函数改走 ame182_resolve 钉死链（旧版裸
            // RTLD_NEXT 落到系统副本 → status/log 读错对象，与编译器
            // 不同库，status=0+空 log 的另一半成因）。
            if (gles_glGetShaderiv == NULL) { gles_glGetShaderiv = ame182_resolve("glGetShaderiv"); }
            GLint ame181_status = 0;
            if (gles_glGetShaderiv != NULL) {
                gles_glGetShaderiv(shader, 35713 /* GL_COMPILE_STATUS */, &ame181_status);
                if (ame181_status == 0) {
                    if (gles_glGetShaderInfoLog == NULL) { gles_glGetShaderInfoLog = ame182_resolve("glGetShaderInfoLog"); }
                    char ame181_log[160];
                    GLsizei ame181_logLen = 0;
                    ame181_log[0] = '\0';
                    if (gles_glGetShaderInfoLog != NULL) {
                        gles_glGetShaderInfoLog(shader, sizeof(ame181_log) - 1, &ame181_logLen, ame181_log);
                        ame181_log[ame181_logLen > 0 && ame181_logLen < (GLsizei)sizeof(ame181_log) - 1 ? ame181_logLen : (GLsizei)sizeof(ame181_log) - 1] = '\0';
                    }
                    printf("[tinygl4angle] Task181 glCompileShader #%d: shader=%u COMPILE_STATUS=0 logHead='%s'\n",
                           s_ame181_compLog, shader, ame181_log);
                } else {
                    printf("[tinygl4angle] Task181 glCompileShader #%d: shader=%u COMPILE_STATUS=1 (ok)\n",
                           s_ame181_compLog, shader);
                }
            }
        }
    }
}

// Task182：补导出 shader 对象生命周期入口（纯转发，与 glCompileShader 同款
// LOOKUP_FUNC 钉死链）。理由：MC 的符号解析走 dlsym(本 dylib handle) 的
// 导出闭包（自身 + 依赖树）——glCreateShader 不在本 dylib 导出面时，它沿
// 依赖树落到的库与本 dylib gles_ 解析链命中的库【不保证同一份】（真机
// 实测即分裂：create 在 Frameworks 副本、upload/compile 在系统副本，
// 两轮装机的 "ERROR: 1:1" 空源码与 "status=0 空 log" 两种形态全由此出）。
// 现在把 create/delete 也拉进本 dylib 的同一解析链：MC 全部 shader 族
// 调用（create→source→compile→query→delete）汇聚到同一份 ANGLE，
// 命名空间彻底闭合。转发本身零语义变化（同一函数，多一层中转）。
GLuint(*gles_glCreateShader)(GLenum type);
void(*gles_glDeleteShader)(GLuint shader);
GLuint glCreateShader(GLenum type) {
    LOOKUP_FUNC(glCreateShader)
    if (gles_glCreateShader) {
        GLuint ame182_id = gles_glCreateShader(type);
        static int s_ame182_createLogs = 0;
        if (s_ame182_createLogs < 4) {
            s_ame182_createLogs++;
            printf("[tinygl4angle] Task182 glCreateShader(type=%u) -> %u (namespace joined: create/source/compile/query now share one ANGLE)\n",
                   (unsigned)type, (unsigned)ame182_id);
        }
        return ame182_id;
    }
    return 0;
}
void glDeleteShader(GLuint shader) {
    LOOKUP_FUNC(glDeleteShader)
    if (gles_glDeleteShader) {
        gles_glDeleteShader(shader);
    }
}

// ============================================================================
// Task186: glUniformMatrix*fv transpose 转置桥（ANGLE 黑屏·内容层头号嫌疑
// 根修 + 取证锚点）。病历（11e4b63 装机 c689d41 latestlog.txt，ANGLE 26.3
// FO 会话）：呈现层全绿（fps=60 swapOK=372、遮罩按 first-swap 移除、音频/
// 输入/主菜单音效俱全、Task183 后无 "Couldn't compile ... for pipeline"
// 刷屏）但屏幕全黑 = MC 画了黑内容。desktop GL 3.3 的 glUniformMatrix*fv
// 允许 transpose=GL_TRUE（行主序输入），ESSL（300/320）强制 transpose=
// GL_FALSE：违反 = GL_INVALID_VALUE 且【调用被整体丢弃】——一旦 MC 某条
// 路径传 TRUE，矩阵 uniform 全灭 → 所有顶点退化为零向量 → 几何全剔除 →
// 只剩 clearColor = 游戏跑着但全黑，与本轮症状逐点吻合。本 dylib 此前
// 不导出矩阵族：MC 的调用沿依赖树直落 ANGLE 原生（ES 语义，无人在场
// 转置）。修法：九函数全族包装——transpose=FALSE 纯转发（零回归）；
// TRUE 时本地转置（行主序→列主序）后以 FALSE 转发（单矩阵 ≤16 float
// 走栈缓冲，热路径零 malloc）；首次 TRUE 打锚点日志（取证修复合一：
// 若装机日志无此行且黑屏仍在，本嫌疑即排除，排查转向 depth/blend 态）。
// GL 语义：glUniformMatrix{cols}x{rows}fv，FALSE=列主序 out[col*rows+row]，
// TRUE=行主序 in[row*cols+col]；转置即 out[col*rows+row]=in[row*cols+col]。
// ============================================================================
static int ame186_transposeLogged = 0;
#define AME186_MATRIX_FN(FN, COLS, ROWS) \
void (*gles_##FN)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value); \
void FN(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { \
    LOOKUP_FUNC(FN) \
    if (!gles_##FN) return; \
    if (transpose == GL_FALSE || value == NULL || count <= 0) { \
        gles_##FN(location, count, transpose, value); \
        return; \
    } \
    const GLsizei ame186_n = (COLS) * (ROWS); \
    GLfloat ame186_stack[16]; \
    GLfloat *ame186_buf = ame186_stack; \
    int ame186_heap = 0; \
    if ((size_t)count * (size_t)ame186_n > 16) { \
        ame186_buf = (GLfloat *)malloc(((size_t)count * (size_t)ame186_n) * sizeof(GLfloat)); \
        if (ame186_buf == NULL) { \
            gles_##FN(location, count, transpose, value); \
            return; \
        } \
        ame186_heap = 1; \
    } \
    for (GLsizei ame186_m = 0; ame186_m < count; ++ame186_m) { \
        const GLfloat *ame186_src = value + (size_t)ame186_m * (size_t)ame186_n; \
        GLfloat *ame186_dst = ame186_buf + (size_t)ame186_m * (size_t)ame186_n; \
        for (int ame186_c = 0; ame186_c < (COLS); ++ame186_c) { \
            for (int ame186_r = 0; ame186_r < (ROWS); ++ame186_r) { \
                ame186_dst[ame186_c * (ROWS) + ame186_r] = ame186_src[ame186_r * (COLS) + ame186_c]; \
            } \
        } \
    } \
    if (ame186_transposeLogged < 4) { \
        ++ame186_transposeLogged; \
        printf("[tinygl4angle] Task186 %s transpose=TRUE -> locally transposed %dx%d x%ld matrix/matrices (ES requires column-major; dropped call was the black-content suspect)\n", \
               #FN, (COLS), (ROWS), (long)count); \
    } \
    gles_##FN(location, count, GL_FALSE, ame186_buf); \
    if (ame186_heap) free(ame186_buf); \
}
AME186_MATRIX_FN(glUniformMatrix2fv, 2, 2)
AME186_MATRIX_FN(glUniformMatrix3fv, 3, 3)
AME186_MATRIX_FN(glUniformMatrix4fv, 4, 4)
AME186_MATRIX_FN(glUniformMatrix2x3fv, 2, 3)
AME186_MATRIX_FN(glUniformMatrix3x2fv, 3, 2)
AME186_MATRIX_FN(glUniformMatrix2x4fv, 2, 4)
AME186_MATRIX_FN(glUniformMatrix4x2fv, 4, 2)
AME186_MATRIX_FN(glUniformMatrix3x4fv, 3, 4)
AME186_MATRIX_FN(glUniformMatrix4x3fv, 4, 3)

int isProxyTexture(GLenum target) {
    switch (target) {
        case GL_PROXY_TEXTURE_1D:
        case GL_PROXY_TEXTURE_2D:
        case GL_PROXY_TEXTURE_3D:
        case GL_PROXY_TEXTURE_RECTANGLE_ARB:
            return 1;
    }
    return 0;
}

static int inline nlevel(int size, int level) {
    if(size) {
        size>>=level;
        if(!size) size=1;
    }
    return size;
}

void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params) {
    LOOKUP_FUNC(glGetTexLevelParameteriv)
    // NSLog("glGetTexLevelParameteriv(%x, %d, %x, %p)", target, level, pname, params);
    if (isProxyTexture(target)) {
        switch (pname) {
            case GL_TEXTURE_WIDTH:
                (*params) = nlevel(proxy_width,level);
                break;
            case GL_TEXTURE_HEIGHT: 
                (*params) = nlevel(proxy_height,level);
                break;
            case GL_TEXTURE_INTERNAL_FORMAT:
                (*params) = proxy_intformat;
                break;
        }
    } else {
        gles_glGetTexLevelParameteriv(target, level, pname, params);
    }
}

void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *data) {
    LOOKUP_FUNC(glTexImage2D)

    if (type == GL_UNSIGNED_INT_8_8_8_8_REV) {
        type = GL_UNSIGNED_BYTE;
    }

    if (isProxyTexture(target)) {
        if (!maxTextureSize) {
            glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
            // maxTextureSize = 16384;
            // NSLog(@"Maximum texture size: %d", maxTextureSize);
        }
        proxy_width = ((width<<level)>maxTextureSize)?0:width;
        proxy_height = ((height<<level)>maxTextureSize)?0:height;
        proxy_intformat = internalformat;
        // swizzle_internalformat((GLenum *) &internalformat, format, type);
    } else {
        gles_glTexImage2D(target, level, internalformat, width, height, border, format, type, data);
    }
}


void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *data) {
    LOOKUP_FUNC(glTexSubImage2D)
    if (type == GL_UNSIGNED_INT_8_8_8_8_REV) {
        type = GL_UNSIGNED_BYTE;
    }
    gles_glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, type, data);
}


void glTexParameterfv(GLenum target, GLenum pname, const GLfloat *params) {
    LOOKUP_FUNC(glTexParameterfv)
    if (pname != GL_TEXTURE_LOD_BIAS) {
        gles_glTexParameterfv(target, pname, params);
    }
}
void glTexParameterf(GLenum target, GLenum pname, GLfloat param) {
    glTexParameterfv(target, pname, &param);
}

// Handle reading depth buffer
void glReadBuffer(GLenum mode) {
    // Override with stub
}

void glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
    if (target != GL_TEXTURE_2D) {
        LOOKUP_FUNC(glCopyTexSubImage2D)
        gles_glCopyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height);
    }

    // Override with stub
#if 0
    float *pixels = malloc(width*height*sizeof(float));
    for (int i = 0; i < width*height; i++) {
        pixels[i] = 0.5f;
    }
    glTexSubImage2D(target, level, xoffset, yoffset, width, height, GL_DEPTH_COMPONENT, GL_FLOAT, pixels);
    free(pixels);
#endif

#if 0
    static GLuint depthFB;
    if (!depthFB) {
        glGenFramebuffers(1, &depthFB);
    }
    int fbID, texID;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbID);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texID);
    //glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, depthFB);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, target, texID, level);
    assert(glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    glBlitFramebuffer(xoffset, yoffset, width, height, x, y, width, height, GL_DEPTH_BUFFER_BIT, GL_NEAREST);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, target, 0, level);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbID);
#endif
}

// VertexArray stuff
#define THUNK(suffix, type, M2) \
void  glVertexAttrib1##suffix (GLuint index, type v0) { GLfloat f[4] = {0,0,0,1}; f[0] =v0; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib2##suffix (GLuint index, type v0, type v1) { GLfloat f[4] = {0,0,0,1}; f[0] =v0; f[1]=v1; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib3##suffix (GLuint index, type v0, type v1, type v2) { GLfloat f[4] = {0,0,0,1}; f[0] =v0; f[1]=v1; f[2]=v2; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib4##suffix (GLuint index, type v0, type v1, type v2, type v3) { GLfloat f[4] = {0,0,0,1}; f[0] =v0; f[1]=v1; f[2]=v2; f[3]=v3; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib1##suffix##v (GLuint index, const type *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib2##suffix##v (GLuint index, const type *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]; f[1]=v[1]; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib3##suffix##v (GLuint index, const type *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]; f[1]=v[1]; f[2]=v[2]; glVertexAttrib4fv(index, f); };
THUNK(s, GLshort, );
THUNK(d, GLdouble, _D);
#undef THUNK
void  glVertexAttrib4dv (GLuint index, const GLdouble *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]; f[1]=v[1]; f[2]=v[2]; f[3]=v[3]; glVertexAttrib4fv(index, f); };

#define THUNK(suffix, type, norm) \
void  glVertexAttrib4##suffix##v (GLuint index, const type *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]; f[1]=v[1]; f[2]=v[2]; f[3]=v[3]; glVertexAttrib4fv(index, f); }; \
void  glVertexAttrib4N##suffix##v (GLuint index, const type *v) { GLfloat f[4] = {0,0,0,1}; f[0] =v[0]/norm; f[1]=v[1]/norm; f[2]=v[2]/norm; f[3]=v[3]/norm; glVertexAttrib4fv(index, f); };
THUNK(b, GLbyte, 127.0f);
THUNK(ub, GLubyte, 255.0f);
THUNK(s, GLshort, 32767.0f);
THUNK(us, GLushort, 65535.0f);
THUNK(i, GLint, 2147483647.0f);
THUNK(ui, GLuint, 4294967295.0f);
#undef THUNK
void glVertexAttrib4Nub(GLuint index, GLubyte v0, GLubyte v1, GLubyte v2, GLubyte v3) {GLfloat f[4] = {0,0,0,1}; f[0] =v0/255.f; f[1]=v1/255.f; f[2]=v2/255.f; f[3]=v3/255.f; glVertexAttrib4fv(index, f); };
