#import "AFNetworking.h"
#import "ForgeInstallViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "BackgroundManager.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"

NSString * const ForgeInstallerFlowErrorDomain = @"ForgeInstallerFlowErrorDomain";

@interface ForgeVersionCell : UITableViewCell
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation ForgeVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.versionLabel = [[UILabel alloc] init];
        self.versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.versionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.versionLabel];
        
        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.numberOfLines = 1;
        self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.subtitleLabel];
        
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        [NSLayoutConstraint activateConstraints:@[
            [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.versionLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:2],
            [self.subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    }
    return self;
}

@end

@interface MinecraftVersionHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;
@property (nonatomic, strong) UIButton *expandCollapseButton;
@property (nonatomic, assign) BOOL isExpanded;
@end

@implementation MinecraftVersionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *containerView = [[UIView alloc] init];
        // 适配自定义启动器背景：透明背景让底层毛玻璃透出
        containerView.backgroundColor = [UIColor clearColor];
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:containerView];
        
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [containerView addSubview:self.titleLabel];
        
        self.chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        self.chevronImageView.tintColor = [UIColor systemGrayColor];
        self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
        [containerView addSubview:self.chevronImageView];
        
        self.expandCollapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.expandCollapseButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.expandCollapseButton.backgroundColor = [UIColor clearColor];
        [containerView addSubview:self.expandCollapseButton];
        
        [NSLayoutConstraint activateConstraints:@[
            [containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronImageView.leadingAnchor constant:-16]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.chevronImageView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16],
            [self.chevronImageView.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
            [self.chevronImageView.widthAnchor constraintEqualToConstant:20],
            [self.chevronImageView.heightAnchor constraintEqualToConstant:20]
        ]];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.expandCollapseButton.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
            [self.expandCollapseButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
            [self.expandCollapseButton.topAnchor constraintEqualToAnchor:containerView.topAnchor],
            [self.expandCollapseButton.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
        ]];
    }
    return self;
}

- (void)setIsExpanded:(BOOL)isExpanded {
    _isExpanded = isExpanded;
    
    // Animate chevron rotation
    [UIView animateWithDuration:0.3 animations:^{
        self.chevronImageView.transform = isExpanded ? 
            CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
    }];
}

@end

@interface ForgeInstallViewController()<NSXMLParserDelegate>
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) NSString *searchText;
@property(atomic) AFURLSessionManager *afManager;
// redesign-download-ui Phase 4 Task 4.2：移除 WFWorkflowProgressView（私有框架，审核风险），
// installer jar 下载进度改由 DownloadTaskManager 统一任务驱动
@property(nonatomic, strong) NSString *currentVendor;
@property(nonatomic, strong) NSString *installerTaskId;

@property(nonatomic) NSDictionary *endpoints;
@property(nonatomic) NSMutableArray<NSNumber *> *visibilityList;
@property(nonatomic) NSMutableArray<NSString *> *versionList;
@property(nonatomic) NSMutableArray<NSMutableArray *> *forgeList;
@property(nonatomic) NSMutableArray<NSMutableArray *> *filteredForgeList;
@property(nonatomic, assign) BOOL isVersionElement;
@property(nonatomic, strong) NSMutableString *currentVersionValue;
@property(nonatomic, strong) NSIndexPath *currentDownloadIndexPath;
@property(atomic, assign) BOOL isDataLoading;
@property(nonatomic, strong) NSLock *dataLock;

// Performance optimizations
@property(nonatomic, strong) NSTimer *searchDebounceTimer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *displayNameCache;
@property(nonatomic, strong) dispatch_queue_t searchQueue;

// Scheme selection
@property(nonatomic, copy) NSString *selectedVersionString;
@end

@implementation ForgeInstallViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // FCL 风格：适配自定义启动器背景，应用毛玻璃到导航栏 + 透明化视图
    if (self.navigationController) {
        [[BackgroundManager sharedManager] applyEffectToNavigationBar:self.navigationController.navigationBar];
    }
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0;
    }

    // 使用 Never 而非 Automatic：Automatic 会自动为导航栏/状态栏添加顶部 contentInset，
    // 在透明导航栏下形成可见的"空白条"。配合 edgesForExtendedLayout = UIRectEdgeAll
    // 让 tableView 延伸到导航栏下方，与毛玻璃导航栏视觉融合。
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    self.extendedLayoutIncludesOpaqueBars = YES;
    self.edgesForExtendedLayout = UIRectEdgeAll;
    
    [self.tableView registerClass:[ForgeVersionCell class] forCellReuseIdentifier:@"ForgeVersionCell"];
    [self.tableView registerClass:[MinecraftVersionHeaderView class] forHeaderFooterViewReuseIdentifier:@"MinecraftVersionHeader"];
    
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[@"Forge", @"NeoForge"]];
    segment.selectedSegmentIndex = self.isNeoForge ? 1 : 0;
    [segment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = segment;
    self.currentVendor = self.isNeoForge ? @"NeoForge" : @"Forge";

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = (id<UISearchResultsUpdating>)self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search versions";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshVersions) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    self.endpoints = @{
        @"Forge": @{
            @"installer": @"https://maven.minecraftforge.net/net/minecraftforge/forge/%1$@/forge-%1$@-installer.jar",
            @"metadata": @"https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
        },
        @"NeoForge": @{
            @"installer": @"https://maven.neoforged.net/releases/net/neoforged/neoforge/%1$@/neoforge-%1$@-installer.jar",
            @"metadata": @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge"
        }
    };
    
    self.visibilityList = [NSMutableArray new];
    self.versionList = [NSMutableArray new];
    self.forgeList = [NSMutableArray new];
    self.filteredForgeList = [NSMutableArray new];
    self.currentVersionValue = [NSMutableString new];
    self.isDataLoading = NO;
    self.dataLock = [[NSLock alloc] init];
    
    self.displayNameCache = [NSMutableDictionary new];
    self.searchQueue = dispatch_queue_create("com.amethyst.forge.search", DISPATCH_QUEUE_SERIAL);

    if (self.presetVersionString.length > 0) {
        // 由上游（LoaderSelectionViewController）已选好版本，跳过版本列表加载，直接进入方案选择
        self.selectedVersionString = self.presetVersionString;
        // 切换到就绪状态，避免列表显示 Loading...
        self.isDataLoading = NO;
        [self.tableView reloadData];
        // weakSelf 防御：用户在 dispatch_async 期间快速返回（pop VC）时避免 present 作用于已不在栈中的 VC
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && [strongSelf.navigationController.viewControllers containsObject:strongSelf]) {
                [strongSelf presentSchemeSelection];
            }
        });
    } else {
        [self loadMetadataFromVendor:self.currentVendor];
    }
}

- (void)presentSchemeSelection {
    if (!self.selectedVersionString) return;
    ForgeInstallSchemeViewController *schemeVC = [[ForgeInstallSchemeViewController alloc] init];
    schemeVC.delegate = self;
    schemeVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:schemeVC animated:YES completion:nil];
}

- (void)dealloc {
    [self.searchDebounceTimer invalidate];
    self.searchDebounceTimer = nil;
}

