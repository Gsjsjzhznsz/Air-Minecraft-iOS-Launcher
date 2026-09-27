// task186_cutin_test.c -- Task186 vgpu shader_conv_ 插入点跟随实际版本行 单测
// 复刻 pack/shaderconv.c 的定位分支（new_version 精确命中 / 实际 #version 行 /
// 无版本行回落 0），验证三种输入形态的 cut_in_offset 取值。
// 编译：gcc -O2 -Wall -fsanitize=address -o /tmp/task186_cutin_test scripts/task186_cutin_test.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static const char *new_version = "#version 320 es";

// ---- 与 pack/shaderconv.c Task186 修改逐字同构的定位逻辑 ----
static int compute_cut_in_offset(const char *converted) {
    int cut_in_offset = -1;
    char *ptr_offset = strstr(converted, new_version);
    if (ptr_offset) {
        // 旧路径：320 会话精确命中（保持原行为，含 +2 跳 "\n\n" 的历史习惯）
        cut_in_offset = ptr_offset + strlen(new_version) + 2 - converted;
    } else {
        // Task186：跟随实际 #version 行
        char *ptr_version = strstr(converted, "#version");
        if (ptr_version != NULL) {
            while (*ptr_version != '\0' && *ptr_version != '\n') { ptr_version++; }
            if (*ptr_version == '\n') { ptr_version++; }
            cut_in_offset = (int)(ptr_version - converted);
        } else {
            cut_in_offset = 0;
        }
    }
    return cut_in_offset;
}

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } else { printf("ok:   %s\n", msg); } } while (0)

int main(void) {
    // 用例 1：Task183 后的 300es 会话形态（GLSLHeader 已改写）——核心病灶
    // 期望 offset 落在版本行之后（= strlen("#version 300 es\n") = 16），
    // 而不是回归前的 0。
    {
        const char *s = "#version 300 es\n\nuniform mat4 mvp;\nvoid main() { gl_Position = mvp * vec4(1.0); }\n";
        int off = compute_cut_in_offset(s);
        CHECK(off == 16, "300es session: offset lands after the version line (16), not 0");
        CHECK(off > 0 && s[off] != '#', "300es session: insertion target is not before #version");
    }
    // 用例 2：310es 会话形态
    {
        const char *s = "#version 310 es\nprecision highp float;\nvoid main() {}\n";
        int off = compute_cut_in_offset(s);
        CHECK(off == 16, "310es session: offset after version line");
    }
    // 用例 3：320es 会话（new_version 精确命中）——旧路径零回归
    {
        const char *s = "#version 320 es\n\nvoid main() {}\n";
        int off = compute_cut_in_offset(s);
        // ptr + strlen("#version 320 es") + 2：跳过版本串 + "\n\n" 两个字符 → 19
        CHECK(off == (int)strlen(new_version) + 2, "320es session: legacy exact-match path preserved");
    }
    // 用例 4：无版本行（ConvertShader 头部缺失的理论形态）→ 回落 0
    {
        const char *s = "uniform mat4 mvp;\nvoid main() {}\n";
        int off = compute_cut_in_offset(s);
        CHECK(off == 0, "no version line: falls back to 0");
    }
    // 用例 5：版本行后紧跟代码（无空行）——offset = 行尾后第一字符
    {
        const char *s = "#version 300 es\nvoid main() {}\n";
        int off = compute_cut_in_offset(s);
        CHECK(off == 16 && s[off] == 'v', "version line directly followed by code");
    }
    // 用例 6：模拟白屏病灶的完整插入——"out mediump vec4 FragColor;" 插到
    // 计算出的 offset 后，验证首行仍是 #version（回归前会插到 0 位破坏版本行）
    {
        const char *s = "#version 300 es\n\nuniform sampler2D tex;\nvoid main() { gl_FragColor = texture(tex, vec2(0.5)); }\n";
        int off = compute_cut_in_offset(s);
        const char *ins = "out mediump vec4 FragColor;\n";
        char *out = malloc(strlen(s) + strlen(ins) + 1);
        memcpy(out, s, off);
        memcpy(out + off, ins, strlen(ins));
        strcpy(out + off + strlen(ins), s + off);
        CHECK(strncmp(out, "#version 300 es\n", 16) == 0, "after insertion the #version line is still the first statement");
        CHECK(strstr(out, "out mediump vec4 FragColor;\n") == out + off, "out declaration inserted after version line");
        free(out);
    }

    printf("\n%s (%d failures)\n", failures ? "TEST FAILED" : "ALL TESTS PASSED", failures);
    return failures ? 1 : 0;
}
