//
//  AccountLoginViewController.m
//  Amethyst
//
//  参照 FCL (Fold Craft Launcher) 与 HMCL 的账户登录界面：
//  - 顶部标题区（大标题 + 副标题）
//  - 四张可点击的登录方式卡片（微软 / LittleSkin / 自定义第三方 / 本地）
//  - 每张卡片：左侧彩色图标圆 + 中间标题/描述 + 右侧箭头
//  - 适配自定义启动器背景（透明 view + 卡片毛玻璃）
//  - 使用 UIButton 替代 UIControl，避免触摸拦截问题
//

#import "AccountLoginViewController.h"
#import "NeomorphKit/NMTheme.h"
#import "BackgroundManager.h"
#import "ScreenUtils.h"
#import "utils.h"

@interface AccountLoginViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *cardStack;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@end

@implementation AccountLoginViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // 适配自定义启动器背景：将当前视图控制器透明化，使全局背景壁纸能够透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.title = localize(@"i18n_str_2", nil);
    // 透明背景，让自定义启动器背景透出（applyBackgroundToView 会把背景加到 window/splitVC 底层）
    self.view.backgroundColor = [UIColor clearColor];

    [self setupUI];
    // 应用背景（遍历 responder chain 找到 splitVC/window，在最底层加背景）
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];

    // 监听背景 UI 效果变化通知，当用户切换背景效果（半透明/毛玻璃）时重新应用透明化
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// 背景效果改变时重新应用透明化（由 BackgroundUIEffectChanged 通知触发）
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 确保 scrollView contentSize 正确
    [self.scrollView layoutIfNeeded];
}

#pragma mark - Setup

- (void)setupUI {
    // ScrollView 容器
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.delegate = self;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    // 卡片堆栈
    self.cardStack = [[UIStackView alloc] init];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = [ScreenUtils dp:14];
    self.cardStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.cardStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.cardStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:[ScreenUtils dp:20]],
        [self.cardStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:[ScreenUtils dp:20]],
        [self.cardStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-[ScreenUtils dp:20]],
        [self.cardStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-[ScreenUtils dp:20]],
        [self.cardStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-[ScreenUtils dp:40]],
    ]];

    // 标题区
    [self setupHeader];

    // 间距
    [self.cardStack addArrangedSubview:[self spacerViewWithHeight:[ScreenUtils dp:8]]];

    // 四张登录卡片
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeMicrosoft
                                                                title:localize(@"i18n_str_10", nil)
                                                          description:localize(@"i18n_str_11", nil)
                                                           iconName:@"xbox.logo"
                                                       fallbackIcon:@"person.crop.circle.fill"
                                                          accentColor:[UIColor colorWithRed:0.0 green:0.45 blue:0.93 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLittleSkin
                                                                title:@"LittleSkin"
                                                          description:localize(@"i18n_str_12", nil)
                                                           iconName:@"person.fill.viewfinder"
                                                       fallbackIcon:@"person.crop.circle.fill"
                                                          accentColor:[UIColor colorWithRed:0.55 green:0.30 blue:0.85 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeThirdParty
                                                                title:localize(@"i18n_str_13", nil)
                                                          description:localize(@"i18n_str_14", nil)
                                                           iconName:@"globe"
                                                       fallbackIcon:@"globe"
                                                          accentColor:[UIColor colorWithRed:0.90 green:0.55 blue:0.15 alpha:1.0]]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLocal
                                                                title:localize(@"i18n_str_15", nil)
                                                          description:localize(@"i18n_str_16", nil)
                                                           iconName:@"person.fill"
                                                       fallbackIcon:@"person.fill"
                                                          accentColor:[UIColor colorWithRed:0.50 green:0.55 blue:0.60 alpha:1.0]]];
}

/// 顶部标题区（FCL/HMCL 风格：大标题 + 副标题）
- (void)setupHeader {
    self.headerContainer = [[UIView alloc] init];
    self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardStack addArrangedSubview:self.headerContainer];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.text = localize(@"i18n_str_17", nil);
    self.headerTitleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:26] weight:UIFontWeightBold];
    self.headerTitleLabel.textColor = [NMTheme nm_label]; // Task91：写死白色改主题主文字色
    self.headerTitleLabel.numberOfLines = 1;
    [self.headerContainer addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerSubtitleLabel.text = localize(@"i18n_str_18", nil);
    self.headerSubtitleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:14] weight:UIFontWeightRegular];
    self.headerSubtitleLabel.textColor = [NMTheme nm_secondaryLabel]; // Task91
    self.headerSubtitleLabel.numberOfLines = 0;
    [self.headerContainer addSubview:self.headerSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerTitleLabel.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor],
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.headerTitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],

        [self.headerSubtitleLabel.topAnchor constraintEqualToAnchor:self.headerTitleLabel.bottomAnchor constant:[ScreenUtils dp:6]],
        [self.headerSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.headerSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],
        [self.headerSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],
    ]];
}

