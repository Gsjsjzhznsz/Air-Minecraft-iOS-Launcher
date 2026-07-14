//
//  MultiplayerViewController.m
//  Amethyst
//
//  MC 联机界面实现（FCL 风格重制版）
//
//  本文件参照 FCL (FoldCraftLauncher) 的联机流程重新设计：
//
//  模式 1：启动器模式（MultiplayerVCModeLauncher）
//    用户在启动游戏前在此界面启用联机、设置预设 Network ID、管理房间、配置直连。
//    Section 0「联机设置」：UISwitch 启用联机开关 + 预设 Network ID 显示/编辑
//    Section 1「我的房间」：保存的房间列表（每行显示 房间名 + Network ID + 状态 + 连接/断开按钮）
//    Section 2「直连」：IP+端口输入 + 加入游戏按钮（写入 PLProfiles）
//
//  模式 2：游戏内模式（MultiplayerVCModeInGame）
//    用户启动游戏后通过悬浮球菜单进入，选择当房主或房客。
//    Section 0「选择角色」：当房主按钮 + 当房客按钮（大卡片样式）
//    Section 1「联机状态」：当前联机状态 + Network ID + 本地 IP
//
//  房主流程：
//    1. 检查 ZeroTier 框架可用性 + 预设 Network ID 是否已设置
//    2. 连接到预设 Network ID 房间（调用 connectToRoom:completion:）
//    3. 连接成功后监听 LanPortDetectorDidDetectPortNotification
//    4. 自动检测 LAN 端口并生成分享代码（调用 generateShareCodeForRoom:）
//    5. 显示分享代码（可复制、可分享）
//
//  房客流程：
//    1. 弹出输入框（UIAlertController with textField）
//    2. 解析分享代码（调用 parseShareCode:）
//    3. 连接到房间（调用 connectToRoom:completion:）
//    4. 连接成功后提示并显示服务器地址（房主 IP:端口）
//

#import "MultiplayerViewController.h"
#import "MultiplayerManager.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "LanPortDetector.h"
#import "ZeroTierBridge.h"
#import "PortForwarder.h"
#import "utils.h"

/// 本地化辅助函数
/// 优先通过 localize() 查找本地化文本；若未找到（返回值等于 key），则使用传入的 fallback。
/// 这样既满足"所有新增文本需要本地化"的要求，又避免 key 未注册时用户看到原始 key。
NS_INLINE NSString *MPLocalized(NSString *key, NSString *fallback) {
    NSString *value = localize(key, nil);
    return [value isEqualToString:key] ? (fallback ?: key) : value;
}

@interface MultiplayerViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, MultiplayerManagerDelegate>

/// 当前界面模式（启动器 / 游戏内）
@property (nonatomic, assign) MultiplayerVCMode mode;

/// 主表格视图（InsetGrouped 风格）
@property (nonatomic, strong) UITableView *tableView;

/// 当前已保存的房间列表
@property (nonatomic, strong) NSArray<MultiplayerRoom *> *rooms;

#pragma mark - 启动器模式专用控件

/// Section 0 Row 0 的"启用联机"开关
@property (nonatomic, strong) UISwitch *enableSwitch;

/// Section 2 Row 0 的 IP 地址输入框（强引用，确保跨 cell 复用时数据不丢失）
@property (nonatomic, strong) UITextField *directIPField;

/// Section 2 Row 0 的端口输入框（强引用）
@property (nonatomic, strong) UITextField *directPortField;

#pragma mark - 游戏内模式专用状态

/// 房主流程是否激活（已点击"当房主"且正在等待/已连接）
@property (nonatomic, assign) BOOL isHostFlowActive;

/// 房客流程是否激活（已点击"当房客"且正在等待/已连接）
@property (nonatomic, assign) BOOL isGuestFlowActive;

/// 房主流程中最新生成的分享代码（用于显示与复制）
@property (nonatomic, copy, nullable) NSString *lastShareCode;

/// 房客流程中最新解析出的服务器地址（hostIP:hostPort，用于显示给用户）
@property (nonatomic, copy, nullable) NSString *lastServerAddress;

/// 房主流程中正在使用的房间对象（用于生成分享代码）
@property (nonatomic, strong, nullable) MultiplayerRoom *hostRoom;

/// 房客流程中正在连接的房间对象（用于显示连接状态）
@property (nonatomic, strong, nullable) MultiplayerRoom *guestRoom;

/// 连接进度提示 Alert（用于动态更新进度文本）
///
/// 当房主或房客流程开始连接时，会 present 此 Alert 并在其中显示进度文本。
/// multiplayerConnectionProgress: 回调会更新此 Alert 的 message 属性，
/// 让用户实时看到"步骤 1/6：正在启动 ZeroTier 节点..."等进度。
///
/// 关键修复：之前连接流程只显示一个静态的"正在连接到 ZeroTier 网络"提示，
/// 用户无法知道后台进度，只能干等 15-30 秒直到成功或失败。
/// 现在通过此 Alert 实时更新进度，让用户看到详细的步骤信息。
@property (nonatomic, strong, nullable) UIAlertController *connectionProgressAlert;

@end

@implementation MultiplayerViewController

#pragma mark - Init

/// 通过模式初始化联机界面
/// @param mode 界面模式（启动器 / 游戏内）
- (instancetype)initWithMode:(MultiplayerVCMode)mode {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mode = mode;
    }
    return self;
}

/// 兜底初始化：未指定模式时默认使用启动器模式
- (instancetype)init {
    return [self initWithMode:MultiplayerVCModeLauncher];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // 根据模式设置标题
    if (self.mode == MultiplayerVCModeInGame) {
        self.title = MPLocalized(@"mp.title.ingame", @"联机");
    } else {
        self.title = MPLocalized(@"mp.title", @"联机");
    }

    // 适配自定义启动器背景：透明化当前 VC，让全局背景图/毛玻璃透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 初始化数据：从 MultiplayerManager 读取已保存的房间列表
    self.rooms = [[MultiplayerManager sharedManager] savedRooms] ?: @[];

    // 构建 UI
    [self setupUI];

    // 注册为 MultiplayerManager 代理，接收节点/网络状态变化的实时回调
    [MultiplayerManager sharedManager].delegate = self;

    // 监听背景效果变化通知，背景切换时重新应用透明效果并刷新表格
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backgroundEffectChanged)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    // 游戏内模式：监听 LAN 端口检测通知（房主流程依赖）
    if (self.mode == MultiplayerVCModeInGame) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(lanPortDidDetect:)
                                                     name:LanPortDetectorDidDetectPortNotification
                                                   object:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // 进入界面时重新应用背景效果（背景可能在其他界面被修改）
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;

    // 重新应用导航栏毛玻璃效果
    [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];

    // 刷新房间列表（可能在其他界面修改过）
    [self refreshRooms];

    // 启动器模式：根据持久化的用户意图恢复开关状态
    //
    // 关键修复（开关状态不同步）：
    // 之前使用 isNodeStarted（运行时状态）恢复开关，存在以下问题：
    //   - 用户点击开关 ON → 后台开始启动节点（耗时 5+ 秒）→ 用户关闭 VC →
    //     重新打开 VC → 此时节点可能仍在启动中（isNodeStarted=NO）→ 开关显示 OFF
    //   - 用户点击开关 ON → 节点启动成功 → 用户关闭启动器（杀进程）→
    //     重新打开启动器 → isNodeStarted=NO（进程重启后状态丢失）→ 开关显示 OFF
    //
    // 修复方案：使用 isMultiplayerEnabled（持久化到 NSUserDefaults）恢复开关状态，
    // 表示用户的意图而非节点实际状态。即使关闭启动器再重新打开，开关也能正确显示。
    if (self.mode == MultiplayerVCModeLauncher) {
        BOOL enabled = [[MultiplayerManager sharedManager] isMultiplayerEnabled];
        [self.enableSwitch setOn:enabled animated:NO];

        // 如果用户之前启用了联机但节点未启动（如关闭启动器后重新打开），
        // 自动重启节点以恢复联机功能，让用户体验无缝衔接。
        if (enabled && ![[MultiplayerManager sharedManager] isNodeStarted]) {
            if ([[MultiplayerManager sharedManager] isFrameworkAvailable]) {
                NSLog(@"[MultiplayerVC] 检测到联机已启用但节点未启动，自动重启节点...");
                __weak typeof(self) weakSelf = self;
                [[MultiplayerManager sharedManager] ensureNodeStartedWithCompletion:^(BOOL success, NSError *error) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;

                    if (!success) {
                        // 关键修复（严重5）：节点启动失败时不应清除用户的持久化意图。
                        // 之前的实现会调用 setMultiplayerEnabled:NO，导致用户下次打开启动器
                        // 开关已自动变为 OFF，需要重新手动启用。
                        // 现在仅回退 UI 开关状态（视觉上关闭），但保留 isMultiplayerEnabled=YES，
                        // 这样用户下次打开启动器时开关会显示 ON 并自动重试启动节点。
                        // 只有 framework 不可用（永久不可用）时才清除意图。
                        NSLog(@"[MultiplayerVC] 自动重启节点失败（保留用户意图，下次重试）：%@", error.localizedDescription);
                        [strongSelf.tableView reloadData];
                    } else {
                        NSLog(@"[MultiplayerVC] 自动重启节点成功");
                        [strongSelf.tableView reloadData];
                    }
                }];
            } else {
                // framework 不可用是永久性故障，清除用户意图
                [[MultiplayerManager sharedManager] setMultiplayerEnabled:NO];
                [self.enableSwitch setOn:NO animated:NO];
            }
        }
    }
}

- (void)backgroundEffectChanged {
    // 背景效果改变时重新透明化当前 VC 并刷新表格，让所有 cell 重新适配文字颜色
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
        // 重新应用导航栏毛玻璃效果
        [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];
        // 刷新表格，让所有 cell 重新读取背景状态并适配颜色
        [self.tableView reloadData];
    });
}

- (void)dealloc {
    // 移除通知观察者，避免 dealloc 后收到通知导致崩溃
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // 清除代理引用，避免悬空指针
    if ([MultiplayerManager sharedManager].delegate == self) {
        [MultiplayerManager sharedManager].delegate = nil;
    }
}

#pragma mark - UI Setup

- (void)setupUI {
    // 使用 InsetGrouped 风格，卡片式布局，与系统设置界面一致
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
    // 启用自动尺寸计算
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    // 注册复用的 cell 类型
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DefaultCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"EmptyCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SwitchCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"NetworkIdCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DirectInputCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"RoleCardCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"StatusCell"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // 导航栏左上角：关闭按钮（xmark），两种模式都需要
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(closeTapped)];
    closeButton.accessibilityLabel = MPLocalized(@"mp.close", @"关闭");
    self.navigationItem.leftBarButtonItem = closeButton;

    // 注意：启动器模式右上角不需要按钮（Network ID 通过 Section 0 设置）
    // 注意：游戏内模式右上角也不需要按钮（房主/房客通过 Section 0 选择）

    // 应用导航栏毛玻璃效果
    [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];
}

#pragma mark - Navigation Actions

