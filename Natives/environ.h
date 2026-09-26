//
// Created by maks on 24.09.2022.
//

#ifndef POJAVLAUNCHER_ENVIRON_H
#define POJAVLAUNCHER_ENVIRON_H

// Task 83（FSR 独立化）：本头从 Task83 起会被 ObjC++ TU（ctxbridges/
// osm_bridge.mm）包含。C 的 <stdatomic.h> 在 C++ 模式下会定义
// atomic_is_lock_free 等函数式宏（Apple clang 15.0.0 stdatomic.h:82），
// 随后 libc++ <atomic>（经 <string> 等）的同名函数声明被宏展开炸掉
// （CI run 34990764454：__atomic/atomic.h:144 expected ')'）。
// C++ 分支改用 <atomic>：std::atomic<size_t> 与 C 的 _Atomic size_t
// 在 clang ABI 下对象布局一致，链接期同一符号互通；atomic_load/store_
// explicit 的使用者全部是 C TU（input_bridge_v3.m），不受影响。
#ifdef __cplusplus
#include <atomic>
typedef std::atomic<size_t> atomic_size_t;
#else
#include <stdatomic.h>
#endif
#include "jni.h"

// Task 83（ObjC++ 化，CI run 35037109152 教训）：下方全部全局变量在 C TU
// 里是临时定义（-fcommon 公共符号，多方合并）；C++ TU 里则成为强定义，
// 与强定义（如 input_bridge_v3.m 的 int guiScale = 1;）在链接期冲突
// （duplicate symbol _guiScale）。C++ 分支一律 extern 声明化——定义仍由
// 各 C TU 承担，链接形态与 Task83 之前完全一致（零行为变化）。
#ifdef __cplusplus
#define AME_ENVIRON_DECL extern
#else
#define AME_ENVIRON_DECL
#endif

typedef struct {
    short type;
    union {
        int i1;
        float f1;
    };
    union {
        int i2;
        float f2;
    };
    short i3;
    short i4;
} GLFWInputEvent;

typedef void GLFW_invoke_Char_func(void* window, unsigned int codepoint);
typedef void GLFW_invoke_CharMods_func(void* window, unsigned int codepoint, int mods);
typedef void GLFW_invoke_CursorEnter_func(void* window, int entered);
typedef void GLFW_invoke_CursorPos_func(void* window, double xpos, double ypos);
typedef void GLFW_invoke_FramebufferSize_func(void* window, int width, int height);
typedef void GLFW_invoke_Key_func(void* window, int key, int scancode, int action, int mods);
typedef void GLFW_invoke_MouseButton_func(void* window, int button, int action, int mods);
typedef void GLFW_invoke_Scroll_func(void* window, double xoffset, double yoffset);
typedef void GLFW_invoke_WindowPos_func(void* window, int x, int y);
typedef void GLFW_invoke_WindowSize_func(void* window, int width, int height);

AME_ENVIRON_DECL jclass class_CTCClipboard;
AME_ENVIRON_DECL jmethodID method_SystemClipboardDataReceived;

//struct pojav_environ_s {
    //render_window_t* mainWindowBundle;
    //BOOL force_vsync;
    AME_ENVIRON_DECL atomic_size_t eventCounter;
    AME_ENVIRON_DECL GLFWInputEvent events[8000];
    AME_ENVIRON_DECL double cursorX, cursorY, cLastX, cLastY;
    //jmethodID method_accessAndroidClipboard;
    //jmethodID method_onGrabStateChanged;
    //jmethodID method_glfwSetWindowAttrib;
    AME_ENVIRON_DECL jmethodID method_internalWindowSizeChanged;
    AME_ENVIRON_DECL jclass bridgeClazz;
    AME_ENVIRON_DECL jclass vmGlfwClass;
    AME_ENVIRON_DECL jboolean isGrabbing;
    AME_ENVIRON_DECL jbyte* keyDownBuffer;
    AME_ENVIRON_DECL JavaVM* runtimeJavaVMPtr;
    AME_ENVIRON_DECL JNIEnv* runtimeJNIEnvPtr;
    //JavaVM* dalvikJavaVMPtr;
    //JNIEnv* dalvikJNIEnvPtr_ANDROID;
    AME_ENVIRON_DECL long showingWindow;
    AME_ENVIRON_DECL bool isInputReady, isCursorEntered, isUseStackQueueCall;
    //int savedWidth, savedHeight;
    AME_ENVIRON_DECL int windowWidth, windowHeight;
    AME_ENVIRON_DECL int physicalWidth, physicalHeight;
