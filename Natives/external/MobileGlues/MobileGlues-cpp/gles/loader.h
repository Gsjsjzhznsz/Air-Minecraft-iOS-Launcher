// MobileGlues - gles/loader.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#ifndef MOBILEGLUES_GLES_LOADER_H_
#define MOBILEGLUES_GLES_LOADER_H_

#include "../gl/log.h"
#include <GL/gl.h>
#include "gles.h"
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <type_traits>

// The value a stub hands back when it has nothing to say. Defined out here rather
// than inside the extern "C" block below because a template cannot have C language
// linkage.
//
// STUB_FUNCTION_END_NO_RETURN is used by ~90 entry points whose return type is not
// void, and those simply ran off the end of the function: at -O3 the body is a
// zero-byte fall-through into whatever the linker put next, so the caller reads an
// untouched return register. GL_EXT_direct_state_access is advertised by default
// (gles/loader.cpp), so several of those entry points are reachable and were
// answering an arbitrary value for a status or a boolean. `return f<void>();` is
// legal in a void function, so the ~2400 void users need no change.
template <class T> static inline T mg_stub_default() {
    if constexpr (!std::is_void_v<T>) return T{};
}

#ifdef __cplusplus
extern "C"
{
#endif

    void* proc_address(void* lib, const char* name);
    extern void *gles, *egl;

    // True only when the ANGLE image is the one that actually got loaded --
    // load_libs() falls back to the system driver when it cannot be opened.
    extern bool g_angle_in_use;

    void init_target_gles();

    void load_libs();

#if GLOBAL_DEBUG
#define INIT_GLES_FUNC(name)                                                                                           \
    {                                                                                                                  \
        LOG_D("INIT_GLES_FUNC(%s)", #name);                                                                            \
        GLES.name = (name##_PTR)proc_address(gles, #name);                                                             \
        if (GLES.name == NULL) LOG_W("Error: GLES function " #name " is NULL\n");                                      \
    }
#else
#define INIT_GLES_FUNC(name)                                                                                           \
    { GLES.name = (name##_PTR)proc_address(gles, #name); }
#endif

    // `used_override`, when given, is set to true only if `override` is what got
    // loaded -- the fallback path leaves it alone.
    void* open_lib(const char** names, const char* override, bool* used_override = nullptr);

// Resolve an EGL entry point from the backend library, once per call site.
//
// The initialiser is a lambda call rather than a `static bool first` flag, so
// the compiler emits a thread-safe guard around it. The old shape was an
// unsynchronised double-checked initialisation: both statics were
// constant-initialised, so no guard was generated and nothing ordered the write
// of the pointer against another thread's read of the flag. Two threads entering
// any EGL wrapper for the first time could see `first == false` with the pointer
// still null.
//
// A failed resolution is reported unconditionally: LOG_W compiles to nothing in
// release builds (GLOBAL_DEBUG in gl/log.h), so the old warning never reached a
// user's log and the caller went on to jump through the null pointer anyway.
#define LOAD_EGL(name)                                                                                                 \
    static name##_PTR egl_##name = []() -> name##_PTR {                                                                \
        name##_PTR p = (egl != NULL) ? (name##_PTR)proc_address(egl, #name) : NULL;                                    \
        if (p == NULL) LOG_W_FORCE("EGL entry point " #name " is not available in the backend library")                \
        return p;                                                                                                      \
    }(); /* the semicolon lives in the macro so the 56 existing call sites, which  \
            were written against a block-shaped macro and carry none, still work */

// Same, but bail out instead of calling through a null pointer. Use it for the
// entry points a backend is genuinely allowed not to have -- the platform and
// EXT variants -- where the old macro produced a crash rather than a failure the
// caller could handle.
#define LOAD_EGL_OR(name, onfail, retval)                                                                              \
    LOAD_EGL(name)                                                                                                     \
    if (egl_##name == NULL) {                                                                                          \
        onfail;                                                                                                        \
        return retval;                                                                                                 \
    }

#define CLEAR_GL_ERROR                                                                                                 \
    GLenum ERR = GLES.glGetError();                                                                                    \
    while (ERR != GL_NO_ERROR)                                                                                         \
        ERR = GLES.glGetError();

#define CLEAR_GL_ERROR_NO_INIT                                                                                         \
    ERR = GLES.glGetError();                                                                                           \
    while (ERR != GL_NO_ERROR)                                                                                         \
        ERR = GLES.glGetError();

#if GLOBAL_DEBUG
#define CHECK_GL_ERROR                                                                                                 \
    GLenum ERR = GLES.glGetError();                                                                                    \
    while (ERR != GL_NO_ERROR) {                                                                                       \
        LOG_E("ERROR: %d @ %s:%d", ERR, __FILE__, __LINE__)                                                            \
        ERR = GLES.glGetError();                                                                                       \
    }

#define INIT_CHECK_GL_ERROR GLenum ERR = GL_NO_ERROR;

#define CHECK_GL_ERROR_NO_INIT                                                                                         \
    ERR = GLES.glGetError();                                                                                           \
    while (ERR != GL_NO_ERROR) {                                                                                       \
        LOG_E("ERROR: %d @ %s:%d", ERR, __FILE__, __LINE__)                                                            \
        ERR = GLES.glGetError();                                                                                       \
    }
#else
#define CHECK_GL_ERROR                                                                                                 \
    {}
#define INIT_CHECK_GL_ERROR                                                                                            \
    {}
#define CHECK_GL_ERROR_NO_INIT                                                                                         \
    {}
#endif

#define INIT_CHECK_GL_ERROR_FORCE GLenum ERR = GL_NO_ERROR;

#ifndef __APPLE__
#define NATIVE_FUNCTION_HEAD(type, name, ...)                                                                          \
    extern "C" GLAPI GLAPIENTRY type name##ARB(__VA_ARGS__) __attribute__((alias(#name)));                             \
    extern "C" GLAPI GLAPIENTRY type name(__VA_ARGS__) {
#else
#define NATIVE_FUNCTION_HEAD(type, name, ...) extern "C" GLAPI GLAPIENTRY type name(__VA_ARGS__) {
#endif

#if GLOBAL_DEBUG
#define NATIVE_FUNCTION_END(type, name, ...)                                                                           \
    LOG_D("Use native function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                            \
    type ret = GLES.name(__VA_ARGS__);                                                                                 \
    GLenum ERR = GLES.glGetError();                                                                                    \
    if (ERR != GL_NO_ERROR) LOG_E("ERROR: %d", ERR)                                                                    \
    return ret;                                                                                                        \
    }
#else
#define NATIVE_FUNCTION_END(type, name, ...)                                                                           \
    LOG_D("Use native function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                            \
    type ret = GLES.name(__VA_ARGS__);                                                                                 \
    CHECK_GL_ERROR                                                                                                     \
    return ret;                                                                                                        \
    }
#endif

#if GLOBAL_DEBUG
#define NATIVE_FUNCTION_END_NO_RETURN(type, name, ...)                                                                 \
    LOG_D("Use native function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                            \
    GLES.name(__VA_ARGS__);                                                                                            \
    CHECK_GL_ERROR                                                                                                     \
    }
#else
#define NATIVE_FUNCTION_END_NO_RETURN(type, name, ...)                                                                 \
    LOG_D("Use native function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                            \
    GLES.name(__VA_ARGS__);                                                                                            \
    }
#endif

#define STUB_FUNCTION_HEAD(type, name, ...)                                                                            \
    extern "C" GLAPI GLAPIENTRY type name(__VA_ARGS__) {                                                               \
        LOG()

#define STUB_FUNCTION_END(type, name, ...)                                                                             \
    LOG_W("Stub function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                                  \
    return (type)1;                                                                                                    \
    }

#define STUB_FUNCTION_END_NO_RETURN(type, name, ...)                                                                   \
    LOG_W("Stub function: %s @ %s(...)", RENDERERNAME, __FUNCTION__);                                                  \
    return mg_stub_default<type>();                                                                                    \
    }

    struct gles_caps_t {
        int major;
        int minor;
        int GL_EXT_buffer_storage;
        int GL_EXT_disjoint_timer_query;
        int GL_QCOM_texture_lod_bias;
        [[maybe_unused]] int GL_EXT_blend_func_extended;
        [[maybe_unused]] int GL_EXT_texture_format_BGRA8888;
        [[maybe_unused]] int GL_EXT_read_format_bgra;
        int GL_OES_mapbuffer;
        int GL_EXT_multi_draw_indirect;
        int GL_OES_draw_elements_base_vertex;
        int GL_OES_depth_texture;
        int GL_OES_depth24;
        int GL_OES_depth_texture_float;
        int GL_EXT_texture_norm16;
        int GL_EXT_texture_rg;
        int GL_EXT_texture_query_lod;
        int GL_EXT_draw_elements_base_vertex;
        // Needed by the virtual enable table (gl/enable.cpp): each of these
        // supplies a GL 4.6 enable capability that GLES 3.2 core does not have,
        // using the same enum value as the desktop one. Without them the layer
        // cannot tell "the driver really supports this" from "the driver will
        // reject it", and glEnable behaves differently from device to device.
        int GL_EXT_multisample_compatibility; // GL_MULTISAMPLE, GL_SAMPLE_ALPHA_TO_ONE
        int GL_EXT_clip_cull_distance;       // GL_CLIP_DISTANCE0..7
        int GL_EXT_depth_clamp;              // GL_DEPTH_CLAMP
        int GL_EXT_sRGB_write_control;       // GL_FRAMEBUFFER_SRGB
        int GL_NV_polygon_mode;              // GL_POLYGON_OFFSET_LINE / _POINT
        int GL_OES_sample_shading;           // GL_SAMPLE_SHADING before ES 3.2
        // GL_EXT_multi_draw_arrays deliberately absent: glext.h defines a macro of
        // that exact name, and gl/multidraw.cpp already probes it lazily because it
        // needs the entry points as well as the string.
    };

    extern struct gles_caps_t g_gles_caps;

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_GLES_LOADER_H_
