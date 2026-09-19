#import "AFNetworking.h"
#import "ThirdPartyAuthenticator.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

// authlib-injector 下载源：BMCLAPI 镜像优先，失败后回退到官方源
// 修复：从 1.2.6 升级到 1.2.7（build 55），1.2.7 修复了 Java 25 兼容性问题。
// 说明：26.x 默认使用 Java 21 启动（Mojang 元数据 javaVersion.majorVersion=21），
// 但若用户在 PLProfiles 中为 26.x 显式设置 javaVersion=25，则 26.x 会使用 Java 25，
// 此时 authlib-injector 1.2.6 的 ASM 字节码处理无法识别 Java 25 class file version 69，
// 导致 javaagent 加载失败、游戏无法启动。升级到 1.2.7 后同时兼容 Java 17/21/25。
// 另：authlib-injector 1.2.7 对 Java 25 的支持也用于 execute_jar 路径
// （如某些 Mod 安装器 JAR 编译目标为 Java 25）。
#define AUTHLIB_INJECTOR_URL_BMCL  @"https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/55/authlib-injector-1.2.7.jar"
#define AUTHLIB_INJECTOR_URL_GITHUB @"https://authlib-injector.yushi.moe/artifact/55/authlib-injector-1.2.7.jar"
#define AUTHLIB_INJECTOR_FILE @"authlib-injector.jar"
#define AUTHLIB_INJECTOR_VERSION @"1.2.7"
#define AUTHLIB_INJECTOR_VERSION_FILE @"authlib-injector.version"

// Helper function to create NSError
static NSError* createError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"ThirdPartyAuthenticator" 
                            code:code 
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ThirdPartyAuthenticator

+ (void)resolveAuthserverURL:(NSString *)inputURL
                  completion:(void (^)(NSString *resolvedURL, NSString *_Nullable metadata))completion {
    if (inputURL.length == 0) {
        if (completion) completion(inputURL, nil);
        return;
    }

    // 1. 缺协议时补 HTTPS（规范要求不允许降级到 HTTP）
    NSString *urlStr = inputURL;
    if (![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"]) {
        urlStr = [@"https://" stringByAppendingString:urlStr];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url || !url.scheme || !url.host) {
        // URL 非法，回退返回原始输入
        if (completion) completion(inputURL, nil);
        return;
    }

    // 2. GET 请求该 URL，检查 X-Authlib-Injector-API-Location 响应头
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15;
    config.timeoutIntervalForResource = 30;
    // 允许跟随重定向（GitHub releases 等 302 跳转）
    config.HTTPShouldUsePipelining = YES;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    // 不缓存，避免 ALI 头被缓存层吞掉
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    __block NSString *resolvedURL = urlStr;
    __block NSString *metadata = nil;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"[ThirdPartyAuthenticator] ALI resolution failed: %@", error.localizedDescription);
                // 解析失败回退到原始 URL，登录仍可尝试
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(inputURL, nil);
                });
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if ([httpResponse isKindOfClass:[NSHTTPURLResponse class]]) {
                // 3. 检查 ALI 头
                NSString *ali = httpResponse.allHeaderFields[@"X-Authlib-Injector-API-Location"];
                if (ali.length > 0) {
                    // 解析 ALI 为绝对 URL
                    NSURL *aliURL = [NSURL URLWithString:ali relativeToURL:httpResponse.URL];
                    if (aliURL) {
                        // 如果 ALI 不指向自身，更新 resolvedURL
                        NSString *aliStr = aliURL.absoluteString;
                        if (![aliStr isEqualToString:httpResponse.URL.absoluteString]) {
                            NSLog(@"[ThirdPartyAuthenticator] ALI redirect: %@ -> %@", urlStr, aliStr);
                            resolvedURL = aliStr;
                            // ALI 指向新地址，需要重新请求获取元数据
                            [self fetchMetadataFromURL:aliURL completion:completion originalInput:inputURL];
                            return;
                        }
                    }
                }
            }

            // 4. 无 ALI 头或 ALI 指向自身：当前 URL 即为 API Root，复用响应体作为元数据
            if (data.length > 0) {
                metadata = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // 校验是否为合法 JSON（元数据必须是 JSON）
                if (metadata) {
                    NSData *check = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:kNilOptions
                                                                     error:nil] ? data : nil;
                    if (!check) {
                        NSLog(@"[ThirdPartyAuthenticator] Response body is not valid JSON, discarding metadata");
                        metadata = nil;
                    }
                }
            }

            // 规范化：确保末尾带斜杠（与 buildAuthURLForServer 的处理一致）
            if (![resolvedURL hasSuffix:@"/"]) {
                resolvedURL = [resolvedURL stringByAppendingString:@"/"];
            }

            NSLog(@"[ThirdPartyAuthenticator] ALI resolution complete: %@ (metadata=%@)", resolvedURL, metadata ? @"YES" : @"NO");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(resolvedURL, metadata);
            });
        }];
    [task resume];
}

/// 辅助方法：从指定 URL 获取服务器元数据（ALI 重定向后的二次请求）
+ (void)fetchMetadataFromURL:(NSURL *)url
                  completion:(void (^)(NSString *, NSString *_Nullable))completion
               originalInput:(NSString *)originalInput {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSString *resolvedURL = url.absoluteString;
            NSString *metadata = nil;

            if (error) {
                NSLog(@"[ThirdPartyAuthenticator] Metadata secondary request failed: %@", error.localizedDescription);
            } else if (data.length > 0) {
                metadata = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // 校验 JSON 合法性
                if (![NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil]) {
                    NSLog(@"[ThirdPartyAuthenticator] Secondary response body is not valid JSON, discarding metadata");
                    metadata = nil;
                }
            }

            if (![resolvedURL hasSuffix:@"/"]) {
                resolvedURL = [resolvedURL stringByAppendingString:@"/"];
            }

            NSLog(@"[ThirdPartyAuthenticator] Metadata secondary request complete: %@ (metadata=%@)", resolvedURL, metadata ? @"YES" : @"NO");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(resolvedURL, metadata);
            });
        }];
    [task resume];
}

