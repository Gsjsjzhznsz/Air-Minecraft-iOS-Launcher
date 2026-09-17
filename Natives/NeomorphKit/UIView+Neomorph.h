//
//  UIView+Neomorph.h
//  NeomorphKit
//
//  Task89：新拟态"凸出"样式的 UIView/UIButton 分类（用户选定 Neomorph 默认
//  outer/凸出样式，非 inner/凹陷）。
//
//  实现原理（对齐 react-native-neomorph-shadows iOS 原生路径）：
//  在目标视图的 layer 上插入两个"投影承载层"（caster）：
//    - 暗影承载层：surface 底色 + 黑色阴影，offset (+r,+r)
//    - 亮影承载层：surface 底色 + 白色阴影，offset (−r,−r)
//  两层底色即元素表面，其阴影分别向右下/左上发散，形成新拟物凸出效果；
//  目标视图自身背景清空、masksToBounds 放开（圆角由承载层圆角保证），
//  原 subviews 位于承载层之上正常显示。
//
//  阴影透明度不写死：按表面色亮度自动计算（NMTheme，helpers.js 算法），
//  深浅色主题各自得到正确立体感；主题切换时由 NMThemeDidChangeNotification
//  驱动全部附件重绘。视图尺寸变化（KVO bounds）自动同步承载层几何。
//

#import <UIKit/UIKit.h>
#import "NMTheme.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIView (Neomorph)

/// 凸出新拟物（默认圆角 12、阴影半径 6）：surface 底色 + 暗亮双外阴影
- (void)nm_convex;

/// 凸出新拟物，指定圆角；阴影半径默认取 圆角×0.5（下限 4）
- (void)nm_convexRadius:(CGFloat)cornerRadius;

/// 凸出新拟物，完整参数（shadowRadius 即库 style.shadowRadius：
/// 偏移 = ±shadowRadius，模糊 = shadowRadius，透明度按底色自动计算）
- (void)nm_convexRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius;

/// 凸出新拟物（嵌套凸起）：使用 surfaceRaised 表面色（比 surface 略亮一档），
/// 用于 surface 卡片之上的再凸起元素（如卡片内的行/按钮）
- (void)nm_convexRaisedRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius;

/// 胶囊新拟物：圆角 = 高度/2（随尺寸变化自动重算），适合状态胶囊/小标签
- (void)nm_pill;

/// 胶囊新拟物（嵌套凸起表面色）
- (void)nm_pillRaised;

/// 平贴表面：仅 surface 底色 + 圆角，无阴影（侧栏/右面板等大面板层，
/// 新拟态层级中的"平"面）
- (void)nm_flatSurfaceWithRadius:(CGFloat)cornerRadius;

/// 平贴表面（嵌套凸起色）
- (void)nm_flatRaisedSurfaceWithRadius:(CGFloat)cornerRadius;

/// 背景色（内容区底色）
- (void)nm_flatBackground;

/// 移除新拟物附件（承载层与监听），恢复视图自由样式
- (void)nm_removeNeomorph;

/// 当前视图是否已应用新拟物样式
- (BOOL)nm_hasNeomorph;

@end

@interface UIButton (Neomorph)

/// 全灰新拟态按钮（用户选定：所有按钮与底同色，仅靠阴影分层）：
/// surface 底 + 凸出双阴影 + label 色标题
- (void)nm_styleConvexButton;

/// 全灰新拟态按钮，指定圆角与阴影半径
- (void)nm_styleConvexButtonRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius;

@end

NS_ASSUME_NONNULL_END
