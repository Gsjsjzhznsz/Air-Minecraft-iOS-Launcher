#!/usr/bin/env python3
"""Task165 syntax gate #2: stub-compile the two new FSR1.cpp blocks (the
render-texture probe and the RCAS bail-out) extracted from the live source.
The full TU needs the MobileGlues tree + GLES loader; this gate catches
typos/semantics the bracket balance cannot."""
import re
import subprocess
import sys

src = open("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp",
           encoding="utf-8").read()

probe = re.search(
    r"(static bool s_ame165_rtProbed = false;.*?// Depth/scissor)",
    src, re.S)
bailout = re.search(
    r"(// Task165：RCAS 运行期熔断.*?// READ 绑定还回)",
    src, re.S)
assert probe, "render-texture probe block not found"
assert bailout, "bail-out block not found"

stub = r'''
#include <cstdio>
typedef int GLsizei; typedef unsigned int GLuint; typedef int GLint;
typedef unsigned int GLenum; typedef unsigned char GLboolean;
typedef float GLfloat;
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_DRAW_FRAMEBUFFER 0x8CA6
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
#define GL_TRIANGLES 0x0004
#define GL_TEXTURE0 0x84C0
#define GL_TEXTURE_2D 0x0DE1
static struct { int dummy; } _glue;
static struct StubGLES {
    void (*glBindFramebuffer)(GLenum, GLuint);
    void (*glReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*);
    void (*glUseProgram)(GLuint);
    void (*glActiveTexture)(GLenum);
    void (*glBindTexture)(GLenum, GLuint);
    void (*glUniform1i)(GLint, GLint);
    void (*glViewport)(GLint, GLint, GLsizei, GLsizei);
    void (*glDrawArrays)(GLenum, GLint, GLsizei);
    unsigned int (*glGetError)(void);
} GLES;
static struct { float fsr1_rcas_sharpness; } global_settings;
#define LOG_I(...) do { printf(__VA_ARGS__); } while (0)
#define LOG_W_FORCE(...) do { printf(__VA_ARGS__); } while (0)
namespace FSR1_Context {
    GLuint g_renderFBO = 1, g_renderTexture = 2, g_fsrProgram = 3, g_rcasProgram = 4;
    GLint g_inputTexLoc = 0;
    GLsizei g_renderWidth = 1180, g_renderHeight = 820;
    GLsizei g_targetWidth = 2360, g_targetHeight = 1640;
}
static bool s_ame165_rcasBailout = false;

static void block_probe() {
''' + probe.group(1) + r'''
}
static void block_bailout(unsigned char ame164_px[4]) {
''' + bailout.group(1) + r'''
}
int main() { block_probe(); unsigned char px[4] = {0,0,0,(unsigned char)255}; block_bailout(px); return 0; }
'''
open("/tmp/task165_fsr_stub.cpp", "w").write(stub)
print(f"[task165] stub written: {len(stub)} bytes")
r = subprocess.run(["g++", "-Wall", "-Wextra", "-Werror", "-std=c++17",
                    "-fsyntax-only", "/tmp/task165_fsr_stub.cpp"],
                   capture_output=True, text=True)
if r.returncode != 0:
    print(r.stderr)
    sys.exit(1)
print("[task165] FSR1 probe + bail-out stub compile: OK")
