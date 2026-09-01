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
    // 2.0.16: resolve from this layer's OWN image handle instead of any
    // special dlsym handle. The special handles (RTLD_SELF / RTLD_NEXT /
    // RTLD_DEFAULT) derive their "caller image" from
    // __builtin_return_address(0) inside dyld -- but the host launcher
    // rebinding dlsym process-wide (fishhook) makes that address land in the
    // HOST BINARY for every dlsym issued from this layer, so RTLD_SELF searched
    // the host's image and its dependency subtree instead of this layer, and
    // the result depended on where the host's dlopen'd renderers (this layer,
    // ANGLE) happen to sit in that subtree. 2.0.15 shipped exactly that trap:
    // RTLD_SELF was expected to find this layer's exports first, yet the device
    // still reported renderpearl's "glGetError mismatch" (LWJGL's provider and
    // the hooked SDL_GL_GetProcAddress disagreeing about glGetError), and the
    // OpenGL backend was rejected again in favour of MoltenVK.
    //
    // A handle-based dlsym has none of that ambiguity: the handle pins the
    // search to THIS image (then its dependents), so this layer's exports win
    // for every name it implements, independent of image order, of who is
    // calling, and of any interposing layers. The handle is obtained via
    // dladdr on one of this layer's own functions + dlopen(RTLD_NOLOAD), which
    // can never map a second copy of the image. RTLD_DEFAULT stays as the
    // fallback for names this layer does not export (extension entry points
    // that live only in the backend).
    static void* own_image = nullptr;
    static bool own_image_tried = false;
    if (!own_image_tried) {
        own_image_tried = true;
        Dl_info info{};
        if (dladdr((void*)&glXGetProcAddress, &info) && info.dli_fname != nullptr) {
            // RTLD_NOLOAD: succeed only if the image is already loaded -- it is,
            // we are executing inside it -- and never map a duplicate.
            own_image = dlopen(info.dli_fname, RTLD_LAZY | RTLD_NOLOAD);
            if (own_image == nullptr) {
                own_image = dlopen(info.dli_fname, RTLD_LAZY | RTLD_GLOBAL);
            }
            if (own_image != nullptr) {
                LOG_W_FORCE("[MG] 2.0.16 own-image resolution: handle for %s", info.dli_fname)
            } else {
                // dlerror() clears the error state on read -- capture once.
                const char* dlerr = dlerror();
                LOG_W_FORCE("[MG] 2.0.16 own-image resolution: dlopen('%s') failed (%s), falling back to RTLD_DEFAULT",
                            info.dli_fname, dlerr != nullptr ? dlerr : "unknown")
            }
        } else {
            LOG_W_FORCE("[MG] 2.0.16 own-image resolution: dladdr could not identify this image, falling back to RTLD_DEFAULT")
        }
    }
    void* resolved = nullptr;
    if (own_image != nullptr) {
        resolved = dlsym(own_image, real_func_name.c_str());
    }
    if (resolved == nullptr) {
        resolved = dlsym(RTLD_DEFAULT, real_func_name.c_str());
    }
    // Flat-namespace canary, added in 2.0.10 when the shared-symbol overlap
    // with the host's ANGLE libGLESv2 was first mapped. Since 2.0.16 the
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