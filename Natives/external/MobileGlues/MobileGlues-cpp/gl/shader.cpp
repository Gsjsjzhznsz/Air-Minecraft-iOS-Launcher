// MobileGlues - gl/shader.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include <cctype>
#include "shader.h"

#include <GL/gl.h>
#include "log.h"
#include "program.h"
#include "../gles/loader.h"
#include "../includes.h"
#include "glsl/glsl_for_es.h"
#include "../config/settings.h"
#include "FSR1/FSR1.h"

#define DEBUG 0

struct shader_t shaderInfo;

UnorderedMap<GLuint, bool> shader_map_is_sampler_buffer_emulated;

bool can_run_essl3(unsigned int esversion, const char* glsl) {
    if (strncmp(glsl, "#version 100", 12) == 0) {
        return true;
    }

    unsigned int glsl_version = 0;
    if (strncmp(glsl, "#version 300 es", 15) == 0) {
        glsl_version = 300;
    } else if (strncmp(glsl, "#version 310 es", 15) == 0) {
        glsl_version = 310;
    } else if (strncmp(glsl, "#version 320 es", 15) == 0) {
        glsl_version = 320;
    } else {
        return false;
    }
    return esversion >= glsl_version;
}

bool is_direct_shader(const char* glsl) {
    bool es3_ability = can_run_essl3(hardware->es_version, glsl);
    return es3_ability;
}

bool check_if_sampler_buffer_used(std::string str) {
    return str.find("samplerBuffer") != std::string::npos;
}

