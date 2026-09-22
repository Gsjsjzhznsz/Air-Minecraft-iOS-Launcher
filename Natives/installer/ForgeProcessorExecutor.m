//
//  ForgeProcessorExecutor.m
//  Amethyst
//
//  新格式 Forge/NeoForge 直装的 install_profile processors 执行器（共用核心）。
//
//  移植自 ZalithLauncher2 的 Install.ForgeLike.kt / _ForgeLikeUtils.kt
//  （参考 HMCL ForgeNewInstallTask），核心差异：
//  - ZL2 为每条 processor spawn 一个子 JVM；iOS 沙箱禁止 fork/exec，
//    这里将全部命令序列化为 commands.json，交由进程内 headless JVM 中的
//    ForgeProcessorRunner 逐条执行（对齐官方 installer 的单 JVM +
//    IsolatedClassLoader 行为）。
//  - DOWNLOAD_MOJMAPS processor 被跳过，改为 ObjC 侧预下载
//    版本 JSON 的 downloads.client_mappings（piston-data / BMCLAPI，sha1 校验）。
//
//  命令 JSON 契约（与 ForgeProcessorRunner.java 对齐）：
//    [ { "name": ..., "mainClass": ..., "classpath": [绝对路径...],
//        "args": [字符串...], "outputs": {"绝对路径": "sha1"} } ]
//  状态 JSON（ForgeProcessorRunner 每步重写）：
//    { "ok": true/false, "completed": N, "total": N, "current": "...",
//      "error": "...", "failedCommand": "..." }
//

#import "ForgeProcessorExecutor.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "utils.h"
#import "external/UnzipKit/UZKArchive.h"

#import <CommonCrypto/CommonDigest.h>
#import <pthread.h>

NSString *const ForgeProcessorExecutorErrorDomain = @"ForgeProcessorExecutorErrorDomain";

// headless JVM 中运行的 processor runner 主类
static NSString *const kProcessorRunnerMainClass = @"net.kdt.pojavlaunch.tools.ForgeProcessorRunner";

// Task 145：headless JVM 专用线程上下文（见 runProcessorsWithProfile 内注释）。
// exit(0) 抑制路径下 hooked_exit 会 pthread_exit 本线程，launchHeadlessJVM
// 永不返回；改跑在独立可 join 的 pthread 上后，pthread_join 两边都能等到
// 线程终结（正常 return 或被抑制的 exit），返回码仅保留启动失败语义。
typedef struct {
    NSString *mainClass;
    NSArray<NSString *> *args;
    int minJava;
    int ret;
} ame145_headlessCtx;

static void *ame145_headlessJvmThread(void *raw) {
    ame145_headlessCtx *ctx = (ame145_headlessCtx *)raw;
    ctx->ret = launchHeadlessJVM(ctx->mainClass, ctx->args, ctx->minJava);
    return NULL;
}

static NSString *const kUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

static NSString *const kManifestURLOfficial = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
static NSString *const kManifestURLBMCLAPI = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";

// 进度内部映射：vars 0~0.05，原版 jar 0.05~0.35，mappings 0.35~0.45，processors 0.45~1.0
static const double kInnerVanillaJarStart = 0.05;
static const double kInnerMojmapsStart = 0.35;
static const double kInnerProcessorsStart = 0.45;

@implementation ForgeProcessorExecutor

#pragma mark - Public

