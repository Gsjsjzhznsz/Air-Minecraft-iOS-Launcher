#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "authenticator/BaseAuthenticator.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "CustomControlsViewController.h"
#import "DownloadProgressViewController.h"
#import "DownloadTasksViewController.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "JavaGUIViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLPickerView.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "installer/modpack/ModrinthAPI.h"

#include <sys/time.h>

#define AUTORESIZE_MASKS UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin

static void *ProgressObserverContext = &ProgressObserverContext;

@interface LauncherNavigationController () <UIDocumentPickerDelegate, UIPickerViewDataSource, PLPickerViewDelegate, UIPopoverPresentationControllerDelegate> {
}

@property(nonatomic) MinecraftResourceDownloadTask* task;
@property(nonatomic) DownloadProgressViewController* progressVC;
@property(nonatomic) PLPickerView* versionPickerView;
@property(nonatomic) UITextField* versionTextField;
@property(nonatomic) int profileSelectedAt;

// ===== 下载中心入口（参照 FCL/ZL2/HMCL 下载进度弹窗入口）=====
// 在工具栏上添加"下载中心"按钮，点击后弹出 DownloadTasksViewController，
// 集中显示所有下载任务的进度（MC本体/模组/光影/资源包/数据包/世界存档/整合包）。
// 所有通过 DownloadTaskManager 注册的下载任务都统一由这个弹窗显示进度。
@property(nonatomic, strong) UIButton *downloadCenterButton;
@property(nonatomic, strong) UIActivityIndicatorView *downloadCenterActivityIndicator;
@property(nonatomic, strong) UILabel *downloadCenterProgressLabel;
@property(nonatomic, weak) DownloadTasksViewController *presentedDownloadCenterVC;
// 标记用户是否手动关闭了下载中心（避免下载任务更新时反复自动弹出）
@property(nonatomic, assign) BOOL userDismissedDownloadCenter;

@end

