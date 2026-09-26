#import "utils.h"
#import "AvatarManager.h"

@interface AvatarManager()
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSString *documentsDirectory;
@property (nonatomic, strong) NSString *avatarsDirectory;
@end

@implementation AvatarManager

+ (instancetype)sharedManager {
    static AvatarManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AvatarManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.fileManager = [NSFileManager defaultManager];
        NSArray *paths = [self.fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        self.documentsDirectory = [paths.firstObject path];
        self.avatarsDirectory = [self.documentsDirectory stringByAppendingPathComponent:@"avatars"];
        if (![self.fileManager fileExistsAtPath:self.avatarsDirectory]) {
            [self.fileManager createDirectoryAtPath:self.avatarsDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                   error:nil];
        }
    }
    return self;
}

/// 将 accountName 转换为安全的文件名（移除路径分隔符等非法字符）。
/// Minecraft 用户名通常为字母数字下划线，但仍做一层防护避免路径穿越。
- (NSString *)safeFileNameForAccount:(NSString *)accountName {
    if (accountName.length == 0) return @"anonymous";
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *parts = [accountName componentsSeparatedByCharactersInSet:invalid];
    NSString *cleaned = [parts componentsJoinedByString:@"_"];
    if (cleaned.length == 0) cleaned = @"anonymous";
    return cleaned;
}

- (NSString *)avatarPathForAccount:(NSString *)accountName {
    NSString *fileName = [self safeFileNameForAccount:accountName];
    return [self.avatarsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", fileName]];
}

- (void)saveAvatarForAccount:(NSString *)accountName
                     image:(UIImage *)image
          withCompletion:(void (^)(BOOL, NSError * _Nullable))completion {
    if (accountName.length == 0) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"AvatarError" code:1001 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_46", nil)}]);
        }
        return;
    }
    NSData *imageData = UIImagePNGRepresentation(image);
    if (!imageData) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"AvatarError" code:1002 userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_47", nil)}]);
        }
        return;
    }
    NSString *path = [self avatarPathForAccount:accountName];
    NSError *error;
    BOOL success = [imageData writeToURL:[NSURL fileURLWithPath:path] options:NSDataWritingAtomic error:&error];
    if (completion) {
        completion(success, error);
    }
}

