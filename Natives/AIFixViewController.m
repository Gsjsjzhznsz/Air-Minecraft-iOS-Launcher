//
//  AIFixViewController.m
//  Amethyst
//
//  AI 崩溃修复界面控制器实现
//

// 必须首先导入 Foundation/UIKit，避免其他头文件中的宏定义与 Objective-C 关键字冲突
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 取消可能存在的 interface 宏定义，避免与 Objective-C 的 @interface 关键字冲突
#ifdef interface
#undef interface
#endif

#import "AIFixViewController.h"
#import "AIFixService.h"
#import "AIConfigService.h"
#import "AIToolKit.h"
#import "utils.h"
#import "PLCrashView.h"
#import "SurfaceViewController.h"
#import "ModService.h"
#import "ModItem.h"
#import "PLProfiles.h"
#import "LiquidGlassCompat.h"

static UIColor *AFHexColor(NSString *hex) {
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// 消息气泡类型
typedef NS_ENUM(NSInteger, MessageBubbleType) {
    MessageBubbleTypeAI,        // AI 消息
    MessageBubbleTypeUser,      // 用户消息
    MessageBubbleTypeSystem,    // 系统消息
    MessageBubbleTypeToolResult // 工具结果
};

// 消息气泡视图
@interface MessageBubbleView : UIView
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, strong) UIImageView *statusIcon;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) MessageBubbleType bubbleType;
@property (nonatomic, assign) BOOL isSuccess;
@property (nonatomic, copy, nullable) NSString *messageId;
@end

@interface AIDashboardTileView : UIControl
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) CAGradientLayer *accentLayer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, assign) BOOL compactLayout;
- (void)configureWithTitle:(NSString *)title value:(NSString *)value subtitle:(NSString *)subtitle icon:(NSString *)iconName accent:(UIColor *)accent compact:(BOOL)compact;
@end

// 工具请求卡片视图
@interface ToolRequestCardView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *toolNameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UITextView *parametersTextView;
@property (nonatomic, strong) UIButton *approveButton;
@property (nonatomic, strong) UIButton *rejectButton;
@property (nonatomic, copy) void(^onApprove)(void);
@property (nonatomic, copy) void(^onReject)(void);

// Mod 预览相关
@property (nonatomic, strong) UIView *modPreviewContainer;
@property (nonatomic, strong) UIImageView *modIconView;
@property (nonatomic, strong) UILabel *modNameLabel;
@property (nonatomic, strong) UILabel *modDescLabel;
@property (nonatomic, strong) UILabel *modStatusLabels;

// Mod 预览方法
- (void)showModPreviewWithName:(NSString *)modName 
                       iconPath:(NSString *)iconPath 
                    description:(NSString *)description 
                   willEnable:(BOOL)willEnable;
- (void)hideModPreview;
- (void)replaceIconWithNewIcon:(UIImageView *)newIcon;
@end

// SVG 图标助手
@interface AIFixSVGIconHelper : NSObject
+ (UIImage *)svgImageNamed:(NSString *)name withColor:(UIColor *)color size:(CGSize)size;
+ (UIImage *)svgImageFromData:(NSData *)data withColor:(UIColor *)color size:(CGSize)size;
+ (UIImageView *)iconViewForTool:(NSString *)toolName size:(CGFloat)size;
@end

@interface AIFixViewController () <AIFixServiceDelegate, UITextViewDelegate>

// UI 组件
@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIView *mainContentView;
@property (nonatomic, strong) UIView *leftPanel;
@property (nonatomic, strong) UIView *rightPanel;
@property (nonatomic, strong) UIScrollView *conversationScrollView;
@property (nonatomic, strong) UIStackView *conversationStackView;
@property (nonatomic, strong) UIView *inputContainerView;
@property (nonatomic, strong) UITextView *inputTextView;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *exitButton;

// 右侧面板组件
@property (nonatomic, strong) UIView *configCardView;
@property (nonatomic, strong) UITextField *apiBaseURLField;
@property (nonatomic, strong) UITextField *modelNameField;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UILabel *configStatusLabel;
@property (nonatomic, strong) UIButton *saveConfigButton;

@property (nonatomic, strong) UIView *toolsCardView;
@property (nonatomic, strong) UILabel *toolsTitleLabel;
@property (nonatomic, strong) UIStackView *toolsStackView;
@property (nonatomic, strong) UIView *historyCardView;
@property (nonatomic, strong) UILabel *historyTitleLabel;
@property (nonatomic, strong) UIStackView *historyStackView;
@property (nonatomic, strong) UIView *riskCardView;
@property (nonatomic, strong) UILabel *riskTitleLabel;
@property (nonatomic, strong) UIStackView *riskStackView;

// 状态视图
@property (nonatomic, strong) UIView *statusBarView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIView *diagnosticStripView;
@property (nonatomic, strong) UILabel *diagnosticTitleLabel;
@property (nonatomic, strong) UILabel *diagnosticSubtitleLabel;
@property (nonatomic, strong) UIStackView *diagnosticTileStack;
@property (nonatomic, strong) UIButton *startFixButton;
@property (nonatomic, strong) UIScrollView *leftScrollView;
@property (nonatomic, strong) UIScrollView *rightScrollView;
@property (nonatomic, strong) UIView *leftContentView;
@property (nonatomic, strong) UIView *rightContentView;

// 工具请求卡片
@property (nonatomic, strong) ToolRequestCardView *toolRequestCard;

// 数据
@property (nonatomic, copy, nullable) NSString *logPath;
@property (nonatomic, assign) BOOL isFromSettings;
@property (nonatomic, assign) BOOL hasStarted;

// 动画
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *dynamicConstraints;

// 紧凑布局下重新计算左栏内会话滚动视图与输入框的 frame
- (void)relayoutLeftPanelContents;

@end

@implementation AIFixViewController

#pragma mark - 初始化

- (instancetype)initWithLogPath:(NSString *)logPath {
    self = [super init];
    if (self) {
        _logPath = logPath;
        _isFromSettings = NO;
        _hasStarted = NO;
    }
    return self;
}

- (instancetype)initForSettings {
    self = [super init];
    if (self) {
        _logPath = nil;
        _isFromSettings = YES;
        _hasStarted = NO;
    }
    return self;
}

- (instancetype)init {
    return [self initWithLogPath:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    
    [self setupUI];
    [self loadConfig];
    [self refreshHistoryAndRiskInfo];
    
    if (![AIConfigService sharedService].hasShownExperimentalWarning) {
        [self showExperimentalWarning];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutMainPanelsIfNeeded];
    [self scrollToBottomAnimated:NO];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.view.frame = [UIScreen mainScreen].bounds;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self setupBackground];

    _mainContentView = [[UIView alloc] initWithFrame:CGRectZero];
    _mainContentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_mainContentView];

    _leftPanel = [[UIView alloc] initWithFrame:CGRectZero];
    [_mainContentView addSubview:_leftPanel];

    _rightPanel = [[UIView alloc] initWithFrame:CGRectZero];
    [_mainContentView addSubview:_rightPanel];

    [self setupLeftPanel];
    [self setupRightPanel];
    [self setupStatusBar];
    [self layoutMainPanelsIfNeeded];
}

- (void)setupBackground {
    // iOS 26+ 液态玻璃 / 低版本毛玻璃
    UIVisualEffectView *blurView = LGCCreateGlassEffectView(YES);
    blurView.frame = self.view.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blurView];
    
    // 深色蒙层
    _backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    _backgroundView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_backgroundView];
}

