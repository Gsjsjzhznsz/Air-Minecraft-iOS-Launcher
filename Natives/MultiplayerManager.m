//
//  MultiplayerManager.m
//  Amethyst
//
//  基于 ZeroTier Apple Framework 的 Minecraft 联机功能管理器实现
//
//  ============================================================================
//  设计理念与参照来源
//  ============================================================================
//
//  本文件参照了以下开源项目的联机管理器设计思路：
//
//  1. FCL (FoldCraftLauncher) - Android 平台的 MC 启动器
//     - 其 MultiplayerManager 通过 JNI 调用 libzt 直接在进程内建立 ZeroTier
//       虚拟网络，无需依赖外部 app。本实现采用相同的进程内运行思路。
//     - FCL 启动一个本地 SOCKS5 代理（基于 libzt socket），将 Minecraft 流量
//       转发到 ZeroTier 网络。本实现完全复刻此设计。
//
//  2. ZL2 (ZalithLauncher) - Android 平台的 MC 启动器（PojavLauncher 分支）
//     - 其 LanServerManager 同样基于 ZeroTier，提供了房间卡片 UI、
//       分享码导入、以及与 MC 内置"添加服务器"功能的联动。
//
//  3. ShardLauncher-iOS - iOS 平台的 MC 启动器
//     - 通过 git submodule 引入 zerotier-sockets-apple-framework (zt.framework)
//     - 使用 ZeroTierBridge 单例封装 libzt C API
//     - 缺陷：创建房间时跳转到 my.zerotier.com 官网，本实现修复此问题，
//       在 App 内完成全流程（输入 Network ID 即可加入，无需跳转）。
//
//  iOS 实现策略：
//    1. 直接链接 zt.framework（zerotier-sockets-apple-framework），在进程内运行
//       ZeroTier 节点。无需 NetworkExtension 权限，纯用户态运行。
//    2. 启动本地 SOCKS5 代理（127.0.0.1:1080），通过 libzt 的 BSD socket API
//       将流量转发到 ZeroTier 虚拟网络。
//    3. Minecraft 通过 JVM 参数 -DsocksProxyHost=127.0.0.1 -DsocksProxyPort=1080
//       走 SOCKS5 代理，所有 Minecraft 流量经 ZeroTier 网络到达房主服务器。
//    4. 启动器本地维护"联机房间"列表（房间名 + Network ID + 房主 IP + 端口），
//       使用 NSUserDefaults + NSKeyedArchiver（NSSecureCoding）持久化。
//    5. 启动器提供"分享文本"功能，将房间信息打包成一段带格式的文本，
//       方便通过微信/QQ/iMessage 等社交渠道发送给好友。
//
//  ZeroTier 网络 ID 说明：
//    - 16 位十六进制字符串（64 位无符号整数）
//    - 由用户在 https://my.zerotier.com 后台创建网络后获得
//    - 房主需在后台将网络设为"Private"并授权成员，或设为"Public"让任何人可加入
//    - 加入网络后，ZeroTier 会为每个节点分配一个虚拟 IP（如 10.147.17.x）
//
//  stub 模式：
//    如果 zt.framework 不可用（如 CI 构建环境链接了 zt_stub.c），所有 ZeroTier
//    API 返回 ZTS_ERR_SERVICE (-2)，isFrameworkAvailable 返回 NO，联机功能不可用。
//    UI 层应检测此情况并提示用户。
//
//  ============================================================================

#import "MultiplayerManager.h"
#import "ZeroTierBridge.h"
#import "SOCKS5Proxy.h"
#import "PortForwarder.h"
#import "LauncherPreferences.h"

#pragma mark - 常量定义

/// NSUserDefaults 中存储房间列表的 key
///
/// 关键修复（移除保存历史房间功能）：此 key 仅用于一次性迁移清理，
/// 不再用于持久化房间列表。用户明确表示不需要保存历史房间功能
/// （FCL 也没有此功能），每次启动器启动时房间列表应为空。
/// 启动时如果检测到旧数据，会主动清除。
static NSString * const kMultiplayerSavedRoomsKey = @"multiplayer_saved_rooms";

/// NSUserDefaults 中存储联机启用状态的 key
/// 用于持久化用户的联机启用意图，独立于节点实际启动状态。
static NSString * const kMultiplayerEnabledKey = @"multiplayer.enabled";

/// MC 默认服务器端口
static NSString * const kDefaultMCPort = @"25565";

/// 分享文本中的各种前缀标记（用于生成和解析）
static NSString * const kShareHeaderLine = @"🎮 来联机吧！";
static NSString * const kShareRoomNamePrefix = @"房间名称：";
static NSString * const kShareNetworkIdPrefix = @"ZeroTier网络ID：";
static NSString * const kShareServerAddressPrefix = @"服务器地址：";

/// SOCKS5 代理默认端口（与 SOCKS5Proxy.h 中的 SOCKS5ProxyDefaultPort 一致）
static uint16_t const kMultiplayerDefaultSOCKS5Port = 1080;

/// 传递给 JavaLauncher 的环境变量名，值为 "127.0.0.1:port"
/// JavaLauncher 检测到此环境变量后会注入 -DsocksProxyHost/-DsocksProxyPort 参数
static NSString * const kAMETHYSTSOCKS5ProxyEnvVar = @"AMETHYST_SOCKS5_PROXY";

/// 等待 ZeroTier 节点上线的超时时间（秒）
static NSTimeInterval const kNodeOnlineTimeout = 30.0;

/// 等待 ZeroTier 网络就绪的超时时间（秒）
static NSTimeInterval const kNetworkReadyTimeout = 30.0;

/// ZeroTier 节点身份文件存储目录名（位于 app Documents 目录下）
static NSString * const kZeroTierHomeDirName = @"zerotier_home";

/// 错误域名
static NSString * const kMultiplayerErrorDomain = @"MultiplayerManagerErrorDomain";

/// 错误码
typedef NS_ENUM(NSInteger, MultiplayerErrorCode) {
    MultiplayerErrorCodeRoomNotFound         = 1001, // 房间未找到
    MultiplayerErrorCodeRoomAlreadyExist     = 1002, // 房间已存在（roomId 重复）
    MultiplayerErrorCodeInvalidNetworkId     = 1003, // Network ID 格式无效
    MultiplayerErrorCodeInvalidRoom          = 1004, // 房间对象无效
    MultiplayerErrorCodeParseShareTextFailed = 1005, // 解析分享文本失败
    MultiplayerErrorCodeFrameworkUnavailable = 1006, // zt.framework 不可用（stub 模式）
    MultiplayerErrorCodeNodeStartFailed      = 1007, // ZeroTier 节点启动失败
    MultiplayerErrorCodeNodeOnlineTimeout    = 1008, // 等待节点上线超时
    MultiplayerErrorCodeJoinNetworkFailed    = 1009, // 加入网络失败
    MultiplayerErrorCodeNetworkReadyTimeout  = 1010, // 等待网络就绪超时
    MultiplayerErrorCodeSOCKS5ProxyStartFailed = 1011, // SOCKS5 代理启动失败
};

#pragma mark - MultiplayerRoom 实现

@implementation MultiplayerRoom

/// NSSecureCoding 要求：声明该类支持安全编码
+ (BOOL)supportsSecureCoding {
    return YES;
}

/// 便捷初始化方法
- (instancetype)initWithId:(NSString *)roomId
                      name:(NSString *)name
                 networkId:(NSString *)networkId
                    hostIP:(NSString *)hostIP
                  hostPort:(NSString *)hostPort {
    self = [super init];
    if (self) {
        _roomId = roomId ?: [[NSUUID UUID] UUIDString];
        _name = [name copy] ?: @"";
        _networkId = [networkId copy] ?: @"";
        _hostIP = [hostIP copy] ?: @"";
        _hostPort = [hostPort copy] ?: kDefaultMCPort;
        _roomDescription = @"";
        _status = MultiplayerRoomStatusDisconnected;
        _ownerName = @"";
        _createdAt = [NSDate date];
        _lastConnectedAt = nil;
        // 关键修复（房客加入后无法连接服务器）：默认 isHostSide=NO（房客模式）。
        // 调用方可按需在创建后通过 room.isHostSide = YES 设置为房主模式。
        // 默认 NO 更安全：若未设置则 connectToRoomFlow: 不会覆盖 hostIP，
        // 避免破坏房客从分享代码解析得到的房主 IP。
        _isHostSide = NO;
    }
    return self;
}

#pragma mark - NSSecureCoding / NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _roomId = [coder decodeObjectOfClass:[NSString class] forKey:@"roomId"] ?: @"";
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"] ?: @"";
        _networkId = [coder decodeObjectOfClass:[NSString class] forKey:@"networkId"] ?: @"";
        _hostIP = [coder decodeObjectOfClass:[NSString class] forKey:@"hostIP"] ?: @"";
        _hostPort = [coder decodeObjectOfClass:[NSString class] forKey:@"hostPort"] ?: kDefaultMCPort;
        _roomDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"description"] ?: @"";
        _ownerName = [coder decodeObjectOfClass:[NSString class] forKey:@"ownerName"] ?: @"";

        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _lastConnectedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastConnectedAt"];

        NSInteger statusValue = [coder decodeIntegerForKey:@"status"];
        if (statusValue < MultiplayerRoomStatusDisconnected ||
            statusValue > MultiplayerRoomStatusError) {
            statusValue = MultiplayerRoomStatusDisconnected;
        }
        _status = (MultiplayerRoomStatus)statusValue;

        // 关键修复（房客加入后无法连接服务器）：解码 isHostSide。
        // 旧版本的数据中没有此字段，containsValueForKey: 检测后使用默认值 NO（房客模式）。
        // 默认 NO 更安全：旧数据反序列化后不会覆盖 hostIP，避免破坏已存在的房主 IP。
        if ([coder containsValueForKey:@"isHostSide"]) {
            _isHostSide = [coder decodeBoolForKey:@"isHostSide"];
        } else {
            _isHostSide = NO;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.roomId forKey:@"roomId"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.networkId forKey:@"networkId"];
    [coder encodeObject:self.hostIP forKey:@"hostIP"];
    [coder encodeObject:self.hostPort forKey:@"hostPort"];
    [coder encodeObject:self.roomDescription forKey:@"description"];
    [coder encodeObject:self.ownerName forKey:@"ownerName"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.lastConnectedAt forKey:@"lastConnectedAt"];
    [coder encodeInteger:(NSInteger)self.status forKey:@"status"];
    // 关键修复（房客加入后无法连接服务器）：编码 isHostSide
    [coder encodeBool:self.isHostSide forKey:@"isHostSide"];
}

#pragma mark - 描述方法（便于调试）

- (NSString *)description {
    return [NSString stringWithFormat:@"<MultiplayerRoom: %p roomId=%@ name=%@ networkId=%@ host=%@:%@ status=%ld isHostSide=%d>",
            self,
            self.roomId,
            self.name,
            self.networkId,
            self.hostIP,
            self.hostPort,
            (long)self.status,
            self.isHostSide];
}

#pragma mark - 复制与相等性（便于去重和比较）

- (id)copyWithZone:(NSZone *)zone {
    MultiplayerRoom *copy = [[MultiplayerRoom alloc] init];
    copy.roomId = [self.roomId copy];
    copy.name = [self.name copy];
    copy.networkId = [self.networkId copy];
    copy.hostIP = [self.hostIP copy];
    copy.hostPort = [self.hostPort copy];
    copy.roomDescription = [self.roomDescription copy];
    copy.status = self.status;
    copy.ownerName = [self.ownerName copy];
    copy.createdAt = [self.createdAt copy];
    copy.lastConnectedAt = [self.lastConnectedAt copy];
    // 关键修复（房客加入后无法连接服务器）：复制 isHostSide 标志
    copy.isHostSide = self.isHostSide;
    return copy;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[MultiplayerRoom class]]) return NO;
    MultiplayerRoom *other = (MultiplayerRoom *)object;
    return [self.roomId isEqualToString:other.roomId];
}

