//
//  BingWallpaperManager.m
//  Amethyst
//
//  Task151：Bing 每日壁纸管理器实现。
//  方案：Bing 官方 HPImageArchive.aspx?format=js 无鉴权 JSON 接口（业界
//  第三方通用做法），cn.bing.com 主源 + www.bing.com 备源；元数据 plist
//  持久化 + 图片磁盘缓存（Application Support/BingWallpaper，避免 Caches
//  被系统清理导致离线首启无图）；UHD 变体优先、失败静默回退 1920x1080。
//

#import "BingWallpaperManager.h"
#import "BackgroundManager.h"
#import "utils.h"

NSString * const BingWallpaperDidUpdateNotification = @"BingWallpaperDidUpdate";

static NSString * const kBingEnabledKey = @"bing_wallpaper_enabled";
static NSString * const kBingLastSyncKey = @"bing_wallpaper_last_sync";
static NSString * const kBingDirName = @"BingWallpaper";
static NSString * const kBingMetadataFile = @"metadata.plist";

static NSTimeInterval kBingMinRefreshInterval = 4.0 * 3600.0; // 4h 内不重复拉元数据
static NSTimeInterval kBingRequestTimeout = 12.0;

@interface BingWallpaperItem ()
@property (nonatomic, copy) NSString *startdate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *copyright;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, copy) NSString *uhdImageURL;
@property (nonatomic, copy) NSString *thumbImageURL;
@end

@implementation BingWallpaperItem
@end

@interface BingWallpaperManager ()
@property (nonatomic, copy) NSArray<BingWallpaperItem *> *items;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbCache;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, assign) BOOL refreshInFlight;
@end

@implementation BingWallpaperManager

+ (instancetype)sharedManager {
    static BingWallpaperManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _thumbCache = [[NSCache alloc] init];
        _thumbCache.totalCostLimit = 32 * 1024 * 1024;
        _ioQueue = dispatch_queue_create("com.air.bingwallpaper.io", DISPATCH_QUEUE_SERIAL);
        [self ame_loadMetadataFromDisk];

        // Task151：回前台也触发一次自动刷新（长驻进程跨天补今日图）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(autoRefreshAndApplyIfEnabled)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(purgeMemoryCache)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Enabled Switch（默认开启）

- (BOOL)isEnabled {
    // 默认开启：从未写入过该键时视为 YES（registerDefaults 之外的显式默认，
    // 与 loadUISettings 的"越界即默认"同思路，避免依赖 registerDefaults 时序）
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kBingEnabledKey];
    if (raw == nil) return YES;
    return [raw boolValue];
}

- (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kBingEnabledKey];
    [defaults synchronize];
}

- (nullable NSDate *)lastSyncDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kBingLastSyncKey];
}

#pragma mark - Cache Paths

