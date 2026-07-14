//
//  ZeroTierBridge.h
//  Angel Aura Amethyst
//
//  ZeroTier libzt C API 的 Objective-C 封装层
//
//  ============================================================================
//  设计说明
//  ============================================================================
//
//  本文件是 ZeroTier 官方 Apple Framework (zt.framework) 的 Objective-C 封装层，
//  参照 FCL (Fold Craft Launcher) 的 ZeroTierService 和 ZL2 (ZalithLauncher) 的
//  ZeroTier 集成方式设计，为 iOS 启动器提供进程内联机能力。
//
//  工作原理：
//    1. zt.framework 内部集成了完整的 ZeroTier 节点（基于 libzt），可以在进程内
//       建立 ZeroTier 虚拟网络，无需依赖外部的 ZeroTier One app。
//    2. 本封装层通过 libzt 的 C API（ZeroTierSockets.h）控制节点的启动、停止、
//       网络的加入与离开，以及通过 ZeroTier 虚拟网络进行 TCP 通信。
//    3. SOCKS5Proxy 使用本封装层提供的 socket 方法，将本地 SOCKS5 流量转发到
//       ZeroTier 虚拟网络中，实现 Minecraft 客户端通过 ZeroTier 连接房主服务器。
//
//  与 Android 平台（FCL/ZL2）的区别：
//    - Android 通过 JNI 调用 libzt 的 Java 绑定
//    - iOS 通过本 Objective-C 封装层直接调用 libzt 的 C API
//    - 协议层完全兼容，可以与 FCL/ZL2/HMCL 互通
//
//  stub 模式：
//    如果 zt.framework 不可用（例如 CI 构建环境），项目会链接 zt_stub.c，
//    所有 API 返回 ZTS_ERR_SERVICE (-2)。本封装层通过 isFrameworkAvailable
//    方法检测此情况，避免在无框架环境下执行无效操作。
//
//  ============================================================================

#import <Foundation/Foundation.h>
#import "external/zt.framework/Headers/ZeroTierSockets.h"

NS_ASSUME_NONNULL_BEGIN

/// ZeroTier 节点状态
///
/// 描述 ZeroTier 节点的运行状态生命周期：
///   Stopped  → Starting → Online ⇄ Offline
///                       ↘ Error
typedef NS_ENUM(NSInteger, ZeroTierNodeStatus) {
    ZeroTierNodeStatusStopped = 0,   // 节点已停止（未启动或已关闭）
    ZeroTierNodeStatusStarting,      // 节点正在启动中（已调用 zts_node_start，等待 ONLINE 事件）
    ZeroTierNodeStatusOnline,        // 节点已上线（至少一个上游节点可达）
    ZeroTierNodeStatusOffline,       // 节点已离线（网络不可达）
    ZeroTierNodeStatusError          // 节点发生错误（如身份冲突）
};

/// ZeroTier 网络状态
///
/// 描述某个 ZeroTier 网络的加入状态：
///   NotJoined → Requesting → Joined
///                         ↘ Denied / NotFound / Error
typedef NS_ENUM(NSInteger, ZeroTierNetworkStatus) {
    ZeroTierNetworkStatusNotJoined = 0, // 未加入此网络
    ZeroTierNetworkStatusRequesting,     // 正在请求网络配置
    ZeroTierNetworkStatusJoined,         // 已成功加入网络（配置已就绪）
    ZeroTierNetworkStatusDenied,         // 加入被拒绝（节点未授权）
    ZeroTierNetworkStatusNotFound,       // 网络不存在
    ZeroTierNetworkStatusError           // 网络状态错误
};

/// ZeroTierBridge 代理协议
///
/// 所有方法均为 @optional，代理可选择实现感兴趣的事件回调。
/// 所有回调方法都会在主线程调用（内部通过 dispatch_async(dispatch_get_main_queue()) 调度）。
@protocol ZeroTierBridgeDelegate <NSObject>
@optional

/// 节点已上线
/// @param nodeID ZeroTier 节点 ID（40 位地址，以 uint64_t 表示）
- (void)zeroTierNodeOnlineWithID:(uint64_t)nodeID;