- (NSUInteger)hash {
    return self.roomId.hash;
}

@end

#pragma mark - MultiplayerManager 实现

@interface MultiplayerManager () <ZeroTierBridgeDelegate>
{
    /// 用于保护房间列表读写操作的锁
    dispatch_queue_t _serializationQueue;

    /// 保护 _currentRoom / _currentLocalIP / _nodeStarted 等连接状态的锁
    NSLock *_stateLock;
}

/// 可读写的房间列表（头文件中声明为 readonly）
@property (nonatomic, strong, readwrite) NSMutableArray<MultiplayerRoom *> *internalRooms;

/// 可读写的当前房间（头文件中声明为 readonly）
/// 关键修复（M1）：改为 atomic，保证 setter 的原子性，避免多线程读写时读到中间状态。
@property (atomic, strong, readwrite, nullable) MultiplayerRoom *currentRoom;

/// 可读写的 SOCKS5 端口
/// 关键修复（M1）：改为 atomic，与头文件声明保持一致
@property (atomic, assign, readwrite) uint16_t currentSOCKS5Port;

/// 可读写的本地 IP
/// 关键修复（M1）：改为 atomic，与头文件声明保持一致
@property (atomic, copy, readwrite, nullable) NSString *currentLocalIP;

/// 可读写的端口转发本地端口
@property (atomic, assign, readwrite) uint16_t currentForwardingPort;

/// ZeroTier 节点是否已启动（不代表已上线）
@property (nonatomic, assign, readwrite) BOOL nodeStarted;

/// 当前正在连接的 Network ID（uint64_t 形式，用于 ZeroTierBridge 查询状态）
/// 0 表示当前没有正在连接的网络
@property (nonatomic, assign) uint64_t currentNetworkID;
@end

@implementation MultiplayerManager

#pragma mark - 单例模式

+ (instancetype)sharedManager {
    static MultiplayerManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static MultiplayerManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [super allocWithZone:zone];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serializationQueue = dispatch_queue_create("com.angelaura.multiplayer.serialization", DISPATCH_QUEUE_SERIAL);
        _stateLock = [[NSLock alloc] init];
        _internalRooms = [[NSMutableArray alloc] init];
        _currentRoom = nil;
        _currentSOCKS5Port = 0;
        _currentLocalIP = nil;
        _nodeStarted = NO;
        _currentNetworkID = 0;

        // 关键修复（移除保存历史房间功能）：
        // 不再从 NSUserDefaults 加载历史房间列表，每次启动时房间列表为空。
        // 同时主动清除可能存在的旧数据（一次性迁移），避免残留。
        [self cleanupLegacySavedRooms];

        // 设置 ZeroTierBridge 代理，接收节点/网络状态回调
        [[ZeroTierBridge sharedInstance] setDelegate:self];

        NSLog(@"[MultiplayerManager] 初始化完成（不加载历史房间，房间列表为空）");
    }
    return self;
}

#pragma mark - 对外暴露的只读属性

- (NSArray<MultiplayerRoom *> *)savedRooms {
    // 关键修复（C2）：移除 dispatch_sync(dispatch_get_main_queue())，
    // 因为从后台线程 dispatch_sync 到主线程会与 @synchronized(self) 形成两套锁机制混用，
    // 导致死锁风险（主线程等待 @synchronized 释放，后台线程等待主线程执行）。
    // 修复方案：统一使用 @synchronized 保护 _internalRooms 的读写，
    // 返回不可变副本（copy），调用方修改不影响内部状态。
    @synchronized(self) {
        return [_internalRooms copy];
    }
}

- (BOOL)isSOCKS5ProxyRunning {
    return [[SOCKS5Proxy sharedProxy] isRunning];
}

- (BOOL)isPortForwarderRunning {
    return [[PortForwarder sharedForwarder] isRunning];
}

- (BOOL)isNodeOnline {
    return [[ZeroTierBridge sharedInstance] isNodeOnline];
}

#pragma mark - 联机启用状态管理

/// 用户是否启用了联机（从 NSUserDefaults 读取）
///
/// 此属性独立于 isNodeStarted，表示用户的意图而非节点实际状态。
/// 用于在 ViewController 重新加载时恢复联机开关状态。
- (BOOL)isMultiplayerEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kMultiplayerEnabledKey];
}

/// 设置联机启用状态（持久化到 NSUserDefaults）
- (void)setMultiplayerEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (enabled) {
        [defaults setBool:YES forKey:kMultiplayerEnabledKey];
    } else {
        [defaults setBool:NO forKey:kMultiplayerEnabledKey];
    }
    [defaults synchronize];
    NSLog(@"[MultiplayerManager] 联机启用状态已设置为 %d", enabled);
}

#pragma mark - 数据持久化（已禁用）

/// 清除旧的保存房间数据（一次性迁移）
///
/// 关键修复（移除保存历史房间功能）：
/// 用户明确表示不需要保存历史房间功能（FCL 也没有此功能）。
/// 此方法在 init 中调用，主动清除可能存在于 NSUserDefaults 中的旧房间数据。
/// 清除后，房间列表完全在内存中管理，不进行持久化。
- (void)cleanupLegacySavedRooms {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *legacyData = [defaults dataForKey:kMultiplayerSavedRoomsKey];
    if (legacyData && legacyData.length > 0) {
        NSLog(@"[MultiplayerManager] 检测到旧版本保存的房间数据（%lu 字节），正在清除...",
              (unsigned long)legacyData.length);
        [defaults removeObjectForKey:kMultiplayerSavedRoomsKey];
        [defaults synchronize];
        NSLog(@"[MultiplayerManager] 旧房间数据已清除（不再持久化房间列表）");
    }
}

/// loadRooms 已废弃（空操作）
///
/// 关键修复（移除保存历史房间功能）：房间列表不再从 NSUserDefaults 加载。
/// 每次启动器启动时房间列表为空，房间仅在当前会话中存在（内存中）。
/// 此方法保留为空操作是为了兼容现有代码中可能的调用（虽然 init 已不再调用）。
- (void)loadRooms {
    // 空操作：不再从持久化存储加载房间列表
    @synchronized(self) {
        self.internalRooms = [[NSMutableArray alloc] init];
    }
}

/// saveRooms 已废弃（空操作）
///
/// 关键修复（移除保存历史房间功能）：房间列表不再持久化到 NSUserDefaults。
/// 此方法保留为空操作是为了兼容现有代码中大量的 [self saveRooms] 调用，
/// 避免需要修改每一处调用点。房间列表仅在内存中管理，关闭启动器后自动清空。
- (void)saveRooms {
    // 空操作：不再持久化房间列表到 NSUserDefaults
    // 房间列表仅在内存中管理，关闭启动器后自动清空
}

#pragma mark - 框架检测与节点管理

- (BOOL)isFrameworkAvailable {
    return [[ZeroTierBridge sharedInstance] isFrameworkAvailable];
}

- (BOOL)isNodeStarted {
    [_stateLock lock];
    BOOL started = _nodeStarted;
    [_stateLock unlock];
    return started;
}

/// 获取 ZeroTier 节点身份文件存储目录
/// 位于 app Documents 目录下的 zerotier_home 子目录
- (NSString *)zeroTierHomeDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = paths.firstObject ?: NSTemporaryDirectory();
    NSString *homeDir = [documentsDir stringByAppendingPathComponent:kZeroTierHomeDirName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:homeDir]) {
        [fm createDirectoryAtPath:homeDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    }
    return homeDir;
}

- (void)ensureNodeStartedWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    // 如果节点已启动，直接回调成功
    if ([self isNodeStarted]) {
        NSLog(@"[MultiplayerManager] ZeroTier 节点已启动，跳过重复启动");
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, nil);
            });
        }
        return;
    }

    // 检测 framework 是否可用
    if (![[ZeroTierBridge sharedInstance] isFrameworkAvailable]) {
        NSLog(@"[MultiplayerManager] zt.framework 不可用，无法启动 ZeroTier 节点");
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeFrameworkUnavailable
                                              userInfo:@{NSLocalizedDescriptionKey: @"ZeroTier 框架不可用，无法启动联机功能"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    NSLog(@"[MultiplayerManager] 启动 ZeroTier 节点...");

    // 在后台线程启动节点，避免阻塞主线程
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *homeDir = [self zeroTierHomeDirectory];
        NSError *startError = nil;
        BOOL success = [[ZeroTierBridge sharedInstance] startNodeWithHomeDirectory:homeDir
                                                                            error:&startError];
        if (success) {
            [self->_stateLock lock];
            self->_nodeStarted = YES;
            [self->_stateLock unlock];
            NSLog(@"[MultiplayerManager] ZeroTier 节点启动请求已提交，等待上线...");
        } else {
            NSLog(@"[MultiplayerManager] ZeroTier 节点启动失败：%@", startError.localizedDescription);
        }

        if (completion) {
            NSError *cbError = success ? nil : [NSError errorWithDomain:kMultiplayerErrorDomain
                                                                     code:MultiplayerErrorCodeNodeStartFailed
                                                                 userInfo:@{NSLocalizedDescriptionKey: startError.localizedDescription ?: @"节点启动失败"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, cbError);
            });
        }
    });
}

#pragma mark - 兼容旧 API（已废弃）

- (BOOL)isZeroTierAppInstalled {
    // 旧 API：检测外部 ZeroTier One app 是否安装
    // 新版本：检测 zt.framework 是否可用
    return [self isFrameworkAvailable];
}

- (void)setZeroTierInstalledOverride:(BOOL)installed {
    // 旧 API：用户手动覆盖 ZeroTier 安装状态
    // 新版本：进程内框架无需此机制，空操作
    NSLog(@"[MultiplayerManager] setZeroTierInstalledOverride:%d 已废弃，新版本无需此操作", installed);
}

- (BOOL)isZeroTierInstallOverridden {
    // 旧 API：用户是否已手动覆盖
    // 新版本：始终返回 NO
    return NO;
}

- (void)openZeroTierApp {
    // 旧 API：打开外部 ZeroTier One app
    // 新版本：进程内框架，无需打开外部 app，空操作
    NSLog(@"[MultiplayerManager] openZeroTierApp 已废弃，新版本使用进程内框架");
}

#pragma mark - 网络加入与离开

- (void)joinNetwork:(NSString *)networkId
         completion:(void (^)(BOOL, NSError * _Nullable))completion {
    if (!networkId || networkId.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeInvalidNetworkId
                                              userInfo:@{NSLocalizedDescriptionKey: @"Network ID 为空"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    NSString *trimmedNetworkId = [networkId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (![self isValidNetworkId:trimmedNetworkId]) {
        NSLog(@"[MultiplayerManager] joinNetwork: Network ID 格式无效：%@", trimmedNetworkId);
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeInvalidNetworkId
                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Network ID 格式无效：%@", trimmedNetworkId]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    // 确保节点已启动后再加入网络
    [self ensureNodeStartedWithCompletion:^(BOOL nodeStarted, NSError * _Nullable nodeError) {
        if (!nodeStarted) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nodeError);
                });
            }
            return;
        }

        // 在后台线程执行 joinNetwork（ZeroTierBridge 是同步调用，但内部只是提交请求）
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            uint64_t netID = [ZeroTierBridge parseNetworkIDFromString:trimmedNetworkId];
            if (netID == 0) {
                if (completion) {
                    NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                          code:MultiplayerErrorCodeInvalidNetworkId
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Network ID 解析失败"}];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, error);
                    });
                }
                return;
            }

            NSError *joinError = nil;
            BOOL success = [[ZeroTierBridge sharedInstance] joinNetwork:netID error:&joinError];
            if (success) {
                NSLog(@"[MultiplayerManager] 已加入 ZeroTier 网络 %@，等待网络就绪...", trimmedNetworkId);
            } else {
                NSLog(@"[MultiplayerManager] 加入 ZeroTier 网络失败：%@", joinError.localizedDescription);
            }

            if (completion) {
                NSError *cbError = success ? nil : [NSError errorWithDomain:kMultiplayerErrorDomain
                                                                          code:MultiplayerErrorCodeJoinNetworkFailed
                                                                      userInfo:@{NSLocalizedDescriptionKey: joinError.localizedDescription ?: @"加入网络失败"}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(success, cbError);
                });
            }
        });
    }];
}

