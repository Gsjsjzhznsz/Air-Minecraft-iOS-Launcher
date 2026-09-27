#import "NeoForgeVersionFetcher.h"
#import "PLMirrorCenter.h"
#import "utils.h"

@implementation NeoForgeVersionFetcher

#pragma mark - Public

+ (void)fetchVersionsForGameVersion:(NSString *)gameVersion
                         completion:(void (^)(NSArray *versions, NSError *error))completion {
    if (!completion) return;
    if (!gameVersion || gameVersion.length == 0) {
        completion(@[], [NSError errorWithDomain:@"NeoForge" code:1 userInfo:@{NSLocalizedDescriptionKey:@"No game version"}]);
        return;
    }

    // 源选择统一走 PLMirrorCenter（ModLoader 类型策略 download.modLoaderSource，
    // 未设置时由 PLMirrorCenter 回退旧键 general.download_source）
    BOOL preferBMCLAPI = [PLMirrorCenter policyForType:PLMirrorResourceTypeModLoader] == PLMirrorPolicyMirrorFirst;

    void (^finish)(NSArray *, NSError *) = ^(NSArray *versions, NSError *error) {
        NSArray *filtered = [self filterVersions:versions gameVersion:gameVersion];
        if (filtered.count > 0) {
            completion(filtered, nil);
        } else if (error) {
            completion(@[], error);
        } else {
            completion(@[], [NSError errorWithDomain:@"NeoForge" code:2 userInfo:@{NSLocalizedDescriptionKey:@"No matching NeoForge versions"}]);
        }
    };

    // Try preferred source first, then fallback.
    [self fetchAllVersionsUseBMCLAPI:preferBMCLAPI completion:^(NSArray *versions, NSError *error) {
        if (versions.count > 0) {
            finish(versions, nil);
        } else {
            NSLog(@"[NeoForge] Primary source (%@) returned no versions, falling back to %@",
                  preferBMCLAPI ? @"BMCLAPI" : @"official",
                  preferBMCLAPI ? @"official" : @"BMCLAPI");
            [self fetchAllVersionsUseBMCLAPI:!preferBMCLAPI completion:^(NSArray *fallbackVersions, NSError *fallbackError) {
                if (fallbackVersions.count > 0) {
                    finish(fallbackVersions, nil);
                } else {
                    finish(@[], fallbackError ?: error);
                }
            }];
        }
    }];
}

+ (NSString *)installerURLForVersion:(NSString *)version {
    if (!version || version.length == 0) return nil;
    // 官方 URL 构造后统一经 PLMirrorCenter（ModLoader 类型）取当前策略首选 URL：
    // mirror_first → BMCLAPI /maven（PLMirrorCenter 会吸收官方路径中的 /releases 段），
    // official_first → 官方 maven 原样返回
    NSString *officialURL;
    // Legacy 1.20.1 versions use the old forge coordinates.
    if ([version containsString:@"1.20.1"] || [version hasPrefix:@"47."]) {
        // 官方 maven 路径必须包含 /releases/，否则 404
        officialURL = [NSString stringWithFormat:@"https://maven.neoforged.net/releases/net/neoforged/forge/%@/forge-%@-installer.jar", version, version];
    } else {
        // 官方 maven 路径必须包含 /releases/，否则 404
        officialURL = [NSString stringWithFormat:@"https://maven.neoforged.net/releases/net/neoforged/neoforge/%@/neoforge-%@-installer.jar", version, version];
    }
    return [[PLMirrorCenter preferredURLForOriginalURL:[NSURL URLWithString:officialURL]
                                          resourceType:PLMirrorResourceTypeModLoader] absoluteString];
}

#pragma mark - Internal

