#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 联机房间状态
typedef NS_ENUM(NSInteger, MultiplayerRoomStatus) {
    MultiplayerRoomStatusDisconnected = 0, // 未连接
    MultiplayerRoomStatusConnecting   = 1, // 连接中
    MultiplayerRoomStatusConnected    = 2, // 已连接
    MultiplayerRoomStatusError        = 3  // 错误
};

/// 联机房间模型
@interface MultiplayerRoom : NSObject <NSCoding, NSSecureCoding>
@property (nonatomic, copy) NSString *roomId;          // 唯一标识（UUID）
@property (nonatomic, copy) NSString *name;            // 房间名称
@property (nonatomic, copy) NSString *networkId;       // ZeroTier Network ID（16位十六进制）
/// 房主在 ZeroTier 网络中的 IP（如 10.147.17.1，Ad-hoc 模式下为 IPv6 地址）。
///
/// 关键修复（M13）：hostIP 改为 atomic，与 status（H12 修复）保持一致。
/// hostIP 在 connectToRoomFlow:（后台 utility queue，在 _stateLock 内）和
/// zeroTierNetworkReady:（主线程，在 _stateLock 内）被写入，但在 UI cell、
/// shareTextForRoom:、lanPortDidDetect: 等主线程位置无锁读取。
/// atomic 保证单个 getter/setter 调用的原子性，避免读到中间状态。
@property (atomic, copy) NSString *hostIP;          // 房主在 ZeroTier 网络中的 IP（如 10.147.17.1）
@property (nonatomic, copy) NSString *hostPort;        // MC 服务器端口（默认 25565）
@property (nonatomic, copy) NSString *roomDescription; // 房间描述
/// 标记当前房间是否为房主侧房间。
///
/// 关键修复（房客加入后无法连接服务器）：
/// 之前 connectToRoomFlow: 和 zeroTierNetworkReady: 在获取到本机 ZeroTier IP 后
/// 会无条件执行 `room.hostIP = localIP`。这对于房主是正确的（房主需要将自己的 IP
/// 同步到 room.hostIP 用于生成分享代码），但对于房客是错误的：
///   - 房客的 room.hostIP 来自分享代码（房主的 IP，如 10.147.17.1）
///   - 房客连接后获取的 localIP 是房客自己的 ZeroTier IP（如 10.147.17.5）
///   - 无条件覆盖后 room.hostIP 变成房客自己的 IP
///   - PortForwarder 用错误的 room.hostIP 启动端口转发：127.0.0.1:25565 → 房客自己的IP:25565
///   - 房客在 MC 直接连接输入 127.0.0.1:25565，PortForwarder 转发到房客自己设备的 25565 端口
///   - 房客自己设备上没有 MC 服务器，连接失败，显示"无法加入服务器"
///
/// 修复方案：添加 isHostSide 属性区分房主/房客房间。只有 isHostSide=YES 的房间
/// 才会在 connectToRoomFlow: 和 zeroTierNetworkReady: 中更新 room.hostIP 为本机 IP。
/// 房客房间（isHostSide=NO）保持 room.hostIP 为分享代码中的房主 IP，确保 PortForwarder
/// 正确转发到房主的 ZeroTier IP。
///
/// 默认值 NO（房客模式，更安全：若未设置则不覆盖 hostIP，避免破坏房客的 hostIP）。
/// 房主创建房间时由 MultiplayerViewController.hostButtonTapped 显式设为 YES。
@property (nonatomic, assign) BOOL isHostSide;      // 是否为房主侧房间（YES=房主，NO=房客）
/// 连接状态。
///
/// 关键修复（H12）：status 改为 atomic，保证多线程读写的内存一致性。
/// 之前为 nonatomic assign，存在以下问题：
///   - 后台连接线程（MultiplayerManager.connectToRoomFlow）会写入 status
///   - 主线程（MultiplayerViewController）会读取 status 用于 UI 显示
///   - 主线程也会写入 status（如点击断开按钮时）
///   - 多线程同时读写 nonatomic 属性会导致读到部分写入的值或脏数据
///
/// atomic 属性会通过底层锁机制保证单个 getter/setter 调用的原子性，
/// 避免读到中间状态。对于状态机这种「单一值」属性，atomic 已足够。
///
/// 注意：atomic 不能保证组合操作（如 read-modify-write）的原子性，
/// 复杂的状态转换仍应由调用方通过锁（如 MultiplayerManager._stateLock）保护。
@property (atomic, assign) MultiplayerRoomStatus status; // 连接状态
@property (nonatomic, copy) NSString *ownerName;       // 房主名称
@property (nonatomic, strong) NSDate *createdAt;       // 创建时间
@property (nonatomic, strong) NSDate *lastConnectedAt; // 上次连接时间
@end

