// MobileGlues - gl/FSR1/FSR1.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#include "FSR1.h"
#include <mutex>
#include <ska/flat_hash_map.hpp>
#include "FSRShaderSource.h"
#include "../../config/settings.h"

#define DEBUG 0

// Which pieces of GL state a body in this file overwrites. Saving the rest is not
// free: everything the guard cannot answer from this layer's own tracking is a
// driver round trip, and the upscale runs once per presented frame.
enum GLStateBits : unsigned int {
    GUARD_PROGRAM = 1u << 0,
    GUARD_VAO = 1u << 1,
    GUARD_ARRAY_BUFFER = 1u << 2,
    // Unit 0's GL_TEXTURE_2D binding and the active unit together, because the
    // guard makes unit 0 current for its whole lifetime.
    GUARD_TEXTURE = 1u << 3,
    GUARD_FRAMEBUFFER = 1u << 4,
    GUARD_RENDERBUFFER = 1u << 5,
};

// Saves the GL state the bodies in this file overwrite and puts it back.
//
// Answered from this layer's own tracking, at no driver cost:
//   - the current program. gl/program.cpp already treats gl_state->current_program
//     as the truth -- it drops a glUseProgram that repeats it -- and program names
//     are not renamed on the way to GLES, so the tracked value is the driver's.
//   - the draw framebuffer. gl/framebuffer.cpp writes gl_state->current_draw_fbo
//     with the name it hands the driver, the redirect of framebuffer 0 to the FSR1
//     render target already resolved, and it is the only file that binds a draw
//     framebuffer through GLES other than this one. It also keeps that field off
//     deleted names, through its own glDeleteFramebuffers -- with one exception,
//     RecreateFSRFBO, which deletes the render FBO behind its back and so has to
//     republish the replacement itself. A saved name has to be live: restoring one
//     GL has deleted is rejected, and the binding then stays wherever the body left
//     it.
//
// Asked of the driver, because nothing in the tree can answer:
//   - the vertex array. What this layer tracks is the application's name, the
//     mapping to the driver's lives in gl/buffer.cpp and is not exported, and the
//     tracked name outlives glDeleteVertexArrays -- restoring from it could hand
//     GLES a name it never generated.
//   - the active unit and unit 0's GL_TEXTURE_2D binding. gl/texture.h's driver
//     shadow declines to answer while FSR1 is enabled, which is exactly when this
//     runs. The active unit has to come from the driver in any case: these guards
//     nest, the moves below go straight to GLES and so never reach that shadow, and
//     an inner guard reading it would restore the outer guard's unit and leave the
//     body running on a unit it never asked for.
//   - the read framebuffer and the renderbuffer binding, which nothing tracks.
//
// The texture entry is unit 0, not whichever unit happened to be active. Unit 0 is
// the unit ApplyFSR samples the render texture from, so it is the binding that has
// to be preserved; saving the active unit's instead left the FSR1 render texture on
// unit 0 once per presented frame with nothing anywhere to put the application's
// texture back. gl/texture.cpp's driver-side shadow was narrowed around that leak
// and can be widened again now that it is gone.
struct GLStateGuard {
    unsigned int saved;
    GLint prevProgram = 0;
    GLint prevVAO = 0;
    GLint prevArrayBuffer = 0;
    GLint prevActiveTexture = GL_TEXTURE0;
    GLint prevTexture = 0;
    GLint prevReadFBO = 0;
    GLint prevDrawFBO = 0;
    GLint prevRenderbuffer = 0;

    explicit GLStateGuard(unsigned int bits) : saved(bits) {
        if (saved & GUARD_PROGRAM) prevProgram = static_cast<GLint>(gl_state->current_program);
        if (saved & GUARD_VAO) GLES.glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVAO);
        if (saved & GUARD_ARRAY_BUFFER) GLES.glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &prevArrayBuffer);
        if (saved & GUARD_TEXTURE) {
            GLES.glGetIntegerv(GL_ACTIVE_TEXTURE, &prevActiveTexture);
            GLES.glActiveTexture(GL_TEXTURE0);
            GLES.glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTexture);
        }
        if (saved & GUARD_FRAMEBUFFER) {
            GLES.glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevReadFBO);
            prevDrawFBO = static_cast<GLint>(gl_state->current_draw_fbo);
        }
        if (saved & GUARD_RENDERBUFFER) GLES.glGetIntegerv(GL_RENDERBUFFER_BINDING, &prevRenderbuffer);
    }

    // Follow a framebuffer this guard saved through a delete-and-recreate.
    //
    // A saved name that the body then deletes cannot be restored: GL rejects it and
    // leaves the binding wherever the body happened to put it. RecreateFSRFBO is the
    // only body here that deletes framebuffers, and the render FBO is the name
    // gl/framebuffer.cpp redirects a bind of framebuffer 0 to -- which is the case
    // this whole path exists for -- so the guard is told where the replacement went
    // instead of being left to restore a dead name.
    void framebuffer_recreated(GLuint from, GLuint to) {
        if (!(saved & GUARD_FRAMEBUFFER) || from == 0 || from == to) return;
        if (prevReadFBO == static_cast<GLint>(from)) prevReadFBO = static_cast<GLint>(to);
        if (prevDrawFBO == static_cast<GLint>(from)) prevDrawFBO = static_cast<GLint>(to);
    }

    ~GLStateGuard() {
        if (saved & GUARD_PROGRAM) GLES.glUseProgram(prevProgram);
        if (saved & GUARD_VAO) GLES.glBindVertexArray(prevVAO);
        if (saved & GUARD_ARRAY_BUFFER) GLES.glBindBuffer(GL_ARRAY_BUFFER, prevArrayBuffer);
        if (saved & GUARD_TEXTURE) {
            // Unit 0 is current for the guard's lifetime, but say so anyway: a body
            // is free to move the active unit as long as this line puts it back.
            GLES.glActiveTexture(GL_TEXTURE0);
            GLES.glBindTexture(GL_TEXTURE_2D, prevTexture);
            GLES.glActiveTexture(prevActiveTexture);
        }
        if (saved & GUARD_RENDERBUFFER) GLES.glBindRenderbuffer(GL_RENDERBUFFER, prevRenderbuffer);
        if (saved & GUARD_FRAMEBUFFER) {
            GLES.glBindFramebuffer(GL_READ_FRAMEBUFFER, prevReadFBO);
            GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, prevDrawFBO);
        }
    }
};