+ (void)fetchAllVersionsUseBMCLAPI:(BOOL)useBMCLAPI
                        completion:(void (^)(NSArray *versions, NSError *error))completion {
    NSString *officialNeoURL = @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge";
    NSString *officialLegacyURL = @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/forge";
    NSString *bmclNeoURL = @"https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/neoforge";
    NSString *bmclLegacyURL = @"https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/forge";

    NSMutableArray *allVersions = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    __block NSError *lastError = nil;

    dispatch_group_enter(group);
    if (useBMCLAPI) {
        [self fetchBMCLAPIVersions:bmclNeoURL completion:^(NSArray *versions, NSError *error) {
            if (versions.count > 0) { @synchronized (allVersions) { [allVersions addObjectsFromArray:versions]; } }
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    } else {
        [self fetchOfficialVersions:officialNeoURL completion:^(NSArray *versions, NSError *error) {
            if (versions.count > 0) { @synchronized (allVersions) { [allVersions addObjectsFromArray:versions]; } }
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_enter(group);
    if (useBMCLAPI) {
        [self fetchBMCLAPIVersions:bmclLegacyURL completion:^(NSArray *versions, NSError *error) {
            if (versions.count > 0) { @synchronized (allVersions) { [allVersions addObjectsFromArray:versions]; } }
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    } else {
        [self fetchOfficialVersions:officialLegacyURL completion:^(NSArray *versions, NSError *error) {
            if (versions.count > 0) { @synchronized (allVersions) { [allVersions addObjectsFromArray:versions]; } }
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (completion) completion(allVersions, lastError);
    });
}

+ (void)fetchOfficialVersions:(NSString *)urlString
                   completion:(void (^)(NSArray *versions, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[NeoForge] Official fetch failed: %@", error.localizedDescription ?: @"no data");
            if (completion) completion(@[], error ?: [NSError errorWithDomain:@"NeoForge" code:3 userInfo:@{NSLocalizedDescriptionKey:@"No data"}]);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSArray *versions = json[@"versions"];
            if ([versions isKindOfClass:[NSArray class]]) {
                if (completion) completion(versions, nil);
                return;
            }
        }
        if (completion) completion(@[], [NSError errorWithDomain:@"NeoForge" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Invalid JSON"}]);
    }];
    [task resume];
}

+ (void)fetchBMCLAPIVersions:(NSString *)urlString
                  completion:(void (^)(NSArray *versions, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[NeoForge] BMCLAPI fetch failed: %@", error.localizedDescription ?: @"no data");
            if (completion) completion(@[], error ?: [NSError errorWithDomain:@"NeoForge" code:3 userInfo:@{NSLocalizedDescriptionKey:@"No data"}]);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSArray *files = json[@"files"];
            if ([files isKindOfClass:[NSArray class]]) {
                NSMutableArray *versions = [NSMutableArray array];
                for (id obj in files) {
                    if (![obj isKindOfClass:[NSDictionary class]]) continue;
                    NSDictionary *file = obj;
                    NSString *type = file[@"type"];
                    NSString *name = file[@"name"];
                    if ([type isEqualToString:@"DIRECTORY"] && name && ![name.lowercaseString containsString:@"maven"]) {
                        [versions addObject:name];
                    }
                }
                if (completion) completion(versions, nil);
                return;
            }
        }
        if (completion) completion(@[], [NSError errorWithDomain:@"NeoForge" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Invalid BMCLAPI JSON"}]);
    }];
    [task resume];
}

+ (NSArray *)filterVersions:(NSArray *)versions gameVersion:(NSString *)gameVersion {
    // Task185：改用 ame185_loaderVersionMatchesGameVersion 等价匹配。
    // 病历（11e4b63 装机反馈）：MC 26.x 起版本号无 "1." 前缀（26.3、26.1.2），
    // 旧提取器把 NeoForge 26.3.x 解析成 MC "1.26.3" → 与 gameVersion "26.3"
    // 永不相等 → 列表全空 = "大于 26 的版本 NeoForge 找不到"。
    // 新匹配器双向候选集等价判定，覆盖新旧两个纪元 + legacy/快照特殊形态。
    NSMutableArray *filtered = [NSMutableArray array];
    for (id obj in versions) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *version = obj;
        if (ame185_loaderVersionMatchesGameVersion(version, gameVersion)) {
            [filtered addObject:version];
        }
    }
    [filtered sortUsingComparator:^NSComparisonResult(NSString *v1, NSString *v2) {
        return [v2 compare:v1 options:NSNumericSearch];
    }];
    return filtered;
}

+ (NSString *)extractMinecraftVersionFromNeoForgeVersion:(NSString *)version {
    // 1.20.1 special versions: 1.20.1-47.1.3 -> 1.20.1
    // 同时覆盖 47.x.y 系列（1.20.1 NeoForge release 版本号，不含 "1.20.1" 子串）
    if ([version containsString:@"1.20.1"] || [version hasPrefix:@"47."]) {
        return @"1.20.1";
    }

    // 0.x special snapshots: 0.25w14craftmine.3 -> 25w14craftmine
    if ([version hasPrefix:@"0."]) {
        NSString *part = [version substringFromIndex:2];
        NSRange hyphenRange = [part rangeOfString:@"-"];
        if (hyphenRange.location != NSNotFound) {
            part = [part substringToIndex:hyphenRange.location];
        }
        NSRange lastDot = [part rangeOfString:@"." options:NSBackwardsSearch];
        if (lastDot.location != NSNotFound) {
            part = [part substringToIndex:lastDot.location];
        }
        return part;
    }

    NSString *cleanVersion = version;
    NSRange hyphenRange = [version rangeOfString:@"-"];
    if (hyphenRange.location != NSNotFound) {
        cleanVersion = [version substringToIndex:hyphenRange.location];
    }

    NSArray *components = [cleanVersion componentsSeparatedByString:@"."];
    if (components.count >= 2) {
        NSString *major = components[0];
        NSString *minor = components[1];

        NSCharacterSet *nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        BOOL majorIsNum = [major rangeOfCharacterFromSet:nonNumbers].location == NSNotFound;
        BOOL minorIsNum = [minor rangeOfCharacterFromSet:nonNumbers].location == NSNotFound;

        if (majorIsNum && minorIsNum) {
            NSInteger majorVal = [major integerValue];
            // 关键修复（阶段6：NeoForge 直装版本号解析错误，参照 ForgeInstallViewController.m:780）
            //
            // NeoForge loader 版本号格式：major.minor.patch[.build]
            //   - major = MC minor（如 21 → MC 1.21）
            //   - minor = MC patch（如 1 → MC 1.21.1）
            //   - patch = NeoForge 自己的 build 号（与 MC 版本无关）
            //
            // 之前使用 components[2]（patch）作为 MC patch 号，导致：
            //   - 21.1.5 被解析为 MC 1.21.5（错误，应为 1.21.1）
            //   - 26.1.0.0 被解析为 MC 1.26.0（凑巧正确，但逻辑错误）
            //   - 用户在 UI 中看不到正确分组的 loader 版本，被迫选错 → install_profile.json
            //     中 maven 坐标版本错误 → 404
            //
            // 正确实现：用 minor（components[1]）作为 MC patch 号，与 ForgeInstallViewController.m:780 一致
            if (majorVal >= 20) {
                // 20.x+ (NeoForge 20.x 对应 MC 1.20.x)：统一用 minor 作为 MC patch
                // 覆盖 20.2.88 → 1.20.2、21.1.5 → 1.21.1、26.1.0 → 1.26.1 等所有情况
                return [NSString stringWithFormat:@"1.%@.%@", major, minor];
            } else {
                // Old format fallback（理论上 NeoForge 不存在 < 20 的版本）
                return [NSString stringWithFormat:@"1.%@.%@", major, minor];
            }
        }
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+\\.\\d+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (match) {
        return [NSString stringWithFormat:@"1.%@", [version substringWithRange:match.range]];
    }

    return @"Unknown";
}

@end
