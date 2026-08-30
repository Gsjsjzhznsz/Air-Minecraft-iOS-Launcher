// MobileGlues - gl/shader.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include <cctype>
#include <cstdio>
#include <cstring>
#include <vector>
#include "shader.h"

#ifndef GL_SHADER_SOURCE_LENGTH
#define GL_SHADER_SOURCE_LENGTH 0x8B88
#endif

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

// The variable names of every samplerBuffer declared in the shader's ORIGINAL
// desktop-GLSL source, recorded when this wrapper converts the source. The
// draw-path sampler rewiring (gl/drawing.cpp setupBufferTextureUniforms) must
// repoint ONLY these samplers at the emulation unit: a Sodium 0.9 chunk program
// carries the section-info isamplerBuffer AND the ordinary sampler2D uniforms
// u_LightTex / u_BlockTex in one program, and repointing those two as well made
// every chunk fragment sample the section-info texture for its atlas and light
// map -- color.a read back as garbage below ALPHA_CUTOUT and the whole chunk
// geometry discarded itself out of existence (MobileGlues-release issue #432,
// "blocks become completely invisible / transparent", MC 26.2 + Sodium 0.9).
UnorderedMap<GLuint, std::vector<std::string>> shader_map_sampler_buffer_names;

// Scan the ORIGINAL source for samplerBuffer/isamplerBuffer/usamplerBuffer
// declarations and return their variable names. Deliberately regex-free: this
// runs once per converted shader on the conversion thread, where std::regex
// construction costs dwarf the scan itself.
//
// The anchor token is "samplerBuffer", which also ends "isamplerBuffer" and
// "usamplerBuffer"; the character before the anchor decides whether this is one
// of those type tokens or the tail of some unrelated identifier. Commented-out
// declarations may slip through and are harmless: their names resolve to
// location -1 and are skipped at draw time.
static std::vector<std::string> extract_sampler_buffer_names(const std::string& src) {
    std::vector<std::string> names;
    static const char* kToken = "samplerBuffer";
    const size_t kTokenLen = strlen(kToken);
    size_t pos = 0;
    while ((pos = src.find(kToken, pos)) != std::string::npos) {
        // The anchor must start a type token: either at string start, after a
        // non-identifier byte, or directly after the 'i'/'u' precision prefixes.
        bool starts_token = false;
        if (pos == 0) {
            starts_token = true;
        } else {
            const char prev = src[pos - 1];
            if (prev == 'i' || prev == 'u') {
                starts_token = pos < 2 ||
                    !(isalnum(static_cast<unsigned char>(src[pos - 2])) || src[pos - 2] == '_');
            } else {
                starts_token = !(isalnum(static_cast<unsigned char>(prev)) || prev == '_');
            }
        }

        size_t name_end = pos + kTokenLen;
        size_t name_begin = name_end;
        while (name_end < src.size() &&
               (src[name_end] == ' ' || src[name_end] == '\t' || src[name_end] == '\n' ||
                src[name_end] == '\r'))
            ++name_end;
        name_begin = name_end;
        while (name_end < src.size() &&
               (isalnum(static_cast<unsigned char>(src[name_end])) || src[name_end] == '_'))
            ++name_end;

        if (starts_token && name_end > name_begin) {
            // Reject the degenerate case of the anchor itself being consumed as
            // an identifier (e.g. a variable literally named samplerBufferFoo
            // cannot follow a type token, but "samplerBuffer" captured above
            // could be a false start for one).
            std::string name = src.substr(name_begin, name_end - name_begin);
            bool duplicate = false;
            for (const auto& existing : names) {
                if (existing == name) { duplicate = true; break; }
            }
            if (!duplicate) names.push_back(std::move(name));
        }
        pos = name_end > pos + kTokenLen ? name_end : pos + kTokenLen;
    }
    return names;
}

// Failure-correlated record of what THIS wrapper last submitted to the driver
// for each shader id, plus what the driver reports back via glGetShaderSource.
// When a compile later fails, glGetShaderiv() dumps the matching record; that
// single log line distinguishes "conversion produced a hollow/corrupt source"
// from "the source never reached the driver" (delivery/interposition bug).
static UnorderedMap<GLuint, std::string> shader_map_submit_record;

static std::string sanitize_head(const char* s, size_t bytes) {
    std::string out;
    for (size_t i = 0; i < bytes && s[i]; ++i) {
        unsigned char c = (unsigned char)s[i];
        out += (c >= 0x20 && c < 0x7f) ? (char)c : '.';
    }
    return out;
}

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
            if (return_code == -999) {
                LOG_W_FORCE("[MG] Shader %d conversion was aborted by the conversion-thread SIGSEGV guard (see conversion CRASHED log above). Reporting a per-shader failure instead of killing the process.", shader)
            } else {
                LOG_W_FORCE("Failed to convert shader %d (empty result).", shader)
            }
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
        // Read back what the driver actually stored. If the length comes back
        // 0 (or the head differs) the submission was swallowed or mangled
        // between this wrapper and the driver -- that is a delivery bug, not
        // a conversion bug, and the next compile failure will say so.
        {
            GLint src_len = 0;
            GLES.glGetShaderiv(shader, GL_SHADER_SOURCE_LENGTH, &src_len);
            char rb[97] = {0};
            GLsizei rb_len = 0;
            if (src_len > 0)
                GLES.glGetShaderSource(shader, sizeof(rb) - 1, &rb_len, rb);
            size_t submitted_len = strlen(essl_src.c_str());
            char rec[512];
            snprintf(rec, sizeof(rec),
                     "size=%zu strlen=%zu | driver SHADER_SOURCE_LENGTH=%ld readback=%d head(submit)='%.96s' head(readback)='%.96s'%s",
                     essl_src.size(), submitted_len, (long)src_len, (int)rb_len,
                     sanitize_head(essl_src.c_str(), 96).c_str(),
                     sanitize_head(rb, 96).c_str(),
                     (src_len > 0 && strncmp(rb, essl_src.c_str(), 32) != 0) ? " <-- MISMATCH" : "");
            shader_map_submit_record[shader] = rec;
        }
        if (hardware->emulate_texture_buffer) {
            shader_map_is_sampler_buffer_emulated[shader] = is_sampler_buffer_emulated;
            // Names come from the ORIGINAL source: conversion rewrites type
            // tokens and texelFetch shapes but leaves identifiers untouched, so
            // the names are also what glGetUniformLocation must be asked for at
            // draw time. Erase rather than overwrite when the re-sourced shader
            // no longer uses a buffer texture -- shader names are recycled.
            if (is_sampler_buffer_emulated)
                shader_map_sampler_buffer_names[shader] = extract_sampler_buffer_names(glsl_src);
            else
                shader_map_sampler_buffer_names.erase(shader);
        }
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
        auto it = shader_map_submit_record.find(shader);
        if (it != shader_map_submit_record.end()) {
            LOG_W_FORCE("[MG] Shader %d submit record: %s", shader, it->second.c_str())
        } else {
            LOG_W_FORCE("[MG] Shader %d submit record: <none -- source was submitted outside this wrapper>", shader)
        }
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