/// 联机状态变化通知代理
///
/// 当 ZeroTier 节点状态、网络状态发生变化时，会通过代理回调通知上层。
/// 所有回调方法都在主线程调用。
@protocol MultiplayerManagerDelegate <NSObject>
@optional

/// ZeroTier 节点已上线
- (void)multiplayerNodeOnline;

/// ZeroTier 节点已离线
- (void)multiplayerNodeOffline;

/// 指定房间已连接成功（网络已就绪且 SOCKS5 代理已启动）
/// @param room 连接成功的房间
- (void)multiplayerRoomConnected:(MultiplayerRoom *)room;

/// 指定房间连接失败
/// @param room 连接失败的房间
/// @param error 错误信息
- (void)multiplayerRoom:(MultiplayerRoom *)room
   didFailWithError:(NSError *)error;

/// ZeroTier 框架可用性检测结果
/// @param available YES 表示 zt.framework 已加载（非 stub）
- (void)multiplayerFrameworkAvailabilityChecked:(BOOL)available;

/// 连接流程进度更新
///
/// 在 connectToRoomFlow: 的各个步骤中调用，通知 UI 当前进度。
/// 用于让用户看到"正在启动节点"、"正在加入网络"等详细进度，
/// 而不是只显示一个静态的"正在连接..."提示。
///
/// @param message 进度描述文本（如"步骤 2：等待节点上线..."）
- (void)multiplayerConnectionProgress:(NSString *)message;

@end

/// ZeroTier 联机管理器
///
/// 参照 FCL 的 MultiplayerManager 和 ZL2 的 LanServerManager 设计：
/// 1. 管理本地联机房间列表（增删改查）
/// 2. 通过 ZeroTier Apple Framework (zt.framework) 在进程内加入/离开 ZeroTier 网络
/// 3. 启动本地 SOCKS5 代理，将 Minecraft 流量转发到 ZeroTier 虚拟网络
/// 4. 检测 zt.framework 是否可用（非 stub）
/// 5. 管理当前连接状态
/// 6. 生成分享信息（房间名 + Network ID + IP + 端口）
///
/// 与旧的基于 URL Scheme 的实现不同，本版本完全在 App 进程内运行 ZeroTier 节点，
/// 无需依赖外部的 ZeroTier One app，也不需要 NetworkExtension 权限。
/// 流量通过本地 SOCKS5 代理（127.0.0.1:1080）转发，Minecraft 通过 JVM 的
/// -DsocksProxyHost/-DsocksProxyPort 参数走代理。
@interface MultiplayerManager : NSObject

+ (instancetype)sharedManager;

/// 代理对象（弱引用）
@property (nonatomic, weak, nullable) id<MultiplayerManagerDelegate> delegate;

/// 当前连接的房间（nil 表示未连接任何房间）
///
/// 关键修复（M1）：改为 atomic，保证多线程读写的内存一致性。
/// currentRoom 在 connectToRoom（主线程）、connectToRoomFlow（后台 utility queue）、
/// disconnectCurrentRoom（任意线程）中被写入，在 UI、delegate 回调等多处被读取。
/// atomic 保证 getter/setter 的原子性，避免读到中间状态。
@property (atomic, strong, readonly, nullable) MultiplayerRoom *currentRoom;

/// 所有已保存的房间列表
@property (nonatomic, strong, readonly) NSArray<MultiplayerRoom *> *savedRooms;

/// 当前 SOCKS5 代理监听端口（代理未运行时返回 0）
///
/// 关键修复（M1）：改为 atomic，与 currentRoom 保持一致。
@property (atomic, assign, readonly) uint16_t currentSOCKS5Port;

/// 当前 SOCKS5 代理是否正在运行
@property (nonatomic, assign, readonly) BOOL isSOCKS5ProxyRunning;

/// 当前端口转发器监听的本地端口（未运行时返回 0）
///
/// 房客连接成功后，PortForwarder 在本地监听一个端口（如 25565），
/// 转发到房主的 ZeroTier IP:MC LAN 端口。房客在 MC 中输入
/// 127.0.0.1:此端口 即可连接到房主的游戏。
@property (atomic, assign, readonly) uint16_t currentForwardingPort;