- (void)layoutMainPanelsIfNeeded {
    CGFloat viewWidth = self.view.bounds.size.width;
    CGFloat viewHeight = self.view.bounds.size.height;
    if (viewWidth <= 0 || viewHeight <= 0 || !_mainContentView) return;

    // 适配 iPhone 窄屏：宽度不足时使用单栏布局，并收紧边距与最大宽度
    BOOL isCompact = viewWidth < 700;
    CGFloat horizontalPadding = isCompact ? 12 : 16;
    CGFloat maxContentWidth = isCompact ? (viewWidth - horizontalPadding * 2) : 1200;
    CGFloat contentWidth = MIN(viewWidth - horizontalPadding * 2, maxContentWidth);
    CGFloat topPadding = isCompact ? 16 : 40;
    CGFloat bottomPadding = isCompact ? 16 : 24;
    CGFloat contentHeight = MAX(viewHeight - topPadding - bottomPadding, 300);
    CGFloat startX = floor((viewWidth - contentWidth) / 2.0);

    _mainContentView.frame = CGRectMake(startX, topPadding, contentWidth, contentHeight);

    CGFloat leftWidth, rightWidth, panelHeight;
    if (isCompact) {
        // 紧凑布局：双栏上下堆叠，左栏（诊断/会话）占 58%，右栏（配置/历史）占 42%
        leftWidth = contentWidth;
        rightWidth = contentWidth;
        CGFloat gap = 8;
        leftWidth = contentWidth;
        panelHeight = floor((contentHeight - gap) * 0.58);
        CGFloat rightHeight = contentHeight - gap - panelHeight;
        _leftPanel.frame = CGRectMake(0, 0, leftWidth, panelHeight);
        _rightPanel.frame = CGRectMake(0, panelHeight + gap, rightWidth, rightHeight);
        _leftScrollView.frame = CGRectMake(0, 0, leftWidth, MAX(panelHeight - 18, 0));
        _rightScrollView.frame = CGRectMake(0, 0, rightWidth, MAX(rightHeight - 18, 0));
        _leftContentView.frame = CGRectMake(0, 0, leftWidth, MAX(panelHeight * 1.25, 560));
        _rightContentView.frame = CGRectMake(0, 0, rightWidth, MAX(rightHeight * 1.35, 420));
    } else {
        leftWidth = floor(contentWidth * 0.6);
        rightWidth = contentWidth - leftWidth;
        panelHeight = contentHeight;
        _leftPanel.frame = CGRectMake(0, 0, leftWidth, panelHeight);
        _rightPanel.frame = CGRectMake(leftWidth, 0, rightWidth, panelHeight);
        _leftScrollView.frame = CGRectMake(0, 0, leftWidth, MAX(panelHeight - 18, 0));
        _rightScrollView.frame = CGRectMake(0, 0, rightWidth, MAX(panelHeight - 18, 0));
        _leftContentView.frame = CGRectMake(0, 0, leftWidth, MAX(panelHeight * 1.25, 720));
        _rightContentView.frame = CGRectMake(0, 0, rightWidth, MAX(panelHeight * 1.35, 560));
    }
    _leftScrollView.contentSize = _leftContentView.bounds.size;
    _rightScrollView.contentSize = _rightContentView.bounds.size;

    CGFloat statusHeight = 26;
    _statusBarView.frame = CGRectMake(16, panelHeight - statusHeight, leftWidth - 32, statusHeight);
    _statusLabel.frame = CGRectMake(32, 0, _statusBarView.bounds.size.width - 40, statusHeight);

    // 紧凑布局下，会话滚动视图需要基于实际左栏高度重新布局，避免被挤压为 0
    [self relayoutLeftPanelContents];
}

// 重新计算左栏内会话滚动视图与输入框的 frame，避免在尺寸变化后被挤压或重叠。
// setupLeftPanel 中这两个视图基于初始 panelHeight 一次性写死，布局变化时不会更新。
- (void)relayoutLeftPanelContents {
    if (!_conversationScrollView || !_inputContainerView || !_riskCardView || !_leftContentView) return;
    CGFloat panelWidth = _leftContentView.bounds.size.width;
    CGFloat panelHeight = _leftContentView.bounds.size.height;
    if (panelWidth <= 0 || panelHeight <= 0) return;
    CGFloat sidePadding = 16;
    CGFloat sectionGap = 12;
    CGFloat inputHeight = 128;

    // inputTop 锚定到面板底部，会话区填充 riskCardView 底部到 inputTop 之间
    CGFloat inputTop = panelHeight - inputHeight;
    CGFloat scrollViewTop = CGRectGetMaxY(_riskCardView.frame) + sectionGap;
    CGFloat scrollBottom = inputTop - sectionGap;
    if (scrollBottom > scrollViewTop) {
        _conversationScrollView.frame = CGRectMake(sidePadding, scrollViewTop, panelWidth - sidePadding * 2, scrollBottom - scrollViewTop);
    } else {
        // 高度不足时，至少给会话区保留一个最小可见高度，避免完全不可见
        _conversationScrollView.frame = CGRectMake(sidePadding, scrollViewTop, panelWidth - sidePadding * 2, 60);
    }
    _inputContainerView.frame = CGRectMake(sidePadding, inputTop, panelWidth - sidePadding * 2, inputHeight);
}

