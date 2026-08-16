// MobileGlues - gl/glsl/glsl_for_es.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef GLSL_FOR_ES
#define GLSL_FOR_ES
#include "../../gles/loader.h"
#include "../../includes.h"
#include "../glcorearb.h"
#include "../log.h"
#include <GL/gl.h>
#include <stdio.h>
#include <string>
#include <vector>

#ifdef __cplusplus
extern "C"
{
#endif
#include "../mg.h"
#ifdef __cplusplus
}
#endif

// One GL_ATOMIC_COUNTER_BUFFER binding used by a shader/program, with the byte
// offsets (declaration order) of the counters that live in it.
struct AtomicBufferBinding {
    int binding = 0;
    std::vector<int> counter_offsets;
};

std::string GLSLtoGLSLES(const char* glsl_code, GLenum glsl_type, uint essl_version, uint glsl_version,
                         int& return_code);
std::string GLSLtoGLSLES_1(const char* glsl_code, GLenum glsl_type, uint esversion, int& return_code);
std::string GLSLtoGLSLES_2(const char* glsl_code, GLenum glsl_type, uint essl_version, int& return_code);
int getGLSLVersion(const char* glsl_code);

// Rewrites `layout(...) uniform atomic_uint ...;` declarations and their
// atomicCounter* calls into an SSBO + atomicAdd scheme. Returns true only when
// an `atomic_uint` declaration was actually converted; shaders merely mentioning
// the word (a comment, an unrelated identifier) are left as-is and report false.
bool process_non_opaque_atomic_to_ssbo(std::string& source);

// Extracts the atomic counter buffer bindings a piece of (desktop or ES) GLSL
// declares, one entry per binding with the byte offsets of its counters in
// declaration order. Empty when the source declares no atomic counters.
std::vector<AtomicBufferBinding> extract_atomic_buffer_bindings(const std::string& source);

#endif