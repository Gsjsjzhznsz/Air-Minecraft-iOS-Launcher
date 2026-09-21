//
//  NMContrast.m
//  NeomorphKit
//
//  Task136：动态文字对比度修复器实现。算法说明见头文件。
//

#import "NMContrast.h"
#import "NMTheme.h"

/// 对比度修复阈值：WCAG 正文可读下限为 4.5，此处取 2.0 —— 只拦截
/// "近似不可读"组合（黑字深底/白字浅底），避免误伤刻意的中对比设计
/// （如 accent 按钮白字对 systemGreen 的比值约 1.6~2.2，由饱和色规则另行保护）。
static const CGFloat kNMContrastFixThreshold = 2.0;

/// 背景饱和度超过该值视为"品牌色表面"（accent 按钮/彩色徽章），整支跳过
static const CGFloat kNMSaturationSkipThreshold = 0.35;

@implementation NMContrast

#pragma mark - Color Math

/// 解析为 RGBA（灰度/非 RGB 空间兜底展开）
static BOOL NMResolveRGBA(UIColor *color, CGFloat *outR, CGFloat *outG, CGFloat *outB, CGFloat *outA) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        *outR = r; *outG = g; *outB = b; *outA = a;
        return YES;
    }
    CGColorRef cg = color.CGColor;
    size_t n = CGColorGetNumberOfComponents(cg);
    const CGFloat *comps = CGColorGetComponents(cg);
    if (n >= 3) {
        *outR = comps[0]; *outG = comps[1]; *outB = comps[2]; *outA = comps[3];
        return YES;
    }
    if (n == 2) {
        *outR = *outG = *outB = comps[0]; *outA = comps[1];
        return YES;
    }
    return NO;
}

/// sRGB 单通道线性化
static CGFloat NMLinearizeChannel(CGFloat c) {
    return (c <= 0.03928) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

/// WCAG 相对亮度（sRGB 线性化）
static CGFloat NMRelativeLuminance(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!NMResolveRGBA(color, &r, &g, &b, &a)) return -1.0;
    return 0.2126 * NMLinearizeChannel(r) + 0.7152 * NMLinearizeChannel(g) + 0.0722 * NMLinearizeChannel(b);
}

+ (CGFloat)nm_contrastRatioBetweenColor:(UIColor *)a andColor:(UIColor *)b {
    CGFloat la = NMRelativeLuminance(a);
    CGFloat lb = NMRelativeLuminance(b);
    if (la < 0 || lb < 0) return -1.0;
    CGFloat lighter = MAX(la, lb);
    CGFloat darker = MIN(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
}

/// HSL 饱和度（0~1）：用于识别 accent/品牌色表面
static CGFloat NMSaturationOfColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!NMResolveRGBA(color, &r, &g, &b, &a)) return -1.0;
    CGFloat mx = MAX(MAX(r, g), b);
    CGFloat mn = MIN(MIN(r, g), b);
    if (mx <= 0.0001) return 0.0;
    return (mx - mn) / mx;
}

#pragma mark - Effective Background

/// 沿 superview 链向上找第一个"不透明实色"背景；返回 nil 表示无法可靠
/// 判定（透明/图片/模糊层背景），此时不做修复（宁可不改也不误改）
static UIColor *NMEffectiveBackgroundColor(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        UIColor *bg = v.backgroundColor;
        if (!bg || [bg isEqual:UIColor.clearColor]) continue;
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if (!NMResolveRGBA(bg, &r, &g, &b, &a)) return nil;  // pattern/图片等
        if (a < 0.9) continue;                               // 半透明底继续向上
        CGFloat alphaOfView = 1.0;
        for (UIView *p = v; p; p = p.superview) { alphaOfView *= p.alpha; }
        if (alphaOfView < 0.9) continue;                     // 所在视图链半透明
        return bg;
    }
    return nil;
}

#pragma mark - Fix Pass

/// 是否需要跳过该视图所在的"饱和表面"分支（accent 按钮、彩色徽章等）
static BOOL NMSkipForSaturatedSurface(UIView *view) {
    UIColor *bg = NMEffectiveBackgroundColor(view);
    if (!bg) return YES;  // 背景无法解析：不修（含背景照片/模糊模式）
    CGFloat sat = NMSaturationOfColor(bg);
    if (sat < 0) return YES;
    return sat > kNMSaturationSkipThreshold;
}

+ (void)nm_fixTextContrastInView:(UIView *)root {
    if (!root) return;

    // 有效背景与饱和度在子树根处判定一次（同表面内的文字共享判定结果，
    // 也避免逐 label 重复向上遍历）
    BOOL skipSubtree = NMSkipForSaturatedSurface(root);

    if ([root isKindOfClass:[UIButton class]] && !skipSubtree) {
        UIButton *button = (UIButton *)root;
        UIColor *bg = NMEffectiveBackgroundColor(root);
        UIColor *title = [button titleColorForState:UIControlStateNormal];
        if (bg && title) {
            CGFloat ratio = [self nm_contrastRatioBetweenColor:title andColor:bg];
            if (ratio >= 0 && ratio < kNMContrastFixThreshold) {
                // 按 NMTheme 深浅色重设为用户指定主文字色（Task136 色板）
                [button setTitleColor:[NMTheme nm_label]
                             forState:UIControlStateNormal];
            }
        }
    }

    if ([root isKindOfClass:[UILabel class]] && !skipSubtree) {
        UILabel *label = (UILabel *)root;
        // 带阴影的文字说明处于毛玻璃/背景照片管线的旧样式，交给原管线管理
        UIColor *bg = NMEffectiveBackgroundColor(root);
        if (bg && label.textColor) {
            CGFloat ratio = [self nm_contrastRatioBetweenColor:label.textColor andColor:bg];
            if (ratio >= 0 && ratio < kNMContrastFixThreshold) {
                label.textColor = [NMTheme nm_label];
            }
        }
    }

    for (UIView *sub in root.subviews) {
        [self nm_fixTextContrastInView:sub];
    }
}

#pragma mark - Self-managed Sweep

+ (void)nm_sweepKeyWindowOnce {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 布局刚完成的一瞬 cell/按钮可能尚未就位，稍作延迟再扫
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] &&
                    scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w.isKeyWindow) { window = w; break; }
                    }
                }
                if (window) break;
            }
            if (!window) return;
            [self nm_fixTextContrastInView:window];
        });
    });
}

+ (void)nm_startContrastSweep {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(nm_sweepKeyWindowOnce)
                                                     name:NMThemeDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(nm_sweepKeyWindowOnce)
                                                     name:@"BackgroundUIEffectChanged"
                                                   object:nil];
    });
    [self nm_sweepKeyWindowOnce];
}

@end
