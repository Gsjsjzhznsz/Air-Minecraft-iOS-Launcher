//
//  ModpackImportViewController.m
//  Amethyst
//
//  修改：增加异常捕获，彻底防止闪退
//  重写：参照 FCL 风格，导入时显示进度卡片（百分比+进度条+阶段文案）替代转圈圈
//

#import "ModpackImportViewController.h"
#import "BackgroundManager.h"
#import "LiquidGlassCompat.h"
#import "ModpackImportService.h"
#import "ModpackExportService.h"
#import "PLProfiles.h"
#import "UnzipKit.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ModpackImportViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *importedModpacks;
@property (nonatomic, strong) ModpackImportService *importService;
@property (nonatomic, strong) NSDictionary *currentImportingModpack;

// FCL 风格进度卡片
@property (nonatomic, strong) UIView *progressOverlay;       // 半透明遮罩
@property (nonatomic, strong) UIView *progressCard;          // 居中卡片
@property (nonatomic, strong) UILabel *progressTitleLabel;   // 标题
@property (nonatomic, strong) UILabel *progressPercentLabel; // 百分比 (36pt 大字)
@property (nonatomic, strong) UIProgressView *progressBar;   // 进度条
@property (nonatomic, strong) UILabel *progressStageLabel;   // 阶段文案
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner; // 不确定模式转圈
@property (nonatomic, strong) UIButton *progressCancelButton; // 取消按钮
@end

@implementation ModpackImportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"导入整合包";

    [[BackgroundManager sharedManager] applyEffectToView:self.view];

    self.importService = [[ModpackImportService alloc] init];
    self.importedModpacks = [NSMutableArray array];
    [self setupUI];
    [self loadImportedModpacks];

    // 右上角导出按钮（参照 FCL/HMCL 整合包导出入口）
    UIBarButtonItem *exportItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(showExportProfilePicker)];
    exportItem.accessibilityLabel = @"导出整合包";
    self.navigationItem.rightBarButtonItem = exportItem;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
}

