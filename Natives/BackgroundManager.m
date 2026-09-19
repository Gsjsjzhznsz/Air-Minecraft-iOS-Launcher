#import "utils.h"
//
//  BackgroundManager.m
//  Amethyst
//
//  Background wallpaper manager implementation - Global Version with Transparency
//

#import "BackgroundManager.h"
#import "NeomorphKit/NMTheme.h"
#import "NeomorphKit/UIView+Neomorph.h"
#import <Photos/Photos.h>

static NSString * const kBackgroundTypeKey = @"background_type";
static NSString * const kBackgroundPathKey = @"background_path";
static NSString * const kBackgroundUIEffectKey = @"background_ui_effect";
static NSString * const kBackgroundUIOpacityKey = @"background_ui_opacity";
static NSString * const kBackgroundBlurIntensityKey = @"background_blur_intensity";
static NSString * const kBackgroundsFolder = @"backgrounds";
static const NSInteger kGlobalBackgroundTag = 99999;
static const NSInteger kBackgroundImageTag = 99998;
static const NSInteger kBackgroundBlurTag = 99997;
static const NSInteger kBackgroundDimTag = 99996;
static const NSInteger kDefaultBackgroundTag = 99995;

@interface BackgroundManager ()
@property (nonatomic, strong) AVPlayer *videoPlayer;
@property (nonatomic, strong) AVPlayerLayer *videoPlayerLayer;
@property (nonatomic, weak) UIView *currentBackgroundView;
@property (nonatomic, readwrite) BackgroundType currentType;
@property (nonatomic, readwrite, nullable) NSString *currentBackgroundPath;
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
    
    // Validate path exists
    if (self.currentBackgroundPath && ![[NSFileManager defaultManager] fileExistsAtPath:self.currentBackgroundPath]) {
        self.currentBackgroundPath = nil;
        self.currentType = BackgroundTypeNone;
        [self saveBackgroundSettings];
    }
}

- (void)saveBackgroundSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentType forKey:kBackgroundTypeKey];
    [defaults setObject:self.currentBackgroundPath forKey:kBackgroundPathKey];
    [defaults synchronize];
}

