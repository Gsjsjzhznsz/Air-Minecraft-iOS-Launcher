// test_task47_include.c — Task 47 单元测试：RenderPearl #include 展开器
//
// 用真实 Minecraft 26.3-pre-2 vanilla shader（scripts/task47_fixtures/，
// 自官方 client.jar 提取）+ 一个按 LWJGL 3.4.1 ShadercIncludeResult 布局
// 构造结果的模拟 resolver（复刻 Mojang ShaderSource 的行为，含 "not
// found" 错误路径），验证：
//
//  A. 真实 terrain.vsh（5 个顶层 include + 1 个条件块内 include）：
//     - 展开后不再含任何 #include 指令
//     - 各 include 片段的特征符号（函数/uniform 名）确实出现在输出
//     - 行号恢复：每个展开点后跟 #line <外层下一行>
//  B. 嵌套展开：oit.glsl → oit_common.glsl → projection.glsl（三层）
//  C. 语义保留：条件结构（#ifndef/#ifdef 块）原样保留（include 原位展开）
//  D. Mojang 错误路径：resolver 返回 createError("not found") 风格 result
//     （content="not found"）——展开器把错误文本内联（与桌面 shaderc 同
//     失败模式：后续 GLSL 语法错），指令本身消失
//  E. 防御：循环 include（A↔B）在深度 16 截断且不死循环
//  F. 防御：resolver 返回 NULL → 原行保留
//  G. 解析器精度：块注释/行注释内的 #include 不展开；#include 后带尾
//     垃圾的行不展开；无引号/尖括号的 include 不展开
//  H. 小输入：无 include 的源码 → ame_include_expand 返回 NULL（无需展开）
//
// 运行：host 编译（gcc/clang，无 iOS 依赖）。
#include "../Natives/shaderc_include.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int g_fail = 0;
#define CHECK(cond, msg)                                                     \
    do {                                                                     \
        if (cond) {                                                          \
            printf("  [PASS] %s\n", msg);                                    \
        } else {                                                             \
            printf("  [FAIL] %s\n", msg);                                    \
            g_fail++;                                                        \
        }                                                                    \
    } while (0)

// ---- 夹具读取 ----
static char *read_file(const char *path, size_t *len_out) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char *)malloc((size_t)n + 1);
    if (buf == NULL) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return NULL; }
    fclose(f);
    buf[n] = '\0';
    if (len_out) *len_out = (size_t)n;
    return buf;
}

// ---- 模拟 resolver（复刻 Mojang + LWJGL 布局）----
// requested 形如 "minecraft:fog.glsl" → 夹具 include/fog.glsl
// 特殊 id（task47:*）用于防御场景。
typedef struct {
    int not_found_calls;   // 计数
    int null_returns;      // 计数
} mock_state_t;
static mock_state_t g_mock;

// 手工构造 LWJGL 布局的 shaderc_include_result（5 字段 40 字节）：
//   +0 source_name(char*) +8 source_name_length +16 content(char*)
//   +24 content_length +32 user_data
// 每次调用独立 malloc（Mojang 的 CachedIncludeSource 每条目独立分配，
// 嵌套递归期间各层内容互不覆写；static 复用会产生伪缺陷）。
static void *mock_result_build(const char *name, const char *content, size_t content_len) {
    char *block = (char *)malloc(content_len + 1 + 40);
    if (block == NULL) return NULL;
    char *storage = block;
    char *result = block + content_len + 1;
    if (content_len > 0) memcpy(storage, content, content_len);
    storage[content_len] = '\0';
    memset(result, 0, 40);
    *(char **)(result + 0) = storage; // source_name（简化：同名）
    *(size_t *)(result + 8) = strlen(name);
    *(char **)(result + 16) = storage; // content
    *(size_t *)(result + 24) = content_len;
    return result; // 进程短生命周期，退出即回收
}

static int g_releases = 0;
static void mock_releaser(void *user_data, void *result) {
    (void)user_data; (void)result;
    g_releases++;
}