@implementation LauncherNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];

    if ([self respondsToSelector:@selector(setNeedsUpdateOfScreenEdgesDeferringSystemGestures)]) {
        [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    }

    self.versionTextField = [[PickTextField alloc] initWithFrame:CGRectMake(4, 4, self.toolbar.frame.size.width * 0.8 - 8, self.toolbar.frame.size.height - 8)];
    [self.versionTextField addTarget:self.versionTextField action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.versionTextField.autoresizingMask = AUTORESIZE_MASKS;
    self.versionTextField.placeholder = @"Specify version...";
    self.versionTextField.leftView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    self.versionTextField.rightView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"SpinnerArrow"] _imageWithSize:CGSizeMake(30, 30)]];
    self.versionTextField.rightView.frame = CGRectMake(0, 0, self.versionTextField.frame.size.height * 0.9, self.versionTextField.frame.size.height * 0.9);
    self.versionTextField.leftViewMode = UITextFieldViewModeAlways;
    self.versionTextField.rightViewMode = UITextFieldViewModeAlways;
    self.versionTextField.textAlignment = NSTextAlignmentCenter;

    self.versionPickerView = [[PLPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    UIToolbar *versionPickToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width, 44.0)];

    [self reloadProfileList];

    // 监听配置文件列表刷新通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfileList)
                                                 name:@"ReloadProfileList"
                                               object:nil];

    UIBarButtonItem *versionFlexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    UIBarButtonItem *versionDoneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(versionClosePicker)];
    versionPickToolbar.items = @[versionFlexibleSpace, versionDoneButton];
    self.versionTextField.inputAccessoryView = versionPickToolbar;
    self.versionTextField.inputView = self.versionPickerView;

    UIView *targetToolbar = self.toolbar;
    [targetToolbar addSubview:self.versionTextField];

    self.progressViewMain = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, self.toolbar.frame.size.width, 4)];
    self.progressViewMain.autoresizingMask = AUTORESIZE_MASKS;
    self.progressViewMain.hidden = YES;
    [targetToolbar addSubview:self.progressViewMain];

    self.buttonInstall = [UIButton buttonWithType:UIButtonTypeSystem];
    setButtonPointerInteraction(self.buttonInstall);
    [self.buttonInstall setTitle:localize(@"Play", nil) forState:UIControlStateNormal];
    self.buttonInstall.autoresizingMask = AUTORESIZE_MASKS;
    self.buttonInstall.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0];
    self.buttonInstall.layer.cornerRadius = 5;
    self.buttonInstall.frame = CGRectMake(self.toolbar.frame.size.width * 0.8, 4, self.toolbar.frame.size.width * 0.2, self.toolbar.frame.size.height - 8);
    self.buttonInstall.tintColor = UIColor.whiteColor;
    self.buttonInstall.enabled = NO;
    [self.buttonInstall addTarget:self action:@selector(performInstallOrShowDetails:) forControlEvents:UIControlEventPrimaryActionTriggered];
    [targetToolbar addSubview:self.buttonInstall];

    self.progressText = [[UILabel alloc] initWithFrame:self.versionTextField.frame];
    self.progressText.adjustsFontSizeToFitWidth = YES;
    self.progressText.autoresizingMask = AUTORESIZE_MASKS;
    self.progressText.font = [self.progressText.font fontWithSize:16];
    self.progressText.textAlignment = NSTextAlignmentCenter;
    self.progressText.userInteractionEnabled = NO;
    [targetToolbar addSubview:self.progressText];

    // ===== 下载中心入口按钮（参照 FCL/ZL2/HMCL 下载进度弹窗入口）=====
    // 在工具栏左侧添加一个"下载中心"按钮，当有下载任务时显示，
    // 点击弹出 DownloadTasksViewController（FormSheet 方式），集中显示所有下载任务进度。
    // 按钮布局：[图标] [进度百分比] [活动指示器]
    CGFloat dcBtnWidth = 72.0;
    CGFloat dcBtnHeight = self.toolbar.frame.size.height - 8;
    self.downloadCenterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    // 不使用按钮的 title 显示文字，改用独立的 progressLabel 避免与图标布局冲突
    self.downloadCenterButton.tintColor = [UIColor whiteColor];
    self.downloadCenterButton.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:0.85];
    self.downloadCenterButton.layer.cornerRadius = 5;
    self.downloadCenterButton.frame = CGRectMake(4, 4, dcBtnWidth, dcBtnHeight);
    self.downloadCenterButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [self.downloadCenterButton setImage:[UIImage systemImageNamed:@"arrow.down.circle"] forState:UIControlStateNormal];
    // 图标固定在按钮左侧
    CGFloat iconSize = 22.0;
    [self.downloadCenterButton setImageEdgeInsets:UIEdgeInsetsMake(0, 4, 0, dcBtnWidth - iconSize - 4)];
    [self.downloadCenterButton addTarget:self action:@selector(openDownloadCenter) forControlEvents:UIControlEventTouchUpInside];
    self.downloadCenterButton.hidden = YES;
    [targetToolbar addSubview:self.downloadCenterButton];

    // 活动指示器（按钮右侧，下载中时旋转）
    self.downloadCenterActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.downloadCenterActivityIndicator.color = [UIColor whiteColor];
    self.downloadCenterActivityIndicator.hidesWhenStopped = YES;
    CGFloat indicatorSize = 20.0;
    self.downloadCenterActivityIndicator.frame = CGRectMake(dcBtnWidth - indicatorSize - 4, (dcBtnHeight - indicatorSize) / 2.0, indicatorSize, indicatorSize);
    self.downloadCenterActivityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.downloadCenterButton addSubview:self.downloadCenterActivityIndicator];

    // 进度百分比标签（按钮中间，显示聚合进度百分比）
    self.downloadCenterProgressLabel = [[UILabel alloc] init];
    self.downloadCenterProgressLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightBold];
    self.downloadCenterProgressLabel.textColor = [UIColor whiteColor];
    self.downloadCenterProgressLabel.textAlignment = NSTextAlignmentCenter;
    self.downloadCenterProgressLabel.text = @"";
    self.downloadCenterProgressLabel.frame = CGRectMake(iconSize + 6, 0, dcBtnWidth - iconSize - indicatorSize - 12, dcBtnHeight);
    self.downloadCenterProgressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.downloadCenterButton addSubview:self.downloadCenterProgressLabel];

    [self fetchRemoteVersionList];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(receiveNotification:)
        name:@"InstallModpack"
        object:nil];

    // ===== 下载中心入口通知监听 =====
    // 监听 DownloadTaskManager 的通知，当有新下载任务注册或进度更新时：
    // 1. 更新下载中心按钮的显示状态和进度百分比
    // 2. 自动弹出下载中心弹窗（如果用户未手动关闭且没有其他模态视图）
    // 这确保了模组、光影、资源包等所有下载都能通过下载中心统一显示进度。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadTaskUpdate:)
                                                 name:DownloadTaskManagerDidUpdateTaskNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadTaskCompleted:)
                                                 name:DownloadTaskManagerTaskCompletedNotification
                                               object:nil];
    // 监听下载中心被用户手动关闭的通知，设置标记避免反复自动弹出
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDownloadCenterDismissed)
                                                 name:@"DownloadCenterDidDismiss"
                                               object:nil];

    if ([BaseAuthenticator.current isKindOfClass:MicrosoftAuthenticator.class]) {
        // Perform token refreshment on startup
        [self setInteractionEnabled:NO forDownloading:NO];
        id callback = ^(id status, BOOL success) {
            status = [status description];
            self.progressText.text = status;
            if (status == nil) {
                [self setInteractionEnabled:YES forDownloading:NO];
            } else if (!success) {
                showDialog(localize(@"Error", nil), status);
            }
        };
        [BaseAuthenticator.current refreshTokenWithCallback:callback];
    }
}

