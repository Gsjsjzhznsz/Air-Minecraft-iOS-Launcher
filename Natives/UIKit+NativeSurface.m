//
//  UIKit+NativeSurface.m
//  Amethyst
//
//  Task210：新拟态引擎整体退役后的卡片表面样式辅助（设计说明见头文件）。
//  保留三件套：平贴表面色 + 深浅自适应主/次文字色（色值逐字节沿用 Task177
//  定稿），命名去 Neumorph 字样；AmeNeumorphShadowView 承载引擎、渐变表面、
//  双阴影、卡体透明度原语与圆角钉住全部随 Task210 删除。
//

#import "UIKit+NativeSurface.h"
#import <objc/runtime.h>

#pragma mark - Task210 卡面色（动态 provider，深浅色自适应）

static UIColor *AmeCardDynamicColor(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) ? dark : light;
        }];
    }
    return light;
}

UIColor *AmeCardSurfaceColor(void) {
    return AmeCardDynamicColor([UIColor colorWithRed:0xE0/255.0 green:0xE0/255.0 blue:0xE0/255.0 alpha:1.0],   // #e0e0e0
                               [UIColor colorWithRed:0x2C/255.0 green:0x2C/255.0 blue:0x2C/255.0 alpha:1.0]);  // #2c2c2c
}

UIColor *AmeCardPrimaryTextColor(void) {
    return AmeCardDynamicColor([UIColor colorWithRed:0x33/255.0 green:0x33/255.0 blue:0x33/255.0 alpha:1.0],   // #333333
                               [UIColor colorWithRed:0xF5/255.0 green:0xF5/255.0 blue:0xF5/255.0 alpha:1.0]);  // #f5f5f5
}

UIColor *AmeCardSecondaryTextColor(void) {
    return AmeCardDynamicColor([UIColor colorWithRed:0x88/255.0 green:0x88/255.0 blue:0x88/255.0 alpha:1.0],   // #888888
                               [UIColor colorWithRed:0xA0/255.0 green:0xA0/255.0 blue:0xA0/255.0 alpha:1.0]);  // #a0a0a0
}

#pragma mark - 平贴表面分类

@implementation UIView (AmeNativeSurface)

- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task210：纯平贴卡面（表面色 + 圆角）。双阴影承载引擎已随新拟态退役；
    // 裁剪保持（Task152 直角露出修复不变）。
    self.backgroundColor = AmeCardSurfaceColor();
    self.layer.cornerRadius = MAX(8.0, MIN(cornerRadius, 50.0));
    self.layer.masksToBounds = YES;
}

- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius {
    // Task163 语义保留：侧栏/右面板等大面板平贴（无阴影承载层）。
    [self ame_applyCardSurfaceWithRadius:cornerRadius];
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
