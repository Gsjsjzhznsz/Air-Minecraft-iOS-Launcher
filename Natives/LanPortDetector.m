//
//  LanPortDetector.m
//  Amethyst
//
//  Minecraft "对局域网开放"端口检测器实现
//
//  ============================================================================
//  实现原理
//  ============================================================================
//
//  1. 日志拦截：
//     PLLogOutputView.appendToLog: 是所有 MC 日志的入口点。本检测器通过
//     Method Swizzle 交换 appendToLog: 的实现，在日志写入 UI 的同时
//     传递给 LanPortDetector 进行正则匹配。
//
//     但为了不侵入 PLLogOutputView 的实现，改用更轻量的方案：
//     直接在 PLLogOutputView._appendToLog: 中调用 LanPortDetector
//     的 parsePortFromLogLine: 方法（需在 PLLogOutputView.m 中添加一行调用）。
//
//     最终权衡：采用通知机制。LanPortDetector 监听一个自定义通知
//     "PLLogOutputLineNotification"，PLLogOutputView 在 _appendToLog: 中
//     发送此通知。这样 LanPortDetector 无需 swizzle，也不依赖
//     PLLogOutputView 的私有实现。
//
//  2. 正则匹配：
//     MC "对局域网开放"日志格式多样，需要覆盖以下模式：
//     - "Local game hosted on port 54321"
//     - "Local game hosted on 0.0.0.0:54321"
//     - "Started serving on 54321"
//     - "Integrated server started on port 54321"
//     - "Starting integrated minecraft server on port 54321"
//
//  3. 通知机制：
//     检测到端口后发送 LanPortDetectorDidDetectPortNotification，
//     userInfo 包含 port 和 source 字段。
//
//  4. 日志文件回退：
//     如果实时检测失败（如用户在检测器启动前就开了 LAN），
//     detectFromLogFile 方法从 latestlog.txt 重新搜索端口。
//
//

#import "LanPortDetector.h"

/// 通知名：PLLogOutputView 输出一行日志时发送
/// PLLogOutputView._appendToLog: 中会发送此通知
/// userInfo: @{@"line": @"日志内容"}
NSString *const PLLogOutputLineNotification = @"PLLogOutputLineNotification";

/// LAN 端口检测通知名
NSString *const LanPortDetectorDidDetectPortNotification = @"LanPortDetectorDidDetectPort";

/// 日志文件路径（POJAV_HOME/latestlog.txt）
static NSString *const kLatestLogPath = @"%s/latestlog.txt";

@interface LanPortDetector ()
{
    id _logObserver;
}

@property (nonatomic, copy, readwrite, nullable) NSString *detectedPort;
@property (nonatomic, assign, readwrite) LanPortSource source;
@property (nonatomic, strong, readwrite, nullable) NSDate *detectedAt;
@property (nonatomic, assign, readwrite, getter=isDetecting) BOOL detecting;

@end

/// 检查一行日志是否来自启动器自身（而非 MC）
///
/// 启动器各组件通过 NSLog 输出的日志会被 PLLogOutputView 捕获并重新发送给
/// LanPortDetector。如果不过滤，genericPortRegex 的 "lan\s*(?:port|server)"
/// 模式会匹配 "[LanPortDetector]" 中的 "LanPort" 字样，导致递归循环。
/// 此函数在 processLogLine: 和 detectFromLogFile 中都被调用。
static BOOL LanPortDetectorIsLauncherLogLine(NSString *line) {
    static NSArray<NSString *> *markers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        markers = @[
            @"[LanPortDetector]",
            @"[PortForwarder]",
            @"[MultiplayerManager]",
            @"[MultiplayerVC]",
            @"[SOCKS5Proxy]",
            @"[ZeroTierBridge]",
            @"[SurfaceVC]",
            @"[SurfaceViewController]",
            @"[JavaLauncher]",
            @"[TouchController]",
            @"[Pre-init]",
            @"[Pre-Init]",
            @"[Debugging]",
            @"[MCDL]",
            @"[MDCL]",
            @"[DyldLVBypass]",
            @"[Init]",
            @"[egl_bridge]",
            @"[gl_bridge]",
            @"[input_bridge]",
            @"[MobileGlues]",
            @"[EGLBridge]",
        ];
    });
    for (NSString *marker in markers) {
        if ([line rangeOfString:marker].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

@implementation LanPortDetector

#pragma mark - 单例

+ (instancetype)sharedDetector {
    static LanPortDetector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static LanPortDetector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [super allocWithZone:zone];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _detectedPort = nil;
        _source = LanPortSourceUnknown;
        _detectedAt = nil;
        _detecting = NO;
    }
    return self;
}

#pragma mark - 检测控制

/// 开始检测
/// 注册 PLLogOutputLineNotification 通知监听
- (void)startDetecting {
    if (self.detecting) {
        NSLog(@"[LanPortDetector] 已在检测中，跳过重复启动");
        return;
    }

    self.detecting = YES;
    NSLog(@"[LanPortDetector] 开始检测 LAN 端口");

    // 先从日志文件尝试检测一次（覆盖检测器启动前就开 LAN 的情况）
    NSString *existingPort = [self detectFromLogFile];
    if (existingPort) {
        NSLog(@"[LanPortDetector] 从日志文件检测到已有 LAN 端口：%@", existingPort);
        [self setPort:existingPort source:LanPortSourceAuto];
    }

    // 注册日志行通知
    __weak typeof(self) weakSelf = self;
    _logObserver = [[NSNotificationCenter defaultCenter] addObserverForName:PLLogOutputLineNotification
                                                                     object:nil
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *notification) {
        NSString *line = notification.userInfo[@"line"];
        if (line) {
            [weakSelf processLogLine:line];
        }
    }];
}