- (void)leaveNetwork:(NSString *)networkId {
    if (!networkId || networkId.length == 0) {
        NSLog(@"[MultiplayerManager] leaveNetwork: networkId 为空");
        return;
    }

    NSString *trimmedNetworkId = [networkId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    uint64_t netID = [ZeroTierBridge parseNetworkIDFromString:trimmedNetworkId];
    if (netID == 0) {
        NSLog(@"[MultiplayerManager] leaveNetwork: Network ID 解析失败：%@", trimmedNetworkId);
        return;
    }

    BOOL success = [[ZeroTierBridge sharedInstance] leaveNetwork:netID];
    if (success) {
        NSLog(@"[MultiplayerManager] 已离开 ZeroTier 网络 %@", trimmedNetworkId);
    } else {
        NSLog(@"[MultiplayerManager] 离开 ZeroTier 网络失败：%@", trimmedNetworkId);
    }

    // 清理当前网络 ID 跟踪
    [_stateLock lock];
    if (_currentNetworkID == netID) {
        _currentNetworkID = 0;
    }
    [_stateLock unlock];
}

#pragma mark - 房间管理（增删改查）

- (void)addRoom:(MultiplayerRoom *)room {
    if (!room) {
        NSLog(@"[MultiplayerManager] addRoom: room 为空");
        return;
    }

    if (!room.roomId || room.roomId.length == 0) {
        NSLog(@"[MultiplayerManager] addRoom: roomId 为空，自动生成");
        room.roomId = [[NSUUID UUID] UUIDString];
    }

    if (!room.name || room.name.length == 0) {
        room.name = @"未命名房间";
    }

    if (!room.hostPort || room.hostPort.length == 0) {
        room.hostPort = kDefaultMCPort;
    }

    if (!room.createdAt) {
        room.createdAt = [NSDate date];
    }

    @synchronized(self) {
        for (MultiplayerRoom *existing in self.internalRooms) {
            if ([existing.roomId isEqualToString:room.roomId]) {
                NSLog(@"[MultiplayerManager] addRoom: roomId 已存在：%@", room.roomId);
                return;
            }
        }

        [self.internalRooms addObject:room];
        [self sortRoomsByCreatedAt];
    }

    NSLog(@"[MultiplayerManager] 已添加房间：%@（%@）", room.name, room.roomId);
    [self saveRooms];
}

- (void)removeRoom:(NSString *)roomId {
    if (!roomId || roomId.length == 0) {
        NSLog(@"[MultiplayerManager] removeRoom: roomId 为空");
        return;
    }

    // 关键修复（M6）：不在 @synchronized 内调用 disconnectCurrentRoom。
    // 之前在 @synchronized 内调用 disconnectCurrentRoom，后者会调用
    // [[SOCKS5Proxy sharedProxy] stop]，stop 会等待客户端线程退出（最长 2 秒）。
    // 此期间 @synchronized(self) 被持有，阻塞所有房间列表操作
    // （savedRooms、addRoom:、updateRoom:、roomWithId: 等），可能导致主线程 UI 卡顿。
    //
    // 修复方案：
    //   1. 在 @synchronized 内只做房间列表的修改和判断是否需要断开
    //   2. 把 disconnectCurrentRoom 的调用移到 @synchronized 外面
    //
    // 关键修复（M2）：移除冗余的 self.currentRoom = nil 和 roomToDisconnect.status = ...
    // disconnectCurrentRoom 已经在 _stateLock 内清空了 currentRoom 和更新了 room.status，
    // 不需要再次设置（且在无 _stateLock 时写入 currentRoom 构成数据竞争）。

    BOOL needsDisconnect = NO;
    @synchronized(self) {
        NSMutableArray *roomsToKeep = [[NSMutableArray alloc] init];
        MultiplayerRoom *roomToRemove = nil;

        for (MultiplayerRoom *room in self.internalRooms) {
            if ([room.roomId isEqualToString:roomId]) {
                roomToRemove = room;
            } else {
                [roomsToKeep addObject:room];
            }
        }

        if (!roomToRemove) {
            NSLog(@"[MultiplayerManager] removeRoom: 未找到 roomId：%@", roomId);
            return;
        }

        self.internalRooms = roomsToKeep;

        // 检查是否需要断开当前连接（在 _stateLock 内读取 currentRoom）
        [_stateLock lock];
        needsDisconnect = (self.currentRoom != nil &&
                           [self.currentRoom.roomId isEqualToString:roomId]);
        [_stateLock unlock];
    }

    // 在锁外断开当前连接（避免长时间持锁）
    if (needsDisconnect) {
        NSLog(@"[MultiplayerManager] 删除的房间是当前连接的房间，先断开连接");
        [self disconnectCurrentRoom];
    }

    NSLog(@"[MultiplayerManager] 已删除房间：%@", roomId);
    [self saveRooms];
}

- (void)updateRoom:(MultiplayerRoom *)room {
    if (!room || !room.roomId || room.roomId.length == 0) {
        NSLog(@"[MultiplayerManager] updateRoom: room 或 roomId 为空");
        return;
    }

    // 关键修复（M3）：currentRoom 的读写必须通过 _stateLock 保护，
    // 不能与 @synchronized(self) 混用。
    // 之前在 @synchronized(self) 内直接读写 self.currentRoom，但 currentRoom
    // 在其他所有位置（connectToRoom、disconnectCurrentRoom、connectToRoomFlow 等）
    // 都通过 _stateLock 保护。两套锁机制混用导致：
    //   - 后台线程通过 @synchronized 写入 currentRoom
    //   - 主线程通过 _stateLock 读取 currentRoom
    //   - 两者无共同的内存屏障，可能导致主线程读到旧值
    //
    // 修复方案：在 @synchronized 内只更新 internalRooms，
    // currentRoom 的读写单独通过 _stateLock 保护。

    @synchronized(self) {
        BOOL found = NO;
        NSMutableArray *updatedRooms = [[NSMutableArray alloc] init];

        for (MultiplayerRoom *existing in self.internalRooms) {
            if ([existing.roomId isEqualToString:room.roomId]) {
                [updatedRooms addObject:room];
                found = YES;
            } else {
                [updatedRooms addObject:existing];
            }
        }

        if (!found) {
            NSLog(@"[MultiplayerManager] updateRoom: 未找到 roomId：%@", room.roomId);
            return;
        }

        self.internalRooms = updatedRooms;
        [self sortRoomsByCreatedAt];
    }

    // 在 _stateLock 内同步更新 currentRoom 引用
    [_stateLock lock];
    if (self.currentRoom && [self.currentRoom.roomId isEqualToString:room.roomId]) {
        self.currentRoom = room;
    }
    [_stateLock unlock];

    NSLog(@"[MultiplayerManager] 已更新房间：%@（%@）", room.name, room.roomId);
    [self saveRooms];
}

- (nullable MultiplayerRoom *)roomWithId:(NSString *)roomId {
    if (!roomId || roomId.length == 0) {
        return nil;
    }

    @synchronized(self) {
        for (MultiplayerRoom *room in self.internalRooms) {
            if ([room.roomId isEqualToString:roomId]) {
                return room;
            }
        }
    }
    return nil;
}

- (void)sortRoomsByCreatedAt {
    [self.internalRooms sortUsingComparator:^NSComparisonResult(MultiplayerRoom *room1, MultiplayerRoom *room2) {
        NSDate *date1 = room1.createdAt;
        NSDate *date2 = room2.createdAt;

        if (!date1 && !date2) return NSOrderedSame;
        if (!date1) return NSOrderedAscending;
        if (!date2) return NSOrderedDescending;

        NSComparisonResult result = [date2 compare:date1];
        if (result == NSOrderedSame) {
            return [room1.roomId compare:room2.roomId];
        }
        return result;
    }];
}

#pragma mark - 连接管理

- (void)connectToRoom:(MultiplayerRoom *)room
           completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!room) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeInvalidRoom
                                              userInfo:@{NSLocalizedDescriptionKey: @"房间对象为空"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    if (!room.networkId || room.networkId.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeInvalidNetworkId
                                              userInfo:@{NSLocalizedDescriptionKey: @"房间的 Network ID 为空"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    // 检测 framework 可用性
    if (![[ZeroTierBridge sharedInstance] isFrameworkAvailable]) {
        NSLog(@"[MultiplayerManager] zt.framework 不可用，无法连接房间");
        room.status = MultiplayerRoomStatusError;
        [self updateRoom:room];
        if (completion) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeFrameworkUnavailable
                                              userInfo:@{NSLocalizedDescriptionKey: @"ZeroTier 框架不可用，请确保 zt.framework 已正确集成"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
        }
        return;
    }

    NSLog(@"[MultiplayerManager] 开始连接房间：%@（Network ID: %@）", room.name, room.networkId);

    // 1. 设置当前房间并更新状态为连接中
    //
    // 关键修复（严重1）：room.status 的修改必须在 _stateLock 内完成，
    // 与 currentRoom 的赋值保持原子性。之前在锁外修改 room.status，
    // 如果 disconnectCurrentRoom 并发执行，会出现：
    //   - connectToRoom 设置 currentRoom = room（持锁）
    //   - disconnectCurrentRoom 读到 currentRoom = room（持锁）
    //   - connectToRoom 写 room.status = Connecting（已释放锁）
    //   - disconnectCurrentRoom 写 room.status = Disconnected（已释放锁，覆盖）
    //   - 最终 status 与实际状态不符
    [_stateLock lock];
    self.currentRoom = room;
    self.currentNetworkID = [ZeroTierBridge parseNetworkIDFromString:room.networkId];
    room.status = MultiplayerRoomStatusConnecting;
    room.lastConnectedAt = [NSDate date];
    [_stateLock unlock];

    // 关键修复：如果房间不在列表中，先添加到列表，否则后续 updateRoom 都会因找不到 roomId 而失败
    if (![self roomWithId:room.roomId]) {
        NSLog(@"[MultiplayerManager] 房间不在列表中，先添加：%@", room.roomId);
        [self addRoom:room];
    }
    [self updateRoom:room];

    // 2. 完整连接流程（在后台线程执行，避免阻塞主线程）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self connectToRoomFlow:room completion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                NSLog(@"[MultiplayerManager] 房间连接成功：%@", room.name);
                room.status = MultiplayerRoomStatusConnected;
            } else {
                NSLog(@"[MultiplayerManager] 房间连接失败：%@ - %@", room.name, error.localizedDescription);
                room.status = MultiplayerRoomStatusError;

                // 关键修复（M4）：连接失败时清空 currentRoom/currentNetworkID 等状态引用。
                // 之前只更新了 room.status 但未清空 manager 持有的 currentRoom 引用，
                // 导致：
                //   - self.currentRoom 仍指向失败房间，UI 显示错误的"当前连接"
                //   - _currentNetworkID 仍匹配该网络，导致后续 zeroTierNetworkReady: 回调
                //     仍会匹配并更新已放弃连接的状态
                //   - 重试连接同一房间时状态不一致
                //
                // 修复方案：在 _stateLock 内检查 currentRoom 是否仍是同一个 room，
                // 只有当 currentRoom 仍是 room 时才清空（避免清空用户已切换到的新房间）。
                [self->_stateLock lock];
                if (self.currentRoom && [self.currentRoom.roomId isEqualToString:room.roomId]) {
                    self.currentRoom = nil;
                    self.currentNetworkID = 0;
                    self.currentLocalIP = nil;
                    self.currentSOCKS5Port = 0;
                    self.currentForwardingPort = 0;
                    NSLog(@"[MultiplayerManager] 连接失败，已清空 currentRoom 状态引用");
                } else {
                    NSLog(@"[MultiplayerManager] 连接失败但 currentRoom 已变更（用户可能切换了房间），不清空状态");
                }
                [self->_stateLock unlock];
            }
            [self updateRoom:room];

            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(success, error);
                });
            }
        }];
    });
}

