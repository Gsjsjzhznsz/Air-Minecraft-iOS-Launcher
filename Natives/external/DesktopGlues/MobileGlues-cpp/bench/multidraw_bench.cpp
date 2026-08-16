// MobileGlues - bench/multidraw_bench.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

// In-process micro benchmark behind the plugin app's "benchmark and sort"
// button. The app dlopens this library, makes a context current through our own
// EGL layer (the same path MGInfoGetter uses to query GL info), then calls
// mg_multidraw_bench_run() and reads back one JSON string.
//
// The measurement therefore runs on the same GPU and driver the game will use,
// but in the plugin app's process, not the game's -- an accepted trade-off for
// being able to run it immediately instead of piggybacking on the next game
// launch (see the delivery notes).
//
// Each (entry point, backend) pair is timed by calling the mg_* implementation
// the dispatcher itself would call, so translation overhead is included. A
// measurement is discarded when g_md_fallback_tick moved, because that means
// the call was actually served by a different backend and the number would be
// a lie.
//
// What this benchmark is really up against is noise, not measurement: the
// numbers being compared are often within a few percent of each other, while a
// phone under a DVFS governor can shift by tens of percent within a second. So
// the schedule matters more than the timer:
//
//   * candidates are measured round-robin, not one candidate to completion --
//     a frequency ramp or a thermal drift then hits every candidate alike
//     instead of systematically favouring whoever was measured while the clock
//     was high;
//   * the traversal order flips every other round, so a candidate cannot
//     profit from always following the same neighbour;
//   * each candidate gets its own iteration count, picked so that one timed
//     batch lasts long enough for the glFinish and clock_gettime overhead to
//     stop mattering -- backends here differ by two orders of magnitude in cost
//     per call, and a fixed count cannot serve both ends;
//   * the reported number is the median over all rounds, not the mean. A
//     scheduler hiccup or a stray compositor frame lands on one round and the
//     median ignores it, whereas a mean would carry it into the ranking;
//   * the spread across rounds is reported alongside, so the UI can tell the
//     user when two candidates are simply too close to separate.
//
// Total wall time is a budget (MG_BENCH_BUDGET_MS, default 8 s) rather than a
// fixed amount of work: a slow device does fewer rounds instead of making the
// user wait proportionally longer.
//
// Whether the numbers are steady enough is judged per entry point, since each
// one is ranked on its own: a function still too shaky to rank is re-measured
// with longer batches while the ones that came out clean drop out of the pass.
// Four passes at most per function -- when even the fourth misses, that
// function's calmest pass is reported with noisy=true and the app puts the
// decision to the user rather than presenting noise as a measurement.

#include "../gl/multidraw.h"
#include "../config/settings.h"
#include "../config/cJSON.h"
#include "../gles/loader.h"
#include "../gl/log.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

extern std::atomic<uint32_t> g_md_fallback_tick;

// Progress of the current run, as attempt * 1000 + permille within that attempt
// (attempt is 0-based). A retry restarts the bar, which is what actually
// happened; keeping both numbers in one atomic keeps them consistent for the
// thread reading them through mg_multidraw_bench_progress().
static std::atomic<int> g_bench_progress{0};

namespace {

// Enough to get past compute shader compilation, scratch buffer growth and the
// first-call probes, and to let the GPU governor notice we are here.
constexpr int BENCH_WARMUP = 8;

// One timed batch aims for this long. A frame here is milliseconds of real
// work, so this comes out to a handful of frames: long enough that one
// scheduler hiccup does not define the sample, short enough that a pass still
// gets many samples.
constexpr double BENCH_TARGET_BATCH_US = 24000.0;
constexpr int BENCH_MIN_FRAMES = 2;
constexpr int BENCH_MAX_FRAMES = 64;

// Odd round counts so the median is a real sample rather than an average of
// two. Five is the floor at which a single outlier cannot move the median.
constexpr int BENCH_MIN_ROUNDS = 5;
constexpr int BENCH_MAX_ROUNDS = 101;

constexpr double BENCH_DEFAULT_BUDGET_US = 8.0e6;
constexpr double BENCH_MIN_BUDGET_US = 1.0e6;
constexpr double BENCH_MAX_BUDGET_US = 120.0e6;

// A spread wider than this means candidates within a few percent of each other
// cannot be told apart, so the pass is retried with longer batches.
constexpr double BENCH_NOISE_TARGET = 0.15;
constexpr int BENCH_MAX_ATTEMPTS = 4;
constexpr double BENCH_MIN_RETRY_SCALE = 2.0;
constexpr double BENCH_MAX_RETRY_SCALE = 8.0;
// How much longer than the base budget a single retry may take, and how long
// the whole thing may take before giving up on ever settling down.
constexpr double BENCH_MAX_BUDGET_SCALE = 3.0;
constexpr double BENCH_TOTAL_BUDGET_US = 75.0e6;

// Written when a run finishes, past any value a real attempt can produce.
constexpr int BENCH_PROGRESS_DONE = BENCH_MAX_ATTEMPTS * 1000;

// ---- The scene: one frame of Minecraft chunk rendering ----
//
// Shaped after Sodium/Embeddium, which is what actually calls glMultiDraw* in
// Minecraft. Sodium keeps every chunk section's geometry in one big VBO and,
// once per render pass, issues a single glMultiDrawElementsBaseVertex over the
// visible sections: one sub-draw per section, count = that section's index
// count, indices all pointing at offset 0 of a shared sequential quad index
// buffer, and baseVertex picking out the section's slice of the VBO.
//
// So the numbers here are per drawn frame, with the sub-draw count, the very
// uneven per-section index counts, the vertex format, the atlas sampling, the
// depth test and the front-to-back order all kept as they are in the game.
// That matters because the backends differ in *where* they spend: unrolling
// costs CPU per sub-draw, compute costs GPU that the rendering also wants. A
// scene with no GPU work cannot see the second kind at all.

constexpr int BENCH_GRID_X = 8;    // sections across
constexpr int BENCH_GRID_Y = 4;    // sections up
// Depth is the knob: how many rows of sections recede from the camera. It is
// chosen at run time rather than compiled in, because the right value is a
// property of the device, not of the benchmark -- see the ladder below.
constexpr int BENCH_SECTIONS_PER_ROW = BENCH_GRID_X * BENCH_GRID_Y;
constexpr int BENCH_SECTION_SIZE = 16;      // blocks per side, as in the game
constexpr int BENCH_QUADS_MIN = 64;         // block faces in a sparse section
constexpr int BENCH_QUADS_MAX = 512;        // ... and in a dense one
constexpr int BENCH_VERTEX_BYTES = 24;      // vec3 pos + vec2 uv + 4x u8 colour

constexpr int BENCH_ATLAS_SIZE = 512;       // block atlas, mipmapped
constexpr int BENCH_ATLAS_TILE = 16;        // 16x16 tiles, as in the game
constexpr int BENCH_DEFAULT_WIDTH = 1280;
constexpr int BENCH_DEFAULT_HEIGHT = 720;

// ---- How big the scene should be ----
//
// A tiler bins every primitive into the tiles it covers, and that list lives in
// a per-context heap that grows on demand and then stops. Past that point the
// job does not slow down, it fails: Mali answers BASE_JD_EVENT_OUT_OF_MEMORY,
// the kernel kills the context, and ANGLE turns the VK_ERROR_DEVICE_LOST into
// GL_CONTEXT_LOST. Measured on a Mali-G77, 512 sections crossed the line and
// 256 did not -- but that number belongs to that phone, and guessing one that
// fits every device means picking a scene too small to be worth measuring.
// (Those measurements predate bench_frame_end: whole batches merged into one
// pass then, so the list held many frames of geometry. With per-frame passes
// the pressure per pass is one frame's worth and the ceiling sits far higher --
// the ladder stays because the limit is still real, just further away.)
//
// So the size is discovered instead, once per run and never written down. The
// run opens at BENCH_START_SECTIONS; a pass that comes back too noisy doubles
// it, because the steadier reading is the one with more real work behind it.
// The first lost context ends the climb for good: whatever crashed is above the
// ceiling, the run drops back below it and stays there. Nothing is remembered
// between runs, so a device that was busy last time is not held to it.
constexpr int BENCH_START_SECTIONS = 256;
constexpr int BENCH_MIN_SECTIONS = BENCH_SECTIONS_PER_ROW;   // one row
// Not a device limit -- a limit on how far a benchmark may go before the scene
// build itself is the slow part. At 2048 the vertex buffer alone is ~57 MB.
constexpr int BENCH_MAX_SECTIONS = 1024;

struct bench_scene_t {
    GLuint program = 0;
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint ibo_shared = 0;   // sequential quad indices, shared by every section
    GLuint ibo_absolute = 0; // same geometry with absolute indices, for the
                             // entry points that have no baseVertex
    GLuint indirect_elements = 0;
    GLuint indirect_arrays = 0;

