//
//  UIView+Neomorph.m
//  NeomorphKit
//
//  Task89：凸出新拟物渲染引擎。算法细节见 NMTheme.h / UIView+Neomorph.h。
//

#import "UIView+Neomorph.h"
#import "NMTheme.h"
#import <objc/runtime.h>

static void *kNMAttachmentKey = &kNMAttachmentKey;
static char kNMDarkCasterKey;
static char kNMLightCasterKey;

/// 表面样式（决定用 surface 还是 surfaceRaised 底色）
typedef NS_ENUM(NSUInteger, NMSurfaceStyle) {
    NMSurfaceStyleNormal = 0,
    NMSurfaceStyleRaised = 1,
};

/// 圆角模式（固定值 / 胶囊=高度一半）
typedef NS_ENUM(NSUInteger, NMRadiusMode) {
    NMRadiusModeFixed = 0,
    NMRadiusModePill  = 1,
};

#pragma mark - 附件对象：承载层几何同步 + 主题切换重绘

@interface _NMNeomorphAttachment : NSObject
@property (nonatomic, weak) UIView *host;
@property (nonatomic, assign) CGFloat cornerRadius;   // 固定圆角值（pill 模式忽略）
@property (nonatomic, assign) CGFloat shadowRadius;   // 库 style.shadowRadius
@property (nonatomic, assign) NMSurfaceStyle surfaceStyle;
@property (nonatomic, assign) NMRadiusMode radiusMode;
@property (nonatomic, assign) BOOL flat;              // 平贴模式（无阴影）
- (void)updateAppearance;
- (void)updateGeometry;
@end

@implementation _NMNeomorphAttachment

- (void)dealloc {
    // host weak 引用不持有；layer KVO 与通知需手动移除
    [_host.layer removeObserver:self forKeyPath:@"bounds"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithHost:(UIView *)host {
    self = [super init];
    if (self) {
        _host = host;
        // KVO bounds：视图尺寸变化（旋转/约束更新/cell 重用）时同步承载层
        [host.layer addObserver:self forKeyPath:@"bounds" options:NSKeyValueObservingOptionNew context:nil];
        // 主题切换：深浅色变化时重绘全部颜色与透明度
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidChange)
                                                     name:NMThemeDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"bounds"]) {
        [self updateGeometry];
    }
}

- (void)themeDidChange {
    [self updateAppearance];
}

- (void)updateGeometry {
    UIView *host = self.host;
    if (!host) return;
    CALayer *dark = objc_getAssociatedObject(host, &kNMDarkCasterKey);
    CALayer *light = objc_getAssociatedObject(host, &kNMLightCasterKey);
    if (!dark || !light) return;
    CGSize size = host.bounds.size;
    CGFloat radius;
    if (self.radiusMode == NMRadiusModePill) {
        // 胶囊：圆角 = 高度一半（库 helpers.js 的 borderRadius 夹断逻辑：
        // radius = min(radius, w/2, h/2)，胶囊高>0 时即 h/2）
        radius = MIN(size.height / 2.0, size.width / 2.0);
    } else {
        radius = self.cornerRadius;
        radius = MIN(radius, size.width / 2.0);
        radius = MIN(radius, size.height / 2.0);
    }
    CGRect frame = host.bounds;
    for (CALayer *caster in @[dark, light]) {
        // 帧外扩 1pt 避免 cornerRadius 抗锯齿边缘截断（不改变阴影形态）
        caster.frame = CGRectMake(-0.5, -0.5, frame.size.width + 1.0, frame.size.height + 1.0);
        caster.cornerRadius = radius;
    }
}

- (void)updateAppearance {
    UIView *host = self.host;
    if (!host) return;
    CALayer *dark = objc_getAssociatedObject(host, &kNMDarkCasterKey);
    CALayer *light = objc_getAssociatedObject(host, &kNMLightCasterKey);
    if (!dark || !light) return;
    NMTheme *theme = [NMTheme shared];
    UIColor *surface = (self.surfaceStyle == NMSurfaceStyleRaised) ? theme.surfaceRaised : theme.surface;
    CGColorRef surfaceCG = surface.CGColor;

    // 视图自身：surface 底色、圆角、不裁剪（阴影由承载层负责）
    host.backgroundColor = surface;
    host.layer.cornerRadius = self.radiusMode == NMRadiusModePill
        ? MIN(host.bounds.size.height / 2.0, host.bounds.size.width / 2.0)
        : self.cornerRadius;
    if (!self.flat) {
        // 凸出模式必须放开裁剪（阴影在帧外）；平贴模式保留视图原有裁剪设置，
        // 避免侧栏/右面板等内容溢出圆角
        host.layer.masksToBounds = NO;
    }

    CGFloat r = self.shadowRadius;
    if (self.flat || r <= 0) {
        // 平贴表面：承载层仅提供底色与圆角，无阴影
        for (CALayer *caster in @[dark, light]) {
            if (!caster) continue;
            caster.backgroundColor = surfaceCG;
            caster.shadowOpacity = 0;
            caster.shadowRadius = 0;
        }
        [self updateGeometry];
        return;
    }

    // 库 Neomorph iOS 原生路径：
    //   暗层 offset (+r,+r) 黑；亮层 offset (−r,−r) 白；模糊均 = r；
    //   透明度按表面色亮度自动计算
    dark.backgroundColor = surfaceCG;
    dark.shadowColor = theme.darkShadowColor.CGColor;
    dark.shadowOffset = CGSizeMake(r, r);
    dark.shadowRadius = r;
    dark.shadowOpacity = [theme darkShadowOpacityForSurfaceColor:surface];

    light.backgroundColor = surfaceCG;
    light.shadowColor = theme.lightShadowColor.CGColor;
    light.shadowOffset = CGSizeMake(-r, -r);
    light.shadowRadius = r;
    light.shadowOpacity = [theme lightShadowOpacityForSurfaceColor:surface];

    [self updateGeometry];
}

