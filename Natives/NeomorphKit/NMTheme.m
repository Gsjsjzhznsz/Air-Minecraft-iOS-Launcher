//
//  NMTheme.m
//  NeomorphKit
//
//  Task89：主题参数与亮度→透明度算法实现（算法来源见 NMTheme.h 头注释）。
//

#import "NMTheme.h"
#import <math.h>

NSNotificationName const NMThemeDidChangeNotification = @"NMThemeDidChange";

/// 浅色主题（库 demo 同款 #ECF0F3 表面；背景同族略深保证阴影可读）
static NSString * const kLightSurface        = @"#ECF0F3";
static NSString * const kLightSurfaceRaised  = @"#F5F8FB";
static NSString * const kLightBackground     = @"#E3E8EF";
/// 深色主题（夜间向；表面略亮于背景，暗阴影黑/亮阴影白仍由算法自动调透明度）
static NSString * const kDarkSurface         = @"#262A2F";
static NSString * const kDarkSurfaceRaised   = @"#2D3238";
static NSString * const kDarkBackground      = @"#1E2227";

@implementation NMTheme

+ (instancetype)shared {
    static NMTheme *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[NMTheme alloc] init];
    });
    return shared;
}

#pragma mark - Theme Colors

- (UIColor *)colorFromHex:(NSString *)hex {
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length != 6) return [UIColor grayColor];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

- (BOOL)isDark {
    // 跟随系统（用户选定）：优先 currentTraitCollection（视图加载期间 UIKit 会正确填充），
    // 未指定时回退 key window 的 traitCollection。
    UIUserInterfaceStyle style = [UITraitCollection currentTraitCollection].userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        UIWindow *keyWindow = nil;
        for (UIWindow *w in scene.windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (keyWindow) style = keyWindow.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark;
}

- (UIColor *)surface {
    return [self colorFromHex:self.isDark ? kDarkSurface : kLightSurface];
}

- (UIColor *)surfaceRaised {
    return [self colorFromHex:self.isDark ? kDarkSurfaceRaised : kLightSurfaceRaised];
}

- (UIColor *)background {
    return [self colorFromHex:self.isDark ? kDarkBackground : kLightBackground];
}

- (UIColor *)label {
    return self.isDark ? [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1.0]
                       : [UIColor colorWithRed:0.22 green:0.25 blue:0.30 alpha:1.0];
}

- (UIColor *)secondaryLabel {
    return self.isDark ? [UIColor colorWithWhite:0.70 alpha:1.0]
                       : [UIColor colorWithWhite:0.42 alpha:1.0];
}

- (UIColor *)placeholder {
    return self.isDark ? [UIColor colorWithWhite:0.48 alpha:1.0]
                       : [UIColor colorWithWhite:0.60 alpha:1.0];
}

- (UIColor *)darkShadowColor {
    // 库默认 darkShadowColor = 'black'
    return [UIColor blackColor];
}

- (UIColor *)lightShadowColor {
    // 库默认 lightShadowColor = 'white'（透明度由底色亮度自动压低，深浅色通用）
    return [UIColor whiteColor];
}

#pragma mark - Brightness → Opacity（helpers.js 忠实移植）

/// HSP 亮度（0~255）：sqrt(0.299·r² + 0.587·g² + 0.114·b²)
static CGFloat NMBrightnessOfColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // 非 RGB 空间兜底：解析 CGColor 组件（灰度为 1~2 组件）
        CGColorRef cg = color.CGColor;
        size_t n = CGColorGetNumberOfComponents(cg);
        const CGFloat *comps = CGColorGetComponents(cg);
        if (n >= 3) {
            r = comps[0]; g = comps[1]; b = comps[2];
        } else {
            r = g = b = (n >= 1 ? comps[0] : 0.5);
        }
    }
    CGFloat r255 = r * 255.0, g255 = g * 255.0, b255 = b * 255.0;
    return sqrt(0.299 * r255 * r255 + 0.587 * g255 * g255 + 0.114 * b255 * b255);
}

/// brightnessToOpacity：ratio=50; opacity = 50^(brightness/255)/50 − 1/50
static CGFloat NMBrightnessToOpacity(CGFloat brightness) {
    const CGFloat ratio = 50.0;
    CGFloat ratioBrightness = brightness / 255.0;
    return pow(ratio, ratioBrightness) / ratio - 1.0 / ratio;
}

- (CGFloat)lightShadowOpacityForSurfaceColor:(UIColor *)color {
    // calcOpacityFromRange(opacity, 0.025, 1) = 0.025 + (1 − 0.025)·opacity
    CGFloat opacity = NMBrightnessToOpacity(NMBrightnessOfColor(color));
    return 0.025 + (1.0 - 0.025) * opacity;
}

- (CGFloat)darkShadowOpacityForSurfaceColor:(UIColor *)color {
    // calcOpacityFromRange(1 − opacity, 0, 0.35) = 0.35·(1 − opacity)
    CGFloat opacity = NMBrightnessToOpacity(NMBrightnessOfColor(color));
    return 0.35 * (1.0 - opacity);
}

#pragma mark - Broadcast

- (void)reloadAndBroadcast {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NMThemeDidChangeNotification object:self];
}

#pragma mark - Convenience

+ (UIColor *)nm_surface        { return [NMTheme shared].surface; }
+ (UIColor *)nm_surfaceRaised  { return [NMTheme shared].surfaceRaised; }
+ (UIColor *)nm_background     { return [NMTheme shared].background; }
+ (UIColor *)nm_label          { return [NMTheme shared].label; }
+ (UIColor *)nm_secondaryLabel { return [NMTheme shared].secondaryLabel; }
+ (UIColor *)nm_placeholder    { return [NMTheme shared].placeholder; }

@end
