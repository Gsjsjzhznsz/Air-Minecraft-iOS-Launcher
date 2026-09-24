//
//  UIKit+NativeSurface.m
//  Amethyst
//
//  Task137：原生表面样式辅助实现（设计说明见头文件）。
//  Task160：新拟态回归——表面/阴影/文字色按用户 CSS 规格重建（见 .h 注释）。
//

#import "UIKit+NativeSurface.h"
#import <objc/runtime.h>

const CGFloat AmeNeumorphBaseDimension = 340.0;

#pragma mark - Task160 新拟态规格色（动态 provider，深浅色自适应）

static UIColor *AmeNeumorphDynamicColor(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        }];
    }
    return light;
}

UIColor *AmeNeumorphSurfaceColor(void) {
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0xE0/255.0 green:0xE0/255.0 blue:0xE0/255.0 alpha:1.0],   // #e0e0e0
                                   [UIColor colorWithRed:0x2C/255.0 green:0x2C/255.0 blue:0x2C/255.0 alpha:1.0]);  // #2c2c2c
}

UIColor *AmeNeumorphShadowColor(void) {
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0xBE/255.0 green:0xBE/255.0 blue:0xBE/255.0 alpha:1.0],   // #bebebe
                                   [UIColor colorWithRed:0x1E/255.0 green:0x1E/255.0 blue:0x1E/255.0 alpha:1.0]);  // #1e1e1e
}

UIColor *AmeNeumorphHighlightColor(void) {
    return AmeNeumorphDynamicColor([UIColor whiteColor],                                                            // #ffffff
                                   [UIColor colorWithRed:0x3A/255.0 green:0x3A/255.0 blue:0x3A/255.0 alpha:1.0]);   // #3a3a3a
}

UIColor *AmeNeumorphPrimaryTextColor(void) {
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0x33/255.0 green:0x33/255.0 blue:0x33/255.0 alpha:1.0],   // #333333
                                   [UIColor colorWithRed:0xF5/255.0 green:0xF5/255.0 blue:0xF5/255.0 alpha:1.0]);  // #f5f5f5
}

UIColor *AmeNeumorphSecondaryTextColor(void) {
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0x88/255.0 green:0x88/255.0 blue:0x88/255.0 alpha:1.0],   // #888888
                                   [UIColor colorWithRed:0xA0/255.0 green:0xA0/255.0 blue:0xA0/255.0 alpha:1.0]);  // #a0a0a0
}

void AmeNeumorphMetricsForSide(CGFloat side,
                               CGFloat *radiusOut,
                               CGFloat *offsetOut,
                               CGFloat *blurOut) {
    // Task160：按元素短边等比（340pt = 100% 规格），下限防小元素过圆/阴影不可见
    CGFloat scale = side / AmeNeumorphBaseDimension;
    if (scale < 0.0) scale = 0.0;
    if (scale > 1.0) scale = 1.0;
    if (radiusOut) *radiusOut = MAX(8.0, 50.0 * scale);
    if (offsetOut) *offsetOut = MAX(4.0, 20.0 * scale);
    if (blurOut) *blurOut = MAX(12.0, 60.0 * scale); // CSS 20:60 = 1:3
}

#pragma mark - Task160 双阴影承载视图

static void *kAmeNeumorphShadowViewKey = &kAmeNeumorphShadowViewKey;

@interface AmeNeumorphShadowView ()
@property (nonatomic, strong) CALayer *ame160_darkLayer;
@property (nonatomic, strong) CALayer *ame160_lightLayer;
@end

@implementation AmeNeumorphShadowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        // 只画投影不画块：元素本体色由宿主自绘，两层 backgroundColor = clear
        _ame160_darkLayer = [CALayer layer];
        _ame160_darkLayer.backgroundColor = [UIColor clearColor].CGColor;
        _ame160_darkLayer.masksToBounds = NO;
        [self.layer addSublayer:_ame160_darkLayer];

        _ame160_lightLayer = [CALayer layer];
        _ame160_lightLayer.backgroundColor = [UIColor clearColor].CGColor;
        _ame160_lightLayer.masksToBounds = NO;
        [self.layer addSublayer:_ame160_lightLayer];

        [self ame_refreshForHostBounds];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ame_refreshForHostBounds];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
            [self ame_refreshForHostBounds];
        }
    }
}

