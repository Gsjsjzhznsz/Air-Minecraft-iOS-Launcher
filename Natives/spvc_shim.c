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
#include <stdlib.h>
#include <string.h>
#include <time.h>

static pthread_mutex_t ame_spvc_shim_lock;  // 本地回退锁（master 协商失败时用）
static pthread_mutex_t *g_ame_master_lock = NULL;
static void *ame_spvc_shim_impl = NULL;
static void *(*ame_spvc_shim_real_dlsym)(void *, const char *) = NULL;

// 前置声明（Task175 区块在文件前部使用，定义在 impl 加载段之后）
static void *ame_spvc_shim_resolve(const char *sym);

// ============================================================================
// Task175：ANGLE 渲染器的桌面 GLSL → GLSL ES 300 重写（pipeline/gui 崩溃根修）
//
// 病历（f484eb7 装机会话 latestlog.old.txt，ANGLE 26.3 FO 包）：
//   [09:19:59] [Render thread/ERROR]: Couldn't compile vertex shader for
//   pipeline (minecraft:core/gui): ERROR: 1:1: '' : syntax error
//   java.lang.IllegalStateException: Failed to find or load pipeline
//   minecraft:pipeline/gui → 崩溃。
// 机制：Task171/172 桥接 + Task173 桌面 GL 补全层生效后游戏已能走到着色器
// 编译；MC 26.3 的 RenderPearl 管线把 GLSL 经 shaderc 编到 SPIR-V 再由
// spirv-cross 交叉编译回【桌面 GLSL 330】（MC 以为是桌面 GL 3.3 上下文——
// tinygl4angle 的 GL_VERSION 就是这么伪装的），glShaderSource 把这份桌面
// GLSL 原样递给底下的 ANGLE GLES3 上下文 → ES 编译器在 1:1 直接语法报错
// （ES 语境的 #version 330 非法）。tinygl4angle.c 的 ES 直通分支（Task173
// 修好上传的那条）只认 "#version NNN es" 开头的源，桌面源走版本改写路径
// 但从不加 "es"——1.1 着色器语法层面无解。
//
// 修法（本垫片内闭环，tinygl4angle/ANGLE 二进制零改动）：拦截
// spvc_compiler_compile —— 真实编译拿到桌面 GLSL（#version >= 130 且非 es）
// 后，用【同一 context 上留存的 SPIR-V 字】重新 parse 一份新鲜 parsed_ir，
// 创建第二个 GLSL 后端编译器并设置 ES 选项（GLSL_ES=1, GLSL_VERSION=300）
// 编译出 ES 源，替换 *source 返回给 MC。MC 随后把 ES 源递给 glShaderSource，
// tinygl4angle 的 ES 直通分支原样上传 → ANGLE GLES3 编译通过。
// 生命周期：ES 编译器挂在与 MC 编译器相同的 context 上，随 MC 自己的
// context_destroy 一并释放；返回的字符串存活期与原始桌面源完全同构
// （都由 context 的 arena 持有到 destroy）。
//
// 门控（防误伤其他渲染器）：AMETHYST_RENDERER（JavaLauncher 对全进程导出）
// 包含 "tinygl4angle" 才启用——mg/zink/vgpu 都是桌面 GL 语义，MC 的桌面
// GLSL 输出是正确的，绝不能重写。逃生阀 AME175_ANGLE_ES_REWRITE=0 强制
// 关闭（分诊用）。
// 选项 API 双形：新版（spvc_context_create_compile_options +
// spvc_compile_options_set_option + spvc_compiler_set_compile_options）优先，
// 旧版（spvc_compiler_create_compiler_options + set_bool/set_uint +
// install_compiler_options）兜底——随包 impl 的导出面两者至少居一。
// 枚举值钉 vendored spirv_cross_c.h：SPVC_COMPILER_OPTION_GLSL_VERSION =
// 8 | 0x2000000，SPVC_COMPILER_OPTION_GLSL_ES = 9 | 0x2000000；
// SPVC_BACKEND_GLSL = 1；SPVC_CAPTURE_MODE_TAKE_OWNERSHIP = 1。
// ============================================================================

