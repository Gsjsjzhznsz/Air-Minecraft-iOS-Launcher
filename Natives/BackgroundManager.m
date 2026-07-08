//
//  BackgroundManager.m
//  Amethyst
//
//  Background wallpaper manager implementation - Global Version with Transparency
//

#import "BackgroundManager.h"
#import "LiquidGlassCompat.h"
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
    
    // For default background, just set the window's background color
    // No need for container
    if (self.currentType == BackgroundTypeNone) {
        if (@available(iOS 13.0, *)) {
            window.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            window.backgroundColor = [UIColor blackColor];
        }
        return;
    }
    
    // Create container (for custom backgrounds)
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
    
    // For default background, just set the view's background color
    // No need for container or transparency
    if (self.currentType == BackgroundTypeNone) {
        if (@available(iOS 13.0, *)) {
            splitVC.view.backgroundColor = [UIColor systemBackgroundColor];
        } else {
            splitVC.view.backgroundColor = [UIColor blackColor];
        }
        return;
    }
    
    // Create container that covers entire split view (for custom backgrounds)
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
    
    // Add dark blur effect with adjustable intensity
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.tag = kBackgroundBlurTag;
    blurView.alpha = self.blurIntensity * 0.5; // max 0.5 for readability
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.frame = container.bounds;
    
    [container addSubview:blurView];
    
    // Add additional dimming view for better contrast
    UIView *dimView = [[UIView alloc] initWithFrame:container.bounds];
    dimView.tag = kBackgroundDimTag;
    dimView.backgroundColor = [UIColor blackColor];
    dimView.alpha = self.blurIntensity * 0.3; // max 0.3 for dimming
    dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    [container addSubview:dimView];
}

#pragma mark - Transparency Helpers with UI Effect Support

- (void)makeViewControllerTransparent:(UIViewController *)viewController {
    if (!viewController) return;
    
    // Main view - apply effect based on settings
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // 毛玻璃效果 - clear background, let blur show through
        viewController.view.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - semi-transparent dark background
        viewController.view.backgroundColor = [UIColor colorWithWhite:0 alpha:1.0 - self.uiOpacity];
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
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // iOS 26+: 液态玻璃 / iOS 14-25: 毛玻璃
        UIVisualEffectView *blurView = LGCCreateGlassEffectView(YES);
        blurView.frame = cell.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Remove old background views
        for (UIView *subview in cell.contentView.superview.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview != blurView) {
                [subview removeFromSuperview];
            }
        }

        cell.backgroundView = blurView;
        cell.contentView.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - simple semi-transparent background
        cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
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
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // iOS 26+: 液态玻璃 - 移除自定义背景让系统接管
        if (LGCIsLiquidGlassAvailable()) {
            LGCAdaptNavigationBar(navigationBar);
            return;
        }
        // 毛玻璃效果（iOS 14-25）
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = [UIColor clearColor];

            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
            appearance.backgroundEffect = blur;

            navigationBar.standardAppearance = appearance;
            navigationBar.scrollEdgeAppearance = appearance;
            navigationBar.compactAppearance = appearance;
        }
        navigationBar.barTintColor = [UIColor clearColor];
        navigationBar.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果
        navigationBar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        navigationBar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            appearance.backgroundEffect = nil;
            
            navigationBar.standardAppearance = appearance;
            navigationBar.scrollEdgeAppearance = appearance;
            navigationBar.compactAppearance = appearance;
        }
    }
}

- (void)applyEffectToToolbar:(UIToolbar *)toolbar {
    if (self.uiEffect == BackgroundUIEffectBlur) {
        // iOS 26+: 液态玻璃 - 移除自定义背景让系统接管
        if (LGCIsLiquidGlassAvailable()) {
            LGCAdaptBar(toolbar);
            return;
        }
        // 毛玻璃效果（iOS 14-25）
        if (@available(iOS 13.0, *)) {
            UIToolbarAppearance *appearance = [[UIToolbarAppearance alloc] init];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = [UIColor clearColor];
            
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
            appearance.backgroundEffect = blur;
            
            toolbar.standardAppearance = appearance;
            toolbar.scrollEdgeAppearance = appearance;
            toolbar.compactAppearance = appearance;
        }
        toolbar.barTintColor = [UIColor clearColor];
        toolbar.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果
        toolbar.barTintColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        toolbar.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        
        if (@available(iOS 13.0, *)) {
            UIToolbarAppearance *appearance = [[UIToolbarAppearance alloc] init];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
            appearance.backgroundEffect = nil;
            
            toolbar.standardAppearance = appearance;
            toolbar.scrollEdgeAppearance = appearance;
            toolbar.compactAppearance = appearance;
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

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // iOS 26+: 液态玻璃 / iOS 14-25: 毛玻璃
        // 先移除已有的 blur view
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                [subview removeFromSuperview];
            }
        }

        UIVisualEffectView *blurView = LGCCreateGlassEffectView(YES);
        blurView.tag = kBackgroundBlurTag;
        blurView.frame = view.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurView.layer.cornerRadius = view.layer.cornerRadius;
        blurView.layer.masksToBounds = YES;

        [view insertSubview:blurView atIndex:0];
        view.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果 - 移除 blur view，使用半透明背景
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                [subview removeFromSuperview];
            }
        }
        view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:self.uiOpacity];
    }
}

- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {
    if (!cell) return;

    if (self.uiEffect == BackgroundUIEffectBlur) {
        // iOS 26+ 液态玻璃 / 低版本毛玻璃效果
        for (UIView *subview in cell.contentView.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                [subview removeFromSuperview];
            }
        }

        UIVisualEffectView *blurView = LGCCreateGlassEffectView(YES);
        blurView.tag = kBackgroundBlurTag;
        blurView.frame = cell.contentView.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurView.layer.cornerRadius = cell.contentView.layer.cornerRadius;
        blurView.layer.masksToBounds = YES;

        [cell.contentView insertSubview:blurView atIndex:0];
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
    } else {
        // 半透明效果
        for (UIView *subview in cell.contentView.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == kBackgroundBlurTag) {
                [subview removeFromSuperview];
            }
        }
        cell.backgroundColor = [UIColor colorWithWhite:0.1 alpha:self.uiOpacity];
        cell.contentView.backgroundColor = [UIColor clearColor];
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
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:1 userInfo:@{NSLocalizedDescriptionKey: @"图片为空"}]);
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
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:2 userInfo:@{NSLocalizedDescriptionKey: @"图片压缩失败"}]);
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
                if (completion) completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:3 userInfo:@{NSLocalizedDescriptionKey: @"保存图片失败"}]);
            });
        }
    });
}

- (void)setVideoBackgroundWithURL:(NSURL *)videoURL completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (!videoURL || ![[NSFileManager defaultManager] fileExistsAtPath:videoURL.path]) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"BackgroundManager" code:4 userInfo:@{NSLocalizedDescriptionKey: @"视频文件不存在"}]);
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
                if (completion) completion(NO, copyError ?: [NSError errorWithDomain:@"BackgroundManager" code:5 userInfo:@{NSLocalizedDescriptionKey: @"复制视频失败"}]);
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