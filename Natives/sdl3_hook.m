// sdl3_hook.m — SDL3 兼容层，移植自 ZalithLauncher2 的
// ZalithLauncher/src/main/jni/sdl_hook.c（Android 端，基于 bytehook）。
//
// iOS 上没有 bytehook，等价机制是 main_hook.m 里 fishhook 住的 dlsym
// （hooked_dlsym）。LWJGL 通过 dlsym 取 SDL 函数指针后直接调用，不走
// __la_symbol_ptr，所以必须在 dlsym 层拦 —— 这和 SDL_SetWindowMouseGrab
// 用的是同一条路子。SDL 内部调用自己的函数不经过 dlsym，因此不会被误伤。
//
// 解决的问题（均与 MC 26.x 的 RenderPearl 相关）：
//
// 1. 移动渲染器都是 OpenGL ES 实现，而 MC 按桌面 GL 惯例初始化 SDL，
//    非 ES 的 profile 请求会被宿主拒绝。建窗前强制切到 ES profile。
//
// 2. MC 26.3 ss9+ 在设备初始化时先建一个隐藏工具窗口（GL 上下文依附其上），
//    随后主窗口创建被拒；销毁工具窗口又会使其上的 GL surface 失效。
//    故把后续建窗请求重定向到首个窗口。
//
// 3. MC 26.3 要求 SDL 与 LWJGL 使用同一 Vulkan 加载器实例（校验
//    vkGetInstanceProcAddr 指针一致），而 SDL 只能按路径加载。若启动器已
//    持有句柄（记录在环境变量里），SDL 加载 libvulkan 时把该句柄还回去。
//
// 4. EGL 代理：eglChooseConfig / eglCreateContext 首选请求失败后做兼容
//    重试（RENDERABLE_TYPE 归一化、剔除 KHR 版本属性、CV=2 兜底）。
//
// 全部行为可用环境变量关闭，默认只在对移动 ES 渲染器时生效：
//   AMETHYST_SDL_GLES_COMPAT=0    关闭 ES profile 强制与 EGL 代理
//   AMETHYST_SDL_REUSE_WINDOW=0   关闭主窗口复用
//   AMETHYST_VULKAN_PTR=<hex>     启用 SDL_LoadObject 句柄共享

#import <Foundation/Foundation.h>
#import "utils.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>   // strcasecmp
#include <sys/types.h>

#pragma mark - SDL3 常量（与 SDL_video.h 对齐，避免依赖 SDL 头文件）

// SDL_GLAttr：从 0 开始顺序计数，CONTEXT_PROFILE_MASK 是第 21 个
#define AME_SDL_GL_CONTEXT_PROFILE_MASK 20
// SDL_GLProfile
#define AME_SDL_GL_CONTEXT_PROFILE_ES 0x0004

#pragma mark - EGL 常量（自给自足，不依赖 EGL 头文件是否存在）

#define AME_EGL_NONE 0x3038
#define AME_EGL_RENDERABLE_TYPE 0x3040
#define AME_EGL_OPENGL_ES_BIT 0x0001
#define AME_EGL_OPENGL_ES2_BIT 0x0004
#define AME_EGL_OPENGL_ES3_BIT 0x0040
#define AME_EGL_OPENGL_BIT 0x0008
// 注意：EGL_CONTEXT_MAJOR_VERSION 与 EGL_CONTEXT_CLIENT_VERSION 同为 0x3098，
// 这是 EGL 的历史遗留（ZL2 代码里也是这个值）。
#define AME_EGL_CONTEXT_CLIENT_VERSION 0x3098
#define AME_EGL_CONTEXT_MAJOR_VERSION_KHR 0x3098
#define AME_EGL_CONTEXT_MINOR_VERSION_KHR 0x30FB

#pragma mark - 真实 SDL 函数指针

// SDL3 里 bool 就是 C99 _Bool（1 字节），这里用 int 做 ABI 安全的返回类型，
// 只取其"非零即成功"的语义，避免与 Objective-C 的 BOOL 混淆。
typedef bool (*ame_fn_SDL_GL_SetAttribute)(int attr, int value);
typedef void *(*ame_fn_SDL_CreateWindow)(const char *title, int w, int h, uint32_t flags);
typedef void *(*ame_fn_SDL_CreateWindowWithProperties)(uint32_t props);
typedef void (*ame_fn_SDL_DestroyWindow)(void *window);
typedef void *(*ame_fn_SDL_LoadFunction)(void *handle, const char *name);
typedef void *(*ame_fn_SDL_EGL_GetProcAddress)(const char *proc);
typedef void *(*ame_fn_SDL_LoadObject)(const char *path);
typedef void (*ame_fn_SDL_UnloadObject)(void *handle);