- (NSString *)getAuthlibInjectorPath {
    NSString *path = [NSString stringWithFormat:@"%s/authlib-injector/%@", getenv("POJAV_HOME"), AUTHLIB_INJECTOR_FILE];
    return path;
}

// Task 128（zl2 同款思路）：随包内置的 authlib-injector 兜底路径。
// 旧实现把 jar 的在线下载作为登录前置（ensureAuthlibInjectorWithCompletion
// 是 loginWithCallback 第一步），下载失败 = 第三方登录完全不可用。
// 现在应用包内常备同版本 jar（Natives/resources/authlib-injector-1.2.7.jar，
// 由 payload 随包拷入），POJAV_HOME 侧缺文件/版本不匹配时直接从包内复制
// （本地操作，零网络依赖），在线下载仅作为包内文件缺失的最后回退。
- (NSString *)bundledAuthlibInjectorPath {
    return [NSBundle.mainBundle pathForResource:@"authlib-injector-" AUTHLIB_INJECTOR_VERSION
                                         ofType:@"jar"];
}

- (NSString *)getAuthlibInjectorVersionPath {
    NSString *path = [NSString stringWithFormat:@"%s/authlib-injector/%@", getenv("POJAV_HOME"), AUTHLIB_INJECTOR_VERSION_FILE];
    return path;
}

- (BOOL)isAuthlibInjectorDownloaded {
    NSString *path = [self getAuthlibInjectorPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    // 版本检查：已下载的 jar 版本必须与当前期望版本一致
    // 修复：旧版 1.2.6 jar 与 Java 25 不兼容，必须升级到 1.2.7
    NSString *versionPath = [self getAuthlibInjectorVersionPath];
    NSString *downloadedVersion = [NSString stringWithContentsOfFile:versionPath encoding:NSUTF8StringEncoding error:nil];
    if (downloadedVersion.length == 0 || ![downloadedVersion isEqualToString:AUTHLIB_INJECTOR_VERSION]) {
        NSLog(@"[ThirdPartyAuthenticator] authlib-injector version outdated (current: %@, required: %@), needs re-download",
              downloadedVersion.length > 0 ? downloadedVersion : @"unknown", AUTHLIB_INJECTOR_VERSION);
        return NO;
    }
    return YES;
}

/// 下载成功后保存版本标记
- (void)saveAuthlibInjectorVersion {
    NSString *versionPath = [self getAuthlibInjectorVersionPath];
    [AUTHLIB_INJECTOR_VERSION writeToFile:versionPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)downloadAuthlibInjector:(void (^)(BOOL success, NSError *error))completion {
    [self downloadAuthlibInjectorFromURL:AUTHLIB_INJECTOR_URL_BMCL attempt:1 completion:completion];
}

/// 逐个尝试下载源：BMCLAPI 失败后回退到 GitHub 官方源
- (void)downloadAuthlibInjectorFromURL:(NSString *)urlString
                               attempt:(NSInteger)attempt
                            completion:(void (^)(BOOL success, NSError *error))completion {
    NSString *dirPath = [NSString stringWithFormat:@"%s/authlib-injector", getenv("POJAV_HOME")];
    NSString *filePath = [self getAuthlibInjectorPath];

    // Create directory if it doesn't exist
    NSError *dirError;
    [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&dirError];
    if (dirError) {
        completion(NO, dirError);
        return;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 120;
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

    NSURL *URL = [NSURL URLWithString:urlString];
    // 使用 NSMutableURLRequest 以允许重定向跟随（GitHub releases 会 302 跳转）
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPShouldUsePipelining = YES;

    NSLog(@"[ThirdPartyAuthenticator] Attempting to download authlib-injector (source %ld): %@", (long)attempt, urlString);

    NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        return [NSURL fileURLWithPath:filePath];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        if (error) {
            NSLog(@"[ThirdPartyAuthenticator] Download failed (source %ld): %@", (long)attempt, error.localizedDescription);
            // BMCLAPI 失败后尝试 GitHub 官方源
            if (attempt == 1) {
                [self downloadAuthlibInjectorFromURL:AUTHLIB_INJECTOR_URL_GITHUB attempt:2 completion:completion];
            } else {
                completion(NO, error);
            }
        } else {
            NSLog(@"[ThirdPartyAuthenticator] Download succeeded (source %ld)", (long)attempt);
            // 保存版本标记，用于后续版本检查
            [self saveAuthlibInjectorVersion];
            completion(YES, nil);
        }
    }];
    [downloadTask resume];
}

- (void)ensureAuthlibInjectorWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    if ([self isAuthlibInjectorDownloaded]) {
        completion(YES, nil);
        return;
    }
    // Task 128（zl2 同款思路）：优先从应用包内复制（本地、即时、零网络依赖）。
    // 旧实现把 jar 的在线下载作为登录前置——下载失败 = 第三方登录完全不可用。
    // 包内常备同版本 jar（Natives/resources/authlib-injector-1.2.7.jar，
    // payload 随包拷入）；在线下载仅作为包内文件缺失的最后回退。
    NSString *ame128_bundled = [self bundledAuthlibInjectorPath];
    if (ame128_bundled.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:ame128_bundled]) {
        NSString *ame128_dir = [NSString stringWithFormat:@"%s/authlib-injector", getenv("POJAV_HOME")];
        NSString *ame128_dest = [self getAuthlibInjectorPath];
        NSError *ame128_copyErr = nil;
        [NSFileManager.defaultManager createDirectoryAtPath:ame128_dir
                                withIntermediateDirectories:YES attributes:nil error:nil];
        // 目标已存在（版本不匹配的旧 jar）时先移除再复制
        if ([NSFileManager.defaultManager fileExistsAtPath:ame128_dest]) {
            [NSFileManager.defaultManager removeItemAtPath:ame128_dest error:nil];
        }
        if ([NSFileManager.defaultManager copyItemAtPath:ame128_bundled toPath:ame128_dest error:&ame128_copyErr]) {
            NSLog(@"[ThirdPartyAuthenticator] Task128: authlib-injector installed from bundled copy");
            [self saveAuthlibInjectorVersion];
            completion(YES, nil);
            return;
        }
        NSLog(@"[ThirdPartyAuthenticator] Task128: bundled copy failed (%@), falling back to network", ame128_copyErr.localizedDescription);
    }
    {
        NSLog(@"[ThirdPartyAuthenticator] Downloading authlib-injector (BMCLAPI preferred, falls back to GitHub)");
        [self downloadAuthlibInjector:^(BOOL success, NSError *error) {
            if (!success) {
                NSLog(@"[ThirdPartyAuthenticator] Failed to download authlib-injector: %@", error.localizedDescription);
                
                // Create a more informative error message
                NSString *errorMessage = [NSString stringWithFormat:@"Failed to download authlib-injector for third party authentication: %@", error.localizedDescription];
                NSError *customError = [NSError errorWithDomain:@"ThirdPartyAuthenticator" 
                                                          code:1001 
                                                      userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
                
                completion(NO, customError);
            } else {
                NSLog(@"[ThirdPartyAuthenticator] Successfully downloaded authlib-injector");
                completion(YES, nil);
            }
        }];
    }
}