/// 节点已离线（网络不可达）
- (void)zeroTierNodeOffline;

/// 节点发生致命错误
///
/// 关键修复（H3）：节点发生致命错误（如身份冲突）时通知 delegate，
/// 让上层 UI 能感知并提示用户。之前仅记录日志，UI 会一直显示"连接中"。
///
/// 可能原因：
///   - 身份冲突（两个节点的公钥哈希到同一个 40 位地址）
///   - libzt 内部不可恢复的错误
///
/// 节点进入此状态后，需要用户重新启动节点（可能需要清理身份文件）。
- (void)zeroTierNodeFatalError;

/// 网络已就绪（已收到 IP 地址分配）
/// @param networkID 网络 ID
/// @param ipv4 分配的 IPv4 地址（可能为 nil，如果尚未分配）
/// @param ipv6 分配的 IPv6 地址（可能为 nil，如果尚未分配）
- (void)zeroTierNetworkReady:(uint64_t)networkID
                        ipv4:(nullable NSString *)ipv4
                        ipv6:(nullable NSString *)ipv6;

/// 网络加入失败
/// @param networkID 网络 ID
/// @param errorDescription 错误描述（本地化）
- (void)zeroTierNetworkJoinFailed:(uint64_t)networkID
                            error:(NSString *)errorDescription;

/// 网络地址已分配
/// @param networkID 网络 ID
/// @param family 地址族（ZTS_AF_INET 或 ZTS_AF_INET6）
/// @param address 地址字符串
- (void)zeroTierAddressAssigned:(uint64_t)networkID
                         family:(int)family
                        address:(NSString *)address;

@end

/// ZeroTier 桥接类（libzt C API 的 Objective-C 封装）
///
/// 单例模式，通过 +sharedInstance 获取全局唯一实例。
/// 负责管理 ZeroTier 节点的生命周期、网络加入/离开、地址查询，
/// 以及提供基于 libzt 的 TCP socket 操作（供 SOCKS5Proxy 使用）。
@interface ZeroTierBridge : NSObject

/// 单例访问
+ (instancetype)sharedInstance;

/// 代理对象（弱引用，避免循环引用）
@property (nonatomic, weak, nullable) id<ZeroTierBridgeDelegate> delegate;

#pragma mark - 节点管理

/// 启动 ZeroTier 节点
///
/// 流程：
///   1. 调用 zts_init_from_storage 设置身份文件存储目录
///   2. 调用 zts_init_set_event_handler 设置事件回调
///   3. 调用 zts_node_start 启动节点
///   4. 节点启动后，会异步触发 ZTS_EVENT_NODE_ONLINE 等事件
///
/// @param homeDir 身份文件存储目录（authtoken.secret、identity.public/secret 等）
/// @param error 错误输出（如果失败）
/// @return YES 如果启动成功（不代表节点已上线，仅代表启动请求已成功提交）
- (BOOL)startNodeWithHomeDirectory:(NSString *)homeDir
                             error:(NSError **)error;

/// 停止 ZeroTier 节点
///
/// 调用 zts_node_stop 停止节点，并清理内部状态缓存。
- (void)stopNode;

/// 节点是否在线
/// @return YES 如果节点已上线（zts_node_is_online() 返回 1）
- (BOOL)isNodeOnline;

/// 获取节点 ID
/// @return 节点 ID（如果节点未上线则返回 0）
- (uint64_t)nodeID;

/// 获取节点状态
/// @return 当前节点状态枚举值
- (ZeroTierNodeStatus)nodeStatus;

#pragma mark - 网络管理

/// 加入 ZeroTier 网络
/// @param networkID 网络 ID（64 位无符号整数）
/// @param error 错误输出（如果失败）
/// @return YES 如果加入请求已成功提交
- (BOOL)joinNetwork:(uint64_t)networkID
              error:(NSError **)error;

/// 离开 ZeroTier 网络
/// @param networkID 网络 ID
/// @return YES 如果成功离开
- (BOOL)leaveNetwork:(uint64_t)networkID;

