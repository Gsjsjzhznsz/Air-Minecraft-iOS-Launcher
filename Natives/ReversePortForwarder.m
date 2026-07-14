//
//  ReversePortForwarder.m
//  Angel Aura Amethyst
//
//  房主侧反向 TCP 端口转发器实现（libzt → 系统 socket 桥接）
//
//  ============================================================================
//  实现说明
//  ============================================================================
//
//  本文件实现 ReversePortForwarder.h 中定义的反向端口转发器。
//
//  关键实现点：
//    1. 监听 socket 使用 libzt socket（通过 ZeroTierBridge 的服务端 API）
//    2. 客户端连接后（libzt accept），在新线程中处理：
//       a. 创建系统 POSIX socket
//       b. connect 到 127.0.0.1:forwardPort（房主 MC 的本地监听地址）
//       c. 双向转发数据
//    3. 双向转发使用 GCD 并发队列，两个方向同时转发
//    4. 使用 _Atomic(BOOL) 标志确保跨线程内存可见性
//    5. stop 时通过关闭 libzt 监听 socket 唤醒 accept 线程，
//       通过 shutdown 活跃连接唤醒阻塞的 read/recv
//
//  线程模型：
//    - 主线程：startWithListenIP:... / stop
//    - Accept 线程：NSThread，循环 accept 新的 libzt 连接
//    - 客户端处理线程：NSThread，每个客户端一个
//    - 转发任务：GCD 并发队列，每个连接两个任务
//
//  与 PortForwarder 的对称性：
//    - PortForwarder（房客侧）：
//        listen socket = 系统 POSIX socket（127.0.0.1:localPort）
//        connect socket = libzt socket（remoteHost:remotePort，房主 ZeroTier IP）
//    - ReversePortForwarder（房主侧）：
//        listen socket = libzt socket（listenIP:listenPort，房主自己的 ZeroTier IP）
//        connect socket = 系统 POSIX socket（127.0.0.1:forwardPort，房主 MC 本地监听）
//
//  ============================================================================

#import "ReversePortForwarder.h"
#import "ZeroTierBridge.h"
#import "utils.h"

// POSIX socket 头文件
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>  // TCP_NODELAY
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>       // fcntl/F_GETFL/F_SETFL/O_NONBLOCK
#include <sys/select.h>
#include <sys/time.h>
#include <stdatomic.h>  // C11 原子操作

#pragma mark - 常量定义

/// 错误域名
static NSString * const kReversePortForwarderErrorDomain = @"ReversePortForwarderErrorDomain";

/// 错误码
typedef NS_ENUM(NSInteger, ReversePortForwarderErrorCode) {
    ReversePortForwarderErrorCodeAlreadyRunning       = 1,  // 转发器已在运行
    ReversePortForwarderErrorCodeSocketCreateFailed   = 2,  // 创建 socket 失败
    ReversePortForwarderErrorCodeBindFailed           = 3,  // 绑定端口失败
    ReversePortForwarderErrorCodeListenFailed         = 4,  // 监听失败
    ReversePortForwarderErrorCodeFrameworkUnavailable = 5,  // ZeroTier framework 不可用
    ReversePortForwarderErrorCodeInvalidListenIP      = 6,  // 监听 IP 无效
    ReversePortForwarderErrorCodeInvalidListenPort    = 7,  // 监听端口无效
    ReversePortForwarderErrorCodeInvalidForwardHost   = 8,  // 转发目标主机无效
    ReversePortForwarderErrorCodeInvalidForwardPort  = 9,   // 转发目标端口无效
};

/// 数据转发缓冲区大小（64KB，与 PortForwarder 保持一致）
#define REVERSE_PORT_FORWARDER_BUFFER_SIZE 65536

/// 系统 socket 连接超时时间（10 秒）
#define REVERSE_PORT_FORWARDER_CONNECT_TIMEOUT 10.0

/// 监听队列最大长度
#define REVERSE_PORT_FORWARDER_BACKLOG 16

#pragma mark - 辅助函数

/// 将所有数据写入 fd（循环 write 直到所有数据写完或出错）
/// @param fd 文件描述符
/// @param buffer 数据缓冲区
/// @param length 数据长度
/// @return 实际写入的字节数，-1 表示错误
static ssize_t writeAllToSystem(int fd, const uint8_t *buffer, size_t length) {
    size_t totalWritten = 0;
    while (totalWritten < length) {
        ssize_t n = write(fd, buffer + totalWritten, length - totalWritten);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (n == 0) {
            break;
        }
        totalWritten += (size_t)n;
    }
    return (ssize_t)totalWritten;
}