// SDL3 GL 入口（被接管后转交启动器 EGL bridge）
typedef bool (*ame_fn_SDL_GL_LoadLibrary)(const char *path);
typedef void *(*ame_fn_SDL_GL_CreateContext)(void *window);
typedef bool (*ame_fn_SDL_GL_MakeCurrent)(void *window, void *context);
typedef bool (*ame_fn_SDL_GL_SwapWindow)(void *window);
typedef void *(*ame_fn_SDL_GL_GetProcAddress)(const char *proc);
typedef bool (*ame_fn_SDL_GL_SetSwapInterval)(int interval);
typedef bool (*ame_fn_SDL_GL_DestroyContext)(void *context);
typedef void *(*ame_fn_SDL_GL_GetCurrentContext)(void);

static ame_fn_SDL_GL_SetAttribute ame_real_GL_SetAttribute = NULL;
static ame_fn_SDL_CreateWindow ame_real_CreateWindow = NULL;
static ame_fn_SDL_CreateWindowWithProperties ame_real_CreateWindowWithProperties = NULL;
static ame_fn_SDL_DestroyWindow ame_real_DestroyWindow = NULL;
static ame_fn_SDL_LoadFunction ame_real_LoadFunction = NULL;
static ame_fn_SDL_EGL_GetProcAddress ame_real_EGL_GetProcAddress = NULL;
static ame_fn_SDL_LoadObject ame_real_LoadObject = NULL;
static ame_fn_SDL_UnloadObject ame_real_UnloadObject = NULL;

static ame_fn_SDL_GL_LoadLibrary ame_real_GL_LoadLibrary = NULL;
static ame_fn_SDL_GL_CreateContext ame_real_GL_CreateContext = NULL;
static ame_fn_SDL_GL_MakeCurrent ame_real_GL_MakeCurrent = NULL;
static ame_fn_SDL_GL_SwapWindow ame_real_GL_SwapWindow = NULL;
static ame_fn_SDL_GL_GetProcAddress ame_real_GL_GetProcAddress = NULL;
static ame_fn_SDL_GL_SetSwapInterval ame_real_GL_SetSwapInterval = NULL;
static ame_fn_SDL_GL_DestroyContext ame_real_GL_DestroyContext = NULL;
static ame_fn_SDL_GL_GetCurrentContext ame_real_GL_GetCurrentContext = NULL;

#pragma mark - EGL 真实函数（首次解析后固定，避免跨 loader 调用）

typedef int (*ame_fn_eglChooseConfig)(void *dpy, const int *attrib_list, void **configs,
                                      int config_size, int *num_config);
typedef void *(*ame_fn_eglCreateContext)(void *dpy, void *config, void *share,
                                         const int *attrib_list);
typedef int (*ame_fn_eglSwapBuffers)(void *dpy, void *surface);

static ame_fn_eglChooseConfig ame_orig_eglChooseConfig = NULL;
static ame_fn_eglCreateContext ame_orig_eglCreateContext = NULL;
static ame_fn_eglSwapBuffers ame_orig_eglSwapBuffers = NULL;

#pragma mark - 外部依赖

// main_hook.m 提供的"绕过 hook"的 dlsym，避免本文件内解析 SDL 符号时
// 又绕回 hooked_dlsym 造成递归。
extern void *amethyst_orig_dlsym(void *handle, const char *name);

static void *ame_real_dlsym(const char *name) {
    if (amethyst_orig_dlsym) {
        void *p = amethyst_orig_dlsym(RTLD_DEFAULT, name);
        if (p != NULL) return p;
    }
    return dlsym(RTLD_DEFAULT, name);
}

#pragma mark - 渲染器分类

static bool ame_envFlagOn(const char *name, bool defaultValue) {
    const char *v = getenv(name);
    if (v == NULL || v[0] == '\0') return defaultValue;
    return !(strcmp(v, "0") == 0 || strcasecmp(v, "false") == 0 ||
             strcasecmp(v, "no") == 0 || strcasecmp(v, "off") == 0);
}

// 启动器把 EGL 库路径放在 POJAVEXEC_EGL（Android 传统），iOS 侧沿用
// AMETHYST_RENDERER。两个都查，保持与 ZL2 语义一致。
static bool ame_isMobileGluesEgl(void) {
    const char *egl = getenv("POJAVEXEC_EGL");
    if (egl == NULL) return false;
    const char *base = strrchr(egl, '/');
    base = (base != NULL) ? base + 1 : egl;
    return strstr(base, "mobileglues") != NULL;
}

