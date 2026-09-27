//
//  UIKit+NativeSurface.m
//  Amethyst
//
//  Task137：原生表面样式辅助实现（设计说明见头文件）。
//  Task160：新拟态回归——表面/阴影/文字色按用户 CSS 规格重建（见 .h 注释）。
//  Task177：按用户给过的 CSS 样式参考（bigbear-ui neu-white）定稿重写——
//          渐变表面 + 固定档全不透明双阴影；透明承载层内侧染色（晕影根源）
//          与壁纸柔和档/卡片透明度原语全部退役。
//  Task178：恢复卡片本体透明度原语（用户定稿：只有"新拟态透明度"拉条
//          可以改变新拟态的透明度，字体恒不透明；UI 效果类型/模糊度/
//          壁纸透明度与新拟态彻底解耦）。Task177 三层引擎下整个卡体都在
//          承载视图内，整体 alpha 淡化即卡体淡化，文字不参与。
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

// Task177：CSS linear-gradient(145deg, 起点, 终点) 的两端（全不透明）。
// 浅色 = bigbear-ui neu-white 原样（#e6e6e6→#ffffff）；深色同构（#333333→#2c2c2c）。
UIColor *AmeNeumorphSurfaceGradientStartColor(void) {
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0xE6/255.0 green:0xE6/255.0 blue:0xE6/255.0 alpha:1.0],   // #e6e6e6
                                   [UIColor colorWithRed:0x33/255.0 green:0x33/255.0 blue:0x33/255.0 alpha:1.0]);  // #333333
}

UIColor *AmeNeumorphSurfaceGradientEndColor(void) {
    return AmeNeumorphDynamicColor([UIColor whiteColor],                                                            // #ffffff
                                   [UIColor colorWithRed:0x2C/255.0 green:0x2C/255.0 blue:0x2C/255.0 alpha:1.0]);  // #2c2c2c
}

