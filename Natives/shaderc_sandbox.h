// shaderc_sandbox.h — Task 42：shaderc 编译进程外沙箱（Amethyst iOS）
//
// 背景（Task 41 判读，latestlog 45dcc45）：GL 路径资源重载阶段 shaderc/glslang
// 编译风暴中 320 次 SIGSEGV（崩溃点 = TIntermConstantUnion::constArray 指针字段
// 读到浮点位/ASCII 垃圾 = native 堆踩踏），导致 72 个必需管线加载失败 → 游戏
// 崩溃退出。跨 41 个 task 的取证结论：
//   - 主锁（Task 37）已把 shaderc/spvc/MG 三方串行——并发竞态不是根因；
//   - glslang 进程状态重建（Task 38）不愈——毒不在 glslang 持久结构；
//   - 首帧门控（Task 39）生效后仍崩——present 不是破坏者；
//   - 同一二进制同输入：某次 run 390 次编译零崩溃、另一 run 63% 崩——
//     非确定性的进程内 native 堆踩踏（写入者在锁外，日志不可见）。
// 锁防不住进程内的堆破坏者。唯一根治 = 编译彻底离开 JVM 进程：
// 本模块用 posix_spawn 把 App 自身可执行文件作为 helper 子进程拉起
// （main.m 顶部 env 分支 → ame_shaderc_sandbox_child_main），Unix socket
// 全双工传输编译请求/响应。子进程里跑【已打补丁的 libshaderc_impl】
// （Task 34 cave 防护依旧生效）+ 32MB 栈 hop；子进程崩溃 = EOF =
// 父进程重启 helper 并重试一次；两次传输失败才退回进程内旧路径
// （崩溃网 + 合成失败，行为不劣于现状）。
//
// Vulkan / GL 两条路径的 RenderPearl GLSL→SPIR-V 编译都经此沙箱
// （干净进程里编译，两边同样受益；沙箱失效时自动降级，不回归现状）。
//
// Task 43（latestlog 9c98cc7）：posix_spawn 在真机沙盒安装上恒 EPERM
//（505 行失败日志，沙箱从未启动，进程内回退照旧 322 次 SIGSEGV）——
// iOS 沙盒 deny 的是 process-【exec】，plain fork()（不 exec）是允许的
// 线路。因此沙箱拉起策略改为两级：
//   1) fork server（主路径）：main.m 在 init_redirectStdio 之后、
//      JVM/hook/ANGLE 诞生之前 fork() 本进程（无 exec）。子进程在进程
//      只有主线程 + 日志读取线程的时刻分叉——JVM/JIT/渲染线程不存在，
//      踩堆的"外部写入者"在子进程地址空间里【从未运行过】，堆天然纯净；
//      且此时 dyld/malloc 锁全部空闲，子进程可安全 dlopen impl。
//      父进程把 fd/pid 经 setenv 桥接给后期才加载的 shim
//      （AME_SB_FORK_FD / AME_SB_FORK_PID，仅本进程可见）。
//      子进程 stderr 已是 latestlog 管道——子进程取证直接落 latestlog。
//   2) posix_spawn（备用）：TrollStore/no-sandbox 安装上仍然可用
//      （JIT 自 spawn 先例）；失败一次即记死（不再每次编译重试刷屏）。
// 子进程另配崩溃网（sigsetjmp 长跳 + glslang 进程状态重建 + 同一请求
// 最多 4 次尝试）：impl 内崩溃不再等于 helper 死亡——恢复后继续服务，
// 崩溃永远困在子进程地址空间里，父进程（JVM）不可能再被 shaderc 拖死。

