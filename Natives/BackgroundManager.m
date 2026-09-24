#import "utils.h"
//
//  BackgroundManager.m
//  Amethyst
//
//  Background wallpaper manager implementation - Global Version with Transparency
//

#import "BackgroundManager.h"
#import "UIKit+NativeSurface.h"
#import <Photos/Photos.h>

static NSString * const kBackgroundTypeKey = @"background_type";
static NSString * const kBackgroundPathKey = @"background_path";
static NSString * const kBackgroundUIEffectKey = @"background_ui_effect";
static NSString * const kBackgroundUIOpacityKey = @"background_ui_opacity";
static NSString * const kBackgroundBlurIntensityKey = @"background_blur_intensity";
// Task151：背景来源标记（"user" = 用户手动设置，"bing" = Bing 每日壁纸自动应用）
static NSString * const kBackgroundSourceKey = @"background_source";
static NSString * const kBackgroundsFolder = @"backgrounds";
static const NSInteger kGlobalBackgroundTag = 99999;
static const NSInteger kBackgroundImageTag = 99998;
static const NSInteger kBackgroundBlurTag = 99997;
static const NSInteger kBackgroundDimTag = 99996;
static const NSInteger kDefaultBackgroundTag = 99995;
// Task160：模态弹窗页面级毛玻璃底层的 tag（防重复添加/便于移除重铺）
static const NSInteger kAme160GlassBackdropTag = 99994;

@interface BackgroundManager ()
@property (nonatomic, strong) AVPlayer *videoPlayer;
@property (nonatomic, strong) AVPlayerLayer *videoPlayerLayer;
@property (nonatomic, weak) UIView *currentBackgroundView;
@property (nonatomic, readwrite) BackgroundType currentType;
@property (nonatomic, readwrite, nullable) NSString *currentBackgroundPath;
// Task151：背景来源（@"user"/@"bing"，nil = 历史数据视为 user）
@property (nonatomic, copy, nullable) NSString *backgroundSource;
@property (nonatomic, weak) UIWindow *currentWindow;
@property (nonatomic, weak) UISplitViewController *currentSplitVC;
@property (nonatomic, strong, readwrite, nullable) UIView *globalBackgroundContainer;
@end

@implementation BackgroundManager

+ (instancetype)sharedManager {
    static BackgroundManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadSavedBackground];
        [self loadUISettings];
        [self setupNotifications];
    }
    return self;
}

- (void)setupNotifications {
    // App lifecycle
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    // Video loop
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
    
    // Orientation changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOrientationChange)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    
    // Window size changes (iPad multitasking, rotation)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateBackgroundFrame)
                                                 name:UIApplicationWillChangeStatusBarFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cleanupVideoPlayer];
}

#pragma mark - Backgrounds Folder

- (NSString *)backgroundsFolderPath {
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *folder = [docsDir stringByAppendingPathComponent:kBackgroundsFolder];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:folder]) {
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return folder;
}

#pragma mark - Load/Save Background

- (void)loadSavedBackground {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.currentType = [defaults integerForKey:kBackgroundTypeKey];
    self.currentBackgroundPath = [defaults stringForKey:kBackgroundPathKey];
    // Task151：读取来源标记；历史数据（升级安装）无标记时视为 user，
    // 保证老用户已设的自定义壁纸不会被 Bing 自动覆盖。
    self.backgroundSource = [defaults stringForKey:kBackgroundSourceKey];
    if (self.backgroundSource.length == 0) {
        self.backgroundSource = (self.currentType != BackgroundTypeNone) ? @"user" : nil;
    }

    // Validate path exists
    if (self.currentBackgroundPath && ![[NSFileManager defaultManager] fileExistsAtPath:self.currentBackgroundPath]) {
        self.currentBackgroundPath = nil;
        self.currentType = BackgroundTypeNone;
        self.backgroundSource = nil;
        [self saveBackgroundSettings];
    }
}

- (void)saveBackgroundSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentType forKey:kBackgroundTypeKey];
    [defaults setObject:self.currentBackgroundPath forKey:kBackgroundPathKey];
    // Task151：来源标记随背景持久化（nil 时移除，回退"无标记=user"语义）
    if (self.backgroundSource.length > 0) {
        [defaults setObject:self.backgroundSource forKey:kBackgroundSourceKey];
    } else {
        [defaults removeObjectForKey:kBackgroundSourceKey];
    }
    [defaults synchronize];
}

- (void)loadUISettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Task164：默认值判定从"范围检查"改为"键是否存在"（用户定稿：毛玻璃、
    // 透明度 60%、模糊 100%）。Task162 的范围检查有两个漏洞：
    //   ① kBackgroundUIEffectKey 从未保存时 integerForKey 返回 0 =
    //      BackgroundUIEffectTranslucent（枚举 0 = 半透明），范围检查
    //      [Translucent, Blur] 对 0 恒放行 → 新装设备默认"半透明"而非
    //      "毛玻璃"（用户实测"半透明 60%/0%"的第一半）；
    //   ② kBackgroundBlurIntensityKey 从未保存时 floatForKey 返回 0.0，
    //      "< 0.0" 检查抓不住 → 默认模糊 0%（第二半）。
    // 只有 _uiOpacity 的 "< 0.1" 检查碰巧把未保存的 0.0 归一到默认。
    // 现在三个键统一"objectForKey == nil = 从未保存 → 写默认；显式保存过
    // 的值（包括用户故意选的 半透明 / 0% 模糊）照常尊重"。
    NSNumber *ame164_effect = [defaults objectForKey:kBackgroundUIEffectKey];
    if (ame164_effect == nil) {
        _uiEffect = BackgroundUIEffectBlur; // Task162/164：默认毛玻璃效果
    } else {
        _uiEffect = [ame164_effect integerValue];
        if (_uiEffect < BackgroundUIEffectTranslucent || _uiEffect > BackgroundUIEffectBlur) {
            _uiEffect = BackgroundUIEffectBlur; // 越界值（历史损坏数据）兜底毛玻璃
        }
    }

    NSNumber *ame164_opacity = [defaults objectForKey:kBackgroundUIOpacityKey];
    if (ame164_opacity == nil) {
        _uiOpacity = 0.6; // Task162/164：默认透明度 60%
    } else {
        _uiOpacity = [ame164_opacity doubleValue];
        if (_uiOpacity < 0.1 || _uiOpacity > 1.0) {
            _uiOpacity = 0.6;
        }
    }

    NSNumber *ame164_blur = [defaults objectForKey:kBackgroundBlurIntensityKey];
    if (ame164_blur == nil) {
        _blurIntensity = 1.0; // Task162/164：默认模糊程度 100%
    } else {
        _blurIntensity = [ame164_blur doubleValue];
        if (_blurIntensity < 0.0 || _blurIntensity > 1.0) {
            _blurIntensity = 1.0;
        }
    }
}

- (void)saveUISettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.uiEffect forKey:kBackgroundUIEffectKey];
    [defaults setFloat:self.uiOpacity forKey:kBackgroundUIOpacityKey];
    [defaults setFloat:self.blurIntensity forKey:kBackgroundBlurIntensityKey];
    [defaults synchronize];
}

- (void)setUiEffect:(BackgroundUIEffect)uiEffect {
    _uiEffect = uiEffect;
    [self saveUISettings];
}

