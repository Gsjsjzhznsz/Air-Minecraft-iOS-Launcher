// DGSortOrderViewController.m
// DesktopGlues MultiDraw 方案排序 + 基准测试界面（对齐 Android 版 MobileGlues 的
// "benchmark and sort" 功能）。
//
// - 顶部提供"运行基准测试"按钮：在后台线程 dlopen libdesktopglues.dylib，经渲染器
//   自己的 EGL 层创建上下文，调用 mg_multidraw_bench_run() 测量每个入口点每个后端的
//   耗时，主线程轮询 mg_multidraw_bench_progress() 显示进度。
// - 测试完成后弹出结果，用户可选择"采用"：把每个入口点按测得耗时从快到慢排序，
//   写入 desktopglues.multidraw_order_<entry> 偏好（JavaLauncher 会转成
//   multidrawOrder<EntryPoint> 写入 config.json）。
// - 每个入口点一个 section，支持拖拽排序后端优先级。

#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import <EGL/egl.h>

#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// ============================================================================
#pragma mark - DGBench：基准测试桥接（dlopen + EGL 上下文 + 调用原生 bench）
// ============================================================================

@interface DGBench : NSObject
/// 在后台线程调用：dlopen 渲染器、创建 EGL 上下文并设为当前。必须在执行
/// runBenchmark 的同一线程上调用（EGL 上下文与线程绑定）。
+ (BOOL)prepareWithError:(NSString **)error;
/// 阻塞运行基准测试（默认预算约 8 秒），返回 JSON 字符串。
+ (NSString *)runBenchmark;
/// 当前进度原始编码（attempt*1000+permille），-1 表示没有进度。可跨线程调用。
+ (int)rawProgress;
/// 清理 EGL 上下文（在后台线程调用）。
+ (void)cleanup;
@end

@implementation DGBench {
    void *_lib;
    EGLDisplay _dpy;
    EGLContext _ctx;
    EGLSurface _surf;
    const char *(*_benchRun)(int, int);
    int (*_benchProgress)(void);
}

static DGBench *g_bench = nil;

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g_bench = [DGBench new]; });
    return g_bench;
}

- (instancetype)init {
    self = [super init];
    _dpy = EGL_NO_DISPLAY;
    _ctx = EGL_NO_CONTEXT;
    _surf = EGL_NO_SURFACE;
    return self;
}

