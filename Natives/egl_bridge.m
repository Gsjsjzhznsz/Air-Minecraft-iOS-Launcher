#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

// 默认 GL 路径，pojavInit() 会重新设置
int clientAPI = GLFW_OPENGL_API;

// FPS 计数器（参照 FCL egl_bridge.c 的 atomic_uint 实现）
// 在 pojavSwapBuffers() 中累加，在 SurfaceViewController 读取时重置
static atomic_uint _pojavFpsCounter = 0;

// 阶段13：首帧渲染检测标志（参照 FCL 的 game_ready 回调）
// pojavSwapBuffers() 首次调用时置为 YES 并发送通知，SurfaceViewController 据此移除启动遮罩
static BOOL s_firstFrameRendered = NO;

unsigned int pojavGetAndResetFps() {
    return atomic_exchange(&_pojavFpsCounter, 0);
}

/// 显式递增 FPS 计数器（供 Vulkan 模式使用）
///
/// Vulkan 渲染器不经过 EGL 的 pojavSwapBuffers 路径，而是通过 MoltenVK 的
/// vkQueuePresentKHR 直接 present。因此 pojavSwapBuffers 中的 FPS 计数逻辑
/// 不会触发。SurfaceViewController 在 Vulkan 模式下使用 CADisplayLink 作为
/// 帧率检测 fallback，每帧通过此函数递增计数器。
void pojavIncrementFpsCounter() {
    atomic_fetch_add(&_pojavFpsCounter, 1);

    // 首帧渲染检测（与 pojavSwapBuffers 中的逻辑一致）
    if (!s_firstFrameRendered) {
        s_firstFrameRendered = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PojavFirstFrameRendered" object:nil];
            NSLog(@"[egl_bridge] First frame rendered (Vulkan displayLink path), game is ready");
        });
    }
}

/// 运行时判定 MC 真实渲染路径是否为 Vulkan。
///
/// 修复 FPS 显示错误的根本问题：
/// 之前 SurfaceViewController 在 viewDidLoad 时通过 graphicsApi 字符串静态推断
/// 是否启用 CADisplayLink fallback 递增 FPS 计数器。但：
///   - graphicsApi=default 时由 MC 内部决定，无法预判（保守起见启用 fallback）
///   - 但若 MC 实际选了 GL 路径，pojavSwapBuffers 也会计数，导致双重计数
///   - 反之若 graphicsApi=prefer_vulkan 但 MC 启动失败回退到 GL，fallback 会错误递增
///
/// 通过 clientAPI 运行时信号（由 MC 调用 glfwWindowHint(GLFW_CLIENT_API, ...) 写入）
/// 可以准确判定 MC 当前实际走的渲染路径：
///   - GLFW_NO_API（0）→ Vulkan 路径，pojavSwapBuffers 不被调用，需要 fallback
///   - 其他值（GLFW_OPENGL_API 等）→ GL 路径，pojavSwapBuffers 会计数，禁用 fallback
///
/// PLDisplayLinkTarget.displayLinkTick: 每帧动态查询此函数，确保 fallback 启用状态
/// 与 MC 实际渲染路径一致，避免双重计数或漏计数。
bool pojavIsActualVulkanPath() {
    // GLFW 模式：clientAPI 由 pojavSetWindowHint(GLFW_CLIENT_API, ...) 写入，
    // pojavInit() 初始化为 GLFW_OPENGL_API。MC 调用 glfwWindowHint(GLFW_NO_API)
    // 切换到 Vulkan 路径。
    if (clientAPI == GLFW_NO_API) return true;

    return false;
}

