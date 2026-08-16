// MobileGlues - gl/enable.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "enable.h"
#include "pixel.h"
#include "../gles/loader.h"
#include "log.h"
#include "mg.h"
#include "../egl/context.h"
#include <cstring>

#define DEBUG 0

// Report a rejected argument once per site. This layer cannot raise a GL error
// -- glGetError always answers GL_NO_ERROR by design -- so an unusable argument
// means "do nothing" plus one line a user can paste into a bug report. LOG_W and
// LOG_E compile to nothing in release builds, hence LOG_W_FORCE.
#define EN_WARN_ONCE(...)                                                                                              \
    do {                                                                                                               \
        static bool mg_en_warned = false;                                                                              \
        if (!mg_en_warned) {                                                                                           \
            mg_en_warned = true;                                                                                       \
            LOG_W_FORCE(__VA_ARGS__)                                                                                   \
        }                                                                                                              \
    } while (0)

// ---------------------------------------------------------------------------
// Capability descriptors
// ---------------------------------------------------------------------------

namespace {

// How a capability reaches the driver.
enum backing_t : unsigned char {
    BK_NATIVE,   // GLES 3.2 core knows this enum: always forward
    BK_EXT,      // an extension supplies it using the same enum value: forward
                 // only when that extension is present, otherwise record only
    BK_VIRTUAL,  // GLES has no equivalent: record only, never forward
};

struct cap_desc_t {
    GLenum cap;
    mg_cap_index index;
    backing_t backing;
    GLboolean initial;
    const char* name;
};

// GL 4.6 initial values are from /docsgl/gl4/glEnable.xhtml. Only GL_DITHER is
// GL_TRUE by default; GL_MULTISAMPLE is also GL_TRUE per the specification but
// is seeded from the framebuffer instead, see mg_enable_reset().
//
// The order is not cosmetic: find_cap() indexes this array by mg_cap_index, so
// entry i must be the descriptor for capability i. The static assertions below
// hold that promise at compile time.
constexpr cap_desc_t k_caps[] = {
    {GL_BLEND, MGC_BLEND, BK_NATIVE, GL_FALSE, "GL_BLEND"},
    {GL_COLOR_LOGIC_OP, MGC_COLOR_LOGIC_OP, BK_VIRTUAL, GL_FALSE, "GL_COLOR_LOGIC_OP"},
    {GL_CULL_FACE, MGC_CULL_FACE, BK_NATIVE, GL_FALSE, "GL_CULL_FACE"},
    {GL_DEBUG_OUTPUT, MGC_DEBUG_OUTPUT, BK_NATIVE, GL_FALSE, "GL_DEBUG_OUTPUT"},
    {GL_DEBUG_OUTPUT_SYNCHRONOUS, MGC_DEBUG_OUTPUT_SYNCHRONOUS, BK_NATIVE, GL_FALSE, "GL_DEBUG_OUTPUT_SYNCHRONOUS"},
    {GL_DEPTH_CLAMP, MGC_DEPTH_CLAMP, BK_EXT, GL_FALSE, "GL_DEPTH_CLAMP"},
    {GL_DEPTH_TEST, MGC_DEPTH_TEST, BK_NATIVE, GL_FALSE, "GL_DEPTH_TEST"},
    {GL_DITHER, MGC_DITHER, BK_NATIVE, GL_TRUE, "GL_DITHER"},
    {GL_FRAMEBUFFER_SRGB, MGC_FRAMEBUFFER_SRGB, BK_EXT, GL_FALSE, "GL_FRAMEBUFFER_SRGB"},
    {GL_LINE_SMOOTH, MGC_LINE_SMOOTH, BK_VIRTUAL, GL_FALSE, "GL_LINE_SMOOTH"},
    {GL_MULTISAMPLE, MGC_MULTISAMPLE, BK_EXT, GL_FALSE, "GL_MULTISAMPLE"},
    {GL_POLYGON_OFFSET_FILL, MGC_POLYGON_OFFSET_FILL, BK_NATIVE, GL_FALSE, "GL_POLYGON_OFFSET_FILL"},
    {GL_POLYGON_OFFSET_LINE, MGC_POLYGON_OFFSET_LINE, BK_EXT, GL_FALSE, "GL_POLYGON_OFFSET_LINE"},
    {GL_POLYGON_OFFSET_POINT, MGC_POLYGON_OFFSET_POINT, BK_EXT, GL_FALSE, "GL_POLYGON_OFFSET_POINT"},
    {GL_POLYGON_SMOOTH, MGC_POLYGON_SMOOTH, BK_VIRTUAL, GL_FALSE, "GL_POLYGON_SMOOTH"},
    {GL_PRIMITIVE_RESTART, MGC_PRIMITIVE_RESTART, BK_VIRTUAL, GL_FALSE, "GL_PRIMITIVE_RESTART"},
    {GL_PRIMITIVE_RESTART_FIXED_INDEX, MGC_PRIMITIVE_RESTART_FIXED_INDEX, BK_NATIVE, GL_FALSE,
     "GL_PRIMITIVE_RESTART_FIXED_INDEX"},
    {GL_PROGRAM_POINT_SIZE, MGC_PROGRAM_POINT_SIZE, BK_VIRTUAL, GL_FALSE, "GL_PROGRAM_POINT_SIZE"},
    {GL_RASTERIZER_DISCARD, MGC_RASTERIZER_DISCARD, BK_NATIVE, GL_FALSE, "GL_RASTERIZER_DISCARD"},
    {GL_SAMPLE_ALPHA_TO_COVERAGE, MGC_SAMPLE_ALPHA_TO_COVERAGE, BK_NATIVE, GL_FALSE, "GL_SAMPLE_ALPHA_TO_COVERAGE"},
    {GL_SAMPLE_ALPHA_TO_ONE, MGC_SAMPLE_ALPHA_TO_ONE, BK_EXT, GL_FALSE, "GL_SAMPLE_ALPHA_TO_ONE"},
    {GL_SAMPLE_COVERAGE, MGC_SAMPLE_COVERAGE, BK_NATIVE, GL_FALSE, "GL_SAMPLE_COVERAGE"},
    {GL_SAMPLE_MASK, MGC_SAMPLE_MASK, BK_NATIVE, GL_FALSE, "GL_SAMPLE_MASK"},
    {GL_SAMPLE_SHADING, MGC_SAMPLE_SHADING, BK_EXT, GL_FALSE, "GL_SAMPLE_SHADING"},
    {GL_SCISSOR_TEST, MGC_SCISSOR_TEST, BK_NATIVE, GL_FALSE, "GL_SCISSOR_TEST"},
    {GL_STENCIL_TEST, MGC_STENCIL_TEST, BK_NATIVE, GL_FALSE, "GL_STENCIL_TEST"},
    {GL_TEXTURE_CUBE_MAP_SEAMLESS, MGC_TEXTURE_CUBE_MAP_SEAMLESS, BK_VIRTUAL, GL_FALSE,
     "GL_TEXTURE_CUBE_MAP_SEAMLESS"},
};

constexpr int k_cap_count = static_cast<int>(sizeof(k_caps) / sizeof(k_caps[0]));

constexpr bool cap_table_is_ordered_by_index() {
    for (int i = 0; i < k_cap_count; ++i) {
        if (static_cast<int>(k_caps[i].index) != i) return false;
    }
    return true;
}

static_assert(k_cap_count == MGC_COUNT, "every mg_cap_index needs exactly one descriptor");
static_assert(cap_table_is_ordered_by_index(), "k_caps must be ordered so k_caps[MGC_X] is the descriptor for X");

// A switch and not a walk of k_caps. This runs on every glEnable/glDisable and,
// through mg_enable_query(), on every glGetBooleanv/glGetFloatv/glGetDoublev/
// glGetInteger64v and on the default branch of glGetIntegerv -- so a query for a
// pname this table does not own used to pay 27 comparisons before falling
// through to the driver. The case labels are sparse enum values, which the
// compiler resolves by a decision tree rather than in sequence.
//
// The returned pointer is into k_caps exactly as before, so every caller below
// keeps reading the same descriptor fields. constexpr only so that the assertion
// underneath can walk the table through it -- a capability added to k_caps but
// not to this switch would otherwise become silently unknown, warned about once
// and reported disabled forever.
constexpr const cap_desc_t* find_cap(GLenum cap) {
    switch (cap) {
    case GL_BLEND:
        return &k_caps[MGC_BLEND];
    case GL_COLOR_LOGIC_OP:
        return &k_caps[MGC_COLOR_LOGIC_OP];
    case GL_CULL_FACE:
        return &k_caps[MGC_CULL_FACE];
    case GL_DEBUG_OUTPUT:
        return &k_caps[MGC_DEBUG_OUTPUT];
    case GL_DEBUG_OUTPUT_SYNCHRONOUS:
        return &k_caps[MGC_DEBUG_OUTPUT_SYNCHRONOUS];
    case GL_DEPTH_CLAMP:
        return &k_caps[MGC_DEPTH_CLAMP];
    case GL_DEPTH_TEST:
        return &k_caps[MGC_DEPTH_TEST];
    case GL_DITHER:
        return &k_caps[MGC_DITHER];
    case GL_FRAMEBUFFER_SRGB:
        return &k_caps[MGC_FRAMEBUFFER_SRGB];
    case GL_LINE_SMOOTH:
        return &k_caps[MGC_LINE_SMOOTH];
    case GL_MULTISAMPLE:
        return &k_caps[MGC_MULTISAMPLE];
    case GL_POLYGON_OFFSET_FILL:
        return &k_caps[MGC_POLYGON_OFFSET_FILL];
    case GL_POLYGON_OFFSET_LINE:
        return &k_caps[MGC_POLYGON_OFFSET_LINE];
    case GL_POLYGON_OFFSET_POINT:
        return &k_caps[MGC_POLYGON_OFFSET_POINT];
    case GL_POLYGON_SMOOTH:
        return &k_caps[MGC_POLYGON_SMOOTH];
    case GL_PRIMITIVE_RESTART:
        return &k_caps[MGC_PRIMITIVE_RESTART];
    case GL_PRIMITIVE_RESTART_FIXED_INDEX:
        return &k_caps[MGC_PRIMITIVE_RESTART_FIXED_INDEX];
    case GL_PROGRAM_POINT_SIZE:
        return &k_caps[MGC_PROGRAM_POINT_SIZE];
    case GL_RASTERIZER_DISCARD:
        return &k_caps[MGC_RASTERIZER_DISCARD];
    case GL_SAMPLE_ALPHA_TO_COVERAGE:
        return &k_caps[MGC_SAMPLE_ALPHA_TO_COVERAGE];
    case GL_SAMPLE_ALPHA_TO_ONE:
        return &k_caps[MGC_SAMPLE_ALPHA_TO_ONE];
    case GL_SAMPLE_COVERAGE:
        return &k_caps[MGC_SAMPLE_COVERAGE];
    case GL_SAMPLE_MASK:
        return &k_caps[MGC_SAMPLE_MASK];
    case GL_SAMPLE_SHADING:
        return &k_caps[MGC_SAMPLE_SHADING];
    case GL_SCISSOR_TEST:
        return &k_caps[MGC_SCISSOR_TEST];
    case GL_STENCIL_TEST:
        return &k_caps[MGC_STENCIL_TEST];
    case GL_TEXTURE_CUBE_MAP_SEAMLESS:
        return &k_caps[MGC_TEXTURE_CUBE_MAP_SEAMLESS];
    default:
        return nullptr;
    }
}

constexpr bool every_cap_is_reachable() {
    for (int i = 0; i < k_cap_count; ++i) {
        if (find_cap(k_caps[i].cap) != &k_caps[i]) return false;
    }
    return true;
}

static_assert(every_cap_is_reachable(), "find_cap() is missing a case for a capability listed in k_caps");

// Whether the extension backing a BK_EXT capability is present. Checked at use
// rather than cached, because the caps are filled in during init and a device
// that has the extension must keep getting the real thing.
bool ext_backing_present(GLenum cap) {
    switch (cap) {
    case GL_DEPTH_CLAMP:
        return g_gles_caps.GL_EXT_depth_clamp != 0;
    case GL_FRAMEBUFFER_SRGB:
        return g_gles_caps.GL_EXT_sRGB_write_control != 0;
    case GL_MULTISAMPLE:
    case GL_SAMPLE_ALPHA_TO_ONE:
        return g_gles_caps.GL_EXT_multisample_compatibility != 0;
    case GL_POLYGON_OFFSET_LINE:
    case GL_POLYGON_OFFSET_POINT:
        return g_gles_caps.GL_NV_polygon_mode != 0;
    case GL_SAMPLE_SHADING:
        // Core from ES 3.2, an extension before it.
        return (g_gles_caps.major > 3 || (g_gles_caps.major == 3 && g_gles_caps.minor >= 2)) ||
               g_gles_caps.GL_OES_sample_shading != 0;
    default:
        return false;
    }
}

bool forwards_to_driver(const cap_desc_t& d) {
    if (d.backing == BK_NATIVE) return true;
    if (d.backing == BK_EXT) return ext_backing_present(d.cap);
    return false;
}

bool is_clip_distance(GLenum cap, GLuint* slot) {
    if (cap < GL_CLIP_DISTANCE0) return false;
    const GLuint n = static_cast<GLuint>(cap) - static_cast<GLuint>(GL_CLIP_DISTANCE0);
    if (n >= MG_MAX_CLIP_DISTANCES) return false;
    *slot = n;
    return true;
}

// Fallback used before any context has been made current, and for a context this
// layer never saw created (the bootstrap probe context, or one made before the
// library was loaded).
mg_enable_state_t g_default_state;

// Whether the table may be trusted to say what the driver already has, which is
// what lets mg_set_enabled() drop a call the driver would answer with no change.
//
// Two things make it untrue, and mg_enable_sync_driver() is the line between
// them. Before it runs the table is deliberately out of step -- GL_MULTISAMPLE
// and GL_FRAMEBUFFER_SRGB carry their GL 4.6 values, which are not the ones GLES
// and GL_EXT_sRGB_write_control start from -- and it never runs for
// g_default_state, which every context this layer did not create shares. Two
// such contexts have one table between them but separate driver state, so a
// value one of them set would suppress the call the other still needs.
//
// Rule 4 audit, everything outside this file that reaches GLES.glEnable or
// GLES.glDisable directly:
//   gl/restart.cpp, gl/drawing.cpp, gl/multidraw.cpp -- every one of them the
//     same capability, GL_PRIMITIVE_RESTART_FIXED_INDEX, borrowed for the length
//     of a draw because GL_PRIMITIVE_RESTART itself is never forwarded. Each site
//     first asks the table whether it is already on -- through
//     mg_restart_needs_driver_fixed(), which answers false in that case, or
//     through mg_enable_get() directly -- and only borrows it when it is off,
//     switching it back afterwards, the scoped ones from a destructor so an early
//     return cannot escape it. Net zero against the table either way.
//   gl/gl.cpp DrawDepthClearTri -- colour mask, depth mask and depth func, each
//     restored from a value queried first. It enables no capability at all.
//   gl/FSR1/FSR1.cpp GLStateGuard -- program, VAO, buffers, texture and
//     framebuffer bindings only, no capability.
//   bench/multidraw_bench.cpp -- GL_DEPTH_TEST and GL_CULL_FACE enabled with no
//     matching disable, on a context this layer does track. Real divergence, but
//     unreachable: it is behind mg_multidraw_bench_run(), which only the plugin
//     app dlsyms in its own process, and nothing there calls this layer's
//     glEnable/glDisable afterwards -- the benchmark itself speaks to GLES
//     directly throughout. No capability is excluded from the filter for it.
// Nothing in the tree calls GLES.glEnablei or GLES.glDisablei.
bool table_matches_driver(const mg_enable_state_t* st) {
    return st->driver_synced;
}

} // namespace