- (void)setUiOpacity:(CGFloat)uiOpacity {
    _uiOpacity = MAX(0.1, MIN(1.0, uiOpacity));
    [self saveUISettings];
}

- (void)setBlurIntensity:(CGFloat)blurIntensity {
    _blurIntensity = MAX(0.0, MIN(1.0, blurIntensity));
    [self saveUISettings];
}

#pragma mark - Global Background Application

- (void)applyBackgroundToWindow:(UIWindow *)window {
    if (!window) {
        [self removeGlobalBackground];
        return;
    }
    
    self.currentWindow = window;
    self.currentSplitVC = nil;
    
    // Remove existing
    [self removeGlobalBackground];

    // Task111：检测并切换（用户实测反馈：Task89 的强制纯色底把启动器背景照片
    // 功能全部顶掉了）。用户设置了自定义背景（图片/视频）时，恢复 Task89 之前的
    // 全局背景管线：容器插入窗口最底层（insertSubview:atIndex:0，即"调低层级"），
    // 图片/视频/模糊/压暗自下而上铺开，UI 悬浮其上；未设置背景时回归 iOS 原生
    // 系统底色（Task137：新拟态退役）。两种模式随 hasBackground 自动切换，
    // 设置/清除背景后本方法被重新调用（setImageBackground/clearBackground 既有链路）。
    if ([self hasBackground]) {
        // Task 129f：有自定义背景时也把窗口底色设为系统底色（动态适配深浅色）：
        // 一旦图片/视频装载失败（解码失败、视频初始化失败等），透出的底色是
        // 系统底色而非随机色。背景装载成功时该底色被容器完全覆盖，零视觉影响。
        window.backgroundColor = [UIColor systemBackgroundColor];
        UIView *container = [[UIView alloc] initWithFrame:window.bounds];
        container.tag = kGlobalBackgroundTag;
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        container.backgroundColor = [UIColor clearColor];

        // Insert at index 0 (behind everything)
        [window insertSubview:container atIndex:0];
        self.globalBackgroundContainer = container;

        // Apply content
        switch (self.currentType) {
            case BackgroundTypeImage:
                [self applyImageBackgroundToContainer:container];
                break;
            case BackgroundTypeVideo:
                [self applyVideoBackgroundToContainer:container];
                break;
            default:
                break;
        }
        return;
    }

    // Task137：新拟态退役——无自定义背景时回归 iOS 原生系统底色，
    // 深浅色由语义色自动适配。
    window.backgroundColor = [UIColor systemBackgroundColor];
}

- (void)applyBackgroundToSplitViewController:(UISplitViewController *)splitVC {
    if (!splitVC || !splitVC.view) {
        [self removeGlobalBackground];
        return;
    }

    self.currentSplitVC = splitVC;
    self.currentWindow = nil;

    // Remove existing
    [self removeGlobalBackground];

    // Task111：同 applyBackgroundToWindow 的检测并切换——有自定义背景时恢复
    // Task89 之前的容器管线（最底层插入 + 图片/视频 + 子 VC 透明化），
    // 无背景时回归 iOS 原生系统底色（Task137：新拟态退役）。
    if ([self hasBackground]) {
        // Task 129f：与 applyBackgroundToWindow 同款兜底——背景容器之下的
        // splitVC.view 底色设为系统底色（动态适配深浅色），图片/视频装载
        // 失败时透出的是系统底色而非随机色。
        splitVC.view.backgroundColor = [UIColor systemBackgroundColor];
        UIView *container = [[UIView alloc] initWithFrame:splitVC.view.bounds];
        container.tag = kGlobalBackgroundTag;
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        container.backgroundColor = [UIColor clearColor];

        // Insert at the very bottom
        [splitVC.view insertSubview:container atIndex:0];
        self.globalBackgroundContainer = container;

        // Apply content
        switch (self.currentType) {
            case BackgroundTypeImage:
                [self applyImageBackgroundToContainer:container];
                break;
            case BackgroundTypeVideo:
                [self applyVideoBackgroundToContainer:container];
                break;
            default:
                break;
        }

        // Make all child controllers transparent (only for custom backgrounds)
        [self makeSplitViewControllerTransparent:splitVC];
        return;
    }

    // Task137：新拟态退役——无自定义背景时回归 iOS 原生系统底色。
    splitVC.view.backgroundColor = [UIColor systemBackgroundColor];
}

- (void)removeGlobalBackground {
    // Remove from window
    if (self.currentWindow) {
        UIView *existing = [self.currentWindow viewWithTag:kGlobalBackgroundTag];
        if (existing) [existing removeFromSuperview];
    }
    
    // Remove from split VC
    if (self.currentSplitVC && self.currentSplitVC.view) {
        UIView *existing = [self.currentSplitVC.view viewWithTag:kGlobalBackgroundTag];
        if (existing) [existing removeFromSuperview];
    }
    
    // Cleanup
    [self cleanupVideoPlayer];
    self.globalBackgroundContainer = nil;
    // Task161（Bing 壁纸“要重启才能加载”根修）：不再清空 currentWindow /
    // currentSplitVC。旧代码在这里把两个宿主引用置 nil，而
    // applyBackgroundToWindow: 的顺序是【先设 currentWindow → 再调本方法
    // → 本方法把它置 nil】——启动后宿主引用恒为 nil，后续
    // setBingBackgroundImageAtPath 的应用分支（currentSplitVC / currentWindow
    // 双 nil）什么都不做：Bing 图下载完成只落盘了状态，活 UI 从不插入
    // 背景容器，直到重启时启动路径才真正应用 = “要重启才能静默加载”。
    // 修复后语义：宿主注册归 applyBackgroundToWindow / ToSplitViewController
    // 所有（互斥另一侧置 nil 的逻辑保留在那两侧）；两个属性均为 weak，
    // 宿主销毁时自动置 nil，无悬挂风险。
}

- (void)updateBackgroundFrame {
    if (!self.globalBackgroundContainer) return;
    
    UIView *parent = self.globalBackgroundContainer.superview;
    if (!parent) return;
    
    // Update container frame
    self.globalBackgroundContainer.frame = parent.bounds;
    
    // Update default background view
    UIView *defaultBg = [self.globalBackgroundContainer viewWithTag:kDefaultBackgroundTag];
    if (defaultBg) defaultBg.frame = self.globalBackgroundContainer.bounds;
    
    // Update image view
    UIView *imageView = [self.globalBackgroundContainer viewWithTag:kBackgroundImageTag];
    if (imageView) imageView.frame = self.globalBackgroundContainer.bounds;
    
    // Update blur view
    UIView *blurView = [self.globalBackgroundContainer viewWithTag:kBackgroundBlurTag];
    if (blurView) blurView.frame = self.globalBackgroundContainer.bounds;
    
    // Update dim view
    UIView *dimView = [self.globalBackgroundContainer viewWithTag:kBackgroundDimTag];
    if (dimView) dimView.frame = self.globalBackgroundContainer.bounds;
    
    // Update video layer
    if (self.videoPlayerLayer) self.videoPlayerLayer.frame = self.globalBackgroundContainer.bounds;
}

- (void)handleOrientationChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateBackgroundFrame];
    });
}

#pragma mark - Background Content Application