void JNI_LWJGL_changeRenderer(const char* value_c) {
    if (value_c == NULL) return;

    // 原实现直接 (*runtimeJavaVMPtr)->GetEnv(...) 且不检查返回值。
    // 在非 JVM 线程上（SDL 的视频/事件线程，SDL3 路径的 SDL_GL_LoadLibrary 就发生在
    // 这类线程上）GetEnv 返回 JNI_EDETACHED 并且**不会写 env**，env 保持为未初始化的
    // 栈垃圾，紧接着 (*env)->NewStringUTF(...) 立刻段错误（崩溃点就是本函数 +0x1c）。
    // 这里补齐：VM 判空 -> GetEnv 结果判空 -> AttachCurrentThread 兜底 -> 用完 detach。
    JavaVM *vm = runtimeJavaVMPtr;
    if (vm == NULL) {
        NSLog(@"[egl_bridge] JNI_LWJGL_changeRenderer('%s') skipped: runtimeJavaVMPtr is NULL", value_c);
        return;
    }

    JNIEnv *env = NULL;
    BOOL attached = NO;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_4) != JNI_OK || env == NULL) {
        if ((*vm)->AttachCurrentThread(vm, (void **)&env, NULL) != JNI_OK || env == NULL) {
            NSLog(@"[egl_bridge] JNI_LWJGL_changeRenderer('%s') skipped: cannot obtain JNIEnv", value_c);
            return;
        }
        attached = YES;
    }

    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    if (key != NULL && value != NULL) {
        jclass clazz = (*env)->FindClass(env, "java/lang/System");
        if (clazz != NULL) {
            jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty",
                "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
            if (method != NULL) {
                (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
            }
            (*env)->DeleteLocalRef(env, clazz);
        }
        (*env)->DeleteLocalRef(env, key);
        (*env)->DeleteLocalRef(env, value);
    }

    if (attached) (*vm)->DetachCurrentThread(vm);
}

void pojavTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

/// OpenGL 子系统是否已初始化成功（渲染器 bridge + br_init()）。
///
/// 必须是全局的而不是 pojavCreateContext 里的局部 static：SDL3 路径下
/// SDL_GL_LoadLibrary 已经调过 pojavInitOpenGLForSDL3() 完成初始化，
/// 若 pojavCreateContext 再凭自己的局部 static 判定"未初始化"，就会再调一次
/// 完整的 pojavInitOpenGL()——那会在 SDL 的原生线程上执行 JNI 调用
/// （JNI_LWJGL_changeRenderer），正是 fc0d838 上报的
/// `C [AngelAuraAmethyst+0x220df8] JNI_LWJGL_changeRenderer+0x1c` 崩溃。
static BOOL s_openGLInited = NO;

BOOL pojavIsOpenGLInited(void) {
    return s_openGLInited;
}

/// 统一收口初始化结果，成功后置位幂等标志。
static int pojavFinishOpenGLInit(int result) {
    if (result == 0) {
        s_openGLInited = YES;
    } else {
        NSLog(@"[egl_bridge] pojavInitOpenGL failed (br_init() returned %d); "
              @"not marking as initialised", result);
    }
    return result;
}