// Method to get JVM arguments for authlib-injector
- (NSArray *)getJvmArgsForAuthlib {
    NSString *injectorPath = [self getAuthlibInjectorPath];

    // Check file existence（Task 128：POJAV_HOME 副本缺失时回退包内 jar——
    // 启动时 agent 永不因文件缺失而静默丢失，这正是 401 蜷缩链的断点之一）
    if (![[NSFileManager defaultManager] fileExistsAtPath:injectorPath]) {
        NSString *ame128_bundled = [self bundledAuthlibInjectorPath];
        if (ame128_bundled.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:ame128_bundled]) {
            injectorPath = ame128_bundled;
            NSLog(@"[ThirdPartyAuthenticator] Task128: using bundled authlib-injector at launch");
        } else {
            NSLog(@"[ThirdPartyAuthenticator] Warning: authlib-injector file not found at %@", injectorPath);
            return @[];
        }
    }

    // Get server URL from authData or use default Ely.by server
    NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";

    NSString *jvmArg = [NSString stringWithFormat:@"-javaagent:%@=%@", injectorPath, serverURL];

    NSMutableArray *args = [NSMutableArray arrayWithArray:@[jvmArg, @"-Dauthlibinjector.side=client"]];

    // 参照 HMCL AuthlibInjectorAuthInfo：传递 prefetched 元数据
    // 将服务器元数据 base64 编码后通过 -Dauthlibinjector.yggdrasil.prefetched 传入，
    // 避免游戏运行时再次请求服务器元数据，提升皮肤加载可靠性
    NSString *metadata = self.authData[@"prefetchedMetadata"];
    if (metadata.length > 0) {
        // 去除 JSON 多余空白（规范要求紧凑形式，减少参数长度）
        NSData *jsonData = [metadata dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonError = nil;
        id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:&jsonError];
        if (jsonObj && !jsonError) {
            NSData *compactData = [NSJSONSerialization dataWithJSONObject:jsonObj
                                                                  options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                                    error:nil];
            if (compactData) {
                NSString *compactStr = [[NSString alloc] initWithData:compactData encoding:NSUTF8StringEncoding];
                NSString *base64 = [[compactStr dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
                if (base64.length > 0) {
                    NSString *prefetchedArg = [NSString stringWithFormat:@"-Dauthlibinjector.yggdrasil.prefetched=%@", base64];
                    [args addObject:prefetchedArg];
                    NSLog(@"[ThirdPartyAuthenticator] Added prefetched metadata parameter (length=%lu)", (unsigned long)base64.length);
                }
            }
        } else {
            NSLog(@"[ThirdPartyAuthenticator] Prefetched metadata JSON parse failed, skipping parameter");
        }
    } else {
        // 登录时未缓存元数据，尝试现场获取（同步，可能阻塞，仅作兜底）
        NSLog(@"[ThirdPartyAuthenticator] No cached metadata, attempting on-the-fly fetch");
        [self fetchMetadataSynchronouslyForServerURL:serverURL];
        NSString *cachedMeta = self.authData[@"prefetchedMetadata"];
        if (cachedMeta.length > 0) {
            NSData *jsonData = [cachedMeta dataUsingEncoding:NSUTF8StringEncoding];
            id jsonObj = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil];
            if (jsonObj) {
                NSData *compactData = [NSJSONSerialization dataWithJSONObject:jsonObj
                                                                      options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                                        error:nil];
                if (compactData) {
                    NSString *compactStr = [[NSString alloc] initWithData:compactData encoding:NSUTF8StringEncoding];
                    NSString *base64 = [[compactStr dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
                    if (base64.length > 0) {
                        NSString *prefetchedArg = [NSString stringWithFormat:@"-Dauthlibinjector.yggdrasil.prefetched=%@", base64];
                        [args addObject:prefetchedArg];
                        NSLog(@"[ThirdPartyAuthenticator] Added on-the-fly fetched prefetched metadata parameter");
                    }
                }
            }
        }
    }

    return args;
}

/// 同步获取服务器元数据并缓存到 authData（getJvmArgsForAuthlib 兜底用）
- (void)fetchMetadataSynchronouslyForServerURL:(NSString *)serverURL {
    if (serverURL.length == 0) return;
    NSString *urlStr = serverURL;
    if (![urlStr hasSuffix:@"/"]) {
        urlStr = [urlStr stringByAppendingString:@"/"];
    }
    // 元数据在 API Root 直接 GET 获取
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10;

    NSError *requestError = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&requestError];
    if (requestError || !data || data.length == 0) {
        NSLog(@"[ThirdPartyAuthenticator] On-the-fly metadata fetch failed: %@", requestError.localizedDescription);
        return;
    }

    // 校验 JSON 合法性
    id jsonObj = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    if (!jsonObj) {
        NSLog(@"[ThirdPartyAuthenticator] On-the-fly fetched metadata is not valid JSON");
        return;
    }

    // 检查 ALI 头，若指向其他地址则需二次请求
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSString *ali = response.allHeaderFields[@"X-Authlib-Injector-API-Location"];
        if (ali.length > 0) {
            NSURL *aliURL = [NSURL URLWithString:ali relativeToURL:response.URL];
            if (aliURL && ![aliURL.absoluteString isEqualToString:response.URL.absoluteString]) {
                // ALI 指向其他地址，二次请求
                NSMutableURLRequest *aliRequest = [NSMutableURLRequest requestWithURL:aliURL];
                aliRequest.HTTPMethod = @"GET";
                aliRequest.timeoutInterval = 10;
                NSError *aliError = nil;
                NSData *aliData = [NSURLConnection sendSynchronousRequest:aliRequest
                                                       returningResponse:nil
                                                                   error:&aliError];
                if (!aliError && aliData.length > 0) {
                    if ([NSJSONSerialization JSONObjectWithData:aliData options:kNilOptions error:nil]) {
                        self.authData[@"prefetchedMetadata"] = [[NSString alloc] initWithData:aliData encoding:NSUTF8StringEncoding];
                        return;
                    }
                }
                return;
            }
        }
    }

    self.authData[@"prefetchedMetadata"] = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"[ThirdPartyAuthenticator] On-the-fly metadata fetch succeeded");
}

