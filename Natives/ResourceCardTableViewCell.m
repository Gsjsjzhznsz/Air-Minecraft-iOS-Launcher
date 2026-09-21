//
//  ResourceCardTableViewCell.m
//  Amethyst
//
//  资源管理卡片 Cell 公共基类实现（Air-Design L2 标准卡片，参照 VersionCardCell 正面基准）。
//

#import "ResourceCardTableViewCell.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"

static NSString * const kResourceCardDefaultIcon = @"doc.fill";

@interface ResourceCardTableViewCell ()
// 内容视图（.h 中 readonly，内部可写）
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
// accessory 插槽
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIImageView *chevronImageView;
@property (nonatomic, strong) UIImageView *updateBadge;
// 中部文字纵向 stack / 右侧 accessory 横向 stack（stack 自动收起隐藏的 arrangedSubview）
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UIStackView *accessoryStack;
// 选中态染色层（accent 0.08，位于毛玻璃之上、内容之下）
@property (nonatomic, strong) UIView *selectionTintView;
// 批量选择模式开关
@property (nonatomic, assign) BOOL selectionModeEnabled;
@end

@implementation ResourceCardTableViewCell

#pragma mark - Init

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        // ----- 外层 cell：不裁剪，承载轻阴影（Air-Design 5.2 轻阴影档：0.10/4/(0,2)）-----
        // shadowPath 在 layoutSubviews 中随 bounds 更新
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.10;
        self.layer.shadowRadius = 4.0;
        self.layer.shadowOffset = CGSizeMake(0, 2);

        // ----- 卡片本体 = contentView：半透明基底 + 12pt continuous 圆角 + 0.5pt 描边，裁圆角 -----
        self.contentView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        self.contentView.layer.cornerRadius = 12.0;  // Task137：回归原生卡片圆角
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 0.5;
        self.contentView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
        self.contentView.layer.masksToBounds = YES;

        [self createSubviews];

        // 第 2 层：BackgroundManager 毛玻璃（毛玻璃/半透明随用户设置自适应，
        // 与 VersionCardCell / 各资源管理页现有做法一致）
        [[BackgroundManager sharedManager] applyEffectToView:self.contentView];

        // 选中染色层插到毛玻璃之上（index 1）、内容之下
        [self.contentView insertSubview:self.selectionTintView atIndex:1];

        [self setupConstraints];
    }
    return self;
}

#pragma mark - UI 构建

- (void)createSubviews {
    // 左侧图标容器：40×40 / 10pt continuous 圆角 / 类型语义色背景
    _iconContainer = [[UIView alloc] init];
    _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _iconContainer.layer.cornerRadius = 10.0;
    _iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
    _iconContainer.layer.masksToBounds = YES;
    _iconContainer.backgroundColor = [UIColor systemGrayColor];

    // 图标本体：白色 SF Symbol，22×22 居中
    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    _iconImageView.tintColor = [UIColor whiteColor];
    _iconImageView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIFontWeightMedium];
    _iconImageView.image = [UIImage systemImageNamed:kResourceCardDefaultIcon];
    [_iconContainer addSubview:_iconImageView];

    // 中部文字
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _nameLabel.textColor = [UIColor labelColor];
    _nameLabel.adjustsFontSizeToFitWidth = YES;
    _nameLabel.minimumScaleFactor = 0.7;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    _subtitleLabel.adjustsFontSizeToFitWidth = YES;
    _subtitleLabel.minimumScaleFactor = 0.7;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _subtitleLabel.hidden = YES;

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _detailLabel.textColor = [UIColor tertiaryLabelColor];
    _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _detailLabel.hidden = YES;

    _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _subtitleLabel, _detailLabel]];
    _textStack.translatesAutoresizingMaskIntoConstraints = NO;
    _textStack.axis = UILayoutConstraintAxisVertical;
    _textStack.alignment = UIStackViewAlignmentFill;
    _textStack.distribution = UIStackViewDistributionFill;
    _textStack.spacing = 2.0;

    // 右侧 accessory 插槽区（具体插槽懒加载插入）
    _accessoryStack = [[UIStackView alloc] init];
    _accessoryStack.translatesAutoresizingMaskIntoConstraints = NO;
    _accessoryStack.axis = UILayoutConstraintAxisHorizontal;
    _accessoryStack.alignment = UIStackViewAlignmentCenter;
    _accessoryStack.spacing = 10.0;

    // 选中染色层：accent 0.08，铺满卡片，默认隐藏
    _selectionTintView = [[UIView alloc] init];
    _selectionTintView.translatesAutoresizingMaskIntoConstraints = NO;
    _selectionTintView.backgroundColor = [accentColor() colorWithAlphaComponent:0.08];
    _selectionTintView.layer.cornerRadius = 12.0;
    _selectionTintView.layer.cornerCurve = kCACornerCurveContinuous;
    _selectionTintView.userInteractionEnabled = NO;
    _selectionTintView.hidden = YES;

    [self.contentView addSubview:_iconContainer];
    [self.contentView addSubview:_textStack];
    [self.contentView addSubview:_accessoryStack];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // 图标容器：左 12（space-xl），垂直居中，40×40
        [self.iconContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.iconContainer.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconContainer.widthAnchor constraintEqualToConstant:40],
        [self.iconContainer.heightAnchor constraintEqualToConstant:40],

        // 图标本体居中，22×22
        [self.iconImageView.centerXAnchor constraintEqualToAnchor:self.iconContainer.centerXAnchor],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.iconContainer.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:22],
        [self.iconImageView.heightAnchor constraintEqualToConstant:22],

        // 文字区：紧跟图标 +12，垂直居中，右侧让位 accessory
        [self.textStack.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:12],
        [self.textStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.accessoryStack.leadingAnchor constant:-8],
        [self.textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],

        // accessory 区：右 -12，垂直居中
        [self.accessoryStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.accessoryStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        // 选中染色层铺满卡片
        [self.selectionTintView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.selectionTintView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.selectionTintView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.selectionTintView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];
}