- (NSString *)bingDirectory {
    NSString *supportDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [supportDir stringByAppendingPathComponent:kBingDirName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

- (NSString *)imagePathForStartdate:(NSString *)startdate {
    return [[self bingDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", startdate]];
}

- (NSString *)thumbPathForStartdate:(NSString *)startdate {
    return [[self bingDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_thumb.jpg", startdate]];
}

#pragma mark - Metadata Persistence

- (void)ame_loadMetadataFromDisk {
    NSString *path = [[self bingDirectory] stringByAppendingPathComponent:kBingMetadataFile];
    __block NSArray *raw = nil; // CI 修正：dispatch_sync 块内赋值需 __block
    dispatch_sync(self.ioQueue, ^{
        raw = [NSArray arrayWithContentsOfFile:path];
    });
    if (![raw isKindOfClass:[NSArray class]] || raw.count == 0) return;

    NSMutableArray<BingWallpaperItem *> *items = [NSMutableArray array];
    for (NSDictionary *dict in raw) {
        if (![dict isKindOfClass:[NSDictionary class]]) continue;
        NSString *startdate = dict[@"startdate"];
        NSString *url = dict[@"imageURL"];
        if (startdate.length == 0 || url.length == 0) continue;
        BingWallpaperItem *item = [[BingWallpaperItem alloc] init];
        item.startdate = startdate;
        item.title = dict[@"title"] ?: @"";
        item.copyright = dict[@"copyright"] ?: @"";
        item.imageURL = url;
        item.uhdImageURL = dict[@"uhdImageURL"] ?: @"";
        item.thumbImageURL = dict[@"thumbImageURL"] ?: @"";
        [items addObject:item];
    }
    if (items.count > 0) self.items = [items copy];
}

- (void)ame_writeMetadataToDisk {
    NSString *path = [[self bingDirectory] stringByAppendingPathComponent:kBingMetadataFile];
    NSMutableArray *raw = [NSMutableArray array];
    for (BingWallpaperItem *item in self.items) {
        [raw addObject:@{
            @"startdate": item.startdate ?: @"",
            @"title": item.title ?: @"",
            @"copyright": item.copyright ?: @"",
            @"imageURL": item.imageURL ?: @"",
            @"uhdImageURL": item.uhdImageURL ?: @"",
            @"thumbImageURL": item.thumbImageURL ?: @""
        }];
    }
    dispatch_async(self.ioQueue, ^{
        [raw writeToFile:path atomically:YES];
    });
}

#pragma mark - Refresh（双源兜底）

- (void)refreshWithCompletion:(void (^)(BOOL, NSError *_Nullable))completion {
    if (self.refreshInFlight) {
        if (completion) completion(NO, [NSError errorWithDomain:@"BingWallpaper" code:101
                                                       userInfo:@{NSLocalizedDescriptionKey: @"refresh already in flight"}]);
        return;
    }
    self.refreshInFlight = YES;

    // cn.bing.com 主源（大陆直连），www.bing.com 备源（海外/主源异常）
    // CI 修正：自递归 block 会强捕获自身（-Warc-retain-cycles），改为实例方法递归
    NSMutableArray<NSString *> *hostList = [@[@"https://cn.bing.com", @"https://www.bing.com"] mutableCopy];
    NSString *apiPath = @"/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN";

    __weak typeof(self) weakSelf = self;
    [self ame_fetchWithHosts:hostList apiPath:apiPath lastError:nil completion:^(BOOL ok, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.refreshInFlight = NO;
            if (ok) {
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:[NSDate date] forKey:kBingLastSyncKey];
                [defaults synchronize];
            }
        }
        if (completion) completion(ok, error);
    }];
}

/// 双源兜底递归（实例方法形态；completion 恒主线程回调）
- (void)ame_fetchWithHosts:(NSMutableArray<NSString *> *)hosts
                   apiPath:(NSString *)apiPath
                 lastError:(nullable NSError *)lastError
                completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
    if (hosts.count == 0) {
        completion(NO, lastError ?: [NSError errorWithDomain:@"BingWallpaper" code:102
                                                    userInfo:@{NSLocalizedDescriptionKey: localize(@"bing.refresh.failed", nil)}]);
        return;
    }
    NSString *host = [hosts firstObject];
    [hosts removeObjectAtIndex:0];

    NSURL *url = [NSURL URLWithString:[host stringByAppendingString:apiPath]];
    if (!url) {
        [self ame_fetchWithHosts:hosts apiPath:apiPath lastError:lastError completion:completion];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = kBingRequestTimeout;
    request.HTTPMethod = @"GET";
    [request setValue:@"Mozilla/5.0 (iOS) AmethystLauncher/6.0" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || status != 200 || data.length == 0) {
                NSLog(@"[BingWallpaper] Task151 fetch failed host=%@ status=%ld error=%@", host, (long)status, error);
                NSError *httpError = error ?: [NSError errorWithDomain:@"BingWallpaper" code:status
                                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)status]}];
                [self ame_fetchWithHosts:hosts apiPath:apiPath lastError:httpError completion:completion];
                return;
            }

            BOOL ok = [self ame_parseMetadataData:data host:host];
            if (ok) {
                completion(YES, nil);
            } else {
                [self ame_fetchWithHosts:hosts apiPath:apiPath
                               lastError:[NSError errorWithDomain:@"BingWallpaper" code:103
                                                          userInfo:@{NSLocalizedDescriptionKey: @"invalid payload"}]
                              completion:completion];
            }
        });
    }];
    [task resume];
}

