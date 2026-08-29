// MobileGlues - config/settings.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_PLUGIN_SETTINGS_H
#define MOBILEGLUES_PLUGIN_SETTINGS_H

#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#include <cctype>

#if !defined(__APPLE__)
#include <stddef.h>
#else
typedef unsigned long size_t;
#endif

#define DEFAULT_GL_VERSION 40

// The distinct multi-draw *implementations*. Which of them are actually distinct
// differs per entry point; md_entry_desc_t::allowed encodes that.
//
// GLES core has no multi-draw command at all -- not even 3.2, which added only
// the singular glDrawElementsBaseVertex. Every batched backend below therefore
// comes from an extension, and each is named after the one that provides it.
// The first three issue one driver call per sub-draw; the next three issue one
// call for the whole batch.
//
// These integers are never persisted: config.json carries the NAMES, so adding a
// backend or an entry point can never repoint a value a user already wrote.
enum class md_backend_t : int {
    Auto = 0,        // "auto"            pick the best available for this entry point
    Unroll,          // "unroll"          N x glDraw{Arrays,Elements}
    BaseVertex,      // "basevertex"      N x glDrawElementsBaseVertex
    Indirect,        // "indirect"        N x glDraw{Arrays,Elements}Indirect
    MultiArrays,     // "multiarrays"     1 x glMultiDraw{Arrays,Elements}EXT
                     //                     (GL_EXT_multi_draw_arrays / GL_ANGLE_multi_draw)
    MultiBaseVertex, // "multibasevertex" 1 x glMultiDrawElementsBaseVertexEXT
                     //                     (GL_EXT/OES_draw_elements_base_vertex)
    MultiIndirect,   // "multiindirect"   1 x glMultiDraw{Arrays,Elements}IndirectEXT
                     //                     (GL_EXT_multi_draw_indirect)
    Compute,         // "compute"         compute-shader index fusion
    MaxValue
};

// The entry points that have more than one implementation to choose between.
// glMultiDraw*IndirectCount are absent on purpose: they have exactly one.
enum class md_entry_t : int {
    Arrays = 0,         // glMultiDrawArrays
    Elements,           // glMultiDrawElements
    ElementsBaseVertex, // glMultiDrawElementsBaseVertex
    ArraysIndirect,     // glMultiDrawArraysIndirect
    ElementsIndirect,   // glMultiDrawElementsIndirect
    MaxValue
};

enum class AngleConfig : int {
    DisableIfPossible = 0,
    EnableIfPossible = 1,
    ForceDisable = 2,
    ForceEnable = 3
};

enum class AngleMode : int {
    Disabled = 0,
    Enabled = 1
};

enum class IgnoreErrorLevel : int {
    None = 0,
    Partial = 1,
    Full = 2
};

enum class NoErrorConfig : int {
    Auto = 0,
    Disable = 1,
    Level1 = 2,
    Level2 = 3
};

enum class AngleDepthClearFixMode : int {
    Disabled = 0,
    Mode1 = 1,
    Mode2 = 2,
    MaxValue
};

enum class HideMGEnvLevel : int {
    Disabled = 0,
    Level1 = 1, // Hide MG extensions and randomise OpenGL version/renderer,
    MaxValue
};

struct Version {
    int Major{0};
    int Minor{0};
    int Patch{0};

    Version() = default;

    Version(int major, int minor, int patch) : Major(major), Minor(minor), Patch(patch) {}

    Version(const std::string& str) {
        size_t start = str.find_first_not_of(" \t\n\r");
        size_t end = str.find_last_not_of(" \t\n\r");
        if (start == std::string::npos) {
            return;
        }
        std::string s = str.substr(start, end - start + 1);

        std::vector<int> parts;
        std::istringstream iss(s);
        std::string token;
        while (std::getline(iss, token, '.') && parts.size() < 3) {
            try {
                parts.push_back(std::stoi(token));
            }
            catch (...) {
                parts.push_back(0);
            }
        }
        while (parts.size() < 3) {
            parts.push_back(0);
        }
        Major = parts[0];
        Minor = parts[1];
        Patch = parts[2];
    }

