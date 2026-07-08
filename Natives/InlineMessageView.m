//
//  InlineMessageView.m
//  Amethyst
//
//  参照 FCL/ZL2 的内联消息显示，替代 UIAlertController 弹窗
//

#import "InlineMessageView.h"
#import "LiquidGlassCompat.h"
#import "utils.h"

@interface InlineMessageView ()

@property (nonatomic, strong) UIView *containerView;     // 毛玻璃容器
@property (nonatomic, strong) UIStackView *stackView;    // 垂直布局
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSTimer *autoDismissTimer;
@property (nonatomic, weak) UIViewController *hostViewController;
@property (nonatomic, assign) InlineMessageType messageType;

@end

@implementation InlineMessageView

+ (instancetype)showInViewController:(UIViewController *)vc
                             title:(NSString *)title
                          message:(nullable NSString *)message
                             type:(InlineMessageType)type {
    return [self showInViewController:vc title:title message:message type:type showsCloseButton:NO];
}

+ (instancetype)showInViewController:(UIViewController *)vc
                             title:(NSString *)title
                          message:(nullable NSString *)message
                             type:(InlineMessageType)type
                  showsCloseButton:(BOOL)showsCloseButton {
    // 如果已存在则先移除
    for (UIView *sub in vc.view.subviews) {
        if ([sub isKindOfClass:[InlineMessageView class]]) {
            [(InlineMessageView *)sub dismissImmediately];
        }
    }

    InlineMessageView *view = [[InlineMessageView alloc] initWithFrame:vc.view.bounds];
    view.hostViewController = vc;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.15];  // 轻微遮罩
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.showsCloseButton = showsCloseButton;

    [vc.view addSubview:view];
    // 居中布局
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
    ]];

    [view setupUIWithTitle:title message:message type:type];
    view.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{
        view.alpha = 1;
    }];

    return view;
}

