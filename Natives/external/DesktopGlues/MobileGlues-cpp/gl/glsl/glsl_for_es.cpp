// MobileGlues - gl/glsl/glsl_for_es.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#include "glsl_for_es.h"

#include <glslang/Public/ShaderLang.h>
#include <glslang/Include/Types.h>
#include <spirv_cross/spirv_cross_c.h>
#include "../log.h"
#include "glslang/SPIRV/GlslangToSpv.h"
#include <string>
#include <string_view>
#include <regex>
#include <algorithm>
#include <sstream>
#include "cache.h"
#include "../../version.h"

#define DEBUG 0

const char* atomicCounterEmulatedWatermark = "// Non-opaque atomic uniform converted to SSBO";

static const TBuiltInResource& InitResources() {
    static const TBuiltInResource resources = []{
        TBuiltInResource res{};

        res.maxLights = 32;
        res.maxClipPlanes = 6;
        res.maxTextureUnits = 32;
        res.maxTextureCoords = 32;
        res.maxVertexAttribs = 64;
        res.maxVertexUniformComponents = 4096;
        res.maxVaryingFloats = 64;
        res.maxVertexTextureImageUnits = 32;
        res.maxCombinedTextureImageUnits = 80;
        res.maxTextureImageUnits = 32;
        res.maxFragmentUniformComponents = 4096;
        res.maxDrawBuffers = 32;
        res.maxVertexUniformVectors = 128;
        res.maxVaryingVectors = 8;
        res.maxFragmentUniformVectors = 16;
        res.maxVertexOutputVectors = 16;
        res.maxFragmentInputVectors = 15;
        res.minProgramTexelOffset = -8;
        res.maxProgramTexelOffset = 7;
        res.maxClipDistances = 8;
        res.maxComputeWorkGroupCountX = 65535;
        res.maxComputeWorkGroupCountY = 65535;
        res.maxComputeWorkGroupCountZ = 65535;
        res.maxComputeWorkGroupSizeX = 1024;
        res.maxComputeWorkGroupSizeY = 1024;
        res.maxComputeWorkGroupSizeZ = 64;
        res.maxComputeUniformComponents = 1024;
        res.maxComputeTextureImageUnits = 16;
        res.maxComputeImageUniforms = 8;
        res.maxComputeAtomicCounters = 8;
        res.maxComputeAtomicCounterBuffers = 1;
        res.maxVaryingComponents = 60;
        res.maxVertexOutputComponents = 64;
        res.maxGeometryInputComponents = 64;
        res.maxGeometryOutputComponents = 128;
        res.maxFragmentInputComponents = 128;
        res.maxImageUnits = 8;
        res.maxCombinedImageUnitsAndFragmentOutputs = 8;
        res.maxCombinedShaderOutputResources = 8;
        res.maxImageSamples = 0;
        res.maxVertexImageUniforms = 0;
        res.maxTessControlImageUniforms = 0;
        res.maxTessEvaluationImageUniforms = 0;
        res.maxGeometryImageUniforms = 0;
        res.maxFragmentImageUniforms = 8;
        res.maxCombinedImageUniforms = 8;
        res.maxGeometryTextureImageUnits = 16;
        res.maxGeometryOutputVertices = 256;
        res.maxGeometryTotalOutputComponents = 1024;
        res.maxGeometryUniformComponents = 1024;
        res.maxGeometryVaryingComponents = 64;
        res.maxTessControlInputComponents = 128;
        res.maxTessControlOutputComponents = 128;
        res.maxTessControlTextureImageUnits = 16;
        res.maxTessControlUniformComponents = 1024;
        res.maxTessControlTotalOutputComponents = 4096;
        res.maxTessEvaluationInputComponents = 128;
        res.maxTessEvaluationOutputComponents = 128;
        res.maxTessEvaluationTextureImageUnits = 16;
        res.maxTessEvaluationUniformComponents = 1024;
        res.maxTessPatchComponents = 120;
        res.maxPatchVertices = 32;
        res.maxTessGenLevel = 64;
        res.maxViewports = 16;
        res.maxVertexAtomicCounters = 0;
        res.maxTessControlAtomicCounters = 0;
        res.maxTessEvaluationAtomicCounters = 0;
        res.maxGeometryAtomicCounters = 0;
        res.maxFragmentAtomicCounters = 8;
        res.maxCombinedAtomicCounters = 8;
        res.maxAtomicCounterBindings = 1;
        res.maxVertexAtomicCounterBuffers = 0;
        res.maxTessControlAtomicCounterBuffers = 0;
        res.maxTessEvaluationAtomicCounterBuffers = 0;
        res.maxGeometryAtomicCounterBuffers = 0;
        res.maxFragmentAtomicCounterBuffers = 1;
        res.maxCombinedAtomicCounterBuffers = 1;
        res.maxAtomicCounterBufferSize = 16384;
        res.maxTransformFeedbackBuffers = 4;
        res.maxTransformFeedbackInterleavedComponents = 64;
        res.maxCullDistances = 8;
        res.maxCombinedClipAndCullDistances = 8;
        res.maxSamples = 4;
        res.maxMeshOutputVerticesNV = 256;
        res.maxMeshOutputPrimitivesNV = 512;
        res.maxMeshWorkGroupSizeX_NV = 32;
        res.maxMeshWorkGroupSizeY_NV = 1;
        res.maxMeshWorkGroupSizeZ_NV = 1;
        res.maxTaskWorkGroupSizeX_NV = 32;
        res.maxTaskWorkGroupSizeY_NV = 1;
        res.maxTaskWorkGroupSizeZ_NV = 1;
        res.maxMeshViewCountNV = 4;

        res.limits.nonInductiveForLoops = true;
        res.limits.whileLoops = true;
        res.limits.doWhileLoops = true;
        res.limits.generalUniformIndexing = true;
        res.limits.generalAttributeMatrixVectorIndexing = true;
        res.limits.generalVaryingIndexing = true;
        res.limits.generalSamplerIndexing = true;
        res.limits.generalVariableIndexing = true;
        res.limits.generalConstantMatrixVectorIndexing = true;

        // Ten fields this table never set, left at 0 by the value-initialisation
        // above. Nine are mesh-shader limits that glslang only reads when a shader
        // asks for them, so 0 was harmless. maxDualSourceDrawBuffersEXT was not:
        // glslang emits
        //     mediump vec4 gl_SecondaryFragDataEXT[gl_MaxDualSourceDrawBuffersEXT];
        // into the ESSL built-in block, and an array sized 0 fails to parse -- which
        // fails the whole built-in table, so every shader routed through glslang was
        // rejected with "unsupported shader version". It only showed on a context
        // whose ESSL version is below the shader's, since a shader the driver can
        // take is passed straight through; ANGLE presents ES 3.1, so turning ANGLE on
        // meant nothing using #version 320 es could compile at all.
        //
        // The values are glslang's own defaults (glslang/ResourceLimits.cpp).
        res.maxDualSourceDrawBuffersEXT = 1;
        res.maxMeshOutputVerticesEXT = 256;
        res.maxMeshOutputPrimitivesEXT = 256;
        res.maxMeshWorkGroupSizeX_EXT = 128;
        res.maxMeshWorkGroupSizeY_EXT = 128;
        res.maxMeshWorkGroupSizeZ_EXT = 128;
        res.maxTaskWorkGroupSizeX_EXT = 128;
        res.maxTaskWorkGroupSizeY_EXT = 128;
        res.maxTaskWorkGroupSizeZ_EXT = 128;
        res.maxMeshViewCountEXT = 4;

        return res;
    }();
    return resources;
}

