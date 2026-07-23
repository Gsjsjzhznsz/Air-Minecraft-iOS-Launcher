#import <Foundation/Foundation.h>
#import "PLLogOutputView.h"
#import "SurfaceViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "mach_excServer.h"

#include <dlfcn.h>
#include <libgen.h>
#include <pthread.h>
#include "external/fishhook/fishhook.h"

// === iOS 26+ PPL bypass（从原版项目移植）===
// excPort：硬件断点异常接收端口，hooked_dlopen_26_ppl 首次调用时分配
mach_port_t excPort;
// 前向声明：hooked_dlopen 在 PPL bypass 分支中通过 musttail 调用此函数
void *hooked_dlopen_26_ppl(const char *path, int mode);

void (*orig_abort)();
void (*orig_exit)(int code);
void* (*orig_dlopen)(const char* path, int mode);
void* (*orig_dlsym)(void* handle, const char* name);
int (*orig_open)(const char *path, int oflag, ...);

// 前向声明：zink stride fix 状态变量（定义在文件后部 Vulkan stride fix 区域，
// 但 hooked_dlopen 在文件前部就需要引用它来检测 libOSMesa 加载）
static BOOL g_zinkStrideFixActive = NO;

// ============================================================================
// SDL3 native hook（关键修复 MC 26.3-snapshot-4+ SDL3 启动崩溃）
// ============================================================================
// 背景：
//   MC 26.3-snapshot-4+ 从 GLFW 切换到 SDL3。MC 通过 LWJGL 的 SDL binding 或
//   自己的 JNI binding 调用 SDL3 函数。LWJGL/Library.loadNative 内部用 dlsym
//   获取 SDL3 函数指针。
//
//   SDL3 UIKit 后端默认创建新的 UIWindowScene，与启动器已有的
//   GameSurfaceView（含 CAMetalLayer）冲突，导致 SDL_CreateWindow 阻塞/崩溃。
//
//   之前的方案是用 SDLVideo.java 覆盖类拦截 SDL_CreateWindow。但日志显示
//   我们的 SDL.java/SDLVideo.java 覆盖类的 println 从未出现，说明 MC 不通过
//   LWJGL 的 SDL binding 加载 SDL3（MC 26.3 可能用自己的 JNI binding）。
//
//   因此改为在 native 层 hook dlsym，拦截 SDL_CreateWindow 请求，返回我们的
//   hook 函数。hook 函数调用 amethyst_sdl_create_window_with_scene（egl_bridge.m），
//   通过 SDL3 Properties API 传入启动器的 UIWindowScene，让 SDL3 复用启动器的
//   窗口场景。

// SDL_Window 不透明类型（避免依赖 SDL3 头文件）
struct SDL_Window;
typedef struct SDL_Window SDL_Window;

// 由 egl_bridge.m 提供：用启动器 UIWindowScene 创建 SDL3 窗口
extern SDL_Window *amethyst_sdl_create_window_with_scene(int w, int h, unsigned int flags);

// 原始 SDL_CreateWindow 函数指针（dlsym hook 捕获后保存）
static SDL_Window *(*g_orig_sdl_CreateWindow)(const char *, int, int, unsigned int) = NULL;

// ============================================================================
// SDL_InitSubSystem hook（参照 Amethyst-Android feat/lwjgl3ify-sdl-support 分支）
// ============================================================================
// 背景：
//   MC 26.3-snapshot-4+ 用 SDL3 替代 GLFW。MC 启动时调用 SDL_Init / SDL_InitSubSystem
//   初始化 SDL3 子系统（video/gamepad/joystick/events 等）。
//
//   Android 仓库的 sdl_hook.c 在 SDL_InitSubSystem 被调用时：
//     1. 通过 JNI 调用 CallbackBridge.notifyLauncher(SDL, INIT) 通知启动器
//     2. 设置 SDL_RETURN_KEY_HIDES_IME=true hint（让 Return 键隐藏软键盘，避免
//        MC 误处理 IME 事件导致输入异常）
//     3. 调用原始 SDL_InitSubSystem
//
//   iOS 移植：不需要 JNI 通知（iOS 启动器与 MC 在同一进程，直接共享状态），
//   但 SDL_RETURN_KEY_HIDES_IME hint 必须设置，否则 MC 26.3-snapshot-4 的
//   软键盘输入会卡住，可能导致启动时输入框阻塞主线程。

// SDL3 函数指针类型
typedef int SDL_bool;                    // SDL_bool = int (SDL_TRUE=1, SDL_FALSE=0)
typedef unsigned int SDL_InitFlags;      // SDL_InitFlags = Uint32
typedef int (*SDL_InitSubSystem_t)(SDL_InitFlags flags);
typedef SDL_bool (*SDL_SetHint_t)(const char *name, const char *value);

// 原始 SDL_InitSubSystem / SDL_SetHint 函数指针
static SDL_InitSubSystem_t g_orig_sdl_InitSubSystem = NULL;
static SDL_SetHint_t g_orig_sdl_SetHint = NULL;
static BOOL g_sdl3_init_hook_done = NO;

/// hook 函数：替换 SDL_InitSubSystem
/// 签名：int SDL_InitSubSystem(Uint32 flags)
static int amethyst_hooked_SDL_InitSubSystem(unsigned int flags) {
    NSLog(@"[SDL3 Hook] SDL_InitSubSystem intercepted: flags=0x%x", flags);

    // 首次调用时设置 SDL_RETURN_KEY_HIDES_IME hint（参照 Android 仓库 sdl_hook.c）
    // 这必须在调用原始 SDL_InitSubSystem 之前设置，确保 hint 在 SDL 初始化时生效
    if (!g_sdl3_init_hook_done) {
        g_sdl3_init_hook_done = YES;
        if (g_orig_sdl_SetHint) {
            // SDL_RETURN_KEY_HIDES_IME=true：按 Return 键隐藏 IME
            // Android 仓库注释："This is the normal for the launcher, the default in SDL is false."
            g_orig_sdl_SetHint("SDL_RETURN_KEY_HIDES_IME", "true");
            NSLog(@"[SDL3 Hook] Set SDL_RETURN_KEY_HIDES_IME=true");

            // 额外设置 iOS 专用 hints
            // SDL_HINT_IOS_HIDE_HOME_INDICATOR=1：隐藏 home indicator（沉浸式游戏体验）
            g_orig_sdl_SetHint("SDL_IOS_HIDE_HOME_INDICATOR", "1");
            // SDL_HINT_MOUSE_TOUCH_EVENTS=0：禁用鼠标模拟触摸事件（避免输入冲突）
            g_orig_sdl_SetHint("SDL_MOUSE_TOUCH_EVENTS", "0");
            // SDL_HINT_TOUCH_MOUSE_EVENTS=0：禁用触摸模拟鼠标事件（启动器自己处理触摸）
            g_orig_sdl_SetHint("SDL_TOUCH_MOUSE_EVENTS", "0");
            NSLog(@"[SDL3 Hook] Set iOS-specific SDL hints (hide home indicator, disable mouse/touch cross-events)");
        } else {
            NSLog(@"[SDL3 Hook] WARNING: SDL_SetHint not available, cannot set SDL_RETURN_KEY_HIDES_IME");
        }
    }

    // 调用原始 SDL_InitSubSystem
    if (!g_orig_sdl_InitSubSystem) {
        // 首次调用时通过 orig_dlsym 获取原始函数指针
        void *sdl_lib = dlopen("@rpath/libSDL3.dylib", RTLD_NOLOAD | RTLD_GLOBAL);
        if (!sdl_lib) {
            sdl_lib = dlopen("libSDL3.dylib", RTLD_NOLOAD | RTLD_GLOBAL);
        }
        if (sdl_lib && orig_dlsym) {
            g_orig_sdl_InitSubSystem = (SDL_InitSubSystem_t)orig_dlsym(sdl_lib, "SDL_InitSubSystem");
            g_orig_sdl_SetHint = (SDL_SetHint_t)orig_dlsym(sdl_lib, "SDL_SetHint");
            NSLog(@"[SDL3 Hook] Resolved original SDL_InitSubSystem=%p, SDL_SetHint=%p",
                  (void*)g_orig_sdl_InitSubSystem, (void*)g_orig_sdl_SetHint);
        }
    }

    if (g_orig_sdl_InitSubSystem) {
        int result = g_orig_sdl_InitSubSystem(flags);
        NSLog(@"[SDL3 Hook] Original SDL_InitSubSystem returned: %d", result);
        return result;
    }

    NSLog(@"[SDL3 Hook] FATAL: Original SDL_InitSubSystem not found, returning -1");
    return -1;
}

/// fishhook 版本的 SDL_InitSubSystem hook
static int amethyst_fishhook_SDL_InitSubSystem(unsigned int flags) {
    return amethyst_hooked_SDL_InitSubSystem(flags);
}

/// 提供给 egl_bridge.m 使用的"绕过 hook"的 dlsym
/// egl_bridge.m 在获取 SDL3 函数指针时必须调用此函数，否则会被 hooked_dlsym
/// 拦截（SDL_CreateWindow 请求会返回 hook 函数，导致无限递归）。
void *amethyst_orig_dlsym(void *handle, const char *name) {
    if (orig_dlsym) {
        return orig_dlsym(handle, name);
    }
    // fallback：如果 hook 尚未初始化（不应发生），用普通 dlsym
    return dlsym(handle, name);
}

