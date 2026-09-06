// test_task43_cache.c — Task 43 磁盘缓存 + 完整 shim 链路功能测试（Linux）
//
// 模式 A（默认，沙箱路径）：fork server + shim 编译转发器（shaderc_compile_into_spv
//   公开入口）→ 沙箱 → 假 impl → 成功落盘缓存；同输入二次编译 → 命中（HIT）；
//   不同输入 → 未命中；CRASHALWAYS → status=3 且【不】落盘。
// 模式 B（AME_SHADERC_SANDBOX_OFF=1，进程内路径）：假 impl 在进程内被直接调用
//   （shim 崩溃网罩住）→ CRASHONCE 触发父进程崩溃网重试 → 成功 → 落盘；
//   二次编译命中缓存 → 完全不触碰 impl。
//
// 构建：gcc -D_GNU_SOURCE -x c -I Natives scripts/test_task43_cache.c \
//         Natives/shaderc_shim.c Natives/shaderc_sandbox.m \
//         -o test43_cache -ldl -lpthread
// 运行：LD_LIBRARY_PATH=<假 impl 目录> POJAV_HOME=<可写目录> ./test43_cache
//       （模式 B 再加 AME_SHADERC_SANDBOX_OFF=1，POJAV_HOME 换新目录）

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "shaderc_sandbox.h"

// shim 公开 ABI（shaderc_shim.c 导出）
void *shaderc_compiler_initialize(void);
void *shaderc_compile_options_initialize(void);
void shaderc_compile_options_set_target_env(void *options, int env, unsigned version);
void shaderc_compile_options_set_optimization_level(void *options, int level);
void shaderc_compile_options_set_generate_debug_info(void *options, int enable);
void shaderc_compile_options_release(void *options);
void *shaderc_compile_into_spv(void *compiler, const char *source, size_t source_size,
                               int kind, const char *input_file, const char *entry_point,
                               void *options);
int shaderc_result_get_compilation_status(void *result);
const char *shaderc_result_get_spv_bytes(void *result);
size_t shaderc_result_get_spv_length(void *result);
const char *shaderc_result_get_error_message(void *result);
void shaderc_result_release(void *result);

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "[TEST-FAIL] %s (line %d)\n", msg, __LINE__);  \
            exit(1);                                                        \
        }                                                                   \
        fprintf(stderr, "[TEST-PASS] %s\n", msg);                           \
    } while (0)

static int count_cache_files(void) {
    const char *home = getenv("POJAV_HOME");
    char dir[4096];
    snprintf(dir, sizeof dir, "%s/ame_shaderc_cache", home);
    // 依赖 find？不——用 opendir 计数
    DIR *d = opendir(dir);
    if (d == NULL) return 0;
    int n = 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] != '.') ++n;
    }
    closedir(d);
    return n;
}

