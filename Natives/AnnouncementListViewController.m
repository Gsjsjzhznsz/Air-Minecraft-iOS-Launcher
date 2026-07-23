//
//  AnnouncementListViewController.m
//  Amethyst
//

#import "AnnouncementListViewController.h"
#import "AnnouncementService.h"
#import "AnnouncementItem.h"
#import "AnnouncementDetailViewController.h"
#import "BackgroundManager.h"

/// 卡片间距
static const CGFloat kAnnCardSpacing = 12.0;
/// 卡片内边距
static const CGFloat kAnnCardPadding = 14.0;
/// 卡片圆角
static const CGFloat kAnnCardCornerRadius = 14.0;
/// 高优先级卡片左侧条宽度
static const CGFloat kAnnHighPriorityBarWidth = 4.0;

#pragma mark - AnnouncementCardCell

@interface AnnouncementCardCell : UICollectionViewCell
@property (nonatomic, strong) UIView *priorityBarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation AnnouncementCardCell

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.dateLabel.text = nil;
    self.summaryLabel.text = nil;
    self.priorityBarView.hidden = YES;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = kAnnCardCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        self.contentView.layer.cornerRadius = kAnnCardCornerRadius;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.clipsToBounds = YES;

        // 高优先级左侧条（默认隐藏）
        _priorityBarView = [[UIView alloc] init];
        _priorityBarView.translatesAutoresizingMaskIntoConstraints = NO;
        _priorityBarView.backgroundColor = [UIColor systemBlueColor];
        _priorityBarView.hidden = YES;
        [self.contentView addSubview:_priorityBarView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
        _dateLabel.textColor = [UIColor tertiaryLabelColor];
        _dateLabel.numberOfLines = 1;
        [self.contentView addSubview:_dateLabel];

        _summaryLabel = [[UILabel alloc] init];
        _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _summaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _summaryLabel.textColor = [UIColor secondaryLabelColor];
        _summaryLabel.numberOfLines = 2;
        [self.contentView addSubview:_summaryLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_priorityBarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_priorityBarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_priorityBarView.widthAnchor constraintEqualToConstant:kAnnHighPriorityBarWidth],
            [_priorityBarView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:kAnnCardPadding],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kAnnCardPadding],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kAnnCardPadding],

            [_dateLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6],
            [_dateLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

            [_summaryLabel.topAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor constant:8],
            [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_summaryLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_summaryLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kAnnCardPadding],
        ]];
    }
    return self;
}

- (void)configureWithItem:(AnnouncementItem *)item {
    self.titleLabel.text = item.title ?: @"";
    self.dateLabel.text = item.formattedDateString ?: @"";
    self.summaryLabel.text = item.summary ?: @"";
    // priority=high 时显示左侧蓝色条
    if ([item.priority caseInsensitiveCompare:@"high"] == NSOrderedSame) {
        self.priorityBarView.hidden = NO;
    } else {
        self.priorityBarView.hidden = YES;
    }
}

@end

#pragma mark - AnnouncementListViewController

@interface AnnouncementListViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSArray<AnnouncementItem *> *items;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation AnnouncementListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"公告";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // 适配自定义启动器背景
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.items = @[];

    [self setupNavBar];
    [self setupUI];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.backgroundView = nil;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    [self loadAnnouncements];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.backgroundView = nil;
    [self.collectionView reloadData];
}

- (void)setupNavBar {
    // 左上角关闭按钮
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                target:self
                                                                                action:@selector(closeAction)];
    self.navigationItem.leftBarButtonItem = closeItem;

    // 右上角刷新按钮
    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                  target:self
                                                                                  action:@selector(forceRefreshAction)];
    self.navigationItem.rightBarButtonItem = refreshItem;
}