- (void)applyDefaultBackgroundToContainer:(UIView *)container {
    // Remove existing default background
    UIView *existing = [container viewWithTag:kDefaultBackgroundTag];
    if (existing) [existing removeFromSuperview];
    
    // Create default background view that adapts to system appearance
    UIView *defaultBackgroundView = [[UIView alloc] initWithFrame:container.bounds];
    defaultBackgroundView.tag = kDefaultBackgroundTag;
    defaultBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Use system background color that adapts to light/dark mode
    // In dark mode: black, In light mode: system background color
    if (@available(iOS 13.0, *)) {
        defaultBackgroundView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        // Fallback for iOS < 13
        defaultBackgroundView.backgroundColor = [UIColor blackColor];
    }
    
    [container addSubview:defaultBackgroundView];
}

- (void)applyImageBackgroundToContainer:(UIView *)container {
    if (!self.currentBackgroundPath) return;
    
    UIImage *image = [UIImage imageWithContentsOfFile:self.currentBackgroundPath];
    if (!image) {
        // Task 129f：图片解码失败（内存压力/格式异常/文件半损）旧实现静默 return，
        // 容器空置 -> 透出 window 底色 systemBackgroundColor（浅色模式=纯白）——
        // “一些设备（如 iPad9）背景是白色而不是设置里的背景”的根因。
        // 修复：容器底铺系统底色兜底（动态适配深浅色），随机底色永不透出；
        // 日志锚点供下一轮装机取证。
        NSLog(@"[BackgroundManager] Task129f: background image failed to decode (%@) - falling back to system base", self.currentBackgroundPath.lastPathComponent);
        UIView *fallback = [[UIView alloc] initWithFrame:container.bounds];
        fallback.tag = kDefaultBackgroundTag;
        fallback.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        fallback.backgroundColor = [UIColor systemBackgroundColor];
        [container addSubview:fallback];
        return;
    }
    
    // Remove existing
    UIView *existing = [container viewWithTag:kBackgroundImageTag];
    if (existing) [existing removeFromSuperview];
    
    // Remove existing fallback (Task129f：解码成功时清除兜底层，避免叠压)
    UIView *existingFallback = [container viewWithTag:kDefaultBackgroundTag];
    if (existingFallback) [existingFallback removeFromSuperview];
    
    // Image view
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.tag = kBackgroundImageTag;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.frame = container.bounds;
    
    [container addSubview:imageView];
    
    // Add blur effect for UI readability
    [self addBlurEffectToContainer:container];
}

- (void)applyVideoBackgroundToContainer:(UIView *)container {
    if (!self.currentBackgroundPath) return;
    
    NSURL *videoURL = [NSURL fileURLWithPath:self.currentBackgroundPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.currentBackgroundPath]) return;
    
    [self cleanupVideoPlayer];
    
    // Create player
    self.videoPlayer = [AVPlayer playerWithURL:videoURL];
    self.videoPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    self.videoPlayer.muted = YES; // Mute to avoid interrupting other audio
    
    // Create player layer
    self.videoPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.videoPlayer];
    self.videoPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.videoPlayerLayer.frame = container.bounds;
    
    // Insert at bottom
    [container.layer insertSublayer:self.videoPlayerLayer atIndex:0];
    
    // Add blur effect
    [self addBlurEffectToContainer:container];
    
    // Start playing
    [self.videoPlayer play];
}

- (void)addBlurEffectToContainer:(UIView *)container {
    // Remove existing blur
    UIView *existingBlur = [container viewWithTag:kBackgroundBlurTag];
    if (existingBlur) [existingBlur removeFromSuperview];

    UIView *existingDim = [container viewWithTag:kBackgroundDimTag];
    if (existingDim) [existingDim removeFromSuperview];

    // 修复：使用 SystemThinMaterial（自适应浅色/深色，且较通透）替代硬编码 Dark。
    // 之前使用 UIBlurEffectStyleDark + 黑色 dim view 叠加，导致：
    // 1. 浅色模式下背景图被完全压暗成"中间一片黑"
    // 2. 左右侧栏完全不透明，背景图透不出来
    // SystemThinMaterial 会在浅色模式呈浅色毛玻璃、深色模式呈深色毛玻璃，
    // 且透明度适中，背景图可见。
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    }
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.tag = kBackgroundBlurTag;
    blurView.alpha = self.blurIntensity * 0.5; // max 0.5 for readability
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.frame = container.bounds;
    // Task161：纯装饰层显式关闭触摸——容器层在任何层级形态下都不得拦截
    // 命中测试（保险带：装机实测“壁砰设置页被盖住、滑块拖不动”的嫌疑层
    // 之一，与 Task160 模态毛玻璃底同轮排查）。
    blurView.userInteractionEnabled = NO;

    [container addSubview:blurView];

    // 修复：dim view 改为自适应颜色而非纯黑，避免浅色模式下过度压暗
    UIView *dimView = [[UIView alloc] initWithFrame:container.bounds];
    dimView.tag = kBackgroundDimTag;
    if (@available(iOS 13.0, *)) {
        dimView.backgroundColor = [UIColor labelColor];
    } else {
        dimView.backgroundColor = [UIColor blackColor];
    }
    dimView.alpha = self.blurIntensity * 0.2; // 降低到 0.2，避免过度压暗
    dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Task161：同上——装饰层不参与命中测试。
    dimView.userInteractionEnabled = NO;

    [container addSubview:dimView];
}

#pragma mark - Transparency Helpers with UI Effect Support

// Task152：背景"从无到有"时对整棵 VC 树重放透明化。首次启动时 Bing 壁纸尚未
// 下载完成，全部已加载 VC 在"无背景"时期经 makeViewControllerTransparent 的
// hasBackground 守卫直接 return（保持不透明 systemBackgroundColor）；数秒后
// setBingBackgroundImageAtPath 插入背景容器时没有任何机制通知这些既有 VC，
// 背景被完全盖住，用户实测表现为"Bing 壁纸加载完成需重启软件才正常"。
// 递归覆盖 childViewControllers（nav/split/tab 子栈均注册为 child）、
// presentedViewController；nav 栏/工具栏效果单独补刷。幂等，可安全重复调用。
- (void)refreshTransparencyForWindowUI {
    UIViewController *root = nil;
    if (self.currentSplitVC && self.currentSplitVC.view.window) {
        root = self.currentSplitVC;
    } else if (self.currentWindow && self.currentWindow.rootViewController) {
        root = self.currentWindow.rootViewController;
    }
    if (!root) {
        NSLog(@"[BackgroundManager] Task152: refreshTransparency skipped (no live root)");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ame_applyTransparencyRecursive:root];
        NSLog(@"[BackgroundManager] Task152: transparency refreshed for live VC tree");
    });
}

- (void)ame_applyTransparencyRecursive:(UIViewController *)vc {
    if (!vc) return;
    [self makeViewControllerTransparent:vc];

    if ([vc isKindOfClass:[UISplitViewController class]]) {
        for (UIViewController *child in [(UISplitViewController *)vc viewControllers]) {
            [self ame_applyTransparencyRecursive:child];
        }
    } else if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        for (UIViewController *child in nav.viewControllers) {
            [self ame_applyTransparencyRecursive:child];
        }
        nav.view.backgroundColor = [UIColor clearColor];
        [self applyEffectToNavigationBar:nav.navigationBar];
        [self applyEffectToToolbar:nav.toolbar];
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        for (UIViewController *child in [(UITabBarController *)vc viewControllers]) {
            [self ame_applyTransparencyRecursive:child];
        }
    }

    for (UIViewController *child in [vc childViewControllers]) {
        if (child != vc.presentedViewController) {
            [self ame_applyTransparencyRecursive:child];
        }
    }
    if (vc.presentedViewController) {
        [self ame_applyTransparencyRecursive:vc.presentedViewController];
    }
}