// ---------------------------------------------------------------------------

void mg_enable_reset(mg_enable_state_t* state) {
    memset(state, 0, sizeof(*state));
    for (const auto& d : k_caps) {
        state->scalar[d.index] = d.initial;
    }

    // GL 4.6 says GL_MULTISAMPLE starts enabled. Where the extension is missing
    // the value is seeded from the framebuffer instead, but that has to wait for
    // the context to be current -- see mg_enable_sync_driver().
    state->scalar[MGC_MULTISAMPLE] = GL_TRUE;

    // GL_BLEND is per draw buffer and GL_SCISSOR_TEST per viewport; the scalar
    // form of each is index 0.
    for (int i = 0; i < MG_MAX_DRAW_BUFFERS; ++i) state->blend_indexed[i] = GL_FALSE;
    for (int i = 0; i < MG_MAX_VIEWPORTS; ++i) state->scissor_indexed[i] = GL_FALSE;

    state->primitive_restart_index = 0;
    state->initialised = true;
    state->driver_synced = false;
}

void mg_enable_sync_driver(mg_enable_state_t* state) {
    if (state == nullptr || state->driver_synced) return;
    state->driver_synced = true;

    // Without GL_EXT_multisample_compatibility the application cannot turn
    // multisampling off anyway -- it is decided by the EGL config -- so reporting
    // the specification's GL_TRUE on a single-sampled framebuffer would be a lie
    // in the other direction. Seed it from what the framebuffer actually is, then
    // track whatever the application sets so enable/disable still round-trips.
    if (!ext_backing_present(GL_MULTISAMPLE)) {
        GLint samples = 0;
        if (GLES.glGetIntegerv) GLES.glGetIntegerv(GL_SAMPLES, &samples);
        state->scalar[MGC_MULTISAMPLE] = samples > 0 ? GL_TRUE : GL_FALSE;
    }

    // Most capabilities start out the same in both APIs, so the table and the
    // driver agree without anyone saying anything. GL_FRAMEBUFFER_SRGB does not:
    // GL 4.6 starts it disabled, and GL_EXT_sRGB_write_control -- the only thing
    // that makes it settable on GLES -- specifies GL_TRUE as its initial value.
    // Left alone, a draw into an SRGB8_ALPHA8 target gets sRGB-encoded while
    // glIsEnabled(GL_FRAMEBUFFER_SRGB) truthfully reports the table's GL_FALSE.
    // Push the table's value down so the two agree from the first draw.
    if (ext_backing_present(GL_FRAMEBUFFER_SRGB) && GLES.glDisable != nullptr) {
        if (state->scalar[MGC_FRAMEBUFFER_SRGB] == GL_FALSE) {
            GLES.glDisable(GL_FRAMEBUFFER_SRGB);
        } else if (GLES.glEnable != nullptr) {
            GLES.glEnable(GL_FRAMEBUFFER_SRGB);
        }
    }
}

