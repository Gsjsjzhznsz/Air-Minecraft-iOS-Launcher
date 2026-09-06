// shaderc_sandbox.m — Task 42：shaderc 编译进程外沙箱实现（见 shaderc_sandbox.h 头注释）
//
// 协议（Unix socket，全双工，小端，定长头 + 变长体）：
//   父→子 request : {u32 magic 'SBQ1'}{u32 kind}{u32 entry}{u32 source_len}
//                   {u32 input_len}{u32 entry_len}{u32 opt_blen}
//                   {source}{input}{entry}{ame_sb_opt_fields_t(定长 POD)}
//   子→父 ready   : {u32 magic 'SBR0'}（spawn 成功且 impl 加载、compiler 初始化后）
//   子→父 response: {u32 magic 'SBR1'}{i32 status}{u32 spv_len}{u32 err_len}
//                   {spv}{err}
//   所有 u32/i32/u64 字段小端；长度字段上限 64MB 防御性校验。
//
// 自愈：请求/响应任何阶段 EOF/ECONNRESET = helper 已死（堆踩踏崩在子进程里，
// 恰是设计目标）→ 回收僵尸 → 重启 helper → 重发同一请求一次；再失败 → 返回
// NULL 让 shim 退回进程内旧路径（Task 34/37/38 崩溃网链，行为不劣于现状）。
// 挂死防护：父 socket 60s 收发超时（helper 单线程无 JVM，正常毫秒级返回）。
//
// 子进程注意：
//   - posix_spawn 自身可执行文件 + env AME_SHADERC_SANDBOX=1 / AME_SB_FD=3；
//     main.m 在【任何】launcher/JVM/hook 初始化之前分支进
//     ame_shaderc_sandbox_child_main（JIT spawn 先例证明设备上可自 spawn）。
//   - 子进程按 <exe_dir>/Frameworks/libshaderc_impl.dylib 绝对路径 dlopen
//     （Task 34 补丁版 impl 与设备上完全同一份）；不经过 shim/不递归。
//   - 每次编译在专用 32MB 栈线程上执行（glslang 深递归，照抄 main_hook.m
//     的 hop 结构——子进程里没有 hooked_dlsym wrapper 兜底，必须自带）。
//   - 子进程 stderr 继承父进程的 latestlog 管道——崩溃网/取证日志直接落盘。

#include "shaderc_sandbox.h"

#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// ---- 基础开关 ----
static int s_sb_is_child = -1;   // -1 未判定 / 0 父进程 / 1 helper 子进程
static int s_sb_fallback_logged = 0; // 沙箱双重失败退回进程内时的一次性日志

int ame_sandbox_active(void) {
    if (s_sb_is_child < 0) {
        const char *mark = getenv("AME_SHADERC_SANDBOX");
        s_sb_is_child = (mark != NULL) ? 1 : 0;
        if (mark != NULL) {
            // helper 子进程：本模块的父侧逻辑永久休眠
            fprintf(stderr, "[shaderc-sandbox] helper process booting (pid=%d)\n", getpid());
        } else if (getenv("AME_SHADERC_SANDBOX_OFF") != NULL) {
            s_sb_is_child = 2; // 显式关闭（调试）：视为"子进程"= 不启用父侧沙箱
            fprintf(stderr, "[shaderc-sandbox] DISABLED by AME_SHADERC_SANDBOX_OFF\n");
        }
    }
    return s_sb_is_child == 0;
}

// ---- 帧收发（带长度防御）----
#define AME_SB_REQ_MAGIC 0x31514253u  // 'SBQ1' LE
#define AME_SB_RDY_MAGIC 0x30525342u  // 'SBR0' LE
#define AME_SB_RSP_MAGIC 0x31525342u  // 'SBR1' LE
#define AME_SB_MAX_BLOB (64u * 1024u * 1024u)