/// 系统 socket 非阻塞 connect + select 超时控制
/// @param fd 系统 socket
/// @param host 目标主机
/// @param port 目标端口
/// @param timeout 超时时间（秒）
/// @return 0 表示成功，< 0 表示失败
static int connectSystemSocket(int fd, const char *host, uint16_t port, NSTimeInterval timeout) {
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);

    if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
        NSLog(@"[ReversePortForwarder] inet_pton 失败：host=%s", host);
        return -1;
    }

    // 设置为非阻塞
    int origFlags = fcntl(fd, F_GETFL, 0);
    if (origFlags < 0) {
        // 回退到阻塞 connect
        return connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    }
    fcntl(fd, F_SETFL, origFlags | O_NONBLOCK);

    int connectResult = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (connectResult == 0) {
        fcntl(fd, F_SETFL, origFlags);
        return 0;
    }
    if (errno != EINPROGRESS) {
        fcntl(fd, F_SETFL, origFlags);
        return connectResult;
    }

    // select 等待可写
    fd_set writeFds;
    FD_ZERO(&writeFds);
    FD_SET(fd, &writeFds);

    struct timeval selectTimeout;
    selectTimeout.tv_sec = (long)timeout;
    selectTimeout.tv_usec = (long)((timeout - (NSTimeInterval)selectTimeout.tv_sec) * 1000000);
    if (selectTimeout.tv_usec < 0) {
        selectTimeout.tv_usec = 0;
    }

    int selectResult = select(fd + 1, NULL, &writeFds, NULL, &selectTimeout);
    fcntl(fd, F_SETFL, origFlags);

    if (selectResult <= 0) {
        NSLog(@"[ReversePortForwarder] connect 超时或失败：selectResult=%d, errno=%d", selectResult, errno);
        return -1;
    }

    int socketError = 0;
    socklen_t errorLen = sizeof(socketError);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLen) != 0 || socketError != 0) {
        NSLog(@"[ReversePortForwarder] connect SO_ERROR=%d", socketError);
        return -1;
    }
    return 0;
}

#pragma mark - ReversePortForwarder 类扩展

@interface ReversePortForwarder () {
    /// libzt 监听 socket 文件描述符（-1 表示未创建）
    int _listenFD;

    /// Accept 线程
    NSThread *_acceptThread;

    /// 线程锁，保护内部状态
    NSLock *_lock;

    /// 是否正在停止
    BOOL _stopping;

    /// 活跃 libzt socket fd 集合（房客侧连接，用于 stop 时 shutdown 唤醒阻塞 recv）
    NSMutableArray<NSNumber *> *_activeZTFDs;

    /// 活跃系统 socket fd 集合（房主 MC 侧连接，用于 stop 时 shutdown 唤醒阻塞 read）
    NSMutableArray<NSNumber *> *_activeSystemFDs;
}

/// 是否正在运行
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;

/// 监听 IP
@property (nonatomic, copy, readwrite, nullable) NSString *listenIP;

/// 监听端口
@property (nonatomic, assign, readwrite) uint16_t listenPort;

/// 转发目标主机
@property (nonatomic, copy, readwrite, nullable) NSString *forwardHost;

/// 转发目标端口
@property (nonatomic, assign, readwrite) uint16_t forwardPort;

/// 在 accept 线程中处理新连接（房客侧的 libzt socket）
/// @param ztFD 房客侧 libzt socket 文件描述符
- (void)handleClient:(int)ztFD;

/// 双向转发数据：libzt socket ↔ 系统 socket
/// @param ztFD 房客侧 libzt socket
/// @param systemFD 房主 MC 侧系统 socket
- (void)forwardDataBetweenZTFD:(int)ztFD
                     systemFD:(int)systemFD;

@end

#pragma mark - ReversePortForwarder 实现

@implementation ReversePortForwarder

#pragma mark - 单例模式

