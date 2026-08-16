// MobileGlues - gl/shader.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_SHADER_H
#define MOBILEGLUES_SHADER_H

#include <GL/gl.h>
#include <string>
#include <unordered_map>

struct ShaderInfo {
    std::string converted;
    // Owned by value. It was a char* holding a `new char[]` that nothing ever
    // deleted: glBindFragDataLocation overwrote it, glLinkProgram nulled it and
    // glShaderSource abandoned it, so every patched shader source stayed on the
    // heap for the life of the process.
    std::string frag_data_changed_converted;
    int frag_data_changed = 0;
    int ignore_error_level = 0;
};

extern std::unordered_map<GLuint, ShaderInfo> g_shaderInfos;

#ifdef __cplusplus
extern "C"
{
#endif

    GLAPI GLAPIENTRY void glShaderSource(GLuint shader, GLsizei count, const GLchar* const* string,
                                         const GLint* length);

    GLAPI GLAPIENTRY void glGetShaderiv(GLuint shader, GLenum pname, GLint* params);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_SHADER_H