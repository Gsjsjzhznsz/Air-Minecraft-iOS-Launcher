// MobileGlues - gl/vertexattrib.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "vertexattrib.h"

#define DEBUG 0

void glVertexAttribI1ui(GLuint index, GLuint x) {
    LOG()
    GLES.glVertexAttribI4ui(index, x, 0, 0, 0);
}

void glVertexAttribI2ui(GLuint index, GLuint x, GLuint y) {
    LOG()
    GLES.glVertexAttribI4ui(index, x, y, 0, 0);
}

void glVertexAttribI3ui(GLuint index, GLuint x, GLuint y, GLuint z) {
    LOG()
    GLES.glVertexAttribI4ui(index, x, y, z, 0);
}