/// 创建一张登录方式卡片（FCL/HMCL 风格）
/// 使用 UIButton 替代 UIControl，确保 touch 事件可靠触发
- (UIView *)createLoginCardWithType:(AccountLoginType)type
                              title:(NSString *)title
                        description:(NSString *)description
                         iconName:(NSString *)iconName
                     fallbackIcon:(NSString *)fallbackIcon
                        accentColor:(UIColor *)accentColor {
    // 卡片容器（UIView + 手势），不直接用 UIButton 是因为需要复杂内部布局
    // 用 UIView + UITapGestureRecognizer 替代 UIControl，避免 UIVisualEffectView 拦截
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = [ScreenUtils dp:16];
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    // 启用触摸交互
    card.userInteractionEnabled = YES;

    // 毛玻璃背景（blurView.userInteractionEnabled = NO 由 applyEffectToView 保证）
    [[BackgroundManager sharedManager] applyEffectToView:card];

    // 左侧图标圆（accentColor 轻底色 + SF Symbol）
    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [accentColor colorWithAlphaComponent:0.18];
    iconCircle.layer.cornerRadius = [ScreenUtils dp:24];
    iconCircle.userInteractionEnabled = NO;
    [card addSubview:iconCircle];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *icon = [UIImage systemImageNamed:iconName] ?: [UIImage systemImageNamed:fallbackIcon];
    iconView.image = icon;
    iconView.tintColor = accentColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [iconCircle addSubview:iconView];

    // 中间标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:17] weight:UIFontWeightSemibold];
    titleLabel.textColor = [NMTheme nm_label]; // Task91：写死白色改主题主文字色
    titleLabel.numberOfLines = 1;
    titleLabel.userInteractionEnabled = NO;
    [card addSubview:titleLabel];

    // 中间描述
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.text = description;
    descLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:13] weight:UIFontWeightRegular];
    descLabel.textColor = [NMTheme nm_secondaryLabel]; // Task91
    descLabel.numberOfLines = 0;
    descLabel.userInteractionEnabled = NO;
    [card addSubview:descLabel];

    // 右侧箭头
    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.image = [UIImage systemImageNamed:@"chevron.right"];
    chevron.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.40];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.userInteractionEnabled = NO;
    [card addSubview:chevron];

    // 布局约束
    CGFloat padding = [ScreenUtils dp:16];
    CGFloat iconSize = [ScreenUtils dp:48];
    CGFloat iconInset = [ScreenUtils dp:24];

    [NSLayoutConstraint activateConstraints:@[
        [iconCircle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:padding],
        [iconCircle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconCircle.widthAnchor constraintEqualToConstant:iconSize],
        [iconCircle.heightAnchor constraintEqualToConstant:iconSize],

        [iconView.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:iconInset],
        [iconView.heightAnchor constraintEqualToConstant:iconInset],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:[ScreenUtils dp:14]],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:[ScreenUtils dp:18]],
        [titleLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-[ScreenUtils dp:8]],

        [descLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:[ScreenUtils dp:4]],
        [descLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [descLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-[ScreenUtils dp:18]],

        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-padding],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:[ScreenUtils dp:14]],
        [chevron.heightAnchor constraintEqualToConstant:[ScreenUtils dp:20]],
    ]];

    // 使用 UITapGestureRecognizer 处理点击（比 UIControlEventTouchUpInside 更可靠，
    // 不会被 UIVisualEffectView 的 contentView 拦截）
    // tag 从 1 开始，避免 0 被 UIKit 视为"未设置 tag"
    card.tag = type + 1;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    tapGesture.cancelsTouchesInView = NO;
    [card addGestureRecognizer:tapGesture];

    return card;
}

- (UIView *)spacerViewWithHeight:(CGFloat)height {
    UIView *spacer = [[UIView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:height].active = YES;
    return spacer;
}

#pragma mark - Actions

/// 卡片点击处理（由 UITapGestureRecognizer 触发）
- (void)cardTapped:(UITapGestureRecognizer *)gesture {
    UIView *card = gesture.view;
    if (!card) return;
    // 还原 tag 偏移（createLoginCardWithType 中存储时 +1）
    AccountLoginType type = (AccountLoginType)(card.tag - 1);

    // 轻微高亮反馈（FCL 风格）
    [UIView animateWithDuration:0.1 animations:^{
        card.alpha = 0.65;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            card.alpha = 1.0;
        } completion:^(BOOL finished2) {
            if (self.onSelectLoginType) {
                self.onSelectLoginType(type);
            }
        }];
    }];
}

@end