namespace FSR1_Context {
    GLuint g_renderFBO = 0;
    GLuint g_renderTexture = 0;
    GLuint g_depthStencilRBO = 0;
    GLuint g_quadVAO = 0;
    GLuint g_quadVBO = 0;
    GLuint g_fsrProgram = 0;

    // Resolved once, when g_fsrProgram is linked. A uniform location is fixed for
    // the life of a program object and this one is never relinked, so asking for it
    // again is a driver-side name lookup per presented frame for an answer that
    // cannot have changed. -1 is what glGetUniformLocation returns for a name the
    // linker dropped, and glUniform* ignores it, so an unresolved location needs no
    // separate "not found" state.
    GLint g_inputTexLoc = -1;
    // Task 80 (Amethyst fork): uConst0 (vec4, declared but never read by the
    // upstream shader) is replaced by uTargetSize (vec2) -- the EASU constant
    // setup needs the upscale output size, which used to be fed the INPUT
    // texture size instead, collapsing the coordinate mapping to identity.
    GLint g_targetSizeLoc = -1;
    GLint g_viewportSizeLoc = -1;

    GLuint g_targetFBO = 0;
    GLuint g_targetTexture = 0;

    GLuint g_currentDrawFBO = 0;
    GLint g_viewport[4] = {0};
    GLsizei g_targetWidth = 2400;
    GLsizei g_targetHeight = 1080;
    GLsizei g_renderWidth = 1200;
    GLsizei g_renderHeight = 540;
    // Task 80 (Amethyst fork): the surface size as last seen by
    // CheckResolutionChange. ApplyFSR blits to the full surface so the presented
    // frame is full-bleed no matter how the preset scale rounds (render 1814 x
    // 1.30 = 2358 vs surface 2360 would otherwise leave a stale right-hand
    // column), and so smaller targets (resolution slider stacked on FSR) get
    // their final stretch from the blit's linear filter. Zero until the first
    // CheckResolutionChange -- ApplyFSR then falls back to a 1:1 blit.
    GLsizei g_surfaceWidth = 0;
    GLsizei g_surfaceHeight = 0;
    bool g_dirty = false;

    bool g_resolutionChanged = false;
    GLsizei g_pendingWidth = 0;
    GLsizei g_pendingHeight = 0;
} // namespace FSR1_Context

void CalculateTargetResolution(FSR1_Quality_Preset preset, int renderWidth, int renderHeight, int* targetWidth,
                               int* targetHeight) {
    float scale;
    switch (preset) {
    case FSR1_Quality_Preset::UltraQuality:
        scale = 1.3f;
        break;
    case FSR1_Quality_Preset::Quality:
        scale = 1.5f;
        break;
    case FSR1_Quality_Preset::Balanced:
        scale = 1.7f;
        break;
    case FSR1_Quality_Preset::Performance:
        scale = 2.0f;
        break;
    default:
        scale = 1.5f;
        break;
    }

    *targetWidth = static_cast<int>(renderWidth * scale);
    *targetHeight = static_cast<int>(renderHeight * scale);

    *targetWidth = (*targetWidth + 1) & ~1;
    *targetHeight = (*targetHeight + 1) & ~1;
    LOG_D("Render resolution: %dx%d", renderWidth, renderHeight);
    LOG_D("Target resolution: %dx%d", *targetWidth, *targetHeight);
}

void CalculateRenderResolution(FSR1_Quality_Preset preset, int targetWidth, int targetHeight, int* renderWidth,
                               int* renderHeight) {
    float scale;
    switch (preset) {
    case FSR1_Quality_Preset::UltraQuality:
        scale = 1.3f;
        break;
    case FSR1_Quality_Preset::Quality:
        scale = 1.5f;
        break;
    case FSR1_Quality_Preset::Balanced:
        scale = 1.7f;
        break;
    case FSR1_Quality_Preset::Performance:
        scale = 2.0f;
        break;
    default:
        scale = 1.5f;
    }

    *renderWidth = (int)(targetWidth / scale);
    *renderHeight = (int)(targetHeight / scale);

    *renderWidth = (*renderWidth + 1) & ~1;
    *renderHeight = (*renderHeight + 1) & ~1;
}

GLuint CompileFSRShader() {
    GLuint program = glCreateProgram();

    GLuint vs = glCreateShader(GL_VERTEX_SHADER);
    LOG_D("Vertex shader source:\n%s", FSR_VSSource);
    glShaderSource(vs, 1, &FSR_VSSource, nullptr);
    glCompileShader(vs);

    GLint status;
    glGetShaderiv(vs, GL_COMPILE_STATUS, &status);
    if (!status) {
        char log[512];
        glGetShaderInfoLog(vs, 512, nullptr, log);
        LOG_F("Vertex shader error: %s\n", log);
        return 0;
    }

    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    LOG_D("Fragment shader source:\n%s", FSR_FSSource);
    glShaderSource(fs, 1, &FSR_FSSource, nullptr);
    glCompileShader(fs);

    glGetShaderiv(fs, GL_COMPILE_STATUS, &status);
    if (!status) {
        char log[512];
        glGetShaderInfoLog(fs, 512, nullptr, log);
        LOG_F("Fragment shader error: %s\n", log);
        return 0;
    }

    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);

    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (!status) {
        char log[512];
        glGetProgramInfoLog(program, 512, nullptr, log);
        LOG_F("Program link error: %s\n", log);
        return 0;
    }

    glDeleteShader(vs);
    glDeleteShader(fs);

    return program;
}

void InitFullscreenQuad() {
    GLStateGuard state(GUARD_VAO | GUARD_ARRAY_BUFFER);
    const float quadVertices[] = {-1.0f, 1.0f, 0.0f, 1.0f, -1.0f, -1.0f, 0.0f, 0.0f, 1.0f, -1.0f, 1.0f, 0.0f,

                                  -1.0f, 1.0f, 0.0f, 1.0f, 1.0f,  -1.0f, 1.0f, 0.0f, 1.0f, 1.0f,  1.0f, 1.0f};

    GLES.glGenVertexArrays(1, &FSR1_Context::g_quadVAO);
    GLES.glGenBuffers(1, &FSR1_Context::g_quadVBO);

    GLES.glBindVertexArray(FSR1_Context::g_quadVAO);
    GLES.glBindBuffer(GL_ARRAY_BUFFER, FSR1_Context::g_quadVBO);

    GLES.glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), quadVertices, GL_STATIC_DRAW);

    GLES.glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0);
    GLES.glEnableVertexAttribArray(0);

    GLES.glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float)));
    GLES.glEnableVertexAttribArray(1);

    GLES.glBindBuffer(GL_ARRAY_BUFFER, 0);
    GLES.glBindVertexArray(0);
}