void glShaderSource(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length) {
    LOG()
    shaderInfo.id = 0;
    shaderInfo.converted = "";
    shaderInfo.frag_data_changed_converted.clear();
    shaderInfo.frag_data_changed = 0;
    size_t l = 0;
    for (int i = 0; i < count; i++)
        l += (length && length[i] >= 0) ? length[i] : strlen(string[i]);
    std::string glsl_src, essl_src;
    glsl_src.reserve(l + 1);
    if (length) {
        for (int i = 0; i < count; i++) {
            if (length[i] >= 0)
                glsl_src += std::string_view(string[i], length[i]);
            else
                glsl_src += string[i];
        }
    } else {
        for (int i = 0; i < count; i++) {
            glsl_src += string[i];
        }
    }

    bool is_sampler_buffer_emulated = hardware->emulate_texture_buffer && check_if_sampler_buffer_used(glsl_src);

    if (is_direct_shader(glsl_src.c_str())) {
        LOG_D("[INFO] [Shader] Direct shader source: ")
        LOG_D("%s", glsl_src.c_str())
        essl_src = glsl_src;
    } else {
        int glsl_version = getGLSLVersion(glsl_src.c_str());
        LOG_D("[INFO] [Shader] Shader source: ")
        LOG_D("%s", glsl_src.c_str())
        GLint shaderType;
        GLES.glGetShaderiv(shader, GL_SHADER_TYPE, &shaderType);
        int return_code = 0;
        essl_src = GLSLtoGLSLES(glsl_src.c_str(), shaderType, hardware->es_version, glsl_version, return_code);

        if (essl_src.empty()) {
            LOG_W_FORCE("Failed to convert shader %d (empty result).", shader)
            LOG_E("Failed to convert shader %d.", shader)
            return;
        }
        // Report the conversion verdict unconditionally. When return_code < 0
        // GLSLtoGLSLES() silently hands back the RAW desktop GLSL, which the
        // iOS host driver (ANGLE) then rejects with a misleading
        // "ERROR: 1:1: '' : syntax error" — this line is what tells the two
        // failure modes apart in latestlog.txt.
        if (return_code < 0) {
            LOG_W_FORCE("[MG] Shader %d conversion FAILED (code=%d, glslver=%d, esver=%u) — falling back to RAW desktop GLSL!",
                        shader, return_code, glsl_version, hardware->es_version)
            LOG_W_FORCE("[MG] Raw source head: %.160s", glsl_src.c_str())
        } else {
            LOG_W_FORCE("[MG] Shader %d converted OK (glslver=%d -> essl ver=%u)", shader, glsl_version, hardware->es_version)
        }
        // Post-conversion sanity gate (iOS "1:1: ''" incident, 2026-08).
        //
        // "converted OK" only means the std::string is non-empty. The driver
        // receives `essl_src.c_str()` and measures it with strlen(), so a
        // translated source that begins with a NUL byte (or contains one)
        // reaches ANGLE as an EMPTY string and fails with exactly
        //   ERROR: 1:1: '' : syntax error
        // while this layer logs "converted OK" — the two together are
        // impossible to explain without this gate. SPIRV-Cross always emits
        // "#version" first, so anything else here is corrupt toolchain output
        // (e.g. a 3rdparty/ tree not checked out at the pinned commits).
        // Refuse to submit and say why; the empty-cache-entry variant is
        // handled in GLSLtoGLSLES().
        if (essl_src.find('\0') != std::string::npos || essl_src.compare(0, 8, "#version") != 0) {
            LOG_W_FORCE("[MG] Shader %d: translated ESSL is CORRUPT (size=%zu, strlen=%zu, head='%.64s') — refusing to submit to driver.",
                        shader, essl_src.size(), strlen(essl_src.c_str()), essl_src.c_str())
            LOG_W_FORCE("[MG] This means the glslang/SPIRV-Cross build did not produce valid ESSL. Verify 3rdparty/ is checked out at the pinned submodule commits (see Makefile dep_mg).")
            return;
        }
        LOG_D("\n[INFO] [Shader] Converted Shader source: \n%s", essl_src.c_str())
    }
    if (!essl_src.empty()) {
        shaderInfo.id = shader;
        shaderInfo.converted = essl_src;
        const char* s[] = {essl_src.c_str()};
        // Submit exactly ONE string: the application's source segments were
        // already concatenated into `essl_src` above. Forwarding the caller's
        // `count` with a 1-element array makes the driver read past the end of
        // `s` whenever the app passes more than one source string.
        GLES.glShaderSource(shader, 1, s, nullptr);
        if (hardware->emulate_texture_buffer)
            shader_map_is_sampler_buffer_emulated[shader] = is_sampler_buffer_emulated;
    } else
        LOG_E("Failed to convert glsl.")
    CHECK_GL_ERROR
}

void glGetShaderiv(GLuint shader, GLenum pname, GLint* params) {
    LOG()
    GLES.glGetShaderiv(shader, pname, params);
    // Report every compile failure unconditionally (the cheat below stays
    // gated by ignore_error): without this line a driver-side rejection is
    // invisible in latestlog unless the game happens to log the info log
    // itself, and the ANGLE message is exactly what pinpoints the failure.
    if (pname == GL_COMPILE_STATUS && !*params) {
        GLchar infoLog[1024];
        GLES.glGetShaderInfoLog(shader, 1024, nullptr, infoLog);
        LOG_W_FORCE("Shader %d compilation failed: \n%s", shader, infoLog)
        if (global_settings.ignore_error >= IgnoreErrorLevel::Partial) {
            LOG_W_FORCE("Now try to cheat.")
            *params = GL_TRUE;
        }
    }
    CHECK_GL_ERROR
}

GLuint glCreateShader(GLenum shaderType) {
    if (global_settings.fsr1_setting != FSR1_Quality_Preset::Disabled && !fsrInitialized) {
        InitFSRResources();
    }

    LOG()
    LOG_D("glCreateShader(%s)", glEnumToString(shaderType))
    GLuint shader = GLES.glCreateShader(shaderType);
    if (shader != 0 && hardware->emulate_texture_buffer) shader_map_is_sampler_buffer_emulated[shader] = false;
    CHECK_GL_ERROR
    return shader;
}