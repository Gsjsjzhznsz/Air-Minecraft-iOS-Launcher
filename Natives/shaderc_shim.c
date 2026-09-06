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
//
// Task 34（hs_err_pid33505，构建 777302c）：黑屏修复验证通过（embed 成功、
// 首帧 eglSwapBuffers OK、fps=10），但 shaderc compile#7（terrain 顶点）在
// glslang::TParseContext::lValueErrorCheck+0x204 SIGSEGV——与 Task 30 同签名
// 同 PC，且同一二进制同一 shader 在上一轮跑了 390 次全过 = 非确定性堆踩踏。
// 双层修复：
//   1) scripts/patch_shaderc_lvalue_guard.py 对 libshaderc_impl.dylib 做机器码
//      级补丁（把脆弱 swizzle 循环体重定位到 __TEXT 尾部 cave，加 5 重空指针
//      + 1 重负值 + 1 重越界防护，与 MobileGlues 源码级 nullguard patch 等价）；
//   2) 本文件加装“编译窗口崩溃恢复网”：真实编译期间进程级接管 SIGSEGV/SIGBUS，
//      编译线程内崩溃→siglongjmp 回未恢复并重试一次；重试再崩→返回 NULL 并
//      把崩溃信息打进日志（非编译线程的崩溃照旧链回 JVM 处理器走 hs_err）。
//      这样即便 impl 里还藏着其它同类脆弱点，也只损失单个 shader 编译而不是
//      整个进程。恢复代价：被丢弃的解析树内存泄漏（罕见事件，可接受）。

//
// Task 37（latestlog 2026-09-06 18:42，构建 e28e4c3，GL 渲染器路径）：
// 渲染器切换成功后 GL 链路首次贯通（embed 成功、首帧 eglSwapBuffers OK），
// 但资源重载阶段 shaderc 复杂 shader（terrain/entity/clouds…）全部双崩
// （重试必崩 = 确定性环境破坏，非瞬态踩踏），崩溃网恢复后返回 NULL →
// LWJGL Checks.check 对 NULL 指针抛 NPE →
// GlslCompiler.compileToSpv:147 → CompletionException → 游戏崩溃。
// 崩溃窗口与 MobileGlues 转换器激活窗口完全重合（[MG] Shader N converted
// 从 t≈280ms 起持续工作；compile#1-4 在 MG 启动前全部成功；同窗口内简单
// shader 也成功、复杂 shader 全崩）。全进程实际存在四套转换引擎并发：
// 本 impl 的 glslang + spvc 的 SPIRV-Cross（RenderPearl 管线，两把独立的
// shim 锁）vs MG 内嵌的 glslang + SPIRV-Cross（GLSLtoGLSLES_2，仅自带
// g_conv_serial 自身互斥）——跨引擎零串行。MG 侧自己的注释（glsl_for_es.cpp
// g_conv_serial 处）已实证同库并发解析会互踩 AST；跨引擎并发同理可信。
// 三连修复：
//   1) ame_master_compile_lock：本垫片升级为跨库总锁持有者并导出 C 符号；
//      spvc_shim / MobileGlues 的 GLSLtoGLSLES_2 通过 dlopen("libshaderc.dylib")
//      + dlsym 协商同一把锁（拿不到则各自退回本地锁，向后兼容）；
//      shaderc 编译 / spvc 交叉编译 / MG 转换三方彻底串行，并发窗口归零。
//   2) 双崩后不再返回 NULL：合成 fake result（magic 标记 + status=
//      internal_error + 取证错误消息），并拦截 shaderc_result_* 访问器族
//      （release / status / errors / warnings / message / bytes / length /
//      spv_bytes / spv_length）识别 fake 指针——LWJGL 拿到非 NULL 句柄，
//      MC 走正常「编译失败」路径，NPE 消失；
//   3) 崩溃网打印崩溃 PC/LR（arm64 ucontext）——下轮日志可直接对着 impl
//      符号表离线 symbolicate，定位具体 glslang 函数。

#include <dlfcn.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static pthread_mutex_t ame_shaderc_shim_lock;
static void *ame_shaderc_shim_impl = NULL;
static void *(*ame_shaderc_shim_real_dlsym)(void *, const char *) = NULL;

// ---- Task 37：跨库编译总锁导出 ----
// spvc_shim 与 MobileGlues 的 GLSL 转换器（GLSLtoGLSLES_2）在运行时
// dlopen("libshaderc.dylib") 后 dlsym("ame_master_compile_lock") 拿到本函数，
// 与本垫片的编译/生命周期锁共用同一把递归互斥锁，消灭「四引擎并发」窗口。
// 返回值恒非 NULL；协商失败方退回各自本地锁，不影响本垫片自身行为。
pthread_mutex_t *ame_master_compile_lock(void) {
    return &ame_shaderc_shim_lock;
}

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

// ---- Task 34：编译窗口崩溃恢复网（SIGSEGV/SIGBUS） ----
// 状态全部线程局部（编译串行，但同时只有一个编译线程带网运行）；
// 旧的 sigaction 快照是进程级的，只在持锁的 install/restore 窗口内读写。
static __thread sigjmp_buf ame_compile_jmp;
static __thread volatile sig_atomic_t ame_in_compile = 0;
static __thread volatile sig_atomic_t ame_last_call_crashed = 0;
static struct sigaction ame_prev_segv;
static struct sigaction ame_prev_bus;
static int ame_net_installed = 0;

