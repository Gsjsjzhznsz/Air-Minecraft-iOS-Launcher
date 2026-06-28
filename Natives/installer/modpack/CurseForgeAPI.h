#import <Foundation/Foundation.h>
#import "ModpackAPI.h"
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

// NSError userInfo keys for diagnostic information (CurseForge API)
extern NSString *const CurseForgeResponseContentTypeKey;
extern NSString *const CurseForgeResponseSnippetKey;

/// CurseForge API 实现，支持模组、资源包、光影、数据包、整合包等
@interface CurseForgeAPI : ModpackAPI

+ (instancetype)sharedInstance;

// ========== 同步方法（兼容旧代码，注意会阻塞线程） ==========
/// 搜索项目（同步，内部使用 dispatch_group_wait，建议在后台队列调用）
- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters
                     previousPageResult:(nullable NSMutableArray *)previousPageResult;

/// 加载项目详情（同步，会填充 item 的版本信息）
- (void)loadDetailsOfMod:(NSMutableDictionary *)item;

// ========== 异步方法（推荐，不阻塞 UI） ==========
/// 异步搜索（推荐），支持 projectType = @"resourcepack" / @"mod" / @"shader" 等
- (void)searchModWithFilters:(NSDictionary *)filters
                  completion:(void (^)(NSArray * _Nullable results, NSError * _Nullable error))completion;

/// 异步获取某个项目的所有版本
- (void)getVersionsForModWithID:(NSString *)modID
                     completion:(void (^)(NSArray<ModVersion *> * _Nullable versions, NSError * _Nullable error))completion;

// ========== 异步详情加载 ==========
/// 异步加载项目详情（不阻塞调用线程）
- (void)loadDetailsOfMod:(NSMutableDictionary *)item
              completion:(void (^)(NSError * _Nullable error))completion;

// ========== 下载工具方法 ==========
/// 获取文件的直接下载链接（CurseForge 需要二次请求）
- (NSString *)downloadURLForFile:(NSDictionary *)file;

/// 检查文件是否匹配项目类型（如资源包只允许 zip）
- (BOOL)file:(NSDictionary *)file matchesProjectType:(NSString *)projectType;

/// 获取项目类型对应的推荐文件后缀（jar/zip）
- (NSArray<NSString *> *)preferredFileExtensionsForProjectType:(NSString *)projectType;

// ========== 指纹反查 ==========
/// 通过 MurmurHash2 文件指纹反查 CurseForge 项目（单个）
- (nullable NSMutableDictionary *)projectForFileHash:(NSString *)murmurHash projectType:(NSString *)projectType;

/// 批量指纹反查（用于批量更新检查）
- (NSArray<NSMutableDictionary *> *)fileFingerprints:(NSArray<NSNumber *> *)fingerprints;

// ========== 整合包处理 ==========
/// 解析 CurseForge 整合包（manifest.json），批量提交下载任务
- (void)downloader:(MinecraftResourceDownloadTask *)downloader
submitDownloadTasksFromPackage:(NSString *)packagePath
            toPath:(NSString *)destPath;

@end

NS_ASSUME_NONNULL_END