- (void)loadUISettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _uiEffect = [defaults integerForKey:kBackgroundUIEffectKey];
    if (_uiEffect < BackgroundUIEffectTranslucent || _uiEffect > BackgroundUIEffectBlur) {
        _uiEffect = BackgroundUIEffectBlur; // 默认毛玻璃效果
    }
    
    _uiOpacity = [defaults floatForKey:kBackgroundUIOpacityKey];
    if (_uiOpacity < 0.1 || _uiOpacity > 1.0) {
        _uiOpacity = 0.7; // 默认透明度
    }
    
    _blurIntensity = [defaults floatForKey:kBackgroundBlurIntensityKey];
    if (_blurIntensity < 0.0 || _blurIntensity > 1.0) {
        _blurIntensity = 0.7; // 默认模糊程度
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
    // 图片/视频/模糊/压暗自下而上铺开，UI 悬浮其上；未设置背景时维持 Task89
    // 新拟态纯色底不动。两种模式随 hasBackground 自动切换，设置/清除背景后
    // 本方法被重新调用（setImageBackground/clearBackground 既有链路）。
    if ([self hasBackground]) {
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

    // Task89：无自定义背景时维持新拟态纯色底。新拟物双阴影只在统一底色上可见，
    // 因此仅在该分支应用 NMTheme 主题背景色。
    window.backgroundColor = [NMTheme nm_background];
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
    // 无背景时维持 Task89 新拟态纯色主题底。
    if ([self hasBackground]) {
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

    // Task89：无自定义背景时维持新拟态纯色主题底。
    splitVC.view.backgroundColor = [NMTheme nm_background];
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
    self.currentWindow = nil;
    self.currentSplitVC = nil;
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
    if (!image) return;
    
    // Remove existing
    UIView *existing = [container viewWithTag:kBackgroundImageTag];
    if (existing) [existing removeFromSuperview];
    
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

    [container addSubview:dimView];
}

#pragma mark - Transparency Helpers with UI Effect Support

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
}

- (void)applyEffectToCell:(UITableViewCell *)cell {
    // Task111：检测并切换——有自定义背景时保持 Task89 之前的毛玻璃/半透明
    // cell 效果（背景图从 cell 下方透出）；无自定义背景时改为 NMTheme surface
    // 实色卡片底（此前无条件走半透明分支，在纯色底上表现为近透明的洗白
    // 菜单，用户实测"有些菜单的背景消失了，只剩下按钮和阴影"）。
    // surface 与 background 对比明显、深浅色自适应，且不逐 cell 挂阴影
    // （表格滚动中阴影会被裁剪，观感差）。
    if (![self hasBackground]) {
        cell.backgroundView = nil;
        cell.backgroundColor = [NMTheme nm_surface];
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

            cell.backgroundView = blurView;
        } else {
            cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
        cell.contentView.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - simple semi-transparent background
        // 修复：使用 secondarySystemBackgroundColor 替代硬编码 0.1 黑色
        if (@available(iOS 13.0, *)) {
            cell.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
        } else {
            cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        }
        cell.contentView.backgroundColor = [UIColor clearColor];
        cell.backgroundView = nil;
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
        // 旧管线不走新拟态承载层；若此前已被装上（模式切换残留）则移除
        [view nm_removeNeomorph];
        return;
    }

    // Task89：新拟态改造（用户选定：凸出样式 + 纯色底）。
    // 原毛玻璃/半透明双模式在无自定义背景时由新拟态凸出表面替代
    // （surface 底色 + 暗/亮双阴影），透明度按表面色亮度自动计算（NMTheme）。
    // 调用点此前自行设置的 layer.cornerRadius 保留为卡片圆角（未设置时取 12）；
    // 阴影半径取圆角的一半（上限 8），保持库 demo 的比例感。
    CGFloat radius = view.layer.cornerRadius;
    if (radius <= 0) radius = 12;
    CGFloat shadowRadius = MAX(4.0, MIN(8.0, radius * 0.5));
    [view nm_convexRadius:radius shadowRadius:shadowRadius];
}

- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {
    if (!cell) return;

    // Task111：检测并切换——有自定义背景时恢复 Task89 之前的毛玻璃/半透明
    // cell 效果；无背景时维持新拟态凸出表面。
    if ([self hasBackground]) {
        if (self.uiEffect == BackgroundUIEffectBlur) {
            // 毛玻璃
            for (UIView *subview in cell.contentView.subviews) {
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
            blurView.frame = cell.contentView.bounds;
            blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            blurView.layer.cornerRadius = cell.contentView.layer.cornerRadius;
            blurView.layer.masksToBounds = YES;

            [cell.contentView insertSubview:blurView atIndex:0];
            cell.backgroundColor = [UIColor clearColor];
            cell.contentView.backgroundColor = [UIColor clearColor];
        } else {
            // 半透明
            for (UIView *subview in cell.contentView.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                    [subview removeFromSuperview];
                }
            }
            if (@available(iOS 13.0, *)) {
                cell.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.uiOpacity];
            } else {
                cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            }
            cell.contentView.backgroundColor = [UIColor clearColor];
        }
        return;
    }

    // Task89：新拟态改造（同 applyEffectToView）。卡片容器为 contentView 内
    // 第一个带圆角的子视图（各 cell 的既定结构）；找不到时退回 contentView
    // 整体（radius 12）。
    UIView *target = nil;
    CGFloat radius = 0;
    for (UIView *sub in cell.contentView.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]] && sub.tag == kBackgroundBlurTag) {
            [sub removeFromSuperview];
            continue;
        }
        if (!target && sub.layer.cornerRadius > 0) {
            target = sub;
            radius = sub.layer.cornerRadius;
        }
    }
    if (!target) {
        target = cell.contentView;
        radius = 12;
    }
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    CGFloat shadowRadius = MAX(4.0, MIN(8.0, radius * 0.5));
    [target nm_convexRadius:radius shadowRadius:shadowRadius];
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
            [self saveBackgroundSettings];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                
                if (completion) completion(YES, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:3 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_50", nil)}]);
            });
        }
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
            [self saveBackgroundSettings];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Reapply if needed
                if (self.currentSplitVC) {
                    [self applyBackgroundToSplitViewController:self.currentSplitVC];
                } else if (self.currentWindow) {
                    [self applyBackgroundToWindow:self.currentWindow];
                }
                
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
        [[NSFileManager defaultManager] removeItemAtPath:self.currentBackgroundPath error:nil];
    }
    
    self.currentType = BackgroundTypeNone;
    self.currentBackgroundPath = nil;
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