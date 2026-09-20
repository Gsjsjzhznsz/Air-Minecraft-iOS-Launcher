#pragma once

#import <UIKit/UIKit.h>

#include <stdbool.h>
#include <string.h>
#include "environ.h"
#include "jni.h"

// Task 83（FSR 独立化 / ObjC++ 化）：本头自 Task83 起被 C++ TU（ctxbridges/
// osm_bridge.mm）包含。函数声明无 extern "C" 防护时，C++ 侧按 Itanium ABI
// 修饰名引用（如 "customNSLog(char const*, int, ...)"），C TU（utils.m 等）
// 的未修饰定义与之无法会合 → 链接失败（CI run 35036079381）。本头纯 C 声明
// （函数/宏/变量，无 ObjC 结构），整体包 extern "C" 安全。
#ifdef __cplusplus
extern "C" {
#endif

// Remove date + time from NSLog, unneeded
#define NSLog(args...) customNSLog(__FILE__,__LINE__,__PRETTY_FUNCTION__,args);

// Control button actions
#define ACTION_DOWN 0
#define ACTION_UP 1
#define ACTION_MOVE 2
#define ACTION_MOVE_MOTION 3

#define BUTTON1_DOWN_MASK 1 << 10 // left btn
#define BUTTON2_DOWN_MASK 1 << 11 // mid btn
#define BUTTON3_DOWN_MASK 1 << 12 // right btn

// GLFW event types
#define EVENT_TYPE_CHAR 1000
#define EVENT_TYPE_CHAR_MODS 1001
#define EVENT_TYPE_CURSOR_ENTER 1002
#define EVENT_TYPE_CURSOR_POS 1003
#define EVENT_TYPE_FRAMEBUFFER_SIZE 1004
#define EVENT_TYPE_KEY 1005
#define EVENT_TYPE_MOUSE_BUTTON 1006
#define EVENT_TYPE_SCROLL 1007
#define EVENT_TYPE_WINDOW_POS 1008
#define EVENT_TYPE_WINDOW_SIZE 1009
#define EVENT_TYPE_MODIFIERS 1010

#define GLFW_FOCUSED 0x00020001
#define GLFW_VISIBLE 0x00020004

#define RENDERER_NAME_GL4ES "libgl4es_114.dylib"
#define RENDERER_NAME_MTL_ANGLE "libtinygl4angle.dylib"
#define RENDERER_NAME_MOBILEGLUES "libmobileglues.dylib"
#define RENDERER_NAME_VK_ZINK "libOSMesa.8.dylib"
#define RENDERER_NAME_VULKAN "libMoltenVK.dylib"
// LTW (Large Thin Wrapper) - OpenGL Core 3.3 → OpenGL ES 3 转译层
// 复刻自官方 MojoLauncher/LTW 仓库，完美支持 Sodium + Iris 光影：
//   - 伪装成 OpenGL 3.3 Core Profile 让 MC 1.17+ 正常运行
//   - 主动声明 GL_ARB_buffer_storage 等 ARB 扩展，让 Sodium 的
//     persistent mapped buffers / texture buffers 正常工作
//   - Fragment shader 编译失败时忽略错误，让 BSL/Mellow 等光影包能运行
#define RENDERER_NAME_LTW "libltw.dylib"

// Mithril 渲染器 - OpenGL 3.3 Core → Vulkan/Metal 转译层（libmithril.dylib）。
// 自带完整的 EGL 1.5 + GL 实现（Vulkan backend，经 MoltenVK 到 Metal），
// 必须从自身 dylib 解析 EGL 符号：若复用 ANGLE 的 EGL，会创建 ANGLE 的 Metal
// 上下文而非 Mithril 的 swapchain，且 eglChooseConfig 在 Mithril 的属性组合下
// 可能返回 0 个配置，触发 gl_init_context 的 assert(bundle->config)。
// 参考：Uniaball/Mithril-Wrapper 仓库 launcher-patch/ 下对 Air 的接入方式。
#define RENDERER_NAME_MITHRIL "libmithril.dylib"

// MobileGL - MobileGL-Dev 的桌面 OpenGL 实现（LGPL-3.0）。
// 两个变体共用同一个 libMobileGL.dylib 二进制，由环境变量
// MOBILEGL_BACKEND_TYPE 在运行时选择后端：
//   libMobileGL.dylib       -> DirectVulkan（GL -> Vulkan -> MoltenVK -> Metal）
//   libMobileGL-gles.dylib  -> DirectGLES（GL -> OpenGL ES）
// 与 Mithril 一样自带 EGL 实现，必须从自身 dylib 解析 EGL 符号。
// 参考：Swung0x48/Amethyst-iOS 提交 dc57bfd3d2 "feat: add MobileGL renderer support"。
#define RENDERER_NAME_MOBILEGL "libMobileGL.dylib"
#define RENDERER_NAME_MOBILEGL_GLES "libMobileGL-gles.dylib"

static inline bool isMobileGLRenderer(const char *renderer) {
    return renderer && (!strcmp(renderer, RENDERER_NAME_MOBILEGL) ||
                        !strcmp(renderer, RENDERER_NAME_MOBILEGL_GLES));
}

static inline bool isMithrilRenderer(const char *renderer) {
    return renderer && !strcmp(renderer, RENDERER_NAME_MITHRIL);
}

// 自带 EGL 实现的渲染器：EGL 符号要从渲染器自己的 dylib 解析，不能用 ANGLE。
static inline bool isSelfEglRenderer(const char *renderer) {
    return isMithrilRenderer(renderer) || isMobileGLRenderer(renderer);
}

// 导出 desktop OpenGL（而非 OpenGL ES）的渲染器：
// 需要 EGL_OPENGL_BIT 配置 + eglBindAPI(EGL_OPENGL_API)。
static inline bool isDesktopGLRenderer(const char *renderer) {
    return isMobileGLRenderer(renderer) || isMithrilRenderer(renderer) ||
           (renderer && !strcmp(renderer, RENDERER_NAME_MTL_ANGLE));
}

#define SPECIALBTN_KEYBOARD -1
#define SPECIALBTN_TOGGLECTRL -2
#define SPECIALBTN_MOUSEPRI -3
#define SPECIALBTN_MOUSESEC -4
#define SPECIALBTN_VIRTUALMOUSE -5
#define SPECIALBTN_MOUSEMID -6
#define SPECIALBTN_SCROLLUP -7
#define SPECIALBTN_SCROLLDOWN -8
#define SPECIALBTN_MENU -9

#define NSDebugLog(...) if (debugLogEnabled) { NSLog(__VA_ARGS__); }
// Task 122 链接修复（CI 35459629168：osm_bridge 与 mgl_fsr 两个 C++ TU 各自
// 强定义这对全局 -> 4 个重复符号）。environ.h 的 AME_ENVIRON_DECL 同款守卫：
// C++ TU 只见 extern 声明，存储由各 C TU 的 tentative 定义承担（-fcommon 合并）。
#ifdef __cplusplus
extern BOOL debugLogEnabled, isJailbroken;
#else
BOOL debugLogEnabled, isJailbroken;
#endif

//__weak UIViewController *viewController;

#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
BOOL isJITEnabled(BOOL checkCSOps);
// Task96：MeloNX 风格信息卡数据源（右面板「设备」「系统」卡片）。
// getDeviceMarketingName：hw.machine（如 iPad15,3）→ Apple 营销名
//（如 "iPad Air 11-inch (M3)"）；未收录机型回退 hw.machine 原始标识，宁缺毋错。
// getSystemVersionDisplay："iPadOS 18.3.2 (22D2082)"（系统名+版本+构建号，
// iPhone 上前缀为 iOS；构建号读不到时只显示系统版本）。
NSString* getDeviceMarketingName(void);
NSString* getSystemVersionDisplay(void);
// Check if a debugger is likely still attached (iOS 26+ TXM workaround).
// When FORCE_MIRRORED + HAS_TXM, brk #0x69 in JavaLauncher requires a
// debugger to be actively attached.  getppid() returns launchd's PID (1)
// when no debugger is present, and the debugger's PID otherwise.
BOOL JIT26IsLikelyDebuggerKeepAttached(void);
// Live "debugger attached right now" check via the kernel P_TRACED flag
// (sysctl KERN_PROC_PID).  Covers debuggers that attach to an
// already-running process by pid (StikJIT/SideJIT), where getppid()
// stays 1 for the whole session.
BOOL JIT26DebuggerAttachedViaPtrace(void);
// Live "debugger holds our task" check via Mach exception ports
// (task_get_exception_ports on EXC_BREAKPOINT|EXC_SOFTWARE).  lldb/debugserver
// keep serving breakpoints through task-level exception ports after
// PT_DETACH, with P_TRACED back at 0 -- this is what actually services the
// JIT26 brk #0x69 / brk #0xf00d traps in that state.
BOOL JIT26DebuggerViaExceptionPorts(void);
// legacy method used to check if we're using universal script
void* JIT26CreateRegionLegacy(size_t len);
// Task91：JIT26CreateRegionLegacy 的 SIGTRAP 安全网包装。
// TXM 设备上 brk #0x69 无人应答（JIT26 调试器未就绪/脚本未挂载/调试器提前
// 脱离）时，裸函数会直接 SIGTRAP 致死（"开启 JIT 后闪退"）。包装器在调用
// 窗口内捕获 SIGTRAP 并返回 NULL，由调用方走优雅报错路径；调试器正常应答
// 时行为与裸函数完全一致。
void* JIT26CreateRegionLegacySafe(size_t len);
// Task91：TrollStore 真实安装判定（entitlement 标记 AND bundle 旁 _TrollStore
// 目录）。签名里预写的 jb.pmap_cs.custom_trust 字符串在普通侧载包上同样存在，
// 单独使用会把非 TrollStore 环境误导入 apple-magnifier:// 死路。
BOOL isTrollStoreInstall(void);
// used for large memory regions
void* JIT26PrepareRegion(void *addr, size_t len);
// same as JIT26PrepareRegion, but used for smaller memory regions
// and retain content instead of filling 0x69
void JIT26PrepareRegionForPatching(void *addr, size_t len);
void JIT26SetDetachAfterFirstBr(BOOL value);
void JIT26SendJITScript(NSString* script);

typedef enum {
    JIT_FLAG_IS_IOS_26 = 1 << 0,
    JIT_FLAG_FORCE_MIRRORED = 1 << 1,
    JIT_FLAG_HAS_TXM = 1 << 2,
} JITFlags;
JITFlags DeviceGetJITFlags(BOOL refresh);
BOOL DeviceHasJITFlags(JITFlags flags);

// Init functions
void init_bypassDyldLibValidation();
void init_hookFunctions();

// Zink (Mesa 25.0.7) + MoltenVK vertex stride 4 字节对齐 fix
// 仅在 zink 渲染器被选中时激活（需在 AMETHYST_RENDERER 环境变量设置后调用）
// 详见 main_hook.m 中的实现注释
void installZinkStrideFix();
// 在新 image（libOSMesa / libMoltenVK）加载后调用，重新执行 fishhook
// 捕获新 image 对 Vulkan loader 函数的符号引用
void rebindZinkStrideFixForNewImage();
void init_hookUIKitConstructor();
void init_setupMultiDir();

// Task 132（sdl3_hook.m 实现）：libjnidispatch 加载后重绑定其 _dlsym
// 指针槽为 hook_fn——JNA 的符号解析由此进 hooked_dlsym /
// amethyst_sdl3_hook_resolve，Task131 的 JNA closure 守卫对 JNA 路径生效。
// handle = 真实 dlopen 返回的句柄（= image mach header 地址）。
void amethyst_task132_rebind_jna_dlsym(void *handle, void *hook_fn);

BOOL PLPatchMachOPlatformForFile(const char *path);

UIViewController* currentVC();
void openLink(UIViewController* sender, NSURL* link);
void handle_fatal_exit(int code);
// Task 27：fatal 通道取证 —— 把 abort/exit/断言的调用线程名+符号化回溯
// O_APPEND 直写 $POJAV_HOME/fatal_trace.txt（绕过 latestlog 管道，防丢尾）
void ame_write_fatal_trace(const char *reason);

NSString* localize(NSString* key, NSString* comment);
NSMutableDictionary* parseJSONFromFile(NSString *path);
NSError* saveJSONToFile(NSDictionary *dict, NSString *path);
void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...);

