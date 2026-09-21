//
//  NMTheme.h
//  NeomorphKit
//
//  Task89：新拟态（Neumorphism）主题参数中心。
//
//  样式来源：react-native-neomorph-shadows（tokkozhin）的 Neomorph / NeomorphFlex
//  组件（用户选定"凸出/outer"样式）。本库无法直接嵌入原生 ObjC 工程，按其
//  src/helpers.js 的算法忠实移植：
//    - HSP 亮度：brightness = sqrt(0.299·r² + 0.587·g² + 0.114·b²)（0~255）
//    - 亮度转透明度：opacity = 50^(brightness/255) / 50 − 1/50
//    - 亮阴影透明度 = 0.025 + 0.975·opacity
//    - 暗阴影透明度 = 0.35·(1 − opacity)
//    - 阴影偏移 = ±shadowRadius（暗阴影右下 (+r,+r)，亮阴影左上 (−r,−r)）
//    - 暗阴影色默认黑、亮阴影色默认白（依底色亮度自动调节透明度）
//
//  双主题：跟随系统深浅色自动切换（用户选定）。Task136 起采用用户指定色板：
//  浅色 surface #E0E0E0（暗影 #BEBEBE/亮影 #FFFFFF，主文字 #333333/次要 #888888），
//  深色 surface #2C2C2C（暗影 #1E1E1E/亮影 #3A3A3A，主文字 #F5F5F5/次要 #A0A0A0），
//  圆角基准 50px（超出元素半宽/半高时由引擎自动夹断）。切换时广播
//  NMThemeDidChangeNotification，所有已应用 Neomorph 样式的视图自动重绘。
//
//  新拟态基本前提：元素与底色同色系（强制纯色底，见 BackgroundManager Task89
//  改动），阴影才可见。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 主题切换通知（深浅色变化时触发；object 为 NMTheme.shared）
extern NSNotificationName const NMThemeDidChangeNotification;

@interface NMTheme : NSObject

+ (instancetype)shared;

/// 当前是否深色模式（跟随系统；取 currentTraitCollection，未指定时回退 key window）
@property (nonatomic, readonly, assign) BOOL isDark;

/// 元素表面色（卡片/按钮/胶囊/行卡片的统一底色）
@property (nonatomic, readonly, strong) UIColor *surface;
/// 嵌套凸起表面色（surface 之上的再凸起层，略亮一档）
@property (nonatomic, readonly, strong) UIColor *surfaceRaised;
/// 全局背景色（窗口/主内容区，与 surface 同族略深，保证表面元素阴影可读）
@property (nonatomic, readonly, strong) UIColor *background;

/// 主文字 / 次要文字 / 占位文字
@property (nonatomic, readonly, strong) UIColor *label;
@property (nonatomic, readonly, strong) UIColor *secondaryLabel;
@property (nonatomic, readonly, strong) UIColor *placeholder;

/// 双阴影默认颜色（库默认：暗=黑，亮=白；透明度按底色亮度自动计算）
@property (nonatomic, readonly, strong) UIColor *darkShadowColor;
@property (nonatomic, readonly, strong) UIColor *lightShadowColor;

/// 按表面色亮度自动计算的双阴影透明度（helpers.js 忠实移植）
- (CGFloat)darkShadowOpacityForSurfaceColor:(UIColor *)color;
- (CGFloat)lightShadowOpacityForSurfaceColor:(UIColor *)color;

/// 重新读取当前深浅色并广播 NMThemeDidChangeNotification
/// （在 SceneDelegate/AppDelegate 的 traitCollectionDidChange 中调用）
- (void)reloadAndBroadcast;

/// 便捷类方法（内部走 shared，随深浅色自动切换）
+ (UIColor *)nm_surface;
+ (UIColor *)nm_surfaceRaised;
+ (UIColor *)nm_background;
+ (UIColor *)nm_label;
+ (UIColor *)nm_secondaryLabel;
+ (UIColor *)nm_placeholder;

@end

NS_ASSUME_NONNULL_END