bool fsrInitialized = false;
void InitFSRResources() {
    fsrInitialized = true;
    // Task 78 (Amethyst fork): adopt the viewport latch when the application
    // has already drawn. Before this, the first swap ran on the 960x540
    // default geometry and the recalc only landed afterwards -- one garbage
    // frame under the launcher's FSR linkage (MC's window told at
    // surface/fsr_scale, so its very first viewport IS the render size).
    // Adopting pending + computing the target here makes the very first
    // ApplyFSR run on the correct geometry. pending == 0 means no viewport
    // was latched yet: keep the defaults and let the first swap settle it.
    if (FSR1_Context::g_pendingWidth > 0 && FSR1_Context::g_pendingHeight > 0) {
        FSR1_Context::g_renderWidth = FSR1_Context::g_pendingWidth;
        FSR1_Context::g_renderHeight = FSR1_Context::g_pendingHeight;
        CalculateTargetResolution(global_settings.fsr1_setting, FSR1_Context::g_pendingWidth,
                                  FSR1_Context::g_pendingHeight,
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetWidth),
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetHeight));
    }
    // No GUARD_VAO or GUARD_ARRAY_BUFFER: the only thing here that binds either is
    // InitFullscreenQuad, which carries its own guard.
    GLStateGuard state(GUARD_PROGRAM | GUARD_TEXTURE | GUARD_FRAMEBUFFER | GUARD_RENDERBUFFER);

    FSR1_Context::g_fsrProgram = CompileFSRShader();
    // Task 80 (Amethyst fork): compile-failure safety net. Upstream pressed on
    // with a dead program: the FBOs below came up, the framebuffer-0 redirect in
    // gl/framebuffer.cpp activated, and ApplyFSR then cleared the target to
    // black, drew nothing (program 0), and blitted that black over the whole
    // surface every frame -- fps and swap counters perfectly healthy, screen
    // perfectly black (0441401: "Shader 3 conversion FAILED ... textureGather
    // requires ESSL 310" -> raw fallback -> "invalid version directive").
    // Returning here leaves g_renderFBO at 0: no redirect (MC keeps drawing
    // straight into the surface), ApplyFSR's own guard no-ops, and the session
    // degrades to "no upscale" instead of "no picture". fsrInitialized stays
    // true so glCreateShader does not re-run this on every shader.
    if (FSR1_Context::g_fsrProgram == 0) {
        LOG_W_FORCE("[MG] FSR1 upscale shader failed to compile -- machinery NOT engaged, frames present directly (preset bypassed for this session)");
        return;
    }

    FSR1_Context::g_inputTexLoc = glGetUniformLocation(FSR1_Context::g_fsrProgram, "uInputTex");
    FSR1_Context::g_targetSizeLoc = glGetUniformLocation(FSR1_Context::g_fsrProgram, "uTargetSize");
    FSR1_Context::g_viewportSizeLoc = glGetUniformLocation(FSR1_Context::g_fsrProgram, "uViewportSize");

    // GLES.glUseProgram and not this layer's own: the frontend one writes
    // gl_state->current_program, and the guard above restores the driver from that
    // same field. Going through the frontend here would leave the tracked program
    // saying 0 while the driver holds the application's, and gl/program.cpp then
    // drops the application's next glUseProgram(0) as redundant.
    //
    // The sampler is set once, here. It is program state, not context state, and
    // this program is never relinked, so ApplyFSR does not repeat it per frame.
    GLES.glUseProgram(FSR1_Context::g_fsrProgram);
    GLES.glUniform1i(FSR1_Context::g_inputTexLoc, 0);
    GLES.glUseProgram(0);

    InitFullscreenQuad();

    GLES.glGenTextures(1, &FSR1_Context::g_renderTexture);
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_renderTexture);
    GLES.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight, 0, GL_RGBA,
                      GL_UNSIGNED_BYTE, nullptr);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);

    GLES.glGenRenderbuffers(1, &FSR1_Context::g_depthStencilRBO);
    GLES.glBindRenderbuffer(GL_RENDERBUFFER, FSR1_Context::g_depthStencilRBO);
    GLES.glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, FSR1_Context::g_renderWidth,
                               FSR1_Context::g_renderHeight);

    GLES.glGenFramebuffers(1, &FSR1_Context::g_renderFBO);
    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_renderFBO);
    GLES.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, FSR1_Context::g_renderTexture, 0);
    GLES.glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER,
                                   FSR1_Context::g_depthStencilRBO);

    GLES.glGenTextures(1, &FSR1_Context::g_targetTexture);
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_targetTexture);
    GLES.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight, 0, GL_RGBA,
                      GL_UNSIGNED_BYTE, nullptr);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);

    GLES.glGenFramebuffers(1, &FSR1_Context::g_targetFBO);
    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, FSR1_Context::g_targetTexture, 0);

    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_renderFBO);
}