/// 获取网络状态
/// @param networkID 网络 ID
/// @return 网络状态枚举值
- (ZeroTierNetworkStatus)networkStatus:(uint64_t)networkID;

/// 获取网络分配的 IPv4 地址
/// @param networkID 网络 ID
/// @return IPv4 地址字符串（如 "10.147.17.1"），如果未分配则返回 nil
- (nullable NSString *)ipv4AddressForNetwork:(uint64_t)networkID;

/// 获取网络分配的 IPv6 地址
/// @param networkID 网络 ID
/// @return IPv6 地址字符串，如果未分配则返回 nil
- (nullable NSString *)ipv6AddressForNetwork:(uint64_t)networkID;

#pragma mark - 框架检测与等待

/// 检测 zt.framework 是否可用（非 stub）
///
/// 检测方式：调用 zts_node_start() 检查返回值。
/// 如果返回 ZTS_ERR_SERVICE (-2)，说明是 stub 实现，framework 不可用。
/// 如果返回 ZTS_ERR_OK (0)，说明是真实 framework（节点可能因此被启动）。
///
/// 结果会被缓存，后续调用直接返回缓存值。
///
/// @return YES 如果 framework 可用
- (BOOL)isFrameworkAvailable;

/// 等待节点上线
///
/// 以 200ms 为间隔轮询 zts_node_is_online()，直到节点上线或超时。
///
/// @param timeout 超时时间（秒）
/// @return YES 如果节点在超时前上线
- (BOOL)waitForNodeOnlineWithTimeout:(NSTimeInterval)timeout;

/// 等待网络就绪
///
/// 以 200ms 为间隔轮询 zts_net_transport_is_ready() 和 zts_addr_is_assigned()，
/// 直到网络就绪且 IPv4 地址已分配，或超时。
///
/// @param networkID 网络 ID
/// @param timeout 超时时间（秒）
/// @return YES 如果网络在超时前就绪
- (BOOL)waitForNetworkReady:(uint64_t)networkID
                    timeout:(NSTimeInterval)timeout;

#pragma mark - Socket 操作（供 SOCKS5Proxy 使用）

/// 创建 TCP socket（封装 zts_bsd_socket）
///
/// 创建一个基于 ZeroTier 虚拟网络的 TCP socket。
/// 此 socket 的所有后续操作（connect/send/recv/close）都通过 libzt API 进行，
/// 数据会经过 ZeroTier 虚拟网络传输，而非系统物理网络。
///
/// @return socket 文件描述符（≥ 0 表示成功，< 0 表示失败）
- (int)createTCPSocket;

/// 创建 TCP socket（指定地址族）
///
/// 用于 Ad-hoc 网络等只有 IPv6 的场景。
/// - ZTS_AF_INET（IPv4）：标准 ZeroTier 网络
/// - ZTS_AF_INET6（IPv6）：Ad-hoc 网络（只有 IPv6 地址）
///
/// @param family 地址族（ZTS_AF_INET 或 ZTS_AF_INET6）
/// @return socket 文件描述符（≥ 0 表示成功，< 0 表示失败）
- (int)createTCPSocketForFamily:(int)family;

/// 连接 socket 到目标主机
///
/// 封装 zts_bsd_connect，支持 IPv4 和 IPv6。
/// 超时通过 zts_bsd_setsockopt 设置 SO_RCVTIMEO 和 SO_SNDTIMEO 实现。
///
/// @param fd socket 文件描述符（由 createTCPSocket 创建）
/// @param host 目标主机 IP 地址字符串（如 "10.147.17.1"）
/// @param port 目标端口
/// @param timeout 连接超时时间（秒），≤ 0 表示不设置超时
/// @return 0 表示成功，< 0 表示失败（参见 ZTS_ERR_* 错误码）
- (int)connectSocket:(int)fd
              toHost:(NSString *)host
                port:(uint16_t)port
             timeout:(NSTimeInterval)timeout;

/// 关闭 socket（封装 zts_bsd_close）
/// @param fd socket 文件描述符
/// @return 0 表示成功，< 0 表示失败
- (int)closeSocket:(int)fd;

