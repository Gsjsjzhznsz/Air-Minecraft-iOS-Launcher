#import "utils.h"
#import "DownloadHistoryViewController.h"
#import "DownloadHistoryStore.h"
#import "DownloadTaskItem.h"
#import "BackgroundManager.h"

static NSString * const kHistoryCellReuseIdentifier = @"DownloadHistoryCell";

/// 历史条目 cell：名称 + 类型/大小/结果副标题 + 时间（右侧）
@interface DownloadHistoryEntryCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *timeLabel;

- (void)configureWithEntry:(NSDictionary *)entry typeDisplayName:(NSString *)typeDisplayName;

@end

@implementation DownloadHistoryEntryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.font = [UIFont boldSystemFontOfSize:15];
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.numberOfLines = 1;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:self.nameLabel];

        self.detailLabel = [[UILabel alloc] init];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [UIFont systemFontOfSize:12];
        self.detailLabel.textColor = [UIColor secondaryLabelColor];
        self.detailLabel.numberOfLines = 1;
        [self.contentView addSubview:self.detailLabel];

        self.timeLabel = [[UILabel alloc] init];
        self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.timeLabel.textColor = [UIColor tertiaryLabelColor];
        self.timeLabel.textAlignment = NSTextAlignmentRight;
        self.timeLabel.numberOfLines = 2;
        [self.contentView addSubview:self.timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.timeLabel.leadingAnchor constant:-8],

            [self.detailLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:3],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
            [self.detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.timeLabel.leadingAnchor constant:-8],
            [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],

            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
            [self.timeLabel.widthAnchor constraintLessThanOrEqualToConstant:110],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.text = nil;
    self.detailLabel.text = nil;
    self.timeLabel.text = nil;
}

- (void)configureWithEntry:(NSDictionary *)entry typeDisplayName:(NSString *)typeDisplayName {
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    self.nameLabel.text = name.length > 0 ? name : localize(@"i18n_str_107", nil);

    // 大小（记录的是任务总大小）
    long long size = [entry[@"size"] longLongValue];
    NSString *sizeText = size > 0 ? [NSByteCountFormatter stringFromByteCount:size
                                                                  countStyle:NSByteCountFormatterCountStyleFile]
                                  : @"--";

    // 结果（当前历史仅记录成功条目）
    NSString *resultRaw = [entry[@"result"] isKindOfClass:[NSString class]] ? entry[@"result"] : @"success";
    NSString *resultText = [resultRaw isEqualToString:@"success"]
        ? localize(@"download.history.result.success", nil)
        : localize(@"download.history.result.failed", nil);

    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                             typeDisplayName ?: @"--", sizeText, resultText];

    // 时间（右侧，两行：日期 + 时间）
    NSTimeInterval timestamp = [entry[@"time"] doubleValue];
    if (timestamp > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
        static NSDateFormatter *dateFormatter = nil;
        static NSDateFormatter *timeFormatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateStyle = NSDateFormatterMediumStyle;
            dateFormatter.timeStyle = NSDateFormatterNoStyle;
            timeFormatter = [[NSDateFormatter alloc] init];
            timeFormatter.dateStyle = NSDateFormatterNoStyle;
            timeFormatter.timeStyle = NSDateFormatterShortStyle;
        });
        self.timeLabel.text = [NSString stringWithFormat:@"%@\n%@",
                               [dateFormatter stringFromDate:date],
                               [timeFormatter stringFromDate:date]];
    } else {
        self.timeLabel.text = @"";
    }
}

@end

#pragma mark - Controller

@interface DownloadHistoryViewController ()

@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) UILabel *emptyLabel;

@end

@implementation DownloadHistoryViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.entries = @[];
    }
    return self;
}

// 统一使用 InsetGrouped 卡片风格，忽略外部传入的 style
- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [self init];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    return [self init];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.entries = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 适配自定义启动器背景：透明化当前视图控制器，使全局背景壁纸透出（与下载中心一致）
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.title = localize(@"download.history.title", nil);

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:localize(@"download.history.clear", nil)
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(clearTapped:)];

    [self reloadEntries];
}

- (void)reloadEntries {
    self.entries = [[DownloadHistoryStore sharedStore] allEntries] ?: @[];
    [self.tableView reloadData];
    [self updateEmptyState];
}

/// 空态占位文案（无下拉刷新，进入页面读取一次即可）
- (void)updateEmptyState {
    if (self.entries.count > 0) {
        [self.emptyLabel removeFromSuperview];
        self.emptyLabel = nil;
        self.tableView.tableHeaderView = nil;
        return;
    }

    if (!self.emptyLabel) {
        self.emptyLabel = [[UILabel alloc] init];
        self.emptyLabel.font = [UIFont systemFontOfSize:16];
        self.emptyLabel.textColor = [UIColor secondaryLabelColor];
        self.emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.emptyLabel.numberOfLines = 0;
    }
    self.emptyLabel.text = localize(@"download.history.empty", nil);

    // 用 tableHeaderView 承载居中空态，避免遮挡导航栏
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 240)];
    self.emptyLabel.frame = CGRectMake(24, 60, header.bounds.size.width - 48, 60);
    [header addSubview:self.emptyLabel];
    self.tableView.tableHeaderView = header;
}

#pragma mark - Actions

- (void)clearTapped:(UIBarButtonItem *)sender {
    if (self.entries.count == 0) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"download.history.title", nil)
                         message:localize(@"download.history.clear_confirm", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
        actionWithTitle:localize(@"download.history.clear", nil)
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
        [[DownloadHistoryStore sharedStore] clearAll];
        [self reloadEntries];
    }]];
    [alert addAction:[UIAlertAction
        actionWithTitle:localize(@"download.history.cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DownloadHistoryEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:kHistoryCellReuseIdentifier];
    if (!cell) {
        cell = [[DownloadHistoryEntryCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:kHistoryCellReuseIdentifier];
    }
    NSDictionary *entry = self.entries[indexPath.row];
    NSString *type = [entry[@"type"] isKindOfClass:[NSString class]] ? entry[@"type"] : @"";
    [cell configureWithEntry:entry typeDisplayName:[self displayNameForResourceType:type]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0;
}

#pragma mark - 工具方法

/// 资源类型显示名（与 DownloadTasksViewController 的映射保持一致）
- (NSString *)displayNameForResourceType:(NSString *)type {
    NSDictionary *map = @{
        DownloadTaskResourceTypeMinecraft: localize(@"i18n_str_113", nil),
        DownloadTaskResourceTypeModloader: localize(@"i18n_str_114", nil),
        DownloadTaskResourceTypeMod: @"Mod",
        DownloadTaskResourceTypeShader: localize(@"i18n_str_115", nil),
        DownloadTaskResourceTypeResourcePack: localize(@"i18n_str_116", nil),
        DownloadTaskResourceTypeDataPack: localize(@"i18n_str_117", nil),
        DownloadTaskResourceTypeModpack: localize(@"i18n_str_118", nil),
        DownloadTaskResourceTypeWorld: localize(@"i18n_str_119", nil),
        DownloadTaskResourceTypeJavaRuntime: localize(@"i18n_str_120", nil)
    };
    return map[type] ?: (type.length > 0 ? type : localize(@"i18n_str_121", nil));
}

@end
