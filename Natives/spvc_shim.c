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
// Task206：SPVC_COMPILER_OPTION_GLSL_EMIT_PUSH_CONSTANT_AS_UNIFORM_BUFFER
// = 33 | 0x2000000（本仓 MobileGlues-cpp/include/spirv_cross/spirv_cross_c.h
// 665 行钉值；与随包 impl dylib 同源）。
// ============================================================================

#define AME175_OPTION_GLSL_VERSION (8u | 0x2000000u)
#define AME175_OPTION_GLSL_ES (9u | 0x2000000u)
// Task206（ANGLE 方块透明根修）：不开此项时 SPIRV-Cross 的 GLSL 后端把
// PushConstant 存储类的块输出为【散装 uniform】而非 uniform block——
// glGetUniformBlockIndex("_push_constants") 永远返回 GL_INVALID_INDEX。
// 装机证据（7c0a021 latestlog.old，26.3 fabric + ANGLE 会话）：Task205
// 重放生效后 _uniform_00_00/01 块全部命中（idx 0/1）且 UBO 绑定链激活
// （glUniformBlockBinding + glBindBufferRange），唯独 _push_constants
// NOT FOUND ×206——MC 逐绘制数据（颜色/alpha 调制）从不绑定 = 方块透明。
// MC 桌面 GL 路径自己会开此项（否则它不会按块名查询 push constants），
// 我们的 ES 编译器必须镜像。
#define AME206_OPTION_GLSL_PUSH_CONST_AS_UBO (33u | 0x2000000u)
#define AME175_BACKEND_GLSL 1
#define AME175_CAPTURE_TAKE_OWNERSHIP 1
// Task183：96 -> 1024。病历（59d4b48 装机 latestlog.txt，ANGLE 26.3 FO
// 会话）：MC 资源重载风暴期【并发持有最多 392 个活 spvc context】
//（批量创建、延迟销毁），96 槽的注册表在 t=1-2s/3-4s 两个风暴窗口被打穿
// ——新 context 的 parse 记录被静默丢弃，对应编译器的 ES 重写静默跳过，
// 584/782 个着色器拿到【桌面 GLSL 330 原文】直达 ANGLE ES 3.0 上下文 =
// "ERROR: 0:1" 行 1 解析错误全家桶 -> "Failed to load required shader
// programs" 异常 -> 全管线缺失 -> 58fps 空帧黑屏。改写率逐秒实锤：
// 0s:98% -> 1s:11% -> 2s:79% -> 3s:2%（与活 context 水位完全反相关）。
// 1024 槽（静态 ~80KB）对 392 峰值留 2.6x 余量；仍配最旧驱逐兜底。
#define AME175_REGISTRY_MAX 1024

// Task205：单编译器重命名记录上限（MC 26.3 每着色器 = 接口变量 + uniform 块
// + push constants，几十条量级；超出限频丢弃——重放缺失只会退回原始名，
// 与修前行为一致，不会更坏）。
#define AME205_NAMES_MAX 256

typedef struct {
    unsigned id;
    char *name;
} ame205_rename_t;

typedef struct {
    void *ctx;
    unsigned *words;   // parse_spirv 时留存的 SPIR-V 字副本（本垫片所有）
    size_t word_count;
    void *last_parsed_ir;
    int live;
    unsigned seq;      // Task183：驱逐用序号（越大越新）
} ame175_ctx_entry;

typedef struct {
    void *compiler;
    void *ctx;
    void *parsed_ir;
    int backend;
    int live;
    unsigned seq;      // Task183：驱逐用序号（越新越大）
    // Task205（ANGLE 黑屏根修）：MC 26.3 GlPipelineRecompiler 在【原】编译器
    // 上用 spvc_compiler_set_name 把 uniform 块改名为 _uniform_%02d_%02d /
    // _push_constants、接口变量改为 _vert_input_%02d 等，GlProgram 再靠
    // glGetUniformBlockIndex(重命名) 找块、GlCommandEncoder 靠
    // glBindBufferRange 绑 UBO。而本垫片的 ES 重写用留存 SPIR-V 字【新建】
    // 编译器——MC 的重命名只落在原编译器上，ES 产物块名保持原始名
    //（6209ca4 装机实锤：编译源 "uniform Projecti" 而非 _uniform_00_00）
    //→ glGetUniformBlockIndex 全 -1 → UBO 永不绑定 → 单位矩阵 → 黑屏。
    // 修法：拦截 set_name 记录（id, name），ES 编译器编译前重放。
    ame205_rename_t names[AME205_NAMES_MAX];
    int name_count;
    char *entry_point;   // spvc_compiler_set_entry_point 留存（NULL=未设置）
    int exec_model;
} ame175_compiler_entry;

static unsigned ame183_seq_counter = 0;

// Task183：跳过/驱逐取证（限频：前 4 条全打，其后每 128 条一条）。
static void ame183_skip_log(const char *why, int counter) {
    if (counter <= 4 || (counter % 128) == 0) {
        fprintf(stderr, "[spvc-shim] Task183 rewrite skipped (%s) #%d\n", why, counter);
    }
}

