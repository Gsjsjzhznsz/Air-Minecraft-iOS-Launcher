// MobileGlues - main.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "config/settings.h"
#include "config/stats.h"
#include "egl/egl.h"
#include "egl/loader.h"
#include "gl/envvars.h"
#include "gl/gl.h"
#include "gl/log.h"
#include "gl/mg.h"
#include "gles/loader.h"
#include "includes.h"
#include <cerrno>
#include <cstring>
#include <sys/stat.h>

#define DEBUG 0

#ifndef __APPLE__
__attribute__((used))
#endif
const char* license = "GNU LGPL-2.1 License";

void init_config() {
    if (!check_path()) return;
    config_refresh();
    // One dlopen of this library is one launch. Counting it here, before any
    // rendering work, means a game that crashes on the first frame still counts.
    bump_launch_count();
}

void show_license() {
    LOG_V("The Open Source License of MobileGlues: ");
    LOG_V("  %s", license);
}

#if PROFILING

PERFETTO_TRACK_EVENT_STATIC_STORAGE();

void init_perfetto() {
    perfetto::TracingInitArgs args;

    args.backends |= perfetto::kSystemBackend;

    perfetto::Tracing::Initialize(args);
    perfetto::TrackEvent::Register();
}
#endif

void proc_init() {
    init_config();

    clear_log();
    start_log();

    LOG_V("Initializing %s ...", RENDERERNAME);
    show_license();

    init_settings();

#ifndef __APPLE__
    load_libs();
    init_target_egl();
    init_target_gles();
    set_multidraw_setting();

    init_settings_post();
#endif

#if PROFILING
    init_perfetto();
#endif

    // Cleanup
#ifndef __APPLE__
    destroy_temp_egl_ctx();
#endif
    g_initialized = 1;
}

#ifdef __APPLE__
// On Apple/iOS, ANGLE (libtinygl4angle.dylib) is loaded by the host launcher
// with RTLD_GLOBAL *after* this dylib's constructor runs.  GL ES function
// pointers must therefore be resolved lazily, once ANGLE is available.
//
// The host calls this function from egl_bridge.m right after
// dlopen(libtinygl4angle.dylib, RTLD_GLOBAL) succeeds.
//
// IMPORTANT: We must resolve GL symbols from the REAL ANGLE libGLESv2 handle,
// NOT via RTLD_DEFAULT and NOT from libtinygl4angle itself.  Two pitfalls:
// 1. MobileGlues exports its own extern "C" wrappers for glGetString/glGetError/
//    glGetIntegerv/glGetStringi with the same symbol names as the real GL
//    functions.  dlsym(RTLD_DEFAULT, ...) would find our wrappers instead of
//    ANGLE's, causing infinite recursion (e.g. glGetError() wrapper calls
//    GLES.glGetError() which IS the wrapper).
// 2. libtinygl4angle is the LAUNCHER's bridge and exports only a subset of
//    GLES symbols -- notably its own glShaderSource, which does not forward
//    into ANGLE's object namespace.  Resolving the table from that handle
//    mixed implementations: glCreateShader/glCompileShader fell through to
//    RTLD_DEFAULT (ANGLE libGLESv2) while glShaderSource was served by
//    tinygl4angle itself, so ANGLE received shader objects that never got any
//    source and rejected every pipeline with "ERROR: 1:1: '' : syntax error"
//    (measured on-device: driver readback of the submitted source returned 0
//    bytes, GL_SHADER_SOURCE_LENGTH=0).

extern "C" __attribute__((visibility("default")))
void mg_init_gles() {
    static bool done = false;
    if (done) return;
    done = true;

    LOG_V("mg_init_gles: loading GL ES function pointers (Apple platform)\n");

    // The host already dlopen'd the bridge with RTLD_GLOBAL, so this just
    // bumps the reference count and returns the existing handle.  It stays
    // responsible for EGL-ish lookups (unchanged from before) and serves as
    // the last-resort GL table fallback below.
    void *angle = dlopen("@rpath/libtinygl4angle.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (!angle) {
        LOG_E("mg_init_gles: failed to dlopen ANGLE bridge: %s", dlerror());
        return;
    }

    // Pin the GL ES table to the REAL ANGLE libGLESv2 image that ships inside
    // the app bundle.  dlopen() on the already-loaded framework only bumps its
    // refcount and hands back the same handle -- no second copy of ANGLE.
    const char* gles_paths[] = {
        "@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
        "@rpath/libGLESv2.framework/libGLESv2",
        "libGLESv2",
    };
    void* real_gles = nullptr;
    const char* gles_via = nullptr;
    for (const char* p : gles_paths) {
        if ((real_gles = dlopen(p, RTLD_NOW | RTLD_LOCAL)) != nullptr) {
            gles_via = p;
            break;
        }
    }
    if (real_gles) {
        gles = real_gles;
        LOG_W_FORCE("[MG] mg_init_gles: GL ES table pinned to real ANGLE libGLESv2 via %s",
                    gles_via)
    } else {
        // Legacy behavior + loud warning: with gles == tinygl4angle the shader
        // pipeline WILL be interposed (see comment above).
        const char* dlerr = dlerror();
        gles = angle;
        LOG_W_FORCE("[MG] mg_init_gles: WARNING could not dlopen ANGLE libGLESv2 (%s); GL ES table falls back to libtinygl4angle -- shader-source interposition risk",
                    dlerr ? dlerr : "unknown error")
    }
    egl = angle;

    init_target_gles();
    set_multidraw_setting();
    init_settings_post();

    g_initialized = 1;
    LOG_V("mg_init_gles: done (%d GL ES functions resolved)\n", (int)sizeof(g_gles_func));
}
#endif