- (BOOL)isVersionInstalled:(NSString *)versionId {
    NSString *localPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionId];
    BOOL isDirectory;
    [NSFileManager.defaultManager fileExistsAtPath:localPath isDirectory:&isDirectory];
    return isDirectory;
}

- (void)fetchLocalVersionList {
    if (!localVersionList) {
        localVersionList = [NSMutableArray new];
    }
    [localVersionList removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/", getenv("POJAV_GAME_DIR")];
    NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:Nil];
    for (NSString *versionId in list) {
        if (![self isVersionInstalled:versionId]) continue;
        [localVersionList addObject:@{
            @"id": versionId,
            @"type": @"custom"
        }];
    }
}

- (void)fetchRemoteVersionList {
    self.buttonInstall.enabled = NO;
    remoteVersionList = @[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"}
    ].mutableCopy;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    // 配置响应序列化器以接受application/octet-stream
    AFJSONResponseSerializer *serializer = [AFJSONResponseSerializer serializer];
    [serializer setAcceptableContentTypes:[NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", @"application/octet-stream", nil]];
    manager.responseSerializer = serializer;
    NSString *downloadSource = getPrefObject(@"general.download_source");
    NSString *versionManifestURL;
    
    if ([downloadSource isEqualToString:@"bmclapi"]) {
        versionManifestURL = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";
    } else {
        versionManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
    }
    
    [manager GET:versionManifestURL parameters:nil headers:nil progress:^(NSProgress * _Nonnull progress) {
        self.progressViewMain.progress = progress.fractionCompleted;
    } success:^(NSURLSessionTask *task, NSDictionary *responseObject) {
        [remoteVersionList addObjectsFromArray:responseObject[@"versions"]];
        NSDebugLog(@"[VersionList] Got %d versions", remoteVersionList.count);
        setPrefObject(@"internal.latest_version", responseObject[@"latest"]);
        self.buttonInstall.enabled = YES;
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSDebugLog(@"[VersionList] Warning: Unable to fetch version list: %@", error.localizedDescription);
        self.buttonInstall.enabled = YES;
    }];
}

- (void)fetchRemoteVersionListForce:(BOOL)force {
    // 直接调用 fetchRemoteVersionList，忽略 force 参数
    [self fetchRemoteVersionList];
}

// Invoked by: startup, instance change event
- (void)reloadProfileList {
    // Reload local version list
    [self fetchLocalVersionList];
    // Reload launcher_profiles.json
    [PLProfiles updateCurrent];
    [self.versionPickerView reloadAllComponents];
    // Reload selected profile info
    self.profileSelectedAt = [PLProfiles.current.profiles.allKeys indexOfObject:PLProfiles.current.selectedProfileName];
    if (self.profileSelectedAt == -1) {
        // This instance has no profiles?
        return;
    }
    [self.versionPickerView selectRow:self.profileSelectedAt inComponent:0 animated:NO];
    [self pickerView:self.versionPickerView didSelectRow:self.profileSelectedAt inComponent:0];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // 关键修复（KVO 泄漏）：兜底移除 KVO 观察者。
    // 正常流程中下载完成/出错时已移除，但若 VC 在下载过程中被释放（如退出启动器），
    // KVO 观察者会指向已释放对象，导致野指针崩溃。
    if (self.task && self.task.progress) {
        @try {
            [self.task.progress removeObserver:self
                                    forKeyPath:@"fractionCompleted"
                                       context:ProgressObserverContext];
        } @catch (NSException *e) {}
    }
}

#pragma mark - 下载中心（参照 FCL/ZL2/HMCL 下载进度弹窗）

/// 打开下载中心弹窗
/// 参照 FCL/ZL2/HMCL 的下载进度显示方式：以 FormSheet 方式弹出 DownloadTasksViewController，
/// 集中显示所有下载任务（MC本体/模组/光影/资源包/数据包/世界存档/整合包）的实时进度。
/// 所有通过 DownloadTaskManager 注册的下载任务都会在这里显示，实现统一的下载进度管理。
- (void)openDownloadCenter {
    // 如果已经弹出了下载中心，直接返回避免重复弹出
    if (self.presentedDownloadCenterVC) {
        return;
    }

    // 用户主动打开了下载中心，重置"用户已关闭"标记
    self.userDismissedDownloadCenter = NO;

    DownloadTasksViewController *downloadCenterVC = [[DownloadTasksViewController alloc] init];
    downloadCenterVC.modalPresentationStyle = UIModalPresentationFormSheet;
    downloadCenterVC.preferredContentSize = CGSizeMake(500, 600);

    // 弱引用持有，避免循环持有
    self.presentedDownloadCenterVC = downloadCenterVC;

    // 获取最顶层的视图控制器来 present
    UIViewController *topVC = self;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    [topVC presentViewController:downloadCenterVC animated:YES completion:nil];
}

/// 处理下载任务更新通知（进度变化、新任务注册等）
/// 当收到通知时仅更新下载中心按钮的状态，不再自动弹出下载中心界面。
///
/// 修改说明（修复下载版本时出现两个进度显示的问题）：
///   之前此方法会在检测到活跃下载任务时自动弹出 DownloadTasksViewController（下载中心界面），
///   同时启动器自身在 launchMinecraft: 中会自动弹出 DownloadProgressViewController
///   （FCL/ZL2 风格单任务进度），导致两个进度显示同时出现。
///   现在统一为 FCL/ZL2/HMCL 风格：版本下载开始时自动弹出 DownloadProgressViewController，
///   DownloadTasksViewController 仅保留为手动打开（通过下载中心按钮）。
- (void)handleDownloadTaskUpdate:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDownloadCenterButton];
    });
}