    GLuint fbo = 0;
    GLuint color_tex = 0;
    GLuint depth_rb = 0;
    GLuint atlas = 0;
    GLint u_mvp = -1;
    int width = BENCH_DEFAULT_WIDTH;
    int height = BENCH_DEFAULT_HEIGHT;
    int sections = BENCH_START_SECTIONS;  // as built, after clamping
    int grid_z = BENCH_START_SECTIONS / BENCH_SECTIONS_PER_ROW;
    float spin = 0.0f;  // moved every frame; a still camera is not a game

    // One entry per section, in front-to-back order.
    std::vector<GLsizei> counts;             // indices per section
    std::vector<const void*> offsets;        // all zero -- the shared index buffer
    std::vector<const void*> offsets_absolute;
    std::vector<GLint> basevertex;           // first vertex of the section
    std::vector<GLint> firsts;               // glMultiDrawArrays: same, as first
    std::vector<GLsizei> counts_arrays;      // ... with vertex counts

    bool ok = false;
    std::string error;
};

// Deterministic noise. The same phone must build the same scene every run, or
// the spread between passes would be measuring the scene, not the driver.
struct bench_rng_t {
    uint32_t state = 0x9E3779B9u;
    uint32_t next() {
        state = state * 1664525u + 1013904223u;
        return state;
    }
    // uniform in [lo, hi]
    int range(int lo, int hi) { return lo + static_cast<int>(next() % static_cast<uint32_t>(hi - lo + 1)); }
    float unit() { return static_cast<float>(next() >> 8) / 16777216.0f; }
};

int bench_dimension(const char* env, int fallback) {
    if (const char* raw = getenv(env)) {
        char* end = nullptr;
        const long v = strtol(raw, &end, 10);
        if (end != raw && v >= 64 && v <= 4096) return static_cast<int>(v);
    }
    return fallback;
}

double now_us() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) * 1e6 + static_cast<double>(ts.tv_nsec) / 1e3;
}

// The one deliberate exemption from the go-through-the-frontend rule (see
// bench_frame_begin): shaders and the program stay on GLES.*. These sources are
// written as ESSL, and the frontend's shader path is a desktop-GLSL-to-ESSL
// translator -- feeding it ESSL is outside its contract. The exemption is safe
// because no backend consults tracked program state: the compute backend saves
// and restores GL_CURRENT_PROGRAM through the driver.
GLuint bench_compile(GLenum type, const char* src, std::string* err) {
    GLuint shader = GLES.glCreateShader(type);
    GLES.glShaderSource(shader, 1, &src, nullptr);
    GLES.glCompileShader(shader);
    GLint ok = GL_FALSE;
    GLES.glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512] = {0};
        GLES.glGetShaderInfoLog(shader, sizeof(log) - 1, nullptr, log);
        *err = std::string("shader compile failed: ") + log;
        GLES.glDeleteShader(shader);
        return 0;
    }
    return shader;
}

// A block atlas: 16x16 tiles of flat-ish colour with per-texel noise, mipmapped.
// The point is not to look like anything, it is to make the sampler do the work
// it does in the game -- a full mip chain, trilinear filtering, and a texel
// stream that does not fit in cache.
void bench_build_atlas(bench_scene_t& s) {
    std::vector<uint8_t> pixels(static_cast<size_t>(BENCH_ATLAS_SIZE) * BENCH_ATLAS_SIZE * 4);
    bench_rng_t rng;
    const int tiles = BENCH_ATLAS_SIZE / BENCH_ATLAS_TILE;
    for (int ty = 0; ty < tiles; ++ty) {
        for (int tx = 0; tx < tiles; ++tx) {
            const uint8_t base_r = static_cast<uint8_t>(rng.range(40, 220));
            const uint8_t base_g = static_cast<uint8_t>(rng.range(40, 220));
            const uint8_t base_b = static_cast<uint8_t>(rng.range(40, 220));
            for (int y = 0; y < BENCH_ATLAS_TILE; ++y) {
                for (int x = 0; x < BENCH_ATLAS_TILE; ++x) {
                    const int px = tx * BENCH_ATLAS_TILE + x;
                    const int py = ty * BENCH_ATLAS_TILE + y;
                    const size_t o = (static_cast<size_t>(py) * BENCH_ATLAS_SIZE + px) * 4;
                    const int n = rng.range(-24, 24);
                    pixels[o + 0] = static_cast<uint8_t>(std::min(255, std::max(0, base_r + n)));
                    pixels[o + 1] = static_cast<uint8_t>(std::min(255, std::max(0, base_g + n)));
                    pixels[o + 2] = static_cast<uint8_t>(std::min(255, std::max(0, base_b + n)));
                    pixels[o + 3] = 255;
                }
            }
        }
    }

    glGenTextures(1, &s.atlas);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, s.atlas);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, BENCH_ATLAS_SIZE, BENCH_ATLAS_SIZE, 0, GL_RGBA,
                      GL_UNSIGNED_BYTE, pixels.data());
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

