//
//  LiquidGlassCompat.m
//  AngelAuraAmethyst
//
//  iOS 26/27 液态玻璃（Liquid Glass）适配层实现
//
//  关键点：
//  1. 项目用 iPhoneOS 17.5 SDK（Xcode 15.4/16）构建，SDK 中没有 UIGlassEffect 声明，
//     因此不能直接 [UIGlassEffect alloc]，必须用 NSClassFromString + objc_msgSend
//     在运行时安全访问 iOS 26+ 的类。
//  2. iOS 26+ 标准控件（UINavigationBar/UITabBar/UIToolbar）会自动获得液态玻璃，
//     前提是移除自定义背景。本文件提供适配函数，让调用方在 iOS 26+ 移除自定义背景。
//  3. 低版本（< iOS 26）完全保持现状，回退到 UIBlurEffectStyleSystemMaterialDark。
//

#import "LiquidGlassCompat.h"
#import <objc/runtime.h>
#import <objc/message.h>

// iOS 26+ UIGlassEffect 的 Objective-C 运行时访问
// SDK（iPhoneOS 17.5）没有这些类声明，用 NSClassFromString 动态获取

/// 检查 iOS 26+ 液态玻璃是否可用
BOOL LGCIsLiquidGlassAvailable(void) {
    // 用 NSProcessInfo 检查系统版本，避免依赖 SDK 中不存在的 API
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    return osVersion.majorVersion >= 26;
}

/// 调用 iOS 26+ 的 [UIGlassEffect effectWithAppearance:]（或类似工厂方法）
/// 由于 SDK 没有声明，用 objc_msgSend 调用
static UIVisualEffect *_LGCCreateGlassEffect(BOOL isDark) {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    if (!glassEffectClass) {
        return nil;
    }
    // iOS 26 UIGlassEffect 有两个主要初始化路径：
    // 1. +[UIGlassEffect regularEffect] / +[UIGlassEffect clearEffect]
    // 2. 通过 appearance 属性区分（UIGlassEffectAppearanceRegular / Clear / Prominent）
    // 这里优先尝试 regularEffect（普通液态玻璃），然后通过 appearance 设置深色。
    SEL regularSel = NSSelectorFromString(@"regularEffect");
    if ([glassEffectClass respondsToSelector:regularSel]) {
        // +[UIGlassEffect regularEffect]
        id effect = ((id (*)(id, SEL))objc_msgSend)(glassEffectClass, regularSel);
        if (effect) {
            // 尝试设置 appearance（如果有的话）
            // UIGlassEffect.appearance 是 UIGlassEffectAppearance 枚举
            // 0 = regular, 1 = clear, 2 = prominent
            // 深色变体通过 tintColor 或 background 调整，这里保持 regular
            return effect;
        }
    }
    // 降级：尝试 alloc/init
    id effect = [[glassEffectClass alloc] init];
    if (effect) {
        return effect;
    }
    return nil;
}

/// 调用 iOS 26+ 的 [UIGlassContainerEffect alloc] initWithSpacing:]
static UIVisualEffect *_LGCCreateGlassContainerEffect(CGFloat spacing) {
    Class containerClass = NSClassFromString(@"UIGlassContainerEffect");
    if (!containerClass) {
        return nil;
    }
    id effect = [[containerClass alloc] init];
    if (effect) {
        // 设置 spacing 属性
        SEL setSpacingSel = NSSelectorFromString(@"setSpacing:");
        if ([effect respondsToSelector:setSpacingSel]) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(effect, setSpacingSel, spacing);
        }
        return effect;
    }
    return nil;
}

/// 创建模糊效果（低版本回退）
static UIVisualEffect *_LGCCreateBlurEffect(BOOL isDark) {
    if (@available(iOS 13.0, *)) {
        // UIBlurEffectStyleSystemMaterialDark 始终深色变体
        // UIBlurEffectStyleSystemMaterial 系统自适应
        return [UIBlurEffect effectWithStyle:isDark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterial];
    } else {
        return [UIBlurEffect effectWithStyle:isDark ? UIBlurEffectStyleDark : UIBlurEffectStyleLight];
    }
}