int getGLSLVersion(const char* glsl_code) {
    std::string code(glsl_code);
    static const std::regex version_pattern(R"(#version\s+(\d{3}))");
    std::smatch match;
    if (std::regex_search(code, match, version_pattern)) {
        return std::stoi(match[1].str());
    }
    return -1;
}

std::string forceSupporterOutput(const std::string& glslCode) {
    bool hasPrecisionFloat =
        glslCode.find("precision ") != std::string::npos && glslCode.find("float;") != std::string::npos;
    bool hasPrecisionInt =
        glslCode.find("precision ") != std::string::npos && glslCode.find("int;") != std::string::npos;

    std::string result;
    result.reserve(glslCode.size() + 64);
    std::string precisionFloat;
    std::string precisionInt;

    if (hasPrecisionFloat && hasPrecisionInt) {
        std::istringstream iss(glslCode);
        std::vector<std::string> lines;
        std::string line;
        while (std::getline(iss, line)) {
            bool isPrecisionLine = (line.find("precision ") != std::string::npos) &&
                                   (line.find("float;") != std::string::npos || line.find("int;") != std::string::npos);
            if (!isPrecisionLine) {
                lines.push_back(std::move(line));
            }
        }
        for (size_t i = 0; i < lines.size(); ++i) {
            if (i != 0) result += '\n';
            result += lines[i];
        }
        precisionFloat = "precision highp float;\n";
        precisionInt = "precision highp int;\n";
    } else {
        result = glslCode;
        precisionFloat = hasPrecisionFloat ? "" : "precision highp float;\n";
        precisionInt = hasPrecisionInt ? "" : "precision highp int;\n";
    }

    size_t lastExtensionPos = result.rfind("#extension");
    size_t insertionPos = 0;

    if (lastExtensionPos != std::string::npos) {
        size_t nextNewline = result.find('\n', lastExtensionPos);
        if (nextNewline != std::string::npos) {
            insertionPos = nextNewline + 1;
        } else {
            insertionPos = result.length();
        }
    } else {
        size_t firstNewline = result.find('\n');
        if (firstNewline != std::string::npos) {
            insertionPos = firstNewline + 1;
        } else {
            result = precisionFloat + precisionInt + result;
            return result;
        }
    }

    result.insert(insertionPos, precisionFloat + precisionInt);
    return result;
}

std::string removeLayoutBinding(const std::string& glslCode) {
    static const std::regex bindingRegex(R"(layout\s*\(\s*binding\s*=\s*\d+\s*\)\s*)");
    std::string result = std::regex_replace(glslCode, bindingRegex, "");
    static const std::regex bindingRegex2(R"(layout\s*\(\s*binding\s*=\s*\d+\s*,)");
    result = std::regex_replace(result, bindingRegex2, "layout(");
    return result;
}

void trim(std::string& str) {
    str.erase(str.begin(), std::find_if(str.begin(), str.end(), [](int ch) { return !std::isspace(ch); }));
    str.erase(std::find_if(str.rbegin(), str.rend(), [](int ch) { return !std::isspace(ch); }).base(), str.end());
}