void RecreateFSRFBO() {
    // No GUARD_PROGRAM, GUARD_VAO or GUARD_ARRAY_BUFFER: nothing below binds any of
    // the three. The program is not recompiled here either, so the uniform
    // locations resolved at link time stay valid across a resolution change.
    GLStateGuard state(GUARD_TEXTURE | GUARD_FRAMEBUFFER | GUARD_RENDERBUFFER);
    // The names about to stop existing. Everything that still refers to either of
    // them once the new pair is up has to be moved over, below.
    const GLuint oldRenderFBO = FSR1_Context::g_renderFBO;
    const GLuint oldTargetFBO = FSR1_Context::g_targetFBO;
    GLES.glDeleteFramebuffers(1, &FSR1_Context::g_renderFBO);
    GLES.glDeleteTextures(1, &FSR1_Context::g_renderTexture);
    GLES.glDeleteRenderbuffers(1, &FSR1_Context::g_depthStencilRBO);

    GLES.glDeleteFramebuffers(1, &FSR1_Context::g_targetFBO);
    GLES.glDeleteTextures(1, &FSR1_Context::g_targetTexture);

    GLES.glGenTextures(1, &FSR1_Context::g_renderTexture);
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_renderTexture);
    // Task 78 (Amethyst fork): RGBA8, matching InitFSRResources above. Upstream
    // recreated this texture as RGBA32F -- 2x the bytes per frame of pure
    // bandwidth for an LDR game upscale, inconsistent with its own init path
    // and with the render texture the application actually drew into before
    // the first resize. EASU/RCAS quality on RGBA8 input is what the init path
    // always used anyway.
    GLES.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight, 0,
                      GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
    GLES.glGenRenderbuffers(1, &FSR1_Context::g_depthStencilRBO);
    GLES.glBindRenderbuffer(GL_RENDERBUFFER, FSR1_Context::g_depthStencilRBO);
    GLES.glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, FSR1_Context::g_renderWidth,
                               FSR1_Context::g_renderHeight);
    GLES.glGenFramebuffers(1, &FSR1_Context::g_renderFBO);
    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_renderFBO);
    GLES.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, FSR1_Context::g_renderTexture, 0);
    GLES.glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER,
                                   FSR1_Context::g_depthStencilRBO);

    GLES.glGenTextures(1, &FSR1_Context::g_targetTexture);
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_targetTexture);
    GLES.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight, 0, GL_RGBA,
                      GL_UNSIGNED_BYTE, nullptr);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLES.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);

    GLES.glGenFramebuffers(1, &FSR1_Context::g_targetFBO);
    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, FSR1_Context::g_targetTexture, 0);

    // The tracked draw binding names the render FBO for as long as the application
    // is drawing to framebuffer 0, because gl/framebuffer.cpp redirects that bind
    // and records the name it handed the driver. That name was deleted above, and
    // nothing in gl/framebuffer.cpp can see it happen -- its glDeleteFramebuffers
    // hook, the one that rebinds 0, is not the path taken here. Left alone, the
    // tracked field would keep naming a dead framebuffer and every GLStateGuard from
    // here on would try to restore it: the restore is rejected, the draw binding
    // stays on framebuffer 0 where ApplyFSR's blit leaves it, and the application
    // renders into the surface at render resolution while the upscale keeps reading
    // a render texture nobody writes.
    //
    // Name 0 is excluded, and it is reachable: this runs once a frame from the swap
    // as soon as FSR1 is switched on, while InitFSRResources waits for the first
    // shader. A tracked 0 there is the real surface, not a redirect, and moving it
    // onto the render FBO would diverge from the driver in the other direction --
    // the guard below restores what it saved, which is 0.
    if (oldRenderFBO != 0 && gl_state->current_draw_fbo == oldRenderFBO) {
        set_gl_state_current_draw_fbo(FSR1_Context::g_renderFBO);
    }
    state.framebuffer_recreated(oldRenderFBO, FSR1_Context::g_renderFBO);
    state.framebuffer_recreated(oldTargetFBO, FSR1_Context::g_targetFBO);

    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_renderFBO);
    GLES.glViewport(0, 0, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight);

    LOG_D("FSR1 resources recreated: render %dx%d, target %dx%d", FSR1_Context::g_renderWidth,
          FSR1_Context::g_renderHeight, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight);
}

std::vector<std::pair<GLsizei, GLsizei>> g_viewportStack;

void ApplyFSR() {
    // Task 76 (Amethyst fork): guard for the zero-gain teardown below. The
    // render FBO is 0 when FSR1 has been torn down (render resolution pinned at
    // or above the surface size -- nothing to upscale for) or before the first
    // initialization. Running the body in either state would bind target-FBO 0
    // and issue a fullscreen pass into whatever the driver considers framebuffer
    // 0, so the early return keeps both the bypass and the init window safe.
    if (FSR1_Context::g_renderFBO == 0) return;
    // No GUARD_ARRAY_BUFFER or GUARD_RENDERBUFFER: nothing below binds either.
    // GL_ARRAY_BUFFER_BINDING is context state and not vertex array object state, so
    // the glBindVertexArray below cannot disturb it.
    GLStateGuard state(GUARD_PROGRAM | GUARD_VAO | GUARD_TEXTURE | GUARD_FRAMEBUFFER);

    GLES.glUseProgram(FSR1_Context::g_fsrProgram);

    // Unit 0 is already current -- the guard made it so, and it is the unit
    // uInputTex was pointed at when the program was linked.
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_renderTexture);

    // Task 80 (Amethyst fork): the EASU constant setup runs in the shader from
    // these two uniforms -- the input (render) size and the upscale output
    // (target) size. Upstream fed a vec4 nobody read (uConst0) and computed the
    // constants with outputSize == inputSize, an identity mapping.
    const GLfloat viewportSize[2] = {(float)FSR1_Context::g_renderWidth,
                                     (float)FSR1_Context::g_renderHeight};
    GLES.glUniform2fv(FSR1_Context::g_viewportSizeLoc, 1, viewportSize);

    const GLfloat targetSize[2] = {(float)FSR1_Context::g_targetWidth,
                                   (float)FSR1_Context::g_targetHeight};
    GLES.glUniform2fv(FSR1_Context::g_targetSizeLoc, 1, targetSize);

    GLES.glBindVertexArray(FSR1_Context::g_quadVAO);

    // Task 83 (Amethyst fork) per-frame cost reduction: 3 fullscreen passes -> 1.
    // The old body paid (a) a clear of the target, (b) the EASU draw, (c) a
    // full-surface blit -- every frame. (a) was pure waste: the EASU quad
    // covers the whole target, so the clear only ever survived into a frame
    // when the pass itself had already failed. (c) is unnecessary whenever the
    // target matches the surface: draw EASU straight into the surface and skip
    // the intermediate target FBO entirely. That match is arranged on the
    // resize path (rounding residue of at most a few pixels is clamped up to
    // the surface), so the common launcher case runs one fullscreen pass; the
    // resolution-slider-stacked path (target genuinely below the surface)
    // keeps the old blit so the linear filter performs that final stretch.
    const bool directToSurface =
        FSR1_Context::g_surfaceWidth > 0 && FSR1_Context::g_surfaceHeight > 0 &&
        FSR1_Context::g_targetWidth == FSR1_Context::g_surfaceWidth &&
        FSR1_Context::g_targetHeight == FSR1_Context::g_surfaceHeight;

    if (directToSurface) {
        // Depth/scissor/blend/cull would all silently eat the quad on a default
        // framebuffer that carries a depth attachment or app-leftover state --
        // the target FBO never had those, the surface may. MC re-arms its own
        // state every frame, so leaving these disabled through the swap is the
        // same stomp the rest of this function already makes.
        GLES.glDisable(GL_DEPTH_TEST);
        GLES.glDisable(GL_SCISSOR_TEST);
        GLES.glDisable(GL_BLEND);
        GLES.glDisable(GL_CULL_FACE);
        GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        GLES.glViewport(0, 0, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight);
        GLES.glDrawArrays(GL_TRIANGLES, 0, 6);
        // Hand the draw binding back to the render FBO the application's next
        // frame expects (the guard would restore it too, but the read binding
        // below is cheap to leave untouched and the explicit bind documents
        // the handoff).
        GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, FSR1_Context::g_renderFBO);
        GLES.glViewport(0, 0, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight);
        return;
    }

    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glViewport(0, 0, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight);

    GLES.glDrawArrays(GL_TRIANGLES, 0, 6);

    GLES.glBindFramebuffer(GL_READ_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    // Task 80 (Amethyst fork): blit the target into the FULL SURFACE, not a
    // target-sized corner of it. The preset scale rounds (render 1814 * 1.30 =
    // 2358 vs surface 2360), the resolution slider can stack with FSR (target
    // well below surface), and a rotation can change the surface out from under
    // a still-valid render size -- a 1:1 blit left a stale right-hand column in
    // every one of those. GL_LINEAR on the blit handles the residual stretch
    // (an exact copy when the sizes match). Before the first
    // CheckResolutionChange the surface size is unknown; fall back to 1:1 on
    // the target for that single frame.
    const GLsizei dstW = (FSR1_Context::g_surfaceWidth > 0) ? FSR1_Context::g_surfaceWidth
                                                            : FSR1_Context::g_targetWidth;
    const GLsizei dstH = (FSR1_Context::g_surfaceHeight > 0) ? FSR1_Context::g_surfaceHeight
                                                             : FSR1_Context::g_targetHeight;
    GLES.glBlitFramebuffer(0, 0, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight, 0, 0,
                           dstW, dstH, GL_COLOR_BUFFER_BIT, GL_LINEAR);

    // The viewport and nothing else. Neither framebuffer binding is worth setting
    // here: the guard restores both on the next line, and what it restores for the
    // draw binding is the render framebuffer itself whenever the application was
    // drawing to framebuffer 0, which is the case this whole path exists for. The
    // viewport is deliberately outside the guard -- FSR1 owns it between frames, and
    // the next frame has to start at render resolution.
    GLES.glViewport(0, 0, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight);
}

