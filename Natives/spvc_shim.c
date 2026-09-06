// spirv-cross (spvc) 串行化垫片（Amethyst iOS 26.3-pre-1 RenderPearl 稳定性修复）
//
// 与 Natives/shaderc_shim.c 同族：RenderPearl 管线 = shaderc（GLSL→SPIR-V）+
// spvc（SPIR-V→桌面 GLSL）。真机证据（hs_err_pid27329）表明存在绕过
// hooked_dlsym 的第二解析路径在专用线程上并发调用编译族入口；shaderc 侧已由
// 垫片串行化，本垫片对 spvc 两个重活入口（parse_spirv / compiler_compile，
// 即深递归所在）做同样的进程级串行化，避免同一竞态转移到 SPIRV-Cross 侧复发。
//
// Task 30（hs_err_pid27946 追加固化）：与 shaderc_shim 同理，把 spvc 的生命
// 周期入口一并纳入同一把锁——spvc_context_destroy / release_allocations 会
// 释放 context 全部子对象内存，若与另一线程的 parse_spirv / create_compiler /
// compile 竞态（MC 资源重载 = 旧管线销毁 + 新管线并发编译），同样是
// use-after-free 家族。create_compiler 从 parsed_ir 抽取 IR 构建后端，与
// destroy 并发同样危险，一并串行。
//
// 真实库改名 libspirv-cross-c-shared.0.impl.dylib（-reexport_library 透传全部
// 符号）；未拦截的原始 dlsym 获取方式与死锁规避，见 shaderc_shim.c 顶部注释。
// 兼容名软链 libspirv-cross.dylib 由 Makefile payload 段照旧创建，指向本垫片。
//
// Task 37（GL 渲染器路径 latestlog 2026-09-06 18:42）：真机日志铁证四引擎
// 并发——shaderc 编译（shaderc_shim 锁）与 spvc 交叉编译（本垫片锁，两把
// 互不相干）与 MobileGlues 转换器（仅自带 g_conv_serial）同时工作；复杂
// shader（terrain/entity）在此窗口全部双崩。本垫片改为运行时协商
// libshaderc.dylib（shaderc_shim）导出的 ame_master_compile_lock()，把
// spvc 的全部入口挂到跨库总锁上，与 shaderc 编译、MG 转换彻底互斥；
// 协商失败（独立构建/加载顺序异常）退回本地锁，行为与旧版一致。
// 死锁审查：spvc 转发 impl 期间不回调 shaderc/MG，单向锁序无环；首次协商
// 的 dlopen 只拿 dyld 锁（与编译互不相嵌）。

#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static pthread_mutex_t ame_spvc_shim_lock;  // 本地回退锁（master 协商失败时用）
static pthread_mutex_t *g_ame_master_lock = NULL;
static void *ame_spvc_shim_impl = NULL;
static void *(*ame_spvc_shim_real_dlsym)(void *, const char *) = NULL;

// ---- Task 37：与 libshaderc.dylib（shaderc_shim）协商跨库编译总锁 ----
// 惰性一次性：首个取锁的调用触发。dlopen 同 install name 的已加载镜像
// 只增加引用计数并返回同一 handle（MC/LWJGL 必然已加载或即将加载同一文件）
// 因此这里不会产生第二个 shaderc 实例。并发首次调用最坏双重 dlopen/dlsym
// 写同值，无害。
static pthread_mutex_t *ame_spvc_master_or_local(void) {
    static volatile int s_negotiated = 0;
    if (!s_negotiated) {
        s_negotiated = 1;
        static const char *const kCandidates[] = {
            "@rpath/libshaderc.dylib",
            "@loader_path/libshaderc.dylib",
            "libshaderc.dylib",
            NULL,
        };
        for (int i = 0; kCandidates[i] != NULL && g_ame_master_lock == NULL; ++i) {
            void *h = dlopen(kCandidates[i], RTLD_LAZY);
            if (h == NULL || ame_spvc_shim_real_dlsym == NULL) continue;
            pthread_mutex_t *(*fn)(void) =
                (pthread_mutex_t *(*)(void))ame_spvc_shim_real_dlsym(
                    h, "ame_master_compile_lock");
            if (fn != NULL) g_ame_master_lock = fn();
        }
        fprintf(stderr, g_ame_master_lock
                ? "[spvc-shim] master compile lock negotiated %p -- shaderc/spvc/MG "
                  "serialization ON\n"
                : "[spvc-shim] master lock unavailable -- falling back to local lock\n",
                g_ame_master_lock ? (void *)g_ame_master_lock : NULL);
    }
    return (g_ame_master_lock != NULL) ? g_ame_master_lock : &ame_spvc_shim_lock;
}