// Method to handle re-authentication with two-factor authentication
- (void)loginWithTwoFactorToken:(NSString *)token callback:(Callback)callback {
    NSString *username = self.authData[@"input"];
    NSString *password = self.authData[@"password"];
    
    if (username.length == 0 || password.length == 0) {
        NSError *error = createError(localize(@"login.error.fields.empty", nil), 1002);
        callback(error, NO);
        return;
    }
    
    // Add two-factor token to password
    NSString *passwordWithToken = [NSString stringWithFormat:@"%@:%@", password, token];
    
    NSDictionary *data = @{
        @"agent": @{@"name": @"Minecraft", @"version": @1},
        @"username": username,
        @"password": passwordWithToken,
        @"clientToken": [[NSUUID UUID] UUIDString],
        @"requestUser": @YES
    };
    
    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    
    [self sendAuthenticateRequest:data manager:manager callback:callback];
}

// Helper method to build authentication URL based on server
- (NSString *)buildAuthURLForServer:(NSString *)serverURL {
    // Ensure serverURL ends with a slash
    if (![serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL stringByAppendingString:@"/"];
    }
    
    // For Ely.by, use the old method
    if ([serverURL isEqualToString:@"https://authserver.ely.by/"]) {
        return [NSString stringWithFormat:@"%@auth/authenticate", serverURL];
    }
    // For other servers, use the standard Yggdrasil API method
    else {
        return [NSString stringWithFormat:@"%@authserver/authenticate", serverURL];
    }
}

// Helper method to build refresh URL based on server
- (NSString *)buildRefreshURLForServer:(NSString *)serverURL {
    // Ensure serverURL ends with a slash
    if (![serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL stringByAppendingString:@"/"];
    }
    
    // For Ely.by, use the old method
    if ([serverURL isEqualToString:@"https://authserver.ely.by/"]) {
        return [NSString stringWithFormat:@"%@auth/refresh", serverURL];
    }
    // For other servers, use the standard Yggdrasil API method
    else {
        return [NSString stringWithFormat:@"%@authserver/refresh", serverURL];
    }
}

// Helper method to send authentication request
/// 多角色场景：调用 refresh 把选定角色绑定到 token
/// 参照 HMCL YggdrasilService.refresh：请求体含 accessToken/clientToken/selectedProfile/requestUser
- (void)refreshToBindProfile:(NSDictionary *)profileToSelect
                  accessToken:(NSString *)accessToken
                  clientToken:(NSString *)clientToken
                     callback:(Callback)callback {
    NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
    if (![serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL stringByAppendingString:@"/"];
    }
    NSString *refreshURL = [self buildRefreshURLForServer:serverURL];

    NSDictionary *data = @{
        @"accessToken": accessToken,
        @"clientToken": clientToken,
        @"selectedProfile": @{
            @"id": profileToSelect[@"id"],
            @"name": profileToSelect[@"name"]
        },
        @"requestUser": @YES
    };

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;

    NSLog(@"[ThirdPartyAuthenticator] Refresh bind profile request: %@", refreshURL);

    __weak typeof(self) weakSelf = self;
    [manager POST:refreshURL parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        @try {
            if (![response isKindOfClass:[NSDictionary class]] ||
                !response[@"accessToken"] || !response[@"clientToken"] ||
                !response[@"selectedProfile"]) {
                NSError *error = createError(localize(@"i18n_str_1106", nil), 1020);
                callback(error, NO);
                return;
            }

            NSDictionary *boundProfile = response[@"selectedProfile"];
            // 校验绑定的角色与请求选择的角色一致
            if (![boundProfile[@"id"] isEqualToString:profileToSelect[@"id"]]) {
                NSError *error = createError(localize(@"i18n_str_1107", nil), 1021);
                callback(error, NO);
                return;
            }

            weakSelf.authData[@"accessToken"] = response[@"accessToken"];
            weakSelf.authData[@"clientToken"] = response[@"clientToken"];
            weakSelf.authData[@"username"] = boundProfile[@"name"];
            weakSelf.authData[@"uuid"] = boundProfile[@"id"];
            weakSelf.authData[@"profileId"] = boundProfile[@"id"];

            // 格式化 UUID（补连字符）
            NSString *uuid = boundProfile[@"id"];
            if (uuid.length == 32) {
                weakSelf.authData[@"profileId"] = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
                    [uuid substringWithRange:NSMakeRange(0, 8)],
                    [uuid substringWithRange:NSMakeRange(8, 4)],
                    [uuid substringWithRange:NSMakeRange(12, 4)],
                    [uuid substringWithRange:NSMakeRange(16, 4)],
                    [uuid substringWithRange:NSMakeRange(20, 12)]
                ];
            }
            // 第三方账户用 profileId（角色 UUID）作为 accountId，使同名账户可共存
            weakSelf.authData[@"accountId"] = weakSelf.authData[@"profileId"];

            // 异步获取头像（与单角色路径一致）
            [weakSelf fetchProfileTextureWithCallback:callback];
        } @catch (NSException *exception) {
            NSError *error = createError([NSString stringWithFormat:localize(@"i18n_str_1108", nil), exception.reason], 1022);
            callback(error, NO);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSString *errMsg = [self parseErrorMessageFromError:error];
        NSError *callbackError = createError(errMsg ?: localize(@"i18n_str_1109", nil), 1023);
        callback(callbackError, NO);
    }];
}