void CheckResolutionChange(EGLDisplay display, EGLSurface surface) {
    GLsizei width = 0, height = 0;
    LOAD_EGL(eglQuerySurface);
    // Taken from the swap this is hooked into rather than latched into statics on
    // first use. The old code kept the first display and surface it ever saw, so
    // after a rotation or a surface rebuild it queried a destroyed surface every
    // frame and the resolution never changed again.
    if (display == EGL_NO_DISPLAY || surface == EGL_NO_SURFACE) {
        display = eglGetCurrentDisplay();
        surface = eglGetCurrentSurface(EGL_DRAW);
    }
    // Both queries stay, once a frame. EGL has no notification for a surface that
    // changed size, and the only other trigger this file has -- the glViewport hook
    // below -- fires solely when the application asks for a viewport larger than the
    // last size latched, so it can see neither a surface that shrank nor one the
    // application never draws full-bleed into. They are also EGL calls, reading
    // attributes the surface record already holds, not GL commands that have to
    // reach the driver's command stream.
    egl_eglQuerySurface(display, surface, EGL_WIDTH, &width);
    egl_eglQuerySurface(display, surface, EGL_HEIGHT, &height);
    // Task 78 (Amethyst fork): the render size follows the APPLICATION, not the
    // surface. Upstream fed the surface dims into OnResize here unconditionally,
    // which pinned render == surface by construction -- in any launcher that
    // tells Minecraft its window equals the surface, the upscale was dead on
    // arrival (Task 76's zero-gain teardown, and before it a double resample).
    // With the launcher's FSR linkage MC's told window -- and therefore its
    // glViewport latch -- IS the render size, and the target below lands on the
    // surface. The surface feed survives only as a pre-first-viewport fallback
    // (pending == 0): a fullscreen-viewport application then settles on
    // render == surface -> zero-gain teardown -> direct present, which is the
    // correct verdict for it.
    if (FSR1_Context::g_pendingWidth == 0 && FSR1_Context::g_pendingHeight == 0) {
        OnResize(width, height);
    }
    // Task 76 (Amethyst fork): keep the surface size visible to the zero-gain
    // branch below under names that cannot be shadowed by the pending-size pair.
    const GLsizei surfaceWidth = width;
    const GLsizei surfaceHeight = height;
    // Task 80 (Amethyst fork): remember the surface for ApplyFSR's full-bleed
    // blit. One frame behind the swap it will present into (this runs after
    // it), which is exactly the freshness the old per-frame code had too.
    FSR1_Context::g_surfaceWidth = surfaceWidth;
    FSR1_Context::g_surfaceHeight = surfaceHeight;

    if (FSR1_Context::g_resolutionChanged) {
        FSR1_Context::g_resolutionChanged = false;
        GLsizei width = FSR1_Context::g_pendingWidth;
        GLsizei height = FSR1_Context::g_pendingHeight;
        FSR1_Context::g_renderWidth = width;
        FSR1_Context::g_renderHeight = height;

        CalculateTargetResolution(global_settings.fsr1_setting, width, height,
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetWidth),
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetHeight));
        // Task 80 (Amethyst fork): clamp the target to the surface when the
        // preset scale would overshoot it. render x scale lands a pixel or two
        // past the surface purely from rounding (1814 x 1.30 = 2358.2 on a
        // 2360-wide surface -- and the launcher derived 1814 FROM 2360), so
        // an unclamped target allocates an oversized FBO and still cannot
        // fill the last column. A target genuinely below the surface (the
        // resolution slider stacked on FSR) is left alone: the blit's linear
        // filter performs that final stretch by design.
        if (surfaceWidth > 0 && FSR1_Context::g_targetWidth > surfaceWidth) {
            FSR1_Context::g_targetWidth = surfaceWidth;
        }
        if (surfaceHeight > 0 && FSR1_Context::g_targetHeight > surfaceHeight) {
            FSR1_Context::g_targetHeight = surfaceHeight;
        }
        // Task 83 (Amethyst fork): round the target UP to the surface when the
        // gap is pure rounding residue (<= 4 px per axis). render x preset
        // regularly lands 1-2 px short of the surface it was derived from
        // (2360 / 1.5 = 1573.3 -> 1573; 1573 x 1.5 = 2359.5 -> 2359 on a
        // 2360 surface). A residue-sized gap buys nothing -- the blit's linear
        // filter stretches those two columns invisibly -- while an exact match
        // lets ApplyFSR take the direct-to-surface path and skip the blit and
        // the intermediate target entirely (one fullscreen pass per frame
        // instead of three). Anything larger than residue is a genuine
        // sub-surface target (resolution slider stacked on FSR) and keeps the
        // blit path.
        if (surfaceWidth > 0 && surfaceWidth - FSR1_Context::g_targetWidth <= 4) {
            FSR1_Context::g_targetWidth = surfaceWidth;
        }
        if (surfaceHeight > 0 && surfaceHeight - FSR1_Context::g_targetHeight <= 4) {
            FSR1_Context::g_targetHeight = surfaceHeight;
        }
        // Task 76 (Amethyst fork): zero-gain bypass. The outer width/height hold
        // the surface size from this swap's eglQuerySurface pair; the local pair
        // shadow them with the pending render size. When the latched render size
        // covers the surface, an upscale pass can only resample twice at up to
        // scale^2 the surface area -- tear down instead of recreating. A future
        // surface that outgrows the render size (window resize up, rotation into
        // a larger surface) re-arms the machinery through RecreateFSRFBO, but a
        // render size that only ever follows the viewport back up re-tears it.
        if (width >= surfaceWidth && height >= surfaceHeight) {
            TeardownFSR1();
        } else if (FSR1_Context::g_fsrProgram == 0) {
            // Task 80 (Amethyst fork): never engage with a dead program -- the
            // geometry says "upscale" but the pass would clear the target to
            // black and draw nothing (see InitFSRResources' safety net for the
            // full failure chain). Unreachable by construction (the init path
            // creates no FBOs without a program); the teardown is a no-op then
            // and stays one -- it only bites if some future path arms the FBOs
            // without a working pass.
            TeardownFSR1();
            static bool s_task80_deadprog = false;
            if (!s_task80_deadprog) {
                s_task80_deadprog = true;
                LOG_W_FORCE("[MG] FSR1 upscale NOT engaged: shader program unavailable -- presenting directly (no upscale this session)");
            }
        } else {
            // Task 78 (Amethyst fork): one-shot engage log. This branch is the
            // first time the upscale is actually live under the launcher's
            // FSR linkage -- render (viewport latch) below the surface, target
            // = render x preset scale on top of the surface.
            static bool s_task78_engaged = false;
            if (!s_task78_engaged) {
                s_task78_engaged = true;
                LOG_W_FORCE("[MG] FSR1 upscale engaged (Task78): render %dx%d -> target %dx%d -> surface %dx%d (viewport-latched render, launcher FSR linkage)",
                            FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight,
                            FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight,
                            surfaceWidth, surfaceHeight);
            }
            RecreateFSRFBO();
        }
    } else if (FSR1_Context::g_renderFBO != 0 && FSR1_Context::g_renderWidth > 0 &&
               FSR1_Context::g_renderWidth >= surfaceWidth && FSR1_Context::g_renderHeight >= surfaceHeight) {
        // Task 78 (Amethyst fork) safety: zero-gain verdict without a pending
        // change. Reachable when the preset is on but the linkage is inactive
        // (MC told the full window: the viewport latch equals the surface, or
        // a legacy init adopted the surface through the fallback feed above).
        // Without this the oversized target kept paying the triple fullscreen
        // tax every frame -- exactly the state Task 76 tore down, resurrected
        // by the init-adoption path.
        TeardownFSR1();
    }
    // No glViewport here. This runs immediately after ApplyFSR and the swap, and
    // ApplyFSR ends every frame with exactly this call at exactly this size; on the
    // one frame where the size does change, RecreateFSRFBO ends with it at the new
    // size. It was setting the viewport to the value it already held, once per
    // presented frame.
}