+ (BOOL)prepareWithError:(NSString **)error {
    DGBench *b = [self shared];
    if (b->_lib) return YES;

    // 与 Android 的 MGBench.run() 相同：先设置环境变量再 dlopen，渲染器在静态构造
    // 里读取它们（MG_DIR_PATH 指向 config.json 所在目录，MG_ANGLE_DIR 借用 ANGLE）。
    NSString *pojavHome = [NSString stringWithUTF8String:getenv("POJAV_HOME") ?: ""];
    NSString *mgDir = [pojavHome stringByAppendingPathComponent:@"MG"];
    setenv("MG_PLUGIN_STATUS", "1", 1);
    setenv("MG_DIR_PATH", mgDir.UTF8String, 1);
    setenv("MG_ANGLE_DIR", mgDir.UTF8String, 1);

    b->_lib = dlopen("@rpath/libdesktopglues.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (!b->_lib) {
        if (error) *error = [NSString stringWithFormat:@"dlopen libdesktopglues 失败: %s", dlerror()];
        return NO;
    }

    // 渲染器自己的 EGL 层（egl.cpp 导出 visibility(default) 的 wrapper）
    PFNEGLGETDISPLAYPROC eglGetDisplay = (PFNEGLGETDISPLAYPROC)dlsym(b->_lib, "eglGetDisplay");
    PFNEGLINITIALIZEPROC eglInitialize = (PFNEGLINITIALIZEPROC)dlsym(b->_lib, "eglInitialize");
    PFNEGLCHOOSECONFIGPROC eglChooseConfig = (PFNEGLCHOOSECONFIGPROC)dlsym(b->_lib, "eglChooseConfig");
    PFNEGLCREATECONTEXTPROC eglCreateContext = (PFNEGLCREATECONTEXTPROC)dlsym(b->_lib, "eglCreateContext");
    PFNEGLCREATEPBUFFERSURFACEPROC eglCreatePbufferSurface = (PFNEGLCREATEPBUFFERSURFACEPROC)dlsym(b->_lib, "eglCreatePbufferSurface");
    PFNEGLMAKECURRENTPROC eglMakeCurrent = (PFNEGLMAKECURRENTPROC)dlsym(b->_lib, "eglMakeCurrent");
    PFNEGLDESTROYCONTEXTPROC eglDestroyContext = (PFNEGLDESTROYCONTEXTPROC)dlsym(b->_lib, "eglDestroyContext");
    PFNEGLDESTROYSURFACEPROC eglDestroySurface = (PFNEGLDESTROYSURFACEPROC)dlsym(b->_lib, "eglDestroySurface");
    PFNEGLTERMINATEPROC eglTerminate = (PFNEGLTERMINATEPROC)dlsym(b->_lib, "eglTerminate");

    if (!eglGetDisplay || !eglInitialize || !eglChooseConfig || !eglCreateContext ||
        !eglCreatePbufferSurface || !eglMakeCurrent) {
        if (error) *error = @"渲染器 EGL 符号解析失败";
        return NO;
    }

    b->_dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (b->_dpy == EGL_NO_DISPLAY) { if (error) *error = @"eglGetDisplay 失败"; return NO; }
    if (!eglInitialize(b->_dpy, NULL, NULL)) { if (error) *error = @"eglInitialize 失败"; return NO; }

    const EGLint configAttribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };
    EGLConfig config;
    EGLint numConfigs = 0;
    if (!eglChooseConfig(b->_dpy, configAttribs, &config, 1, &numConfigs) || numConfigs < 1) {
        if (error) *error = @"eglChooseConfig 失败";
        return NO;
    }

    const EGLint ctxAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    b->_ctx = eglCreateContext(b->_dpy, config, EGL_NO_CONTEXT, ctxAttribs);
    if (b->_ctx == EGL_NO_CONTEXT) { if (error) *error = @"eglCreateContext 失败"; return NO; }

    const EGLint surfAttribs[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE };
    b->_surf = eglCreatePbufferSurface(b->_dpy, config, surfAttribs);
    if (b->_surf == EGL_NO_SURFACE) { if (error) *error = @"eglCreatePbufferSurface 失败"; return NO; }

    if (!eglMakeCurrent(b->_dpy, b->_surf, b->_surf, b->_ctx)) {
        if (error) *error = @"eglMakeCurrent 失败";
        return NO;
    }

    b->_benchRun = (const char *(*)(int, int))dlsym(b->_lib, "mg_multidraw_bench_run");
    b->_benchProgress = (int (*)(void))dlsym(b->_lib, "mg_multidraw_bench_progress");
    if (!b->_benchRun) {
        if (error) *error = @"mg_multidraw_bench_run 符号未找到";
        return NO;
    }
    return YES;
}

+ (NSString *)runBenchmark {
    DGBench *b = [self shared];
    if (!b->_benchRun) return @"{\"error\":\"bench not prepared\"}";
    const char *json = b->_benchRun(0, 0);
    return json ? [NSString stringWithUTF8String:json] : @"{\"error\":\"bench returned null\"}";
}

+ (int)rawProgress {
    DGBench *b = [self shared];
    if (!b->_benchProgress) return -1;
    return b->_benchProgress();
}

