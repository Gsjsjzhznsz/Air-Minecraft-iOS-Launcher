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
//  ===== Task177：按用户给过的 CSS 样式参考（bigbear-ui）定稿重写 =====
//
//  用户指令："先重写新拟态，用我给过的css样式参考，不要加任何的透明度，
//  不要让UI效果的模糊度透明度来影响到"。参考实现 = bigbear-ui 的
//  neu-white 系列 mixin（styles/mixin/_index.scss + _variables.scss）：
//
//    $btn-neu-normal: 2px;  $btn-neu-large: 4px;
//    @mixin neu-white($n) {
//        background: linear-gradient(145deg, #e6e6e6, #fff);
//        box-shadow: $n $n $n*2 #d6d6d6, -$n -$n $n*2 #fff;
//    }
//
//  换算成原生规格（卡片 = large 档，小元素 = normal 档）：
//
//    表面：linear-gradient(145deg, 起点→终点)；浅色 #e6e6e6→#ffffff，
//          深色同构 #333333→#2c2c2c（145° 轴向 = start(0.213,0.090)→
//          end(0.787,0.910)，全不透明）
//    双阴影：偏移 = N、模糊 = 2N（N=4pt 卡片档 / 2pt 小件档），颜色
//          全不透明（opacity 1.0）：浅色 #d6d6d6（右下暗影）+#ffffff
//          （左上高光）；深色 #1e1e1e / #3a3a3a。阴影 = 纯投影层垫在
//          不透明渐变表面之后（CSS box-shadow 在元素之后合成的语义），
//          投影内侧被表面遮住，只留外侧微晕——2~4pt 量级，不再是
//          Task160 短边等比的 20/60pt 重晕影，也没有 Task175 柔和档的
//          0.45/0.5 透明度。
//    透明度隔离（Task177 定稿 / Task178 修订）：新拟态表面/阴影不读 UI
//          效果的模糊度/壁纸透明度（uiOpacity / blurIntensity 无关）；
//          卡体透明度唯一入口 = cardsNeumorphOpacity（Task178 恢复，
//          默认 100% = 规格原样），经 ame_applyNeumorphCardOpacity
//          施加在承载视图整体 alpha 上（文字不参与）。
//
//  Task160 沿用的稳定决策保留：圆角按元素短边等比 clamp[8,50]
//  （Task178 修订：opt-in 圆角钉住 ame_setNeumorphPinnedCornerRadius，
//  显式圆角语义的卡片如新闻卡 12pt 不被等比改写）；
//  dynamic provider 深浅色自适应；宿主 masksToBounds = NO 放行外阴影。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 新拟态 CSS 规格基准尺寸：仅用于圆角的短边等比（340pt = 圆角 50）。
FOUNDATION_EXPORT const CGFloat AmeNeumorphBaseDimension;

/// 新拟态平贴表面色（Flat 行/回退底用）：浅色 #e0e0e0 / 深色 #2c2c2c（动态色）。
/// 凸起卡片的可见表面 = 渐变（见下），本色仅作阴影未铺前的兜底底色。
FOUNDATION_EXPORT UIColor *AmeNeumorphSurfaceColor(void);

/// Task177：渐变表面起点/终点色（CSS linear-gradient(145deg, 起点, 终点)）。
/// 浅色 #e6e6e6→#ffffff；深色 #333333→#2c2c2c（动态色，全不透明）。
FOUNDATION_EXPORT UIColor *AmeNeumorphSurfaceGradientStartColor(void);
FOUNDATION_EXPORT UIColor *AmeNeumorphSurfaceGradientEndColor(void);

/// 新拟态暗影色（CSS 参考 #d6d6d6）：浅色 #d6d6d6 / 深色 #1e1e1e（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphShadowColor(void);

/// 新拟态高光色：浅色 #ffffff / 深色 #3a3a3a（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphHighlightColor(void);

/// 新拟态主要文字色：浅色 #333333 / 深色 #f5f5f5（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphPrimaryTextColor(void);

/// 新拟态次要文字色：浅色 #888888 / 深色 #a0a0a0（动态色）
FOUNDATION_EXPORT UIColor *AmeNeumorphSecondaryTextColor(void);

/// Task177 度量：圆角沿用短边等比 clamp[8,50]；偏移/模糊改为 CSS 参考
/// 固定档（不再等比缩放——20/60pt 的等比放大正是历轮装机"重晕影"的根源）：
///   偏移 = 4pt（$btn-neu-large），模糊 = 8pt（2N，写入 CALayer 时再除 2
///   折算 shadowRadius）。小件档（2/4）由阴影视图按宿主短边 < 60pt 自动降档。
FOUNDATION_EXPORT void AmeNeumorphMetricsForSide(CGFloat side,
                                                 CGFloat *radiusOut,
                                                 CGFloat *offsetOut,
                                                 CGFloat *blurOut);

