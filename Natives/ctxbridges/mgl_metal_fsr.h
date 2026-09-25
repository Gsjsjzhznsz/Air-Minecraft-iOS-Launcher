// ============================================================================
// Task 166（Amethyst）：MobileGL DirectVulkan 后端的 Metal 层 FSR1。
//
// 对外 API（gl_bridge.m / SurfaceViewController.m 消费）：
//   ame166_metal_fsr_should_engage(renderer)   —— 门控判定（渲染器 + 几何 + env）
//   ame166_metal_fsr_acquire_layer(view, w, h)  —— 惰性创建私有交换层（nil = 回退）
//   ame166_metal_fsr_update_size(w, h)          —— 旋转/分辨率变更钩子
//   ame166_metal_fsr_context_reset()            —— 新 EGL 上下文时复位会话态
//   ame166_metal_fsr_teardown()                 —— 桥接层终止时清理
//
// 设计与病历见 Natives/ctxbridges/mgl_metal_fsr.mm 文件头。
// ============================================================================
#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Task 166 门控：AMETHYST_RENDERER 为 libMobileGL.dylib（DirectVulkan，
/// 即 mg 家族的 Vulkan 后端）且 FSR 联动几何在场（windowWidth < ame_surfaceWidth，
/// 即 updateSavedResolution 已按 FSR 预设缩窗）且环境开关未关闭。
/// 其余渲染器（MobileGlues 走渲染器内置 FSR1、zink 走 osm_bridge、
/// libMobileGL-gles 与 Mithril 维持全分辨率直呈）一律返回 false。
bool ame166_metal_fsr_should_engage(const char *renderer);

/// Task 166：获取（首次调用时创建）私有 CAMetalLayer 交换层。
/// viewLayer = 视图真层（Layer A，保持全分辨率、负责上屏）；返回的私有层
/// （Layer B）以 renderW x renderH 作为 native window 交给 MobileGL 的伪 EGL
/// -> MoltenVK swapchain。任何一步初始化失败返回 nil，调用方回退旧路径
/// （视图层直连 + 全分辨率 attribs，da5918a 语义）。
CAMetalLayer *ame166_metal_fsr_acquire_layer(CAMetalLayer *viewLayer, int renderW, int renderH);

/// Task 166：updateSavedResolution 钩子——旋转/分辨率缩放后同步 Layer B 的
/// drawableSize（= 新渲染分辨率）。非活跃态零开销。
void ame166_metal_fsr_update_size(int renderW, int renderH);

/// Task 166：新 EGL 上下文（gl_init_context 入口）时复位会话级状态
/// （锚点日志/帧计数；层与管线按需重建）。
void ame166_metal_fsr_context_reset(void);

/// Task 166：桥接层终止（br_terminate）时释放层与管线。
void ame166_metal_fsr_teardown(void);

#ifdef __cplusplus
}
#endif
