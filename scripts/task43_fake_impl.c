// task43_fake_impl.c — Task 43 测试用假 libshaderc_impl（Linux 端到端测试）
//
// 实现 shaderc_sandbox.m 子进程 dlsym 的全部入口。编译行为由源码前缀驱动：
//   "CRASHALWAYS ..." → 每次调用 SIGSEGV（测试子进程 4 次重试耗尽路径）
//   "CRASHONCE ..."   → 进程内首次调用 SIGSEGV，之后成功（测试崩溃恢复重试）
//   其它              → 成功，SPIR-V 字节 = "SPV:<kind>:<源码前 64 字节>"
// glslang::InitializeProcess/FinalizeProcess 符号按 impl 的真实 mangled 名导出
// （_ZN7glslang17InitializeProcessEv / _ZN7glslang15FinalizeProcessEv），
// 重建链路可被验证。
//
// 构建：gcc -shared -fPIC -D_GNU_SOURCE -x c task43_fake_impl.c \
//         -o libshaderc_impl.dylib -ldl
// 运行：测试主程序经 LD_LIBRARY_PATH 找到本文件（子进程 dlopen 兜底按
//         纯名 "libshaderc_impl.dylib" 解析）。

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int status;
    size_t len;
    char *bytes;
    char *err;
} fake_res_t;

static int g_crash_once_used = 0;
static int g_glslang_inits = 0;
static int g_glslang_finis = 0;

static void fake_log(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fflush(stderr);
}

void _ZN7glslang17InitializeProcessEv(void) {
    g_glslang_inits++;
    fake_log("[fake-impl] glslang::InitializeProcess #%d\n", g_glslang_inits);
}

void _ZN7glslang15FinalizeProcessEv(void) {
    g_glslang_finis++;
    fake_log("[fake-impl] glslang::FinalizeProcess #%d\n", g_glslang_finis);
}

void *shaderc_compiler_initialize(void) {
    static int handle = 0x1234;
    fake_log("[fake-impl] compiler_initialize\n");
    return (void *)&handle;
}

void shaderc_compiler_release(void *compiler) {
    fake_log("[fake-impl] compiler_release %p\n", compiler);
}

void *shaderc_compile_options_initialize(void) {
    fake_log("[fake-impl] options_initialize\n");
    return calloc(1, 32);
}

void *shaderc_compile_options_clone(const void *src) {
    (void)src;
    fake_log("[fake-impl] options_clone\n");
    return calloc(1, 32);
}

void shaderc_compile_options_release(void *options) {
    fake_log("[fake-impl] options_release %p\n", options);
    free(options);
}

void shaderc_compile_options_set_target_env(void *o, int env, unsigned v) {
    fake_log("[fake-impl] set_target_env %d %u\n", env, v);
}
void shaderc_compile_options_set_source_language(void *o, int v) {
    fake_log("[fake-impl] set_source_language %d\n", v);
}
void shaderc_compile_options_set_optimization_level(void *o, int v) {
    fake_log("[fake-impl] set_optimization_level %d\n", v);
}
void shaderc_compile_options_set_generate_debug_info(void *o, int v) {
    fake_log("[fake-impl] set_generate_debug_info %d\n", v);
}
void shaderc_compile_options_set_forced_version_profile(void *o, int v, int p) {
    fake_log("[fake-impl] set_forced_version_profile %d %d\n", v, p);
}
void shaderc_compile_options_add_macro_definition(void *o, const char *n, size_t nl,
                                                  const char *v, size_t vl) {
    fake_log("[fake-impl] add_macro %.*s\n", (int)(nl > 32 ? 32 : nl), n);
}

static void *fake_compile_common(void *compiler, const char *source, size_t source_size,
                                 int kind, const char *input_file, const char *entry_point,
                                 void *options) {
    (void)compiler;
    (void)options;
    (void)entry_point;
    fake_log("[fake-impl] compile in='%s' len=%zu kind=%d\n",
             input_file ? input_file : "?", source_size, kind);
    if (source_size >= 11 && memcmp(source, "CRASHALWAYS", 11) == 0) {
        fake_log("[fake-impl] SIGSEGV on demand (CRASHALWAYS)\n");
        volatile int *p = (int *)0;
        *p = 1; // SIGSEGV
    }
    if (source_size >= 9 && memcmp(source, "CRASHONCE", 9) == 0 && !g_crash_once_used) {
        g_crash_once_used = 1;
        fake_log("[fake-impl] SIGSEGV on demand (CRASHONCE first time)\n");
        volatile int *p = (int *)0;
        *p = 1; // SIGSEGV
    }
    fake_res_t *r = (fake_res_t *)calloc(1, sizeof *r);
    char buf[512];
    int n = snprintf(buf, sizeof buf, "SPV:%d:%.*s", kind,
                     (int)(source_size < 64 ? source_size : 64), source);
    r->status = 0;
    r->len = (size_t)n;
    r->bytes = strdup(buf);
    r->err = strdup("");
    return r;
}

void *shaderc_compile_into_spv(void *c, const char *s, size_t n, int k, const char *i,
                               const char *e, void *o) {
    return fake_compile_common(c, s, n, k, i, e, o);
}
void *shaderc_compile_into_spv_assembly(void *c, const char *s, size_t n, int k,
                                        const char *i, const char *e, void *o) {
    return fake_compile_common(c, s, n, k, i, e, o);
}
void *shaderc_compile_into_preprocessed_text(void *c, const char *s, size_t n, int k,
                                              const char *i, const char *e, void *o) {
    return fake_compile_common(c, s, n, k, i, e, o);
}

int shaderc_result_get_compilation_status(void *result) {
    return ((fake_res_t *)result)->status;
}
size_t shaderc_result_get_num_errors(void *result) {
    return ((fake_res_t *)result)->status ? 1 : 0;
}
size_t shaderc_result_get_num_warnings(void *result) {
    (void)result;
    return 0;
}
const char *shaderc_result_get_error_message(void *result) {
    return ((fake_res_t *)result)->err;
}
const char *shaderc_result_get_bytes(void *result) {
    return ((fake_res_t *)result)->bytes;
}
size_t shaderc_result_get_length(void *result) {
    return ((fake_res_t *)result)->len;
}
const char *shaderc_result_get_spv_bytes(void *result) {
    return ((fake_res_t *)result)->bytes;
}
size_t shaderc_result_get_spv_length(void *result) {
    return ((fake_res_t *)result)->len;
}
void shaderc_result_release(void *result) {
    fake_res_t *r = (fake_res_t *)result;
    free(r->bytes);
    free(r->err);
    free(r);
}