+ (BOOL)runProcessorsWithProfile:(NSDictionary *)installProfile
                   installerPath:(NSString *)installerPath
                minecraftVersion:(NSString *)minecraftVersion
                      mainGameDir:(NSString *)mainGameDir
                     baseProgress:(double)baseProgress
                    progressSpan:(double)progressSpan
                        progress:(void (^)(double, NSString *))progress
                           error:(NSError **)error {
    void (^report)(double, NSString *) = ^(double inner, NSString *msg) {
        double p = baseProgress + progressSpan * inner;
        if (p > baseProgress + progressSpan) p = baseProgress + progressSpan;
        if (p < 0) p = 0;
        NSLog(@"[ForgeProcExec] Progress: %.2f - %@", p, msg);
        if (progress) progress(p, msg);
    };

    if (error) *error = nil;

    // 前置防御：本进程已创建过 JVM（跑过游戏或跑过一次 processors），
    // 再次 JLI_Launch 必然崩溃，引导用户重启 app。
    if (JVMUsedInProcess()) {
        NSLog(@"[ForgeProcExec] JVM already created in this process, restart required");
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorJvmAlreadyUsed
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1143", nil)}];
        }
        return NO;
    }

    NSArray *processors = [installProfile[@"processors"] isKindOfClass:[NSArray class]]
        ? installProfile[@"processors"] : @[];
    if (processors.count == 0) {
        // 无 processors（理论上新格式都有；防御性直接成功）
        NSLog(@"[ForgeProcExec] No processors in install_profile, nothing to run");
        return YES;
    }

    NSString *librariesDir = [mainGameDir stringByAppendingPathComponent:@"libraries"];
    NSString *cacheDir = [mainGameDir stringByAppendingPathComponent:@".temp/forge_installer_cache"];
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:cacheDir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&dirError]) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1144", nil), cacheDir, dirError.localizedDescription ?: @"unknown"]}];
        }
        return NO;
    }

    // ------------------------------------------------------------------
    // 1. 构建 vars：data.*.client 逐项 parseLiteral
    //    （plain 值从安装器 zip 解压到 cacheDir），再补充系统变量
    // ------------------------------------------------------------------
    report(0.0, localize(@"i18n_str_1321", nil));
    NSMutableDictionary *vars = [self buildVars:installProfile
                                   installerPath:installerPath
                                   librariesDir:librariesDir
                                       cacheDir:cacheDir
                                          error:error];
    if (!vars) {
        return NO;
    }

    NSString *vanillaJarPath = [mainGameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.jar", minecraftVersion, minecraftVersion]];
    vars[@"SIDE"] = @"client";
    vars[@"MINECRAFT_JAR"] = vanillaJarPath;
    vars[@"MINECRAFT_VERSION"] = vanillaJarPath;
    vars[@"ROOT"] = mainGameDir;
    vars[@"INSTALLER"] = installerPath;
    vars[@"LIBRARY_DIR"] = librariesDir;

    // ------------------------------------------------------------------
    // 2. 确保原版 client.jar 存在（jarsplitter/binarypatcher 的输入）
    // ------------------------------------------------------------------
    report(kInnerVanillaJarStart, localize(@"i18n_str_1322", nil));
    if (![self ensureVanillaClientJar:minecraftVersion
                          mainGameDir:mainGameDir
                             progress:^(double inner, NSString *msg) {
        report(kInnerVanillaJarStart + (kInnerMojmapsStart - kInnerVanillaJarStart) * inner, msg);
    } error:error]) {
        return NO;
    }

    // ------------------------------------------------------------------
    // 3. 预下载 client mappings（替代 DOWNLOAD_MOJMAPS processor）
    // ------------------------------------------------------------------
    report(kInnerMojmapsStart, localize(@"i18n_str_1323", nil));
    if (![self preDownloadMojmaps:processors
                     librariesDir:librariesDir
                             vars:vars
                     mainGameDir:mainGameDir
                          progress:^(double inner, NSString *msg) {
        report(kInnerMojmapsStart + (kInnerProcessorsStart - kInnerMojmapsStart) * inner, msg);
    } error:error]) {
        return NO;
    }

    // ------------------------------------------------------------------
    // 4. 构建 client side 命令清单（outputs 已就绪的命令跳过）
    // ------------------------------------------------------------------
    report(kInnerProcessorsStart, localize(@"i18n_str_1324", nil));
    NSArray *commands = [self buildCommands:processors
                               librariesDir:librariesDir
                                      vars:vars
                                     error:error];
    if (!commands) {
        return NO;
    }
    if (commands.count == 0) {
        NSLog(@"[ForgeProcExec] All processor outputs already satisfied, skipping execution");
        report(1.0, localize(@"i18n_str_1325", nil));
        [[NSFileManager defaultManager] removeItemAtPath:cacheDir error:nil];
        return YES;
    }

    // ------------------------------------------------------------------
    // 5. 写 commands.json 并执行（headless JVM + 状态轮询）
    // ------------------------------------------------------------------
    NSString *commandsPath = [cacheDir stringByAppendingPathComponent:@"commands.json"];
    NSString *statusPath = [cacheDir stringByAppendingPathComponent:@"status.json"];

    NSData *commandsJSON = [NSJSONSerialization dataWithJSONObject:commands
                                                           options:0
                                                             error:error];
    if (!commandsJSON || ![commandsJSON writeToFile:commandsPath options:NSDataWritingAtomic error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1150", nil), commandsPath]}];
        }
        return NO;
    }
    // 清掉上一次残留的 status，避免误读旧终态
    [[NSFileManager defaultManager] removeItemAtPath:statusPath error:nil];
    NSLog(@"[ForgeProcExec] Wrote %lu command(s) to %@", (unsigned long)commands.count, commandsPath);

    // 轮询线程：每 0.5s 读 status.json 上报进度。
    // pollDone 无锁读写是刻意为之：最坏情况多轮询一轮，读到的是同一文件的
    // 只读快照，且所有回调都发生在 runProcessorsWithProfile 返回之前。
    __block BOOL pollDone = NO;
    dispatch_queue_t pollQueue = dispatch_queue_create("forge.processor.status.poll", DISPATCH_QUEUE_SERIAL);
    dispatch_async(pollQueue, ^{
        while (!pollDone) {
            @autoreleasepool {
                NSDictionary *status = [self readStatusFile:statusPath];
                if (status) {
                    NSInteger completed = [status[@"completed"] integerValue];
                    NSInteger total = [status[@"total"] integerValue];
                    NSString *current = [status[@"current"] isKindOfClass:[NSString class]] ? status[@"current"] : nil;
                    if (total > 0) {
                        double inner = kInnerProcessorsStart
                            + (1.0 - kInnerProcessorsStart) * ((double)completed / (double)total);
                        report(inner, [NSString stringWithFormat:localize(@"i18n_str_1151", nil),
                            (long)completed, (long)total, current.length ? [NSString stringWithFormat:@": %@", current] : @""]);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.5];
        }
    });

    // 按原版 MC 版本推断 processor 所需 Java 大版本（对齐游戏运行时要求）
    int minJava = [self inferJavaMajorForMinecraft:minecraftVersion];
    NSLog(@"[ForgeProcExec] Launching headless JVM (minJava=%d)", minJava);
    // Task 144：headless JVM 执行期抑制进程级 exit —— 安装器 JVM 结束时
    // libjli 内部线程会 exit(0) 结束自身，但 JVM 与启动器同进程，此前整个
    // app 被带走（用户视角"forge安装闪退"，modpack 卡在 85%）。置位后
    // hooked_exit 改为只终结调用线程；JLI_Launch 正常返回，下方照常读
    // status.json 判定安装成败。
    atomic_store(&g_ame_suppressJvmExit, 1);
    // Task 145：headless JVM 移到独立可 join 的 pthread 上执行。
    //
    // Task 144 病历补充（装机 latestlog.forge 22:21 会话实锤）：JLI_Launch 在
    // JVM main 返回后由 libjli 启动线程（fatal-trace 栈帧 dummyTimer）调用
    // exit(0) 终结进程 —— 该线程就是本函数的调用线程。Task144 的抑制把它转
    // 成 pthread_exit，结果 launchHeadlessJVM 永不返回，下方 status.json 终态
    // 判定与收尾代码永远不执行，轮询线程挂死（装机表现为进度恒 0.85、
    // "正在执行安装任务 (4/4)" 刷屏直到用户切后台）。
    // 专用线程 + pthread_join 后：无论 JLI 正常返回还是 exit 被转成线程退出，
    // join 都能等到，调用方照常读 status.json 判定安装成败；ret 仅保留
    // JLI 启动失败语义（-1~-6，无 exit 发生的路径）。
    ame145_headlessCtx ame145_ctx = {
        .mainClass = kProcessorRunnerMainClass,
        .args = @[commandsPath, statusPath],
        .minJava = minJava,
        .ret = 0,
    };
    pthread_attr_t ame145_attr;
    pthread_attr_init(&ame145_attr);
    // JVM 原生侧调用深度不可控，给足栈空间（虚拟内存，实际按需提交）。
    pthread_attr_setstacksize(&ame145_attr, 64ull * 1024 * 1024);
    pthread_t ame145_tid = NULL;
    int ame145_rc = pthread_create(&ame145_tid, &ame145_attr, ame145_headlessJvmThread, &ame145_ctx);
    pthread_attr_destroy(&ame145_attr);
    if (ame145_rc == 0) {
        pthread_join(ame145_tid, NULL);
    } else {
        // 兜底：线程创建失败时保持旧行为（同线程执行）。
        NSLog(@"[ForgeProcExec] Task145: pthread_create failed (%d), running headless JVM inline", ame145_rc);
        ame145_ctx.ret = launchHeadlessJVM(ame145_ctx.mainClass, ame145_ctx.args, ame145_ctx.minJava);
    }
    atomic_store(&g_ame_suppressJvmExit, 0);
    pollDone = YES;
    int ret = ame145_ctx.ret;

    if (ret != 0) {
        NSLog(@"[ForgeProcExec] launchHeadlessJVM returned %d", ret);
        if (error) {
            NSString *reason = nil;
            if (ret == -1) reason = localize(@"i18n_str_1152", nil);
            else if (ret == -2) reason = localize(@"i18n_str_1153", nil);
            else if (ret == -3) reason = localize(@"i18n_str_1154", nil);
            else if (ret == -4) reason = localize(@"i18n_str_1155", nil);
            else if (ret == -5) reason = localize(@"i18n_str_1156", nil);
            else if (ret == -6) reason = localize(@"i18n_str_1157", nil);
            else reason = [NSString stringWithFormat:localize(@"i18n_str_1158", nil), ret];
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorLaunchFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1159", nil),
                                         reason,
                                         (ret == -5 || ret == -1) ? localize(@"i18n_str_2049", nil) : localize(@"i18n_str_1161", nil)]}];
        }
        return NO;
    }

    // ------------------------------------------------------------------
    // 6. 读终态 status.json 判定成败
    // ------------------------------------------------------------------
    NSDictionary *finalStatus = [self readStatusFile:statusPath];
    if (!finalStatus) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorProcessingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1162", nil), statusPath]}];
        }
        return NO;
    }
    if (![finalStatus[@"ok"] boolValue]) {
        NSString *detail = [finalStatus[@"error"] isKindOfClass:[NSString class]] ? finalStatus[@"error"] : nil;
        NSString *failed = [finalStatus[@"failedCommand"] isKindOfClass:[NSString class]] ? finalStatus[@"failedCommand"] : nil;
        NSLog(@"[ForgeProcExec] Processor failed: %@\n%@", failed ?: @"unknown", detail ?: @"no detail");
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorProcessingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1163", nil),
                                         failed.length ? [NSString stringWithFormat:@"（%@）", failed] : @"",
                                         detail ?: localize(@"i18n_str_97", nil)]}];
        }
        return NO;
    }

    NSLog(@"[ForgeProcExec] All %ld processor(s) finished successfully", (long)[finalStatus[@"total"] integerValue]);

    // 成功后清理临时缓存（断点续装依赖的是 libraries 下的正式 outputs，可安全删除）
    [[NSFileManager defaultManager] removeItemAtPath:cacheDir error:nil];
    report(1.0, localize(@"i18n_str_1326", nil));
    return YES;
}