/// 处理下载任务完成通知
- (void)handleDownloadTaskCompleted:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDownloadCenterButton];
    });
}

/// 处理下载中心被用户手动关闭的通知
/// 设置 userDismissedDownloadCenter=YES，避免后续下载任务更新时反复自动弹出下载中心。
/// 用户可以通过点击启动器上的"下载中心"按钮重新打开（会重置此标记）。
- (void)handleDownloadCenterDismissed {
    self.userDismissedDownloadCenter = YES;
    self.presentedDownloadCenterVC = nil;
}

/// 更新下载中心按钮的显示状态和进度百分比
- (void)updateDownloadCenterButton {
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];
    NSArray<DownloadTaskItem *> *allTasks = [manager allTasks];

    if (allTasks.count == 0) {
        self.downloadCenterButton.hidden = YES;
        [self.downloadCenterActivityIndicator stopAnimating];
        return;
    }

    self.downloadCenterButton.hidden = NO;

    BOOL hasActive = NO;
    BOOL allCompleted = YES;
    double totalProgress = 0.0;
    NSInteger activeCount = 0;

    for (DownloadTaskItem *task in allTasks) {
        if (task.state == DownloadTaskStateDownloading || task.state == DownloadTaskStatePending) {
            hasActive = YES;
            allCompleted = NO;
            totalProgress += task.progress;
            activeCount++;
        } else if (task.state != DownloadTaskStateCompleted) {
            allCompleted = NO;
        }
    }

    if (hasActive) {
        double avgProgress = activeCount > 0 ? totalProgress / activeCount : 0.0;
        NSInteger percent = (NSInteger)(avgProgress * 100.0 + 0.5);
        percent = MAX(0, MIN(100, percent));
        self.downloadCenterProgressLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
        [self.downloadCenterActivityIndicator startAnimating];
    } else if (allCompleted) {
        self.downloadCenterProgressLabel.text = @"完成";
        [self.downloadCenterActivityIndicator stopAnimating];
    } else {
        self.downloadCenterProgressLabel.text = @"暂停";
        [self.downloadCenterActivityIndicator stopAnimating];
    }
}

