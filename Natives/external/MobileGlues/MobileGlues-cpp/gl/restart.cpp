// MobileGlues - gl/restart.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "restart.h"
#include "buffer.h"
#include "enable.h"
#include "../egl/context.h"
#include "../gles/loader.h"
#include "log.h"
#include "mg.h"
#include <vector>

#define DEBUG 0

#define RS_WARN_ONCE(...)                                                                                              \
    do {                                                                                                               \
        static bool mg_rs_warned = false;                                                                              \
        if (!mg_rs_warned) {                                                                                           \
            mg_rs_warned = true;                                                                                       \
            LOG_W_FORCE(__VA_ARGS__)                                                                                   \
        }                                                                                                              \
    } while (0)

namespace {

// The scratch stream buffer, and the context that owns it. thread_local because
// g_current_ctx is, so two threads with different current contexts each keep
// their own name instead of trading one back and forth.
thread_local GLuint g_restart_ibo = 0;
thread_local unsigned long long g_restart_owner_ctx_id = 0;

// Drop the cached name when the current context is not the one that created it.
//
// mg_restart_invalidate() only runs when the application happens to issue a
// multi-draw, so without this a plain glDrawElements after a context switch
// would reuse the old name. Drawing stayed correct because the whole stream is
// re-uploaded every time, but if the name collides with a buffer the new context
// owns, the glBufferData below overwrites that buffer's contents.
void restart_check_context() {
    const unsigned long long cur = g_current_ctx ? g_current_ctx->id : 0;
    if (cur == g_restart_owner_ctx_id) return;

    // Deliberately no glDeleteBuffers here: if the owning context is gone the
    // buffer went with it, and if it is merely not current then this name refers
    // to a buffer belonging to whichever context *is* current.
    g_restart_ibo = 0;
    g_restart_owner_ctx_id = cur;
}

GLsizei index_size(GLenum type) {
    switch (type) {
    case GL_UNSIGNED_BYTE:
        return 1;
    case GL_UNSIGNED_SHORT:
        return 2;
    case GL_UNSIGNED_INT:
        return 4;
    default:
        return 0;
    }
}

GLuint fixed_sentinel(GLenum type) {
    switch (type) {
    case GL_UNSIGNED_BYTE:
        return 0xFFu;
    case GL_UNSIGNED_SHORT:
        return 0xFFFFu;
    default:
        return 0xFFFFFFFFu;
    }
}

// Widen to 32 bits, apply the base vertex, and turn the application's chosen
// restart value into the fixed sentinel the driver understands.
void rewrite(GLuint* dst, const void* src, GLsizei count, GLenum type, GLint basevertex, GLuint restart_value) {
    const GLuint bv = static_cast<GLuint>(basevertex);
#define RS_LOOP(SRCTYPE)                                                                                               \
    do {                                                                                                               \
        const SRCTYPE* s = static_cast<const SRCTYPE*>(src);                                                           \
        for (GLsizei i = 0; i < count; ++i) {                                                                          \
            const GLuint v = static_cast<GLuint>(s[i]);                                                                \
            dst[i] = (v == restart_value) ? 0xFFFFFFFFu : (v + bv);                                                    \
        }                                                                                                              \
    } while (0)

    switch (type) {
    case GL_UNSIGNED_INT:
        RS_LOOP(GLuint);
        break;
    case GL_UNSIGNED_SHORT:
        RS_LOOP(GLushort);
        break;
    case GL_UNSIGNED_BYTE:
        RS_LOOP(GLubyte);
        break;
    default:
        break;
    }
#undef RS_LOOP
}

} // namespace

void mg_restart_invalidate(void) {
    g_restart_ibo = 0;
}

bool mg_restart_needs_rewrite(GLenum type) {
    if (index_size(type) == 0) return false;
    mg_enable_state_t* st = mg_enable_state();
    if (!st->scalar[MGC_PRIMITIVE_RESTART]) return false;
    // The fixed-index form takes precedence, and the driver already implements
    // it, so nothing has to be rewritten.
    if (st->scalar[MGC_PRIMITIVE_RESTART_FIXED_INDEX]) return false;
    // An application that picked exactly the fixed value gets the driver's
    // implementation for free; only a different value needs the substitution.
    return st->primitive_restart_index != fixed_sentinel(type);
}

