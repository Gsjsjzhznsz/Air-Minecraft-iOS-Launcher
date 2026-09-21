//
//  NMTheme.m
//  NeomorphKit
//
//  Task89：主题参数与亮度→透明度算法实现（算法来源见 NMTheme.h 头注释）。
//

#import "NMTheme.h"
#import <math.h>

NSNotificationName const NMThemeDidChangeNotification = @"NMThemeDidChange";

/// 浅色主题（Task136：用户指定色板——表面 #E0E0E0；背景同族略深保证阴影可读）
static NSString * const kLightSurface        = @"#E0E0E0";
static NSString * const kLightSurfaceRaised  = @"#E8E8E8";
static NSString * const kLightBackground     = @"#D6D6D6";
/// 深色主题（Task136：用户指定色板——表面 #2C2C2C；背景同族略深）
static NSString * const kDarkSurface         = @"#2C2C2C";
static NSString * const kDarkSurfaceRaised   = @"#333333";
static NSString * const kDarkBackground      = @"#252525";

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
    // Task136：用户指定主文字色精确值——浅色 #333333 / 深色 #F5F5F5
    // （替代 Task91 的 #222222/#EEEEEE）
    return self.isDark ? [UIColor colorWithRed:0xF5 / 255.0 green:0xF5 / 255.0 blue:0xF5 / 255.0 alpha:1.0]
                       : [UIColor colorWithRed:0x33 / 255.0 green:0x33 / 255.0 blue:0x33 / 255.0 alpha:1.0];
}

- (UIColor *)secondaryLabel {
    // Task136：用户指定次要文字色——浅色 #888888 / 深色 #A0A0A0
    return self.isDark ? [UIColor colorWithRed:0xA0 / 255.0 green:0xA0 / 255.0 blue:0xA0 / 255.0 alpha:1.0]
                       : [UIColor colorWithRed:0x88 / 255.0 green:0x88 / 255.0 blue:0x88 / 255.0 alpha:1.0];
}

- (UIColor *)placeholder {
    return self.isDark ? [UIColor colorWithWhite:0.48 alpha:1.0]
                       : [UIColor colorWithWhite:0.60 alpha:1.0];
}

- (UIColor *)darkShadowColor {
    // Task136：用户指定暗阴影色——浅色 #BEBEBE / 深色 #1E1E1E
    // （CSS box-shadow 的暗影色，全透明度直绘，替代库默认黑色+算法透明度）
    return [self colorFromHex:self.isDark ? @"#1E1E1E" : @"#BEBEBE"];
}

- (UIColor *)lightShadowColor {
    // Task136：用户指定亮阴影色——浅色 #FFFFFF / 深色 #3A3A3A
    return [self colorFromHex:self.isDark ? @"#3A3A3A" : @"#FFFFFF"];
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
    // Task136：用户 CSS 的阴影色本身就是最终渲染色（#FFFFFF/#3A3A3A 全 alpha），
    // 不再按表面亮度换算透明度——固定 1.0 忠实还原 neumorphism.io 观感。
    // color 参数保留以兼容既有签名（校验器/调用方）。
    (void)color;
    return 1.0;
}

- (CGFloat)darkShadowOpacityForSurfaceColor:(UIColor *)color {
    // Task136：同上——#BEBEBE/#1E1E1E 全 alpha 直绘。
    (void)color;
    return 1.0;
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