/// 通知 delegate 连接流程进度
///
/// 在 connectToRoomFlow: 的各个步骤中调用，让 UI 能实时显示当前进度。
/// 通过 dispatch_async 到主线程调用，确保线程安全。
///
/// @param message 进度描述文本
- (void)notifyConnectionProgress:(NSString *)message {
    if ([self.delegate respondsToSelector:@selector(multiplayerConnectionProgress:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate multiplayerConnectionProgress:message];
        });
    }
}

/// 房间连接的完整流程（在后台线程执行）
///
/// 步骤：
///   1. 启动 ZeroTier 节点（如果尚未启动）
///   2. 等待节点上线
///   3. 加入 ZeroTier 网络
///   4. 等待网络就绪（IPv4 地址已分配）
///   5. 启动本地 SOCKS5 代理
///   6. 设置 AMETHYST_SOCKS5_PROXY 环境变量
- (void)connectToRoomFlow:(MultiplayerRoom *)room
               completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    // 步骤 1：启动节点
    //
    // 关键修复（H5）：移除 dispatch_semaphore_wait 对主线程的依赖。
    // 之前的实现调用 ensureNodeStartedWithCompletion:，该方法会将 completion
    // 通过 dispatch_async(main_queue) 投递到主线程执行。如果在 connectToRoomFlow
    // 中用 semaphore 等待该 completion，会出现：
    //   - 主线程若被 UI 操作（如滑表格、点击按钮）占用，completion 会被延迟执行，
    //     导致 semaphore 等待时间变长，进而让整个连接流程超时。
    //   - 极端情况：若上层在主线程同步等待连接流程完成（虽然不推荐），会形成
    //     主线程等待后台线程、后台线程等待主线程的死锁。
    //
    // 修复方案：connectToRoomFlow 已经在后台 utility queue 执行，直接调用
    // ZeroTierBridge 的 startNodeWithHomeDirectory:error: 同步 API，避免经过
    // main_queue 分发。framework 可用性检查在 connectToRoom 入口已做，此处不再重复。
    if (![self isNodeStarted]) {
        NSLog(@"[MultiplayerManager] [连接流程] 步骤 1：启动 ZeroTier 节点");
        [self notifyConnectionProgress:@"步骤 1/6：正在启动 ZeroTier 节点..."];
        NSString *homeDir = [self zeroTierHomeDirectory];
        NSError *startError = nil;
        BOOL nodeStartSuccess = [[ZeroTierBridge sharedInstance] startNodeWithHomeDirectory:homeDir
                                                                                     error:&startError];
        if (nodeStartSuccess) {
            [_stateLock lock];
            _nodeStarted = YES;
            [_stateLock unlock];
            NSLog(@"[MultiplayerManager] [连接流程] ZeroTier 节点启动请求已提交，等待上线...");
        } else {
            NSLog(@"[MultiplayerManager] [连接流程] ZeroTier 节点启动失败：%@", startError.localizedDescription);
            if (completion) {
                completion(NO, startError ?: [NSError errorWithDomain:kMultiplayerErrorDomain
                                                                   code:MultiplayerErrorCodeNodeStartFailed
                                                               userInfo:@{NSLocalizedDescriptionKey: @"节点启动失败"}]);
            }
            return;
        }
    } else {
        NSLog(@"[MultiplayerManager] [连接流程] 步骤 1：节点已启动，跳过");
    }

    // 步骤 2：等待节点上线
    NSLog(@"[MultiplayerManager] [连接流程] 步骤 2：等待节点上线（超时 %.0fs）", kNodeOnlineTimeout);
    [self notifyConnectionProgress:@"步骤 2/6：正在等待节点上线..."];
    if (![[ZeroTierBridge sharedInstance] isNodeOnline]) {
        BOOL online = [[ZeroTierBridge sharedInstance] waitForNodeOnlineWithTimeout:kNodeOnlineTimeout];
        if (!online) {
            if (completion) {
                completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                    code:MultiplayerErrorCodeNodeOnlineTimeout
                                                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"等待 ZeroTier 节点上线超时（%.0fs）", kNodeOnlineTimeout]}]);
            }
            return;
        }
    }
    NSLog(@"[MultiplayerManager] [连接流程] 节点已上线");

    // 关键修复（M5）：在关键步骤前检查 self.currentRoom 是否仍是 room。
    // connectToRoomFlow 在后台线程执行 6 个步骤，全程使用 block 捕获的 room 参数，
    // 从不检查 self.currentRoom 是否已被并发调用 disconnectCurrentRoom 清空。
    // 若用户在连接中点击断开：
    //   1. disconnectCurrentRoom 停止 SOCKS5、清除环境变量、leaveNetwork、清空 currentRoom
    //   2. connectToRoomFlow 继续执行：重新 joinNetwork（刚被 leave）、重新 startWithPort
    //      SOCKS5（刚被 stop）、重新 setenv（刚被 unsetenv）
    //   3. 流程完成后：SOCKS5 代理在运行、环境变量已设置、网络已加入，但 currentRoom 为 nil
    //   4. 用户再次调用 disconnectCurrentRoom 时因 currentRoom == nil 直接返回，无法清理
    //      泄漏的代理和环境变量
    //
    // 修复方案：在加入网络前、启动 SOCKS5 前检查 currentRoom 是否仍是 room，
    // 如果不是则中止流程并清理已做的操作。
    [_stateLock lock];
    BOOL stillCurrent = (self.currentRoom != nil &&
                         [self.currentRoom.roomId isEqualToString:room.roomId]);
    [_stateLock unlock];
    if (!stillCurrent) {
        NSLog(@"[MultiplayerManager] [连接流程] 检测到 currentRoom 已变更（用户可能断开或切换了房间），中止连接流程");
        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeRoomNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"连接已取消"}]);
        }
        return;
    }

    // 步骤 3：加入网络
    NSLog(@"[MultiplayerManager] [连接流程] 步骤 3：加入 ZeroTier 网络 %@", room.networkId);
    [self notifyConnectionProgress:[NSString stringWithFormat:@"步骤 3/6：正在加入 ZeroTier 网络 %@...", room.networkId]];
    uint64_t netID = [ZeroTierBridge parseNetworkIDFromString:room.networkId];
    if (netID == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeInvalidNetworkId
                                            userInfo:@{NSLocalizedDescriptionKey: @"Network ID 解析失败"}]);
        }
        return;
    }

    NSError *joinError = nil;
    if (![[ZeroTierBridge sharedInstance] joinNetwork:netID error:&joinError]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeJoinNetworkFailed
                                            userInfo:@{NSLocalizedDescriptionKey: joinError.localizedDescription ?: @"加入网络失败"}]);
        }
        return;
    }

    // 步骤 4：等待网络就绪
    //
    // 关键修复（房客授权卡住问题）：
    // Private 网络中未授权的节点加入时，ZeroTier 控制器会忽略该节点（不分配 IP），
    // 但不发送 ACCESS_DENIED 事件。导致 waitForNetworkReady 中的 Denied 检查
    // 永远不触发，持续轮询 30 秒直到超时，用户看到"正在等待网络就绪"卡住。
    //
    // 修复方案：
    //   1. 启动一个 8 秒后的后台定时器，检查网络状态
    //   2. 如果已加入网络（Joined）但没有 IP，说明节点未授权
    //      → 发送"正在等待房主授权"的进度通知
    //   3. 超时后检查网络状态，给出更精确的错误信息
    NSLog(@"[MultiplayerManager] [连接流程] 步骤 4：等待网络就绪（超时 %.0fs）", kNetworkReadyTimeout);
    [self notifyConnectionProgress:@"步骤 4/6：正在等待网络就绪..."];

    // 8 秒后检查是否需要授权提示（Private 网络未授权的节点不会收到 ACCESS_DENIED 事件）
    __block BOOL step4Done = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (step4Done) return;
        ZeroTierNetworkStatus status = [[ZeroTierBridge sharedInstance] networkStatus:netID];
        NSString *ipv4 = [[ZeroTierBridge sharedInstance] ipv4AddressForNetwork:netID];
        NSString *ipv6 = [[ZeroTierBridge sharedInstance] ipv6AddressForNetwork:netID];
        NSLog(@"[MultiplayerManager] [连接流程] 8秒检查：status=%ld, ipv4=%@, ipv6=%@",
              (long)status, ipv4, ipv6);
        if (status == ZeroTierNetworkStatusJoined && !ipv4.length && !ipv6.length) {
            // 已加入网络但没有 IP = Private 网络未授权
            [weakSelf notifyConnectionProgress:@"仍在等待网络就绪...你的节点可能未被授权，请提醒房主在 central.zerotier.com 后台授权你的设备"];
        } else if (status == ZeroTierNetworkStatusNotJoined || status == ZeroTierNetworkStatusRequesting) {
            // 仍在请求加入网络
            [weakSelf notifyConnectionProgress:@"仍在请求加入网络，请稍候..."];
        }
    });

    BOOL ready = [[ZeroTierBridge sharedInstance] waitForNetworkReady:netID
                                                              timeout:kNetworkReadyTimeout];
    step4Done = YES;

    if (!ready) {
        // 关键修复（H4）：网络就绪等待失败时，必须离开已加入的网络，避免资源泄漏。
        NSLog(@"[MultiplayerManager] [连接流程] 网络就绪等待失败，清理已加入的网络 %@", room.networkId);
        [[ZeroTierBridge sharedInstance] leaveNetwork:netID];

        // 检查网络状态，给出更精确的错误信息
        ZeroTierNetworkStatus failStatus = [[ZeroTierBridge sharedInstance] networkStatus:netID];
        NSString *failDesc = nil;
        if (failStatus == ZeroTierNetworkStatusDenied) {
            failDesc = @"网络访问被拒绝。请联系房主在 central.zerotier.com 后台授权你的设备。";
        } else if (failStatus == ZeroTierNetworkStatusNotFound) {
            failDesc = @"网络不存在，请检查 Network ID 是否正确。";
        } else if (failStatus == ZeroTierNetworkStatusJoined) {
            failDesc = @"已加入网络但未分配到 IP 地址。你的节点可能未被授权，请提醒房主在 central.zerotier.com 后台的 Member Devices 中授权你的设备（勾选 Auth 复选框）。";
        } else {
            failDesc = [NSString stringWithFormat:@"等待 ZeroTier 网络就绪超时（%.0fs）。请确认网络 ID 正确且节点已在 central.zerotier.com 后台授权。", kNetworkReadyTimeout];
        }

        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeNetworkReadyTimeout
                                            userInfo:@{NSLocalizedDescriptionKey: failDesc}]);
        }
        return;
    }

    // 获取分配的 IP 地址
    // 标准模式：获取 IPv4 地址
    // Ad-hoc 模式（快速模式）：只有 IPv6 地址，需要特殊处理
    NSString *localIP = nil;
    BOOL isAdhoc = [self isAdhocNetworkId:room.networkId];
    if (isAdhoc) {
        // Ad-hoc 网络只有 IPv6 地址
        localIP = [[ZeroTierBridge sharedInstance] ipv6AddressForNetwork:netID];
        NSLog(@"[MultiplayerManager] [连接流程] Ad-hoc 模式，本机 ZeroTier IPv6：%@", localIP ?: @"（未分配）");
    } else {
        // 标准模式：获取 IPv4 地址
        localIP = [[ZeroTierBridge sharedInstance] ipv4AddressForNetwork:netID];
        NSLog(@"[MultiplayerManager] [连接流程] 标准模式，本机 ZeroTier IPv4：%@", localIP ?: @"（未分配）");
    }

    // 关键修复（H4）：如果获取不到本地 IP，说明网络虽就绪但 IP 分配异常，
    // 此时也应清理已加入的网络，避免后续重连时状态混乱。
    if (!localIP || localIP.length == 0) {
        NSLog(@"[MultiplayerManager] [连接流程] 无法获取本机 ZeroTier IP，清理已加入的网络 %@", room.networkId);
        [[ZeroTierBridge sharedInstance] leaveNetwork:netID];

        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeNetworkReadyTimeout
                                            userInfo:@{NSLocalizedDescriptionKey: @"已加入 ZeroTier 网络但未分配到本地 IP，可能是网络授权未通过或地址耗尽"}]);
        }
        return;
    }

    [_stateLock lock];
    self.currentLocalIP = localIP;
    // 关键修复（房客加入后无法连接服务器）：只有房主侧房间（isHostSide=YES）才将本机
    // ZeroTier IP 同步到 room.hostIP。
    //
    // 之前的 bug：connectToRoomFlow: 在获取到本机 ZeroTier IP 后无条件执行
    // `self.currentRoom.hostIP = localIP`。这对于房主是正确的（房主需要将自己的 IP
    // 同步到 room.hostIP 用于生成分享代码），但对于房客是致命错误：
    //   - 房客的 room.hostIP 来自分享代码（房主的 IP，如 10.147.17.1）
    //   - 房客连接后获取的 localIP 是房客自己的 ZeroTier IP（如 10.147.17.5）
    //   - 无条件覆盖后 room.hostIP 变成房客自己的 IP（10.147.17.5）
    //   - 步骤 6 中 PortForwarder 用错误的 room.hostIP 启动端口转发：
    //     127.0.0.1:25565 → 10.147.17.5:25565（房客自己的设备）
    //   - 房客在 MC 直接连接输入 127.0.0.1:25565，PortForwarder 转发到房客自己设备的 25565 端口
    //   - 房客自己设备上没有 MC 服务器，连接失败，显示"无法加入服务器"
    //
    // 修复方案：通过 room.isHostSide 区分房主/房客房间：
    //   - 房主房间（isHostSide=YES）：将本机 IP 同步到 room.hostIP，用于生成分享代码
    //   - 房客房间（isHostSide=NO）：保留分享代码中的房主 IP，确保 PortForwarder 正确转发
    if (localIP && localIP.length > 0 && self.currentRoom) {
        if (self.currentRoom.isHostSide) {
            // 房主模式：将本机 ZeroTier IP 同步到 room.hostIP，使 shareTextForRoom:
            // 能正确输出房主的服务器地址，分享代码中也包含正确的房主 IP。
            self.currentRoom.hostIP = localIP;
            NSLog(@"[MultiplayerManager] [连接流程] 房主模式，已同步本机 ZeroTier IP 到房间 %@：%@", self.currentRoom.name, localIP);
        } else {
            // 房客模式：保留分享代码中的房主 IP，不覆盖。
            // 房客的 localIP 仅用于 currentLocalIP（显示给用户参考），不写入 room.hostIP。
            NSLog(@"[MultiplayerManager] [连接流程] 房客模式，保留房主 IP（%@），本机 ZeroTier IP 为 %@（不覆盖 room.hostIP）",
                  self.currentRoom.hostIP, localIP);
        }
    }
    MultiplayerRoom *roomForIPUpdate = self.currentRoom;
    // 关键修复（房客加入后无法连接服务器）：房客模式下不需要将 room 写回房间列表，
    // 因为 hostIP 没有变化（仍为分享代码中的房主 IP），避免无意义的持久化操作。
    // 仅当 hostIP 实际发生变化（房主模式）时才需要写回。
    if (roomForIPUpdate && !roomForIPUpdate.isHostSide) {
        // 房客模式：room.hostIP 未被修改，跳过写回操作
        roomForIPUpdate = nil;
    }
    [_stateLock unlock];

    // 持久化房主 IP 到房间列表（后台异步写入，避免阻塞连接流程）
    if (roomForIPUpdate && localIP && localIP.length > 0) {
        [self updateRoom:roomForIPUpdate];
    }

    // 关键修复（M5）：在启动 SOCKS5 代理前再次检查 currentRoom 是否仍是 room。
    // 步骤 4（等待网络就绪）可能耗时最长 30 秒，期间用户可能点击断开。
    // 如果用户已断开，currentRoom 已被清空，此时不应继续启动 SOCKS5 代理。
    // 同时需要清理已加入的网络（leaveNetwork）。
    [_stateLock lock];
    BOOL stillCurrentBeforeProxy = (self.currentRoom != nil &&
                                    [self.currentRoom.roomId isEqualToString:room.roomId]);
    [_stateLock unlock];
    if (!stillCurrentBeforeProxy) {
        NSLog(@"[MultiplayerManager] [连接流程] 步骤 5 前检测到 currentRoom 已变更，中止流程并清理网络");
        [[ZeroTierBridge sharedInstance] leaveNetwork:netID];
        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeRoomNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"连接已取消"}]);
        }
        return;
    }

    // 步骤 5：启动 SOCKS5 代理
    NSLog(@"[MultiplayerManager] [连接流程] 步骤 5：启动 SOCKS5 代理");
    [self notifyConnectionProgress:@"步骤 5/6：正在启动 SOCKS5 代理..."];
    NSError *proxyError = nil;
    BOOL proxyStarted = [[SOCKS5Proxy sharedProxy] startWithPort:kMultiplayerDefaultSOCKS5Port
                                                            error:&proxyError];
    if (!proxyStarted) {
        NSLog(@"[MultiplayerManager] [连接流程] SOCKS5 代理启动失败：%@", proxyError.localizedDescription);
        // 关键修复（H4）：SOCKS5 代理启动失败时，同样需要离开已加入的网络，
        // 否则下一次连接尝试会因为节点已加入网络而出现状态不一致。
        NSLog(@"[MultiplayerManager] [连接流程] 清理已加入的网络 %@", room.networkId);
        [[ZeroTierBridge sharedInstance] leaveNetwork:netID];

        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeSOCKS5ProxyStartFailed
                                            userInfo:@{NSLocalizedDescriptionKey: proxyError.localizedDescription ?: @"SOCKS5 代理启动失败"}]);
        }
        return;
    }

    uint16_t actualPort = [[SOCKS5Proxy sharedProxy] listeningPort];

    // 关键修复（严重2）：SOCKS5 代理启动成功后，再次检查 currentRoom 是否仍是 room。
    // M5 修复只在 startWithPort 调用前检查，但检查通过后到 startWithPort 返回之间
    // 仍有时间窗口。如果用户在此期间点击断开：
    //   - disconnectCurrentRoom 会清空 currentRoom、清除环境变量、leaveNetwork
    //   - 但 connectToRoomFlow 继续执行，SOCKS5 代理已启动
    //   - 最终 SOCKS5 代理在运行、环境变量已设置，但 currentRoom == nil
    //   - 用户再次调用 disconnectCurrentRoom 因 currentRoom == nil 直接返回，无法清理
    //   - 导致 SOCKS5 代理和环境变量泄漏
    //
    // 修复方案：代理启动成功后再次检查，如果不是当前房间则立即停止代理并返回。
    [_stateLock lock];
    BOOL stillCurrentAfterProxy = (self.currentRoom != nil &&
                                   [self.currentRoom.roomId isEqualToString:room.roomId]);
    if (stillCurrentAfterProxy) {
        self.currentSOCKS5Port = actualPort;
    }
    [_stateLock unlock];

    if (!stillCurrentAfterProxy) {
        NSLog(@"[MultiplayerManager] [连接流程] SOCKS5 启动后检测到 currentRoom 已变更，立即停止代理并清理");
        [[SOCKS5Proxy sharedProxy] stop];
        unsetenv([kAMETHYSTSOCKS5ProxyEnvVar UTF8String]);
        [[ZeroTierBridge sharedInstance] leaveNetwork:netID];
        if (completion) {
            completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                code:MultiplayerErrorCodeRoomNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"连接已取消"}]);
        }
        return;
    }

    NSLog(@"[MultiplayerManager] [连接流程] SOCKS5 代理已启动，监听 127.0.0.1:%u", actualPort);

    // 步骤 6：设置环境变量 + 启动端口转发器
    //
    // 端口转发器说明：
    //   SOCKS5 代理只对 java.net.Socket 有效（登录认证等），但 MC 的多人游戏连接
    //   使用 Netty 的 NioSocketChannel（基于 java.nio.channels.SocketChannel），
    //   不走 Java 的 SOCKS5 代理。因此需要额外启动一个本地端口转发器：
    //     - 在 127.0.0.1:25565（或下一个可用端口）监听 TCP
    //     - 通过 libzt socket 转发到房主的 ZeroTier IP:MC LAN 端口
    //     - 房客在 MC 中输入 127.0.0.1:25565 即可连接
    //
    //   仅当房间有 hostIP 和 hostPort 时才启动（即房客连接到房主房间时）。
    //   房主不需要端口转发器（房主自己开 LAN，其他玩家通过 ZeroTier 连过来）。
    [self notifyConnectionProgress:@"步骤 6/6：正在设置代理和端口转发..."];
    NSString *proxyValue = [NSString stringWithFormat:@"127.0.0.1:%u", actualPort];
    setenv([kAMETHYSTSOCKS5ProxyEnvVar UTF8String], [proxyValue UTF8String], 1);
    NSLog(@"[MultiplayerManager] [连接流程] 已设置环境变量 %@=%@", kAMETHYSTSOCKS5ProxyEnvVar, proxyValue);

    // 如果房间有房主 IP 和端口（房客模式），启动端口转发器
    //
    // 关键修复（房客复制到 10. 开头地址而非 127.0.0.1）：
    // 之前的 bug：如果 PortForwarder 已在运行（例如上一次连接未完全清理就重连，
    // 或者 disconnectCurrentRoom 中 stop 是异步的还没执行完就重新连接），
    // startWithLocalPort: 会返回 PortForwarderErrorCodeAlreadyRunning（forwardPort=0），
    // 导致 currentForwardingPort 不被设置（保持 0）。
    // 随后 showGuestConnectedAlert 读到 currentForwardingPort == 0，
    // 走 else 回退分支，复制 hostIP:hostPort（10. 开头的房主 ZeroTier IP）而非
    // 127.0.0.1:forwardPort。房客在 MC 中输入 10.x.x.x:25565 时系统无法路由，
    // 显示"无法加入服务器"。
    //
    // 修复方案：启动前先检查 PortForwarder 是否已在运行，如果是则先 stop 再 start，
    // 确保能正确返回 forwardPort 并设置 currentForwardingPort。
    // 同时，房客模式下 PortForwarder 启动失败必须中断连接流程并报错，
    // 因为房客必须通过 PortForwarder 转发才能连接到房主（MC 的 Netty 不走 SOCKS5）。
    NSString *hostIP = room.hostIP;
    NSString *hostPortStr = room.hostPort;
    if (hostIP.length > 0 && hostPortStr.length > 0) {
        uint16_t hostPort = (uint16_t)[hostPortStr integerValue];
        if (hostPort > 0) {
            // 如果 PortForwarder 已在运行，先停止（可能是上一次连接残留）
            if ([[PortForwarder sharedForwarder] isRunning]) {
                NSLog(@"[MultiplayerManager] [连接流程] PortForwarder 已在运行（端口 %u），先停止再重新启动",
                      [[PortForwarder sharedForwarder] listeningPort]);
                [[PortForwarder sharedForwarder] stop];
            }

            NSLog(@"[MultiplayerManager] [连接流程] 启动端口转发器：127.0.0.1:%u → %@:%u",
                  PortForwarderDefaultLocalPort, hostIP, hostPort);

            NSError *forwardError = nil;
            uint16_t forwardPort = [[PortForwarder sharedForwarder] startWithLocalPort:PortForwarderDefaultLocalPort
                                                                            remoteHost:hostIP
                                                                            remotePort:hostPort
                                                                                 error:&forwardError];
            if (forwardPort > 0) {
                NSLog(@"[MultiplayerManager] [连接流程] 端口转发器已启动：127.0.0.1:%u → %@:%u",
                      forwardPort, hostIP, hostPort);

                [_stateLock lock];
                self.currentForwardingPort = forwardPort;
                [_stateLock unlock];
            } else {
                NSLog(@"[MultiplayerManager] [连接流程] 端口转发器启动失败：%@",
                      forwardError.localizedDescription);

                // 关键修复：房客模式下 PortForwarder 是必须的（MC 的 Netty 不走 SOCKS5）。
                // 如果启动失败，连接虽然"成功"（ZeroTier 网络已就绪），但房客无法在 MC 中
                // 连接到房主。此时必须中断流程并报错，避免 showGuestConnectedAlert
                // 回退到错误的 hostIP:hostPort（10. 开头，系统无法路由）。
                //
                // 清理已启动的 SOCKS5 代理和已加入的网络
                [[SOCKS5Proxy sharedProxy] stop];
                unsetenv([kAMETHYSTSOCKS5ProxyEnvVar UTF8String]);
                [[ZeroTierBridge sharedInstance] leaveNetwork:netID];

                [_stateLock lock];
                if (self.currentRoom && [self.currentRoom.roomId isEqualToString:room.roomId]) {
                    self.currentRoom = nil;
                    self.currentNetworkID = 0;
                    self.currentLocalIP = nil;
                    self.currentSOCKS5Port = 0;
                    self.currentForwardingPort = 0;
                }
                [_stateLock unlock];

                room.status = MultiplayerRoomStatusError;
                [self updateRoom:room];

                // 关键修复：修正编译错误。
                // 原代码 userInfo 字典末尾有多余的 ]，导致括号不匹配，
                // Clang 报错 "expected ')'" 和 "expected expression"。
                // 同时使用临时变量替代 ?:（GNU nil-coalescing）运算符，
                // 提高代码可读性。
                NSString *forwardErrorDesc = forwardError.localizedDescription;
                if (!forwardErrorDesc || forwardErrorDesc.length == 0) {
                    forwardErrorDesc = @"未知错误";
                }
                if (completion) {
                    completion(NO, [NSError errorWithDomain:kMultiplayerErrorDomain
                                                        code:MultiplayerErrorCodeSOCKS5ProxyStartFailed
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"端口转发器启动失败，无法连接到房主：%@", forwardErrorDesc]}]);
                }
                return;
            }
        } else {
            NSLog(@"[MultiplayerManager] [连接流程] 房主端口无效：%@，跳过端口转发", hostPortStr);
        }
    } else {
        NSLog(@"[MultiplayerManager] [连接流程] 房间无房主 IP/端口（可能是房主模式），跳过端口转发");
    }

    if (completion) {
        completion(YES, nil);
    }
}

