//
//  AnnouncementService.h
//  Amethyst
//
//  公告拉取服务
//  Task 130：公告源为本仓库托管的 announcements.json（raw.githubusercontent.com
//  主源 + jsDelivr 镜像级联，用户可用 general.news_url 自定义独占源）。
//  带 30 分钟本地缓存；全部在线源失败时回退缓存，再回退随包内置离线公告
//  （Task129h，Natives/resources/announcements-fallback.json）。
//

#import <Foundation/Foundation.h>

@class AnnouncementItem;

NS_ASSUME_NONNULL_BEGIN

/// 公告拉取完成回调
typedef void(^AnnouncementFetchHandler)(NSArray<AnnouncementItem *> * _Nullable items,
                                        NSError * _Nullable error);

@interface AnnouncementService : NSObject

+ (instancetype)sharedService;

/// 从远程拉取公告列表（带 30 分钟本地缓存）
/// @param completion 主线程回调
- (void)fetchAnnouncementsWithCompletion:(AnnouncementFetchHandler)completion;

/// 强制刷新（忽略缓存）
- (void)forceRefreshWithCompletion:(AnnouncementFetchHandler)completion;

/// 获取缓存中的公告（无网络请求）
- (NSArray<AnnouncementItem *> *)cachedAnnouncements;

@end

NS_ASSUME_NONNULL_END