/// 关闭按钮回调：兼容 push 和 present 两种容器
- (void)closeTapped {
    [self.view endEditing:YES];
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - 启动器模式：启用联机开关

/// "启用联机"开关状态变化回调
///
/// 对标 FCL 启动器界面顶部的联机总开关：
///   - 打开：调用 ensureNodeStartedWithCompletion: 启动 ZeroTier 节点
///   - 关闭：调用 disconnectCurrentRoom 停止所有联机活动（节点保持运行，可再次打开）
///
/// 关键修复（开关状态不同步）：
/// 打开/关闭时通过 setMultiplayerEnabled: 持久化用户意图到 NSUserDefaults，
/// 这样即使关闭启动器再重新打开，开关状态也能正确恢复。
- (void)enableSwitchChanged:(UISwitch *)sender {
    if (sender.on) {
        // 检查 ZeroTier 框架可用性
        if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
            [sender setOn:NO animated:YES];
            [self showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                    message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法启用联机。请使用包含真实 zt.framework 的构建版本。")];
            return;
        }

        // 持久化用户启用联机的意图
        [[MultiplayerManager sharedManager] setMultiplayerEnabled:YES];

        // 启动 ZeroTier 节点
        __weak typeof(self) weakSelf = self;
        [[MultiplayerManager sharedManager] ensureNodeStartedWithCompletion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (!success) {
                // 关键修复（严重5）：节点启动失败时保留用户意图，仅回退 UI 开关。
                // 这样下次打开启动器时开关仍会显示 ON 并自动重试。
                // 之前会调用 setMultiplayerEnabled:NO，导致用户需要每次重新手动启用。
                [strongSelf.enableSwitch setOn:NO animated:YES];
                [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.node.start_failed_title", @"启动失败")
                                              message:error.localizedDescription ?: MPLocalized(@"mp.node.start_failed_msg", @"ZeroTier 节点启动失败，请重试。")];
            } else {
                // 启动成功：刷新表格以更新开关行的辅助文字
                [strongSelf.tableView reloadData];
            }
        }];
    } else {
        // 持久化用户关闭联机的意图
        [[MultiplayerManager sharedManager] setMultiplayerEnabled:NO];

        // 关闭联机：断开当前房间（如有）
        if ([[MultiplayerManager sharedManager] currentRoom]) {
            [[MultiplayerManager sharedManager] disconnectCurrentRoom];
        }
        [self refreshRooms];
    }
}

#pragma mark - 启动器模式：预设 Network ID 编辑

/// 点击 Network ID 行：弹出 UIAlertController 让用户输入预设 Network ID
///
/// 对标 FCL：房主首次设置一次 Network ID（在 central.zerotier.com 创建后填入），
/// 之后每次开房自动使用，分享代码中自动包含此 Network ID。
- (void)networkIdCellTapped {
    [self.view endEditing:YES];

    // 检查 ZeroTier 框架可用性
    if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法设置 Network ID。")];
        return;
    }

    NSString *current = [[MultiplayerManager sharedManager] presetNetworkId] ?: @"";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.network_id.title", @"设置 Network ID")
                                                                   message:MPLocalized(@"mp.network_id.message", @"在 central.zerotier.com 创建网络后填入 16 位 Network ID，开房时自动使用")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = current;
        textField.placeholder = MPLocalized(@"mp.network_id.placeholder", @"16 位十六进制 Network ID");
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.cancel", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // 快速模式按钮：自动生成 Ad-hoc 网络 ID，无需注册账号
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.network_id.use_adhoc", @"使用快速模式（无需注册）")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 检查 ZeroTier 框架可用性
        if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                          message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法使用快速模式。")];
            return;
        }

        // 生成 Ad-hoc 网络 ID
        NSString *adhocNetId = [[MultiplayerManager sharedManager] generateAdhocNetworkId];
        if (!adhocNetId.length) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.adhoc_failed_title", @"生成失败")
                                          message:MPLocalized(@"mp.network_id.adhoc_failed_msg", @"无法生成快速模式 Network ID，请改用标准模式")];
            return;
        }

        // 保存为预设 Network ID
        [[MultiplayerManager sharedManager] setPresetNetworkId:adhocNetId];
        [strongSelf.tableView reloadData];

        // 提示用户
        [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.adhoc_success_title", @"已启用快速模式")
                                      message:[NSString stringWithFormat:@"%@\n\n%@",
                                               MPLocalized(@"mp.network_id.adhoc_success_msg", @"已自动生成 Network ID，无需注册账号即可联机。注意：快速模式稳定性不如标准模式，IP 可能变化。"),
                                               [NSString stringWithFormat:@"Network ID: %@", adhocNetId]]];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.save", @"保存")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        UITextField *field = alert.textFields.firstObject;
        NSString *value = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (value.length == 0) {
            // 空字符串：清除预设
            [[MultiplayerManager sharedManager] setPresetNetworkId:nil];
            [strongSelf.tableView reloadData];
            return;
        }

        // 校验格式
        if (![[MultiplayerManager sharedManager] isValidNetworkId:value]) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.invalid_title", @"格式不正确")
                                          message:MPLocalized(@"mp.network_id.invalid_msg", @"Network ID 应为 16 位十六进制字符串")];
            return;
        }

        [[MultiplayerManager sharedManager] setPresetNetworkId:value];
        [strongSelf.tableView reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 启动器模式：ZeroTier 网络创建教程

/// 显示 ZeroTier 网络创建教程
///
/// 对标 FCL 的"联机帮助"功能：说明两种联机模式的区别和使用方法。
///
/// 两种模式：
///   1. 标准模式（稳定）：在 central.zerotier.com 注册账号创建网络
///      - 优点：IP 固定、支持 Private 授权、每人独立网络
///      - 缺点：需要注册账号、配置较复杂
///   2. 快速模式（不稳定）：使用 Ad-hoc 网络自动分配
///      - 优点：无需注册账号、即开即用
///      - 缺点：只有 IPv6、公开网络、IP 可能变化
- (void)showZeroTierGuide {
    [self.view endEditing:YES];

    // 构建教程内容：两种模式对比
    NSString *modeStandard = [NSString stringWithFormat:@"%@（%@）\n%@",
                              MPLocalized(@"mp.guide.mode_standard", @"标准模式"),
                              MPLocalized(@"mp.guide.stable", @"稳定"),
                              MPLocalized(@"mp.guide.mode_standard_desc", @"在 central.zerotier.com 注册账号并创建组织，获得固定的 Network ID。IP 稳定、支持授权管理、每人独立网络。")];

    NSString *modeFast = [NSString stringWithFormat:@"%@（%@）\n%@",
                          MPLocalized(@"mp.guide.mode_fast", @"快速模式"),
                          MPLocalized(@"mp.guide.unstable", @"不稳定"),
                          MPLocalized(@"mp.guide.mode_fast_desc", @"使用 Ad-hoc 网络自动生成 Network ID，无需注册账号。但只有 IPv6 地址、公开网络安全性弱、IP 可能变化。")];

    // 标准模式步骤
    NSString *standardTitle = [NSString stringWithFormat:@"\n【%@】", MPLocalized(@"mp.guide.mode_standard", @"标准模式")];

    NSString *step1 = [NSString stringWithFormat:@"1. %@\n   %@",
                       MPLocalized(@"mp.guide.step1_title", @"注册 ZeroTier 账号"),
                       MPLocalized(@"mp.guide.step1_desc", @"访问 central.zerotier.com（新版 Central），注册并登录账号（免费，支持 Google/GitHub/Microsoft 登录）")];

    NSString *step2 = [NSString stringWithFormat:@"2. %@\n   %@",
                       MPLocalized(@"mp.guide.step2_title", @"创建组织"),
                       MPLocalized(@"mp.guide.step2_desc", @"登录后输入组织名称，点击「Create Organization」。免费套餐自带一个 Network Group 和一个 Network")];

    NSString *step3 = [NSString stringWithFormat:@"3. %@\n   %@",
                       MPLocalized(@"mp.guide.step3_title", @"获取 Network ID"),
                       MPLocalized(@"mp.guide.step3_desc", @"在左侧边栏展开「Networks」，点击默认网络（如 my-first-network），复制顶部的 16 位 Network ID")];

    NSString *step4 = [NSString stringWithFormat:@"4. %@\n   %@",
                       MPLocalized(@"mp.guide.step4_title", @"设置网络访问控制"),
                       MPLocalized(@"mp.guide.step4_desc", @"Private（推荐）：需手动授权成员更安全；Public：任何人可直接加入")];

    NSString *step5 = [NSString stringWithFormat:@"5. %@\n   %@",
                       MPLocalized(@"mp.guide.step5_title", @"填入启动器"),
                       MPLocalized(@"mp.guide.step5_desc", @"回到本页面，点击「预设 Network ID」行，粘贴并保存")];

    NSString *step6 = [NSString stringWithFormat:@"6. %@\n   %@",
                       MPLocalized(@"mp.guide.step6_title", @"授权房客设备"),
                       MPLocalized(@"mp.guide.step6_desc", @"房客加入后在「Member Devices」标签点击三点菜单→「Authorize」授权（Private 模式需要，Public 模式跳过）")];

    NSString *step7 = [NSString stringWithFormat:@"7. %@\n   %@",
                       MPLocalized(@"mp.guide.step7_title", @"开始联机"),
                       MPLocalized(@"mp.guide.step7_desc", @"启动游戏后在悬浮球中打开联机界面，选择「当房主」即可开房")];

    // 快速模式步骤
    NSString *fastTitle = [NSString stringWithFormat:@"\n【%@】", MPLocalized(@"mp.guide.mode_fast", @"快速模式")];

    NSString *fastStep1 = [NSString stringWithFormat:@"1. %@\n   %@",
                           MPLocalized(@"mp.guide.fast_step1_title", @"点击「预设 Network ID」"),
                           MPLocalized(@"mp.guide.fast_step1_desc", @"在本页面点击「预设 Network ID」行")];

    NSString *fastStep2 = [NSString stringWithFormat:@"2. %@\n   %@",
                           MPLocalized(@"mp.guide.fast_step2_title", @"选择快速模式"),
                           MPLocalized(@"mp.guide.fast_step2_desc", @"点击「使用快速模式（无需注册）」按钮，系统自动生成 Network ID")];

    NSString *fastStep3 = [NSString stringWithFormat:@"3. %@\n   %@",
                           MPLocalized(@"mp.guide.fast_step3_title", @"开始联机"),
                           MPLocalized(@"mp.guide.fast_step3_desc", @"启动游戏后在悬浮球中打开联机界面，选择「当房主」即可开房")];

    NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n\n%@\n\n%@%@",
                         MPLocalized(@"mp.guide.intro", @"ZeroTier 提供两种联机模式，根据需求选择："),
                         modeStandard,
                         modeFast,
                         standardTitle, step1];

    // 使用多行格式拼接所有步骤（标准模式 7 步 + 快速模式 3 步）
    message = [NSString stringWithFormat:@"%@\n\n%@\n\n%@\n\n%@\n\n%@\n\n%@\n\n%@\n\n%@\n\n%@",
               message,
               step2,
               step3,
               step4,
               step5,
               step6,
               step7,
               fastTitle,
               [NSString stringWithFormat:@"%@\n%@\n%@", fastStep1, fastStep2, fastStep3]];

    // 添加注意事项
    message = [NSString stringWithFormat:@"%@\n\n%@",
               message,
               MPLocalized(@"mp.guide.note", @"注意：房主和房客使用相同的 Network ID 才能联机。标准模式需在后台授权成员（Private）或设为 Public。快速模式所有人共享同一公开网络。")];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.guide.title", @"ZeroTier 联机教程")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 「打开 central.zerotier.com」按钮：直接跳转到浏览器（标准模式需要）
    // 新版 Central：central.zerotier.com（推荐新用户使用）
    // 旧版 Central：my.zerotier.com（老用户继续使用）
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.guide.open_website", @"打开 central.zerotier.com（标准模式）")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:@"https://central.zerotier.com/"];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }]];

    // 「使用快速模式」按钮：直接生成 Ad-hoc 网络 ID
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.guide.use_fast_mode", @"使用快速模式")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 检查 ZeroTier 框架可用性
        if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                          message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法使用快速模式。")];
            return;
        }

        // 生成 Ad-hoc 网络 ID
        NSString *adhocNetId = [[MultiplayerManager sharedManager] generateAdhocNetworkId];
        if (!adhocNetId.length) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.adhoc_failed_title", @"生成失败")
                                          message:MPLocalized(@"mp.network_id.adhoc_failed_msg", @"无法生成快速模式 Network ID，请改用标准模式")];
            return;
        }

        // 保存为预设 Network ID
        [[MultiplayerManager sharedManager] setPresetNetworkId:adhocNetId];
        [strongSelf.tableView reloadData];

        // 提示用户
        [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.adhoc_success_title", @"已启用快速模式")
                                      message:[NSString stringWithFormat:@"%@\n\n%@",
                                               MPLocalized(@"mp.network_id.adhoc_success_msg", @"已自动生成 Network ID，无需注册账号即可联机。注意：快速模式稳定性不如标准模式，IP 可能变化。"),
                                               [NSString stringWithFormat:@"Network ID: %@", adhocNetId]]];
    }]];

    // 「我知道了」按钮
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.ok", @"我知道了")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 房间连接