#define AME175_OPTION_GLSL_VERSION (8u | 0x2000000u)
#define AME175_OPTION_GLSL_ES (9u | 0x2000000u)
#define AME175_BACKEND_GLSL 1
#define AME175_CAPTURE_TAKE_OWNERSHIP 1
#define AME175_REGISTRY_MAX 96

typedef struct {
    void *ctx;
    unsigned *words;   // parse_spirv 时留存的 SPIR-V 字副本（本垫片所有）
    size_t word_count;
    void *last_parsed_ir;
    int live;
} ame175_ctx_entry;

typedef struct {
    void *compiler;
    void *ctx;
    void *parsed_ir;
    int backend;
    int live;
} ame175_compiler_entry;

static ame175_ctx_entry ame175_ctx_registry[AME175_REGISTRY_MAX];
static ame175_compiler_entry ame175_compiler_registry[AME175_REGISTRY_MAX];

/// 门控：仅 ANGLE（tinygl4angle）渲染器会话启用重写；逃生阀可强制关闭。
static int ame175_rewrite_enabled(void) {
    const char *kill = getenv("AME175_ANGLE_ES_REWRITE");
    if (kill != NULL && strcmp(kill, "0") == 0) return 0;
    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL) return 0;
    return strstr(renderer, "tinygl4angle") != NULL;
}

static void ame175_record_parse(void *ctx, const unsigned *spirv, size_t word_count,
                                void *parsed_ir) {
    for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
        ame175_ctx_entry *e = &ame175_ctx_registry[i];
        if (e->live && e->ctx == ctx) {
            free(e->words);
            e->words = NULL;
            if (word_count > 0 && spirv != NULL) {
                e->words = (unsigned *)malloc(word_count * sizeof(unsigned));
                if (e->words != NULL) memcpy(e->words, spirv, word_count * sizeof(unsigned));
            }
            e->word_count = (e->words != NULL) ? word_count : 0;
            e->last_parsed_ir = parsed_ir;
            return;
        }
    }
    for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
        ame175_ctx_entry *e = &ame175_ctx_registry[i];
        if (!e->live) {
            e->live = 1;
            e->ctx = ctx;
            e->words = NULL;
            if (word_count > 0 && spirv != NULL) {
                e->words = (unsigned *)malloc(word_count * sizeof(unsigned));
                if (e->words != NULL) memcpy(e->words, spirv, word_count * sizeof(unsigned));
            }
            e->word_count = (e->words != NULL) ? word_count : 0;
            e->last_parsed_ir = parsed_ir;
            return;
        }
    }
}

static void ame175_forget_context(void *ctx) {
    for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
        ame175_ctx_entry *e = &ame175_ctx_registry[i];
        if (e->live && e->ctx == ctx) {
            free(e->words);
            memset(e, 0, sizeof(*e));
        }
    }
    for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
        ame175_compiler_entry *c = &ame175_compiler_registry[i];
        if (c->live && c->ctx == ctx) memset(c, 0, sizeof(*c));
    }
}

/// 桌面 GLSL 判定：#version >= 130 且非 "es" 后缀（spirv-cross 输出必以
/// #version 行开头；#version 100/110 是 ES2/上古语义，tinygl4angle 自己
/// 的改写路径能消化，不归本重写管）。
static int ame175_is_desktop_glsl(const char *src) {
    if (src == NULL) return 0;
    if (strncmp(src, "#version ", 9) != 0) return 0;
    if (strncmp(&src[13], "es", 2) == 0) return 0;
    long ver = strtol(&src[9], NULL, 10);
    return ver >= 130;
}