/// 解析 HPImageArchive JSON（images[]），成功则更新 items + 写盘 + 发通知
- (BOOL)ame_parseMetadataData:(NSData *)data host:(NSString *)host {
    NSError *jsonError = nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[BingWallpaper] Task151 invalid JSON: %@", jsonError);
        return NO;
    }
    NSArray *images = payload[@"images"];
    if (![images isKindOfClass:[NSArray class]] || images.count == 0) return NO;

    NSMutableArray<BingWallpaperItem *> *items = [NSMutableArray array];
    for (NSDictionary *entry in images) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *startdate = entry[@"startdate"];
        NSString *url = entry[@"url"];
        if (startdate.length == 0 || url.length == 0) continue;

        // 绝对化：接口返回 "/th?id=OHR.xxx_1920x1080.jpg&rf=..." 相对路径
        NSString *absoluteURL;
        if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
            absoluteURL = url;
        } else {
            absoluteURL = [host stringByAppendingString:url];
        }
        if (absoluteURL.length == 0) continue;

        BingWallpaperItem *item = [[BingWallpaperItem alloc] init];
        item.startdate = startdate;
        item.title = entry[@"title"] ?: @"";
        item.copyright = entry[@"copyright"] ?: @"";
        item.imageURL = absoluteURL;

        // UHD 变体：1920x1080 → UHD（th?id=OHR.xxx_UHD.jpg）；可能 404，下载层负责回退
        NSString *uhd = [absoluteURL stringByReplacingOccurrencesOfString:@"_1920x1080" withString:@"_UHD"];
        item.uhdImageURL = [uhd isEqualToString:absoluteURL] ? @"" : uhd;

        // 缩略图：th 服务附加 w 参数（服务不支持时原样返回大图，零失败模式）
        item.thumbImageURL = [absoluteURL stringByAppendingFormat:@"&w=%ld", (long)640];

        [items addObject:item];
    }

    if (items.count == 0) return NO;

    self.items = [items copy];
    [self ame_writeMetadataToDisk];
    NSLog(@"[BingWallpaper] Task151 metadata synced: %lu items (host=%@, today=%@)",
          (unsigned long)items.count, host, ((BingWallpaperItem *)items.firstObject).startdate);

    [[NSNotificationCenter defaultCenter] postNotificationName:BingWallpaperDidUpdateNotification object:self];
    return YES;
}

#pragma mark - Auto Refresh & Apply（默认开启主链路）

- (void)autoRefreshAndApplyIfEnabled {
    if (!self.isEnabled) return;

    // 用户自定义壁纸优先：来源非 bing 且已有背景 → 让位
    BackgroundManager *bg = [BackgroundManager sharedManager];
    if ([bg hasBackground] && ![bg isBingSource]) return;

    BOOL needFetch = YES;
    NSDate *last = [self lastSyncDate];
    NSString *today = [self ame_todayString];
    if (last && -[last timeIntervalSinceNow] < kBingMinRefreshInterval && self.items.count > 0) {
        for (BingWallpaperItem *item in self.items) {
            if ([item.startdate isEqualToString:today]) {
                needFetch = NO;
                break;
            }
        }
    }

    if (needFetch) {
        __weak typeof(self) weakSelf = self;
        [self refreshWithCompletion:^(BOOL success, NSError *_Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf ame_applyTodayIfPermitted];
        }];
    } else {
        [self ame_applyTodayIfPermitted];
    }
}