// GLES 兼容层（强制 ES profile、EGL 重试）只对移动 ES 渲染器生效，
// 桌面 / OSMesa 路径不得被 ES 化 —— 否则 zink 会被错误处理。
static bool ame_sdlGlesCompatEnabled(void) {
    if (!ame_envFlagOn("AMETHYST_SDL_GLES_COMPAT", true)) return false;

    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return ame_isMobileGluesEgl();

    if (strstr(renderer, "desktopgl") != NULL) return false;
    if (strncmp(renderer, "gallium_", 8) == 0) return false;      // OSMesa 系
    if (strncmp(renderer, "libOSMesa", 9) == 0) return false;     // zink（含版本号）
    if (strcmp(renderer, "vulkan_zink") == 0) return false;       // zink
    if (strstr(renderer, "libMoltenVK") != NULL) return false;    // 原生 Vulkan
    if (strncmp(renderer, "opengles", 8) == 0) return true;       // 内置 GL4ES
    if (strstr(renderer, "libMobileGL") != NULL) return true;     // MobileGL 双后端
    if (strstr(renderer, "libmithril") != NULL) return true;      // Mithril
    return ame_isMobileGluesEgl();                                // MobileGlues
}

#pragma mark - 1) 强制 ES profile

static bool ame_forcedEsProfile = false;

static void ame_forceEglProfileEs(void) {
    if (!ame_sdlGlesCompatEnabled()) return;
    if (ame_real_GL_SetAttribute == NULL) {
        ame_real_GL_SetAttribute = (ame_fn_SDL_GL_SetAttribute)ame_real_dlsym("SDL_GL_SetAttribute");
    }
    if (ame_real_GL_SetAttribute != NULL) {
        ame_real_GL_SetAttribute(AME_SDL_GL_CONTEXT_PROFILE_MASK, AME_SDL_GL_CONTEXT_PROFILE_ES);
        ame_forcedEsProfile = true;
        NSDebugLog(@"[SDLHook] forced SDL_GL_CONTEXT_PROFILE_MASK = ES");
    } else {
        NSDebugLog(@"[SDLHook] SDL_GL_SetAttribute unresolved, cannot force ES profile");
    }
}

#pragma mark - 2) 主窗口复用

static void *ame_primaryWindow = NULL;
static unsigned int ame_primaryWindowRefs = 0;

static bool ame_shouldReusePrimaryWindow(void) {
    // 仅对移动 ES 渲染器生效。zink / OSMesa 目前工作正常，任何窗口行为的改动
    // 都不能波及它们 —— 这条链路不经过 EGL，本文件的兼容逻辑对它没有意义。
    if (!ame_sdlGlesCompatEnabled()) return false;
    return ame_envFlagOn("AMETHYST_SDL_REUSE_WINDOW", true);
}

#pragma mark - 3) EGL 兼容重试

// RENDERABLE_TYPE 归一化为 ES2_BIT：宿主若不支持请求的 ES3/桌面 GL 位，
// 退回 ES2 至少能拿到一个可用 config。
static int ame_normalizeEglChooseConfigList(const int *attrib_list, int *fixed, int cap) {
    if (attrib_list == NULL) return 0;
    int n = 0;
    for (int i = 0; n < cap - 2; i += 2) {
        int attr = attrib_list[i];
        int val = attrib_list[i + 1];
        if (attr == AME_EGL_NONE) {
            fixed[n] = AME_EGL_NONE;
            fixed[n + 1] = 0;
            n += 2;
            break;
        }
        if (attr == AME_EGL_RENDERABLE_TYPE) {
            if ((val & (AME_EGL_OPENGL_ES3_BIT | AME_EGL_OPENGL_BIT)) != 0 &&
                (val & AME_EGL_OPENGL_ES2_BIT) == 0) {
                val = (val & ~(AME_EGL_OPENGL_ES3_BIT | AME_EGL_OPENGL_BIT)) |
                      AME_EGL_OPENGL_ES2_BIT;
            }
        }
        fixed[n] = attr;
        fixed[n + 1] = val;
        n += 2;
    }
    return n > 0;
}

// 剔除宿主不识别的 KHR 版本属性，生成兼容重试表；返回请求的主版本号（无则 0）
static int ame_normalizeEglContextAttribs(const int *attrib_list, int *fixed, int cap,
                                          bool esSemantics) {
    int version = 0;
    bool hasClientVersion = false;
    if (attrib_list == NULL) return 0;
    int n = 0;
    for (int i = 0; n < cap - 2; i += 2) {
        int attr = attrib_list[i];
        int val = attrib_list[i + 1];
        if (attr == AME_EGL_NONE) break;
        if (attr == AME_EGL_CONTEXT_MAJOR_VERSION_KHR) {  // 记录主版本后剔除
            if (version == 0) version = val;
            continue;
        }
        if (attr == AME_EGL_CONTEXT_MINOR_VERSION_KHR) continue;
        if (attr == AME_EGL_CONTEXT_CLIENT_VERSION) {
            hasClientVersion = true;
            if (version == 0) version = val;
        }
        if (n >= cap - 2) return 0;
        fixed[n++] = attr;
        fixed[n++] = val;
    }
    // 仅 ES 语义下补写 CLIENT_VERSION（避免退化成驱动默认版本）；
    // desktop 语义不补写 —— 桌面 context 不使用 CLIENT_VERSION
    if (esSemantics && version > 0 && !hasClientVersion) {
        if (n >= cap - 2) return 0;
        fixed[n++] = AME_EGL_CONTEXT_CLIENT_VERSION;
        fixed[n++] = version;
    }
    if (n >= cap - 2) return 0;
    fixed[n++] = AME_EGL_NONE;
    fixed[n++] = 0;
    return version;
}