mg_enable_state_t* mg_enable_state(void) {
    MGContext* ctx = g_current_ctx;
    if (ctx != nullptr) return &ctx->enable;
    if (!g_default_state.initialised) mg_enable_reset(&g_default_state);
    return &g_default_state;
}

GLboolean mg_enable_get(GLenum cap, GLuint index) {
    mg_enable_state_t* st = mg_enable_state();

    GLuint slot = 0;
    if (is_clip_distance(cap, &slot)) {
        return (st->clip_distance_mask & (1u << slot)) ? GL_TRUE : GL_FALSE;
    }

    const cap_desc_t* d = find_cap(cap);
    if (!d) return GL_FALSE;

    if (d->cap == GL_BLEND && index < MG_MAX_DRAW_BUFFERS) return st->blend_indexed[index];
    if (d->cap == GL_SCISSOR_TEST && index < MG_MAX_VIEWPORTS) return st->scissor_indexed[index];
    return st->scalar[d->index];
}

bool mg_enable_query(GLenum pname, GLboolean* out) {
    GLuint slot = 0;
    if (is_clip_distance(pname, &slot)) {
        *out = mg_enable_get(pname, 0);
        return true;
    }
    if (!find_cap(pname)) return false;
    *out = mg_enable_get(pname, 0);
    return true;
}