/// 连接到指定房间
///
/// 内部调用 MultiplayerManager 的 connectToRoom:completion:，
/// 并在主线程更新房间状态和 UI。连接成功后回调 completion。
- (void)connectToRoom:(MultiplayerRoom *)room completion:(void (^)(BOOL success, NSError *error))completion {
    // 设置状态为连接中
    room.status = MultiplayerRoomStatusConnecting;
    [[MultiplayerManager sharedManager] updateRoom:room];
    [self refreshRooms];

    __weak typeof(self) weakSelf = self;
    [[MultiplayerManager sharedManager] connectToRoom:room completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // 根据连接结果更新房间状态
            if (success) {
                room.status = MultiplayerRoomStatusConnected;
                room.lastConnectedAt = [NSDate date];
            } else {
                room.status = MultiplayerRoomStatusError;
            }
            [[MultiplayerManager sharedManager] updateRoom:room];
            [strongSelf refreshRooms];

            if (completion) {
                completion(success, error);
            }
        });
    }];
}

/// 断开当前房间连接
- (void)disconnectRoom:(MultiplayerRoom *)room {
    [[MultiplayerManager sharedManager] disconnectCurrentRoom];
    room.status = MultiplayerRoomStatusDisconnected;
    [[MultiplayerManager sharedManager] updateRoom:room];
    [self refreshRooms];
}

#pragma mark - 房间行按钮回调

/// 房间行的"连接/断开"按钮回调
///
/// 通过 button.tag 找到对应的房间索引
- (void)roomButtonTapped:(UIButton *)button {
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.rooms.count) {
        return;
    }

    MultiplayerRoom *room = self.rooms[row];

    // 防止连接中重复点击
    if (room.status == MultiplayerRoomStatusConnecting) {
        return;
    }

    if (room.status == MultiplayerRoomStatusConnected) {
        // 已连接则断开
        [self disconnectRoom:room];
    } else {
        // 未连接则连接
        [self connectToRoom:room completion:^(BOOL success, NSError *error) {
            if (!success) {
                [self showSimpleAlertWithTitle:MPLocalized(@"mp.connect.failed", @"连接失败")
                                        message:error.localizedDescription ?: MPLocalized(@"mp.connect.failed_msg", @"无法连接到房间，请检查 Network ID 是否正确以及网络是否畅通。")];
            }
        }];
    }
}

#pragma mark - 房间详情 ActionSheet

/// 显示房间详情 ActionSheet
///
/// 提供以下操作：
///   - 连接 / 断开（根据当前状态显示）
///   - 分享房间（生成分享文本，调用系统分享面板）
///   - 删除房间（二次确认后删除）
- (void)showRoomActionsForRoom:(MultiplayerRoom *)room {
    [self.view endEditing:YES];

    NSString *title = room.name.length ? room.name : MPLocalized(@"mp.room.unnamed", @"未命名房间");
    NSString *message = [NSString stringWithFormat:@"%@: %@",
                         MPLocalized(@"mp.room.network_id", @"Network ID"),
                         room.networkId ?: @"-"];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // 连接 / 断开按钮（根据当前状态切换标题）
    NSString *connectTitle = (room.status == MultiplayerRoomStatusConnected)
        ? MPLocalized(@"mp.room.action.disconnect", @"断开连接")
        : MPLocalized(@"mp.room.action.connect", @"连接房间");

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:connectTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (room.status == MultiplayerRoomStatusConnected) {
            [strongSelf disconnectRoom:room];
        } else {
            [strongSelf connectToRoom:room completion:^(BOOL success, NSError *error) {
                if (!success) {
                    [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.connect.failed", @"连接失败")
                                                  message:error.localizedDescription ?: MPLocalized(@"mp.connect.failed_msg", @"无法连接到房间，请检查 Network ID 是否正确以及网络是否畅通。")];
                }
            }];
        }
    }]];

    // 分享房间按钮（使用 shareTextForRoom: 生成可读分享文本）
    [sheet addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.room.action.share", @"分享房间")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *shareText = [[MultiplayerManager sharedManager] shareTextForRoom:room];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[shareText] applicationActivities:nil];

        // iPad 适配：popover 指向屏幕中央
        if (activityVC.popoverPresentationController) {
            activityVC.popoverPresentationController.sourceView = strongSelf.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(strongSelf.view.bounds.size.width / 2.0,
                                                                              strongSelf.view.bounds.size.height / 2.0,
                                                                              1, 1);
        }
        [strongSelf presentViewController:activityVC animated:YES completion:nil];
    }]];

    // 删除房间按钮（destructive 红色）
    [sheet addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.room.action.delete", @"删除房间")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 二次确认对话框
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.room.delete.confirm_title", @"确认删除")
                                                                         message:[NSString stringWithFormat:@"%@「%@」？\n%@",
                                                                                  MPLocalized(@"mp.room.delete.confirm_prefix", @"确定要删除房间"),
                                                                                  room.name,
                                                                                  MPLocalized(@"mp.room.delete.confirm_warning", @"此操作无法撤销。")]
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.cancel", @"取消") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.room.delete.button", @"删除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            // 如果该房间已连接，先断开连接
            if (room.status == MultiplayerRoomStatusConnected) {
                [[MultiplayerManager sharedManager] disconnectCurrentRoom];
            }
            [[MultiplayerManager sharedManager] removeRoom:room.roomId];
            [strongSelf refreshRooms];
        }]];
        [strongSelf presentViewController:confirm animated:YES completion:nil];
    }]];

    // 取消按钮
    [sheet addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.cancel", @"取消") style:UIAlertActionStyleCancel handler:nil]];

    // iPad 适配：popover 指向屏幕中央
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0,
                                                                    self.view.bounds.size.height / 2.0,
                                                                    1, 1);
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 启动器模式：直连

/// 点击"加入游戏"按钮：将 IP:端口 写入当前 profile，启动游戏后自动加入
- (void)joinDirectConnect {
    [self.view endEditing:YES];

    NSString *ip = [self.directIPField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *port = [self.directPortField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 校验：IP 非空
    if (ip.length == 0) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.direct.error_title", @"提示")
                                message:MPLocalized(@"mp.direct.error.ip_empty", @"请输入服务器 IP 地址")];
        return;
    }

    // 端口默认值
    if (port.length == 0) {
        port = @"25565";
    }

    // 校验：IP 格式
    if (![[MultiplayerManager sharedManager] isValidIPAddress:ip]) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.direct.error_title", @"提示")
                                message:MPLocalized(@"mp.direct.error.ip_invalid", @"IP 地址格式不正确，请检查输入")];
        return;
    }

    // 拼接服务器地址 "IP:端口"
    NSString *serverAddress = [NSString stringWithFormat:@"%@:%@", ip, port];

    // 将服务器地址写入当前 profile
    NSString *profileName = [PLProfiles current].selectedProfileName;
    if (!profileName || profileName.length == 0) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.direct.error_title", @"提示")
                                message:MPLocalized(@"mp.direct.error.no_profile", @"未找到当前 profile，请先选择一个游戏配置")];
        return;
    }
    [[PLProfiles current] setServerIp:serverAddress forProfile:profileName];

    // 显示成功提示
    [self showSimpleAlertWithTitle:MPLocalized(@"mp.direct.success_title", @"已添加服务器")
                           message:[NSString stringWithFormat:@"%@ %@",
                                    MPLocalized(@"mp.direct.success_msg_prefix", @"已添加服务器"),
                                    serverAddress]];
}

#pragma mark - 游戏内模式：房主流程