// Render to a texture the size a phone actually renders at. The 1x1 pbuffer the
// context was created with cannot show a fill-rate cost, and fill rate is
// exactly what the compute backend competes with.
bool bench_build_target(bench_scene_t& s) {
    glGenTextures(1, &s.color_tex);
    glBindTexture(GL_TEXTURE_2D, s.color_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, s.width, s.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    glGenRenderbuffers(1, &s.depth_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, s.depth_rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, s.width, s.height);

    glGenFramebuffers(1, &s.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s.color_tex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, s.depth_rb);
    return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

// The scene goes straight through the GLES table: the multidraw backends read
// GL state through the same table, and the frontend state machine plays no part
// in what is being measured.
// `sections` is rounded down to whole rows and clamped to the ladder; the value
// actually built is left in s.sections, which is what the report must quote.
void bench_scene_build(bench_scene_t& s, int sections) {
    if (!GLES.glCreateShader || !GLES.glGenVertexArrays || !GLES.glGenBuffers ||
        !GLES.glGenFramebuffers || !GLES.glGenTextures || !GLES.glGenerateMipmap) {
        s.error = "GLES entry points missing";
        return;
    }

    sections = std::min(std::max(sections, BENCH_MIN_SECTIONS), BENCH_MAX_SECTIONS);
    s.grid_z = std::max(1, sections / BENCH_SECTIONS_PER_ROW);
    s.sections = s.grid_z * BENCH_SECTIONS_PER_ROW;

    s.width = bench_dimension("MG_BENCH_WIDTH", BENCH_DEFAULT_WIDTH);
    s.height = bench_dimension("MG_BENCH_HEIGHT", BENCH_DEFAULT_HEIGHT);

    // Close to what the game's terrain shader does: transform, sample the
    // atlas, apply the baked light and vertex colour. No alpha test -- the
    // solid pass is the bulk of the frame, and discard would cost every backend
    // its early-z alike while making the comparison less like that pass.
    const char* vs_src = "#version 300 es\n"
                         "layout(location = 0) in vec3 aPos;\n"
                         "layout(location = 1) in vec2 aUV;\n"
                         "layout(location = 2) in vec4 aColor;\n"
                         "uniform mat4 uMVP;\n"
                         "out vec2 vUV;\n"
                         "out vec4 vColor;\n"
                         "void main() {\n"
                         "    vUV = aUV;\n"
                         "    vColor = aColor;\n"
                         "    gl_Position = uMVP * vec4(aPos, 1.0);\n"
                         "}\n";
    const char* fs_src = "#version 300 es\n"
                         "precision mediump float;\n"
                         "uniform sampler2D uAtlas;\n"
                         "in vec2 vUV;\n"
                         "in vec4 vColor;\n"
                         "out vec4 oColor;\n"
                         "void main() {\n"
                         "    vec4 t = texture(uAtlas, vUV);\n"
                         "    oColor = vec4(t.rgb * vColor.rgb * vColor.a, 1.0);\n"
                         "}\n";

    std::string err;
    GLuint vs = bench_compile(GL_VERTEX_SHADER, vs_src, &err);
    if (!vs) {
        s.error = err;
        return;
    }
    GLuint fs = bench_compile(GL_FRAGMENT_SHADER, fs_src, &err);
    if (!fs) {
        GLES.glDeleteShader(vs);
        s.error = err;
        return;
    }
    s.program = GLES.glCreateProgram();
    GLES.glAttachShader(s.program, vs);
    GLES.glAttachShader(s.program, fs);
    GLES.glLinkProgram(s.program);
    GLES.glDeleteShader(vs);
    GLES.glDeleteShader(fs);
    GLint linked = GL_FALSE;
    GLES.glGetProgramiv(s.program, GL_LINK_STATUS, &linked);
    if (!linked) {
        s.error = "program link failed";
        return;
    }
    GLES.glUseProgram(s.program);
    s.u_mvp = GLES.glGetUniformLocation(s.program, "uMVP");
    const GLint u_atlas = GLES.glGetUniformLocation(s.program, "uAtlas");
    if (u_atlas >= 0) GLES.glUniform1i(u_atlas, 0);

    bench_build_atlas(s);
    if (!bench_build_target(s)) {
        s.error = "render target incomplete";
        return;
    }

    // ---- Terrain: one section at a time, near to far ----
    //
    // Sections are walked front-to-back exactly as the game submits them, so
    // the depth test throws away most of the far geometry the way it really
    // does. Sorting the other way would triple the fill cost and measure a
    // frame nobody renders.

    struct vertex_t {
        float x, y, z;
        float u, v;
        uint8_t r, g, b, a;
    };
    static_assert(sizeof(vertex_t) == BENCH_VERTEX_BYTES, "vertex layout drifted");

    std::vector<vertex_t> verts;
    verts.reserve(static_cast<size_t>(s.sections) * BENCH_QUADS_MAX * 4 / 2);

    s.counts.reserve(s.sections);
    s.offsets.reserve(s.sections);
    s.offsets_absolute.reserve(s.sections);
    s.basevertex.reserve(s.sections);
    s.firsts.reserve(s.sections);
    s.counts_arrays.reserve(s.sections);

    bench_rng_t rng;
    const float atlas_tiles = static_cast<float>(BENCH_ATLAS_SIZE / BENCH_ATLAS_TILE);
    int max_quads = 0;

    for (int gz = 0; gz < s.grid_z; ++gz) {
        for (int gy = 0; gy < BENCH_GRID_Y; ++gy) {
            for (int gx = 0; gx < BENCH_GRID_X; ++gx) {
                const int quads = rng.range(BENCH_QUADS_MIN, BENCH_QUADS_MAX);
                max_quads = std::max(max_quads, quads);

                const GLint first_vertex = static_cast<GLint>(verts.size());
                const float ox = (static_cast<float>(gx) - BENCH_GRID_X * 0.5f) * BENCH_SECTION_SIZE;
                const float oy = (static_cast<float>(gy) - BENCH_GRID_Y * 0.5f) * BENCH_SECTION_SIZE;
                const float oz = -static_cast<float>(BENCH_SECTION_SIZE) * (gz + 1);

                for (int q = 0; q < quads; ++q) {
                    // A block face somewhere inside this 16^3 section, facing
                    // the camera. Real terrain is mostly axis-aligned quads of
                    // one block; so is this.
                    const float px = ox + rng.unit() * BENCH_SECTION_SIZE;
                    const float py = oy + rng.unit() * BENCH_SECTION_SIZE;
                    const float pz = oz + rng.unit() * BENCH_SECTION_SIZE;
                    const float tile_u = static_cast<float>(rng.range(0, static_cast<int>(atlas_tiles) - 1));
                    const float tile_v = static_cast<float>(rng.range(0, static_cast<int>(atlas_tiles) - 1));
                    const float u0 = tile_u / atlas_tiles;
                    const float v0 = tile_v / atlas_tiles;
                    const float du = 1.0f / atlas_tiles;
                    // Baked light, as the game bakes it into the vertex colour.
                    const uint8_t light = static_cast<uint8_t>(rng.range(120, 255));

                    const vertex_t a{px, py, pz, u0, v0, light, light, light, 255};
                    const vertex_t b{px + 1.0f, py, pz, u0 + du, v0, light, light, light, 255};
                    const vertex_t c{px + 1.0f, py + 1.0f, pz, u0 + du, v0 + du, light, light, light, 255};
                    const vertex_t d{px, py + 1.0f, pz, u0, v0 + du, light, light, light, 255};
                    verts.push_back(a);
                    verts.push_back(b);
                    verts.push_back(c);
                    verts.push_back(d);
                }

                s.counts.push_back(static_cast<GLsizei>(quads * 6));
                s.basevertex.push_back(first_vertex);
                // Sodium points every sub-draw at the start of the shared index
                // buffer and separates sections with baseVertex alone.
                s.offsets.push_back(nullptr);
                s.firsts.push_back(first_vertex);
                s.counts_arrays.push_back(static_cast<GLsizei>(quads * 4));
            }
        }
    }

    // The shared sequential quad index buffer: 0 1 2, 2 3 0, 4 5 6, ... long
    // enough for the largest section, reused by every one of them.
    std::vector<GLuint> shared;
    shared.reserve(static_cast<size_t>(max_quads) * 6);
    for (int q = 0; q < max_quads; ++q) {
        const GLuint base = static_cast<GLuint>(q) * 4;
        shared.push_back(base + 0);
        shared.push_back(base + 1);
        shared.push_back(base + 2);
        shared.push_back(base + 2);
        shared.push_back(base + 3);
        shared.push_back(base + 0);
    }

    // glMultiDrawElements has no baseVertex, so it needs the same geometry
    // spelled out with absolute indices.
    std::vector<GLuint> absolute;
    absolute.reserve(static_cast<size_t>(verts.size()) / 4 * 6);
    for (size_t i = 0; i < s.counts.size(); ++i) {
        s.offsets_absolute.push_back(
            reinterpret_cast<const void*>(absolute.size() * sizeof(GLuint)));
        const GLuint base_vertex = static_cast<GLuint>(s.basevertex[i]);
        const int quads = s.counts[i] / 6;
        for (int q = 0; q < quads; ++q) {
            const GLuint base = base_vertex + static_cast<GLuint>(q) * 4;
            absolute.push_back(base + 0);
            absolute.push_back(base + 1);
            absolute.push_back(base + 2);
            absolute.push_back(base + 2);
            absolute.push_back(base + 3);
            absolute.push_back(base + 0);
        }
    }

    glGenVertexArrays(1, &s.vao);
    glBindVertexArray(s.vao);

    glGenBuffers(1, &s.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s.vbo);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(verts.size() * sizeof(vertex_t)),
                      verts.data(), GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, BENCH_VERTEX_BYTES, nullptr);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, BENCH_VERTEX_BYTES,
                               reinterpret_cast<const void*>(12));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, BENCH_VERTEX_BYTES,
                               reinterpret_cast<const void*>(20));

    glGenBuffers(1, &s.ibo_shared);
    glGenBuffers(1, &s.ibo_absolute);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, s.ibo_absolute);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(absolute.size() * sizeof(GLuint)),
                      absolute.data(), GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, s.ibo_shared);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(shared.size() * sizeof(GLuint)),
                      shared.data(), GL_STATIC_DRAW);

    // Command buffers for the two *Indirect entry points, which take commands
    // from the application instead of building them.
    struct elem_cmd_t {
        GLuint count, instanceCount, firstIndex;
        GLint baseVertex;
        GLuint reserved;
    };
    struct array_cmd_t {
        GLuint count, instanceCount, first, reserved;
    };
    std::vector<elem_cmd_t> elem_cmds(s.counts.size());
    std::vector<array_cmd_t> array_cmds(s.counts.size());
    for (size_t i = 0; i < s.counts.size(); ++i) {
        elem_cmds[i] = {static_cast<GLuint>(s.counts[i]), 1, 0, s.basevertex[i], 0};
        array_cmds[i] = {static_cast<GLuint>(s.counts_arrays[i]), 1,
                         static_cast<GLuint>(s.firsts[i]), 0};
    }
    glGenBuffers(1, &s.indirect_elements);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, s.indirect_elements);
    glBufferData(GL_DRAW_INDIRECT_BUFFER,
                      static_cast<GLsizeiptr>(elem_cmds.size() * sizeof(elem_cmd_t)), elem_cmds.data(),
                      GL_STATIC_DRAW);
    glGenBuffers(1, &s.indirect_arrays);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, s.indirect_arrays);
    glBufferData(GL_DRAW_INDIRECT_BUFFER,
                      static_cast<GLsizeiptr>(array_cmds.size() * sizeof(array_cmd_t)), array_cmds.data(),
                      GL_STATIC_DRAW);
    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);

    glViewport(0, 0, s.width, s.height);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    // Dither is the one piece of default-on state that may perturb identical
    // draws into non-identical bytes; the output gate compares frames bit for
    // bit, so it goes. On RGBA8 it is almost always an identity anyway.
    glDisable(GL_DITHER);
    glClearColor(0.47f, 0.65f, 1.0f, 1.0f);  // sky

    while (GLES.glGetError() != GL_NO_ERROR) {
    }
    s.ok = true;
}

