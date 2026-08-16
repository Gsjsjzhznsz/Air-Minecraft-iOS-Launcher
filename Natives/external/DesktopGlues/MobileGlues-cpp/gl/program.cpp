// MobileGlues - gl/program.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include <regex.h>
#include "GL/glext.h"
#include "GLES3/gl32.h"
#include "log.h"
#include "shader.h"
#include "program.h"
#include <regex>
#include <cstring>
#include <iostream>
#include <cstdint>
#include "../config/settings.h"
#include "drawing.h"
#include "glsl/glsl_for_es.h"

#define DEBUG 0

extern UnorderedMap<GLuint, bool> shader_map_is_sampler_buffer_emulated;
UnorderedMap<GLuint, bool> program_map_is_sampler_buffer_emulated;

extern UnorderedMap<GLuint, bool> shader_map_is_atomic_counter_emulated;
UnorderedMap<GLuint, bool> program_map_is_atomic_counter_emulated;

extern UnorderedMap<GLuint, std::vector<AtomicBufferBinding>> shader_map_atomic_bindings;
UnorderedMap<GLuint, std::vector<AtomicBufferBinding>> program_map_atomic_bindings;

bool g_current_program_needs_sampler_emulation = false;

enum class ShouldGenerateFSState : int {
    Never = 0,
    Maybe = 1,
    Unknown = 2
};

UnorderedMap<GLuint, ShouldGenerateFSState> program_map_should_generate_fs;
std::unordered_map<GLuint, int> g_programIgnoreErrorLevel;
std::unordered_map<GLuint, std::vector<std::pair<GLuint, std::string>>> g_programFragDataBindings;

std::string updateLayoutLocation(const std::string& esslSource, GLuint color, const char* name) {
    const std::string& shaderCode = esslSource;

    std::string pattern = std::string(R"((layout\s*$[^)]*location\s*=\s*\d+[^)]*$\s*)?)") +
                          R"(out\s+((?:highp|mediump|lowp|\w+\s+)*\w+)\s+)" + name + R"(\s*;)";

    std::string replacement = "layout (location = " + std::to_string(color) + ") out $2 " + name + ";";

    std::regex reg(pattern);
    std::string modifiedCode = std::regex_replace(shaderCode, reg, replacement);

    return modifiedCode;
}

void glBindFragDataLocation(GLuint program, GLuint color, const GLchar* name) {
    LOG()
    LOG_D("glBindFragDataLocation(%d, %d, %s)", program, color, name)

    if (strlen(name) > 8 && strncmp(name, "outColor", 8) == 0) {
        const char* numberStr = name + 8;
        bool isNumber = true;
        for (int i = 0; numberStr[i] != '\0'; ++i) {
            if (!isdigit(numberStr[i])) {
                isNumber = false;
                break;
            }
        }

        if (isNumber) {
            unsigned int extractedColor = static_cast<unsigned int>(std::stoul(numberStr));
            if (extractedColor == color) {
                // outColor was bound in glsl process. exit now
                LOG_D("Find outColor* with color *, skipping")
                return;
            }
        }
    }

    // Applied at link time: glBindFragDataLocation only names the program, and
    // which fragment shader it will attach is not known until glLinkProgram.
    g_programFragDataBindings[program].push_back({color, std::string(name)});
}

static std::string DefaultFSSource;
static unsigned CurrentDefaultFSSourceVersion = 0;

void GenerateDefaultFSSource() {
    if (CurrentDefaultFSSourceVersion != hardware->es_version) {
        CurrentDefaultFSSourceVersion = hardware->es_version;
        std::ostringstream ss;
        ss << "#version " << CurrentDefaultFSSourceVersion << " es\n";
        ss << "precision mediump float;\n\n";
        ss << "out vec4 fragColor;\n\n";
        ss << "void main() {\n";
        ss << "    fragColor = vec4(1.0, 1.0, 1.0, 1.0);\n";
        ss << "}\n";
        DefaultFSSource = ss.str();
    }
}

static UnorderedMap<unsigned, GLuint> DefaultFSMap;