- (void)disconnectCurrentRoom {
    [_stateLock lock];
    MultiplayerRoom *room = self.currentRoom;
    NSString *networkId = room.networkId;
    [_stateLock unlock];

    if (!room) {
        NSLog(@"[MultiplayerManager] disconnectCurrentRoom: 当前没有连接的房间");
        return;
    }

    NSLog(@"[MultiplayerManager] 断开房间连接：%@（Network ID: %@）", room.name, networkId);

    // 1. 停止 SOCKS5 代理
    if ([[SOCKS5Proxy sharedProxy] isRunning]) {
        NSLog(@"[MultiplayerManager] 停止 SOCKS5 代理");
        [[SOCKS5Proxy sharedProxy] stop];
    }

    // 1.5 停止端口转发器（房客模式）
    if ([[PortForwarder sharedForwarder] isRunning]) {
        NSLog(@"[MultiplayerManager] 停止端口转发器");
        [[PortForwarder sharedForwarder] stop];
    }

    [_stateLock lock];
    self.currentSOCKS5Port = 0;
    self.currentForwardingPort = 0;
    self.currentLocalIP = nil;
    [_stateLock unlock];

    // 2. 清除环境变量
    unsetenv([kAMETHYSTSOCKS5ProxyEnvVar UTF8String]);
    NSLog(@"[MultiplayerManager] 已清除环境变量 %@", kAMETHYSTSOCKS5ProxyEnvVar);

    // 3. 离开 ZeroTier 网络
    if (networkId && networkId.length > 0) {
        [self leaveNetwork:networkId];
    }

    // 4. 更新房间状态为已断开
    room.status = MultiplayerRoomStatusDisconnected;

    @synchronized(self) {
        for (MultiplayerRoom *existing in self.internalRooms) {
            if ([existing.roomId isEqualToString:room.roomId]) {
                existing.status = MultiplayerRoomStatusDisconnected;
                break;
            }
        }
    }

    // 5. 清空当前房间引用
    [_stateLock lock];
    self.currentRoom = nil;
    self.currentNetworkID = 0;
    [_stateLock unlock];

    // 6. 持久化
    [self saveRooms];

    NSLog(@"[MultiplayerManager] 已断开房间连接");
}

