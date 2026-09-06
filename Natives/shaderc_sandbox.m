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
//
// Task 43 增补（latestlog 9c98cc7：posix_spawn 在真机沙盒上恒 EPERM）：
//   - fork server：main.m 在 init_redirectStdio 之后、JVM/hook/渲染线程诞生
//     之前 fork()（不 exec）——iOS 沙盒 deny 的是 process-exec，plain fork
//     可用；fork 时刻进程只有主线程+日志读取线程，子进程堆天然纯净。
//     fd/pid 经 setenv（AME_SB_FORK_FD/AME_SB_FORK_PID）桥接给后期加载的 shim。
//   - 子进程崩溃网：SEGV/BUS/ILL/FPE/ABRT → siglongjmp 回编译现场（同一
//     32MB 栈线程内），glslang 进程状态重建（Finalize+Initialize+新 compiler）
//     后重试，同一请求最多 4 次；崩溃永远困死于子进程，不再需要“重启
//     helper”。posix_spawn 失败一次即记死（不再每次编译刷屏）。
//   - Linux 可移植守卫（__APPLE__ / /proc/self/exe）：本文件可在 Linux
//     上真实编译运行，支撑 fork 链路功能测试。

#include "shaderc_sandbox.h"

#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// 可移植：取当前可执行文件绝对路径（Darwin _NSGetExecutablePath / Linux
// /proc/self/exe）。返回 0 成功。
static int sb_exe_path(char *buf, uint32_t buflen) {
#ifdef __APPLE__
    return _NSGetExecutablePath(buf, &buflen) != 0 ? -1 : 0;
#else
    ssize_t n = readlink("/proc/self/exe", buf, buflen - 1);
    if (n <= 0) return -1;
    buf[n] = '\0';
    return 0;
#endif
}

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

// ---- Task 43：子进程崩溃网（共享状态与处理器）----
// 子进程没有 JVM：崩溃可以激进恢复（长跳）而不是退出。处理器只做两件事：
// 活动保护区内 → siglongjmp 回保护区；保护区外 → _exit(66)（父进程见
// EOF 自动降级进程内路径，行为不劣于 Task 42）。
// s_active_jmp 指向“当前唯一活动保护区”的跳转目标（子进程同一时刻只有
// 一个编译在进行：32MB 栈 worker 内 or 回路线程的结果提取段）。
static sigjmp_buf *volatile s_sb_active_jmp = NULL;

static void sb_child_sig_handler(int sig, siginfo_t *si, void *uc) {
    (void)si;
    (void)uc;
    sigjmp_buf *j = s_sb_active_jmp;
    if (j == NULL) {
        // 保护区外崩溃（子进程自身 bug）：干净退出，父进程走降级链
        static const char kMsg[] =
            "[shaderc-sandbox] child: fatal crash outside compile guard -- exiting\n";
        (void)write(2, kMsg, sizeof(kMsg) - 1);
        _exit(66);
    }
    s_sb_active_jmp = NULL;
    siglongjmp(*j, sig);
}

static void sb_child_install_net(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = sb_child_sig_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK; // 栈溢出型崩溃也能进处理器
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL); // glslang 内部 assert/abort 同样可恢复
}

// 子进程取证日志：raw write(2)（避开 stdio FILE 锁——fork 瞬间父进程侧
// 理论上可能有线程持锁；信号处理器上下文也可安全使用）。
static void sb_clog(const char *fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    if (n <= 0) return;
    if ((size_t)n >= sizeof buf) n = (int)sizeof buf - 1;
    (void)write(2, buf, (size_t)n);
}

// 保护区线程注册 sigaltstack（64KB；正常路径回收，崩溃路径泄漏可接受）。
static void *sb_altstack_arm(void) {
    void *stk = mmap(NULL, 64 * 1024, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (stk == MAP_FAILED) return NULL;
    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_sp = stk;
    ss.ss_size = 64 * 1024;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) != 0) {
        munmap(stk, 64 * 1024);
        return NULL;
    }
    return stk;
}