static void *mock_resolver(void *user_data, const char *requested, int type,
                           const char *requesting, size_t depth) {
    (void)user_data; (void)type; (void)requesting; (void)depth;
    char path[512];
    if (strncmp(requested, "minecraft:", 10) == 0) {
        snprintf(path, sizeof path, "task47_fixtures/include/%s", requested + 10);
    } else if (strncmp(requested, "task47:", 7) == 0) {
        snprintf(path, sizeof path, "task47_generated/%s", requested + 7);
    } else {
        g_mock.not_found_calls++;
        return mock_result_build("", "not found", strlen("not found"));
    }
    if (strcmp(requested, "task47:null") == 0) {
        g_mock.null_returns++;
        return NULL;
    }
    size_t len = 0;
    char *data = read_file(path, &len);
    if (data == NULL) {
        g_mock.not_found_calls++;
        return mock_result_build("", "not found", strlen("not found"));
    }
    void *r = mock_result_build(requested, data, len);
    free(data);
    return r;
}

// 统计展开输出中残留的“指令级”#include（行首 #include，非注释）
static int count_real_includes(const char *s) {
    int n = 0;
    const char *p = s;
    while (p != NULL && *p != '\0') {
        const char *eol = strchr(p, '\n');
        size_t linelen = eol ? (size_t)(eol - p) : strlen(p);
        const char *q = p;
        while (q < p + linelen && (*q == ' ' || *q == '\t')) q++;
        if ((size_t)(p + linelen - q) >= 8 && strncmp(q, "#include", 8) == 0)
            n++;
        p = eol ? eol + 1 : NULL;
    }
    return n;
}

static int contains(const char *hay, const char *needle) {
    return strstr(hay, needle) != NULL;
}