static int sb_send_all(int fd, const void *buf, size_t n) {
    const char *p = (const char *)buf;
    while (n > 0) {
        ssize_t w = send(fd, p, n, 0);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

static int sb_recv_all(int fd, void *buf, size_t n) {
    char *p = (char *)buf;
    while (n > 0) {
        ssize_t r = recv(fd, p, n, 0);
        if (r == 0) return -1; // EOF：helper 死了
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += r;
        n -= (size_t)r;
    }
    return 0;
}

static int sb_recv_u32(int fd, uint32_t *out) {
    return sb_recv_all(fd, out, 4);
}

// ---- 父进程：helper 生命周期 ----
static pid_t s_child_pid = -1;
static int s_child_fd = -1;

static void sb_reap(void) {
    if (s_child_pid > 0) {
        int status = 0;
        waitpid(s_child_pid, &status, WNOHANG);
        s_child_pid = -1;
    }
}

static void sb_kill_child(void) {
    if (s_child_fd >= 0) {
        close(s_child_fd);
        s_child_fd = -1;
    }
    if (s_child_pid > 0) {
        kill(s_child_pid, SIGKILL);
        int status = 0;
        waitpid(s_child_pid, &status, 0);
        s_child_pid = -1;
    }
}

// posix_spawn 自身可执行文件。返回 0 = helper 就绪（收到 ready 握手）。
static int sb_spawn(void) {
    sb_reap();
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) {
        fprintf(stderr, "[shaderc-sandbox] socketpair failed errno=%d\n", errno);
        return -1;
    }
    // 父侧：崩溃写不打 SIGPIPE；60s 收发超时防 helper 挂死拖死游戏
    struct timeval tv;
    tv.tv_sec = 60;
    tv.tv_usec = 0;
    setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fds[0], SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
#ifdef SO_NOSIGPIPE // Darwin；Linux 本地语法检查无此宏（用 MSG_NOSIGNAL 语义等价）
    setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int));
#endif

    char path[4096];
    uint32_t plen = (uint32_t)sizeof path;
    if (_NSGetExecutablePath(path, &plen) != 0) {
        fprintf(stderr, "[shaderc-sandbox] executable path too long\n");
        close(fds[0]);
        close(fds[1]);
        return -1;
    }

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], 3);
    // 信号掩码清零（编译 hop 线程的掩码不该遗传给 helper）
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    sigset_t empty;
    sigemptyset(&empty);
    posix_spawnattr_setsigmask(&attr, &empty);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK);

    // env = environ + AME_SHADERC_SANDBOX=1 + AME_SB_FD=3
    extern char **environ;
    int envc = 0;
    while (environ[envc] != NULL) envc++;
    char **envp = (char **)malloc(sizeof(char *) * (size_t)(envc + 3));
    if (envp == NULL) {
        close(fds[0]);
        close(fds[1]);
        return -1;
    }
    for (int i = 0; i < envc; ++i) envp[i] = environ[i];
    envp[envc] = (char *)"AME_SHADERC_SANDBOX=1";
    envp[envc + 1] = (char *)"AME_SB_FD=3";
    envp[envc + 2] = NULL;

    char *argv_sp[] = {path, (char *)"--shaderc-sandbox", NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, path, &fa, &attr, argv_sp, envp);
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&attr);
    free(envp);
    close(fds[1]); // 父侧只留 fds[0]
    if (rc != 0) {
        fprintf(stderr, "[shaderc-sandbox] posix_spawn failed rc=%d errno=%d\n", rc, errno);
        close(fds[0]);
        return -1;
    }
    s_child_fd = fds[0];
    s_child_pid = pid;

    // ready 握手：确认 helper 完成了 impl dlopen + compiler 初始化
    uint32_t rdy = 0;
    if (sb_recv_u32(s_child_fd, &rdy) != 0 || rdy != AME_SB_RDY_MAGIC) {
        fprintf(stderr,
                "[shaderc-sandbox] helper handshake failed (pid=%d) -- not ready\n", pid);
        sb_kill_child();
        return -1;
    }
    fprintf(stderr, "[shaderc-sandbox] helper spawned and ready (pid=%d)\n", pid);
    return 0;
}

// 请求头（12 个 u32：magic/kind/entry/三段长度/opt_blen —— 打包为定长 40 字节）
typedef struct {
    uint32_t magic;
    uint32_t kind;
    uint32_t entry;
    uint32_t source_len;
    uint32_t input_len;
    uint32_t entry_len;
    uint32_t opt_blen;
    uint32_t reserved[3];
} sb_req_hdr_t;