#pragma mark - 懒加载 accessory 插槽（默认隐藏）

- (UISwitch *)toggleSwitch {
    if (!_toggleSwitch) {
        _toggleSwitch = [[UISwitch alloc] init];
        _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleSwitch.hidden = YES;
        // 缩小开关尺寸以适配紧凑卡片（与 ModTableViewCell 现有做法一致）
        _toggleSwitch.transform = CGAffineTransformMakeScale(0.78, 0.78);
        [self.accessoryStack addArrangedSubview:_toggleSwitch];
    }
    return _toggleSwitch;
}

- (UIImageView *)chevronImageView {
    if (!_chevronImageView) {
        _chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        _chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronImageView.tintColor = [UIColor tertiaryLabelColor];
        _chevronImageView.hidden = YES;
        [_chevronImageView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_chevronImageView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.accessoryStack addArrangedSubview:_chevronImageView];
        [NSLayoutConstraint activateConstraints:@[
            [_chevronImageView.widthAnchor constraintEqualToConstant:14],
            [_chevronImageView.heightAnchor constraintEqualToConstant:14],
        ]];
    }
    return _chevronImageView;
}

- (UIImageView *)updateBadge {
    if (!_updateBadge) {
        _updateBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"]];
        _updateBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _updateBadge.contentMode = UIViewContentModeScaleAspectFit;
        _updateBadge.tintColor = accentColor();
        _updateBadge.hidden = YES;
        [_updateBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_updateBadge setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.accessoryStack addArrangedSubview:_updateBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_updateBadge.widthAnchor constraintEqualToConstant:16],
            [_updateBadge.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    return _updateBadge;
}

#pragma mark - 配置

- (void)configureWithIcon:(NSString *)sfSymbolName
                iconColor:(UIColor *)color
                    title:(NSString *)title
                 subtitle:(NSString *)subtitle
                   detail:(NSString *)detail {
    self.iconImageView.image = [UIImage systemImageNamed:sfSymbolName.length > 0 ? sfSymbolName : kResourceCardDefaultIcon]
                               ?: [UIImage systemImageNamed:kResourceCardDefaultIcon];
    self.iconContainer.backgroundColor = color ?: [UIColor systemGrayColor];

    self.nameLabel.text = title;

    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = (subtitle.length == 0);

    self.detailLabel.text = detail;
    self.detailLabel.hidden = (detail.length == 0);
}

#pragma mark - 选中态（批量选择模式）

- (void)setSelectionModeEnabled:(BOOL)enabled {
    if (_selectionModeEnabled == enabled) return;
    _selectionModeEnabled = enabled;
    [self updateCardSelectionVisual];
}

- (void)setCardSelected:(BOOL)selected animated:(BOOL)animated {
    // 走本类 setSelected: 覆写，保证选中视觉同步更新
    [self setSelected:selected animated:animated];
}

// UITableView 编辑（勾选）模式进入/退出时自动同步选择模式标志
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    _selectionModeEnabled = editing;
    [self updateCardSelectionVisual];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self updateCardSelectionVisual];
}

- (void)updateCardSelectionVisual {
    BOOL highlighted = _selectionModeEnabled && self.isSelected;
    if (highlighted) {
        // 选中态三层反馈之前两层：1.5pt accent 描边 + accent 0.08 染色
        self.contentView.layer.borderColor = accentColor().CGColor;
        self.contentView.layer.borderWidth = 1.5;
        self.selectionTintView.backgroundColor = [accentColor() colorWithAlphaComponent:0.08];
        self.selectionTintView.hidden = NO;
    } else {
        // 默认态：0.5pt 白 0.10 描边（Air-Design 5.3 边框规格）
        self.contentView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
        self.contentView.layer.borderWidth = 0.5;
        self.selectionTintView.hidden = YES;
    }
}

#pragma mark - Layout / Reuse

- (void)layoutSubviews {
    [super layoutSubviews];
    // shadowPath 跟随 contentView 实际 frame（编辑模式缩进时阴影同步跟随），
    // 外层不裁剪（masksToBounds = NO）以保留阴影
    CGRect shadowRect = self.contentView.frame;
    if (!CGRectIsEmpty(shadowRect)) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowRect cornerRadius:12.0].CGPath;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.subtitleLabel.hidden = YES;
    self.detailLabel.text = nil;
    self.detailLabel.hidden = YES;
    self.iconImageView.image = [UIImage systemImageNamed:kResourceCardDefaultIcon];
    self.iconContainer.backgroundColor = [UIColor systemGrayColor];

    // accessory 插槽复位为隐藏（子类按需重新显示）
    if (_toggleSwitch) {
        _toggleSwitch.hidden = YES;
        [_toggleSwitch setOn:NO animated:NO];
    }
    if (_chevronImageView) _chevronImageView.hidden = YES;
    if (_updateBadge) _updateBadge.hidden = YES;

    [super setSelected:NO animated:NO];
    [self updateCardSelectionVisual];
}

@end