std::string process_uniform_declarations(const std::string& glslCode) {
    std::string result;
    size_t scan_pos = 0;
    size_t chunk_start = 0;
    const size_t length = glslCode.length();
    const std::vector<std::string> precision_kws = {"highp", "lowp", "mediump"};

    result.reserve(glslCode.length());

    while (scan_pos < length) {
        if (glslCode.compare(scan_pos, 7, "uniform") == 0) {
            if (scan_pos > chunk_start) {
                result.append(glslCode, chunk_start, scan_pos - chunk_start);
            }

            const size_t decl_start = scan_pos;
            scan_pos += 7;

            std::string precision, type;
            bool found_precision = false;

            while (scan_pos < length) {
                while (scan_pos < length && std::isspace(glslCode[scan_pos]))
                    ++scan_pos;

                for (const auto& kw : precision_kws) {
                    if (glslCode.compare(scan_pos, kw.length(), kw) == 0) {
                        precision = " " + kw;
                        scan_pos += kw.length();
                        found_precision = true;
                        break;
                    }
                }
                if (found_precision) break;

                const size_t type_start = scan_pos;
                while (scan_pos < length && (std::isalnum(glslCode[scan_pos]) || glslCode[scan_pos] == '_')) {
                    ++scan_pos;
                }
                type = glslCode.substr(type_start, scan_pos - type_start);
                break;
            }

            while (scan_pos < length) {
                while (scan_pos < length && std::isspace(glslCode[scan_pos]))
                    ++scan_pos;

                bool found = false;
                for (const auto& kw : precision_kws) {
                    if (glslCode.compare(scan_pos, kw.length(), kw) == 0) {
                        if (precision.empty()) precision = " " + kw;
                        scan_pos += kw.length();
                        found = true;
                        break;
                    }
                }
                if (!found) break;
            }

            if (type.empty()) {
                const size_t type_start = scan_pos;
                while (scan_pos < length && (std::isalnum(glslCode[scan_pos]) || glslCode[scan_pos] == '_')) {
                    ++scan_pos;
                }
                type = glslCode.substr(type_start, scan_pos - type_start);
            }

            while (scan_pos < length && std::isspace(glslCode[scan_pos]))
                ++scan_pos;
            const size_t name_start = scan_pos;
            while (scan_pos < length && (std::isalnum(glslCode[scan_pos]) || glslCode[scan_pos] == '_')) {
                ++scan_pos;
            }
            const std::string name = glslCode.substr(name_start, scan_pos - name_start);

            size_t decl_end = glslCode.find(';', scan_pos);
            if (decl_end == std::string::npos)
                decl_end = length;
            else
                ++decl_end;
            const bool has_initializer = (glslCode.find('=', scan_pos) < decl_end);
            if (has_initializer) {
                result.append("uniform").append(precision).append(" ").append(type).append(" ").append(name).append(";");
            } else {
                result.append(glslCode, decl_start, decl_end - decl_start);
            }

            scan_pos = chunk_start = decl_end;
        } else {
            ++scan_pos;
        }
    }

    if (chunk_start < length) {
        result.append(glslCode, chunk_start, length - chunk_start);
    }

    return result;
}

std::string processOutColorLocations(const std::string& glslCode) {
    static const std::regex pattern(R"(\n(out highp vec4 outColor)(\d+);)");
    const std::string replacement = "\nlayout(location=$2) $1$2;";
    return std::regex_replace(glslCode, pattern, replacement);
}

bool checkIfAtomicCounterBufferEmulated(std::string_view glslCode) {
    return glslCode.find(atomicCounterEmulatedWatermark) != std::string_view::npos;
}

std::string GLSLtoGLSLES(const char* glsl_code, GLenum glsl_type, uint essl_version, uint glsl_version,
                         int& return_code) {
    std::string sha256_string(glsl_code);
    sha256_string += "\n//" + std::to_string(MAJOR) + "." + std::to_string(MINOR) + "." + std::to_string(REVISION) +
                     "|" + std::to_string(essl_version);
    const char* cachedESSL = Cache::get_instance().get(sha256_string.c_str());
    if (cachedESSL) {
        LOG_D("GLSL Hit Cache:\n%s\n-->\n%s", glsl_code, cachedESSL)
        return_code = checkIfAtomicCounterBufferEmulated(cachedESSL) ? 1 : 0;
        return std::string(cachedESSL);
    }

    return_code = -1;
    std::string converted = GLSLtoGLSLES_2(glsl_code, glsl_type, essl_version, return_code);
    if (return_code >= 0 && !converted.empty()) {
        converted = process_uniform_declarations(converted);
        Cache::get_instance().put(sha256_string.c_str(), converted.c_str());
    }

    return (return_code >= 0) ? converted : std::string(glsl_code);
}

std::string replace_line_starting_with(const std::string& glslCode, const std::string& starting,
                                       const std::string& substitution = "") {
    std::string result;
    size_t length = glslCode.size();
    size_t start = 0;
    size_t current = 0;

    auto append_chunk = [&](size_t end) {
        if (end > start) {
            result.append(glslCode, start, end - start);
        }
    };

    while (current < length) {
        size_t lineStart = current;
        while (current < length && (glslCode[current] == ' ' || glslCode[current] == '\t')) {
            current++;
        }

        bool isLineDirective = false;
        if (current + 5 <= length && glslCode.compare(current, 5, "#line") == 0) {
            isLineDirective = true;
        }

        while (current < length && glslCode[current] != '\r' && glslCode[current] != '\n') {
            current++;
        }

        size_t newlineLength = 0;
        if (current < length) {
            if (glslCode[current] == '\r') {
                newlineLength = (current + 1 < length && glslCode[current + 1] == '\n') ? 2 : 1;
            } else {
                newlineLength = 1;
            }
        }

        if (isLineDirective) {
            append_chunk(lineStart);
            current += newlineLength;
            start = current;
            result += substitution;
        } else {
            current += newlineLength;
        }
    }

    append_chunk(current);
    return result;
}

static inline void replace_all(std::string& str, const std::string& from, const std::string& to) {
    size_t start_pos = 0;
    while ((start_pos = str.find(from, start_pos)) != std::string::npos) {
        str.replace(start_pos, from.length(), to);
        start_pos += to.length();
    }
}

