// MobileGlues - gl/enable.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_ENABLE_H
#define MOBILEGLUES_ENABLE_H

#include "../includes.h"
#include <GL/gl.h>
#include "glcorearb.h"

// ---------------------------------------------------------------------------
// The virtual enable state
//
// GL 4.6 has 28 enable capabilities; 13 of them do not exist in GLES 3.2 core.
// Forwarding glEnable straight to the driver made those 13 fail with
// GL_INVALID_ENUM, and left the five state queries contradicting each other:
// glIsEnabled must return GL_FALSE on error, while glGetBooleanv and friends
// leave their output untouched, so the same capability answered two different
// things in the same frame -- and glGetError always reports GL_NO_ERROR, so the
// application could not tell.
//
// Every enable capability now lives in one table. Queries read it, the enable
// entry points write it, and whether the driver is also told is a per-capability
// property rather than an accident of which enum the driver happens to know.
// ---------------------------------------------------------------------------

#ifdef __cplusplus
extern "C"
{
#endif

    // Scalar capabilities. GL_CLIP_DISTANCEi is a contiguous enum range rather
    // than a single value and is kept as a bitmask instead of occupying slots.
    enum mg_cap_index : int {
        MGC_BLEND = 0,
        MGC_COLOR_LOGIC_OP,
        MGC_CULL_FACE,
        MGC_DEBUG_OUTPUT,
        MGC_DEBUG_OUTPUT_SYNCHRONOUS,
        MGC_DEPTH_CLAMP,
        MGC_DEPTH_TEST,
        MGC_DITHER,
        MGC_FRAMEBUFFER_SRGB,
        MGC_LINE_SMOOTH,
        MGC_MULTISAMPLE,
        MGC_POLYGON_OFFSET_FILL,
        MGC_POLYGON_OFFSET_LINE,
        MGC_POLYGON_OFFSET_POINT,
        MGC_POLYGON_SMOOTH,
        MGC_PRIMITIVE_RESTART,
        MGC_PRIMITIVE_RESTART_FIXED_INDEX,
        MGC_PROGRAM_POINT_SIZE,
        MGC_RASTERIZER_DISCARD,
        MGC_SAMPLE_ALPHA_TO_COVERAGE,
        MGC_SAMPLE_ALPHA_TO_ONE,
        MGC_SAMPLE_COVERAGE,
        MGC_SAMPLE_MASK,
        MGC_SAMPLE_SHADING,
        MGC_SCISSOR_TEST,
        MGC_STENCIL_TEST,
        MGC_TEXTURE_CUBE_MAP_SEAMLESS,
        MGC_COUNT
    };

    // GL 4.6 requires at least 8 clip distances and at least 8 draw buffers.
    // Anything the driver reports above these is clamped; the layer never claims
    // more than it can store.
    enum { MG_MAX_CLIP_DISTANCES = 8, MG_MAX_DRAW_BUFFERS = 16, MG_MAX_VIEWPORTS = 16 };

    struct mg_enable_state_t {
        GLboolean scalar[MGC_COUNT];
        GLboolean blend_indexed[MG_MAX_DRAW_BUFFERS];   // GL_BLEND per draw buffer
        GLboolean scissor_indexed[MG_MAX_VIEWPORTS];    // GL_SCISSOR_TEST per viewport
        GLuint clip_distance_mask;                    // GL_CLIP_DISTANCE0..7
        GLuint primitive_restart_index;               // glPrimitiveRestartIndex
        bool initialised;
        bool driver_synced;  // mg_enable_sync_driver() has run for this context
    };

    // Current table. Today there is one; gl/enable.cpp routes every access
    // through this accessor so that S5 can make it per-context by changing this
    // function alone.
    struct mg_enable_state_t* mg_enable_state(void);

    // Read a capability. index is ignored for non-indexed capabilities.
    // Returns GL_FALSE for anything that is not an enable capability -- the same
    // answer glIsEnabled owes for a bad enum, which this layer cannot report.
    GLboolean mg_enable_get(GLenum cap, GLuint index);

    // True when pname names an enable capability, in which case *out receives its
    // state. Used by every glGet* variant so they cannot disagree with
    // glIsEnabled.
    bool mg_enable_query(GLenum pname, GLboolean* out);

    // True when pname is a piece of state this table owns and can answer as an
    // integer (GL_PRIMITIVE_RESTART_INDEX, GL_MAX_CLIP_DISTANCES, ...).
    bool mg_enable_query_int(GLenum pname, GLint* out);

    void mg_enable_set_primitive_restart_index(GLuint index);

    // The restart index actually in effect, and whether restarting is on at all.
    // GL_PRIMITIVE_RESTART_FIXED_INDEX wins over GL_PRIMITIVE_RESTART when both
    // are enabled, matching the GL 4.6 rule that the fixed index is used
    // regardless of the value set by glPrimitiveRestartIndex.
    bool mg_primitive_restart_enabled(void);
    GLuint mg_primitive_restart_index_for(GLenum type);

    void mg_enable_reset(struct mg_enable_state_t* state);

    // Make the driver agree with the table. Seeds the entries that can only be
    // answered by asking the driver, and pushes down the ones whose GLES default
    // is not the GL 4.6 default. Must run with the context current -- which
    // mg_enable_reset() is not, it runs inside eglCreateContext -- so this is
    // called from mg_context_make_current(). Runs once per context.
    void mg_enable_sync_driver(struct mg_enable_state_t* state);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_ENABLE_H
