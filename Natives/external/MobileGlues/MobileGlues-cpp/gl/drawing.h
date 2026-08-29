// MobileGlues - gl/drawing.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_DRAWING_H
#define MOBILEGLUES_DRAWING_H

#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cstring>
#include <GLES3/gl32.h>
#include "../includes.h"
#include <GL/gl.h>
#include "glcorearb.h"
#include "log.h"
#include "../gles/loader.h"
#include "mg.h"

struct SamplerInfo {
    GLint locWidth;
    GLint locHeight;
    std::vector<GLint> samplers;
};

#ifdef __cplusplus
extern "C"
{
#endif

    GLAPI GLAPIENTRY void glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const void* indices,
                                                  GLsizei primcount);
    GLAPI GLAPIENTRY void glDrawElementsBaseVertex(GLenum mode, GLsizei count, GLenum type, const void* indices,
                                                   GLint basevertex);
    GLAPI GLAPIENTRY void glMultiDrawElements(GLenum mode, const GLsizei* count, GLenum type,
                                              const void* const* indices, GLsizei primcount);
    GLAPI GLAPIENTRY void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void* indices);

    // The rest of the indexed family, so GL_PRIMITIVE_RESTART is applied to all
    // of it rather than only to the three above.
    GLAPI GLAPIENTRY void glDrawRangeElements(GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type,
                                              const void* indices);
    GLAPI GLAPIENTRY void glDrawRangeElementsBaseVertex(GLenum mode, GLuint start, GLuint end, GLsizei count,
                                                        GLenum type, const void* indices, GLint basevertex);
    GLAPI GLAPIENTRY void glDrawElementsInstancedBaseVertex(GLenum mode, GLsizei count, GLenum type,
                                                            const void* indices, GLsizei instancecount,
                                                            GLint basevertex);

    // GL 4.2 base instance. GLES has none, so these forward and report a
    // non-zero base instance once; they used to be stubs that drew nothing.
    GLAPI GLAPIENTRY void glDrawArraysInstancedBaseInstance(GLenum mode, GLint first, GLsizei count,
                                                            GLsizei instancecount, GLuint baseinstance);
    GLAPI GLAPIENTRY void glDrawElementsInstancedBaseInstance(GLenum mode, GLsizei count, GLenum type,
                                                              const void* indices, GLsizei instancecount,
                                                              GLuint baseinstance);
    GLAPI GLAPIENTRY void glDrawElementsInstancedBaseVertexBaseInstance(GLenum mode, GLsizei count, GLenum type,
                                                                        const void* indices, GLsizei instancecount,
                                                                        GLint basevertex, GLuint baseinstance);

    GLAPI GLAPIENTRY void glBindImageTexture(GLuint unit, GLuint texture, GLint level, GLboolean layered, GLint layer,
                                             GLenum access, GLenum format);
    GLAPI GLAPIENTRY void glDispatchCompute(GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z);
    GLAPI GLAPIENTRY void glMemoryBarrier(GLbitfield barriers);
    GLAPI GLAPIENTRY void glUniform1i(GLint location, GLint v0);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_DRAWING_H
