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
// ⚠️ 实现要点：解析 impl 真实符号必须用"未被 fishhook 拦截的原始 dlsym"。
// 若直接调用 dlsym(impl, "shaderc_compile_into_spv")，hooked_dlsym 会按符号名
// 拦截并返回 main_hook.m 的 32MB-stack wrapper，而该 wrapper 又会回调本垫片的
// 转发器 —— 同线程重入已持有的锁即自死锁。因此构造时先经
// dlsym(RTLD_DEFAULT, "dlsym") 取回原始 dlsym（hook 只拦 shaderc_/spvc_/SDL
// 前缀，"dlsym" 本身直通），后续一律用它解析 impl。
//
// 注意：本垫片只做串行化，不做 32MB 栈 hop（hooked 路径的 hop 仍由
// main_hook.m 的 wrapper 负责，二者按构造叠加：wrapper hop → 本垫片加锁）。

#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>

static pthread_mutex_t ame_shaderc_shim_lock;
static void *ame_shaderc_shim_impl = NULL;
static void *(*ame_shaderc_shim_real_dlsym)(void *, const char *) = NULL;

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

typedef void *(*ame_shaderc_shim_compile_fn_t)(void *compiler, const char *source,
                                               size_t source_size, int kind,
                                               const char *input_file,
                                               const char *entry_point, void *options);

static void *ame_shaderc_shim_compile(const char *sym, void *compiler,
                                      const char *source, size_t source_size,
                                      int kind, const char *input_file,
                                      const char *entry_point, void *options) {
    void *impl = ame_shaderc_shim_impl_handle();
    void *real = (impl != NULL && ame_shaderc_shim_real_dlsym != NULL)
                     ? ame_shaderc_shim_real_dlsym(impl, sym)
                     : NULL;
    if (real == NULL) {
        fprintf(stderr, "[shaderc-shim] %s unresolved (%s) -- returning NULL\n", sym,
                (impl == NULL) ? "impl missing" : "symbol missing");
        return NULL;
    }
    pthread_mutex_lock(&ame_shaderc_shim_lock);
    void *result = ((ame_shaderc_shim_compile_fn_t)real)(compiler, source, source_size,
                                                         kind, input_file, entry_point,
                                                         options);
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    return result;
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
                                    source, source_size, kind, input_file, entry_point,
                                    options);
}

void *shaderc_compile_into_preprocessed_text(void *compiler, const char *source,
                                             size_t source_size, int kind,
                                             const char *input_file,
                                             const char *entry_point, void *options) {
    return ame_shaderc_shim_compile("shaderc_compile_into_preprocessed_text", compiler,
                                    source, source_size, kind, input_file, entry_point,
                                    options);
}