/// 停止检测
- (void)stopDetecting {
    if (!self.detecting) return;

    NSLog(@"[LanPortDetector] 停止检测 LAN 端口");
    self.detecting = NO;

    if (_logObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_logObserver];
        _logObserver = nil;
    }
}

#pragma mark - 日志处理

/// 处理一行日志，检测是否包含 LAN 端口信息
- (void)processLogLine:(NSString *)line {
    if (!line || line.length == 0) return;

    // 关键修复（递归循环 bug 导致端口检测错误）：
    //
    // 根因：启动器各组件（PortForwarder / MultiplayerManager / LanPortDetector
    // 等）通过 NSLog 输出的日志会被 PLLogOutputView 捕获并重新发送给
    // LanPortDetector 处理。其中 genericPortRegex 的模式 "lan\s*(?:port|server)"
    // （大小写不敏感）会匹配到 "[LanPortDetector]" 中的 "LanPort" 字样，
    // 导致把启动器自己的端口号（如 25565）误识别为 MC LAN 端口。
    //
    // 随后 LanPortDetector 打印检测日志 "[LanPortDetector] 从日志检测到 LAN 端口..."
    // 该日志又被 PLLogOutputView 捕获，触发新一轮匹配，形成无限递归。
    // 递归过程中日志行不断嵌套变长（引号层层嵌套），最终正则匹配到被
    // 截断的 "2556"（4位数字），导致分享代码中的端口变成 2556 而非正确的
    // MC LAN 端口（如 50798）。
    //
    // 修复：识别并跳过所有启动器组件的日志行，只处理真正的 MC 日志。
    if (LanPortDetectorIsLauncherLogLine(line)) {
        return;
    }

    NSString *port = [self parsePortFromLogLine:line];
    if (port) {
        NSLog(@"[LanPortDetector] 从日志检测到 LAN 端口：%@（来源：行 '%@'）", port, line);
        [self setPort:port source:LanPortSourceAuto];
    } else {
        // 调试日志：识别疑似 LAN 相关但未匹配的行，帮助诊断新 MC 版本的日志格式
        // 只记录长度 > 5 的行，避免空行噪声
        // 注意：使用 [MultiplayerVC] 标记前缀让 LanPortDetectorIsLauncherLogLine 过滤此日志
        // 防止与 LanPortDetector 自身的日志混在一起触发递归
        static NSUInteger skippedCount = 0;
        NSString *lowerLine = line.lowercaseString;
        if (line.length > 5 && ([lowerLine containsString:@"local game"]
                                 || [lowerLine containsString:@"open to lan"]
                                 || [lowerLine containsString:@"open.*lan"]
                                 || [lowerLine containsString:@"对局域网开放"])) {
            skippedCount++;
            // 只打印前 5 条疑似日志，避免日志爆炸
            if (skippedCount <= 5) {
                NSLog(@"[MultiplayerVC] 疑似 LAN 端口日志未匹配任何正则（行：'%@'），可能需要扩展 LanPortDetector 正则", line);
            }
        }
    }
}