- (void)actionCancelDownload {
    if (self.currentDownloadIndexPath) {
        [self resetCellAppearance:self.currentDownloadIndexPath];
        self.currentDownloadIndexPath = nil;
    }
    [self.afManager invalidateSessionCancelingTasks:YES resetSession:NO];
    // redesign-download-ui Phase 4：同步取消统一任务管理器中的 installer 下载任务
    if (self.installerTaskId) {
        [[DownloadTaskManager sharedManager] cancelTaskWithId:self.installerTaskId];
        self.installerTaskId = nil;
    }
    showDialog(@"Download Cancelled", @"The download has been cancelled.");
}

- (void)resetCellAppearance:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (void)actionClose {
    if (self.completionHandler) {
        NSError *cancelError = [NSError errorWithDomain:ForgeInstallerFlowErrorDomain
                                                   code:ForgeInstallerFlowErrorCodeCancelled
                                               userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1135", nil)}];
        self.completionHandler(NO, nil, cancelError);
    }
    // 兼容两种呈现方式：push 到中间内容区时用 pop，模态呈现时用 dismiss
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)segmentChanged:(UISegmentedControl *)segment {
    [self.searchDebounceTimer invalidate];
    self.searchDebounceTimer = nil;

    if (self.searchController.isActive) {
        [self.searchController dismissViewControllerAnimated:YES completion:nil];
    }
    
    NSString *vendor = [segment titleForSegmentAtIndex:segment.selectedSegmentIndex];
    self.currentVendor = vendor;
    [self loadMetadataFromVendor:vendor];
}

- (void)refreshVersions {
    [self loadMetadataFromVendor:self.currentVendor];
}

- (void)loadMetadataFromVendor:(NSString *)vendor {
    [self switchToLoadingState];
    
    self.isDataLoading = YES;
    
    [self.dataLock lock];
    [self.visibilityList removeAllObjects];
    [self.versionList removeAllObjects];
    [self.forgeList removeAllObjects];
    [self.filteredForgeList removeAllObjects];
    [self.displayNameCache removeAllObjects];
    [self.dataLock unlock];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
    
    if ([vendor isEqualToString:@"NeoForge"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *downloadSource = getPrefObject(@"general.download_source");
            BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];

            // 内部方法：从指定源获取版本列表
            void (^fetchFromSource)(BOOL) = ^(BOOL useBMCL) {
                NSString *neoURLString = useBMCL ?
                    @"https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/neoforge" :
                    @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge";
                NSString *legacyURLString = useBMCL ?
                    @"https://bmclapi2.bangbang93.com/neoforge/meta/api/maven/details/releases/net/neoforged/forge" :
                    @"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/forge";

                dispatch_group_t group = dispatch_group_create();
                NSMutableArray *allVersions = [NSMutableArray new];
                NSLock *versionsLock = [[NSLock alloc] init];

                dispatch_group_enter(group);
                NSURL *neoURL = [NSURL URLWithString:neoURLString];
                NSURLSessionDataTask *neoTask = [[NSURLSession sharedSession] dataTaskWithURL:neoURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (!error && data) {
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        if (json) {
                            if (useBMCL) {
                                NSArray *files = json[@"files"];
                                if ([files isKindOfClass:[NSArray class]]) {
                                    [versionsLock lock];
                                    for (NSDictionary *file in files) {
                                        if (![file isKindOfClass:[NSDictionary class]]) continue;
                                        NSString *type = file[@"type"];
                                        NSString *name = file[@"name"];
                                        if ([type isEqualToString:@"DIRECTORY"] && name && ![name.lowercaseString containsString:@"maven"]) {
                                            [allVersions addObject:name];
                                        }
                                    }
                                    [versionsLock unlock];
                                }
                            } else {
                                NSArray *versions = json[@"versions"];
                                if ([versions isKindOfClass:[NSArray class]]) {
                                    [versionsLock lock];
                                    [allVersions addObjectsFromArray:versions];
                                    [versionsLock unlock];
                                }
                            }
                        }
                    } else {
                        NSLog(@"[NeoForge] Fetch %@ failed: %@", useBMCL ? @"BMCLAPI" : @"official", error.localizedDescription ?: @"no data");
                    }
                    dispatch_group_leave(group);
                }];
                [neoTask resume];

                dispatch_group_enter(group);
                NSURL *legacyURL = [NSURL URLWithString:legacyURLString];
                NSURLSessionDataTask *legacyTask = [[NSURLSession sharedSession] dataTaskWithURL:legacyURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (!error && data) {
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                        if (json) {
                            if (useBMCL) {
                                NSArray *files = json[@"files"];
                                if ([files isKindOfClass:[NSArray class]]) {
                                    [versionsLock lock];
                                    for (NSDictionary *file in files) {
                                        if (![file isKindOfClass:[NSDictionary class]]) continue;
                                        NSString *type = file[@"type"];
                                        NSString *name = file[@"name"];
                                        if ([type isEqualToString:@"DIRECTORY"] && name && ![name.lowercaseString containsString:@"maven"]) {
                                            [allVersions addObject:name];
                                        }
                                    }
                                    [versionsLock unlock];
                                }
                            } else {
                                NSArray *versions = json[@"versions"];
                                if ([versions isKindOfClass:[NSArray class]]) {
                                    [versionsLock lock];
                                    [allVersions addObjectsFromArray:versions];
                                    [versionsLock unlock];
                                }
                            }
                        }
                    } else {
                        NSLog(@"[NeoForge] Fetch legacy %@ failed: %@", useBMCL ? @"BMCLAPI" : @"official", error.localizedDescription ?: @"no data");
                    }
                    dispatch_group_leave(group);
                }];
                [legacyTask resume];

                dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

                if (allVersions.count > 0) {
                    for (NSString *version in allVersions) {
                        [self addVersionToList:version];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self finalizeVersionList];
                    });
                } else {
                    if (useBMCL == useBMCLAPI) {
                        NSLog(@"[NeoForge] Primary source (%@) failed, falling back to %@", useBMCLAPI ? @"BMCLAPI" : @"official", useBMCLAPI ? @"official" : @"BMCLAPI");
                        fetchFromSource(!useBMCLAPI);
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.isDataLoading = NO;
                            [self.refreshControl endRefreshing];
                            showDialog(localize(@"Error", nil), localize(@"i18n_str_1318", nil));
                            [self actionClose];
                        });
                    }
                }
            };

            fetchFromSource(useBMCLAPI);
        });
    } else {
        // Forge 分支
        //
        // 性能优化（参考 ZL2 / PCL2）：
        //   1. 当 gameVersion 已指定时（DownloadViewController 传入），优先使用 BMCLAPI 按版本
        //      JSON 接口 /forge/minecraft/<mcVersion>，只返回该 MC 版本的 Forge 列表，数据量极小
        //      （几十 KB vs 全量 maven-metadata.xml 的几 MB），解析为 JSON 也比 NSXMLParser 快。
        //   2. 全量 maven-metadata.xml 流程保留作为 fallback（gameVersion 为空或快速路径失败时），
        //      并改为"主源优先"串行回退：先等主源（用户偏好源），主源拿到有效 XML 立即解析返回；
        //      主源失败/无匹配再请求备用源，避免之前 dispatch_group_wait 同步等双源最多 90s 的慢路径。
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *downloadSource = getPrefObject(@"general.download_source");
            BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];
            NSString *userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

            // 收尾：成功则 finalize，失败则提示并关闭
            void (^finishSuccess)(void) = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finalizeVersionList];
                });
            };
            void (^finishFailure)(NSString *) = ^(NSString *reason) {
                NSLog(@"[Forge] All sources failed: %@. versionList.count=%lu",
                      reason ?: @"unknown", (unsigned long)self.versionList.count);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.isDataLoading = NO;
                    [self.refreshControl endRefreshing];
                    showDialog(localize(@"Error", nil), localize(@"i18n_str_1319", nil));
                    [self actionClose];
                });
            };

            // ========== 快速路径：BMCLAPI 按版本 JSON 接口 ==========
            // 接口：https://bmclapi2.bangbang93.com/forge/minecraft/<mcVersion>
            // 返回：[{ "version": "47.2.0", "branch": null, "modified": "...", "files": [...] }, ...]
            // 每条对应一个 Forge 版本，version 即 Forge 版本号，拼接成 <mcVersion>-<version> 喂给 addVersionToList
            if (self.gameVersion.length > 0) {
                NSString *mcVersion = self.gameVersion;
                NSString *encodedMC = [mcVersion stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
                NSString *bmclJSONURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/forge/minecraft/%@", encodedMC];

                __block NSData *jsonData = nil;
                __block NSError *jsonError = nil;
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                NSMutableURLRequest *jsonReq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:bmclJSONURL]];
                jsonReq.timeoutInterval = 20.0;
                [jsonReq setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                NSURLSessionDataTask *jsonTask = [[NSURLSession sharedSession] dataTaskWithRequest:jsonReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    jsonData = data;
                    jsonError = error;
                    dispatch_semaphore_signal(sem);
                }];
                [jsonTask resume];
                dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC));

                if (jsonData && !jsonError) {
                    NSArray *tokens = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                    if ([tokens isKindOfClass:[NSArray class]] && tokens.count > 0) {
                        NSMutableArray *collected = [NSMutableArray new];
                        for (NSDictionary *token in tokens) {
                            if (![token isKindOfClass:[NSDictionary class]]) continue;
                            NSString *ver = token[@"version"];
                            id branchRaw = token[@"branch"];
                            // branch 可能为 NSNull（JSON null），需排除后再当字符串用
                            NSString *branch = [branchRaw isKindOfClass:[NSString class]] ? branchRaw : nil;
                            if (!ver || ![ver isKindOfClass:[NSString class]] || ver.length == 0) continue;
                            // 拼成 Forge 标准命名 <mcVersion>-<version>[-<branch>]
                            NSString *fullVersion = branch.length > 0
                                ? [NSString stringWithFormat:@"%@-%@-%@", mcVersion, ver, branch]
                                : [NSString stringWithFormat:@"%@-%@", mcVersion, ver];
                            [collected addObject:fullVersion];
                        }
                        if (collected.count > 0) {
                            for (NSString *v in collected) {
                                [self addVersionToList:v];
                            }
                            NSLog(@"[Forge] Fast path success: BMCLAPI JSON fetched %@ versions (MC %@)", @(collected.count), mcVersion);
                            finishSuccess();
                            return;
                        }
                    }
                }
                NSLog(@"[Forge] Fast path failed (data=%@ error=%@), falling back to full maven-metadata.xml",
                      jsonData ? [NSString stringWithFormat:@"%luB", (unsigned long)jsonData.length] : @"nil",
                      jsonError.localizedDescription ?: @"nil");
            }

            // ========== fallback：全量 maven-metadata.xml（主源优先 + 串行回退）==========
            NSString *bmclURLString = @"https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/maven-metadata.xml";
            NSString *officialURLString = @"https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml";

            // 校验响应是 XML 而非 HTML 错误页（BMCLAPI 限流 429 / 5xx 时可能返回 HTML）
            BOOL (^isValidXML)(NSData *) = ^(NSData *data) {
                if (!data || data.length == 0) return NO;
                NSUInteger previewLen = MIN(256, data.length);
                NSString *preview = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, previewLen)] encoding:NSUTF8StringEncoding];
                if (!preview) return NO;
                NSString *lower = preview.lowercaseString;
                if ([lower containsString:@"<html"] || [lower containsString:@"<!doctype"] || [lower containsString:@"<head"]) {
                    return NO;
                }
                if (![preview containsString:@"<metadata"]) return NO;
                return YES;
            };

            // 同步拉取单个源（带超时），返回 data 或 nil
            NSData *(^fetchSource)(NSString *) = ^NSData *(NSString *urlString) {
                __block NSData *result = nil;
                dispatch_semaphore_t s = dispatch_semaphore_create(0);
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
                req.timeoutInterval = 30.0;
                [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (data && !error) result = data;
                    dispatch_semaphore_signal(s);
                }];
                [task resume];
                dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC));
                return result;
            };

            // 解析指定数据并收集匹配 gameVersion 的 Forge 版本
            BOOL (^parseAndCollect)(NSData *) = ^(NSData *data) {
                if (!isValidXML(data)) return NO;
                NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
                parser.delegate = self;
                self.currentVersionValue = [NSMutableString new];
                BOOL parseOK = [parser parse];
                if (parseOK && self.versionList.count > 0) {
                    return YES;
                }
                NSLog(@"[Forge] Parse returned no matching versions (parseOK=%d, parserError=%@)",
                      parseOK, parser.parserError.localizedDescription ?: @"none");
                return NO;
            };

            // 主源优先：拉主源 → 解析；失败/无匹配再拉备用源解析
            NSString *primaryURL = useBMCLAPI ? bmclURLString : officialURLString;
            NSString *secondaryURL = useBMCLAPI ? officialURLString : bmclURLString;
            NSString *primaryName = useBMCLAPI ? @"BMCLAPI" : @"official";
            NSString *secondaryName = useBMCLAPI ? @"official" : @"BMCLAPI";

            BOOL success = NO;
            NSData *primaryData = fetchSource(primaryURL);
            if (primaryData) {
                success = parseAndCollect(primaryData);
                if (success) {
                    NSLog(@"[Forge] Loaded versions from primary source (%@)", primaryName);
                }
            }

            NSData *secondaryData = nil;
            if (!success && self.versionList.count == 0) {
                NSLog(@"[Forge] Primary source (%@) failed/empty, falling back to %@", primaryName, secondaryName);
                secondaryData = fetchSource(secondaryURL);
                if (secondaryData) {
                    success = parseAndCollect(secondaryData);
                    if (success) {
                        NSLog(@"[Forge] Loaded versions from fallback source (%@)", secondaryName);
                    }
                }
            }

            if (success && self.versionList.count > 0) {
                finishSuccess();
            } else {
                finishFailure([NSString stringWithFormat:@"primary(%@)=%@, secondary(%@)=%@",
                               primaryName, primaryData ? [NSString stringWithFormat:@"%luB", (unsigned long)primaryData.length] : @"nil",
                               secondaryName, secondaryData ? [NSString stringWithFormat:@"%luB", (unsigned long)secondaryData.length] : @"nil"]);
            }
        });
    }
}