- (void)setupLeftPanel {
    CGFloat panelWidth = _leftPanel.bounds.size.width;
    CGFloat panelHeight = _leftPanel.bounds.size.height;
    CGFloat sidePadding = 16;
    CGFloat topSpacing = 8;
    CGFloat toolHeight = 86;
    CGFloat inputHeight = 128;
    CGFloat sectionGap = 12;

    _leftScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, panelHeight - 18)];
    _leftScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _leftScrollView.showsVerticalScrollIndicator = YES;
    _leftScrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _leftScrollView.alwaysBounceVertical = YES;
    [_leftPanel addSubview:_leftScrollView];

    _leftContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, panelHeight * 1.25)];
    [_leftScrollView addSubview:_leftContentView];

    _diagnosticStripView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, 0, panelWidth - sidePadding * 2, 70)];
    _diagnosticStripView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
    _diagnosticStripView.layer.cornerRadius = 18;
    _diagnosticStripView.layer.cornerCurve = kCACornerCurveContinuous;
    _diagnosticStripView.layer.borderWidth = 0.5;
    _diagnosticStripView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    _diagnosticStripView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_leftContentView addSubview:_diagnosticStripView];

    _diagnosticTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, _diagnosticStripView.bounds.size.width - 32, 22)];
    _diagnosticTitleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    _diagnosticTitleLabel.textColor = [UIColor whiteColor];
    _diagnosticTitleLabel.text = localize(@"ai.fix.dash_title", @"AI 修复诊断工作台");
    [_diagnosticStripView addSubview:_diagnosticTitleLabel];

    _diagnosticSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, _diagnosticStripView.bounds.size.width - 32, 18)];
    _diagnosticSubtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _diagnosticSubtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.62];
    _diagnosticSubtitleLabel.text = localize(@"ai.fix.dash_subtitle", @"先分析，再修复，所有高风险操作都将等待确认");
    [_diagnosticStripView addSubview:_diagnosticSubtitleLabel];

    CGFloat tileTop = CGRectGetMaxY(_diagnosticStripView.frame) + topSpacing;
    _diagnosticTileStack = [[UIStackView alloc] initWithFrame:CGRectMake(sidePadding, tileTop, panelWidth - sidePadding * 2, toolHeight)];
    _diagnosticTileStack.axis = UILayoutConstraintAxisHorizontal;
    _diagnosticTileStack.spacing = 10;
    _diagnosticTileStack.distribution = UIStackViewDistributionFillEqually;
    _diagnosticTileStack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_leftContentView addSubview:_diagnosticTileStack];

    NSArray *tiles = @[
        @{@"title": localize(@"ai.fix.tile.analyze", @"分析"), @"value": localize(@"ai.fix.tile.analyze_value", @"日志与配置"), @"subtitle": localize(@"ai.fix.tile.analyze_sub", @"读取崩溃日志"), @"icon": @"doc.text.magnifyingglass", @"accent": AFHexColor(@"#3B82F6")},
        @{@"title": localize(@"ai.fix.tile.plan", @"计划"), @"value": localize(@"ai.fix.tile.plan_value", @"逐步修复"), @"subtitle": localize(@"ai.fix.tile.plan_sub", @"生成最小风险方案"), @"icon": @"list.bullet.clipboard", @"accent": AFHexColor(@"#8B5CF6")},
        @{@"title": localize(@"ai.fix.tile.safe", @"安全"), @"value": localize(@"ai.fix.tile.safe_value", @"人工确认"), @"subtitle": localize(@"ai.fix.tile.safe_sub", @"危险操作需确认"), @"icon": @"shield.lefthalf.filled", @"accent": AFHexColor(@"#10B981")}
    ];
    for (NSDictionary *info in tiles) {
        AIDashboardTileView *tile = [[AIDashboardTileView alloc] init];
        [tile configureWithTitle:info[@"title"] value:info[@"value"] subtitle:info[@"subtitle"] icon:info[@"icon"] accent:info[@"accent"] compact:YES];
        [_diagnosticTileStack addArrangedSubview:tile];
    }

    CGFloat historyTop = CGRectGetMaxY(_diagnosticTileStack.frame) + sectionGap;
    CGFloat historyHeight = 88;
    _historyCardView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, historyTop, panelWidth - sidePadding * 2, historyHeight)];
    _historyCardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
    _historyCardView.layer.cornerRadius = 18;
    _historyCardView.layer.cornerCurve = kCACornerCurveContinuous;
    _historyCardView.layer.borderWidth = 0.5;
    _historyCardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    [_leftContentView addSubview:_historyCardView];

    _historyTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, _historyCardView.bounds.size.width - 32, 18)];
    _historyTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _historyTitleLabel.textColor = [UIColor whiteColor];
    _historyTitleLabel.text = localize(@"ai.fix.history.title", @"修复历史");
    [_historyCardView addSubview:_historyTitleLabel];

    _historyStackView = [[UIStackView alloc] initWithFrame:CGRectMake(16, 32, _historyCardView.bounds.size.width - 32, 44)];
    _historyStackView.axis = UILayoutConstraintAxisHorizontal;
    _historyStackView.spacing = 8;
    _historyStackView.distribution = UIStackViewDistributionFillEqually;
    [_historyCardView addSubview:_historyStackView];

    NSArray *historyInfos = @[
        @{@"title": localize(@"ai.fix.history.sessions", @"会话"), @"value": localize(@"ai.fix.history.sessions_value", @"自动记录"), @"subtitle": localize(@"ai.fix.history.sessions_sub", @"每次修复可回看"), @"icon": @"clock.arrow.circlepath", @"accent": AFHexColor(@"#F59E0B")},
        @{@"title": localize(@"ai.fix.history.rollback", @"回滚"), @"value": localize(@"ai.fix.history.rollback_value", @"一键撤销"), @"subtitle": localize(@"ai.fix.history.rollback_sub", @"保留修改痕迹"), @"icon": @"arrow.uturn.backward.circle.fill", @"accent": AFHexColor(@"#8B5CF6")}
    ];
    for (NSDictionary *info in historyInfos) {
        AIDashboardTileView *tile = [[AIDashboardTileView alloc] init];
        [tile configureWithTitle:info[@"title"] value:info[@"value"] subtitle:info[@"subtitle"] icon:info[@"icon"] accent:info[@"accent"] compact:YES];
        [_historyStackView addArrangedSubview:tile];
    }

    CGFloat riskTop = CGRectGetMaxY(_historyCardView.frame) + sectionGap;
    CGFloat riskHeight = 116;
    _riskCardView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, riskTop, panelWidth - sidePadding * 2, riskHeight)];
    _riskCardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
    _riskCardView.layer.cornerRadius = 18;
    _riskCardView.layer.cornerCurve = kCACornerCurveContinuous;
    _riskCardView.layer.borderWidth = 0.5;
    _riskCardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    [_leftContentView addSubview:_riskCardView];

    _riskTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, _riskCardView.bounds.size.width - 32, 18)];
    _riskTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _riskTitleLabel.textColor = [UIColor whiteColor];
    _riskTitleLabel.text = localize(@"ai.fix.risk.title", @"风险提示");
    [_riskCardView addSubview:_riskTitleLabel];

    _riskStackView = [[UIStackView alloc] initWithFrame:CGRectMake(16, 34, _riskCardView.bounds.size.width - 32, 70)];
    _riskStackView.axis = UILayoutConstraintAxisVertical;
    _riskStackView.spacing = 6;
    _riskStackView.alignment = UIStackViewAlignmentFill;
    [_riskCardView addSubview:_riskStackView];

    NSArray *riskItems = @[
        @{@"title": localize(@"ai.fix.risk.backup", @"修改前已备份"), @"subtitle": localize(@"ai.fix.risk.backup_sub", @"关键文件会尽量保留恢复依据")},
        @{@"title": localize(@"ai.fix.risk.confirm", @"高风险操作需确认"), @"subtitle": localize(@"ai.fix.risk.confirm_sub", @"删除、重命名、Mod 操作不会静默执行")},
        @{@"title": localize(@"ai.fix.risk.verify", @"修复后需手动验证"), @"subtitle": localize(@"ai.fix.risk.verify_sub", @"请重新启动游戏确认实际效果")}
    ];
    for (NSDictionary *item in riskItems) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
        row.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        row.layer.cornerRadius = 10;
        row.layer.cornerCurve = kCACornerCurveContinuous;
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, _riskStackView.bounds.size.width - 20, 16)];
        title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        title.textColor = [UIColor whiteColor];
        title.text = item[@"title"];
        [row addSubview:title];
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 20, _riskStackView.bounds.size.width - 20, 14)];
        sub.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        sub.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.58];
        sub.text = item[@"subtitle"];
        [row addSubview:sub];
        row.frame = CGRectMake(0, 0, _riskStackView.bounds.size.width, 30);
        [_riskStackView addArrangedSubview:row];
    }

    CGFloat scrollViewTop = CGRectGetMaxY(_riskCardView.frame) + sectionGap;
    CGFloat inputTop = panelHeight - inputHeight;
    CGFloat scrollBottom = inputTop - 12;
    _conversationScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(sidePadding, scrollViewTop, panelWidth - sidePadding * 2, scrollBottom - scrollViewTop)];
    _conversationScrollView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    _conversationScrollView.layer.cornerRadius = 18;
    _conversationScrollView.layer.cornerCurve = kCACornerCurveContinuous;
    _conversationScrollView.layer.borderWidth = 0.5;
    _conversationScrollView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    _conversationScrollView.showsVerticalScrollIndicator = YES;
    _conversationScrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _conversationScrollView.alwaysBounceVertical = YES;
    [_leftContentView addSubview:_conversationScrollView];

    _conversationStackView = [[UIStackView alloc] init];
    _conversationStackView.axis = UILayoutConstraintAxisVertical;
    _conversationStackView.spacing = 12;
    _conversationStackView.alignment = UIStackViewAlignmentFill;
    _conversationStackView.distribution = UIStackViewDistributionFill;
    _conversationStackView.layoutMargins = UIEdgeInsetsMake(12, 12, 12, 12);
    _conversationStackView.layoutMarginsRelativeArrangement = YES;
    [_conversationScrollView addSubview:_conversationStackView];

    _conversationStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [_conversationStackView.topAnchor constraintEqualToAnchor:_conversationScrollView.topAnchor].active = YES;
    [_conversationStackView.leadingAnchor constraintEqualToAnchor:_conversationScrollView.leadingAnchor].active = YES;
    [_conversationStackView.trailingAnchor constraintEqualToAnchor:_conversationScrollView.trailingAnchor].active = YES;
    [_conversationStackView.widthAnchor constraintEqualToAnchor:_conversationScrollView.widthAnchor constant:-24].active = YES;

    _inputContainerView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, inputTop, panelWidth - sidePadding * 2, inputHeight)];
    _inputContainerView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    _inputContainerView.layer.cornerRadius = 18;
    _inputContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    _inputContainerView.layer.borderWidth = 0.5;
    _inputContainerView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    [_leftContentView addSubview:_inputContainerView];

    UILabel *inputTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 180, 18)];
    inputTitle.text = localize(@"ai.fix.input_title", @"指令与补充信息");
    inputTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    inputTitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    [_inputContainerView addSubview:inputTitle];

    _inputTextView = [[UITextView alloc] initWithFrame:CGRectMake(12, 30, _inputContainerView.bounds.size.width - 24, 56)];
    _inputTextView.backgroundColor = [UIColor clearColor];
    _inputTextView.textColor = [UIColor whiteColor];
    _inputTextView.font = [UIFont systemFontOfSize:15];
    _inputTextView.delegate = self;
    _inputTextView.textContainerInset = UIEdgeInsetsZero;
    _inputTextView.textContainer.lineFragmentPadding = 0;
    [_inputContainerView addSubview:_inputTextView];

    UILabel *placeholder = [[UILabel alloc] initWithFrame:CGRectMake(12, 30, 260, 24)];
    placeholder.text = localize(@"ai.fix.input_placeholder", @"描述现象、补充信息或直接开始对话...");
    placeholder.font = [UIFont systemFontOfSize:15];
    placeholder.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35];
    placeholder.tag = 999;
    [_inputContainerView addSubview:placeholder];

    _stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _stopButton.frame = CGRectMake(_inputContainerView.bounds.size.width - 162, _inputContainerView.bounds.size.height - 36, 72, 28);
    [_stopButton setTitle:localize(@"ai.fix.stop", @"停止") forState:UIControlStateNormal];
    _stopButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _stopButton.backgroundColor = AFHexColor(@"#DC2626");
    _stopButton.layer.cornerRadius = 14;
    _stopButton.tintColor = [UIColor whiteColor];
    _stopButton.hidden = YES;
    [_stopButton addTarget:self action:@selector(stopFix) forControlEvents:UIControlEventTouchUpInside];
    [_inputContainerView addSubview:_stopButton];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.frame = CGRectMake(_inputContainerView.bounds.size.width - 80, _inputContainerView.bounds.size.height - 36, 68, 28);
    [_sendButton setTitle:localize(@"ai.fix.send", @"发送") forState:UIControlStateNormal];
    _sendButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _sendButton.backgroundColor = AFHexColor(@"#2563EB");
    _sendButton.layer.cornerRadius = 14;
    _sendButton.tintColor = [UIColor whiteColor];
    [_sendButton addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
    [_inputContainerView addSubview:_sendButton];
}

