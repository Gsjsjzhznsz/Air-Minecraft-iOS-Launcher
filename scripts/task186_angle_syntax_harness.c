// task186_angle_syntax_harness.c -- 提取 tinygl4angle.c 本轮新增矩阵族区块
// + 其宏环境（LOOKUP_FUNC/ame182_resolve 签名）做独立编译级语法/语义检查。
// Linux 无 iOS SDK/ObjC runtime，整文件不可编译；新增区块为纯 C，可独立验证。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "GL/gl.h"
#include "GL/glext.h"

// ---- 环境复刻（与 tinygl4angle.c 同构）----
static void *ame182_resolve(const char *name) { (void)name; return (void *)1; }
#define LOOKUP_FUNC(func) \
    if (!gles_##func) { \
        gles_##func = ame182_resolve(#func); \
    }

// ==== 以下为 tinygl4angle.c Task186 区块逐字拷贝 ====
static int ame186_transposeLogged = 0;
#define AME186_MATRIX_FN(FN, COLS, ROWS) \
void (*gles_##FN)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value); \
void FN(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { \
    LOOKUP_FUNC(FN) \
    if (!gles_##FN) return; \
    if (transpose == GL_FALSE || value == NULL || count <= 0) { \
        gles_##FN(location, count, transpose, value); \
        return; \
    } \
    const GLsizei ame186_n = (COLS) * (ROWS); \
    GLfloat ame186_stack[16]; \
    GLfloat *ame186_buf = ame186_stack; \
    int ame186_heap = 0; \
    if ((size_t)count * (size_t)ame186_n > 16) { \
        ame186_buf = (GLfloat *)malloc(((size_t)count * (size_t)ame186_n) * sizeof(GLfloat)); \
        if (ame186_buf == NULL) { \
            gles_##FN(location, count, transpose, value); \
            return; \
        } \
        ame186_heap = 1; \
    } \
    for (GLsizei ame186_m = 0; ame186_m < count; ++ame186_m) { \
        const GLfloat *ame186_src = value + (size_t)ame186_m * (size_t)ame186_n; \
        GLfloat *ame186_dst = ame186_buf + (size_t)ame186_m * (size_t)ame186_n; \
        for (int ame186_c = 0; ame186_c < (COLS); ++ame186_c) { \
            for (int ame186_r = 0; ame186_r < (ROWS); ++ame186_r) { \
                ame186_dst[ame186_c * (ROWS) + ame186_r] = ame186_src[ame186_r * (COLS) + ame186_c]; \
            } \
        } \
    } \
    if (ame186_transposeLogged < 4) { \
        ++ame186_transposeLogged; \
        printf("[tinygl4angle] Task186 %s transpose=TRUE -> locally transposed %dx%d x%ld matrix/matrices (ES requires column-major; dropped call was the black-content suspect)\n", \
               #FN, (COLS), (ROWS), (long)count); \
    } \
    gles_##FN(location, count, GL_FALSE, ame186_buf); \
    if (ame186_heap) free(ame186_buf); \
}
AME186_MATRIX_FN(glUniformMatrix2fv, 2, 2)
AME186_MATRIX_FN(glUniformMatrix3fv, 3, 3)
AME186_MATRIX_FN(glUniformMatrix4fv, 4, 4)
AME186_MATRIX_FN(glUniformMatrix2x3fv, 2, 3)
AME186_MATRIX_FN(glUniformMatrix3x2fv, 3, 2)
AME186_MATRIX_FN(glUniformMatrix2x4fv, 2, 4)
AME186_MATRIX_FN(glUniformMatrix4x2fv, 4, 2)
AME186_MATRIX_FN(glUniformMatrix3x4fv, 3, 4)
AME186_MATRIX_FN(glUniformMatrix4x3fv, 4, 3)
// ==== Task186 区块结束 ====

// ---- 链接级验证：九个符号确实生成 ----
#define SYM_CHECK(fn) do { \
    void (*probe)() = (void (*)())fn; \
    if (!probe) return 2; \
} while (0)

int main(void) {
    SYM_CHECK(glUniformMatrix2fv);
    SYM_CHECK(glUniformMatrix3fv);
    SYM_CHECK(glUniformMatrix4fv);
    SYM_CHECK(glUniformMatrix2x3fv);
    SYM_CHECK(glUniformMatrix3x2fv);
    SYM_CHECK(glUniformMatrix2x4fv);
    SYM_CHECK(glUniformMatrix4x2fv);
    SYM_CHECK(glUniformMatrix3x4fv);
    SYM_CHECK(glUniformMatrix4x3fv);
    printf("all 9 matrix family symbols compiled and linked\n");
    return 0;
}
