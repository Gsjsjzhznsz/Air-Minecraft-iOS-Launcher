//
//  AnnouncementService.m
//  Amethyst
//

#import "AnnouncementService.h"
#import "AnnouncementItem.h"
#import "LauncherPreferences.h"

/// 缓存有效期：30 分钟
static NSTimeInterval const kAnnouncementCacheInterval = 30 * 60;

/// 缓存键
static NSString * const kCachedAnnouncementsKey = @"cached_announcements";
static NSString * const kCachedAnnouncementsTimestampKey = @"cached_announcements_timestamp";

@implementation AnnouncementService

+ (instancetype)sharedService {
    static AnnouncementService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AnnouncementService alloc] init];
    });
    return instance;
}

- (NSString *)apiURLString {
    // 从偏好设置读取 news_url，默认为官网 API 地址
    NSString *url = getPrefObject(@"general.news_url");
    if (url.length == 0) {
        url = @"https://amethyst.ct.ws/api/announcements.json";
    }
    return url;
}

- (NSArray<AnnouncementItem *> *)cachedAnnouncements {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kCachedAnnouncementsKey];
    if (!data) return nil;
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !json) return nil;
    return [self parseAnnouncementsFromJSON:json];
}

- (BOOL)isCacheValid {
    NSTimeInterval timestamp = [[NSUserDefaults standardUserDefaults] doubleForKey:kCachedAnnouncementsTimestampKey];
    if (timestamp == 0) return NO;
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - timestamp;
    return elapsed < kAnnouncementCacheInterval;
}

- (void)fetchAnnouncementsWithCompletion:(AnnouncementFetchHandler)completion {
    // 缓存有效时直接返回缓存
    if ([self isCacheValid]) {
        NSArray *cached = [self cachedAnnouncements];
        if (cached) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached, nil);
            });
            return;
        }
    }
    [self forceRefreshWithCompletion:completion];
}

- (void)forceRefreshWithCompletion:(AnnouncementFetchHandler)completion {
    NSString *urlString = [self apiURLString];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@[], [NSError errorWithDomain:@"AnnouncementService" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效的公告 URL"}]);
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"Air/1.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 15.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data || ((NSHTTPURLResponse *)response).statusCode != 200) {
            // 网络失败时尝试返回缓存
            NSArray *cached = [self cachedAnnouncements];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(cached ?: @[], error ?: [NSError errorWithDomain:@"AnnouncementService" code:2 userInfo:@{NSLocalizedDescriptionKey: @"公告拉取失败"}]);
            });
            return;
        }

        // 缓存原始 JSON 数据
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCachedAnnouncementsKey];
        [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:kCachedAnnouncementsTimestampKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        // 解析
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || !json) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], parseError ?: [NSError errorWithDomain:@"AnnouncementService" code:3 userInfo:@{NSLocalizedDescriptionKey: @"公告 JSON 解析失败"}]);
            });
            return;
        }

        NSArray *items = [self parseAnnouncementsFromJSON:json];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(items, nil);
        });
    }];
    [task resume];
}

- (NSArray<AnnouncementItem *> *)parseAnnouncementsFromJSON:(NSDictionary *)json {
    NSArray *rawArray = json[@"announcements"];
    if (![rawArray isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *dict in rawArray) {
        AnnouncementItem *item = [AnnouncementItem itemFromDictionary:dict];
        if (item) [items addObject:item];
    }
    // 按日期降序排列
    [items sortUsingComparator:^NSComparisonResult(AnnouncementItem *a, AnnouncementItem *b) {
        return [b.date compare:a.date];
    }];
    return [items copy];
}

@end
