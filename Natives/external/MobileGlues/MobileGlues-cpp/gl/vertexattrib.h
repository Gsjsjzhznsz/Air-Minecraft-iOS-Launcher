// MobileGlues - gl/vertexattrib.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_VERTEXATTRIB_H
#define MOBILEGLUES_VERTEXATTRIB_H

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

    GLAPI GLAPIENTRY void glVertexAttribI1ui(GLuint index, GLuint x);
    GLAPI GLAPIENTRY void glVertexAttribI2ui(GLuint index, GLuint x, GLuint y);
    GLAPI GLAPIENTRY void glVertexAttribI3ui(GLuint index, GLuint x, GLuint y, GLuint z);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_VERTEXATTRIB_H