/// 异步获取角色纹理并设置头像 URL，完成后触发 callback
- (void)fetchProfileTextureWithCallback:(Callback)callback {
    NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
    if (![serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL stringByAppendingString:@"/"];
    }

    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
    manager.requestSerializer = AFJSONRequestSerializer.serializer;
    NSString *profileURL = [NSString stringWithFormat:@"%@sessionserver/session/minecraft/profile/%@", serverURL, self.authData[@"profileId"]];

    __weak typeof(self) weakSelf = self;
    [manager GET:profileURL parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        if (response[@"properties"] && [response[@"properties"] isKindOfClass:[NSArray class]]) {
            NSArray *properties = response[@"properties"];
            for (NSDictionary *property in properties) {
                if ([property[@"name"] isEqualToString:@"textures"]) {
                    NSString *textures = property[@"value"];
                    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:textures options:0];
                    if (decodedData) {
                        NSError *error = nil;
                        NSDictionary *texturesDict = [NSJSONSerialization JSONObjectWithData:decodedData options:kNilOptions error:&error];
                        if (texturesDict && !error) {
                            NSString *skinURL = texturesDict[@"textures"][@"SKIN"][@"url"];
                            if (skinURL) {
                                NSString *headURL = [skinURL stringByReplacingOccurrencesOfString:@".png" withString:@"/helm.png"];
                                weakSelf.authData[@"profilePicURL"] = headURL;
                                [weakSelf saveChanges];
                                callback(nil, YES);
                                return;
                            }
                        }
                    }
                }
            }
        }
        weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
        [weakSelf saveChanges];
        callback(nil, YES);
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
        [weakSelf saveChanges];
        callback(nil, YES);
    }];
}

/// 从 AFNetworking 错误中解析 Yggdrasil 服务器返回的 errorMessage
- (NSString *)parseErrorMessageFromError:(NSError *)error {
    NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
    if (data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
        if (json) {
            NSString *msg = json[@"errorMessage"] ?: json[@"error"];
            if (msg.length > 0) return msg;
        }
    }
    return error.localizedDescription;
}