// ---- 父进程：沙箱编译 ----
void *ame_sandbox_compile(int entry, const char *source, size_t source_size,
                          int kind, const char *input_file, const char *entry_point,
                          const ame_sb_opt_fields_t *opt) {
    if (!ame_sandbox_active()) return NULL;

    ame_sb_opt_fields_t default_opt;
    memset(&default_opt, 0, sizeof default_opt);
    if (opt == NULL) opt = &default_opt;
    const char *input = (input_file != NULL) ? input_file : "";
    const char *ep = (entry_point != NULL) ? entry_point : "";
    size_t input_len = strlen(input);
    size_t ep_len = strlen(ep);
    if (input_len > 4096 || ep_len > 1024) {
        fprintf(stderr, "[shaderc-sandbox] oversize input/entry names -- refusing\n");
        return NULL;
    }

    for (int attempt = 0; attempt < 2; ++attempt) {
        if (s_child_fd < 0 && sb_spawn() != 0) continue;

        sb_req_hdr_t hdr;
        memset(&hdr, 0, sizeof hdr);
        hdr.magic = AME_SB_REQ_MAGIC;
        hdr.kind = (uint32_t)kind;
        hdr.entry = (uint32_t)entry;
        hdr.source_len = (uint32_t)source_size;
        hdr.input_len = (uint32_t)input_len;
        hdr.entry_len = (uint32_t)ep_len;
        hdr.opt_blen = (uint32_t)sizeof(ame_sb_opt_fields_t);

        if (sb_send_all(s_child_fd, &hdr, sizeof hdr) != 0 ||
            sb_send_all(s_child_fd, source, source_size) != 0 ||
            sb_send_all(s_child_fd, input, input_len + 1) != 0 ||
            sb_send_all(s_child_fd, ep, ep_len + 1) != 0 ||
            sb_send_all(s_child_fd, opt, sizeof *opt) != 0) {
            fprintf(stderr,
                    "[shaderc-sandbox] request send failed (attempt %d/2) -- helper died? "
                    "respawning\n",
                    attempt + 1);
            sb_kill_child();
            continue;
        }

        // 响应：{magic, status, spv_len, err_len, spv, err}
        uint32_t rh[4];
        if (sb_recv_all(s_child_fd, rh, sizeof rh) != 0) {
            fprintf(stderr,
                    "[shaderc-sandbox] response read failed (attempt %d/2) -- helper "
                    "crashed mid-compile, respawning\n",
                    attempt + 1);
            sb_kill_child();
            continue;
        }
        if (rh[0] != AME_SB_RSP_MAGIC || rh[1] > 64u || rh[2] > AME_SB_MAX_BLOB ||
            rh[3] > 1024u * 1024u) {
            fprintf(stderr,
                    "[shaderc-sandbox] malformed response header (attempt %d/2)\n",
                    attempt + 1);
            sb_kill_child();
            continue;
        }
        uint32_t spv_len = rh[2];
        uint32_t err_len = rh[3];
        ame_sb_result_t *res = (ame_sb_result_t *)malloc(sizeof(ame_sb_result_t) +
                                                          spv_len + err_len + 1);
        if (res == NULL) return NULL; // OOM：让 shim 走合成失败
        res->magic = AME_SB_RESULT_MAGIC;
        res->status = (int32_t)rh[1];
        res->spv_len = spv_len;
        res->err_len = err_len;
        char *spv = (char *)ame_sb_result_spv(res);
        char *err = (char *)ame_sb_result_err(res);
        if ((spv_len && sb_recv_all(s_child_fd, spv, spv_len) != 0) ||
            sb_recv_all(s_child_fd, err, err_len + 1) != 0) {
            fprintf(stderr,
                    "[shaderc-sandbox] response body read failed (attempt %d/2)\n",
                    attempt + 1);
            free(res);
            sb_kill_child();
            continue;
        }
        return res;
    }
    if (!s_sb_fallback_logged) {
        s_sb_fallback_logged = 1;
        fprintf(stderr,
                "[shaderc-sandbox] sandbox exhausted 2 attempts -- falling back to "
                "in-process compile (legacy crash-net path)\n");
    }
    return NULL;
}

