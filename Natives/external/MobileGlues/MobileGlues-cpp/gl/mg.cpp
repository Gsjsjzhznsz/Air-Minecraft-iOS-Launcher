// MobileGlues - gl/mg.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include <unistd.h>
#include <cstdarg>
#include <cstdio>
#include "mg.h"

#define DEBUG 0

hardware_t hardware;
gl_state_s g_default_gl_state;
thread_local gl_state_t gl_state = &g_default_gl_state;

FUNC_GL_STATE_SIZEI(proxy_width)
FUNC_GL_STATE_SIZEI(proxy_height)
FUNC_GL_STATE_ENUM(proxy_intformat)
FUNC_GL_STATE_UINT(current_program)
FUNC_GL_STATE_UINT(current_tex_unit)
FUNC_GL_STATE_UINT(current_draw_fbo)

#ifndef __APPLE__
FILE* file;
#endif

void start_log() {
#ifndef __APPLE__
    file = fopen(log_file_path, "a");
#endif
}

void write_log(const char* format, ...) {
#ifndef __APPLE__
    if (file == nullptr) {
        return;
    }
    va_list args;
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    fprintf(file, "\n");
    fflush(file);
#if FORCE_SYNC_WITH_LOG_FILE == 1
    int fd = fileno(file);
    fsync(fd);
#endif
    // Todo: close file
    // fclose(file);
#endif
}

void write_log_n(const char* format, ...) {
#ifndef __APPLE__
    if (file == NULL) {
        return;
    }
    va_list args;
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    // Todo: close file
    fflush(file);
#endif
}

void clear_log() {
#ifndef __APPLE__
    file = fopen(log_file_path, "w");
    if (file == nullptr) {
        return;
    }
    fclose(file);
#endif
}

GLenum pname_convert(GLenum pname) {
    switch (pname) {
    // TODO: Realize GL_TEXTURE_LOD_BIAS for other devices.
    case GL_TEXTURE_LOD_BIAS:
        return GL_TEXTURE_LOD_BIAS_QCOM;
    }
    return pname;
}

GLenum map_tex_target(GLenum target) {
    switch (target) {
    case GL_TEXTURE_1D:
    case GL_TEXTURE_3D:
    case GL_TEXTURE_RECTANGLE_ARB:
        return GL_TEXTURE_2D;

    case GL_PROXY_TEXTURE_1D:
    case GL_PROXY_TEXTURE_3D:
    case GL_PROXY_TEXTURE_RECTANGLE_ARB:
        return GL_PROXY_TEXTURE_2D;

    default:
        return target;
    }
}