#pragma mark - Options
- (void)enterCustomControls {
    CustomControlsViewController *vc = [[CustomControlsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.setDefaultCtrl = ^(NSString *name){
        setPrefObject(@"control.default_ctrl", name);
    };
    vc.getDefaultCtrl = ^{
        return getPrefObject(@"control.default_ctrl");
    };
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)enterModInstaller {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]]
        asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}



- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter {
    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = hitEnter;
    if (!vc.requiredJavaVersion) {
        // 解析失败（manifest 缺失/主类非法）时明确提示，避免静默 return 让用户以为安装器已启动
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:@"无法解析安装器主类或 Java 版本：%@", path.lastPathComponent]);
        return;
    }
    // execute_jar 路径：Caciocavallo17 jar 现已统一为 Java 17 编译版本，
    // Java 17/21 均可加载，不再需要强制提升 requiredJavaVersion 到 25。
    // - Java 8 JAR（如 OptiFine 安装器）走 Caciocavallo（非 17）路径，用 Java 8
    // - Java 17+ JAR 走 Caciocavallo17 路径，用 Java 17/21 即可
    // 与 JavaLauncher.m launchJar 分支保持一致。
    int requiredJavaVersion = vc.requiredJavaVersion;
    // 预检 execute_jar 标签的 JRE 是否已配置，避免 present 后才发现没 JRE 导致黑屏
    // 与 LauncherRightPanelViewController.enterModInstallerWithPath: 行为一致
    NSString *javaHome = getSelectedJavaHome(@"execute_jar", requiredJavaVersion);
    if (!javaHome) {
        showDialog(localize(@"Error", nil),
            [NSString stringWithFormat:@"执行 JAR 需要 Java %d 或更高版本，但未配置对应的运行时。\n\n请到「设置 → 管理运行时」中为「执行 Jar」标签分配一个 Java %d+ 的运行时。", requiredJavaVersion, requiredJavaVersion]);
        return;
    }
    [self invokeAfterJITEnabled:^{
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        NSLog(@"[ModInstaller] launching %@", vc.filepath);
        [self presentViewController:vc animated:YES completion:nil];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    // Handle normal jar file import
    [self enterModInstallerWithPath:url.path hitEnterAfterWindowShown:NO];
}

- (void)setInteractionEnabled:(BOOL)enabled forDownloading:(BOOL)downloading {
    for (UIControl *view in self.toolbar.subviews) {
        if ([view isKindOfClass:UIControl.class]) {
            view.alpha = enabled ? 1 : 0.2;
            view.enabled = enabled;
        }
    }
    // 启动游戏的完整性检查/下载：始终显示进度（HMCL 风格进度条+文本），
    // 不再被悬浮球设置隐藏，确保用户在启动前能"一模一样"地看到完整性检查进度。
    BOOL showProgressUI = YES;
    self.progressViewMain.hidden = enabled || !showProgressUI;
    if (!showProgressUI) {
        self.progressText.text = nil;
    }
    if (downloading) {
        [self.buttonInstall setTitle:localize(enabled ? @"Play" : @"Details", nil) forState:UIControlStateNormal];
        self.buttonInstall.alpha = 1;
        self.buttonInstall.enabled = YES;
    }
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
}

- (void)launchMinecraft:(UIButton *)sender {
    if (!self.versionTextField.hasText) {
        [self.versionTextField becomeFirstResponder];
        return;
    }

    if (BaseAuthenticator.current == nil) {
        // Present the account selector if none selected
        UIViewController *view = [(UINavigationController *)self.splitViewController.viewControllers[0]
        viewControllers][0];
        [view performSelector:@selector(selectAccount:) withObject:sender];
        return;
    }

    [self setInteractionEnabled:NO forDownloading:YES];

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
    NSDictionary *object = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(id == %@)", versionId]].firstObject;
    if (!object) {
        object = @{
            @"id": versionId,
            @"type": @"custom"
        };
    }

    self.task = [MinecraftResourceDownloadTask new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                // 关键修复（KVO 泄漏）：出错时必须先移除 KVO 再置 nil task，
                // 否则 task.progress 仍持有对 self 的 KVO 观察者，下次下载会重复添加。
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
                weakSelf.progressVC = nil;
            });
        };
        [self.task downloadVersion:object];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressViewMain.observedProgress = self.task.progress;
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];

            // 自动弹出 FCL/ZL2 风格的单任务进度对话框（参照 FCL 启动下载时自动显示进度对话框）
            // 之前通过 DownloadTaskManager 通知自动弹出 DownloadTasksViewController（下载中心界面），
            // 导致两个进度显示同时出现。现在统一使用 DownloadProgressViewController。
            if (!weakSelf.progressVC) {
                weakSelf.progressVC = [[DownloadProgressViewController alloc] initWithTask:weakSelf.task];
            }
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:weakSelf.progressVC];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            // 检查是否已有模态视图弹出，避免覆盖重要弹窗（如账号登录）
            UIViewController *topVC = weakSelf;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            if (!topVC.presentedViewController) {
                [topVC presentViewController:nav animated:YES completion:nil];
            }
        });
    });
}