// ---- 子进程：impl 解析与 32MB 栈 hop ----
typedef void *(*ame_impl_compile_fn)(void *, const char *, size_t, int, const char *,
                                     const char *, void *);
typedef void *(*ame_impl_init_fn)(void);
typedef void (*ame_impl_release_fn)(void *);
typedef void (*ame_impl_set_int_fn)(void *, int);
typedef void (*ame_impl_set_env_fn)(void *, int, unsigned);
typedef void (*ame_impl_set_vp_fn)(void *, int, int);
typedef void (*ame_impl_macro_fn)(void *, const char *, size_t, const char *, size_t);
typedef int (*ame_impl_result_status_fn)(void *);
typedef const char *(*ame_impl_result_bytes_fn)(void *);
typedef size_t (*ame_impl_result_len_fn)(void *);
typedef const char *(*ame_impl_result_msg_fn)(void *);

typedef struct {
    void *compiler;
    ame_impl_compile_fn into_spv;
    ame_impl_compile_fn into_asm;
    ame_impl_compile_fn into_pre;
    ame_impl_init_fn opt_init;
    ame_impl_release_fn opt_release;
    ame_impl_set_env_fn opt_set_env;
    ame_impl_set_int_fn opt_set_lang;
    ame_impl_set_int_fn opt_set_opt;
    ame_impl_set_int_fn opt_set_dbg;
    ame_impl_set_vp_fn opt_set_vp;
    ame_impl_macro_fn opt_macro;
    ame_impl_release_fn result_release;
    ame_impl_result_status_fn result_status;
    ame_impl_result_bytes_fn result_spv_bytes;
    ame_impl_result_len_fn result_spv_len;
    ame_impl_result_bytes_fn result_bytes;
    ame_impl_result_len_fn result_len;
    ame_impl_result_msg_fn result_msg;
} sb_impl_t;

static int sb_child_load_impl(sb_impl_t *impl) {
    memset(impl, 0, sizeof *impl);
    char exe[4096];
    uint32_t elen = (uint32_t)sizeof exe;
    if (_NSGetExecutablePath(exe, &elen) != 0) return -1;
    char pathbuf[4096 + 64];
    snprintf(pathbuf, sizeof pathbuf, "%s/Frameworks/libshaderc_impl.dylib", dirname(exe));
    void *h = dlopen(pathbuf, RTLD_NOW | RTLD_LOCAL);
    if (h == NULL) {
        h = dlopen("libshaderc_impl.dylib", RTLD_NOW | RTLD_LOCAL);
    }
    if (h == NULL) {
        fprintf(stderr, "[shaderc-sandbox] child: dlopen impl failed: %s\n", dlerror());
        return -1;
    }
    // 显式解析（各入口类型不同，逐一 dlsym；任何一个缺失都算致命）
    impl->into_spv = (ame_impl_compile_fn)dlsym(h, "shaderc_compile_into_spv");
    impl->into_asm = (ame_impl_compile_fn)dlsym(h, "shaderc_compile_into_spv_assembly");
    impl->into_pre = (ame_impl_compile_fn)dlsym(h, "shaderc_compile_into_preprocessed_text");
    impl->opt_init = (ame_impl_init_fn)dlsym(h, "shaderc_compile_options_initialize");
    impl->opt_release = (ame_impl_release_fn)dlsym(h, "shaderc_compile_options_release");
    impl->opt_set_env = (ame_impl_set_env_fn)dlsym(h, "shaderc_compile_options_set_target_env");
    impl->opt_set_lang = (ame_impl_set_int_fn)dlsym(h, "shaderc_compile_options_set_source_language");
    impl->opt_set_opt = (ame_impl_set_int_fn)dlsym(h, "shaderc_compile_options_set_optimization_level");
    impl->opt_set_dbg = (ame_impl_set_int_fn)dlsym(h, "shaderc_compile_options_set_generate_debug_info");
    impl->opt_set_vp = (ame_impl_set_vp_fn)dlsym(h, "shaderc_compile_options_set_forced_version_profile");
    impl->opt_macro = (ame_impl_macro_fn)dlsym(h, "shaderc_compile_options_add_macro_definition");
    impl->result_release = (ame_impl_release_fn)dlsym(h, "shaderc_result_release");
    impl->result_status = (ame_impl_result_status_fn)dlsym(h, "shaderc_result_get_compilation_status");
    impl->result_spv_bytes = (ame_impl_result_bytes_fn)dlsym(h, "shaderc_result_get_spv_bytes");
    impl->result_spv_len = (ame_impl_result_len_fn)dlsym(h, "shaderc_result_get_spv_length");
    impl->result_bytes = (ame_impl_result_bytes_fn)dlsym(h, "shaderc_result_get_bytes");
    impl->result_len = (ame_impl_result_len_fn)dlsym(h, "shaderc_result_get_length");
    impl->result_msg = (ame_impl_result_msg_fn)dlsym(h, "shaderc_result_get_error_message");

    ame_impl_init_fn compiler_init = (ame_impl_init_fn)dlsym(h, "shaderc_compiler_initialize");
    ame_impl_release_fn compiler_release = (ame_impl_release_fn)dlsym(h, "shaderc_compiler_release");
    if (compiler_init == NULL) return -1;
    impl->compiler = compiler_init();
    if (impl->compiler == NULL) return -1;
    (void)compiler_release; // compiler 进程级长存（与父进程行为一致）
    return 0;
}