+ (instancetype)sharedForwarder {
    static ReversePortForwarder *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static ReversePortForwarder *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [super allocWithZone:zone];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
        _acceptThread = nil;
        _stopping = NO;
        _running = NO;
        _listenPort = 0;
        _forwardPort = 0;
        _listenIP = nil;
        _forwardHost = nil;
        _lock = [[NSLock alloc] init];
        _activeZTFDs = [[NSMutableArray alloc] init];
        _activeSystemFDs = [[NSMutableArray alloc] init];
        NSLog(@"[ReversePortForwarder] 单例已初始化");
    }
    return self;
}

#pragma mark - 启动反向端口转发

- (BOOL)startWithListenIP:(NSString *)listenIP
               listenPort:(uint16_t)listenPort
              forwardHost:(NSString *)forwardHost
              forwardPort:(uint16_t)forwardPort
                   error:(NSError **)error {
    // ============================================================
    // 步骤 1：参数校验
    // ============================================================
    if (!listenIP || listenIP.length == 0) {
        NSLog(@"[ReversePortForwarder] start 失败：listenIP 为空");
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeInvalidListenIP
                                      userInfo:@{NSLocalizedDescriptionKey: @"监听 IP 无效"}];
        }
        return NO;
    }
    if (listenPort == 0) {
        NSLog(@"[ReversePortForwarder] start 失败：listenPort 为 0");
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeInvalidListenPort
                                      userInfo:@{NSLocalizedDescriptionKey: @"监听端口无效"}];
        }
        return NO;
    }
    if (!forwardHost || forwardHost.length == 0) {
        NSLog(@"[ReversePortForwarder] start 失败：forwardHost 为空");
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeInvalidForwardHost
                                      userInfo:@{NSLocalizedDescriptionKey: @"转发目标主机无效"}];
        }
        return NO;
    }
    if (forwardPort == 0) {
        NSLog(@"[ReversePortForwarder] start 失败：forwardPort 为 0");
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeInvalidForwardPort
                                      userInfo:@{NSLocalizedDescriptionKey: @"转发目标端口无效"}];
        }
        return NO;
    }

    // ============================================================
    // 步骤 2：检查是否已在运行
    // ============================================================
    [_lock lock];
    if (_running) {
        [_lock unlock];
        NSLog(@"[ReversePortForwarder] start 失败：已在运行（%@:%u → %@:%u）",
              _listenIP, _listenPort, _forwardHost, _forwardPort);
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeAlreadyRunning
                                      userInfo:@{NSLocalizedDescriptionKey: @"反向端口转发器已在运行，请先停止"}];
        }
        return NO;
    }
    [_lock unlock];

    // ============================================================
    // 步骤 3：检查 ZeroTier framework 是否可用
    // ============================================================
    if (![[ZeroTierBridge sharedInstance] isFrameworkAvailable]) {
        NSLog(@"[ReversePortForwarder] start 失败：ZeroTier framework 不可用");
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeFrameworkUnavailable
                                      userInfo:@{NSLocalizedDescriptionKey: @"ZeroTier framework 不可用"}];
        }
        return NO;
    }

    NSLog(@"[ReversePortForwarder] 启动反向端口转发：libzt %@:%u → 系统 %@:%u",
          listenIP, listenPort, forwardHost, forwardPort);

    // ============================================================
    // 步骤 4：创建 libzt 监听 socket
    // ============================================================
    // 检测地址族（IPv4/IPv6）
    BOOL isIPv6 = (zts_inet_pton(ZTS_AF_INET6, [listenIP UTF8String], NULL) == 1);
    int socketFamily = isIPv6 ? ZTS_AF_INET6 : ZTS_AF_INET;

    int listenFD = [[ZeroTierBridge sharedInstance] createTCPSocketForFamily:socketFamily];
    if (listenFD < 0) {
        NSLog(@"[ReversePortForwarder] 创建 libzt socket 失败：listenFD=%d", listenFD);
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeSocketCreateFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"创建 libzt socket 失败"}];
        }
        return NO;
    }

    // ============================================================
    // 步骤 5：bind + listen
    // ============================================================
    int bindResult = [[ZeroTierBridge sharedInstance] bindSocket:listenFD
                                                       toLocalIP:listenIP
                                                             port:listenPort];
    if (bindResult != 0) {
        NSLog(@"[ReversePortForwarder] bind 失败：result=%d", bindResult);
        [[ZeroTierBridge sharedInstance] closeSocket:listenFD];
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeBindFailed
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"libzt bind 失败：%@", listenIP]}];
        }
        return NO;
    }

    int listenResult = [[ZeroTierBridge sharedInstance] listenOnSocket:listenFD
                                                               backlog:REVERSE_PORT_FORWARDER_BACKLOG];
    if (listenResult != 0) {
        NSLog(@"[ReversePortForwarder] listen 失败：result=%d", listenResult);
        [[ZeroTierBridge sharedInstance] closeSocket:listenFD];
        if (error) {
            *error = [NSError errorWithDomain:kReversePortForwarderErrorDomain
                                          code:ReversePortForwarderErrorCodeListenFailed
                                      userInfo:@{NSLocalizedDescriptionKey: @"libzt listen 失败"}];
        }
        return NO;
    }

    // ============================================================
    // 步骤 6：更新状态并启动 accept 线程
    // ============================================================
    [_lock lock];
    _listenFD = listenFD;
    _listenIP = [listenIP copy];
    _listenPort = listenPort;
    _forwardHost = [forwardHost copy];
    _forwardPort = forwardPort;
    _running = YES;
    _stopping = NO;
    [_lock unlock];

    __weak typeof(self) weakSelf = self;
    _acceptThread = [[NSThread alloc] initWithBlock:^{
        [weakSelf acceptLoop];
    }];
    _acceptThread.name = @"ReversePortForwarder-Accept";
    [_acceptThread start];

    NSLog(@"[ReversePortForwarder] 反向端口转发已启动：libzt %@:%u → 系统 %@:%u",
          listenIP, listenPort, forwardHost, forwardPort);

    return YES;
}