/// 当前端口转发器是否正在运行
@property (nonatomic, assign, readonly) BOOL isPortForwarderRunning;

/// 当前房主侧反向端口转发器是否正在运行
///
/// 关键说明：房主侧使用 ReversePortForwarder 在 libzt socket 上监听房主的
/// ZeroTier IP:LAN_PORT，accept 房客的 libzt 连接后用系统 socket 转发到
/// 127.0.0.1:LAN_PORT（房主 MC 本地监听）。这是为了桥接 libzt socket 与
/// 系统 socket 命名空间，使房客能通过 ZeroTier 虚拟网络到达房主 MC 的 LAN 服务器。
@property (nonatomic, assign, readonly) BOOL isReversePortForwarderRunning;

/// ZeroTier 节点是否已上线
@property (nonatomic, assign, readonly) BOOL isNodeOnline;

/// 当前房间在 ZeroTier 网络中分配到的本地 IP（可用于显示给用户）
/// 仅在房间已连接且 ZeroTier 分配了 IP 后才有效
///
/// 关键修复（M1）：改为 atomic，与 currentRoom 保持一致。
@property (atomic, copy, readonly, nullable) NSString *currentLocalIP;

#pragma mark - 框架检测

/// 检测 zt.framework 是否可用（非 stub 实现）
///
/// 本方法委托给 ZeroTierBridge 的 isFrameworkAvailable，结果会被缓存。
/// 当 framework 不可用时（如 CI 构建环境链接了 zt_stub.c），所有联机功能将不可用。
///
/// @return YES 如果 framework 可用
- (BOOL)isFrameworkAvailable;

/// 用户是否启用了联机（持久化到 NSUserDefaults）
///
/// 此属性独立于 isNodeStarted，表示用户的意图而非节点实际状态。
/// 用于在 ViewController 重新加载时恢复联机开关状态。
///
/// 场景：用户点击联机开关 ON → 后台开始启动 ZeroTier 节点（耗时数秒）→
/// 用户关闭联机 ViewController → 用户重新打开联机 ViewController →
/// 此时节点可能仍在启动中（isNodeStarted=NO），但用户已表达启用意图
/// （isMultiplayerEnabled=YES），开关应显示为 ON。
///
/// 节点启动成功后，如果 isMultiplayerEnabled=YES，开关保持 ON；
/// 节点启动失败时，调用方应将 isMultiplayerEnabled 设为 NO 并回退开关。
///
/// 此属性持久化到 NSUserDefaults，即使关闭启动器（杀进程）再重新打开，
/// 也能恢复用户的联机启用状态（但节点不会自动启动，需要用户再次操作开关）。
///
/// @return YES 如果用户已启用联机
- (BOOL)isMultiplayerEnabled;

/// 设置联机启用状态（持久化到 NSUserDefaults）
/// @param enabled YES 表示用户启用了联机
- (void)setMultiplayerEnabled:(BOOL)enabled;

/// ZeroTier 节点是否已启动
/// @return YES 如果节点已启动（不要求已上线）
- (BOOL)isNodeStarted;

/// 启动 ZeroTier 节点
///
/// 如果节点尚未启动，则在后台线程启动节点。
/// 节点启动后会异步触发 ZTS_EVENT_NODE_ONLINE 事件。
///
/// @param completion 完成回调（主线程，YES 表示启动请求已成功提交）
- (void)ensureNodeStartedWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion;

#pragma mark - 兼容旧 API（已废弃，仅用于平滑过渡）

/// 检测 ZeroTier One app 是否已安装（已废弃）
///
/// 旧的基于 URL Scheme 的实现需要检测外部 ZeroTier One app 是否安装。
/// 新版本使用进程内 zt.framework，不再依赖外部 app。
/// 本方法现在返回 isFrameworkAvailable 的结果，保持 API 兼容性。
///
/// @return YES 如果 zt.framework 可用
- (BOOL)isZeroTierAppInstalled __attribute__((deprecated("使用 isFrameworkAvailable 代替")));

/// 设置 ZeroTier 安装状态覆盖（已废弃，新版本为空操作）
/// @param installed 已废弃参数，无实际效果
- (void)setZeroTierInstalledOverride:(BOOL)installed __attribute__((deprecated("新版本无需手动覆盖安装状态")));