static void ame_compile_crash_handler(int sig, siginfo_t *si, void *ctx) {
    if (ame_in_compile) {
        ame_in_compile = 0;
        // Task 37：崩溃 PC/LR 取证（arm64 ucontext）——离线对着 impl 符号表
        // symbolicate 即可定位崩溃函数（lValueErrorCheck 家族或新脆弱点）。
        uint64_t pc = 0, lr = 0;
#if defined(__aarch64__)
        if (ctx != NULL) {
            ucontext_t *uc = (ucontext_t *)ctx;
            pc = (uint64_t)uc->uc_mcontext->__ss.__pc;
            lr = (uint64_t)uc->uc_mcontext->__ss.__lr;
        }
#endif
        // 阻断本信号，防止 longjmp 展开过程中同一错误页立即重触发
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, sig);
        sigprocmask(SIG_BLOCK, &set, NULL);
        fprintf(stderr,
                "[shaderc-shim] compile CRASHED (sig=%d si_addr=%p pc=%p lr=%p "
                "tid=%lx t=%.0fms) -- recovered via longjmp\n",
                sig, si ? si->si_addr : NULL, (void *)pc, (void *)lr,
                ame_shim_tid(), ame_shim_ms());
        siglongjmp(ame_compile_jmp, 1);
    }
    // 非编译线程（或非编译窗口）：链回先前安装的处理器（通常是 JVM 的，
    // 走 hs_err 报告路径），保持进程其它部分的崩溃语义不变。
    struct sigaction prev = (sig == SIGBUS) ? ame_prev_bus : ame_prev_segv;
    if (prev.sa_flags & SA_SIGINFO) {
        prev.sa_sigaction(sig, si, ctx);
    } else if (prev.sa_handler == SIG_DFL) {
        // 恢复默认处置并返回；出错指令重执行时内核套用默认动作。
        signal(sig, SIG_DFL);
    } else if (prev.sa_handler == SIG_IGN) {
        /* 忽略 */
    } else {
        prev.sa_handler(sig);
    }
}

// 仅在持有 ame_shaderc_shim_lock 时调用（编译串行化保证单线程 install/restore）。
static void ame_crash_net_install(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = ame_compile_crash_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGSEGV, &sa, &ame_prev_segv) != 0) return;
    if (sigaction(SIGBUS, &sa, &ame_prev_bus) != 0) {
        sigaction(SIGSEGV, &ame_prev_segv, NULL);
        return;
    }
    ame_net_installed = 1;
}

static void ame_crash_net_restore(void) {
    if (!ame_net_installed) return;
    sigaction(SIGSEGV, &ame_prev_segv, NULL);
    sigaction(SIGBUS, &ame_prev_bus, NULL);
    ame_net_installed = 0;
}

// 带网调用真实编译；崩溃恢复后置 ame_last_call_crashed 并返回 NULL。
static void *ame_call_real_guarded(ame_shaderc_shim_compile_fn_t fn, void *compiler,
                                   const char *source, size_t source_size, int kind,
                                   const char *input_file, const char *entry_point,
                                   void *options) {
    ame_last_call_crashed = 0;
    ame_in_compile = 1;
    if (sigsetjmp(ame_compile_jmp, 1) == 0) {
        return fn(compiler, source, source_size, kind, input_file, entry_point, options);
    }
    ame_last_call_crashed = 1;
    return NULL;
}

// Task 37 前置声明：合成失败 result（定义见下方 result 访问器族）。
static void *ame_fake_result_create(int seq);

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
    // Task 34：崩溃恢复网罩住真实调用；首次崩溃→重试一次（新鲜解析树，
    // 堆踩踏通常是瞬态的）；重试再崩→返回合成失败 result（Task 37：绝不能
    // 返回 NULL——LWJGL Checks.check 对 NULL 抛 NPE，真机 CompletionException
    // 的直接死因）；诊断链不丢失。
    ame_crash_net_install();
    void *result = ame_call_real_guarded((ame_shaderc_shim_compile_fn_t)real, compiler,
                                         source, source_size, kind, input_file,
                                         entry_point, options);
    if (ame_last_call_crashed) {
        fprintf(stderr,
                "[shaderc-shim] compile#%d crashed on first attempt -- retrying once "
                "with fresh parse state\n",
                seq);
        result = ame_call_real_guarded((ame_shaderc_shim_compile_fn_t)real, compiler,
                                       source, source_size, kind, input_file,
                                       entry_point, options);
        if (ame_last_call_crashed) {
            fprintf(stderr,
                    "[shaderc-shim] compile#%d crashed on RETRY too -- giving up, "
                    "returning synthetic failure result (compilation will be "
                    "reported failed, no NULL to LWJGL)\n",
                    seq);
            // Task 37：合成 fake result（status=internal_error + 取证消息）。
            result = ame_fake_result_create(seq);
        }
    }
    ame_in_compile = 0;
    ame_crash_net_restore();
    pthread_mutex_unlock(&ame_shaderc_shim_lock);
    return result;
}