#pragma mark - Accept 线程

/// Accept 线程主循环
///
/// 注意：libzt 的 accept 是阻塞调用，没有系统级 select 可用。
/// 通过 _stopping 标志和 close listenFD 来唤醒：
///   - libzt accept 在 listen socket 被关闭后会返回错误（zts_errno）
///   - 检测到 stopping 或 accept 失败时退出循环
- (void)acceptLoop {
    NSLog(@"[ReversePortForwarder] Accept 线程已启动");

    while (YES) {
        @autoreleasepool {
            [_lock lock];
            int listenFD = _listenFD;
            BOOL stopping = _stopping;
            [_lock unlock];

            if (stopping || listenFD < 0) {
                NSLog(@"[ReversePortForwarder] Accept 线程：收到停止信号，退出循环");
                break;
            }

            // 阻塞等待新连接
            // 注意：zts_bsd_accept 在 listenFD 被关闭后会返回错误
            int clientFD = [[ZeroTierBridge sharedInstance] acceptOnSocket:listenFD];
            if (clientFD < 0) {
                [_lock lock];
                BOOL nowStopping = _stopping;
                [_lock unlock];

                if (nowStopping) {
                    NSLog(@"[ReversePortForwarder] Accept 线程：stop 触发的 accept 失败，正常退出");
                    break;
                }

                // 异常错误，记录后退出
                NSLog(@"[ReversePortForwarder] Accept 线程：accept 异常，退出");
                break;
            }

            NSLog(@"[ReversePortForwarder] 新客户端连接：clientFD=%d", clientFD);

            // 在新线程中处理客户端连接
            __weak typeof(self) weakSelf = self;
            NSThread *clientThread = [[NSThread alloc] initWithBlock:^{
                [weakSelf handleClient:clientFD];
            }];
            clientThread.name = [NSString stringWithFormat:@"ReversePF-Client-%d", clientFD];
            [clientThread start];
        }
    }

    NSLog(@"[ReversePortForwarder] Accept 线程已退出");
}

#pragma mark - 客户端处理

