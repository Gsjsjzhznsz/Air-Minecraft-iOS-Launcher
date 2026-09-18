#import "LauncherMenuViewController.h"
#import "NeomorphKit/UIView+Neomorph.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherPreferences.h"
#import "VersionManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "PLProfiles.h"
#import "BackgroundManager.h"
#import "utils.h"

@interface LauncherMenuViewController ()

@property(nonatomic, strong) UIView *sidebarView;
@property(nonatomic, strong) UIStackView *menuStackView;
@property(nonatomic, strong) NSArray<NSDictionary *> *menuItems;
@property(nonatomic, assign) NSInteger selectedIndex;

@end

@implementation LauncherMenuViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 即使本控制器在 LauncherRootViewController 中作为子 VC 添加，仍需在自身 viewDidLoad 中调用。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    // 监听外观变更（字体颜色变化时刷新菜单按钮颜色）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyCustomAppearance)
                                                 name:@"LauncherAppearanceChanged"
                                               object:nil];

    // 菜单项配置
    // 联机相关入口暂不显示（需进一步完善）
    // case 3 为"联机"（陶瓦联机 Terracotta，与 HMCL/FCL/ZL2 互通）
    // case 4 为"ZeroTier 联机"（独立入口，与陶瓦联机并列，便于用户直接进入 ZeroTier 界面）
    // case 5 为"设置"
    // case 6 为"使用问题"（Task 82：FAQ 标签页，收录渲染/输入/安装/故障排除常见问题）
    // 键位调整界面已移到设置页面中
    self.menuItems = @[
        @{@"icon": @"house.fill", @"title": @" ", @"index": @0},
        @{@"icon": @"arrow.down.circle.fill", @"title": @" ", @"index": @1},
        @{@"icon": @"sparkles", @"title": @" ", @"index": @2},
        @{@"icon": @"puzzlepiece.fill", @"title": @" ", @"index": @3},
        // 暂时移除两个联机图标，恢复时取消下方两行注释并将设置项 index 顺延
        // @{@"icon": @"antenna.radiowaves.left.and.right", @"title": @" ", @"index": @4},
        // @{@"icon": @"network", @"title": @" ", @"index": @5},
        @{@"icon": @"gearshape.fill", @"title": @" ", @"index": @4},
        @{@"icon": @"questionmark.circle.fill", @"title": @" ", @"index": @5}
    ];
    
    self.selectedIndex = 0;
    
    [self setupSidebar];
}

#pragma mark - UI Setup

- (void)setupSidebar {
    self.sidebarView = [[UIView alloc] init];
    self.sidebarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.sidebarView];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.sidebarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.sidebarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.sidebarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    // 创建垂直均分的 UIStackView，替代固定偏移布局。
    // 之前用 startY=60 + 固定间距 15，5 个按钮总高 370pt，在 iPhone 横屏（卡片高度不足）
    // 时第 5 个按钮（设置）被卡片 masksToBounds 裁剪，且按钮只锚定 top 无 bottom 约束，
    // 下方留出大块空白加剧"下面空隙大"的观感。
    // 改用 UIStackView EqualSpacing 让按钮在可用空间内垂直均匀分布，上下留白相同，
    // 无论卡片高度如何都能完整显示所有按钮，且消除固定 startY 导致的下方空白。
    self.menuStackView = [[UIStackView alloc] init];
    self.menuStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.menuStackView.axis = UILayoutConstraintAxisVertical;
    self.menuStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.menuStackView.alignment = UIStackViewAlignmentCenter;
    self.menuStackView.spacing = 8;
    [self.sidebarView addSubview:self.menuStackView];

    CGFloat buttonSize = 50;
    for (NSInteger i = 0; i < self.menuItems.count; i++) {
        NSDictionary *item = self.menuItems[i];
        UIButton *btn = [self createMenuButtonWithItem:item index:i];
        [self.menuStackView addArrangedSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:buttonSize],
            [btn.heightAnchor constraintEqualToConstant:buttonSize]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.menuStackView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
        [self.menuStackView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
        [self.menuStackView.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor constant:8],
        [self.menuStackView.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor constant:-8],
        [self.menuStackView.centerXAnchor constraintEqualToAnchor:self.sidebarView.centerXAnchor]
    ]];
}