static size_t find_insertion_point(const std::string& glsl) {
    size_t pos = 0;
    size_t insertion_point = 0;

    size_t version_pos = glsl.find("#version");
    if (version_pos != std::string::npos) {
        size_t version_end = glsl.find('\n', version_pos);
        if (version_end == std::string::npos) {
            version_end = glsl.length();
        } else {
            version_end++;
        }
        insertion_point = version_end;
        pos = version_end;
    } else {
        insertion_point = 0;
        pos = 0;
    }

    while (pos < glsl.length()) {
        size_t line_begin = pos;
        while (pos < glsl.length() && std::isspace(glsl[pos])) {
            pos++;
        }
        if (pos >= glsl.length()) break;

        if (glsl[pos] == '#') {
            pos++;
            while (pos < glsl.length() && std::isspace(glsl[pos])) {
                pos++;
            }
            if (glsl.compare(pos, 9, "extension") == 0) {
                size_t ext_end = glsl.find('\n', pos);
                if (ext_end == std::string::npos) {
                    ext_end = glsl.length();
                } else {
                    ext_end++;
                }
                insertion_point = ext_end;
                pos = ext_end;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    return insertion_point;
}
namespace {
struct AtomicCounterDecl {
    std::string var;
    int binding = -1;
    int offset = -1;
    size_t pos = 0; // byte offset of the whole declaration in the source
    size_t len = 0;
    size_t seq = 0; // order within the declaration, tiebreaker for equal positions
};

// Scan the desktop GLSL source for `layout(...) uniform atomic_uint ...;`
// declarations. Multi-variable declarations (`uniform atomic_uint a, b;`) yield
// one entry per name. CounterDecls without a binding qualifier are dropped:
// there is no buffer to attach them to.
std::vector<AtomicCounterDecl> scan_atomic_decls(const std::string& source) {
    std::vector<AtomicCounterDecl> decls;
    static const std::regex decl_rx(
        R"(layout\s*\(\s*([^)]*?)\s*\)\s*uniform\s+atomic_uint\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*;)",
        std::regex::icase);
    static const std::regex bind_rx(R"(binding\s*=\s*(\d+))", std::regex::icase);
    static const std::regex off_rx(R"(offset\s*=\s*(\d+))", std::regex::icase);

    std::smatch m;
    auto it = source.cbegin();
    size_t seq = 0;
    while (std::regex_search(it, source.cend(), m, decl_rx)) {
        size_t pos = std::distance(source.cbegin(), it) + m.position(0);
        size_t len = m.length(0);
        std::smatch b, o;
        const std::string quals = m[1].str();
        int binding = -1;
        int offset = -1;
        if (std::regex_search(quals, b, bind_rx)) binding = std::stoi(b[1].str());
        if (std::regex_search(quals, o, off_rx)) offset = std::stoi(o[1].str());

        // One declaration may list several counters: `uniform atomic_uint a, b;`
        // They share the layout qualifiers; only the first takes the explicit
        // offset, the rest fall into declaration order.
        const std::string names_str = m[2].str();
        std::vector<std::string> names;
        size_t comma;
        size_t start = 0;
        while ((comma = names_str.find(',', start)) != std::string::npos) {
            names.push_back(names_str.substr(start, comma - start));
            start = comma + 1;
        }
        names.push_back(names_str.substr(start));
        for (size_t idx = 0; idx < names.size(); ++idx) {
            std::string name = names[idx];
            const size_t bpos = name.find_first_not_of(" \t");
            const size_t epos = name.find_last_not_of(" \t");
            name = (bpos == std::string::npos) ? "" : name.substr(bpos, epos - bpos + 1);
            if (name.empty()) continue;
            // Without a binding qualifier there is no buffer to attach the
            // counter to; such declarations are left untouched.
            if (binding < 0) continue;
            AtomicCounterDecl decl;
            decl.var = name;
            decl.pos = pos;
            decl.len = len;
            decl.binding = binding;
            decl.offset = (idx == 0 && offset >= 0) ? offset : -1;
            decl.seq = seq++;
            decls.push_back(std::move(decl));
        }
        it = source.cbegin() + pos + len;
    }
    return decls;
}

// Declaration order for counters that share a source position (multi-variable
// declarations) is the order their names were written, so tie on `seq` instead
// of leaving it to std::sort's unstable order.
bool decl_before(const AtomicCounterDecl& a, const AtomicCounterDecl& b) {
    if (a.pos != b.pos) return a.pos < b.pos;
    return a.seq < b.seq;
}

// Fill in the implicit (absent) offsets in declaration order, 4 bytes per
// counter, so explicit offsets keep working for the rest.
void assign_implicit_offsets(std::vector<AtomicCounterDecl>& decls) {
    std::map<int, std::vector<size_t>> by_binding;
    for (size_t i = 0; i < decls.size(); ++i) by_binding[decls[i].binding].push_back(i);
    for (auto& entry : by_binding) {
        std::vector<size_t>& members = entry.second;
        std::sort(members.begin(), members.end(), [&](size_t a, size_t b) { return decl_before(decls[a], decls[b]); });
        int cursor = 0;
        for (size_t i : members) {
            if (decls[i].offset == -1) decls[i].offset = cursor;
            cursor = decls[i].offset + 4;
        }
    }
}
} // namespace

bool process_non_opaque_atomic_to_ssbo(std::string& source) {
    if (source.find("atomicCounter") == std::string::npos) return false;

    std::vector<AtomicCounterDecl> decls = scan_atomic_decls(source);

    // No `atomic_uint` block made it into a usable declaration. `source` may
    // only mention the word inside a comment or an unrelated (plain-uint) name,
    // so this shader needs no emulation and must NOT be flagged as emulated.
    if (decls.empty()) return false;

    // Counters sharing one binding live in the same buffer. Give implicit offsets
    // in declaration order (4 bytes per counter) so explicit offsets keep working.
    assign_implicit_offsets(decls);

    std::set<std::string> atomic_vars;
    std::set<int> emitted;
    std::map<int, size_t> binding_block_pos;
    bool helper_emitted = false;
    std::vector<std::pair<size_t, std::pair<size_t, std::string>>> replacements;
    std::map<int, std::vector<size_t>> by_binding;
    for (size_t i = 0; i < decls.size(); ++i) by_binding[decls[i].binding].push_back(i);

    // atomicCounterDecrement saturates at zero and reports the post-clamp
    // value. `atomicAdd(mem, uint(-1))` would wrap below zero and cannot
    // produce the new value, so use a compare-and-swap loop that serves both.
    // atomicCounterAdd promises the post-add value; routing it through a helper
    // also keeps the app's data expression evaluated exactly once (a bare
    // `atomicAdd(x, d) + d` would run side effects twice).
    static const char* atomicCounterHelper = R"(
uint mgAtomicCounterDecrement(inout uint value) {
    uint current = value;
    for (;;) {
        uint next = (current == 0u) ? 0u : current - 1u;
        uint previous = atomicCompSwap(value, current, next);
        if (previous == current) {
            memoryBarrierBuffer();
            return next;
        }
        current = previous;
    }
}
uint mgAtomicCounterAdd(inout uint value, uint data) {
    uint previous = atomicAdd(value, data);
    memoryBarrierBuffer();
    return previous + data;
}
)";

    for (size_t i = 0; i < decls.size(); ++i) {
        atomic_vars.insert(decls[i].var);
        if (emitted.count(decls[i].binding)) {
            // A sibling of an already-processed binding. Multiple counters can
            // share one declaration (`uniform atomic_uint a, b;`): they then
            // also share the source position the block replacement consumed, so
            // nothing is left to erase there. Only a genuinely separate
            // declaration at a different position gets deleted.
            if (binding_block_pos[decls[i].binding] != decls[i].pos) {
                replacements.push_back({decls[i].pos, {decls[i].len, ""}});
            }
            continue;
        }
        emitted.insert(decls[i].binding);
        binding_block_pos[decls[i].binding] = decls[i].pos;

        // One block per binding; members keep their declared byte offsets, with
        // padding inserted where gaps appear, so std430 mirrors the layout the
        // original atomic buffer had.
        std::vector<size_t> members = by_binding[decls[i].binding];
        std::sort(members.begin(), members.end(), [&](size_t a, size_t b) {
            if (decls[a].offset != decls[b].offset) return decls[a].offset < decls[b].offset;
            return decl_before(decls[a], decls[b]);
        });

        std::string block = "layout(std430, binding=" + std::to_string(decls[i].binding) +
                            ") buffer AtomicCounterSSBO_" + std::to_string(decls[i].binding) + " {\n";
        int cursor = 0;
        int pad = 0;
        for (size_t mi : members) {
            int gap = decls[mi].offset - cursor;
            if (gap > 0) {
                block += "    uint pad_" + std::to_string(decls[i].binding) + "_" + std::to_string(pad++) + "[" +
                         std::to_string(gap / 4) + "];\n";
            }
            block += "    uint " + decls[mi].var + ";\n";
            cursor = decls[mi].offset + 4;
        }
        block += "};\n";
        // Saturating decrement needs a CAS loop; emit the helper once, directly
        // after the first block, so its definition precedes every use.
        if (!helper_emitted) {
            block += atomicCounterHelper;
            helper_emitted = true;
        }
        replacements.push_back({decls[i].pos, {decls[i].len, std::move(block)}});
    }

    // Replace from the back so earlier positions stay valid.
    for (auto rit = replacements.rbegin(); rit != replacements.rend(); ++rit) {
        source.replace(rit->first, rit->second.first, rit->second.second);
    }

    for (const auto& var : atomic_vars) {
        // These are built per variable; do not make them static or the regexes
        // stay bound to the first variable forever.
        //
        // The ES shared-memory/SSBO atomics return the value *before* the
        // operation, while atomicCounterIncrement/Add promise the *new* value,
        // so the raw return has to be corrected with an extra add.
        const std::regex incRx(R"(\batomicCounterIncrement\s*\(\s*)" + var + R"(\s*\))", std::regex::icase);
        source = std::regex_replace(source, incRx, "(atomicAdd(" + var + ", 1u) + 1u)");

        // atomicCounterDecrement saturates at zero instead of wrapping, which a
        // plain atomicAdd(..., uint(-1)) cannot express. A CAS loop that clamps
        // to 0 handles it (see the helper injected next to the first block).
        const std::regex decRx(R"(\batomicCounterDecrement\s*\(\s*)" + var + R"(\s*\))", std::regex::icase);
        source = std::regex_replace(source, decRx, "mgAtomicCounterDecrement(" + var + ")");

        // atomicCounterAdd returns the incremented (new) value, and its data
        // expression must not run twice.
        const std::regex addRx(R"(\batomicCounterAdd\s*\(\s*)" + var + R"(\s*,\s*([^)]+)\s*\))",
                               std::regex::icase);
        source = std::regex_replace(source, addRx, "mgAtomicCounterAdd(" + var + ", ($1))");

        const std::regex cntRx(R"(\batomicCounter\s*\(\s*)" + var + R"(\s*\))", std::regex::icase);
        source = std::regex_replace(source, cntRx, var);
    }

    {
        static const std::regex rx_barrier(R"(([ \t]*\batomicAdd\b[^;]*;))", std::regex::icase);
        std::set<size_t> processed_positions;
        std::string result;
        size_t last_pos = 0;

        for (auto it = std::sregex_iterator(source.begin(), source.end(), rx_barrier); it != std::sregex_iterator();
             ++it) {
            size_t start_pos = it->position();
            size_t end_pos = start_pos + it->length();
            if (processed_positions.find(start_pos) != processed_positions.end()) {
                continue;
            }
            result += source.substr(last_pos, start_pos - last_pos);
            std::string matched_stmt = it->str();
            result += matched_stmt;
            result += "\n    memoryBarrierBuffer();";
            processed_positions.insert(start_pos);
            last_pos = end_pos;
        }
        result += source.substr(last_pos);
        source = std::move(result);
    }

    source += "\n" + std::string(atomicCounterEmulatedWatermark);
    return true;
}

std::vector<AtomicBufferBinding> extract_atomic_buffer_bindings(const std::string& source) {
    std::vector<AtomicBufferBinding> out;
    std::vector<AtomicCounterDecl> decls = scan_atomic_decls(source);
    if (decls.empty()) return out;
    assign_implicit_offsets(decls);

    std::map<int, std::vector<size_t>> by_binding;
    for (size_t i = 0; i < decls.size(); ++i) by_binding[decls[i].binding].push_back(i);
    for (auto& entry : by_binding) {
        const int binding = entry.first;
        std::vector<size_t>& members = entry.second;
        std::sort(members.begin(), members.end(), [&](size_t a, size_t b) { return decl_before(decls[a], decls[b]); });
        AtomicBufferBinding info;
        info.binding = binding;
        for (size_t i : members) info.counter_offsets.push_back(decls[i].offset);
        out.push_back(std::move(info));
    }
    return out;
}

void process_sampler_buffer(std::string& source) { // a simplized version, should be rewritten in the future
    if (source.find("isamplerBuffer") == std::string::npos) {
        return;
    }

    size_t pos = 0;
    while ((pos = source.find("isamplerBuffer", pos)) != std::string::npos) {
        source.replace(pos, 14, "isampler2D");
        pos += 11;
    }

    static const std::regex texelFetchPattern(R"(texelFetch\s*\(\s*(\w+)\s*,\s*([^)]+?)\s*\))");
    source = std::regex_replace(source, texelFetchPattern,
                                "texelFetch($1, ivec2(($2) % u_BufferTexWidth, ($2) / u_BufferTexWidth), 0)");

    static const char* boundaryProtection = R"(
ivec2 bufferCoords(int index) {
    int width = u_BufferTexWidth;
    int x = index % width;
    int y = index / width;
    if (y >= u_BufferTexHeight) {
        y = u_BufferTexHeight - 1;
        x = width - 1;
    }
    return ivec2(x, y);
}
)";

    static const std::regex texelFetchIvec2(R"(texelFetch\((\w+)\s*,\s*ivec2\(([^)]+)\)\s*,\s*0\))");
    source = std::regex_replace(source, texelFetchIvec2, "texelFetch($1, bufferCoords($2), 0)");

    size_t insertion_point = find_insertion_point(source);
    if (insertion_point != std::string::npos) {
        source.insert(insertion_point, boundaryProtection);
    }

    static const char* uniformDecl = R"(
uniform int u_BufferTexWidth;
uniform int u_BufferTexHeight;
)";

    insertion_point = find_insertion_point(source);
    if (insertion_point != std::string::npos) {
        insertion_point = source.find('\n', insertion_point);
        if (insertion_point != std::string::npos) {
            source.insert(insertion_point + 1, uniformDecl);
        }
    }
}