- (void)makeViewControllerTransparent:(UIViewController *)viewController {
    if (!viewController) return;

    // Task111：无自定义背景时什么都不做——新拟态纯色底下没有需要"透出"的
    // 背景图，保持各 VC 自己的背景与系统 cell 样式即可。此前无条件透明化会在
    // 纯色底上叠出白色蒙膜（Translucent 模式）并把表格 cell 洗成近透明的
    // secondarySystemBackgroundColor，用户实测表现为"有些菜单的背景消失了，
    // 只剩下按钮和阴影"。有自定义背景时才执行原有透明化管线。
    if (![self hasBackground]) {
        return;
    }

    // Main view - apply effect based on settings
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃效果 - clear background, let blur show through
        viewController.view.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - semi-transparent background
        // 修复：使用 systemBackgroundColor 替代硬编码黑色，自适应浅色/深色模式
        if (@available(iOS 13.0, *)) {
            UIColor *base = [UIColor systemBackgroundColor];
            viewController.view.backgroundColor = [base colorWithAlphaComponent:1.0 - self.uiOpacity];
        } else {
            viewController.view.backgroundColor = [UIColor colorWithWhite:0 alpha:1.0 - self.uiOpacity];
        }
    }

    // For UITableViewController
    if ([viewController isKindOfClass:[UITableViewController class]]) {
        UITableViewController *tableVC = (UITableViewController *)viewController;
        tableVC.tableView.backgroundColor = [UIColor clearColor];
        tableVC.tableView.backgroundView = nil;

        // Make cells semi-transparent or with blur effect
        tableVC.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;

        // Apply to all visible cells
        for (UITableViewCell *cell in tableVC.tableView.visibleCells) {
            [self applyEffectToCell:cell];
        }
    }

    // For UICollectionViewController
    if ([viewController isKindOfClass:[UICollectionViewController class]]) {
        UICollectionViewController *collectionVC = (UICollectionViewController *)viewController;
        collectionVC.collectionView.backgroundColor = [UIColor clearColor];
    }

    // Child view controllers
    for (UIViewController *childVC in viewController.childViewControllers) {
        [self makeViewControllerTransparent:childVC];
    }

    // Task161：模态弹窗页面级毛玻璃底收口到方法末尾——必须在上方
    // UITableViewController 分支（backgroundView = nil）之后执行，否则
    // table 控制器的 glass 会被立即清掉。仅毛玻璃模式（Task160 语义）。
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // Task160：模态弹窗"把背景加回来"（用户指令：自定义背景/自定义主页等
        // 大量小窗口此前整页透明直接透壁纸，文字直接压在壁纸上）。壁纸模式下
        // 给弹窗页铺一层页面级 SystemThinMaterial 毛玻璃底（文字可读、隐约透
        // 壁纸）；侧栏/右面板/root 中央内容区（非模态）不铺、保持透壁纸。
        // 无壁纸时上方已 return，弹窗保持各页自持的系统底色。
        [self ame160_applyGlassBackdropIfModal:viewController];
    }
}

/// Task160：模态弹窗页面级毛玻璃底（"把背景加回来"）。
/// 判定：present 出来的 VC（presentingViewController 非空）或弹窗 nav 内
/// push 的子页（navigationController.presentingViewController 非空）。侧栏/
/// 右面板/root 中央内容区（setContentViewController 嵌入）两链都为空，
/// 自然跳过。SystemThinMaterial：比 cell 级 SystemMaterial 更通透，避免
/// 页面底+cell 毛玻璃双层叠加后过浓；深浅色自动适配。
- (void)ame160_applyGlassBackdropIfModal:(UIViewController *)viewController {
    if (!viewController || !viewController.viewIfLoaded) return;
    BOOL isModal = (viewController.presentingViewController != nil) ||
                   (viewController.navigationController.presentingViewController != nil);
    if (!isModal) return;

    if (@available(iOS 13.0, *)) {
        // Task161：UITableViewController 的 view 即 UITableView 本体时
        // （未在 viewDidLoad 里重赋 tableView 的形态——BackgroundSettings
        // ViewController 正是如此），绝不 insertSubview——外来视图插进
        // UITableView 不在受支持用法内：子视图顺序由表自管（iOS 27 实测
        // 布局与命中测试不可预期，装机表现为"整页像盖了东西、文字按钮
        // 看不到、滑块拖不动"）。改挂 tableView.backgroundView——UIKit
        // 管理的背景位，天然位于全部 cells 之下且不参与命中测试。
        if ([viewController isKindOfClass:[UITableViewController class]] &&
            viewController.view == ((UITableViewController *)viewController).tableView) {
            UITableView *ame161_table = ((UITableViewController *)viewController).tableView;
            UIView *ame161_existing = ame161_table.backgroundView;
            if (ame161_existing.tag != kAme160GlassBackdropTag) {
                UIBlurEffect *ame161_effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
                UIVisualEffectView *ame161_glass = [[UIVisualEffectView alloc] initWithEffect:ame161_effect];
                ame161_glass.tag = kAme160GlassBackdropTag;
                ame161_glass.frame = ame161_table.bounds;
                ame161_glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                ame161_glass.userInteractionEnabled = NO;
                ame161_table.backgroundView = ame161_glass;
            }
            return;
        }

        // 防重复：先移除旧底层再重铺（重复调用/布局变更场景）
        for (UIView *sub in [NSArray arrayWithArray:viewController.view.subviews]) {
            if (sub.tag == kAme160GlassBackdropTag) [sub removeFromSuperview];
        }

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.tag = kAme160GlassBackdropTag;
        glass.frame = viewController.view.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.userInteractionEnabled = NO;
        [viewController.view insertSubview:glass atIndex:0];
    }
}