UIColor *AmeNeumorphShadowColor(void) {
    // Task177：暗影色改 CSS 参考 #d6d6d6（原 #bebebe 是 neumorphism.io 默认，
    // 配合 20/60pt 等比阴影过重；bigbear-ui 用 #d6d6d6 + 2~4pt 微阴影）
    return AmeNeumorphDynamicColor([UIColor colorWithRed:0xD6/255.0 green:0xD6/255.0 blue:0xD6/255.0 alpha:1.0],   // #d6d6d6
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
    // Task177：圆角沿用短边等比（340pt = 圆角 50，clamp [8,50]）；
    // 偏移/模糊不再随尺寸放大——固定 CSS 参考档：卡片（large）= 4pt 偏移 /
    // 8pt 模糊；小件（normal，宿主短边 < 60pt）= 2pt / 4pt。历轮装机
    // "很重的晕影"的量级根源就是这里的 20*scale / 60*scale 等比放大。
    CGFloat scale = side / AmeNeumorphBaseDimension;
    if (scale < 0.0) scale = 0.0;
    if (scale > 1.0) scale = 1.0;
    if (radiusOut) *radiusOut = MAX(8.0, 50.0 * scale);
    if (offsetOut) *offsetOut = (side > 0.0 && side < 60.0) ? 2.0 : 4.0;   // $btn-neu-large / $btn-neu-normal
    if (blurOut)   *blurOut   = (side > 0.0 && side < 60.0) ? 4.0 : 8.0;   // CSS 模糊 = 2N
}

#pragma mark - Task177 新拟态承载视图（投影对 + 不透明渐变表面）

static void *kAmeNeumorphShadowViewKey = &kAmeNeumorphShadowViewKey;
/// Task178：圆角钉住（opt-in）——宿主关联对象存 NSNumber，非空时
/// ame_refreshForHostBounds 以钉住值为圆角（不再短边等比改写）。
static void *kAmeNeumorphPinnedRadiusKey = &kAmeNeumorphPinnedRadiusKey;

@interface AmeNeumorphShadowView ()
/// 右下暗影投影层（clear，只画投影；边界内侧被表面层遮住）
@property (nonatomic, strong) CALayer *ame177_darkLayer;
/// 左上高光投影层（clear，只画投影）
@property (nonatomic, strong) CALayer *ame177_lightLayer;
/// 不透明渐变表面层（顶层）：CSS linear-gradient(145deg) 的原生等价物，
/// 盖住两层投影的边界内侧——即 CSS "box-shadow 在元素之后合成"的语义，
/// 也是 Task160 透明承载层把整卡染出晕影的根治。
@property (nonatomic, strong) CAGradientLayer *ame177_surfaceLayer;
@end

@implementation AmeNeumorphShadowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        // 暗影投影层（右下）：纯投影不画块，表面由 ame177_surfaceLayer 负责
        _ame177_darkLayer = [CALayer layer];
        _ame177_darkLayer.backgroundColor = [UIColor clearColor].CGColor;
        _ame177_darkLayer.masksToBounds = NO;
        [self.layer addSublayer:_ame177_darkLayer];

        // 高光投影层（左上）
        _ame177_lightLayer = [CALayer layer];
        _ame177_lightLayer.backgroundColor = [UIColor clearColor].CGColor;
        _ame177_lightLayer.masksToBounds = NO;
        [self.layer addSublayer:_ame177_lightLayer];

        // 不透明渐变表面层（顶层，后加 = 最上）
        _ame177_surfaceLayer = [CAGradientLayer layer];
        _ame177_surfaceLayer.masksToBounds = NO;
        [self.layer addSublayer:_ame177_surfaceLayer];

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

/// 按 iOS 13+ 动态色在当前 trait 下解析 CGColor（pre-13 动态色函数本身回退静态浅色）
static CGColorRef Ame177ResolvedCGColor(UIColor *color, UITraitCollection *trait) {
    if (@available(iOS 13.0, *)) {
        return [[color resolvedColorWithTraitCollection:trait] CGColor];
    }
    return color.CGColor;
}

/// 按宿主（superview）当前 bounds 重算度量并同步两层投影 + 渐变表面 + 宿主圆角
- (void)ame_refreshForHostBounds {
    UIView *host = self.superview;
    CGFloat radius = 8.0;
    if (host) {
        CGFloat side = MIN(host.bounds.size.width, host.bounds.size.height);
        CGFloat offset = 4.0, blur = 8.0;
        AmeNeumorphMetricsForSide(side, &radius, &offset, &blur);
        // Task178：opt-in 圆角钉住优先（新闻卡等带显式圆角语义的卡片，
        // 双列窄高布局下等比结果 ~27pt 远超卡片自定的 12pt——"太圆了"）
        NSNumber *pinnedRadius = objc_getAssociatedObject(host, kAmeNeumorphPinnedRadiusKey);
        if (pinnedRadius) radius = MAX(8.0, MIN(pinnedRadius.doubleValue, 50.0));

        self.ame177_darkLayer.frame = self.bounds;
        self.ame177_lightLayer.frame = self.bounds;
        self.ame177_surfaceLayer.frame = self.bounds;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius];
        self.ame177_darkLayer.shadowPath = path.CGPath;
        self.ame177_lightLayer.shadowPath = path.CGPath;
        self.ame177_darkLayer.cornerRadius = radius;
        self.ame177_lightLayer.cornerRadius = radius;
        self.ame177_surfaceLayer.cornerRadius = radius;

        UITraitCollection *trait = self.traitCollection;
        // 暗影：右下（+offset, +offset）；不透明度恒 1.0（CSS 纯色阴影无 alpha）
        self.ame177_darkLayer.shadowColor = Ame177ResolvedCGColor(AmeNeumorphShadowColor(), trait);
        self.ame177_darkLayer.shadowOpacity = 1.0;
        self.ame177_darkLayer.shadowOffset = CGSizeMake(offset, offset);
        // CSS 模糊半径 ≈ CALayer.shadowRadius 的两倍（高斯 σ 映射）
        self.ame177_darkLayer.shadowRadius = blur / 2.0;

        // 高光：左上（-offset, -offset）
        self.ame177_lightLayer.shadowColor = Ame177ResolvedCGColor(AmeNeumorphHighlightColor(), trait);
        self.ame177_lightLayer.shadowOpacity = 1.0;
        self.ame177_lightLayer.shadowOffset = CGSizeMake(-offset, -offset);
        self.ame177_lightLayer.shadowRadius = blur / 2.0;

        // 不透明渐变表面（CSS linear-gradient(145deg, start, end)）：
        // 145° 轴向单位向量 (sin145°, -cos145°) ≈ (0.5736, 0.8192)，
        // 折算 start = center - v/2 = (0.2132, 0.0904)，end = center + v/2 = (0.7868, 0.9096)
        // CGColorRef 进 NSArray 字面量需 __bridge 显式桥接（ARC 硬要求；数组
        // 插入时自行 retain，解析出的 autoreleased UIColor 活过本语句，安全）
        self.ame177_surfaceLayer.colors = @[
            (__bridge id)Ame177ResolvedCGColor(AmeNeumorphSurfaceGradientStartColor(), trait),
            (__bridge id)Ame177ResolvedCGColor(AmeNeumorphSurfaceGradientEndColor(), trait),
        ];
        self.ame177_surfaceLayer.startPoint = CGPointMake(0.2132, 0.0904);
        self.ame177_surfaceLayer.endPoint   = CGPointMake(0.7868, 0.9096);
    }
    if (host) host.layer.cornerRadius = radius;
}

@end

#pragma mark - Task160 表面分类

@implementation UIView (AmeNativeSurface)

