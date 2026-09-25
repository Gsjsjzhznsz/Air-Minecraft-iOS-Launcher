#import "LauncherHelpViewController.h"
#import "BackgroundManager.h"
#import "LauncherPreferences.h"
#import "utils.h"

// ============================================================================
// Task 82：启动器"使用问题"（FAQ）页面
//
// 左侧边栏新增"使用问题"标签，收录项目迭代中反复出现的用户问题与结论
// （每条都来自真实日志判读，非泛泛帮助文案）。语言跟随本 fork 的 AI 模块
// 先例：直接使用中文（用户主语言），不做 54 语言 l10n。
//
// 交互：按分类分组，点击问题行展开/收起答案，同一时刻允许多条同时展开。
// ============================================================================

@interface LauncherHelpFaqItem : NSObject
@property (nonatomic, copy) NSString *question;
@property (nonatomic, copy) NSString *answer;
@property (nonatomic, copy) NSString *iconName;
@end

@implementation LauncherHelpFaqItem
@end

@interface LauncherHelpViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSArray<NSArray<LauncherHelpFaqItem *> *> *itemsByCategory;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *expandedPaths;
@end

@implementation LauncherHelpViewController

#pragma mark - Data

- (void)buildFaqData {
    // Task168：条目数据源迁移到随包 JSON（与启动器公告同模式，双文件对齐：
    // 仓库根 help-faq.json = 维护源，Natives/resources/help-faq.json = 随包
    // 运行时读取，两文件逐字节一致由 verify_task168 把守漂移）。条目字段：
    // icon（SF Symbols 名）/ title（标题）/ description（简介）。
    // 历史口径不变：本页自 Task82 起为纯中文页面（不做 54 语言 l10n），
    // JSON 内容同口径——条目为项目 worklog 定案的真实结论，非泛泛帮助文案。
    // 解析失败时页面呈现空分组（不崩溃），日志留痕便于发现坏包。
    NSString *path = [NSBundle.mainBundle pathForResource:@"help-faq" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *cats = [root isKindOfClass:[NSDictionary class]] ? root[@"categories"] : nil;

    NSMutableArray<NSString *> *catNames = [NSMutableArray array];
    NSMutableArray<NSArray<LauncherHelpFaqItem *> *> *itemsByCat = [NSMutableArray array];
    for (NSDictionary *cat in [cats isKindOfClass:[NSArray class]] ? cats : @[]) {
        if (![cat isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = [cat[@"name"] isKindOfClass:[NSString class]] ? cat[@"name"] : @"";
        if (name.length == 0) continue;
        NSMutableArray<LauncherHelpFaqItem *> *items = [NSMutableArray array];
        for (NSDictionary *raw in [cat[@"items"] isKindOfClass:[NSArray class]] ? cat[@"items"] : @[]) {
            if (![raw isKindOfClass:[NSDictionary class]]) continue;
            NSString *title = [raw[@"title"] isKindOfClass:[NSString class]] ? raw[@"title"] : @"";
            NSString *desc = [raw[@"description"] isKindOfClass:[NSString class]] ? raw[@"description"] : @"";
            if (title.length == 0 || desc.length == 0) continue;
            LauncherHelpFaqItem *item = [[LauncherHelpFaqItem alloc] init];
            item.question = title;
            item.answer = desc;
            item.iconName = ([raw[@"icon"] isKindOfClass:[NSString class]] && [(NSString *)raw[@"icon"] length] > 0)
                ? (NSString *)raw[@"icon"] : @"questionmark.circle";
            [items addObject:item];
        }
        if (items.count == 0) continue;
        [catNames addObject:name];
        [itemsByCat addObject:[items copy]];
    }
    if (catNames.count == 0) {
        NSLog(@"[LauncherHelp] Task168 help-faq.json missing/unparsable -- FAQ rendered empty");
    }
    self.categories = [catNames copy];
    self.itemsByCategory = [itemsByCat copy];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"使用问题";

    // 与其他内容页一致：透出全局背景（图片/视频/毛玻璃）
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.expandedPaths = [NSMutableSet set];
    [self buildFaqData];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HelpFaqCell"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 收起大标题，保持列表可视面积
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.categories.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.categories[section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.itemsByCategory[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HelpFaqCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor secondarySystemBackgroundColor];

    LauncherHelpFaqItem *item = self.itemsByCategory[indexPath.section][indexPath.row];
    BOOL expanded = [self.expandedPaths containsObject:@(indexPath.row * 1000 + indexPath.section)];

    // 问题行：图标 + 问题 + 展开指示箭头
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:item.question
                                                                              attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor
    }];
    if (expanded) {
        // 答案直接拼进同一 cell（动态行高展开），问题与答案之间空一行
        NSString *answerBlock = [NSString stringWithFormat:@"\n\n%@", item.answer];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:answerBlock
                                                                       attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:14],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor
        }]];
    }
    cell.textLabel.attributedText = title;
    cell.textLabel.numberOfLines = 0;

    UIImage *icon = [UIImage systemImageNamed:item.iconName];
    cell.imageView.image = [icon imageWithTintColor:accentColor()
                              renderingMode:UIImageRenderingModeAlwaysOriginal];

    cell.accessoryType = expanded ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.row * 1000 + indexPath.section);
    if ([self.expandedPaths containsObject:key]) {
        [self.expandedPaths removeObject:key];
    } else {
        [self.expandedPaths addObject:key];
    }
    // 只刷新这一行（展开/收起动画），避免整表 reload 造成的滚动位置跳动
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

@end