+ (BOOL)jvmUsedThisProcess {
    return JVMUsedInProcess();
}

#pragma mark - vars 构建

/// 移植 ZL2 installNewForgeHMCLWay：解析 install_profile.data.*.client。
/// plain 值（如 "/data/client.lzma"）从安装器 zip 解压到 cacheDir；
/// 解压失败时该变量不设置（对齐 ZL2 的 ?.let 行为）。
+ (NSMutableDictionary *)buildVars:(NSDictionary *)installProfile
                     installerPath:(NSString *)installerPath
                     librariesDir:(NSString *)librariesDir
                         cacheDir:(NSString *)cacheDir
                            error:(NSError **)error {
    NSMutableDictionary *vars = [NSMutableDictionary dictionary];

    NSError *openError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:installerPath error:&openError];
    if (!archive || openError) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1165", nil), installerPath, openError.localizedDescription ?: @"unknown"]}];
        }
        return nil;
    }

    NSDictionary *data = [installProfile[@"data"] isKindOfClass:[NSDictionary class]]
        ? installProfile[@"data"] : nil;
    for (NSString *key in data) {
        NSDictionary *entry = [data[key] isKindOfClass:[NSDictionary class]] ? data[key] : nil;
        if (!entry) continue;
        NSString *clientValue = [entry[@"client"] isKindOfClass:[NSString class]] ? entry[@"client"] : nil;
        if (!clientValue) continue;

        // data 阶段 vars 为空（对齐 ZL2：parseLiteral 默认 emptyMap）
        NSString *resolved = [self parseLiteral:clientValue
                                   librariesDir:librariesDir
                                          vars:@{}
                                plainConverter:^NSString *(NSString *plain) {
            // 去掉前导 \ 或 /，统一分隔符后从安装器 zip 解压
            NSString *item = plain;
            while ([item hasPrefix:@"\\"] || [item hasPrefix:@"/"]) {
                item = [item substringFromIndex:1];
            }
            item = [item stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
            if (item.length == 0) return nil;

            NSError *extractError = nil;
            NSData *entryData = [archive extractDataFromFile:item error:&extractError];
            if (!entryData) {
                NSLog(@"[ForgeProcExec] Warning: failed to extract %@ from installer: %@", item, extractError.localizedDescription ?: @"unknown");
                return nil;
            }
            NSString *dest = [cacheDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
            if (![entryData writeToFile:dest options:NSDataWritingAtomic error:nil]) {
                return nil;
            }
            NSLog(@"[ForgeProcExec] Extracted installer entry %@ -> %@", item, dest);
            return dest;
        } error:nil];

        if (resolved) {
            vars[key] = resolved;
            NSLog(@"[ForgeProcExec] Var %@ = %@", key, resolved);
        }
    }

    return vars;
}

#pragma mark - 命令构建

/// 移植 ZL2 runProcessors 的命令构建部分：
/// 过滤非 client side；跳过 DOWNLOAD_MOJMAPS（已预下载）；outputs 全部
/// 存在且 sha1 匹配的命令跳过（断点续装）；processor jar 读 Manifest
/// Main-Class；classpath = processor 声明的库 + processor jar（必须存在）。
+ (NSArray<NSDictionary *> *)buildCommands:(NSArray *)processors
                              librariesDir:(NSString *)librariesDir
                                     vars:(NSDictionary *)vars
                                    error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *commands = [NSMutableArray array];

    for (NSDictionary *processor in processors) {
        if (![processor isKindOfClass:[NSDictionary class]]) continue;

        // side 过滤（不看 args，避免 server-only 参数解析失败）
        NSArray *sides = [processor[@"sides"] isKindOfClass:[NSArray class]] ? processor[@"sides"] : nil;
        BOOL isClient = (sides == nil) || [sides containsObject:@"client"];
        if (!isClient) continue;

        NSArray *args = [processor[@"args"] isKindOfClass:[NSArray class]] ? processor[@"args"] : @[];

        // task 过滤：DOWNLOAD_MOJMAPS 已由 preDownloadMojmaps 预下载替代
        NSDictionary *options = [self parseOptions:args librariesDir:librariesDir vars:vars error:error];
        if (!options) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                             code:ForgeProcessorExecutorErrorInvalidProfile
                                         userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1166", nil)}];
            }
            return nil;
        }
        if ([options[@"task"] isEqualToString:@"DOWNLOAD_MOJMAPS"]) continue;

        // outputs：{路径: sha1}，key/value 均需 parseLiteral
        NSDictionary *outputsRaw = [processor[@"outputs"] isKindOfClass:[NSDictionary class]]
            ? processor[@"outputs"] : @{};
        NSMutableDictionary<NSString *, NSString *> *outputs = [NSMutableDictionary dictionary];
        for (NSString *rawKey in outputsRaw) {
            NSString *path = [self parseLiteral:rawKey librariesDir:librariesDir vars:vars plainConverter:nil error:error];
            NSString *sha = [self parseLiteral:outputsRaw[rawKey] librariesDir:librariesDir vars:vars plainConverter:nil error:error];
            if (!path || !sha) {
                if (error && !*error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorInvalidProfile
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1167", nil), rawKey, outputsRaw[rawKey]]}];
                }
                return nil;
            }
            outputs[path] = sha;
        }

        // 断点续装：outputs 非空且全部存在、sha1 匹配 → 跳过
        if (outputs.count > 0 && [self allOutputsSatisfied:outputs]) {
            NSLog(@"[ForgeProcExec] Skipping processor (outputs already satisfied): %@", options[@"task"] ?: processor[@"jar"]);
            continue;
        }

        // processor jar
        NSString *jarDescriptor = [processor[@"jar"] isKindOfClass:[NSString class]] ? processor[@"jar"] : nil;
        if (!jarDescriptor) {
            if (error) {
                *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                             code:ForgeProcessorExecutorErrorInvalidProfile
                                         userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1168", nil)}];
            }
            return nil;
        }
        NSString *jarPath = [librariesDir stringByAppendingPathComponent:
            [self libraryPathFromDescriptor:jarDescriptor error:error]];
        if (!jarPath) return nil;
        if (![fm fileExistsAtPath:jarPath]) {
            if (error) {
                *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                             code:ForgeProcessorExecutorErrorMissingLibrary
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1169", nil), jarDescriptor, jarPath]}];
            }
            return nil;
        }

        // Main-Class（从 jar Manifest 读取）
        NSString *mainClass = [self mainClassFromJar:jarPath];
        if (!mainClass) {
            if (error) {
                *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                             code:ForgeProcessorExecutorErrorMissingLibrary
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1170", nil), jarPath]}];
            }
            return nil;
        }

        // classpath = processor 声明的库 + processor jar 本身
        NSMutableArray<NSString *> *classpath = [NSMutableArray array];
        NSArray *cpDescriptors = [processor[@"classpath"] isKindOfClass:[NSArray class]]
            ? processor[@"classpath"] : @[];
        for (NSString *desc in cpDescriptors) {
            if (![desc isKindOfClass:[NSString class]]) continue;
            NSString *libPath = [librariesDir stringByAppendingPathComponent:
                [self libraryPathFromDescriptor:desc error:error]];
            if (!libPath) return nil;
            if (![fm fileExistsAtPath:libPath]) {
                if (error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorMissingLibrary
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1171", nil), desc, libPath]}];
                }
                return nil;
            }
            [classpath addObject:libPath];
        }
        [classpath addObject:jarPath];

        // args 逐个 parseLiteral
        NSMutableArray<NSString *> *resolvedArgs = [NSMutableArray array];
        for (NSString *arg in args) {
            if (![arg isKindOfClass:[NSString class]]) continue;
            NSString *resolved = [self parseLiteral:arg librariesDir:librariesDir vars:vars plainConverter:nil error:error];
            if (!resolved) {
                if (error && !*error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorInvalidProfile
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1172", nil), arg]}];
                }
                return nil;
            }
            [resolvedArgs addObject:resolved];
        }

        // 显示名：优先 outputs 文件名（对齐 ZL2 的 taskStr），否则 jar 坐标
        NSString *name = nil;
        if (outputs.count > 0) {
            NSString *lastPath = outputs.allKeys.lastObject;
            name = lastPath.lastPathComponent;
        }
        if (!name) name = jarDescriptor;

        [commands addObject:@{
            @"name": name,
            @"mainClass": mainClass,
            @"classpath": classpath,
            @"args": resolvedArgs,
            @"outputs": outputs,
        }];
        NSLog(@"[ForgeProcExec] Built command %@ (mainClass=%@, cp=%lu, args=%lu, outputs=%lu)",
              name, mainClass, (unsigned long)classpath.count, (unsigned long)resolvedArgs.count, (unsigned long)outputs.count);
    }

    return commands;
}