/// 处理房客侧的 libzt 连接
///
/// 流程：
///   1. 创建系统 POSIX socket
///   2. connect 到 127.0.0.1:forwardPort（房主 MC 的本地监听）
///   3. 双向转发数据：libzt socket ↔ 系统 socket
///   4. 关闭连接
- (void)handleClient:(int)ztFD {
    @autoreleasepool {
        [_lock lock];
        NSString *forwardHost = [_forwardHost copy];
        uint16_t forwardPort = _forwardPort;
        [_lock unlock];

        if (!forwardHost.length) {
            NSLog(@"[ReversePortForwarder] handleClient：forwardHost 为空，关闭连接");
            [[ZeroTierBridge sharedInstance] closeSocket:ztFD];
            return;
        }

        NSLog(@"[ReversePortForwarder] 处理客户端连接 ztFD=%d，转发到 %@:%u", ztFD, forwardHost, forwardPort);

        // 对 libzt socket 设置 TCP_NODELAY
        int ztNoDelay = 1;
        zts_bsd_setsockopt(ztFD, ZTS_IPPROTO_TCP, ZTS_TCP_NODELAY, &ztNoDelay, sizeof(ztNoDelay));

        // ============================================================
        // 步骤 1：创建系统 POSIX socket 并连接到房主 MC
        // ============================================================
        int systemFD = socket(AF_INET, SOCK_STREAM, 0);
        if (systemFD < 0) {
            NSLog(@"[ReversePortForwarder] 创建系统 socket 失败：errno=%d (%s)", errno, strerror(errno));
            [[ZeroTierBridge sharedInstance] closeSocket:ztFD];
            return;
        }

        // 对系统 socket 设置 TCP_NODELAY
        int systemNoDelay = 1;
        setsockopt(systemFD, IPPROTO_TCP, TCP_NODELAY, &systemNoDelay, sizeof(systemNoDelay));

        // 对系统 socket 设置 SO_KEEPALIVE
        int keepAlive = 1;
        setsockopt(systemFD, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, sizeof(keepAlive));

        // connect 到房主 MC 的本地监听地址
        int connectResult = connectSystemSocket(systemFD,
                                                [forwardHost UTF8String],
                                                forwardPort,
                                                REVERSE_PORT_FORWARDER_CONNECT_TIMEOUT);
        if (connectResult != 0) {
            NSLog(@"[ReversePortForwarder] 连接房主 MC 失败：errno=%d (%s)，目标 %@:%u",
                  errno, strerror(errno), forwardHost, forwardPort);
            close(systemFD);
            [[ZeroTierBridge sharedInstance] closeSocket:ztFD];
            return;
        }

        NSLog(@"[ReversePortForwarder] 连接房主 MC 成功：systemFD=%d → %@:%u", systemFD, forwardHost, forwardPort);

        // 将 fd 加入活跃列表（用于 stop 时 shutdown 唤醒阻塞的 read/recv）
        [_lock lock];
        [_activeZTFDs addObject:@(ztFD)];
        [_activeSystemFDs addObject:@(systemFD)];
        [_lock unlock];

        // ============================================================
        // 步骤 2：双向转发数据
        // ============================================================
        [self forwardDataBetweenZTFD:ztFD systemFD:systemFD];

        // 从活跃列表中移除
        [_lock lock];
        [_activeZTFDs removeObject:@(ztFD)];
        [_activeSystemFDs removeObject:@(systemFD)];
        [_lock unlock];

        // ============================================================
        // 步骤 3：关闭连接
        // ============================================================
        NSLog(@"[ReversePortForwarder] 转发结束，关闭连接：ztFD=%d, systemFD=%d", ztFD, systemFD);
        close(systemFD);
        [[ZeroTierBridge sharedInstance] closeSocket:ztFD];
    }
}

#pragma mark - 双向数据转发