static ame175_ctx_entry ame175_ctx_registry[AME175_REGISTRY_MAX];
static ame175_compiler_entry ame175_compiler_registry[AME175_REGISTRY_MAX];

/// Task205：释放某编译器条目的全部重命名记录（条目复用/驱逐/销毁时调）。
static void ame205_free_names(ame175_compiler_entry *c) {
    if (c == NULL) return;
    for (int i = 0; i < c->name_count && i < AME205_NAMES_MAX; ++i) {
        free(c->names[i].name);
        c->names[i].name = NULL;
    }
    c->name_count = 0;
}

/// Task205：记录 set_name（同 id 重复设置 = 覆盖；溢出限频丢弃）。
static void ame205_record_name(ame175_compiler_entry *c, unsigned id,
                               const char *name) {
    if (c == NULL || name == NULL) return;
    for (int i = 0; i < c->name_count; ++i) {
        if (c->names[i].id == id) {
            char *dup = strdup(name);
            if (dup != NULL) {
                free(c->names[i].name);
                c->names[i].name = dup;
            }
            return;
        }
    }
    if (c->name_count >= AME205_NAMES_MAX) {
        static int s_ame205_drop = 0;
        ++s_ame205_drop;
        ame183_skip_log("rename registry full -- dropping set_name", s_ame205_drop);
        return;
    }
    char *dup = strdup(name);
    if (dup == NULL) return;
    c->names[c->name_count].id = id;
    c->names[c->name_count].name = dup;
    ++c->name_count;
}

