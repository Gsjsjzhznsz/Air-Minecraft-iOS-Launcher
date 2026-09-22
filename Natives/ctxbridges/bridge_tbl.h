#pragma once

#include <stdlib.h>
#include "gl_bridge.h"
#include "osm_bridge.h"
#include "vk_bridge.h"

typedef union {
    gl_render_window_t gl;
    osm_render_window_t osm;
    vk_render_window_t vk;
} basic_render_window_t;

typedef basic_render_window_t* (*br_init_context_t)(basic_render_window_t* share);
typedef void (*br_make_current_t)(basic_render_window_t* bundle);
typedef basic_render_window_t* (*br_get_current_t)();

bool (*br_init)();
br_init_context_t br_init_context;
br_make_current_t br_make_current;
//br_get_current_t br_get_current = NULL;
void (*br_swap_buffers)();
void (*br_setup_window)();
void (*br_swap_interval)(int swapInterval);
void (*br_terminate)();

// ----------------------------------------------------------------------------
// Task 144：线程级"当前上下文"改为跨编译单元共享的单一 TLS 实例。
//
// 病历（Mithril 4.0 后端装机闪退 latestlog.txt 2026-09-22 20:40）：本头文件
// 原先 `static __thread ... currentBundle` 以文件作用域定义在头里 —— 每个
// 包含本头的 .m/.mm 都各有一份副本。gl_bridge.m 的 gl_make_current 只写给
// gl_bridge.m 自己那份；egl_bridge.m 的 pojavGetCurrentContext()（LWJGL
// GLFW.glfwGetCurrentContext 的后端）读的却是 egl_bridge.m 那份【永远为
// NULL】的副本。Mithril 的 glGetString 是线程绑定模型，加上 POJAV_RENDERER
// 修复（JavaLauncher 侧 setenv，激活 LWJGL 补丁的 fixPojavGLContext 重绑）
// 之前，渲染线程的上下文状态全靠各渲染器自身语义兜底：
//   - MobileGL-gles / OSMesa：全局单上下文模型 -> 混过 glGetString 探针；
//   - Mithril：TLS 模型 -> 渲染线程 glGetString 返回 NULL ->
//     LWJGL 抛 "There is no OpenGL context current in the current thread"。
// 修复：TLS 变量 extern 化，定义在 egl_bridge.m（必然链接的 TU）；
// 写入一律走 br_set_current（同步登记 ame_brLastCurrent 供采纳兜底）。
extern __thread basic_render_window_t* ame_brCurrent;
extern basic_render_window_t* ame_brLastCurrent;

static inline basic_render_window_t* br_get_current() {
    return ame_brCurrent;
}

static inline void br_set_current(basic_render_window_t* bundle) {
    ame_brCurrent = bundle;
    if (bundle) ame_brLastCurrent = bundle;
}