- (void)switchToLoadingState {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:indicator];
    [indicator startAnimating];
    self.navigationController.modalInPresentation = YES;
}

- (void)switchToReadyState {
    UIActivityIndicatorView *indicator = (id)self.navigationItem.rightBarButtonItem.customView;
    [indicator stopAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = NO;
    [self.refreshControl endRefreshing];
}

#pragma mark - Search Results Updating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    if (self.isDataLoading) return;
    
    NSString *searchText = searchController.searchBar.text;
    [self.searchDebounceTimer invalidate];
    self.searchDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                                 target:self
                                                               selector:@selector(performSearch:)
                                                               userInfo:searchText
                                                                repeats:NO];
}

- (void)performSearch:(NSTimer *)timer {
    NSString *searchText = timer.userInfo;
    self.searchText = searchText;
    
    if (searchText.length == 0) {
        [self.dataLock lock];
        [self.filteredForgeList removeAllObjects];
        for (NSMutableArray *forgeVersions in self.forgeList) {
            [self.filteredForgeList addObject:[forgeVersions mutableCopy]];
        }
        [self.dataLock unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
        return;
    }
    
    dispatch_async(self.searchQueue, ^{
        [self.dataLock lock];
        NSArray *forgeListSnapshot = [self.forgeList copy];
        NSString *vendor = [self.currentVendor copy];
        [self.dataLock unlock];
        
        NSMutableArray *newFilteredList = [NSMutableArray new];
        NSMutableIndexSet *sectionsWithResults = [NSMutableIndexSet new];
        
        for (NSUInteger i = 0; i < forgeListSnapshot.count; i++) {
            NSArray *sectionVersions = forgeListSnapshot[i];
            NSMutableArray *filteredSectionVersions = [NSMutableArray new];
            
            for (NSString *version in sectionVersions) {
                NSString *displayName = [self getCachedDisplayName:version forVendor:vendor];
                if ([displayName localizedCaseInsensitiveContainsString:searchText]) {
                    [filteredSectionVersions addObject:version];
                }
            }
            
            [newFilteredList addObject:filteredSectionVersions];
            if (filteredSectionVersions.count > 0) {
                [sectionsWithResults addIndex:i];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.dataLock lock];
            [self.filteredForgeList removeAllObjects];
            [self.filteredForgeList addObjectsFromArray:newFilteredList];
            [sectionsWithResults enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                if (idx < self.visibilityList.count) {
                    self.visibilityList[idx] = @YES;
                }
            }];
            [self.dataLock unlock];
            [self.tableView reloadData];
        });
    });
}