/// 点击"当房主"按钮：进入房主流程
///
/// 对标 FCL 房主流程：
///   1. 检查 ZeroTier 框架可用性
///   2. 检查预设 Network ID 是否已设置（未设置则提示去启动器设置）
///   3. 自动连接到预设 Network ID 的房间
///   4. 连接成功后监听 LanPortDetectorDidDetectPortNotification
///   5. 自动检测 LAN 端口
///   6. 生成分享代码（generateShareCodeForRoom:）
///   7. 显示分享代码（可复制、可分享）
- (void)hostButtonTapped {
    [self.view endEditing:YES];

    // 检查 1：ZeroTier 框架可用性
    if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法作为房主开房。请使用包含真实 zt.framework 的构建版本。")];
        return;
    }

    // 检查 2：预设 Network ID 是否已设置
    NSString *presetNetId = [[MultiplayerManager sharedManager] presetNetworkId];
    if (!presetNetId.length) {
        // 未设置：提示用户去启动器设置
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.host.no_network_id_title", @"未设置 Network ID")
                                                                       message:MPLocalized(@"mp.host.no_network_id_msg", @"房主需要先设置预设 ZeroTier Network ID。请在启动器联机界面中设置后再来。")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.ok", @"好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // 校验 Network ID 格式
    if (![[MultiplayerManager sharedManager] isValidNetworkId:presetNetId]) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.network_id.invalid_title", @"Network ID 格式不正确")
                                message:MPLocalized(@"mp.network_id.invalid_msg", @"请在启动器联机界面设置正确的 16 位十六进制 Network ID")];
        return;
    }

    // ============================================================
    // 幂等性检查：房主流程已激活时的短路处理
    // ============================================================
    // 关键修复：之前再次点击"当房主"按钮会重新走整个连接流程，
    // 即使已经连接成功且 LAN 端口已检测到，也会：
    //   1. 清空 lastShareCode/lastServerAddress（丢失已生成的分享代码）
    //   2. 重新显示"正在开启联机"进度提示
    //   3. 重新调用 connectToRoom（把 status 重置为 Connecting）
    //   4. 连接成功后再次显示"等待检测 LAN 端口..."提示（误导）
    //   5. 由于 LanPortDetector 对相同端口去重，不会再次触发 lanPortDidDetect:
    //      导致用户无法重新看到分享代码
    //
    // 修复方案：如果房主流程已激活且房间已连接，根据是否已有分享代码
    // 直接显示对应提示，不重新走连接流程。
    if (self.isHostFlowActive) {
        MultiplayerRoom *currentRoom = [[MultiplayerManager sharedManager] currentRoom];
        if (currentRoom && [currentRoom.networkId isEqualToString:presetNetId]) {
            // 房间已连接
            if (self.lastShareCode.length) {
                // 分享代码已存在：直接显示分享代码
                NSLog(@"[MultiplayerVC] 房主流程已激活且分享代码已存在，直接显示分享代码");
                [self showHostShareCodeAlert];
            } else {
                // 分享代码不存在：检查 LanPortDetector 是否已检测到端口
                // 先检查 detectedPort，再尝试从日志文件解析
                NSString *detectedPort = [[LanPortDetector sharedDetector] detectedPort];
                if (!detectedPort.length) {
                    NSLog(@"[MultiplayerVC] 幂等检查：detectedPort 为空，尝试从日志文件重新解析...");
                    detectedPort = [[LanPortDetector sharedDetector] detectFromLogFile];
                    if (detectedPort.length) {
                        [[LanPortDetector sharedDetector] setManualPort:detectedPort];
                    }
                }
                if (detectedPort.length) {
                    NSLog(@"[MultiplayerVC] 房主流程已激活，检测到端口 %@，生成分享代码", detectedPort);
                    [self generateShareCodeWithPort:detectedPort];
                } else {
                    // LAN 端口尚未检测到：显示"等待检测 LAN 端口"提示
                    NSLog(@"[MultiplayerVC] 房主流程已激活但 LAN 端口尚未检测到，显示等待提示");
                    [self showHostConnectedAlert];
                }
            }
            return;
        }
        // 房间未连接或 networkId 不匹配：继续走完整流程（会先断开旧连接）
    }

    // 标记房主流程激活
    self.isHostFlowActive = YES;
    self.lastShareCode = nil;
    self.lastServerAddress = nil;

    // 构建/复用房主房间对象
    MultiplayerRoom *room = self.hostRoom;
    if (!room || ![room.networkId isEqualToString:presetNetId]) {
        room = [[MultiplayerRoom alloc] init];
        room.roomId = [[MultiplayerManager sharedManager] generateRoomId];
        room.name = MPLocalized(@"mp.host.default_room_name", @"我的联机房间");
        room.networkId = presetNetId;
        room.hostIP = @"";
        // 关键修复（P2）：房主创建房间时不再预设 hostPort=25565。
        // 房主"对局域网开放"后，MC 的 LAN 端口是随机的（49152-65535），
        // 由 LanPortDetector 实时检测后才确定。
        // 之前预设为 25565 会导致：
        //   - 房主在步骤 4.5 hostIP 同步后即触发 connectToRoomFlow 步骤 6
        //     （虽然本提交同步修复了 P1 让房主跳过步骤 6，但 hostPort=25565 仍是
        //      错误的初始值，会导致分享代码生成前 room.hostPort 错误）
        //   - 分享代码生成时若 LanPortDetector 未检测到端口，hostPort 仍为 25565
        //     导致房客 PortForwarder 转发到房主:25565（房主 MC 未监听此端口）
        // 正确做法：初始化为空字符串，由 generateShareCodeWithPort: 在检测到
        // LAN 端口后填入实际端口。
        room.hostPort = @"";
        room.roomDescription = @"";
        room.ownerName = @"";
        room.status = MultiplayerRoomStatusDisconnected;
        room.createdAt = [NSDate date];
        // 关键修复（房客加入后无法连接服务器）：标记为房主侧房间。
        // MultiplayerManager 在 connectToRoomFlow: 和 zeroTierNetworkReady: 回调中
        // 只允许 isHostSide=YES 的房间将 room.hostIP 同步为本机 ZeroTier IP，
        // 用于生成分享代码；房客房间（isHostSide=NO）保留分享代码中的房主 IP，
        // 确保 PortForwarder 正确转发到房主而非本机自身。
        room.isHostSide = YES;
        self.hostRoom = room;
    } else {
        // 已存在房主房间对象（可能是复用的旧对象），确保 isHostSide=YES。
        // 防止旧持久化数据中 isHostSide 为 NO 导致后续逻辑误判为房客房间。
        room.isHostSide = YES;
    }

    // 如果当前已连接到其他房间，先断开
    MultiplayerRoom *currentRoom = [[MultiplayerManager sharedManager] currentRoom];
    if (currentRoom && ![currentRoom.networkId isEqualToString:presetNetId]) {
        [[MultiplayerManager sharedManager] disconnectCurrentRoom];
    }

    // 显示"正在连接"进度提示（可动态更新进度文本）
    //
    // 关键修复（前台无反馈）：
    // 之前只显示一个静态的"正在连接到 ZeroTier 网络，请稍候..."提示，
    // 用户无法知道后台进度，连接流程耗时 15-30 秒期间用户只能干等。
    // 现在使用 showConnectionProgressWithTitle:message: 显示一个带 Cancel 按钮的 Alert，
    // 并通过 multiplayerConnectionProgress: 回调实时更新 message 为"步骤 1/6：..."等进度。
    [self showConnectionProgressWithTitle:MPLocalized(@"mp.host.connecting_title", @"正在开启联机")
                                   message:MPLocalized(@"mp.host.connecting_msg", @"正在连接到 ZeroTier 网络，请稍候...")];

    // 启动 LAN 端口检测器（房主在 MC 中开放局域网后会被自动检测到）
    [[LanPortDetector sharedDetector] startDetecting];

    // 连接到预设房间
    __weak typeof(self) weakSelf = self;
    [self connectToRoom:room completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 先关闭进度提示 Alert，再显示结果
        [strongSelf dismissConnectionProgressAlertWithCompletion:^{
            if (success) {
                // 连接成功
                //
                // 关键修复：检查 LanPortDetector 是否已经检测到端口。
                // 用户可能先在游戏中"对局域网开放"，然后才点"当房主"按钮。
                // 此时 LanPortDetector 已经检测到端口并发送过通知，但由于
                // isHostFlowActive 还是 NO，lanPortDidDetect: 回调被忽略。
                // 之后连接成功时，LanPortDetector 因端口去重不再发通知，
                // 导致分享代码永远无法生成。
                //
                // 修复方案（三层兜底）：
                //   1. 优先检查 LanPortDetector.detectedPort（实时通知已检测到的端口）
                //   2. 若为 nil，调用 detectFromLogFile 从日志文件重新搜索
                //      （覆盖通知丢失或检测器未及时启动的情况）
                //   3. 若仍为 nil，显示"等待检测 LAN 端口"提示
                NSString *detectedPort = [[LanPortDetector sharedDetector] detectedPort];
                if (!detectedPort.length) {
                    // detectedPort 为空：尝试从日志文件重新解析
                    NSLog(@"[MultiplayerVC] detectedPort 为空，尝试从日志文件重新解析...");
                    detectedPort = [[LanPortDetector sharedDetector] detectFromLogFile];
                    if (detectedPort.length) {
                        // 从日志文件找到端口，手动设置到 LanPortDetector
                        NSLog(@"[MultiplayerVC] 从日志文件检测到端口 %@，设置到 LanPortDetector", detectedPort);
                        [[LanPortDetector sharedDetector] setManualPort:detectedPort];
                    }
                }

                if (detectedPort.length && strongSelf.hostRoom) {
                    NSLog(@"[MultiplayerVC] 连接成功，检测到 LAN 端口 %@，直接生成分享代码", detectedPort);
                    [strongSelf generateShareCodeWithPort:detectedPort];
                } else {
                    // 尚未检测到 LAN 端口：显示等待提示
                    NSLog(@"[MultiplayerVC] 连接成功但未检测到 LAN 端口，显示等待提示");
                    [strongSelf showHostConnectedAlert];
                }
            } else {
                // 连接失败
                strongSelf.isHostFlowActive = NO;
                [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.connect.failed", @"连接失败")
                                              message:error.localizedDescription ?: MPLocalized(@"mp.connect.failed_msg", @"无法连接到 ZeroTier 网络，请检查 Network ID 是否正确以及网络是否畅通。")];
            }
        }];
        [strongSelf.tableView reloadData];
    }];

    [self.tableView reloadData];
}

/// 显示房主连接成功后的提示
///
/// 对标 FCL 房主开房成功后的引导：
///   - "请在 MC 中创建世界并开放局域网"
///   - "系统会自动检测 LAN 端口并生成分享代码"
- (void)showHostConnectedAlert {
    NSString *localIP = [[MultiplayerManager sharedManager] currentLocalIP] ?: @"-";
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n%@\n\n%@: %@",
                         MPLocalized(@"mp.host.connected_msg", @"已连接到联机网络，等待检测 LAN 端口..."),
                         MPLocalized(@"mp.host.tip.create_world", @"请在 MC 中创建世界并开放局域网"),
                         MPLocalized(@"mp.host.tip.auto_detect", @"系统会自动检测 LAN 端口并生成分享代码"),
                         MPLocalized(@"mp.host.local_ip", @"本机 IP"),
                         localIP];
    [self showSimpleAlertWithTitle:MPLocalized(@"mp.host.connected_title", @"联机已开启")
                           message:message];
}

#pragma mark - 游戏内模式：LAN 端口检测回调

/// LanPortDetector 检测到端口后的回调
///
/// 房主流程核心：MC 开放局域网后，LanPortDetector 自动检测到端口号，
/// 触发本回调。本方法负责：
///   1. 将检测到的端口写入房主房间对象
///   2. 生成分享代码（generateShareCodeForRoom:）
///   3. 刷新 UI 显示分享代码
- (void)lanPortDidDetect:(NSNotification *)notification {
    // 仅在房主流程激活时处理
    if (!self.isHostFlowActive) {
        return;
    }

    NSString *port = notification.userInfo[@"port"];
    if (!port.length) {
        return;
    }

    [self generateShareCodeWithPort:port];
}