static void inject_textureQueryLod(std::string& glsl) {
    static const std::regex defRegex(R"(vec2\s+mg_textureQueryLod\s*\()", std::regex::ECMAScript);
    if (glsl.find("textureQueryLod") == std::string::npos) {
        return;
    }
    if (std::regex_search(glsl, defRegex)) {
        return;
    }

    static const char* textureQueryLodImpl = R"(
#define textureQueryLod mg_textureQueryLod

vec2 mg_textureQueryLod(sampler2D tex, vec2 uv) {
    vec4 _ = textureLod(tex, uv, 0.0);
    vec2 tSize = vec2(textureSize(tex, 0));
    vec2 dx = dFdx(uv * tSize);
    vec2 dy = dFdy(uv * tSize);
    float dmax = max(length(dx), length(dy));
    float lod = log2(max(dmax, 1e-6));
    return vec2(lod);
}
vec2 mg_textureQueryLod(sampler2DShadow tex, vec2 uv) {
    float _ = textureLod(tex, vec3(uv, 0.0), 0.0);
    vec2 tSize = vec2(textureSize(tex, 0));
    vec2 dx = dFdx(uv * tSize);
    vec2 dy = dFdy(uv * tSize);
    float dmax = max(length(dx), length(dy));
    float lod = log2(max(dmax, 1e-6));
    return vec2(lod);
}
vec2 mg_textureQueryLod(samplerCube tex, vec3 dir) {
    vec4 _ = textureLod(tex, dir, 0.0);
    vec3 dx = dFdx(dir);
    vec3 dy = dFdy(dir);
    float dmax = max(length(dx), length(dy)) * 512.0;
    float lod = log2(max(dmax, 1e-6));
    
}
)";

    size_t insertPos = find_insertion_point(glsl);
    glsl.insert(insertPos, "\n" + std::string(textureQueryLodImpl) + "\n");
}