- (NSString *)getCachedDisplayName:(NSString *)version forVendor:(NSString *)vendor {
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%@", vendor, version];
    NSString *cached = self.displayNameCache[cacheKey];
    if (cached) return cached;
    
    NSString *displayName = [self getDisplayName:version];
    self.displayNameCache[cacheKey] = displayName;
    return displayName;
}

#pragma mark - Version Display Methods

- (NSString *)getDisplayName:(NSString *)version {
    if ([self.currentVendor isEqualToString:@"NeoForge"]) {
        NSString *mcVersion = [self extractMinecraftVersionFromNeoForgeVersion:version];
        if (![mcVersion isEqualToString:@"Unknown"]) {
            if ([self isSnapshotVersion:mcVersion] || [mcVersion containsString:@"w"]) {
                return [NSString stringWithFormat:@"NeoForge %@ (Snapshot %@)", version, mcVersion];
            } else {
                return [NSString stringWithFormat:@"NeoForge %@ (Minecraft %@)", version, mcVersion];
            }
        } else {
            return [NSString stringWithFormat:@"NeoForge %@", version];
        }
    } else {
        NSString *mcVersion = [self extractMinecraftVersionFromForgeVersion:version];
        NSRange hyphenRange = [version rangeOfString:@"-"];
        if (hyphenRange.location != NSNotFound && ![mcVersion isEqualToString:@"Unknown"]) {
            NSString *forgeVersion = [version substringFromIndex:hyphenRange.location + 1];
            if ([self isSnapshotVersion:mcVersion]) {
                return [NSString stringWithFormat:@"Forge %@ (Snapshot %@)", forgeVersion, mcVersion];
            } else {
                return [NSString stringWithFormat:@"Forge %@ (Minecraft %@)", forgeVersion, mcVersion];
            }
        } else {
            return version;
        }
    }
}

- (NSString *)extractMinecraftVersionFromForgeVersion:(NSString *)version {
    NSRange hyphenRange = [version rangeOfString:@"-"];
    if (hyphenRange.location != NSNotFound) {
        NSString *mcPortion = [version substringToIndex:hyphenRange.location];
        if ([self isSnapshotVersion:mcPortion]) {
            return mcPortion;
        }
        // Task185：正则扩展——旧 "^1\\." 只认旧纪元，26.x 起复合版本首段
        // 无 "1." 前缀（"26.3-66.0.5" → "26.3"），原被误判 "Unknown"。
        // 数字点分形态全接受（复合版本的首段按定义就是 MC 版本号）。
        NSRegularExpression *mcRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d+(\\.\\d+)*$" options:0 error:nil];
        NSRange fullRange = NSMakeRange(0, mcPortion.length);
        if ([mcRegex firstMatchInString:mcPortion options:0 range:fullRange]) {
            return mcPortion;
        }
    }
    return @"Unknown";
}

- (NSString *)extractMinecraftVersionFromNeoForgeVersion:(NSString *)version {
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
        // 仅当 part 匹配快照版本号格式（如 25w14craftmine）才返回，避免误判
        NSRegularExpression *snapshotRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d{2}w\\d{2}[a-z]+"
                                                                                       options:0
                                                                                         error:nil];
        if ([snapshotRegex firstMatchInString:part options:0 range:NSMakeRange(0, part.length)]) {
            return part;
        }
        return @"Unknown";
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
            // Task185：26.x 新纪元修正。NeoForge 版本 = <MC 版本> + <build>，
            // MC 版本号本身从 26 起去掉 "1." 前缀：
            //   21.1.5      → MC 1.21.1（旧纪元，前缀 "1."）
            //   20.2.88     → MC 1.20.2（同上）
            //   26.3.7      → MC 26.3（新纪元，无前缀）
            //   26.1.2.71   → MC 26.1.2（新纪元，四分量）
            //   26.3.0.5    → MC 26.3.0（新纪元，四分量）
            // 统一规则：去掉最后一个点分量（build 号），余下即 MC 版本；
            // major ≤ 25 补 "1." 前缀，major ≥ 26 直接用。旧代码固定取
            // 前两段拼 "1.%@.%@"，26.x 全部解析成 "1.26.3" = 找不到的根源。
            if (components.count >= 3) {
                NSArray *mcParts = [components subarrayWithRange:NSMakeRange(0, components.count - 1)];
                NSString *mcVersion = [mcParts componentsJoinedByString:@"."];
                return (majorVal >= 26) ? mcVersion
                                        : [NSString stringWithFormat:@"1.%@", mcVersion];
            }
            // 两分量形态（罕见）：直接用前两段
            return (majorVal >= 26) ? [NSString stringWithFormat:@"%@.%@", major, minor]
                                    : [NSString stringWithFormat:@"1.%@.%@", major, minor];
        }
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+\\.\\d+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (match) {
        return [NSString stringWithFormat:@"1.%@", [version substringWithRange:match.range]];
    }

    return @"Unknown";
}

- (BOOL)isSnapshotVersion:(NSString *)version {
    if (version.length == 0) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?i)^\\d{2}w\\d{2}[a-z]$" options:0 error:nil];
    NSRange fullRange = NSMakeRange(0, version.length);
    return [regex firstMatchInString:version options:0 range:fullRange] != nil;
}

