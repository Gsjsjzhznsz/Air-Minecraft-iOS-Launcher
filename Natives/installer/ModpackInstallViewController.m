#import "ModpackInstallViewController.h"
#import "BackgroundManager.h"
#import "LiquidGlassCompat.h"
#import "InlineMessageView.h"
#import "modpack/ModrinthAPI.h"
#import "MinecraftResourceDownloadTask.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "WFWorkflowProgressView.h"
#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import <dlfcn.h>

#define kCurseForgeGameIDMinecraft 432
#define kCurseForgeClassIDModpack 4471
#define kCurseForgeClassIDMod 6

@interface ModpackInstallViewController()<UIContextMenuInteractionDelegate>
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) UIMenu *currentMenu;
@property(nonatomic) NSMutableArray *list;
@property(nonatomic) NSMutableDictionary *filters;
@property ModrinthAPI *modrinth;
@property(nonatomic, strong) InlineMessageView *currentMessageView;
@property(nonatomic) NSIndexPath *loadingIndexPath;  // 当前正在加载版本的 indexPath
@end

@implementation ModpackInstallViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[BackgroundManager sharedManager] applyEffectToView:self.view];
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    self.modrinth = [ModrinthAPI new];
    self.filters = @{
        @"isModpack": @(YES),
        @"projectType": @"modpack",
        @"name": @" "
    }.mutableCopy;
    [self updateSearchResults];
    
    // 设置表格样式
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBackgroundUIEffectChanged:)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"BackgroundUIEffectChanged" object:nil];
}

// 重写 tableView 的 getter 以修改背景（避免重复代码）
- (UITableView *)tableView {
    UITableView *tv = [super tableView];
    if (!tv) {
        tv = [super tableView];
    }
    return tv;
}

- (void)loadSearchResultsWithPrevList:(BOOL)prevList {
    NSString *name = self.searchController.searchBar.text;
    if (!prevList && [self.filters[@"name"] isEqualToString:name]) {
        return;
    }

    [self switchToLoadingState];
    // 显示内联加载提示（首次加载时）
    if (!prevList) {
        self.currentMessageView = [InlineMessageView showInViewController:self
                                                                    title:@"加载中"
                                                                 message:nil
                                                                    type:InlineMessageTypeLoading];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.filters[@"name"] = name;
        self.list = [self.modrinth searchModWithFilters:self.filters previousPageResult:prevList ? self.list : nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.currentMessageView dismiss];
            self.currentMessageView = nil;
            if (self.list) {
                [self switchToReadyState];
                [self.tableView reloadData];
            } else {
                // 在内容区显示错误，不再用弹窗
                self.currentMessageView = [InlineMessageView showInViewController:self
                                                                            title:localize(@"Error", nil)
                                                                         message:self.modrinth.lastError.localizedDescription
                                                                            type:InlineMessageTypeError];
                [self switchToReadyState];
            }
        });
    });
}

- (void)updateSearchResults {
    [self loadSearchResultsWithPrevList:NO];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateSearchResults) object:nil];
    [self performSelector:@selector(updateSearchResults) withObject:nil afterDelay:0.5];
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)switchToLoadingState {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:indicator];
    [indicator startAnimating];
    self.navigationController.modalInPresentation = YES;
    self.tableView.allowsSelection = NO;
}

- (void)switchToReadyState {
    UIActivityIndicatorView *indicator = (id)self.navigationItem.rightBarButtonItem.customView;
    [indicator stopAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = NO;
    self.tableView.allowsSelection = YES;
}

#pragma mark UIContextMenu

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return self.currentMenu;
    }];
}