#define ADD_CALLBACK_WWIN(NAME) \
    AME_ENVIRON_DECL GLFW_invoke_##NAME##_func* GLFW_invoke_##NAME;
    ADD_CALLBACK_WWIN(Char);
    ADD_CALLBACK_WWIN(CharMods);
    ADD_CALLBACK_WWIN(CursorEnter);
    ADD_CALLBACK_WWIN(CursorPos);
    ADD_CALLBACK_WWIN(FramebufferSize);
    ADD_CALLBACK_WWIN(Key);
    ADD_CALLBACK_WWIN(MouseButton);
    ADD_CALLBACK_WWIN(Scroll);
    ADD_CALLBACK_WWIN(WindowPos);
    ADD_CALLBACK_WWIN(WindowSize);

#undef ADD_CALLBACK_WWIN
//};

AME_ENVIRON_DECL int guiScale;
AME_ENVIRON_DECL float resolutionScale;
AME_ENVIRON_DECL BOOL virtualMouseEnabled, isControlModifiable;

// Task 83（FSR 独立化）：呈现表面像素尺寸（= physical × resolutionScale，
// updateSavedResolution 单点写入）。OSMesa/zink 桥的 FSR 升采样需要"表面
// 全尺寸"而 windowWidth/windowHeight 是"MC 窗口信念"（FSR 联动下二者
// 不同：window = surface / fsr_scale）。0 = 尚未初始化（消费者自行回退
// windowWidth 口径）。
AME_ENVIRON_DECL int ame_surfaceWidth, ame_surfaceHeight;

// Task175（物品栏命中几何的单一事实源）：物理像素 / MC 窗口像素 的合成比
// 例（= fsr / resolutionScale 的合成，含旋转/分辨率/FSR 档位全部因子）。
// 由 updateSavedResolution 单点写入（窗口信念的唯一作者），消费者首选它、
// 本地重算仅作 0 值时的回退——防 CallbackBridge_nativeSendScreenSize 等
// Java 侧屏幕尺寸回报把 windowWidth/Height 全局改写后，命中矩形跟着走样
// （用户实测"切换界面尺寸或更换分辨率后物品栏位置/大小偏移"的存活假设
// 之一）。值域与 touchHotbar 的旧钳制一致 [0.25, 8]，异常时写 0 = 未就绪。
AME_ENVIRON_DECL float ame_windowToPhysRatio;

// Task 153（MobileGL 延迟缩窗 → Task 154 已退役，档案保留）：曾用于 FSR
// 联动 + MobileGL 的"全尺寸启动 → 链确认全尺寸后缓冲后下发缩窗"流程；
// 7c32bc3 装机日志实证 libMobileGL 的伪 EGL 使 eglQuerySurface 链恒 idle、
// 缩窗永不下发（输入错位 + FSR 无效果的直接根因），Task154 起 MobileGL
// 整体退出 FSR 联动（ame83 能力表除名，mgl_fsr 链 #if 0 存档）。全局
// 保留原因：updateSavedResolution 仍将其清零防跨渲染器残留；mgl_fsr 的
// #if 0 档案体引用（未来复活的现成接缝）。
AME_ENVIRON_DECL int ame153_fsr_deferred_armed;
AME_ENVIRON_DECL int ame153_fsr_pending_render_w, ame153_fsr_pending_render_h;
AME_ENVIRON_DECL int ame153_fsr_believed_surface_w, ame153_fsr_believed_surface_h;

// 硬件断点重定向数组（同步自上游，用于非 TXM 的 iOS 26+ 设备 dlopen 重定向）
// 由 redirectFunctionHWBreakpoint 填充，由 catch_mach_exception_raise_state 读取
AME_ENVIRON_DECL uint64_t hwRedirectOrig[6], hwRedirectTarget[6];

#endif //POJAVLAUNCHER_ENVIRON_H
