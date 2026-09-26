#include <Foundation/Foundation.h>
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

#define LOOKUP_FUNC(func) \
    if (!gles_##func) { \
        gles_##func = dlsym(RTLD_NEXT, #func); \
    } if (!gles_##func) { \
        gles_##func = dlsym(RTLD_DEFAULT, #func); \
    }

#define AliasDecl(NAME, EXT)

#define AliasDeclPriv(NAME)

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
    (void)0; /* harness: forensics stubbed */

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

typedef void (*ame173_fn_glTexBuffer)(GLenum, GLenum, GLuint);
static ame173_fn_glTexBuffer ame173_ptr_glTexBuffer;
void glTexBuffer(GLenum target, GLenum internalformat, GLuint buffer) {
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
    (void)fn; /* harness: log stubbed */

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

    // get the size of the shader sources and than concatenate in a single string
    int l = 0;
    for (int i=0; i<count; i++) l+=(length && length[i] >= 0)?length[i]:strlen(string[i]);
    if (source) free(source);
    source = calloc(1, l+1);
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