// 修复：移除私有 _UIContextMenuStyle 方法，因为不需要自定义样式，系统默认样式即可

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.list.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 使用自定义卡片式单元格（ModernAssetCell 如果存在，否则回退）
    static NSString *cellIdentifier = @"ModpackCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        // 尝试使用 ModernAssetCell（如果存在）
        Class modernCellClass = NSClassFromString(@"ModernAssetCell");
        if (modernCellClass) {
            cell = [[modernCellClass alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
        }
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
        // iOS 26+ 液态玻璃 / 低版本毛玻璃效果卡片
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
    }

    NSDictionary *item = self.list[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"description"];
    cell.detailTextLabel.numberOfLines = 2;
    UIImage *fallbackImage = [UIImage imageNamed:@"DefaultProfile"];
    [cell.imageView setImageWithURL:[NSURL URLWithString:item[@"imageUrl"]] placeholderImage:fallbackImage];
    cell.imageView.layer.cornerRadius = 8;
    cell.imageView.clipsToBounds = YES;

    if (!self.modrinth.reachedLastPage && indexPath.row == self.list.count-1) {
        [self loadSearchResultsWithPrevList:YES];
    }

    return cell;
}

- (void)showDetails:(NSDictionary *)details atIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];

    NSMutableArray<UIAction *> *menuItems = [[NSMutableArray alloc] init];
    [details[@"versionNames"] enumerateObjectsUsingBlock:
    ^(NSString *name, NSUInteger i, BOOL *stop) {
        NSString *nameWithVersion = name;
        NSString *mcVersion = details[@"mcVersionNames"][i];
        if (![name hasSuffix:mcVersion]) {
            nameWithVersion = [NSString stringWithFormat:@"%@ - %@", name, mcVersion];
        }
        [menuItems addObject:[UIAction
            actionWithTitle:nameWithVersion
            image:nil identifier:nil
            handler:^(UIAction *action) {
            [self actionClose];
            NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
            
            // 修复：替换私有方法 _imageWithSize: 为公开缩放实现
            UIImage *originalImage = cell.imageView.image;
            if (originalImage) {
                CGSize targetSize = CGSizeMake(40, 40);
                UIGraphicsBeginImageContextWithOptions(targetSize, NO, 0.0);
                [originalImage drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
                UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                [UIImagePNGRepresentation(scaledImage) writeToFile:tmpIconPath atomically:YES];
            } else {
                // 如果没有图片，写入空数据或忽略
                [[NSData data] writeToFile:tmpIconPath atomically:YES];
            }
            
            [self.modrinth installModpackFromDetail:self.list[indexPath.row] atIndex:i];
        }]];
    }];

    self.currentMenu = [UIMenu menuWithTitle:@"" children:menuItems];
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    cell.detailTextLabel.interactions = @[interaction];
    // 修复：移除私有方法 _presentMenuAtLocation:，系统会在用户交互时自动显示菜单
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.list[indexPath.row];
    if ([item[@"versionDetailsLoaded"] boolValue]) {
        [self showDetails:item atIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    // 防止重复点击
    if (self.loadingIndexPath) return;
    self.loadingIndexPath = indexPath;

    // 在内容区中央显示加载提示（替代 nav bar 转圈，不阻塞）
    NSString *loadingTitle = [NSString stringWithFormat:@"\"%@\"", item[@"title"]];
    self.currentMessageView = [InlineMessageView showInViewController:self
                                                                title:loadingTitle
                                                             message:@"正在加载版本列表"
                                                                type:InlineMessageTypeLoading];

    // 使用异步加载，避免 dispatch_group_wait 同步阻塞（修复加载列表过慢）
    NSMutableDictionary *mutableItem = self.list[indexPath.row];
    __weak typeof(self) weakSelf = self;
    [self.modrinth loadDetailsOfModAsync:mutableItem completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.loadingIndexPath = nil;
            [strongSelf.currentMessageView dismiss];
            strongSelf.currentMessageView = nil;

            if (success && [mutableItem[@"versionDetailsLoaded"] boolValue]) {
                [strongSelf showDetails:mutableItem atIndexPath:indexPath];
            } else {
                // 在内容区显示错误，不弹窗
                NSString *errMsg = error.localizedDescription ?: strongSelf.modrinth.lastError.localizedDescription;
                strongSelf.currentMessageView = [InlineMessageView showInViewController:strongSelf
                                                                                  title:localize(@"Error", nil)
                                                                               message:errMsg
                                                                                  type:InlineMessageTypeError];
            }
        });
    }];
}

- (void)handleBackgroundUIEffectChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[BackgroundManager sharedManager] applyEffectToView:self.view];
        [self.tableView reloadData];
    });
}

@end