- (void)setupUI {
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.importButton setTitle:@"选择整合包文件" forState:UIControlStateNormal];
    [self.importButton setImage:[UIImage systemImageNamed:@"doc.badge.plus"] forState:UIControlStateNormal];
    self.importButton.backgroundColor = [UIColor systemBlueColor];
    [self.importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.importButton.layer.cornerRadius = 10;
    self.importButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.importButton addTarget:self action:@selector(selectModpackFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ModpackCell"];
    self.tableView.rowHeight = 80;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.text = @"还没有导入的整合包\n点击上方按钮导入";
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.importButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.importButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.importButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.importButton.heightAnchor constraintEqualToConstant:50],

        [self.tableView.topAnchor constraintEqualToAnchor:self.importButton.bottomAnchor constant:16],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

#pragma mark - FCL 风格进度卡片

- (void)showProgressCardWithTitle:(NSString *)title {
    [self hideProgressCard];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [self.view addSubview:overlay];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 18;
    card.layer.masksToBounds = YES;
    [overlay addSubview:card];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:titleLabel];

    UILabel *percentLabel = [[UILabel alloc] init];
    percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    percentLabel.font = [UIFont systemFontOfSize:36 weight:UIFontWeightHeavy];
    percentLabel.textAlignment = NSTextAlignmentCenter;
    percentLabel.text = @"0%";
    [card addSubview:percentLabel];

    UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.progressTintColor = [UIColor systemBlueColor];
    [card addSubview:bar];

    UILabel *stageLabel = [[UILabel alloc] init];
    stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    stageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    stageLabel.textColor = [UIColor secondaryLabelColor];
    stageLabel.textAlignment = NSTextAlignmentCenter;
    stageLabel.numberOfLines = 0;
    [card addSubview:stageLabel];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.hidesWhenStopped = YES;
    [card addSubview:spinner];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [cancelBtn addTarget:self action:@selector(cancelImport) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:300],

        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],

        [percentLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [percentLabel.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [spinner.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [spinner.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [bar.topAnchor constraintEqualToAnchor:percentLabel.bottomAnchor constant:12],
        [bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [bar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [bar.heightAnchor constraintEqualToConstant:8],

        [stageLabel.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:12],
        [stageLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stageLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],

        [cancelBtn.topAnchor constraintEqualToAnchor:stageLabel.bottomAnchor constant:16],
        [cancelBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20]
    ]];

    self.progressOverlay = overlay;
    self.progressCard = card;
    self.progressTitleLabel = titleLabel;
    self.progressPercentLabel = percentLabel;
    self.progressBar = bar;
    self.progressStageLabel = stageLabel;
    self.progressSpinner = spinner;
    self.progressCancelButton = cancelBtn;

    // 初始不确定模式 (只显示转圈)
    [self setProgress:-1 stageMessage:@"正在准备..."];
}

- (void)setProgress:(double)progress stageMessage:(NSString *)stageMessage {
    if (!self.progressCard) return;

    if (progress < 0) {
        // 不确定模式
        self.progressBar.hidden = YES;
        self.progressPercentLabel.hidden = YES;
        self.progressSpinner.hidden = NO;
        [self.progressSpinner startAnimating];
    } else {
        self.progressBar.hidden = NO;
        self.progressPercentLabel.hidden = NO;
        self.progressSpinner.hidden = YES;
        [self.progressSpinner stopAnimating];
        double clamped = MAX(0.0, MIN(1.0, progress));
        NSInteger percent = (NSInteger)(clamped * 100);
        self.progressPercentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
        [self.progressBar setProgress:(float)clamped animated:YES];
    }
    self.progressStageLabel.text = stageMessage ?: @"";
}

- (void)hideProgressCard {
    if (self.progressOverlay) {
        [self.progressOverlay removeFromSuperview];
        self.progressOverlay = nil;
        self.progressCard = nil;
        self.progressTitleLabel = nil;
        self.progressPercentLabel = nil;
        self.progressBar = nil;
        self.progressStageLabel = nil;
        self.progressSpinner = nil;
        self.progressCancelButton = nil;
    }
}

- (void)cancelImport {
    // 简化处理：取消只是隐藏卡片 (后台导入会继续，但结果被忽略)
    // 真正的取消需要 ModpackImportService 支持取消，这里暂不实现
    [self hideProgressCard];
    self.currentImportingModpack = nil;
}

- (void)loadImportedModpacks {
    NSArray *modpacks = [self.importService getImportedModpacks];
    [self.importedModpacks removeAllObjects];
    [self.importedModpacks addObjectsFromArray:modpacks];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.emptyLabel.hidden = self.importedModpacks.count > 0;
        [self.tableView reloadData];
    });
}

#pragma mark - 文件选择

- (void)selectModpackFile {
    NSArray<UTType *> *contentTypes = @[
        [UTType typeWithFilenameExtension:@"mrpack"],
        [UTType typeWithFilenameExtension:@"zip"]
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    NSURL *fileURL = urls.firstObject;
    NSString *fileExtension = fileURL.pathExtension.lowercaseString;

    if (![fileExtension isEqualToString:@"mrpack"] && ![fileExtension isEqualToString:@"zip"]) {
        [self showAlertWithTitle:@"无效的文件" message:@"请选择 .mrpack 或 .zip 文件"];
        return;
    }

    BOOL accessGranted = [fileURL startAccessingSecurityScopedResource];
    if (!accessGranted) {
        [self showAlertWithTitle:@"访问被拒绝" message:@"无法访问选中的文件"];
        return;
    }

    // 解析阶段：显示不确定模式进度卡片
    [self showProgressCardWithTitle:@"正在解析整合包"];
    [self setProgress:-1 stageMessage:@"正在读取整合包信息..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *modpackInfo = nil;

        @try {
            modpackInfo = [self.importService parseModpackAtURL:fileURL error:&error];
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"ModpackImportError" code:9999
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"解析异常: %@", exception.reason]}];
        }

        [fileURL stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !modpackInfo) {
                [self hideProgressCard];
                [self showAlertWithTitle:@"解析失败" message:error.localizedDescription ?: @"无法解析整合包文件"];
                return;
            }
            self.currentImportingModpack = modpackInfo;
            [self hideProgressCard];
            [self showModpackImportConfirmation:modpackInfo];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

#pragma mark - 导入确认

- (void)showModpackImportConfirmation:(NSDictionary *)modpackInfo {
    NSString *name = modpackInfo[@"name"] ?: @"未知";
    NSString *version = modpackInfo[@"version"] ?: @"未知";
    NSString *mcVersion = modpackInfo[@"minecraftVersion"] ?: @"未知";
    NSString *loader = modpackInfo[@"loader"] ?: @"未知";
    NSString *loaderVersion = modpackInfo[@"loaderVersion"] ?: @"";

    NSString *message = [NSString stringWithFormat:@"名称: %@\n版本: %@\nMinecraft: %@\n加载器: %@ %@\n\n是否导入此整合包？",
                         name, version, mcVersion, loader, loaderVersion];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入整合包" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self.currentImportingModpack = nil;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self startModpackImport:modpackInfo];
    }]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startModpackImport:(NSDictionary *)modpackInfo {
    [self showProgressCardWithTitle:[NSString stringWithFormat:@"正在导入 %@", modpackInfo[@"name"] ?: @"整合包"]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSError *error = nil;
        __block BOOL success = NO;

        @try {
            success = [self.importService importModpack:modpackInfo
                                               progress:^(double progress, NSString *stageMessage) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setProgress:progress stageMessage:stageMessage];
                });
            } error:&error];
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"ModpackImportError" code:9998
                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"导入异常: %@", exception.reason]}];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // 完成时显示 100%
            [self setProgress:1.0 stageMessage:@"导入完成"];

            // 停留 0.6s 让用户看到完成状态
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self hideProgressCard];
                self.currentImportingModpack = nil;

                if (success) {
                    NSString *loader = modpackInfo[@"loader"];
                    NSString *msg = [NSString stringWithFormat:@"整合包 '%@' 已成功导入。", modpackInfo[@"name"]];
                    if ([loader isEqualToString:@"Forge"] || [loader isEqualToString:@"NeoForge"]) {
                        msg = [msg stringByAppendingFormat:@"\n\n注意: 此整合包使用 %@ %@ 加载器，请先通过下载界面手动安装该加载器版本，否则启动会失败。", loader, modpackInfo[@"loaderVersion"]];
                    }
                    [self showAlertWithTitle:@"导入成功" message:msg completion:^{
                        [self loadImportedModpacks];
                    }];
                } else {
                    [self showAlertWithTitle:@"导入失败" message:error.localizedDescription ?: @"未知错误"];
                }
            });
        });
    });
}