static void sb_altstack_disarm(void *stk) {
    if (stk == NULL) return;
    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_flags = SS_DISABLE;
    sigaltstack(&ss, NULL);
    munmap(stk, 64 * 1024);
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
// Task 43：仅作备用拉起路径（TrollStore/no-sandbox 安装可用）；沙盒安装
// 上 EPERM 一次即被调用方记死，不再重复尝试。
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
    if (sb_exe_path(path, (uint32_t)sizeof path) != 0) {
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

// ---- Task 43：fork server（主拉起路径，无 exec）----
// main.m 在 init_redirectStdio 之后、JVM/hook/渲染线程诞生之前调用。
// fork 时刻：stdout/stderr 已接 latestlog 管道（子进程取证直接落盘）；
// 进程只有主线程 + 日志读取线程（read() 阻塞中，不持 malloc/stdio 锁）
// —— fork 后子进程可安全 dlopen impl；父进程 env 桥接 fd/pid 给 shim。
// 幂等；失败返回 -1（调用方照常继续，零行为回退）。
static int s_fork_done = 0;
static int s_fork_rc = -1;

int ame_sb_fork_server_early(void) {
    if (s_fork_done) return s_fork_rc;
    s_fork_done = 1;
    if (getenv("AME_SHADERC_SANDBOX") != NULL) { // helper 本体（spawn 路径）
        s_fork_rc = 0;
        return 0;
    }
    if (getenv("AME_SHADERC_SANDBOX_OFF") != NULL) {
        fprintf(stderr, "[shaderc-sandbox] fork server skipped (Sandbox OFF)\n");
        s_fork_rc = -1;
        return s_fork_rc;
    }
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) {
        fprintf(stderr, "[shaderc-sandbox] fork server: socketpair failed errno=%d\n",
                errno);
        s_fork_rc = -1;
        return s_fork_rc;
    }
    // 握手阶段 10s 超时（impl dlopen + compiler 初始化通常毫秒级）
    struct timeval tv10 = {10, 0};
    setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv10, sizeof tv10);
#ifdef SO_NOSIGPIPE
    setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int));
#endif

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr,
                "[shaderc-sandbox] fork() failed errno=%d -- sandbox disabled "
                "(iOS sandbox denies fork on this install?)\n",
                errno);
        close(fds[0]);
        close(fds[1]);
        s_fork_rc = -1;
        return s_fork_rc;
    }
    if (pid == 0) {
        // 子进程：此后只用 POSIX + impl C API（无 ObjC/CF/dispatch/stdout）
        close(fds[0]);
        int rc = ame_shaderc_sandbox_child_main_fd(fds[1]);
        _exit(rc & 0xff);
    }
    close(fds[1]);
    s_child_fd = fds[0];
    s_child_pid = pid;

    // ready 握手：子进程完成崩溃网安装 + impl dlopen + compiler 初始化
    uint32_t rdy = 0;
    if (sb_recv_u32(s_child_fd, &rdy) != 0 || rdy != AME_SB_RDY_MAGIC) {
        fprintf(stderr,
                "[shaderc-sandbox] fork helper handshake failed (pid=%d) -- "
                "sandbox disabled\n",
                (int)pid);
        sb_kill_child();
        s_fork_rc = -1;
        return s_fork_rc;
    }
    // 握手完成后恢复 60s 收发超时（与 sb_spawn 语义一致）
    struct timeval tv60 = {60, 0};
    setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv60, sizeof tv60);
    setsockopt(fds[0], SOL_SOCKET, SO_SNDTIMEO, &tv60, sizeof tv60);

    // env 桥接：shim（libshaderc.dylib）后期才加载，同进程 getenv 可见
    char fdbuf[16], pidbuf[16];
    snprintf(fdbuf, sizeof fdbuf, "%d", s_child_fd);
    snprintf(pidbuf, sizeof pidbuf, "%d", (int)pid);
    setenv("AME_SB_FORK_FD", fdbuf, 1);
    setenv("AME_SB_FORK_PID", pidbuf, 1);
    fprintf(stderr,
            "[shaderc-sandbox] fork server online (pid=%d, fd=%d) -- Task 43\n",
            (int)pid, s_child_fd);
    s_fork_rc = 0;
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
// Task 43：posix_spawn 失败一次即记死（真机沙盒上恒 EPERM，旧实现每次编译
// 重试 2 次刷出 505 行失败日志）；fork server 的 fd 经 env 桥接惰性收养。
static int s_spawn_dead = 0;    // posix_spawn 永久失败（本进程不再尝试）
static int s_env_adopted = 0;   // AME_SB_FORK_FD 桥接只做一次