#pragma mark - ZeroTierBridgeDelegate

- (void)zeroTierNodeOnlineWithID:(uint64_t)nodeID {
    NSLog(@"[MultiplayerManager] ZeroTier 节点已上线，nodeID = %llu", nodeID);
    if ([self.delegate respondsToSelector:@selector(multiplayerNodeOnline)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate multiplayerNodeOnline];
        });
    }
}

- (void)zeroTierNodeOffline {
    NSLog(@"[MultiplayerManager] ZeroTier 节点已离线");

    // 关键稳定性优化：节点离线时，PortForwarder 和 SOCKS5Proxy 已无法转发数据，
    // 应该立即停止它们，避免房客在 MC 中看到"连接中"长时间卡住。
    // 不调用 disconnectCurrentRoom（会清空 currentRoom），仅停止代理和转发器。
    if ([[PortForwarder sharedForwarder] isRunning]) {
        NSLog(@"[MultiplayerManager] 节点离线，停止端口转发器");
        [[PortForwarder sharedForwarder] stop];
    }
    if ([[SOCKS5Proxy sharedProxy] isRunning]) {
        NSLog(@"[MultiplayerManager] 节点离线，停止 SOCKS5 代理");
        [[SOCKS5Proxy sharedProxy] stop];
    }

    [_stateLock lock];
    self.currentSOCKS5Port = 0;
    self.currentForwardingPort = 0;
    [_stateLock unlock];

    if ([self.delegate respondsToSelector:@selector(multiplayerNodeOffline)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate multiplayerNodeOffline];
        });
    }
}

- (void)zeroTierNetworkReady:(uint64_t)networkID
                        ipv4:(NSString *)ipv4
                        ipv6:(NSString *)ipv6 {
    NSLog(@"[MultiplayerManager] ZeroTier 网络就绪：networkID=%llu ipv4=%@ ipv6=%@",
          networkID, ipv4 ?: @"(nil)", ipv6 ?: @"(nil)");

    // 关键修复（N8）：将 currentRoom 读取、isAdhoc 判断、effectiveIP 计算全部移入 _stateLock 内。
    //
    // 问题：之前在锁外读取 self.currentRoom，然后计算 isAdhoc 和 effectiveIP，
    // 再进入锁内检查 _currentNetworkID。在锁外读取与锁内检查之间存在时间窗口，
    // 在此窗口内 disconnectCurrentRoom 可能清空 currentRoom 和 currentNetworkID。
    // 虽然实际影响有限（effectiveIP 已被计算但不会被写入，因为 _currentNetworkID 已被清空），
    // 但仍存在以下风险：
    //   - 在锁外读取的 currentRoom 在进入锁内时可能已被替换为另一个房间（切换房间场景）
    //   - 导致 effectiveIP 使用旧房间的 isAdhoc 判断写入到新房间的 currentLocalIP
    //
    // 修复方案：所有相关读取和判断都在 _stateLock 内完成，确保状态一致性。
    [_stateLock lock];

    // 判断当前网络是否为 Ad-hoc 网络
    // Ad-hoc 网络只有 IPv6 地址，需要使用 ipv6 而非 ipv4
    MultiplayerRoom *currentRoom = self.currentRoom;
    BOOL isAdhoc = currentRoom && [self isAdhocNetworkId:currentRoom.networkId];
    NSString *effectiveIP = isAdhoc ? ipv6 : ipv4;

    // 更新当前房间的本地 IP
    if (_currentNetworkID == networkID) {
        self.currentLocalIP = effectiveIP;
        // 关键修复（对标 FCL/HMCL）：ZeroTier 网络就绪回调可能晚于 connectToRoomFlow 完成，
        // 此处也需将 IP 同步到 room.hostIP，确保分享文本能输出正确的服务器地址。
        // Ad-hoc 模式下使用 IPv6，标准模式下使用 IPv4。
        //
        // 关键修复（房客加入后无法连接服务器）：只有房主侧房间（isHostSide=YES）才同步
        // room.hostIP 到本机 IP。房客侧房间（isHostSide=NO）必须保留分享代码中的房主 IP，
        // 否则 PortForwarder 会用错误的 hostIP 启动端口转发，导致房客在 MC 直接连接
        // 127.0.0.1:25565 时被转发到房客自己设备，连接失败显示"无法加入服务器"。
    }
    MultiplayerRoom *room = currentRoom;
    BOOL needsUpdate = NO;
    if (room && effectiveIP && effectiveIP.length > 0) {
        // 关键修复（房客加入后无法连接服务器）：通过 room.isHostSide 区分房主/房客房间
        if (room.isHostSide) {
            // 房主模式：仅当 IP 变化时才更新，避免重复写入
            if (![room.hostIP isEqualToString:effectiveIP]) {
                room.hostIP = effectiveIP;
                needsUpdate = YES;
            }
            NSLog(@"[MultiplayerManager] 房主模式，已更新房间 %@ 的本地 IP（%@）：%@",
                  room.name, isAdhoc ? @"IPv6" : @"IPv4", effectiveIP);
        } else {
            // 房客模式：保留房主 IP（来自分享代码），不覆盖 room.hostIP。
            // 房客的 effectiveIP 仅用于 currentLocalIP（显示给用户参考）。
            NSLog(@"[MultiplayerManager] 房客模式，保留房主 IP（%@），本机 ZeroTier IP 为 %@（不覆盖 room.hostIP）",
                  room.hostIP, effectiveIP);
        }
    }
    [_stateLock unlock];

    // 持久化到房间列表（后台异步写入）
    if (needsUpdate && room) {
        [self updateRoom:room];
    }

    // 通知 delegate 刷新 UI（IP 显示可能需要更新）
    //
    // 关键修复（H6）：dispatch_async 内必须再次检查 currentRoom 是否仍是同一个 room。
    // 之前直接捕获外部 room 变量在 dispatch_async 块内使用，存在以下风险：
    //   - 网络就绪事件可能在用户切换房间后才被投递到主线程
    //   - 此时 self.currentRoom 已经变成了另一个房间，但回调仍在通知旧的 room
    //   - 导致 UI 显示与新房间不一致的连接成功状态
    // 修复方案：在 dispatch_async 内重新读取 self.currentRoom，并与 room 比对，
    // 只有当 currentRoom 仍是 room 时才通知 delegate。
    if (room && [self.delegate respondsToSelector:@selector(multiplayerRoomConnected:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MultiplayerRoom *currentNow = self.currentRoom;
            if (currentNow && [currentNow.roomId isEqualToString:room.roomId]) {
                [self.delegate multiplayerRoomConnected:room];
            } else {
                NSLog(@"[MultiplayerManager] 网络就绪回调到达主线程时当前房间已变更，跳过通知（roomId=%@）",
                      room.roomId);
            }
        });
    }
}