/// Task205：按编译器指针找登记条目（未登记返回 NULL）。
static ame175_compiler_entry *ame205_find_compiler(void *compiler) {
    if (compiler == NULL) return NULL;
    for (int i = 0; i < AME175_REGISTRY_MAX; ++i) {
        ame175_compiler_entry *c = &ame175_compiler_registry[i];
        if (c->live && c->compiler == compiler) return c;
    }
    return NULL;
}

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
            e->seq = ++ame183_seq_counter;
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
            e->seq = ++ame183_seq_counter;
            return;
        }
    }
    // Task183：满表驱逐最旧（1024 槽下理论上到不了；到了说明 destroy 链
    // 断了——被逐条目的字副本释放防泄漏，限频打点供装机日志定位）。
    {
        int oldest = 0;
        for (int i = 1; i < AME175_REGISTRY_MAX; ++i) {
            if (ame175_ctx_registry[i].seq < ame175_ctx_registry[oldest].seq) oldest = i;
        }
        static int s_ame183_evict = 0;
        ++s_ame183_evict;
        ame183_skip_log("ctx registry full -- evicting oldest", s_ame183_evict);
        free(ame175_ctx_registry[oldest].words);
        ame175_ctx_entry *e = &ame175_ctx_registry[oldest];
        e->live = 1;
        e->ctx = ctx;
        e->words = NULL;
        if (word_count > 0 && spirv != NULL) {
            e->words = (unsigned *)malloc(word_count * sizeof(unsigned));
            if (e->words != NULL) memcpy(e->words, spirv, word_count * sizeof(unsigned));
        }
        e->word_count = (e->words != NULL) ? word_count : 0;
        e->last_parsed_ir = parsed_ir;
        e->seq = ++ame183_seq_counter;
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
        if (c->live && c->ctx == ctx) {
            ame205_free_names(c);
            free(c->entry_point);
            c->entry_point = NULL;
            memset(c, 0, sizeof(*c));
        }
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
// Task183：256 -> 1024（本轮起选项式清洗副本也注册于此——OIT/clouds
// 系着色器数十起步，且文本兑底路径全量注册；256 槽在大整合包下必满）。
#define AME176_FALLBACK_MAX 1024
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

// ============================================================================
// Task183：ES 输出清洗（选项式/文本式改写之后的第二道后处理）。
// 病历（59d4b48 装机 latestlog.txt，ANGLE 26.3 FO 会话；Task182 命名空间
// 修复让编译真实执行后暴露的下一层——两类 ESSL 300 非法构造）：
//
//   B 族（OIT 输出数组动态索引）："ERROR: 0:190: '[' : array indexes for
//   fragment outputs must be constant integral expressions"——MC 26.x OIT
//   系 fragment 声明 `layout(location = 0) out vec4 coeff[N];` 并用循环
//   变量写 `coeff[attachmentIndex][i] = ...`（桌面 GLSL 330 合法、ESSL 300
//   禁止 fragment 输出数组动态索引）。terrain/block/entity/item/particle/
//   position_color/text 七族 fragment 全军覆没 = 管线缺失大户。修法（移植
//   MobileGlues glsl_for_es.cpp fix_dynamic_output_indexing 同构逻辑）：
//   声明用标记保护 -> 全部 `name[` 访问改走 `name_mgio[`（普通全局数组
//   动态索引合法）-> 声明后补 `TYPE name_mgio[N];` 草稿声明 -> main 尾部
//   插入常量索引复制（name[k] = name_mgio[k]）。
//
//   C 族（buffer 纹理扩展）：clouds.vsh 的 `uniform isamplerBuffer
//   CloudFaces` + texelFetch 线性取数——spvc ES300 输出原样保留类型并加
//   `#extension GL_EXT_texture_buffer : require`（第 2 行），ANGLE ES 3.0
//   上下文无此扩展直接拒绝（clouds 管线在 required 名单里，缺失 = 整个
//   ShaderManager reload 抛异常）。修法（模拟，与 tinygl4angle 侧
//   glTexBuffer PBO 桥的 256 宽铺图对齐）：删扩展行 + samplerBuffer 族
//   -> sampler2D 族（保 i/u 前缀）+ 仅对 buffer 派生的采样器把
//   texelFetch(S, X) 线性索引折叠为 ivec2((X) & 255, (X) >> 8)。
//
// 入参为待清洗 ES 源；需清洗时返回 malloc 副本（调用方注册进 ctx 兜底
// 表随 destroy 释放），无需清洗返回 NULL（调用方沿用原指针）。
// ============================================================================

static int ame183_is_ident(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '_';
}

/// 有界子串搜索（Darwin string.h 不声明 memmem，避免隐式声明告警）。
static const char *ame183_memem(const char *hay, size_t hlen, const char *needle, size_t nlen) {
    if (nlen == 0 || hay == NULL || hlen < nlen) return NULL;
    for (size_t i = 0; i + nlen <= hlen; ++i) {
        if (memcmp(hay + i, needle, nlen) == 0) return hay + i;
    }
    return NULL;
}

/// 词边界受限的全量替换：把 `from[`（from 为完整标识符且后随 '['）换成
/// `to[`。返回新 malloc 缓冲；无命中返回 NULL。
static char *ame183_replace_out_accesses(const char *src, const char *from, const char *to) {
    size_t flen = strlen(from), tlen = strlen(to);
    size_t hits = 0;
    const char *p = src;
    while ((p = strstr(p, from)) != NULL) {
        if (p[flen] == '[' && (p == src || !ame183_is_ident(p[-1]))) ++hits;
        p += flen;
    }
    if (hits == 0) return NULL;
    char *out = (char *)malloc(strlen(src) + hits * (tlen - flen) + 1);
    if (out == NULL) return NULL;
    char *w = out;
    const char *r = src;
    while (*r) {
        if (strncmp(r, from, flen) == 0 && r[flen] == '[' &&
            (r == src || !ame183_is_ident(r[-1]))) {
            memcpy(w, to, tlen);
            w += tlen;
            r += flen;
        } else {
            *w++ = *r++;
        }
    }
    *w = '\0';
    return out;
}

/// 在 [s, e) 里跳过空白。
static const char *ame183_skipws(const char *s, const char *e) {
    while (s < e && (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r')) ++s;
    return s;
}

/// 读一个标识符到 buf（<=cap-1），返回结尾；失败返回 NULL。
static const char *ame183_read_ident(const char *s, const char *e, char *buf, size_t cap) {
    size_t n = 0;
    while (s < e && ame183_is_ident(*s)) {
        if (n + 1 < cap) buf[n++] = *s;
        ++s;
    }
    if (n == 0) return NULL;
    buf[n] = '\0';
    return s;
}

typedef struct {
    char name[64];
    char decl[192];   // 原声明全文（含分号）
    int n;            // 数组元素数
} ame183_outarr_t;

/// 解析一个 "out" 声明（调用点已确认 word=="out" 且前向布局可选）。
/// 成功时填 name/decl/n，返回声明结束（';' 之后）在 src 里的偏移；
/// 不是输出数组声明返回 -1。
static long ame183_parse_out_array(const char *src, size_t len, size_t out_at, ame183_outarr_t *out) {
    const char *e = src + len;
    const char *p = src + out_at + 3;  // 跳过 "out"
    char prec[16] = "", type[40], name[64];
    p = ame183_skipws(p, e);
    if (p >= e) return -1;
    // 可选精度
    if (strncmp(p, "highp", 5) == 0 || strncmp(p, "mediump", 7) == 0 || strncmp(p, "lowp", 4) == 0) {
        const char *w = p;
        while (w < e && ame183_is_ident(*w)) ++w;
        size_t pl = (size_t)(w - p);
        if (pl < sizeof(prec)) { memcpy(prec, p, pl); prec[pl] = '\0'; }
        p = ame183_skipws(w, e);
    }
    p = ame183_read_ident(p, e, type, sizeof(type));
    if (p == NULL) return -1;
    p = ame183_skipws(p, e);
    p = ame183_read_ident(p, e, name, sizeof(name));
    if (p == NULL) return -1;
    p = ame183_skipws(p, e);
    if (p >= e || *p != '[') return -1;
    ++p;
    p = ame183_skipws(p, e);
    if (p >= e || *p < '0' || *p > '9') return -1;
    long n = 0;
    while (p < e && *p >= '0' && *p <= '9') { n = n * 10 + (*p - '0'); ++p; }
    p = ame183_skipws(p, e);
    if (p >= e || *p != ']') return -1;
    ++p;
    p = ame183_skipws(p, e);
    if (p >= e || *p != ';') return -1;
    ++p;
    if (n <= 0 || n > 64) return -1;
    snprintf(out->name, sizeof(out->name), "%s", name);
    snprintf(out->decl, sizeof(out->decl), "%.*s", (int)(p - (src + out_at)), src + out_at);
    out->n = (int)n;
    (void)prec;
    return (long)(p - src);
}

/// B 族主逻辑：返回清洗后的 malloc 缓冲或 NULL。
static char *ame183_fix_output_arrays(const char *src) {
    ame183_outarr_t arrs[16];
    int arr_count = 0;
    // (a) 找全部输出数组声明。为支持"边找边标"的两遍处理，先收集。
    typedef struct { size_t at; long end; } span_t;
    span_t spans[16];
    size_t i = 0;
    while (i + 3 < strlen(src) && arr_count < 16) {
        if (src[i] == 'o' && src[i+1] == 'u' && src[i+2] == 't' &&
            !ame183_is_ident(src[i+3]) && (i == 0 || !ame183_is_ident(src[i-1]))) {
            ame183_outarr_t a;
            long end = ame183_parse_out_array(src, strlen(src), i, &a);
            if (end > 0) {
                arrs[arr_count] = a;
                spans[arr_count].at = i;
                spans[arr_count].end = end;
                ++arr_count;
                i = (size_t)end;
                continue;
            }
        }
        ++i;
    }
    if (arr_count == 0) return NULL;
    // (b) 声明替换为标记（防止 (c) 改写声明自身）。
    size_t cap = strlen(src) + arr_count * 256 + 64;
    char *cur = (char *)malloc(cap);
    if (cur == NULL) return NULL;
    {
        size_t w = 0, r = 0;
        for (int k = 0; k < arr_count; ++k) {
            size_t seg = spans[k].at - r;
            memcpy(cur + w, src + r, seg);
            w += seg;
            w += (size_t)snprintf(cur + w, cap - w, "@@A183OUT%d@@", k);
            r = (size_t)spans[k].end;
        }
        strcpy(cur + w, src + r);
    }
    // (c) 全部 name[ 访问改走 name_mgio[。
    for (int k = 0; k < arr_count; ++k) {
        char mgio[80];
        snprintf(mgio, sizeof(mgio), "%s_mgio", arrs[k].name);
        char *rep = ame183_replace_out_accesses(cur, arrs[k].name, mgio);
        if (rep != NULL) {
            free(cur);
            cur = rep;
            cap = strlen(cur) + 1;  // 真实容量（精确分配；后续步骤按需 realloc）
        }
    }
    // (d) 标记还原：声明 + 草稿声明（普通全局数组，动态索引合法）。
    for (int k = 0; k < arr_count; ++k) {
        char marker[32], repl[384];
        snprintf(marker, sizeof(marker), "@@A183OUT%d@@", k);
        // decl 形如 "out mediump vec4 coeff[4];"；body = 去掉 "out" 后的
        // "mediump vec4 coeff"（截到 '[' 前，含名字）——补 "_mgio" 即草稿名。
        const char *d = arrs[k].decl;
        const char *body = d + 4;  // 跳过 "out"
        while (*body == ' ' || *body == '\t' || *body == '\n') ++body;
        {
            char typepart[160];
            const char *br = strchr(body, '[');
            size_t tl = br ? (size_t)(br - body) : strlen(body) - 1;
            if (tl >= sizeof(typepart)) tl = sizeof(typepart) - 1;
            memcpy(typepart, body, tl);
            typepart[tl] = '\0';
            snprintf(repl, sizeof(repl), "%s\n%s_mgio[%d];", d, typepart, arrs[k].n);
        }
        // 简单标记替换（标记唯一，直接 find/replace 一次）
        char *m = strstr(cur, marker);
        if (m != NULL) {
            size_t ml = strlen(marker), rl = strlen(repl);
            size_t tail = strlen(m + ml);
            if (strlen(cur) - ml + rl + 1 > cap) {
                cap = strlen(cur) - ml + rl + 64;
                cur = (char *)realloc(cur, cap);
                if (cur == NULL) return NULL;
                m = strstr(cur, marker);
            }
            memmove(m + rl, m + ml, tail + 1);
            memcpy(m, repl, rl);
        }
    }
    // (e) main 尾部插入常量索引复制。
    {
        const char *mp = strstr(cur, "void main(");
        if (mp == NULL) mp = strstr(cur, "void main (");
        if (mp != NULL) {
            const char *brace = strchr(mp, '{');
            if (brace != NULL) {
                int depth = 1;
                const char *q = brace + 1;
                while (*q && depth > 0) {
                    if (*q == '{') ++depth;
                    else if (*q == '}') --depth;
                    ++q;
                }
                if (depth == 0) {
                    size_t close_at = (size_t)(q - cur) - 1;
                    char copies[1024];
                    size_t cl = 0;
                    int rn2 = snprintf(copies + cl, sizeof(copies) - cl,
                        "\n    // mg: constant-index fragment-output copies (ESSL 300, Task183)\n");
                    if (rn2 > 0) cl += (size_t)rn2;
                    for (int k = 0; k < arr_count && cl + 96 < sizeof(copies); ++k) {
                        for (int j = 0; j < arrs[k].n && cl + 96 < sizeof(copies); ++j) {
                            rn2 = snprintf(copies + cl, sizeof(copies) - cl,
                                "    %s[%d] = %s_mgio[%d];\n", arrs[k].name, j, arrs[k].name, j);
                            if (rn2 <= 0) break;
                            cl += (size_t)rn2;
                            if (cl >= sizeof(copies)) { cl = sizeof(copies) - 1; break; }
                        }
                    }
                    size_t need = strlen(cur) + cl + 1;
                    if (need > cap) {
                        cur = (char *)realloc(cur, need + 64);
                        if (cur == NULL) return NULL;
                        // realloc 后 close_at 仍有效（按偏移计算）
                    }
                    memmove(cur + close_at + cl, cur + close_at, strlen(cur + close_at) + 1);
                    memcpy(cur + close_at, copies, cl);
                }
            }
        }
    }
    return cur;
}

/// C 族：buffer 纹理模拟（shader 侧）。返回清洗后 malloc 缓冲或 NULL。
static char *ame183_emulate_texture_buffers(const char *src) {
    if (src == NULL || strstr(src, "samplerBuffer") == NULL) return NULL;
    // (a) 收集 buffer 派生采样器名（uniform [prec] *samplerBuffer NAME[..];）。
    //     token 级扫描：类型 token 以 "samplerBuffer" 结尾（isamplerBuffer/
    //     usamplerBuffer 前缀自动兼容），随后读标识符名。
    char names[8][64];
    int name_count = 0;
    const char *u = src;
    while ((u = strstr(u, "uniform")) != NULL && name_count < 8) {
        if (u == src || !ame183_is_ident(u[-1])) {
            const char *p = u + 7;
            while (*p && *p != ';' && *p != '\n') {
                if (ame183_is_ident(*p)) {
                    const char *tok = p;
                    while (ame183_is_ident(*p)) ++p;
                    size_t tl = (size_t)(p - tok);
                    if (tl >= 13 && strncmp(tok + tl - 13, "samplerBuffer", 13) == 0) {
                        const char *q = p;
                        while (*q == ' ' || *q == '\t') ++q;
                        char nm[64];
                        if (ame183_read_ident(q, q + strlen(q), nm, sizeof(nm)) != NULL) {
                            snprintf(names[name_count], sizeof(names[name_count]), "%s", nm);
                            ++name_count;
                        }
                        break;
                    }
                } else {
                    ++p;
                }
            }
        }
        u += 7;
    }
    // (b) 删 #extension GL_EXT_texture_buffer 行 + 类型替换 + texelFetch 重写。
    //     逐行重建：命中扩展行跳过；行内做类型替换；texelFetch 用括号配对改写。
    size_t cap = strlen(src) * 2 + 4096;
    char *out = (char *)malloc(cap);
    if (out == NULL) return NULL;
    size_t w = 0;
    const char *line = src;
    int changed = 0;
    while (line != NULL && *line != '\0') {
        const char *eol = strchr(line, '\n');
        size_t ll = eol ? (size_t)(eol - line) : strlen(line);
        // 扩展行整行删除
        if (ll > 10 && strncmp(line, "#extension", 10) == 0 &&
            ame183_memem(line, ll, "GL_EXT_texture_buffer", 21) != NULL) {
            changed = 1;
        } else {
            // 行内类型替换
            for (size_t k = 0; k + 13 <= ll; ++k) {
                if (strncmp(line + k, "samplerBuffer", 13) == 0) {
                    memcpy((void *)(out + w), line, k);
                    w += k;
                    memcpy(out + w, "sampler2D", 9);
                    w += 9;
                    line += k + 13;
                    ll -= k + 13;
                    k = (size_t)-1;
                    changed = 1;
                    // 继续处理本行剩余
                    continue;
                }
            }
            memcpy(out + w, line, ll);
            w += ll;
        }
        if (eol != NULL) { out[w++] = '\n'; line = eol + 1; }
        else { line = NULL; }
    }
    out[w] = '\0';
    if (!changed) { free(out); return NULL; }
    // (c) texelFetch 重写（只动 buffer 派生采样器）。
    for (int k = 0; k < name_count; ++k) {
        size_t nl = strlen(names[k]);
        const char *tf = out;
        while ((tf = strstr(tf, "texelFetch")) != NULL) {
            if (tf != out && ame183_is_ident(tf[-1])) { ++tf; continue; }
            const char *par = tf + 10;
            while (*par == ' ' || *par == '\t') ++par;
            if (*par != '(') { ++tf; continue; }
            // 第一参数须是 buffer 采样器名
            const char *a1 = par + 1;
            while (*a1 == ' ' || *a1 == '\t') ++a1;
            if (strncmp(a1, names[k], nl) != 0 || ame183_is_ident(a1[nl])) { ++tf; continue; }
            const char *comma = a1 + nl;
            while (*comma == ' ' || *comma == '\t') ++comma;
            if (*comma != ',') { ++tf; continue; }
            // 括号配对
            const char *close = NULL;
            {
                int depth2 = 0;
                const char *q2 = par;
                for (; *q2; ++q2) {
                    if (*q2 == '(') ++depth2;
                    else if (*q2 == ')') { --depth2; if (depth2 == 0) { close = q2; break; } }
                }
            }
            if (close == NULL) break;
            // 坐标表达式 = comma+1 .. 前一个顶层 ')' 之间（去掉外层包裹）
            // 支持两种形态：texelFetch(S, X) / texelFetch(S, ivec2(X), 0)
            const char *coordBegin = comma + 1;
            const char *coordEnd = close;
            const char *cursor = comma + 1;
            int d2 = 0;
            const char *lastTopComma = NULL;
            for (const char *q2 = comma + 1; q2 < close; ++q2) {
                if (*q2 == '(') ++d2;
                else if (*q2 == ')') --d2;
                else if (*q2 == ',' && d2 == 0) lastTopComma = q2;
            }
            int thirdArgZero = 0;
            if (lastTopComma != NULL) {
                // 3 参形态：第 2 参须是 ivec2(...)，第 3 参须是 0
                const char *a3 = lastTopComma + 1;
                while (*a3 == ' ' || *a3 == '\t') ++a3;
                if (*a3 == '0' && (a3 + 1 == close)) thirdArgZero = 1;
                coordEnd = lastTopComma;
            }
            (void)cursor;
            // ivec2( 剥壳
            const char *cb = coordBegin;
            while (cb < coordEnd && (*cb == ' ' || *cb == '\t')) ++cb;
            const char *ce = coordEnd;
            while (ce > cb && (ce[-1] == ' ' || ce[-1] == '\t')) --ce;
            if (ce - cb > 7 && strncmp(cb, "ivec2(", 6) == 0) {
                // 校验闭合
                int d3 = 0;
                const char *q3;
                for (q3 = cb; q3 < ce; ++q3) {
                    if (*q3 == '(') ++d3;
                    else if (*q3 == ')') { --d3; if (d3 == 0) break; }
                }
                if (d3 == 0 && q3 + 1 == ce) { cb += 6; ce -= 1; }
            }
            if (!thirdArgZero && lastTopComma != NULL) { ++tf; continue; }  // 不认识的形态
            // 重建：texelFetch(NAME, ivec2((X) & 255, (X) >> 8), 0)
            size_t coordLen = (size_t)(ce - cb);
            size_t frag2 = 14 + nl + 32 + coordLen * 2 + 16;
            char *repl2 = (char *)malloc(frag2);
            if (repl2 == NULL) break;
            int rn = snprintf(repl2, frag2, "texelFetch(%.*s, ivec2((%.*s) & 255, (%.*s) >> 8), 0)",
                              (int)nl, names[k], (int)coordLen, cb, (int)coordLen, cb);
            if (rn <= 0) { free(repl2); break; }
            // Task183：先记偏移再换缓冲（tf/close 指向旧块，free 后即悬垂）。
            size_t tfOff = (size_t)(tf - out);
            size_t segLen = (size_t)(close + 1 - tf);
            size_t newTotal = strlen(out) - segLen + (size_t)rn + 1;
            char *buf2 = (char *)malloc(newTotal);
            if (buf2 == NULL) { free(repl2); break; }
            memcpy(buf2, out, tfOff);
            memcpy(buf2 + tfOff, repl2, (size_t)rn);
            memcpy(buf2 + tfOff + (size_t)rn, close + 1, strlen(close + 1) + 1);
            free(repl2);
            free(out);
            out = buf2;
            tf = out + tfOff + (size_t)rn;
        }
    }
    return out;
}

/// Task183 总入口：B + C 清洗。返回 malloc 副本或 NULL（无需清洗）。
static char *ame183_sanitize_essl(const char *essl) {
    if (essl == NULL) return NULL;
    char *c_fixed = ame183_emulate_texture_buffers(essl);
    const char *base = (c_fixed != NULL) ? c_fixed : essl;
    char *b_fixed = ame183_fix_output_arrays(base);
    if (b_fixed != NULL) {
        free(c_fixed);
        return b_fixed;
    }
    return c_fixed;
}

/// 在同一 context 上重建 ES 编译器并编译；失败返回 NULL（调用方回落原源）。
/// Task205：新增 orig 参数——把 MC 在【原】编译器上的 spvc_compiler_set_name
/// 重命名与 set_entry_point 重放到新建的 ES 编译器上（见结构体注释；不重放
/// 则块名保持原始名，MC 的 glGetUniformBlockIndex 全 -1 → 黑屏）。
static const char *ame175_compile_es_source(void *ctx, const unsigned *words,
                                            size_t word_count,
                                            ame175_compiler_entry *orig) {
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
    typedef void (*set_name_fn_t)(void *, unsigned, const char *);
    /* Task205c：真库返回 spvc_result（枚举 = int ABI）；重放调用点忽略返回值，
     * 但转换类型必须与真函数一致（初版 void 转换是 ABI 错误）。 */
    typedef int (*set_entry_fn_t)(void *, const char *, int);

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
            // Task206：push-constant 块以 UBO 形态输出（见常量区病历）
            new_set_opt(opts, AME206_OPTION_GLSL_PUSH_CONST_AS_UBO, 1u);
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
                // Task206：push-constant 块以 UBO 形态输出（见常量区病历）
                old_set_bool(opts, AME206_OPTION_GLSL_PUSH_CONST_AS_UBO, 1);
                if (old_install(es_compiler, opts) == 0) options_ok = 1;
            }
        }
    }
    if (!options_ok) return NULL;  // ES 编译器留在 ctx 上随 destroy 释放

    // Task206 装机锚点：push-constant-as-UBO 已装（下轮日志与 blockIdx
    // 探针对账：_push_constants 应从 4294967295 变为 >= 0）。
    {
        static int s_ame206_pcLogged = 0;
        if (!s_ame206_pcLogged) {
            s_ame206_pcLogged = 1;
            fprintf(stderr,
                    "[spvc-shim] Task206: EMIT_PUSH_CONSTANT_AS_UNIFORM_BUFFER "
                    "enabled on ES compiler (_push_constants becomes a queryable "
                    "uniform block)\n");
        }
    }

    // Task205：重放重命名 + 入口点。SPIR-V result id 在同一份字上确定性
    // 一致，直接按记录的 id 重放到新编译器即可。任一步失败不阻断——
    // 缺失重命名只是退回原始块名（与修前行为一致），后续装机会从
    // glGetUniformBlockIndex 的返回值里现形。
    int ame205_replayed = 0;
    const char *ame205_entry = NULL;
    if (orig != NULL) {
        set_name_fn_t real_set_name =
            (set_name_fn_t)ame_spvc_shim_resolve("spvc_compiler_set_name");
        set_entry_fn_t real_set_entry =
            (set_entry_fn_t)ame_spvc_shim_resolve("spvc_compiler_set_entry_point");
        if (real_set_name != NULL) {
            for (int i = 0; i < orig->name_count && i < AME205_NAMES_MAX; ++i) {
                if (orig->names[i].name == NULL) continue;
                real_set_name(es_compiler, orig->names[i].id, orig->names[i].name);
                ++ame205_replayed;
            }
        }
        if (real_set_entry != NULL && orig->entry_point != NULL) {
            real_set_entry(es_compiler, orig->entry_point, orig->exec_model);
            ame205_entry = orig->entry_point;
        }
        static int s_ame205_replayLogged = 0;
        if (s_ame205_replayLogged < 4) {
            ++s_ame205_replayLogged;
            fprintf(stderr,
                    "[spvc-shim] Task205 rename replay: %d names%s applied to ES "
                    "compiler (blocks like _uniform_00_XX / _push_constants survive "
                    "the ES rewrite now)\n",
                    ame205_replayed,
                    ame205_entry ? " + entry point" : "");
        }
    }

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
        // Task183：静默跳过取证（59d4b48 病历：584/782 静默拿到桌面源，
        // 零日志零线索——本轮起每个跳过分支都限频打点）。
        static int s_ame183_noComp = 0;
        static int s_ame183_noCtx = 0;
        if (ame175_ce == NULL) {
            ++s_ame183_noComp;
            ame183_skip_log("compiler unregistered", s_ame183_noComp);
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
                    ame175_ce->ctx, ame175_ctxe->words, ame175_ctxe->word_count,
                    ame175_ce);   // Task205：携带原编译器条目 → 重放 set_name 重命名
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
                    // Task183：ES 输出清洗（B：OIT 输出数组动态索引；
                    // C：texture buffer 模拟）。选项式输出是 ctx 内存的
                    // const 指针，不可原地改——清洗副本注册进兜底表。
                    static int s_ame183_saniLogged = 0;
                    char *ame183_san = ame183_sanitize_essl(ame176_final);
                    if (ame183_san != NULL) {
                        const char *ame183_reg = ame176_register_fallback(ame175_ce->ctx, ame183_san);
                        if (ame183_reg != NULL) {
                            ame176_final = ame183_reg;
                            if (s_ame183_saniLogged < 4) {
                                ++s_ame183_saniLogged;
                                fprintf(stderr,
                                        "[spvc-shim] Task183 ESSL sanitized (output-array/texbuf, head48='%.48s')\n",
                                        ame176_final);
                            }
                        }
                    }
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
            } else {
                // Task183：ctx 缺失 / ir 失配 / 字丢失 —— 限频打点。
                ++s_ame183_noCtx;
                ame183_skip_log("ctx missing or ir mismatch", s_ame183_noCtx);
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
        if (ame175_slot < 0) {
            // Task183：满表驱逐最旧（同 ctx 注册表间架；1024 槽下为断链兜底）。
            ame175_slot = 0;
            for (int i = 1; i < AME175_REGISTRY_MAX; ++i) {
                if (ame175_compiler_registry[i].seq < ame175_compiler_registry[ame175_slot].seq) ame175_slot = i;
            }
            static int s_ame183_cevict = 0;
            ++s_ame183_cevict;
            ame183_skip_log("compiler registry full -- evicting oldest", s_ame183_cevict);
        }
        ame175_compiler_registry[ame175_slot].live = 1;
        ame175_compiler_registry[ame175_slot].compiler = *compiler;
        ame175_compiler_registry[ame175_slot].ctx = context;
        ame175_compiler_registry[ame175_slot].parsed_ir = parsed_ir;
        ame175_compiler_registry[ame175_slot].backend = backend;
        ame175_compiler_registry[ame175_slot].seq = ++ame183_seq_counter;
        // Task205：槽位复用/驱逐时彻底清掉旧条目的重命名与入口点记录，
        // 防止上一着色器的名字重放到这个新编译器上（id 同源但语义不同）。
        ame205_free_names(&ame175_compiler_registry[ame175_slot]);
        free(ame175_compiler_registry[ame175_slot].entry_point);
        ame175_compiler_registry[ame175_slot].entry_point = NULL;
        ame175_compiler_registry[ame175_slot].exec_model = 0;
    }
    pthread_mutex_unlock(ame_spvc_master_or_local());
    fprintf(stderr, "[spvc-shim] create_compiler backend=%d -> %p rc=%d (t=%.0fms "
                    "tid=%lx)\n",
            backend, (compiler ? *compiler : NULL), rc, ame_spvc_shim_ms(),
            ame_spvc_shim_tid());
    return rc;
}