/// 按宿主（superview）当前 bounds 短边重算度量并同步两层投影与宿主圆角
- (void)ame_refreshForHostBounds {
    UIView *host = self.superview;
    CGFloat side = 0.0;
    CGFloat radius = 8.0;
    if (host) {
        side = MIN(host.bounds.size.width, host.bounds.size.height);
        // 宿主圆角：等比度量（调用点显式圆角由三方法写入 host.layer 后被本
        // 方法覆盖为新拟态规格圆角；AME160 约定新拟态元素圆角统一跟随规格）
        CGFloat offset = 4.0, blur = 12.0;
        AmeNeumorphMetricsForSide(side, &radius, &offset, &blur);

        self.ame160_darkLayer.frame = self.bounds;
        self.ame160_lightLayer.frame = self.bounds;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius];
        self.ame160_darkLayer.shadowPath = path.CGPath;
        self.ame160_lightLayer.shadowPath = path.CGPath;
        self.ame160_darkLayer.cornerRadius = radius;
        self.ame160_lightLayer.cornerRadius = radius;

        // 暗影：右下（+offset, +offset）；高光：左上（-offset, -offset）
        self.ame160_darkLayer.shadowColor = AmeNeumorphShadowColor().CGColor;
        self.ame160_darkLayer.shadowOpacity = 1.0;
        self.ame160_darkLayer.shadowOffset = CGSizeMake(offset, offset);
        self.ame160_darkLayer.shadowRadius = blur;

        self.ame160_lightLayer.shadowColor = AmeNeumorphHighlightColor().CGColor;
        self.ame160_lightLayer.shadowOpacity = 1.0;
        self.ame160_lightLayer.shadowOffset = CGSizeMake(-offset, -offset);
        self.ame160_lightLayer.shadowRadius = blur;
    }
    if (host) host.layer.cornerRadius = radius;
}

@end

#pragma mark - Task160 表面分类

@implementation UIView (AmeNativeSurface)

/// 新拟态表面（Task160）：规格表面色 + 双阴影承载视图 + masksToBounds = NO。
/// 圆角由阴影承载视图按宿主短边等比写入规格值（下限 8，封顶 50）。
- (void)ame_applyNeumorphSurface {
    self.backgroundColor = AmeNeumorphSurfaceColor();
    self.layer.masksToBounds = NO; // Task137 教训：YES 会裁掉外阴影

    AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);
    if (!shadowView) {
        shadowView = [[AmeNeumorphShadowView alloc] initWithFrame:self.bounds];
        shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self insertSubview:shadowView atIndex:0];
        objc_setAssociatedObject(self, kAmeNeumorphShadowViewKey, shadowView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    shadowView.frame = self.bounds; // 非自动布局场景立即对齐；autoresizing 兜后续
    [shadowView setNeedsLayout];
}

- (void)ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius {
    // Task160：cell/列表场景平贴版——只上规格表面色与圆角，无阴影层（避免
    // 被相邻 cell/tableView 裁剪互叠），裁剪保持（Task152 直角露出修复不变）
    self.backgroundColor = AmeNeumorphSurfaceColor();
    self.layer.cornerRadius = MAX(8.0, MIN(cornerRadius, 50.0));
    self.layer.masksToBounds = YES;
}

- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task160：新拟态表面（表面色/圆角/双阴影统一规格口径；传入圆角仅作为
    // 小于等比结果时的视觉保底——规格圆角不低于 min(传入值, 等比结果) 由
    // 度量下限 8 兜底）。Task137 语义的 secondarySystemGroupedBackground 退役。
    [self ame_applyNeumorphSurface];
}

- (void)ame_applyRaisedCardSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task160：嵌套凸起卡片同款新拟态表面（凸起感由双阴影 + 层级关系呈现）
    [self ame_applyNeumorphSurface];
}

- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task160：平贴面板同款新拟态表面。旧约定"不改动裁剪"升级为显式
    // masksToBounds = NO（露出外阴影必需；面板内容本身约束在面板内）
    [self ame_applyNeumorphSurface];
}

@end

#pragma mark - AmeBadgeLabel（Task137 胶囊徽章，实现不变）

@implementation AmeBadgeLabel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self ame137_commonInit];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self ame137_commonInit];
    }
    return self;
}

- (void)ame137_commonInit {
    _textInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    self.textAlignment = NSTextAlignmentCenter;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    // 胶囊永不压缩变形：宽度始终 = 文字 + 内边距，空间不足时由相邻视图让位
    [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

// 关键修复：UILabel 默认 intrinsicContentSize 不含自定义内边距，
// 必须显式补上，否则约束宽度 < 绘制宽度，文字尾部必然截断成 …
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + _textInsets.left + _textInsets.right,
                      size.height + _textInsets.top + _textInsets.bottom);
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self invalidateIntrinsicContentSize];
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    [self invalidateIntrinsicContentSize];
}

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect insetRect = UIEdgeInsetsInsetRect(bounds, self.textInsets);
    CGRect textRect = [super textRectForBounds:insetRect limitedToNumberOfLines:numberOfLines];
    textRect.origin.x -= self.textInsets.left;
    textRect.origin.y -= self.textInsets.top;
    return textRect;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 胶囊：圆角 = 高度一半（任意高度/文本长度均保持胶囊形状）
    CGFloat h = self.bounds.size.height;
    if (h > 0) self.layer.cornerRadius = h / 2.0;
}

@end