- (void)applyEffectToCell:(UITableViewCell *)cell {
    // Task111：检测并切换——有自定义背景时保持 Task89 之前的毛玻璃/半透明
    // cell 效果（背景图从 cell 下方透出）；无自定义背景时回归 iOS 原生列表
    // 外观（Task137：新拟态退役）——cell 保持系统默认透明底，页面底色由各页
    // 自持 systemBackgroundColor，深浅色由语义色自动适配，标准分隔线可见。
    if (![self hasBackground]) {
        cell.backgroundView = nil;
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
        return;
    }

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃效果 - use UIBlurEffect on cell background
        if (@available(iOS 13.0, *)) {
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.frame = cell.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            // Remove old background views
            for (UIView *subview in cell.contentView.superview.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview != blurView) {
                    [subview removeFromSuperview];
                }
            }

            // Task152：卡片化 cell（contentView 自带圆角，如下载页模组加载器列表）
            // 不能用直角 backgroundView 铺 blur——卡片圆角四角外会露出深色直角
            // （用户实测"圆角有黑直边"）。改为插入 contentView 底层并继承圆角；
            // 普通矩形行维持 backgroundView 原路径。
            CGFloat contentRadius = cell.contentView.layer.cornerRadius;
            if (contentRadius > 0) {
                blurView.frame = cell.contentView.bounds;
                blurView.layer.cornerRadius = contentRadius;
                blurView.layer.cornerCurve = cell.contentView.layer.cornerCurve;
                blurView.layer.masksToBounds = YES;
                blurView.userInteractionEnabled = NO;
                [cell.contentView insertSubview:blurView atIndex:0];
                cell.backgroundView = nil;
            } else {
                cell.backgroundView = blurView;
            }
        } else {
            cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
        cell.contentView.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - simple semi-transparent background
        // 修复：使用 secondarySystemBackgroundColor 替代硬编码 0.1 黑色
        if (@available(iOS 13.0, *)) {
            // Task152：卡片化 cell（圆角 > 0）把半透明底作用到 contentView，
            // 避免直角 cell 底色在卡片圆角外露直角。
            CGFloat contentRadius = cell.contentView.layer.cornerRadius;
            if (contentRadius > 0) {
                cell.backgroundColor = [UIColor clearColor];
                cell.contentView.backgroundColor = [[UIColor secondarySystemBackgroundColor]
                    colorWithAlphaComponent:self.uiOpacity];
                cell.contentView.layer.masksToBounds = YES;
                cell.backgroundView = nil;
            } else {
                cell.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
                cell.contentView.backgroundColor = [UIColor clearColor];
                cell.backgroundView = nil;
            }
        } else {
            cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            cell.contentView.backgroundColor = [UIColor clearColor];
            cell.backgroundView = nil;
        }
    }
}

- (void)makeSplitViewControllerTransparent:(UISplitViewController *)splitVC {
    if (!splitVC) return;
    
    // Make split view itself transparent
    splitVC.view.backgroundColor = [UIColor clearColor];
    
    // Make all view controllers transparent
    for (UIViewController *vc in splitVC.viewControllers) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)vc;
            
            // Navigation controller setup
            nav.view.backgroundColor = [UIColor clearColor];
            nav.navigationBar.translucent = YES;
            nav.toolbar.translucent = YES;
            
            // Apply effect to navigation bar
            [self applyEffectToNavigationBar:nav.navigationBar];
            [self applyEffectToToolbar:nav.toolbar];
            
            // Make all view controllers in stack transparent
            for (UIViewController *childVC in nav.viewControllers) {
                [self makeViewControllerTransparent:childVC];
            }
        } else {
            [self makeViewControllerTransparent:vc];
        }
    }
}

- (void)applyEffectToNavigationBar:(UINavigationBar *)navigationBar {
    // 关键修复（UI 累积异常 + 小白条根治）：
    // 1. 之前每次调用都重建 UINavigationBarAppearance，iOS 内部会重新生成 hairline
    //    UIImageView，累积后表现为"上方一行小白条"。现改为静态单例 Appearance，
    //    同一种效果只构建一次，避免反复触发 iOS 内部 hairline view 重建。
    // 2. 之前清理 hairline 只遍历 navigationBar.subviews（直接子视图），但 iOS 的
    //    hairline 常嵌在 _UINavigationBarBackground / _UIBarBackground 等私有子视图
    //    内部。改为递归遍历所有后代视图，彻底清理累积的 hairline。
    static UIImage *emptyImage = nil;
    static UINavigationBarAppearance *blurAppearance = nil;
    static UINavigationBarAppearance *translucentAppearance = nil;
    static UIColor *translucentBarColor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyImage = [UIImage new];
        // 预构建毛玻璃 Appearance（configureWithTransparentBackground + shadowImage 置空）
        blurAppearance = [[UINavigationBarAppearance alloc] init];
        [blurAppearance configureWithTransparentBackground];
        blurAppearance.backgroundColor = [UIColor clearColor];
        blurAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        blurAppearance.shadowColor = nil;
        blurAppearance.shadowImage = emptyImage;
        // 半透明 Appearance 在首次调用时按当前 uiOpacity 构建（见下方懒加载）
    });

    // 递归清理 iOS 内部累积的 hairline UIImageView（高度极小的分割线视图）
    // hairline 常嵌在 _UINavigationBarBackground / _UIBarBackground 等私有子视图内部
    //
    // 关键修复（Card/Root 布局进入所有页闪退加固）：
    //   block 内引用自身（removeHairlines(sub)）必须用 __block 限定符，否则
    //   捕获的是 nil（block 字面量赋值还未完成时的栈帧值），递归调用是 no-op，
    //   只会处理 navigationBar 的直接子视图，无法清理 _UIBarBackground 内层的 hairline。
    //   累积的 hairline 在 setContentViewController 反复切换时会触发私有子视图
    //   layout 解算异常，导致 EXC_BAD_ACCESS（不被 NSUncaughtExceptionHandler 捕获）。
    __block void (^removeHairlines)(UIView *) = ^(UIView *view) {
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UIImageView class]] &&
                sub.bounds.size.height > 0 &&
                sub.bounds.size.height <= 2.0) {
                [sub removeFromSuperview];
            } else {
                removeHairlines(sub);
            }
        }
    };
    removeHairlines(navigationBar);

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃效果 - 复用静态单例
        if (@available(iOS 13.0, *)) {
            navigationBar.standardAppearance = blurAppearance;
            navigationBar.scrollEdgeAppearance = blurAppearance;
            navigationBar.compactAppearance = blurAppearance;
        }
        navigationBar.barTintColor = [UIColor clearColor];
        navigationBar.backgroundColor = [UIColor clearColor];
        navigationBar.shadowImage = emptyImage;
    } else {
        // 半透明效果
        if (@available(iOS 13.0, *)) {
            UIColor *barColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
            navigationBar.barTintColor = barColor;
            navigationBar.backgroundColor = barColor;
            // 半透明 Appearance 需要按当前 uiOpacity 构建（uiOpacity 可变，无法像 blur 一样全局单例）
            // 但同一 uiOpacity 下复用同一实例，避免反复重建
            if (!translucentAppearance || ![translucentBarColor isEqual:barColor]) {
                UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
                [appearance configureWithTransparentBackground];
                appearance.backgroundColor = barColor;
                appearance.backgroundEffect = nil;
                appearance.shadowColor = nil;
                appearance.shadowImage = emptyImage;
                translucentAppearance = appearance;
                translucentBarColor = barColor;
            }
            navigationBar.standardAppearance = translucentAppearance;
            navigationBar.scrollEdgeAppearance = translucentAppearance;
            navigationBar.compactAppearance = translucentAppearance;
        } else {
            navigationBar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            navigationBar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
        navigationBar.shadowImage = emptyImage;
    }
}