- (UIColor *)getColorForVersionType:(NSString *)version {
    if ([version containsString:@"recommended"]) {
        return [UIColor systemGreenColor];
    } else if ([version containsString:@"beta"] || [version containsString:@"-beta"]) {
        return [UIColor systemOrangeColor];
    } else if ([version containsString:@"alpha"] || [version containsString:@"-alpha"]) {
        return [UIColor systemRedColor];
    } else {
        return [UIColor systemBlueColor];
    }
}

- (NSString *)getLabelForVersionType:(NSString *)version {
    if ([version containsString:@"recommended"]) {
        return @"Recommended";
    } else if ([version containsString:@"beta"] || [version containsString:@"-beta"]) {
        return @"Beta";
    } else if ([version containsString:@"alpha"] || [version containsString:@"-alpha"]) {
        return @"Alpha";
    } else {
        return @"Release";
    }
}

- (BOOL)isNumeric:(NSString *)string {
    if (!string || string.length == 0) return NO;
    NSCharacterSet *nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonNumbers].location == NSNotFound;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.isDataLoading) return 0;
    [self.dataLock lock];
    NSInteger count = self.versionList.count;
    [self.dataLock unlock];
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isDataLoading) return 0;
    
    [self.dataLock lock];
    if (section >= self.visibilityList.count) {
        [self.dataLock unlock];
        return 0;
    }
    
    NSInteger rows = 0;
    if (self.visibilityList[section].boolValue) {
        if (self.searchController.isActive) {
            if (section < self.filteredForgeList.count) {
                rows = self.filteredForgeList[section].count;
            }
        } else {
            if (section < self.forgeList.count) {
                rows = self.forgeList[section].count;
            }
        }
    }
    [self.dataLock unlock];
    return rows;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MinecraftVersionHeaderView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"MinecraftVersionHeader"];
    
    if (self.isDataLoading) {
        headerView.titleLabel.text = @"Loading...";
        headerView.isExpanded = NO;
        headerView.expandCollapseButton.tag = section;
        [headerView.expandCollapseButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        return headerView;
    }
    
    [self.dataLock lock];
    if (section >= self.versionList.count || self.versionList.count == 0) {
        [self.dataLock unlock];
        headerView.titleLabel.text = @"Loading...";
        headerView.isExpanded = NO;
        headerView.expandCollapseButton.tag = section;
        [headerView.expandCollapseButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        return headerView;
    }
    
    NSString *mcVersion = self.versionList[section];
    // Task185：26.x 新纪元分区头也带 Minecraft 前缀（旧代码只认 "1." 开头）
    BOOL ame185_numericHead = mcVersion.length > 0 &&
        [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[mcVersion characterAtIndex:0]];
    if ([mcVersion hasPrefix:@"1."] || ame185_numericHead) {
        headerView.titleLabel.text = [NSString stringWithFormat:@"Minecraft %@", mcVersion];
    } else {
        headerView.titleLabel.text = mcVersion;
    }
    
    if (section < self.visibilityList.count) {
        headerView.isExpanded = self.visibilityList[section].boolValue;
    } else {
        headerView.isExpanded = NO;
    }
    [self.dataLock unlock];
    
    headerView.expandCollapseButton.tag = section;
    [headerView.expandCollapseButton addTarget:self action:@selector(toggleSection:) forControlEvents:UIControlEventTouchUpInside];
    
    return headerView;
}

- (void)toggleSection:(UIButton *)sender {
    if (self.isDataLoading) return;
    NSInteger section = sender.tag;
    
    [self.dataLock lock];
    if (section >= 0 && section < self.visibilityList.count && self.versionList.count > section) {
        self.visibilityList[section] = @(!self.visibilityList[section].boolValue);
        [self.dataLock unlock];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.dataLock unlock];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 60.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 56.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ForgeVersionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ForgeVersionCell" forIndexPath:indexPath];
    
    if (self.isDataLoading) {
        cell.versionLabel.text = @"Loading...";
        cell.subtitleLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    [self.dataLock lock];
    BOOL outOfBounds = NO;
    if (self.searchController.isActive) {
        outOfBounds = (indexPath.section >= self.filteredForgeList.count || 
                      (indexPath.section < self.filteredForgeList.count && 
                       indexPath.row >= self.filteredForgeList[indexPath.section].count));
    } else {
        outOfBounds = (indexPath.section >= self.forgeList.count || 
                      (indexPath.section < self.forgeList.count && 
                       indexPath.row >= self.forgeList[indexPath.section].count));
    }
    
    if (outOfBounds) {
        [self.dataLock unlock];
        cell.versionLabel.text = @"Loading...";
        cell.subtitleLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    NSString *version = self.searchController.isActive ? 
        self.filteredForgeList[indexPath.section][indexPath.row] : 
        self.forgeList[indexPath.section][indexPath.row];
    version = [version copy];
    NSString *vendor = [self.currentVendor copy];
    [self.dataLock unlock];
    
    NSString *displayName = [self getCachedDisplayName:version forVendor:vendor];
    cell.versionLabel.text = displayName;
    
    NSString *typeLabel = [self getLabelForVersionType:version];
    UIColor *typeColor = [self getColorForVersionType:version];
    cell.subtitleLabel.text = typeLabel;
    cell.subtitleLabel.textColor = typeColor;
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (self.isDataLoading) return;
    
    [self.dataLock lock];
    BOOL outOfBounds = NO;
    if (self.searchController.isActive) {
        outOfBounds = (indexPath.section >= self.filteredForgeList.count || 
                      (indexPath.section < self.filteredForgeList.count && 
                       indexPath.row >= self.filteredForgeList[indexPath.section].count));
    } else {
        outOfBounds = (indexPath.section >= self.forgeList.count || 
                      (indexPath.section < self.forgeList.count && 
                       indexPath.row >= self.forgeList[indexPath.section].count));
    }
    
    if (outOfBounds) {
        [self.dataLock unlock];
        return;
    }
    
    NSString *versionString = self.searchController.isActive ?
        self.filteredForgeList[indexPath.section][indexPath.row] :
        self.forgeList[indexPath.section][indexPath.row];
    versionString = [versionString copy];
    [self.dataLock unlock];

    self.selectedVersionString = versionString;

    ForgeInstallSchemeViewController *schemeVC = [[ForgeInstallSchemeViewController alloc] init];
    schemeVC.delegate = self;
    schemeVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:schemeVC animated:YES completion:nil];
}

#pragma mark - ForgeInstallSchemeViewControllerDelegate

- (void)schemeViewController:(ForgeInstallSchemeViewController *)controller didSelectScheme:(NSInteger)scheme {
    if (scheme < 0) {
        // 用户点关闭按钮取消，回调失败避免上游永久阻塞
        if (self.completionHandler) {
            NSError *cancelError = [NSError errorWithDomain:ForgeInstallerFlowErrorDomain
                                                       code:ForgeInstallerFlowErrorCodeCancelled
                                                   userInfo:@{NSLocalizedDescriptionKey: localize(@"i18n_str_1138", nil)}];
            self.completionHandler(NO, nil, cancelError);
        }
        return;
    }
    if (scheme == 0) {
        // 原版方案在 iOS 上对 Forge 1.13+/NeoForge 不可用（processors 需要 fork/exec）
        // 弹窗告知用户风险，让用户决定是否继续或改用直装方案
        if ([self isOriginalSchemeIncompatible]) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:localize(@"i18n_str_1139", nil)
                                 message:localize(@"i18n_str_1140", nil)
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1141", nil)
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *a) {
                [self startDownloadWithScheme:1];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_1142", nil)
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *a) {
                [self startDownloadWithScheme:0];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        [self startDownloadWithScheme:0];
    } else if (scheme == 1) {
        [self startDownloadWithScheme:1];
    }
}

/// 判断原版方案（运行 installer.jar）对当前选中的版本是否不可用
/// NeoForge 全版本、Forge 1.13+ 的 installer.jar 内含 processors，需要 fork/exec 子进程
- (BOOL)isOriginalSchemeIncompatible {
    if ([self.currentVendor isEqualToString:@"NeoForge"]) {
        return YES;  // 所有 NeoForge 版本都依赖 processors
    }
    // Forge：检查 MC 版本是否 1.13+
    // versionString 形如 "1.20.1-47.3.0"、"1.12.2-14.23.5.2860"
    NSString *version = self.selectedVersionString;
    if (![version hasPrefix:@"1."]) {
        // 非 "1." 开头的版本号（纯 loader 版本）通常对应 1.13+ 的新格式
        return YES;
    }
    NSArray *parts = [version componentsSeparatedByString:@"."];
    if (parts.count >= 2) {
        NSInteger minor = [parts[1] integerValue];
        if (minor >= 13) return YES;
    }
    return NO;
}

- (void)startDownloadWithScheme:(NSInteger)scheme {
    NSString *versionString = self.selectedVersionString;
    if (!versionString) return;

    // 修复 Forge installer 下载 404（参考 ZL2 ForgeVersions.getDownloadUrl 的
    // "<inherit>-<fileVersion>" 复合格式规则）：
    // ModLoaderInstallViewController 传入的 presetVersionString 是纯 Forge 版本号
    // （如 "47.2.0"），而官方 maven / BMCLAPI 的 installer 路径必须是复合格式
    // "<mcVersion>-<forgeVersion>"（如 "1.20.1-47.2.0"），缺失前缀时 URL 必然 404。
    // 此处检测前缀缺失时补全；NeoForge 不适用（其 maven 路径本就是纯版本号格式）。
    if ([self.currentVendor isEqualToString:@"Forge"] && self.gameVersion.length > 0) {
        NSString *compoundPrefix = [NSString stringWithFormat:@"%@-", self.gameVersion];
        if (![versionString hasPrefix:compoundPrefix] &&
            ![versionString hasPrefix:self.gameVersion]) {
            versionString = [compoundPrefix stringByAppendingString:versionString];
            // 回写：后续直装（ForgeDirectInstaller 解析 inheritsFrom）与
            // completion 回调均使用复合格式
            self.selectedVersionString = versionString;
        }
    }

    self.selectedScheme = scheme;
    NSIndexPath *indexPath = [self indexPathForVersionString:versionString];
    self.currentDownloadIndexPath = indexPath;
    self.tableView.allowsSelection = NO;
    [self switchToLoadingState];

    NSString *jarURL;
    NSString *downloadSource = getPrefObject(@"general.download_source");
    BOOL useBMCLAPI = [downloadSource isEqualToString:@"bmclapi"];
    if ([self.currentVendor isEqualToString:@"NeoForge"] && ([versionString containsString:@"1.20.1"] || [versionString hasPrefix:@"47."])) {
        if (useBMCLAPI) {
            jarURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/maven/net/neoforged/forge/%@/forge-%@-installer.jar", versionString, versionString];
        } else {
            jarURL = [NSString stringWithFormat:@"https://maven.neoforged.net/releases/net/neoforged/forge/%@/forge-%@-installer.jar", versionString, versionString];
        }
    } else if ([self.currentVendor isEqualToString:@"NeoForge"]) {
        if (useBMCLAPI) {
            jarURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/%@/neoforge-%@-installer.jar", versionString, versionString];
        } else {
            jarURL = [NSString stringWithFormat:self.endpoints[self.currentVendor][@"installer"], versionString];
        }
    } else {
        // Forge：参考 ZL2 BMCLAPI 镜像替换规则
        // （https://maven.minecraftforge.net → https://bmclapi2.bangbang93.com/maven），
        // 用户偏好 BMCLAPI 时走镜像下载，避免国内直连官方 maven 失败
        if (useBMCLAPI) {
            jarURL = [NSString stringWithFormat:@"https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/%@/forge-%@-installer.jar", versionString, versionString];
        } else {
            jarURL = [NSString stringWithFormat:self.endpoints[self.currentVendor][@"installer"], versionString];
        }
    }
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@-installer-%@.jar",
                          self.currentVendor,
                          [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSDebugLog(@"[%@ Installer] Downloading %@", self.currentVendor, jarURL);

    // redesign-download-ui Phase 4 Task 4.2：installer jar 下载注册为统一下载任务，
    // PLTaskStagesSingleFile 单阶段 + autoPresentDetail 自动弹出统一进度页
    NSString *taskName = [NSString stringWithFormat:@"%@-installer-%@", self.currentVendor, versionString];
    NSString *source = downloadSource ?: @"official";
    DownloadTaskItem *taskItem = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeModloader
                        resourceName:taskName
                         displayName:[NSString stringWithFormat:@"%@ Installer %@", self.currentVendor, versionString]
                      downloadSource:source
                             rawTask:nil
                      supportsResume:NO
                             iconURL:nil];
    if (taskItem) {
        taskItem.downloadURL = jarURL;
        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesSingleFile()];
        taskItem.autoPresentDetail = YES;
        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId state:DownloadTaskStateDownloading];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId stageAtIndex:0 status:PLTaskStageStatusRunning];
        self.installerTaskId = taskItem.taskId;
    }
    NSString *taskId = self.installerTaskId;
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];

    self.afManager = [AFURLSessionManager new];
    // rawTask 挂接 AF 下载任务：统一进度页的取消/暂停按钮可作用于该 task
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:jarURL]];
    NSURLSessionDownloadTask *downloadTask = [self.afManager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull progress){
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!taskId) return;
            [manager updateTaskWithId:taskId
                              progress:progress.fractionCompleted
                          totalBytes:progress.totalUnitCount
                       downloadedBytes:progress.completedUnitCount];
            [manager updateTaskWithId:taskId stageAtIndex:0 progress:progress.fractionCompleted message:nil];
        });
    } destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
        return [NSURL fileURLWithPath:outPath];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tableView.allowsSelection = YES;
            if (self.currentDownloadIndexPath) {
                [self resetCellAppearance:self.currentDownloadIndexPath];
            }
            self.currentDownloadIndexPath = nil;

            if (error) {
                if (taskId) {
                    if (error.code == NSURLErrorCancelled) {
                        [manager setTaskWithId:taskId state:DownloadTaskStateCancelled];
                    } else {
                        [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusFailed];
                        [manager updateTaskWithId:taskId error:error];
                        [manager setTaskWithId:taskId state:DownloadTaskStateFailed];
                    }
                    self.installerTaskId = nil;
                }
                if (error.code != NSURLErrorCancelled) {
                    NSDebugLog(@"Error: %@", error);
                    showDialog(localize(@"Error", nil), error.localizedDescription);
                }
                [self switchToReadyState];
                if (self.completionHandler) {
                    self.completionHandler(NO, nil, error);
                }
                return;
            }

            if (taskId) {
                [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusCompleted];
                [manager setTaskWithId:taskId state:DownloadTaskStateCompleted];
                self.installerTaskId = nil;
            }

            NSString *profileName = [NSString stringWithFormat:@"%@-%@", self.currentVendor, versionString];

            if (self.completionHandler) {
                // 将安装方案和文件路径一起打包，避免外部依赖 weak 引用的生命周期
                NSDictionary *result = @{
                    @"filePath": outPath,
                    @"selectedScheme": @(self.selectedScheme)
                };
                self.completionHandler(YES, profileName, result);
            }

            [self switchToReadyState];
        });
    }];

    if (taskItem) {
        taskItem.rawTask = downloadTask;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [downloadTask resume];
    });
}