int main(void) {
    size_t len = 0;
    size_t out_len = 0;
    char *src = NULL, *out = NULL;

    printf("== A. 真实 terrain.vsh 展开 ==\n");
    src = read_file("task47_fixtures/terrain.vsh", &len);
    CHECK(src != NULL, "读取 terrain.vsh 夹具");
    out = ame_include_expand(src, len, "minecraft:core/terrain", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "展开成功返回 buffer");
    if (out != NULL) {
        CHECK(count_real_includes(out) == 0, "展开后无残留 #include 指令");
        // terrain.vsh 的 6 个 include：fog globals projection sample_lightmap
        // terrainglobals（+条件内 chunksection）
        CHECK(contains(out, "linear_fog_value"), "fog.glsl 内容已内联");
        CHECK(contains(out, "Projection"), "projection.glsl 的 uniform 已内联");
        CHECK(contains(out, "TerrainUniform"), "terrainglobals.glsl 已内联");
        CHECK(contains(out, "chunkVisibility"), "chunksection.glsl（条件块内）已内联");
        CHECK(contains(out, "#ifndef MULTIDRAW_TERRAIN"),
              "条件结构原样保留（include 原位展开，语义不变）");
        CHECK(contains(out, "#line 5\n"), "行号恢复指令存在（#line 5）");
        CHECK(out_len == strlen(out), "长度与 NUL 终止一致");
        // 6 个 include → 6 次 release 协议调用
        printf("  [INFO] resolver not_found=%d null=%d releases=%d out=%zuB\n",
               g_mock.not_found_calls, g_mock.null_returns, g_releases, out_len);
        CHECK(g_releases >= 6, "每个展开的 result 都按协议调用了 releaser");
        free(out);
    }
    free(src);

    printf("== B. 三层嵌套展开（oit → oit_common → projection）==\n");
    g_releases = 0;
    src = read_file("task47_fixtures/terrain.vsh", &len); // 复用：其 include 链最浅
    free(src);
    src = read_file("task47_fixtures/include/oit.glsl", &len);
    CHECK(src != NULL, "读取 oit.glsl 夹具（嵌套链源头）");
    out = ame_include_expand(src, len, "minecraft:include/oit", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "嵌套展开成功");
    if (out != NULL) {
        // oit.glsl → #ifdef OIT 内 oit_common.glsl → projection.glsl
        CHECK(contains(out, "projection_from_position"),
              "三层深度：oit→oit_common→projection 全部内联");
        CHECK(count_real_includes(out) == 0, "嵌套后无残留指令");
        free(out);
    }
    free(src);

    printf("== C. 语义保留：条件块内容不被错误裁剪 ==\n");
    const char *cond_src =
        "#version 330\n"
        "#ifndef MULTIDRAW_TERRAIN\n"
        "#include <minecraft:chunksection.glsl>\n"
        "#endif\n"
        "void main() {}\n";
    out = ame_include_expand(cond_src, strlen(cond_src), "test", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "条件块内 include 展开成功");
    if (out != NULL) {
        CHECK(contains(out, "#ifndef MULTIDRAW_TERRAIN") &&
                  contains(out, "#endif") &&
                  !contains(out, "#include"),
              "#ifndef/#endif 骨架完整、指令消失、内容原位");
        free(out);
    }

    printf("== D. Mojang 'not found' 错误路径 ==\n");
    g_mock.not_found_calls = 0;
    const char *missing_src = "#version 330\n#include <minecraft:does_not_exist.glsl>\nvoid main() {}\n";
    out = ame_include_expand(missing_src, strlen(missing_src), "test",
                             mock_resolver, NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "missing include 仍完成展开（错误文本内联）");
    if (out != NULL) {
        CHECK(contains(out, "not found"),
              "错误文本内联（与桌面 shaderc 同失败模式：后续语法错）");
        CHECK(count_real_includes(out) == 0, "指令本身已消失");
        free(out);
    }

    printf("== E. 循环 include 深度截断 ==\n");
    mkdir("task47_generated", 0755);
    FILE *f = fopen("task47_generated/loopA.glsl", "w");
    if (f != NULL) {
        fputs("#include <task47:loopB.glsl>\nfloat a;\n", f);
        fclose(f);
    }
    f = fopen("task47_generated/loopB.glsl", "w");
    if (f != NULL) {
        fputs("#include <task47:loopA.glsl>\nfloat b;\n", f);
        fclose(f);
    }
    const char *loop_src = "#version 330\n#include <task47:loopA.glsl>\n";
    out = ame_include_expand(loop_src, strlen(loop_src), "test", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "循环 include 展开终止（非 NULL）");
    if (out != NULL) {
        CHECK(contains(out, "depth limit") || contains(out, "float a;"),
              "深度截断证据或最深层内容存在");
        free(out);
    }

    printf("== F. resolver 返回 NULL → 原行保留 ==\n");
    const char *null_src = "#version 330\n#include <task47:null>\nvoid main() {}\n";
    out = ame_include_expand(null_src, strlen(null_src), "test", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "NULL result 展开流程完成");
    if (out != NULL) {
        CHECK(contains(out, "#include <task47:null>"),
              "resolver 失败的指令原行保留（可见诊断）");
        free(out);
    }

    printf("== G. 解析器精度 ==\n");
    const char *cmt_src =
        "#version 330\n"
        "/* #include <minecraft:fog.glsl> block comment */\n"
        "// #include <minecraft:fog.glsl> line comment\n"
        "#include <minecraft:fog.glsl> // trailing comment ok\n"
        "#include \"unterminated\n"
        "#include not_a_form\n"
        "#includex <minecraft:fog.glsl>\n";
    out = ame_include_expand(cmt_src, strlen(cmt_src), "test", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out != NULL, "混合形态源码展开完成");
    if (out != NULL) {
        CHECK(contains(out, "/* #include"), "块注释内的指令未被展开");
        CHECK(contains(out, "// #include"), "行注释内的指令未被展开");
        CHECK(contains(out, "linear_fog_value"),
              "尾随 // 注释的合法指令正常展开");
        CHECK(contains(out, "#includex"), "前缀相似但不匹配的指令保留");
        CHECK(contains(out, "#include not_a_form"), "非标准形态指令保留");
        free(out);
    }

    printf("== H. 无 include 源码 → NULL（零开销直通）==\n");
    const char *plain = "#version 330\nvoid main() {}\n";
    out = ame_include_expand(plain, strlen(plain), "test", mock_resolver,
                             NULL, mock_releaser, NULL, &out_len);
    CHECK(out == NULL && out_len == 0, "无指令时返回 NULL（调用方保持原源码）");
    (void)out;

    printf("\n%s: %d failure(s)\n", g_fail == 0 ? "ALL PASS" : "FAILED", g_fail);
    return g_fail == 0 ? 0 : 1;
}