static void *ame_proxyEglCreateContext(void *dpy, void *config, void *share,
                                       const int *attrib_list) {
    if (ame_orig_eglCreateContext == NULL) {
        NSDebugLog(@"[SDLHook] eglCreateContext was not resolved");
        return NULL;
    }

    void *ctx = ame_orig_eglCreateContext(dpy, config, share, attrib_list);
    if (ctx != NULL || !ame_sdlGlesCompatEnabled()) return ctx;

    bool esSemantics = ame_forcedEsProfile;
    int fixed[64];
    int version = ame_normalizeEglContextAttribs(attrib_list, fixed, 64, esSemantics);
    if (version == 0) return ctx;

    NSDebugLog(@"[SDLHook] retrying eglCreateContext without KHR version attrs (CV=%d)", version);
    ctx = ame_orig_eglCreateContext(dpy, config, share, fixed);
    if (ctx != NULL || !esSemantics || version <= 2) return ctx;  // CV=2 为移动端最后兜底

    NSDebugLog(@"[SDLHook] retrying eglCreateContext with CV=2 after CV=%d failed", version);
    int es2[3] = {AME_EGL_CONTEXT_CLIENT_VERSION, 2, AME_EGL_NONE};
    return ame_orig_eglCreateContext(dpy, config, share, es2);
}

static int ame_proxyEglChooseConfig(void *dpy, const int *attrib_list, void **configs,
                                    int config_size, int *num_config) {
    if (ame_orig_eglChooseConfig == NULL) {
        NSDebugLog(@"[SDLHook] eglChooseConfig was not resolved");
        return 0;
    }

    int result = ame_orig_eglChooseConfig(dpy, attrib_list, configs, config_size, num_config);
    if (result && num_config != NULL && *num_config > 0) return result;
    if (!ame_sdlGlesCompatEnabled()) return result;  // 兼容 fallback 仅限移动 ES 渲染器

    int fixed[64];
    if (!ame_normalizeEglChooseConfigList(attrib_list, fixed, 64)) return result;
    int fallbackCount = 0;
    int fallbackResult = ame_orig_eglChooseConfig(dpy, fixed, configs, config_size, &fallbackCount);
    if (fallbackResult && num_config != NULL) *num_config = fallbackCount;
    NSDebugLog(@"[SDLHook] eglChooseConfig fallback result=%d count=%d",
               fallbackResult, fallbackCount);
    return fallbackResult;
}

static int ame_proxyEglSwapBuffers(void *dpy, void *surface) {
    if (ame_orig_eglSwapBuffers == NULL) {
        NSDebugLog(@"[SDLHook] eglSwapBuffers was not resolved");
        return 0;
    }
    return ame_orig_eglSwapBuffers(dpy, surface);
}

// 把原始指针换成代理。orig 为 NULL 时不覆盖（ZL2 语义：首次解析后固定）。
static void ame_maybeWrapEgl(const char *name, void **out) {
    if (name == NULL || *out == NULL) return;
    if (strcmp(name, "eglChooseConfig") == 0) {
        if (ame_orig_eglChooseConfig == NULL) ame_orig_eglChooseConfig = (ame_fn_eglChooseConfig)*out;
        if (*out != (void *)ame_proxyEglChooseConfig) *out = (void *)ame_proxyEglChooseConfig;
    } else if (strcmp(name, "eglCreateContext") == 0) {
        if (ame_orig_eglCreateContext == NULL) ame_orig_eglCreateContext = (ame_fn_eglCreateContext)*out;
        if (*out != (void *)ame_proxyEglCreateContext) *out = (void *)ame_proxyEglCreateContext;
    } else if (strcmp(name, "eglSwapBuffers") == 0) {
        if (ame_orig_eglSwapBuffers == NULL) ame_orig_eglSwapBuffers = (ame_fn_eglSwapBuffers)*out;
        if (*out != (void *)ame_proxyEglSwapBuffers) *out = (void *)ame_proxyEglSwapBuffers;
    }
}

