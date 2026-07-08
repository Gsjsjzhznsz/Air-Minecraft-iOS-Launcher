//
//  LiquidGlassCompat.h
//  AngelAuraAmethyst
//
//  iOS 26/27 液态玻璃（Liquid Glass）适配层
//  在 iOS 26+ 使用 UIGlassEffect/UIGlassContainerEffect，
//  低版本回退到 UIBlurEffectStyleSystemMaterialDark 等现有模糊效果。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 判断当前系统是否支持液态玻璃（iOS 26+）
FOUNDATION_EXTERN BOOL LGCIsLiquidGlassAvailable(void);

/// 创建一个液态玻璃 UIVisualEffectView。
/// - iOS 26+：使用 UIGlassEffect（普通变体）
/// - 低版本：回退到 UIBlurEffectStyleSystemMaterialDark
/// @param isDark 是否使用深色变体（低版本回退时区分深浅色）
FOUNDATION_EXTERN UIVisualEffectView *LGCCreateGlassEffectView(BOOL isDark);

/// 创建一个液态玻璃容器 UIVisualEffectView（用于多个 glass 元素组合）。
/// - iOS 26+：使用 UIGlassContainerEffect
/// - 低版本：回退到普通模糊
/// @param spacing 元素间距（仅 iOS 26+ 生效）
FOUNDATION_EXTERN UIVisualEffectView *LGCCreateGlassContainerView(CGFloat spacing, BOOL isDark);

/// 给视图应用液态玻璃背景（替换 BackgroundManager 的模糊效果）。
/// 如果视图已有 UIVisualEffectView 子视图会被替换。
/// - iOS 26+：UIGlassEffect
/// - 低版本：UIBlurEffectStyleSystemMaterialDark
/// @param view 目标视图
/// @param isDark 深色变体
/// @return 应用的 UIVisualEffectView（便于后续配置）
FOUNDATION_EXTERN UIVisualEffectView *LGCApplyGlassBackgroundToView(UIView *view, BOOL isDark);

/// 适配 UINavigationBar：在 iOS 26+ 移除自定义背景让系统接管液态玻璃。
/// 低版本保持现状（由调用方自行配置标准Appearance）。
FOUNDATION_EXTERN void LGCAdaptNavigationBar(UINavigationBar *navigationBar);

/// 适配 UIToolbar/UITabBar：在 iOS 26+ 移除自定义背景。
FOUNDATION_EXTERN void LGCAdaptBar(UIBar *bar);

/// 适配 UIBarButtonItem customView：在 iOS 26+ 隐藏共享玻璃背景。
FOUNDATION_EXTERN void LGCAdaptBarButtonItem(UIBarButtonItem *item);

NS_ASSUME_NONNULL_END