- (void)setupUIWithTitle:(NSString *)title message:(NSString *)message type:(InlineMessageType)type {
    _messageType = type;

    // 毛玻璃容器
    self.containerView = [[UIView alloc] init];
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerView.layer.cornerRadius = 16;
    self.containerView.layer.masksToBounds = YES;
    self.containerView.layer.borderWidth = 1;
    self.containerView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.1].CGColor;

    // 根据类型设置背景色（iOS 26+ 液态玻璃 / 低版本毛玻璃）
    UIVisualEffectView *blurView = LGCCreateGlassEffectView(NO);
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:blurView];

    // 背景色覆盖（根据类型）
    UIView *tintView = [[UIView alloc] init];
    tintView.translatesAutoresizingMaskIntoConstraints = NO;
    UIColor *tintColor = [self tintColorForType:type];
    tintView.backgroundColor = [tintColor colorWithAlphaComponent:0.15];
    [self.containerView insertSubview:tintView belowSubview:blurView];

    [self addSubview:self.containerView];

    // StackView：图标/转圈 + 文本 + 关闭按钮
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    self.stackView.spacing = 10;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.containerView addSubview:self.stackView];

    // 第一行：图标/转圈 + 标题 + 关闭按钮（水平排列）
    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.spacing = 10;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;

    if (type == InlineMessageTypeLoading) {
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [self.activityIndicator startAnimating];
        [headerStack addArrangedSubview:self.activityIndicator];
    } else {
        self.iconImageView = [[UIImageView alloc] init];
        NSString *iconName = @"";
        switch (type) {
            case InlineMessageTypeError:   iconName = @"xmark.circle.fill"; break;
            case InlineMessageTypeSuccess: iconName = @"checkmark.circle.fill"; break;
            case InlineMessageTypeInfo:    iconName = @"info.circle.fill"; break;
            default: break;
        }
        if (iconName.length > 0) {
            UIImage *icon = [UIImage systemImageNamed:iconName];
            self.iconImageView.image = icon;
            self.iconImageView.tintColor = tintColor;
            self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
            [headerStack addArrangedSubview:self.iconImageView];
            [NSLayoutConstraint activateConstraints:@[
                [self.iconImageView.widthAnchor constraintEqualToConstant:24],
                [self.iconImageView.heightAnchor constraintEqualToConstant:24],
            ]];
        }
    }

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = title ?: @"";
    self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [headerStack addArrangedSubview:self.titleLabel];

    // 错误类型或显式要求时显示关闭按钮
    if (type == InlineMessageTypeError || self.showsCloseButton) {
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *closeIcon = [UIImage systemImageNamed:@"xmark"];
        [self.closeButton setImage:closeIcon forState:UIControlStateNormal];
        self.closeButton.tintColor = [UIColor secondaryLabelColor];
        [self.closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [headerStack addArrangedSubview:self.closeButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.closeButton.widthAnchor constraintEqualToConstant:28],
            [self.closeButton.heightAnchor constraintEqualToConstant:28],
        ]];
    }

    // 点击手势（用于 loading 类型提供"查看详情"等入口）
    if (type == InlineMessageTypeLoading) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        self.containerView.userInteractionEnabled = YES;
        [self.containerView addGestureRecognizer:tap];
    }

    [self.stackView addArrangedSubview:headerStack];

    // 第二行：消息文本（如果有）
    if (message.length > 0) {
        self.messageLabel = [[UILabel alloc] init];
        self.messageLabel.text = message;
        self.messageLabel.font = [UIFont systemFontOfSize:13];
        self.messageLabel.textColor = [UIColor secondaryLabelColor];
        self.messageLabel.numberOfLines = 0;
        self.messageLabel.textAlignment = NSTextAlignmentCenter;
        self.messageLabel.preferredMaxLayoutWidth = 260;
        [self.stackView addArrangedSubview:self.messageLabel];
    }

    // 布局
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.containerView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.containerView.widthAnchor constraintLessThanOrEqualToConstant:320],
        [self.containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
        [self.containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24],

        [blurView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],

        [tintView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [tintView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        [tintView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [tintView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:20],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-20],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:20],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-20],
    ]];

    // 自动消失（成功/信息类）
    if (type == InlineMessageTypeSuccess || type == InlineMessageTypeInfo) {
        __weak typeof(self) weakSelf = self;
        self.autoDismissTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                                 repeats:NO
                                                                   block:^(NSTimer *t) {
            [weakSelf dismiss];
        }];
    }
}

- (UIColor *)tintColorForType:(InlineMessageType)type {
    switch (type) {
        case InlineMessageTypeError:   return [UIColor systemRedColor];
        case InlineMessageTypeSuccess: return [UIColor systemGreenColor];
        case InlineMessageTypeInfo:    return [UIColor systemBlueColor];
        case InlineMessageTypeLoading: return [UIColor systemBlueColor];
    }
    return [UIColor systemBlueColor];
}

- (void)updateWithMessage:(NSString *)message type:(InlineMessageType)type {
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;

    // 直接重建 UI
    [self.containerView removeFromSuperview];
    [self setupUIWithTitle:self.titleLabel.text message:message type:type];
}

- (void)updateMessage:(NSString *)message {
    // 仅更新消息文本，保持当前类型与布局
    if (self.messageLabel) {
        self.messageLabel.text = message;
    } else if (message.length > 0) {
        // 之前没有 messageLabel，需要重建以添加
        [self updateWithMessage:message type:self.messageType];
    }
}

- (void)handleTap {
    if (self.onTap) {
        self.onTap();
    }
}

- (void)closeButtonTapped {
    if (self.onClose) {
        // 自定义关闭逻辑（如取消下载），由调用方负责调用 dismiss
        self.onClose();
    } else {
        [self dismiss];
    }
}

- (void)dismiss {
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;
    [self.activityIndicator stopAnimating];

    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)dismissImmediately {
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;
    [self.activityIndicator stopAnimating];
    [self removeFromSuperview];
}

@end