// Start of a frame: clear, and move the camera a little. Games do not render
// the same matrix twice, and a still one invites the driver to notice.
void bench_frame_begin(bench_scene_t& s) {
    // State goes through the FRONTEND here, and everywhere else in this file
    // that establishes it. The backends are still called directly -- what this
    // harness bypasses is the dispatcher's backend selection, never the state
    // machine -- because the backends' contract is "the frontend's tracked
    // state describes the driver", and they read that tracked state instead of
    // querying the driver. A scene built through GLES.* is a scene the tracking
    // has never heard of: the indirect paths see "no element buffer bound" and
    // fall back, and the unroll paths skip every sub-draw and win the ranking
    // with a time in which nothing was drawn. That is also just the truthful
    // measurement: the game reaches these entry points through the frontend, so
    // a frame that pays the frontend's bind path is the frame being predicted.
    glBindFramebuffer(GL_FRAMEBUFFER, s.fbo);
    glViewport(0, 0, s.width, s.height);
    GLES.glUseProgram(s.program);
    glBindVertexArray(s.vao);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, s.atlas);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);

    s.spin += 0.013f;
    const float aspect = static_cast<float>(s.width) / static_cast<float>(s.height);
    const float fov = 70.0f * 3.14159265f / 180.0f;
    const float f = 1.0f / std::tan(fov * 0.5f);
    const float near_z = 0.05f;
    // Far enough that the last row of sections is still inside the frustum. A
    // fixed plane would silently clip away the very geometry a larger scene was
    // grown to add, so the load would stop rising while the numbers pretended
    // it had.
    const float far_z = std::max(512.0f, static_cast<float>(BENCH_SECTION_SIZE * (s.grid_z + 2)));
    const float depth_a = (far_z + near_z) / (near_z - far_z);
    const float depth_b = 2.0f * far_z * near_z / (near_z - far_z);
    const float yaw = std::sin(s.spin) * 0.05f;
    const float cy = std::cos(yaw);
    const float sy = std::sin(yaw);

    // perspective * yaw about Y, column-major
    const float mvp[16] = {
        f / aspect * cy, 0.0f, -sy * depth_a, sy,
        0.0f,            f,    0.0f,          0.0f,
        f / aspect * sy, 0.0f, cy * depth_a,  -cy,
        0.0f,            0.0f, depth_b,       0.0f,
    };
    if (s.u_mvp >= 0) GLES.glUniformMatrix4fv(s.u_mvp, 1, GL_FALSE, mvp);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void bench_scene_destroy(bench_scene_t& s) {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (s.fbo) glDeleteFramebuffers(1, &s.fbo);
    if (s.depth_rb) glDeleteRenderbuffers(1, &s.depth_rb);
    if (s.color_tex) glDeleteTextures(1, &s.color_tex);
    if (s.atlas) glDeleteTextures(1, &s.atlas);
    if (s.indirect_arrays) glDeleteBuffers(1, &s.indirect_arrays);
    if (s.indirect_elements) glDeleteBuffers(1, &s.indirect_elements);
    if (s.ibo_shared) glDeleteBuffers(1, &s.ibo_shared);
    if (s.ibo_absolute) glDeleteBuffers(1, &s.ibo_absolute);
    if (s.vbo) glDeleteBuffers(1, &s.vbo);
    if (s.vao) glDeleteVertexArrays(1, &s.vao);
    if (s.program) GLES.glDeleteProgram(s.program);
}