/// 根据检测到的 LAN 端口生成分享代码并显示
///
/// 此方法提取自 lanPortDidDetect:，供以下两个场景复用：
///   1. lanPortDidDetect: 收到 LanPortDetector 通知时调用
///   2. hostButtonTapped 连接成功后主动检查 LanPortDetector.detectedPort 时调用
///
/// 第二个场景用于修复"用户先开放局域网再点当房主"的问题：
///   - 用户先在 MC 中"对局域网开放" → LanPortDetector 检测到端口并发通知
///   - 但此时 isHostFlowActive=NO，lanPortDidDetect: 忽略通知
///   - 用户点"当房主"→ 连接成功 → LanPortDetector 因去重不再发通知
///   - 修复：连接成功后主动检查 detectedPort 并调用此方法
- (void)generateShareCodeWithPort:(NSString *)port {
    MultiplayerRoom *room = self.hostRoom;
    if (!room) {
        return;
    }

    // 关键修复（P4）：检查 ZeroTier 本地 IP 是否有效，避免房主断开后生成无效分享代码。
    //
    // 问题：generateShareCodeWithPort: 由 LanPortDetector 通知触发。当房主断开连接
    // 后 isHostFlowActive 可能仍为 YES（disconnectCurrentRoom 不会清空 ViewController
    // 的 isHostFlowActive），LanPortDetector 通知仍能触发本方法。此时 currentLocalIP
    // 已被清空，room.hostIP 不会更新（保持空字符串或旧值），生成的分享代码无效。
    // 同时 ReversePortForwarder 启动会因 currentLocalIP 为空而失败。
    //
    // 修复方案：本方法入口处检查 currentLocalIP，若为空则提示用户并直接返回，
    // 不生成分享代码、不启动 ReversePortForwarder。
    NSString *localIP = [[MultiplayerManager sharedManager] currentLocalIP];
    if (!localIP || localIP.length == 0) {
        NSLog(@"[MultiplayerVC] generateShareCodeWithPort: ZeroTier 本地 IP 为空，跳过生成分享代码（可能已断开连接）");
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.host.not_connected_title", @"未连接到联机网络")
                                      message:MPLocalized(@"mp.host.not_connected_msg",
                                                          @"请先点「当房主」按钮连接到 ZeroTier 网络，再在 MC 中开放局域网。")];
        return;
    }

    // 更新房间的端口和本机 IP
    room.hostPort = port;
    if (localIP.length) {
        room.hostIP = localIP;
    }
    [[MultiplayerManager sharedManager] updateRoom:room];

    // 关键架构修复（P0）：启动房主侧反向 PortForwarder
    //
    // libzt 是用户态 socket，与系统 socket 是两套独立的命名空间。
    // 房主 MC 通过 java.net.ServerSocket 在 127.0.0.1:port（系统 socket）监听，
    // 房客的 PortForwarder 通过 libzt socket connect 到房主 ZeroTier IP:port 时，
    // 连接到达房主的 libzt 实例后无法直接交付给房主 MC 的系统 socket。
    //
    // 解决方案：房主在 libzt socket 上监听 ZeroTier IP:port，accept 房客连接后
    // 用系统 socket 转发到 127.0.0.1:port（房主 MC 本地监听）。
    //
    // 启动时机：LanPortDetector 检测到 LAN 端口后立即启动，确保房客连接时
    // 房主侧已就绪。如果反向 PortForwarder 已在运行（如重复检测到端口），
    // 先停止再启动，确保监听最新的 IP 和端口。
    if (port.length > 0) {
        uint16_t portValue = (uint16_t)[port integerValue];
        if (portValue > 0) {
            // 如果反向 PortForwarder 已在运行，先停止（端口或 IP 可能已变化）
            if ([[MultiplayerManager sharedManager] isReversePortForwarderRunning]) {
                NSLog(@"[MultiplayerVC] 反向 PortForwarder 已在运行，先停止再重启");
                [[MultiplayerManager sharedManager] stopHostReverseForwarder];
            }

            NSError *reverseError = nil;
            BOOL reverseStarted = [[MultiplayerManager sharedManager]
                startHostReverseForwarderWithListenPort:portValue
                                              forwardPort:portValue
                                                   error:&reverseError];
            if (reverseStarted) {
                NSLog(@"[MultiplayerVC] 房主侧反向 PortForwarder 已启动：libzt %@:%u → 127.0.0.1:%u",
                      localIP ?: @"(nil)", portValue, portValue);
            } else {
                NSLog(@"[MultiplayerVC] 房主侧反向 PortForwarder 启动失败：%@",
                      reverseError.localizedDescription ?: @"(未知错误)");
                // 反向 PortForwarder 失败不阻断分享代码生成，
                // 但房客连接会失败（connection refused），通过日志告知用户。
                [self showSimpleAlertWithTitle:MPLocalized(@"mp.host.reverse_pf_failed_title", @"反向端口转发启动失败")
                                          message:[NSString stringWithFormat:@"%@\n\n%@",
                                                    MPLocalized(@"mp.host.reverse_pf_failed_msg",
                                                                @"房客将无法连接到你的游戏，请检查 ZeroTier 网络状态后重试。"),
                                                    reverseError.localizedDescription ?: @"(未知错误)"]];
            }
        }
    }

    // 生成分享代码
    self.lastShareCode = [[MultiplayerManager sharedManager] generateShareCodeForRoom:room];
    self.lastServerAddress = [NSString stringWithFormat:@"%@:%@", room.hostIP, room.hostPort];

    // 刷新表格，让 Section 1 显示最新的分享代码
    [self.tableView reloadData];

    // 弹出提示告知用户分享代码已生成
    [self showHostShareCodeAlert];
}

/// 显示房主分享代码 Alert
///
/// 提供以下操作：
///   - 复制分享代码到剪贴板
///   - 通过系统分享面板分享
- (void)showHostShareCodeAlert {
    NSString *shareCode = self.lastShareCode ?: @"";
    NSString *serverAddr = self.lastServerAddress ?: @"-";

    NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n\n%@\n%@\n\n%@",
                         MPLocalized(@"mp.host.share_code_ready", @"分享代码已生成！将以下代码发给房客："),
                         shareCode,
                         MPLocalized(@"mp.host.tip.wait_guest", @"房客输入此代码即可加入你的联机网络"),
                         [NSString stringWithFormat:@"%@: %@", MPLocalized(@"mp.host.server_address", @"服务器地址"), serverAddr],
                         MPLocalized(@"mp.host.tip.copy_or_share", @"可点击下方按钮复制或分享代码")];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.host.share_code_title", @"分享代码已生成")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    // 复制按钮
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.host.copy_code", @"复制代码")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = shareCode;
    }]];

    // 分享按钮
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.host.share_button", @"分享...")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[shareCode] applicationActivities:nil];
        if (activityVC.popoverPresentationController) {
            activityVC.popoverPresentationController.sourceView = strongSelf.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(strongSelf.view.bounds.size.width / 2.0,
                                                                              strongSelf.view.bounds.size.height / 2.0,
                                                                              1, 1);
        }
        [strongSelf presentViewController:activityVC animated:YES completion:nil];
    }]];

    // 关闭按钮
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.ok", @"好")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 游戏内模式：房客流程

/// 点击"当房客"按钮：进入房客流程
///
/// 对标 FCL 房客流程：
///   1. 弹出输入框（UIAlertController with textField）
///   2. 用户输入分享代码
///   3. 解析代码（parseShareCode:）
///   4. 连接到房间（connectToRoom:completion:）
///   5. 连接成功后提示并显示服务器地址
- (void)guestButtonTapped {
    [self.view endEditing:YES];

    // 检查 ZeroTier 框架可用性
    if (![[MultiplayerManager sharedManager] isFrameworkAvailable]) {
        [self showSimpleAlertWithTitle:MPLocalized(@"mp.core.unavailable_title", @"联机核心不可用")
                                message:MPLocalized(@"mp.core.unavailable_msg", @"ZeroTier 联机核心未加载，无法作为房客加入。请使用包含真实 zt.framework 的构建版本。")];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MPLocalized(@"mp.guest.input_title", @"输入分享代码")
                                                                   message:MPLocalized(@"mp.guest.input_msg", @"请输入房主提供的分享代码")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = MPLocalized(@"mp.guest.code_placeholder", @"在此粘贴分享代码");
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeASCIICapable;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.cancel", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"mp.guest.join_button", @"加入")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        UITextField *field = alert.textFields.firstObject;
        NSString *code = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // 校验：代码非空
        if (code.length == 0) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.guest.error_title", @"输入为空")
                                          message:MPLocalized(@"mp.guest.error.empty", @"请输入房主提供的分享代码")];
            return;
        }

        // 解析分享代码
        MultiplayerRoom *parsedRoom = [[MultiplayerManager sharedManager] parseShareCode:code];
        if (!parsedRoom) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.guest.error_title", @"代码无效")
                                          message:MPLocalized(@"mp.guest.error.invalid_code", @"无法解析分享代码，请确认代码完整无误")];
            return;
        }

        // 校验解析出的 Network ID
        if (!parsedRoom.networkId.length || ![[MultiplayerManager sharedManager] isValidNetworkId:parsedRoom.networkId]) {
            [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.guest.error_title", @"代码无效")
                                          message:MPLocalized(@"mp.guest.error.invalid_network_id", @"分享代码中的 Network ID 无效")];
            return;
        }

        [strongSelf performGuestJoinWithRoom:parsedRoom shareCode:code];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

/// 房客流程：执行加入房间
///
/// @param parsedRoom 从分享代码解析出的房间对象
/// @param shareCode 原始分享代码（用于显示）
- (void)performGuestJoinWithRoom:(MultiplayerRoom *)parsedRoom shareCode:(NSString *)shareCode {
    // 标记房客流程激活
    self.isGuestFlowActive = YES;
    self.lastShareCode = shareCode;
    // 临时设置房主地址，连接成功后会在 showGuestConnectedAlert 中更新为端口转发地址
    self.lastServerAddress = [NSString stringWithFormat:@"%@:%@", parsedRoom.hostIP, parsedRoom.hostPort];

    // 设置房客房间对象（保存以便显示状态）
    self.guestRoom = parsedRoom;

    // 如果当前已连接到其他房间，先断开
    MultiplayerRoom *currentRoom = [[MultiplayerManager sharedManager] currentRoom];
    if (currentRoom && ![currentRoom.networkId isEqualToString:parsedRoom.networkId]) {
        [[MultiplayerManager sharedManager] disconnectCurrentRoom];
    }

    // 显示"正在连接"进度提示（可动态更新进度文本）
    //
    // 关键修复（前台无反馈）：
    // 与 hostButtonTapped 相同，使用可更新进度的 Alert 替代静态提示。
    [self showConnectionProgressWithTitle:MPLocalized(@"mp.guest.connecting_title", @"正在加入联机")
                                   message:MPLocalized(@"mp.guest.connecting_msg", @"正在连接到房主的 ZeroTier 网络，请稍候...")];

    // 连接到房间
    __weak typeof(self) weakSelf = self;
    [self connectToRoom:parsedRoom completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 关键诊断日志：记录 completion 回调时的状态，便于排查房客复制到错误地址的问题
        NSLog(@"[MultiplayerVC] connectToRoom completion 回调：success=%d, error=%@, guestRoom=%@, guestRoom.hostIP=%@, parsedRoom指针=%p, guestRoom指针=%p, 是否同一对象=%d",
              success,
              error.localizedDescription,
              strongSelf.guestRoom,
              strongSelf.guestRoom.hostIP,
              parsedRoom,
              strongSelf.guestRoom,
              (parsedRoom == strongSelf.guestRoom));

        // 先关闭进度提示 Alert，再显示结果
        [strongSelf dismissConnectionProgressAlertWithCompletion:^{
            if (success) {
                // 连接成功：显示房客加入成功提示
                [strongSelf showGuestConnectedAlert];
            } else {
                // 连接失败
                strongSelf.isGuestFlowActive = NO;
                [strongSelf showSimpleAlertWithTitle:MPLocalized(@"mp.connect.failed", @"连接失败")
                                              message:error.localizedDescription ?: MPLocalized(@"mp.connect.failed_msg", @"无法连接到房主的网络，请检查分享代码是否正确以及网络是否畅通。")];
            }
        }];
        [strongSelf.tableView reloadData];
    }];

    [self.tableView reloadData];
}