@end

#pragma mark - 安装/卸载

static _NMNeomorphAttachment *NMInstallOnView(UIView *view,
                                              CGFloat cornerRadius,
                                              CGFloat shadowRadius,
                                              NMSurfaceStyle style,
                                              NMRadiusMode radiusMode,
                                              BOOL flat) {
    _NMNeomorphAttachment *old = objc_getAssociatedObject(view, kNMAttachmentKey);
    [view nm_removeNeomorph];

    CALayer *dark = [CALayer layer];
    dark.masksToBounds = NO;
    CALayer *light = [CALayer layer];
    light.masksToBounds = NO;
    // 承载层置于最底部（内容 subviews 在其上）；先暗后亮，亮层底色覆盖暗层底色，
    // 阴影均在承载层帧之外发散互不遮挡
    [view.layer insertSublayer:light atIndex:0];
    [view.layer insertSublayer:dark atIndex:0];

    objc_setAssociatedObject(view, &kNMDarkCasterKey, dark, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kNMLightCasterKey, light, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    _NMNeomorphAttachment *attachment =
        [[_NMNeomorphAttachment alloc] initWithHost:view];
    attachment.cornerRadius = cornerRadius;
    attachment.shadowRadius = shadowRadius;
    attachment.surfaceStyle = style;
    attachment.radiusMode = radiusMode;
    attachment.flat = flat;
    objc_setAssociatedObject(view, kNMAttachmentKey, attachment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [attachment updateAppearance];
    // 首次安装时 bounds 可能尚未布局（translatesAutoresizingMaskIntoConstraints=NO
    // 的视图在约束激活后才有尺寸），updateGeometry 已由 updateAppearance 调用，
    // KVO 会在 bounds 变化时再次同步。
    return attachment;
}

#pragma mark - UIView 分类实现

@implementation UIView (Neomorph)

- (void)nm_convex {
    [self nm_convexRadius:12 shadowRadius:6];
}

- (void)nm_convexRadius:(CGFloat)cornerRadius {
    [self nm_convexRadius:cornerRadius shadowRadius:MAX(4.0, cornerRadius * 0.5)];
}

- (void)nm_convexRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius {
    NMInstallOnView(self, cornerRadius, shadowRadius, NMSurfaceStyleNormal, NMRadiusModeFixed, NO);
}

- (void)nm_convexRaisedRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius {
    NMInstallOnView(self, cornerRadius, shadowRadius, NMSurfaceStyleRaised, NMRadiusModeFixed, NO);
}

- (void)nm_pill {
    [self nm_pillWithStyle:NMSurfaceStyleNormal];
}

- (void)nm_pillRaised {
    [self nm_pillWithStyle:NMSurfaceStyleRaised];
}

- (void)nm_pillWithStyle:(NMSurfaceStyle)style {
    NMInstallOnView(self, 0, 4, style, NMRadiusModePill, NO);
}

- (void)nm_flatSurfaceWithRadius:(CGFloat)cornerRadius {
    NMInstallOnView(self, cornerRadius, 0, NMSurfaceStyleNormal, NMRadiusModeFixed, YES);
}

- (void)nm_flatRaisedSurfaceWithRadius:(CGFloat)cornerRadius {
    NMInstallOnView(self, cornerRadius, 0, NMSurfaceStyleRaised, NMRadiusModeFixed, YES);
}

- (void)nm_flatBackground {
    self.backgroundColor = [NMTheme shared].background;
    self.layer.cornerRadius = 0;
    [self nm_removeNeomorph];
}

- (void)nm_removeNeomorph {
    _NMNeomorphAttachment *attachment = objc_getAssociatedObject(self, kNMAttachmentKey);
    CALayer *dark = objc_getAssociatedObject(self, &kNMDarkCasterKey);
    CALayer *light = objc_getAssociatedObject(self, &kNMLightCasterKey);
    if (attachment) {
        // 置空即释放附件，KVO/通知在 dealloc 中统一移除（避免双重移除崩溃）
        objc_setAssociatedObject(self, kNMAttachmentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (dark) [dark removeFromSuperlayer];
    if (light) [light removeFromSuperlayer];
    objc_setAssociatedObject(self, &kNMDarkCasterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kNMLightCasterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)nm_hasNeomorph {
    return objc_getAssociatedObject(self, kNMAttachmentKey) != nil;
}

@end

#pragma mark - UIButton 分类实现

@implementation UIButton (Neomorph)

- (void)nm_styleConvexButton {
    [self nm_styleConvexButtonRadius:12 shadowRadius:6];
}

- (void)nm_styleConvexButtonRadius:(CGFloat)cornerRadius shadowRadius:(CGFloat)shadowRadius {
    [self nm_convexRadius:cornerRadius shadowRadius:shadowRadius];
    // 全灰新拟态（用户选定）：标题用 label 色，去掉系统着色
    [self setTitleColor:[NMTheme shared].label forState:UIControlStateNormal];
    [self setTitleColor:[[NMTheme shared].label colorWithAlphaComponent:0.45]
               forState:UIControlStateDisabled];
    self.tintColor = [NMTheme shared].label;
}

@end
