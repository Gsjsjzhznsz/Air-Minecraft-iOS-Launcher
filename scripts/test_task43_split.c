// test_task43_split.c — Task 43 分体架构测试（最高保真模拟设备）
//
// 设备真实布局：App 可执行文件编译进了 shaderc_sandbox.m（fork server 用），
// libshaderc.dylib shim 里【另有一份】shaderc_sandbox.m 副本（各自独立 static
// 状态），两者唯一的桥 = setenv/getenv(AME_SB_FORK_FD)。本测试在 Linux 上
// 1:1 复刻：
//   exe  = test43_split（链接 Natives/shaderc_sandbox.m —— exe 侧副本）
//   shim = lib43shim.so（shaderc_shim.c + shaderc_sandbox.m —— dylib 侧副本）
// 验证：exe 侧 fork → env 桥接 → shim 侧收养 fd → 沙箱编译 → 缓存命中。
//
// 构建：见 scripts/task43_build_and_test.sh
// 运行：LD_LIBRARY_PATH=<假 impl 目录> POJAV_HOME=<可写目录> ./test43_split

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "shaderc_sandbox.h" // exe 侧副本（fork server API）

typedef void *(*init_fn)(void);
typedef void *(*compile_fn)(void *, const char *, size_t, int, const char *, const char *, void *);
typedef int (*status_fn)(void *);
typedef const char *(*bytes_fn)(void *);
typedef size_t (*len_fn)(void *);
typedef void (*release_fn)(void *);
typedef void *(*opt_init_fn)(void);
typedef void (*opt_set_env_fn)(void *, int, unsigned);
typedef void (*opt_release_fn)(void *);

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "[TEST-FAIL] %s (line %d)\n", msg, __LINE__);  \
            exit(1);                                                        \
        }                                                                   \
        fprintf(stderr, "[TEST-PASS] %s\n", msg);                           \
    } while (0)

int main(void) {
    // 1. exe 侧 fork server（shim 尚未加载——与设备时序一致）
    CHECK(ame_sb_fork_server_early() == 0, "exe-side fork server online");
    CHECK(getenv("AME_SB_FORK_FD") != NULL, "env bridge set by exe side");

    // 2. 加载 shim（独立副本；内部 static 与 exe 侧互不相通）
    void *shim = dlopen("./lib43shim.so", RTLD_NOW);
    CHECK(shim != NULL, "shim dylib loaded");
    init_fn comp_init = (init_fn)dlsym(shim, "shaderc_compiler_initialize");
    compile_fn compile = (compile_fn)dlsym(shim, "shaderc_compile_into_spv");
    status_fn status = (status_fn)dlsym(shim, "shaderc_result_get_compilation_status");
    bytes_fn spv_bytes = (bytes_fn)dlsym(shim, "shaderc_result_get_spv_bytes");
    len_fn spv_len = (len_fn)dlsym(shim, "shaderc_result_get_spv_length");
    release_fn result_release = (release_fn)dlsym(shim, "shaderc_result_release");
    opt_init_fn options_init = (opt_init_fn)dlsym(shim, "shaderc_compile_options_initialize");
    opt_set_env_fn opt_env = (opt_set_env_fn)dlsym(shim, "shaderc_compile_options_set_target_env");
    opt_release_fn options_release = (opt_release_fn)dlsym(shim, "shaderc_compile_options_release");
    CHECK(comp_init && compile && status && spv_bytes && spv_len && result_release &&
              options_init && opt_env && options_release,
          "all shim symbols resolved");

    void *compiler = comp_init();
    void *options = options_init();
    opt_env(options, 0, 4202496);

    // 3. 经 shim 编译（shim 侧应打印 "adopted early-fork helper"）
    const char *src = "void main() { vec4 v = vec4(1.0); }";
    void *r1 = compile(compiler, src, strlen(src), 0, "split/test", "main", options);
    CHECK(r1 != NULL, "split compile #1 non-NULL");
    CHECK(status(r1) == 0, "split compile #1 status=0 (via env-adopted fork child)");
    char expect[512];
    snprintf(expect, sizeof expect, "SPV:0:%s", src);
    CHECK(spv_len(r1) == strlen(expect) && memcmp(spv_bytes(r1), expect, spv_len(r1)) == 0,
          "split compile #1 bytes exact");
    result_release(r1);

    // 4. 二次编译：缓存命中（shim 侧缓存）
    void *r2 = compile(compiler, src, strlen(src), 0, "split/test", "main", options);
    CHECK(r2 != NULL && status(r2) == 0, "split compile #2 status=0");
    CHECK(spv_len(r2) == strlen(expect) && memcmp(spv_bytes(r2), expect, spv_len(r2)) == 0,
          "split compile #2 cache HIT identical");
    result_release(r2);

    options_release(options);
    fprintf(stderr, "\n=== ALL TASK43 SPLIT-ARCH TESTS PASSED ===\n");
    return 0;
}
