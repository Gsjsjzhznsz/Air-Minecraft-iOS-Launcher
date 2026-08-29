// MobileGlues - gl/getter.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "../includes.h"
#include <GL/gl.h>
#include "glcorearb.h"
#include "log.h"
#include "../config/settings.h"
#include "../gles/loader.h"
#include "mg.h"
#include "../version.h"

#ifndef MOBILEGLUES_GETTER_H
#define MOBILEGLUES_GETTER_H

#ifdef __cplusplus
extern "C"
{
#endif

    GLAPI GLAPIENTRY const GLubyte* glGetString(GLenum name);
    GLAPI GLAPIENTRY const GLubyte* glGetStringi(GLenum name, GLuint index);
    GLAPI GLAPIENTRY GLenum glGetError();
    GLAPI GLAPIENTRY void glGetIntegerv(GLenum pname, GLint* params);
    GLAPI GLAPIENTRY void glGetQueryObjectiv(GLuint id, GLenum pname, GLint* params);
    GLAPI GLAPIENTRY void glGetQueryObjecti64v(GLuint id, GLenum pname, GLint64* params);

    void AppendExtension(const char* ext);
    void InitGLESBaseExtensions();
    void set_es_version();

#ifdef __cplusplus
}
#endif

extern Version GLVersion;

#endif // MOBILEGLUES_GETTER_H