/// outputs 全部存在且 sha1 匹配则返回 YES（对齐 ZL2/HMCL 断点续装判断；
/// sha1 不匹配的文件会被删除以便重新生成）
+ (BOOL)allOutputsSatisfied:(NSDictionary<NSString *, NSString *> *)outputs {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in outputs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) return NO;
        NSString *expected = outputs[path];
        NSString *actual = [self sha1OfFile:path];
        if (!actual) return NO;
        if (expected.length > 0 && [actual caseInsensitiveCompare:expected] != NSOrderedSame) {
            // 损坏的产物删除，重试时可重新生成
            NSLog(@"[ForgeProcExec] Removing stale artifact (sha1 mismatch): %@", path);
            [fm removeItemAtPath:path error:nil];
            return NO;
        }
    }
    return YES;
}

#pragma mark - DOWNLOAD_MOJMAPS 预下载

/// 找到 task=DOWNLOAD_MOJMAPS 的 processor，解析其 --version/--output，
/// 从版本 JSON 的 downloads.client_mappings 下载到 output 路径。
/// （piston-data 官方源与 BMCLAPI 镜像按 general.download_source 排序，sha1 校验）
+ (BOOL)preDownloadMojmaps:(NSArray *)processors
              librariesDir:(NSString *)librariesDir
                      vars:(NSDictionary *)vars
                mainGameDir:(NSString *)mainGameDir
                  progress:(void (^)(double, NSString *))progress
                     error:(NSError **)error {
    NSString *mojmapsVersion = nil;
    NSString *mojmapsOutput = nil;

    for (NSDictionary *processor in processors) {
        if (![processor isKindOfClass:[NSDictionary class]]) continue;
        NSArray *args = [processor[@"args"] isKindOfClass:[NSArray class]] ? processor[@"args"] : @[];

        // 快速判定是否 DOWNLOAD_MOJMAPS（"--task" 的下一个元素）
        BOOL isMojmaps = NO;
        for (NSUInteger i = 0; i + 1 < args.count; i++) {
            if ([args[i] isKindOfClass:[NSString class]] && [args[i] isEqualToString:@"--task"]
                && [args[i + 1] isKindOfClass:[NSString class]]
                && [args[i + 1] isEqualToString:@"DOWNLOAD_MOJMAPS"]) {
                isMojmaps = YES;
                break;
            }
        }
        if (!isMojmaps) continue;

        NSDictionary *options = [self parseOptions:args librariesDir:librariesDir vars:vars error:error];
        if (!options) return NO;
        mojmapsVersion = options[@"version"];
        mojmapsOutput = options[@"output"];
        break;
    }

    if (!mojmapsOutput) {
        // 没有 DOWNLOAD_MOJMAPS processor，无需预下载
        return YES;
    }
    if (!mojmapsVersion) mojmapsVersion = @"";

    if (progress) progress(0.0, localize(@"i18n_str_1327", nil));
    NSLog(@"[ForgeProcExec] Pre-downloading client mappings: version=%@ output=%@", mojmapsVersion, mojmapsOutput);

    // 读版本 JSON（不存在时自动下载）
    NSDictionary *versionJSON = [self ensureVersionJSON:mojmapsVersion mainGameDir:mainGameDir error:error];
    if (!versionJSON) return NO;

    NSDictionary *clientMappings = [versionJSON[@"downloads"] isKindOfClass:[NSDictionary class]]
        ? versionJSON[@"downloads"][@"client_mappings"] : nil;
    if (![clientMappings isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1174", nil), mojmapsVersion]}];
        }
        return NO;
    }

    return [self downloadArtifactFromVersionEntry:clientMappings
                                           toPath:mojmapsOutput
                                          label:localize(@"i18n_str_1175", nil)
                                         progress:progress
                                            error:error];
}