// ============================================================================
// Task176：ES 重写自证 + 文本兑底。
//
// 病历（48a7055 装机日志 latestlog.txt，ANGLE 26.3 FO 会话）：Task175 的
// 选项式重写日志已打出（"desktop GLSL -> GLSL ES 300"），但 ANGLE 仍报
// 与修复前【逐字相同】的 "ERROR: 1:1: '' : syntax error" —— 错误一字不
// 变意味着送达 ANGLE 的源仍是桌面 GLSL：impl 预构建二进制（0.65.0）与
// vendored 源（0.68.0）版本不一致，旧版选项 API（create_compiler_options
// + set_uint/set_bool + install）在 0.65 二进制里可能静默吞掉 es/version
// 选项（源码层面 0.68 的 install 走完整 Options 拷贝无切片，但二进制无从
// 验证）。Task175 只检查了 es_source != NULL，从未验证输出真的是 ES。
//
// 本轮双管齐下：
//   (1) 自证：选项式编译后验证首行确为 "#version NNN es"，不是就丢弃；
//   (2) 文本兑底：对桌面源做版本行替换（#version 330[ core] ->
//       #version 300 es）+ 注入 ES 必需的 precision 声明（ES3 fragment
//       无 float 默认精度，缺了直接编译错）。MC 26.x core 管线的着色器
//       （blit/post/gui：显式 out 变量 + texture()/texelFetch +
//       layout(location)，无 gl_FragData/固定管线）在 ES300 语义下合法。
//       兑底字符串挂 ctx 注册表，context_destroy 时释放（不泄漏）。
//   (3) 取证：前 4 次重写记录最终源的头 48 字节 + 路径（option/textual），
//       下轮装机日志直接看到 ANGLE 实收什么。
// ============================================================================

/// ES 源自证：首行 "#version NNN es"（es 为独立 token）。
static int ame176_is_es_source(const char *src) {
    if (src == NULL) return 0;
    if (strncmp(src, "#version ", 9) != 0) return 0;
    long ver = strtol(&src[9], NULL, 10);
    if (ver < 300) return 0;
    const char *tail = &src[9];
    while (*tail >= '0' && *tail <= '9') ++tail;
    if (tail[0] != ' ') return 0;           // "#version 300\n"（无 profile）= 桌面
    if (strncmp(tail + 1, "es", 2) != 0) return 0;
    char after = tail[3];
    return after == '\n' || after == ' ' || after == '\0';
}

// 兑底字符串注册表（按 ctx 挂靠，destroy 时释放）。
#define AME176_FALLBACK_MAX 256
typedef struct {
    void *ctx;
    char *str;
} ame176_fallback_entry;
static ame176_fallback_entry ame176_fallbacks[AME176_FALLBACK_MAX];
static int ame176_fallback_count = 0;

static void ame176_forget_fallbacks(void *ctx) {
    for (int i = 0; i < ame176_fallback_count;) {
        if (ame176_fallbacks[i].ctx == ctx) {
            free(ame176_fallbacks[i].str);
            ame176_fallbacks[i] = ame176_fallbacks[ame176_fallback_count - 1];
            ame176_fallback_count--;
        } else {
            ++i;
        }
    }
}

static const char *ame176_register_fallback(void *ctx, char *str) {
    if (str == NULL) return NULL;
    if (ame176_fallback_count >= AME176_FALLBACK_MAX) {
        // 表满：释放最老一条（极不可能——一个会话着色器数 < 256 时根本到不了这里；
        // 到了说明 destroy 路径断了，丢最老的防泄漏）。
        free(ame176_fallbacks[0].str);
        for (int i = 1; i < ame176_fallback_count; ++i)
            ame176_fallbacks[i - 1] = ame176_fallbacks[i];
        --ame176_fallback_count;
    }
    ame176_fallbacks[ame176_fallback_count].ctx = ctx;
    ame176_fallbacks[ame176_fallback_count].str = str;
    ++ame176_fallback_count;
    return str;
}