// 32MB 栈 hop（子进程内自带；结构同 main_hook.m 的 ame_run_on_32mb_stack）
typedef struct {
    sb_impl_t *impl;
    int entry;
    const char *source;
    size_t source_size;
    int kind;
    const char *input;
    const char *entry_point;
    ame_sb_opt_fields_t opt;
    void *options;
    void *result;
} sb_job_t;

static void *sb_job_main(void *arg) {
    sb_job_t *job = (sb_job_t *)arg;
    sb_impl_t *im = job->impl;

    // 按影子字段重建 options
    job->options = im->opt_init();
    if (job->options != NULL) {
        im->opt_set_env(job->options, job->opt.target_env, job->opt.target_env_version);
        im->opt_set_opt(job->options, job->opt.optimization_level);
        if (job->opt.generate_debug) im->opt_set_dbg(job->options, 1);
        if (job->opt.source_language) im->opt_set_lang(job->options, job->opt.source_language);
        if (job->opt.has_forced) im->opt_set_vp(job->options, job->opt.forced_version, job->opt.forced_profile);
        for (int i = 0; i < job->opt.macro_count && i < AME_SB_MAX_MACROS; ++i) {
            const char *name = job->opt.macro_name[i];
            const char *value = job->opt.macro_value[i];
            if (job->opt.macro_has_value[i]) {
                im->opt_macro(job->options, name, strlen(name), value, strlen(value));
            } else {
                im->opt_macro(job->options, name, strlen(name), NULL, 0);
            }
        }
    }

    ame_impl_compile_fn fn = (job->entry == 1) ? im->into_asm
                             : (job->entry == 2) ? im->into_pre
                                                 : im->into_spv;
    job->result = fn(im->compiler, job->source, job->source_size, job->kind, job->input,
                     job->entry_point, job->options);
    return NULL;
}

static void *sb_run_on_32mb(void *(*main_fn)(void *), void *job) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 32ull * 1024ull * 1024ull);
    pthread_t tid;
    int rc = pthread_create(&tid, &attr, main_fn, job);
    pthread_attr_destroy(&attr);
    if (rc != 0) return NULL; // 极端 OOM：返回失败结果（status=3）
    pthread_join(tid, NULL);
    return job;
}