static inline CGFloat clamp(CGFloat x, CGFloat lower, CGFloat upper) {
    return fmin(upper, fmax(x, lower));
}
CGFloat MathUtils_dist(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2);
CGFloat MathUtils_map(CGFloat x, CGFloat in_min, CGFloat in_max, CGFloat out_min, CGFloat out_max);
CGFloat dpToPx(CGFloat dp);
CGFloat pxToDp(CGFloat px);
void setButtonPointerInteraction(UIButton *button);
void _CGDataProviderReleaseBytePointerCallback(void *info,const void *pointer);
void dismissModalViewController(UIViewController *viewController);

jboolean attachThread(bool isAndroid, JNIEnv** secondJNIEnvPtr);

void sendData(short type, int i1, int i2, short i3, short i4);
void sendDataFloat(short type, float i1, float i2, short i3, short i4);

void closeGLFWWindow();
void callback_LauncherViewController_installMinecraft();
void callback_SurfaceViewController_launchMinecraft(int width, int height);
int callback_SurfaceViewController_touchHotbar(CGFloat x, CGFloat y);

// FPS 计数器：在 pojavSwapBuffers() 中累加，调用此函数读取并重置（参照 FCL/ZL2）
unsigned int pojavGetAndResetFps();
// 显式递增 FPS 计数器（供 Vulkan 模式 CADisplayLink fallback 使用）
void pojavIncrementFpsCounter();
// 黑屏取证（Task 32）：eglSwapBuffers 真实成功/失败计数（gl_bridge.m 实现）。
// 与上面的 FPS 计数器区分：FPS 计 pojavSwapBuffers 入口调用（成功与否都+1），
// 这两个计数器计 eglSwapBuffers 的真实返回值，用于判断呈现路径是否断裂。
void ame_egl_swap_stats(unsigned long *ok, unsigned long *fail);
// Task 76（帧节奏诊断）：读取并重置 5 秒窗口内的 swap 帧间隔统计
//（gl_bridge.m 实现，渲染线程侧记录）。maxGap=窗口内最大帧间隔（尖峰），
// avgGap=平均帧间隔。读取即重置，由 [RenderDiag] 心跳（SurfaceViewController
// updateGameStats 的 5 秒档）调用。帧率均值掩盖节奏问题——vsync 锁 60 下
// maxGap 的阶梯分布（33/50/100/200ms）才是"30fps 看得像 10fps"的直接度量。
void ame_egl_swap_framegap(unsigned int *maxGapMs, unsigned int *avgGapMs);
// Task 77（帧相位归因）：读取并重置 5 秒窗口内渲染线程帧循环的两相位
// 计时（gl_bridge.m 实现，渲染线程侧记录）：
//   present = eglSwapBuffers 本体耗时（ANGLE Metal 编码提交/nextDrawable/
//             GPU 追赶；maxDrawableCount=3 耗尽时阻塞在此）
//   build   = 上次 present 返回 → 本次 swap 入口（MC tick+事件泵+GL 编码
//             穿 MobileGlues/ANGLE 的 CPU 税）
// avg/max 均折算毫秒，读取即重置。MG 卡顿归因的判读法：presAvg≈avgGap
// → 停在呈现/GPU 侧；buildAvg≈avgGap → 停在 CPU 帧构造侧。
void ame_egl_swap_phase_stats(unsigned int *presentAvgMs, unsigned int *presentMaxMs,
                              unsigned int *buildAvgMs, unsigned int *buildMaxMs);
