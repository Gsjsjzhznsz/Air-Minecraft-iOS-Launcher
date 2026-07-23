//
//  AnnouncementService.h
//  Amethyst
//
//  公告拉取服务
//  从 general.news_url 指向的 JSON API 拉取公告列表，带 30 分钟本地缓存。
//  缓存原始 NSData 到 NSUserDefaults，网络失败时回退到缓存。
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
