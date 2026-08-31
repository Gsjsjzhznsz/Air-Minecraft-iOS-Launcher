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
#ifndef RTLD_SELF
#define RTLD_SELF ((void *) -3)
#endif
    // 2.0.15: resolve from this layer's OWN image first. RTLD_SELF searches
    // the calling image (this layer) and then its dependents, so this layer's
    // exports win for every name it implements -- independent of dyld image
    // order. RTLD_DEFAULT alone searches the process-wide flat namespace,
    // where this layer and the host's ANGLE libGLESv2 export the same gl*
    // names and whichever image dyld put earlier wins. That order flipped in
    // the MC 26.3 SDL3 host (ANGLE loads first there): the host's LWJGL
    // provider bound ANGLE's GLES exports through this very function, while
    // the host's hooked SDL_GL_GetProcAddress returned this layer's exports.
    // renderpearl's GlBackend.loadLibrary demands pointer equality between
    // the two for "glGetError" ("glGetError mismatch"), so the OpenGL backend
    // was rejected and the game fell back to MoltenVK. RTLD_DEFAULT stays as
    // the fallback for names this layer does not export (the RTLD_SELF search
    // already covers this layer's ANGLE dependents before it fails).
    void* resolved = dlsym(RTLD_SELF, real_func_name.c_str());
    if (resolved == nullptr) {
        resolved = dlsym(RTLD_DEFAULT, real_func_name.c_str());
    }
    // Flat-namespace canary, added in 2.0.10 when the shared-symbol overlap
    // with the host's ANGLE libGLESv2 was first mapped. Since 2.0.15 the
    // resolution above no longer depends on the flat order, so a theft line
    // is environment diagnostics (who else exports gl* in this process), not
    // a functional failure by itself. It still matters: anything that binds
    // these names WITHOUT going through this function -- direct flat-namespace
    // linkage in the host binary, dlsym(RTLD_DEFAULT) in host code -- gets
    // the winner of that race, which is the failure shape the 2.0.9
    // diagnostics hinted at (the depth-attach and composite probes never
    // fired while the same-file blit probe did).
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