int main(void) {
    const char *home = getenv("POJAV_HOME");
    CHECK(home != NULL && *home != '\0', "POJAV_HOME set");
    CHECK(getenv("AME_SB_FORK_FD") == NULL, "fresh process (no stale env bridge)");

    int sandbox_mode = (getenv("AME_SHADERC_SANDBOX_OFF") == NULL);
    if (sandbox_mode) {
        CHECK(ame_sb_fork_server_early() == 0, "fork server online (mode A)");
    } else {
        CHECK(ame_sb_fork_server_early() == -1, "fork server skipped (mode B, OFF)");
    }

    void *compiler = shaderc_compiler_initialize();
    CHECK(compiler != NULL, "compiler initialized");
    void *options = shaderc_compile_options_initialize();
    CHECK(options != NULL, "options initialized");
    shaderc_compile_options_set_target_env(options, 0, 4202496);
    shaderc_compile_options_set_optimization_level(options, 0);
    shaderc_compile_options_set_generate_debug_info(options, 1);

    const char *src1 = "void main() { gl_Position = vec4(1.0); }";
    size_t s1len = strlen(src1);

    // ---- 第一次编译：MISS → 编译 → 落盘 ----
    void *r1 = shaderc_compile_into_spv(compiler, src1, s1len, 0, "minecraft:test/one",
                                        "main", options);
    CHECK(r1 != NULL, "compile #1 non-NULL");
    CHECK(shaderc_result_get_compilation_status(r1) == 0, "compile #1 status=0");
    size_t l1 = shaderc_result_get_spv_length(r1);
    CHECK(l1 > 0, "compile #1 has spv bytes");
    char b1[512];
    snprintf(b1, sizeof b1, "SPV:0:%s", src1);
    CHECK(l1 == strlen(b1) && memcmp(shaderc_result_get_spv_bytes(r1), b1, l1) == 0,
          "compile #1 spv echo exact");
    int files1 = count_cache_files();
    CHECK(files1 == 1, "cache stored exactly 1 entry after compile #1");
    shaderc_result_release(r1);

    // ---- 第二次编译（同输入）：HIT → 不触碰 impl ----
    void *r2 = shaderc_compile_into_spv(compiler, src1, s1len, 0, "minecraft:test/one",
                                        "main", options);
    CHECK(r2 != NULL, "compile #2 non-NULL");
    CHECK(shaderc_result_get_compilation_status(r2) == 0, "compile #2 status=0");
    size_t l2 = shaderc_result_get_spv_length(r2);
    CHECK(l2 == l1 && memcmp(shaderc_result_get_spv_bytes(r2), b1, l2) == 0,
          "compile #2 cache HIT returns identical bytes");
    CHECK(count_cache_files() == 1, "cache entry count unchanged on hit");
    shaderc_result_release(r2);

    // ---- 第三次编译（不同源码）：MISS → 编译 → 落盘 ----
    const char *src2 = "void main() { gl_Position = vec4(0.5); }";
    void *r3 = shaderc_compile_into_spv(compiler, src2, strlen(src2), 0,
                                        "minecraft:test/two", "main", options);
    CHECK(shaderc_result_get_compilation_status(r3) == 0, "compile #3 (new src) status=0");
    CHECK(count_cache_files() == 2, "cache now has 2 entries");
    shaderc_result_release(r3);

    // ---- 崩溃注入 ----
    // 模式 A（沙箱）：子进程 4 次重试后 status=3；模式 B（进程内）：崩溃网
    // 重试后 CRASHONCE 成功。两种模式下都验证"失败不落盘"或"成功落盘"。
    const char *crash_src = sandbox_mode ? "CRASHALWAYS void main() {}"
                                         : "CRASHONCE void main() {}";
    void *r4 = shaderc_compile_into_spv(compiler, crash_src, strlen(crash_src), 0,
                                        "minecraft:test/crash", "main", options);
    CHECK(r4 != NULL, "crash-inject compile non-NULL (never NULL to LWJGL)");
    int st4 = shaderc_result_get_compilation_status(r4);
    if (sandbox_mode) {
        CHECK(st4 == 3, "mode A: crash-always exhausts to status=3");
        CHECK(count_cache_files() == 2, "mode A: failure NOT cached");
    } else {
        CHECK(st4 == 0, "mode B: crash-once recovered by parent crash-net retry");
        CHECK(count_cache_files() == 3, "mode B: recovered success cached");
    }
    shaderc_result_release(r4);

    // ---- 崩溃注入后的同输入复编（模式 A 仍 miss；模式 B 应 HIT）----
    void *r5 = shaderc_compile_into_spv(compiler, crash_src, strlen(crash_src), 0,
                                        "minecraft:test/crash", "main", options);
    CHECK(r5 != NULL, "post-crash recompile non-NULL");
    shaderc_result_release(r5);

    shaderc_compile_options_release(options);

    fprintf(stderr, "\n=== ALL TASK43 CACHE TESTS PASSED (mode %s) ===\n",
            sandbox_mode ? "A:sandbox" : "B:in-process");
    return 0;
}