/// hook 函数：替换 SDL_CreateWindow
/// 签名必须与 SDL3 的 SDL_CreateWindow 完全一致：
///   SDL_Window *SDL_CreateWindow(const char *title, int w, int h, Uint32 flags)
static SDL_Window *amethyst_hooked_SDL_CreateWindow(const char *title, int w, int h, unsigned int flags) {
    NSLog(@"[SDL3 Hook] SDL_CreateWindow intercepted: title=%s w=%d h=%d flags=0x%x",
          title ? title : "(null)", w, h, flags);
    // 调用我们的桥接函数（会用 Properties API 传入 UIWindowScene）
    SDL_Window *window = amethyst_sdl_create_window_with_scene(w, h, flags);
    NSLog(@"[SDL3 Hook] amethyst_sdl_create_window_with_scene returned: %p", window);
    return window;
}

void handle_fatal_exit(int code) {
    if (NSThread.isMainThread) {
        return;
    }

    // 检查 handleExitCode 返回值（对齐原版 main_hook.m L26-28）
    // 返回 NO 表示没有 current 日志视图（JVM 未启动或已退出），
    // 此时不应进入 sleep/dispatch_group_wait，直接 return 让进程正常退出。
    if (![PLLogOutputView handleExitCode:code]) {
        return;
    }

    if (fatalExitGroup != nil) {
        // Likely other threads are crashing, put them to sleep
        sleep(INT_MAX);
    }
    fatalExitGroup = dispatch_group_create();
    dispatch_group_enter(fatalExitGroup);
    dispatch_group_wait(fatalExitGroup, DISPATCH_TIME_FOREVER);
}

void hooked_abort() {
    NSLog(@"abort() called");
    handle_fatal_exit(SIGABRT);
    orig_abort();
}

void hooked___assert_rtn(const char* func, const char* file, int line, const char* failedexpr)
{
    if (func == NULL) {
        fprintf(stderr, "Assertion failed: (%s), file %s, line %d.\n", failedexpr, file, line);
    } else {
        fprintf(stderr, "Assertion failed: (%s), function %s, file %s, line %d.\n", failedexpr, func, file, line);
    }
    hooked_abort();
}

void hooked_exit(int code) {
    NSLog(@"exit(%d) called", code);
    if (code == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication.sharedApplication performSelector:@selector(suspend)];
        });
        usleep(100*1000);
        orig_exit(0);
        return;
    }
    handle_fatal_exit(code);

    orig_exit(code);
}

void* hooked_dlopen(const char* path, int mode) {
    // === iOS 26+ PPL bypass 分支（从原版项目移植）===
    // 当设备处于 FORCE_MIRRORED 且无 TXM 时，使用硬件断点 + Mach 异常的
    // PPL bypass 方式加载 home/tmp 目录下的 dylib（绕过 iOS 26+ 的 PPL 签名
    // 校验）。此分支必须使用 musttail 尾调用 hooked_dlopen_26_ppl，因为后者
    // 需要读取本函数的返回地址来解析 @loader_path。
    BOOL shouldUseDyldBypass26PPL = NO;
    if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED)) {
        shouldUseDyldBypass26PPL = hwRedirectOrig[0] && !DeviceHasJITFlags(JIT_FLAG_HAS_TXM);
    }
    if (shouldUseDyldBypass26PPL) {
        const char *home = getenv("HOME");
        const char *tmpdir = getenv("TMPDIR");
        char fullpath[PATH_MAX];
        if (path && realpath(path, fullpath) &&
            (strstr(fullpath, home) || (tmpdir && strstr(fullpath, tmpdir)))) {
            __attribute__((musttail)) return hooked_dlopen_26_ppl(path, mode);
        }
    }

    // === 现有 SDL3/libOSMesa 检测 + Vulkan stride fix 逻辑（保留不变）===
    const char *home = getenv("HOME");
    // Only proceed to check if dylib is in the home dir
    char fullpath[PATH_MAX];
    if (!path || !realpath(path, fullpath) || !strstr(fullpath, home)) {
        // 即使 path 不在 home 目录，也检查是否是 libSDL3.dylib
        // MC 26.3-snapshot-4+ 加载 libSDL3.dylib 后，需要立即对 SDL_CreateWindow
        // 进行 fishhook 符号重绑定（dlsym hook 对 MC 的 SDL3 调用方式无效）
        void *handle = orig_dlopen(path, mode);
        if (handle && path && strstr(path, "libSDL3")) {
            NSLog(@"[SDL3 Hook] libSDL3.dylib loaded via dlopen, rebinding SDL_CreateWindow via fishhook");
            // 重新注册所有 hook，包括 SDL_CreateWindow
            init_hookFunctions();
        }
        // Zink stride fix：libOSMesa 加载后重新执行 fishhook，捕获其对
        // vkGetInstanceProcAddr / vkGetDeviceProcAddr 的符号引用
        // （installZinkStrideFix 在 libOSMesa 加载前调用，初次 rebind 无法
        //  捕获 libOSMesa image 内的引用；必须在其加载后再次 rebind）
        if (handle && path && strstr(path, "libOSMesa") && g_zinkStrideFixActive) {
            NSLog(@"[ZinkStrideFix] libOSMesa loaded via dlopen, re-rebinding Vulkan symbols");
            rebindZinkStrideFixForNewImage();
        }
        return handle;
    }

    PLPatchMachOPlatformForFile(path);
    void *handle = orig_dlopen(path, mode);
    if (handle && path && strstr(path, "libSDL3")) {
        NSLog(@"[SDL3 Hook] libSDL3.dylib loaded via dlopen (home), rebinding SDL_CreateWindow via fishhook");
        init_hookFunctions();
    }
    if (handle && path && strstr(path, "libOSMesa") && g_zinkStrideFixActive) {
        NSLog(@"[ZinkStrideFix] libOSMesa loaded via dlopen (home), re-rebinding Vulkan symbols");
        rebindZinkStrideFixForNewImage();
    }
    return handle;
}

// ============================================================================
// Vulkan vertex stride alignment fix（zink + MoltenVK + Mesa 25.0.7）
// ============================================================================
// 问题：
//   Metal API 硬性要求 vertex attribute binding stride 必须 4 字节对齐。
//   Mesa 25.0.7 zink 移除了 Mesa 21.0.0 中存在的 stride 对齐 workaround。
//   当光影包（如 BSL）触发管线重建且 stride 非 4 对齐时，MoltenVK 返回
//   VK_ERROR_INITIALIZATION_FAILED，zink 的 update_gfx_pipeline 未处理该
//   错误，使用 NULL pipeline 句柄导致 SIGSEGV。
//
// 解决方案：
//   通过 dlsym 拦截 + fishhook 双重机制 hook vkGetInstanceProcAddr /
//   vkGetDeviceProcAddr。当 zink 请求 vkCreateGraphicsPipelines 时返回
//   我们的 wrapper。wrapper 在调用真实函数前将 vertex binding stride
//   向上对齐到 4 字节边界。
//
//   此 fix 仅在 zink 渲染器（libOSMesa）被选中时激活。

// 最小 Vulkan 类型定义（布局严格匹配 vulkan_core.h，64 位平台）
typedef int32_t VkZResult;
typedef struct VkZInstance_T* VkZInstance;
typedef struct VkZDevice_T* VkZDevice;
typedef struct VkZCommandBuffer_T* VkZCommandBuffer;
typedef struct VkZPipelineCache_T* VkZPipelineCache;
typedef struct VkZPipeline_T* VkZPipeline;
typedef struct VkZPipelineLayout_T* VkZPipelineLayout;
typedef struct VkZRenderPass_T* VkZRenderPass;

#define VK_Z_SUCCESS 0
#define VK_Z_ERROR_INITIALIZATION_FAILED (-3)

// VkPipelineBindPoint
typedef enum {
    VK_Z_PIPELINE_BIND_POINT_GRAPHICS = 0,
    VK_Z_PIPELINE_BIND_POINT_COMPUTE = 1,
} VkZPipelineBindPoint;

typedef enum {
    VK_Z_VERTEX_INPUT_RATE_VERTEX = 0,
    VK_Z_VERTEX_INPUT_RATE_INSTANCE = 1,
} VkZVertexInputRate;

typedef struct {
    uint32_t binding;
    uint32_t stride;
    VkZVertexInputRate inputRate;
} VkZVertexInputBindingDescription;

typedef struct {
    uint32_t location;
    uint32_t binding;
    int32_t format;
    uint32_t offset;
} VkZVertexInputAttributeDescription;

typedef struct {
    int32_t sType;                   // VkStructureType
    const void* pNext;
    uint32_t flags;
    uint32_t vertexBindingDescriptionCount;
    const VkZVertexInputBindingDescription* pVertexBindingDescriptions;
    uint32_t vertexAttributeDescriptionCount;
    const VkZVertexInputAttributeDescription* pVertexAttributeDescriptions;
} VkZPipelineVertexInputStateCreateInfo;

// VkGraphicsPipelineCreateInfo 完整布局（匹配 vulkan_core.h，64 位）
typedef struct {
    int32_t sType;                   // VkStructureType
    const void* pNext;
    uint32_t flags;
    uint32_t stageCount;
    const void* pStages;             // const VkPipelineShaderStageCreateInfo*
    const VkZPipelineVertexInputStateCreateInfo* pVertexInputState;
    const void* pInputAssemblyState;
    const void* pTessellationState;
    const void* pViewportState;
    const void* pRasterizationState;
    const void* pMultisampleState;
    const void* pDepthStencilState;
    const void* pColorBlendState;
    const void* pDynamicState;
    VkZPipelineLayout layout;
    VkZRenderPass renderPass;
    uint32_t subpass;
    VkZPipeline basePipelineHandle;
    int32_t basePipelineIndex;
} VkZGraphicsPipelineCreateInfo;

typedef VkZResult (*PFN_zkCreateGraphicsPipelines)(
    VkZDevice, VkZPipelineCache, uint32_t,
    const VkZGraphicsPipelineCreateInfo*, const void*, VkZPipeline*);
typedef void* (*PFN_zkGetInstanceProcAddr)(VkZInstance, const char*);
typedef void* (*PFN_zkGetDeviceProcAddr)(VkZDevice, const char*);

