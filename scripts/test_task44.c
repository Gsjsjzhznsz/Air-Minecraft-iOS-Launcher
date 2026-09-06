// test_task44.c — Task 44 新鲜线程重试链 + 崩溃网加固 + 源码转储 端到端测试（Linux，进程内路径）
//
// 场景（FAKE44_MODE 控制假 impl 崩溃语义，每场景独立进程跑）：
//   once     : 首次尝试崩 → 新鲜线程重试成功（RECOVERED on fresh-thread retry）
//              → 结果落缓存 → 同输入二编 HIT（不触碰 impl）→ 转储目录有精确源码
//   perthread: 首试崩（主线程）→ 新鲜线程重试也崩（每线程毒化）→ glslang 重建
//              → 重建后新鲜线程成功（RECOVERED via rebuild + fresh thread）→ 落缓存
//   always   : 三段全崩 → 合成失败（status=3，绝不 NULL）→ 失败不落缓存
//
// 构建：gcc -D_GNU_SOURCE -x c -I Natives scripts/test_task44.c \
//         Natives/shaderc_shim.c Natives/shaderc_sandbox.m \
//         -o /tmp/test44 -ldl -lpthread
// 运行：LD_LIBRARY_PATH=<假 impl 目录> POJAV_HOME=<可写目录> \
//         AME_SHADERC_SANDBOX_OFF=1 FAKE44_MODE=<once|perthread|always> ./test44

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
void shaderc_result_release(void *result);

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "[TEST-FAIL] %s (line %d)\n", msg, __LINE__);  \
            exit(1);                                                        \
        }                                                                   \
        fprintf(stderr, "[TEST-PASS] %s\n", msg);                           \
    } while (0)

static int count_dir_files(const char *dir, const char *suffix) {
    DIR *d = opendir(dir);
    if (d == NULL) return -1;
    int n = 0;
    struct dirent *de;
    size_t slen = suffix ? strlen(suffix) : 0;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.') continue;
        if (slen > 0) {
            size_t nl = strlen(de->d_name);
            if (nl < slen || strcmp(de->d_name + nl - slen, suffix) != 0) continue;
        }
        ++n;
    }
    closedir(d);
    return n;
}

// 读转储目录里唯一的 .src 文件，校验字节与源码一致
static int check_dump(const char *home, const char *src, size_t src_len) {
    char dir[4096], path[4096];
    snprintf(dir, sizeof dir, "%s/ame_shaderc_dump", home);
    int nsrc = count_dir_files(dir, ".src");
    int nmeta = count_dir_files(dir, ".meta");
    if (nsrc < 1 || nmeta < 1) return 0;
    // 找到唯一的 .src
    DIR *d = opendir(dir);
    if (d == NULL) return 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        size_t nl = strlen(de->d_name);
        if (nl > 4 && strcmp(de->d_name + nl - 4, ".src") == 0) {
            snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
            break;
        }
        de = NULL;
    }
    closedir(d);
    if (de == NULL) return 0;
    FILE *f = fopen(path, "rb");
    if (f == NULL) return 0;
    char buf[4096];
    size_t got = fread(buf, 1, sizeof buf, f);
    fclose(f);
    return got == src_len && memcmp(buf, src, src_len) == 0;
}

int main(void) {
    const char *home = getenv("POJAV_HOME");
    const char *mode = getenv("FAKE44_MODE");
    CHECK(home != NULL && *home != '\0', "POJAV_HOME set");
    CHECK(mode != NULL, "FAKE44_MODE set");
    CHECK(getenv("AME_SB_FORK_FD") == NULL, "fresh process (no stale env bridge)");
    CHECK(ame_sb_fork_server_early() == -1, "fork server skipped (in-process mode)");

    void *compiler = shaderc_compiler_initialize();
    CHECK(compiler != NULL, "compiler initialized");
    void *options = shaderc_compile_options_initialize();
    CHECK(options != NULL, "options initialized");
    shaderc_compile_options_set_target_env(options, 0, 4202496);
    shaderc_compile_options_set_optimization_level(options, 0);
    shaderc_compile_options_set_generate_debug_info(options, 1);

    const char *src1 = "void main() { gl_Position = vec4(1.0); }";
    size_t s1len = strlen(src1);
    char expect[512];
    snprintf(expect, sizeof expect, "SPV:%s", src1);

    if (strcmp(mode, "once") == 0 || strcmp(mode, "perthread") == 0) {
        // ---- 第一次编译：MISS → （崩溃链恢复）→ 成功 → 落盘 ----
        void *r1 = shaderc_compile_into_spv(compiler, src1, s1len, 0,
                                            "minecraft:test44/one", "main", options);
        CHECK(r1 != NULL, "compile #1 non-NULL (never NULL to LWJGL)");
        CHECK(shaderc_result_get_compilation_status(r1) == 0,
              "compile #1 status=0 (crash chain recovered)");
        size_t l1 = shaderc_result_get_spv_length(r1);
        CHECK(l1 == strlen(expect) &&
                  memcmp(shaderc_result_get_spv_bytes(r1), expect, l1) == 0,
              "compile #1 spv echo exact (recovered result intact)");
        shaderc_result_release(r1);

        char cache_dir[4096];
        snprintf(cache_dir, sizeof cache_dir, "%s/ame_shaderc_cache", home);
        CHECK(count_dir_files(cache_dir, NULL) == 1,
              "recovered success cached (exactly 1 entry)");

        // ---- 同输入二编：HIT（零 impl 触碰）----
        void *r2 = shaderc_compile_into_spv(compiler, src1, s1len, 0,
                                            "minecraft:test44/one", "main", options);
        CHECK(r2 != NULL && shaderc_result_get_compilation_status(r2) == 0,
              "compile #2 cache HIT (status=0)");
        size_t l2 = shaderc_result_get_spv_length(r2);
        CHECK(l2 == l1 && memcmp(shaderc_result_get_spv_bytes(r2), expect, l2) == 0,
              "compile #2 HIT bytes identical");
        shaderc_result_release(r2);

        // ---- 转储校验：miss 时已写入精确源码 ----
        CHECK(check_dump(home, src1, s1len),
              "source dump written with exact bytes (.src + .meta)");

        fprintf(stderr, "\n=== TASK44 TEST PASSED (mode=%s) ===\n", mode);
    } else if (strcmp(mode, "always") == 0) {
        // ---- 恒崩 shader：三段全崩 → 合成失败 ----
        void *r1 = shaderc_compile_into_spv(compiler, src1, s1len, 0,
                                            "minecraft:test44/always", "main", options);
        CHECK(r1 != NULL, "crash-always compile non-NULL (synthetic result)");
        CHECK(shaderc_result_get_compilation_status(r1) == 3,
              "crash-always status=3 internal_error");
        shaderc_result_release(r1);

        char cache_dir[4096];
        snprintf(cache_dir, sizeof cache_dir, "%s/ame_shaderc_cache", home);
        int n = count_dir_files(cache_dir, NULL);
        CHECK(n == 0, "failure NOT cached (0 entries)");
        // 转储仍在（miss 即转储，与编译成败无关）
        CHECK(count_dir_files(home, NULL) >= 0, "process alive after crash storm");

        fprintf(stderr, "\n=== TASK44 TEST PASSED (mode=always) ===\n");
    } else {
        CHECK(0, "unknown FAKE44_MODE (expect once|perthread|always)");
    }

    shaderc_compile_options_release(options);
    return 0;
}