/// 关闭 socket 的读/写端（封装 zts_bsd_shutdown）
///
/// 与 closeSocket: 不同，shutdownSocket: 不会释放 fd 资源，
/// 但会立即让所有阻塞在该 fd 上的 read/recv/write/send 返回。
///
/// 关键修复（M12）：SOCKS5Proxy.stop 需要 shutdown 远程 fd 来唤醒
/// 阻塞在 recvData: 上的客户端线程，避免线程泄漏。
///
/// @param fd socket 文件描述符
/// @param how 关闭方式（ZTS_SHUT_RD / ZTS_SHUT_WR / ZTS_SHUT_RDWR）
/// @return 0 表示成功，< 0 表示失败
- (int)shutdownSocket:(int)fd how:(int)how;

/// 发送数据（封装 zts_bsd_send）
/// @param fd socket 文件描述符
/// @param buf 发送缓冲区
/// @param len 缓冲区长度
/// @return 实际发送的字节数（< 0 表示失败）
- (ssize_t)sendData:(int)fd
             buffer:(const void *)buf
              length:(size_t)len;

/// 接收数据（封装 zts_bsd_recv）
/// @param fd socket 文件描述符
/// @param buf 接收缓冲区
/// @param len 缓冲区长度
/// @return 实际接收的字节数（< 0 表示失败，0 表示连接已关闭）
- (ssize_t)recvData:(int)fd
             buffer:(void *)buf
              length:(size_t)len;

#pragma mark - Socket 服务端操作（供 ReversePortForwarder 使用）

/// 将 libzt socket 绑定到本地 ZeroTier 网络接口
///
/// 用于房主侧反向端口转发：在 libzt socket 上监听房主的 ZeroTier IP:port，
/// 让其他 ZeroTier 节点的 connect() 可以到达。
///
/// 支持 IPv4 和 IPv6。地址族由 fd 创建时决定（createTCPSocketForFamily:）。
///
/// @param fd socket 文件描述符（由 createTCPSocket/createTCPSocketForFamily: 创建）
/// @param host 本地绑定的 IP 地址字符串（如 "10.147.17.1"，可传 nil/"0.0.0.0" 绑定所有接口）
/// @param port 本地绑定端口
/// @return 0 表示成功，< 0 表示失败
- (int)bindSocket:(int)fd
        toLocalIP:(nullable NSString *)host
              port:(uint16_t)port;

/// 在已 bind 的 libzt socket 上开始监听
///
/// 封装 zts_bsd_listen，将 socket 转为被动监听模式，等待其他节点的 connect。
///
/// @param fd socket 文件描述符
/// @param backlog 等待连接队列最大长度
/// @return 0 表示成功，< 0 表示失败
- (int)listenOnSocket:(int)fd
              backlog:(int)backlog;

/// 在已 listen 的 libzt socket 上接受新连接
///
/// 封装 zts_bsd_accept，阻塞等待直到有新连接到达。
/// 调用方应在独立线程中调用此方法，避免阻塞主线程。
///
/// @param fd 已 listen 的 socket 文件描述符
/// @return 新连接的 socket fd（≥ 0 表示成功），< 0 表示失败
- (int)acceptOnSocket:(int)fd;

#pragma mark - 工具方法

/// 从十六进制字符串解析网络 ID
///
/// ZeroTier 网络 ID 通常以 16 位十六进制字符串表示（如 "a84ac5c10a1b2c3d"），
/// 本方法将其转换为 uint64_t。
///
/// @param networkIDStr 十六进制字符串
/// @return 网络 ID（解析失败返回 0）
+ (uint64_t)parseNetworkIDFromString:(NSString *)networkIDStr;

/// 将网络 ID 格式化为十六进制字符串
/// @param networkID 网络 ID
/// @return 16 位十六进制字符串（小写，如 "a84ac5c10a1b2c3d"）
+ (NSString *)formatNetworkID:(uint64_t)networkID;

@end

NS_ASSUME_NONNULL_END