// vkCmd* 函数指针类型（用于 dummy pipeline skip draws）
// 参数数量严格匹配 Vulkan 标准签名（vulkan_core.h），避免与函数实现调用不一致
typedef void (*PFN_zkCmdBindPipeline)(VkZCommandBuffer, VkZPipelineBindPoint, VkZPipeline);
typedef void (*PFN_zkCmdDraw)(VkZCommandBuffer, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void (*PFN_zkCmdDrawIndexed)(VkZCommandBuffer, uint32_t, uint32_t, uint32_t, int32_t, uint32_t);
// vkCmdDrawIndirect(cmd, buffer, offset, drawCount, stride) — 5 个参数
typedef void (*PFN_zkCmdDrawIndirect)(VkZCommandBuffer, uint64_t, uint64_t, uint32_t, uint32_t);
typedef void (*PFN_zkCmdDrawIndexedIndirect)(VkZCommandBuffer, uint64_t, uint64_t, uint32_t, uint32_t);
// vkCmdDrawIndirectCount(cmd, buffer, offset, countBuffer, countBufferOffset, maxDrawCount, stride) — 7 个参数
typedef void (*PFN_zkCmdDrawIndirectCount)(VkZCommandBuffer, uint64_t, uint64_t, uint64_t, uint64_t, uint32_t, uint32_t);
typedef void (*PFN_zkCmdDrawIndexedIndirectCount)(VkZCommandBuffer, uint64_t, uint64_t, uint64_t, uint64_t, uint32_t, uint32_t);
// vkDestroyPipeline(device, pipeline, pAllocator) — 3 个参数
// 必须 hook：zink 销毁 dummy pipeline 时，MoltenVK 解引用 magic handle 会崩溃
typedef void (*PFN_zkDestroyPipeline)(VkZDevice, VkZPipeline, const void*);

// Stride fix 状态（g_zinkStrideFixActive 已在文件前部前向声明）
static PFN_zkGetInstanceProcAddr g_real_vkGetInstanceProcAddr = NULL;
static PFN_zkGetDeviceProcAddr g_real_vkGetDeviceProcAddr = NULL;
static PFN_zkCreateGraphicsPipelines g_real_vkCreateGraphicsPipelines = NULL;

// vkCmd* 真实函数指针（dummy pipeline skip draws 需要）
static PFN_zkCmdBindPipeline g_real_vkCmdBindPipeline = NULL;
static PFN_zkCmdDraw g_real_vkCmdDraw = NULL;
static PFN_zkCmdDrawIndexed g_real_vkCmdDrawIndexed = NULL;
static PFN_zkCmdDrawIndirect g_real_vkCmdDrawIndirect = NULL;
static PFN_zkCmdDrawIndexedIndirect g_real_vkCmdDrawIndexedIndirect = NULL;
static PFN_zkCmdDrawIndirectCount g_real_vkCmdDrawIndirectCount = NULL;
static PFN_zkCmdDrawIndexedIndirectCount g_real_vkCmdDrawIndexedIndirectCount = NULL;
// vkDestroyPipeline 真实函数指针（dummy pipeline 销毁需要）
static PFN_zkDestroyPipeline g_real_vkDestroyPipeline = NULL;

// ============================================================================
// Dummy pipeline 机制（修复 zink + Mesa 25.0.7 光影 SIGSEGV）
// ============================================================================
// 问题：
//   Mesa 25.0.7 zink 比 21.0.0 更严格地校验 SPIR-V shader 接口。
//   当光影包（如 BSL、Mellow Shader）的 fragment shader 声明了 vertex shader
//   未写入的 input（如 user(locn1_2)），MoltenVK 在 vkCreateGraphicsPipelines
//   时返回 VK_ERROR_INITIALIZATION_FAILED。
//
//   zink 的 update_gfx_pipeline 未正确处理此失败：
//   Vulkan spec 规定 vkCreateGraphicsPipelines 失败时 pPipelines[i] 设为
//   VK_NULL_HANDLE，zink 后续使用 NULL pipeline 句柄导致 SIGSEGV。
//
// 解决方案（dummy pipeline + skip draws）：
//   1. 当 vkCreateGraphicsPipelines 失败时，不返回失败，而是返回 VK_SUCCESS
//      并为每个失败的 pipeline 分配一个 dummy 句柄（非 NULL 的 magic 值）。
//   2. 维护 dummy pipeline 集合。
//   3. Hook vkCmdBindPipeline：跟踪当前绑定的 pipeline，如果是 dummy 则跳过绑定。
//   4. Hook vkCmdDraw*：如果当前绑定的 pipeline 是 dummy，跳过绘制。
//
//   这样 zink 认为 pipeline 创建成功，不会 SIGSEGV；
//   失败的 pipeline 对应的几何体不会被绘制（黑屏/缺失，但不崩溃）。
//   成功的 pipeline 正常渲染，光影效果保留。

#define ZINK_DUMMY_PIPELINE_MAGIC 0xDEAD0000ULL
#define ZINK_DUMMY_PIPELINE_MAX 4096

// dummy pipeline 集合（使用简单数组，线性查找；dummy pipeline 数量通常很少）
static uintptr_t g_dummyPipelines[ZINK_DUMMY_PIPELINE_MAX];
static uint32_t g_dummyPipelineCount = 0;
// 当前绑定的 graphics pipeline（用于判断 draw 是否应该跳过）
// 注意：VkCommandBuffer 可能多个，但 zink 单线程渲染，用全局变量足够
static VkZPipeline g_currentBoundGraphicsPipeline = NULL;

/// 判断 pipeline 是否为 dummy
static BOOL isDummyPipeline(VkZPipeline pipeline) {
    if (!pipeline) return NO;
    uintptr_t val = (uintptr_t)pipeline;
    if ((val & 0xFFFF0000ULL) != ZINK_DUMMY_PIPELINE_MAGIC) return NO;
    // 二分查找或线性查找（dummy pipeline 数量通常 <100，线性查找足够）
    for (uint32_t i = 0; i < g_dummyPipelineCount; i++) {
        if (g_dummyPipelines[i] == val) return YES;
    }
    return NO;
}

/// 分配一个新的 dummy pipeline 句柄
static VkZPipeline allocDummyPipeline(void) {
    if (g_dummyPipelineCount >= ZINK_DUMMY_PIPELINE_MAX) {
        // 溢出：复用第一个（极端情况，几乎不会发生）
        NSLog(@"[ZinkStrideFix] WARNING: dummy pipeline pool exhausted, reusing slot 0");
        return (VkZPipeline)g_dummyPipelines[0];
    }
    uintptr_t handle = ZINK_DUMMY_PIPELINE_MAGIC | (g_dummyPipelineCount + 1);
    g_dummyPipelines[g_dummyPipelineCount++] = handle;
    return (VkZPipeline)handle;
}

// 前向声明（供 hooked_dlsym 使用）
static void* amethyst_vkGetInstanceProcAddr(VkZInstance instance, const char* pName);
static void* amethyst_vkGetDeviceProcAddr(VkZDevice device, const char* pName);
static VkZResult amethyst_vkCreateGraphicsPipelines(
    VkZDevice device, VkZPipelineCache pipelineCache, uint32_t createInfoCount,
    const VkZGraphicsPipelineCreateInfo* pCreateInfos, const void* pAllocator,
    VkZPipeline* pPipelines);
static void amethyst_vkCmdBindPipeline(VkZCommandBuffer cmd, VkZPipelineBindPoint bp, VkZPipeline pipeline);
static void amethyst_vkCmdDraw(VkZCommandBuffer cmd, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance);
static void amethyst_vkCmdDrawIndexed(VkZCommandBuffer cmd, uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t vertexOffset, uint32_t firstInstance);
static void amethyst_vkCmdDrawIndirect(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint32_t drawCount, uint32_t stride);
static void amethyst_vkCmdDrawIndexedIndirect(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint32_t drawCount, uint32_t stride);
static void amethyst_vkCmdDrawIndirectCount(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint64_t countBuffer, uint64_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride);
static void amethyst_vkCmdDrawIndexedIndirectCount(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint64_t countBuffer, uint64_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride);
static void amethyst_vkDestroyPipeline(VkZDevice device, VkZPipeline pipeline, const void* pAllocator);

// ============================================================================
// UINT→SINT 顶点属性格式转换（修复 MTLAttributeFormatUShort3 转换失败）
// ============================================================================
// 问题：
//   MoltenVK 编译 pipeline 时，若 vertex attribute 使用 UINT 格式（如
//   VK_FORMAT_R16G16B16_UINT → MTLAttributeFormatUShort3），但 shader 声明的
//   input 是有符号整数类型（int/ivec3），Metal 无法自动转换格式，返回
//   VK_ERROR_INITIALIZATION_FAILED：
//   "Cannot convert attribute from MTLAttributeFormatUShort3 to a signed integer type."
//
//   此问题在 Iris 光影 + Mesa 25.0.7 zink 下频发，导致实体渲染 pipeline 创建
//   失败，被 dummy pipeline fallback 替换后实体不渲染（黑屏/缺失）。
//
// 解决方案：
//   当 pipeline 首次创建失败时，重试一次：将所有 UINT 格式的 vertex attribute
//   转换为对应的 SINT 格式（如 R16G16B16_UINT → R16G16B16_SINT）。
//   Metal 会以有符号方式解析字节，与 shader 期望匹配。
//   对于大多数顶点属性（骨骼索引、坐标等），值通常很小，signed/unsigned 解析
//   结果一致，不会引入渲染错误。

/// 判断 Vulkan 格式是否为 UINT 类型
/// Vulkan 格式枚举值参考 vulkan_core.h：
///   R8_UINT=9, R8G8_UINT=11, R8G8B8_UINT=13, R8G8B8A8_UINT=42
///   R16_UINT=76, R16G16_UINT=78, R16G16B16_UINT=80, R16G16B16A16_UINT=82
///   R32_UINT=96, R32G32_UINT=98, R32G32B32_UINT=100, R32G32B32A32_UINT=102
static BOOL isVkUIntFormat(int32_t format) {
    switch (format) {
        case 9:   // VK_FORMAT_R8_UINT
        case 11:  // VK_FORMAT_R8G8_UINT
        case 13:  // VK_FORMAT_R8G8B8_UINT
        case 42:  // VK_FORMAT_R8G8B8A8_UINT
        case 76:  // VK_FORMAT_R16_UINT
        case 78:  // VK_FORMAT_R16G16_UINT
        case 80:  // VK_FORMAT_R16G16B16_UINT
        case 82:  // VK_FORMAT_R16G16B16A16_UINT
        case 96:  // VK_FORMAT_R32_UINT
        case 98:  // VK_FORMAT_R32G32_UINT
        case 100: // VK_FORMAT_R32G32B32_UINT
        case 102: // VK_FORMAT_R32G32B32A32_UINT
            return YES;
        default:
            return NO;
    }
}

/// 将 UINT 格式转换为对应的 SINT 格式
/// Vulkan 格式枚举中，UINT 和 SINT 是连续的（UINT+1 = SINT）：
///   R8_UINT(9) → R8_SINT(10), R8G8_UINT(11) → R8G8_SINT(12), ...
static int32_t convertVkUIntToSIntFormat(int32_t format) {
    switch (format) {
        case 9:   return 10;   // R8_UINT → R8_SINT
        case 11:  return 12;   // R8G8_UINT → R8G8_SINT
        case 13:  return 14;   // R8G8B8_UINT → R8G8B8_SINT
        case 42:  return 43;   // R8G8B8A8_UINT → R8G8B8A8_SINT
        case 76:  return 77;   // R16_UINT → R16_SINT
        case 78:  return 79;   // R16G16_UINT → R16G16_SINT
        case 80:  return 81;   // R16G16B16_UINT → R16G16B16_SINT
        case 82:  return 83;   // R16G16B16A16_UINT → R16G16B16A16_SINT
        case 96:  return 97;   // R32_UINT → R32_SINT
        case 98:  return 99;   // R32G32_UINT → R32G32_SINT
        case 100: return 101;  // R32G32B32_UINT → R32G32B32_SINT
        case 102: return 103;  // R32G32B32A32_UINT → R32G32B32A32_SINT
        default:  return format;
    }
}

/// 检查 pipeline create infos 中是否存在 UINT 格式的 vertex attribute
static BOOL pipelineCreateInfosHaveUIntFormat(
    uint32_t createInfoCount,
    const VkZGraphicsPipelineCreateInfo* pCreateInfos)
{
    for (uint32_t i = 0; i < createInfoCount; i++) {
        const VkZPipelineVertexInputStateCreateInfo* vis = pCreateInfos[i].pVertexInputState;
        if (!vis || !vis->pVertexAttributeDescriptions) continue;
        for (uint32_t j = 0; j < vis->vertexAttributeDescriptionCount; j++) {
            if (isVkUIntFormat(vis->pVertexAttributeDescriptions[j].format)) {
                return YES;
            }
        }
    }
    return NO;
}

/// 重试 pipeline 创建：将 UINT 顶点属性格式转换为 SINT
/// 可选地对齐 stride（用于与 stride 对齐修复组合使用）
/// 返回真实函数的调用结果
static VkZResult retryPipelineWithSIntFormats(
    VkZDevice device, VkZPipelineCache pipelineCache, uint32_t createInfoCount,
    const VkZGraphicsPipelineCreateInfo* pCreateInfos, const void* pAllocator,
    VkZPipeline* pPipelines,
    BOOL alsoAlignStrides)
{
    if (!g_real_vkCreateGraphicsPipelines) {
        return VK_Z_ERROR_INITIALIZATION_FAILED;
    }

    // 如果没有 UINT 格式，重试无意义
    if (!pipelineCreateInfosHaveUIntFormat(createInfoCount, pCreateInfos)) {
        return VK_Z_ERROR_INITIALIZATION_FAILED;
    }

    NSLog(@"[ZinkStrideFix] Retrying pipeline creation with UINT→SINT format conversion%s",
          alsoAlignStrides ? " + stride alignment" : "");

    // 深拷贝并应用格式转换（可选 + stride 对齐）
    VkZGraphicsPipelineCreateInfo* newCreateInfos = malloc(sizeof(VkZGraphicsPipelineCreateInfo) * createInfoCount);
    VkZPipelineVertexInputStateCreateInfo* newVIS = malloc(sizeof(VkZPipelineVertexInputStateCreateInfo) * createInfoCount);
    VkZVertexInputBindingDescription** allocedBindings = calloc(createInfoCount, sizeof(VkZVertexInputBindingDescription*));
    VkZVertexInputAttributeDescription** allocedAttrs = calloc(createInfoCount, sizeof(VkZVertexInputAttributeDescription*));

    memcpy(newCreateInfos, pCreateInfos, sizeof(VkZGraphicsPipelineCreateInfo) * createInfoCount);

    for (uint32_t i = 0; i < createInfoCount; i++) {
        const VkZPipelineVertexInputStateCreateInfo* vis = pCreateInfos[i].pVertexInputState;
        if (!vis) continue;

        newVIS[i] = *vis;

        // 格式转换：UINT → SINT
        if (vis->pVertexAttributeDescriptions && vis->vertexAttributeDescriptionCount > 0) {
            uint32_t attrCount = vis->vertexAttributeDescriptionCount;
            VkZVertexInputAttributeDescription* newAttrs = malloc(sizeof(VkZVertexInputAttributeDescription) * attrCount);
            memcpy(newAttrs, vis->pVertexAttributeDescriptions, sizeof(VkZVertexInputAttributeDescription) * attrCount);
            for (uint32_t j = 0; j < attrCount; j++) {
                if (isVkUIntFormat(newAttrs[j].format)) {
                    int32_t oldFmt = newAttrs[j].format;
                    newAttrs[j].format = convertVkUIntToSIntFormat(newAttrs[j].format);
                    NSLog(@"[ZinkStrideFix] Pipeline %u attr %u: format %d -> %d (UINT→SINT)",
                          i, j, oldFmt, newAttrs[j].format);
                }
            }
            allocedAttrs[i] = newAttrs;
            newVIS[i].pVertexAttributeDescriptions = newAttrs;
        }

        // 可选：stride 对齐
        if (alsoAlignStrides && vis->pVertexBindingDescriptions) {
            BOOL pipelineNeedsAlignment = NO;
            for (uint32_t j = 0; j < vis->vertexBindingDescriptionCount; j++) {
                if (vis->pVertexBindingDescriptions[j].stride & 3) {
                    pipelineNeedsAlignment = YES;
                    break;
                }
            }
            if (pipelineNeedsAlignment) {
                uint32_t bindingCount = vis->vertexBindingDescriptionCount;
                VkZVertexInputBindingDescription* newBindings = malloc(sizeof(VkZVertexInputBindingDescription) * bindingCount);
                memcpy(newBindings, vis->pVertexBindingDescriptions, sizeof(VkZVertexInputBindingDescription) * bindingCount);
                for (uint32_t j = 0; j < bindingCount; j++) {
                    uint32_t oldStride = newBindings[j].stride;
                    uint32_t newStride = (oldStride + 3) & ~3u;
                    if (newStride != oldStride) {
                        NSLog(@"[ZinkStrideFix] Pipeline %u binding %u: stride %u -> %u",
                              i, j, oldStride, newStride);
                        newBindings[j].stride = newStride;
                    }
                }
                allocedBindings[i] = newBindings;
                newVIS[i].pVertexBindingDescriptions = newBindings;
            }
        }

        newCreateInfos[i].pVertexInputState = &newVIS[i];
    }

    VkZResult result = g_real_vkCreateGraphicsPipelines(device, pipelineCache, createInfoCount, newCreateInfos, pAllocator, pPipelines);

    for (uint32_t i = 0; i < createInfoCount; i++) {
        if (allocedBindings[i]) free(allocedBindings[i]);
        if (allocedAttrs[i]) free(allocedAttrs[i]);
    }
    free(allocedAttrs);
    free(allocedBindings);
    free(newVIS);
    free(newCreateInfos);

    return result;
}

/// 仅对齐 vertex binding stride 到 4 字节（不做格式转换），调用真实函数
/// 供 amethyst_vkCreateGraphicsPipelines 在策略 3 中使用
static VkZResult createPipelinesWithAlignedStrides(
    VkZDevice device, VkZPipelineCache pipelineCache, uint32_t createInfoCount,
    const VkZGraphicsPipelineCreateInfo* pCreateInfos, const void* pAllocator,
    VkZPipeline* pPipelines)
{
    if (!g_real_vkCreateGraphicsPipelines) {
        return VK_Z_ERROR_INITIALIZATION_FAILED;
    }

    NSLog(@"[ZinkStrideFix] Aligning vertex binding strides for %u pipelines", createInfoCount);

    VkZGraphicsPipelineCreateInfo* newCreateInfos = malloc(sizeof(VkZGraphicsPipelineCreateInfo) * createInfoCount);
    VkZPipelineVertexInputStateCreateInfo* newVIS = malloc(sizeof(VkZPipelineVertexInputStateCreateInfo) * createInfoCount);
    VkZVertexInputBindingDescription** allocedBindings = calloc(createInfoCount, sizeof(VkZVertexInputBindingDescription*));

    memcpy(newCreateInfos, pCreateInfos, sizeof(VkZGraphicsPipelineCreateInfo) * createInfoCount);

    for (uint32_t i = 0; i < createInfoCount; i++) {
        const VkZPipelineVertexInputStateCreateInfo* vis = pCreateInfos[i].pVertexInputState;
        if (!vis || !vis->pVertexBindingDescriptions) continue;

        BOOL pipelineNeedsAlignment = NO;
        for (uint32_t j = 0; j < vis->vertexBindingDescriptionCount; j++) {
            if (vis->pVertexBindingDescriptions[j].stride & 3) {
                pipelineNeedsAlignment = YES;
                break;
            }
        }
        if (!pipelineNeedsAlignment) continue;

        uint32_t bindingCount = vis->vertexBindingDescriptionCount;
        VkZVertexInputBindingDescription* newBindings = malloc(sizeof(VkZVertexInputBindingDescription) * bindingCount);
        memcpy(newBindings, vis->pVertexBindingDescriptions, sizeof(VkZVertexInputBindingDescription) * bindingCount);
        for (uint32_t j = 0; j < bindingCount; j++) {
            uint32_t oldStride = newBindings[j].stride;
            uint32_t newStride = (oldStride + 3) & ~3u;
            if (newStride != oldStride) {
                NSLog(@"[ZinkStrideFix] Pipeline %u binding %u: stride %u -> %u", i, j, oldStride, newStride);
                newBindings[j].stride = newStride;
            }
        }
        allocedBindings[i] = newBindings;

        newVIS[i] = *vis;
        newVIS[i].pVertexBindingDescriptions = newBindings;
        newCreateInfos[i].pVertexInputState = &newVIS[i];
    }

    VkZResult result = g_real_vkCreateGraphicsPipelines(device, pipelineCache, createInfoCount, newCreateInfos, pAllocator, pPipelines);

    for (uint32_t i = 0; i < createInfoCount; i++) {
        if (allocedBindings[i]) free(allocedBindings[i]);
    }
    free(allocedBindings);
    free(newVIS);
    free(newCreateInfos);

    return result;
}

/// vkCreateGraphicsPipelines wrapper：尝试多种修复策略确保 pipeline 创建成功
///
/// 修复策略（按顺序尝试）：
///   1. 原始 stride 直接创建（MoltenVK 1.2.9+ 可能已支持未对齐 stride）
///   2. UINT→SINT 格式转换 + 原始 stride（修复 MTLAttributeFormatUShort3 转换错误）
///   3. stride 4 字节对齐（修复 Metal API 硬性要求）
///   4. UINT→SINT 格式转换 + stride 对齐（组合修复）
///   5. dummy pipeline fallback（避免 NULL pipeline 导致 SIGSEGV）
///
/// 关键修复（实体渲染错乱）：
///   之前的实现总是先做 stride 对齐（54→56），但 vertex buffer 数据仍按原始
///   stride 54 排列，导致 MoltenVK 按对齐 stride 56 读取数据但数据布局不匹配，
///   造成实体渲染错乱。
///   新实现优先尝试原始 stride，只有当 MoltenVK 拒绝未对齐 stride 时才回退到
///   stride 对齐。这样在支持未对齐 stride 的 MoltenVK 版本上，stride 与数据
///   布局匹配，渲染正确。
static VkZResult amethyst_vkCreateGraphicsPipelines(
    VkZDevice device, VkZPipelineCache pipelineCache, uint32_t createInfoCount,
    const VkZGraphicsPipelineCreateInfo* pCreateInfos, const void* pAllocator,
    VkZPipeline* pPipelines)
{
    // 首次调用时解析真实函数指针
    if (!g_real_vkCreateGraphicsPipelines) {
        if (g_real_vkGetDeviceProcAddr) {
            g_real_vkCreateGraphicsPipelines = (PFN_zkCreateGraphicsPipelines)
                g_real_vkGetDeviceProcAddr(device, "vkCreateGraphicsPipelines");
        }
        if (!g_real_vkCreateGraphicsPipelines && g_real_vkGetInstanceProcAddr) {
            g_real_vkCreateGraphicsPipelines = (PFN_zkCreateGraphicsPipelines)
                g_real_vkGetInstanceProcAddr((VkZInstance)NULL, "vkCreateGraphicsPipelines");
        }
        if (!g_real_vkCreateGraphicsPipelines) {
            g_real_vkCreateGraphicsPipelines = (PFN_zkCreateGraphicsPipelines)
                amethyst_orig_dlsym(RTLD_DEFAULT, "vkCreateGraphicsPipelines");
        }
        NSLog(@"[ZinkStrideFix] real vkCreateGraphicsPipelines = %p", (void*)g_real_vkCreateGraphicsPipelines);
    }

    if (!g_real_vkCreateGraphicsPipelines) {
        NSLog(@"[ZinkStrideFix] FATAL: real vkCreateGraphicsPipelines is NULL");
        return VK_Z_ERROR_INITIALIZATION_FAILED;
    }

    // 预检查：是否需要 stride 对齐 / 是否有 UINT 格式
    BOOL needsAlignment = NO;
    for (uint32_t i = 0; i < createInfoCount; i++) {
        const VkZPipelineVertexInputStateCreateInfo* vis = pCreateInfos[i].pVertexInputState;
        if (!vis || !vis->pVertexBindingDescriptions) continue;
        for (uint32_t j = 0; j < vis->vertexBindingDescriptionCount; j++) {
            if (vis->pVertexBindingDescriptions[j].stride & 3) {
                needsAlignment = YES;
                break;
            }
        }
        if (needsAlignment) break;
    }
    BOOL hasUIntFormat = pipelineCreateInfosHaveUIntFormat(createInfoCount, pCreateInfos);

    // ===== 策略 1：原始 stride 直接创建 =====
    // 优先尝试原始 stride，保持 stride 与 vertex buffer 数据布局匹配。
    // MoltenVK 1.2.9+ 可能通过 setVertexBuffer:offset:attributeStride:atIndex:
    // 或其他机制支持未对齐 stride。这是修复实体渲染错乱的关键。
    {
        VkZResult result = g_real_vkCreateGraphicsPipelines(device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines);
        if (result == VK_Z_SUCCESS) {
            if (needsAlignment) {
                NSLog(@"[ZinkStrideFix] Pipeline created with original (unaligned) stride - MoltenVK accepted");
            }
            return result;
        }
        NSLog(@"[ZinkStrideFix] Strategy 1 (original stride) failed: %d", result);
        // 清理 pPipelines（失败时 MoltenVK 可能已部分设置）
        for (uint32_t i = 0; i < createInfoCount; i++) pPipelines[i] = NULL;
    }

    // ===== 策略 2：UINT→SINT 格式转换 + 原始 stride =====
    // 修复 MTLAttributeFormatUShort3 转换错误，保持原始 stride
    if (hasUIntFormat) {
        NSLog(@"[ZinkStrideFix] Strategy 2: UINT→SINT format conversion (original stride)");
        VkZResult retryResult = retryPipelineWithSIntFormats(
            device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines, NO);
        if (retryResult == VK_Z_SUCCESS) {
            NSLog(@"[ZinkStrideFix] Strategy 2 succeeded (UINT→SINT, original stride)");
            return retryResult;
        }
        NSLog(@"[ZinkStrideFix] Strategy 2 failed: %d", retryResult);
        for (uint32_t i = 0; i < createInfoCount; i++) pPipelines[i] = NULL;
    }

    // ===== 策略 3：stride 4 字节对齐 =====
    // MoltenVK 拒绝未对齐 stride 时，回退到 stride 对齐。
    // 注意：这可能导致 stride 与 vertex buffer 数据布局不匹配，引发渲染错乱。
    // 但可以避免 pipeline 创建失败导致的 SIGSEGV。
    NSLog(@"[ZinkStrideFix] Strategy 3: stride 4-byte alignment");
    {
        VkZResult result = createPipelinesWithAlignedStrides(
            device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines);
        if (result == VK_Z_SUCCESS) {
            NSLog(@"[ZinkStrideFix] Strategy 3 succeeded (stride alignment)");
            return result;
        }
        NSLog(@"[ZinkStrideFix] Strategy 3 failed: %d", result);
        for (uint32_t i = 0; i < createInfoCount; i++) pPipelines[i] = NULL;
    }

    // ===== 策略 4：UINT→SINT 格式转换 + stride 对齐 =====
    if (hasUIntFormat) {
        NSLog(@"[ZinkStrideFix] Strategy 4: UINT→SINT + stride alignment");
        VkZResult retryResult = retryPipelineWithSIntFormats(
            device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines, YES);
        if (retryResult == VK_Z_SUCCESS) {
            NSLog(@"[ZinkStrideFix] Strategy 4 succeeded (UINT→SINT + stride alignment)");
            return retryResult;
        }
        NSLog(@"[ZinkStrideFix] Strategy 4 failed: %d", retryResult);
        for (uint32_t i = 0; i < createInfoCount; i++) pPipelines[i] = NULL;
    }

    // ===== 策略 5：dummy pipeline fallback =====
    // 所有修复策略都失败，分配 dummy pipeline 避免 NULL pipeline 导致 SIGSEGV。
    // dummy pipeline 的 draw 调用会被我们的 hook 跳过（实体不渲染，但不崩溃）。
    NSLog(@"[ZinkStrideFix] All strategies failed, applying dummy pipeline fallback");
    for (uint32_t i = 0; i < createInfoCount; i++) {
        if (!pPipelines[i]) {
            pPipelines[i] = allocDummyPipeline();
            NSLog(@"[ZinkStrideFix] Pipeline %u: allocated dummy handle %p", i, (void*)pPipelines[i]);
        }
    }
    return VK_Z_SUCCESS;
}

/// vkGetInstanceProcAddr wrapper
/// 拦截 vkGetDeviceProcAddr、vkCreateGraphicsPipelines、vkCmd* 请求，返回我们的 hook
static void* amethyst_vkGetInstanceProcAddr(VkZInstance instance, const char* pName) {
    if (pName) {
        if (strcmp(pName, "vkGetDeviceProcAddr") == 0) {
            if (!g_real_vkGetDeviceProcAddr && g_real_vkGetInstanceProcAddr) {
                g_real_vkGetDeviceProcAddr = (PFN_zkGetDeviceProcAddr)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkGetDeviceProcAddr;
        }
        if (strcmp(pName, "vkCreateGraphicsPipelines") == 0) {
            if (!g_real_vkCreateGraphicsPipelines && g_real_vkGetInstanceProcAddr) {
                g_real_vkCreateGraphicsPipelines = (PFN_zkCreateGraphicsPipelines)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCreateGraphicsPipelines;
        }
        // vkCmd* hooks（dummy pipeline skip draws）
        if (strcmp(pName, "vkCmdBindPipeline") == 0) {
            if (!g_real_vkCmdBindPipeline && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdBindPipeline = (PFN_zkCmdBindPipeline)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdBindPipeline;
        }
        if (strcmp(pName, "vkCmdDraw") == 0) {
            if (!g_real_vkCmdDraw && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDraw = (PFN_zkCmdDraw)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDraw;
        }
        if (strcmp(pName, "vkCmdDrawIndexed") == 0) {
            if (!g_real_vkCmdDrawIndexed && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDrawIndexed = (PFN_zkCmdDrawIndexed)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexed;
        }
        if (strcmp(pName, "vkCmdDrawIndirect") == 0) {
            if (!g_real_vkCmdDrawIndirect && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDrawIndirect = (PFN_zkCmdDrawIndirect)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDrawIndirect;
        }
        if (strcmp(pName, "vkCmdDrawIndexedIndirect") == 0) {
            if (!g_real_vkCmdDrawIndexedIndirect && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDrawIndexedIndirect = (PFN_zkCmdDrawIndexedIndirect)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexedIndirect;
        }
        if (strcmp(pName, "vkCmdDrawIndirectCount") == 0) {
            if (!g_real_vkCmdDrawIndirectCount && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDrawIndirectCount = (PFN_zkCmdDrawIndirectCount)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDrawIndirectCount;
        }
        if (strcmp(pName, "vkCmdDrawIndexedIndirectCount") == 0) {
            if (!g_real_vkCmdDrawIndexedIndirectCount && g_real_vkGetInstanceProcAddr) {
                g_real_vkCmdDrawIndexedIndirectCount = (PFN_zkCmdDrawIndexedIndirectCount)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexedIndirectCount;
        }
        // vkDestroyPipeline hook：dummy pipeline 销毁时跳过，避免 MoltenVK 崩溃
        if (strcmp(pName, "vkDestroyPipeline") == 0) {
            if (!g_real_vkDestroyPipeline && g_real_vkGetInstanceProcAddr) {
                g_real_vkDestroyPipeline = (PFN_zkDestroyPipeline)
                    g_real_vkGetInstanceProcAddr(instance, pName);
            }
            return (void*)amethyst_vkDestroyPipeline;
        }
    }
    if (!g_real_vkGetInstanceProcAddr) {
        return amethyst_orig_dlsym(RTLD_DEFAULT, pName);
    }
    return g_real_vkGetInstanceProcAddr(instance, pName);
}

/// vkGetDeviceProcAddr wrapper
/// 拦截 vkCreateGraphicsPipelines、vkCmd* 请求，返回我们的 hook
static void* amethyst_vkGetDeviceProcAddr(VkZDevice device, const char* pName) {
    if (pName) {
        if (strcmp(pName, "vkCreateGraphicsPipelines") == 0) {
            if (!g_real_vkCreateGraphicsPipelines && g_real_vkGetDeviceProcAddr) {
                g_real_vkCreateGraphicsPipelines = (PFN_zkCreateGraphicsPipelines)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCreateGraphicsPipelines;
        }
        // vkCmd* hooks（dummy pipeline skip draws）
        if (strcmp(pName, "vkCmdBindPipeline") == 0) {
            if (!g_real_vkCmdBindPipeline && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdBindPipeline = (PFN_zkCmdBindPipeline)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdBindPipeline;
        }
        if (strcmp(pName, "vkCmdDraw") == 0) {
            if (!g_real_vkCmdDraw && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDraw = (PFN_zkCmdDraw)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDraw;
        }
        if (strcmp(pName, "vkCmdDrawIndexed") == 0) {
            if (!g_real_vkCmdDrawIndexed && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDrawIndexed = (PFN_zkCmdDrawIndexed)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexed;
        }
        if (strcmp(pName, "vkCmdDrawIndirect") == 0) {
            if (!g_real_vkCmdDrawIndirect && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDrawIndirect = (PFN_zkCmdDrawIndirect)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDrawIndirect;
        }
        if (strcmp(pName, "vkCmdDrawIndexedIndirect") == 0) {
            if (!g_real_vkCmdDrawIndexedIndirect && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDrawIndexedIndirect = (PFN_zkCmdDrawIndexedIndirect)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexedIndirect;
        }
        if (strcmp(pName, "vkCmdDrawIndirectCount") == 0) {
            if (!g_real_vkCmdDrawIndirectCount && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDrawIndirectCount = (PFN_zkCmdDrawIndirectCount)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDrawIndirectCount;
        }
        if (strcmp(pName, "vkCmdDrawIndexedIndirectCount") == 0) {
            if (!g_real_vkCmdDrawIndexedIndirectCount && g_real_vkGetDeviceProcAddr) {
                g_real_vkCmdDrawIndexedIndirectCount = (PFN_zkCmdDrawIndexedIndirectCount)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkCmdDrawIndexedIndirectCount;
        }
        // vkDestroyPipeline hook：dummy pipeline 销毁时跳过，避免 MoltenVK 崩溃
        if (strcmp(pName, "vkDestroyPipeline") == 0) {
            if (!g_real_vkDestroyPipeline && g_real_vkGetDeviceProcAddr) {
                g_real_vkDestroyPipeline = (PFN_zkDestroyPipeline)
                    g_real_vkGetDeviceProcAddr(device, pName);
            }
            return (void*)amethyst_vkDestroyPipeline;
        }
    }
    if (!g_real_vkGetDeviceProcAddr) {
        return amethyst_orig_dlsym(RTLD_DEFAULT, pName);
    }
    return g_real_vkGetDeviceProcAddr(device, pName);
}

/// vkCmdBindPipeline hook
/// 跟踪当前绑定的 graphics pipeline，dummy pipeline 跳过实际绑定
static void amethyst_vkCmdBindPipeline(VkZCommandBuffer cmd, VkZPipelineBindPoint bp, VkZPipeline pipeline) {
    if (bp == VK_Z_PIPELINE_BIND_POINT_GRAPHICS) {
        g_currentBoundGraphicsPipeline = pipeline;
        if (isDummyPipeline(pipeline)) {
            // Dummy pipeline：跳过实际绑定，避免 MoltenVK 因无效句柄崩溃
            return;
        }
    }
    if (g_real_vkCmdBindPipeline) {
        g_real_vkCmdBindPipeline(cmd, bp, pipeline);
    }
}

/// vkCmdDraw hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDraw(VkZCommandBuffer cmd, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDraw) g_real_vkCmdDraw(cmd, vertexCount, instanceCount, firstVertex, firstInstance);
}

/// vkCmdDrawIndexed hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDrawIndexed(VkZCommandBuffer cmd, uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t vertexOffset, uint32_t firstInstance) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDrawIndexed) g_real_vkCmdDrawIndexed(cmd, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance);
}

/// vkCmdDrawIndirect hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDrawIndirect(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint32_t drawCount, uint32_t stride) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDrawIndirect) g_real_vkCmdDrawIndirect(cmd, buffer, offset, drawCount, stride);
}

/// vkCmdDrawIndexedIndirect hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDrawIndexedIndirect(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint32_t drawCount, uint32_t stride) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDrawIndexedIndirect) g_real_vkCmdDrawIndexedIndirect(cmd, buffer, offset, drawCount, stride);
}

/// vkCmdDrawIndirectCount hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDrawIndirectCount(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint64_t countBuffer, uint64_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDrawIndirectCount) g_real_vkCmdDrawIndirectCount(cmd, buffer, offset, countBuffer, countBufferOffset, maxDrawCount, stride);
}

/// vkCmdDrawIndexedIndirectCount hook：当前绑定 dummy pipeline 时跳过绘制
static void amethyst_vkCmdDrawIndexedIndirectCount(VkZCommandBuffer cmd, uint64_t buffer, uint64_t offset, uint64_t countBuffer, uint64_t countBufferOffset, uint32_t maxDrawCount, uint32_t stride) {
    if (isDummyPipeline(g_currentBoundGraphicsPipeline)) return;
    if (g_real_vkCmdDrawIndexedIndirectCount) g_real_vkCmdDrawIndexedIndirectCount(cmd, buffer, offset, countBuffer, countBufferOffset, maxDrawCount, stride);
}

/// vkDestroyPipeline hook：销毁 dummy pipeline 时跳过，避免 MoltenVK 解引用 magic handle 崩溃
/// 关键修复：切换 shaderpack 时 zink 会销毁所有旧 pipelines，包括 dummy pipeline
/// 句柄（0xDEAD0001 等）。MoltenVK 的 vkDestroyPipeline 会解引用 pipeline 指针
/// 查找内部资源，dummy handle 是无效指针，导致 SIGSEGV。
static void amethyst_vkDestroyPipeline(VkZDevice device, VkZPipeline pipeline, const void* pAllocator) {
    if (isDummyPipeline(pipeline)) {
        // Dummy pipeline：跳过销毁，避免 MoltenVK 崩溃
        // 同时从 dummy pipeline 集合中移除（避免集合无限增长）
        uintptr_t val = (uintptr_t)pipeline;
        for (uint32_t i = 0; i < g_dummyPipelineCount; i++) {
            if (g_dummyPipelines[i] == val) {
                // 用最后一个元素填补空洞（顺序无关紧要，数组只是用于查找）
                g_dummyPipelines[i] = g_dummyPipelines[g_dummyPipelineCount - 1];
                g_dummyPipelineCount--;
                break;
            }
        }
        // 如果正在销毁的 dummy pipeline 恰好是当前绑定的，清除绑定状态
        if (g_currentBoundGraphicsPipeline == pipeline) {
            g_currentBoundGraphicsPipeline = NULL;
        }
        return;
    }
    if (g_real_vkDestroyPipeline) g_real_vkDestroyPipeline(device, pipeline, pAllocator);
}

/// 内部：执行 fishhook 重绑定（可在新 image 加载后重复调用以捕获新引用）
/// fishhook 的 rebind_symbols 是幂等的——会遍历所有已加载 image 并重绑定
/// vkGetInstanceProcAddr / vkGetDeviceProcAddr 的引用到我们的 wrapper。
/// 使用静态存储的 rebindings 数组（避免栈上局部变量在 future-image 加载时 UAF：
/// fishhook 会保留 rebindings 用于后续 dlopen 加载的 image）。
static void zinkStrideFixRebind(void) {
    static struct rebinding rebindings[] = {
        {"vkGetInstanceProcAddr", (void*)amethyst_vkGetInstanceProcAddr, (void**)&g_real_vkGetInstanceProcAddr},
        {"vkGetDeviceProcAddr", (void*)amethyst_vkGetDeviceProcAddr, (void**)&g_real_vkGetDeviceProcAddr},
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}

/// 安装 zink vertex stride 对齐 fix
/// 仅在 zink 渲染器被选中时激活。通过 fishhook 重绑定符号引用，
/// 并通过 hooked_dlsym 拦截 dlsym 查找（双重机制确保覆盖所有调用路径）。
void installZinkStrideFix(void) {
    if (g_zinkStrideFixActive) return;

    const char* renderer = getenv("AMETHYST_RENDERER");
    if (!renderer || !strstr(renderer, "libOSMesa")) {
        NSLog(@"[ZinkStrideFix] Skipped (zink not selected, AMETHYST_RENDERER=%s)",
              renderer ? renderer : "(null)");
        return;
    }

    g_zinkStrideFixActive = YES;

    // 初次重绑定（捕获当前已加载 image 的引用，主要是启动器主二进制）
    zinkStrideFixRebind();

    NSLog(@"[ZinkStrideFix] Installed vertex stride alignment hooks for zink (Mesa 25.0.7 + MoltenVK)");
}

/// 在新 image（特别是 libOSMesa / libMoltenVK）加载后调用，重新执行 fishhook
/// 以捕获新 image 对 vkGetInstanceProcAddr / vkGetDeviceProcAddr 的符号引用。
/// 由 hooked_dlopen 在检测到 libOSMesa 加载时调用。
void rebindZinkStrideFixForNewImage(void) {
    if (!g_zinkStrideFixActive) return;
    zinkStrideFixRebind();
    NSLog(@"[ZinkStrideFix] Re-rebound Vulkan symbols for newly loaded image");
}

/// dlsym hook：拦截 SDL3 / Vulkan 关键函数请求，返回我们的 hook 函数
///
/// 拦截的函数：
///   - SDL_CreateWindow → 返回 amethyst_hooked_SDL_CreateWindow
///     （让 SDL3 UIKit 后端复用启动器的 UIWindowScene）
///   - vkGetInstanceProcAddr / vkGetDeviceProcAddr → 返回我们的 wrapper
///     （zink stride fix：拦截 vkCreateGraphicsPipelines 调用）
///
/// 其他函数正常返回 orig_dlsym 的结果，避免日志爆炸。
void* hooked_dlsym(void* handle, const char* name) {
    if (name != NULL) {
        // Zink stride fix：拦截 Vulkan loader 函数查找
        if (g_zinkStrideFixActive) {
            if (strcmp(name, "vkGetInstanceProcAddr") == 0) {
                if (!g_real_vkGetInstanceProcAddr) {
                    g_real_vkGetInstanceProcAddr = (PFN_zkGetInstanceProcAddr)orig_dlsym(handle, name);
                }
                NSLog(@"[ZinkStrideFix] dlsym intercepted: vkGetInstanceProcAddr -> hook");
                return (void*)amethyst_vkGetInstanceProcAddr;
            }
            if (strcmp(name, "vkGetDeviceProcAddr") == 0) {
                if (!g_real_vkGetDeviceProcAddr) {
                    g_real_vkGetDeviceProcAddr = (PFN_zkGetDeviceProcAddr)orig_dlsym(handle, name);
                }
                NSLog(@"[ZinkStrideFix] dlsym intercepted: vkGetDeviceProcAddr -> hook");
                return (void*)amethyst_vkGetDeviceProcAddr;
            }
        }

        if (strcmp(name, "SDL_CreateWindow") == 0) {
            NSLog(@"[SDL3 Hook] dlsym intercepted: SDL_CreateWindow -> returning hook");
            // 首次拦截时，用 orig_dlsym 获取原始函数指针并保存
            // （amethyst_sdl_create_window_with_scene 内部会通过 amethyst_orig_dlsym
            //  重新获取 SDL3 函数指针，这里保存只是为了诊断/备份用途）
            if (!g_orig_sdl_CreateWindow && orig_dlsym) {
                g_orig_sdl_CreateWindow = (SDL_Window *(*)(const char *, int, int, unsigned int))
                    orig_dlsym(handle, name);
                NSLog(@"[SDL3 Hook] Original SDL_CreateWindow saved: %p", (void *)g_orig_sdl_CreateWindow);
            }
            return (void *)amethyst_hooked_SDL_CreateWindow;
        }

        // SDL_InitSubSystem hook（参照 Android 仓库 sdl_hook.c）
        // MC 26.3-snapshot-4+ 启动时调用 SDL_Init / SDL_InitSubSystem 初始化子系统
        if (strcmp(name, "SDL_InitSubSystem") == 0) {
            NSLog(@"[SDL3 Hook] dlsym intercepted: SDL_InitSubSystem -> returning hook");
            if (!g_orig_sdl_InitSubSystem && orig_dlsym) {
                g_orig_sdl_InitSubSystem = (SDL_InitSubSystem_t)orig_dlsym(handle, name);
                g_orig_sdl_SetHint = (SDL_SetHint_t)orig_dlsym(handle, "SDL_SetHint");
                NSLog(@"[SDL3 Hook] Original SDL_InitSubSystem=%p, SDL_SetHint=%p",
                      (void*)g_orig_sdl_InitSubSystem, (void*)g_orig_sdl_SetHint);
            }
            return (void *)amethyst_hooked_SDL_InitSubSystem;
        }
    }
    return orig_dlsym(handle, name);
}

int hooked_open(const char *path, int oflag, ...) {
    va_list args;
    va_start(args, oflag);
    mode_t mode = va_arg(args, int);
    va_end(args);
    if (path && !strcmp(path, "/etc/resolv.conf")) {
        return orig_open([NSString stringWithFormat:@"%s/resolv.conf", getenv("POJAV_HOME")].UTF8String, oflag, mode);
    }

    return orig_open(path, oflag, mode);
}

// 原始 SDL_CreateWindow 函数指针（fishhook 捕获后保存）
// 与 g_orig_sdl_CreateWindow 不同，这个是从 fishhook rebind 捕获的
static SDL_Window *(*g_fishhook_orig_sdl_CreateWindow)(const char *, int, int, unsigned int) = NULL;

/// fishhook 版本的 SDL_CreateWindow hook
/// 与 dlsym hook 的 amethyst_hooked_SDL_CreateWindow 功能相同，
/// 但通过 fishhook 的符号重绑定机制拦截，不需要 dlsym。
/// 这对 MC 26.3-snapshot-4+ 通过 LWJGL SharedLibrary.getFunctionAddress
/// 或 JNA 直接获取 SDL_CreateWindow 地址的方式有效。
static SDL_Window *amethyst_fishhook_SDL_CreateWindow(const char *title, int w, int h, unsigned int flags) {
    NSLog(@"[SDL3 Hook] fishhook SDL_CreateWindow intercepted: title=%s w=%d h=%d flags=0x%x",
          title ? title : "(null)", w, h, flags);
    // 调用我们的桥接函数（会用 Properties API 传入 UIWindowScene）
    SDL_Window *window = amethyst_sdl_create_window_with_scene(w, h, flags);
    NSLog(@"[SDL3 Hook] fishhook amethyst_sdl_create_window_with_scene returned: %p", window);
    return window;
}

void init_hookFunctions() {
    // 检查窗口后端模式：AMETHYST_WINDOWING_BACKEND 由 JavaLauncher.m 设置
    //   - "sdl"  → SDL3 模式（MC 26.3-snapshot-4+），需要 SDL_CreateWindow/SDL_InitSubSystem hook
    //   - "glfw" → GLFW 模式（MC 26.3-snapshot-3 及以下），不需要 SDL3 hook
    //   - 未设置 → 早期调用（main.m 中 UIApplicationMain 之前），保守注册所有 hook
    //     （libSDL3 还未加载，SDL3 hook 不会有实际副作用；后续 libSDL3 加载时
    //      会通过 hooked_dlopen 再次调用 init_hookFunctions 补充注册）
    const char *windowingBackend = getenv("AMETHYST_WINDOWING_BACKEND");
    BOOL registerSDL3Hooks = (windowingBackend == NULL) || (strcmp(windowingBackend, "sdl") == 0);

    // 基础 hook（始终注册）
    struct rebinding rebindings[] = (struct rebinding[]){
        {"abort", hooked_abort, (void *)&orig_abort},
        {"__assert_rtn", hooked___assert_rtn, NULL},
        {"exit", hooked_exit, (void *)&orig_exit},
        {"dlopen", hooked_dlopen, (void *)&orig_dlopen},
        {"dlsym", hooked_dlsym, (void *)&orig_dlsym},
        {"open", hooked_open, (void *)&orig_open},
    };
    size_t rebindings_count = sizeof(rebindings)/sizeof(struct rebinding);

    // SDL3 hook（仅 SDL3 模式或未确定模式时注册）
    // SDL_CreateWindow：MC 26.3-snapshot-4+ 不通过 dlsym 获取，而是通过 LWJGL
    //   SharedLibrary.getFunctionAddress 或 JNA，fishhook 可直接修改符号表引用
    // SDL_InitSubSystem：参照 Android 仓库 sdl_hook.c，拦截 MC 调用 SDL_Init/
    //   SDL_InitSubSystem，设置 SDL_RETURN_KEY_HIDES_IME 等 hints
    struct rebinding sdl3_rebindings[] = (struct rebinding[]){
        {"SDL_CreateWindow", amethyst_fishhook_SDL_CreateWindow, (void *)&g_fishhook_orig_sdl_CreateWindow},
        {"SDL_InitSubSystem", amethyst_fishhook_SDL_InitSubSystem, NULL}
    };
    size_t sdl3_rebindings_count = sizeof(sdl3_rebindings)/sizeof(struct rebinding);

    if (registerSDL3Hooks) {
        // 合并基础 hook 和 SDL3 hook 一起注册
        struct rebinding all_rebindings[sizeof(rebindings)/sizeof(struct rebinding) +
                                         sizeof(sdl3_rebindings)/sizeof(struct rebinding)];
        memcpy(all_rebindings, rebindings, sizeof(rebindings));
        memcpy(all_rebindings + rebindings_count, sdl3_rebindings, sizeof(sdl3_rebindings));
        rebind_symbols(all_rebindings, rebindings_count + sdl3_rebindings_count);
        NSLog(@"[main_hook] fishhook registered: base hooks + SDL3 hooks (SDL_CreateWindow + SDL_InitSubSystem), backend=%s",
              windowingBackend ? windowingBackend : "<unset>");
    } else {
        // GLFW 模式：仅注册基础 hook，不注册 SDL3 hook
        rebind_symbols(rebindings, rebindings_count);
        NSLog(@"[main_hook] fishhook registered: base hooks only (GLFW mode, SDL3 hooks skipped)");
    }

    // 注意：不在此处预加载 libSDL3.dylib。
    //
    // 历史问题：commit 3a837cc 曾在 init_hookFunctions 中主动 dlopen
    // libSDL3.dylib。但 init_hookFunctions 在 main() 中于 UIApplicationMain
    // 之前被调用（main.m 第 324 行）。SDL3 dylib 的 constructor 会初始化
    // UIKit 后端（注册 SDLUIKitDelegate / SDL main hook），在 UIApplicationMain
    // 之前加载会干扰 UIApplication / UIScene 的正常初始化，导致：
    //   1. SceneDelegate.scene:willConnectToSession: 不被正确调用 → 白屏
    //   2. requestGeometryUpdateWithPreferences 不执行 → 强制横屏失效
    //
    // 现在依赖 hooked_dlopen 拦截 libSDL3 的加载（无论 MC 通过 LWJGL
    // Library.loadNative / JNA / 自己的 JNI binding，最终都通过 dlopen
    // 加载 dylib，会被 hooked_dlopen 拦截并触发 rebind_symbols）。
    // 如需额外保障，可在 launchMinecraft 中调用 amethyst_preloadSDL3ForHook()。
}

/// 主动预加载 libSDL3.dylib 并重绑定符号（供启动 MC 时调用）
/// 必须在 UIApplicationMain 之后调用（例如 SurfaceViewController.launchMinecraft），
/// 避免在 UIApplication 启动前加载 SDL3 干扰 UIKit 初始化。
void amethyst_preloadSDL3ForHook(void) {
    void *sdl_lib = dlopen("@rpath/libSDL3.dylib", RTLD_NOLOAD | RTLD_GLOBAL);
    if (!sdl_lib) {
        sdl_lib = dlopen("@rpath/libSDL3.dylib", RTLD_LAZY | RTLD_GLOBAL);
        if (sdl_lib) {
            NSLog(@"[SDL3 Hook] libSDL3.dylib preloaded via amethyst_preloadSDL3ForHook, rebinding all images");
            init_hookFunctions();
        } else {
            NSLog(@"[SDL3 Hook] libSDL3.dylib preload failed in amethyst_preloadSDL3ForHook: %s", dlerror());
        }
    } else {
        NSLog(@"[SDL3 Hook] libSDL3.dylib already loaded in amethyst_preloadSDL3ForHook, rebinding all images");
        init_hookFunctions();
    }
}

// ============================================================================
// iOS 26+ PPL bypass（从原版项目移植）
// ============================================================================
// 背景：
//   iOS 26+ 引入 PPL（Page Protection Layer）对 dyld 加载的 Mach-O __TEXT
//   段做签名校验，传统的 dyld bypass（PLPatchMachOPlatformForFile）不再有效。
//   对于无 TXM（JIT 模块）且处于 FORCE_MIRRORED 模式的设备，需要使用硬件
//   断点 + Mach 异常的方式绕过 PPL：
//     1. 设置 ARM64 硬件断点（BVR/BCR）监控 hwRedirectOrig 指定的地址
//     2. 当 PC 命中断点时，Mach 内核发送 EXC_BREAKPOINT 异常到 excPort
//     3. exception_handler 线程通过 mach_msg_server 接收异常
//     4. catch_mach_exception_raise_state 将 PC 重定向到 hwRedirectTarget
//
//   hooked_dlopen 在检测到 home/tmp 目录下的 dylib 且设备需要 PPL bypass 时，
//   通过 musttail 尾调用 hooked_dlopen_26_ppl 执行上述流程。

// hack dlopen for non-TXM 26.x
void *exception_handler(void *unused) {
    mach_msg_server(mach_exc_server, sizeof(union __RequestUnion__catch_mach_exc_subsystem), excPort, MACH_MSG_OPTION_NONE);
    abort();
}
void *hooked_dlopen_26_ppl(const char *path, int mode) {
    if (!excPort) {
        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &excPort);
        mach_port_insert_right(mach_task_self(), excPort, excPort, MACH_MSG_TYPE_MAKE_SEND);
        pthread_t thread;
        pthread_create(&thread, NULL, exception_handler, NULL);
    }

    // save old thread states
    exception_mask_t mask = EXC_MASK_BREAKPOINT;
    mach_msg_type_number_t masksCnt = 1;
    exception_handler_t handler = excPort;
    exception_behavior_t behavior = EXCEPTION_STATE | MACH_EXCEPTION_CODES;
    thread_state_flavor_t flavor = ARM_THREAD_STATE64;
    arm_debug_state64_t origDebugState;
    mach_port_t thread = mach_thread_self();
    thread_get_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&origDebugState, &(mach_msg_type_number_t){ARM_DEBUG_STATE64_COUNT});
    thread_swap_exception_ports(thread, mask, handler, behavior, flavor, &mask, &masksCnt, &handler, &behavior, &flavor);
    assert(masksCnt == 1);

    // hook stuff. this will overwrite LiveContainer private container multitask's hook, we will load __TEXT using JIT inside
    arm_debug_state64_t hookDebugState = {0};
    for(int i = 0; i < 6 && hwRedirectOrig[i]; i++) {
        hookDebugState.__bvr[i] = (uint64_t)hwRedirectOrig[i];
        hookDebugState.__bcr[i] = 0x1e5;
    }
    thread_set_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&hookDebugState, ARM_DEBUG_STATE64_COUNT);

    // fixup @loader_path since we cannot use musttail here
    void *result;
    void *callerAddr = __builtin_return_address(0);
    struct dl_info info;
    if (path && !strncmp(path, "@loader_path/", 13) && dladdr(callerAddr, &info)) {
        char resolvedPath[PATH_MAX];
        snprintf(resolvedPath, sizeof(resolvedPath), "%s/%s", dirname((char *)info.dli_fname), path + 13);
        result = orig_dlopen(resolvedPath, mode);
    } else {
        result = orig_dlopen(path, mode);
    }

    // restore old thread states
    thread_set_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&origDebugState, ARM_DEBUG_STATE64_COUNT);
    thread_swap_exception_ports(thread, mask, handler, behavior, flavor, &mask, &masksCnt, &handler, &behavior, &flavor);

    return result;
}
kern_return_t catch_mach_exception_raise_state( mach_port_t exception_port, exception_type_t exception, const mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, const thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    arm_thread_state64_t *old = (arm_thread_state64_t *)old_state;
    arm_thread_state64_t *new = (arm_thread_state64_t *)new_state;
    uint64_t pc = arm_thread_state64_get_pc(*old);

    for(int i = 0; i < 6 && hwRedirectOrig[i]; i++) {
        if(pc == (uint64_t)hwRedirectOrig[i]) {
            *new = *old;
            *new_stateCnt = old_stateCnt;
            arm_thread_state64_set_pc_fptr(*new, hwRedirectTarget[i]);
            return KERN_SUCCESS;
        }
    }
    NSLog(@"[DyldLVBypass] Unknown breakpoint at pc: %p", (void*)pc);
    return KERN_FAILURE;
}
kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt) {
    abort();
}
kern_return_t catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    abort();
}