- (void)sendAuthenticateRequest:(NSDictionary *)data manager:(AFHTTPSessionManager *)manager callback:(Callback)callback {
    // Get server URL from authData or use default Ely.by server
    NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
    // Ensure serverURL ends with a slash for consistency
    if (![serverURL hasSuffix:@"/"]) {
        serverURL = [serverURL stringByAppendingString:@"/"];
    }
    NSString *authURL = [self buildAuthURLForServer:serverURL];
    
    NSLog(@"[ThirdPartyAuthenticator] Sending authentication request to %@", authURL);
    
    [manager POST:authURL parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
        @try {
            NSLog(@"[ThirdPartyAuthenticator] Authentication success response received");
            
            // Handle successful response
            if (![response isKindOfClass:[NSDictionary class]]) {
                NSError *error = createError(localize(@"login.error.invalid_response", @"Invalid server response"), 1003);
                callback(error, NO);
                return;
            }
            
            if (!response[@"accessToken"] || !response[@"clientToken"]) {
                NSError *error = createError(localize(@"login.error.invalid_response", @"Invalid server response"), 1004);
                callback(error, NO);
                return;
            }

            // Yggdrasil 规范：当用户有且仅有一个角色时返回 selectedProfile；
            // 有多个角色时只返回 availableProfiles；无角色时两者都缺失。
            // 参照 HMCL：多角色场景下需要调用 refresh 把选定角色绑定到 token，
            // 否则 token 处于"无 profile"状态，游戏 join server 会失败。
            NSDictionary *selectedProfile = response[@"selectedProfile"];
            NSArray *availableProfiles = response[@"availableProfiles"];
            if (![availableProfiles isKindOfClass:[NSArray class]]) {
                availableProfiles = @[];
            }

            if (!selectedProfile && availableProfiles.count > 0) {
                // 多角色场景：先保存 token，再 refresh 绑定第一个角色
                // （HMCL 这里会弹出角色选择器；移动端简化为选第一个）
                NSString *accessToken = response[@"accessToken"];
                NSString *clientToken = response[@"clientToken"];
                NSDictionary *profileToSelect = availableProfiles[0];
                NSLog(@"[ThirdPartyAuthenticator] Multi-profile scenario, refresh binding profile: %@", profileToSelect[@"name"]);
                [self refreshToBindProfile:profileToSelect
                                accessToken:accessToken
                                clientToken:clientToken
                                   callback:callback];
                return;
            }

            if (!selectedProfile) {
                // 有 token 但无任何角色：账户未创建游戏角色
                NSString *errMsg = localize(@"i18n_str_1110", nil);
                NSError *error = createError(errMsg, 1019);
                callback(error, NO);
                return;
            }

            self.authData[@"accessToken"] = response[@"accessToken"];
            self.authData[@"clientToken"] = response[@"clientToken"];
            self.authData[@"username"] = selectedProfile[@"name"];
            self.authData[@"uuid"] = selectedProfile[@"id"];
            self.authData[@"profileId"] = selectedProfile[@"id"];

            // Save information for authlib-injector
        self.authData[@"authserver"] = self.authData[@"authserver"] ?: @"https://authserver.ely.by";

            // Format UUID with hyphens
            NSString *uuid = selectedProfile[@"id"];
            if (uuid.length == 32) { // If UUID without hyphens
                self.authData[@"profileId"] = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
                    [uuid substringWithRange:NSMakeRange(0, 8)],
                    [uuid substringWithRange:NSMakeRange(8, 4)],
                    [uuid substringWithRange:NSMakeRange(12, 4)],
                    [uuid substringWithRange:NSMakeRange(16, 4)],
                    [uuid substringWithRange:NSMakeRange(20, 12)]
                ];
            }
            // 第三方账户用 profileId（角色 UUID）作为 accountId，使同名账户可共存
            self.authData[@"accountId"] = self.authData[@"profileId"];

            // 尝试使用Yggdrasil API获取头像
            NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
            // 确保serverURL以斜杠结尾
            if (![serverURL hasSuffix:@"/"]) {
                serverURL = [serverURL stringByAppendingString:@"/"];
            }

            AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
            manager.requestSerializer = AFJSONRequestSerializer.serializer;
            NSString *profileURL = [NSString stringWithFormat:@"%@sessionserver/session/minecraft/profile/%@", serverURL, self.authData[@"profileId"]];
            
            // 保存当前的authData，以便在异步回调中使用
            __block NSMutableDictionary *localAuthData = [self.authData mutableCopy];
            __weak typeof(self) weakSelf = self;
            
            [manager GET:profileURL parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
                if (response[@"properties"] && [response[@"properties"] isKindOfClass:[NSArray class]]) {
                    NSArray *properties = response[@"properties"];
                    for (NSDictionary *property in properties) {
                        if ([property[@"name"] isEqualToString:@"textures"]) {
                            // 解析皮肤数据
                            NSString *textures = property[@"value"];
                            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:textures options:0];
                            if (decodedData) {
                                NSError *error = nil;
                                NSDictionary *texturesDict = [NSJSONSerialization JSONObjectWithData:decodedData options:kNilOptions error:&error];
                                if (texturesDict && !error) {
                                    // 获取皮肤URL
                                    NSString *skinURL = texturesDict[@"textures"][@"SKIN"][@"url"];
                                    if (skinURL) {
                                        // 设置头像URL为皮肤URL的头盔版本
                                        NSString *headURL = [skinURL stringByReplacingOccurrencesOfString:@".png" withString:@"/helm.png"];
                                        weakSelf.authData[@"profilePicURL"] = headURL;
                                        // 异步更新头像后再次保存，避免账户列表读到失效的占位 URL
                                        [weakSelf saveChanges];
                                        return;
                                    }
                                }
                            }
                        }
                    }
                }

                // 如果Yggdrasil API失败，使用 mc-heads.net 头像服务作为回退
                weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
                [weakSelf saveChanges];
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                // 如果请求失败，使用 mc-heads.net 头像服务作为回退
                weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
                [weakSelf saveChanges];
            }];

            // 设置默认头像，避免UI显示问题（异步获取真实皮肤URL后会覆盖并再次保存）
            self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", self.authData[@"username"]];

            // Token expiration time (24 hours)
            self.authData[@"expiresAt"] = @((long)[NSDate.date timeIntervalSince1970] + 86400);
            // Task 128：显式账户类型标记（zl2 同款 AccountType 思路）。
            // 旧判别靠 expiresAt/clientToken 键位嗅探，三处判别器口径不一
            // （BaseAuthenticator / AccountList / Java 端各一套），易串类。
            self.authData[@"accountType"] = @"thirdparty";

            // Save changes
            callback(nil, [self saveChanges]);
        } @catch (NSException *exception) {
            NSLog(@"[ThirdPartyAuthenticator] Exception in login success: %@", exception);
            NSError *error = createError([NSString stringWithFormat:@"Error: %@", exception.reason], 1005);
            callback(error, NO);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSLog(@"[ThirdPartyAuthenticator] Authentication failed: %@", error);
        
        NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        NSHTTPURLResponse *response = error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
        
        if (errorData) {
            @try {
                // Log error data for diagnostics
                NSString *rawErrorStr = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
                NSLog(@"[ThirdPartyAuthenticator] Raw error data: %@", rawErrorStr);
                
                NSDictionary *errorDict = [NSJSONSerialization JSONObjectWithData:errorData options:kNilOptions error:nil];
                NSLog(@"[ThirdPartyAuthenticator] Error dictionary: %@", errorDict);
                
                // Check for two-factor authentication (status code 401 + specific error message)
                if (response.statusCode == 401 && 
                    [errorDict[@"error"] isEqualToString:@"ForbiddenOperationException"] &&
                    [errorDict[@"errorMessage"] isEqualToString:@"Account protected with two factor auth."]) {
                    
                    NSLog(@"[ThirdPartyAuthenticator] Two-factor authentication required");
                    
                    // Request TOTP code via UI
                    UIAlertController *alert = [UIAlertController 
                        alertControllerWithTitle:localize(@"login.3rdparty.2fa.title", @"Two-Factor Authentication")
                        message:localize(@"login.3rdparty.2fa.message", @"Please enter your two-factor authentication code")
                        preferredStyle:UIAlertControllerStyleAlert];
                    
                    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                        textField.placeholder = localize(@"login.3rdparty.2fa.code", @"Authentication code");
                        textField.keyboardType = UIKeyboardTypeNumberPad;
                    }];
                    
                    UIAlertAction *okAction = [UIAlertAction 
                        actionWithTitle:localize(@"OK", @"OK") 
                        style:UIAlertActionStyleDefault 
                        handler:^(UIAlertAction *action) {
                            NSString *code = alert.textFields.firstObject.text;
                            if (code.length > 0) {
                                [self loginWithTwoFactorToken:code callback:callback];
                            } else {
                                NSError *codeError = createError(localize(@"login.3rdparty.2fa.empty", @"Authentication code cannot be empty"), 1006);
                                callback(codeError, NO);
                            }
                        }];
                    
                    UIAlertAction *cancelAction = [UIAlertAction 
                        actionWithTitle:localize(@"Cancel", @"Cancel") 
                        style:UIAlertActionStyleCancel 
                        handler:^(UIAlertAction *action) {
                            NSError *cancelError = createError(localize(@"login.cancelled", @"Login cancelled"), 1007);
                            callback(cancelError, NO);
                        }];
                    
                    [alert addAction:okAction];
                    [alert addAction:cancelAction];
                    
                    // Get ViewController to present alert
                    UIViewController *rootVC = nil;
                    UIWindow *keyWindow = [UIApplication sharedApplication].delegate.window;
                    if (!keyWindow) {
                        // Fallback for iOS 13+ scene-based apps
                        for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
                            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                                keyWindow = windowScene.windows.firstObject;
                                break;
                            }
                        }
                        // If no active scene, use the first available window
                        if (!keyWindow && [UIApplication sharedApplication].connectedScenes.count > 0) {
                            NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
                            if (scenes.count > 0) {
                                UIWindowScene *firstScene = (UIWindowScene *)[scenes anyObject];
                                if (firstScene.windows.count > 0) {
                                    keyWindow = firstScene.windows.firstObject;
                                }
                            }
                        }
                    }
                    if (keyWindow) {
                        rootVC = keyWindow.rootViewController;
                    }
                    
                    if (rootVC) {
                        [rootVC presentViewController:alert animated:YES completion:nil];
                    } else {
                        NSLog(@"[ThirdPartyAuthenticator] Error: Could not find root view controller to present 2FA alert");
                        NSError *viewError = createError(@"Internal error: Could not present 2FA dialog", 1008);
                        callback(viewError, NO);
                    }
                    return;
                } else if (response.statusCode == 401 && [errorDict[@"error"] isEqualToString:@"ForbiddenOperationException"]) {
                    // Check for specific error for invalid credentials
                    if ([errorDict[@"errorMessage"] isEqualToString:@"Invalid credentials. Invalid username or password."]) {
                        NSError *invalidCredentialsError = createError(localize(@"login.error.invalid_credentials", @"Invalid username or password"), 1020);
                        callback(invalidCredentialsError, NO);
                        return;
                    }
                }
                
                NSString *errorMessage = errorDict[@"errorMessage"] ?: error.localizedDescription;
                NSError *customError = createError(errorMessage, 1009);
                callback(customError, NO);
            } @catch (NSException *exception) {
                NSLog(@"[ThirdPartyAuthenticator] Exception while processing error: %@", exception);
                NSError *exceptionError = createError(error.localizedDescription, 1010);
                callback(exceptionError, NO);
            }
        } else {
            NSError *networkError = createError(error.localizedDescription, 1011);
            callback(networkError, NO);
        }
    }];
}