#pragma mark - UITableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.importedModpacks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModpackCell" forIndexPath:indexPath];
    // 重置 cell 样式
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    for (UIView *subview in cell.contentView.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]]) {
            [subview removeFromSuperview];
        }
    }

    NSDictionary *modpack = self.importedModpacks[indexPath.row];
    NSString *name = modpack[@"name"] ?: @"未知";
    NSString *mcVersion = modpack[@"minecraftVersion"] ?: @"未知";
    NSString *loader = modpack[@"loader"] ?: @"未知";

    cell.textLabel.text = name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Minecraft %@ - %@", mcVersion, loader];
    cell.imageView.image = [UIImage systemImageNamed:@"archivebox"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *blurView = LGCCreateGlassEffectView(NO);
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.layer.cornerRadius = 12;
    blurView.layer.masksToBounds = YES;
    [cell.contentView insertSubview:blurView atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
        [blurView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
        [blurView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        [blurView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4]
    ]];
    cell.backgroundView = nil;
    return cell;
}

#pragma mark - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *modpack = self.importedModpacks[indexPath.row];
    [self showModpackOptions:modpack];
}

- (void)showModpackOptions:(NSDictionary *)modpack {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:modpack[@"name"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"启动整合包" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self launchModpack:modpack];
    }]];
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteModpack:modpack];
    }]];
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = self.view;
        actionSheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)launchModpack:(NSDictionary *)modpack {
    NSString *profileName = modpack[@"profileName"];
    if (profileName && PLProfiles.current.profiles[profileName]) {
        PLProfiles.current.selectedProfileName = profileName;
        [self showAlertWithTitle:@"配置文件已选择" message:[NSString stringWithFormat:@"已切换到整合包配置文件: %@", profileName]];
    } else {
        [self showAlertWithTitle:@"错误" message:@"找不到整合包配置文件"];
    }
}

- (void)deleteModpack:(NSDictionary *)modpack {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"确认删除" message:[NSString stringWithFormat:@"删除整合包 '%@'？此操作无法撤销。", modpack[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self showProgressCardWithTitle:@"正在删除"];
        [self setProgress:-1 stageMessage:@"正在删除整合包文件..."];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            BOOL success = [self.importService deleteModpack:modpack error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideProgressCard];
                if (success) {
                    [self loadImportedModpacks];
                } else {
                    [self showAlertWithTitle:@"删除失败" message:error.localizedDescription];
                }
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - 辅助方法

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [self showAlertWithTitle:title message:message completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message completion:(void (^ _Nullable)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion();
    }]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BackgroundManager sharedManager] applyEffectToView:self.view];
        [self.tableView reloadData];
    });
}