- (void)setupRightPanel {
    CGFloat panelWidth = _rightPanel.bounds.size.width;
    CGFloat panelHeight = _rightPanel.bounds.size.height;
    CGFloat sidePadding = 12;
    CGFloat top = 0;

    _rightScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, panelHeight - 18)];
    _rightScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _rightScrollView.showsVerticalScrollIndicator = YES;
    _rightScrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _rightScrollView.alwaysBounceVertical = YES;
    [_rightPanel addSubview:_rightScrollView];

    _rightContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, panelHeight * 1.35)];
    [_rightScrollView addSubview:_rightContentView];

    _configCardView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, top, panelWidth - sidePadding * 2, 206)];
    _configCardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    _configCardView.layer.cornerRadius = 18;
    _configCardView.layer.cornerCurve = kCACornerCurveContinuous;
    _configCardView.layer.borderWidth = 0.5;
    _configCardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    [_rightContentView addSubview:_configCardView];
    [self setupConfigCard];

    _toolsCardView = [[UIView alloc] initWithFrame:CGRectMake(sidePadding, 218, panelWidth - sidePadding * 2, 220)];
    _toolsCardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    _toolsCardView.layer.cornerRadius = 18;
    _toolsCardView.layer.cornerCurve = kCACornerCurveContinuous;
    _toolsCardView.layer.borderWidth = 0.5;
    _toolsCardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    _toolsCardView.hidden = YES;
    [_rightContentView addSubview:_toolsCardView];
    [self setupToolsCard];

    _exitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _exitButton.frame = CGRectMake(sidePadding, panelHeight - 48, panelWidth - sidePadding * 2, 44);
    [_exitButton setTitle:localize(@"ai.fix.exit", @"退出启动器") forState:UIControlStateNormal];
    _exitButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _exitButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    _exitButton.layer.cornerRadius = 14;
    _exitButton.layer.cornerCurve = kCACornerCurveContinuous;
    _exitButton.tintColor = [UIColor whiteColor];
    [_exitButton addTarget:self action:@selector(exitLauncher) forControlEvents:UIControlEventTouchUpInside];
    [_rightContentView addSubview:_exitButton];
}

- (void)setupConfigCard {
    CGFloat cardWidth = _configCardView.bounds.size.width;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, cardWidth - 32, 24)];
    titleLabel.text = localize(@"ai.fix.model_config", @"模型配置");
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor whiteColor];
    [_configCardView addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 34, cardWidth - 32, 18)];
    subtitleLabel.text = localize(@"ai.fix.config_subtitle", @"可对接兼容 OpenAI 的 API 服务");
    subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    [_configCardView addSubview:subtitleLabel];

    _startFixButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startFixButton.frame = CGRectMake(16, 166, 108, 32);
    [_startFixButton setTitle:localize(@"ai.fix.start_fix", @"开始修复") forState:UIControlStateNormal];
    _startFixButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _startFixButton.backgroundColor = AFHexColor(@"#10B981");
    _startFixButton.layer.cornerRadius = 16;
    _startFixButton.layer.cornerCurve = kCACornerCurveContinuous;
    _startFixButton.tintColor = [UIColor whiteColor];
    [_startFixButton addTarget:self action:@selector(startFixManually) forControlEvents:UIControlEventTouchUpInside];
    [_configCardView addSubview:_startFixButton];

    _apiBaseURLField = [self createTextField:CGRectMake(16, 58, cardWidth - 32, 32) placeholder:@"API Base URL"];
    [_configCardView addSubview:_apiBaseURLField];

    _modelNameField = [self createTextField:CGRectMake(16, 94, cardWidth - 32, 32) placeholder:localize(@"ai.fix.model_name", @"模型名")];
    [_configCardView addSubview:_modelNameField];

    _apiKeyField = [self createTextField:CGRectMake(16, 130, cardWidth - 32, 32) placeholder:@"API Key"];
    _apiKeyField.secureTextEntry = YES;
    [_configCardView addSubview:_apiKeyField];

    _configStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 170, cardWidth - 100, 18)];
    _configStatusLabel.font = [UIFont systemFontOfSize:12];
    _configStatusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    [_configCardView addSubview:_configStatusLabel];

    _saveConfigButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveConfigButton.frame = CGRectMake(cardWidth - 82, 162, 66, 32);
    [_saveConfigButton setTitle:localize(@"ai.fix.save", @"保存") forState:UIControlStateNormal];
    _saveConfigButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _saveConfigButton.backgroundColor = AFHexColor(@"#2563EB");
    _saveConfigButton.layer.cornerRadius = 16;
    _saveConfigButton.layer.cornerCurve = kCACornerCurveContinuous;
    _saveConfigButton.tintColor = [UIColor whiteColor];
    [_saveConfigButton addTarget:self action:@selector(saveConfig) forControlEvents:UIControlEventTouchUpInside];
    [_configCardView addSubview:_saveConfigButton];
}

- (void)setupToolsCard {
    CGFloat cardWidth = _toolsCardView.bounds.size.width;

    _toolsTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, cardWidth - 32, 24)];
    _toolsTitleLabel.text = localize(@"ai.fix.tool_requests", @"工具请求");
    _toolsTitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _toolsTitleLabel.textColor = [UIColor whiteColor];
    [_toolsCardView addSubview:_toolsTitleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 34, cardWidth - 32, 18)];
    subtitle.text = localize(@"ai.fix.tool_subtitle", @"高风险操作会在这里等待您的确认");
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    [_toolsCardView addSubview:subtitle];

    _toolsStackView = [[UIStackView alloc] initWithFrame:CGRectMake(16, 56, cardWidth - 32, 154)];
    _toolsStackView.axis = UILayoutConstraintAxisVertical;
    _toolsStackView.spacing = 10;
    _toolsStackView.alignment = UIStackViewAlignmentFill;
    [_toolsCardView addSubview:_toolsStackView];
}

- (void)setupStatusBar {
    CGFloat barWidth = _leftPanel.bounds.size.width - 32;

    _statusBarView = [[UIView alloc] initWithFrame:CGRectMake(16, _leftPanel.bounds.size.height - 34, barWidth, 26)];
    _statusBarView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    _statusBarView.layer.cornerRadius = 13;
    _statusBarView.layer.cornerCurve = kCACornerCurveContinuous;
    [_leftPanel addSubview:_statusBarView];

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _activityIndicator.color = [UIColor whiteColor];
    _activityIndicator.frame = CGRectMake(8, 3, 20, 20);
    [_statusBarView addSubview:_activityIndicator];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(32, 0, barWidth - 40, 26)];
    _statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _statusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.82];
    _statusLabel.text = localize(@"ai.fix.ready", @"准备就绪");
    [_statusBarView addSubview:_statusLabel];
}

- (UITextField *)createTextField:(CGRect)frame placeholder:(NSString *)placeholder {
    UITextField *textField = [[UITextField alloc] initWithFrame:frame];
    textField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    textField.layer.cornerRadius = 8;
    textField.textColor = [UIColor whiteColor];
    textField.font = [UIFont systemFontOfSize:14];
    textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.4]}];
    textField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    textField.leftViewMode = UITextFieldViewModeAlways;
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    return textField;
}

#pragma mark - 配置管理

- (void)loadConfig {
    AIConfigService *config = [AIConfigService sharedService];
    _apiBaseURLField.text = config.apiBaseURL;
    _modelNameField.text = config.modelName;
    _apiKeyField.text = config.apiKey;
    
    [self updateConfigStatus];
}

- (void)saveConfig {
    AIConfigService *config = [AIConfigService sharedService];
    config.apiBaseURL = _apiBaseURLField.text;
    config.modelName = _modelNameField.text;
    config.apiKey = _apiKeyField.text;
    
    [config saveConfig];
    [self updateConfigStatus];
    [self showTransientMessage:localize(@"ai.fix.config_saved", @"配置已保存")];
    
    if (!_hasStarted && config.isConfigured && !_isFromSettings) {
        [self checkAndStartAutoFix];
    }
}

- (void)updateConfigStatus {
    AIConfigService *config = [AIConfigService sharedService];
    
    if (config.isConfigured) {
        _configStatusLabel.text = localize(@"ai.fix.configured", @"已配置");
        _configStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
        
        // 运行时禁用配置编辑
        if ([AIFixService sharedService].isRunning) {
            _apiBaseURLField.enabled = NO;
            _modelNameField.enabled = NO;
            _apiKeyField.enabled = NO;
            _saveConfigButton.enabled = NO;
            [_saveConfigButton setTitle:localize(@"ai.fix.running", @"运行中") forState:UIControlStateNormal];
        }
    } else {
        _configStatusLabel.text = localize(@"ai.fix.not_configured", @"未配置");
        _configStatusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.3 alpha:1.0];
    }
}