#pragma mark - SDL 函数包装

static void *ame_SDL_CreateWindow(const char *title, int w, int h, uint32_t flags) {
    ame_forceEglProfileEs();
    NSDebugLog(@"[SDLHook] SDL_CreateWindow title=%s %dx%d flags=0x%x",
               title ? title : "(null)", w, h, flags);
    bool reuse = ame_shouldReusePrimaryWindow();
    if (reuse && ame_primaryWindow != NULL) {
        ame_primaryWindowRefs++;
        NSDebugLog(@"[SDLHook] reusing primary window %p, refs=%u",
                   ame_primaryWindow, ame_primaryWindowRefs);
        return ame_primaryWindow;
    }
    void *wnd = ame_real_CreateWindow ? ame_real_CreateWindow(title, w, h, flags) : NULL;
    if (reuse && wnd != NULL) {
        ame_primaryWindow = wnd;
        ame_primaryWindowRefs = 1;
    }
    NSDebugLog(@"[SDLHook] SDL_CreateWindow -> %p", wnd);
    return wnd;
}

static void *ame_SDL_CreateWindowWithProperties(uint32_t props) {
    ame_forceEglProfileEs();
    NSDebugLog(@"[SDLHook] SDL_CreateWindowWithProperties props=%u", props);
    bool reuse = ame_shouldReusePrimaryWindow();
    if (reuse && ame_primaryWindow != NULL) {
        ame_primaryWindowRefs++;
        NSDebugLog(@"[SDLHook] reusing primary window %p, refs=%u",
                   ame_primaryWindow, ame_primaryWindowRefs);
        return ame_primaryWindow;
    }
    void *wnd = ame_real_CreateWindowWithProperties
                    ? ame_real_CreateWindowWithProperties(props)
                    : NULL;
    if (reuse && wnd != NULL) {
        ame_primaryWindow = wnd;
        ame_primaryWindowRefs = 1;
    }
    NSDebugLog(@"[SDLHook] SDL_CreateWindowWithProperties -> %p", wnd);
    return wnd;
}

static void ame_SDL_DestroyWindow(void *window) {
    if (window != NULL && window == ame_primaryWindow) {
        if (ame_primaryWindowRefs > 0) ame_primaryWindowRefs--;
        if (ame_primaryWindowRefs > 0) {
            NSDebugLog(@"[SDLHook] DestroyWindow %p skipped, refs=%u",
                       window, ame_primaryWindowRefs);
            return;
        }
        ame_primaryWindow = NULL;
        ame_primaryWindowRefs = 0;
    }
    if (ame_real_DestroyWindow) ame_real_DestroyWindow(window);
}

static void *ame_SDL_LoadFunction(void *handle, const char *name) {
    void *r = ame_real_LoadFunction ? ame_real_LoadFunction(handle, name) : NULL;
    ame_maybeWrapEgl(name, &r);
    return r;
}

// SDL 公共 EGL 解析入口，可绕过 SDL_LoadFunction；补齐同样的代理
static void *ame_SDL_EGL_GetProcAddress(const char *proc) {
    void *r = ame_real_EGL_GetProcAddress ? ame_real_EGL_GetProcAddress(proc) : NULL;
    if (proc == NULL || r == NULL) return r;
    ame_maybeWrapEgl(proc, &r);
    return r;
}

// Vulkan 加载器一致性：MC 26.3 起 RenderPearl 要求 SDL 与 LWJGL 使用同一
// 加载器实例（校验 vkGetInstanceProcAddr 指针一致），而 SDL 仅能按路径加载。
// 启动器若已持有句柄（十六进制记录在 AMETHYST_VULKAN_PTR），此处直接还回。
// 对应句柄的引用计数由启动器持有，故忽略 SDL 侧的卸载。
static void *ame_SDL_LoadObject(const char *path) {
    if (path != NULL && (strstr(path, "vulkan") != NULL || strstr(path, "MoltenVK") != NULL)) {
        const char *vkptr = getenv("AMETHYST_VULKAN_PTR");
        if (vkptr != NULL && vkptr[0] != '\0') {
            void *handle = (void *)(uintptr_t)strtoull(vkptr, NULL, 16);
            if (handle != NULL) {
                NSDebugLog(@"[SDLHook] SDL_LoadObject('%s') -> shared handle %p", path, handle);
                return handle;
            }
        }
    }
    return ame_real_LoadObject ? ame_real_LoadObject(path) : NULL;
}