// Task 50：GL 呈现层所有权（gl_bridge.m 实现）。GL 路径创建 EGL surface
// 成功后为真——SurfaceViewController.updateSavedResolution 据此把呈现层
// 对齐到 1x 点数（bounds 跟随旋转），与 MC viewport/ANGLE surface 保持
// 单一事实源。Vulkan 路径恒为假（MoltenVK 自管 drawableSize，行为不变）。
bool ame_gl_surface_owns_layer();
// Task 53：EGL surface 与 MC viewport 几何失配（转置锁死且重对齐未治愈）
// 期间为真（gl_bridge.m 实现，交换路径逐帧刷新）。updateSavedResolution
// 据此停写 drawableSize——失配期由 Task52 guard 以 surface 尺寸独占写权
// （present 自洽），避免两写者拉锯产生"左半屏压扁 + 右半屏残帧"的分裂
// 画面；重对齐成功后 surface==bounds，正常写入恢复为同值 no-op。
bool ame_gl_surface_transposed();
// 运行时判定 MC 真实渲染路径是否为 Vulkan（clientAPI == GLFW_NO_API）。
// 比 SurfaceViewController 在 viewDidLoad 时的静态字符串推断更准确：
// - 真正 Vulkan 路径（graphicsApi=prefer_vulkan 或 default 走 Vulkan）→ 返回 true
// - Vulkan 渲染器但 MC 实际选 OpenGL 路径（prefer_opengl）→ 返回 false，避免双重计数
// 此函数读取 egl_bridge.m 中的 clientAPI 全局变量，由 pojavSetWindowHint(GLFW_CLIENT_API, ...) 写入。
bool pojavIsActualVulkanPath();