static int pojavInitOpenGLInternal(BOOL setLwjglProperty) {
    if (s_openGLInited) {
        // 幂等：重复初始化会二次 dlopen 渲染器、二次 br_init()（eglInitialize），
        // 且在 SDL3 路径上会触发无意义的 JNI 调用。
        NSDebugLog(@"[egl_bridge] pojavInitOpenGL skipped: already initialised");
        return 0;
    }
    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_LTW]) {
        // LTW (Large Thin Wrapper) - OpenGL Core 3.3 → OpenGL ES 3 转译层
        // 复刻自官方 MojoLauncher/LTW 仓库，完美支持 Sodium + Iris 光影。
        //
        // 关键：LTW 的 constructor（proc.c）需要通过 dlsym 找到 eglGetProcAddress
        // 等 EGL 函数符号。LTW 自身只导出 eglCreateContext / eglDestroyContext /
        // eglMakeCurrent 三个 wrapper，其他 EGL 函数直接转发给 host EGL（ANGLE）。
        // 所以必须先 dlopen ANGLE（RTLD_GLOBAL）让 ANGLE 的 EGL 符号进入全局符号表，
        // LTW constructor 才能成功初始化。
        //
        // gl_bridge.m 的 dlsym_EGL() 在 LTW 模式下会从 libltw.dylib 直接 dlsym
        // 这三个 wrapper 函数，其余 EGL 函数仍从 ANGLE 解析。
        NSLog(@"[egl_bridge] LTW renderer: preloading ANGLE as host EGL before LTW init");
        dlopen("@rpath/" RENDERER_NAME_MTL_ANGLE, RTLD_GLOBAL);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MITHRIL]) {
        // Mithril 渲染器：EGL 1.5 + GL 3.3 Core 全部由 libmithril.dylib 提供
        // （Vulkan backend，经 MoltenVK 到 Metal）。
        // gl_bridge.m 的 dlsym_EGL() 会从 libmithril.dylib 解析 EGL 符号，
        // gl_init_context 用 EGL_OPENGL_BIT + EGL_OPENGL_API 创建 desktop GL 上下文。
        // 下方的统一逻辑会把它设为 LWJGL 的 opengl.libname 并 RTLD_GLOBAL 预加载。
        NSLog(@"[egl_bridge] Mithril renderer: EGL/GL provided by libmithril.dylib (Vulkan backend)");
        set_gl_bridge_tbl();
    } else if (isMobileGLRenderer(renderer.UTF8String)) {
        // MobileGL 渲染器：EGL + GL 由 libMobileGL.dylib 提供。
        // 两个变体共用同一个二进制，用 MOBILEGL_BACKEND_TYPE 选择后端：
        //   libMobileGL.dylib      -> DirectVulkan (GL -> Vulkan -> MoltenVK -> Metal)
        //   libMobileGL-gles.dylib -> DirectGLES   (GL -> OpenGL ES)
        setenv("MOBILEGL_BACKEND_TYPE",
            [renderer isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES] ? "DirectGLES" : "DirectVulkan",
            1);
        NSLog(@"[egl_bridge] MobileGL renderer: backend=%s",
            getenv("MOBILEGL_BACKEND_TYPE") ?: "<unset>");
        set_gl_bridge_tbl();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_VULKAN]) {
        // 关键修复（MoltenVK + OpenGL 黑屏 + 图形 API 切换无效）：
        //
        // 之前 Vulkan 渲染器单向调用 set_vk_bridge_tbl()，一旦设置所有 GL 调用都走
        // vk_bridge 的 stub（vk_init_context 返回 dummy，vk_make_current 空实现）。
        // 当 MC 26.2+ 选 prefer_opengl 时仍走 GL 路径（clientAPI != GLFW_NO_API），
        // 但 bridge 已是 vk stub → 无真实 GL 上下文 → 黑屏。
        //
        // 修复策略（参照 FCL/HMCL 的 renderer + graphicsApi 联动逻辑）：
        //   1. 始终初始化 GL bridge（set_gl_bridge_tbl），让 GL 路径有真实上下文
        //   2. 同时预加载 libMoltenVK.dylib（Vulkan 路径需要）
        //   3. pojavCreateContext 根据 clientAPI 动态决定返回值：
        //      - GLFW_NO_API（Vulkan 路径）→ 返回 CAMetalLayer，MC/LWJGL 自管 Vulkan
        //      - 其他（GL 路径）→ 调用 br_init_context 创建真实 EGL/GL 上下文
        //
        // 这样无论 MC 选 OpenGL 还是 Vulkan 路径都能正常工作：
        //   - prefer_vulkan：MC 走 Vulkan 路径，glfwWindowHint(GLFW_NO_API) → CAMetalLayer
        //   - prefer_opengl：MC 走 GL 路径，glfwWindowHint(GLFW_OPENGL_API) → EGL 上下文
        //   - default：MC 内部决定，两种路径都能处理
        //
        // 注意：JavaLauncher.m 已在 Vulkan 模式下设置 org.lwjgl.opengl.libname=libmobileglues.dylib，
        // 所以 LWJGL 加载的 GL 库是 MobileGlues（GL→Vulkan 翻译层），能通过 Vulkan 后端路由 GL 调用。
        // 这就是用户说的"用 OpenGL 渲染游戏加用 MoltenVK，帧率才能达到 120"的实现原理：
        // MC 走 GL 路径 → EGL 上下文（ANGLE Metal）→ MobileGlues 翻译 → Vulkan → MoltenVK → Metal
        // MobileGlues 的 Vulkan 后端使用 IMMEDIATE present mode，可超过屏幕刷新率。
        NSLog(@"[egl_bridge] Vulkan renderer: initializing GL bridge for OpenGL path fallback (graphicsApi linkage)");
        set_gl_bridge_tbl();
        // 预加载 libMoltenVK.dylib（Vulkan 路径需要，GL 路径不影响）
        dlopen("@rpath/" RENDERER_NAME_VULKAN, RTLD_GLOBAL);
        // Vulkan 模式下 LWJGL OpenGL 库使用 MobileGlues（由 JavaLauncher.m 设置）
        // 不再调用 JNI_LWJGL_changeRenderer(RENDERER_NAME_MTL_ANGLE)，
        // 因为 JavaLauncher.m 已通过 -Dorg.lwjgl.opengl.libname=libmobileglues.dylib 设置
        if (setLwjglProperty) JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
        // 跳过下方的统一 JNI_LWJGL_changeRenderer 和 dlopen（已处理）
        return pojavFinishOpenGLInit(!br_init());
    }
    if (!isMobileGLRenderer(renderer.UTF8String)) {
        // 切换渲染器后清掉 MobileGL 专用环境变量，避免残留影响下一次启动
        unsetenv("MOBILEGL_BACKEND_TYPE");
        unsetenv("MOBILEGL_LOG_FILE_PATH");
    }
    if (setLwjglProperty && strcmp(renderer.UTF8String, RENDERER_NAME_VULKAN) != 0) {
        JNI_LWJGL_changeRenderer(renderer.UTF8String);
    }
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return pojavFinishOpenGLInit(!br_init());
    //return 0;
}