static void sb_adopt_fork_env(void) {
    if (s_env_adopted) return;
    s_env_adopted = 1;
    if (s_child_fd >= 0) return; // 已持有（fork server 同映像调用等极端场景）
    const char *fd_s = getenv("AME_SB_FORK_FD");
    if (fd_s == NULL) return;
    int fd = atoi(fd_s);
    if (fd <= 0) return;
    const char *pid_s = getenv("AME_SB_FORK_PID");
    s_child_fd = fd;
    s_child_pid = (pid_s != NULL) ? (pid_t)atoi(pid_s) : -1;
    fprintf(stderr,
            "[shaderc-sandbox] adopted early-fork helper (fd=%d pid=%d) -- Task 43\n",
            fd, (int)s_child_pid);
}

void *ame_sandbox_compile(int entry, const char *source, size_t source_size,
                          int kind, const char *input_file, const char *entry_point,
                          const ame_sb_opt_fields_t *opt) {
    if (!ame_sandbox_active()) return NULL;
    sb_adopt_fork_env(); // Task 43：收养 main() 早期 fork 的 server

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
        if (s_child_fd < 0) {
            if (s_spawn_dead) break; // posix_spawn 已记死：直接降级进程内
            if (sb_spawn() != 0) {
                s_spawn_dead = 1;
                break;
            }
        }

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
// Task 43：glslang 进程级状态重建入口（impl 导出，设备符号名已验证）。
typedef void (*ame_glslang_void_fn)(void);

typedef struct {
    void *compiler;
    void *impl_handle; // dlopen 句柄（重建时 dlsym 用）
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
    ame_impl_init_fn compiler_init;      // Task 43：重建用
    ame_impl_release_fn compiler_release; // Task 43：重建用
    ame_glslang_void_fn glslang_init;     // _ZN7glslang17InitializeProcessEv
    ame_glslang_void_fn glslang_fini;     // _ZN7glslang15FinalizeProcessEv
} sb_impl_t;

static int sb_child_load_impl(sb_impl_t *impl) {
    memset(impl, 0, sizeof *impl);
    char exe[4096];
    if (sb_exe_path(exe, (uint32_t)sizeof exe) != 0) return -1;
    char pathbuf[4096 + 64];
    snprintf(pathbuf, sizeof pathbuf, "%s/Frameworks/libshaderc_impl.dylib", dirname(exe));
    void *h = dlopen(pathbuf, RTLD_NOW | RTLD_LOCAL);
    if (h == NULL) {
        h = dlopen("libshaderc_impl.dylib", RTLD_NOW | RTLD_LOCAL);
    }
    if (h == NULL) {
        sb_clog("[shaderc-sandbox] child: dlopen impl failed: %s\n", dlerror());
        return -1;
    }
    impl->impl_handle = h;
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
    impl->compiler_init = compiler_init;
    impl->compiler_release = compiler_release;
    // Task 43：glslang 进程级重建入口（符号名与 Task 38 设备实测一致）
    impl->glslang_init =
        (ame_glslang_void_fn)dlsym(h, "_ZN7glslang17InitializeProcessEv");
    impl->glslang_fini =
        (ame_glslang_void_fn)dlsym(h, "_ZN7glslang15FinalizeProcessEv");
    impl->compiler = compiler_init();
    if (impl->compiler == NULL) return -1;
    sb_clog("[shaderc-sandbox] child: impl loaded (glslang rebuild %s)\n",
            (impl->glslang_init && impl->glslang_fini) ? "armed" : "unavailable");
    return 0;
}

// ---- Task 43：子进程 glslang 进程状态重建（回路线程上罩网执行）----
// 编译崩溃后毒可能残留在 glslang 跨编译存活的全局结构里（符号表/字符串
// 池/池分配器头）；Finalize+Initialize 全拆重建。释放旧 compiler 本身可能
// 崩（半构造对象）——整段罩在崩溃网里：第一段崩 → 跳过 release 直接
// Finalize+Init；再崩 → 返回 -1（调用方放弃重试/退出子进程）。
static int sb_child_rebuild_core(sb_impl_t *impl, int with_release) {
    if (with_release && impl->compiler != NULL && impl->compiler_release != NULL) {
        impl->compiler_release(impl->compiler);
        impl->compiler = NULL;
    }
    if (impl->glslang_fini != NULL) impl->glslang_fini();
    if (impl->glslang_init != NULL) impl->glslang_init();
    if (impl->compiler_init != NULL) impl->compiler = impl->compiler_init();
    return (impl->compiler != NULL) ? 0 : -1;
}

static int sb_child_rebuild(sb_impl_t *impl) {
    sigjmp_buf j;
    s_sb_active_jmp = &j;
    if (sigsetjmp(j, 1) == 0) {
        int rc = sb_child_rebuild_core(impl, 1);
        s_sb_active_jmp = NULL;
        return rc;
    }
    // 第一段（含 release）崩：处理器已清 s_sb_active_jmp
    sb_clog("[shaderc-sandbox] child: rebuild crashed during compiler release -- "
            "retrying bare glslang cycle\n");
    s_sb_active_jmp = &j;
    if (sigsetjmp(j, 1) == 0) {
        int rc = sb_child_rebuild_core(impl, 0);
        s_sb_active_jmp = NULL;
        return rc;
    }
    sb_clog("[shaderc-sandbox] child: bare glslang rebuild crashed too -- giving up\n");
    return -1;
}

// 32MB 栈 hop（子进程内自带；结构同 main_hook.m 的 ame_run_on_32mb_stack）
// Task 43：job 增加崩溃网字段——worker 线程内 sigsetjmp 包住 impl 调用，
// 崩溃 → siglongjmp 跳回【同一线程】的 setjmp 点（绝不跨线程长跳），
// worker 正常返回后由回路线程决策重建/重试。
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
    volatile int crashed;   // 0 = 未崩 / 非 0 = 崩溃信号编号
} sb_job_t;