- (void)setupUI {
    // 双列自适应布局（estimated height）
    UICollectionViewLayout *layout = [self createCompositionalLayout];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[AnnouncementCardCell class] forCellWithReuseIdentifier:@"AnnouncementCardCell"];
    self.collectionView.contentInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [self.view addSubview:self.collectionView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(forceRefreshAction) forControlEvents:UIControlEventValueChanged];
    [self.collectionView addSubview:self.refreshControl];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.textColor = [UIColor secondaryLabelColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.retryButton setTitle:@"重试" forState:UIControlStateNormal];
    self.retryButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.retryButton addTarget:self action:@selector(loadAnnouncements) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.errorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],

        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.retryButton.topAnchor constraintEqualToAnchor:self.errorLabel.bottomAnchor constant:12],
    ]];
}

/// 双列自适应高度布局
- (UICollectionViewLayout *)createCompositionalLayout {
    UICollectionViewCompositionalLayoutConfiguration *config = [[UICollectionViewCompositionalLayoutConfiguration alloc] init];
    config.interSectionSpacing = kAnnCardSpacing;
    config.scrollDirection = UICollectionViewScrollDirectionVertical;

    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
        NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]
                                                                            heightDimension:[NSCollectionLayoutDimension estimatedDimension:160]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                                                                                             heightDimension:[NSCollectionLayoutDimension estimatedDimension:160]]
                                                                                      subitems:@[item]];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:kAnnCardSpacing];

        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.interGroupSpacing = kAnnCardSpacing;
        section.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
        return section;
    } configuration:config];
}

#pragma mark - Data Loading

- (void)loadAnnouncements {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.errorLabel.hidden = YES;
    self.retryButton.hidden = YES;
    if (self.items.count == 0) {
        [self.activityIndicator startAnimating];
    }

    __weak typeof(self) weakSelf = self;
    [[AnnouncementService sharedService] fetchAnnouncementsWithCompletion:^(NSArray<AnnouncementItem *> *items, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isLoading = NO;
        [strongSelf.activityIndicator stopAnimating];
        [strongSelf.refreshControl endRefreshing];

        if (error && (!items || items.count == 0)) {
            strongSelf.errorLabel.text = [NSString stringWithFormat:@"加载失败\n%@", error.localizedDescription ?: @""];
            strongSelf.errorLabel.hidden = NO;
            strongSelf.retryButton.hidden = NO;
            return;
        }

        strongSelf.items = items ?: @[];
        [strongSelf.collectionView reloadData];
    }];
}

- (void)forceRefreshAction {
    if (self.isLoading) return;
    self.isLoading = YES;
    if (self.items.count == 0) {
        [self.activityIndicator startAnimating];
    }

    __weak typeof(self) weakSelf = self;
    [[AnnouncementService sharedService] forceRefreshWithCompletion:^(NSArray<AnnouncementItem *> *items, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isLoading = NO;
        [strongSelf.activityIndicator stopAnimating];
        [strongSelf.refreshControl endRefreshing];

        if (error && (!items || items.count == 0)) {
            strongSelf.errorLabel.text = [NSString stringWithFormat:@"加载失败\n%@", error.localizedDescription ?: @""];
            strongSelf.errorLabel.hidden = NO;
            strongSelf.retryButton.hidden = NO;
            return;
        }

        strongSelf.items = items ?: @[];
        strongSelf.errorLabel.hidden = YES;
        strongSelf.retryButton.hidden = YES;
        [strongSelf.collectionView reloadData];
    }];
}

- (void)closeAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    AnnouncementCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AnnouncementCardCell" forIndexPath:indexPath];
    AnnouncementItem *item = self.items[indexPath.item];
    [cell configureWithItem:item];
    // 适配自定义启动器背景
    [[BackgroundManager sharedManager] applyEffectToCollectionViewCell:cell];
    return cell;
}

#pragma mark - UICollectionView Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    AnnouncementItem *item = self.items[indexPath.item];
    AnnouncementDetailViewController *detailVC = [[AnnouncementDetailViewController alloc] initWithAnnouncement:item];
    [self.navigationController pushViewController:detailVC animated:YES];
}

@end