#ifndef AME_SHADERC_SANDBOX_H
#define AME_SHADERC_SANDBOX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- options 影子字段（父进程从 shim 拦截的 setter 序列重建，序列化传子进程）----
// MC RenderPearl 每个管线编译前 configure 一遍 options；shim 侧把值存进
// 影子注册表（shaderc_shim.c），编译请求携带快照，子进程按快照重建。
#define AME_SB_MAX_MACROS 16
#define AME_SB_MACRO_NAME_MAX 64
#define AME_SB_MACRO_VALUE_MAX 192
typedef struct {
    int target_env;              // shaderc_target_env
    unsigned target_env_version; // 如 4202496
    int source_language;         // shaderc_source_language
    int optimization_level;      // shaderc_optimization_level
    int generate_debug;          // 0/1
    int has_forced;              // set_forced_version_profile 是否调用过
    int forced_version;          // 强制 GLSL 版本
    int forced_profile;          // 强制 profile 枚举
    int macro_count;             // add_macro_definition 数量
    char macro_name[AME_SB_MAX_MACROS][AME_SB_MACRO_NAME_MAX];
    char macro_value[AME_SB_MAX_MACROS][AME_SB_MACRO_VALUE_MAX];
    unsigned char macro_has_value[AME_SB_MAX_MACROS]; // 0 = 无值宏
} ame_sb_opt_fields_t;

// ---- 沙箱结果对象（父进程 malloc，由 shim 的 result 访问器族识别/释放）----
// 布局：头 + spv 字节 + err 文本（NUL 结尾）。magic 区分于 impl 结果与
// Task 37 的 fake result。
#define AME_SB_RESULT_MAGIC 0x5A17EFA2E515ULL
typedef struct {
    uint64_t magic;
    int32_t status;   // shaderc_compilation_status：0 success / 2 compile_error / 3 internal_error
    uint32_t spv_len; // SPIR-V（或 assembly/preprocessed 文本）字节数
    uint32_t err_len; // 错误消息长度（不含 NUL）
    /* 后跟：char spv[spv_len]; char err[err_len + 1]; */
} ame_sb_result_t;

static inline const char *ame_sb_result_spv(const ame_sb_result_t *r) {
    return (const char *)r + sizeof(ame_sb_result_t);
}
static inline const char *ame_sb_result_err(const ame_sb_result_t *r) {
    return (const char *)r + sizeof(ame_sb_result_t) + r->spv_len;
}

// ---- 父进程侧 API（shaderc_shim.c 调用；实现于 shaderc_sandbox.m）----

// 沙箱是否启用：进程环境无 AME_SHADERC_SANDBOX（即本进程不是 helper 子进程）
// 且未显式关闭（AME_SHADERC_SANDBOX_OFF=1，调试用）。
int ame_sandbox_active(void);

// 沙箱化编译。entry：0=shaderc_compile_into_spv / 1=spv_assembly /
// 2=preprocessed_text（决定字节语义，子进程选用对应 impl 入口）。
// 返回 malloc 的 ame_sb_result_t*（成功/失败皆非 NULL，status 表达编译结果）；
// NULL = 沙箱彻底不可用（spawn/传输双重失败）——调用方退回进程内旧路径。
void *ame_sandbox_compile(int entry, const char *source, size_t source_size,
                          int kind, const char *input_file, const char *entry_point,
                          const ame_sb_opt_fields_t *opt);

// ---- 子进程侧 API（main.m 顶部 env 分支调用）----
// 阻塞服务循环：读请求 → 重建 options → 32MB 栈上编译 → 写响应。
// EOF（父进程退出/关闭）时干净返回 0。
int ame_shaderc_sandbox_child_main(void);

// Task 43：fd 直传版本（fork server 子进程不经 env，直接拿父进程传下的
// socketpair fd 进入服务循环；posix_spawn 路径仍走 env 版）。
int ame_shaderc_sandbox_child_main_fd(int fd);

// ---- fork server 侧 API（main.m 在 init_redirectStdio 之后调用）----
// Task 43：在 JVM/hook/渲染线程诞生前 fork() 编译服务器（不 exec）。
// 返回 0 = fork server 在线（握手完成，fd/pid 已 setenv 桥接给 shim）；
// -1 = fork/握手失败（沙盒禁 fork、impl 加载失败等）——调用方照常继续，
// shim 后续自动走 posix_spawn/进程内旧路径，零行为回退。
// 幂等：重复调用直接返回上次结果；AME_SHADERC_SANDBOX[_OFF] 环境下跳过。
int ame_sb_fork_server_early(void);

#ifdef __cplusplus
}
#endif

#endif // AME_SHADERC_SANDBOX_H