static void ame_SDL_UnloadObject(void *handle) {
    const char *vkptr = getenv("AMETHYST_VULKAN_PTR");
    if (vkptr != NULL && vkptr[0] != '\0') {
        void *vulkan_handle = (void *)(uintptr_t)strtoull(vkptr, NULL, 16);
        if (handle == vulkan_handle) {
            NSDebugLog(@"[SDLHook] SDL_UnloadObject(%p) ignored (shared handle)", handle);
            return;
        }
    }
    if (ame_real_UnloadObject) ame_real_UnloadObject(handle);
}

#pragma mark - 5) SDL GL 入口 → 启动器 EGL bridge

// 为什么需要接管：
//   SDL 的 UIKit 后端走的是 EAGL / CAEAGLLayer（iOS 系统 OpenGLES 框架），
//   而 MobileGL / Mithril / MobileGlues 提供的是 **EGL + GL** 符号。两者不是
//   同一套 ABI，SDL 自己建的上下文拿不到渲染器的 GL 函数，MC 26.3 的
//   GlBackend 因此判定 OpenGL 不可用并回落到原生 Vulkan。
//
//   启动器的 EGL bridge（gl_bridge.m）早已在 GLFW 路径（26.2 及以下）验证可用，
//   且 gl_init_context() 直接从 SurfaceViewController 的 layer 建 EGL surface，
//   不依赖 SDL 建了哪个 view —— 所以可以整条搬到 SDL3 路径上复用。
//
// 判定复用 ame_sdlGlesCompatEnabled()：它已排除 zink（libOSMesa/gallium_/
// vulkan_zink）与原生 Vulkan（libMoltenVK），因此 zink 在 26.3 上"回落 Vulkan"
// 那条已验证可用的路径不会受到任何影响。
static bool ame_glBridgeEnabled(void) {
    if (!ame_envFlagOn("AMETHYST_SDL_GL_BRIDGE", true)) return false;

    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return false;

    // 绝不接管的：zink 在 26.3 上依赖"OpenGL 被隐藏 → 回落 Vulkan"且已验证
    // 可进世界，是唯一的可用路径，一个字节都不能动。
    if (strncmp(renderer, "libOSMesa", 9) == 0) return false;    // zink（带版本号）
    if (strncmp(renderer, "gallium_", 8) == 0) return false;     // OSMesa 系
    if (strcmp(renderer, "vulkan_zink") == 0) return false;      // zink
    // 原生 Vulkan 自身走 Vulkan 路径，不需要 GL bridge
    if (strstr(renderer, "libMoltenVK") != NULL) return false;

    // 需要 EGL bridge 的转译型渲染器：它们提供 EGL + GL 符号，SDL 的 EAGL
    // 后端无法对接，必须由 bridge 建上下文并供给 GL 函数指针。
    if (strstr(renderer, "libMobileGL") != NULL) return true;    // MobileGL 双后端
    if (strstr(renderer, "libmithril") != NULL) return true;     // Mithril
    if (strstr(renderer, "mobileglues") != NULL) return true;    // MobileGlues
    if (strstr(renderer, "gl4es") != NULL) return true;          // GL4ES
    if (strstr(renderer, "libltw") != NULL) return true;         // LTW
    if (strncmp(renderer, "opengles", 8) == 0) return true;      // 内置 GLES

    return ame_isMobileGluesEgl();
}

// egl_bridge.m 的上下文入口。这些函数没有公开头文件，故在此 extern 声明。
// 参数用 void* 以避开 basic_render_window_t 的类型依赖。
// SDL3 路径用 ForSDL3 变体：不写 org.lwjgl.opengl.libname（该属性由 JavaLauncher
// 在 JVM 启动时以 -D 传入，LWJGL 早已读取；此处再设无效且需 attach 非 JVM 线程）。
extern int   pojavInitOpenGLForSDL3(void);
extern void *pojavCreateContext(void *contextSrc);
extern void  pojavMakeCurrent(void *window);
extern void  pojavSwapBuffers(void);
extern void  pojavSwapInterval(int interval);

static bool   g_glBridgeInited = false;
static void  *g_glContext = NULL;      // 充当 SDL_GLContext
static void  *g_rendererHandle = NULL; // 渲染器 dylib 句柄（缓存，避免重复 dlopen）

static void *ame_rendererHandle(void) {
    if (g_rendererHandle != NULL) return g_rendererHandle;
    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return NULL;
    NSString *path = [NSString stringWithFormat:@"@rpath/%s", renderer];
    // 渲染器已由 pojavInitOpenGL 以 RTLD_GLOBAL 预加载，此处返回同一句柄，
    // 仅增加引用计数，不会重复映射。
    g_rendererHandle = dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (g_rendererHandle == NULL) {
        NSDebugLog(@"[SDLHook] renderer dlopen('%@') failed: %s",
                   path, dlerror() ?: "unknown");
    }
    return g_rendererHandle;
}