static inline void inject_temporal_filter(std::string& glsl) {
    static const std::regex defRegex(R"(vec4\s+GI_TemporalFilter\s*\()", std::regex::ECMAScript);
    if (glsl.find("GI_TemporalFilter") == std::string::npos) {
        return;
    }
    if (std::regex_search(glsl, defRegex)) {
        return;
    }

    static const std::regex uniformRegex(
        R"(^\s*(?:layout\s*\([^)]*\)\s*)?uniform\s+\w+(?:\s*\[\s*\d+\s*\])?\s+\w+(?:\s*\[\s*\d+\s*\])?\s*;.*$)",
        std::regex::ECMAScript | std::regex::multiline);
    std::sregex_iterator it(glsl.begin(), glsl.end(), uniformRegex);
    std::sregex_iterator end;
    size_t insertPos = 0;
    for (; it != end; ++it) {
        insertPos = it->position() + it->length();
    }

    static const char* GI_TemporalFilterImpl = R"(
vec4 GI_TemporalFilter() {
    vec2 uv = gl_FragCoord.xy / screenSize;
    uv += taaJitter * pixelSize;
    vec4 currentGI = texture(colortex0, uv);
    float depth = texture(depthtex0, uv).r;
    vec4 clipPos = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 viewPos = gbufferProjectionInverse * clipPos;
    viewPos /= viewPos.w;
    vec4 worldPos = gbufferModelViewInverse * viewPos;
    vec4 prevClipPos = gbufferPreviousProjection * (gbufferPreviousModelView * worldPos);
    prevClipPos /= prevClipPos.w;
    vec2 prevUV = prevClipPos.xy * 0.5 + 0.5;
    vec4 historyGI = texture(colortex1, prevUV);
    float difference = length(currentGI.rgb - historyGI.rgb);
    float thresholdValue = 0.1;
    float adaptiveBlend = mix(0.9, 0.0, smoothstep(thresholdValue, thresholdValue * 2.0, difference));
    vec4 filteredGI = mix(currentGI, historyGI, adaptiveBlend);
    if (difference > thresholdValue * 2.0) {
        filteredGI = currentGI;
    }
    return filteredGI;
}
)";
    glsl.insert(insertPos, "\n" + std::string(GI_TemporalFilterImpl) + "\n");
}