#pragma mark - 原版 client.jar

/// 确保 versions/{mc}/{mc}.jar 存在且 sha1 匹配版本 JSON 的 downloads.client。
+ (BOOL)ensureVanillaClientJar:(NSString *)minecraftVersion
                    mainGameDir:(NSString *)mainGameDir
                      progress:(void (^)(double, NSString *))progress
                         error:(NSError **)error {
    if (minecraftVersion.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1176", nil)}];
        }
        return NO;
    }

    if (progress) progress(0.0, localize(@"i18n_str_1328", nil));

    NSDictionary *versionJSON = [self ensureVersionJSON:minecraftVersion mainGameDir:mainGameDir error:error];
    if (!versionJSON) return NO;

    NSDictionary *clientDownload = [versionJSON[@"downloads"] isKindOfClass:[NSDictionary class]]
        ? versionJSON[@"downloads"][@"client"] : nil;
    if (![clientDownload isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1178", nil), minecraftVersion]}];
        }
        return NO;
    }

    NSString *jarPath = [mainGameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@/%@.jar", minecraftVersion, minecraftVersion]];
    return [self downloadArtifactFromVersionEntry:clientDownload
                                           toPath:jarPath
                                          label:localize(@"i18n_str_1179", nil)
                                         progress:progress
                                            error:error];
}

#pragma mark - 版本 JSON / 下载