// 库已由启动器预加载，这里只负责初始化 bridge
static bool ame_SDL_GL_LoadLibrary(const char *path) {
    if (!g_glBridgeInited) {
        g_glBridgeInited = true;
        int r = pojavInitOpenGLForSDL3();
        NSDebugLog(@"[SDLHook] SDL_GL_LoadLibrary('%s') -> pojavInitOpenGLForSDL3()=%d (EGL bridge)",
                   path ?: "<null>", r);
    }
    return true;
}

static void *ame_SDL_GL_CreateContext(void *window) {
    // MC 26.3 ss9+ 在设备初始化时先建一个隐藏工具窗口（flags 含 SDL_WINDOW_HIDDEN），
    // 随后再建主窗口。而 EGL bridge 的上下文生命周期与进程一致
    // （SDL_GL_DestroyContext 不真正销毁，见下），若每次调用都新建，就会在同一个
    // CALayer 上叠加第二个 EGLSurface —— 部分 EGL 实现（含 MobileGL）会直接失败，
    // 即便成功也会让 eglMakeCurrent 在两个 surface 间反复切换。
    // 故复用首个上下文，与 ZL2 的 shouldReusePrimaryWindow() 同一思路。
    if (g_glContext != NULL) {
        NSDebugLog(@"[SDLHook] SDL_GL_CreateContext(%p) -> reuse existing %p", window, g_glContext);
        // 复用时也要保证它处于 current 状态：MC 建完上下文后必然调 MakeCurrent，
        // 这里不额外处理。
        return g_glContext;
    }
    void *ctx = pojavCreateContext(NULL);
    if (ctx != NULL) g_glContext = ctx;
    NSDebugLog(@"[SDLHook] SDL_GL_CreateContext(%p) -> %p (EGL bridge)", window, ctx);
    return ctx;
}

static bool ame_SDL_GL_MakeCurrent(void *window, void *context) {
    if (context != NULL) g_glContext = context;
    pojavMakeCurrent(context);
    NSDebugLog(@"[SDLHook] SDL_GL_MakeCurrent(%p, %p) -> EGL bridge", window, context);
    return true;
}

static bool ame_SDL_GL_SwapWindow(void *window) {
    pojavSwapBuffers();
    return true;
}

// GL 函数必须来自渲染器自身。若误返回系统 GLES / EAGL 的实现，
// LWJGL 拿到的函数指针与 EGL 上下文不匹配，会直接崩。
static void *ame_SDL_GL_GetProcAddress(const char *proc) {
    if (proc == NULL) return NULL;
    void *h = ame_rendererHandle();
    if (h != NULL) {
        void *p = dlsym(h, proc);
        if (p != NULL) return p;
    }
    void *r = ame_real_GL_GetProcAddress ? ame_real_GL_GetProcAddress(proc) : NULL;
    if (r == NULL) r = dlsym(RTLD_DEFAULT, proc);
    return r;
}

static bool ame_SDL_GL_SetSwapInterval(int interval) {
    pojavSwapInterval(interval);
    return true;
}

// 上下文由 EGL bridge 持有，生命周期与进程一致。这里不真正销毁，
// 只摘掉引用 —— 否则 SDL 会用 EAGL 的语义去释放一个 EGL 对象而崩溃。
static bool ame_SDL_GL_DestroyContext(void *context) {
    NSDebugLog(@"[SDLHook] SDL_GL_DestroyContext(%p) ignored (owned by EGL bridge)", context);
    if (g_glContext == context) g_glContext = NULL;
    return true;
}

static void *ame_SDL_GL_GetCurrentContext(void) {
    return g_glContext;
}

#pragma mark - 对 main_hook.m 的接入点

