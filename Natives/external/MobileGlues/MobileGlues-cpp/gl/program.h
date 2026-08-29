// MobileGlues - gl/program.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_PROGRAM_H
#define MOBILEGLUES_PROGRAM_H

#include <GL/gl.h>

#ifdef __cplusplus
extern "C"
{
#endif

    GLAPI GLAPIENTRY void glBindFragDataLocation(GLuint program, GLuint color, const GLchar* name);
    GLAPI GLAPIENTRY void glLinkProgram(GLuint program);
    GLAPI GLAPIENTRY void glGetProgramiv(GLuint program, GLenum pname, GLint* params);
    GLAPI GLAPIENTRY void glUseProgram(GLuint program);
    GLAPI GLAPIENTRY GLuint glCreateProgram();
    GLAPI GLAPIENTRY void glAttachShader(GLuint program, GLuint shader);
    GLAPI GLAPIENTRY GLuint glCreateShader(GLenum shaderType);
    GLAPI GLAPIENTRY void glGetActiveUniformName(GLuint program, GLuint uniformIndex, GLsizei bufSize, GLsizei* length,
                                                 GLchar* uniformName);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_PROGRAM_H