// 进程启动起的毫秒数 + 线程标识（取证时间轴，与 shaderc-shim 日志对齐）。
static double ame_spvc_shim_ms(void) {
    static struct timespec t0;
    static volatile int t0_set = 0;
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC_RAW, &now);
    if (!t0_set) {
        t0 = now;
        t0_set = 1;
    }
    return (double)(now.tv_sec - t0.tv_sec) * 1000.0 +
           (double)(now.tv_nsec - t0.tv_nsec) / 1.0e6;
}

static unsigned long ame_spvc_shim_tid(void) {
    return (unsigned long)(((uintptr_t)pthread_self()) & 0xffffffffull);
}

static void ame_spvc_shim_lock_or_report_blocked(const char *what, const void *obj) {
    pthread_mutex_t *lock = ame_spvc_master_or_local();
    if (pthread_mutex_trylock(lock) == 0) return;
    fprintf(stderr,
            "[spvc-shim] %s(%p) BLOCKED behind in-flight parse/compile -- waiting "
            "(t=%.0fms tid=%lx)\n",
            what, obj, ame_spvc_shim_ms(), ame_spvc_shim_tid());
    pthread_mutex_lock(lock);
}

__attribute__((constructor))
static void ame_spvc_shim_init(void) {
    pthread_mutexattr_t lock_attr;
    pthread_mutexattr_init(&lock_attr);
    pthread_mutexattr_settype(&lock_attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&ame_spvc_shim_lock, &lock_attr);
    pthread_mutexattr_destroy(&lock_attr);
    ame_spvc_shim_real_dlsym =
        (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "dlsym");
    if (ame_spvc_shim_real_dlsym == NULL) {
        fprintf(stderr, "[spvc-shim] FATAL: cannot obtain unhooked dlsym\n");
        return;
    }
    static const char *const kCandidates[] = {
        "@loader_path/libspirv-cross-c-shared.0.impl.dylib",
        "@rpath/libspirv-cross-c-shared.0.impl.dylib",
        "libspirv-cross-c-shared.0.impl.dylib",
        NULL,
    };
    for (int i = 0; kCandidates[i] != NULL; ++i) {
        ame_spvc_shim_impl = dlopen(kCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (ame_spvc_shim_impl != NULL) {
            fprintf(stderr, "[spvc-shim] impl loaded via %s\n", kCandidates[i]);
            return;
        }
    }
    fprintf(stderr, "[spvc-shim] FAILED to load impl: %s\n", dlerror());
}

static void *ame_spvc_shim_impl_handle(void) {
    if (ame_spvc_shim_impl == NULL) ame_spvc_shim_init();
    return ame_spvc_shim_impl;
}

static void *ame_spvc_shim_resolve(const char *sym) {
    void *impl = ame_spvc_shim_impl_handle();
    return (impl != NULL && ame_spvc_shim_real_dlsym != NULL)
               ? ame_spvc_shim_real_dlsym(impl, sym)
               : NULL;
}

typedef int (*ame_spvc_shim_parse_fn_t)(void *context, const unsigned *spirv,
                                        size_t word_count, void **parsed_ir);
typedef int (*ame_spvc_shim_compile_fn_t)(void *compiler, const char **source);

// ---- 重活入口（原有，补取证日志） ----

int spvc_context_parse_spirv(void *context, const unsigned *spirv, size_t word_count,
                             void **parsed_ir) {
    void *real = ame_spvc_shim_resolve("spvc_context_parse_spirv");
    if (real == NULL) {
        fprintf(stderr, "[spvc-shim] spvc_context_parse_spirv unresolved -- returning "
                        "error\n");
        return -1;
    }
    pthread_mutex_lock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] parse_spirv words=%zu ctx=%p (t=%.0fms tid=%lx)\n",
            word_count, context, ame_spvc_shim_ms(), ame_spvc_shim_tid());
    int rc = ((ame_spvc_shim_parse_fn_t)real)(context, spirv, word_count, parsed_ir);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    return rc;
}