/// 新拟态表面（Task177 CSS 参考规格）：渐变表面 + 全不透明双阴影承载视图
/// + masksToBounds = NO。圆角由承载视图按宿主短边等比写入（下限 8，封顶 50）。
- (void)ame_applyNeumorphSurface {
    self.backgroundColor = AmeNeumorphSurfaceColor(); // 兜底底色（渐变表面铺上后不可见）
    self.layer.masksToBounds = NO; // Task137 教训：YES 会裁掉外阴影

    AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);
    if (!shadowView) {
        shadowView = [[AmeNeumorphShadowView alloc] initWithFrame:self.bounds];
        shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self insertSubview:shadowView atIndex:0];
        objc_setAssociatedObject(self, kAmeNeumorphShadowViewKey, shadowView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    shadowView.frame = self.bounds; // 非自动布局场景立即对齐；autoresizing 兜后续
    // Task178：重铺 = 回归规格全不透明（透明档由 ame_applyNeumorphCardOpacity
    // 在管线尾部重新施加；未配对调用时向用户认可的 Task177 形态失效安全）
    shadowView.alpha = 1.0;
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
    // Task177：凸起卡片 = CSS 参考规格（渐变表面 + 全不透明固定档双阴影）；
    // Task137 语义的 secondarySystemGroupedBackground 退役。
    [self ame_applyNeumorphSurface];
}

- (void)ame_applyRaisedCardSurfaceWithRadius:(CGFloat)cornerRadius {
    // 嵌套凸起卡片同款表面（凸起感由双阴影 + 层级关系呈现）
    [self ame_applyNeumorphSurface];
}

- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task163：平贴面板退役阴影（侧栏/右面板等全屏高大容器不挂阴影承载层）。
    // Task177 后此家族仍为 Flat 表面（无渐变无阴影）——面板不在凸起规格内。
    [self ame_applyNeumorphSurfaceFlatWithRadius:cornerRadius];
}

- (void)ame_removeNeumorphShadow {
    // Task163：背景模式切换的残留清理——新拟态卡片切回毛玻璃/半透明管线
    // 时，旧承载视图（关联对象持有）会漏在 blur/半透明底外面穿帮。
    // 未挂载时为无害空操作；只移视图与关联，不动表面色/圆角/裁剪
    // （后续管线会按自己的形态重设）。
    AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);
    if (shadowView) {
        [shadowView removeFromSuperview];
        objc_setAssociatedObject(self, kAmeNeumorphShadowViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kAmeNeumorphPinnedRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // Task178：钉住随挂载一并清
    }
}

- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity {
    // Task178：卡片本体透明度（不含文字）。设为独立引擎原语的原因（沿用
    // Task172 定稿口径）：不能用宿主 view.alpha——alpha 沿层级连乘，
    // 文字/图标子视图会一起被淡掉（用户定稿"字体始终是不透明的"）。
    // Task177 三层引擎的适配：整个卡体（不透明渐变表面 + 双阴影投影层）
    // 都在 AmeNeumorphShadowView 内，且不透明表面层盖住投影边界内侧——
    // 承载视图整体 alpha 淡化保持这一合成结构不变（半透明态下投影内侧
    // 剪影与表面同步衰减，晕影不随透明度回归），卡体对外呈统一的 o。
    // 宿主兜底底色必须同步让位：不透明的 #e0e0e0 垫在承载视图下面，会把
    // 半透明卡面从底下垫回不透明（透明度形同虚设）。
    CGFloat o = MAX(0.0, MIN(1.0, opacity));
    AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);
    if (!shadowView) return; // 未挂承载视图（平贴表面/旧管线宿主）：无害空操作
    if (shadowView.alpha != o) shadowView.alpha = o;
    if (![self.backgroundColor isEqual:[UIColor clearColor]]) {
        self.backgroundColor = [UIColor clearColor]; // 兜底让位（幂等）
    }
}

- (void)ame_setNeumorphPinnedCornerRadius:(CGFloat)cornerRadius {
    // Task178：圆角钉住（opt-in）。关联对象存 NSNumber（nil = 解除），
    // 刷新链（layoutSubviews / trait 变化 / 宿主 bounds 变化）每帧读取，
    // 生命周期与承载视图解耦。设置后立即重刷一次（bounds 不变时
    // layoutSubviews 不会自发重跑）。
    if (cornerRadius > 0.0) {
        objc_setAssociatedObject(self, kAmeNeumorphPinnedRadiusKey,
                                 @(MAX(8.0, MIN(cornerRadius, 50.0))),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(self, kAmeNeumorphPinnedRadiusKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    AmeNeumorphShadowView *shadowView = objc_getAssociatedObject(self, kAmeNeumorphShadowViewKey);
    [shadowView ame_refreshForHostBounds]; // 未挂载时为无害空操作
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
