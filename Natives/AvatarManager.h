#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 账户头像自定义导入管理器（单例）。
/// 按 accountName 将自定义头像 PNG 存储到 Documents/avatars/<accountName>.png。
/// 读取时本地优先，回退到在线 URL。
@interface AvatarManager : NSObject

+ (instancetype)sharedManager;

/// 保存指定账户的自定义头像图片。
/// accountName 为 nil 或空串时调用无效。
- (void)saveAvatarForAccount:(NSString *)accountName
                     image:(UIImage *)image
          withCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// 读取指定账户的自定义头像图片，不存在返回 nil。
- (nullable UIImage *)avatarForAccount:(NSString *)accountName;

/// 是否已存在指定账户的自定义头像。
- (BOOL)hasCustomAvatarForAccount:(NSString *)accountName;

/// 删除指定账户的自定义头像（恢复使用在线 URL 头像）。
- (void)removeAvatarForAccount:(NSString *)accountName;

/// Task169：网络头像获取（10s 超时 + Caches 磁盘缓存 + 失败日志）。
/// completion 恰好回调一次（主线程），参数 = 最佳可用图片
/// （磁盘缓存 > 网络 > nil）；磁盘命中后仍在后台刷新缓存。
/// 替代各处裸 NSData dataWithContentsOfURL（默认 60s 挂起、失败静默、
/// 无持久化——装机实测主页头像"要点一下才能显示"的根因）。
- (void)fetchAvatarFromURL:(NSString *)urlString
                completion:(void (^)(UIImage * _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
