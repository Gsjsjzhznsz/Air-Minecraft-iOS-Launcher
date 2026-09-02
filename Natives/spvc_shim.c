// spirv-cross (spvc) 串行化垫片（Amethyst iOS 26.3-pre-1 RenderPearl 稳定性修复）
//
// 与 Natives/shaderc_shim.c 同族：RenderPearl 管线 = shaderc（GLSL→SPIR-V）+
// spvc（SPIR-V→桌面 GLSL）。真机证据（hs_err_pid27329）表明存在绕过
// hooked_dlsym 的第二解析路径在专用线程上并发调用编译族入口；shaderc 侧已由
// 垫片串行化，本垫片对 spvc 两个重活入口（parse_spirv / compiler_compile，
// 即 glslang/ spirv-cross 深递归所在）做同样的进程级串行化，避免同一竞态
// 转移到 SPIRV-Cross 侧复发。
//
// 真实库改名 libspirv-cross-c-shared.0.impl.dylib（-reexport_library 透传全部
// 符号）；未拦截的原始 dlsym 获取方式与死锁规避，见 shaderc_shim.c 顶部注释。
// 兼容名软链 libspirv-cross.dylib 由 Makefile payload 段照旧创建，指向本垫片。

#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>

static pthread_mutex_t ame_spvc_shim_lock;
static void *ame_spvc_shim_impl = NULL;
static void *(*ame_spvc_shim_real_dlsym)(void *, const char *) = NULL;

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

typedef int (*ame_spvc_shim_parse_fn_t)(void *context, const unsigned *spirv,
                                        size_t word_count, void **parsed_ir);
typedef int (*ame_spvc_shim_compile_fn_t)(void *compiler, const char **source);

int spvc_context_parse_spirv(void *context, const unsigned *spirv, size_t word_count,
                             void **parsed_ir) {
    void *impl = ame_spvc_shim_impl_handle();
    void *real = (impl != NULL && ame_spvc_shim_real_dlsym != NULL)
                     ? ame_spvc_shim_real_dlsym(impl, "spvc_context_parse_spirv")
                     : NULL;
    if (real == NULL) {
        fprintf(stderr, "[spvc-shim] spvc_context_parse_spirv unresolved -- returning "
                        "error\n");
        return -1;
    }
    pthread_mutex_lock(&ame_spvc_shim_lock);
    int rc = ((ame_spvc_shim_parse_fn_t)real)(context, spirv, word_count, parsed_ir);
    pthread_mutex_unlock(&ame_spvc_shim_lock);
    return rc;
}

int spvc_compiler_compile(void *compiler, const char **source) {
    void *impl = ame_spvc_shim_impl_handle();
    void *real = (impl != NULL && ame_spvc_shim_real_dlsym != NULL)
                     ? ame_spvc_shim_real_dlsym(impl, "spvc_compiler_compile")
                     : NULL;
    if (real == NULL) {
        fprintf(stderr, "[spvc-shim] spvc_compiler_compile unresolved -- returning "
                        "error\n");
        return -1;
    }
    pthread_mutex_lock(&ame_spvc_shim_lock);
    int rc = ((ame_spvc_shim_compile_fn_t)real)(compiler, source);
    pthread_mutex_unlock(&ame_spvc_shim_lock);
    return rc;
}