/// 确保 versions/{version}/{version}.json 存在（不存在则从版本清单下载），
/// 返回解析后的 JSON 字典。
+ (NSDictionary *)ensureVersionJSON:(NSString *)versionId
                        mainGameDir:(NSString *)mainGameDir
                              error:(NSError **)error {
    NSString *versionDir = [mainGameDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"versions/%@", versionId]];
    NSString *jsonPath = [versionDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.json", versionId]];

    if ([[NSFileManager defaultManager] fileExistsAtPath:jsonPath]) {
        NSDictionary *existing = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:jsonPath] options:0 error:nil];
        if ([existing isKindOfClass:[NSDictionary class]] && existing[@"downloads"]) {
            return existing;
        }
    }

    NSLog(@"[ForgeProcExec] Version JSON missing, downloading: %@", versionId);

    // 1. 版本清单
    NSString *downloadSource = getPrefObject(@"general.download_source");
    BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];
    NSArray<NSString *> *manifestURLs = useBMCLAPI
        ? @[kManifestURLBMCLAPI, kManifestURLOfficial]
        : @[kManifestURLOfficial, kManifestURLBMCLAPI];

    NSData *manifestData = nil;
    for (NSString *manifestURL in manifestURLs) {
        manifestData = [self downloadDataFromURLString:manifestURL error:nil];
        if (manifestData) break;
    }
    if (!manifestData) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1180", nil)}];
        }
        return nil;
    }

    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
    NSArray *versions = [manifest isKindOfClass:[NSDictionary class]] ? manifest[@"versions"] : nil;
    if (![versions isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1181", nil)}];
        }
        return nil;
    }

    // 2. 查找版本条目
    NSString *versionJSONURL = nil;
    for (NSDictionary *v in versions) {
        if ([v isKindOfClass:[NSDictionary class]] && [v[@"id"] isEqualToString:versionId]) {
            versionJSONURL = [v[@"url"] isKindOfClass:[NSString class]] ? v[@"url"] : nil;
            break;
        }
    }
    if (!versionJSONURL) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1182", nil), versionId]}];
        }
        return nil;
    }

    // 3. 下载版本 JSON（官方源 + BMCLAPI 镜像）
    NSArray<NSString *> *jsonURLs = useBMCLAPI
        ? @[[self bmclapiURLFor:versionJSONURL], versionJSONURL]
        : @[versionJSONURL, [self bmclapiURLFor:versionJSONURL]];

    NSData *jsonData = nil;
    for (NSString *url in jsonURLs) {
        if (!url) continue;
        jsonData = [self downloadDataFromURLString:url error:nil];
        if (jsonData) break;
    }
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1183", nil), versionId]}];
        }
        return nil;
    }

    // 4. 写盘
    NSError *dirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:versionDir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&dirError]) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1184", nil), versionDir, dirError.localizedDescription ?: @"unknown"]}];
        }
        return nil;
    }
    if (![jsonData writeToFile:jsonPath options:NSDataWritingAtomic error:error]) {
        return nil;
    }

    NSLog(@"[ForgeProcExec] Downloaded version JSON for %@ (%lu bytes)", versionId, (unsigned long)jsonData.length);
    return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
}

/// 通用 artifact 下载：按版本 JSON 条目（url/sha1/size）下载到 toPath。
/// 已存在且 sha1 匹配则跳过；下载后校验 sha1，失败删除文件并报错。
+ (BOOL)downloadArtifactFromVersionEntry:(NSDictionary *)entry
                                  toPath:(NSString *)destPath
                                   label:(NSString *)label
                                progress:(void (^)(double, NSString *))progress
                                   error:(NSError **)error {
    NSString *url = [entry[@"url"] isKindOfClass:[NSString class]] ? entry[@"url"] : nil;
    NSString *sha1 = [entry[@"sha1"] isKindOfClass:[NSString class]] ? entry[@"sha1"] : nil;
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorDownloadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1185", nil), label]}];
        }
        return NO;
    }

    // 已存在且 sha1 匹配 → 跳过
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath isDirectory:&isDir] && !isDir) {
        NSString *actual = [self sha1OfFile:destPath];
        if (actual && sha1 && [actual caseInsensitiveCompare:sha1] == NSOrderedSame) {
            NSLog(@"[ForgeProcExec] %@ already present and valid: %@", label, destPath);
            if (progress) progress(1.0, [NSString stringWithFormat:localize(@"i18n_str_1186", nil), label]);
            return YES;
        }
        // sha1 不匹配或无法校验（无期望值时保守重新下载）
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }

    // 官方源 + BMCLAPI 镜像
    NSString *downloadSource = getPrefObject(@"general.download_source");
    BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];
    NSArray<NSString *> *urls = useBMCLAPI
        ? @[[self bmclapiURLFor:url], url]
        : @[url, [self bmclapiURLFor:url]];

    NSError *lastError = nil;
    for (NSString *candidateURL in urls) {
        if (!candidateURL) continue;
        if (progress) progress(0.2, [NSString stringWithFormat:localize(@"i18n_str_1187", nil), label]);
        NSLog(@"[ForgeProcExec] Downloading %@ from %@", label, candidateURL);
        NSError *downloadError = nil;
        if ([self downloadFileFromURLString:candidateURL toPath:destPath error:&downloadError]) {
            // sha1 校验
            if (sha1.length > 0) {
                NSString *actual = [self sha1OfFile:destPath];
                if (!actual || [actual caseInsensitiveCompare:sha1] != NSOrderedSame) {
                    [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
                    if (error) {
                        *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                     code:ForgeProcessorExecutorErrorDownloadFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1188", nil), label, sha1, actual ?: localize(@"i18n_str_1189", nil)]}];
                    }
                    return NO;
                }
            }
            if (progress) progress(1.0, [NSString stringWithFormat:localize(@"i18n_str_1190", nil), label]);
            return YES;
        }
        lastError = downloadError;
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }

    if (error) {
        *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                     code:ForgeProcessorExecutorErrorDownloadFailed
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1191", nil), label, lastError.localizedDescription ?: localize(@"i18n_str_1192", nil)]}];
    }
    return NO;
}