/// Task177 新拟态引擎（三层承载视图）：
///   底层 = 暗影投影层（clear，右下 +N）+ 高光投影层（clear，左上 -N），
///   顶层 = 不透明渐变表面层（CSS linear-gradient(145deg)）。表面盖住两层
///   投影的边界内侧，只留外侧 2~4pt 微晕——即 CSS "box-shadow 在元素之后
///   合成"的原生等价物，也是 Task160 透明承载层把整卡染出晕影的根治
///   （透明投影层的边界内侧直接叠在卡面上，20/60pt 模糊把整卡罩进晕影）。
/// layoutSubviews 按 bounds 重算度量/颜色/宿主圆角；
/// traitCollectionDidChange 时重刷。作为宿主第一个 subview 自动随 bounds
/// 缩放（autoresizing W|H），userInteractionEnabled = NO 不拦截触摸。
@interface AmeNeumorphShadowView : UIView
/// 强制立即按宿主当前 bounds 重算度量/颜色（宿主 frame 变化后调用）
- (void)ame_refreshForHostBounds;
@end

/// 原生卡片/面板表面（Task137 起替代 nm_convex / nm_flat 系列引擎调用）
///
/// Task177：凸起三方法（Card/Raised/NeumorphSurface）统一为 CSS 参考规格
/// （渐变表面 + 固定档全不透明双阴影），调用点无需改动；Panel/Flat 平贴
/// 家族不变（无阴影承载层）。
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

/// Task180：平贴面板表面 + 底色透明度（背景透明度滑条的 Flat 档载体）。
/// 只改宿主自身 backgroundColor 的 alpha（文字/图标是兄弟子视图，恒全
/// 不透明），不挂阴影承载层；1.0 = 与旧 Flat 完全一致（失效安全）。
- (void)ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius
                                opacity:(CGFloat)opacity;

/// Task177：纯新拟态表面（CSS 参考规格：渐变表面 + 全不透明双阴影承载
/// 视图 + masksToBounds = NO；圆角按宿主短边等比自动写入）。供三方法外的
/// 自创卡片直接使用。
- (void)ame_applyNeumorphSurface;

/// Task160：cell/列表场景专用的平贴新拟态表面——阴影会被相邻 cell 与
/// tableView 裁剪互叠（Task137 历史问题），此处只上规格表面色 + 圆角
/// （尊重调用点传入值，clamp [8,50]），裁剪保持（Task152 直角露出修复不变）。
- (void)ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius;

/// Task180：平贴表面 + 底色透明度（背景透明度滑条在 cell/行/列表场景的
/// 载体）：规格表面色 colorWithAlphaComponent:opacity + 圆角 + 裁剪保持，
/// 其余同上——只淡宿主底色，子视图（文字/图标）不受影响；opacity 钉到
/// [0,1]，1.0 与旧 Flat 完全一致。重铺幂等（滑条拖动时反复调用安全）。
- (void)ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius
                                       opacity:(CGFloat)opacity;

/// Task163：移除 ame_applyNeumorphSurface 挂载的承载视图并清空
/// 关联对象（背景模式切换场景的残留清理——新拟态卡片切回毛玻璃/半透明
/// 管线时旧投影会漏在 blur/半透明底外面穿帮）。未挂载时为无害空操作。
- (void)ame_removeNeumorphShadow;

/// Task178：卡片本体透明度（不含文字）——恢复 Task170/172/174 滑条语义，
/// 适配 Task177 三层引擎（用户定稿"只有那个透明度拉条可以改变新拟态的
/// 透明度，当然字体始终是不透明的"）。在 ame_applyNeumorphSurface 之后
/// 调用：Task177 引擎下整个卡体（不透明渐变表面 + 双阴影投影层）都住在
/// AmeNeumorphShadowView 内，整体 alpha 淡化 = 卡体同步淡化且不破坏
/// "表面盖住投影内侧"的规格结构；文字/图标是宿主的其余子视图，不参与
/// （恒全不透明）。宿主兜底底色同步让位（clear）——不透明的兜底色会把
/// 半透明卡面从下面垫回不透明。100%（默认）= Task177 规格原样；0% =
/// 卡体完全透明（文字仍可见）。未挂承载视图时无害空操作；重复调用幂等。
- (void)ame_applyNeumorphCardOpacity:(CGFloat)opacity;

/// Task178：新拟态圆角钉住（opt-in，默认不钉）——挂载后承载视图以本值
/// 为准（clamp [8,50]），不再按宿主短边等比改写宿主圆角。背景：短边等比
/// 是 Task160 全局定稿（大卡高圆角），但带显式圆角语义的卡片（如新闻卡
/// 12pt）在双列窄高布局下会被等比改写成 ~27pt（"太圆了"）。钉住后投影
/// shadowPath 与表面圆角同步用钉住值。传 0 = 解除钉住恢复等比。
/// 需在 ame_applyNeumorphSurface 之前/之后调用均可（刷新链每帧读取）。
- (void)ame_setNeumorphPinnedCornerRadius:(CGFloat)cornerRadius;

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
