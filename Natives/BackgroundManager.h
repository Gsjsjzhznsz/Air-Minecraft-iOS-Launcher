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

// Task172（用户定稿，重写卡片管线）：新拟态界面开关。
//   开启（默认）→ 卡片永远按"正常态"渲染：规格表面色 + 双阴影（即用户
//   复现方法"Bing 壁纸开着调一次 UI 效果再关掉 Bing 壁纸后看到的形态"），
//   与是否有壁纸完全无关——壁纸适配分支整链退役，不再有"动态卡面"。
//   关闭 → 回归旧管线：有壁纸走毛玻璃/半透明（设置页其余 UI 效果选项
//   恢复可操作），无壁纸走原生平铺。设置页"模糊程度"下方的开关行控制，
//   开启时其余 UI 效果选项变灰、新拟态透明度可操作，关闭反转。
@property (nonatomic, assign) BOOL cardsNeumorphEnabled; // defaults background_cards_neumorph_enabled，默认 YES

// Task170（Task172 语义修订）：卡片新拟态"本体"透明度滑条（0% ~ 100%）。
//   语义 = 卡片本体（卡面规格表面色 + 双阴影承载层）按比例淡化；文字/
//   图标等内容子视图不参与（保持全不透明）——不再使用宿主 view.alpha
//   整体缩放（那会把文字一起淡掉，用户定稿"不要包括字体"）。
//   100%（默认）= 规格表面原样；调低 = 卡面连同边缘阴影晕影一起变淡；
//   0% = 卡面与阴影完全透明（文字仍可见，极端档）。
//   仅在新拟态界面开关开启时参与渲染；列表行（applyCardEffectToCell）
//   恒为平贴新拟态表面，不受此滑条影响。
@property (nonatomic, assign) CGFloat cardsNeumorphOpacity; // 0.0 ~ 1.0

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