#pragma mark - 实验性功能警告

- (void)showExperimentalWarning {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"ai.fix.experimental_title", @"实验性功能")
                                                                   message:localize(@"ai.fix.experimental_message", @"AI 崩溃修复功能为实验性功能，可能较为不稳定。在使用前请确保已做好备份工作。是否继续？")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"ai.fix.continue", @"继续") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [AIConfigService sharedService].hasShownExperimentalWarning = YES;
        [[AIConfigService sharedService] saveConfig];
        [self checkAndStartAutoFix];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"ai.fix.cancel", @"取消") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 自动修复

- (void)checkAndStartAutoFix {
    AIConfigService *config = [AIConfigService sharedService];
    if (!config.isConfigured) {
        [self addSystemMessage:localize(@"ai.fix.please_configure", @"请先完成 API 配置后点击“保存”按钮。")];
        return;
    }
    if (_isFromSettings) {
        [self addSystemMessage:localize(@"ai.fix.settings_mode", @"您已进入 AI 修复设置界面。请点击“开始修复”按钮启动诊断，或直接发送补充信息。")];
        return;
    }
    [self startAutoFix];
}

- (void)startAutoFix {
    if (_hasStarted) return;
    _hasStarted = YES;
    _apiBaseURLField.enabled = NO;
    _modelNameField.enabled = NO;
    _apiKeyField.enabled = NO;
    _saveConfigButton.enabled = NO;
    _startFixButton.enabled = NO;
    [_saveConfigButton setTitle:localize(@"ai.fix.running", @"运行中") forState:UIControlStateNormal];
    [self updateConfigStatus];
    [AIFixService sharedService].delegate = self;
    NSString *logPath = _logPath ?: [NSString stringWithFormat:@"%s/latestlog.txt", getenv("POJAV_HOME")];
    [self addSystemMessage:localize(@"ai.fix.starting", @"正在启动 AI 修复流程...")];
    NSError *error;
    if (![[AIFixService sharedService] startFixWithLogPath:logPath error:&error]) {
        [self addSystemMessage:[NSString stringWithFormat:@"%@: %@", localize(@"ai.fix.start_failed", @"启动失败"), error.localizedDescription]];
        _hasStarted = NO;
        _apiBaseURLField.enabled = YES;
        _modelNameField.enabled = YES;
        _apiKeyField.enabled = YES;
        _saveConfigButton.enabled = YES;
        _startFixButton.enabled = YES;
        [_saveConfigButton setTitle:localize(@"ai.fix.save", @"保存") forState:UIControlStateNormal];
    }
}

#pragma mark - 消息处理

- (void)sendMessage {
    NSString *rawText = _inputTextView.text ?: @"";
    NSString *text = [rawText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0) return;
    
    _inputTextView.text = nil;
    [self updatePlaceholderVisibility];
    
    if (!_hasStarted && [AIConfigService sharedService].isConfigured) {
        [self startAutoFix];
    }
    
    [self addUserMessage:text];
    [[AIFixService sharedService] sendUserMessage:text];
}

- (void)addUserMessage:(NSString *)text {
    MessageBubbleView *bubble = [self createMessageBubbleWithType:MessageBubbleTypeUser content:text];
    [self addBubbleToConversation:bubble animate:YES];
}

- (void)addAIMessage:(NSString *)text {
    MessageBubbleView *bubble = [self createMessageBubbleWithType:MessageBubbleTypeAI content:text];
    [self addBubbleToConversation:bubble animate:YES];
}

- (void)addSystemMessage:(NSString *)text {
    MessageBubbleView *bubble = [self createMessageBubbleWithType:MessageBubbleTypeSystem content:text];
    [self addBubbleToConversation:bubble animate:YES];
}

- (void)addToolResultMessage:(NSString *)text isSuccess:(BOOL)isSuccess {
    MessageBubbleView *bubble = [self createMessageBubbleWithType:MessageBubbleTypeToolResult content:text];
    bubble.isSuccess = isSuccess;
    [self addBubbleToConversation:bubble animate:YES];
}

- (MessageBubbleView *)createMessageBubbleWithType:(MessageBubbleType)type content:(NSString *)content {
    MessageBubbleView *bubble = [[MessageBubbleView alloc] init];
    bubble.bubbleType = type;
    bubble.isSuccess = YES;

    switch (type) {
        case MessageBubbleTypeAI:
            bubble.backgroundColor = [[UIColor colorWithRed:0.18 green:0.28 blue:0.44 alpha:1.0] colorWithAlphaComponent:0.88];
            break;
        case MessageBubbleTypeUser:
            bubble.backgroundColor = [[UIColor colorWithRed:0.16 green:0.44 blue:0.30 alpha:1.0] colorWithAlphaComponent:0.88];
            break;
        case MessageBubbleTypeSystem:
            bubble.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
            break;
        case MessageBubbleTypeToolResult:
            bubble.backgroundColor = [[UIColor colorWithRed:0.20 green:0.42 blue:0.26 alpha:1.0] colorWithAlphaComponent:0.88];
            break;
    }

    bubble.layer.cornerRadius = 16;
    bubble.layer.cornerCurve = kCACornerCurveContinuous;

    CGFloat maxWidth = _conversationScrollView.bounds.size.width - 56;
    CGSize textSize = [content boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14]}
                                             context:nil].size;

    bubble.contentLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, textSize.width + 4, textSize.height + 4)];
    bubble.contentLabel.text = content;
    bubble.contentLabel.font = [UIFont systemFontOfSize:14];
    bubble.contentLabel.textColor = [UIColor whiteColor];
    bubble.contentLabel.numberOfLines = 0;
    bubble.contentLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [bubble addSubview:bubble.contentLabel];

    bubble.frame = CGRectMake(0, 0, MIN(textSize.width + 36, maxWidth), textSize.height + 24);

    return bubble;
}

- (void)addBubbleToConversation:(MessageBubbleView *)bubble animate:(BOOL)animate {
    [_conversationStackView addArrangedSubview:bubble];
    
    if (animate) {
        bubble.alpha = 0;
        bubble.transform = CGAffineTransformMakeTranslation(0, 20);
        
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            bubble.alpha = 1;
            bubble.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    
    [self scrollToBottomAnimated:YES];
}

#pragma mark - 工具请求

- (void)showToolRequest:(AIToolRequest *)request {
    _toolsCardView.hidden = NO;

    for (UIView *view in _toolsStackView.arrangedSubviews.copy) {
        [view removeFromSuperview];
    }

    ToolRequestCardView *card = [[ToolRequestCardView alloc] init];
    card.frame = CGRectMake(0, 0, _toolsStackView.bounds.size.width, 180);
    card.backgroundColor = [UIColor clearColor];

    card.toolNameLabel.text = request.toolDisplayName;
    card.descriptionLabel.text = request.reason;

    UIImageView *newIcon = [AIFixSVGIconHelper iconViewForTool:request.toolName size:28];
    newIcon.frame = card.iconView.frame;
    [card replaceIconWithNewIcon:newIcon];

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:request.parameters options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (jsonData) {
        card.parametersTextView.text = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }

    if ([request.toolName isEqualToString:@"toggle_mod"]) {
        NSString *modPath = request.parameters[@"mod_path"];
        BOOL willEnable = [request.parameters[@"enable"] boolValue];
        [self loadModPreviewForCard:card modPath:modPath willEnable:willEnable];
    }

    __weak typeof(self) weakSelf = self;
    card.onApprove = ^{
        [weakSelf respondToToolRequest:YES];
    };
    card.onReject = ^{
        [weakSelf respondToToolRequest:NO];
    };

    [_toolsStackView addArrangedSubview:card];
    [_toolsCardView layoutIfNeeded];
    _toolsCardView.alpha = 0;
    _toolsCardView.transform = CGAffineTransformMakeScale(0.96, 0.96);

    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
        weakSelf.toolsCardView.alpha = 1;
        weakSelf.toolsCardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)loadModPreviewForCard:(ToolRequestCardView *)card modPath:(NSString *)modPath willEnable:(BOOL)willEnable {
    if (!modPath) return;
    
    // 获取当前配置的游戏目录
    NSString *gameDir = [PLProfiles resolveKeyForCurrentProfile:@"gameDir"];
    if (!gameDir) {
        gameDir = [NSString stringWithFormat:@"%s/game", getenv("POJAV_HOME")];
    }
    
    // 加载 Mod 元数据
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ModItem *modItem = [[ModItem alloc] initWithFilePath:modPath];
        
        // 尝试从缓存加载图标
        NSString *iconCachePath = [[ModService sharedService] iconCachePathForURL:@""];
        NSString *modIconPath = [iconCachePath stringByAppendingPathComponent:modItem.basename];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [card showModPreviewWithName:modItem.displayName
                                 iconPath:[NSFileManager.defaultManager fileExistsAtPath:modIconPath] ? modIconPath : nil
                              description:modItem.modDescription
                             willEnable:willEnable];
            
            // 调整卡片高度以适应 Mod 预览
            CGRect frame = card.frame;
            frame.size.height = 220;
            card.frame = frame;
        });
    });
}