int pojavInitOpenGL(void) {
    return pojavInitOpenGLInternal(YES);
}

/// SDL3 路径专用入口：不写 org.lwjgl.opengl.libname。
///
/// 该属性由 JavaLauncher 在 JVM 启动时以 -D 传入，LWJGL 在 bootstrap 阶段就已读取
/// 并 dlopen 了渲染器库（这正是 MC 26.3 报 "OpenGL library already loaded" 的来源）。
/// 等到 SDL_GL_LoadLibrary 再设这个属性既无效果（LWJGL 的 System property 只在类
/// 初始化时读一次），又要为此把非 JVM 线程 attach 到 VM，属于纯粹的收益为负的操作。
int pojavInitOpenGLForSDL3(void) {
    return pojavInitOpenGLInternal(NO);
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(getenv("AMETHYST_RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("AMETHYST_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("AMETHYST_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    // FPS 计数（参照 FCL/ZL2 在 native swap buffer 入口计数，反映真实渲染帧率）
    atomic_fetch_add(&_pojavFpsCounter, 1);

    // 阶段13：首帧渲染检测（参照 FCL 的 game_ready 回调）
    // 首次调用 pojavSwapBuffers 表示游戏已渲染第一帧，发送通知移除启动遮罩
    if (!s_firstFrameRendered) {
        s_firstFrameRendered = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PojavFirstFrameRendered" object:nil];
            NSLog(@"[egl_bridge] First frame rendered, game is ready");
        });
    }

    if (!br_swap_buffers) return;
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    if (!br_make_current) return;
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    // 用全局幂等标志而非局部 static：SDL3 路径下 SDL_GL_LoadLibrary 已通过
    // pojavInitOpenGLForSDL3() 完成初始化，此处若用局部 static 判定为"未初始化"，
    // 会再调一次完整的 pojavInitOpenGL()，在 SDL 的原生线程上触发 JNI 调用。
    if (!pojavIsOpenGLInited()) {
        pojavInitOpenGL();
    }

    const char *renderer = getenv("AMETHYST_RENDERER");
    const char *graphicsApi = getenv("AMETHYST_GRAPHICS_API");
    NSLog(@"[egl_bridge] pojavCreateContext: clientAPI=%d (GLFW_NO_API=%d), renderer=%s, graphicsApi=%s",
          clientAPI, GLFW_NO_API, renderer ?: "<unset>", graphicsApi ?: "<unset>");

    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        // MC 26.2+ graphicsApi=prefer_vulkan 或 default（Vulkan 路径）会走这里
        // 返回 CAMetalLayer 作为 Vulkan surface，MC/LWJGL 通过 libMoltenVK.dylib 自管 Vulkan
        NSLog(@"[egl_bridge] Vulkan path: returning CAMetalLayer as Vulkan surface");
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    // GL 路径（clientAPI == GLFW_OPENGL_API 或 GLFW_OPENGL_ES_API）
    // MC 26.2+ graphicsApi=prefer_opengl 或 default（OpenGL 路径）会走这里
    // 调用 br_init_context 创建真实 EGL/GL 上下文
    // 即使 renderer=libMoltenVK.dylib，pojavInitOpenGL 已设置 GL bridge（set_gl_bridge_tbl），
    // 所以这里会调用 gl_init_context 创建 ANGLE Metal EGL 上下文
    NSLog(@"[egl_bridge] OpenGL path: creating EGL/GL context via br_init_context");
    return br_init_context(contextSrc);
}

void pojavSwapInterval(int interval) {
    // Vulkan 模式诊断：即使 br_swap_interval 为 NULL（Vulkan 不使用 EGL swap interval），
    // 也记录调用以帮助诊断帧率解锁问题
    if (!br_swap_interval) {
        const char* vsyncEnv = getenv("POJAV_DISABLE_VSYNC");
        NSLog(@"[egl_bridge] pojavSwapInterval(%d) called but br_swap_interval is NULL "
              @"(likely Vulkan mode). POJAV_DISABLE_VSYNC=%s. "
              @"Vulkan present mode is controlled by vkCreateSwapchainKHR, not eglSwapInterval.",
              interval, vsyncEnv ?: "<unset>");
        return;
    }
    // 解锁帧率（关闭垂直同步）：当启动器偏好 video.disable_game_vsync 开启时
    // （POJAV_DISABLE_VSYNC=1，由 JavaLauncher.m 设置），强制 swap interval=0，
    // 覆盖游戏 glfwSwapInterval(1) 的垂直同步请求。
    //
    // 这是 GL 类渲染器（gl4es/ANGLE/MobileGlues）真正生效 VSync 的落点
    // （gl_bridge.m gl_swap_interval → eglSwapInterval）。
    //
    // ANGLE Metal 后端对 eglSwapInterval 的处理：
    // - interval=0：eglSwapBuffers 不等待 vblank，渲染线程可立即继续下一帧渲染。
    //   虽然 Core Animation 仍按屏幕刷新率合成（60/120Hz），但渲染线程不被阻塞，
    //   可保持高吞吐量。多余的帧会被 Core Animation 丢弃，但 FPS 计数器反映渲染帧率。
    // - interval=1：eglSwapBuffers 等待 vblank，渲染线程被锁在屏幕刷新率。
    //
    // 与 PojavLauncher.java 写 enableVsync=false 互为兜底：即便游戏在运行时再次请求
    // VSync（某些 mod/版本会重设），native 层也会拦截。
    //
    // 与 Vulkan 渲染器的区别：
    // - GL 类渲染器（含 zink）：VSync 通过 eglSwapInterval 控制（此处生效）
    //   zink 创建 swapchain 时根据 eglSwapInterval 选择 present mode：
    //   interval=0 → IMMEDIATE（不等 vsync），interval=1 → FIFO（等 vsync）
    // - Vulkan 渲染器：VSync 通过 vkCreateSwapchainKHR 的 presentMode 控制
    //   （由 LWJGL 根据 glfwSwapInterval 选择，设备能力由 MoltenVK 自动检测）

    const char* vsyncEnv = getenv("POJAV_DISABLE_VSYNC");
    const char* renderer = getenv("AMETHYST_RENDERER");

    if (vsyncEnv && strcmp(vsyncEnv, "1") == 0) {
        if (interval != 0) {
            // 关键修复（FPS 解锁无效问题）：记录每次 VSync 拦截
            // 某些 mod（如 OptiFine、Sodium）或 MC 版本会在运行时反复调用 glfwSwapInterval(1)
            // 重新启用 VSync。记录每次拦截帮助诊断"帧率被重新锁定"的问题。
            // 之前只记录前几次，无法发现运行中被 mod 重新启用的情况。
            NSLog(@"[egl_bridge] pojavSwapInterval: intercepted VSync request interval=%d -> 0 (POJAV_DISABLE_VSYNC=1, renderer=%s)", interval, renderer ?: "<unset>");
        }
        interval = 0;
    } else {
        // 仅记录前几次调用，帮助诊断
        static int s_logCount = 0;
        if (s_logCount < 3) {
            s_logCount++;
            NSLog(@"[egl_bridge] pojavSwapInterval(%d) called (POJAV_DISABLE_VSYNC=%s, renderer=%s, count=%d)",
                  interval, vsyncEnv ?: "<unset>", renderer ?: "<unset>", s_logCount);
        }
    }

    br_swap_interval(interval);
}

