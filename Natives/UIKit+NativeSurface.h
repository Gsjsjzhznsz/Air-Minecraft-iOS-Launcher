//
//  UIKit+NativeSurface.h
//  Amethyst
//
//  Task210：新拟态引擎整体退役后的卡片表面样式辅助（用户定稿"检索并删除
//  所有新拟态代码和其选项和设置，因为维护过于麻烦"）。
//
//  本轮删除（随 Task210 全链移除，无遗留）：
//    - AmeNeumorphShadowView 三层承载引擎（暗影/高光投影 + 渐变表面）
//    - AmeNeumorphSurfaceGradientStart/EndColor、ShadowColor、HighlightColor
//    - AmeNeumorphMetricsForSide / AmeNeumorphBaseDimension（短边等比度量）
//    - ame_applyNeumorphSurface / ...FlatWithRadius: / ame_removeNeumorphShadow
//    - ame_applyNeumorphCardOpacity:（Task178 卡体透明度滑条原语）
//    - ame_setNeumorphPinnedCornerRadius:（圆角钉住）
//    - ame_applyRaisedCardSurfaceWithRadius:（无外部调用点）
//
//  本轮保留（改名去 Neumorph 字样，色值逐字节不变）：
//    - AmeNeumorphSurfaceColor       → AmeCardSurfaceColor
//      （平贴卡面：浅色 #e0e0e0 / 深色 #2c2c2c，用户定稿"保留平贴灰面
//        但去掉双阴影"——无壁纸时全 app 卡面的统一身份色）
//    - AmeNeumorphPrimaryTextColor   → AmeCardPrimaryTextColor
//      （浅色 #333333 / 深色 #f5f5f5，"深色和灰色"深浅自适应主文字）
//    - AmeNeumorphSecondaryTextColor → AmeCardSecondaryTextColor
//      （浅色 #888888 / 深色 #a0a0a0，深浅自适应次要文字）
//    - AmeBadgeLabel（Task137 胶囊徽章，与新拟态无关，原样保留）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 平贴卡面身份色（Task210 定稿保留）：浅色 #e0e0e0 / 深色 #2c2c2c（动态色）。
FOUNDATION_EXPORT UIColor *AmeCardSurfaceColor(void);

/// 卡面主文字色：浅色 #333333 / 深色 #f5f5f5（动态色，深浅自适应）
FOUNDATION_EXPORT UIColor *AmeCardPrimaryTextColor(void);

/// 卡面次要文字色：浅色 #888888 / 深色 #a0a0a0（动态色，深浅自适应）
FOUNDATION_EXPORT UIColor *AmeCardSecondaryTextColor(void);

/// 原生卡片/面板表面（Task210：平贴家族——表面色 + 圆角，无任何自绘阴影）
@interface UIView (AmeNativeSurface)

/// 卡片表面：AmeCardSurfaceColor 平贴 + 指定圆角（clamp [8,50]）。
/// Task210 起为纯平贴（Task177 双阴影引擎已随新拟态退役）。
- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius;

/// 平贴面板表面（侧栏/右面板等大面板）：与卡片同款平贴（无阴影承载层；
/// maskedCorners 由调用点维护的约定不变，masksToBounds = YES）。
- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius;

@end

/// 带左右内边距的胶囊徽章标签（Task137：列表右侧小字框的统一实现）。
///
/// 修复 Task136 的"所有小字框显示 …"回归：此前 InsetTypeLabel 只重写了
/// textRectForBounds:/drawTextInRect: 注入内边距，但没有重写
/// intrinsicContentSize——自动布局按"纯文字宽度"给定标签宽度，绘制时再被
/// 左右内边距各裁掉 8pt，任何文本都必然尾部截断成省略号。
///
/// 本类完整实现三件套：
///   1. intrinsicContentSize = 文字尺寸 + 左右内边距（宽度随字体动态）；
///   2. textRectForBounds:/drawTextInRect: 注入同样的内边距（绘制居中）；
///   3. layoutSubviews 圆角 = 高度一半（任意高度保持胶囊形状）。
/// hugging/compression 均为 Required：胶囊永不压缩变形，由相邻文本侧让位。
@interface AmeBadgeLabel : UILabel

/// 文字内边距（默认左右各 8pt、上下 0）
@property (nonatomic, assign) UIEdgeInsets textInsets;

@end

NS_ASSUME_NONNULL_END