void glLinkProgram(GLuint program) {
    LOG()
    LOG_D("glLinkProgram(%d)", program)
    GLint numShaders = 0;
    GLES.glGetProgramiv(program, GL_ATTACHED_SHADERS, &numShaders);
    GLuint fragShader = 0;
    if (numShaders > 0) {
        std::vector<GLuint> shaders(numShaders);
        GLES.glGetAttachedShaders(program, numShaders, nullptr, shaders.data());
        for (GLuint s : shaders) {
            GLint type = 0;
            GLES.glGetShaderiv(s, GL_SHADER_TYPE, &type);
            if (type == GL_FRAGMENT_SHADER) {
                fragShader = s;
                break;
            }
        }
    }

    if (fragShader != 0) {
        auto it = g_shaderInfos.find(fragShader);
        auto bindIt = g_programFragDataBindings.find(program);
        if (it != g_shaderInfos.end()) {
            auto& info = it->second;
            if (bindIt != g_programFragDataBindings.end() && !bindIt->second.empty()) {
                std::string modifiedSource = info.converted;
                for (const auto& binding : bindIt->second) {
                    modifiedSource = updateLayoutLocation(modifiedSource, binding.first, binding.second.c_str());
                }
                info.frag_data_changed_converted = modifiedSource;
                info.frag_data_changed = 1;
            }

            if (info.frag_data_changed) {
                const char* src = info.frag_data_changed_converted.empty()
                                      ? info.converted.c_str()
                                      : info.frag_data_changed_converted.c_str();
                GLES.glShaderSource(fragShader, 1, &src, nullptr);
                GLES.glCompileShader(fragShader);
                GLint status = 0;
                GLES.glGetShaderiv(fragShader, GL_COMPILE_STATUS, &status);
                if (status != GL_TRUE) {
                    char tmp[500];
                    GLES.glGetShaderInfoLog(fragShader, 500, nullptr, tmp);
                    LOG_E("Failed to compile patched shader, log:\n%s", tmp)
                }
                info.frag_data_changed = 0;
                info.frag_data_changed_converted.clear();
            }
        }
    }

    g_programFragDataBindings.erase(program);

    if (program_map_should_generate_fs[program] == ShouldGenerateFSState::Maybe) {
        GenerateDefaultFSSource();
        GLuint& default_fs = DefaultFSMap[CurrentDefaultFSSourceVersion];
        if (!default_fs) {
            default_fs = GLES.glCreateShader(GL_FRAGMENT_SHADER);
            const char* src = DefaultFSSource.c_str();
            GLES.glShaderSource(default_fs, 1, &src, nullptr);
            GLES.glCompileShader(default_fs);
            GLint success = 0;
            GLES.glGetShaderiv(default_fs, GL_COMPILE_STATUS, &success);
            if (!success) {
                GLint logLength = 0;
                GLES.glGetShaderiv(default_fs, GL_INFO_LOG_LENGTH, &logLength);
                std::vector<char> log(logLength);
                GLES.glGetShaderInfoLog(default_fs, logLength, nullptr, log.data());
                LOG_E("Default fragment shader compile error for program %u :\n%s\n", program, log.data());
                GLES.glDeleteShader(default_fs);
                default_fs = 0;
            }
        }
        if (default_fs) {
            LOG_D("Attaching missing default FS for program %u...", program);
            GLES.glAttachShader(program, default_fs);
            program_map_should_generate_fs[program] = ShouldGenerateFSState::Never;
        }
    }

    GLES.glLinkProgram(program);
    CHECK_GL_ERROR
}

void glGetProgramiv(GLuint program, GLenum pname, GLint* params) {
    LOG()
    GLES.glGetProgramiv(program, pname, params);

    if ((pname == GL_LINK_STATUS || pname == GL_VALIDATE_STATUS) && !*params) {
        int ignore_level = 0;
        auto it = g_programIgnoreErrorLevel.find(program);
        if (it != g_programIgnoreErrorLevel.end()) {
            ignore_level = it->second;
        }
        if (ignore_level >= static_cast<int>(IgnoreErrorLevel::Partial)) {
            GLchar infoLog[512];
            GLES.glGetProgramInfoLog(program, 512, nullptr, infoLog);
            LOG_W_FORCE("Program %d linking failed: \n%s", program, infoLog);
            LOG_W_FORCE("Now try to cheat.");
            *params = GL_TRUE;
        }
    }

    CHECK_GL_ERROR
}

void glUseProgram(GLuint program) {
    LOG()
    LOG_D("glUseProgram(%d)", program)
    if (program != gl_state->current_program) {
        gl_state->current_program = program;
        if (hardware->emulate_texture_buffer) {
            auto it = program_map_is_sampler_buffer_emulated.find(program);
            g_current_program_needs_sampler_emulation = (it != program_map_is_sampler_buffer_emulated.end() && it->second);
        } else {
            g_current_program_needs_sampler_emulation = false;
        }
        GLES.glUseProgram(program);
        CHECK_GL_ERROR
    }
}