    explicit Version(int code) {
        if (code < 0) code = -code;
        std::string s = std::to_string(code);
        for (size_t i = 0; i < 3; ++i) {
            int digit = 0;
            if (i < s.size() && std::isdigit(s[i])) {
                digit = s[i] - '0';
            }
            switch (i) {
            case 0:
                Major = digit;
                break;
            case 1:
                Minor = digit;
                break;
            case 2:
                Patch = digit;
                break;
            }
        }
    }

    std::string toString() const {
        std::ostringstream oss;
        oss << Major << '.' << Minor << '.' << Patch;
        return oss.str();
    }

    int toInt(int digit_count = 3) const {
        switch (digit_count) {
        case 1:
            return Major;
        case 2:
            return Major * 10 + Minor;
        default:
            return Major * 100 + Minor * 10 + Patch;
        }
    }

    bool isEmpty() const { return Major == 0 && Minor == 0 && Patch == 0; }
};

typedef enum class FSR1_Quality_Preset : int { // may be useless
    Disabled = 0,
    UltraQuality, // 1
    Quality,      // 2
    Balanced,     // 3
    Performance,  // 4
    MaxValue      // 5
};

constexpr int MD_ENTRY_COUNT = static_cast<int>(md_entry_t::MaxValue);
constexpr int MD_BACKEND_COUNT = static_cast<int>(md_backend_t::MaxValue);

struct global_settings_t {
    AngleMode angle;
    // The two halves of how `angle` came to be, kept so a report can tell the
    // truth. `angle` alone cannot: EnableIfPossible resolves to Disabled on a
    // device the probe rejects, and then nothing downstream can distinguish
    // "user did not want ANGLE" from "user wanted it, device cannot".
    AngleConfig angle_config; // the raw configured choice, before device gating
    bool angle_supported;     // what checkIfANGLESupported() said at init
    IgnoreErrorLevel ignore_error;
    bool ext_compute_shader;
    bool ext_timer_query;
    bool ext_direct_state_access;
    bool buffer_coherent_as_flush;
    size_t max_glsl_cache_size;
    md_backend_t multidraw_backend[MD_ENTRY_COUNT];
    // Per entry point: the user's preference order over the backends that are a
    // distinct implementation there AND that this device can run, best first.
    // Built by init_settings_post() from "multidrawOrder" (global, may contain
    // the pseudo item "native") and "multidrawOrder<EntryPoint>" (per-function
    // exception, concrete backends only). The runtime fallback chains walk this
    // order too, so a degradation never jumps somewhere the user ranked lower
    // than necessary -- or higher than the failing backend.
    md_backend_t multidraw_order[MD_ENTRY_COUNT][MD_BACKEND_COUNT];
    int multidraw_order_len[MD_ENTRY_COUNT];
    AngleDepthClearFixMode angle_depth_clear_fix_mode;
    Version custom_gl_version;
    FSR1_Quality_Preset fsr1_setting;
    HideMGEnvLevel hide_mg_env_level;
};

extern global_settings_t global_settings;

void init_settings();
void init_settings_post();
std::string dump_settings_string(std::string prefix = "");
void set_multidraw_setting();

// Resolved backend for one entry point. Always a concrete backend after
// init_settings_post(); never md_backend_t::Auto.
inline md_backend_t multidraw_backend_of(md_entry_t e) {
    return global_settings.multidraw_backend[static_cast<int>(e)];
}
const char* md_backend_name(md_backend_t b);

// The backend the runtime fallback chains should try after `cur` failed for
// this entry point: the next item in the user's order. When `cur` is not in the
// order (a mg_* symbol reached by a direct dlsym), the last item is returned so
// the chain terminates instead of cycling. Returns the last item too when `cur`
// already is the last -- callers guard against calling back into `cur`.
md_backend_t md_next_backend(md_entry_t e, md_backend_t cur);

// Suffix of the mg_<entry>_<suffix> symbol implementing a backend. One table so
// the dispatcher in gl/multidraw.cpp and the symbol glx/lookup.cpp hands to the
// application cannot disagree about which implementation a setting selects.
const char* md_backend_suffix(md_backend_t b);

// Defined in gl/multidraw.cpp: resolves GL_EXT_multi_draw_arrays lazily, because
// the GLES loader does not carry those entry points and gles/* is not ours to
// change. Safe to call once a context is current.
bool mg_multi_draw_arrays_ext_available();
bool mg_multi_draw_elements_basevertex_ext_available();

#endif // MOBILEGLUES_PLUGIN_SETTINGS_H