/// 由 hooked_dlsym 在返回 orig_dlsym 之前调用。
/// 返回非 NULL 表示本模块接管了该符号；否则返回 NULL 让调用方走原路径。
void *amethyst_sdl3_hook_resolve(void *handle, const char *name) {
    if (name == NULL) return NULL;

    // 先记下真实指针（无论本次是否接管，后续包装都要用到）
    if (strcmp(name, "SDL_CreateWindow") == 0) {
        if (ame_real_CreateWindow == NULL) {
            ame_real_CreateWindow = (ame_fn_SDL_CreateWindow)amethyst_orig_dlsym(handle, name);
        }
        NSDebugLog(@"[SDLHook] hooked SDL_CreateWindow (real=%p)", (void *)ame_real_CreateWindow);
        return (void *)ame_SDL_CreateWindow;
    }
    if (strcmp(name, "SDL_CreateWindowWithProperties") == 0) {
        if (ame_real_CreateWindowWithProperties == NULL) {
            ame_real_CreateWindowWithProperties =
                (ame_fn_SDL_CreateWindowWithProperties)amethyst_orig_dlsym(handle, name);
        }
        NSDebugLog(@"[SDLHook] hooked SDL_CreateWindowWithProperties (real=%p)",
                   (void *)ame_real_CreateWindowWithProperties);
        return (void *)ame_SDL_CreateWindowWithProperties;
    }
    if (strcmp(name, "SDL_DestroyWindow") == 0) {
        if (ame_real_DestroyWindow == NULL) {
            ame_real_DestroyWindow = (ame_fn_SDL_DestroyWindow)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_DestroyWindow;
    }
    if (strcmp(name, "SDL_LoadFunction") == 0) {
        if (ame_real_LoadFunction == NULL) {
            ame_real_LoadFunction = (ame_fn_SDL_LoadFunction)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_LoadFunction;
    }
    if (strcmp(name, "SDL_EGL_GetProcAddress") == 0) {
        if (ame_real_EGL_GetProcAddress == NULL) {
            ame_real_EGL_GetProcAddress =
                (ame_fn_SDL_EGL_GetProcAddress)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_EGL_GetProcAddress;
    }
    if (strcmp(name, "SDL_LoadObject") == 0) {
        if (ame_real_LoadObject == NULL) {
            ame_real_LoadObject = (ame_fn_SDL_LoadObject)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_LoadObject;
    }
    if (strcmp(name, "SDL_UnloadObject") == 0) {
        if (ame_real_UnloadObject == NULL) {
            ame_real_UnloadObject = (ame_fn_SDL_UnloadObject)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_UnloadObject;
    }
    // SDL_GL_SetAttribute 不接管：MC 自己调用它设属性是合法行为，我们只在
    // 建窗前主动调用同一个函数来强制 ES profile（见 ame_forceEglProfileEs）。

    // SDL GL 上下文接管（MobileGL / Mithril / MobileGlues / gl4es / LTW）
    if (ame_glBridgeEnabled()) {
        if (strcmp(name, "SDL_GL_LoadLibrary") == 0) {
            if (ame_real_GL_LoadLibrary == NULL)
                ame_real_GL_LoadLibrary = (ame_fn_SDL_GL_LoadLibrary)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_LoadLibrary -> EGL bridge");
            return (void *)ame_SDL_GL_LoadLibrary;
        }
        if (strcmp(name, "SDL_GL_CreateContext") == 0) {
            if (ame_real_GL_CreateContext == NULL)
                ame_real_GL_CreateContext = (ame_fn_SDL_GL_CreateContext)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_CreateContext -> EGL bridge");
            return (void *)ame_SDL_GL_CreateContext;
        }
        if (strcmp(name, "SDL_GL_MakeCurrent") == 0) {
            if (ame_real_GL_MakeCurrent == NULL)
                ame_real_GL_MakeCurrent = (ame_fn_SDL_GL_MakeCurrent)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_MakeCurrent -> EGL bridge");
            return (void *)ame_SDL_GL_MakeCurrent;
        }
        if (strcmp(name, "SDL_GL_SwapWindow") == 0) {
            if (ame_real_GL_SwapWindow == NULL)
                ame_real_GL_SwapWindow = (ame_fn_SDL_GL_SwapWindow)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_SwapWindow -> EGL bridge");
            return (void *)ame_SDL_GL_SwapWindow;
        }
        if (strcmp(name, "SDL_GL_GetProcAddress") == 0) {
            if (ame_real_GL_GetProcAddress == NULL)
                ame_real_GL_GetProcAddress = (ame_fn_SDL_GL_GetProcAddress)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_GetProcAddress -> renderer dlsym");
            return (void *)ame_SDL_GL_GetProcAddress;
        }
        if (strcmp(name, "SDL_GL_SetSwapInterval") == 0) {
            if (ame_real_GL_SetSwapInterval == NULL)
                ame_real_GL_SetSwapInterval = (ame_fn_SDL_GL_SetSwapInterval)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_SetSwapInterval -> EGL bridge");
            return (void *)ame_SDL_GL_SetSwapInterval;
        }
        if (strcmp(name, "SDL_GL_DestroyContext") == 0) {
            if (ame_real_GL_DestroyContext == NULL)
                ame_real_GL_DestroyContext = (ame_fn_SDL_GL_DestroyContext)amethyst_orig_dlsym(handle, name);
            return (void *)ame_SDL_GL_DestroyContext;
        }
        if (strcmp(name, "SDL_GL_GetCurrentContext") == 0) {
            if (ame_real_GL_GetCurrentContext == NULL)
                ame_real_GL_GetCurrentContext = (ame_fn_SDL_GL_GetCurrentContext)amethyst_orig_dlsym(handle, name);
            return (void *)ame_SDL_GL_GetCurrentContext;
        }
    }

    return NULL;
}