- (void)respondToToolRequest:(BOOL)approved {
    [[AIFixService sharedService] respondToToolRequest:approved];

    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.22 animations:^{
        weakSelf.toolsCardView.alpha = 0;
        weakSelf.toolsCardView.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        weakSelf.toolsCardView.hidden = YES;
    }];
}

#pragma mark - AIFixServiceDelegate

- (void)aiService:(AIFixService *)service didChangeState:(AISessionState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateStatusForState:state];
    });
}

- (void)aiService:(AIFixService *)service didReceiveMessage:(AIMessage *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addAIMessage:message.content];
    });
}

- (void)aiService:(AIFixService *)service didReceiveToolRequest:(AIToolRequest *)request {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showToolRequest:request];
    });
}

- (void)aiService:(AIFixService *)service didCompleteToolRequest:(AIToolRequest *)request withResult:(AIToolResult *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *message = result.success ? 
            [NSString stringWithFormat:localize(@"ai.fix.tool_success", @"%@ 执行成功"), request.toolDisplayName] :
            [NSString stringWithFormat:@"%@: %@", localize(@"ai.fix.tool_failed", @"执行失败"), result.error.localizedDescription];
        
        [self addToolResultMessage:message isSuccess:result.success];
    });
}

- (void)aiService:(AIFixService *)service didRecordModification:(AIFileModification *)modification {
    // 可以在此显示修改记录
}

- (void)aiService:(AIFixService *)service didEncounterError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addSystemMessage:[NSString stringWithFormat:@"%@: %@", localize(@"ai.fix.error", @"错误"), error.localizedDescription]];
        [_activityIndicator stopAnimating];
    });
}

- (void)aiServiceDidCompleteFix:(AIFixService *)service {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *report = [service generateFixReport];
        (void)report;
        
        [self addSystemMessage:localize(@"ai.fix.completed", @"修复完成！")];
        
        if (service.modifications.count > 0) {
            [self addSystemMessage:[NSString stringWithFormat:localize(@"ai.fix.modifications", @"共修改了 %lu 个文件"), (unsigned long)service.modifications.count]];
        }
        
        [self addSystemMessage:localize(@"ai.fix.restart_hint", @"修复流程已结束。请手动重新启动游戏进行验证：1) 关闭当前游戏实例；2) 返回启动器并重新进入对应配置；3) 正常启动游戏并复现原场景；4) 若问题仍存在，可继续反馈日志或使用撤销修改。")];
        
        [_activityIndicator stopAnimating];
        [self refreshHistoryAndRiskInfo];
    });
}

- (void)refreshHistoryAndRiskInfo {
    if (!_historyStackView || !_riskStackView) return;
    NSUInteger modificationCount = [AIFixService sharedService].modifications.count;
    NSUInteger messageCount = [AIFixService sharedService].messages.count;

    for (UIView *view in _historyStackView.arrangedSubviews.copy) {
        [view removeFromSuperview];
    }
    for (UIView *view in _riskStackView.arrangedSubviews.copy) {
        [view removeFromSuperview];
    }

    NSArray *historyInfos = @[
        @{@"title": localize(@"ai.fix.history.sessions", @"会话记录"), @"value": [NSString stringWithFormat:@"%lu", (unsigned long)messageCount], @"subtitle": localize(@"ai.fix.history.sessions_sub", @"消息与工具调用会被保留"), @"icon": @"clock.arrow.circlepath", @"accent": AFHexColor(@"#F59E0B")},
        @{@"title": localize(@"ai.fix.history.rollback", @"可回滚项"), @"value": [NSString stringWithFormat:@"%lu", (unsigned long)modificationCount], @"subtitle": localize(@"ai.fix.history.rollback_sub", @"修复完成后可撤销最近修改"), @"icon": @"arrow.uturn.backward.circle.fill", @"accent": AFHexColor(@"#8B5CF6")}
    ];
    for (NSDictionary *info in historyInfos) {
        AIDashboardTileView *tile = [[AIDashboardTileView alloc] init];
        [tile configureWithTitle:info[@"title"] value:info[@"value"] subtitle:info[@"subtitle"] icon:info[@"icon"] accent:info[@"accent"] compact:YES];
        [_historyStackView addArrangedSubview:tile];
    }

    NSArray *riskItems = @[
        @{@"title": localize(@"ai.fix.risk.backup", @"修改前已备份"), @"subtitle": localize(@"ai.fix.risk.backup_sub", @"写入、删除与 Mod 改动会尽量保留恢复信息")},
        @{@"title": localize(@"ai.fix.risk.confirm", @"高风险操作需确认"), @"subtitle": localize(@"ai.fix.risk.confirm_sub", @"删除、重命名、Mod 启停不会静默执行")},
        @{@"title": localize(@"ai.fix.risk.verify", @"修复后需手动验证"), @"subtitle": localize(@"ai.fix.risk.verify_sub", @"请启动游戏并观察原崩溃是否消失")}
    ];
    for (NSDictionary *item in riskItems) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
        row.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        row.layer.cornerRadius = 10;
        row.layer.cornerCurve = kCACornerCurveContinuous;
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, _riskStackView.bounds.size.width - 20, 14)];
        title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        title.textColor = [UIColor whiteColor];
        title.text = item[@"title"];
        [row addSubview:title];
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 19, _riskStackView.bounds.size.width - 20, 12)];
        sub.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        sub.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.58];
        sub.text = item[@"subtitle"];
        [row addSubview:sub];
        row.frame = CGRectMake(0, 0, _riskStackView.bounds.size.width, 30);
        [_riskStackView addArrangedSubview:row];
    }
}

#pragma mark - 状态更新

- (void)updateStatusForState:(AISessionState)state {
    NSString *statusText;
    NSString *subtitle = localize(@"ai.fix.ready_subtitle", @"等待输入或开始自动分析");
    UIColor *accent = AFHexColor(@"#3B82F6");

    switch (state) {
        case AISessionStateIdle:
            statusText = localize(@"ai.fix.ready", @"准备就绪");
            [_activityIndicator stopAnimating];
            _stopButton.hidden = YES;
            _sendButton.hidden = NO;
            break;
        case AISessionStateThinking:
            statusText = localize(@"ai.fix.thinking", @"AI 思考中...");
            subtitle = localize(@"ai.fix.thinking_subtitle", @"正在分析日志、配置与环境信息");
            accent = AFHexColor(@"#8B5CF6");
            [_activityIndicator startAnimating];
            _stopButton.hidden = NO;
            _sendButton.hidden = YES;
            break;
        case AISessionStateWaitingTool:
            statusText = localize(@"ai.fix.waiting_confirm", @"等待确认");
            subtitle = localize(@"ai.fix.waiting_subtitle", @"当前操作需要您确认后才会执行");
            accent = AFHexColor(@"#F59E0B");
            [_activityIndicator stopAnimating];
            _stopButton.hidden = NO;
            _sendButton.hidden = YES;
            break;
        case AISessionStateExecutingTool:
            statusText = localize(@"ai.fix.executing", @"执行工具中...");
            subtitle = localize(@"ai.fix.executing_subtitle", @"正在执行受控修复步骤");
            accent = AFHexColor(@"#10B981");
            [_activityIndicator startAnimating];
            _stopButton.hidden = NO;
            _sendButton.hidden = YES;
            break;
        case AISessionStateCompleted:
            statusText = localize(@"ai.fix.completed", @"已完成");
            subtitle = localize(@"ai.fix.completed_subtitle", @"请重新启动游戏验证修复结果");
            accent = AFHexColor(@"#22C55E");
            [_activityIndicator stopAnimating];
            _stopButton.hidden = YES;
            _sendButton.hidden = NO;
            break;
        case AISessionStateError:
            statusText = localize(@"ai.fix.error", @"出错");
            subtitle = localize(@"ai.fix.error_subtitle", @"可以导出报告或回滚最近修改");
            accent = AFHexColor(@"#EF4444");
            [_activityIndicator stopAnimating];
            _stopButton.hidden = YES;
            _sendButton.hidden = NO;
            break;
        case AISessionStateStopped:
            statusText = localize(@"ai.fix.stopped", @"已停止");
            subtitle = localize(@"ai.fix.stopped_subtitle", @"会话已终止，您可以重新开始");
            accent = AFHexColor(@"#64748B");
            [_activityIndicator stopAnimating];
            _stopButton.hidden = YES;
            _sendButton.hidden = NO;
            break;
    }

    _statusLabel.text = statusText;
    _diagnosticSubtitleLabel.text = subtitle;
    _diagnosticStripView.backgroundColor = [accent colorWithAlphaComponent:0.12];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self updatePlaceholderVisibility];
}