void OnResize(int width, int height) {
    if (FSR1_Context::g_renderWidth == width && FSR1_Context::g_renderHeight == height) return;

    FSR1_Context::g_pendingWidth = width;
    FSR1_Context::g_pendingHeight = height;
    FSR1_Context::g_resolutionChanged = true;
}

// Task 76 (Amethyst fork): tear the FSR1 machinery down for this context.
//
// FSR1 exists to upscale a LOW render resolution up to the surface size. The
// application (Minecraft with a fullscreen window) drives its first
// glViewport at the full window size, the glViewport hook below latches that
// as the render size, and the render size lands equal to (or above) the EGL
// surface. From that moment the upscale has nothing to offer:
//
//   - the target is render * scale (3540x2460 for a 2360x1640 surface at the
//     Quality preset, 2.25x the surface's pixel count);
//   - ApplyFSR pays a fullscreen clear + the EASU/RCAS pass into that oversized
//     target every frame;
//   - the closing blit then scales BACK DOWN to the surface, so the presented
//     image went render -> upscale -> downscale: three fullscreen passes and
//     a double resample, for image quality strictly WORSE than presenting the
//     render texture directly, on top of the frame-time cost.
//
// Zero gain is detected once the geometry is latched (CheckResolutionChange)
// and resolved by deleting the render/target objects and zeroing g_renderFBO.
// gl/framebuffer.cpp keys its framebuffer-0 redirect on g_renderFBO != 0, so
// the teardown also reverts the application to drawing straight into the
// surface, and ApplyFSR's guard above makes the per-swap call a no-op.
// fsrInitialized is deliberately left true so glCreateShader does not rebuild
// this machinery for a state already judged zero-gain. Per-context state is
// consistent: mg_fsr1_bind_context stores/loads these globals verbatim, so a
// torn-down context stays torn down across binds.
void TeardownFSR1() {
    if (FSR1_Context::g_renderFBO == 0 && FSR1_Context::g_targetFBO == 0) return;
    GLStateGuard state(GUARD_FRAMEBUFFER | GUARD_TEXTURE);

    const GLuint deadRenderFBO = FSR1_Context::g_renderFBO;
    const GLuint deadTargetFBO = FSR1_Context::g_targetFBO;
    const GLuint deadRenderTex = FSR1_Context::g_renderTexture;
    const GLuint deadTargetTex = FSR1_Context::g_targetTexture;
    const GLuint deadRBO = FSR1_Context::g_depthStencilRBO;

    // gl/framebuffer.cpp owns gl_state->current_draw_fbo. If the tracked draw
    // binding points at a name that is about to die, repoint it at 0 (the real
    // surface) by hand, and tell any live GLStateGuard that saved one of the
    // dead names to restore 0 instead -- restoring a deleted name is rejected
    // and leaves the binding wherever the body left it (the exact failure mode
    // RecreateFSRFBO's framebuffer_recreated bookkeeping exists to prevent).
    if (gl_state->current_draw_fbo == deadRenderFBO || gl_state->current_draw_fbo == deadTargetFBO) {
        set_gl_state_current_draw_fbo(0);
    }
    state.framebuffer_recreated(deadRenderFBO, 0);
    state.framebuffer_recreated(deadTargetFBO, 0);

    GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    GLES.glDeleteFramebuffers(1, &deadRenderFBO);
    GLES.glDeleteFramebuffers(1, &deadTargetFBO);
    GLES.glDeleteTextures(1, &deadRenderTex);
    GLES.glDeleteTextures(1, &deadTargetTex);
    GLES.glDeleteRenderbuffers(1, &deadRBO);

    FSR1_Context::g_renderFBO = 0;
    FSR1_Context::g_renderTexture = 0;
    FSR1_Context::g_targetFBO = 0;
    FSR1_Context::g_targetTexture = 0;
    FSR1_Context::g_depthStencilRBO = 0;

    LOG_W_FORCE("[MG] FSR1 zero-gain bypass: render %dx%d >= surface -- FSR machinery torn down, frames presented directly (preset kept for a future sub-surface render size)",
                FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight);
}