/// 双向转发数据：libzt socket ↔ 系统 socket
///
/// @param ztFD 房客侧 libzt socket
/// @param systemFD 房主 MC 侧系统 socket
- (void)forwardDataBetweenZTFD:(int)ztFD
                     systemFD:(int)systemFD {
    __block _Atomic(BOOL) ztClosed = NO;
    __block _Atomic(BOOL) systemClosed = NO;

    dispatch_queue_t forwardQueue = dispatch_queue_create("com.angelaura.reverseportforwarder.forward", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t group = dispatch_group_create();

    // ============================================================
    // 方向 1：zt → system
    // 从房客（libzt）读取数据，发送给房主 MC（系统 socket）
    // ============================================================
    dispatch_group_async(group, forwardQueue, ^{
        uint8_t buffer[REVERSE_PORT_FORWARDER_BUFFER_SIZE];

        while (YES) {
            @autoreleasepool {
                if (atomic_load(&systemClosed)) {
                    NSLog(@"[ReversePortForwarder] zt→system：系统侧已关闭，退出");
                    break;
                }

                ssize_t n = [[ZeroTierBridge sharedInstance] recvData:ztFD
                                                                buffer:buffer
                                                                length:sizeof(buffer)];
                if (n <= 0) {
                    NSLog(@"[ReversePortForwarder] zt→system 结束：n=%zd", n);
                    atomic_store(&ztClosed, YES);
                    shutdown(systemFD, SHUT_WR);
                    break;
                }

                ssize_t sent = writeAllToSystem(systemFD, buffer, (size_t)n);
                if (sent <= 0) {
                    NSLog(@"[ReversePortForwarder] 写入系统 socket 失败：sent=%zd", sent);
                    atomic_store(&systemClosed, YES);
                    [[ZeroTierBridge sharedInstance] shutdownSocket:ztFD how:ZTS_SHUT_WR];
                    break;
                }
            }
        }
    });

    // ============================================================
    // 方向 2：system → zt
    // 从房主 MC（系统 socket）读取数据，发送给房客（libzt）
    // ============================================================
    dispatch_group_async(group, forwardQueue, ^{
        uint8_t buffer[REVERSE_PORT_FORWARDER_BUFFER_SIZE];

        while (YES) {
            @autoreleasepool {
                if (atomic_load(&ztClosed)) {
                    NSLog(@"[ReversePortForwarder] system→zt：libzt 侧已关闭，退出");
                    break;
                }

                ssize_t n = read(systemFD, buffer, sizeof(buffer));
                if (n <= 0) {
                    NSLog(@"[ReversePortForwarder] system→zt 结束：n=%zd, errno=%d", n, errno);
                    atomic_store(&systemClosed, YES);
                    [[ZeroTierBridge sharedInstance] shutdownSocket:ztFD how:ZTS_SHUT_WR];
                    break;
                }

                ssize_t sent = [[ZeroTierBridge sharedInstance] sendData:ztFD
                                                                  buffer:buffer
                                                                  length:(size_t)n];
                if (sent <= 0) {
                    NSLog(@"[ReversePortForwarder] 发送到 libzt 失败：sent=%zd", sent);
                    atomic_store(&ztClosed, YES);
                    shutdown(systemFD, SHUT_WR);
                    break;
                }
            }
        }
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    NSLog(@"[ReversePortForwarder] 双向转发已结束：ztFD=%d, systemFD=%d", ztFD, systemFD);
}

#pragma mark - 停止反向端口转发

- (void)stop {
    BOOL isMainThread = [NSThread isMainThread];

    [_lock lock];
    if (!_running) {
        [_lock unlock];
        NSLog(@"[ReversePortForwarder] stop：未在运行，跳过");
        return;
    }

    NSLog(@"[ReversePortForwarder] 停止反向端口转发（%@:%u → %@:%u，isMainThread=%d）",
          _listenIP, _listenPort, _forwardHost, _forwardPort, isMainThread);

    _stopping = YES;
    _running = NO;
    int listenFD = _listenFD;
    _listenFD = -1;
    NSThread *acceptThread = _acceptThread;

    NSArray<NSNumber *> *ztFDs = [_activeZTFDs copy];
    NSArray<NSNumber *> *systemFDs = [_activeSystemFDs copy];
    [_activeZTFDs removeAllObjects];
    [_activeSystemFDs removeAllObjects];
    [_lock unlock];

    // 1. 关闭 libzt 监听 socket，唤醒 accept 线程
    if (listenFD >= 0) {
        [[ZeroTierBridge sharedInstance] closeSocket:listenFD];
    }

    // 2. shutdown 所有活跃连接（唤醒阻塞的 read/recv）
    NSLog(@"[ReversePortForwarder] shutdown %lu 个 libzt 连接和 %lu 个系统连接...",
          (unsigned long)ztFDs.count, (unsigned long)systemFDs.count);

    for (NSNumber *fdNum in ztFDs) {
        int fd = [fdNum intValue];
        if (fd >= 0) {
            [[ZeroTierBridge sharedInstance] shutdownSocket:fd how:ZTS_SHUT_RDWR];
        }
    }

    for (NSNumber *fdNum in systemFDs) {
        int fd = [fdNum intValue];
        if (fd >= 0) {
            shutdown(fd, SHUT_RDWR);
        }
    }

    // 3. 清理状态
    [_lock lock];
    _acceptThread = nil;
    _listenIP = nil;
    _listenPort = 0;
    _forwardHost = nil;
    _forwardPort = 0;
    _stopping = NO;
    [_lock unlock];

    NSLog(@"[ReversePortForwarder] 反向端口转发已停止");
}

@end