// One frame drawn through `entry` on `backend`. Returns false when the call
// cannot be issued at all (no implementation for the pair).
//
// Indices are GL_UNSIGNED_INT, as Sodium uses -- a section's geometry runs well
// past 65535 vertices, and the index type changes what several of the backends
// have to do.
bool bench_issue(bench_scene_t& s, md_entry_t entry, md_backend_t backend) {
    using B = md_backend_t;
    const GLsizei n = static_cast<GLsizei>(s.counts.size());
    switch (entry) {
    case md_entry_t::Elements:
        // No baseVertex here, so the sections are addressed with absolute
        // indices instead of the shared sequential buffer.
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, s.ibo_absolute);
        switch (backend) {
        case B::Unroll:
            mg_glMultiDrawElements_drawelements(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                s.offsets_absolute.data(), n);
            return true;
        case B::Indirect:
            mg_glMultiDrawElements_indirect(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                            s.offsets_absolute.data(), n);
            return true;
        case B::MultiIndirect:
            mg_glMultiDrawElements_multiindirect(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                 s.offsets_absolute.data(), n);
            return true;
        case B::MultiBaseVertex:
            mg_glMultiDrawElements_multibasevertex(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                   s.offsets_absolute.data(), n);
            return true;
        case B::MultiArrays:
            mg_glMultiDrawElements_multiarrays(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                               s.offsets_absolute.data(), n);
            return true;
        default:
            return false;
        }
    case md_entry_t::ElementsBaseVertex:
        // The path the game actually takes: shared index buffer at offset 0,
        // sections separated by baseVertex.
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, s.ibo_shared);
        switch (backend) {
        case B::Unroll:
            mg_glMultiDrawElementsBaseVertex_drawelements(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                          s.offsets.data(), n, s.basevertex.data());
            return true;
        case B::BaseVertex:
            mg_glMultiDrawElementsBaseVertex_basevertex(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                        s.offsets.data(), n, s.basevertex.data());
            return true;
        case B::Indirect:
            mg_glMultiDrawElementsBaseVertex_indirect(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                      s.offsets.data(), n, s.basevertex.data());
            return true;
        case B::MultiIndirect:
            mg_glMultiDrawElementsBaseVertex_multiindirect(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                           s.offsets.data(), n, s.basevertex.data());
            return true;
        case B::MultiBaseVertex:
            mg_glMultiDrawElementsBaseVertex_multibasevertex(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                             s.offsets.data(), n, s.basevertex.data());
            return true;
        case B::Compute:
            mg_glMultiDrawElementsBaseVertex_compute(GL_TRIANGLES, s.counts.data(), GL_UNSIGNED_INT,
                                                     s.offsets.data(), n, s.basevertex.data());
            return true;
        default:
            return false;
        }
    case md_entry_t::Arrays:
        switch (backend) {
        case B::Unroll:
            mg_glMultiDrawArrays_unroll(GL_TRIANGLES, s.firsts.data(), s.counts_arrays.data(), n);
            return true;
        case B::MultiArrays:
            mg_glMultiDrawArrays_multiarrays(GL_TRIANGLES, s.firsts.data(), s.counts_arrays.data(), n);
            return true;
        case B::MultiIndirect:
            mg_glMultiDrawArrays_multiindirect(GL_TRIANGLES, s.firsts.data(), s.counts_arrays.data(), n);
            return true;
        default:
            return false;
        }
    case md_entry_t::ArraysIndirect:
        // The application supplies the command buffer, so the two variants are
        // reproduced directly: one driver call vs. a walk of the commands.
        glBindBuffer(GL_DRAW_INDIRECT_BUFFER, s.indirect_arrays);
        if (backend == B::MultiIndirect) {
            if (!GLES.glMultiDrawArraysIndirectEXT) return false;
            GLES.glMultiDrawArraysIndirectEXT(GL_TRIANGLES, nullptr, n, 0);
            return true;
        }
        if (backend == B::Indirect) {
            if (!GLES.glDrawArraysIndirect) return false;
            for (GLsizei i = 0; i < n; ++i) {
                GLES.glDrawArraysIndirect(GL_TRIANGLES, reinterpret_cast<const void*>(
                                                            static_cast<uintptr_t>(i) * 4 * sizeof(GLuint)));
            }
            return true;
        }
        return false;
    case md_entry_t::ElementsIndirect:
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, s.ibo_shared);
        glBindBuffer(GL_DRAW_INDIRECT_BUFFER, s.indirect_elements);
        if (backend == B::MultiIndirect) {
            if (!GLES.glMultiDrawElementsIndirectEXT) return false;
            GLES.glMultiDrawElementsIndirectEXT(GL_TRIANGLES, GL_UNSIGNED_INT, nullptr, n, 0);
            return true;
        }
        if (backend == B::Indirect) {
            if (!GLES.glDrawElementsIndirect) return false;
            for (GLsizei i = 0; i < n; ++i) {
                GLES.glDrawElementsIndirect(GL_TRIANGLES, GL_UNSIGNED_INT,
                                            reinterpret_cast<const void*>(static_cast<uintptr_t>(i) * 5 *
                                                                          sizeof(GLuint)));
            }
            return true;
        }
        return false;
    default:
        return false;
    }
}

// One (entry point, backend) pair that survived probing, with its per-round
// samples in microseconds per drawn frame.
struct bench_candidate_t {
    md_entry_t entry = md_entry_t::Arrays;
    md_backend_t backend = md_backend_t::Unroll;
    int frames = 1;             // frames per timed batch
    double probe_us = 0.0;      // rough frame cost from probing, used to size rounds
    uint64_t image_hash = 0;    // checksum of one fixed-camera frame, for the output gate
    std::vector<double> samples;
    int discarded = 0;          // rounds thrown away because a fallback fired
};

// End of a frame: close the render pass and submit it, waiting for nothing.
//
// The scene renders into an FBO, so no eglSwapBuffers ever ends a frame here --
// and a glClear does not close a pass that is already open. Without this, every
// frame of a batch merged into one render pass: a shape no game produces, with
// the per-pass work amortised in a way no game frame would amortise it, and the
// tiler binning a whole batch's geometry into one polygon list. Unbinding the
// framebuffer is the non-deferrable boundary (the next frame's draws go
// somewhere else, so the pass must close); the flush submits it. Neither call
// waits, so the CPU/GPU overlap the batch timing depends on is preserved.
void bench_frame_end(bench_scene_t& s) {
    (void)s;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    GLES.glFlush();
}