- (UIImage *)avatarForAccount:(NSString *)accountName {
    if (accountName.length == 0) return nil;
    NSString *path = [self avatarPathForAccount:accountName];
    if (![self.fileManager fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (UIImage *)avatarForAccount:(NSString *)accountName
             usernameFallback:(NSString *)username {
    // Task180：accountId 优先，miss 且 username 非空时按 username 兑底
    //（兼容历史按 username 存盘的头像文件；账号 ID 漂移后旧文件仍可命中）
    UIImage *image = [self avatarForAccount:accountName];
    if (!image && username.length > 0 && ![username isEqualToString:accountName]) {
        image = [self avatarForAccount:username];
        if (image) {
            NSLog(@"[Task180] avatar hit via username fallback (%@ -> %@)", accountName, username);
        }
    }
    return image;
}

- (void)ame180_migrateAvatarFromAccount:(NSString *)oldAccount
                              toAccount:(NSString *)newAccount {
    // Task180：账号 ID 漂移（refresh 链改写 accountId）时头像文件随迁；
    // 仅当旧存在且新不存在时搬移（幂等防覆盖，与 loadSavedName 迁移家法一致）
    if (oldAccount.length == 0 || newAccount.length == 0 || [oldAccount isEqualToString:newAccount]) return;
    NSString *oldPath = [self avatarPathForAccount:oldAccount];
    NSString *newPath = [self avatarPathForAccount:newAccount];
    if ([self.fileManager fileExistsAtPath:oldPath] &&
        ![self.fileManager fileExistsAtPath:newPath]) {
        NSError *error = nil;
        BOOL ok = [self.fileManager moveItemAtPath:oldPath toPath:newPath error:&error];
        NSLog(@"[Task180] avatar migrated %@ -> %@ (%@)", oldAccount, newAccount, ok ? @"ok" : error.localizedDescription);
    }
}

- (BOOL)hasCustomAvatarForAccount:(NSString *)accountName {
    if (accountName.length == 0) return NO;
    return [self.fileManager fileExistsAtPath:[self avatarPathForAccount:accountName]];
}

- (void)removeAvatarForAccount:(NSString *)accountName {
    if (accountName.length == 0) return;
    NSString *path = [self avatarPathForAccount:accountName];
    if ([self.fileManager fileExistsAtPath:path]) {
        [self.fileManager removeItemAtPath:path error:nil];
    }
}

#pragma mark - Task169：网络头像获取（超时受控 + 磁盘缓存）

/// 网络头像的磁盘缓存目录（按 URL 哈希存原始字节，Caches 下系统可回收）。
- (NSString *)ame169_urlCacheDirectory {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"Ame169RemoteAvatars"];
    if (![self.fileManager fileExistsAtPath:dir]) {
        [self.fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

- (NSString *)ame169_cachePathForURL:(NSString *)urlString {
    // 简单稳定哈希（djb2）——缓存文件名只需唯一可复现，不需要密码学强度
    unsigned long long h = 5381;
    for (NSUInteger i = 0; i < urlString.length; i++) {
        h = ((h << 5) + h) + [urlString characterAtIndex:i];
    }
    return [[self ame169_urlCacheDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"avatar_%llu.img", h]];
}

/// Task169：网络头像获取（10s 超时 + 磁盘缓存 + 失败日志）。
/// 病历（装机 485b18c，"主页上方头像有时要点一下才能显示"）：旧实现
/// NSData dataWithContentsOfURL 默认 60s 挂起、失败完全静默、无任何持久
/// 化——xboxlive 头像域在境内网络慢/失败时，主页顶卡长时间默认头像，
/// 网络恰好完成后才因下次 cellForItem 显示（用户感知成"点一下才有"）。
/// 契约：completion 恰好回调一次（主线程），参数 = 最佳可用图片
/// （磁盘缓存 > 网络 > nil）。磁盘命中后仍在后台刷新缓存（下次冷启动
/// 才生效，头像变更低频，不双回调）。
- (void)fetchAvatarFromURL:(NSString *)urlString
                completion:(void (^)(UIImage * _Nullable))completion {
    if (![urlString isKindOfClass:NSString.class] || urlString.length == 0) {
        if (completion) completion(nil);
        return;
    }
    NSString *cachePath = [self ame169_cachePathForURL:urlString];
    NSData *cached = [self.fileManager contentsAtPath:cachePath];
    UIImage *cachedImage = cached ? [UIImage imageWithData:cached] : nil;
    if (cachedImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(cachedImage);
        });
        // 后台静默刷新（成功仅更新缓存，不再回调）
        [self ame169_networkFetchAvatar:urlString cachePath:cachePath completion:nil];
        return;
    }
    [self ame169_networkFetchAvatar:urlString cachePath:cachePath completion:^(UIImage *img) {
        if (completion) completion(img);
    }];
}

- (void)ame169_networkFetchAvatar:(NSString *)urlString
                        cachePath:(NSString *)cachePath
                       completion:(void (^)(UIImage * _Nullable))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        // Task172：坏 URL 路径也必须回主线程（契约：completion 恰好一次、
        // 永远在主线程；此前这里同步调，若调用方在后台线程则违反契约）。
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 10.0;  // Task169：受控超时（旧实现默认 60s 挂起）
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // Task169：失败必须有日志（旧实现静默，装机日志零痕迹）
            NSLog(@"[AvatarManager] Task169 avatar fetch failed (%@): %@",
                  urlString.lastPathComponent ?: urlString, error.localizedDescription);
            // Task172：失败路径同样必须回主线程——旧代码在 NSURLSession 的
            // 回调线程里直接调 completion，消费方（主页 Profile 卡）会在非
            // 主线程触碰 UICollectionView（reloadProfileSection）与 UIImageView，
            // 更新静默失效或延迟到下一次交互（用户感知"点一下才显示"）。
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
            return;
        }
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (img && data) {
            [data writeToFile:cachePath atomically:YES];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(img);
        });
    }];
    [task resume];
}

@end
