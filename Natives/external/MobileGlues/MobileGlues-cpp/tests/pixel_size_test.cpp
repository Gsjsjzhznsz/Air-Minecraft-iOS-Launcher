// Host harness for the pure pixel-size logic. Stubs stand in for the GL state the
// real translation unit reaches; the tables themselves are the real ones.
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <GL/gl.h>
#include <GL/glext.h>

#include "gl/pixel.h"
#include "gl/mg.h"

// The externals gl/pixel.cpp reaches for. The tables under test are the real
// ones -- this links gl/pixel.cpp rather than a copy of it, so the test cannot
// drift away from the code it checks.
gl_state_s g_default_gl_state{};
thread_local gl_state_t gl_state = &g_default_gl_state;
void mg_set_gl_error(GLenum) {}
extern "C" void write_log(const char*, ...) {}
int __android_log_print(int, const char*, const char*, ...) { return 0; }

static int fails = 0;
static void eq(const char* what, long got, long want) {
    if (got != want) { printf("  FAIL %-46s got %ld want %ld\n", what, got, want); ++fails; }
}

// GL 4.6 sec 8.4.4.1: k is the number of ELEMENTS per row.
//   k = n*l                     if s >= a
//   k = (a/s) * ceil(s*n*l/a)   if s < a
// Row bytes = k*s. n = components, s = component bytes, l = row length.
static long spec_row_bytes(long n, long s, long l, long a) {
    long k = (s >= a) ? n * l : (a / s) * ((s * n * l + a - 1) / a);
    return k * s;
}

int main() {
    printf("component/packed sizes\n");
    eq("gl_sizeof(UNSIGNED_BYTE)",              gl_sizeof(GL_UNSIGNED_BYTE), 1);
    eq("gl_sizeof(UNSIGNED_SHORT)",             gl_sizeof(GL_UNSIGNED_SHORT), 2);
    eq("gl_sizeof(FLOAT)",                      gl_sizeof(GL_FLOAT), 4);
    eq("gl_sizeof(UNSIGNED_INT_24_8)",          gl_sizeof(GL_UNSIGNED_INT_24_8), 4);
    eq("gl_sizeof(10F_11F_11F_REV)",            gl_sizeof(GL_UNSIGNED_INT_10F_11F_11F_REV), 4);
    eq("gl_sizeof(5_9_9_9_REV)",                gl_sizeof(GL_UNSIGNED_INT_5_9_9_9_REV), 4);
    eq("gl_sizeof(FLOAT_32_UNSIGNED_INT_24_8_REV)", gl_sizeof(GL_FLOAT_32_UNSIGNED_INT_24_8_REV), 8);

    printf("format enums are not in the type table\n");
    eq("gl_sizeof(GL_DEPTH_COMPONENT) rejected", gl_sizeof(GL_DEPTH_COMPONENT), 0);
    eq("gl_sizeof(GL_ALPHA) rejected",           gl_sizeof(GL_ALPHA), 0);
    eq("gl_sizeof(GL_LUMINANCE_ALPHA) rejected", gl_sizeof(GL_LUMINANCE_ALPHA), 0);

    printf("internalformats are not in the format table\n");
    eq("pixel_sizeof(GL_R32F,FLOAT) rejected",   pixel_sizeof(GL_R32F, GL_FLOAT), 0);
    eq("pixel_sizeof(GL_RGBA8,UBYTE) rejected",  pixel_sizeof(GL_RGBA8, GL_UNSIGNED_BYTE), 0);

    printf("bytes per pixel\n");
    eq("RGBA/UNSIGNED_BYTE",                    pixel_sizeof(GL_RGBA, GL_UNSIGNED_BYTE), 4);
    eq("RGB/UNSIGNED_BYTE",                     pixel_sizeof(GL_RGB, GL_UNSIGNED_BYTE), 3);
    eq("RGB/UNSIGNED_SHORT_5_6_5 (packed)",     pixel_sizeof(GL_RGB, GL_UNSIGNED_SHORT_5_6_5), 2);
    eq("RGBA/UNSIGNED_INT_8_8_8_8 (packed)",    pixel_sizeof(GL_RGBA, GL_UNSIGNED_INT_8_8_8_8), 4);
    eq("RGBA_INTEGER/UNSIGNED_INT",             pixel_sizeof(GL_RGBA_INTEGER, GL_UNSIGNED_INT), 16);
    eq("RED_INTEGER/UNSIGNED_INT",              pixel_sizeof(GL_RED_INTEGER, GL_UNSIGNED_INT), 4);
    eq("RGB/10F_11F_11F_REV (packed)",          pixel_sizeof(GL_RGB, GL_UNSIGNED_INT_10F_11F_11F_REV), 4);
    eq("DEPTH_STENCIL/UNSIGNED_INT_24_8",       pixel_sizeof(GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8), 4);
    eq("DEPTH_STENCIL/F32_UI24_8_REV",          pixel_sizeof(GL_DEPTH_STENCIL, GL_FLOAT_32_UNSIGNED_INT_24_8_REV), 8);
    eq("BGRA/UNSIGNED_BYTE",                    pixel_sizeof(GL_BGRA, GL_UNSIGNED_BYTE), 4);
    eq("GREEN_INTEGER/UNSIGNED_BYTE",           pixel_sizeof(GL_GREEN_INTEGER, GL_UNSIGNED_BYTE), 1);

    printf("widthalign against the spec row formula\n");
    struct { GLenum fmt, type; long n, s; } cases[] = {
        {GL_RGB,  GL_UNSIGNED_BYTE,  3, 1}, {GL_RGBA, GL_UNSIGNED_BYTE,  4, 1},
        {GL_RGB,  GL_UNSIGNED_SHORT, 3, 2}, {GL_RG,   GL_FLOAT,          2, 4},
        {GL_RED,  GL_UNSIGNED_BYTE,  1, 1}, {GL_RGBA, GL_UNSIGNED_SHORT, 4, 2},
    };
    for (auto& c : cases)
        for (long a : {1L, 2L, 4L, 8L})
            for (long l = 1; l <= 17; ++l) {
                long got  = (long)widthalign((uintptr_t)(l * pixel_sizeof(c.fmt, c.type)), (uintptr_t)a);
                long want = spec_row_bytes(c.n, c.s, l, a);
                if (got != want) {
                    printf("  FAIL fmt=0x%x type=0x%x l=%ld a=%ld: got %ld want %ld\n",
                           c.fmt, c.type, l, a, got, want);
                    ++fails;
                }
            }

    printf("widthalign degenerate alignments\n");
    eq("align 0 returns the width",  (long)widthalign((uintptr_t)7, (uintptr_t)0), 7);
    eq("align 3 (not pow2) passes",  (long)widthalign((uintptr_t)7, (uintptr_t)3), 7);
    eq("align 1 is identity",        (long)widthalign((uintptr_t)7, (uintptr_t)1), 7);

    printf("\n%s (%d failures)\n", fails ? "FAILED" : "all checks passed", fails);
    return fails != 0;
}
