#pragma once

#import <QuartzCore/QuartzCore.h>
#include <EGL/egl.h>
#include <GL/osmesa.h>

typedef struct {
    GLboolean (*OSMesaMakeCurrent) (OSMesaContext ctx, void *buffer, GLenum type, GLsizei width, GLsizei height);
    OSMesaContext (*OSMesaGetCurrentContext) (void);
OSMesaContext  (*OSMesaCreateContext) (GLenum format, OSMesaContext sharelist);
    void (*OSMesaDestroyContext) (OSMesaContext ctx);
    void (*OSMesaPixelStore) ( GLint pname, GLint value );
    GLubyte* (*glGetString) (GLenum name);
    void (*glFinish) (void);
    void (*glClearColor) (GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha);
    void (*glClear) (GLbitfield mask);
} osmesa_library;

typedef struct {
    OSMesaContext context;
    uint32_t width, height;
    CGColorSpaceRef color_space;
    void* buffer;
} osm_render_window_t;

// Task 83（FSR 独立化）：osm_bridge 已改为 ObjC++（.mm）——本头的函数声明
// 被 C TU（egl_bridge.m 等）和唯一 C++ TU（osm_bridge.mm）共同包含。无防护
// 时 .mm 侧定义走 C++ name mangling，.m 调用方链接 C 符号 → undefined symbol。
#ifdef __cplusplus
extern "C" {
#endif

void osm_swap_buffers();
void set_osm_bridge_tbl();

#ifdef __cplusplus
}
#endif