#define xstr(s) str(s)
#define str(s) #s

void inject_mg_macro_definition(std::string& glslCode) {
    std::string macro_definitions =
        "\n#define MG_MOBILEGLUES\n"
        "#define MG_MOBILEGLUES_VERSION " xstr(MAJOR) xstr(MINOR) xstr(REVISION) xstr(PATCH) "\n";

    size_t versionPos = glslCode.rfind("#version");
    size_t insertionPos = 0;

    if (versionPos != std::string::npos) {
        size_t nextNewline = glslCode.find('\n', versionPos);
        insertionPos = (nextNewline != std::string::npos) ? nextNewline + 1 : glslCode.length();
    } else {
        size_t firstNewline = glslCode.find('\n');
        insertionPos = (firstNewline != std::string::npos) ? firstNewline + 1 : 0;
    }

    glslCode.insert(insertionPos, macro_definitions);
}

std::string preprocess_glsl(const std::string& glsl, GLenum shaderType, bool* atomicCounterEmulated) {
    std::string ret = glsl;
    ret = replace_line_starting_with(ret, "#line");
    replace_all(ret, "#ifdef GL_ARB_derivative_control", "#if 0");
    replace_all(ret, "#ifndef GL_ARB_derivative_control", "#if 1");
    replace_all(ret, "const mat3 rotInverse = transpose(rot);",
                "const mat3 rotInverse = mat3(rot[0][0], rot[1][0], rot[2][0], rot[0][1], rot[1][1], rot[2][1], "
                "rot[0][2], rot[1][2], rot[2][2]);");

    inject_temporal_filter(ret);

    if (!g_gles_caps.GL_EXT_texture_query_lod) {
        inject_textureQueryLod(ret);
    }

    inject_mg_macro_definition(ret);

    if (hardware->emulate_texture_buffer) {
        process_sampler_buffer(ret);
    }

    if (global_settings.ext_shader_atomic_counters) {
        *atomicCounterEmulated = process_non_opaque_atomic_to_ssbo(ret);
    } else {
        *atomicCounterEmulated = false;
    }
    return ret;
}

int get_or_add_glsl_version(std::string& glsl) {
    int glsl_version = getGLSLVersion(glsl.c_str());
    if (glsl_version == -1) {
        glsl_version = 150;
        glsl.insert(0, "#version 150\n");
    } else if (glsl_version < 140) {
        glsl = replace_line_starting_with(glsl, "#version", "#version 150 compatibility\n");
        glsl_version = 150;
    }
    LOG_D("GLSL version: %d", glsl_version)
    return glsl_version;
}

std::vector<unsigned int> glsl_to_spirv(GLenum shader_type, int glsl_version, const char* const* shader_src,
                                        int& errc) {
    EShLanguage shader_language;
    switch (shader_type) {
    case GL_VERTEX_SHADER:          shader_language = EShLanguage::EShLangVertex; break;
    case GL_FRAGMENT_SHADER:        shader_language = EShLanguage::EShLangFragment; break;
    case GL_COMPUTE_SHADER:         shader_language = EShLanguage::EShLangCompute; break;
    case GL_TESS_CONTROL_SHADER:    shader_language = EShLanguage::EShLangTessControl; break;
    case GL_TESS_EVALUATION_SHADER: shader_language = EShLanguage::EShLangTessEvaluation; break;
    case GL_GEOMETRY_SHADER:        shader_language = EShLanguage::EShLangGeometry; break;
    default:
        LOG_D("GLSL type not supported!")
        errc = -1;
        return {};
    }

    glslang::TShader shader(shader_language);
    shader.setStrings(shader_src, 1);

    using namespace glslang;

    shader.setEnvInput(EShSourceGlsl, shader_language, EShClientVulkan, glsl_version);
    shader.setEnvClient(EShClientOpenGL, EShTargetOpenGL_450);
    shader.setEnvTarget(EShTargetSpv, EShTargetSpv_1_5);
    shader.setAutoMapLocations(true);
    shader.setPreamble("#undef VULKAN\n");
    shader.setAutoMapBindings(true);

    const TBuiltInResource& resources = InitResources();

    if (!shader.parse(&resources, glsl_version, true, EShMsgDefault)) {
        LOG_D("GLSL Compiling ERROR: \n%s", shader.getInfoLog())
        errc = -1;
        return {};
    }
    LOG_D("GLSL Compiled.")

    glslang::TProgram program;
    program.addShader(&shader);

    if (!program.link(EShMsgDefault)) {
        LOG_D("Shader Linking ERROR: %s", program.getInfoLog())
        errc = -1;
        return {};
    }
    LOG_D("Shader Linked.")

    std::vector<unsigned int> spirv_code;
    glslang::SpvOptions spvOptions;
    spvOptions.disableOptimizer = false;
    glslang::GlslangToSpv(*program.getIntermediate(shader_language), spirv_code, &spvOptions);
    errc = 0;
    return spirv_code;
}

