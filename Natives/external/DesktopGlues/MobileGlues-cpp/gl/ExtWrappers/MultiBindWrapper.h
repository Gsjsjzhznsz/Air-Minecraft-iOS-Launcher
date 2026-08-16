// MobileGlues - gl/ExtWrappers/MultiBindWrapper.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#pragma once
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <regex.h>
#include "../log.h"
#include "../shader.h"
#include "../program.h"
#include "../buffer.h"
#include <regex>
#include <cstring>
#include <iostream>
#include "../../config/settings.h"
#include "../drawing.h"

extern "C"
{
    GLAPI void glBindTextures(GLuint first, GLsizei count, const GLuint* textures);
    GLAPI void glBindSamplers(GLuint first, GLsizei count, const GLuint* samplers);
    GLAPI void glBindImageTextures(GLuint first, GLsizei count, const GLuint* textures);
    GLAPI void glBindVertexBuffers(GLuint first, GLsizei count, const GLuint* buffers, const GLintptr* offsets,
                                   const GLsizei* strides);
}