- (NSIndexPath *)indexPathForVersionString:(NSString *)versionString {
    [self.dataLock lock];
    for (NSUInteger section = 0; section < self.forgeList.count; section++) {
        NSArray *versions = self.forgeList[section];
        for (NSUInteger row = 0; row < versions.count; row++) {
            if ([versions[row] isEqualToString:versionString]) {
                [self.dataLock unlock];
                return [NSIndexPath indexPathForRow:row inSection:section];
            }
        }
    }
    [self.dataLock unlock];
    return nil;
}

- (void)addVersionToList:(NSString *)version {
    if (version.length == 0) return;
    
    [self.dataLock lock];
    
    if ([self.currentVendor isEqualToString:@"NeoForge"]) {
        NSArray *skipPatterns = @[
            @"sources", @"userdev", @"javadoc", @"universal", @"slim", 
            @"-javadoc", @"-sources", @"-all", @"-changelog", 
            @"-installer-win", @"-mdk"
        ];
        
        for (NSString *pattern in skipPatterns) {
            if ([version containsString:pattern]) {
                NSLog(@"[ForgeInstall] Skipping problematic NeoForge version: %@", version);
                [self.dataLock unlock];
                return;
            }
        }
        
        NSString *minecraftVersion = [self extractMinecraftVersionFromNeoForgeVersion:version];
        if ([minecraftVersion isEqualToString:@"Unknown"]) {
            NSLog(@"[ForgeInstall] Skipping NeoForge version with unknown MC version: %@", version);
            [self.dataLock unlock];
            return;
        }
        
        // 当 gameVersion 已设置时（例如由 DownloadViewController 传入），仅加载对应 MC 版本的加载器版本
        // 避免一次性把所有 MC 版本的 Forge/NeoForge 全部加载出来
        // Task185：过滤器换共享等价匹配器（病历见 utils.h
        // ame185_loaderVersionMatchesGameVersion）。旧逻辑比对提取器输出，
        // 而 26.x 新纪元提取器会把 26.3.x 解析成 "1.26.3"、把 26.1.2.71
        // 按首两段解析成 "1.26.1"——与 gameVersion "26.3"/"26.1.2" 永不
        // 相等 → 全部条目被跳过 = "大于 26 的版本 NeoForge 找不到"。匹配器
        // 直接在原始版本串上做双向候选集等价判定，新旧纪元 + legacy 全兼容。
        if (self.gameVersion.length > 0 && !ame185_loaderVersionMatchesGameVersion(version, self.gameVersion)) {
            NSLog(@"[ForgeInstall] Skipping NeoForge version (gameVersion filter): %@ (MC %@ != %@)", version, minecraftVersion, self.gameVersion);
            [self.dataLock unlock];
            return;
        }
        
        NSUInteger sectionIndex = NSNotFound;
        for (NSUInteger i = 0; i < self.versionList.count; i++) {
            if ([self.versionList[i] isEqualToString:minecraftVersion]) {
                sectionIndex = i;
                break;
            }
        }
        
        if (sectionIndex == NSNotFound) {
            [self.versionList addObject:minecraftVersion];
            [self.visibilityList addObject:@NO];
            [self.forgeList addObject:[NSMutableArray new]];
            sectionIndex = self.versionList.count - 1;
        }
        
        if (![self.forgeList[sectionIndex] containsObject:version]) {
            [self.forgeList[sectionIndex] addObject:version];
        }
    } else {
        if (![version containsString:@"-"]) {
            NSLog(@"[ForgeInstall] Skipping invalid Forge version format: %@", version);
            [self.dataLock unlock];
            return;
        }
        
        NSArray *skipPatterns = @[
            @"mdk", @"userdev", @"javadoc", @"src", @"sources", @"universal",
            @"-all", @"-changelog", @"-client", @"-server", @"-launcher"
        ];
        
        for (NSString *pattern in skipPatterns) {
            if ([version containsString:pattern]) {
                NSLog(@"[ForgeInstall] Skipping problematic Forge version: %@", version);
                [self.dataLock unlock];
                return;
            }
        }
        
        NSRange hyphenRange = [version rangeOfString:@"-"];
        if (hyphenRange.location == NSNotFound) {
            [self.dataLock unlock];
            return;
        }
    
        NSString *minecraftVersion = [version substringToIndex:hyphenRange.location];
        
        // 当 gameVersion 已设置时（例如由 DownloadViewController 传入），仅加载对应 MC 版本的加载器版本
        // 避免一次性把所有 MC 版本的 Forge 全部加载出来
        // Task185：同 NeoForge 分支——过滤器换共享等价匹配器（复合版本
        // "26.3-66.0.5" / "1.20.1-47.2.0" 全兼容，含跨纪元等价形态）。
        if (self.gameVersion.length > 0 && !ame185_loaderVersionMatchesGameVersion(version, self.gameVersion)) {
            NSLog(@"[ForgeInstall] Skipping Forge version (gameVersion filter): %@ (MC %@ != %@)", version, minecraftVersion, self.gameVersion);
            [self.dataLock unlock];
            return;
        }
        
        NSUInteger sectionIndex = NSNotFound;
        for (NSUInteger i = 0; i < self.versionList.count; i++) {
            if ([self.versionList[i] isEqualToString:minecraftVersion]) {
                sectionIndex = i;
                break;
            }
        }
        
        if (sectionIndex == NSNotFound) {
            [self.versionList addObject:minecraftVersion];
            [self.visibilityList addObject:@NO];
            [self.forgeList addObject:[NSMutableArray new]];
            sectionIndex = self.versionList.count - 1;
        }
        
        if (![self.forgeList[sectionIndex] containsObject:version]) {
            [self.forgeList[sectionIndex] addObject:version];
        }
    }
    
    [self.dataLock unlock];
}

