// MobileGlues - gl/buffer.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_BUFFER_H
#define GL_GLEXT_PROTOTYPES
#include "../config/settings.h"
#include "../gles/loader.h"
#include "../includes.h"
#include "glcorearb.h"
#include "log.h"
#include "mg.h"
#include <GL/gl.h>
#include <cstddef>
#include <vector>

#ifdef __cplusplus
extern "C"
{
#endif

    GLuint gen_buffer();

    GLboolean has_buffer(GLuint key);

    void modify_buffer(GLuint key, GLuint value);

    void remove_buffer(GLuint key);

    GLuint find_real_buffer(GLuint key);

    // key is a *_BINDING query enum, the kind glGetIntegerv is given.
    GLuint find_bound_buffer(GLenum key);
    // target is a bind target, the kind glBindBuffer is given. Not interchangeable
    // with the above: each rejects the other's enums and returns 0.
    GLuint find_bound_buffer_by_target(GLenum target);

    // The real/driver name bound to target, as GLES.glGetIntegerv(<target>_BINDING)
    // would report it -- the two functions above answer with this layer's own
    // names, which the driver has never heard of. Computed from tracked state, so
    // it costs nothing and is safe to call per draw, and it is the value to hand
    // straight back to GLES.glBindBuffer when restoring a temporary bind.
    //
    // Only valid where the driver's binding still agrees with the tracked one; the
    // comment on the definition in gl/buffer.cpp lists where it does not.
    GLuint mg_driver_bound_buffer(GLenum target);

    GLuint gen_array();

    GLboolean has_array(GLuint key);

    void modify_array(GLuint key, GLuint value);

    void remove_array(GLuint key);

    GLuint find_real_array(GLuint key);

    GLuint find_bound_array();

    static GLenum get_binding_query(GLenum target);

    void InitBufferMap(size_t expectedSize);

    void InitVertexArrayMap(size_t expectedSize);

    GLAPI GLAPIENTRY void glGenBuffers(GLsizei n, GLuint* buffers);

    GLAPI GLAPIENTRY void glDeleteBuffers(GLsizei n, const GLuint* buffers);

    GLAPI GLAPIENTRY GLboolean glIsBuffer(GLuint buffer);

    GLAPI GLAPIENTRY void glBindBuffer(GLenum target, GLuint buffer);

    GLAPI GLAPIENTRY void glBindBufferRange(GLenum target, GLuint index, GLuint buffer, GLintptr offset,
                                            GLsizeiptr size);

    GLAPI GLAPIENTRY void glBindBufferBase(GLenum target, GLuint index, GLuint buffer);

    GLAPI GLAPIENTRY void glBindVertexBuffer(GLuint bindingindex, GLuint buffer, GLintptr offset, GLsizei stride);

    GLAPI GLAPIENTRY void glTexBuffer(GLenum target, GLenum internalformat, GLuint buffer);

    GLAPI GLAPIENTRY void glTexBufferRange(GLenum target, GLenum internalformat, GLuint buffer, GLintptr offset,
                                           GLsizeiptr size);

    GLAPI GLAPIENTRY GLboolean glUnmapBuffer(GLenum target);

    GLAPI GLAPIENTRY void* glMapBuffer(GLenum target, GLenum access);

    GLAPI GLAPIENTRY void* glMapBufferRange(GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access);

    GLAPI GLAPIENTRY void glBufferData(GLenum target, GLsizeiptr size, const void* data, GLenum usage);

    GLAPI GLAPIENTRY void glBufferStorage(GLenum target, GLsizeiptr size, const void* data, GLbitfield flags);

    GLAPI GLAPIENTRY void glFlushMappedBufferRange(GLenum target, GLintptr offset, GLsizeiptr length);

    GLAPI GLAPIENTRY void glGenVertexArrays(GLsizei n, GLuint* arrays);

    GLAPI GLAPIENTRY void glDeleteVertexArrays(GLsizei n, const GLuint* arrays);

    GLAPI GLAPIENTRY GLboolean glIsVertexArray(GLuint array);

    GLAPI GLAPIENTRY void glBindVertexArray(GLuint array);

#ifdef __cplusplus
}
#endif

#define MOBILEGLUES_BUFFER_H

#endif // MOBILEGLUES_BUFFER_H
