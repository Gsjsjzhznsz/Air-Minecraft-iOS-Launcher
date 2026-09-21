//
//  UIKit+NativeSurface.h
//  Amethyst
//
//  Task137：新拟态（NeomorphKit）退役后的原生表面样式辅助。
//
//  背景：Task89 引入的新拟态凸出引擎（双承载层 + 暗/亮双外阴影）在用户实测中
//  暴露三类问题——阴影被父视图裁剪、统一圆角 50 对小元素过圆/大元素阴影过宽、
//  深浅色对比需要额外扫描器兜底。用户最终决定：删除全部新拟态代码，回归
//  iOS 原生 UI（系统语义色 + 标准圆角，无任何自绘阴影）。
//
//  本分类是替换层：全部使用 UIKit 语义色（secondarySystemGroupedBackground 等），
//  深浅色适配由 UIColor 动态色自动完成，无需通知广播/KVO/重绘。
//  尺寸与位置不受影响——只改底色/圆角/裁剪三个样式维度。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 原生卡片/面板表面（Task137 起替代 nm_convex / nm_flat 系列引擎调用）
@interface UIView (AmeNativeSurface)

/// 原生卡片表面：secondarySystemGroupedBackground 底 + 指定圆角，
/// 裁剪内容到圆角内（对应原 nm_convexRadius:shadowRadius: 无背景分支）。
- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius;

/// 原生嵌套凸起卡片表面：tertiarySystemGroupedBackground 底 + 指定圆角，
/// 裁剪内容（对应原 nm_convexRaisedRadius:shadowRadius:）。
- (void)ame_applyRaisedCardSurfaceWithRadius:(CGFloat)cornerRadius;

/// 原生平贴面板表面：secondarySystemBackground 底 + 指定圆角，
/// 不改动裁剪（对应原 nm_flatSurfaceWithRadius:，用于侧栏/右面板等大面板）。
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
