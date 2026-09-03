// shaderc 串行化垫片（Amethyst iOS 26.3-pre-1 RenderPearl 稳定性修复）
//
// 背景（hs_err_pid27329，构建 bcf33453）：ABI 修复后 shaderc 首编成功、MG 转换
// 连续成功、首帧渲染完成；随后资源重载阶段，两个 32MB 栈 JVM 线程（Thread-1/
// Thread-2）同时直接执行 libshaderc 的 glslang yyparse（绕过了 hooked_dlsym
// wrapper 的调用路径），并发编译导致 glslang AST 节点内存互相踩踏，
// TParseContext::lValueErrorCheck+0x204 读到脏指针 SEGV_ACCERR，双线程同崩。
//
// 修复策略：把真实库改名 libshaderc_impl.dylib，本垫片顶替 libshaderc.dylib：
//   - 通过 -reexport_library 透传 impl 的全部符号（glslang/shaderc API 原样可用）；
//   - 自行定义三个编译入口（shaderc_compile_into_spv / _spv_assembly /
//     _preprocessed_text），以进程级递归互斥锁强制全部编译串行——无论调用方走
//     hooked dlsym、RTLD_DEFAULT 还是其它任何动态解析路径，拿到的都是这里的
//     带锁转发器，从根上消灭"多上下文并发编译"这一崩溃形态。
//
// Task 30（hs_err_pid27946，构建 744642f2）：串行化已生效，崩溃线程栈确认为
// wrapper → 本垫片 → impl 单线程编译，但第 9 次编译仍在
// glslang::TParseContext::lValueErrorCheck+0x204 崩：SWIZZLE 选择器节点的
// constArray 指针字段（对象偏移 +0xd8）被 8 字节 ASCII 字符串数据覆盖
// （si_addr=0x66617263656e6900 = "\0inceraf"）——内存被释放后又被字符串分配
// 复用的特征。本垫片此前只串行了 3 个编译入口，而 shaderc 的生命周期入口
// 全部裸奔：
//   shaderc_compiler_release →（最后一个 compiler 时）glslang::FinalizeProcess()
//   → 拆全局符号表、释放 glslang 池。MC 26.3 资源重载 = 旧 RenderPearl 管线
//   释放 + 新管线并发编译（release 可能经任意 Java 线程乃至 GC/Cleaner 线程
//   触发），release 与 in-flight 编译竞态 → 编译中的 AST 所在内存被释放、
//   随后被任意字符串分配（JVM young GC / 资源加载 / unifont 装载）复用 →
//   ASCII 字节落进指针字段。2026-08 MobileGlues 2.0.1..2.0.3 的同签名设备
//   崩溃（注释原文 "clean under ASan"）说明该竞态家族早于 Amethyst 介入。
// 修复：compiler/options 的 initialize / release / clone / add_macro_definition
//   一并纳入同一把递归互斥锁。release 若撞上 in-flight 编译会阻塞等待并打出
//   "BLOCKED" 取证日志——竞态窗口从根上关闭。options_set_* 变更族不入锁：
//   options 是单线程编译作用域对象，实际危险的是 release-vs-compile，已覆盖。
//
// ⚠️ 实现要点：解析 impl 真实符号必须用"未被 fishhook 拦截的原始 dlsym"。
// 若直接调用 dlsym(impl, "shaderc_compile_into_spv")，hooked_dlsym 会按符号名
// 拦截并返回 main_hook.m 的 32MB-stack wrapper，而该 wrapper 又会回调本垫片的
// 转发器 —— 同线程重入已持有的锁即自死锁。因此构造时先经
// dlsym(RTLD_DEFAULT, "dlsym") 取回原始 dlsym（hook 只拦 shaderc_/spvc_/SDL
// 前缀，"dlsym" 本身直通），后续一律用它解析 impl。
//
// 注意：本垫片只做串行化 + 取证日志，不做 32MB 栈 hop（hooked 路径的 hop 仍由
// main_hook.m 的 wrapper 负责，二者按构造叠加：wrapper hop → 本垫片加锁）。
// 取证日志（Task 30）：每个生命周期事件与每次编译各一行，带进程启动起的毫秒
// 数与线程标识；release 在锁被占用时先打 "BLOCKED behind in-flight compile"
// 再等锁——若真机日志出现该行，即证明 release-vs-compile 竞态真实发生过
// （且已被本次修复挡下）。