- (void)performInstallOrShowDetails:(UIButton *)sender {
    if (self.task) {
        // 显示下载进度详情（悬浮球已移除）
        if (!self.progressVC) {
            self.progressVC = [[DownloadProgressViewController alloc] initWithTask:self.task];
        }
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.progressVC];
        nav.modalPresentationStyle = UIModalPresentationPopover;
        nav.popoverPresentationController.sourceView = sender;
        [self presentViewController:nav animated:YES completion:nil];
    } else {
        [self launchMinecraft:sender];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != ProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // Calculate download speed and ETA
    static CGFloat lastMsTime;
    static NSUInteger lastSecTime, lastCompletedUnitCount;
    NSProgress *progress = self.task.textProgress;
    struct timeval tv;
    gettimeofday(&tv, NULL); 
    NSInteger completedUnitCount = self.task.progress.totalUnitCount * self.task.progress.fractionCompleted;
    progress.completedUnitCount = completedUnitCount;
    if (lastSecTime < tv.tv_sec) {
        CGFloat currentTime = tv.tv_sec + tv.tv_usec / 1000000.0;
        NSInteger throughput = (completedUnitCount - lastCompletedUnitCount) / (currentTime - lastMsTime);
        progress.throughput = @(throughput);
        progress.estimatedTimeRemaining = @((progress.totalUnitCount - completedUnitCount) / throughput);
        lastCompletedUnitCount = completedUnitCount;
        lastSecTime = tv.tv_sec;
        lastMsTime = currentTime;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // 启动游戏的完整性检查/下载：始终显示进度（HMCL 风格进度条+文本）
        BOOL showProgressUI = YES;
        if (showProgressUI) {
            self.progressText.text = progress.localizedAdditionalDescription;
        }

        if (!progress.finished) return;
        [self.progressVC dismissViewControllerAnimated:NO completion:nil];

        self.progressViewMain.observedProgress = nil;
        // 关键修复（KVO 泄漏）：下载完成时移除 KVO 观察者。
        // 之前不移除，导致每次下载都在 self.task.progress 上累积一个观察者，
        // 多次下载后 progress 变化会触发多次 observeValueForKeyPath，UI 异常。
        @try {
            [self.task.progress removeObserver:self
                                    forKeyPath:@"fractionCompleted"
                                       context:ProgressObserverContext];
        } @catch (NSException *e) {}
        if (self.task.metadata) {
            [self invokeAfterJITEnabled:^{
                UIKit_launchMinecraftSurfaceVC(self.view.window, self.task.metadata);
            }];
        } else {
            self.task = nil;
            [self setInteractionEnabled:YES forDownloading:YES];
            [self reloadProfileList];
        }
    });
}