// ---- Task 37：合成失败 result（防 NULL → NPE） ----
// 双崩后 MC/LWJGL 需要一个非 NULL 的 shaderc_compilation_result_t；本层
// 用 malloc 的 fake 对象（magic 头识别）+ 拦截的 result 访问器族共同实现。
// malloc 失败的兑底静态件用低位翻转的 magic 标记（release 跳过 free）。
// 访问器转发真实对象时不加锁：result 为调用线程独占的个体堆对象，不存在
// release-vs-compile 的全局状态竞态（Task 30 已证明危险面在 options/compiler）。
typedef struct {
    uint64_t magic;   // AME_FAKE_RESULT_MAGIC / _STATIC
    int seq;          // 崩溃的编译序号（取证）
    char message[96]; // 固定错误消息（含序号）
} ame_fake_result_t;

#define AME_FAKE_RESULT_MAGIC        0x5A17EFA2E51DULL
#define AME_FAKE_RESULT_MAGIC_STATIC (0x5A17EFA2E51DULL ^ 1ull)

static int ame_is_fake_result(const void *result) {
    if (result == NULL) return 0;
    uint64_t m = *(const uint64_t *)result;
    return m == AME_FAKE_RESULT_MAGIC || m == AME_FAKE_RESULT_MAGIC_STATIC;
}

static void ame_fake_result_fill(ame_fake_result_t *fr, uint64_t magic, int seq) {
    fr->magic = magic;
    fr->seq = seq;
    snprintf(fr->message, sizeof(fr->message),
             "[amethyst] shaderc compile #%d crashed twice (shim recovery)", seq);
}

static void *ame_fake_result_create(int seq) {
    ame_fake_result_t *fr = (ame_fake_result_t *)malloc(sizeof(ame_fake_result_t));
    if (fr != NULL) {
        ame_fake_result_fill(fr, AME_FAKE_RESULT_MAGIC, seq);
        return fr;
    }
    // malloc 失败的极端场景：静态兑底件（magic 低位翻转，release 识别跳过 free）。
    static ame_fake_result_t s_static_fake;
    ame_fake_result_fill(&s_static_fake, AME_FAKE_RESULT_MAGIC_STATIC, seq);
    return &s_static_fake;
}

// ---- result 访问器族：fake → 合成值；真实对象 → 转发 impl ----
// （拿不到 impl 符号时返回安全值，绝不把 NULL 指针交给 impl 解引用）。
// shaderc_compilation_status 枚举： success=0 / invalid_stage=1 /
// compilation_error=2 / internal_error=3 —— fake 报 3。

void shaderc_result_release(void *result) {
    if (ame_is_fake_result(result)) {
        if (*(uint64_t *)result == AME_FAKE_RESULT_MAGIC) free(result);
        return;
    }
    void *real = ame_shaderc_shim_resolve("shaderc_result_release");
    if (real == NULL || result == NULL) return;
    ((void (*)(void *))real)(result);
}

int shaderc_result_get_compilation_status(void *result) {
    if (ame_is_fake_result(result)) return 3; // shaderc_compilation_status_internal_error
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_compilation_status");
    if (real == NULL || result == NULL) return 3;
    return ((int (*)(void *))real)(result);
}

size_t shaderc_result_get_num_errors(void *result) {
    if (ame_is_fake_result(result)) return 1;
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_num_errors");
    if (real == NULL || result == NULL) return 0;
    return ((size_t (*)(void *))real)(result);
}

size_t shaderc_result_get_num_warnings(void *result) {
    if (ame_is_fake_result(result)) return 0;
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_num_warnings");
    if (real == NULL || result == NULL) return 0;
    return ((size_t (*)(void *))real)(result);
}

const char *shaderc_result_get_error_message(void *result) {
    if (ame_is_fake_result(result))
        return ((ame_fake_result_t *)result)->message;
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_error_message");
    if (real == NULL || result == NULL) return "(shim: result missing)";
    return ((const char *(*)(void *))real)(result);
}

const char *shaderc_result_get_bytes(void *result) {
    if (ame_is_fake_result(result)) return "";
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_bytes");
    if (real == NULL || result == NULL) return "";
    return ((const char *(*)(void *))real)(result);
}

size_t shaderc_result_get_length(void *result) {
    if (ame_is_fake_result(result)) return 0;
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_length");
    if (real == NULL || result == NULL) return 0;
    return ((size_t (*)(void *))real)(result);
}

const char *shaderc_result_get_spv_bytes(void *result) {
    if (ame_is_fake_result(result)) return "";
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_spv_bytes");
    if (real == NULL || result == NULL) return "";
    return ((const char *(*)(void *))real)(result);
}

size_t shaderc_result_get_spv_length(void *result) {
    if (ame_is_fake_result(result)) return 0;
    void *real = ame_shaderc_shim_resolve("shaderc_result_get_spv_length");
    if (real == NULL || result == NULL) return 0;
    return ((size_t (*)(void *))real)(result);
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