#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static pthread_mutex_t ame_shaderc_shim_lock;
static void *ame_shaderc_shim_impl = NULL;
static void *(*ame_shaderc_shim_real_dlsym)(void *, const char *) = NULL;

// 进程启动起的毫秒数（取证时间轴；首个调用线程初始化 t0，毫秒精度足够）。
static double ame_shim_ms(void) {
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

// 线程标识（pthread_t 低 32 位；用于与 hs_err 线程列表人工对照）。
static unsigned long ame_shim_tid(void) {
    return (unsigned long)(((uintptr_t)pthread_self()) & 0xffffffffull);
}

// 取锁；若已有 in-flight 编译持有锁，先打 BLOCKED 取证行再等待。
static void ame_shim_lock_or_report_blocked(const char *what, const void *obj) {
    if (pthread_mutex_trylock(&ame_shaderc_shim_lock) == 0) return;
    fprintf(stderr,
            "[shaderc-shim] %s(%p) BLOCKED behind in-flight compile -- waiting "
            "(t=%.0fms tid=%lx)\n",
            what, obj, ame_shim_ms(), ame_shim_tid());
    pthread_mutex_lock(&ame_shaderc_shim_lock);
}

__attribute__((constructor))
static void ame_shaderc_shim_init(void) {
    pthread_mutexattr_t lock_attr;
    pthread_mutexattr_init(&lock_attr);
    pthread_mutexattr_settype(&lock_attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&ame_shaderc_shim_lock, &lock_attr);
    pthread_mutexattr_destroy(&lock_attr);
    // 原始 dlsym（"dlsym" 不在 hooked_dlsym 的拦截名单内，直通 orig_dlsym）
    ame_shaderc_shim_real_dlsym =
        (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "dlsym");
    if (ame_shaderc_shim_real_dlsym == NULL) {
        fprintf(stderr, "[shaderc-shim] FATAL: cannot obtain unhooked dlsym\n");
        return;
    }
    static const char *const kCandidates[] = {
        "@loader_path/libshaderc_impl.dylib",
        "@rpath/libshaderc_impl.dylib",
        "libshaderc_impl.dylib",
        NULL,
    };
    for (int i = 0; kCandidates[i] != NULL; ++i) {
        ame_shaderc_shim_impl = dlopen(kCandidates[i], RTLD_NOW | RTLD_LOCAL);
        if (ame_shaderc_shim_impl != NULL) {
            fprintf(stderr, "[shaderc-shim] impl loaded via %s\n", kCandidates[i]);
            return;
        }
    }
    fprintf(stderr, "[shaderc-shim] FAILED to load libshaderc_impl.dylib: %s\n",
            dlerror());
}

// 每次调用惰性重试（构造期 dyld 环境尚未就绪等极端场景的兜底）
static void *ame_shaderc_shim_impl_handle(void) {
    if (ame_shaderc_shim_impl == NULL) ame_shaderc_shim_init();
    return ame_shaderc_shim_impl;
}

static void *ame_shaderc_shim_resolve(const char *sym) {
    void *impl = ame_shaderc_shim_impl_handle();
    return (impl != NULL && ame_shaderc_shim_real_dlsym != NULL)
               ? ame_shaderc_shim_real_dlsym(impl, sym)
               : NULL;
}

typedef void *(*ame_shaderc_shim_compile_fn_t)(void *compiler, const char *source,
                                               size_t source_size, int kind,
                                               const char *input_file,
                                               const char *entry_point, void *options);

static void *ame_shaderc_shim_compile(const char *sym, void *compiler,
                                      const char *source, size_t source_size,
                                      int kind, const char *input_file,
                                      const char *entry_point, void *options) {
    void *real = ame_shaderc_shim_resolve(sym);
    if (real == NULL) {
        fprintf(stderr, "[shaderc-shim] %s unresolved (%s) -- returning NULL\n", sym,
                (ame_shaderc_shim_impl == NULL) ? "impl missing" : "symbol missing");
        return NULL;
    }
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    // 逐编译取证（Task 30）：编译序号 + compiler/options 指针 + kind + 长度 +
    // 文件名。下轮崩溃日志可直接对照：第几次编译、compiler 是否在重载后换新、
    // options 指针是否曾被 options_release 日志指认。
    static int s_compile_seq = 0;
    int seq = ++s_compile_seq;
    fprintf(stderr,
            "[shaderc-shim] compile#%d t=%.0fms tid=%lx kind=%d len=%zu comp=%p "
            "opt=%p in='%.48s'\n",
            seq, ame_shim_ms(), ame_shim_tid(), kind, source_size, compiler, options,
            input_file ? input_file : "(null)");
    void *result = ((ame_shaderc_shim_compile_fn_t)real)(compiler, source, source_size,
                                                         kind, input_file, entry_point,
                                                         options);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    return result;
}

// ---- 生命周期入口（Task 30）：与编译共用同一把锁，关闭 release-vs-compile
// 竞态窗口，见文件头注释。签名与 shaderc.h 公开 ABI 一致（不透明指针以 void*
// 承载，不透明结构句柄在 arm64 上均为指针宽度）。 ----

void *shaderc_compiler_initialize(void) {
    void *real = ame_shaderc_shim_resolve("shaderc_compiler_initialize");
    if (real == NULL) return NULL;
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    void *compiler = ((void *(*)(void))real)();
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    fprintf(stderr, "[shaderc-shim] compiler_initialize -> %p (t=%.0fms tid=%lx)\n",
            compiler, ame_shim_ms(), ame_shim_tid());
    return compiler;
}

void shaderc_compiler_release(void *compiler) {
    void *real = ame_shaderc_shim_resolve("shaderc_compiler_release");
    if (real == NULL || compiler == NULL) return;
    ame_shim_lock_or_report_blocked("compiler_release", compiler);
    ((void (*)(void *))real)(compiler);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    fprintf(stderr, "[shaderc-shim] compiler_release %p done (t=%.0fms tid=%lx)\n",
            compiler, ame_shim_ms(), ame_shim_tid());
}

void *shaderc_compile_options_initialize(void) {
    void *real = ame_shaderc_shim_resolve("shaderc_compile_options_initialize");
    if (real == NULL) return NULL;
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    void *options = ((void *(*)(void))real)();
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    return options;
}

void *shaderc_compile_options_clone(const void *options) {
    void *real = ame_shaderc_shim_resolve("shaderc_compile_options_clone");
    if (real == NULL || options == NULL) return NULL;
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    void *cloned = ((void *(*)(const void *))real)(options);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    return cloned;
}

void shaderc_compile_options_release(void *options) {
    void *real = ame_shaderc_shim_resolve("shaderc_compile_options_release");
    if (real == NULL || options == NULL) return;
    ame_shim_lock_or_report_blocked("options_release", options);
    ((void (*)(void *))real)(options);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    fprintf(stderr, "[shaderc-shim] options_release %p done (t=%.0fms tid=%lx)\n",
            options, ame_shim_ms(), ame_shim_tid());
}

// 宏名/宏值写入 options：与 release/clone 同锁，防止 options 被并发拆掉时写入。
void shaderc_compile_options_add_macro_definition(void *options, const char *name,
                                                  size_t name_length, const char *value,
                                                  size_t value_length) {
    void *real = ame_shaderc_shim_resolve("shaderc_compile_options_add_macro_definition");
    if (real == NULL || options == NULL) return;
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    ((void (*)(void *, const char *, size_t, const char *, size_t))real)(
        options, name, name_length, value, value_length);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
}

void *shaderc_compile_into_spv(void *compiler, const char *source, size_t source_size,
                               int kind, const char *input_file, const char *entry_point,
                               void *options) {
    return ame_shaderc_shim_compile("shaderc_compile_into_spv", compiler, source,
                                    source_size, kind, input_file, entry_point, options);
}

void *shaderc_compile_into_spv_assembly(void *compiler, const char *source,
                                        size_t source_size, int kind,
                                        const char *input_file, const char *entry_point,
                                        void *options) {
    return ame_shaderc_shim_compile("shaderc_compile_into_spv_assembly", compiler,
                                    source, source_size, kind, input_file, entry_point, options);
}

void *shaderc_compile_into_preprocessed_text(void *compiler, const char *source,
                                             size_t source_size, int kind,
                                             const char *input_file,
                                             const char *entry_point, void *options) {
    return ame_shaderc_shim_compile("shaderc_compile_into_preprocessed_text", compiler,
                                    source, source_size, kind, input_file, entry_point, options);
}