/// 用户是否已手动覆盖 ZeroTier 安装状态（已废弃）
/// @return 始终返回 NO
- (BOOL)isZeroTierInstallOverridden __attribute__((deprecated("新版本始终返回 NO")));

/// 打开 ZeroTier One app（已废弃，新版本为空操作）
- (void)openZeroTierApp __attribute__((deprecated("新版本使用进程内框架，无需打开外部 app")));

#pragma mark - 网络加入与离开

/// 通过 Network ID 加入 ZeroTier 网络
///
/// 本方法直接在进程内调用 zts_net_join 加入指定网络。
/// 如果节点尚未启动，会先启动节点。
///
/// @param networkId ZeroTier Network ID（16位十六进制）
/// @param completion 完成回调（主线程，YES 表示加入请求已成功提交，不代表网络已就绪）
- (void)joinNetwork:(NSString *)networkId
         completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;

/// 离开 ZeroTier 网络
///
/// 本方法直接在进程内调用 zts_net_leave 离开指定网络。
///
/// @param networkId ZeroTier Network ID
- (void)leaveNetwork:(NSString *)networkId;

#pragma mark - 房间管理（增删改查）

/// 添加房间到本地列表
/// @param room 房间对象
- (void)addRoom:(MultiplayerRoom *)room;

/// 删除房间
/// @param roomId 房间 ID
- (void)removeRoom:(NSString *)roomId;

/// 更新房间信息
/// @param room 更新后的房间对象
- (void)updateRoom:(MultiplayerRoom *)room;

/// 获取指定房间
/// @param roomId 房间 ID
- (nullable MultiplayerRoom *)roomWithId:(NSString *)roomId;

#pragma mark - 连接管理

/// 连接到房间
///
/// 完整流程：
///   1. 校验 room 非空且 networkId 有效
///   2. 设置 currentRoom 并更新状态为 Connecting
///   3. 启动 ZeroTier 节点（如果尚未启动）
///   4. 加入 ZeroTier 网络
///   5. 等待网络就绪（IPv4 地址已分配）
///   6. 启动本地 SOCKS5 代理（端口 1080）
///   7. 设置 AMETHYST_SOCKS5_PROXY 环境变量（供 JavaLauncher 读取）
///   8. 更新房间状态为 Connected，回调 completion
///
/// 任何一步失败都会更新房间状态为 Error 并回调 completion(NO, error)。
///
/// @param room       房间对象
/// @param completion 完成回调（主线程）
- (void)connectToRoom:(MultiplayerRoom *)room
           completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// 断开当前房间连接
///
/// 流程：
///   1. 停止本地 SOCKS5 代理
///   2. 停止正向端口转发器（房客模式）
///   3. 停止反向端口转发器（房主模式）
///   4. 清除 AMETHYST_SOCKS5_PROXY 环境变量
///   5. 离开 ZeroTier 网络
///   6. 更新房间状态为 Disconnected
///   7. 清空 currentRoom
- (void)disconnectCurrentRoom;

#pragma mark - 房主侧反向端口转发

/// 启动房主侧反向端口转发
///
/// 关键架构修复（P0）：libzt 是用户态 socket 实现，与系统 socket 是两套独立的
/// 命名空间。房主 MC 通过 java.net.ServerSocket 在 127.0.0.1:LAN_PORT（系统
/// socket 命名空间）监听，房客通过 libzt socket connect 房主的 ZeroTier IP:LAN_PORT
/// 时，连接到达房主的 libzt 实例后无法直接交付给房主 MC 的系统 socket。
///
/// 本方法在 libzt socket 上监听房主的 ZeroTier IP:listenPort，accept 房客的
/// libzt 连接后用系统 socket 转发到 127.0.0.1:forwardPort（房主 MC 的本地监听地址）。
///
/// 调用时机：房主在 LanPortDetector 检测到 LAN 端口、生成分享代码后调用。
/// listenPort 与 forwardPort 通常相同（都是房主 MC 的 LAN 端口）。
///
/// @param listenPort 在 libzt 上监听的端口（房主 MC LAN 端口）
/// @param forwardPort 系统 socket 转发的目标端口（房主 MC LAN 端口，通常 = listenPort）
/// @param error 错误输出
/// @return YES 表示成功
- (BOOL)startHostReverseForwarderWithListenPort:(uint16_t)listenPort
                                     forwardPort:(uint16_t)forwardPort
                                          error:(NSError **)error;