- (void)updatePlaceholderVisibility {
    UILabel *placeholder = [_inputContainerView viewWithTag:999];
    placeholder.hidden = _inputTextView.text.length > 0;
}

#pragma mark - Actions

- (void)exitLauncher {
    if ([AIFixService sharedService].isRunning) {
        [[AIFixService sharedService] stopFix];
    }
    
    [self dismissViewControllerAnimated:YES completion:^{
        // 返回启动器
        [[PLCrashView class] performSelector:@selector(dismissAndReturnToLauncher) withObject:nil afterDelay:0];
    }];
}

- (void)stopFix {
    [[AIFixService sharedService] stopFix];
    [self addSystemMessage:localize(@"ai.fix.stopped_by_user", @"已停止修复")];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            _conversationScrollView.contentOffset = CGPointMake(0, _conversationScrollView.contentSize.height - _conversationScrollView.bounds.size.height + _conversationScrollView.contentInset.bottom);
        }];
    } else {
        _conversationScrollView.contentOffset = CGPointMake(0, _conversationScrollView.contentSize.height - _conversationScrollView.bounds.size.height + _conversationScrollView.contentInset.bottom);
    }
}

- (void)showTransientMessage:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 20;
    toast.clipsToBounds = YES;
    
    CGSize size = [message boundingRectWithSize:CGSizeMake(300, 40)
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:@{NSFontAttributeName: toast.font}
                                         context:nil].size;
    
    toast.frame = CGRectMake((self.view.bounds.size.width - size.width - 32) / 2,
                              self.view.bounds.size.height - 100,
                              size.width + 32,
                              40);
    
    [self.view addSubview:toast];
    
    toast.alpha = 0;
    toast.transform = CGAffineTransformMakeTranslation(0, 20);
    
    [UIView animateWithDuration:0.3 animations:^{
        toast.alpha = 1;
        toast.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{
            toast.alpha = 0;
            toast.transform = CGAffineTransformMakeTranslation(0, -20);
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    }];
}

@end

#pragma mark - MessageBubbleView

@implementation MessageBubbleView
@end

#pragma mark - AIDashboardTileView

@implementation AIDashboardTileView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerRadius = 18;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = NO;

        _blurView = LGCCreateGlassEffectView(YES);
        _blurView.translatesAutoresizingMaskIntoConstraints = NO;
        _blurView.layer.cornerRadius = 18;
        _blurView.layer.cornerCurve = kCACornerCurveContinuous;
        _blurView.layer.masksToBounds = YES;
        [self addSubview:_blurView];

        _contentContainer = [[UIView alloc] init];
        _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [_blurView.contentView addSubview:_contentContainer];

        _accentLayer = [CAGradientLayer layer];
        _accentLayer.startPoint = CGPointMake(0, 0.5);
        _accentLayer.endPoint = CGPointMake(1, 0.5);
        [_blurView.contentView.layer addSublayer:_accentLayer];

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_contentContainer addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        [_contentContainer addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        _valueLabel.textColor = [UIColor whiteColor];
        _valueLabel.numberOfLines = 1;
        [_contentContainer addSubview:_valueLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65];
        _subtitleLabel.numberOfLines = 2;
        [_contentContainer addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_contentContainer.topAnchor constraintEqualToAnchor:_blurView.contentView.topAnchor constant:12],
            [_contentContainer.leadingAnchor constraintEqualToAnchor:_blurView.contentView.leadingAnchor constant:12],
            [_contentContainer.trailingAnchor constraintEqualToAnchor:_blurView.contentView.trailingAnchor constant:-12],
            [_contentContainer.bottomAnchor constraintEqualToAnchor:_blurView.contentView.bottomAnchor constant:-12],

            [_iconView.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
            [_iconView.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18],
            [_iconView.heightAnchor constraintEqualToConstant:18],

            [_titleLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],

            [_valueLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:8],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_valueLabel.bottomAnchor constant:4],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title value:(NSString *)value subtitle:(NSString *)subtitle icon:(NSString *)iconName accent:(UIColor *)accent compact:(BOOL)compact {
    self.compactLayout = compact;
    _titleLabel.text = title;
    _valueLabel.text = value;
    _subtitleLabel.text = subtitle;
    _iconView.image = [UIImage systemImageNamed:iconName];
    _iconView.tintColor = accent;
    _accentLayer.colors = @[(id)accent.CGColor, (id)[accent colorWithAlphaComponent:0.35].CGColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _accentLayer.frame = CGRectMake(0, 0, self.bounds.size.width, 2);
}

@end

#pragma mark - ToolRequestCardView

@interface ToolRequestCardView ()

@end

@implementation ToolRequestCardView

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    self.layer.cornerRadius = 10;
    
    // 图标 - 使用 SVG 图标助手
    _iconView = [AIFixSVGIconHelper iconViewForTool:@"" size:28];
    _iconView.frame = CGRectMake(12, 12, 28, 28);
    [self addSubview:_iconView];
    
    // 工具名称
    _toolNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(48, 12, self.bounds.size.width - 60, 24)];
    _toolNameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _toolNameLabel.textColor = [UIColor whiteColor];
    [self addSubview:_toolNameLabel];
    
    // 描述
    _descriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 40, self.bounds.size.width - 24, 20)];
    _descriptionLabel.font = [UIFont systemFontOfSize:12];
    _descriptionLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    _descriptionLabel.numberOfLines = 2;
    [self addSubview:_descriptionLabel];
    
    // 参数显示
    _parametersTextView = [[UITextView alloc] initWithFrame:CGRectMake(12, 64, self.bounds.size.width - 24, 48)];
    _parametersTextView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    _parametersTextView.layer.cornerRadius = 6;
    _parametersTextView.font = [UIFont fontWithName:@"Menlo" size:10];
    _parametersTextView.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    _parametersTextView.editable = NO;
    _parametersTextView.scrollEnabled = YES;
    [self addSubview:_parametersTextView];
    
    // 同意按钮 - 添加图标
    _approveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _approveButton.frame = CGRectMake(12, 120, (self.bounds.size.width - 32) / 2, 32);
    
    // 使用 SF Symbol 图标
    if (@available(iOS 13.0, *)) {
        UIImage *checkIcon = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        [_approveButton setImage:checkIcon forState:UIControlStateNormal];
        _approveButton.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
        _approveButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 0);
    }
    
    [_approveButton setTitle:localize(@"ai.fix.approve", @"同意") forState:UIControlStateNormal];
    _approveButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _approveButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.4 alpha:1.0];
    _approveButton.layer.cornerRadius = 8;
    _approveButton.tintColor = [UIColor whiteColor];
    [_approveButton addTarget:self action:@selector(approveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_approveButton];
    
    // 拒绝按钮 - 添加图标
    _rejectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _rejectButton.frame = CGRectMake(self.bounds.size.width / 2 + 4, 120, (self.bounds.size.width - 32) / 2, 32);
    
    // 使用 SF Symbol 图标
    if (@available(iOS 13.0, *)) {
        UIImage *xIcon = [UIImage systemImageNamed:@"xmark.circle.fill"];
        [_rejectButton setImage:xIcon forState:UIControlStateNormal];
        _rejectButton.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
        _rejectButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 0);
    }
    
    [_rejectButton setTitle:localize(@"ai.fix.reject", @"拒绝") forState:UIControlStateNormal];
    _rejectButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _rejectButton.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:1.0];
    _rejectButton.layer.cornerRadius = 8;
    _rejectButton.tintColor = [UIColor whiteColor];
    [_rejectButton addTarget:self action:@selector(rejectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_rejectButton];
}

- (void)approveTapped {
    if (self.onApprove) {
        self.onApprove();
    }
}

