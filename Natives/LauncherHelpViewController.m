#import "LauncherHelpViewController.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"

// ============================================================================
// Task 82：启动器"使用问题"（FAQ）页面
//
// 左侧边栏新增"使用问题"标签，收录项目迭代中反复出现的用户问题与结论
// （每条都来自真实日志判读，非泛泛帮助文案）。语言跟随本 fork 的 AI 模块
// 先例：直接使用中文（用户主语言），不做 54 语言 l10n。
//
// 交互：按分类分组，点击问题行展开/收起答案，同一时刻允许多条同时展开。
// ============================================================================

@interface LauncherHelpFaqItem : NSObject
@property (nonatomic, copy) NSString *question;
@property (nonatomic, copy) NSString *answer;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation LauncherHelpFaqItem
@end

@interface LauncherHelpViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSArray<NSArray<LauncherHelpFaqItem *> *> *itemsByCategory;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *expandedPaths;
@end

@implementation LauncherHelpViewController

#pragma mark - Data

- (void)buildFaqData {
    // 每条目均为项目 worklog 中定案的真实结论（Task 68-82）。
    LauncherHelpFaqItem *renderer = [[LauncherHelpFaqItem alloc] init];
    renderer.iconName = @"cpu";
    renderer.question = @"渲染器应该怎么选？";
    renderer.answer = @"渲染器在 设置 → Java → 渲染器 中选择（游戏未运行时才能改）：\n\n"
                      @"• Zink：基于 Vulkan（MoltenVK），适合 26.x 新版本和装了模组的场景，区块加载更流畅。\n"
                      @"• MobileGlues：兼容性好，适合轻量场景和老版本；加载区块时每帧转译开销较大，会感到卡顿（安卓设备同样如此，属已知特性，不是你的设备问题）。\n"
                      @"• 自动：由启动器按版本自动选择。\n\n"
                      @"简单记法：玩新版本/整合包用 Zink，怀旧老版本用 MobileGlues。";

    LauncherHelpFaqItem *xray = [[LauncherHelpFaqItem alloc] init];
    xray.iconName = @"eye.fill";
    xray.question = @"方块、实体、云层出现\"透视/穿透\"怎么办？";
    xray.answer = @"这通常是 Sodium 模组的\"改进透明\"选项与渲染器之间的兼容性问题，不是启动器或存档坏了。\n\n"
                  @"解决方法：游戏内打开 视频设置 → Sodium → 找到\"改进透明\"（Improve transparency / 半透明排序）并关闭，穿透即消失。\n\n"
                  @"此问题与渲染器类型无关，换 Zink 或 MobileGlues 都可能遇到，关闭该选项即可。";

    LauncherHelpFaqItem *mgLag = [[LauncherHelpFaqItem alloc] init];
    mgLag.iconName = @"speedometer";
    mgLag.question = @"MobileGlues 加载区块时卡顿正常吗？";
    mgLag.answer = @"正常（已知特性）。MobileGlues 是 OpenGL → Metal 的转译层，26.x 新区块管线对它压力较大：同视距下转译调用量约为老版本的 3 倍，移动时帧率会明显下降；安卓设备跑 MobileGlues 同样卡顿。\n\n"
                   @"缓解办法：\n"
                   @"1. 换 Zink 渲染器（推荐，见上条）；\n"
                   @"2. 开启 FSR 超分辨率降低渲染分辨率（见下条）；\n"
                   @"3. 视距保持 10 左右即可，调大只会放大加载风暴。\n\n"
                   @"已排除的因素：GC、内存容量、GPU 性能都不是该卡顿的原因，单纯加大内存分配不会治愈它。";

    LauncherHelpFaqItem *fsr = [[LauncherHelpFaqItem alloc] init];
    fsr.iconName = @"square.grid.3x2";
    fsr.question = @"FSR 超分辨率怎么用？为什么以前开了黑屏/画面缩小？";
    fsr.answer = @"FSR 1.0 在 设置 → MobileGlues 渲染器 → FSR 1.0 超分辨率 中选择档位（超高品质 77%／高品质 67%／均衡 59%／性能优先 50%）：开启后游戏自动以低分辨率渲染，再由 FSR 放大回全屏，帧率明显提升、画质轻微下降。\n\n"
                 @"注意：\n"
                 @"1. 分辨率滑条保持 100% 即可，不需要再手动降低分辨率（那反而会二次缩放）；\n"
                 @"2. 该设置仅对 MobileGlues 渲染器有效；\n"
                 @"3. 早期版本的\"开启后黑屏\"\"画面缩在左下角\"已分别修复（着色器降级修复 + 渲染视口识别修复），如仍出现请上传日志反馈。";

    LauncherHelpFaqItem *keyboard = [[LauncherHelpFaqItem alloc] init];
    keyboard.iconName = @"keyboard";
    keyboard.question = @"游戏里怎么打字（聊天、命令）？";
    keyboard.answer = @"两种方式呼出系统键盘：\n\n"
                      @"1. 点按控件布局左上角的 Keyboard 按钮（再点一次收起）；\n"
                      @"2. 双指长按屏幕（需先在 设置 → 控制 → 双指呼出键盘 中开启）。\n\n"
                      @"26.3 等新版本（SDL3 输入路径）的打字无效问题已修复；如果键盘弹出但游戏里没反应，请确认聊天框已打开（点 Chat 按钮或按 T），再上传日志反馈。";

    LauncherHelpFaqItem *joystick = [[LauncherHelpFaqItem alloc] init];
    joystick.iconName = @"gamecontroller";
    joystick.question = @"摇杆推了没反应 / 必须按住 Shift 才能动？";
    joystick.answer = @"这类问题在新版本中已系统性修复（虚拟按键状态直写 + 键位档自动纠错 + 摇杆心跳重发），正常情况下推杆即走。\n\n"
                      @"如果仍遇到：\n"
                      @"1. 检查 设置 → 控制 → 默认控件方案 是否为\"custom\"（自定义布局）；\n"
                      @"2. 检查游戏内 按键绑定 是否被改坏（恢复默认即可）；\n"
                      @"3. 升级到最新构建后再试一次——旧构建的输入修复不完整。";

    LauncherHelpFaqItem *memory = [[LauncherHelpFaqItem alloc] init];
    memory.iconName = @"internaldrive";
    memory.question = @"内存分配和性能有哪些建议？";
    memory.answer = @"• 8GB 设备：建议 4GB 左右（默认自动分配已按 50% 物理内存上调）；\n"
                    @"• 视距：10 是性价比最高的档位，调大主要增加加载风暴时长和内存占用；\n"
                    @"• 渲染分辨率：优先用 FSR 档位降分辨率，而不是手动调分辨率滑条；\n"
                    @"• 卡顿时先看是\"加载区块卡\"（换 Zink / 开 FSR）还是\"整体帧率低\"（降视距/分辨率），对症下药。";

    LauncherHelpFaqItem *modpack = [[LauncherHelpFaqItem alloc] init];
    modpack.iconName = @"shippingbox";
    modpack.question = @"安装整合包提示\"缺少父版本 JSON / json 丢失\"？";
    modpack.answer = @"新版已支持自动补拉：整合包安装过程中父版本 JSON 缺失或损坏时，启动器会自动从 Mojang 官方源与 BMCLAPI 镜像双源补拉，通常无需手动预装原版。\n\n"
                     @"如果仍失败：\n"
                      @"1. 检查网络（两个源都不通才会报错）；\n"
                      @"2. 也可先在下载页手动安装对应原版版本再装整合包；\n"
                      @"3. 重试前完全退出启动器再打开。";

    LauncherHelpFaqItem *crash = [[LauncherHelpFaqItem alloc] init];
    crash.iconName = @"exclamationmark.triangle";
    crash.question = @"遇到崩溃/黑屏该怎么反馈？";
    crash.answer = @"最有价值的是日志文件 latestlog.txt（位于启动器沙盒 Documents 目录，游戏内也可通过菜单查看）：每次游戏会话结束后它会自动保留，把它连同以下信息一起反馈即可：\n\n"
                   @"1. 设备型号与系统版本（如 iPad Air M4 / iPadOS 26.6）；\n"
                   @"2. 游戏版本与模组列表（如 26.3 + Sodium）；\n"
                   @"3. 渲染器与 FSR 设置；\n"
                   @"4. 问题发生的时机（进世界时/游玩中/暂停回来时）。\n\n"
                   @"大多数问题可以只靠日志定位，不需要录屏。";

    LauncherHelpFaqItem *data = [[LauncherHelpFaqItem alloc] init];
    data.iconName = @"folder";
    data.question = @"启动器的数据（存档、模组、布局）存在哪里？";
    data.answer = @"全部在应用沙盒 Documents 目录（POJAV_HOME）下：\n\n"
                  @"• versions/：游戏版本与隔离的模组/配置；\n"
                  @"• saves/：存档；\n"
                  @"• controlmap/：自定义控件布局（default.json 为默认布局，可在 设置 → 键位调整 里编辑）；\n"
                  @"• MG/：MobileGlues 渲染器配置（config.json，含 FSR 档位）。\n\n"
                  @"卸载重装启动器会清空这些数据，重要存档请先备份。";

    self.categories = @[ @"渲染与性能", @"输入与控制", @"安装与数据", @"故障排除" ];
    self.itemsByCategory = @[
        @[ renderer, mgLag, fsr ],
        @[ keyboard, joystick ],
        @[ modpack, data ],
        @[ xray, crash ]
    ];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"使用问题";

    // 与其他内容页一致：透出全局背景（图片/视频/毛玻璃）
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.expandedPaths = [NSMutableSet set];
    [self buildFaqData];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HelpFaqCell"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 收起大标题，保持列表可视面积
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.categories.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.categories[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.itemsByCategory[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HelpFaqCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor secondarySystemBackgroundColor];

    LauncherHelpFaqItem *item = self.itemsByCategory[indexPath.section][indexPath.row];
    BOOL expanded = [self.expandedPaths containsObject:@(indexPath.row * 1000 + indexPath.section)];

    // 问题行：图标 + 问题 + 展开指示箭头
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:item.question
                                                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor
    }];
    if (expanded) {
        // 答案直接拼进同一 cell（动态行高展开），问题与答案之间空一行
        NSString *answerBlock = [NSString stringWithFormat:@"\n\n%@", item.answer];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:answerBlock
                                                                       attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:14],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor
        }]];
    }
    cell.textLabel.attributedText = title;
    cell.textLabel.numberOfLines = 0;

    UIImage *icon = [UIImage systemImageNamed:item.iconName];
    cell.imageView.image = [icon imageWithTintColor:accentColor()
                              renderingMode:UIImageRenderingModeAlwaysOriginal];

    cell.accessoryType = expanded ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.row * 1000 + indexPath.section);
    if ([self.expandedPaths containsObject:key]) {
        [self.expandedPaths removeObject:key];
    } else {
        [self.expandedPaths addObject:key];
    }
    // 只刷新这一行（展开/收起动画），避免整表 reload 造成的滚动位置跳动
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

@end