- (UIButton *)createMenuButtonWithItem:(NSDictionary *)item index:(NSInteger)index {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tag = index;

    // 设置图标（Task101：仅图标按钮，无文字；图标在 50×50 按钮内居中，
    // 与新拟物高亮面板几何中心对齐）
    UIImage *icon = [UIImage systemImageNamed:item[@"icon"]];
    [btn setImage:icon forState:UIControlStateNormal];

    // 设置颜色 - 选中项高亮
    // 支持自定义字体颜色：用户在设置中配置 general.text_color 后，
    // 未选中项使用自定义颜色，选中项保持高亮蓝色
    UIColor *normalColor = [self menuNormalColor];
    UIColor *accent = accentColor();
    if (index == self.selectedIndex) {
        btn.tintColor = accent;
    } else {
        btn.tintColor = normalColor;
    }

    // 图标居中（Task101：原 imageEdgeInsets(-10,0,0,0)+空白标题的
    // 图标在上文字在下布局退役——菜单项标题本就是空格 " "，
    // 原偏移让图标偏离高亮面板中心，用户实测"高亮和图标有点偏差"）
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    
    [btn addTarget:self action:@selector(menuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    // 统一圆角：防御性设置 10pt，避免后续给选中态加背景高亮时出现直角方块
    btn.layer.cornerRadius = 10;
    // Task89：新拟态——初始选中项直接应用凸出面板（选中态在 updateButtonColors 维护）
    if (index == self.selectedIndex) {
        [btn nm_convexRadius:12 shadowRadius:5];
    }

    return btn;
}

#pragma mark - Actions

// Task101：菜单图标自愈——启动早期偶发 systemImageNamed: 拿到 nil
// （用户实测：左上角主界面 house.fill 图标有时刚打开软件时消失，
// 二次启动恢复正常，典型时序型 nil）。这里对 image 为空的按钮
// 幂等重取符号，viewWillAppear 与外观刷新路径都会调用。
- (void)refreshMenuIconImages {
    for (UIView *view in self.menuStackView.arrangedSubviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)view;
        NSInteger idx = btn.tag;
        if (idx < 0 || idx >= (NSInteger)self.menuItems.count) continue;
        if ([btn imageForState:UIControlStateNormal]) continue;
        UIImage *icon = [UIImage systemImageNamed:self.menuItems[idx][@"icon"]];
        if (icon) {
            [btn setImage:icon forState:UIControlStateNormal];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshMenuIconImages];
}

- (void)menuButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;

    // FCL 风格：选中菜单项时添加弹跳动画（ScaleX/ScaleY 弹跳，OvershootInterpolator 效果）
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.5
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];

    // 更新选中状态
    self.selectedIndex = index;
    [self updateButtonColors];

    // 回调
    NSString *title = self.menuItems[index][@"title"];
    if (self.onMenuItemSelected) {
        self.onMenuItemSelected(index, title);
    }

    // 处理导航
    [self handleMenuSelection:index];
}

- (void)updateButtonColors {
    UIColor *normalColor = [self menuNormalColor];
    UIColor *accent = accentColor();
    // Task101：顺手补拉缺失图标（幂等，仅填 nil）
    [self refreshMenuIconImages];
    // 按钮现在在 menuStackView.arrangedSubviews 中（UIStackView 重构后）
    for (UIView *view in self.menuStackView.arrangedSubviews) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            NSInteger index = btn.tag;

            if (index == self.selectedIndex) {
                btn.tintColor = accent;
                // Task101：按钮无标题（纯图标），仅剩图标着色，原 setTitleColor 分支退场
                // Task89：新拟态——选中项为凸出面板（surface 底 + 双阴影），
                // 替代原半透明 accent 高亮；幂等重刷（重复调用安全）
                [btn nm_convexRadius:12 shadowRadius:5];
            } else {
                btn.tintColor = normalColor;
                // 未选中项恢复平贴（无底色无阴影）
                [btn nm_removeNeomorph];
                btn.backgroundColor = [UIColor clearColor];
            }
        }
    }
}

// 字体颜色变更时刷新所有菜单按钮
- (void)applyCustomAppearance {
    [self updateButtonColors];
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 确保全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 未选中菜单项的颜色：优先使用用户自定义的 general.text_color，否则默认 systemGray
- (UIColor *)menuNormalColor {
    NSString *hex = getPrefObject(@"general.text_color");
    if (hex.length > 0) {
        UIColor *custom = [self colorFromHexString:hex];
        if (custom) return custom;
    }
    return [UIColor systemGrayColor];
}

- (UIColor *)colorFromHexString:(NSString *)hexString {
    NSString *hex = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length != 6 && hex.length != 8) return nil;
    unsigned int r, g, b, a = 255;
    if (hex.length == 6) {
        [[NSScanner scannerWithString:hex] scanHexInt:&r];
        b = r & 0xFF;
        g = (r >> 8) & 0xFF;
        r = (r >> 16) & 0xFF;
    } else {
        [[NSScanner scannerWithString:hex] scanHexInt:&r];
        a = r & 0xFF;
        b = (r >> 8) & 0xFF;
        g = (r >> 16) & 0xFF;
        r = (r >> 24) & 0xFF;
    }
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a/255.0];
}

- (void)handleMenuSelection:(NSInteger)index {
    switch (index) {
        case 0: // 主页
            // 通知父控制器切换到新闻页
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHomePage" object:nil];
            break;

        case 1: // 下载
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowDownloadPage" object:nil];
            break;

        case 2: // AI 助手
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowAIPage" object:nil];
            break;

        case 3: // 版本管理（合并了原"当前版本设置"功能）
            [self showVersionManager];
            break;

        case 4: // 设置（联机入口暂时移除，恢复时顺延 index）
            [self showSettings];
            break;

        case 5: // 使用问题（Task 82：FAQ 页）
            [self showHelpPage];
            break;
    }
}

- (void)showVersionManager {
    // 发送通知让 LauncherRootViewController 在中间内容区显示
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowVersionManager" object:nil];
}

- (void)showMultiplayer {
    // 发送通知让 LauncherRootViewController 显示陶瓦联机界面
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowMultiplayer" object:nil];
}

- (void)showZeroTier {
    // 发送通知让 LauncherRootViewController 显示 ZeroTier 联机界面
    // ZeroTier 与陶瓦联机为并列的两套联机方案，独立菜单入口避免用户先进入陶瓦再切换。
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowZeroTier" object:nil];
}

- (void)showSettings {
    // 发送通知让 LauncherRootViewController 在中间内容区显示
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowSettings" object:nil];
}

- (void)showHelpPage {
    // Task 82：发送通知让 LauncherRootViewController 在中间内容区显示"使用问题"FAQ 页
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowHelpPage" object:nil];
}

#pragma mark - Data Updates

- (void)updateAccountInfo {
    // 账户信息在右侧面板显示，这里不需要处理
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

@end