UIVisualEffectView *LGCCreateGlassEffectView(BOOL isDark) {
    UIVisualEffect *effect = nil;
    if (LGCIsLiquidGlassAvailable()) {
        effect = _LGCCreateGlassEffect(isDark);
    }
    if (!effect) {
        effect = _LGCCreateBlurEffect(isDark);
    }
    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
    effectView.frame = CGRectZero;
    effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    effectView.userInteractionEnabled = NO;
    return effectView;
}

UIVisualEffectView *LGCCreateGlassContainerView(CGFloat spacing, BOOL isDark) {
    UIVisualEffect *effect = nil;
    if (LGCIsLiquidGlassAvailable()) {
        effect = _LGCCreateGlassContainerEffect(spacing);
    }
    if (!effect) {
        effect = _LGCCreateBlurEffect(isDark);
    }
    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:effect];
    effectView.frame = CGRectZero;
    effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    effectView.userInteractionEnabled = NO;
    return effectView;
}

UIVisualEffectView *LGCApplyGlassBackgroundToView(UIView *view, BOOL isDark) {
    if (!view) return nil;
    // 移除已有的 UIVisualEffectView 子视图（标记）
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            [sub removeFromSuperview];
        }
    }
    UIVisualEffectView *effectView = LGCCreateGlassEffectView(isDark);
    effectView.frame = view.bounds;
    effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view insertSubview:effectView atIndex:0];
    return effectView;
}

void LGCAdaptNavigationBar(UINavigationBar *navigationBar) {
    if (!navigationBar) return;
    if (!LGCIsLiquidGlassAvailable()) return;
    // iOS 26+: 移除自定义背景，让系统接管液态玻璃
    // 标准做法：使用 transparent 背景，让 scrollEdgeAppearance 的标准配置生效
    // 1. 设置标准 Appearance 为 transparent
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        navigationBar.standardAppearance = appearance;
        navigationBar.scrollEdgeAppearance = appearance;
        // iOS 26+ compactAppearance 也设置
        navigationBar.compactAppearance = appearance;
    }
    // 2. 移除背景图片（如果有）
    [navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    [navigationBar setShadowImage:nil];
    // 3. 设置 translucent = YES（液态玻璃需要透明）
    navigationBar.translucent = YES;
}

void LGCAdaptBar(UIBar *bar) {
    if (!bar) return;
    if (!LGCIsLiquidGlassAvailable()) return;
    // UIToolbar / UITabBar 通用适配：移除自定义背景
    if ([bar isKindOfClass:[UIToolbar class]]) {
        UIToolbar *toolbar = (UIToolbar *)bar;
        if (@available(iOS 13.0, *)) {
            UIToolbarAppearance *appearance = [UIToolbarAppearance new];
            [appearance configureWithTransparentBackground];
            toolbar.standardAppearance = appearance;
            toolbar.compactAppearance = appearance;
            if (@available(iOS 15.0, *)) {
                toolbar.scrollEdgeAppearance = appearance;
            }
        }
        toolbar.barStyle = UIBarStyleDefault;
        [toolbar setBarTintColor:nil];
    } else if ([bar isKindOfClass:[UITabBar class]]) {
        UITabBar *tabBar = (UITabBar *)bar;
        if (@available(iOS 13.0, *)) {
            UITabBarAppearance *appearance = [UITabBarAppearance new];
            [appearance configureWithTransparentBackground];
            tabBar.standardAppearance = appearance;
            if (@available(iOS 15.0, *)) {
                tabBar.scrollEdgeAppearance = appearance;
            }
        }
        tabBar.barStyle = UIBarStyleDefault;
        [tabBar setBarTintColor:nil];
    }
}

void LGCAdaptBarButtonItem(UIBarButtonItem *item) {
    if (!item) return;
    if (!LGCIsLiquidGlassAvailable()) return;
    // iOS 26+: 隐藏 customView 周围的共享玻璃背景
    // hidesSharedBackground 是 iOS 26+ 新属性
    SEL hidesSharedBackgroundSel = NSSelectorFromString(@"setHidesSharedBackground:");
    if ([item respondsToSelector:hidesSharedBackgroundSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(item, hidesSharedBackgroundSel, YES);
    }
}