/// 应用今日图（含全部守卫：开关/用户优先/同图跳过；离线时走磁盘缓存）
- (void)ame_applyTodayIfPermitted {
    if (!self.isEnabled) return;

    BackgroundManager *bg = [BackgroundManager sharedManager];
    if ([bg hasBackground] && ![bg isBingSource]) return; // 刷新期间用户设了自定义壁纸

    BingWallpaperItem *today = self.items.firstObject;
    if (!today) return; // 首启离线且无缓存：无图可设，等下次联网

    __weak typeof(self) weakSelf = self;
    [self ensureImageForItem:today completion:^(NSString *_Nullable path, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !path) return;
        if (!strongSelf.isEnabled) return;

        BackgroundManager *bgManager = [BackgroundManager sharedManager];
        if ([bgManager hasBackground] && ![bgManager isBingSource]) return; // 双检
        if ([bgManager hasBackground] && [bgManager.currentBackgroundPath isEqualToString:path]) {
            return; // 已是今日图，避免每日无谓重建闪烁
        }
        [bgManager setBingBackgroundImageAtPath:path completion:^(BOOL ok, NSError *_Nullable err) {
            NSLog(@"[BingWallpaper] Task151 auto-apply %@ (%@)", ok ? @"OK" : @"FAILED", path.lastPathComponent);
        }];
    }];
}

- (NSString *)ame_todayString {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd";
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - Image Download & Cache

- (void)ensureImageForItem:(BingWallpaperItem *)item
                completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion {
    if (!item || item.startdate.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"BingWallpaper" code:201
                                                        userInfo:@{NSLocalizedDescriptionKey: localize(@"bing.apply.failed", nil)}]);
        return;
    }

    NSString *targetPath = [self imagePathForStartdate:item.startdate];
    dispatch_async(self.ioQueue, ^{
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:targetPath];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exists) {
                if (completion) completion(targetPath, nil);
                return;
            }
            [self ame_downloadImageForItem:item targetPath:targetPath completion:completion];
        });
    });
}

/// UHD 优先下载，失败回退 1920x1080 原图
- (void)ame_downloadImageForItem:(BingWallpaperItem *)item
                      targetPath:(NSString *)targetPath
                      completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion {
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    if (item.uhdImageURL.length > 0) [urls addObject:item.uhdImageURL];
    if (item.imageURL.length > 0) [urls addObject:item.imageURL];
    if (urls.count == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"BingWallpaper" code:202
                                                        userInfo:@{NSLocalizedDescriptionKey: localize(@"bing.apply.failed", nil)}]);
        return;
    }

    // CI 修正：自递归 block 强捕获自身（-Warc-retain-cycles），改为实例方法递归
    [self ame_attemptDownloadURLs:urls index:0 targetPath:targetPath completion:completion];
}

/// 变体逐个尝试递归（UHD 失败回退原图；completion 恒主线程回调）
- (void)ame_attemptDownloadURLs:(NSArray<NSString *> *)urls
                          index:(NSUInteger)index
                     targetPath:(NSString *)targetPath
                     completion:(void (^)(NSString *_Nullable path, NSError *_Nullable error))completion {
    if (index >= urls.count) {
        NSLog(@"[BingWallpaper] Task151 all variants failed for %@", targetPath.lastPathComponent);
        if (completion) completion(nil, [NSError errorWithDomain:@"BingWallpaper" code:203
                                                        userInfo:@{NSLocalizedDescriptionKey: localize(@"bing.apply.failed", nil)}]);
        return;
    }
    NSURL *url = [NSURL URLWithString:urls[index]];
    if (!url) {
        [self ame_attemptDownloadURLs:urls index:index + 1 targetPath:targetPath completion:completion];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = kBingRequestTimeout;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        BOOL ok = (!error && status == 200 && data.length > 4096); // >4KB 防截断占位
        if (!ok) {
            NSLog(@"[BingWallpaper] Task151 image download failed url=%@ status=%ld error=%@ (fallback next)",
                  url.absoluteString, (long)status, error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self ame_attemptDownloadURLs:urls index:index + 1 targetPath:targetPath completion:completion];
            });
            return;
        }
        dispatch_async(self.ioQueue, ^{
            BOOL written = [data writeToFile:targetPath atomically:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (written) {
                    NSLog(@"[BingWallpaper] Task151 image saved %@ (%lu KB)", targetPath.lastPathComponent, (unsigned long)(data.length / 1024));
                    if (completion) completion(targetPath, nil);
                } else {
                    if (completion) completion(nil, [NSError errorWithDomain:@"BingWallpaper" code:204
                                                                    userInfo:@{NSLocalizedDescriptionKey: localize(@"bing.apply.failed", nil)}]);
                }
            });
        });
    }];
    [task resume];
}