/// piston-meta / piston-data / launchermeta → BMCLAPI 镜像域名
+ (NSString *)bmclapiURLFor:(NSString *)url {
    if (!url.length) return nil;
    NSString *mirrored = url;
    mirrored = [mirrored stringByReplacingOccurrencesOfString:@"piston-meta.mojang.com"
                                                   withString:@"bmclapi2.bangbang93.com"];
    mirrored = [mirrored stringByReplacingOccurrencesOfString:@"piston-data.mojang.com"
                                                   withString:@"bmclapi2.bangbang93.com"];
    mirrored = [mirrored stringByReplacingOccurrencesOfString:@"launchermeta.mojang.com"
                                                   withString:@"bmclapi2.bangbang93.com"];
    return mirrored;
}

#pragma mark - 解析工具（移植 ZL2 _ForgeLikeUtils.kt）

/// maven 坐标 → libraries 下相对路径。
/// 坐标格式：group:artifact:version[:classifier][@extension]
/// （对齐 ZL2 fromDescriptor().toPath()：@ext 只在最后一段解析，默认 jar）
+ (NSString *)libraryPathFromDescriptor:(NSString *)descriptor error:(NSError **)error {
    if (![descriptor isKindOfClass:[NSString class]] || descriptor.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1193", nil), descriptor]}];
        }
        return nil;
    }

    NSArray *parts = [descriptor componentsSeparatedByString:@":"];
    if (parts.count != 3 && parts.count != 4) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1193", nil), descriptor]}];
        }
        return nil;
    }

    NSMutableArray *segments = [parts mutableCopy];
    NSString *extension = @"jar";
    NSString *last = segments.lastObject;
    NSArray *lastSplit = [last componentsSeparatedByString:@"@"];
    if (lastSplit.count == 2) {
        segments[segments.count - 1] = lastSplit[0];
        extension = lastSplit[1];
    } else if (lastSplit.count > 2) {
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1194", nil), descriptor]}];
        }
        return nil;
    }

    NSString *groupId = [segments[0] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *artifactId = segments[1];
    NSString *version = segments[2];
    NSString *classifier = (segments.count >= 4) ? segments[3] : @"";

    NSString *rawName = classifier.length > 0
        ? [NSString stringWithFormat:@"%@-%@-%@", artifactId, version, classifier]
        : [NSString stringWithFormat:@"%@-%@", artifactId, version];
    NSString *fileName = [NSString stringWithFormat:@"%@.%@", rawName, extension];

    return [NSString stringWithFormat:@"%@/%@/%@/%@",
        [groupId stringByReplacingOccurrencesOfString:@"." withString:@"/"], artifactId, version, fileName];
}

/// 四类字面量解析（对齐 ZL2/HMCL parseLiteral）：
///   {VAR} → vars[VAR]（不存在则 nil）
///   'lit' → lit
///   [maven坐标] → librariesDir + libraryPathFromDescriptor
///   plain  → replaceTokens(vars) + plainConverter
+ (NSString *)parseLiteral:(NSString *)literal
              librariesDir:(NSString *)librariesDir
                     vars:(NSDictionary<NSString *, NSString *> *)vars
           plainConverter:(NSString * _Nullable (^)(NSString *plain))plainConverter
                     error:(NSError **)error {
    if (![literal isKindOfClass:[NSString class]] || literal.length == 0) return nil;

    if (literal.length >= 2 && [literal hasPrefix:@"{"] && [literal hasSuffix:@"}"]) {
        NSString *key = [literal substringWithRange:NSMakeRange(1, literal.length - 2)];
        return vars[key];
    }
    if (literal.length >= 2 && [literal hasPrefix:@"'"] && [literal hasSuffix:@"'"]) {
        return [literal substringWithRange:NSMakeRange(1, literal.length - 2)];
    }
    if (literal.length >= 2 && [literal hasPrefix:@"["] && [literal hasSuffix:@"]"]) {
        NSString *descriptor = [literal substringWithRange:NSMakeRange(1, literal.length - 2)];
        NSString *relative = [self libraryPathFromDescriptor:descriptor error:error];
        if (!relative) return nil;
        return [librariesDir stringByAppendingPathComponent:relative];
    }

    NSString *replaced = [self replaceTokens:vars value:literal error:error];
    if (!replaced) return nil;
    if (plainConverter) return plainConverter(replaced);
    return replaced;
}

/// --key value 解析（对齐 ZL2 parseOptions：值经 parseLiteral 解析，
/// 重复的 key 取最后一个，尾部孤立 key 记为空串）
+ (NSDictionary<NSString *, NSString *> *)parseOptions:(NSArray<NSString *> *)args
                                          librariesDir:(NSString *)librariesDir
                                                 vars:(NSDictionary *)vars
                                                error:(NSError **)error {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSString *optionName = nil;

    for (NSString *arg in args) {
        if (![arg isKindOfClass:[NSString class]]) continue;
        if ([arg hasPrefix:@"--"]) {
            if (optionName) options[optionName] = @"";
            optionName = [arg substringFromIndex:2];
        } else if (optionName) {
            NSString *value = [self parseLiteral:arg librariesDir:librariesDir vars:vars plainConverter:nil error:error];
            if (!value) {
                if (error && !*error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorInvalidProfile
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1195", nil), arg]}];
                }
                return nil;
            }
            options[optionName] = value;
            optionName = nil;
        }
    }
    if (optionName) options[optionName] = @"";
    return options;
}

