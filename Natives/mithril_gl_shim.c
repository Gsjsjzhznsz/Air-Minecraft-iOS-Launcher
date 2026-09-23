// ============================================================================
// Task 156: libmithril_glshim.dylib -- Mithril(OpenGL 4.0 档) GL provider 垫片
//
// 病历（latestlog.txt 0d45e3f，Mithril 会话，0a22f51 构建）：
//   java.lang.ArithmeticException: / by zero
//     at net.minecraft.util.Mth.positiveCeilDiv(Mth.java:795)
//     at net.minecraft.util.Mth.roundToward(Mth.java:787)
//     at net.minecraft.client.renderer.DynamicUniformStorage.<init>(...:30)
//     at com.mojang.blaze3d.systems.RenderSystem.initRenderer(RenderSystem.java:169)
//
//   反编译 MC 26.2 client.jar 实锤（GlHeuristics.java:75）：
//     new DeviceLimits(..., GL33C.glGetInteger(35380), ...)
//     35380 = GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT，Mithril 包装层对该枚举返回 0
//     → DynamicUniformStorage 的 roundToward(uboSize, 0) → floorDiv 除零。
//     Mithril 的 DirectGLES 兄弟问题：libMobileGL-gles（Espryt）的 multidraw
//     native/ext 档静默丢绘制（方块透明）——见 JavaLauncher 的
//     MOBILEGL_ESPRYT_MULTIDRAW_MODE 修复，本文件不涉。
//
// 修复（双层，均不触碰 libmithril.dylib 二进制）：
//   1) re-export libmithril.dylib 全部符号（dep_openal_shim 同款模式）：
//      LWJGL 以 -Dorg.lwjgl.opengl.libname 指向本垫片后，GL$1 Delegate 的
//      per-name dlsym 解析经 re-export 全部落到 Mithril 自身实现——
//      Task154 已实证 dlsym-direct 是 Mithril 唯一可靠解析路径（其
//      eglGetProcAddress 对核心 gl* 发放坏指针）。
//   2) 本地定义 glGetIntegerv / glGetInteger64v（本地符号优先于 re-export，
//      openal_shim/shaderc_shim 同款先例）：先调 Mithril 真实现，再对
//      "枚举值 <= 0 属于非法" 的 limit 查询做下限补底。只补 0/负值，
//      真实值原样透传——对正常驱动零行为差异。
//
// 同时导出 eglGetProcAddress 漏斗（对每个名字 dlsym(mithril)）：
//   若未来 Delegate 的 GetProcAddress 间接路径被恢复（jar 补丁回退等），
//   漏斗保证同样的 dlsym-direct 解析语义，垫片在两种 Delegate 状态下都工作。
//
// 线程安全：dlopen/dlsym 线程安全；静态函数指针缓存的 benign race
// （幂等赋值，最坏重复 dlsym 一次）。
// ============================================================================

#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

typedef unsigned int GLenum;
typedef int GLint;
typedef long GLint64;  // arm64 LP64: jint64/long 一致

// ---- 真实现解析（显式句柄 dlsym，不经过本 dylib 的 re-export 面） ----------
static void *ame156_mithril(void) {
    static void *s_handle;
    if (s_handle == NULL) {
        // 绝对路径与 re-export 依赖指向同一物理文件（dyld 按安装名去重）。
        s_handle = dlopen("@executable_path/Frameworks/libmithril.dylib",
                          RTLD_NOW | RTLD_LOCAL);
        if (s_handle == NULL) {
            s_handle = dlopen("libmithril.dylib", RTLD_NOW | RTLD_LOCAL);
        }
    }
    return s_handle;
}

// ---- limit 下限表（仅当真实现返回 <= 0 时启用；0 对这些枚举永远非法） -------
static GLint ame156_floor32(GLenum pname, GLint v) {
    if (v > 0) return v;
    switch (pname) {
        case 3379:  return 1024;    // GL_MAX_TEXTURE_SIZE（MC 自带 1024 兜底，防御性对齐）
        case 34852: return 8;       // GL_MAX_COLOR_ATTACHMENTS
        case 35361: return 16384;   // GL_MAX_UNIFORM_BLOCK_SIZE
        case 35380: return 256;     // GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT（/0 崩溃元凶）
        default:    return v;
    }
}

void glGetIntegerv(GLenum pname, GLint *params) {
    static void (*real)(GLenum, GLint *);
    if (real == NULL) {
        real = (void (*)(GLenum, GLint *))dlsym(ame156_mithril(), "glGetIntegerv");
    }
    if (real == NULL || params == NULL) return;
    real(pname, params);
    switch (pname) {
        case 3379:
        case 34852:
        case 35361:
        case 35380:
            params[0] = ame156_floor32(pname, params[0]);
            break;
        default:
            break;
    }
}

void glGetInteger64v(GLenum pname, GLint64 *params) {
    static void (*real)(GLenum, GLint64 *);
    if (real == NULL) {
        real = (void (*)(GLenum, GLint64 *))dlsym(ame156_mithril(), "glGetInteger64v");
    }
    if (real == NULL || params == NULL) return;
    real(pname, params);
    if (params[0] <= 0) {
        switch (pname) {
            case 35361: params[0] = 16384; break;  // GL_MAX_UNIFORM_BLOCK_SIZE
            case 35380: params[0] = 256;    break; // GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT
            default: break;
        }
    }
}

// ---- eglGetProcAddress 漏斗（Delegate GetProcAddress 间接路径的等价语义） ---
void *eglGetProcAddress(const char *name) {
    if (name == NULL) return NULL;
    if (strcmp(name, "glGetIntegerv") == 0)    return (void *)&glGetIntegerv;
    if (strcmp(name, "glGetInteger64v") == 0)  return (void *)&glGetInteger64v;
    return dlsym(ame156_mithril(), name);
}