- (void)applyEffectToToolbar:(UIToolbar *)toolbar {
    // 关键修复（同 applyEffectToNavigationBar:）：静态单例 Appearance + 递归清理 hairline
    static UIImage *emptyImage = nil;
    static UIToolbarAppearance *blurToolbarAppearance = nil;
    static UIToolbarAppearance *translucentToolbarAppearance = nil;
    static UIColor *translucentToolbarColor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyImage = [UIImage new];
        blurToolbarAppearance = [[UIToolbarAppearance alloc] init];
        [blurToolbarAppearance configureWithTransparentBackground];
        blurToolbarAppearance.backgroundColor = [UIColor clearColor];
        blurToolbarAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        blurToolbarAppearance.shadowColor = nil;
        blurToolbarAppearance.shadowImage = emptyImage;
    });

    // 递归清理累积的 hairline UIImageView
    // 关键修复：同 applyEffectToNavigationBar:，block 内引用自身必须用 __block
    // 限定符，否则递归调用是 no-op，无法清理 _UIBarBackground 内层的 hairline。
    __block void (^removeHairlines)(UIView *) = ^(UIView *view) {
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UIImageView class]] &&
                sub.bounds.size.height > 0 &&
                sub.bounds.size.height <= 2.0) {
                [sub removeFromSuperview];
            } else {
                removeHairlines(sub);
            }
        }
    };
    removeHairlines(toolbar);

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃效果 - 复用静态单例
        if (@available(iOS 13.0, *)) {
            toolbar.standardAppearance = blurToolbarAppearance;
            toolbar.scrollEdgeAppearance = blurToolbarAppearance;
            toolbar.compactAppearance = blurToolbarAppearance;
        }
        toolbar.barTintColor = [UIColor clearColor];
        toolbar.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果
        if (@available(iOS 13.0, *)) {
            UIColor *barColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
            toolbar.barTintColor = barColor;
            toolbar.backgroundColor = barColor;
            if (!translucentToolbarAppearance || ![translucentToolbarColor isEqual:barColor]) {
                UIToolbarAppearance *appearance = [[UIToolbarAppearance alloc] init];
                [appearance configureWithTransparentBackground];
                appearance.backgroundColor = barColor;
                appearance.backgroundEffect = nil;
                appearance.shadowColor = nil;
                appearance.shadowImage = emptyImage;
                translucentToolbarAppearance = appearance;
                translucentToolbarColor = barColor;
            }
            toolbar.standardAppearance = translucentToolbarAppearance;
            toolbar.scrollEdgeAppearance = translucentToolbarAppearance;
            toolbar.compactAppearance = translucentToolbarAppearance;
        } else {
            toolbar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            toolbar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
    }
}

- (void)refreshUIEffect {
    if (self.currentSplitVC && self.currentType != BackgroundTypeNone) {
        [self makeSplitViewControllerTransparent:self.currentSplitVC];
    }
    
    // Re-apply blur intensity to background container
    if (self.globalBackgroundContainer) {
        [self addBlurEffectToContainer:self.globalBackgroundContainer];
    }
    
    // Post notification for other views to refresh
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
}

#pragma mark - Unified View Effect Application

- (void)applyEffectToView:(UIView *)view {
    if (!view) return;

    // Task111：检测并切换——有自定义背景时恢复 Task89 之前的毛玻璃/半透明
    // 卡片效果（背景图从卡片下方透出）；无背景时维持新拟态凸出表面。
    // 防御性移除历史遗留的 blur 子视图在两条分支各自处理。
    if ([self hasBackground]) {
        // Task163：防御性清掉可能残留的新拟态阴影承载视图（从无壁纸新拟态
        // 切回的宿主，旧投影会漏在 blur/半透明底外面穿帮）；未挂载时空操作。
        [view ame_removeNeumorphShadow];
        if (self.uiEffect == BackgroundUIEffectBlur) {
            // 毛玻璃效果 - 创建 UIVisualEffectView 作为子视图
            for (UIView *subview in view.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }

            // SystemThinMaterial：浅色/深色模式自适应，且足够通透让背景图透出
            UIBlurEffect *blur;
            if (@available(iOS 13.0, *)) {
                blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
            } else {
                blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
            }
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.tag = kBackgroundBlurTag;
            blurView.frame = view.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            blurView.layer.cornerRadius = view.layer.cornerRadius;
            blurView.layer.masksToBounds = YES;

            // 模糊强度→透明度（0.3~1.0），无背景时再提高不透明度使 UI 更清晰
            CGFloat effectiveAlpha = 0.3 + (self.blurIntensity * 0.7);
            if (![self hasBackground]) {
                effectiveAlpha = MIN(effectiveAlpha + 0.2, 1.0);
            }
            blurView.alpha = effectiveAlpha;

            // 毛玻璃本身不响应触摸，让事件穿透到宿主视图（如 UIControl 卡片）
            blurView.userInteractionEnabled = NO;

            [view insertSubview:blurView atIndex:0];
            view.backgroundColor = [UIColor clearColor];
        } else {
            // 半透明效果 - 移除 blur view，使用半透明背景
            for (UIView *subview in view.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }
            if (@available(iOS 13.0, *)) {
                CGFloat effectiveOpacity = self.uiOpacity;
                if (![self hasBackground]) {
                    effectiveOpacity = MIN(effectiveOpacity + 0.3, 1.0);
                }
                UIColor *base = [UIColor secondarySystemBackgroundColor];
                view.backgroundColor = [base colorWithAlphaComponent:effectiveOpacity];
            } else {
                view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:self.uiOpacity];
            }
        }
        return;
    }

    // Task160：新拟态回归——无自定义背景时按新拟态规格重建表面。
    // 调用点预置了圆角的（卡片容器）= 规格表面色平贴卡片（无外阴影：
    // 本 helper 的调用者含 cell/列表场景，阴影会被裁剪互叠，统一平贴）；
    // 未设圆角的（多数页面的整页 self.view）= systemBackground 平铺整页，
    // 不加圆角不强制裁剪（原生页面形态）。
    CGFloat radius = view.layer.cornerRadius;
    if (radius > 0) {
        [view ame_applyNeumorphSurfaceFlatWithRadius:radius];
    } else {
        view.backgroundColor = [UIColor systemBackgroundColor];
    }
}

- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {
    if (!cell) return;

    // Task111：检测并切换——有自定义背景时恢复 Task89 之前的毛玻璃/半透明
    // cell 效果；无背景时维持新拟态凸出表面。
    if ([self hasBackground]) {
        // Task152：探测卡片容器（contentView 内第一个带圆角的非文本/控件子视图）。
        // 此前 blur/半透明一律铺满直角 contentView，而 VMTileBaseCell 等的圆角在
        // contentContainer 上 → 深色毛玻璃直角铺满 cell，卡片圆角四角外露出深色
        // 直角（用户实测"圆角有黑直边"）。现改为把效果作用到卡片容器本身，
        // 位置/尺寸/圆角全部对齐；无容器时回退 contentView（行为同旧）。
        UIView *cardTarget = nil;
        CGFloat cardRadius = 0;
        for (UIView *subview in cell.contentView.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                continue; // blur 层不参与容器探测
            }
            if (!cardTarget && subview.layer.cornerRadius > 0 &&
                ![subview isKindOfClass:[UIImageView class]] &&
                ![subview isKindOfClass:[UILabel class]] &&
                ![subview isKindOfClass:[UITextView class]] &&
                ![subview isKindOfClass:[UIControl class]]) {
                cardTarget = subview;
                cardRadius = subview.layer.cornerRadius;
            }
        }
        if (!cardTarget) {
            cardTarget = cell.contentView;
            cardRadius = cell.contentView.layer.cornerRadius > 0
                ? cell.contentView.layer.cornerRadius : 12;
        }

        // Task163：同 applyEffectToView——切回壁纸管线前清残留阴影承载层
        // （无壁纸新拟态卡片会挂在 contentView 或卡片容器上）。
        [cell.contentView ame_removeNeumorphShadow];
        [cardTarget ame_removeNeumorphShadow];

        if (self.uiEffect == BackgroundUIEffectBlur) {
            // 毛玻璃
            for (UIView *subview in cell.contentView.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }
            for (UIView *subview in cardTarget.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }

            UIBlurEffect *blur;
            if (@available(iOS 13.0, *)) {
                blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            } else {
                blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
            }
            UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
            blurView.tag = kBackgroundBlurTag;
            blurView.frame = cardTarget.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            blurView.layer.cornerRadius = cardRadius;
            blurView.layer.cornerCurve = cardTarget.layer.cornerCurve;
            blurView.layer.masksToBounds = YES;
            blurView.alpha = 0.3 + (self.blurIntensity * 0.7);
            blurView.userInteractionEnabled = NO;

            [cardTarget insertSubview:blurView atIndex:0];
            cardTarget.backgroundColor = [UIColor clearColor];
            cell.backgroundColor = [UIColor clearColor];
            cell.contentView.backgroundColor = [UIColor clearColor];
        } else {
            // 半透明
            for (UIView *subview in cell.contentView.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }
            for (UIView *subview in cardTarget.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }
            if (@available(iOS 13.0, *)) {
                cardTarget.backgroundColor = [[UIColor secondarySystemBackgroundColor]
                    colorWithAlphaComponent:self.uiOpacity];
            } else {
                cardTarget.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            }
            cell.backgroundColor = [UIColor clearColor];
            cell.contentView.backgroundColor = [UIColor clearColor];
        }
        return;
    }

    // Task163：无自定义背景时回归新拟态凸起卡片（用户实测"主页的卡片一点
    // 没改"——Task160 把 cell 管线统一成 Flat 平贴后磁贴完全丢失凸起感；
    // 现对卡片容器挂规格双阴影：暗影右下/高光左上，短边等比）。宿主链
    // 逐层放行裁剪（cell.clipsToBounds = NO；contentView/cell.layer masks
    // = NO）让阴影越出卡片边界投到磁贴间隙——相邻淡阴影叠加属新拟态正常
    // 形态，collectionView 边界外的阴影仍由其自身裁剪收口。
    UIView *target = nil;
    CGFloat radius = 0;
    for (UIView *sub in cell.contentView.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]] && sub.tag == kBackgroundBlurTag) {
            [sub removeFromSuperview];
            continue;
        }
        if (!target && sub.layer.cornerRadius > 0 &&
            ![sub isKindOfClass:[UIImageView class]] &&
            ![sub isKindOfClass:[UILabel class]] &&
            ![sub isKindOfClass:[UITextView class]] &&
            ![sub isKindOfClass:[UIControl class]]) {
            target = sub;
            radius = sub.layer.cornerRadius;
        }
    }
    if (!target) {
        target = cell.contentView;
        radius = cell.contentView.layer.cornerRadius > 0
            ? cell.contentView.layer.cornerRadius : 12;
    }
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.clipsToBounds = NO;
    cell.layer.masksToBounds = NO;
    cell.contentView.layer.masksToBounds = NO;
    [target ame_applyNeumorphSurface];
}

- (void)applyCardEffectToCell:(UITableViewCell *)cell {
    if (!cell) return;

    // 有自定义背景：与普通表格 cell 同管线（毛玻璃/半透明）
    if ([self hasBackground]) {
        [self applyEffectToCell:cell];
        return;
    }

    // Task160：新拟态退役→回归——无背景时 cell 整体为新拟态卡片行
    // （规格表面色平贴 + 12pt 圆角，与上级菜单卡片同语言，无自绘阴影；
    // cell 场景阴影会被裁剪互叠，用 flat 版本）。
    cell.backgroundView = nil;
    cell.backgroundColor = [UIColor clearColor];
    cell.clipsToBounds = YES;
    cell.layer.masksToBounds = NO;
    [cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];
}

- (void)applyNeumorphCardEffectToView:(UIView *)view {
    if (!view) return;

    // Task163：独立卡片容器的新拟态凸起管线（用户实测"下载页面版本选项
    // 一点没改"——版本卡走 applyEffectToView 的 Flat 尾分支完全丢失阴影）。
    // 有自定义背景：转调旧管线（毛玻璃/半透明），转调前清残留阴影层。
    if ([self hasBackground]) {
        [view ame_removeNeumorphShadow];
        [self applyEffectToView:view];
        return;
    }

    // 无自定义背景：规格表面色 + 双阴影（暗影右下/高光左上，短边等比）。
    // 容器未预置圆角时取 12 兼底；调用点（VersionCardCell）容器链已
    // masksToBounds = NO，阴影可越出卡片边界投到列表间隙。
    if (view.layer.cornerRadius <= 0) view.layer.cornerRadius = 12;
    [view ame_applyNeumorphSurface];
}

- (void)applyEffectToSearchBar:(UISearchBar *)searchBar {
    if (!searchBar) return;

    // 1. searchBar 整体背景透明，让底层自定义启动器背景透出
    //    UISearchBar 默认是不透明的 systemBackgroundColor，会遮挡全局背景图/毛玻璃
    searchBar.barTintColor = [UIColor clearColor];
    searchBar.backgroundColor = [UIColor clearColor];
    searchBar.translucent = YES;
    // Minimal 样式让系统不绘制不透明背景，仅保留输入框背景
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // 移除系统自动添加的 _UISearchBarBackground 不透明背景视图
    for (UIView *sub in searchBar.subviews) {
        for (UIView *inner in sub.subviews) {
            if ([NSStringFromClass(inner.class) containsString:@"Background"]) {
                inner.backgroundColor = [UIColor clearColor];
                inner.hidden = NO;
            }
        }
        if ([NSStringFromClass(sub.class) containsString:@"Background"]) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }

    // 2. 透明化内部 UITextField（搜索输入框）背景
    //    UITextField 默认带 systemFillColor 浅灰色背景，遮挡自定义背景
    UITextField *textField = nil;
    for (UIView *sub in searchBar.subviews) {
        for (UIView *inner in sub.subviews) {
            if ([inner isKindOfClass:[UITextField class]]) {
                textField = (UITextField *)inner;
                break;
            }
        }
        if (textField) break;
    }
    // iOS 13+ 可直接用 -searchTextField
    if (!textField && [searchBar respondsToSelector:@selector(searchTextField)]) {
        @try {
            textField = [searchBar performSelector:@selector(searchTextField)];
        } @catch (NSException *e) {
            textField = nil;
        }
    }
    if (textField) {
        if (self.uiEffect == BackgroundUIEffectBlur) {
            // 毛玻璃：输入框背景设为浅色半透明，保证文字可读且不挡背景
            if (@available(iOS 13.0, *)) {
                textField.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.5];
            } else {
                textField.backgroundColor = [UIColor colorWithWhite:0.95 alpha:0.5];
            }
        } else {
            // 半透明效果：输入框背景按 uiOpacity 调整
            if (@available(iOS 13.0, *)) {
                textField.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:MAX(0.3, self.uiOpacity)];
            } else {
                textField.backgroundColor = [UIColor colorWithWhite:0.95 alpha:MAX(0.3, self.uiOpacity)];
            }
        }
    }
}

#pragma mark - Legacy Methods

- (void)applyBackgroundToView:(UIView *)view {
    // Find the view controller or window
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UISplitViewController class]]) {
            [self applyBackgroundToSplitViewController:(UISplitViewController *)responder];
            return;
        }
        if ([responder isKindOfClass:[UIWindow class]]) {
            [self applyBackgroundToWindow:(UIWindow *)responder];
            return;
        }
        responder = responder.nextResponder;
    }
}

