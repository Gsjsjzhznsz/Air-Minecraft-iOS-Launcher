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
//  ===== Task160：新拟态回归（按用户 CSS 规格重建） =====
//
//  用户指令："所有自创UI全部更改为新拟态UI，按照css样式来写启动器原生的代码
//  而不是webview，按照比例调整阴影和高光"。规格（CSS 100% 基准）：
//
//    浅色：background #e0e0e0；box-shadow  20px 20px 60px #bebebe（暗影）
//                                         -20px -20px 60px #ffffff（高光）
//          主要文字 #333333；次要文字 #888888
//    深色：background #2c2c2c；box-shadow  20px 20px 60px #1e1e1e（暗影）
//                                         -20px -20px 60px #3a3a3a（高光）
//          主要文字 #f5f5f5；次要文字 #a0a0a0
//
//  Task137 三类历史问题的本轮对策：
//    1) 阴影被父视图裁剪 → 阴影承载视图插在宿主 subview 最底层，宿主与承载
//       层 masksToBounds 一律 NO（内容裁剪交给卡片内部容器，卡片内容本身在
//       约束内不溢出）；
//    2) 统一圆角 50 对小元素过圆 → 圆角/阴影偏移/模糊全部按元素短边等比缩放
//       （340pt = 100% 规格），并设下限（圆角 8 / 偏移 4 / 模糊 12）；
//    3) 深浅色对比 → 全部颜色用 dynamic provider 动态色，承载视图在
//       traitCollectionDidChange 时重刷 CGColor，无需广播。
//
//  尺寸与位置不受影响——只改底色/圆角/阴影/文字色四个样式维度。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 新拟态 CSS 规格基准尺寸：340pt 宽的元素 = 100% 规格（圆角 50/偏移 20/模糊 60）。
/// 小于基准的元素按 短边/340 等比缩放，带下限；大于基准封顶 100%。
FOUNDATION_EXPORT const CGFloat AmeNeumorphBaseDimension;

/// 新拟态表面色（Task160 规格）：浅色 #e0e0e0 / 深色 #2c2c2c（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphSurfaceColor(void);

/// 新拟态暗影色：浅色 #bebebe / 深色 #1e1e1e（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphShadowColor(void);

/// 新拟态高光色：浅色 #ffffff / 深色 #3a3a3a（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphHighlightColor(void);

/// 新拟态主要文字色：浅色 #333333 / 深色 #f5f5f5（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphPrimaryTextColor(void);

/// 新拟态次要文字色：浅色 #888888 / 深色 #a0a0a0（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphSecondaryTextColor(void);

/// 按元素短边等比计算新拟态度量（Task160）：
///   scale = clamp(短边 / 340, 0, 1)；圆角 = clamp(50*scale, 8, 50)；
///   偏移 = clamp(20*scale, 4, 20)；模糊 = 偏移 * 3（CSS 20:60 同比例）。
FOUNDATION_EXPORT void AmeNeumorphMetricsForSide(CGFloat side,
                                                 CGFloat *radiusOut,
                                                 CGFloat *offsetOut,
                                                 CGFloat *blurOut);

/// 双阴影承载视图（Task160 新拟态引擎）：
/// 两个 CALayer（暗影 + 高光）只画投影不画块（backgroundColor = clear），
/// 元素本体色由宿主 view 自绘；layoutSubviews 按 bounds 短边重算度量并写
/// 宿主 layer.cornerRadius；traitCollectionDidChange 时重刷阴影颜色。
/// 作为宿主的第一个 subview 自动随 bounds 缩放（autoresizing W|H），
/// userInteractionEnabled = NO 不拦截触摸。
@interface AmeNeumorphShadowView : UIView
/// 强制立即按宿主当前 bounds 重算度量/颜色（宿主 frame 变化后调用）
- (void)ame_refreshForHostBounds;
@end

/// 原生卡片/面板表面（Task137 起替代 nm_convex / nm_flat 系列引擎调用）
///
/// Task160：三个方法的内部实现统一升级为新拟态表面（表面色/圆角/双阴影按
/// 上文规格），调用点无需改动——传入的 cornerRadius 参数仍被尊重（调用点
/// 既有圆角设计不变），双阴影度量按元素短边等比。仅 Panel 平贴面板沿用
/// "不强制改裁剪"的旧约定，但为露出阴影会保证 masksToBounds = NO。
@interface UIView (AmeNativeSurface)

/// 原生卡片表面（Task160 新拟态：规格表面色 + 双外阴影 + 指定圆角）。
- (void)ame_applyCardSurfaceWithRadius:(CGFloat)cornerRadius;

/// 原生嵌套凸起卡片表面（Task160 新拟态同款表面；嵌套凸起感由双阴影与
/// 宿主层级关系呈现）。
- (void)ame_applyRaisedCardSurfaceWithRadius:(CGFloat)cornerRadius;

/// 原生平贴面板表面（Task163 语义修订：侧栏/右面板等大面板不再携带
/// 新拟态双阴影——用户实测全屏高大容器的等比阴影直接溢出、压到中央
/// 卡片上（"不该改的你改了"）。面板回归平贴：规格表面色 + 圆角
/// （clamp [8,50]），不挂阴影承载层；maskedCorners 由调用点维护的约定
/// 不变，masksToBounds = YES 与侧栏容器创建态一致）。
- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius;

/// Task160：纯新拟态表面（规格表面色 + 双阴影承载视图 + masksToBounds = NO；
/// 圆角按宿主短边等比自动写入规格值）。供三方法外的自创卡片直接使用。
- (void)ame_applyNeumorphSurface;

/// Task160：cell/列表场景专用的平贴新拟态表面——阴影会被相邻 cell 与
/// tableView 裁剪互叠（Task137 历史问题），此处只上规格表面色 + 圆角
/// （尊重调用点传入值，clamp [8,50]），裁剪保持（Task152 直角露出修复不变）。
- (void)ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius;

/// Task163：移除 ame_applyNeumorphSurface 挂载的双阴影承载视图并清空
/// 关联对象（背景模式切换场景的残留清理——新拟态卡片切回毛玻璃/半透明
/// 管线时旧投影会漏在 blur/半透明底外面穿帮）。未挂载时为无害空操作。
- (void)ame_removeNeumorphShadow;

/// Task168：仅阴影挂载（动态新拟态）——保留宿主现有卡面（壁纸管线的毛
/// 玻璃/半透明底，随用户的透明度/模糊设置动态变化），只追加双阴影承载
/// 视图并把宿主圆角统一到规格等比值；masksToBounds = NO 放行阴影外溢。
/// 与实底版 ame_applyNeumorphSurface 的唯一差异是不写 backgroundColor。
/// 调用点负责把卡面子视图（如 blur 层）的圆角同步到宿主新值。
- (void)ame_attachNeumorphShadowOnly;

/// Task172：卡片本体透明度（不含文字）——在 ame_applyNeumorphSurface 之后
/// 调用。卡面背景色按 opacity 淡化（动态色安全：dynamic provider 内逐
/// trait 重解析后再叠 alpha，深浅色切换不脱色），双阴影承载层整体 alpha
/// 同步淡化；文字/图标等内容子视图不参与（保持全不透明）。
///   100%（默认）= 规格表面原样；0% = 卡面与阴影完全透明（文字仍可见）。
/// 未挂阴影承载层时只处理卡面（无害）。重复调用幂等（每次全量重写）。
- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;

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