/// 显示房客连接成功后的提示
///
/// 对标 FCL 房客加入成功后的引导：
///   - "已连接到房主的联机网络"
///   - 自动将服务器地址写入当前 profile（下次启动 MC 自动连接）
///   - 自动将服务器地址复制到剪贴板（方便在 MC 中粘贴）
///   - 显示操作引导和服务器地址
///
/// 由于我们使用进程内 libzt（不创建系统网络接口），MC 的 UDP 局域网广播
/// 无法通过 ZeroTier 网络，因此"自动发现房间"不可行。替代方案是：
///   1. 自动写入 profile 的 serverIp（下次启动 MC 时自动连接）
///   2. 自动复制服务器地址到剪贴板（方便房客在 MC 中"添加服务器"时粘贴）
///   3. 显示清晰的操作引导
- (void)showGuestConnectedAlert {
    MultiplayerRoom *room = self.guestRoom;
    // 关键诊断日志：记录 guestRoom 的完整状态，便于排查房客复制到错误地址的问题
    NSLog(@"[MultiplayerVC] showGuestConnectedAlert 诊断：guestRoom=%@, currentLocalIP=%@, currentForwardingPort=%u, PortForwarder.isRunning=%d, PortForwarder.listeningPort=%u",
          room,
          [[MultiplayerManager sharedManager] currentLocalIP],
          [[MultiplayerManager sharedManager] currentForwardingPort],
          [[PortForwarder sharedForwarder] isRunning],
          [[PortForwarder sharedForwarder] listeningPort]);
    NSString *hostIP = room.hostIP.length ? room.hostIP : ([[MultiplayerManager sharedManager] currentLocalIP] ?: @"-");
    NSString *hostPort = room.hostPort.length ? room.hostPort : @"25565";

    // 关键修复：MC 使用 Netty 的 NioSocketChannel，不走 Java 的 SOCKS5 代理。
    // 房客不能直接输入房主的 ZeroTier IP（系统无法路由），必须通过本地端口转发器。
    // PortForwarder 在 127.0.0.1:25565（或下一个可用端口）监听，转发到房主的 ZeroTier IP:端口。
    // 房客在 MC 中输入 127.0.0.1:转发端口 即可连接。
    //
    // 关键修复（房客复制到 10. 开头地址而非 127.0.0.1）：
    // 之前的 bug：如果 currentForwardingPort == 0（例如 PortForwarder 启动失败，
    // 或者 disconnectCurrentRoom 清除了 currentForwardingPort 但 PortForwarder 仍在运行），
    // showGuestConnectedAlert 会回退到 hostIP:hostPort（10. 开头的房主 ZeroTier IP）。
    // 房客在 MC 中输入 10.x.x.x:25565 时系统无法路由，显示"无法加入服务器"。
    //
    // 修复方案：如果 currentForwardingPort == 0，检查 PortForwarder 单例是否在运行，
    // 如果在运行则使用其 listeningPort 作为转发端口。这样即使 currentForwardingPort
    // 因时序问题未被设置，也能从 PortForwarder 实例获取正确的端口。
    uint16_t forwardPort = [[MultiplayerManager sharedManager] currentForwardingPort];
    if (forwardPort == 0 && [[PortForwarder sharedForwarder] isRunning]) {
        // fallback：currentForwardingPort 未设置，但 PortForwarder 实例在运行
        forwardPort = [[PortForwarder sharedForwarder] listeningPort];
        NSLog(@"[MultiplayerVC] currentForwardingPort 为 0，从 PortForwarder 实例获取 listeningPort: %u", forwardPort);
    }
    NSString *serverAddress;
    if (forwardPort > 0) {
        // 端口转发器已启动，使用本地地址
        serverAddress = [NSString stringWithFormat:@"127.0.0.1:%u", forwardPort];
        NSLog(@"[MultiplayerVC] 房客使用端口转发地址：%@（转发到 %@:%@）",
              serverAddress, hostIP, hostPort);
    } else {
        // 端口转发器未启动（回退到直连，可能失败）
        serverAddress = [NSString stringWithFormat:@"%@:%@", hostIP, hostPort];
        NSLog(@"[MultiplayerVC] 警告：端口转发器未启动，房客直连 %@（可能无法连接）",
              serverAddress);
    }
    self.lastServerAddress = serverAddress;

    // 自动将服务器地址写入当前 profile（下次启动 MC 时会自动连接到此服务器）
    NSString *profileName = [PLProfiles current].selectedProfileName;
    if (profileName && profileName.length > 0) {
        [[PLProfiles current] setServerIp:serverAddress forProfile:profileName];
        NSLog(@"[Multiplayer] 已自动将服务器地址 %@ 写入 profile %@", serverAddress, profileName);
    }

    // 自动复制服务器地址到剪贴板（方便房客在 MC 中"添加服务器"时直接粘贴）
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = serverAddress;

    // 构建提示信息
    NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n%@\n\n%@: %@\n\n%@",
                         MPLocalized(@"mp.guest.connected_msg", @"已连接到房主的联机网络"),
                         MPLocalized(@"mp.guest.tip.add_server", @"请在 MC 多人游戏界面点击「添加服务器」，粘贴以下地址即可加入"),
                         MPLocalized(@"mp.guest.tip.address_copied", @"服务器地址已自动复制到剪贴板，直接粘贴即可"),
                         MPLocalized(@"mp.guest.server_address", @"服务器地址"),
                         serverAddress,
                         MPLocalized(@"mp.guest.tip.auto_saved", @"地址已自动保存到当前配置，下次启动游戏会自动连接")];

    [self showSimpleAlertWithTitle:MPLocalized(@"mp.guest.connected_title", @"已加入联机")
                           message:message];
}

#pragma mark - MultiplayerManagerDelegate

/// ZeroTier 节点已上线：刷新房间列表与状态
- (void)multiplayerNodeOnline {
    [self refreshRooms];
    [self.tableView reloadData];
}

/// ZeroTier 节点已离线：刷新房间列表与状态
- (void)multiplayerNodeOffline {
    [self refreshRooms];
    [self.tableView reloadData];
}

/// 指定房间已连接成功：刷新房间列表与状态
- (void)multiplayerRoomConnected:(MultiplayerRoom *)room {
    [self refreshRooms];
    [self.tableView reloadData];
}

/// 指定房间连接失败：刷新房间列表与状态
- (void)multiplayerRoom:(MultiplayerRoom *)room didFailWithError:(NSError *)error {
    [self refreshRooms];
    [self.tableView reloadData];
}

/// ZeroTier 框架可用性检测结果：刷新房间列表
- (void)multiplayerFrameworkAvailabilityChecked:(BOOL)available {
    [self refreshRooms];
    [self.tableView reloadData];
}

/// 连接流程进度更新
///
/// 由 MultiplayerManager 的 notifyConnectionProgress: 在主线程调用。
/// 更新 connectionProgressAlert 的 message 属性，让用户实时看到当前连接步骤。
///
/// 关键修复（前台无反馈）：
/// 之前连接流程只显示静态"正在连接到 ZeroTier 网络"提示，
/// 用户无法知道后台进度（启动节点、等待上线、加入网络、等待就绪、启动代理...）。
/// 现在通过此回调实时更新进度文本，让用户看到详细的步骤信息。
///
/// @param message 进度描述文本（如"步骤 2/6：正在等待节点上线..."）
- (void)multiplayerConnectionProgress:(NSString *)message {
    // 此方法已在主线程调用（由 MultiplayerManager.notifyConnectionProgress: 保证）
    if (self.connectionProgressAlert) {
        // 更新已显示的进度 Alert 的 message
        // UIAlertController 的 message 属性可以在 present 后动态更新，
        // 系统会自动刷新 UI 显示，无需重新 present。
        self.connectionProgressAlert.message = message;
    }
    NSLog(@"[MultiplayerVC] 连接进度：%@", message);
}

#pragma mark - 工具方法

/// 刷新房间列表（主线程）
- (void)refreshRooms {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.rooms = [[MultiplayerManager sharedManager] savedRooms] ?: @[];
        [self.tableView reloadData];
    });
}

/// 显示简单的 Alert 提示
- (void)showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 关键修复：显示新 Alert 前清除进度 Alert 引用（如果存在）
        self.connectionProgressAlert = nil;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.ok", @"好") style:UIAlertActionStyleDefault handler:nil]];
        // 避免重复 present
        if (self.presentedViewController) {
            [self.presentedViewController dismissViewControllerAnimated:NO completion:^{
                [self presentViewController:alert animated:YES completion:nil];
            }];
        } else {
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

/// 显示连接进度 Alert（可动态更新 message）
///
/// 此 Alert 包含一个"取消"按钮，允许用户在连接过程中取消连接。
/// 取消时会调用 disconnectCurrentRoom 中止连接流程。
///
/// 显示后，通过 multiplayerConnectionProgress: 回调更新 self.connectionProgressAlert.message
/// 即可实时更新 Alert 中显示的进度文本，无需重新 present。
///
/// @param title   Alert 标题（如"正在开启联机"）
/// @param message 初始进度文本（如"正在连接到 ZeroTier 网络，请稍候..."）
- (void)showConnectionProgressWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 如果已有进度 Alert 在显示，先关闭它
        if (self.connectionProgressAlert && self.presentedViewController == self.connectionProgressAlert) {
            [self dismissViewControllerAnimated:NO completion:^{
                [self presentNewConnectionProgressAlertWithTitle:title message:message];
            }];
        } else if (self.presentedViewController) {
            // 有其他 VC 在显示（如之前的简单 Alert），先关闭
            [self.presentedViewController dismissViewControllerAnimated:NO completion:^{
                [self presentNewConnectionProgressAlertWithTitle:title message:message];
            }];
        } else {
            [self presentNewConnectionProgressAlertWithTitle:title message:message];
        }
    });
}

/// 内部方法：创建并 present 新的连接进度 Alert
- (void)presentNewConnectionProgressAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];

    // 添加"取消"按钮：用户可在连接过程中取消
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:MPLocalized(@"common.cancel", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // 用户取消连接：中止正在进行的连接流程
        NSLog(@"[MultiplayerVC] 用户取消了连接流程");
        strongSelf.isHostFlowActive = NO;
        strongSelf.isGuestFlowActive = NO;
        [[MultiplayerManager sharedManager] disconnectCurrentRoom];
        strongSelf.connectionProgressAlert = nil;
        [strongSelf.tableView reloadData];
    }]];

    self.connectionProgressAlert = alert;
    [self presentViewController:alert animated:YES completion:nil];
}

/// 关闭连接进度 Alert
///
/// 在连接完成（成功或失败）后调用，关闭进度提示 Alert，
/// 然后在 completion 中显示结果 Alert（成功提示或错误提示）。
///
/// @param completion Alert 关闭后的回调
- (void)dismissConnectionProgressAlertWithCompletion:(void (^)(void))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.connectionProgressAlert && self.presentedViewController == self.connectionProgressAlert) {
            // 进度 Alert 正在显示：关闭它，然后在 completion 中执行后续操作
            self.connectionProgressAlert = nil;
            [self dismissViewControllerAnimated:YES completion:^{
                if (completion) completion();
            }];
        } else {
            // 进度 Alert 不在显示（可能已被用户取消或未创建）：
            // 清除引用，直接执行 completion
            self.connectionProgressAlert = nil;
            if (completion) completion();
        }
    });
}

/// 生成纯色圆形小图标（用于状态指示点）
/// @param color 圆形颜色
/// @param size 圆形直径（pt）
/// @return 圆形 UIImage
- (UIImage *)circleImageWithColor:(UIColor *)color size:(CGFloat)size {
    CGRect rect = CGRectMake(0, 0, size, size);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillEllipseInRect(context, rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/// 获取房间状态对应的颜色
/// @param status 房间状态
/// @return 状态颜色（连接中=橙、已连接=绿、断开=灰、错误=红）
- (UIColor *)colorForRoomStatus:(MultiplayerRoomStatus)status {
    switch (status) {
        case MultiplayerRoomStatusDisconnected:
            return [UIColor systemGrayColor];
        case MultiplayerRoomStatusConnecting:
            return [UIColor systemOrangeColor];
        case MultiplayerRoomStatusConnected:
            return [UIColor systemGreenColor];
        case MultiplayerRoomStatusError:
            return [UIColor systemRedColor];
    }
    return [UIColor systemGrayColor];
}

/// 获取房间状态对应的本地化文本
/// @param status 房间状态
/// @return 状态文本（"未连接" / "连接中" / "已连接" / "错误"）
- (NSString *)textForRoomStatus:(MultiplayerRoomStatus)status {
    switch (status) {
        case MultiplayerRoomStatusDisconnected:
            return MPLocalized(@"mp.room.status.disconnected", @"未连接");
        case MultiplayerRoomStatusConnecting:
            return MPLocalized(@"mp.room.status.connecting", @"连接中");
        case MultiplayerRoomStatusConnected:
            return MPLocalized(@"mp.room.status.connected", @"已连接");
        case MultiplayerRoomStatusError:
            return MPLocalized(@"mp.room.status.error", @"错误");
    }
    return @"";
}

/// 创建房间行的连接/断开按钮
///
/// 按钮样式：圆角矩形，宽 64pt 高 32pt
/// - 已连接：显示"断开"，红色背景
/// - 连接中：显示"连接中"，灰色背景，禁用点击
/// - 其他：显示"连接"，蓝色背景
///
/// @param room 房间对象
/// @return 配置好的按钮
- (UIButton *)makeActionButtonForRoom:(MultiplayerRoom *)room {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 64, 32);
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 8;
    button.layer.masksToBounds = YES;

    NSString *title;
    UIColor *bgColor;

    if (room.status == MultiplayerRoomStatusConnected) {
        title = MPLocalized(@"mp.room.button.disconnect", @"断开");
        bgColor = [UIColor systemRedColor];
        button.enabled = YES;
    } else if (room.status == MultiplayerRoomStatusConnecting) {
        title = MPLocalized(@"mp.room.button.connecting", @"连接中");
        bgColor = [UIColor systemGrayColor];
        button.enabled = NO;
    } else {
        title = MPLocalized(@"mp.room.button.connect", @"连接");
        bgColor = [UIColor systemBlueColor];
        button.enabled = YES;
    }

    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = bgColor;

    return button;
}

#pragma mark - UITextFieldDelegate

/// 点击 Return 键时收起键盘
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.directIPField) {
        // 在 IP 输入框按 Return 切换到端口输入框
        [self.directPortField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

#pragma mark - UITableViewDataSource

/// Section 数量：根据模式返回
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.mode == MultiplayerVCModeInGame) {
        // 游戏内模式：选择角色 + 联机状态
        return 2;
    }
    // 启动器模式：联机设置 + 我的房间 + 直连
    return 3;
}