// Task 82 (Amethyst fork): the surface size as seen by this context's last
// CheckResolutionChange, or -- before the first swap -- straight from EGL.
// The glViewport latch below needs it to tell a window viewport from an
// intermediate render pass, and the poisoning it exists to stop happens
// exactly in the pre-first-swap window where the cache is still empty.
static void task82_surface_size(GLsizei* outW, GLsizei* outH) {
    if (FSR1_Context::g_surfaceWidth > 0 && FSR1_Context::g_surfaceHeight > 0) {
        *outW = FSR1_Context::g_surfaceWidth;
        *outH = FSR1_Context::g_surfaceHeight;
        return;
    }
    // Same fallback CheckResolutionChange uses. eglGetCurrentDisplay /
    // eglGetCurrentSurface are this image's own frontend exports (egl/egl.cpp),
    // and eglQuerySurface reads attributes the surface record already holds --
    // no driver round trip, no command-stream interaction.
    EGLDisplay display = eglGetCurrentDisplay();
    EGLSurface surface = eglGetCurrentSurface(EGL_DRAW);
    if (display == EGL_NO_DISPLAY || surface == EGL_NO_SURFACE) {
        *outW = 0;
        *outH = 0;
        return;
    }
    LOAD_EGL(eglQuerySurface);
    if (egl_eglQuerySurface == NULL) {
        *outW = 0;
        *outH = 0;
        return;
    }
    EGLint w = 0, h = 0;
    egl_eglQuerySurface(display, surface, EGL_WIDTH, &w);
    egl_eglQuerySurface(display, surface, EGL_HEIGHT, &h);
    *outW = w;
    *outH = h;
}

void glViewport(GLint x, GLint y, GLsizei w, GLsizei h) {
    LOG()
    LOG_D("glViewport: x=%d, y=%d, w=%d, h=%d", x, y, w, h);

    if (w > FSR1_Context::g_pendingWidth || h > FSR1_Context::g_pendingHeight) {
        // Task 82 (Amethyst fork): the latch only ever grows, so any
        // intermediate render pass with a viewport larger than the window's
        // poisons it for good. MC 26.x renders animated atlas sprites into
        // the blocks atlas through a glViewport of the full atlas size --
        // 2048x2048 on a 2360x1640 surface whose window (surface / preset
        // scale) is 1814x1262. The atlas latch won (2048 > 1814), the main
        // viewport could never reclaim it (nothing grows past 2048), and the
        // upscale then stretched the mostly-unwritten 2048x2048 render
        // texture over the whole surface: the game appeared shrunk into the
        // bottom-left corner (ea27def: "render 2048x2048 -> target
        // 2360x1640" while every swap probe showed the real frame viewport
        // at 1814x1262).
        //
        // Two properties separate a window viewport from an intermediate
        // pass, and a latch candidate has to pass both:
        //   1. it never exceeds the EGL surface -- the window IS at most the
        //      surface, the launcher derives it as surface / preset scale;
        //   2. it carries the surface's aspect ratio -- the window scales the
        //      surface uniformly, while atlas and shadow-map passes are
        //      square and post-processing targets are window-shaped and no
        //      larger. 3% absorbs the preset-scale rounding (1814/1262 =
        //      1.4371 vs 2360/1640 = 1.4390, a 0.13% drift).
        // Candidates failing either are refused; the growth rule stays for
        // the ones that pass, so a rotation (a dimension swap is still a
        // growth in one axis) keeps re-latching as before. Checked only
        // while FSR1 is enabled -- with the preset off nothing consumes the
        // latch and the EGL queries would be pure overhead.
        bool latch = true;
        if (global_settings.fsr1_setting != FSR1_Quality_Preset::Disabled) {
            GLsizei surfaceW = 0, surfaceH = 0;
            task82_surface_size(&surfaceW, &surfaceH);
            if (surfaceW > 0 && surfaceH > 0) {
                if (w > surfaceW || h > surfaceH) {
                    latch = false;
                } else {
                    const float surfaceAspect = (float)surfaceW / (float)surfaceH;
                    const float vpAspect = (float)w / (float)h;
                    const float drift =
                        (vpAspect > surfaceAspect ? vpAspect - surfaceAspect : surfaceAspect - vpAspect) /
                        surfaceAspect;
                    if (drift > 0.03f) latch = false;
                }
                if (!latch) {
                    // Once per distinct rejected size: the atlas pass fires
                    // every frame, and the first refusal is the whole story.
                    static GLsizei s_task82_rejW = -1;
                    static GLsizei s_task82_rejH = -1;
                    if (s_task82_rejW != w || s_task82_rejH != h) {
                        s_task82_rejW = w;
                        s_task82_rejH = h;
                        LOG_W_FORCE("[MG] FSR1 viewport latch rejected (Task 82): %dx%d is not a window viewport "
                                    "(surface %dx%d) -- intermediate render pass kept out of the upscale geometry",
                                    w, h, surfaceW, surfaceH);
                    }
                }
            }
        }
        if (latch) {
            FSR1_Context::g_pendingWidth = w;
            FSR1_Context::g_pendingHeight = h;
            FSR1_Context::g_resolutionChanged = true;
        }
    }

    GLES.glViewport(x, y, w, h);
}