// One frame with a pinned camera, hashed. Every backend of an entry point must
// produce the same image -- they are five implementations of one draw call --
// so a fixed spin makes the frames bit-comparable and FNV-1a over the readback
// is enough to tell "drew the same thing" from "won by drawing less". The
// readback is a full pipeline sync, which is why this runs once per candidate
// at probe time and never inside a timed batch.
bool bench_frame_hash(bench_scene_t& s, md_entry_t entry, md_backend_t backend, uint64_t* out) {
    const float saved_spin = s.spin;
    s.spin = 0.0f;
    bench_frame_begin(s);
    const bool issued = bench_issue(s, entry, backend);
    if (!issued) {
        bench_frame_end(s);
        s.spin = saved_spin;
        return false;
    }
    static thread_local std::vector<uint8_t> pixels;
    pixels.resize(static_cast<size_t>(s.width) * s.height * 4);
    // GLES-direct on purpose: this is introspection of our own FBO with default
    // pack state (RGBA rows of a 4-multiple width need no alignment care), not
    // state the frontend must track.
    GLES.glReadPixels(0, 0, s.width, s.height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    bench_frame_end(s);
    s.spin = saved_spin;

    uint64_t h = 1469598103934665603ull;
    for (uint8_t b : pixels) {
        h ^= b;
        h *= 1099511628211ull;
    }
    *out = h;
    return true;
}

// Draws `frames` frames back to back and returns microseconds per frame, or a
// negative value if a fallback fired during the batch (the number would then
// describe some other backend).
//
// Only one glFinish, at the end. Syncing every frame would serialise CPU and
// GPU and report submit time plus draw time added together, which is not what a
// running game costs -- there the two overlap and the longer of them is the
// frame. Letting several frames queue up reproduces that, so a backend that
// spends on the CPU and one that spends on the GPU are compared the way the
// game would actually feel them.
const char* bench_entry_label(md_entry_t e);

// Set once the driver has thrown the context away, and never cleared: nothing
// measured afterwards is worth anything.
bool g_bench_context_lost = false;

// GL_CONTEXT_LOST is not a complaint about the call that returned it.
//
// After it, every query answers zero and every draw is a no-op -- so a batch
// timed past that point is not fast, it is fiction, and the backends that check
// their preconditions see those zeros and "fall back", which this harness would
// otherwise write down as "this device cannot do it". A ranking built from that
// mixture is worse than no ranking: it is wrong and it looks fine. Whoever was
// being measured when it happened is named, because that is the one clue to why.
bool bench_note_context_lost(md_entry_t entry, md_backend_t backend) {
    if (g_bench_context_lost) return true;
    if (!GLES.glGetError) return false;
    for (int i = 0; i < 16; ++i) {
        const GLenum e = GLES.glGetError();
        if (e == GL_NO_ERROR) break;
        if (e == GL_CONTEXT_LOST) {
            g_bench_context_lost = true;
            LOG_W_FORCE("bench: the driver lost the GL context while measuring %s/%s; everything after this "
                        "point would be fiction, so the run stops here",
                        bench_entry_label(entry), md_backend_name(backend))
            return true;
        }
    }
    return false;
}

double bench_timed_batch(bench_scene_t& s, md_entry_t entry, md_backend_t backend, int frames) {
    if (g_bench_context_lost) return -1.0;
    const uint32_t tick_before = g_md_fallback_tick.load(std::memory_order_relaxed);
    GLES.glFinish();
    const double t0 = now_us();
    for (int i = 0; i < frames; ++i) {
        bench_frame_begin(s);
        bench_issue(s, entry, backend);
        bench_frame_end(s);
    }
    GLES.glFinish();
    const double t1 = now_us();
    if (bench_note_context_lost(entry, backend)) return -1.0;
    if (g_md_fallback_tick.load(std::memory_order_relaxed) != tick_before) return -1.0;
    return (t1 - t0) / frames;
}

double bench_median(std::vector<double> v) {
    if (v.empty()) return 0.0;
    const size_t mid = v.size() / 2;
    std::nth_element(v.begin(), v.begin() + mid, v.end());
    const double hi = v[mid];
    if (v.size() % 2 != 0) return hi;
    const double lo = *std::max_element(v.begin(), v.begin() + mid);
    return (lo + hi) / 2.0;
}

// Median absolute deviation, scaled to be comparable to a standard deviation on
// normal data. Unlike a standard deviation it does not let one bad round
// dominate the spread it reports.
double bench_mad(const std::vector<double>& v, double median) {
    if (v.empty()) return 0.0;
    std::vector<double> dev;
    dev.reserve(v.size());
    for (double x : v) dev.push_back(std::fabs(x - median));
    return 1.4826 * bench_median(std::move(dev));
}

// Everything known about one entry point: its candidates as they are being
// measured now, and the calmest pass seen so far.
//
// Settling is per entry point, not for the run as a whole. Each entry point is
// ranked on its own, so one shaky function has no business dragging the ones
// that already came out clean through another pass.
struct bench_entry_state_t {
    md_entry_t entry = md_entry_t::Arrays;
    std::vector<bench_candidate_t> candidates;

    std::vector<bench_candidate_t> best;  // samples from the calmest pass
    double best_rsd = 0.0;
    int best_rounds = 0;
    // The scene the calmest pass ran on. Passes grow the scene, so two entry
    // points can end up settling on different ones -- and a microsecond figure
    // means nothing without the size it was measured at. Rankings are unaffected
    // (each entry point is ranked within one pass), but the numbers shown next
    // to them would be comparing different scenes if this were not reported.
    int best_sections = 0;
    bool have_best = false;

    int attempts = 0;
    bool settled = false;  // spread is under the target; stop re-measuring it
    // Backends that ran but drew a different image than the reference. Reported
    // rather than ranked: a wrong picture at any speed is not a candidate.
    std::vector<const char*> wrong_output;
};

// The spread of the shakiest candidate is the grade for the whole group: an
// order is only as trustworthy as its least stable member.
double bench_worst_rsd(const std::vector<bench_candidate_t>& candidates) {
    double worst = 0.0;
    for (const bench_candidate_t& c : candidates) {
        // Fewer than three samples cannot say anything about spread, and a
        // candidate that kept falling back never really ran.
        if (c.samples.size() < 3) continue;
        if (c.samples.size() * 2 <= static_cast<size_t>(c.discarded)) continue;
        const double median = bench_median(c.samples);
        if (median <= 0.0) continue;
        worst = std::max(worst, bench_mad(c.samples, median) / median);
    }
    return worst;
}

// Where one live candidate lives, so a pass can walk everything still being
// measured round-robin without caring which entry point it belongs to.
struct bench_live_ref_t {
    size_t state;
    size_t candidate;
};

// How many frames of this candidate make one batch of about BENCH_TARGET_BATCH_US.
int bench_frames_for(double probe_us) {
    const double want = probe_us > 0.0 ? BENCH_TARGET_BATCH_US / probe_us : BENCH_MAX_FRAMES;
    return static_cast<int>(std::min(std::max(want, static_cast<double>(BENCH_MIN_FRAMES)),
                                     static_cast<double>(BENCH_MAX_FRAMES)));
}

// Throw the scene away and build a bigger one, then re-time every candidate on
// it. Both halves are required: a frame of the new scene costs about twice a
// frame of the old, so the batch lengths calibrated against the old one would
// overshoot the time budget by the same factor and the pass would run half the
// rounds it was asked for.
//
// The candidate list itself is left alone. Re-running the full probe would also
// re-decide which backends are measurable, and a backend dropping in or out
// halfway through a run is a worse problem than a stale frame count: the passes
// would no longer be measuring the same set of things.
//
// Returns false with the old scene rebuilt and intact if the larger one could
// not be created, so a device that runs out of memory here simply stops
// climbing instead of losing the run.
bool bench_scene_regrow(bench_scene_t& scene, int sections,
                        std::vector<bench_entry_state_t>& states) {
    const int previous = scene.sections;
    if (sections == previous) return false;

    bench_scene_destroy(scene);
    scene = bench_scene_t{};
    bench_scene_build(scene, sections);
    if (!scene.ok) {
        bench_scene_destroy(scene);
        scene = bench_scene_t{};
        bench_scene_build(scene, previous);
        return false;
    }

    for (bench_entry_state_t& s : states) {
        for (bench_candidate_t& c : s.candidates) {
            const double probe_us = bench_timed_batch(scene, c.entry, c.backend, 4);
            // A negative probe means a fallback fired or the context is gone.
            // Neither is a reason to guess: keep the old pacing and let the pass
            // discard the candidate the same way it always would.
            if (probe_us > 0.0) {
                c.probe_us = probe_us;
                c.frames = bench_frames_for(probe_us);
            }
        }
    }
    return true;
}

// One round-robin pass over every candidate still unsettled. Interleaving
// across entry points as well as backends is the point: whatever the clock does
// during the pass, it does to all of them.
int bench_measure(bench_scene_t& scene, std::vector<bench_entry_state_t>& states,
                  const std::vector<bench_live_ref_t>& live, double budget_us, int attempt) {
    double per_round_us = 0.0;
    for (const bench_live_ref_t& ref : live) {
        const bench_candidate_t& c = states[ref.state].candidates[ref.candidate];
        per_round_us += c.probe_us * c.frames;
    }
    // Two glFinish round trips per batch, generously accounted for.
    per_round_us += static_cast<double>(live.size()) * 400.0;

    int rounds = per_round_us > 0.0 ? static_cast<int>(budget_us / per_round_us) : BENCH_MIN_ROUNDS;
    rounds = std::min(std::max(rounds, BENCH_MIN_ROUNDS), BENCH_MAX_ROUNDS);
    if (rounds % 2 == 0) ++rounds;

    for (const bench_live_ref_t& ref : live) {
        bench_candidate_t& c = states[ref.state].candidates[ref.candidate];
        c.samples.clear();
        c.discarded = 0;
    }

    const double start_us = now_us();
    const int total_batches = rounds * static_cast<int>(live.size());
    int completed = 0;
    for (int r = 0; r < rounds; ++r) {
        const bool forward = (r % 2) == 0;
        for (size_t i = 0; i < live.size(); ++i) {
            const bench_live_ref_t& ref = live[forward ? i : live.size() - 1 - i];
            bench_candidate_t& c = states[ref.state].candidates[ref.candidate];
            const double us = bench_timed_batch(scene, c.entry, c.backend, c.frames);
            if (us < 0.0) {
                ++c.discarded;
            } else {
                c.samples.push_back(us);
            }
            ++completed;
            g_bench_progress.store(attempt * 1000 + completed * 1000 / total_batches,
                                   std::memory_order_relaxed);
            if (g_bench_context_lost) return r + 1;
        }
        // Overrunning the budget is worse than one round short: the user is
        // staring at a spinner, and the median is already stable by now.
        if (r + 1 >= BENCH_MIN_ROUNDS && now_us() - start_us > budget_us) {
            rounds = r + 1;
            break;
        }
    }
    return rounds;
}

double bench_budget_us() {
    double budget = BENCH_DEFAULT_BUDGET_US;
    if (const char* raw = getenv("MG_BENCH_BUDGET_MS")) {
        char* end = nullptr;
        const double ms = strtod(raw, &end);
        if (end != raw && ms > 0.0) budget = ms * 1000.0;
    }
    return std::min(std::max(budget, BENCH_MIN_BUDGET_US), BENCH_MAX_BUDGET_US);
}

const char* bench_entry_label(md_entry_t e) {
    switch (e) {
    case md_entry_t::Arrays:
        return "glMultiDrawArrays";
    case md_entry_t::Elements:
        return "glMultiDrawElements";
    case md_entry_t::ElementsBaseVertex:
        return "glMultiDrawElementsBaseVertex";
    case md_entry_t::ArraysIndirect:
        return "glMultiDrawArraysIndirect";
    case md_entry_t::ElementsIndirect:
        return "glMultiDrawElementsIndirect";
    default:
        return "?";
    }
}

} // namespace

