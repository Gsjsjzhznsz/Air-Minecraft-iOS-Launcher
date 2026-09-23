//
//  BingWallpaperManager.h
//  Amethyst
//
//  Task151：Bing 每日壁纸管理器。
//  接入方式与业界第三方一致：Bing 官方 HPImageArchive 无鉴权 JSON 接口
//  （https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN），
//  双源兜底（cn.bing.com 失败回退 www.bing.com），图片 URL 补全 host 前缀
//  即可下载；1920x1080 变体可替换为 UHD 取 4K（失败静默回退原图）。
//  职责：元数据拉取/解析/持久化、图片磁盘缓存、每日自动刷新与自动应用
//  （与 BackgroundManager 的 bing 来源联动：用户自定义壁纸优先）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - BingWallpaperItem

/// 单张 Bing 壁纸元数据（对应 HPImageArchive images[] 一项）
@interface BingWallpaperItem : NSObject

/// Bing 侧日期（yyyyMMdd，如 20260923），同时作为本地缓存文件名主键（稳定唯一）
@property (nonatomic, copy, readonly) NSString *startdate;
/// 壁纸标题（可能为空串，旧条目无 title 字段）
@property (nonatomic, copy, readonly) NSString *title;
/// 版权说明（含 © 作者，必展示于画廊操作面板）
@property (nonatomic, copy, readonly) NSString *copyright;
/// 全尺寸图片绝对 URL（1920x1080，直接可下载）
@property (nonatomic, copy, readonly) NSString *imageURL;
/// UHD 变体绝对 URL（4K，按 1920x1080 → UHD 替换规则推导；可能 404，调用方需回退）
@property (nonatomic, copy, readonly) NSString *uhdImageURL;
/// 缩略图 URL（th 服务附加 w 参数，忽略则返回原图，零失败模式）
@property (nonatomic, copy, readonly) NSString *thumbImageURL;

@end

#pragma mark - BingWallpaperManager

@interface BingWallpaperManager : NSObject

+ (instancetype)sharedManager;

/// Bing 每日壁纸总开关（默认开启；持久化于 NSUserDefaults bing_wallpaper_enabled）
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/// 已缓存的壁纸元数据（最新在前，至多 8 条；来自磁盘缓存，离线可用）
@property (nonatomic, copy, readonly) NSArray<BingWallpaperItem *> *items;

/// 最近一次成功同步时间（nil = 从未同步）
@property (nonatomic, readonly, nullable) NSDate *lastSyncDate;

/// 启动/回前台自动刷新入口：
/// 1) 开关关闭 → 直接返回；
/// 2) 用户已设置自定义壁纸（来源非 bing）→ 让位，不拉取不覆盖；
/// 3) 否则异步刷新元数据并自动应用今日图（离线时回退最近一次缓存图）。
/// 全程异步，不阻塞启动。
- (void)autoRefreshAndApplyIfEnabled;

/// 手动刷新元数据（设置页「立即刷新」/画廊刷新按钮）。
/// completion 主线程回调；success=元数据拉取并解析成功。
- (void)refreshWithCompletion:(nullable void (^)(BOOL success, NSError *_Nullable error))completion;

/// 确保条目图片已下载到本地缓存并返回路径（磁盘命中直接回调）。
/// 优先尝试 UHD 变体，404/失败静默回退 1920x1080 原图。
/// completion 主线程回调；path 为 nil 表示全部变体失败。
- (void)ensureImageForItem:(BingWallpaperItem *)item
                completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion;

/// 确保条目缩略图已缓存并返回UIImage（画廊网格用；失败回调 nil，cell 显示占位）。
- (void)thumbnailForItem:(BingWallpaperItem *)item
              completion:(void (^)(UIImage *_Nullable image))completion;

/// 同步取已缓存缩略图（cell 复用快速填充，无磁盘 IO 阻塞主线程由调用方权衡；
/// 未命中返回 nil 并可转 ensureThumbnail 异步补）
- (nullable UIImage *)cachedThumbnailForItem:(BingWallpaperItem *)item;

/// 清空内存缓存（不删磁盘，低内存告警时调用）
- (void)purgeMemoryCache;

@end

/// Task151：Bing 壁纸元数据刷新完成通知（object = manager）。
/// 设置页监听以刷新「今日：xxx」状态行与画廊数据。
FOUNDATION_EXPORT NSString * const BingWallpaperDidUpdateNotification;

NS_ASSUME_NONNULL_END
