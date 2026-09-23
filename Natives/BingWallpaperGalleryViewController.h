//
//  BingWallpaperGalleryViewController.h
//  Amethyst
//
//  Task151：Bing 壁纸库画廊（近 8 天每日壁纸网格）。
//  基础功能：网格浏览（缩略图异步加载）、设为壁纸、保存到相册、
//  手动刷新、当前应用项勾选标记、离线缓存展示。
//

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface BingWallpaperGalleryViewController : UICollectionViewController

/// 工厂方法：按设备宽度预配置网格布局的画廊控制器（Task151）
+ (UICollectionViewController *)galleryController;

@end

NS_ASSUME_NONNULL_END
