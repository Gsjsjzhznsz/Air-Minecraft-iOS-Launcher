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
    GLint g_const0Loc = -1;
    GLint g_viewportSizeLoc = -1;

    GLuint g_targetFBO = 0;
    GLuint g_targetTexture = 0;

    GLuint g_currentDrawFBO = 0;
    GLint g_viewport[4] = {0};
    GLsizei g_targetWidth = 2400;
    GLsizei g_targetHeight = 1080;
    GLsizei g_renderWidth = 1200;
    GLsizei g_renderHeight = 540;
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
    // No GUARD_VAO or GUARD_ARRAY_BUFFER: the only thing here that binds either is
    // InitFullscreenQuad, which carries its own guard.
    GLStateGuard state(GUARD_PROGRAM | GUARD_TEXTURE | GUARD_FRAMEBUFFER | GUARD_RENDERBUFFER);

    FSR1_Context::g_fsrProgram = CompileFSRShader();

    FSR1_Context::g_inputTexLoc = glGetUniformLocation(FSR1_Context::g_fsrProgram, "uInputTex");
    FSR1_Context::g_const0Loc = glGetUniformLocation(FSR1_Context::g_fsrProgram, "uConst0");
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
    GLES.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, FSR1_Context::g_renderWidth, FSR1_Context::g_renderHeight, 0,
                      GL_RGBA, GL_FLOAT, nullptr);
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
    // No GUARD_ARRAY_BUFFER or GUARD_RENDERBUFFER: nothing below binds either.
    // GL_ARRAY_BUFFER_BINDING is context state and not vertex array object state, so
    // the glBindVertexArray below cannot disturb it.
    GLStateGuard state(GUARD_PROGRAM | GUARD_VAO | GUARD_TEXTURE | GUARD_FRAMEBUFFER);

    GLES.glBindFramebuffer(GL_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glViewport(0, 0, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight);
    GLES.glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    GLES.glClear(GL_COLOR_BUFFER_BIT);

    GLES.glUseProgram(FSR1_Context::g_fsrProgram);

    // Unit 0 is already current -- the guard made it so, and it is the unit
    // uInputTex was pointed at when the program was linked.
    GLES.glBindTexture(GL_TEXTURE_2D, FSR1_Context::g_renderTexture);

    // Plain arrays rather than a vector type from a maths library: these two are
    // handed straight to glUniform*fv, and nothing is ever computed with them.
    const GLfloat const0[4] = {float(FSR1_Context::g_renderWidth) / FSR1_Context::g_targetWidth,
                               float(FSR1_Context::g_renderHeight) / FSR1_Context::g_targetHeight,
                               1.0f / FSR1_Context::g_targetWidth,
                               1.0f / FSR1_Context::g_targetHeight};

    GLES.glUniform4fv(FSR1_Context::g_const0Loc, 1, const0);

    const GLfloat viewportSize[2] = {(float)FSR1_Context::g_renderWidth,
                                     (float)FSR1_Context::g_renderHeight};
    GLES.glUniform2fv(FSR1_Context::g_viewportSizeLoc, 1, viewportSize);

    GLES.glBindVertexArray(FSR1_Context::g_quadVAO);
    GLES.glDrawArrays(GL_TRIANGLES, 0, 6);

    GLES.glBindFramebuffer(GL_READ_FRAMEBUFFER, FSR1_Context::g_targetFBO);
    GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    GLES.glBlitFramebuffer(0, 0, FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight, 0, 0,
                           FSR1_Context::g_targetWidth, FSR1_Context::g_targetHeight, GL_COLOR_BUFFER_BIT, GL_LINEAR);

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
    OnResize(width, height);

    if (FSR1_Context::g_resolutionChanged) {
        FSR1_Context::g_resolutionChanged = false;
        GLsizei width = FSR1_Context::g_pendingWidth;
        GLsizei height = FSR1_Context::g_pendingHeight;
        FSR1_Context::g_renderWidth = width;
        FSR1_Context::g_renderHeight = height;

        CalculateTargetResolution(global_settings.fsr1_setting, width, height,
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetWidth),
                                  reinterpret_cast<int*>(&FSR1_Context::g_targetHeight));
        RecreateFSRFBO();
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

void glViewport(GLint x, GLint y, GLsizei w, GLsizei h) {
    LOG()
    LOG_D("glViewport: x=%d, y=%d, w=%d, h=%d", x, y, w, h);

    if (w > FSR1_Context::g_pendingWidth || h > FSR1_Context::g_pendingHeight) {
        FSR1_Context::g_pendingWidth = w;
        FSR1_Context::g_pendingHeight = h;
        FSR1_Context::g_resolutionChanged = true;
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
    GLint inputTexLoc = -1, const0Loc = -1, viewportSizeLoc = -1;
    GLuint targetFBO = 0, targetTexture = 0, currentDrawFBO = 0;
    GLsizei targetWidth = 0, targetHeight = 0, renderWidth = 0, renderHeight = 0;
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
    d.const0Loc = FSR1_Context::g_const0Loc;
    d.viewportSizeLoc = FSR1_Context::g_viewportSizeLoc;
    d.targetFBO = FSR1_Context::g_targetFBO;
    d.targetTexture = FSR1_Context::g_targetTexture;
    d.currentDrawFBO = FSR1_Context::g_currentDrawFBO;
    d.targetWidth = FSR1_Context::g_targetWidth;
    d.targetHeight = FSR1_Context::g_targetHeight;
    d.renderWidth = FSR1_Context::g_renderWidth;
    d.renderHeight = FSR1_Context::g_renderHeight;
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
    FSR1_Context::g_const0Loc = s.const0Loc;
    FSR1_Context::g_viewportSizeLoc = s.viewportSizeLoc;
    FSR1_Context::g_targetFBO = s.targetFBO;
    FSR1_Context::g_targetTexture = s.targetTexture;
    FSR1_Context::g_currentDrawFBO = s.currentDrawFBO;
    FSR1_Context::g_targetWidth = s.targetWidth;
    FSR1_Context::g_targetHeight = s.targetHeight;
    FSR1_Context::g_renderWidth = s.renderWidth;
    FSR1_Context::g_renderHeight = s.renderHeight;
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