/// 文本兑底：桌面 GLSL -> ES300。返回 malloc 字符串（调用方注册到 ctx）。
/// 版本行替换 + precision 注入；版本行缺失返回 NULL（防御，spirv-cross
/// 输出恒有）。
static char *ame176_textual_es_rewrite(const char *desktop) {
    if (desktop == NULL) return NULL;
    // 跳过可能的前导空白/注释（防御；spirv-cross 输出直接以 #version 开头）
    const char *p = desktop;
    while (*p == '\n' || *p == ' ' || *p == '\t' || *p == '\r') ++p;
    if (strncmp(p, "#version ", 9) != 0) return NULL;
    const char *eol = strchr(p, '\n');
    if (eol == NULL) return NULL;
    static const char *const kAme176Prec =
        "#version 300 es\n"
        "precision highp float;\n"
        "precision highp int;\n"
        "precision highp sampler2D;\n"
        "precision highp sampler3D;\n"
        "precision highp samplerCube;\n"
        "precision highp sampler2DShadow;\n"
        "precision highp samplerCubeShadow;\n"
        "precision highp sampler2DArray;\n"
        "precision highp isampler2D;\n"
        "precision highp usampler2D;\n"
        "precision highp isampler3D;\n"
        "precision highp usampler3D;\n"
        "precision highp image2D;\n"
        "precision highp iimage2D;\n"
        "precision highp uimage2D;\n";
    size_t head_len = strlen(kAme176Prec);
    size_t rest_len = strlen(eol + 1);
    char *out = (char *)malloc(head_len + rest_len + 1);
    if (out == NULL) return NULL;
    memcpy(out, kAme176Prec, head_len);
    memcpy(out + head_len, eol + 1, rest_len);
    out[head_len + rest_len] = '\0';
    return out;
}