- (void)zeroTierNetworkJoinFailed:(uint64_t)networkID
                            error:(NSString *)errorDescription {
    NSLog(@"[MultiplayerManager] ZeroTier 网络加入失败：networkID=%llu error=%@", networkID, errorDescription);

    [_stateLock lock];
    MultiplayerRoom *room = (_currentNetworkID == networkID) ? self.currentRoom : nil;
    [_stateLock unlock];

    if (room) {
        room.status = MultiplayerRoomStatusError;
        [self updateRoom:room];

        if ([self.delegate respondsToSelector:@selector(multiplayerRoom:didFailWithError:)]) {
            NSError *error = [NSError errorWithDomain:kMultiplayerErrorDomain
                                                  code:MultiplayerErrorCodeJoinNetworkFailed
                                              userInfo:@{NSLocalizedDescriptionKey: errorDescription}];
            // 关键修复（H6）：与 zeroTierNetworkReady 同样的修复——
            // dispatch_async 到主线程期间，用户可能切换了房间，需要再次校验
            // currentRoom 仍是同一个 room，避免向 delegate 通知过时的房间状态。
            dispatch_async(dispatch_get_main_queue(), ^{
                MultiplayerRoom *currentNow = self.currentRoom;
                if (currentNow && [currentNow.roomId isEqualToString:room.roomId]) {
                    [self.delegate multiplayerRoom:room didFailWithError:error];
                } else {
                    NSLog(@"[MultiplayerManager] 网络加入失败回调到达主线程时当前房间已变更，跳过通知（roomId=%@）",
                          room.roomId);
                }
            });
        }
    }
}

- (void)zeroTierAddressAssigned:(uint64_t)networkID
                         family:(int)family
                        address:(NSString *)address {
    NSLog(@"[MultiplayerManager] ZeroTier 地址分配：networkID=%llu family=%d address=%@",
          networkID, family, address);

    // 关键修复（M14）：处理 IPv6 地址分配事件。
    // 之前仅处理 IPv4（AF_INET == 2），完全忽略 IPv6（AF_INET6 == 10）。
    // Ad-hoc 网络只有 IPv6 地址，若 IPv6 地址后续发生变化（重新分配），
    // ADDR_ADDED_IP6 事件触发的 zeroTierAddressAssigned: 不会更新 currentLocalIP，
    // 导致显示的本地 IP 过时。
    //
    // 修复方案：
    //   - IPv4 地址：始终更新 currentLocalIP（标准模式）
    //   - IPv6 地址：仅当当前网络为 Ad-hoc 网络时更新（Ad-hoc 模式）
    //     标准网络的 IPv6 地址不更新 currentLocalIP，避免覆盖 IPv4 地址
    BOOL shouldUpdate = NO;
    if (family == 2 /* AF_INET */) {
        shouldUpdate = YES;
    } else if (family == 10 /* AF_INET6 */) {
        // IPv6 地址：仅当当前网络为 Ad-hoc 网络时更新
        [_stateLock lock];
        MultiplayerRoom *room = (_currentNetworkID == networkID) ? self.currentRoom : nil;
        [_stateLock unlock];
        if (room && [self isAdhocNetworkId:room.networkId]) {
            shouldUpdate = YES;
        }
    }

    if (shouldUpdate) {
        [_stateLock lock];
        if (_currentNetworkID == networkID) {
            self.currentLocalIP = address;
            NSLog(@"[MultiplayerManager] 已更新 currentLocalIP = %@（family=%d）", address, family);
        }
        [_stateLock unlock];
    }
}

#pragma mark - 分享功能

- (NSString *)shareTextForRoom:(MultiplayerRoom *)room {
    if (!room) {
        return @"";
    }

    NSString *name = room.name ?: @"未命名房间";
    NSString *networkId = room.networkId ?: @"";
    // hostIP 可能为空字符串（房主尚未连接房间时），此时显示提示
    NSString *hostIP = (room.hostIP && room.hostIP.length > 0) ? room.hostIP : @"（房主连接房间后自动显示）";
    NSString *hostPort = (room.hostPort && room.hostPort.length > 0) ? room.hostPort : kDefaultMCPort;

    // 关键修复（M7）：IPv6 地址在 host:port 格式中必须用方括号包裹。
    // 之前直接拼接为 host:port，对 IPv6 地址（如 2001:db8::1）会得到 2001:db8::1:25565，
    // 端口号与地址中的冒号无法区分，Minecraft 客户端无法正确解析。
    // RFC 3986 规定 IPv6 地址在 URI 中必须用 [和] 包裹，例如 [2001:db8::1]:25565。
    // 检测方法：如果 hostIP 包含冒号，则视为 IPv6 地址。
    NSString *serverAddress;
    BOOL isIPv6 = ([hostIP rangeOfString:@":"].location != NSNotFound);
    if (isIPv6) {
        serverAddress = [NSString stringWithFormat:@"[%@]:%@", hostIP, hostPort];
    } else {
        serverAddress = [NSString stringWithFormat:@"%@:%@", hostIP, hostPort];
    }

    NSMutableString *text = [NSMutableString string];

    [text appendString:kShareHeaderLine];
    [text appendString:@"\n"];

    [text appendString:kShareRoomNamePrefix];
    [text appendString:name];
    [text appendString:@"\n"];

    [text appendString:kShareNetworkIdPrefix];
    [text appendString:networkId];
    [text appendString:@"\n"];

    [text appendString:kShareServerAddressPrefix];
    [text appendString:serverAddress];
    [text appendString:@"\n"];

    [text appendString:@"\n"];
    [text appendString:@"加入步骤：\n"];
    [text appendString:@"1. 在启动器联机页面输入上方的 ZeroTier 网络 ID\n"];
    [text appendString:@"2. 点击「加入房间」，启动器会自动启动联机核心并连接\n"];
    [text appendFormat:@"3. 连接成功后启动游戏，在 MC 中添加服务器：%@", serverAddress];
    [text appendString:@"\n\n"];
    [text appendString:@"提示：房主需先在启动器内连接房间并启动游戏（或开放局域网），加入者才能连入。"];

    return [text copy];
}

- (nullable MultiplayerRoom *)parseRoomFromShareText:(NSString *)text {
    if (!text || text.length == 0) {
        return nil;
    }

    NSString *roomName = nil;
    NSString *networkId = nil;
    NSString *hostIP = nil;
    NSString *hostPort = nil;

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];

    // ========== 1. 逐行匹配带前缀的字段 ==========

    NSRegularExpression *nameRegex = [NSRegularExpression
        regularExpressionWithPattern:@"房间名称[：:]?\\s*(.+)"
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];

    NSRegularExpression *networkIdRegex = [NSRegularExpression
        regularExpressionWithPattern:@"(?:ZeroTier网络ID|网络ID|Network\\s*ID)[：:]?\\s*([0-9a-fA-F]{16})"
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];

    // 关键修复（M8）：addressRegex 同时匹配 IPv4 和 IPv6 地址。
    // 之前仅匹配 IPv4 格式（[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}），
    // 导致 Ad-hoc 模式下分享文本中的 IPv6 服务器地址（如 [2001:db8::1]:25565）
    // 完全无法被解析，从分享文本导入 Ad-hoc 房间时 hostIP 始终为空。
    //
    // 修复方案：正则中增加 IPv6 分支，匹配带方括号的 IPv6 地址（\[[0-9a-fA-F:]+\]）。
    // 注意：shareTextForRoom 总是以 [IPv6]:port 格式输出 IPv6 地址（M7 修复），
    // 所以解析时只需匹配带方括号的格式即可。
    // IPv6 地址中的方括号会保留在 hostIP 中，便于后续识别地址类型。
    NSRegularExpression *addressRegex = [NSRegularExpression
        regularExpressionWithPattern:@"服务器地址[：:]?\\s*((?:[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}|\\[[0-9a-fA-F:]+\\]))(?::([0-9]{1,5}))?"
                             options:0
                               error:nil];

    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedLine.length == 0) continue;

        if (!roomName) {
            NSTextCheckingResult *nameMatch = [nameRegex firstMatchInString:trimmedLine
                                                                   options:0
                                                                     range:NSMakeRange(0, trimmedLine.length)];
            if (nameMatch && nameMatch.numberOfRanges >= 2) {
                roomName = [trimmedLine substringWithRange:[nameMatch rangeAtIndex:1]];
                roomName = [roomName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }

        if (!networkId) {
            NSTextCheckingResult *networkMatch = [networkIdRegex firstMatchInString:trimmedLine
                                                                            options:0
                                                                              range:NSMakeRange(0, trimmedLine.length)];
            if (networkMatch && networkMatch.numberOfRanges >= 2) {
                networkId = [trimmedLine substringWithRange:[networkMatch rangeAtIndex:1]];
                networkId = [networkId lowercaseString];
            }
        }

        if (!hostIP) {
            NSTextCheckingResult *addressMatch = [addressRegex firstMatchInString:trimmedLine
                                                                          options:0
                                                                            range:NSMakeRange(0, trimmedLine.length)];
            if (addressMatch && addressMatch.numberOfRanges >= 2) {
                hostIP = [trimmedLine substringWithRange:[addressMatch rangeAtIndex:1]];
                if (addressMatch.numberOfRanges >= 3) {
                    NSRange portRange = [addressMatch rangeAtIndex:2];
                    if (portRange.location != NSNotFound && portRange.length > 0) {
                        hostPort = [trimmedLine substringWithRange:portRange];
                    }
                }
            }
        }
    }

    // ========== 2. 兜底：未匹配到 Network ID 时，在整个文本中搜索 ==========

    if (!networkId) {
        NSRegularExpression *rawHexRegex = [NSRegularExpression
            regularExpressionWithPattern:@"\\b([0-9a-fA-F]{16})\\b"
                                 options:0
                                   error:nil];
        NSTextCheckingResult *rawHexMatch = [rawHexRegex firstMatchInString:text
                                                                   options:0
                                                                     range:NSMakeRange(0, text.length)];
        if (rawHexMatch && rawHexMatch.numberOfRanges >= 2) {
            networkId = [[text substringWithRange:[rawHexMatch rangeAtIndex:1]] lowercaseString];
        }
    }

    // ========== 3. 兜底：未匹配到服务器地址时，在整个文本中搜索 ==========

    if (!hostIP) {
        // 关键修复（M8）：rawAddressRegex 同样支持 IPv6 地址（带方括号格式）。
        NSRegularExpression *rawAddressRegex = [NSRegularExpression
            regularExpressionWithPattern:@"((?:[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}|\\[[0-9a-fA-F:]+\\]))(?::([0-9]{1,5}))?"
                                 options:0
                                   error:nil];
        NSTextCheckingResult *rawAddressMatch = [rawAddressRegex firstMatchInString:text
                                                                           options:0
                                                                             range:NSMakeRange(0, text.length)];
        if (rawAddressMatch && rawAddressMatch.numberOfRanges >= 2) {
            hostIP = [text substringWithRange:[rawAddressMatch rangeAtIndex:1]];
            if (rawAddressMatch.numberOfRanges >= 3) {
                NSRange portRange = [rawAddressMatch rangeAtIndex:2];
                if (portRange.location != NSNotFound && portRange.length > 0) {
                    hostPort = [text substringWithRange:portRange];
                }
            }
        }
    }

    // ========== 4. 校验解析结果 ==========

    if (!networkId || networkId.length != 16) {
        NSLog(@"[MultiplayerManager] 解析分享文本失败：Network ID 无效或缺失");
        return nil;
    }

    if (![self isValidNetworkId:networkId]) {
        NSLog(@"[MultiplayerManager] 解析分享文本失败：Network ID 格式校验未通过：%@", networkId);
        return nil;
    }

    if (!roomName || roomName.length == 0) {
        roomName = @"导入的房间";
    }

    if (!hostPort || hostPort.length == 0) {
        hostPort = kDefaultMCPort;
    }

    if (!hostIP) {
        hostIP = @"";
        NSLog(@"[MultiplayerManager] 解析分享文本：未找到服务器 IP，用户需后续手动补充");
    }

    // ========== 5. 构造房间对象 ==========

    MultiplayerRoom *room = [[MultiplayerRoom alloc] initWithId:nil
                                                            name:roomName
                                                       networkId:networkId
                                                          hostIP:hostIP
                                                        hostPort:hostPort];
    room.roomDescription = @"从分享文本导入";
    room.status = MultiplayerRoomStatusDisconnected;

    NSLog(@"[MultiplayerManager] 成功解析分享文本：name=%@, networkId=%@, host=%@:%@",
          roomName, networkId, hostIP, hostPort);

    return room;
}