void glAttachShader(GLuint program, GLuint shader) {
    LOG()
    LOG_D("glAttachShader(%u, %u)", program, shader)
    if (hardware->emulate_texture_buffer && shader_map_is_sampler_buffer_emulated[shader])
        program_map_is_sampler_buffer_emulated[program] = true;
    if (shader_map_is_atomic_counter_emulated[shader]) {
        program_map_is_atomic_counter_emulated[program] = true;
        LOG_D("Shader %d is atomic counter emulated, setting program %d to atomic counter emulated", shader, program)
    }
    // Merge the shader's atomic counter bindings into the program's, keeping
    // the list sorted by binding number so glGetActiveAtomicCounterBufferiv's
    // bufferIndex order is deterministic.
    const auto bit = shader_map_atomic_bindings.find(shader);
    if (bit != shader_map_atomic_bindings.end() && !bit->second.empty()) {
        auto& merged = program_map_atomic_bindings[program];
        for (const AtomicBufferBinding& add : bit->second) {
            size_t found = SIZE_MAX;
            for (size_t k = 0; k < merged.size(); ++k) {
                if (merged[k].binding == add.binding) {
                    found = k;
                    break;
                }
            }
            if (found == SIZE_MAX) {
                merged.push_back(add);
            } else {
                // A second stage can contribute counters to the same buffer.
                for (int off : add.counter_offsets) {
                    if (std::find(merged[found].counter_offsets.begin(), merged[found].counter_offsets.end(), off) ==
                        merged[found].counter_offsets.end()) {
                        merged[found].counter_offsets.push_back(off);
                    }
                }
            }
        }
        std::sort(merged.begin(), merged.end(),
                  [](const AtomicBufferBinding& a, const AtomicBufferBinding& b) { return a.binding < b.binding; });
    }

    GLint type = 0;
    GLES.glGetShaderiv(shader, GL_SHADER_TYPE, &type);
    auto& should_gen_fs_map = program_map_should_generate_fs;
    if (type == GL_FRAGMENT_SHADER) {
        should_gen_fs_map[program] = ShouldGenerateFSState::Never;
    } else if (type == GL_VERTEX_SHADER) {
        auto it = should_gen_fs_map.find(program);
        if (it == should_gen_fs_map.end() || should_gen_fs_map[program] != ShouldGenerateFSState::Never) {
            should_gen_fs_map[program] = ShouldGenerateFSState::Maybe;
        }
    }

    GLES.glAttachShader(program, shader);
    CHECK_GL_ERROR
}

extern UnorderedMap<GLuint, SamplerInfo> g_samplerCacheForSamplerBuffer;

GLuint glCreateProgram() {
    LOG()
    LOG_D("glCreateProgram")
    GLuint program = GLES.glCreateProgram();
    if (program != 0) {
        g_programIgnoreErrorLevel[program] = static_cast<int>(global_settings.ignore_error);
        if (hardware->emulate_texture_buffer) {
            program_map_is_sampler_buffer_emulated[program] = false;
            if (g_samplerCacheForSamplerBuffer.find(program) != g_samplerCacheForSamplerBuffer.end()) {
                g_samplerCacheForSamplerBuffer.erase(program);
            }
        }
        program_map_is_atomic_counter_emulated[program] = false;
        program_map_atomic_bindings[program].clear();
        program_map_should_generate_fs[program] = ShouldGenerateFSState::Unknown;
    }
    CHECK_GL_ERROR
    return program;
}

// GL 3.1's name-only half of the active-uniform query, on top of the ES call that
// already returns the same string.
//
// It was a stub -- a no-op that wrote neither the name nor the length and, being a
// stub rather than an error, left glGetError clean. Callers got whatever was
// already in the buffer they passed.
//
// That is not a cosmetic gap. The standard way to build a name -> location map is
// to walk the active uniforms by index and ask for each name, and a caller doing
// that ended up with a map keyed on garbage: every later lookup missed, so the
// uniforms never got set and kept whatever the driver had zero-initialised them
// to. NeoForge's early loading window does exactly this, and a screenSize of
// (0, 0) turned its every vertex into a division by zero -- gl_Position came out
// non-finite, every primitive was discarded, and the window rendered black with
// nothing anywhere reporting a problem.
void glGetActiveUniformName(GLuint program, GLuint uniformIndex, GLsizei bufSize, GLsizei* length,
                            GLchar* uniformName) {
    LOG()
    LOG_D("glGetActiveUniformName(program: %u, index: %u, bufSize: %d)", program, uniformIndex, bufSize)

    if (length) *length = 0;
    if (bufSize <= 0 || uniformName == nullptr) {
        // Nothing to write. Still forwarded when bufSize is negative so the driver
        // raises the GL_INVALID_VALUE the caller is owed.
        if (bufSize < 0) GLES.glGetActiveUniform(program, uniformIndex, bufSize, nullptr, nullptr, nullptr, nullptr);
        CHECK_GL_ERROR
        return;
    }

    // Same buffer contract in both calls: at most bufSize-1 characters plus the
    // terminator, and a length that excludes it. The size and type this also
    // returns are what glGetActiveUniformsiv is for; they are discarded here.
    GLint size = 0;
    GLenum type = 0;
    GLsizei written = 0;
    uniformName[0] = '\0';
    GLES.glGetActiveUniform(program, uniformIndex, bufSize, &written, &size, &type, uniformName);
    if (length) *length = written;

    LOG_D("  -> \"%s\"", uniformName)
    CHECK_GL_ERROR
}

