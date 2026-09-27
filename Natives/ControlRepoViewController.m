#import "ControlRepoViewController.h"
#import "NMToast.h"
#import "utils.h"
#import "LauncherPreferences.h"
#include <stdlib.h>  // getenv（POJAV_HOME；显式包含，不依赖伞头传递）

// 仓库远端：主源 raw.githubusercontent.com，回退 jsDelivr CDN（国内可达性）。
// 索引结构见仓库 controls/index.json：
//   { "version": 1, "layouts": [ { id/name/author/description/file/version/size } ] }
// 布局文件为编辑器 layoutDictionary 同构 JSON（mControlDataList 等键，
// dynamicX/dynamicY 相对定位表达式 => 分辨率无关、跨设备可分享）。
static NSString *const kTask188IndexPrimary =
    @"https://raw.githubusercontent.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/main/controls/index.json";
static NSString *const kTask188IndexFallback =
    @"https://cdn.jsdelivr.net/gh/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher@main/controls/index.json";
static NSString *const kTask188FilePrimaryFmt =
    @"https://raw.githubusercontent.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/main/controls/%@";
static NSString *const kTask188FileFallbackFmt =
    @"https://cdn.jsdelivr.net/gh/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher@main/controls/%@";

@interface ControlRepoViewController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *layouts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *localVersions;  // id -> 本地已装版本
@property (nonatomic, strong) NSHashTable *downloading;  // 正在下载的 id 集合（去重点击）
@property (nonatomic, assign) BOOL loadFailed;
@end

@implementation ControlRepoViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _layouts = [NSMutableArray array];
        _localVersions = [NSMutableDictionary dictionary];
        _downloading = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"custom_controls.repo.title", nil);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self action:@selector(refreshRepo:)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshRepo:)
                  forControlEvents:UIControlEventValueChanged];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    [self scanLocalVersions];
    [self fetchIndex];
}

/// 扫描本地 controlmap/ 的同名文件，计算"已下载/可更新"角标数据。
/// 仓库 id 与本地文件名一一对应（<id>.json），版本对比用仓库条目的
/// version 字段与本地无版本信息（旧文件）的区分。
- (void)scanLocalVersions {
    [self.localVersions removeAllObjects];
    NSString *dir = [NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *f in files) {
        if (![f.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSString *stem = [f stringByDeletingPathExtension];
        // 读取本地文件的 version 字段（存在才有），无则记为 "?"（已下载旧版）
        NSString *p = [dir stringByAppendingPathComponent:f];
        NSData *d = [NSData dataWithContentsOfFile:p];
        if (!d) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        id v = [(NSDictionary *)obj objectForKey:@"version"];
        self.localVersions[stem] = [v isKindOfClass:[NSString class]] ? v :
                                   ([v respondsToSelector:@selector(stringValue)] ? [v stringValue] : @"?");
    }
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)refreshRepo:(id)sender {
    [self fetchIndex];
}

- (void)fetchIndex {
    [self.refreshControl beginRefreshing];
    [self fetchURL:kTask188IndexPrimary
        fallback:kTask188IndexFallback
        completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
            if (!data || error) {
                NSLog(@"[ControlRepo] Task188: index fetch failed: %@", error.localizedDescription ?: @"unknown");
                self.loadFailed = YES;
                [self.layouts removeAllObjects];
                [self.tableView reloadData];
                return;
            }
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *arr = ([obj isKindOfClass:[NSDictionary class]]) ? obj[@"layouts"] : nil;
            if (![arr isKindOfClass:[NSArray class]]) {
                NSLog(@"[ControlRepo] Task188: index JSON invalid (no layouts array)");
                self.loadFailed = YES;
                [self.layouts removeAllObjects];
                [self.tableView reloadData];
                return;
            }
            self.loadFailed = NO;
            [self.layouts removeAllObjects];
            for (NSDictionary *e in arr) {
                if ([e isKindOfClass:[NSDictionary class]] && [e[@"id"] isKindOfClass:[NSString class]]) {
                    [self.layouts addObject:e];
                }
            }
            NSLog(@"[ControlRepo] Task188: index loaded, %lu layouts", (unsigned long)self.layouts.count);
            [self scanLocalVersions];
        });
    }];
}

- (void)fetchURL:(NSString *)primary fallback:(NSString *)fallback
      completion:(void (^)(NSData *, NSError *))completion {
    [self fetchOneURL:primary completion:^(NSData *data, NSError *err) {
        if (data && !err) { completion(data, nil); return; }
        [self fetchOneURL:fallback completion:^(NSData *d2, NSError *e2) {
            completion(d2, e2 ?: err);
        }];
    }];
}