- (void)loginWithCallback:(Callback)callback {
    // First check/download authlib-injector
    [self ensureAuthlibInjectorWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            callback(error, NO);
            return;
        }
        
        // Continue authentication process
        callback(createError(localize(@"login.3rdparty.progress.auth", nil), 0), YES);
        
        NSString *username = self.authData[@"input"];
        NSString *password = self.authData[@"password"];
        
        if (username.length == 0 || password.length == 0) {
            NSError *fieldsError = createError(localize(@"login.error.fields.empty", nil), 1002);
            callback(fieldsError, NO);
            return;
        }
        
        NSDictionary *data = @{
            @"agent": @{@"name": @"Minecraft", @"version": @1},
            @"username": username,
            @"password": password,
            @"clientToken": [[NSUUID UUID] UUIDString],
            @"requestUser": @YES
        };
        
        AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
        manager.requestSerializer = AFJSONRequestSerializer.serializer;
        
        [self sendAuthenticateRequest:data manager:manager callback:callback];
    }];
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // First check/download authlib-injector
    [self ensureAuthlibInjectorWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            callback(error, NO);
            return;
        }
        
        callback(createError(localize(@"login.3rdparty.progress.refresh", nil), 0), YES);
        
        NSString *accessToken = self.authData[@"accessToken"];
        NSString *clientToken = self.authData[@"clientToken"];
        
        if (accessToken.length == 0 || clientToken.length == 0) {
            NSError *tokenError = createError(localize(@"login.error.token_missing", @"Access token or client token is missing"), 1012);
            callback(tokenError, NO);
            return;
        }
        
        NSDictionary *data = @{
            @"accessToken": accessToken,
            @"clientToken": clientToken,
            @"requestUser": @YES
        };
        
        AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
        manager.requestSerializer = AFJSONRequestSerializer.serializer;
        
        NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
        // Ensure serverURL ends with a slash for consistency
        if (![serverURL hasSuffix:@"/"]) {
            serverURL = [serverURL stringByAppendingString:@"/"];
        }
        NSString *refreshURL = [self buildRefreshURLForServer:serverURL];
        
        [manager POST:refreshURL parameters:data headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
            @try {
                // Update tokens
                if (![response isKindOfClass:[NSDictionary class]] || !response[@"accessToken"] || !response[@"clientToken"]) {
                    NSError *invalidError = createError(localize(@"login.error.invalid_response", @"Invalid server response"), 1013);
                    callback(invalidError, NO);
                    return;
                }
                
                self.authData[@"accessToken"] = response[@"accessToken"];
                self.authData[@"clientToken"] = response[@"clientToken"];
                
                // Update selectedProfile if present
                if (response[@"selectedProfile"]) {
                    self.authData[@"username"] = response[@"selectedProfile"][@"name"];
                    self.authData[@"uuid"] = response[@"selectedProfile"][@"id"];
                    
                    // Format UUID with hyphens if needed
                    NSString *uuid = response[@"selectedProfile"][@"id"];
                    if (uuid.length == 32) { // If UUID without hyphens
                        self.authData[@"profileId"] = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
                            [uuid substringWithRange:NSMakeRange(0, 8)],
                            [uuid substringWithRange:NSMakeRange(8, 4)],
                            [uuid substringWithRange:NSMakeRange(12, 4)],
                            [uuid substringWithRange:NSMakeRange(16, 4)],
                            [uuid substringWithRange:NSMakeRange(20, 12)]
                        ];
                    } else {
                        self.authData[@"profileId"] = uuid;
                    }
                    // 第三方账户用 profileId（角色 UUID）作为 accountId，使同名账户可共存
                    self.authData[@"accountId"] = self.authData[@"profileId"];

                    // 尝试使用Yggdrasil API获取头像
                    NSString *serverURL = self.authData[@"authserver"] ?: @"https://authserver.ely.by";
                    // 确保serverURL以斜杠结尾
                    if (![serverURL hasSuffix:@"/"]) {
                        serverURL = [serverURL stringByAppendingString:@"/"];
                    }
                    
                    AFHTTPSessionManager *manager = AFHTTPSessionManager.manager;
                    manager.requestSerializer = AFJSONRequestSerializer.serializer;
                    NSString *profileURL = [NSString stringWithFormat:@"%@sessionserver/session/minecraft/profile/%@", serverURL, self.authData[@"profileId"]];
                    
                    // 保存当前的authData，以便在异步回调中使用
                    __block NSMutableDictionary *localAuthData = [self.authData mutableCopy];
                    __weak typeof(self) weakSelf = self;
                    
                    [manager GET:profileURL parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask *task, NSDictionary *response) {
                        if (response[@"properties"] && [response[@"properties"] isKindOfClass:[NSArray class]]) {
                            NSArray *properties = response[@"properties"];
                            for (NSDictionary *property in properties) {
                                if ([property[@"name"] isEqualToString:@"textures"]) {
                                    // 解析皮肤数据
                                    NSString *textures = property[@"value"];
                                    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:textures options:0];
                                    if (decodedData) {
                                        NSError *error = nil;
                                        NSDictionary *texturesDict = [NSJSONSerialization JSONObjectWithData:decodedData options:kNilOptions error:&error];
                                        if (texturesDict && !error) {
                                            // 获取皮肤URL
                                            NSString *skinURL = texturesDict[@"textures"][@"SKIN"][@"url"];
                                            if (skinURL) {
                                                // 设置头像URL为皮肤URL的头盔版本
                                                NSString *headURL = [skinURL stringByReplacingOccurrencesOfString:@".png" withString:@"/helm.png"];
                                                weakSelf.authData[@"profilePicURL"] = headURL;
                                                // 异步更新头像后再次保存，避免账户列表读到失效的占位 URL
                                                [weakSelf saveChanges];
                                                return;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 如果Yggdrasil API失败，使用 mc-heads.net 头像服务作为回退
                        weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
                        [weakSelf saveChanges];
                    } failure:^(NSURLSessionDataTask *task, NSError *error) {
                        // 如果请求失败，使用 mc-heads.net 头像服务作为回退
                        weakSelf.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", weakSelf.authData[@"username"]];
                        [weakSelf saveChanges];
                    }];

                    // 设置默认头像，避免UI显示问题（异步获取真实皮肤URL后会覆盖并再次保存）
                    self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"https://mc-heads.net/avatar/%@/100", self.authData[@"username"]];
                }
                
                // Token expiration time (24 hours)
                self.authData[@"expiresAt"] = @((long)[NSDate.date timeIntervalSince1970] + 86400);
                // Task 128：显式账户类型标记（同上）
                self.authData[@"accountType"] = @"thirdparty";
                
                // Save changes
                callback(nil, [self saveChanges]);
            } @catch (NSException *exception) {
                NSLog(@"[ThirdPartyAuthenticator] Exception in refresh success: %@", exception);
                NSError *exceptionError = createError([NSString stringWithFormat:@"Error: %@", exception.reason], 1014);
                callback(exceptionError, NO);
            }
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSData *errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
            if (errorData) {
                @try {
                    NSDictionary *errorDict = [NSJSONSerialization JSONObjectWithData:errorData options:kNilOptions error:nil];
                    
                    // Check for expired token error
                    if ([errorDict[@"error"] isEqualToString:@"ForbiddenOperationException"] && 
                        [errorDict[@"errorMessage"] isEqualToString:@"Token expired."]) {
                        NSError *expiredError = createError(localize(@"login.error.token_expired", @"Authentication token has expired, please log in again"), 1015);
                        callback(expiredError, NO);
                        return;
                    }
                    
                    NSString *errorMessage = errorDict[@"errorMessage"] ?: error.localizedDescription;
                    NSError *customError = createError(errorMessage, 1016);
                    callback(customError, NO);
                } @catch (NSException *exception) {
                    NSError *exceptionError = createError(error.localizedDescription, 1017);
                    callback(exceptionError, NO);
                }
            } else {
                NSError *networkError = createError(error.localizedDescription, 1018);
                callback(networkError, NO);
            }
        }];
    }];
}

@end