#pragma mark - 辅助方法

- (NSString *)generateRoomId {
    return [[NSUUID UUID] UUIDString];
}

- (BOOL)isValidNetworkId:(NSString *)networkId {
    if (!networkId || networkId.length != 16) {
        return NO;
    }

    NSCharacterSet *hexCharset = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < networkId.length; i++) {
        unichar ch = [networkId characterAtIndex:i];
        if (![hexCharset characterIsMember:ch]) {
            return NO;
        }
    }

    NSString *lowercase = [networkId lowercaseString];
    if ([lowercase isEqualToString:@"0000000000000000"]) {
        return NO;
    }

    return YES;
}

- (BOOL)isValidIPAddress:(NSString *)ipAddress {
    if (!ipAddress || ipAddress.length == 0) {
        return NO;
    }

    NSArray *components = [ipAddress componentsSeparatedByString:@"."];
    if (components.count != 4) {
        return NO;
    }

    for (NSString *component in components) {
        if (component.length == 0 || component.length > 3) {
            return NO;
        }

        NSCharacterSet *digitCharset = [NSCharacterSet decimalDigitCharacterSet];
        for (NSUInteger i = 0; i < component.length; i++) {
            unichar ch = [component characterAtIndex:i];
            if (![digitCharset characterIsMember:ch]) {
                return NO;
            }
        }

        NSInteger value = [component integerValue];
        if (value < 0 || value > 255) {
            return NO;
        }

        if (component.length > 1 && [component hasPrefix:@"0"]) {
            return NO;
        }
    }

    return YES;
}

#pragma mark - 分享代码（FCL 风格 Base64 编码）

/// 分享代码的 JSON key 常量
static NSString * const kShareCodeKeyNetworkId = @"n";
static NSString * const kShareCodeKeyHostIP = @"h";
static NSString * const kShareCodeKeyHostPort = @"p";
static NSString * const kShareCodeKeyRoomName = @"r";

/// 预设 Network ID 的偏好键
static NSString * const kPresetNetworkIdPrefKey = @"multiplayer.preset_network_id";

- (NSString *)generateShareCodeForRoom:(MultiplayerRoom *)room {
    if (!room || !room.networkId) {
        return @"";
    }

    // 构建 JSON 字典
    NSMutableDictionary *jsonDict = [NSMutableDictionary dictionary];
    jsonDict[kShareCodeKeyNetworkId] = room.networkId;
    if (room.hostIP && room.hostIP.length > 0) {
        jsonDict[kShareCodeKeyHostIP] = room.hostIP;
    }
    if (room.hostPort && room.hostPort.length > 0) {
        jsonDict[kShareCodeKeyHostPort] = room.hostPort;
    } else {
        jsonDict[kShareCodeKeyHostPort] = kDefaultMCPort;
    }
    if (room.name && room.name.length > 0) {
        jsonDict[kShareCodeKeyRoomName] = room.name;
    }

    // 序列化为 JSON Data
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict
                                                       options:NSJSONWritingSortedKeys
                                                         error:&jsonError];
    if (jsonError || !jsonData) {
        NSLog(@"[MultiplayerManager] 生成分享代码失败：JSON 序列化失败 - %@", jsonError);
        return @"";
    }

    // Base64 编码（URL 安全：去掉换行符）
    NSString *base64String = [jsonData base64EncodedStringWithOptions:0];
    // 去除可能的换行符和空格
    base64String = [base64String stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    base64String = [base64String stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    base64String = [base64String stringByReplacingOccurrencesOfString:@" " withString:@""];

    NSLog(@"[MultiplayerManager] 已生成分享代码（长度=%lu）：%@...",
          (unsigned long)base64String.length,
          base64String.length > 20 ? [base64String substringToIndex:20] : base64String);

    return base64String;
}

- (nullable MultiplayerRoom *)parseShareCode:(NSString *)code {
    if (!code || code.length == 0) {
        return nil;
    }

    // 清理输入：去除首尾空白和换行符
    NSString *cleanCode = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanCode.length == 0) {
        return nil;
    }

    // Base64 解码
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:cleanCode
                                                            options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!jsonData || jsonData.length == 0) {
        NSLog(@"[MultiplayerManager] 解析分享代码失败：Base64 解码失败");
        return nil;
    }

    // JSON 反序列化
    NSError *jsonError = nil;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                            options:0
                                                              error:&jsonError];
    if (jsonError || !jsonDict || ![jsonDict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[MultiplayerManager] 解析分享代码失败：JSON 反序列化失败 - %@", jsonError);
        return nil;
    }

    // 提取字段
    NSString *networkId = jsonDict[kShareCodeKeyNetworkId];
    NSString *hostIP = jsonDict[kShareCodeKeyHostIP];
    NSString *hostPort = jsonDict[kShareCodeKeyHostPort];
    NSString *roomName = jsonDict[kShareCodeKeyRoomName];

    // 校验 Network ID
    if (!networkId || ![self isValidNetworkId:networkId]) {
        NSLog(@"[MultiplayerManager] 解析分享代码失败：Network ID 无效 - %@", networkId);
        return nil;
    }

    // 构建房间对象
    MultiplayerRoom *room = [[MultiplayerRoom alloc] init];
    room.roomId = [self generateRoomId];
    room.networkId = networkId;
    room.hostIP = hostIP ?: @"";
    room.hostPort = hostPort ?: kDefaultMCPort;
    room.name = roomName ?: [NSString stringWithFormat:@"%@...", [networkId substringToIndex:8]];
    room.roomDescription = @"";
    room.ownerName = @"";
    room.status = MultiplayerRoomStatusDisconnected;
    room.createdAt = [NSDate date];

    NSLog(@"[MultiplayerManager] 已解析分享代码：roomName=%@ networkId=%@ hostIP=%@ hostPort=%@",
          room.name, room.networkId, room.hostIP, room.hostPort);

    return room;
}

#pragma mark - 预设 Network ID 管理（FCL 风格）

- (nullable NSString *)presetNetworkId {
    NSString *networkId = [[NSUserDefaults standardUserDefaults] stringForKey:kPresetNetworkIdPrefKey];
    if (networkId && networkId.length > 0 && [self isValidNetworkId:networkId]) {
        return networkId;
    }
    return nil;
}

- (void)setPresetNetworkId:(nullable NSString *)networkId {
    if (!networkId || networkId.length == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPresetNetworkIdPrefKey];
        NSLog(@"[MultiplayerManager] 已清除预设 Network ID");
        return;
    }

    // 校验格式
    if (![self isValidNetworkId:networkId]) {
        NSLog(@"[MultiplayerManager] 预设 Network ID 格式无效，未保存：%@", networkId);
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:networkId forKey:kPresetNetworkIdPrefKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[MultiplayerManager] 已保存预设 Network ID：%@", networkId);
}

#pragma mark - Ad-hoc 网络（快速模式，无需注册账号）

- (NSString *)generateAdhocNetworkId {
    // 使用 zts_net_compute_adhoc_id 生成 Ad-hoc 网络 ID
    // 参数：端口范围 0-65535（兼容 MC 所有端口，包括 25565 和 LAN 随机端口）
    // 返回值：uint64_t 类型的网络 ID，需要转换为 16 位十六进制字符串
    uint64_t adhocNetId = zts_net_compute_adhoc_id(0, 65535);

    // 关键修复（H11）：检查 zts_net_compute_adhoc_id 返回值的有效性。
    // 之前不检查返回值，直接格式化为字符串，导致：
    //   - 在 stub 模式（zt.framework 不可用）下，zts_net_compute_adhoc_id 返回 0，
    //     格式化后变成 "0000000000000000"，调用方拿到这个 ID 后会尝试加入一个
    //     不存在的网络，引发各种不可预知的错误。
    //   - 即使 framework 可用，如果端口范围参数非法或 libzt 内部异常，
    //     也可能返回 0 或无效值，同样会导致后续加入网络失败。
    //
    // 修复方案：
    //   1. 检查 adhocNetId 是否为 0（最明显的失败标志）
    //   2. 检查 adhocNetId 的高字节是否为 0xff（Ad-hoc 网络 ID 的规范要求
    //      高字节必须是 0xff，参见 ZeroTierSockets.h 中 zts_net_compute_adhoc_id
    //      的文档说明，例如 ff0000ffff000000）
    //   3. 如果检查失败，返回 nil，由调用方处理（UI 层已检查 nil/空字符串）
    if (adhocNetId == 0) {
        NSLog(@"[MultiplayerManager] generateAdhocNetworkId 失败：zts_net_compute_adhoc_id 返回 0（可能是 stub 模式或 libzt 异常）");
        return nil;
    }

    // Ad-hoc 网络 ID 高字节必须是 0xff（参见 ZeroTierSockets.h 第 1559-1560 行的示例：
    // ff00160016000000、ff0000ffff000000）
    uint8_t highByte = (uint8_t)((adhocNetId >> 56) & 0xFF);
    if (highByte != 0xFF) {
        NSLog(@"[MultiplayerManager] generateAdhocNetworkId 失败：返回值 0x%016llx 的高字节不是 0xff（不符合 Ad-hoc 网络 ID 规范）",
              adhocNetId);
        return nil;
    }

    // 转换为 16 位十六进制字符串（与标准 Network ID 格式一致）
    NSString *adhocNetIdStr = [NSString stringWithFormat:@"%016llx", adhocNetId];

    NSLog(@"[MultiplayerManager] 已生成 Ad-hoc 网络 ID：%@ (raw=%llu)", adhocNetIdStr, adhocNetId);
    return adhocNetIdStr;
}

- (BOOL)isAdhocNetworkId:(NSString *)networkId {
    // Ad-hoc 网络 ID 以 "ff" 开头（如 ff0000ffff000000）
    // 标准网络 ID 以其他字符开头（如 1a2b3c4d5e6f7g8h）
    if (!networkId || networkId.length < 2) {
        return NO;
    }
    NSString *prefix = [[networkId substringToIndex:2] lowercaseString];
    return [prefix isEqualToString:@"ff"];
}

@end