/// 在同一 context 上重建 ES 编译器并编译；失败返回 NULL（调用方回落原源）。
static const char *ame175_compile_es_source(void *ctx, const unsigned *words,
                                            size_t word_count) {
    typedef int (*parse_fn_t)(void *, const unsigned *, size_t, void **);
    typedef int (*create_compiler_fn_t)(void *, int, void *, int, void **);
    typedef int (*compile_fn_t)(void *, const char **);
    typedef void *(*ctx_create_opts_fn_t)(void *);
    typedef int (*set_option_fn_t)(void *, unsigned, unsigned);
    typedef int (*compiler_set_opts_fn_t)(void *, void *);
    typedef int (*comp_create_opts_fn_t)(void *, void **);
    typedef int (*set_uint_fn_t)(void *, unsigned, unsigned);
    typedef int (*set_bool_fn_t)(void *, unsigned, int);
    typedef int (*install_opts_fn_t)(void *, void *);

    parse_fn_t real_parse = (parse_fn_t)ame_spvc_shim_resolve("spvc_context_parse_spirv");
    create_compiler_fn_t real_create =
        (create_compiler_fn_t)ame_spvc_shim_resolve("spvc_context_create_compiler");
    compile_fn_t real_compile = (compile_fn_t)ame_spvc_shim_resolve("spvc_compiler_compile");
    if (real_parse == NULL || real_create == NULL || real_compile == NULL) return NULL;

    void *fresh_ir = NULL;
    if (real_parse(ctx, words, word_count, &fresh_ir) != 0 || fresh_ir == NULL) return NULL;

    void *es_compiler = NULL;
    if (real_create(ctx, AME175_BACKEND_GLSL, fresh_ir, AME175_CAPTURE_TAKE_OWNERSHIP,
                    &es_compiler) != 0 ||
        es_compiler == NULL)
        return NULL;

    // 选项双形：新版 API 优先，旧版兜底（两套至少有一套在 impl 导出面上）。
    int options_ok = 0;
    ctx_create_opts_fn_t new_create_opts =
        (ctx_create_opts_fn_t)ame_spvc_shim_resolve("spvc_context_create_compile_options");
    set_option_fn_t new_set_opt =
        (set_option_fn_t)ame_spvc_shim_resolve("spvc_compile_options_set_option");
    compiler_set_opts_fn_t new_install =
        (compiler_set_opts_fn_t)ame_spvc_shim_resolve("spvc_compiler_set_compile_options");
    if (new_create_opts != NULL && new_set_opt != NULL && new_install != NULL) {
        void *opts = new_create_opts(ctx);
        if (opts != NULL) {
            new_set_opt(opts, AME175_OPTION_GLSL_VERSION, 300u);
            new_set_opt(opts, AME175_OPTION_GLSL_ES, 1u);
            if (new_install(es_compiler, opts) == 0) options_ok = 1;
        }
    }
    if (!options_ok) {
        comp_create_opts_fn_t old_create_opts =
            (comp_create_opts_fn_t)ame_spvc_shim_resolve("spvc_compiler_create_compiler_options");
        set_uint_fn_t old_set_uint =
            (set_uint_fn_t)ame_spvc_shim_resolve("spvc_compiler_options_set_uint");
        set_bool_fn_t old_set_bool =
            (set_bool_fn_t)ame_spvc_shim_resolve("spvc_compiler_options_set_bool");
        install_opts_fn_t old_install =
            (install_opts_fn_t)ame_spvc_shim_resolve("spvc_compiler_install_compiler_options");
        if (old_create_opts != NULL && old_set_uint != NULL && old_set_bool != NULL &&
            old_install != NULL) {
            void *opts = NULL;
            if (old_create_opts(es_compiler, &opts) == 0 && opts != NULL) {
                old_set_uint(opts, AME175_OPTION_GLSL_VERSION, 300u);
                old_set_bool(opts, AME175_OPTION_GLSL_ES, 1);
                if (old_install(es_compiler, opts) == 0) options_ok = 1;
            }
        }
    }
    if (!options_ok) return NULL;  // ES 编译器留在 ctx 上随 destroy 释放

    const char *es_source = NULL;
    if (real_compile(es_compiler, &es_source) != 0 || es_source == NULL) return NULL;
    return es_source;
}

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
    // Task175：留存 SPIR-V 字副本 + 本 context 最新 parsed_ir（ES 重写的原料；
    // 失败 parse 不记录，rc==0 且 parsed_ir 非空才算数）
    if (rc == 0 && parsed_ir != NULL && *parsed_ir != NULL) {
        ame175_record_parse(context, spirv, word_count, *parsed_ir);
    }
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
    // Task175：ANGLE 渲染器会话里，MC 要的其实是 ES GLSL——桌面源在
    // tinygl4angle 的 GLES3 上下文上必炸（1:1 syntax error，pipeline/gui
    // 崩溃链）。用留存的 SPIR-V 字重开一个 ES 编译器编译，替换 *source。
    // 任何一步不满足（非 ANGLE / 非 GLSL 后端 / 非桌面源 / 字已失配 /
    // ES 编译失败）都静默回落原始桌面源（行为与旧版一致）。
    if (rc == 0 && source != NULL && *source != NULL && ame175_rewrite_enabled()) {
        ame175_compiler_entry *ame175_ce = NULL;
        for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
            ame175_compiler_entry *c = &ame175_compiler_registry[i];
            if (c->live && c->compiler == compiler) {
                ame175_ce = c;
                break;
            }
        }
        if (ame175_ce != NULL && ame175_ce->backend == AME175_BACKEND_GLSL &&
            ame175_is_desktop_glsl(*source)) {
            ame175_ctx_entry *ame175_ctxe = NULL;
            for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
                ame175_ctx_entry *e = &ame175_ctx_registry[i];
                if (e->live && e->ctx == ame175_ce->ctx) {
                    ame175_ctxe = e;
                    break;
                }
            }
            // 字与编译器同源校验（context 被复用解析过别的模块时放弃重写）
            if (ame175_ctxe != NULL && ame175_ctxe->last_parsed_ir == ame175_ce->parsed_ir &&
                ame175_ctxe->words != NULL && ame175_ctxe->word_count > 0) {
                const char *ame175_es = ame175_compile_es_source(
                    ame175_ce->ctx, ame175_ctxe->words, ame175_ctxe->word_count);
                // Task176：自证——选项式输出必须真的是 "#version NNN es"。
                // 0.65 预构建 impl 与 vendored 源版本不一致，选项可能被静默
                // 吞掉（装机实锤：重写日志已打出但 ANGLE 错误与修前逐字相同）。
                int ame176_viaOption = (ame175_es != NULL && ame176_is_es_source(ame175_es));
                const char *ame176_final = NULL;
                const char *ame176_path = NULL;
                if (ame176_viaOption) {
                    ame176_final = ame175_es;
                    ame176_path = "option";
                } else {
                    // 文本兑底：桌面源版本行替换 + precision 注入。
                    char *ame176_txt = ame176_textual_es_rewrite(*source);
                    if (ame176_txt != NULL) {
                        ame176_final = ame176_register_fallback(ame175_ce->ctx, ame176_txt);
                        ame176_path = "textual";
                    }
                }
                if (ame176_final != NULL) {
                    static int s_ame176_headLogged = 0;
                    if (s_ame176_headLogged < 4) {
                        ++s_ame176_headLogged;
                        fprintf(stderr,
                                "[spvc-shim] Task176 ES rewrite via %s: head48='%.48s'\n",
                                ame176_path, ame176_final);
                    }
                    fprintf(stderr,
                            "[spvc-shim] Task175 ANGLE ES rewrite: desktop GLSL -> GLSL ES "
                            "300 (comp=%p ctx=%p words=%zu path=%s, t=%.0fms)\n",
                            compiler, ame175_ce->ctx, ame175_ctxe->word_count, ame176_path,
                            ame_spvc_shim_ms());
                    *source = ame176_final;
                } else {
                    fprintf(stderr,
                            "[spvc-shim] Task175 ANGLE ES rewrite FAILED -- falling back to "
                            "desktop source (comp=%p option_rc=%s, t=%.0fms)\n",
                            compiler, (ame175_es != NULL) ? "non-es-output" : "null",
                            ame_spvc_shim_ms());
                }
            }
        }
    }
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
    // Task175：context 亡，登记项与留存字一并清（防悬垂指针/泄漏）
    ame175_forget_context(context);
    // Task176：兑底字符串同 ctx 一并释放
    ame176_forget_fallbacks(context);
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
    // Task175：子对象全释 = 本 context 上一切 parsed_ir/编译器/字符串已亡，
    // 留存字与登记项必须同步作废（后续同 context 的新 parse 会重新登记）
    ame175_forget_context(context);
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
    // Task175：登记编译器 ->（context, parsed_ir, backend）供 ES 重写定位
    if (rc == 0 && compiler != NULL && *compiler != NULL) {
        int ame175_slot = -1;
        for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
            ame175_compiler_entry *c = &ame175_compiler_registry[i];
            if (c->live && c->compiler == *compiler) {
                ame175_slot = i;
                break;
            }
            if (!c->live && ame175_slot < 0) ame175_slot = i;
        }
        if (ame175_slot >= 0) {
            ame175_compiler_registry[ame175_slot].live = 1;
            ame175_compiler_registry[ame175_slot].compiler = *compiler;
            ame175_compiler_registry[ame175_slot].ctx = context;
            ame175_compiler_registry[ame175_slot].parsed_ir = parsed_ir;
            ame175_compiler_registry[ame175_slot].backend = backend;
        }
    }
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] create_compiler backend=%d -> %p rc=%d (t=%.0fms "
                    "tid=%lx)\n",
            backend, (compiler ? *compiler : NULL), rc, ame_spvc_shim_ms(),
            ame_spvc_shim_tid());
    return rc;
}