/// 从日志行解析 LAN 端口
///
/// 支持的 MC 日志格式（覆盖 MC 1.8 ~ 1.21+ 所有主流版本）：
/// 1. "[CHAT] Local game hosted on port 54321"（MC 1.8+ 通用聊天消息日志）
/// 2. "Local game hosted on 0.0.0.0:54321"（部分版本）
/// 3. "Local game hosted on *:54321"（部分版本）
/// 4. "Started serving on 54321"（极旧版本）
/// 5. "Started on 54321"（MC 1.8 Client thread 日志）
/// 6. "Integrated server started on port 54321"（部分 Forge 版本）
/// 7. "Starting integrated minecraft server on port 54321"
/// 8. "ThreadedAnvilChunkSystem: Integrated server started on *:54321"
///
/// @param logLine 日志行
/// @return 端口号字符串，nil 表示不包含
- (NSString *)parsePortFromLogLine:(NSString *)logLine {
    if (!logLine || logLine.length == 0) return nil;

    // 预编译正则表达式（性能优化：静态变量只编译一次）
    static NSRegularExpression *hostedOnPortRegex = nil;
    static NSRegularExpression *hostedOnAddrPortRegex = nil;
    static NSRegularExpression *startedServingRegex = nil;
    static NSRegularExpression *startedOnRegex = nil;
    static NSRegularExpression *integratedStartedRegex = nil;
    static NSRegularExpression *genericPortRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 模式 1："Local game hosted on port 54321" 或 "[CHAT] Local game hosted on port 54321"
        // 或 "[System] [CHAT] Local game hosted on port [54321]"（部分 Mod/版本端口号被方括号包围）
        // 这是 MC 1.7+ 所有版本通用的聊天消息日志，是最可靠的检测依据
        // 关键兼容性修复：\[?...\]? 支持端口号被方括号包围的变体格式
        hostedOnPortRegex = [NSRegularExpression regularExpressionWithPattern:
            @"hosted on port \\[?(\\d{1,5})\\]?"
            options:NSRegularExpressionCaseInsensitive error:nil];
        // 模式 2："Local game hosted on 0.0.0.0:54321" 或 "hosted on *:54321"
        hostedOnAddrPortRegex = [NSRegularExpression regularExpressionWithPattern:
            @"hosted on (?:[0-9.*]+):(\\d{1,5})"
            options:NSRegularExpressionCaseInsensitive error:nil];
        // 模式 3："Started serving on 54321" 或 "Started serving on [54321]"（极旧版本/Mod 变体）
        startedServingRegex = [NSRegularExpression regularExpressionWithPattern:
            @"started serving on \\[?(\\d{1,5})\\]?"
            options:NSRegularExpressionCaseInsensitive error:nil];
        // 模式 4："Started on 54321"（MC 1.8 Client thread 日志）
        // 注意：要求 4-5 位数字以减少误匹配（LAN 端口范围 1024-65535）
        startedOnRegex = [NSRegularExpression regularExpressionWithPattern:
            @"started on \\[?(\\d{4,5})\\]?"
            options:NSRegularExpressionCaseInsensitive error:nil];
        // 模式 5："Integrated server started on port 54321" 或 "on *:54321"
        integratedStartedRegex = [NSRegularExpression regularExpressionWithPattern:
            @"integrated server.*?(?:port|on [\\*0-9.]*:?)\\s*\\[?(\\d{4,5})\\]?"
            options:NSRegularExpressionCaseInsensitive error:nil];
        // 模式 6：通用兜底模式
        // 匹配包含 "serving"、"hosted"、"lan port"、"lan server" 等关键词
        // 且后面跟着端口号的日志行（支持端口号被方括号包围的变体）
        genericPortRegex = [NSRegularExpression regularExpressionWithPattern:
            @"(?:serving|hosted|lan\\s*(?:port|server)|open.*?lan).*(?::|\\s)+\\[?(\\d{4,5})\\]?"
            options:NSRegularExpressionCaseInsensitive error:nil];
    });

    // 逐个模式匹配（按可靠性从高到低排序）
    NSArray<NSRegularExpression *> *regexes = @[
        hostedOnPortRegex,       // 最可靠：MC 1.8+ 通用聊天消息
        hostedOnAddrPortRegex,   // 次可靠：带 IP/通配符的 hosted on
        startedServingRegex,     // 旧版本：started serving on
        startedOnRegex,          // MC 1.8：started on
        integratedStartedRegex,  // Forge：integrated server
        genericPortRegex,        // 兜底：通用模式
    ];

    for (NSRegularExpression *regex in regexes) {
        if (!regex) continue;
        NSTextCheckingResult *match = [regex firstMatchInString:logLine
                                                        options:0
                                                          range:NSMakeRange(0, logLine.length)];
        if (match && match.numberOfRanges >= 2) {
            NSString *portStr = [logLine substringWithRange:[match rangeAtIndex:1]];
            // 验证端口号范围（1024-65535，LAN 端口通常在这个范围）
            NSInteger portNum = [portStr integerValue];
            if (portNum >= 1024 && portNum <= 65535) {
                return portStr;
            }
        }
    }

    return nil;
}

