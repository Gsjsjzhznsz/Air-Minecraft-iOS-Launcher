// task186_matrix_test.c -- Task186 glUniformMatrix*fv 转置桥数学正确性单测
// 提取 tinygl4angle.c 宏的核心转置循环，用已知矩阵验证行主序→列主序映射。
// 编译：gcc -O2 -Wall -fsanitize=address -o /tmp/task186_matrix_test scripts/task186_matrix_test.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// ---- 与 tinygl4angle.c AME186_MATRIX_FN 相同的转置核心（逐字提取，
//      仅 src/dst 基指针名对齐测试局部变量 value/buf） ----
#define TRANSPOSE_ONE(COLS, ROWS) \
    for (int m = 0; m < count; ++m) { \
        const float *src = value + (size_t)m * (size_t)((COLS)*(ROWS)); \
        float *dst = buf + (size_t)m * (size_t)((COLS)*(ROWS)); \
        for (int c = 0; c < (COLS); ++c) { \
            for (int r = 0; r < (ROWS); ++r) { \
                dst[c * (ROWS) + r] = src[r * (COLS) + c]; \
            } \
        } \
    }

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } else { printf("ok:   %s\n", msg); } } while (0)

int main(void) {
    // ---- 用例 1：glUniformMatrix4fv（4 列 4 行），行主序输入 ----
    // 行主序（desktop transpose=TRUE）矩阵：
    //   1  2  3  4
    //   5  6  7  8
    //   9 10 11 12
    //  13 14 15 16
    // 期望列主序输出（ES transpose=FALSE 语义，同一矩阵）：
    //   col0=(1,5,9,13) col1=(2,6,10,14) col2=(3,7,11,15) col3=(4,8,12,16)
    {
        const float value[16] = {1,2,3,4, 5,6,7,8, 9,10,11,12, 13,14,15,16};
        float buf[16];
        int count = 1;
        TRANSPOSE_ONE(4, 4)
        const float expect[16] = {1,5,9,13, 2,6,10,14, 3,7,11,15, 4,8,12,16};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "4x4 row-major -> column-major");
    }
    // ---- 用例 2：glUniformMatrix4fv 非对称置换（独立于用例 1 的数值路径） ----
    {
        const float value[16] = {0,1,0,0, 0,0,1,0, 1,0,0,0, 0,0,0,1};
        float buf[16];
        int count = 1;
        TRANSPOSE_ONE(4, 4)
        const float expect[16] = {0,0,1,0, 1,0,0,0, 0,1,0,0, 0,0,0,1};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "4x4 permutation values");
    }
    // ---- 用例 3：glUniformMatrix2x3fv（2 列 3 行）----
    // 行主序输入（3 行 × 每行 2 元素）；期望列主序 col0=(a,c,e) col1=(b,d,f)
    {
        const float value[6] = {'a','b','c','d','e','f'};
        float buf[6];
        int count = 1;
        TRANSPOSE_ONE(2, 3)
        const float expect[6] = {'a','c','e','b','d','f'};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "2x3 (2 cols 3 rows) layout");
    }
    // ---- 用例 4：glUniformMatrix3x2fv（3 列 2 行）----
    {
        const float value[6] = {'a','b','c','d','e','f'};
        float buf[6];
        int count = 1;
        TRANSPOSE_ONE(3, 2)
        const float expect[6] = {'a','d','b','e','c','f'};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "3x2 (3 cols 2 rows) layout");
    }
    // ---- 用例 5：count>1 批量（两个 4x4）----
    {
        const float value[32] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
                                 16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1};
        float buf[32];
        int count = 2;
        TRANSPOSE_ONE(4, 4)
        const float expect[32] = {1,5,9,13,2,6,10,14,3,7,11,15,4,8,12,16,
                                  16,12,8,4,15,11,7,3,14,10,6,2,13,9,5,1};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "batch count=2 4x4");
    }
    // ---- 用例 6：glUniformMatrix2x4fv（2 列 4 行）----
    {
        const float value[8] = {1,2, 3,4, 5,6, 7,8}; // 行主序 4 行×2 列
        float buf[8];
        int count = 1;
        TRANSPOSE_ONE(2, 4)
        const float expect[8] = {1,3,5,7, 2,4,6,8};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "2x4 (2 cols 4 rows) layout");
    }
    // ---- 用例 7：glUniformMatrix4x2fv（4 列 2 行）----
    {
        const float value[8] = {1,2,3,4, 5,6,7,8}; // 行主序 2 行×4 列
        float buf[8];
        int count = 1;
        TRANSPOSE_ONE(4, 2)
        const float expect[8] = {1,5, 2,6, 3,7, 4,8};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "4x2 (4 cols 2 rows) layout");
    }
    // ---- 用例 8：glUniformMatrix3x4fv（3 列 4 行）----
    {
        const float value[12] = {1,2,3,4,5,6,7,8,9,10,11,12}; // 行主序 4 行×3 列
        float buf[12];
        int count = 1;
        TRANSPOSE_ONE(3, 4)
        const float expect[12] = {1,4,7,10, 2,5,8,11, 3,6,9,12};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "3x4 (3 cols 4 rows) layout");
    }
    // ---- 用例 9：glUniformMatrix4x3fv（4 列 3 行）----
    {
        const float value[12] = {1,2,3,4,5,6,7,8,9,10,11,12}; // 行主序 3 行×4 列
        float buf[12];
        int count = 1;
        TRANSPOSE_ONE(4, 3)
        const float expect[12] = {1,5,9, 2,6,10, 3,7,11, 4,8,12};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "4x3 (4 cols 3 rows) layout");
    }
    // ---- 用例 10：glUniformMatrix2fv / 3fv（方阵小矩阵）----
    {
        const float value[4] = {1,2, 3,4};
        float buf[4];
        int count = 1;
        TRANSPOSE_ONE(2, 2)
        const float expect[4] = {1,3, 2,4};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "2x2 layout");
    }
    {
        const float value[9] = {1,2,3, 4,5,6, 7,8,9};
        float buf[9];
        int count = 1;
        TRANSPOSE_ONE(3, 3)
        const float expect[9] = {1,4,7, 2,5,8, 3,6,9};
        CHECK(memcmp(buf, expect, sizeof(expect)) == 0, "3x3 layout");
    }

    printf("\n%s (%d failures)\n", failures ? "TEST FAILED" : "ALL TESTS PASSED", failures);
    return failures ? 1 : 0;
}