- (void)rejectTapped {
    if (self.onReject) {
        self.onReject();
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat yOffset = 12;
    
    // 如果有 Mod 预览，调整布局
    if (_modPreviewContainer && !_modPreviewContainer.hidden) {
        _modPreviewContainer.frame = CGRectMake(12, yOffset, self.bounds.size.width - 24, 70);
        yOffset += 78;
    }
    
    _iconView.frame = CGRectMake(12, yOffset, 28, 28);
    _toolNameLabel.frame = CGRectMake(48, yOffset, self.bounds.size.width - 60, 24);
    yOffset += 28;
    
    _descriptionLabel.frame = CGRectMake(12, yOffset, self.bounds.size.width - 24, 20);
    yOffset += 24;
    
    _parametersTextView.frame = CGRectMake(12, yOffset, self.bounds.size.width - 24, 48);
    yOffset += 52;
    
    _approveButton.frame = CGRectMake(12, yOffset, (self.bounds.size.width - 32) / 2, 32);
    _rejectButton.frame = CGRectMake(self.bounds.size.width / 2 + 4, yOffset, (self.bounds.size.width - 32) / 2, 32);
}

#pragma mark - Mod 预览

- (void)setupModPreview {
    // Mod 预览容器
    _modPreviewContainer = [[UIView alloc] init];
    _modPreviewContainer.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    _modPreviewContainer.layer.cornerRadius = 8;
    _modPreviewContainer.hidden = YES;
    [self addSubview:_modPreviewContainer];
    
    // Mod 图标
    _modIconView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 10, 50, 50)];
    _modIconView.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    _modIconView.layer.cornerRadius = 10;
    _modIconView.clipsToBounds = YES;
    _modIconView.contentMode = UIViewContentModeScaleAspectFill;
    [_modPreviewContainer addSubview:_modIconView];
    
    // Mod 名称
    _modNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(72, 10, _modPreviewContainer.bounds.size.width - 84, 22)];
    _modNameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _modNameLabel.textColor = [UIColor whiteColor];
    [_modPreviewContainer addSubview:_modNameLabel];
    
    // Mod 描述
    _modDescLabel = [[UILabel alloc] initWithFrame:CGRectMake(72, 32, _modPreviewContainer.bounds.size.width - 84, 18)];
    _modDescLabel.font = [UIFont systemFontOfSize:11];
    _modDescLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    _modDescLabel.numberOfLines = 2;
    [_modPreviewContainer addSubview:_modDescLabel];
    
    // 状态标签
    _modStatusLabels = [[UILabel alloc] initWithFrame:CGRectMake(72, 52, _modPreviewContainer.bounds.size.width - 84, 16)];
    _modStatusLabels.font = [UIFont systemFontOfSize:10];
    _modStatusLabels.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    [_modPreviewContainer addSubview:_modStatusLabels];
}

- (void)showModPreviewWithName:(NSString *)modName 
                       iconPath:(NSString *)iconPath 
                    description:(NSString *)description 
                       willEnable:(BOOL)willEnable {
    if (!_modPreviewContainer) {
        [self setupModPreview];
    }
    
    _modPreviewContainer.hidden = NO;
    
    // 设置 Mod 名称
    _modNameLabel.text = modName ?: @"Unknown Mod";
    
    // 设置描述
    _modDescLabel.text = description ?: @"暂无描述";
    
    // 设置状态 - 使用 SF Symbols 图标替代 Emoji
    if (willEnable) {
        // 使用 checkmark.circle.fill SF Symbol 作为启用图标
        if (@available(iOS 13.0, *)) {
            UIImage *icon = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            if (icon) {
                NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                attachment.image = [icon imageWithTintColor:[UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0]];
                attachment.bounds = CGRectMake(0, -2, 14, 14);
                NSAttributedString *iconString = [NSAttributedString attributedStringWithAttachment:attachment];
                NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
                [attrString appendAttributedString:iconString];
                [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:@" 将启用此 Mod" attributes:@{
                    NSForegroundColorAttributeName: [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0],
                    NSFontAttributeName: [UIFont systemFontOfSize:10]
                }]];
                _modStatusLabels.attributedText = attrString;
            } else {
                _modStatusLabels.text = @"将启用此 Mod";
                _modStatusLabels.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0];
            }
        } else {
            _modStatusLabels.text = @"将启用此 Mod";
            _modStatusLabels.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0];
        }
    } else {
        // 使用 xmark.circle.fill SF Symbol 作为禁用图标
        if (@available(iOS 13.0, *)) {
            UIImage *icon = [UIImage systemImageNamed:@"xmark.circle.fill"];
            if (icon) {
                NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                attachment.image = [icon imageWithTintColor:[UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0]];
                attachment.bounds = CGRectMake(0, -2, 14, 14);
                NSAttributedString *iconString = [NSAttributedString attributedStringWithAttachment:attachment];
                NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
                [attrString appendAttributedString:iconString];
                [attrString appendAttributedString:[[NSAttributedString alloc] initWithString:@" 将禁用此 Mod" attributes:@{
                    NSForegroundColorAttributeName: [UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0],
                    NSFontAttributeName: [UIFont systemFontOfSize:10]
                }]];
                _modStatusLabels.attributedText = attrString;
            } else {
                _modStatusLabels.text = @"将禁用此 Mod";
                _modStatusLabels.textColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0];
            }
        } else {
            _modStatusLabels.text = @"将禁用此 Mod";
            _modStatusLabels.textColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0];
        }
    }
    
    // 加载图标
    if (iconPath.length > 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *icon = [UIImage imageWithContentsOfFile:iconPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.modIconView.image = icon ?: [AIFixSVGIconHelper svgImageNamed:@"cube" 
                                                                          withColor:[UIColor colorWithWhite:0.5 alpha:1.0] 
                                                                              size:CGSizeMake(50, 50)];
            });
        });
    } else {
        // 使用默认 SVG 图标
        _modIconView.image = [AIFixSVGIconHelper svgImageNamed:@"cube" 
                                                     withColor:[UIColor colorWithWhite:0.5 alpha:1.0] 
                                                         size:CGSizeMake(50, 50)];
    }
    
    // 调整卡片高度
    [self setNeedsLayout];
}

- (void)hideModPreview {
    _modPreviewContainer.hidden = YES;
    [self setNeedsLayout];
}

- (void)replaceIconWithNewIcon:(UIImageView *)newIcon {
    [_iconView removeFromSuperview];
    _iconView = newIcon;
    [self addSubview:_iconView];
}

@end

#pragma mark - AIFixSVGIconHelper

@implementation AIFixSVGIconHelper

+ (UIImage *)svgImageNamed:(NSString *)name withColor:(UIColor *)color size:(CGSize)size {
    // 使用 SF Symbols 作为 SVG 替代方案（iOS 13+）
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size.width weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleLarge];
        UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
        if (image && color) {
            return [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        return image;
    }
    
    // iOS 13 以下回退方案：生成简单图形
    return [self fallbackImageWithColor:color size:size];
}

+ (UIImage *)svgImageFromData:(NSData *)data withColor:(UIColor *)color size:(CGSize)size {
    // 简化实现：使用 Core Graphics 绘制
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    [color setFill];
    CGContextFillEllipseInRect(context, CGRectMake(0, 0, size.width, size.height));
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

+ (UIImageView *)iconViewForTool:(NSString *)toolName size:(CGFloat)size {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    
    NSString *iconName;
    UIColor *iconColor;
    
    if ([toolName containsString:@"toggle_mod"] || [toolName containsString:@"Mod"]) {
        iconName = @"cube.box";
        iconColor = [UIColor colorWithRed:0.4 green:0.7 blue:0.4 alpha:1.0];
    } else if ([toolName containsString:@"delete_mod"]) {
        iconName = @"trash";
        iconColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:1.0];
    } else if ([toolName containsString:@"read_file"]) {
        iconName = @"doc.text";
        iconColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:1.0];
    } else if ([toolName containsString:@"write_file"] || [toolName containsString:@"append_file"]) {
        iconName = @"pencil.and.outline";
        iconColor = [UIColor colorWithRed:0.9 green:0.6 blue:0.3 alpha:1.0];
    } else if ([toolName containsString:@"setting"]) {
        iconName = @"gearshape";
        iconColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    } else if ([toolName containsString:@"profile"]) {
        iconName = @"person.crop.circle";
        iconColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:1.0];
    } else if ([toolName containsString:@"log"]) {
        iconName = @"list.bullet.rectangle";
        iconColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    } else if ([toolName containsString:@"crash"]) {
        iconName = @"exclamationmark.triangle";
        iconColor = [UIColor colorWithRed:0.9 green:0.5 blue:0.3 alpha:1.0];
    } else {
        iconName = @"wrench.and.screwdriver";
        iconColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    }
    
    imageView.image = [self svgImageNamed:iconName withColor:iconColor size:CGSizeMake(size, size)];
    return imageView;
}

+ (UIImage *)fallbackImageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(size.width * 0.1, size.height * 0.1, size.width * 0.8, size.height * 0.8));
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@end