// ---- 子进程：服务循环 ----
int ame_shaderc_sandbox_child_main(void) {
    const char *fd_s = getenv("AME_SB_FD");
    int fd = (fd_s != NULL) ? atoi(fd_s) : 3;
    if (fd <= 0) fd = 3;

    sb_impl_t impl;
    if (sb_child_load_impl(&impl) != 0) {
        fprintf(stderr, "[shaderc-sandbox] child: impl load failed -- exiting\n");
        return 1;
    }
    uint32_t rdy = AME_SB_RDY_MAGIC;
    if (sb_send_all(fd, &rdy, 4) != 0) return 0; // 父进程已退出

    fprintf(stderr, "[shaderc-sandbox] child loop online (compiler=%p)\n", impl.compiler);

    for (;;) {
        sb_req_hdr_t hdr;
        if (sb_recv_all(fd, &hdr, sizeof hdr) != 0) return 0; // EOF：父进程退出
        if (hdr.magic != AME_SB_REQ_MAGIC || hdr.source_len > AME_SB_MAX_BLOB ||
            hdr.input_len > 8192 || hdr.entry_len > 2048 ||
            hdr.opt_blen != sizeof(ame_sb_opt_fields_t)) {
            fprintf(stderr, "[shaderc-sandbox] child: malformed request header\n");
            return 2;
        }

        char *source = (char *)malloc(hdr.source_len ? hdr.source_len : 1);
        char *input = (char *)malloc(hdr.input_len + 2);
        char *ep = (char *)malloc(hdr.entry_len + 2);
        if (source == NULL || input == NULL || ep == NULL) {
            free(source);
            free(input);
            free(ep);
            return 3;
        }
        if ((hdr.source_len && sb_recv_all(fd, source, hdr.source_len) != 0) ||
            sb_recv_all(fd, input, hdr.input_len + 1) != 0 ||
            sb_recv_all(fd, ep, hdr.entry_len + 1) != 0) {
            free(source);
            free(input);
            free(ep);
            return 0; // 传输中断
        }
        ame_sb_opt_fields_t opt;
        if (sb_recv_all(fd, &opt, sizeof opt) != 0) {
            free(source);
            free(input);
            free(ep);
            return 0;
        }

        // 编译（32MB 栈线程上）
        sb_job_t job;
        memset(&job, 0, sizeof job);
        job.impl = &impl;
        job.entry = (int)hdr.entry;
        job.source = source;
        job.source_size = hdr.source_len;
        job.kind = (int)hdr.kind;
        job.input = input;
        job.entry_point = ep;
        job.opt = opt;
        if (sb_run_on_32mb(sb_job_main, &job) == NULL) {
            job.result = NULL;
        }

        // 提取结果
        int status = 3; // internal_error（hop 失败/结果为空时的兜底）
        const char *spv = "";
        size_t spv_len = 0;
        const char *err = "";
        if (job.result != NULL) {
            status = impl.result_status(job.result);
            spv = impl.result_spv_bytes(job.result);
            spv_len = impl.result_spv_len(job.result);
            if (spv_len == 0) {
                // assembly / preprocessed 文本走 get_bytes/get_length
                spv = impl.result_bytes(job.result);
                spv_len = impl.result_len(job.result);
            }
            const char *m = impl.result_msg(job.result);
            err = (m != NULL) ? m : "";
        } else {
            err = "[sandbox] 32MB stack hop failed (pthread_create)";
        }
        if (spv == NULL) { spv = ""; spv_len = 0; }
        size_t err_len = strlen(err);
        if (err_len > 1024u * 1024u) err_len = 1024u * 1024u;

        uint32_t rh[4];
        rh[0] = AME_SB_RSP_MAGIC;
        rh[1] = (uint32_t)(status & 0xff);
        rh[2] = (uint32_t)spv_len;
        rh[3] = (uint32_t)err_len;
        int ok = sb_send_all(fd, rh, sizeof rh) == 0 &&
                 (spv_len == 0 || sb_send_all(fd, spv, spv_len) == 0) &&
                 sb_send_all(fd, err, err_len + 1) == 0;

        if (job.result != NULL && impl.result_release != NULL) {
            impl.result_release(job.result);
        }
        if (job.options != NULL && impl.opt_release != NULL) {
            impl.opt_release(job.options);
        }
        free(source);
        free(input);
        free(ep);
        if (!ok) return 0; // 父进程断开
    }
}