// attempt * 1000 + permille within that attempt, attempt 0-based. Stays at its
// last value once the run returns; the caller decides what to do with that.
extern "C" __attribute__((visibility("default"))) int mg_multidraw_bench_progress() {
    return g_bench_progress.load(std::memory_order_relaxed);
}

// start_sections: the scene to open with, or 0 for the default.
// max_sections:   a ceiling the run must not climb past, or 0 for none. The
//                 caller sets this after a previous run lost the context, since
//                 the size that did it cannot be discovered twice in one
//                 process -- the context it would need is the one that died.
extern "C" __attribute__((visibility("default"))) const char* mg_multidraw_bench_run(
        int start_sections, int max_sections) {
    static std::string result;

    g_bench_progress.store(0, std::memory_order_relaxed);

    const double budget_us = bench_budget_us();
    const double started_us = now_us();

    const int ceiling = max_sections > 0
                        ? std::min(max_sections, BENCH_MAX_SECTIONS)
                        : BENCH_MAX_SECTIONS;
    const int opening = std::min(start_sections > 0 ? start_sections : BENCH_START_SECTIONS,
                                 ceiling);

    cJSON* root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "version", 3);
    cJSON_AddNumberToObject(root, "budgetMs", budget_us / 1000.0);
    cJSON_AddNumberToObject(root, "startSections", opening);
    cJSON_AddNumberToObject(root, "maxSections", max_sections > 0 ? ceiling : 0);

    // Which driver these numbers describe. The renderer falls back to the system
    // driver when ANGLE was asked for but could not be opened, and an order
    // measured on the wrong one of those is worse than no order at all.
    cJSON_AddBoolToObject(root, "angleRequested", global_settings.angle == AngleMode::Enabled);
    cJSON_AddBoolToObject(root, "angleInUse", g_angle_in_use);
    // The resolved mode is not the whole story: under EnableIfPossible on a
    // device the probe rejects, angleRequested is false and the borrowed ANGLE
    // was ignored -- which is invisible unless the raw choice and the device
    // verdict ride along.
    cJSON_AddNumberToObject(root, "angleConfigured", static_cast<int>(global_settings.angle_config));
    cJSON_AddBoolToObject(root, "angleSupported", global_settings.angle_supported);
    if (const GLubyte* renderer = GLES.glGetString ? GLES.glGetString(GL_RENDERER) : nullptr) {
        cJSON_AddStringToObject(root, "renderer", reinterpret_cast<const char*>(renderer));
    }

    g_bench_context_lost = false;
    bench_scene_t scene;
    bench_scene_build(scene, opening);
    cJSON_AddNumberToObject(root, "width", scene.width);
    cJSON_AddNumberToObject(root, "height", scene.height);
    if (!scene.ok) {
        cJSON_AddNumberToObject(root, "sections", scene.sections);
        cJSON_AddStringToObject(root, "error", scene.error.c_str());
        char* text = cJSON_PrintUnformatted(root);
        result = text ? text : "{\"error\":\"print failed\"}";
        cJSON_free(text);
        cJSON_Delete(root);
        bench_scene_destroy(scene);
        g_bench_progress.store(BENCH_PROGRESS_DONE, std::memory_order_relaxed);
        return result.c_str();
    }

    // ---- Probe: who can actually run, and how long one call takes ----
    //
    // The cost estimate here is deliberately crude. It only has to be right to
    // within a factor of a few, because all it decides is how many calls go
    // into one timed batch.

    std::vector<bench_entry_state_t> states;
    for (int ei = 0; ei < MD_ENTRY_COUNT; ++ei) {
        const md_entry_t entry = static_cast<md_entry_t>(ei);
        bench_entry_state_t state;
        state.entry = entry;

        const int order_len = global_settings.multidraw_order_len[ei];
        for (int k = 0; k < order_len; ++k) {
            const md_backend_t backend = global_settings.multidraw_order[ei][k];

            const uint32_t tick_before_warmup = g_md_fallback_tick.load(std::memory_order_relaxed);
            bool issued = true;
            for (int w = 0; w < BENCH_WARMUP && issued; ++w) {
                // Whole frames, same as the measured batches: warming up on a
                // half-set-up frame warms up the wrong thing.
                bench_frame_begin(scene);
                issued = bench_issue(scene, entry, backend);
                bench_frame_end(scene);
            }
            GLES.glFinish();
            if (!issued) continue;
            if (g_md_fallback_tick.load(std::memory_order_relaxed) != tick_before_warmup) {
                // The warmup was served by some other backend: the driver cannot
                // actually run this one. No number is better than a wrong one.
                continue;
            }

            const double probe_us = bench_timed_batch(scene, entry, backend, 4);
            if (probe_us < 0.0) continue;

            // The output gate's evidence, taken while the candidate is warm. A
            // fallback during this frame means the image belongs to some other
            // backend, so it disqualifies the same way the warmup check does.
            const uint32_t tick_before_hash = g_md_fallback_tick.load(std::memory_order_relaxed);
            uint64_t image_hash = 0;
            if (!bench_frame_hash(scene, entry, backend, &image_hash)) continue;
            if (bench_note_context_lost(entry, backend)) break;
            if (g_md_fallback_tick.load(std::memory_order_relaxed) != tick_before_hash) continue;

            bench_candidate_t c;
            c.entry = entry;
            c.backend = backend;
            c.probe_us = probe_us;
            c.image_hash = image_hash;
            c.frames = bench_frames_for(probe_us);
            state.candidates.push_back(std::move(c));
        }

        // The output gate. Five backends of one entry point are five
        // implementations of the same draw call: with the camera pinned they
        // must produce the same image, bit for bit -- same triangles, same
        // order, same pipeline, dither disabled. A mismatch means the fast
        // number was bought by drawing something else, which is exactly how a
        // backend that silently skips work would otherwise win the ranking.
        // The reference is unroll when it survived probing -- one native draw
        // per sub-draw, the simplest possible semantics -- and the first
        // survivor otherwise.
        if (state.candidates.size() > 1) {
            uint64_t ref_hash = state.candidates.front().image_hash;
            for (const bench_candidate_t& c : state.candidates) {
                if (c.backend == md_backend_t::Unroll) {
                    ref_hash = c.image_hash;
                    break;
                }
            }
            for (size_t i = state.candidates.size(); i-- > 0;) {
                const bench_candidate_t& c = state.candidates[i];
                if (c.image_hash == ref_hash) continue;
                LOG_W_FORCE("bench: %s/%s drew a different image than the reference "
                            "(%016llx vs %016llx); a wrong picture at any speed is not a "
                            "candidate, so it is excluded from the ranking",
                            bench_entry_label(entry), md_backend_name(c.backend),
                            static_cast<unsigned long long>(c.image_hash),
                            static_cast<unsigned long long>(ref_hash))
                state.wrong_output.push_back(md_backend_name(c.backend));
                state.candidates.erase(state.candidates.begin() + static_cast<long>(i));
            }
        }

        if (!state.candidates.empty()) states.push_back(std::move(state));
    }

    if (states.empty()) {
        cJSON_AddNumberToObject(root, "sections", scene.sections);
        cJSON_AddStringToObject(root, "error", "no measurable backend on this device");
        char* text = cJSON_PrintUnformatted(root);
        result = text ? text : "{\"error\":\"print failed\"}";
        cJSON_free(text);
        cJSON_Delete(root);
        bench_scene_destroy(scene);
        g_bench_progress.store(BENCH_PROGRESS_DONE, std::memory_order_relaxed);
        return result.c_str();
    }

    // ---- Measure, and re-measure whichever functions are still too shaky ----
    //
    // Settling is judged per entry point, because each one is ranked on its own.
    // A function whose spread is already under the target drops out of the next
    // pass; only the shaky ones are measured again. Four passes at most -- if
    // even the fourth misses, that function's calmest pass is reported with
    // noisy=true and the app asks the user about that function specifically.
    //
    // A shaky pass is answered in one of two ways, and which one is not a matter
    // of taste:
    //
    //   * below the ceiling, the scene doubles. Jitter is largely a fixed cost
    //     per frame -- a scheduler slice, a governor step -- so doubling the
    //     real work per frame halves its share of the reading. This is the
    //     preferred answer, and it is the one that can end the run: bigger
    //     scene, more tiler memory, and past some size the driver throws the
    //     context away. That is the ladder working as intended; the caller comes
    //     back with a ceiling and this run never reaches for it again.
    //
    //   * at the ceiling, the budget grows instead, which buys rounds -- more
    //     independent samples under the median, at exactly the load the device
    //     has already proven it survives.
    //
    // What deliberately does NOT grow is the frames-per-batch. It was the old
    // answer to a shaky pass, and it is the one knob that raises peak load
    // without being subject to the ceiling: a longer batch is more geometry
    // queued before the next glFinish, which is the same resource the ceiling
    // exists to protect. Leaving it pinned to whatever the probe calibrated is
    // what keeps the ladder a ratchet -- load only ever moves down after a lost
    // context, never quietly back up because a reading looked unsteady.

    double budget_scale = 1.0;
    for (int attempt = 0; attempt < BENCH_MAX_ATTEMPTS; ++attempt) {
        std::vector<bench_live_ref_t> live;
        for (size_t si = 0; si < states.size(); ++si) {
            if (states[si].settled) continue;
            for (size_t ci = 0; ci < states[si].candidates.size(); ++ci) {
                live.push_back({si, ci});
            }
        }
        if (live.empty()) break;

        const int rounds = bench_measure(scene, states, live, budget_us * budget_scale, attempt);

        for (bench_entry_state_t& s : states) {
            if (s.settled) continue;
            ++s.attempts;
            const double rsd = bench_worst_rsd(s.candidates);
            if (!s.have_best || rsd < s.best_rsd) {
                s.best = s.candidates;
                s.best_rsd = rsd;
                s.best_rounds = rounds;
                s.best_sections = scene.sections;
                s.have_best = true;
            }
            if (rsd <= BENCH_NOISE_TARGET) s.settled = true;
        }

        if (g_bench_context_lost) break;
        if (attempt + 1 >= BENCH_MAX_ATTEMPTS) break;
        // A device this busy will not settle down within any budget we are
        // willing to make the user sit through.
        if (now_us() - started_us > BENCH_TOTAL_BUDGET_US) break;

        double worst_scale = 1.0;
        double worst_rsd = 0.0;
        for (const bench_entry_state_t& s : states) {
            if (s.settled) continue;
            double scale = s.best_rsd / BENCH_NOISE_TARGET;
            scale = std::min(std::max(scale * scale, BENCH_MIN_RETRY_SCALE), BENCH_MAX_RETRY_SCALE);
            worst_scale = std::max(worst_scale, scale);
            worst_rsd = std::max(worst_rsd, s.best_rsd);
        }

        if (scene.sections * 2 <= ceiling &&
            bench_scene_regrow(scene, scene.sections * 2, states)) {
            LOG_I("bench: readings still spread %.0f%% (target %.0f%%), growing the scene to %d sections",
                  worst_rsd * 100.0, BENCH_NOISE_TARGET * 100.0, scene.sections)
            // The regrow re-timed every candidate against the new scene, so the
            // budget still buys the rounds it was going to buy. Growing it too
            // would be paying twice for one shaky pass.
            if (g_bench_context_lost) break;
            continue;
        }

        // At the ceiling (or unable to grow): buy samples instead of load.
        budget_scale = std::min(budget_scale * worst_scale, BENCH_MAX_BUDGET_SCALE);
    }

    // ---- Report ----

    cJSON* entries = cJSON_AddObjectToObject(root, "entries");
    cJSON* stats = cJSON_AddObjectToObject(root, "stats");
    cJSON* quality = cJSON_AddObjectToObject(root, "quality");
    int max_attempts_used = 0;
    double worst_noise = 0.0;
    bool any_noisy = false;

    for (const bench_entry_state_t& s : states) {
        if (!s.have_best) continue;
        const char* label = bench_entry_label(s.entry);
        cJSON* entry_obj = cJSON_AddObjectToObject(entries, label);
        cJSON* stats_obj = cJSON_AddObjectToObject(stats, label);

        for (const bench_candidate_t& c : s.best) {
            // A backend that kept falling back mid-run never really ran; the
            // few rounds that did survive describe a driver we cannot rely on.
            if (c.samples.empty()) continue;
            if (c.samples.size() * 2 <= static_cast<size_t>(c.discarded)) continue;

            const double median = bench_median(c.samples);
            const double mad = bench_mad(c.samples, median);
            const double fastest = *std::min_element(c.samples.begin(), c.samples.end());

            cJSON_AddNumberToObject(entry_obj, md_backend_name(c.backend), median);

            cJSON* st = cJSON_AddObjectToObject(stats_obj, md_backend_name(c.backend));
            cJSON_AddNumberToObject(st, "median", median);
            cJSON_AddNumberToObject(st, "mad", mad);
            cJSON_AddNumberToObject(st, "rsd", median > 0.0 ? mad / median : 0.0);
            cJSON_AddNumberToObject(st, "best", fastest);
            cJSON_AddNumberToObject(st, "samples", static_cast<double>(c.samples.size()));
            cJSON_AddNumberToObject(st, "discarded", c.discarded);
            cJSON_AddNumberToObject(st, "framesPerBatch", c.frames);
        }

        // How this one function came out: what the app shows under its ranking.
        const bool noisy = s.best_rsd > BENCH_NOISE_TARGET;
        cJSON* q = cJSON_AddObjectToObject(quality, label);
        cJSON_AddNumberToObject(q, "noise", s.best_rsd);
        cJSON_AddNumberToObject(q, "rounds", s.best_rounds);
        cJSON_AddNumberToObject(q, "attempts", s.attempts);
        // The scene these microseconds were measured on. Two functions can carry
        // different values when one settled before the other grew the scene.
        cJSON_AddNumberToObject(q, "sections", s.best_sections);
        cJSON_AddBoolToObject(q, "noisy", noisy);
        if (!s.wrong_output.empty()) {
            cJSON* wrong = cJSON_AddArrayToObject(q, "wrongOutput");
            for (const char* name : s.wrong_output) {
                cJSON_AddItemToArray(wrong, cJSON_CreateString(name));
            }
        }

        max_attempts_used = std::max(max_attempts_used, s.attempts);
        worst_noise = std::max(worst_noise, s.best_rsd);
        any_noisy = any_noisy || noisy;
    }

    // The scene the run ended on. On a lost context this is the size that did
    // it, which is the one thing the caller needs to come back with a ceiling.
    cJSON_AddNumberToObject(root, "sections", scene.sections);
    cJSON_AddNumberToObject(root, "attempts", max_attempts_used);
    cJSON_AddNumberToObject(root, "worstNoise", worst_noise);
    cJSON_AddNumberToObject(root, "noiseTarget", BENCH_NOISE_TARGET);
    cJSON_AddBoolToObject(root, "noisy", any_noisy);
    cJSON_AddNumberToObject(root, "elapsedMs", (now_us() - started_us) / 1000.0);

    glBindBuffer(GL_DRAW_INDIRECT_BUFFER, 0);
    bench_scene_destroy(scene);

    // A lost context makes the whole run a failure, not a partial result. What
    // was measured before it happened cannot be told apart from what was
    // "measured" after, and half the candidates look unsupported because their
    // preconditions read back as zero. Reporting the ranking anyway would hand
    // the user a confident answer assembled out of fiction.
    //
    // The caller is expected to try again in a fresh process below this size --
    // not here. The context is gone, and so is the ANGLE device under it; a new
    // one is only reliable in a process that never saw the old one.
    if (g_bench_context_lost) {
        cJSON_AddStringToObject(root, "error", "context-lost");
    }

    char* text = cJSON_PrintUnformatted(root);
    result = text ? text : "{\"error\":\"print failed\"}";
    cJSON_free(text);
    cJSON_Delete(root);
    g_bench_progress.store(BENCH_PROGRESS_DONE, std::memory_order_relaxed);
    return result.c_str();
}