- (void)receiveNotification:(NSNotification *)notification {
    if (![notification.name isEqualToString:@"InstallModpack"]) {
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];
    self.task = [MinecraftResourceDownloadTask new];
    NSDictionary *userInfo = notification.userInfo;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                // 关键修复（KVO 泄漏）：出错时移除 KVO，与 launchMinecraft 流程一致
                @try {
                    [weakSelf.task.progress removeObserver:weakSelf
                                                forKeyPath:@"fractionCompleted"
                                                   context:ProgressObserverContext];
                } @catch (NSException *e) {}
                weakSelf.task = nil;
                weakSelf.progressVC = nil;
            });
        };
        [self.task downloadModpackFromAPI:notification.object detail:userInfo[@"detail"] atIndex:[userInfo[@"index"] unsignedLongValue]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressViewMain.observedProgress = self.task.progress;
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)invokeAfterJITEnabled:(void(^)(void))handler {
    // 注意：不要在此清空 localVersionList/remoteVersionList
    // 该方法既被 JAR 执行调用，也被正常启动游戏调用；清空会导致用户返回后版本列表为空、
    // buttonInstall 短暂不可用。版本列表的生命周期应由 reloadProfileList 统一管理。
    BOOL hasTrollStoreJIT = getEntitlementValue(@"com.apple.private.local.sandboxed-jit") || getEntitlementValue(@"jb.pmap_cs.custom_trust");
    BOOL isLiveContainer = getenv("LC_HOME_PATH") != NULL;

    if (isJITEnabled(false)) {
        [ALTServerManager.sharedManager stopDiscovering];
        handler();
        return;
    } else if (hasTrollStoreJIT) {
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier]];
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:nil];
        // Do not return, wait for TrollStore to enable JIT and jump back
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else if (@available(iOS 17.4, *)) {
        NSString *scriptDataString = @"";
        if(DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", NSBundle.mainBundle.bundleIdentifier, getpid(), scriptDataString]] options:@{} completionHandler:nil];
    } else {
        // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing, so it only jumps to SideStore.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]] options:@{} completionHandler:nil];
    }

    self.progressText.text = localize(@"launcher.wait_jit.title", nil);

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
        message:hasTrollStoreJIT ? localize(@"launcher.wait_jit_trollstore.message", nil) : localize(@"launcher.wait_jit.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
/* TODO:
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^{
        
    }];
    [alert addAction:cancel];
*/
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!isJITEnabled(false)) {
            // Perform check for every 200ms
            usleep(1000*200);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:handler];
        });
    });
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - UIPickerView stuff
- (void)pickerView:(PLPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.profileSelectedAt = row;
    //((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    ((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
    PLProfiles.current.selectedProfileName = self.versionTextField.text;
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return PLProfiles.current.profiles.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return PLProfiles.current.profiles.allValues[row][@"name"];
}

- (void)pickerView:(UIPickerView *)pickerView enumerateImageView:(UIImageView *)imageView forRow:(NSInteger)row forComponent:(NSInteger)component {
    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    NSString *urlString = PLProfiles.current.profiles.allValues[row][@"icon"];
    [imageView setImageWithURL:[NSURL URLWithString:urlString] placeholderImage:fallbackImage];
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

#pragma mark - View controller UI mode

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 发送通知更新账户信息
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
}

@end