bool mg_enable_query_int(GLenum pname, GLint* out) {
    switch (pname) {
    case GL_PRIMITIVE_RESTART_INDEX:
        *out = static_cast<GLint>(mg_enable_state()->primitive_restart_index);
        return true;
    case GL_MAX_CLIP_DISTANCES:
        // Reported as the number the table can actually track. GL 4.6 requires at
        // least 8; the driver's own answer is meaningless here because GLES has no
        // such limit, and the query used to leave the output untouched -- an
        // application reading it got whatever was on its stack.
        *out = MG_MAX_CLIP_DISTANCES;
        return true;
    case GL_MAX_VIEWPORTS:
        // GL 4.6 requires at least 16. The state for all of them is tracked so an
        // application that reads this number and then indexes up to it gets
        // consistent answers back. Only viewport 0 reaches the driver, because
        // glViewportIndexedf and glScissorIndexed are still stubs -- a scissor
        // test enabled on viewport 3 is remembered and reported, not applied.
        *out = MG_MAX_VIEWPORTS;
        return true;
    case GL_MAX_DRAW_BUFFERS: {
        // Clamped to what blend_indexed can hold, so glEnablei(GL_BLEND, i) is
        // never rejected for an index the application was told it could use.
        GLint n = 0;
        if (GLES.glGetIntegerv) GLES.glGetIntegerv(GL_MAX_DRAW_BUFFERS, &n);
        if (n <= 0) n = 1;
        *out = n > MG_MAX_DRAW_BUFFERS ? MG_MAX_DRAW_BUFFERS : n;
        return true;
    }
    default:
        return false;
    }
}

