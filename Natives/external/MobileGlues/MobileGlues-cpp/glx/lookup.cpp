// MobileGlues - glx/lookup.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "lookup.h"

#include "../config/settings.h"
#include "../gl/envvars.h"
#include "../gl/log.h"
#include "../gl/mg.h"
#include "../gl/framebuffer.h"
#include "../gl/texture.h"
#include "../gl/drawing.h"
#include "../includes.h"
#include <EGL/egl.h>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

#define DEBUG 0

// The application can ask for a multi-draw entry point by name and call the
// result directly, bypassing the dispatcher in gl/multidraw.cpp. Hand back the
// symbol implementing whatever backend that entry point resolved to, so both
// routes agree. The suffix table lives in config/settings.cpp for exactly that
// reason.
std::string handle_multidraw_func_name(std::string name) {
    md_entry_t entry;
    if (name == "glMultiDrawElements") {
        entry = md_entry_t::Elements;
    } else if (name == "glMultiDrawElementsBaseVertex") {
        entry = md_entry_t::ElementsBaseVertex;
    } else {
        // Everything else -- glMultiDrawArrays, the two *Indirect entry points and
        // every EXT/ARB alias -- is a single exported definition that selects its
        // own backend internally, so the plain name is already correct.
        return name;
    }

    const char* suffix = md_backend_suffix(multidraw_backend_of(entry));
    if (!suffix) {
        // Auto should never survive init_settings_post. Fall back to the
        // dispatcher rather than to dlsym of a name that does not exist.
        LOG_W_FORCE("handle_multidraw_func_name: %s has no resolved backend, using the dispatcher", name.c_str())
        return name;
    }
    return "mg_" + name + suffix;
}

void* glXGetProcAddress(const char* name) {
    LOG()
    std::string real_func_name = handle_multidraw_func_name(std::string(name));
#ifdef __APPLE__
    void* resolved = dlsym((void*)(~(uintptr_t)0), real_func_name.c_str());
    // RTLD_DEFAULT searches the process-wide flat namespace, which contains
    // this layer AND the host's ANGLE libGLESv2. Whichever image dyld put
    // earlier wins for every symbol both export. If ANGLE wins for a function
    // this layer wraps, the application binds the backend DIRECTLY and this
    // layer silently never sees the call -- the exact failure shape the 2.0.9
    // diagnostics hinted at (the depth-attach and composite probes never
    // fired while the same-file blit probe did). Grade the three functions the
    // transparency pipeline rides on, once, against this layer's own exports.
    static bool mg_theft_checked = false;
    if (!mg_theft_checked) {
        mg_theft_checked = true;
        // Taking the address of this layer's own exports binds locally, so the
        // comparison answers "did the flat namespace hand the application one
        // of OUR entry points or someone else's".
        struct { const char* name; void* mine; } probes[3] = {
            {"glFramebufferTexture2D", (void*)&glFramebufferTexture2D},
            {"glTexImage2D", (void*)&glTexImage2D},
            {"glDrawArrays", (void*)&glDrawArrays},
        };
        for (int i = 0; i < 3; ++i) {
            void* flat = dlsym((void*)(~(uintptr_t)0), probes[i].name);
            if (flat != probes[i].mine) {
                LOG_W_FORCE("[MG] SYMBOL THEFT: flat namespace resolves %s to %p, this layer's export is %p -- "
                            "the application is calling someone else for this function",
                            probes[i].name, flat, probes[i].mine)
            }
        }
    }
    return resolved;
#else

    void* proc = nullptr;

    proc = dlsym(RTLD_DEFAULT, real_func_name.c_str());

    if (!proc) {
        LOG_W("Failed to get OpenGL function: %s", real_func_name.c_str())
        return nullptr;
    }

    return proc;
#endif
}

void* glXGetProcAddressARB(const char* name) {
    return glXGetProcAddress(name);
}