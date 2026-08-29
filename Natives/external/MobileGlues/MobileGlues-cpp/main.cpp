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
extern "C" __attribute__((visibility("default")))
void mg_init_gles() {
    static bool done = false;
    if (done) return;
    done = true;

    LOG_V("mg_init_gles: loading GL ES function pointers (Apple platform)\n");

    // Mark GL functions as loaded from the system/ANGLE rather than a
    // dlopen'd library.  proc_address() on Apple uses RTLD_DEFAULT.
    gles = nullptr;
    egl = nullptr;

    init_target_gles();
    set_multidraw_setting();
    init_settings_post();

    g_initialized = 1;
    LOG_V("mg_init_gles: done (%d GL ES functions resolved)\n", (int)sizeof(g_gles_func));
}
#endif