+ (void)cleanup {
    DGBench *b = [self shared];
    if (!b->_lib) return;
    PFNEGLMAKECURRENTPROC eglMakeCurrent = (PFNEGLMAKECURRENTPROC)dlsym(b->_lib, "eglMakeCurrent");
    PFNEGLDESTROYSURFACEPROC eglDestroySurface = (PFNEGLDESTROYSURFACEPROC)dlsym(b->_lib, "eglDestroySurface");
    PFNEGLDESTROYCONTEXTPROC eglDestroyContext = (PFNEGLDESTROYCONTEXTPROC)dlsym(b->_lib, "eglDestroyContext");
    PFNEGLTERMINATEPROC eglTerminate = (PFNEGLTERMINATEPROC)dlsym(b->_lib, "eglTerminate");
    if (eglMakeCurrent) eglMakeCurrent(b->_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (eglDestroySurface && b->_surf != EGL_NO_SURFACE) eglDestroySurface(b->_dpy, b->_surf);
    if (eglDestroyContext && b->_ctx != EGL_NO_CONTEXT) eglDestroyContext(b->_dpy, b->_ctx);
    if (eglTerminate && b->_dpy != EGL_NO_DISPLAY) eglTerminate(b->_dpy);
    b->_dpy = EGL_NO_DISPLAY;
    b->_ctx = EGL_NO_CONTEXT;
    b->_surf = EGL_NO_SURFACE;
    dlclose(b->_lib);
    b->_lib = NULL;
    b->_benchRun = NULL;
    b->_benchProgress = NULL;
}

@end

// ============================================================================
#pragma mark - DGSortOrderViewController
// ============================================================================

// 每个入口点的配置键后缀（对应 config.json 的 multidrawOrder<EntryPoint>）
static NSString *const kEntryPrefSuffix[] = {
    @"multidraw_order_arrays",
    @"multidraw_order_elements",
    @"multidraw_order_elementsbasevertex",
    @"multidraw_order_arraysindirect",
    @"multidraw_order_elementsindirect",
};

// 每个入口点的 GL 函数名（也是基准测试 JSON 里的键）
static NSString *const kEntryGLFunction[] = {
    @"glMultiDrawArrays",
    @"glMultiDrawElements",
    @"glMultiDrawElementsBaseVertex",
    @"glMultiDrawArraysIndirect",
    @"glMultiDrawElementsIndirect",
};

// 每个入口点允许的后端（与 DesktopGlues settings.cpp k_md_entries 一致）
static NSArray<NSString *> *kAllowedBackends[] = {
    @[@"unroll", @"multiarrays", @"multiindirect"],
    @[@"unroll", @"indirect", @"multiindirect", @"multibasevertex", @"multiarrays"],
    @[@"unroll", @"basevertex", @"indirect", @"multiindirect", @"multibasevertex", @"compute"],
    @[@"indirect", @"multiindirect"],
    @[@"indirect", @"multiindirect"],
};

static const NSInteger kEntryCount = 5;
static const NSInteger kBenchSection = 0;

// 后端显示名（本地化）
static NSString *backendDisplayName(NSString *name) {
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"auto": @"Auto",
            @"unroll": @"Unroll",
            @"basevertex": @"BaseVertex",
            @"indirect": @"Indirect",
            @"multiindirect": @"MultiIndirect",
            @"multibasevertex": @"MultiBaseVertex",
            @"multiarrays": @"MultiArrays",
            @"compute": @"Compute",
            @"native": @"Native",
        };
    });
    return map[name] ?: name;
}

@interface DGSortOrderViewController : UITableViewController
@end

@interface DGSortOrderViewController () {
    NSMutableArray<NSMutableArray<NSString *> *> *_orders; // 每个入口点的有效顺序
    BOOL _benchRunning;
    UIAlertController *_progressAlert;
    UIProgressView *_progressView;
    NSTimer *_progressTimer;
    NSString *_benchResultJSON;
}
@end

@implementation DGSortOrderViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"preference.title.dg_multidraw_sort", nil);
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    [self loadOrders];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveOrders];
}

#pragma mark - 数据加载/保存

- (NSArray<NSString *> *)defaultGlobalOrder {
    NSString *raw = getPrefObject(@"desktopglues.multidraw_order");
    if (raw && [raw length] > 0) {
        return [self splitOrder:raw];
    }
    return @[@"native", @"multiindirect", @"multibasevertex", @"multiarrays", @"indirect", @"basevertex", @"unroll", @"compute"];
}