// The context owns the ParsedIR, the compiler and every string they hand back, and the only
// destroy used to sit past the early return. A shader the ES backend rejects is a normal
// outcome and failed translations are not cached, so that leaked the lot again on every
// resource-pack reload. Scoped so no exit can skip it.
namespace {
struct spvc_context_guard_t {
    spvc_context context = nullptr;
    spvc_context_guard_t() = default;
    ~spvc_context_guard_t() {
        if (context) spvc_context_destroy(context);
    }
    spvc_context_guard_t(const spvc_context_guard_t&) = delete;
    spvc_context_guard_t& operator=(const spvc_context_guard_t&) = delete;
};
} // namespace

// SPIRV-Cross throws internally and turns that into a result code at its C boundary; on failure
// it leaves the out-parameter untouched. Dropping the code therefore hands the next call a
// handle that was never written, which crashes rather than reporting anything.
static bool spvc_ok(spvc_context context, spvc_result res, const char* what) {
    if (res == SPVC_SUCCESS) {
        return true;
    }
    LOG_E("Error: %s failed in spirv-cross: %s", what, spvc_context_get_last_error_string(context))
    return false;
}

std::string spirv_to_essl(std::vector<unsigned int> spirv, uint essl_version, int& errc) {
    spvc_parsed_ir ir = nullptr;
    spvc_compiler compiler_glsl = nullptr;
    spvc_compiler_options options = nullptr;
    const char* result = nullptr;

    const SpvId* p_spirv = spirv.data();
    size_t word_count = spirv.size();

    LOG_D("spirv_code.size(): %d", spirv.size())

    // Declared before 'essl': the compiled source lives in context-owned memory and is only
    // copied out when the std::string is constructed, so the guard has to outlive it.
    spvc_context_guard_t guard;
    if (spvc_context_create(&guard.context) != SPVC_SUCCESS || !guard.context) {
        LOG_E("Error: could not create a spirv-cross context.")
        errc = -1;
        return "";
    }
    spvc_context context = guard.context;

    if (!spvc_ok(context, spvc_context_parse_spirv(context, p_spirv, word_count, &ir), "spvc_context_parse_spirv") ||
        !ir) {
        errc = -1;
        return "";
    }
    if (!spvc_ok(context,
                 spvc_context_create_compiler(context, SPVC_BACKEND_GLSL, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
                                              &compiler_glsl),
                 "spvc_context_create_compiler") ||
        !compiler_glsl) {
        errc = -1;
        return "";
    }
    if (!spvc_ok(context, spvc_compiler_create_compiler_options(compiler_glsl, &options),
                 "spvc_compiler_create_compiler_options") ||
        !options) {
        errc = -1;
        return "";
    }
    // A silently dropped GLSL_ES option would emit desktop GLSL and hand it straight to the
    // driver, so these are checked too.
    if (!spvc_ok(context,
                 spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_GLSL_VERSION,
                                                essl_version >= 300 ? essl_version : 300),
                 "spvc_compiler_options_set_uint") ||
        !spvc_ok(context, spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_GLSL_ES, SPVC_TRUE),
                 "spvc_compiler_options_set_bool") ||
        !spvc_ok(context, spvc_compiler_install_compiler_options(compiler_glsl, options),
                 "spvc_compiler_install_compiler_options")) {
        errc = -1;
        return "";
    }
    if (!spvc_ok(context, spvc_compiler_compile(compiler_glsl, &result), "spvc_compiler_compile") || !result) {
        errc = -1;
        return "";
    }

    std::string essl = result;

    errc = 0;
    return essl;
}

static bool glslang_inited = false;

std::string GLSLtoGLSLES_2(const char* glsl_code, GLenum glsl_type, uint essl_version, int& return_code) {
    bool atomicCounterEmulated = false;
    std::string correct_glsl_str = preprocess_glsl(glsl_code, glsl_type, &atomicCounterEmulated);
    LOG_D("Firstly converted GLSL:\n%s", correct_glsl_str.c_str())
    int glsl_version = get_or_add_glsl_version(correct_glsl_str);

    if (!glslang_inited) {
        glslang::InitializeProcess();
        glslang_inited = true;
    }

    const char* s[] = {correct_glsl_str.c_str()};
    int errc = 0;
    std::vector<unsigned int> spirv_code = glsl_to_spirv(glsl_type, glsl_version, s, errc);
    if (errc != 0) {
        return_code = -1;
        return "";
    }

    errc = 0;
    std::string essl = spirv_to_essl(std::move(spirv_code), essl_version, errc);
    if (errc != 0) {
        return_code = -2;
        return "";
    }

    if (glsl_type != GL_COMPUTE_SHADER) {
        essl = removeLayoutBinding(essl);
    }
    essl = processOutColorLocations(essl);
    essl = forceSupporterOutput(essl);

    LOG_D("Originally GLSL to GLSL ES Complete: \n%s", essl.c_str())
    return_code = atomicCounterEmulated ? 1 : 0;
    return essl;
}