#pragma mark - 日志文件检测

/// 从 latestlog.txt 检测端口
///
/// 当实时检测失败时（如检测器启动前就开了 LAN），
/// 从日志文件中从后往前搜索最近的端口匹配。
- (NSString *)detectFromLogFile {
    NSString *logPath = [NSString stringWithFormat:kLatestLogPath, getenv("POJAV_HOME")];
    if (!logPath) return nil;

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:logPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content || content.length == 0) {
        NSLog(@"[LanPortDetector] 读取日志文件失败：%@（路径：%@）", error.localizedDescription, logPath);
        return nil;
    }

    NSLog(@"[LanPortDetector] 日志文件读取成功（%lu 字节），开始搜索 LAN 端口...", (unsigned long)content.length);

    // 按行分割，从后往前搜索（最近的端口匹配）
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:
        [NSCharacterSet newlineCharacterSet]];

    NSLog(@"[LanPortDetector] 日志共 %lu 行", (unsigned long)lines.count);

    for (NSInteger i = lines.count - 1; i >= 0; i--) {
        NSString *line = lines[i];
        // 跳过启动器自身的日志行，避免误匹配（同 processLogLine: 中的过滤）
        if (LanPortDetectorIsLauncherLogLine(line)) {
            continue;
        }
        NSString *port = [self parsePortFromLogLine:line];
        if (port) {
            NSLog(@"[LanPortDetector] 从日志文件第 %ld 行检测到端口：%@（行内容：%@）", (long)i, port, line);
            return port;
        }
    }

    // 未找到端口：打印最后 10 行日志帮助诊断
    NSLog(@"[LanPortDetector] 日志文件中未找到 LAN 端口，最后 10 行日志：");
    NSInteger startIdx = MAX(0, (NSInteger)lines.count - 10);
    for (NSInteger i = startIdx; i < (NSInteger)lines.count; i++) {
        NSLog(@"[LanPortDetector]   行 %ld: %@", (long)i, lines[i]);
    }

    return nil;
}

#pragma mark - 端口设置

/// 手动设置端口
- (void)setManualPort:(NSString *)port {
    if (!port || port.length == 0) {
        NSLog(@"[LanPortDetector] setManualPort: 端口为空");
        return;
    }

    // 验证端口号
    NSInteger portNum = [port integerValue];
    if (portNum < 1 || portNum > 65535) {
        NSLog(@"[LanPortDetector] setManualPort: 端口号无效：%@", port);
        return;
    }

    [self setPort:port source:LanPortSourceManual];
}

/// 清除当前端口
- (void)clearPort {
    NSLog(@"[LanPortDetector] 清除端口（之前：%@）", self.detectedPort);
    self.detectedPort = nil;
    self.source = LanPortSourceUnknown;
    self.detectedAt = nil;
}

/// 内部设置端口方法
- (void)setPort:(NSString *)port source:(LanPortSource)source {
    if (!port || port.length == 0) return;

    // 如果端口相同且来源相同，不重复通知
    if ([port isEqualToString:self.detectedPort] && source == self.source) {
        return;
    }

    self.detectedPort = [port copy];
    self.source = source;
    self.detectedAt = [NSDate date];

    NSLog(@"[LanPortDetector] 端口已设置：%@（来源：%@）", port,
          source == LanPortSourceAuto ? @"自动检测" :
          source == LanPortSourceManual ? @"手动输入" : @"未知");

    // 发送通知
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LanPortDetectorDidDetectPortNotification
                                                            object:self
                                                          userInfo:@{
        @"port": port,
        @"source": @(source),
    }];
    });
}

@end
