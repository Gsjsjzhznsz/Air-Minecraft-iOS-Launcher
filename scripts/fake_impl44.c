// fake_impl44.c — Task 44 端到端测试用的假 libshaderc_impl
// 完整复刻 shaderc C ABI；compile_into_spv 返回 status=0 + "SPV:"+源码回显。
// 崩溃语义由环境变量 FAKE44_MODE 控制（模拟设备上的毒化形态）：
//   once     — 进程内第 1 次 compile 调用 SIGSEGV（旧 Task 34 场景）
//   perthread— 每个线程的第 1 次 compile 调用 SIGSEGV，直到出现
//              release→initialize 重建周期（= shim 的 glslang 进程状态重建）
//              后痊愈（模拟：同线程重试必崩 / TLS 毒化 / 重建后新线程可救）
//   always   — 每次调用都 SIGSEGV（恒崩 shader）
//   其他/未设置 — 从不崩溃
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned magic;
    int status;
    unsigned spv_len;
    unsigned err_len;
    char data[512];
} fake_result_t;
#define FAKE_RESULT_MAGIC 0xF4CEFA1Eu

static int g_calls = 0;
static int g_inits = 0;      // compiler_initialize 调用次数（≥2 = 出现过重建）
static int g_releases = 0;
static __thread int t_first = 1; // 每线程首调标记

static int mode_is(const char *m) {
    const char *v = getenv("FAKE44_MODE");
    return v != NULL && strcmp(v, m) == 0;
}

static int should_crash(void) {
    if (mode_is("always")) return 1;
    if (mode_is("once")) return g_calls == 1;
    if (mode_is("perthread")) {
        // 重建周期（release 后再次 initialize）之后痊愈
        if (g_releases > 0 && g_inits > 1) return 0;
        return t_first;
    }
    return 0;
}

void *shaderc_compiler_initialize(void) {
    g_inits++;
    return (void *)0x1234;
}
void shaderc_compiler_release(void *c) {
    (void)c;
    g_releases++;
}

void *shaderc_compile_options_initialize(void) { return malloc(64); }
void *shaderc_compile_options_clone(const void *o) {
    void *n = malloc(64);
    if (n && o) memcpy(n, o, 64);
    return n;
}
void shaderc_compile_options_release(void *o) { free(o); }
void shaderc_compile_options_set_target_env(void *o, int e, unsigned v) { (void)o; (void)e; (void)v; }
void shaderc_compile_options_set_source_language(void *o, int l) { (void)o; (void)l; }
void shaderc_compile_options_set_optimization_level(void *o, int l) { (void)o; (void)l; }
void shaderc_compile_options_set_generate_debug_info(void *o) { (void)o; }
void shaderc_compile_options_set_forced_version_profile(void *o, int v, int p) { (void)o; (void)v; (void)p; }
void shaderc_compile_options_add_macro_definition(void *o, const char *n, size_t nl, const char *v, size_t vl) { (void)o; (void)n; (void)nl; (void)v; (void)vl; }

static void *fake_compile(void *compiler, const char *source, size_t source_size,
                          int kind, const char *input_file, const char *entry_point,
                          void *options) {
    (void)compiler; (void)options; (void)entry_point;
    g_calls++;
    if (should_crash()) {
        t_first = 0;
        fprintf(stderr, "[fake_impl44] call #%d on new-thread?%d -- deliberate SIGSEGV "
                "(mode=%s)\n",
                g_calls, t_first, getenv("FAKE44_MODE") ? getenv("FAKE44_MODE") : "?");
        fflush(stderr);
        volatile int *p = (int *)0x1;
        *p = 42; // SIGSEGV
        return NULL;
    }
    t_first = 0;
    fake_result_t *r = (fake_result_t *)malloc(sizeof(fake_result_t));
    r->magic = FAKE_RESULT_MAGIC;
    r->status = 0;
    size_t n = source_size < sizeof r->data - 5 ? source_size : sizeof r->data - 5;
    memcpy(r->data, "SPV:", 4);
    memcpy(r->data + 4, source ? source : "", n);
    r->spv_len = (unsigned)(4 + n);
    r->err_len = 0;
    r->data[r->spv_len] = '\0';
    fprintf(stderr, "[fake_impl44] call #%d kind=%d in='%s' -> %uB (mode=%s)\n",
            g_calls, kind, input_file ? input_file : "?", r->spv_len,
            getenv("FAKE44_MODE") ? getenv("FAKE44_MODE") : "none");
    return r;
}

void *shaderc_compile_into_spv(void *compiler, const char *source, size_t source_size,
                               int kind, const char *input_file, const char *entry_point,
                               void *options) {
    return fake_compile(compiler, source, source_size, kind, input_file, entry_point, options);
}
void *shaderc_compile_into_spv_assembly(void *c, const char *s, size_t n, int k, const char *i,
                                        const char *e, void *o) {
    return fake_compile(c, s, n, k, i, e, o);
}
void *shaderc_compile_into_preprocessed_text(void *c, const char *s, size_t n, int k, const char *i,
                                             const char *e, void *o) {
    return fake_compile(c, s, n, k, i, e, o);
}

int shaderc_result_get_compilation_status(void *result) {
    return result ? ((fake_result_t *)result)->status : 3;
}
size_t shaderc_result_get_num_errors(void *result) {
    return (!result || ((fake_result_t *)result)->status != 0) ? 1 : 0;
}
size_t shaderc_result_get_num_warnings(void *result) { (void)result; return 0; }
const char *shaderc_result_get_error_message(void *result) {
    if (!result) return "(null)";
    return ((fake_result_t *)result)->data + ((fake_result_t *)result)->spv_len + 1;
}
const char *shaderc_result_get_bytes(void *result) { return ((fake_result_t *)result)->data; }
size_t shaderc_result_get_length(void *result) { return ((fake_result_t *)result)->spv_len; }
const char *shaderc_result_get_spv_bytes(void *result) { return ((fake_result_t *)result)->data; }
size_t shaderc_result_get_spv_length(void *result) { return ((fake_result_t *)result)->spv_len; }
void shaderc_result_release(void *result) { free(result); }