/// 每个 Section 的行数：根据模式和 Section 返回
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.mode == MultiplayerVCModeInGame) {
        switch (section) {
            case 0:
                // 选择角色：当房主 + 当房客
                return 2;
            case 1:
                // 联机状态：1 行综合状态
                return 1;
            default:
                return 0;
        }
    }
    // 启动器模式
    switch (section) {
        case 0:
            // 联机设置：启用联机开关 + Network ID + ZeroTier 创建教程
            return 3;
        case 1:
            // 我的房间：至少 1 行（空状态提示）
            return MAX(1, (NSInteger)self.rooms.count);
        case 2:
            // 直连：IP+端口输入 + 加入游戏按钮
            return 2;
        default:
            return 0;
    }
}

/// Section 标题：根据模式返回
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.mode == MultiplayerVCModeInGame) {
        switch (section) {
            case 0:
                return MPLocalized(@"mp.ingame.section.role", @"选择角色");
            case 1:
                return MPLocalized(@"mp.ingame.section.status", @"联机状态");
            default:
                return nil;
        }
    }
    switch (section) {
        case 0:
            return MPLocalized(@"mp.section.settings", @"联机设置");
        case 1:
            return MPLocalized(@"mp.section.rooms", @"我的房间");
        case 2:
            return MPLocalized(@"mp.section.direct", @"直连");
        default:
            return nil;
    }
}

/// Section 脚注：根据模式返回
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.mode == MultiplayerVCModeInGame) {
        switch (section) {
            case 0:
                return MPLocalized(@"mp.ingame.section.role_footer", @"房主需在 MC 中开放局域网，房客输入分享代码即可加入");
            case 1:
                return MPLocalized(@"mp.ingame.section.status_footer", @"显示当前联机网络的状态信息");
            default:
                return nil;
        }
    }
    switch (section) {
        case 0:
            return MPLocalized(@"mp.section.settings_footer", @"启用联机后可设置 Network ID，房主开房时自动使用");
        case 2:
            return MPLocalized(@"mp.section.direct_footer", @"输入服务器 IP 和端口，写入当前 profile，启动游戏后自动加入");
        default:
            return nil;
    }
}

/// 根据 IndexPath 配置对应的 cell
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mode == MultiplayerVCModeInGame) {
        return [self cellForInGameSection:indexPath];
    }
    return [self cellForLauncherSection:indexPath];
}

#pragma mark - 启动器模式 Cell 配置

/// 启动器模式 cell 配置分发
- (UITableViewCell *)cellForLauncherSection:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return [self cellForSettingsSectionAtRow:indexPath.row];
        case 1:
            return [self cellForRoomsSectionAtRow:indexPath.row];
        case 2:
            return [self cellForDirectSectionAtRow:indexPath.row];
        default:
            return [UITableViewCell new];
    }
}