bool mg_restart_needs_driver_fixed(GLenum type) {
    if (index_size(type) == 0) return false;
    mg_enable_state_t* st = mg_enable_state();
    if (!st->scalar[MGC_PRIMITIVE_RESTART]) return false;
    if (st->scalar[MGC_PRIMITIVE_RESTART_FIXED_INDEX]) return false; // the driver is already doing it
    return st->primitive_restart_index == fixed_sentinel(type);
}

bool mg_draw_elements_restart(GLenum mode, GLsizei count, GLenum type, const void* indices, GLint basevertex,
                              GLsizei instancecount) {
    const GLsizei isize = index_size(type);
    if (isize == 0 || count <= 0) return false;

    const GLuint restart_value = mg_enable_state()->primitive_restart_index;

    // The tracked binding instead of asking the driver: mg_driver_bound_buffer
    // answers with the driver-side name, which is exactly what the two
    // glBindBuffer calls below need, and it is read here at entry, before this
    // function binds the scratch buffer over it. The only path that can leave the
    // driver's element array binding disagreeing with the tracked one is
    // gl/gl.cpp's ANGLE depth-clear triangle, and it does that by leaving vertex
    // array 0 bound, which makes the draw itself wrong either way.
    const GLuint prev_ibo = mg_driver_bound_buffer(GL_ELEMENT_ARRAY_BUFFER);

    // Grown but never shrunk, and thread_local for the same reason g_restart_ibo
    // is. Only the first `count` elements are written and uploaded, so whatever a
    // larger earlier draw left past that is never read; sizing it exactly instead
    // would zero-fill a range rewrite() overwrites in full immediately after.
    static thread_local std::vector<GLuint> rewritten;
    if (rewritten.size() < static_cast<size_t>(count)) rewritten.resize(static_cast<size_t>(count));

    if (prev_ibo != 0) {
        GLES.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, prev_ibo);
        void* src = GLES.glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER,
                                          static_cast<GLintptr>(reinterpret_cast<uintptr_t>(indices)),
                                          static_cast<GLsizeiptr>(count) * isize, GL_MAP_READ_BIT);
        if (!src) {
            // An immutable or persistently mapped index buffer cannot be read
            // back. Rather than draw geometry with the restart silently missing,
            // hand the batch back so the caller issues its ordinary draw -- the
            // restarts will not happen, but nothing is invented.
            RS_WARN_ONCE("primitive restart: index buffer is not readable, custom restart index ignored");
            return false;
        }
        rewrite(rewritten.data(), src, count, type, basevertex, restart_value);
        GLES.glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
    } else {
        rewrite(rewritten.data(), indices, count, type, basevertex, restart_value);
    }

    restart_check_context();
    if (!g_restart_ibo) GLES.glGenBuffers(1, &g_restart_ibo);
    GLES.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, g_restart_ibo);
    GLES.glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(count) * sizeof(GLuint), rewritten.data(),
                      GL_STREAM_DRAW);

    // The rewritten stream uses the fixed sentinel, so the driver's fixed-index
    // restart has to be on for this draw. It is switched directly rather than
    // through glEnable so the virtual table keeps reporting what the application
    // set, which is GL_PRIMITIVE_RESTART and not this.
    const bool had_fixed = mg_enable_get(GL_PRIMITIVE_RESTART_FIXED_INDEX, 0) == GL_TRUE;
    if (!had_fixed) GLES.glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);

    if (instancecount >= 0) {
        GLES.glDrawElementsInstanced(mode, count, GL_UNSIGNED_INT, nullptr, instancecount);
    } else {
        GLES.glDrawElements(mode, count, GL_UNSIGNED_INT, nullptr);
    }

    if (!had_fixed) GLES.glDisable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
    GLES.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, prev_ibo);
    return true;
}
