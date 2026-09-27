//
//  BackgroundManager.h
//  Amethyst
//
//  Background wallpaper manager - Global support for all view controllers
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BackgroundType) {
    BackgroundTypeNone = 0,
    BackgroundTypeImage,
    BackgroundTypeVideo
};

typedef NS_ENUM(NSInteger, BackgroundUIEffect) {
    BackgroundUIEffectTranslucent = 0,  // 半透明
    BackgroundUIEffectBlur              // 毛玻璃效果
};

@interface BackgroundManager : NSObject

+ (instancetype)sharedManager;

// Background type
@property (nonatomic, readonly) BackgroundType currentType;
@property (nonatomic, readonly, nullable) NSString *currentBackgroundPath;

// UI effect settings (for custom background)
@property (nonatomic, assign) BackgroundUIEffect uiEffect;
@property (nonatomic, assign) CGFloat uiOpacity;  // 0.0 ~ 1.0
@property (nonatomic, assign) CGFloat blurIntensity; // 0.0 ~ 1.0, 背景模糊程度

// Task172（用户定稿，重写卡片管线）：新拟态界面开关。Task177 规格定稿：
//   开启（默认）→ 卡片永远按 CSS 参考规格渲染：渐变表面 + 固定档双阴影
//   （卡体透明度可调 = cardsNeumorphOpacity，Task178 恢复），与是否有壁纸
//   完全无关；UI 效果类型/模糊度/壁纸透明度（uiOpacity）一律不影响卡片。
//   关闭 → 回归旧管线：有壁纸走毛玻璃/半透明（设置页其余 UI 效果选项
//   恢复可操作），无壁纸走原生平铺。设置页"模糊程度"下方的开关行控制；
//   Task178 用户定稿：开关不管开还是关，都不会使其他选项变灰（灰化退役），
//   且 UI 效果类型/模糊度在开启时也不影响新拟态——新拟态与旧管线两套
//   渲染并行共存，各读各的偏好。
@property (nonatomic, assign) BOOL cardsNeumorphEnabled; // defaults background_cards_neumorph_enabled，默认 YES
// Task178（Task170 机制恢复，用户定稿"只有那个透明度拉条可以改变新拟态
// 的透明度，当然字体始终是不透明的"）：卡片本体透明度——只淡卡体（渐变
// 表面 + 双阴影承载视图整体 alpha，引擎原语非宿主 alpha），文字/图标恒
// 不透明。与 UI 效果类型/模糊度/壁纸透明度（uiOpacity）完全无关，唯一
// 入口 = 本偏好。defaults background_cards_neumorph_opacity 直读写，
// 默认 1.0（= Task177 规格原样，用户已认可的定稿形态不缩水）。
@property (nonatomic, assign) CGFloat cardsNeumorphOpacity;

// Global background container
@property (nonatomic, strong, readonly, nullable) UIView *globalBackgroundContainer;

// Apply background globally
- (void)applyBackgroundToWindow:(UIWindow *)window;
- (void)applyBackgroundToSplitViewController:(UISplitViewController *)splitVC;
- (void)removeGlobalBackground;

// Legacy compatibility
- (void)applyBackgroundToView:(UIView *)view;
- (void)removeBackgroundFromView:(UIView *)view;

// Set background
- (void)setImageBackground:(UIImage *)image completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)setVideoBackgroundWithURL:(NSURL *)videoURL completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)clearBackground;

// Task151：Bing 每日壁纸联动（来源标记机制）
// 当前背景是否由 Bing 壁纸链路设置（source == @"bing"）。
// 语义：用户手动设置的图片/视频来源为 user，优先于 Bing 自动应用；
// 无背景或来源为 bing 时，BingWallpaperManager 可每日自动换图。
@property (nonatomic, readonly) BOOL isBingSource;
// Task162：背景容器是否真实挂在活窗口上（自愈判定）。
// 状态层（currentBackgroundPath）与视图层（globalBackgroundContainer）
// 可能脱节——例如历史会话的首次应用只落了状态、容器插入失败/宿主引用
// 丢失，用户实测“Bing 壁纸加载完成还要重启才有图”。Bing 链路用它判断
// 是否需要重放应用，避免静默跳过。
- (BOOL)isBackgroundLiveAttached;
// 将已存在于磁盘的 Bing 壁纸图直接登记为当前背景（不再复制到 backgrounds/
// 目录，避免每日图双份存储；来源标记为 bing）。
- (void)setBingBackgroundImageAtPath:(NSString *)path completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// Check if has background
- (BOOL)hasBackground;
- (BOOL)hasImageBackground;
- (BOOL)hasVideoBackground;

// Get background preview
- (nullable UIImage *)backgroundPreview;

// Pause/Resume video (for app lifecycle)
- (void)pauseVideo;
- (void)resumeVideo;

// Update background frame (call on rotation)
- (void)updateBackgroundFrame;

// Make view controllers transparent (for global background visibility)
- (void)makeViewControllerTransparent:(UIViewController *)viewController;
- (void)makeSplitViewControllerTransparent:(UISplitViewController *)splitVC;

// Task152：背景"从无到有"时（Bing 首次联网拉到图 / 用户首次设置图片或视频）
// 对当前窗口整棵 VC 树重新执行透明化管线——否则已加载的 VC 保持不透明底色，
// 新插入的背景容器被完全盖住，表现为"壁纸要重启软件后才显示"。
- (void)refreshTransparencyForWindowUI;

// Apply UI effect to any UIView (blur or translucent based on settings)
- (void)applyEffectToView:(UIView *)view;
- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell;
- (void)applyEffectToCell:(UITableViewCell *)cell;
/// Task136：表格 cell 的"卡片化"新拟态样式（下载页模组加载器等与上级菜单
/// 对齐的页面专用）——无自定义背景时 cell 整体应用凸出表面（圆角 50 基准、
/// 双外阴影）；有自定义背景时行为与 applyEffectToCell: 一致（毛玻璃/半透明）。
- (void)applyCardEffectToCell:(UITableViewCell *)cell;
/// Task163：独立卡片容器的新拟态凸起管线（下载版本卡等"该改的"）。
/// Task172 重写（用户定稿）：新拟态界面开关开启时与壁纸完全无关——永远
/// 规格表面色 + 双阴影（"正常态"），并按卡片本体透明度淡化（文字不动）；
/// 关闭时回归旧管线 applyEffectToView:（毛玻璃/半透明/原生平铺）。
- (void)applyNeumorphCardEffectToView:(UIView *)view;
// 适配 UISearchBar：移除默认不透明背景，让 searchBar 透出底层自定义启动器背景
- (void)applyEffectToSearchBar:(UISearchBar *)searchBar;

// Apply UI effect to navigation bar and toolbar
- (void)applyEffectToNavigationBar:(UINavigationBar *)navigationBar;
- (void)applyEffectToToolbar:(UIToolbar *)toolbar;

// Apply UI effect settings to current split view controller
- (void)refreshUIEffect;

@end

NS_ASSUME_NONNULL_END