int spvc_compiler_compile(void *compiler, const char **source) {
    void *real = ame_spvc_shim_resolve("spvc_compiler_compile");
    if (real == NULL) {
        fprintf(stderr, "[spvc-shim] spvc_compiler_compile unresolved -- returning "
                        "error\n");
        return -1;
    }
    pthread_mutex_lock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] compiler_compile comp=%p (t=%.0fms tid=%lx)\n",
            compiler, ame_spvc_shim_ms(), ame_spvc_shim_tid());
    int rc = ((ame_spvc_shim_compile_fn_t)real)(compiler, source);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    return rc;
}

// ---- 生命周期入口（Task 30 新增）：与 parse/compile 共用同一把锁 ----
// 签名按 spirv_cross_c.h 公开 ABI（spvc_result / 枚举按 int 承载，不透明句柄
// 均为指针宽度）。

int spvc_context_create(void **context) {
    void *real = ame_spvc_shim_resolve("spvc_context_create");
    if (real == NULL || context == NULL) return -1;
    pthread_mutex_lock(ame_spvc_master_or_local());
    int rc = ((int (*)(void **))real)(context);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] context_create -> %p rc=%d (t=%.0fms tid=%lx)\n",
            (context ? *context : NULL), rc, ame_spvc_shim_ms(), ame_spvc_shim_tid());
    return rc;
}

void spvc_context_destroy(void *context) {
    void *real = ame_spvc_shim_resolve("spvc_context_destroy");
    if (real == NULL || context == NULL) return;
    ame_spvc_shim_lock_or_report_blocked("context_destroy", context);
    ((void (*)(void *))real)(context);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] context_destroy %p done (t=%.0fms tid=%lx)\n",
            context, ame_spvc_shim_ms(), ame_spvc_shim_tid());
}

// 语义上等于"释放 context 全部子对象内存但留壳"（spirv_cross_c.h 原注释），
// 与 destroy 同级危险，同样串行 + 取证。
void spvc_context_release_allocations(void *context) {
    void *real = ame_spvc_shim_resolve("spvc_context_release_allocations");
    if (real == NULL || context == NULL) return;
    ame_spvc_shim_lock_or_report_blocked("release_allocations", context);
    ((void (*)(void *))real)(context);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] release_allocations %p done (t=%.0fms tid=%lx)\n",
            context, ame_spvc_shim_ms(), ame_spvc_shim_tid());
}

int spvc_context_create_compiler(void *context, int backend, void *parsed_ir,
                                 int capture_mode, void **compiler) {
    void *real = ame_spvc_shim_resolve("spvc_context_create_compiler");
    if (real == NULL || compiler == NULL) return -1;
    pthread_mutex_lock(ame_spvc_master_or_local());
    int rc = ((int (*)(void *, int, void *, int, void **))real)(
        context, backend, parsed_ir, capture_mode, compiler);
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] create_compiler backend=%d -> %p rc=%d (t=%.0fms "
                    "tid=%lx)\n",
            backend, (compiler ? *compiler : NULL), rc, ame_spvc_shim_ms(),
            ame_spvc_shim_tid());
    return rc;
}