// ============================================================================
// Task205：spvc_compiler_set_name / set_entry_point 拦截（ANGLE 黑屏根修）。
// 垫片此前只导出 6 个入口，其余符号靠 -reexport_library 透传——set_name
// 直达真实库，我们的 ES 重写（新建编译器）对它一无所知。MC 26.3 的
// renameDescriptors/renameInterfaceVariables 把 uniform 块改名为
// _uniform_%02d_%02d / _push_constants、接口变量改为 _vert_input_%02d，
// GlProgram.setupBindGroupLayouts 靠 glGetUniformBlockIndex(新名) 找块、
// GlCommandEncoder 靠 glBindBufferRange 绑 UBO——重命名丢失 = 块查询
// 全 -1 = 矩阵永不绑定 = 单位变换黑屏（6209ca4 装机：块名 "Projecti"
// 存活、glBindBufferRange 零触发、glMapBufferRange(UBO) 2000+ 次全白搭）。
// 这里改为垫片内拦截：转发真实库 + 按编译器登记（id, name），供 ES
// 编译器编译前重放（见 ame175_compile_es_source）。
// ============================================================================
void spvc_compiler_set_name(void *compiler, unsigned id, const char *name) {
    void *real = ame_spvc_shim_resolve("spvc_compiler_set_name");
    pthread_mutex_lock(ame_spvc_master_or_local());
    ame175_compiler_entry *ame205_ce = ame205_find_compiler(compiler);
    if (ame205_ce != NULL) {
        ame205_record_name(ame205_ce, id, name);
    }
    if (real != NULL) {
        ((void (*)(void *, unsigned, const char *))real)(compiler, id, name);
    }
    pthread_mutex_unlock(ame_spvc_master_or_local());
}

// Task205c 返回类型勘误：真头（spirv_cross_c.h）声明本函数返回 spvc_result
// （枚举 = int ABI）——初版拦截写成 void，调用方若检查返回值会读到垃圾
// 寄存器值。现转发真实库的 rc（真库缺失时返回 0 = SPVC_SUCCESS，因为
// 垫片此时仍完成了登记职责；此分支正常装机不会走到）。
int spvc_compiler_set_entry_point(void *compiler, const char *name, int model) {
    void *real = ame_spvc_shim_resolve("spvc_compiler_set_entry_point");
    pthread_mutex_lock(ame_spvc_master_or_local());
    ame175_compiler_entry *ame205_ce = ame205_find_compiler(compiler);
    if (ame205_ce != NULL && name != NULL) {
        char *dup = strdup(name);
        if (dup != NULL) {
            free(ame205_ce->entry_point);
            ame205_ce->entry_point = dup;
            ame205_ce->exec_model = model;
        }
    }
    int ame205_rc = 0;
    if (real != NULL) {
        ame205_rc = ((int (*)(void *, const char *, int))real)(compiler, name, model);
    }
    pthread_mutex_unlock(ame_spvc_master_or_local());
    return ame205_rc;
}