- (NSArray<NSString *> *)splitOrder:(NSString *)raw {
    NSArray *parts = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;"]];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *p in parts) {
        NSString *t = [[p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        if (t.length > 0) [result addObject:t];
    }
    return result;
}

- (void)loadOrders {
    _orders = [NSMutableArray arrayWithCapacity:kEntryCount];
    NSArray *global = [self defaultGlobalOrder];
    for (NSInteger i = 0; i < kEntryCount; i++) {
        NSString *pref = getPrefObject([NSString stringWithFormat:@"desktopglues.%@", kEntryPrefSuffix[i]]);
        NSArray *allowed = kAllowedBackends[i];
        NSMutableArray *order = [NSMutableArray array];
        if (pref && [pref length] > 0) {
            for (NSString *b in [self splitOrder:pref]) {
                if ([allowed containsObject:b] && ![order containsObject:b]) [order addObject:b];
            }
        }
        // 用全局顺序过滤出该入口点允许的后端，作为默认/兜底
        for (NSString *b in global) {
            if ([allowed containsObject:b] && ![order containsObject:b]) [order addObject:b];
        }
        // 补上允许但未出现的后端
        for (NSString *b in allowed) {
            if (![order containsObject:b]) [order addObject:b];
        }
        [_orders addObject:order];
    }
}

- (void)saveOrders {
    for (NSInteger i = 0; i < kEntryCount; i++) {
        NSString *joined = [_orders[i] componentsJoinedByString:@", "];
        setPrefObject([NSString stringWithFormat:@"desktopglues.%@", kEntryPrefSuffix[i]], joined);
    }
}

#pragma mark - 基准测试

- (void)runBenchmark {
    if (_benchRunning) return;
    _benchRunning = YES;

    [self showProgressAlert];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        if (![DGBench prepareWithError:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideProgressAlert];
                _benchRunning = NO;
                [self showError:error ?: @"基准测试初始化失败"];
            });
            return;
        }
        NSString *json = [DGBench runBenchmark];
        [DGBench cleanup];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideProgressAlert];
            _benchRunning = NO;
            _benchResultJSON = json;
            [self showBenchResult:json];
        });
    });
}

- (void)showProgressAlert {
    _progressAlert = [UIAlertController alertControllerWithTitle:localize(@"preference.title.dg_bench_running", nil)
                                                         message:localize(@"preference.detail.dg_bench_running", nil)
                                                  preferredStyle:UIAlertControllerStyleAlert];
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.frame = CGRectMake(10, 70, 250, 2);
    _progressView.progress = 0;
    [_progressAlert.view addSubview:_progressView];
    [self presentViewController:_progressAlert animated:YES completion:nil];

    _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        int raw = [DGBench rawProgress];
        if (raw >= 0) {
            float fraction = (raw % 1000) / 1000.0f;
            int attempt = raw / 1000 + 1;
            _progressView.progress = fraction;
            _progressAlert.message = [NSString stringWithFormat:@"%@\n第 %d 轮 %d%%",
                localize(@"preference.detail.dg_bench_running", nil), attempt, (int)(fraction * 100)];
        }
    }];
}