void mg_enable_set_primitive_restart_index(GLuint index) {
    mg_enable_state()->primitive_restart_index = index;
}

bool mg_primitive_restart_enabled(void) {
    mg_enable_state_t* st = mg_enable_state();
    return st->scalar[MGC_PRIMITIVE_RESTART] || st->scalar[MGC_PRIMITIVE_RESTART_FIXED_INDEX];
}

GLuint mg_primitive_restart_index_for(GLenum type) {
    mg_enable_state_t* st = mg_enable_state();
    // GL 4.6: when GL_PRIMITIVE_RESTART_FIXED_INDEX is enabled the fixed value
    // for the index type is used and glPrimitiveRestartIndex is ignored.
    if (st->scalar[MGC_PRIMITIVE_RESTART_FIXED_INDEX] || !st->scalar[MGC_PRIMITIVE_RESTART]) {
        switch (type) {
        case GL_UNSIGNED_BYTE:
            return 0xFFu;
        case GL_UNSIGNED_SHORT:
            return 0xFFFFu;
        default:
            return 0xFFFFFFFFu;
        }
    }
    return st->primitive_restart_index;
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

static void mg_set_enabled(GLenum cap, GLuint index, bool indexed, GLboolean value) {
    mg_enable_state_t* st = mg_enable_state();

    GLuint slot = 0;
    if (is_clip_distance(cap, &slot)) {
        if (indexed) {
            EN_WARN_ONCE("glEnablei/glDisablei: GL_CLIP_DISTANCE%u is not an indexed capability", slot);
            return;
        }
        const bool was_on = (st->clip_distance_mask & (1u << slot)) != 0;
        if (value)
            st->clip_distance_mask |= (1u << slot);
        else
            st->clip_distance_mask &= ~(1u << slot);
        const bool redundant = (was_on == (value != GL_FALSE)) && table_matches_driver(st);
        if (!redundant && g_gles_caps.GL_EXT_clip_cull_distance && GLES.glEnable && GLES.glDisable) {
            if (value)
                GLES.glEnable(cap);
            else
                GLES.glDisable(cap);
        }
        return;
    }

    const cap_desc_t* d = find_cap(cap);
    if (!d) {
        EN_WARN_ONCE("glEnable/glDisable: 0x%04x is not an enable capability, ignored", cap);
        return;
    }

    if (indexed) {
        // GL 4.6 has exactly two indexed capabilities: GL_BLEND, indexed by draw
        // buffer, and GL_SCISSOR_TEST, indexed by viewport. Viewport arrays are
        // not implemented here (glScissorIndexed is a stub), so only index 0 of
        // GL_SCISSOR_TEST is meaningful.
        if (d->cap == GL_BLEND) {
            if (index >= MG_MAX_DRAW_BUFFERS) {
                EN_WARN_ONCE("glEnablei(GL_BLEND, %u): index is past GL_MAX_DRAW_BUFFERS, ignored", index);
                return;
            }
            const GLboolean was = st->blend_indexed[index];
            st->blend_indexed[index] = value;
            if (index == 0) st->scalar[MGC_BLEND] = value;
            // blend_indexed[] mirrors the driver's per-draw-buffer state one for
            // one: the scalar path below writes every entry exactly when it tells
            // the driver to change all of them, so an entry that already holds
            // this value means the driver does too.
            if (was == value && table_matches_driver(st)) return;
            if (GLES.glEnablei && GLES.glDisablei) {
                if (value)
                    GLES.glEnablei(cap, index);
                else
                    GLES.glDisablei(cap, index);
            } else if (index == 0 && GLES.glEnable && GLES.glDisable) {
                if (value)
                    GLES.glEnable(cap);
                else
                    GLES.glDisable(cap);
            }
            return;
        }
        if (d->cap == GL_SCISSOR_TEST) {
            if (index >= MG_MAX_VIEWPORTS) {
                EN_WARN_ONCE("glEnablei(GL_SCISSOR_TEST, %u): index is past GL_MAX_VIEWPORTS, ignored", index);
                return;
            }
            st->scissor_indexed[index] = value;
            if (index != 0) {
                // Recorded so the query agrees, but nothing applies it: the
                // viewport array entry points are stubs.
                EN_WARN_ONCE("glEnablei(GL_SCISSOR_TEST, %u): viewport arrays are not implemented, the state is "
                             "tracked but has no effect",
                             index);
                return;
            }
        } else {
            EN_WARN_ONCE("glEnablei/glDisablei: %s is not an indexed capability, ignored", d->name);
            return;
        }
    }

    // Read before the table is written over. The scalar alone settles it for
    // every capability but GL_BLEND: glEnablei can leave one draw buffer
    // disagreeing with buffer 0, and the scalar form owes the new value to all of
    // them, so buffer 0 already agreeing does not mean the driver needs nothing.
    // GL_SCISSOR_TEST has no such case -- only viewport 0 is ever forwarded, the
    // rest being tracked for the queries alone.
    bool already_set = st->scalar[d->index] == value;
    if (already_set && d->cap == GL_BLEND) {
        for (int i = 0; i < MG_MAX_DRAW_BUFFERS; ++i) {
            if (st->blend_indexed[i] != value) {
                already_set = false;
                break;
            }
        }
    }

    st->scalar[d->index] = value;
    if (d->cap == GL_BLEND) {
        for (int i = 0; i < MG_MAX_DRAW_BUFFERS; ++i) st->blend_indexed[i] = value;
    }
    if (d->cap == GL_SCISSOR_TEST) {
        for (int i = 0; i < MG_MAX_VIEWPORTS; ++i) st->scissor_indexed[i] = value;
    }

    if (!forwards_to_driver(*d)) {
        LOG_D("%s is tracked but not forwarded (no GLES equivalent)", d->name)
        return;
    }

    // A renderer brackets nearly every pass with GL_BLEND, GL_DEPTH_TEST,
    // GL_CULL_FACE and GL_SCISSOR_TEST, usually setting the value already in
    // force. The table knows that without asking, and the driver call is not free
    // even when it changes nothing: it crosses into the driver and, under ANGLE,
    // into a second translation layer. The bookkeeping above still runs, so only
    // the call is dropped and never a recorded value.
    if (already_set && table_matches_driver(st)) return;

    if (value)
        GLES.glEnable(cap);
    else
        GLES.glDisable(cap);
}

extern "C"
{

    GLAPI GLAPIENTRY void glEnable(GLenum cap) {
        LOG()
        LOG_D("glEnable, cap = 0x%04x", cap)
        mg_set_enabled(cap, 0, false, GL_TRUE);
    }

    GLAPI GLAPIENTRY void glDisable(GLenum cap) {
        LOG()
        LOG_D("glDisable, cap = 0x%04x", cap)
        mg_set_enabled(cap, 0, false, GL_FALSE);
    }

    GLAPI GLAPIENTRY GLboolean glIsEnabled(GLenum cap) {
        LOG()
        return mg_enable_get(cap, 0);
    }

    GLAPI GLAPIENTRY void glEnablei(GLenum cap, GLuint index) {
        LOG()
        mg_set_enabled(cap, index, true, GL_TRUE);
    }

    GLAPI GLAPIENTRY void glDisablei(GLenum cap, GLuint index) {
        LOG()
        mg_set_enabled(cap, index, true, GL_FALSE);
    }

    GLAPI GLAPIENTRY GLboolean glIsEnabledi(GLenum cap, GLuint index) {
        LOG()
        return mg_enable_get(cap, index);
    }

    // The five state queries below all funnel through the same table, so they
    // cannot contradict each other or glIsEnabled. That used to be possible: on a
    // capability GLES does not know, glIsEnabled returned GL_FALSE (the answer the
    // specification owes on error) while glGetBooleanv left its output untouched
    // and glGetDoublev was a no-op stub that never wrote anything at all.
    GLAPI GLAPIENTRY void glGetBooleanv(GLenum pname, GLboolean* data) {
        LOG()
        GLboolean enabled = GL_FALSE;
        GLint ival = 0;
        if (mg_enable_query(pname, &enabled)) {
            *data = enabled;
            return;
        }
        if (mg_enable_query_int(pname, &ival)) {
            *data = ival != 0 ? GL_TRUE : GL_FALSE;
            return;
        }
        if (mg_pixel_store_query_int(pname, &ival)) {
            *data = ival != 0 ? GL_TRUE : GL_FALSE;
            return;
        }
        GLES.glGetBooleanv(pname, data);
    }

    GLAPI GLAPIENTRY void glGetFloatv(GLenum pname, GLfloat* data) {
        LOG()
        GLboolean enabled = GL_FALSE;
        GLint ival = 0;
        if (mg_enable_query(pname, &enabled)) {
            *data = enabled ? 1.0f : 0.0f;
            return;
        }
        if (mg_enable_query_int(pname, &ival)) {
            *data = static_cast<GLfloat>(ival);
            return;
        }
        if (mg_pixel_store_query_int(pname, &ival)) {
            *data = static_cast<GLfloat>(ival);
            return;
        }
        GLES.glGetFloatv(pname, data);
    }

    GLAPI GLAPIENTRY void glGetInteger64v(GLenum pname, GLint64* data) {
        LOG()
        GLboolean enabled = GL_FALSE;
        GLint ival = 0;
        if (mg_enable_query(pname, &enabled)) {
            *data = enabled ? 1 : 0;
            return;
        }
        if (mg_enable_query_int(pname, &ival)) {
            *data = ival;
            return;
        }
        if (mg_pixel_store_query_int(pname, &ival)) {
            *data = ival;
            return;
        }
        GLES.glGetInteger64v(pname, data);
    }

    // How many values glGetFloatv writes for a pname. Anything not listed writes
    // one. See /docsgl/gl4/glGet.xhtml.
    static int mg_get_components(GLenum pname) {
        switch (pname) {
        case GL_DEPTH_RANGE:
        case GL_ALIASED_LINE_WIDTH_RANGE:
        case GL_ALIASED_POINT_SIZE_RANGE:
        case GL_MAX_VIEWPORT_DIMS:
        case GL_POINT_SIZE_RANGE:
            return 2;
        case GL_VIEWPORT:
        case GL_SCISSOR_BOX:
        case GL_COLOR_CLEAR_VALUE:
        case GL_BLEND_COLOR:
        case GL_COLOR_WRITEMASK:
            return 4;
        default:
            return 1;
        }
    }

    // GLES has no glGetDoublev at all. It used to be a stub that returned without
    // writing params, so the application read whatever was on its stack.
    GLAPI GLAPIENTRY void glGetDoublev(GLenum pname, GLdouble* data) {
        LOG()
        GLboolean enabled = GL_FALSE;
        GLint ival = 0;
        if (mg_enable_query(pname, &enabled)) {
            *data = enabled ? 1.0 : 0.0;
            return;
        }
        if (mg_enable_query_int(pname, &ival)) {
            *data = static_cast<GLdouble>(ival);
            return;
        }
        // Sized by the pname, not assumed to be one. GL_DEPTH_RANGE writes two
        // floats and GL_VIEWPORT four; handing the driver a single GLfloat on the
        // stack let it write past it.
        GLfloat tmp[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        GLES.glGetFloatv(pname, tmp);
        const int n = mg_get_components(pname);
        for (int i = 0; i < n; ++i) data[i] = static_cast<GLdouble>(tmp[i]);
    }

    GLAPI GLAPIENTRY void glPrimitiveRestartIndex(GLuint index) {
        LOG()
        LOG_D("glPrimitiveRestartIndex, index = %u", index)
        mg_enable_set_primitive_restart_index(index);
    }

#ifndef __APPLE__
    // GL_ARB_draw_buffers_blend spells the indexed forms with an ARB suffix, and
    // the NATIVE_FUNCTION macro used to generate those aliases for free. Keep
    // them: glXGetProcAddress is a bare dlsym (glx/lookup.cpp), so a vanished
    // symbol becomes a silently null function pointer rather than an error.
    GLAPI GLAPIENTRY void glEnableiARB(GLenum cap, GLuint index) __attribute__((alias("glEnablei")));
    GLAPI GLAPIENTRY void glDisableiARB(GLenum cap, GLuint index) __attribute__((alias("glDisablei")));
    GLAPI GLAPIENTRY GLboolean glIsEnablediARB(GLenum cap, GLuint index) __attribute__((alias("glIsEnabledi")));
#else
    GLAPI GLAPIENTRY void glEnableiARB(GLenum cap, GLuint index) { glEnablei(cap, index); }
    GLAPI GLAPIENTRY void glDisableiARB(GLenum cap, GLuint index) { glDisablei(cap, index); }
    GLAPI GLAPIENTRY GLboolean glIsEnablediARB(GLenum cap, GLuint index) { return glIsEnabledi(cap, index); }
#endif

} // extern "C"