/// 停止房主侧反向端口转发
- (void)stopHostReverseForwarder;

#pragma mark - 分享与导入

/// 生成房间的分享文本
/// @param room 房间对象
/// @return 分享文本
- (NSString *)shareTextForRoom:(MultiplayerRoom *)room;

/// 从分享文本解析房间信息
/// @param text 分享文本
/// @return 解析出的房间对象（解析失败返回 nil）
- (nullable MultiplayerRoom *)parseRoomFromShareText:(NSString *)text;

/// 生成新的 ZeroTier 风格房间 ID（UUID）
- (NSString *)generateRoomId;

#pragma mark - 分享代码（FCL 风格 Base64 编码）

/// 生成房间的分享代码（Base64 编码的 JSON）
///
/// 对标 FCL 的联机分享码：房主开放局域网后自动生成一段代码，
/// 房客输入代码即可加入房间。
///
/// 代码格式：Base64(JSON)，JSON 包含：
///   - networkId: ZeroTier Network ID
///   - hostIP: 房主在 ZeroTier 网络中的 IP
///   - hostPort: MC 服务器端口（LAN 端口或 25565）
///   - roomName: 房间名称
///
/// @param room 房间对象
/// @return Base64 编码的分享代码
- (NSString *)generateShareCodeForRoom:(MultiplayerRoom *)room;

/// 从分享代码解析房间信息（Base64 编码的 JSON）
///
/// @param code Base64 编码的分享代码
/// @return 解析出的房间对象（解析失败返回 nil）
- (nullable MultiplayerRoom *)parseShareCode:(NSString *)code;

#pragma mark - 预设 Network ID 管理（FCL 风格）

/// 获取用户预设的 ZeroTier Network ID
///
/// 对标 FCL：房主首次设置一次 Network ID（在 my.zerotier.com 创建后填入），
/// 之后每次开房自动使用这个 Network ID，无需重复输入。
///
/// @return 预设的 Network ID（未设置时返回 nil）
- (nullable NSString *)presetNetworkId;

/// 设置预设的 ZeroTier Network ID
/// @param networkId Network ID（传入 nil 或空字符串则清除）
- (void)setPresetNetworkId:(nullable NSString *)networkId;

#pragma mark - Ad-hoc 网络（快速模式，无需注册账号）

/// 生成 Ad-hoc 网络 ID（快速模式）
///
/// 对标 FCL 的"无需注册直接联机"体验：
///   - 调用 zts_net_compute_adhoc_id 生成一个无需网络控制器的公开网络 ID
///   - 房主和房客使用相同的端口范围即可加入同一网络
///   - 无需在 my.zerotier.com 注册账号、创建网络、授权成员
///
/// 注意：
///   1. Ad-hoc 网络只有 IPv6 地址（无 IPv4）
///   2. 网络是公开的，任何人都能加入（安全性弱）
///   3. IP 基于节点 ID 自动分配，可能变化（稳定性不如标准模式）
///   4. 端口范围限制：MC 服务器端口和 LAN 端口需在范围内
///
/// 为兼容 MC 的所有端口（25565 和 LAN 随机端口 49152-65535），
/// 本方法使用 0-65535 的全端口范围。
///
/// @return 16 位十六进制的 Ad-hoc 网络 ID 字符串
- (NSString *)generateAdhocNetworkId;

/// 判断 Network ID 是否为 Ad-hoc 网络
///
/// Ad-hoc 网络 ID 以 "ff" 开头（如 ff0000ffff000000）。
/// 用于在连接流程中区分标准模式和快速模式。
///
/// @param networkId 待判断的 Network ID
/// @return YES 如果是 Ad-hoc 网络
- (BOOL)isAdhocNetworkId:(NSString *)networkId;

#pragma mark - 校验工具

/// 验证 ZeroTier Network ID 格式
/// @param networkId 待校验的 Network ID 字符串
/// @return YES 如果格式有效
- (BOOL)isValidNetworkId:(NSString *)networkId;

/// 验证 IP 地址格式
/// @param ipAddress 待校验的 IP 地址字符串
/// @return YES 如果格式有效
- (BOOL)isValidIPAddress:(NSString *)ipAddress;

@end

NS_ASSUME_NONNULL_END