/// token 替换（对齐 ZL2/HMCL replaceTokens）：
/// 支持 `\` 转义、`{key}`（vars 查找，缺失报错）、`'lit'` 字面量，
/// 未闭合的 `{` / `'` 与尾部孤立 `\` 报错。
+ (NSString *)replaceTokens:(NSDictionary<NSString *, NSString *> *)tokens
                      value:(NSString *)value
                      error:(NSError **)error {
    NSMutableString *buf = [NSMutableString string];
    NSUInteger x = 0;
    while (x < value.length) {
        unichar c = [value characterAtIndex:x];
        if (c == '\\') {
            if (x == value.length - 1) {
                if (error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorInvalidProfile
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1196", nil), value]}];
                }
                return nil;
            }
            x++;
            unichar escaped = [value characterAtIndex:x];
            [buf appendString:[NSString stringWithCharacters:&escaped length:1]];
        } else if (c == '{' || c == '\'') {
            NSMutableString *key = [NSMutableString string];
            NSUInteger y = x + 1;
            BOOL closed = NO;
            while (y < value.length) {
                unichar d = [value characterAtIndex:y];
                if (d == '\\') {
                    if (y == value.length - 1) {
                        if (error) {
                            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                         code:ForgeProcessorExecutorErrorInvalidProfile
                                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1196", nil), value]}];
                        }
                        return nil;
                    }
                    y++;
                    unichar escaped = [value characterAtIndex:y];
                    [key appendString:[NSString stringWithCharacters:&escaped length:1]];
                } else {
                    if ((c == '{' && d == '}') || (c == '\'' && d == '\'')) {
                        closed = YES;
                        break;
                    }
                    [key appendString:[NSString stringWithCharacters:&d length:1]];
                }
                y++;
            }
            if (!closed) {
                if (error) {
                    *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                 code:ForgeProcessorExecutorErrorInvalidProfile
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1197", nil), c, value]}];
                }
                return nil;
            }
            if (c == '\'') {
                [buf appendString:key];
            } else {
                NSString *token = tokens[key];
                if (!token) {
                    if (error) {
                        *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                     code:ForgeProcessorExecutorErrorInvalidProfile
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1198", nil), value, key]}];
                    }
                    return nil;
                }
                [buf appendString:token];
            }
            x = y;
        } else {
            [buf appendString:[NSString stringWithCharacters:&c length:1]];
        }
        x++;
    }
    return buf;
}

#pragma mark - 工具

/// 读取 jar 的 META-INF/MANIFEST.MF 中的 Main-Class。
+ (NSString *)mainClassFromJar:(NSString *)jarPath {
    NSError *openError = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jarPath error:&openError];
    if (!archive || openError) return nil;

    NSError *extractError = nil;
    NSData *manifestData = [archive extractDataFromFile:@"META-INF/MANIFEST.MF" error:&extractError];
    if (!manifestData) return nil;

    NSString *manifest = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
    if (!manifest) return nil;

    // Manifest 换行可能是 \r\n；逐段解析，Main-Class 理论上可跨行续行，
    // 实际的 processor jar 均为单行，这里只处理单行（解析不到则返回 nil）
    NSArray *lines = [manifest componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"Main-Class:"]) {
            NSString *value = [[trimmed substringFromIndex:@"Main-Class:".length]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return value.length > 0 ? value : nil;
        }
    }
    return nil;
}

/// 文件 SHA-1（小写十六进制），失败返回 nil。
+ (NSString *)sha1OfFile:(NSString *)path {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;

    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);

    @try {
        NSData *chunk = nil;
        static const NSUInteger kChunkSize = 1 << 16;
        while ((chunk = [handle readDataOfLength:kChunkSize]).length > 0) {
            CC_SHA1_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    } @catch (NSException *e) {
        [handle closeFile];
        return nil;
    } @finally {
        [handle closeFile];
    }

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

/// 读取 ForgeProcessorRunner 写的 status.json。
+ (NSDictionary *)readStatusFile:(NSString *)statusPath {
    NSData *data = [NSData dataWithContentsOfFile:statusPath];
    if (!data) return nil;
    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [status isKindOfClass:[NSDictionary class]] ? status : nil;
}

/// 按原版 MC 版本推断 processor 所需 Java 大版本
/// （对齐游戏运行时要求：1.20.5+/1.21+ → 21，1.17+ → 17，其余 8）
+ (int)inferJavaMajorForMinecraft:(NSString *)minecraftVersion {
    NSArray *parts = [minecraftVersion componentsSeparatedByString:@"."];
    if (parts.count >= 2 && [parts[0] integerValue] == 1) {
        NSInteger minor = [parts[1] integerValue];
        NSInteger patch = (parts.count >= 3) ? [parts[2] integerValue] : 0;
        if (minor >= 21) return 21;
        if (minor >= 20 && patch >= 5) return 21;
        if (minor >= 17) return 17;
        return 8;
    }
    return 17; // 未知格式保守取 17
}

#pragma mark - 网络下载（对齐 ForgeDirectInstaller 的 NSURLSession + 信号量模式）

+ (NSData *)downloadDataFromURLString:(NSString *)urlString error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 60.0;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];

    __block NSData *resultData = nil;
    __block NSError *resultError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
        if (taskError) {
            resultError = taskError;
        } else if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode >= 400) {
                resultError = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                                   code:statusCode
                                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld: %@", (long)statusCode, urlString]}];
            } else {
                resultData = data;
            }
        } else {
            resultData = data;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 70 * NSEC_PER_SEC));
    if (waitResult != 0) {
        [task cancel];
        if (error) {
            *error = [NSError errorWithDomain:ForgeProcessorExecutorErrorDomain
                                         code:NSURLErrorTimedOut
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:localize(@"i18n_str_1129", nil), urlString]}];
        }
        return nil;
    }

    if (error) *error = resultError;
    return resultData;
}

+ (BOOL)downloadFileFromURLString:(NSString *)urlString toPath:(NSString *)destPath error:(NSError **)error {
    if (error) *error = nil;

    // 创建目标目录
    NSString *destDir = [destPath stringByDeletingLastPathComponent];
    NSError *dirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:destDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&dirError];
    if (dirError) {
        if (error) {
            *error = dirError;
        }
        return NO;
    }

    NSData *data = [self downloadDataFromURLString:urlString error:error];
    if (!data || data.length == 0) {
        return NO;
    }
    return [data writeToFile:destPath options:NSDataWritingAtomic error:error];
}

@end
