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

std::unordered_map<GLuint, ShaderInfo> g_shaderInfos;

UnorderedMap<GLuint, bool> shader_map_is_sampler_buffer_emulated;

UnorderedMap<GLuint, bool> shader_map_is_atomic_counter_emulated;

UnorderedMap<GLuint, std::vector<AtomicBufferBinding>> shader_map_atomic_bindings;

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

bool check_if_sampler_buffer_used(const std::string& str) {
    return str.find("samplerBuffer") != std::string::npos;
}

void glShaderSource(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length) {
    LOG()
    ShaderInfo& info = g_shaderInfos[shader];
    info.converted.clear();
    info.frag_data_changed_converted.clear();
    info.frag_data_changed = 0;

    size_t l = 0;
    for (int i = 0; i < count; i++) l += (length && length[i] >= 0) ? length[i] : strlen(string[i]);

    std::string glsl_src, essl_src;
    glsl_src.reserve(l + 1);
    if (length) {
        for (int i = 0; i < count; i++) {
            if (length[i] >= 0) glsl_src += std::string_view(string[i], length[i]);
            else glsl_src += string[i];
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
        // A shader that already runs on this GLES still needs the emulation pass
        // when the driver cannot express native atomic counters at all: direct
        // shaders were bypassing it entirely, so their atomic_uint bindings landed
        // on a target the driver rejects.
        if (global_settings.ext_shader_atomic_counters) {
            if (process_non_opaque_atomic_to_ssbo(essl_src)) {
                shader_map_is_atomic_counter_emulated[shader] = true;
                LOG_D("[INFO] [Shader] Atomic counter emulated in direct shader %d", shader)
            }
        }
    } else {
        GLint shaderType;
        GLES.glGetShaderiv(shader, GL_SHADER_TYPE, &shaderType);
        unsigned es_version = hardware->es_version;

        int glsl_version = getGLSLVersion(glsl_src.c_str());
        LOG_D("[INFO] [Shader] Shader source: ")
        LOG_D("%s", glsl_src.c_str())

        int return_code = 0;
        essl_src = GLSLtoGLSLES(glsl_src.c_str(), shaderType, es_version, glsl_version, return_code);

        if (return_code == 1) {
            shader_map_is_atomic_counter_emulated[shader] = true;
            LOG_D("[INFO] [Shader] Atomic counter emulated in shader %d", shader)
        }

        if (essl_src.empty()) {
            LOG_E("Failed to convert shader %d. Falling back to original desktop GLSL – rendering may break.", shader);
            essl_src = glsl_src;
        }

        LOG_D("\n[INFO] [Shader] Converted Shader source: \n%s", essl_src.c_str())
    }

    if (global_settings.ext_shader_atomic_counters) {
        // Track which atomic counter buffers the shader uses so the program
        // can answer glGetActiveAtomicCounterBufferiv. Parsed from the source
        // the application supplied: it is what declares the counters, and it
        // stays valid across the GLSL cache.
        auto bindings = extract_atomic_buffer_bindings(glsl_src);
        if (!bindings.empty()) shader_map_atomic_bindings[shader] = std::move(bindings);
    }

    if (!essl_src.empty()) {
        info.converted = essl_src;
        const char* s[] = {essl_src.c_str()};
        GLES.glShaderSource(shader, 1, s, nullptr);
        if (hardware->emulate_texture_buffer) shader_map_is_sampler_buffer_emulated[shader] = is_sampler_buffer_emulated;
    } else {
        LOG_E("Shader source empty for shader %d, unable to submit.", shader)
    }

    CHECK_GL_ERROR
}

void glGetShaderiv(GLuint shader, GLenum pname, GLint* params) {
    LOG()
    GLES.glGetShaderiv(shader, pname, params);

    if (pname == GL_COMPILE_STATUS && !*params) {
        int ignore_level = 0;
        auto it = g_shaderInfos.find(shader);
        if (it != g_shaderInfos.end()) {
            ignore_level = it->second.ignore_error_level;
        }
        if (ignore_level >= static_cast<int>(IgnoreErrorLevel::Partial)) {
            GLchar infoLog[512];
            GLES.glGetShaderInfoLog(shader, 512, nullptr, infoLog);
            LOG_W_FORCE("Shader %d compilation failed: \n%s", shader, infoLog)
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

    if (shader != 0) {
        g_shaderInfos[shader].ignore_error_level = static_cast<int>(global_settings.ignore_error);
        if (hardware->emulate_texture_buffer) {
            shader_map_is_sampler_buffer_emulated[shader] = false;
        }
    }

    CHECK_GL_ERROR
    return shader;
}