#pragma mark - 整合包导出（参照 FCL ExportModpackViewModel / HMCL ModpackHelper）

- (void)showExportProfilePicker {
    NSDictionary *profiles = PLProfiles.current.profiles;
    NSArray *profileNames = profiles.allKeys;

    if (profileNames.count == 0) {
        [self showAlertWithTitle:@"无法导出" message:@"当前没有任何可导出的游戏配置文件"];
        return;
    }

    // 优先使用当前选中 profile
    NSString *selected = PLProfiles.current.selectedProfileName;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择要导出的配置文件"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in profileNames) {
        NSString *title = name;
        if ([name isEqualToString:selected]) {
            title = [NSString stringWithFormat:@"%@ (当前)", name];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self showExportFormatPickerForProfile:name];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showExportFormatPickerForProfile:(NSString *)profileName {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择导出格式"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Modrinth (.mrpack)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showExportInfoAlertForProfile:profileName format:ModpackExportFormatModrinth];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"CurseForge (.zip)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showExportInfoAlertForProfile:profileName format:ModpackExportFormatCurseForge];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"链接列表 (.txt)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showExportInfoAlertForProfile:profileName format:ModpackExportFormatLinkList];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showExportInfoAlertForProfile:(NSString *)profileName format:(ModpackExportFormat)format {
    // 预填名称和版本
    NSDictionary *profile = PLProfiles.current.profiles[profileName];
    NSString *lastVersionId = profile[@"lastVersionId"] ?: @"";
    NSDictionary *parsed = [ModpackExportService parseVersionId:lastVersionId];
    NSString *defaultName = profileName;
    NSString *defaultVersion = @"1.0";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出整合包"
                                                                   message:@"请输入整合包信息"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"整合包名称";
        textField.text = defaultName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"版本号";
        textField.text = defaultVersion;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"作者";
        textField.text = @"Amethyst User";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = alert.textFields[0].text ?: @"";
        NSString *version = alert.textFields[1].text ?: @"1.0";
        NSString *author = alert.textFields[2].text ?: @"Amethyst User";
        if (name.length == 0) name = profileName;
        if (version.length == 0) version = @"1.0";
        (void)parsed;
        [self startExportForProfile:profileName name:name version:version author:author format:format];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startExportForProfile:(NSString *)profileName
                         name:(NSString *)name
                      version:(NSString *)version
                       author:(NSString *)author
                       format:(ModpackExportFormat)format {
    // 确定文件扩展名
    NSString *ext = @"mrpack";
    switch (format) {
        case ModpackExportFormatModrinth:   ext = @"mrpack"; break;
        case ModpackExportFormatCurseForge: ext = @"zip";    break;
        case ModpackExportFormatLinkList:   ext = @"txt";    break;
    }

    // 构造导出路径到 Documents/Exports/
    NSString *exportsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Exports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:exportsDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 清理文件名中的非法字符
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString *safeName = [[name componentsSeparatedByCharactersInSet:invalidChars] componentsJoinedByString:@"_"];

    NSString *destPath = [exportsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-v%@.%@", safeName, version, ext]];

    // 显示进度卡片
    [self showProgressCardWithTitle:@"正在导出整合包"];
    [self setProgress:0.0 stageMessage:@"准备中..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL success = [[ModpackExportService sharedService] exportModpackForProfile:profileName
                                                                               toPath:destPath
                                                                                  name:name
                                                                               version:version
                                                                                author:author
                                                                                format:format
                                                                      includeOverrides:YES
                                                                             progress:^(double p, NSString *stageMessage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setProgress:p stageMessage:stageMessage];
            });
        }
                                                                                  error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideProgressCard];
            if (success) {
                [self showExportSuccessWithPath:destPath];
            } else {
                NSString *msg = error.localizedDescription ?: @"未知错误";
                [self showAlertWithTitle:@"导出失败" message:msg];
            }
        });
    });
}

- (void)showExportSuccessWithPath:(NSString *)path {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出成功"
                                                                   message:[NSString stringWithFormat:@"整合包已保存到：\n%@", path]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self shareExportedFile:path];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareExportedFile:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

@end