// MobileGlues - gl/multidraw.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_MULTIDRAW_H
#define MOBILEGLUES_MULTIDRAW_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <GLES3/gl32.h>
#include "../includes.h"
#include <GL/gl.h>
#include "glcorearb.h"
#include "log.h"
#include "../gles/loader.h"
#include "mg.h"

#ifdef __cplusplus
extern "C"
{
#endif

    struct draw_elements_indirect_command_t {
        GLuint count;
        GLuint instanceCount;
        GLuint firstIndex;
        GLint baseVertex;
        GLuint reservedMustBeZero;
    };

    // GL 4.6 DrawArraysIndirectCommand. Four words, tightly packed. GLES only
    // treats the fourth as baseInstance with EXT_base_instance; otherwise it is
    // reservedMustBeZero, and glMultiDrawArrays has no base instance, so writing
    // 0 is correct under both readings.
    struct draw_arrays_indirect_command_t {
        GLuint count;
        GLuint instanceCount;
        GLuint first;
        GLuint baseInstanceOrReserved;
    };

    // Per-sub-draw data handed to the compute shader as a single std430 ivec2
    // array. Merging firstIndex and baseVertex keeps the shader at four shader
    // storage blocks, which is the minimum GLES 3.1 guarantees.
    struct drawcmd_compute_t {
        GLuint firstIndex;
        GLint baseVertex;
    };

    GLAPI GLAPIENTRY void glMultiDrawElementsBaseVertex(GLenum mode, GLsizei* counts, GLenum type,
                                                        const void* const* indices, GLsizei primcount,
                                                        const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_indirect(GLenum mode, GLsizei* counts, GLenum type,
                                                                    const void* const* indices, GLsizei primcount,
                                                                    const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_multiindirect(GLenum mode, GLsizei* counts, GLenum type,
                                                                         const void* const* indices, GLsizei primcount,
                                                                         const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_basevertex(GLenum mode, GLsizei* counts, GLenum type,
                                                                      const void* const* indices, GLsizei primcount,
                                                                      const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_drawelements(GLenum mode, GLsizei* counts, GLenum type,
                                                                        const void* const* indices, GLsizei primcount,
                                                                        const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_compute(GLenum mode, GLsizei* counts, GLenum type,
                                                                   const void* const* indices, GLsizei primcount,
                                                                   const GLint* basevertex);
    GLAPI GLAPIENTRY void mg_glMultiDrawElementsBaseVertex_multibasevertex(GLenum mode, GLsizei* counts, GLenum type,
                                                                  const void* const* indices, GLsizei primcount,
                                                                  const GLint* basevertex);

    GLAPI GLAPIENTRY void glMultiDrawElements(GLenum mode, const GLsizei* count, GLenum type,
                                              const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_indirect(GLenum mode, const GLsizei* count, GLenum type,
                                                          const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_multiindirect(GLenum mode, const GLsizei* count, GLenum type,
                                                               const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_basevertex(GLenum mode, const GLsizei* count, GLenum type,
                                                            const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_drawelements(GLenum mode, const GLsizei* count, GLenum type,
                                                              const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_compute(GLenum mode, const GLsizei* count, GLenum type,
                                                         const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_multibasevertex(GLenum mode, const GLsizei* count, GLenum type,
                                                        const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawElements_multiarrays(GLenum mode, const GLsizei* count, GLenum type,
                                                           const void* const* indices, GLsizei primcount);

    // GL 4.6 core multi-draw entry points. These used to be silent no-op stubs
    // in gl_stub.cpp, so an application calling them got no geometry and no
    // error.
    GLAPI GLAPIENTRY void glMultiDrawArrays(GLenum mode, const GLint* first, const GLsizei* count, GLsizei drawcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawArrays_unroll(GLenum mode, const GLint* first, const GLsizei* count,
                                                            GLsizei drawcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawArrays_multiarrays(GLenum mode, const GLint* first, const GLsizei* count,
                                                         GLsizei drawcount);
    GLAPI GLAPIENTRY void mg_glMultiDrawArrays_multiindirect(GLenum mode, const GLint* first, const GLsizei* count,
                                                             GLsizei drawcount);
    GLAPI GLAPIENTRY void glMultiDrawArraysIndirect(GLenum mode, const void* indirect, GLsizei drawcount,
                                                    GLsizei stride);
    GLAPI GLAPIENTRY void glMultiDrawElementsIndirect(GLenum mode, GLenum type, const void* indirect,
                                                      GLsizei drawcount, GLsizei stride);
    // The draw count is read on the GPU: a compute shader compacts the command
    // buffer so the commands past the count draw nothing. No CPU readback, so no
    // pipeline stall and no stale count.
    GLAPI GLAPIENTRY void glMultiDrawArraysIndirectCount(GLenum mode, const void* indirect, GLintptr drawcount,
                                                         GLsizei maxdrawcount, GLsizei stride);
    GLAPI GLAPIENTRY void glMultiDrawElementsIndirectCount(GLenum mode, GLenum type, const void* indirect,
                                                           GLintptr drawcount, GLsizei maxdrawcount, GLsizei stride);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_MULTIDRAW_H