static void *sb_job_main(void *arg) {
    sb_job_t *job = (sb_job_t *)arg;
    sb_impl_t *im = job->impl;

    // 本 worker 线程注册 sigaltstack（栈溢出型崩溃处理器也能跑）
    void *altstk = sb_altstack_arm();

    job->crashed = 0;
    sigjmp_buf j;
    s_sb_active_jmp = &j;
    if (sigsetjmp(j, 1) == 0) {
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
        job->result = fn(im->compiler, job->source, job->source_size, job->kind,
                         job->input, job->entry_point, job->options);
        s_sb_active_jmp = NULL;
    } else {
        // 崩溃路径：处理器已清 s_sb_active_jmp；跳回值 = 信号编号。
        // 半构造的 options/result 直接泄漏（子进程，量级有界）——释放本身
        // 可能再崩，不值得冒险。
        job->crashed = 1;
        job->result = NULL;
        job->options = NULL;
    }
    sb_altstack_disarm(altstk);
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

// ---- 子进程：服务循环（Task 43：崩溃自愈 + 同请求最多 4 次尝试）----
#define AME_SB_CHILD_MAX_ATTEMPTS 4

static int ame_sb_child_serve_fd(int fd) {
    sb_impl_t impl;
    sb_child_install_net(); // 先装崩溃网（impl 加载/初始化也受保护）
    if (sb_child_load_impl(&impl) != 0) {
        sb_clog("[shaderc-sandbox] child: impl load failed -- exiting\n");
        return 1;
    }
    uint32_t rdy = AME_SB_RDY_MAGIC;
    if (sb_send_all(fd, &rdy, 4) != 0) return 0; // 父进程已退出

    sb_clog("[shaderc-sandbox] child loop online (pid=%d compiler=%p)\n",
            (int)getpid(), impl.compiler);

    for (;;) {
        sb_req_hdr_t hdr;
        if (sb_recv_all(fd, &hdr, sizeof hdr) != 0) return 0; // EOF：父进程退出
        if (hdr.magic != AME_SB_REQ_MAGIC || hdr.source_len > AME_SB_MAX_BLOB ||
            hdr.input_len > 8192 || hdr.entry_len > 2048 ||
            hdr.opt_blen != sizeof(ame_sb_opt_fields_t)) {
            sb_clog("[shaderc-sandbox] child: malformed request header\n");
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

        // 编译（32MB 栈线程上；崩溃 → 重建 glslang → 重试，最多 4 次）
        int status = 3; // internal_error（兜底）
        const char *spv = "";
        size_t spv_len = 0;
        const char *err = "";
        char giveup_msg[256];
        int attempts = 0;
        int done = 0;           // 循环正常 break（无论编译成败）= 1
        void *pending_result = NULL;  // 响应发送【之后】才释放（spv/err 指向其内部缓冲）
        void *pending_options = NULL;
        int suspect_result = 0;  // 提取段崩过：跳过 release（防二次崩，泄漏有界）

        while (attempts < AME_SB_CHILD_MAX_ATTEMPTS) {
            attempts++;
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

            if (job.crashed) {
                sb_clog("[shaderc-sandbox] child: compile crashed on attempt %d/%d "
                        "(fresh-thread retry with glslang rebuild)\n",
                        attempts, AME_SB_CHILD_MAX_ATTEMPTS);
                if (sb_child_rebuild(&impl) != 0) {
                    // 重建本身崩死：子进程不再可靠，干净退出走父进程降级链
                    free(source);
                    free(input);
                    free(ep);
                    return 4;
                }
                continue; // 换全新线程 + 全新进程状态重试
            }

            // 结果提取（回路线程上罩网：毒化的 result 访问也可能崩）
            int extract_ok = 1;
            if (job.result != NULL) {
                sigjmp_buf ej;
                s_sb_active_jmp = &ej;
                if (sigsetjmp(ej, 1) == 0) {
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
                    s_sb_active_jmp = NULL;
                } else {
                    // 提取段崩溃：视作编译崩溃走重建重试
                    extract_ok = 0;
                    suspect_result = 1;
                    sb_clog("[shaderc-sandbox] child: result extraction crashed "
                            "(attempt %d/%d)\n",
                            attempts, AME_SB_CHILD_MAX_ATTEMPTS);
                }
            } else {
                err = "[sandbox] 32MB stack hop failed (pthread_create)";
            }

            if (!extract_ok) {
                pending_options = job.options; // options 正常，发送后释放
                if (sb_child_rebuild(&impl) != 0) {
                    free(source);
                    free(input);
                    free(ep);
                    return 4;
                }
                continue;
            }

            // 成功路径：释放延后到响应发送之后（spv/err 指向 result 内部缓冲）
            pending_result = job.result;
            pending_options = job.options;
            done = 1;
            break; // 完成（无论编译成败，只要没崩就出循环）
        }

        // 循环耗尽 = 4 次全崩：合成 internal_error 响应，子进程继续服务
        if (!done) {
            snprintf(giveup_msg, sizeof giveup_msg,
                     "[amethyst] sandbox-child compile crashed %d times -- "
                     "internal_error (child still serving)",
                     AME_SB_CHILD_MAX_ATTEMPTS);
            err = giveup_msg;
            // 耗尽后也重建一次，保证后续请求从干净状态开始
            if (sb_child_rebuild(&impl) != 0) {
                free(source);
                free(input);
                free(ep);
                return 4;
            }
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

        // 响应发送完毕才释放（spv/err 指向 result 内部缓冲；与原 Task 42 同序）
        if (pending_result != NULL && !suspect_result && impl.result_release != NULL) {
            impl.result_release(pending_result);
        }
        if (pending_options != NULL && impl.opt_release != NULL) {
            impl.opt_release(pending_options);
        }

        free(source);
        free(input);
        free(ep);
        if (!ok) return 0; // 父进程断开
    }
}

// env 版入口（posix_spawn 路径）：fd 从 AME_SB_FD 取。
int ame_shaderc_sandbox_child_main(void) {
    const char *fd_s = getenv("AME_SB_FD");
    int fd = (fd_s != NULL) ? atoi(fd_s) : 3;
    if (fd <= 0) fd = 3;
    return ame_shaderc_sandbox_child_main_fd(fd);
}

// fd 直传入口（Task 43 fork server 路径）。
int ame_shaderc_sandbox_child_main_fd(int fd) {
    return ame_sb_child_serve_fd(fd);
}
