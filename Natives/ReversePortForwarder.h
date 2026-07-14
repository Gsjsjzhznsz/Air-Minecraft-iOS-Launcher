//
//  ReversePortForwarder.h
//  Angel Aura Amethyst
//
//  房主侧反向 TCP 端口转发器（libzt → 系统 socket 桥接）
//
//  ============================================================================
//  设计说明
//  ============================================================================
//
//  本文件实现房主侧的反向端口转发器，与 PortForwarder（房客侧）配合使用，
//  解决 iOS 上 libzt socket 与系统 socket 之间的鸿沟问题。
//
//  问题背景（详见 PortForwarder.h）：
//    iOS 上 ZeroTier 通过进程内 libzt 实现，不创建系统网络接口（无 utun 设备）。
//    房主 Minecraft "对局域网开放"时，JVM 通过 java.net.ServerSocket 监听
//    127.0.0.1:LAN_PORT（系统 POSIX socket 命名空间）。
//    房客 PortForwarder 通过 libzt socket connect 到房主的 ZeroTier IP:LAN_PORT，
//    数据到达房主设备的 libzt 实例后，无法直接交付给房主 MC 的系统 socket 监听端口
//    —— 因为 libzt socket 与系统 socket 是两套独立的命名空间。
//
//  解决方案（反向 PortForwarder）：
//    房主侧在 libzt socket 上监听房主的 ZeroTier IP:LAN_PORT，
//    accept 房客的 libzt 连接后，用系统 POSIX socket connect 到 127.0.0.1:LAN_PORT
//    （房主 MC 的本地监听地址），双向转发数据。
//
//  完整数据流：
//    房客 MC
//      → 127.0.0.1:25565（房客 PortForwarder 系统监听）
//      → libzt socket（房客 PortForwarder connect 房主 ZeroTier IP:LAN_PORT）
//      → ZeroTier 虚拟网络
//      → 房主 libzt accept（本类，监听 房主 ZeroTier IP:LAN_PORT）
//      → 系统 socket connect 127.0.0.1:LAN_PORT（本类，房主 MC 本地监听地址）
//      → 房主 MC 服务器
//
//  工作流程：
//    1. 房主调用 startWithListenIP:listenPort:forwardHost:forwardPort:
//       创建 libzt socket 并 bind+listen 到房主 ZeroTier IP:LAN_PORT
//    2. 房客的 libzt socket connect 到房主 ZeroTier IP:LAN_PORT
//    3. 本类 accept 该连接（返回房客侧 libzt socket fd）
//    4. 本类用系统 POSIX socket connect 到 127.0.0.1:LAN_PORT（房主 MC）
//    5. 双向转发：libzt socket ↔ 系统 socket
//
//  与 PortForwarder 的对比：
//    - PortForwarder：系统 socket listen → libzt socket connect（房客侧）
//    - ReversePortForwarder：libzt socket listen → 系统 socket connect（房主侧）
//
//  与 ZeroTierBridge 的关系：
//    本类依赖 ZeroTierBridge 提供的 libzt 服务端 API：
//      - createTCPSocketForFamily: 创建 libzt socket
//      - bindSocket:toLocalIP:port: 绑定到本机 ZeroTier IP
//      - listenOnSocket:backlog: 监听
//      - acceptOnSocket: 接受连接
//      - sendData/recvData/closeSocket/shutdownSocket 数据转发与清理
//
//  ============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 房主侧反向端口转发器
///
/// 单例模式，通过 +sharedForwarder 获取全局唯一实例。
/// 在 libzt 虚拟网络上监听房主的 ZeroTier IP:port，accept 后用系统 socket
/// 转发到房主 MC 的本地监听地址（127.0.0.1:forwardPort）。
@interface ReversePortForwarder : NSObject

/// 单例访问
+ (instancetype)sharedForwarder;

/// 启动反向端口转发
///
/// 在 libzt 虚拟网络上监听 listenIP:listenPort（房主的 ZeroTier IP:LAN_PORT），
/// accept 后用系统 POSIX socket 连接到 forwardHost:forwardPort（通常 127.0.0.1:LAN_PORT，
/// 即房主 MC 的本地监听地址），双向转发数据。
///
/// 调用时机：房主在 LanPortDetector 检测到 LAN 端口、生成分享代码之后调用。
///
/// @param listenIP 在 libzt 上监听的本地 IP（房主的 ZeroTier IP，如 10.147.17.1）
/// @param listenPort 在 libzt 上监听的端口（房主 MC 的 LAN 端口）
/// @param forwardHost 系统 socket 转发的目标主机（通常 "127.0.0.1"）
/// @param forwardPort 系统 socket 转发的目标端口（通常 = listenPort，房主 MC 本地监听端口）
/// @param error 错误输出（如果失败）
/// @return YES 表示成功，NO 表示失败（错误通过 error 返回）
- (BOOL)startWithListenIP:(NSString *)listenIP
               listenPort:(uint16_t)listenPort
              forwardHost:(NSString *)forwardHost
              forwardPort:(uint16_t)forwardPort
                   error:(NSError **)error;

/// 停止反向端口转发
///
/// 关闭 libzt 监听 socket，停止接受新连接，shutdown 所有活跃连接。
- (void)stop;

/// 反向转发器是否正在运行
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// 当前监听的 libzt IP
@property (nonatomic, readonly, copy, nullable) NSString *listenIP;

/// 当前监听的 libzt 端口
@property (nonatomic, readonly) uint16_t listenPort;

/// 当前转发目标主机（系统 socket，通常 127.0.0.1）
@property (nonatomic, readonly, copy, nullable) NSString *forwardHost;

/// 当前转发目标端口（系统 socket，房主 MC LAN 端口）
@property (nonatomic, readonly) uint16_t forwardPort;

@end

NS_ASSUME_NONNULL_END
