//
//  NMContrast.h
//  NeomorphKit
//
//  Task136：动态文字对比度修复器（用户需求："动态检索所有按钮及页面，
//  判断其深浅模式并相应改动"）。
//
//  背景：启动器早期基于深色页面制作，部分按钮/标签存在硬编码文字色，
//  在另一侧模式下会出现"黑字深底/白字浅底"的不可读组合。本组件按
//  WCAG 对比度规则动态扫描视图树：
//    - 对每个 UIButton / UILabel 解析其有效背景色（沿 superview 链向上
//      找第一个不透明实色背景；遇无法解析的背景——如图片/模糊层——整支跳过）
//    - 饱和背景（accentColor 等品牌色按钮）整支跳过，保留既有的白字设计
//    - 文字色与有效背景的对比度 < 2.0（近似不可读）时，按 NMTheme 深浅色
//      重设为用户指定主文字色（浅 #333333 / 深 #F5F5F5）
//
//  触发时机（自管理）：NMThemeDidChangeNotification / BackgroundUIEffectChanged
//  广播后自动异步扫描 key window；另提供显式入口供页面与校验器调用。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NMContrast : NSObject

/// 对 root 子树执行一轮对比度修复（幂等：已是可读组合的文字保持原色）
+ (void)nm_fixTextContrastInView:(UIView *)root;

/// WCAG 相对亮度对比度比值（(L1+0.05)/(L2+0.05)，≥1）
+ (CGFloat)nm_contrastRatioBetweenColor:(UIColor *)a andColor:(UIColor *)b;

/// 注册通知观察者并立即调度一轮扫描（SceneDelegate 启动完成后调用一次）
+ (void)nm_startContrastSweep;

@end

NS_ASSUME_NONNULL_END