/// Section 0「联机设置」的 cell 配置
/// @param row 行号（0=启用联机开关，1=预设 Network ID，2=ZeroTier 创建教程）
- (UITableViewCell *)cellForSettingsSectionAtRow:(NSInteger)row {
    if (row == 2) {
        // ZeroTier 网络创建教程入口
        return [self cellForGuideSection];
    }
    if (row == 0) {
        // 启用联机开关行
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"SwitchCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = MPLocalized(@"mp.settings.enable_multiplayer", @"启用联机");
        cell.textLabel.font = [UIFont systemFontOfSize:16];

        // 懒初始化 UISwitch
        if (!self.enableSwitch) {
            self.enableSwitch = [[UISwitch alloc] init];
            [self.enableSwitch addTarget:self action:@selector(enableSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        }
        // 初始状态：根据持久化的用户意图设置开关（与 viewWillAppear: 保持一致）
        BOOL enabled = [[MultiplayerManager sharedManager] isMultiplayerEnabled];
        [self.enableSwitch setOn:enabled animated:NO];
        cell.accessoryView = self.enableSwitch;

        // 辅助文字：显示节点的实际运行状态（而非用户意图）
        BOOL started = [[MultiplayerManager sharedManager] isNodeStarted];
        if (started) {
            if ([[MultiplayerManager sharedManager] isNodeOnline]) {
                cell.detailTextLabel.text = MPLocalized(@"mp.settings.node_online", @"节点已上线");
            } else {
                cell.detailTextLabel.text = MPLocalized(@"mp.settings.node_starting", @"节点启动中...");
            }
        } else {
            // 节点未启动：如果用户已启用（等待自动重启），显示"启动中"
            if (enabled) {
                cell.detailTextLabel.text = MPLocalized(@"mp.settings.node_starting", @"节点启动中...");
            } else {
                cell.detailTextLabel.text = MPLocalized(@"mp.settings.node_offline", @"节点未启动");
            }
        }
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

        // 适配自定义背景
        if ([[BackgroundManager sharedManager] hasBackground]) {
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.detailTextLabel.textColor = [UIColor whiteColor];
        } else {
            cell.textLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }

        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        return cell;
    } else {
        // 预设 Network ID 行
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"NetworkIdCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = MPLocalized(@"mp.settings.preset_network_id", @"预设 Network ID");
        cell.textLabel.font = [UIFont systemFontOfSize:16];

        // 显示当前预设的 Network ID（脱敏显示：前 4 + ... + 后 4）
        NSString *presetNetId = [[MultiplayerManager sharedManager] presetNetworkId];
        NSString *displayValue;
        if (presetNetId.length >= 16) {
            displayValue = [NSString stringWithFormat:@"%@...%@",
                            [presetNetId substringToIndex:4],
                            [presetNetId substringFromIndex:presetNetId.length - 4]];
        } else if (presetNetId.length > 0) {
            displayValue = presetNetId;
        } else {
            displayValue = MPLocalized(@"mp.settings.not_set", @"未设置");
        }

        // 使用 detailTextLabel 显示值
        cell.detailTextLabel.text = displayValue;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.numberOfLines = 1;
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.7;

        // 右侧显示编辑图标
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        // 适配自定义背景
        if ([[BackgroundManager sharedManager] hasBackground]) {
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.detailTextLabel.textColor = [UIColor whiteColor];
        } else {
            cell.textLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }

        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        return cell;
    }
}

/// Section 0「联机设置」的教程入口 cell（row == 2）
///
/// 对标 FCL 的"联机帮助"入口：引导房主完成 ZeroTier 网络的创建和配置。
/// 点击后弹出详细的图文教程，包含注册账号、创建网络、获取 Network ID、
/// 设置网络可见性等步骤，并提供"打开 central.zerotier.com"快捷按钮。
- (UITableViewCell *)cellForGuideSection {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DefaultCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.text = MPLocalized(@"mp.settings.zt_guide", @"ZeroTier 网络创建教程");
    cell.textLabel.font = [UIFont systemFontOfSize:16];

    // 左侧图标：问号圆圈
    cell.imageView.image = [UIImage systemImageNamed:@"questionmark.circle"];
    cell.imageView.tintColor = [UIColor systemBlueColor];

    // 右侧箭头
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // 辅助文字：简短说明
    cell.detailTextLabel.text = MPLocalized(@"mp.settings.zt_guide_desc", @"不知道怎么创建网络？点这里");
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    // 适配自定义背景
    if ([[BackgroundManager sharedManager] hasBackground]) {
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    return cell;
}

/// Section 1「我的房间」的 cell 配置
/// @param row 行号
- (UITableViewCell *)cellForRoomsSectionAtRow:(NSInteger)row {
    // 空状态：显示提示文字
    if (self.rooms.count == 0) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"EmptyCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = MPLocalized(@"mp.rooms.empty", @"暂无房间（房间仅在本次会话中保留）");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        // 适配自定义背景
        if ([[BackgroundManager sharedManager] hasBackground]) {
            cell.textLabel.textColor = [UIColor whiteColor];
        } else {
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
        }
        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        return cell;
    }

    // 有房间：使用 subtitle 风格的标准 UITableViewCell
    MultiplayerRoom *room = self.rooms[row];
    // 不注册 RoomCell，使用 dequeueReusableCellWithIdentifier: 手工创建 subtitle 风格的 cell
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"RoomCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RoomCell"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    // 房间名
    cell.textLabel.text = room.name.length ? room.name : MPLocalized(@"mp.room.unnamed", @"未命名房间");
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    // 详情：Network ID + 状态 + 服务器地址（已连接时显示完整地址方便分享）
    NSString *statusText = [self textForRoomStatus:room.status];
    NSMutableString *detail = [NSMutableString string];
    [detail appendFormat:@"%@: %@",
        MPLocalized(@"mp.room.network_id", @"Network ID"),
        room.networkId ?: @"-"];
    [detail appendFormat:@"\n%@", statusText];
    if (room.status == MultiplayerRoomStatusConnected) {
        // 已连接时显示完整服务器地址
        NSString *hostIP = room.hostIP.length ? room.hostIP : [[MultiplayerManager sharedManager] currentLocalIP];
        NSString *hostPort = room.hostPort.length ? room.hostPort : @"25565";
        if (hostIP.length) {
            [detail appendFormat:@"\n%@: %@:%@",
                MPLocalized(@"mp.room.server_address", @"服务器地址"),
                hostIP, hostPort];
        }
    }
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.numberOfLines = 0;

    // 状态指示点（imageView 显示彩色小圆点）
    UIColor *statusColor = [self colorForRoomStatus:room.status];
    UIImage *dotImage = [self circleImageWithColor:statusColor size:10];
    cell.imageView.image = dotImage;

    // 连接 / 断开按钮（accessoryView）
    UIButton *actionButton = [self makeActionButtonForRoom:room];
    [actionButton addTarget:self action:@selector(roomButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    actionButton.tag = row;
    cell.accessoryView = actionButton;

    // 适配自定义背景
    if ([[BackgroundManager sharedManager] hasBackground]) {
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    return cell;
}

/// Section 2「直连」的 cell 配置
/// @param row 行号（0=IP+端口输入，1=加入游戏按钮）
- (UITableViewCell *)cellForDirectSectionAtRow:(NSInteger)row {
    if (row == 0) {
        // IP + 端口输入行
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DirectInputCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        // 懒初始化 IP 输入框
        if (!self.directIPField) {
            self.directIPField = [[UITextField alloc] init];
            self.directIPField.placeholder = MPLocalized(@"mp.direct.ip_placeholder", @"服务器 IP");
            self.directIPField.font = [UIFont systemFontOfSize:15];
            self.directIPField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.directIPField.autocorrectionType = UITextAutocorrectionTypeNo;
            self.directIPField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            self.directIPField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.directIPField.returnKeyType = UIReturnKeyNext;
            self.directIPField.delegate = self;
            self.directIPField.translatesAutoresizingMaskIntoConstraints = NO;
        }

        // 懒初始化端口输入框
        if (!self.directPortField) {
            self.directPortField = [[UITextField alloc] init];
            self.directPortField.placeholder = @"25565";
            self.directPortField.font = [UIFont systemFontOfSize:15];
            self.directPortField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.directPortField.autocorrectionType = UITextAutocorrectionTypeNo;
            self.directPortField.keyboardType = UIKeyboardTypeNumberPad;
            self.directPortField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.directPortField.returnKeyType = UIReturnKeyDone;
            self.directPortField.delegate = self;
            self.directPortField.translatesAutoresizingMaskIntoConstraints = NO;
        }

        // 懒初始化冒号分隔标签
        UILabel *colonLabel = (UILabel *)[cell.contentView viewWithTag:9528];
        if (!colonLabel) {
            colonLabel = [[UILabel alloc] init];
            colonLabel.tag = 9528;
            colonLabel.text = @":";
            colonLabel.font = [UIFont systemFontOfSize:15];
            colonLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:colonLabel];
        }

        // 如果 textField 已在别的 cell 上（cell 复用场景），先移除
        if (self.directIPField.superview && self.directIPField.superview != cell.contentView) {
            [self.directIPField removeFromSuperview];
        }
        if (self.directPortField.superview && self.directPortField.superview != cell.contentView) {
            [self.directPortField removeFromSuperview];
        }

        BOOL needsNewConstraints = NO;
        if (!self.directIPField.superview) {
            [cell.contentView addSubview:self.directIPField];
            needsNewConstraints = YES;
        }
        if (!self.directPortField.superview) {
            [cell.contentView addSubview:self.directPortField];
            needsNewConstraints = YES;
        }

        // 仅在 textField 首次添加到 cell 时设置约束（避免重复激活导致冲突）
        if (needsNewConstraints) {
            [NSLayoutConstraint activateConstraints:@[
                [self.directIPField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [self.directIPField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
                [self.directIPField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
                [self.directIPField.trailingAnchor constraintEqualToAnchor:colonLabel.leadingAnchor constant:-4],

                [colonLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [colonLabel.widthAnchor constraintEqualToConstant:8],

                [self.directPortField.leadingAnchor constraintEqualToAnchor:colonLabel.trailingAnchor constant:4],
                [self.directPortField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [self.directPortField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [self.directPortField.widthAnchor constraintEqualToConstant:80],
            ]];
        }

        // 适配自定义背景
        BOOL hasBackground = [[BackgroundManager sharedManager] hasBackground];
        if (hasBackground) {
            self.directIPField.textColor = [UIColor whiteColor];
            self.directPortField.textColor = [UIColor whiteColor];
            colonLabel.textColor = [UIColor whiteColor];
        } else {
            self.directIPField.textColor = [UIColor labelColor];
            self.directPortField.textColor = [UIColor labelColor];
            colonLabel.textColor = [UIColor labelColor];
        }

        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        return cell;
    } else {
        // 加入游戏按钮行
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = MPLocalized(@"mp.direct.join_button", @"加入游戏");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        // 适配自定义背景
        if ([[BackgroundManager sharedManager] hasBackground]) {
            cell.textLabel.textColor = [UIColor whiteColor];
        } else {
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
        [[BackgroundManager sharedManager] applyEffectToCell:cell];
        return cell;
    }
}

#pragma mark - 游戏内模式 Cell 配置

/// 游戏内模式 cell 配置分发
- (UITableViewCell *)cellForInGameSection:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return [self cellForRoleSectionAtRow:indexPath.row];
        case 1:
            return [self cellForInGameStatusSection];
        default:
            return [UITableViewCell new];
    }
}

/// Section 0「选择角色」的 cell 配置
/// @param row 行号（0=当房主，1=当房客）
- (UITableViewCell *)cellForRoleSectionAtRow:(NSInteger)row {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"RoleCardCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // 自定义卡片式布局：左侧大图标 + 右侧标题和说明
    if (row == 0) {
        // 当房主
        cell.imageView.image = [UIImage systemImageNamed:@"crown"];
        cell.imageView.tintColor = [UIColor systemOrangeColor];
        cell.textLabel.text = MPLocalized(@"mp.ingame.host_title", @"当房主");
        cell.textLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = MPLocalized(@"mp.ingame.host_desc", @"创建联机房间，开放局域网后生成分享代码");
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.detailTextLabel.numberOfLines = 0;

        // 房主流程激活时显示状态指示
        if (self.isHostFlowActive) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        // 当房客
        cell.imageView.image = [UIImage systemImageNamed:@"person.2"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.textLabel.text = MPLocalized(@"mp.ingame.guest_title", @"当房客");
        cell.textLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = MPLocalized(@"mp.ingame.guest_desc", @"输入分享代码，加入房主的联机网络");
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.detailTextLabel.numberOfLines = 0;

        // 房客流程激活时显示状态指示
        if (self.isGuestFlowActive) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }

    // 适配自定义背景
    if ([[BackgroundManager sharedManager] hasBackground]) {
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    return cell;
}

/// Section 1「联机状态」的 cell 配置
///
/// 综合显示：
///   - 当前联机状态（已连接/未连接）
///   - Network ID
///   - 本地 IP
///   - 房主流程：分享代码
///   - 房客流程：服务器地址
- (UITableViewCell *)cellForInGameStatusSection {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StatusCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    MultiplayerManager *manager = [MultiplayerManager sharedManager];
    MultiplayerRoom *currentRoom = manager.currentRoom;
    BOOL connected = (currentRoom != nil) && (currentRoom.status == MultiplayerRoomStatusConnected);

    // 标题：联机状态
    cell.textLabel.text = connected ? MPLocalized(@"mp.ingame.status.connected", @"已连接") : MPLocalized(@"mp.ingame.status.disconnected", @"未连接");
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

    // 详情：Network ID + 本地 IP + （房主）分享代码 / （房客）服务器地址
    NSMutableString *detail = [NSMutableString string];

    // 状态指示
    if (self.isHostFlowActive) {
        [detail appendString:MPLocalized(@"mp.ingame.status.host_mode", @"房主模式")];
    } else if (self.isGuestFlowActive) {
        [detail appendString:MPLocalized(@"mp.ingame.status.guest_mode", @"房客模式")];
    } else {
        [detail appendString:MPLocalized(@"mp.ingame.status.idle", @"未开始")];
    }

    // Network ID
    NSString *networkId = currentRoom.networkId.length ? currentRoom.networkId : [manager presetNetworkId];
    if (networkId.length) {
        [detail appendFormat:@"\n%@: %@", MPLocalized(@"mp.ingame.status.network_id", @"Network ID"), networkId];
    } else {
        [detail appendFormat:@"\n%@: %@", MPLocalized(@"mp.ingame.status.network_id", @"Network ID"), MPLocalized(@"mp.settings.not_set", @"未设置")];
    }

    // 本地 IP
    NSString *localIP = manager.currentLocalIP;
    if (localIP.length) {
        [detail appendFormat:@"\n%@: %@", MPLocalized(@"mp.ingame.status.local_ip", @"本地 IP"), localIP];
    }

    // 房主流程：显示分享代码
    if (self.isHostFlowActive && self.lastShareCode.length) {
        [detail appendFormat:@"\n%@: %@",
            MPLocalized(@"mp.ingame.status.share_code", @"分享代码"),
            self.lastShareCode];
    }

    // 房客流程：显示服务器地址
    if (self.isGuestFlowActive && self.lastServerAddress.length) {
        [detail appendFormat:@"\n%@: %@",
            MPLocalized(@"mp.ingame.status.server_address", @"服务器地址"),
            self.lastServerAddress];
    }

    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.numberOfLines = 0;

    // 状态指示点
    UIColor *statusColor = connected ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
    UIImage *dotImage = [self circleImageWithColor:statusColor size:10];
    cell.imageView.image = dotImage;

    // 适配自定义背景
    if ([[BackgroundManager sharedManager] hasBackground]) {
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    return cell;
}

#pragma mark - UITableViewDelegate

/// 点击行回调：根据模式和 Section 分发
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.mode == MultiplayerVCModeInGame) {
        [self handleInGameSelectionAtIndexPath:indexPath];
        return;
    }
    [self handleLauncherSelectionAtIndexPath:indexPath];
}

/// 启动器模式点击处理
- (void)handleLauncherSelectionAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            if (indexPath.row == 0) {
                // 点击开关行：让开关获得焦点（切换开关状态）
                // 不做处理，开关自身会响应
            } else if (indexPath.row == 1) {
                // 点击 Network ID 行：弹出编辑对话框
                [self networkIdCellTapped];
            } else if (indexPath.row == 2) {
                // 点击教程入口：弹出 ZeroTier 网络创建教程
                [self showZeroTierGuide];
            }
            break;
        case 1:
            if (self.rooms.count == 0) {
                // 空状态：提示用户先设置 Network ID 或直接加入房间
                [self showSimpleAlertWithTitle:MPLocalized(@"mp.rooms.empty_title", @"暂无房间")
                                         message:MPLocalized(@"mp.rooms.empty_msg", @"请先在 Section 0 设置 Network ID，然后在游戏内模式中选择当房主或房客")];
            } else {
                // 点击房间行：弹出 ActionSheet
                MultiplayerRoom *room = self.rooms[indexPath.row];
                [self showRoomActionsForRoom:room];
            }
            break;
        case 2:
            if (indexPath.row == 0) {
                // 点击直连输入行：让 IP 输入框获得焦点
                [self.directIPField becomeFirstResponder];
            } else if (indexPath.row == 1) {
                // 点击加入游戏按钮
                [self joinDirectConnect];
            }
            break;
        default:
            break;
    }
}

/// 游戏内模式点击处理
- (void)handleInGameSelectionAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            if (indexPath.row == 0) {
                // 当房主
                [self hostButtonTapped];
            } else if (indexPath.row == 1) {
                // 当房客
                [self guestButtonTapped];
            }
            break;
        case 1:
            // 联机状态行：无操作（仅显示信息）
            // 房主流程激活时点击可重新显示分享代码
            if (self.isHostFlowActive && self.lastShareCode.length) {
                [self showHostShareCodeAlert];
            }
            break;
        default:
            break;
    }
}

/// 行高：根据模式和 IndexPath 返回
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mode == MultiplayerVCModeInGame) {
        if (indexPath.section == 0) {
            // 选择角色卡片行：大卡片样式，更高
            return 76;
        }
        if (indexPath.section == 1) {
            // 联机状态行：动态高度（多行详情）
            return UITableViewAutomaticDimension;
        }
        return 56;
    }
    // 启动器模式
    if (indexPath.section == 0) {
        // 联机设置行
        return 56;
    }
    if (indexPath.section == 1) {
        if (self.rooms.count == 0) {
            // 空状态提示行
            return 60;
        }
        // 房间行：subtitle 显示 2-3 行，需要更多空间
        return 76;
    }
    if (indexPath.section == 2) {
        // IP+端口输入行 / 加入按钮行
        return 48;
    }
    return UITableViewAutomaticDimension;
}

@end