- (void)fetchOneURL:(NSString *)urlString completion:(void (^)(NSData *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { completion(nil, [NSError errorWithDomain:@"ControlRepo" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"invalid url"}]); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) { completion(nil, error); return; }
        if ([resp isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse *)resp statusCode] >= 400) {
            completion(nil, [NSError errorWithDomain:@"ControlRepo" code:[(NSHTTPURLResponse *)resp statusCode]
                                          userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP %ld", (long)[(NSHTTPURLResponse *)resp statusCode]}]]);
            return;
        }
        completion(data, nil);
    }];
    [task resume];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.loadFailed ? 1 : (self.layouts.count == 0 ? 1 : self.layouts.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *rid = @"Task188RepoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.numberOfLines = 0;
    }
    if (self.loadFailed || self.layouts.count == 0) {
        cell.textLabel.text = self.loadFailed ? localize(@"custom_controls.repo.fetch.failed", nil)
                                              : localize(@"custom_controls.repo.empty", nil);
        cell.detailTextLabel.text = self.loadFailed ? localize(@"custom_controls.repo.retry_hint", nil) : @"";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *e = self.layouts[indexPath.row];
    cell.textLabel.text = [e[@"name"] isKindOfClass:[NSString class]] ? e[@"name"] : e[@"id"];
    NSString *author = [e[@"author"] isKindOfClass:[NSString class]] ? e[@"author"] : @"?";
    NSString *desc = [e[@"description"] isKindOfClass:[NSString class]] ? e[@"description"] : @"";
    NSString *ver = [e[@"version"] isKindOfClass:[NSString class]] ? e[@"version"] : @"1.0";
    NSMutableString *sub = [NSMutableString string];
    NSString *local = self.localVersions[e[@"id"]];
    if (local != nil) {
        [sub appendFormat:@"%@", [NSString stringWithFormat:localize(@"custom_controls.repo.installed", nil), local]];
        if (![local isEqualToString:ver]) {
            [sub appendFormat:@" · %@", [NSString stringWithFormat:localize(@"custom_controls.repo.update_available", nil), ver]];
        }
    } else {
        [sub appendString:[NSString stringWithFormat:localize(@"custom_controls.repo.author", nil), author]];
    }
    if (desc.length > 0) [sub appendFormat:@"\n%@", desc];
    cell.detailTextLabel.text = sub;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.loadFailed || self.layouts.count == 0) {
        if (self.loadFailed) [self fetchIndex];
        return;
    }
    NSDictionary *e = self.layouts[indexPath.row];
    NSString *layoutId = e[@"id"];
    if ([self.downloading containsObject:layoutId]) return;  // 防连点
    [self.downloading addObject:layoutId];
    NSString *file = [e[@"file"] isKindOfClass:[NSString class]] ? e[@"file"] :
                     [NSString stringWithFormat:@"layouts/%@.json", layoutId];
    NSLog(@"[ControlRepo] Task188: downloading layout %@ (%@)", layoutId, file);
    NSString *primary = [NSString stringWithFormat:kTask188FilePrimaryFmt, file];
    NSString *fallback = [NSString stringWithFormat:kTask188FileFallbackFmt, file];
    [self fetchURL:primary fallback:fallback completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.downloading removeObject:layoutId];
            if (!data || error) {
                NSLog(@"[ControlRepo] Task188: layout download failed: %@", error.localizedDescription ?: @"unknown");
                [NMToast showMessage:[NSString stringWithFormat:@"%@\n%@", localize(@"custom_controls.repo.download.failed", nil), error.localizedDescription ?: @""]];
                return;
            }
            // 校验：必须是 layoutDictionary 同构（顶层 dict + mControlDataList 数组），
            // 拦截被 CDN/代理污染的 HTML 错误页等。
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![obj isKindOfClass:[NSDictionary class]] ||
                ![[obj objectForKey:@"mControlDataList"] isKindOfClass:[NSArray class]]) {
                NSLog(@"[ControlRepo] Task188: layout JSON invalid (not a control layout)");
                [NMToast showMessage:localize(@"custom_controls.repo.download.invalid", nil)];
                return;
            }
            NSString *dir = [NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")];
            ame188_ensureDirectoryHealed(dir);
            NSString *dest = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", layoutId]];
            if (![data writeToFile:dest options:NSDataWritingAtomic error:nil]) {
                [NMToast showMessage:localize(@"custom_controls.repo.download.failed", nil)];
                return;
            }
            NSLog(@"[ControlRepo] Task188: layout saved -> %@", dest);
            [self scanLocalVersions];
            [NMToast showMessage:[NSString stringWithFormat:localize(@"custom_controls.repo.download.done", nil), layoutId]];
            if (self.whenLayoutDownloaded) self.whenLayoutDownloaded(layoutId);
        });
    }];
}

@end