- (void)hideProgressAlert {
    [_progressTimer invalidate];
    _progressTimer = nil;
    [_progressAlert dismissViewControllerAnimated:YES completion:nil];
    _progressAlert = nil;
    _progressView = nil;
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.title.dg_bench_failed", nil)
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showBenchResult:(NSString *)json {
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) {
        [self showError:json];
        return;
    }
    NSString *error = root[@"error"];
    if (error) {
        [self showError:error];
        return;
    }
    NSDictionary *entries = root[@"entries"];
    if (![entries isKindOfClass:[NSDictionary class]]) {
        [self showError:localize(@"preference.detail.dg_bench_no_entries", nil)];
        return;
    }

    // 每个入口点按测得耗时从快到慢排序
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *newOrders = [NSMutableArray arrayWithCapacity:kEntryCount];
    for (NSInteger i = 0; i < kEntryCount; i++) {
        NSDictionary *timings = entries[kEntryGLFunction[i]];
        NSArray *allowed = kAllowedBackends[i];
        NSMutableArray *ranked = [NSMutableArray array];
        NSMutableArray *unmeasured = [NSMutableArray array];
        if ([timings isKindOfClass:[NSDictionary class]]) {
            NSArray *sorted = [timings keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
                return [a doubleValue] > [b doubleValue] ? NSOrderedDescending : ([a doubleValue] < [b doubleValue] ? NSOrderedAscending : NSOrderedSame);
            }];
            for (NSString *b in sorted) {
                if ([allowed containsObject:b]) [ranked addObject:b];
            }
            for (NSString *b in allowed) {
                if (![ranked containsObject:b]) [unmeasured addObject:b];
            }
        } else {
            [ranked addObjectsFromArray:_orders[i]];
        }
        [ranked addObjectsFromArray:unmeasured];
        [newOrders addObject:ranked];

        NSMutableArray *line = [NSMutableArray arrayWithObject:kEntryGLFunction[i]];
        for (NSString *b in ranked) {
            NSNumber *us = [timings isKindOfClass:[NSDictionary class]] ? timings[b] : nil;
            if (us) {
                [line addObject:[NSString stringWithFormat:@"%@ %.0fµs", backendDisplayName(b), [us doubleValue]]];
            } else {
                [line addObject:[NSString stringWithFormat:@"%@ -", backendDisplayName(b)]];
            }
        }
        [lines addObject:[line componentsJoinedByString:@"\n"]];
    }

    NSString *message = [lines componentsJoinedByString:@"\n\n"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.title.dg_bench_done", nil)
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"preference.title.dg_bench_adopt", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        _orders = newOrders;
        [self saveOrders];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kEntryCount + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kBenchSection) return 2; // 运行按钮 + 重置按钮
    return _orders[section - 1].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kBenchSection) return nil;
    return kEntryGLFunction[section - 1];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == kBenchSection) {
        return localize(@"preference.detail.dg_multidraw_sort", nil);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }
    if (indexPath.section == kBenchSection) {
        if (indexPath.row == 0) {
            cell.textLabel.text = localize(@"preference.title.dg_bench_run", nil);
            cell.textLabel.textColor = self.view.tintColor;
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.editingAccessoryType = UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = localize(@"preference.title.dg_multidraw_reset", nil);
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.editingAccessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }
    NSInteger ei = indexPath.section - 1;
    NSString *backend = _orders[ei][indexPath.row];
    cell.textLabel.text = backendDisplayName(backend);
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)(indexPath.row + 1)];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section != kBenchSection;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != destinationIndexPath.section) return;
    NSInteger ei = sourceIndexPath.section - 1;
    NSString *item = _orders[ei][sourceIndexPath.row];
    [_orders[ei] removeObjectAtIndex:sourceIndexPath.row];
    [_orders[ei] insertObject:item atIndex:destinationIndexPath.row];
    [self saveOrders];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == kBenchSection) {
        if (indexPath.row == 0) {
            [self runBenchmark];
        } else {
            // 重置：清空所有入口点覆盖，恢复全局顺序
            for (NSInteger i = 0; i < kEntryCount; i++) {
                setPrefObject([NSString stringWithFormat:@"desktopglues.%@", kEntryPrefSuffix[i]], @"");
            }
            [self loadOrders];
            [self.tableView reloadData];
        }
    }
}

#pragma mark - 拖拽（仅用于行内排序）

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kBenchSection) return @[];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:_orders[indexPath.section - 1][indexPath.row]];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = indexPath;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    if (destinationIndexPath && destinationIndexPath.section != kBenchSection) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationForbidden];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *dest = coordinator.destinationIndexPath;
    if (!dest || dest.section == kBenchSection) return;
    for (id<UITableViewDropItem> item in coordinator.items) {
        NSIndexPath *src = item.sourceIndexPath;
        if (!src || src.section != dest.section) continue;
        [tableView moveRowAtIndexPath:src toIndexPath:dest];
        [self tableView:tableView moveRowAtIndexPath:src toIndexPath:dest];
    }
}

@end