#pragma mark - Thumbnails

- (void)thumbnailForItem:(BingWallpaperItem *)item
              completion:(void (^)(UIImage *_Nullable image))completion {
    if (!item || item.startdate.length == 0) {
        if (completion) completion(nil);
        return;
    }

    UIImage *mem = [self.thumbCache objectForKey:item.startdate];
    if (mem) {
        if (completion) completion(mem);
        return;
    }

    NSString *thumbPath = [self thumbPathForStartdate:item.startdate];
    dispatch_async(self.ioQueue, ^{
        UIImage *disk = [UIImage imageWithContentsOfFile:thumbPath];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (disk) {
                [self.thumbCache setObject:disk forKey:item.startdate cost:(int)(disk.size.width * disk.size.height * 4)];
                if (completion) completion(disk);
                return;
            }

            // 磁盘未命中：优先直接下采样全尺寸缓存图（若已下载过），否则网络拉缩略图
            NSString *fullPath = [self imagePathForStartdate:item.startdate];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
                UIImage *full = [UIImage imageWithContentsOfFile:fullPath];
                UIImage *scaled = full ? [self ame_downsampleImage:full toMaxPixel:640.0] : nil;
                if (scaled) {
                    NSData *jpeg = UIImageJPEGRepresentation(scaled, 0.8);
                    if (jpeg) [jpeg writeToFile:thumbPath atomically:YES];
                }
                [self.thumbCache setObject:(scaled ?: full) forKey:item.startdate cost:(int)(full.size.width * full.size.height * 4)];
                if (completion) completion(scaled ?: full);
                return;
            }

            NSURL *url = item.thumbImageURL.length > 0 ? [NSURL URLWithString:item.thumbImageURL] : nil;
            if (!url) {
                if (completion) completion(nil);
                return;
            }
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            request.timeoutInterval = kBingRequestTimeout;
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSInteger status = [(NSHTTPURLResponse *)response statusCode];
                UIImage *image = (!error && status == 200 && data.length > 0) ? [UIImage imageWithData:data] : nil;
                if (image) {
                    NSData *jpeg = UIImageJPEGRepresentation(image, 0.8);
                    if (jpeg) [jpeg writeToFile:thumbPath atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.thumbCache setObject:image forKey:item.startdate cost:(int)(image.size.width * image.size.height * 4)];
                        if (completion) completion(image);
                    });
                } else {
                    NSLog(@"[BingWallpaper] Task151 thumb failed %@ status=%ld error=%@", item.startdate, (long)status, error);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(nil);
                    });
                }
            }];
            [task resume];
        });
    });
}

- (nullable UIImage *)cachedThumbnailForItem:(BingWallpaperItem *)item {
    if (!item) return nil;
    return [self.thumbCache objectForKey:item.startdate];
}

- (void)purgeMemoryCache {
    [self.thumbCache removeAllObjects];
}

- (UIImage *)ame_downsampleImage:(UIImage *)image toMaxPixel:(CGFloat)maxPixel {
    CGSize size = image.size;
    CGFloat scale = MAX(size.width, size.height) / maxPixel;
    if (scale <= 1.0) return image;
    CGSize target = CGSizeMake(floor(size.width / scale), floor(size.height / scale));

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull ctx) {
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

@end