- (void)removeBackgroundFromView:(UIView *)view {
    [self removeGlobalBackground];
}

#pragma mark - Video Management

- (void)cleanupVideoPlayer {
    if (self.videoPlayer) {
        [self.videoPlayer pause];
        self.videoPlayer = nil;
    }
    if (self.videoPlayerLayer) {
        [self.videoPlayerLayer removeFromSuperlayer];
        self.videoPlayerLayer = nil;
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *playerItem = notification.object;
    [playerItem seekToTime:kCMTimeZero completionHandler:nil];
}

#pragma mark - App Lifecycle

- (void)appDidEnterBackground {
    [self pauseVideo];
}

- (void)appWillEnterForeground {
    [self resumeVideo];
}

- (void)pauseVideo {
    if (self.videoPlayer) [self.videoPlayer pause];
}

- (void)resumeVideo {
    if (self.videoPlayer && self.currentType == BackgroundTypeVideo) {
        [self.videoPlayer play];
    }
}

#pragma mark - Set Background

- (void)setImageBackground:(UIImage *)image completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!image) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:1 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_48", nil)}]);
        }
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Clear existing
        [self clearBackgroundInternal];
        
        // Save image
        NSString *fileName = [NSString stringWithFormat:@"background_image_%ld.jpg", (long)[[NSDate date] timeIntervalSince1970]];
        NSString *filePath = [[self backgroundsFolderPath] stringByAppendingPathComponent:fileName];
        
        NSData *imageData = UIImageJPEGRepresentation(image, 0.85);
        if (!imageData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:2 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_49", nil)}]);
            });
            return;
        }
        
        BOOL saved = [imageData writeToFile:filePath atomically:YES];
        
        if (saved) {
            self.currentType = BackgroundTypeImage;
            self.currentBackgroundPath = filePath;
            self.backgroundSource = @"user"; // Task151：用户手动设置，优先于 Bing 自动应用
            [self saveBackgroundSettings];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                // Task152：无背景 → 有背景的同款即时生效刷新（用户首次设置图片/视频）
                [self refreshTransparencyForWindowUI];

                if (completion) completion(YES, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:3 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_50", nil)}]);
            });
        }
    });
}

#pragma mark - Task151：Bing 每日壁纸联动

- (BOOL)isBingSource {
    return [self.backgroundSource isEqualToString:@"bing"];
}

// Task162：背景容器是否真实挂在活窗口上。
// 判定链：容器存在 → 容器有 window（在任意 UIWindow 层级里）→ 宿主引用
//（currentWindow / currentSplitVC）至少一个活着且其视图也在窗口上。
// 轻量纯读，Bing 每次元数据同步/前台回调时调用一次无性能负担。
- (BOOL)isBackgroundLiveAttached {
    if (![self hasBackground]) return NO;
    if (!self.globalBackgroundContainer) return NO;
    if (!self.globalBackgroundContainer.window) return NO;
    // 容器挂载了但宿主引用双失（理论上不该发生——容器就在宿主视图里），
    // 视为脱节，交由调用方重放应用重建全链。
    BOOL ame162_hostAlive = (self.currentWindow != nil && self.currentWindow.rootViewController != nil)
        || (self.currentSplitVC != nil && self.currentSplitVC.view.window != nil);
    return ame162_hostAlive;
}

// 将 Bing 缓存目录中已存在的图片直接登记为当前背景（不复制、不删源文件）。
// 与 setImageBackground 的差异：跳过 JPEG 重编码与 backgrounds/ 目录复制，
// 来源标记为 bing（供 BingWallpaperManager 的"用户优先"守卫与画廊勾选使用）。
- (void)setBingBackgroundImageAtPath:(NSString *)path completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:6 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_48", nil)}]);
        }
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self clearBackgroundInternal];

        self.currentType = BackgroundTypeImage;
        self.currentBackgroundPath = path;
        self.backgroundSource = @"bing";
        [self saveBackgroundSettings];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.currentSplitVC) {
                [self applyBackgroundToSplitViewController:self.currentSplitVC];
            } else if (self.currentWindow) {
                [self applyBackgroundToWindow:self.currentWindow];
            }
            // Task152：首次拉到 Bing 壁纸时既有 VC 是"无背景"时期建的（不透明），
            // 必须重放透明化，否则壁纸被盖住直到重启。
            [self refreshTransparencyForWindowUI];
            if (completion) completion(YES, nil);
        });
    });
}

- (void)setVideoBackgroundWithURL:(NSURL *)videoURL completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!videoURL || ![[NSFileManager defaultManager] fileExistsAtPath:videoURL.path]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:4 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_51", nil)}]);
        }
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Clear existing
        [self clearBackgroundInternal];
        
        // Copy video
        NSString *fileName = [NSString stringWithFormat:@"background_video_%ld.mp4", (long)[[NSDate date] timeIntervalSince1970]];
        NSString *filePath = [[self backgroundsFolderPath] stringByAppendingPathComponent:fileName];
        
        NSError *copyError = nil;
        BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:videoURL toURL:[NSURL fileURLWithPath:filePath] error:&copyError];
        
        if (copied) {
            self.currentType = BackgroundTypeVideo;
            self.currentBackgroundPath = filePath;
            self.backgroundSource = @"user"; // Task151：用户手动设置，优先于 Bing 自动应用
            [self saveBackgroundSettings];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                // Task152：无背景 → 有背景的同款即时生效刷新（用户首次设置图片/视频）
                [self refreshTransparencyForWindowUI];

                if (completion) completion(YES, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, copyError ?: [NSError errorWithDomain:@"BackgroundManager" code:5 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_52", nil)}]);
            });
        }
    });
}

- (void)clearBackground {
    [self clearBackgroundInternal];
    [self removeGlobalBackground];
    [self saveBackgroundSettings];
}

- (void)clearBackgroundInternal {
    [self cleanupVideoPlayer];

    if (self.currentBackgroundPath) {
        // Task151：仅清理 backgrounds/ 目录内的文件。Bing 缓存图
        // （Application Support/BingWallpaper/）不属于本目录，清除背景时
        // 保留缓存（离线回退与画廊复用需要），避免误删后重复下载。
        NSString *folder = [self backgroundsFolderPath];
        if ([self.currentBackgroundPath hasPrefix:folder]) {
            [[NSFileManager defaultManager] removeItemAtPath:self.currentBackgroundPath error:nil];
        }
    }

    self.currentType = BackgroundTypeNone;
    self.currentBackgroundPath = nil;
    self.backgroundSource = nil; // Task151：来源一并复位（saveBackgroundSettings 移除标记）
}

#pragma mark - Check Background

- (BOOL)hasBackground {
    return self.currentType != BackgroundTypeNone && self.currentBackgroundPath != nil;
}

- (BOOL)hasImageBackground {
    return self.currentType == BackgroundTypeImage && self.currentBackgroundPath != nil;
}

- (BOOL)hasVideoBackground {
    return self.currentType == BackgroundTypeVideo && self.currentBackgroundPath != nil;
}

#pragma mark - Preview

- (nullable UIImage *)backgroundPreview {
    if (self.currentType == BackgroundTypeImage && self.currentBackgroundPath) {
        return [UIImage imageWithContentsOfFile:self.currentBackgroundPath];
    }
    return nil;
}

@end