// ---------------------------------------------------------------------------

namespace {

struct fsr1_ctx_state_t {
    GLuint renderFBO = 0, renderTexture = 0, depthStencilRBO = 0;
    GLuint quadVAO = 0, quadVBO = 0, fsrProgram = 0;
    // Locations belong to fsrProgram, so they travel with it rather than being
    // re-resolved after a context switch.
    GLint inputTexLoc = -1, targetSizeLoc = -1, viewportSizeLoc = -1;
    GLuint targetFBO = 0, targetTexture = 0, currentDrawFBO = 0;
    GLsizei targetWidth = 0, targetHeight = 0, renderWidth = 0, renderHeight = 0;
    // Task 80 (Amethyst fork): surface geometry is per-context state -- a second
    // context presents to its own surface.
    GLsizei surfaceWidth = 0, surfaceHeight = 0;
    bool initialised = false;
};

std::mutex g_fsr_mutex;
// Plain value, not a unique_ptr like the other per-context tables: nothing here
// keeps the address of an entry. Both operator[] calls in mg_fsr1_bind_context
// are separate statements, so the first reference is dead before the second one
// can rehash the map.
ska::flat_hash_map<unsigned long long, fsr1_ctx_state_t> g_fsr_states;
fsr1_ctx_state_t g_fsr_default;
thread_local unsigned long long g_fsr_current_id = 0;

void store_into(fsr1_ctx_state_t& d) {
    d.renderFBO = FSR1_Context::g_renderFBO;
    d.renderTexture = FSR1_Context::g_renderTexture;
    d.depthStencilRBO = FSR1_Context::g_depthStencilRBO;
    d.quadVAO = FSR1_Context::g_quadVAO;
    d.quadVBO = FSR1_Context::g_quadVBO;
    d.fsrProgram = FSR1_Context::g_fsrProgram;
    d.inputTexLoc = FSR1_Context::g_inputTexLoc;
    d.targetSizeLoc = FSR1_Context::g_targetSizeLoc;
    d.viewportSizeLoc = FSR1_Context::g_viewportSizeLoc;
    d.targetFBO = FSR1_Context::g_targetFBO;
    d.targetTexture = FSR1_Context::g_targetTexture;
    d.currentDrawFBO = FSR1_Context::g_currentDrawFBO;
    d.targetWidth = FSR1_Context::g_targetWidth;
    d.targetHeight = FSR1_Context::g_targetHeight;
    d.renderWidth = FSR1_Context::g_renderWidth;
    d.renderHeight = FSR1_Context::g_renderHeight;
    d.surfaceWidth = FSR1_Context::g_surfaceWidth;
    d.surfaceHeight = FSR1_Context::g_surfaceHeight;
    d.initialised = fsrInitialized;
}

void load_from(const fsr1_ctx_state_t& s) {
    FSR1_Context::g_renderFBO = s.renderFBO;
    FSR1_Context::g_renderTexture = s.renderTexture;
    FSR1_Context::g_depthStencilRBO = s.depthStencilRBO;
    FSR1_Context::g_quadVAO = s.quadVAO;
    FSR1_Context::g_quadVBO = s.quadVBO;
    FSR1_Context::g_fsrProgram = s.fsrProgram;
    FSR1_Context::g_inputTexLoc = s.inputTexLoc;
    FSR1_Context::g_targetSizeLoc = s.targetSizeLoc;
    FSR1_Context::g_viewportSizeLoc = s.viewportSizeLoc;
    FSR1_Context::g_targetFBO = s.targetFBO;
    FSR1_Context::g_targetTexture = s.targetTexture;
    FSR1_Context::g_currentDrawFBO = s.currentDrawFBO;
    FSR1_Context::g_targetWidth = s.targetWidth;
    FSR1_Context::g_targetHeight = s.targetHeight;
    FSR1_Context::g_renderWidth = s.renderWidth;
    FSR1_Context::g_renderHeight = s.renderHeight;
    FSR1_Context::g_surfaceWidth = s.surfaceWidth;
    FSR1_Context::g_surfaceHeight = s.surfaceHeight;
    fsrInitialized = s.initialised;
    // Left alone deliberately: g_dirty, g_resolutionChanged and the pending size
    // describe work queued for the frame in flight, not the context's objects.
}

} // namespace

void mg_fsr1_bind_context(unsigned long long ctx_id) {
    if (ctx_id == g_fsr_current_id) return;
    std::lock_guard<std::mutex> lock(g_fsr_mutex);
    store_into(g_fsr_current_id == 0 ? g_fsr_default : g_fsr_states[g_fsr_current_id]);
    load_from(ctx_id == 0 ? g_fsr_default : g_fsr_states[ctx_id]);
    g_fsr_current_id = ctx_id;
}

void mg_fsr1_forget_context(unsigned long long ctx_id) {
    if (ctx_id == 0) return;
    std::lock_guard<std::mutex> lock(g_fsr_mutex);
    // If this is still the loaded set, the live globals describe a context that is
    // gone. Drop back to the default set rather than storing them into the entry
    // about to be erased.
    if (g_fsr_current_id == ctx_id) {
        load_from(g_fsr_default);
        g_fsr_current_id = 0;
    }
    g_fsr_states.erase(ctx_id);
}