void CallbackBridge_nativeSetInputReady(BOOL inputReady);
BOOL CallbackBridge_nativeSendChar(jchar codepoint /* jint codepoint */);
BOOL CallbackBridge_nativeSendCharMods(jchar codepoint, int mods);
// Task83：控件按钮键盘打字支持——executebtn 在按键按下时对本键补发
// 字符事件（MC 1.13+ 聊天框只认 charTyped/text-input，纯 key 事件不进文本）。
// 仅由按钮路径调用（SurfaceViewController executebtn），硬件键盘不走这里。
BOOL CallbackBridge_buttonKeySynthesizeText(int key);
void CallbackBridge_nativeSendCursorPos(char event, CGFloat x, CGFloat y);
void CallbackBridge_nativeSendKey(int key, int scancode, int action, int mods);
void CallbackBridge_nativeSendMouseButton(int button, int action, int mods);
void CallbackBridge_nativeSendScreenSize(int width, int height);
void CallbackBridge_nativeSendScroll(CGFloat xoffset, CGFloat yoffset);
void CallbackBridge_sendKeycode(int keycode, jchar keychar, int scancode, int modifiers, BOOL isDown);
void CallbackBridge_pauseGameIfNeed();
// issue #27 修复（参照 FCL commit 08c0716）：物理键盘 modifier 同步
// 显式同步 MC 1.21.9+ 内部的 InputConstants modifier 缓存。
// 由 KeyboardInput.m 在物理键盘按下/释放事件中调用。
void CallbackBridge_syncModifiersToMC(int mods);
void CallbackBridge_queueModifierSync(int mods);

// ============================================================================
// Task 67（options.txt 移动键位净化 + Task66 状态数组对证）
// - ame67_sanitizeOptionsKeybinds：launchJVM 早期调用（MC 读 options.txt 前）。
//   dump 全部 key_key.* 行；把 forward/left/back/right/jump/sneak/sprint
//   七键中"存在且偏离默认"的行回归规范值（备份 options.txt.amethyst-bak）。
//   根因假设：输入损坏时代按键设置捕获对话框把垃圾事件写成键位（例如
//   forward 绑到 Shift），事件层全绿也救不了坏绑定。
// - Ame66GetKbState/Ame66GetKbNumKeys：暴露 Task66 直写的 SDL 键盘状态
//   数组指针，供 sdl3_hook 的 SDL_GetKeyboardState 钩子对证 MC 轮询侧
//   与写入侧是否同一块内存。
// ============================================================================
void ame67_sanitizeOptionsKeybinds(void);
const bool *Ame66GetKbState(void);
int Ame66GetKbNumKeys(void);

#ifdef __cplusplus
}
#endif