#pragma mark - NSXMLParserDelegate

- (void)finalizeVersionList {
    [self.dataLock lock];
    
    NSString *vendor = self.currentVendor;
    NSMutableArray<NSNumber *> *indices = [NSMutableArray new];
    for (NSInteger i = 0; i < self.versionList.count; i++) {
        [indices addObject:@(i)];
    }
    
    // 完善版本排序逻辑
    [indices sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSString *va = self.versionList[a.integerValue];
        NSString *vb = self.versionList[b.integerValue];
        
        // 快照版本排在后面
        BOOL vaIsSnapshot = [self isSnapshotVersion:va];
        BOOL vbIsSnapshot = [self isSnapshotVersion:vb];
        if (vaIsSnapshot != vbIsSnapshot) {
            return vaIsSnapshot ? NSOrderedDescending : NSOrderedAscending;
        }
        
        // 按版本号降序排列（新版本在前）
        NSArray *pa = [va componentsSeparatedByString:@"."];
        NSArray *pb = [vb componentsSeparatedByString:@"."];
        NSInteger aMajor = pa.count > 0 ? [pa[0] integerValue] : 0;
        NSInteger bMajor = pb.count > 0 ? [pb[0] integerValue] : 0;
        if (aMajor != bMajor) return (aMajor < bMajor) ? NSOrderedDescending : NSOrderedAscending;
        
        NSInteger aMinor = pa.count > 1 ? [pa[1] integerValue] : 0;
        NSInteger bMinor = pb.count > 1 ? [pb[1] integerValue] : 0;
        if (aMinor != bMinor) return (aMinor < bMinor) ? NSOrderedDescending : NSOrderedAscending;
        
        NSInteger aPatch = pa.count > 2 ? [pa[2] integerValue] : 0;
        NSInteger bPatch = pb.count > 2 ? [pb[2] integerValue] : 0;
        if (aPatch != bPatch) return (aPatch < bPatch) ? NSOrderedDescending : NSOrderedAscending;
        
        return NSOrderedSame;
    }];

    NSMutableArray *newVisibility = [NSMutableArray new];
    NSMutableArray *newVersionList = [NSMutableArray new];
    NSMutableArray *newForgeList = [NSMutableArray new];
    for (NSNumber *idx in indices) {
        // 修复：防止越界
        NSInteger index = idx.integerValue;
        if (index < self.visibilityList.count && index < self.versionList.count && index < self.forgeList.count) {
            [newVisibility addObject:self.visibilityList[index]];
            [newVersionList addObject:self.versionList[index]];
            [newForgeList addObject:self.forgeList[index]];
        }
    }
    self.visibilityList = newVisibility;
    self.versionList = newVersionList;
    self.forgeList = newForgeList;

    // 修复：自动展开分区。原实现所有 visibilityList 默认为 NO（折叠），用户只看到
    // MC 版本标题但看不到任何 Forge 版本，误以为"加载不出任何版本"。
    // 策略：若指定了 gameVersion，展开匹配该版本的分区；否则展开第一个分区。
    // 分区数 <= 5 时全部展开（常见场景，避免用户逐个点击）。
    if (self.versionList.count > 0) {
        BOOL expandAll = (self.versionList.count <= 5);
        BOOL foundMatchingSection = NO;
        for (NSUInteger i = 0; i < self.versionList.count; i++) {
            if (expandAll) {
                self.visibilityList[i] = @YES;
            } else if (self.gameVersion.length > 0 && [self.versionList[i] isEqualToString:self.gameVersion]) {
                self.visibilityList[i] = @YES;
                foundMatchingSection = YES;
            }
        }
        // 若未找到匹配 gameVersion 的分区，至少展开第一个（最新版本）
        if (!expandAll && !foundMatchingSection) {
            self.visibilityList[0] = @YES;
        }
    }

    for (NSMutableArray<NSString *> *versions in self.forgeList) {
        [versions sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
            if ([vendor isEqualToString:@"Forge"]) {
                NSRange dashL = [lhs rangeOfString:@"-"];
                NSRange dashR = [rhs rangeOfString:@"-"];
                NSString *lv = dashL.location != NSNotFound ? [lhs substringFromIndex:dashL.location + 1] : lhs;
                NSString *rv = dashR.location != NSNotFound ? [rhs substringFromIndex:dashR.location + 1] : rhs;
                NSArray *lp = [lv componentsSeparatedByString:@"."];
                NSArray *rp = [rv componentsSeparatedByString:@"."];
                NSInteger lA = lp.count > 0 ? [lp[0] integerValue] : 0;
                NSInteger rA = rp.count > 0 ? [rp[0] integerValue] : 0;
                if (lA != rA) return (lA < rA) ? NSOrderedDescending : NSOrderedAscending;
                NSInteger lB = lp.count > 1 ? [lp[1] integerValue] : 0;
                NSInteger rB = rp.count > 1 ? [rp[1] integerValue] : 0;
                if (lB != rB) return (lB < rB) ? NSOrderedDescending : NSOrderedAscending;
                NSInteger lC = lp.count > 2 ? [lp[2] integerValue] : 0;
                NSInteger rC = rp.count > 2 ? [rp[2] integerValue] : 0;
                if (lC != rC) return (lC < rC) ? NSOrderedDescending : NSOrderedAscending;
                return NSOrderedSame;
            } else {
                BOOL lBeta = [lhs containsString:@"-beta"];
                BOOL rBeta = [rhs containsString:@"-beta"];
                NSString *lClean = [lhs stringByReplacingOccurrencesOfString:@"-beta" withString:@""];
                NSString *rClean = [rhs stringByReplacingOccurrencesOfString:@"-beta" withString:@""];
                NSArray *lc = [lClean componentsSeparatedByString:@"."];
                NSArray *rc = [rClean componentsSeparatedByString:@"."];
                NSInteger lBuild = lc.count > 2 ? [lc[2] integerValue] : 0;
                NSInteger rBuild = rc.count > 2 ? [rc[2] integerValue] : 0;
                if (lBuild != rBuild) return (lBuild < rBuild) ? NSOrderedDescending : NSOrderedAscending;
                return NSOrderedSame;
            }
        }];
    }
    
    [self.filteredForgeList removeAllObjects];
    for (NSMutableArray *forgeVersions in self.forgeList) {
        [self.filteredForgeList addObject:[forgeVersions mutableCopy]];
    }
    
    [self.dataLock unlock];
    
    self.isDataLoading = NO;
    [self switchToReadyState];
    [self.tableView reloadData];
    
    if (self.versionList.count > 0) {
        [self.tableView setContentOffset:CGPointZero animated:YES];
    }
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    // 不在此触发 finalizeVersionList。
    // Forge 分支已在 loadMetadataFromVendor: 中，等双源解析 + fallback 全部完成后再统一调用
    // finalizeVersionList。若在此 dispatch_async，会在第一源（如 BMCLAPI 旧数据被 gameVersion
    // 全过滤后 versionList 为空）解析完成时立即终结加载状态（isDataLoading=NO + switchToReadyState），
    // 导致 fallback 到官方源的 30s 请求期间用户看到空列表 + Close 按钮，误以为"加载不出列表"。
    // NeoForge 分支用 JSON 不走 NSXMLParser，不受影响。
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict {
    self.isVersionElement = [elementName isEqualToString:@"version"];
    if (self.isVersionElement) {
        [self.currentVersionValue setString:@""];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.isVersionElement) {
        [self.currentVersionValue appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"version"]) {
        NSString *versionString = [self.currentVersionValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (versionString.length > 0) {
            [self addVersionToList:versionString];
        }
        self.isVersionElement = NO;
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    // 仅记录日志，不弹错误框。
    // Forge 分支的双源 fallback 逻辑会在所有源都失败时统一弹出错误提示。
    // 若在此弹框，BMCLAPI 返回 HTML 错误页（如 429 限流）导致解析失败时会立即弹框，
    // 随后 fallback 到官方源成功，用户却已经看到错误提示，体验混乱。
    NSLog(@"[ForgeInstall] XML parse error: %@", parseError.localizedDescription);
}

@end