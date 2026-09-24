#import <AuthenticationServices/AuthenticationServices.h>
#import <objc/runtime.h>   // Task 130b：按钮 row 关联对象
#import "NMToast.h"

#import "authenticator/BaseAuthenticator.h"
#import "authenticator/ThirdPartyAuthenticator.h"
#import "AccountListViewController.h"
#import "AccountLoginViewController.h"
#import "ThirdPartyLoginViewController.h"
#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "UIImageView+AFNetworking.h"
#import "BackgroundManager.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface AccountListViewController()<ASWebAuthenticationPresentationContextProviding>

@property(nonatomic, strong) NSMutableArray *accountList;
@property(nonatomic) ASWebAuthenticationSession *authVC;

@end

@implementation AccountListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 适配自定义启动器背景：将当前视图控制器透明化，使全局背景壁纸能够透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.title = localize(@"login.title", @"账户管理");
    self.view.backgroundColor = [UIColor clearColor];

    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }

    // List accounts
    [self reloadAccountList];

    // 参照 FCL：卡片式账户列表，去除默认分割线，圆角卡片自带视觉分隔
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.estimatedRowHeight = 88;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    // 底部内边距避免最后一个 cell 被浮动按钮遮挡
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 80, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    // 注册卡片 cell
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"accountCardCell"];

    // 添加底部"添加账户"浮动按钮（FCL 风格）
    [self setupAddAccountButton];

    // 应用背景
    [[BackgroundManager sharedManager] applyBackgroundToView:self.view];

    // 监听背景 UI 效果变化通知，当用户切换背景效果（半透明/毛玻璃）时重新应用透明化
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
    // Task162：账号增删/切换后自动刷新列表（用户实测：添加账号完成后必须
    // 手动刷新账号标签页才出现）。旧实现只在 viewDidLoad 扫一次 accounts
    // 目录，push 登录页返回后列表过期。三个触发口：viewWillAppear（pop
    // 返回）、AccountChanged、UpdateAccountInfo。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame162_handleAccountsChanged)
                                                 name:@"AccountChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ame162_handleAccountsChanged)
                                                 name:@"UpdateAccountInfo"
                                               object:nil];
}

// Task162：重扫 accounts 目录并刷新表格（主线程）。
- (void)ame162_handleAccountsChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadAccountList];
        [self.tableView reloadData];
    });
}

// Task162：扫描 accounts 目录重建 accountList（从 viewDidLoad 原地提取，
// 可重复调用）。新增/删除/登录成功后重扫，返回本页即见。
- (void)reloadAccountList {
    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }
    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    for(NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if(!isDir && [file hasSuffix:@".json"]) {
            [self.accountList addObject:parseJSONFromFile(path)];
        }
    }
}

/// 背景效果改变时重新应用透明化（由 BackgroundUIEffectChanged 通知触发）
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

// Task162：pop 返回本页时重扫账号目录——添加账户流程（push 登录页 →
// 登录成功 pop 回来）后新账号立即可见，无需手动刷新。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadAccountList];
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupAddAccountButton {
    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [addBtn setTitle:localize(@"login.option.add", @"添加账户") forState:UIControlStateNormal];
    addBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [addBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    addBtn.tintColor = [UIColor whiteColor];
    addBtn.backgroundColor = accentColor();
    addBtn.layer.cornerRadius = 24;
    addBtn.layer.cornerCurve = kCACornerCurveContinuous;
    addBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 0);
    addBtn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
    // 投影增强浮动感（FCL 风格）
    addBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    addBtn.layer.shadowOpacity = 0.35;
    addBtn.layer.shadowOffset = CGSizeMake(0, 4);
    addBtn.layer.shadowRadius = 10;
    [addBtn addTarget:self action:@selector(addAccountTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:addBtn];
    // 使用 frameLayoutGuide（UITableView 的可见区域锚点）而非 safeAreaLayoutGuide，
    // 确保按钮随可见区域底部浮动，不会跟随 cell 滚动
    [NSLayoutConstraint activateConstraints:@[
        [addBtn.bottomAnchor constraintEqualToAnchor:self.tableView.frameLayoutGuide.bottomAnchor constant:-16],
        [addBtn.centerXAnchor constraintEqualToAnchor:self.tableView.frameLayoutGuide.centerXAnchor],
        [addBtn.heightAnchor constraintEqualToConstant:48],
        [addBtn.widthAnchor constraintGreaterThanOrEqualToConstant:160]
    ]];
    self.addAccountButton = addBtn;
}

- (void)addAccountTapped {
    [self actionAddAccount:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // FCL 风格：列表只显示已有账户，添加账户改由底部浮动按钮触发
    return self.accountList.count;
}

/// 计算账户类型标签文字与配色（参照 FCL：微软=蓝、第三方=橙、本地=灰、Demo=紫）
- (void)applyAccountTypeBadgeForAccount:(NSDictionary *)accountData
                              badgeLabel:(UILabel *)badgeLabel {
    NSString *username = accountData[@"username"];
    if ([username hasPrefix:@"Demo."]) {
        badgeLabel.text = localize(@"login.option.demo", @"演示");
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.55 green:0.35 blue:0.85 alpha:1.0];
    } else if (accountData[@"clientToken"] != nil) {
        badgeLabel.text = localize(@"login.option.3rdparty", @"第三方");
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.92 green:0.55 blue:0.18 alpha:1.0];
    } else if (accountData[@"xboxGamertag"] == nil) {
        badgeLabel.text = localize(@"login.option.local", @"本地");
        // Task137：原生中性灰底（白字在深浅色下均可读；其余账户类型仍为品牌色底）
        badgeLabel.backgroundColor = [UIColor systemGrayColor];
    } else {
        // 微软账户
        badgeLabel.text = @"Microsoft";
        badgeLabel.backgroundColor = [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0];
    }
}

/// 当前选中的账户 accountId（用于卡片显示选中状态）
/// 使用 accountId 而非 username，确保同名账户也能正确区分选中状态
- (NSString *)currentSelectedAccountId {
    // BaseAuthenticator.current 保存当前活跃账户的 authData
    BaseAuthenticator *currentAuth = BaseAuthenticator.current;
    return currentAuth.authData[@"accountId"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // FCL 风格卡片 cell：圆角 + 毛玻璃 + 左侧头像 + 中间用户名/副标题 + 右侧类型徽章/选中勾
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"accountCardCell" forIndexPath:indexPath];

    // 重置 cell：移除上一次复用残留的 contentView 子视图
    for (UIView *sub in cell.contentView.subviews) {
        [sub removeFromSuperview];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];

    NSDictionary *accountData = self.accountList[indexPath.row];
    NSString *displayName = accountData[@"username"];
    NSString *subtitle = @"";

    // 副标题：Demo 账户显示"演示账户"，第三方显示服务器名，微软显示 Xbox gamertag，本地显示"离线模式"
    if ([displayName hasPrefix:@"Demo."]) {
        displayName = [displayName substringFromIndex:5];
        subtitle = localize(@"login.option.demo", @"演示账户");
    } else if (accountData[@"clientToken"] != nil) {
        // 第三方账户：显示其 authserver 地址
        subtitle = accountData[@"authserver"] ?: localize(@"login.option.3rdparty", @"第三方账户");
    } else if (accountData[@"xboxGamertag"] == nil) {
        subtitle = localize(@"login.option.local", @"离线模式");
    } else {
        subtitle = accountData[@"xboxGamertag"] ?: @"Microsoft";
    }

    // 卡片容器（圆角 + 半透明背景 + 毛玻璃）
    UIView *cardView = [[UIView alloc] init];
    cardView.translatesAutoresizingMaskIntoConstraints = NO;
    cardView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10];
    cardView.layer.cornerRadius = 16;  // Task137：回归原生卡片圆角
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.borderWidth = 0.5;
    cardView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOffset = CGSizeMake(0, 4);
    cardView.layer.shadowOpacity = 0.12;
    cardView.layer.shadowRadius = 10;
    [cell.contentView addSubview:cardView];
    [[BackgroundManager sharedManager] applyEffectToView:cardView];

    // 左侧头像
    UIImageView *avatarView = [[UIImageView alloc] init];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;
    avatarView.layer.cornerRadius = 24;
    avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    // Task137：原生占位底色
    avatarView.backgroundColor = [UIColor tertiarySystemFillColor];
    avatarView.image = [UIImage imageNamed:@"DefaultAccount"];
    [cardView addSubview:avatarView];
    NSString *picURLStr = [accountData[@"profilePicURL"] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    if (picURLStr.length > 0) {
        [avatarView setImageWithURL:[NSURL URLWithString:picURLStr] placeholderImage:[UIImage imageNamed:@"DefaultAccount"]];
    }

    // 用户名
    UILabel *usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.text = displayName;
    usernameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    usernameLabel.textColor = [UIColor labelColor];
    usernameLabel.adjustsFontSizeToFitWidth = YES;
    usernameLabel.minimumScaleFactor = 0.7;
    usernameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:usernameLabel];

    // 副标题
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.font = [UIFont systemFontOfSize:12];
    subtitleLabel.textColor = [UIColor secondaryLabelColor];
    subtitleLabel.adjustsFontSizeToFitWidth = YES;
    subtitleLabel.minimumScaleFactor = 0.7;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [cardView addSubview:subtitleLabel];

    // 右侧账户类型徽章（Task136：高 24 ≈ 两行 12pt 字、圆角随高取半、
    // 宽度随字体自适应）
    UILabel *badgeLabel = [[UILabel alloc] init];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    badgeLabel.textColor = [UIColor whiteColor];
    badgeLabel.textAlignment = NSTextAlignmentCenter;
    badgeLabel.layer.cornerRadius = 12;
    badgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    badgeLabel.layer.masksToBounds = YES;
    [cardView addSubview:badgeLabel];
    [self applyAccountTypeBadgeForAccount:accountData badgeLabel:badgeLabel];

    // 选中状态指示
    UIImageView *checkmark = [[UIImageView alloc] init];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    checkmark.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    checkmark.tintColor = [UIColor colorWithRed:0.20 green:0.65 blue:0.40 alpha:1.0];
    checkmark.contentMode = UIViewContentModeScaleAspectFit;
    [cardView addSubview:checkmark];

    // Task 130b：第三方多角色账户的行内「切换角色」按钮（用户反馈：选完
    // 角色后想换角色只能重输密码——v5.1.0 无 Task129b 的长按菜单，且长按
    // 本身发现性差）。按钮位于卡片右侧、类型徽章与选中勾之间的垂直中部；
    // 点击弹出角色 actionSheet（与长按菜单共用 ame129b_switchAccountAtIndexPath，
    // switchToProfile 走 refresh 重绑，免重输密码）。仅当 availableProfiles
    // >= 2 时创建（判别口径与长按菜单一致：accountType 显式 + clientToken
    // 嗅探回退）。
    UIButton *ame130b_switchBtn = nil;
    {
        NSString *ame130b_type = accountData[@"accountType"];
        BOOL ame130b_is3P;
        if (ame130b_type.length > 0) {
            ame130b_is3P = [ame130b_type isEqualToString:@"thirdparty"];
        } else {
            ame130b_is3P = (accountData[@"clientToken"] != nil);
        }
        NSArray *ame130b_profiles = accountData[@"availableProfiles"];
        if (ame130b_is3P && [ame130b_profiles isKindOfClass:NSArray.class] &&
            ame130b_profiles.count >= 2) {
            ame130b_switchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            ame130b_switchBtn.translatesAutoresizingMaskIntoConstraints = NO;
            [ame130b_switchBtn setImage:[UIImage systemImageNamed:@"person.2"]
                              forState:UIControlStateNormal];
            ame130b_switchBtn.tintColor = [UIColor colorWithRed:0.30 green:0.55 blue:1.0 alpha:1.0];
            ame130b_switchBtn.accessibilityLabel = localize(@"account.switch_role.button", @"切换角色");
            // row 绑定：cell 复用后按钮随卡片重建（cellForRow 每次移除旧子
            // 视图），关联对象携带当前 row，避免闭包捕获过期 indexPath。
            objc_setAssociatedObject(ame130b_switchBtn, "ame130b_row",
                                     @(indexPath.row), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [ame130b_switchBtn addTarget:self
                                   action:@selector(ame130b_switchRoleTapped:)
                         forControlEvents:UIControlEventTouchUpInside];
            [cardView addSubview:ame130b_switchBtn];
        }
    }

    NSString *selectedAccountId = [self currentSelectedAccountId];
    BOOL isCurrentSelected = (selectedAccountId.length > 0 &&
                              [selectedAccountId isEqualToString:accountData[@"accountId"]]);
    checkmark.hidden = !isCurrentSelected;

    // 卡片内边距与子视图布局约束
    [NSLayoutConstraint activateConstraints:@[
        [cardView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [cardView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [cardView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [cardView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],

        [avatarView.leadingAnchor constraintEqualToAnchor:cardView.leadingAnchor constant:14],
        [avatarView.centerYAnchor constraintEqualToAnchor:cardView.centerYAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:48],
        [avatarView.heightAnchor constraintEqualToConstant:48],

        [usernameLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor constant:14],
        [usernameLabel.topAnchor constraintEqualToAnchor:cardView.topAnchor constant:18],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:badgeLabel.leadingAnchor constant:-8],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:usernameLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:usernameLabel.bottomAnchor constant:3],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:usernameLabel.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-18],

        [badgeLabel.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [badgeLabel.centerYAnchor constraintEqualToAnchor:usernameLabel.centerYAnchor],
        [badgeLabel.heightAnchor constraintEqualToConstant:24],
        [badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:52],

        [checkmark.trailingAnchor constraintEqualToAnchor:cardView.trailingAnchor constant:-14],
        [checkmark.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-14],
        [checkmark.widthAnchor constraintEqualToConstant:20],
        [checkmark.heightAnchor constraintEqualToConstant:20],
    ]];

    // Task 130b：切换角色按钮约束（底部行、选中勾左侧——与顶部徽章/用户名
    // 行零重叠；点按热区 32x32 比图标大，小屏友好）。
    if (ame130b_switchBtn != nil) {
        [NSLayoutConstraint activateConstraints:@[
            [ame130b_switchBtn.trailingAnchor constraintEqualToAnchor:checkmark.leadingAnchor constant:-10],
            [ame130b_switchBtn.centerYAnchor constraintEqualToAnchor:checkmark.centerYAnchor],
            [ame130b_switchBtn.widthAnchor constraintEqualToConstant:32],
            [ame130b_switchBtn.heightAnchor constraintEqualToConstant:32],
        ]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];

    self.modalInPresentation = YES;
    self.tableView.userInteractionEnabled = NO;
    [self addActivityIndicatorTo:cell];

    id callback = ^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^(){
            [self callbackMicrosoftAuth:status success:success forCell:cell];
        });
    };

    // Check if this is a third party account
    NSDictionary *accountData = self.accountList[indexPath.row];
    // 优先用 accountId 加载；若 accountId 缺失（旧格式账户未迁移），回退到 username 触发迁移
    NSString *loadKey = accountData[@"accountId"];
    if (loadKey.length == 0) {
        loadKey = accountData[@"username"];
    }
    // Task 128：判别统一走显式 accountType（旧文件回退 clientToken 嗅探），
    // 与 BaseAuthenticator.loadSavedName 同口径。
    NSString *ame128_type = accountData[@"accountType"];
    BOOL ame128_is3P;
    if (ame128_type.length > 0) {
        ame128_is3P = [ame128_type isEqualToString:@"thirdparty"];
    } else {
        ame128_is3P = (accountData[@"clientToken"] != nil);
    }
    if (ame128_is3P) {
        // This is a third party account
        ThirdPartyAuthenticator *ame128_auth = [ThirdPartyAuthenticator loadSavedName:loadKey];
        if ([self ame128_sessionValidated:loadKey]) {
            // zl2 同款 isSessionValidated：本会话已通过服务端校验，直接选中，
            // 不再每次选择都打 refresh（旧实现每次选择都请求，token 过期即
            // 硬失败弹错误窗 -> 账户永远选不中 -> "第三方登录完全使用不了"）。
            dispatch_async(dispatch_get_main_queue(), ^(){
                [self ame128_finishSelectionForCell:cell];
            });
        } else {
            [ame128_auth refreshTokenWithCallback:^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^(){
                    if (success) {
                        [self ame128_markSessionValidated:loadKey];
                        [self callbackMicrosoftAuth:status success:YES forCell:cell];
                    } else {
                        // Task 128（zl2 同款优雅回退）：refresh 失败不再硬阻断选择。
                        // 旧实现：错误弹窗 -> 账户无法选中 -> 第三方账户形同虚设。
                        // 现在：仍然选中该账户（current 已由 loadSavedName 设置；
                        // selected_account 持久化），toast 提示重新登录可恢复完整
                        // 功能（皮肤/联机校验可能受限），游戏可正常启动。
                        NSLog(@"[ThirdPartyAuthenticator] Task128: refresh failed (%@) -- selecting with stale token, re-login suggested", [status isKindOfClass:[NSError class]] ? [(NSError *)status localizedDescription] : @"unknown");
                        [self ame128_markSessionValidated:loadKey];
                        setPrefObject(@"internal.selected_account", loadKey);
                        [self ame128_finishSelectionForCell:cell];
                        [NMToast showMessage:[NSString stringWithFormat:@"%@\n%@",
                            localize(@"login.3rdparty.stale.title", nil),
                            localize(@"login.3rdparty.stale.message", nil)]
                                      duration:6.0];
                    }
                });
            }];
        }
    } else {
        // This is a Microsoft or local account
        [[BaseAuthenticator loadSavedName:loadKey] refreshTokenWithCallback:callback];
    }
}

#pragma mark - Task 128: third-party selection resilience (zl2-style)

// 本会话已通过服务端校验的账户（loadKey 集合；zl2 isSessionValidated 同款语义）
static NSMutableSet *ame128_validatedSet(void) {
    static NSMutableSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}

- (BOOL)ame128_sessionValidated:(NSString *)loadKey {
    if (loadKey.length == 0) return NO;
    return [ame128_validatedSet() containsObject:loadKey];
}

- (void)ame128_markSessionValidated:(NSString *)loadKey {
    if (loadKey.length > 0) [ame128_validatedSet() addObject:loadKey];
}

// 选中收尾：恢复交互、刷新列表、通知容器（与 callbackMicrosoftAuth 成功路径同款）
- (void)ame128_finishSelectionForCell:(UITableViewCell *)cell {
    if (cell) [self removeActivityIndicatorFrom:cell];
    self.modalInPresentation = NO;
    self.tableView.userInteractionEnabled = YES;
    [self reloadAccountList];
    if (self.whenItemSelected) self.whenItemSelected();
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Task 129b（FCL 多角色管理）：多角色第三方账户长按 -> 角色切换菜单（公开
// UIContextMenuConfiguration API，长按系统呈现；与设置页悬浮 pick 语义一致）。
// 每个角色一个 action，当前绑定角色打勾；点击后走 switchToProfile（refresh
// 绑定 + 旧账户文件清理 + selected_account 迁移），完成后刷新列表。
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
    point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (indexPath.row >= self.accountList.count) return nil;
    NSDictionary *accountData = self.accountList[indexPath.row];

    // 仅第三方账户且有已保存角色表（Task129b 登录时写入）且多于 1 个
    NSString *ame128_type = accountData[@"accountType"];
    BOOL is3P = [ame128_type isEqualToString:@"thirdparty"] ?: (accountData[@"clientToken"] != nil);
    if (!is3P) return nil;
    NSArray *profiles = accountData[@"availableProfiles"];
    if (![profiles isKindOfClass:[NSArray class]] || profiles.count < 2) return nil;

    NSString *currentProfileId = accountData[@"profileId"];
    NSString *displayName = accountData[@"username"] ?: @"";
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    for (NSDictionary *p in profiles) {
        if (![p isKindOfClass:[NSDictionary class]]) continue;
        NSString *pid = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : nil;
        NSString *pname = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
        if (pid.length == 0) continue;
        // UUID 归一化比较（服务器可能返回无连字符形式）
        NSString *pidNorm = [pid stringByReplacingOccurrencesOfString:@"-" withString:@""];
        NSString *curNorm = [currentProfileId stringByReplacingOccurrencesOfString:@"-" withString:@""];
        __block UIAction *action = [UIAction actionWithTitle:pname image:nil identifier:nil
            handler:^(UIAction *a) {
                [self ame129b_switchAccountAtIndexPath:indexPath toProfile:p];
            }];
        action.state = [pidNorm isEqualToString:curNorm] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    if (actions.count < 2) return nil;

    NSString *menuTitle = [NSString stringWithFormat:localize(@"account.switch_role.title", @"切换角色 — %@"), displayName];
    UIMenu *menu = [UIMenu menuWithTitle:menuTitle children:actions];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            return menu;
        }];
}

/// Task 130b：行内「切换角色」按钮回调（卡片右侧 person.2 图标）。
/// 弹出悬浮 actionSheet 角色列表（与设置页悬浮 pick 同形态；iPad 经
/// popover 锚定在按钮旁）——用户实测反馈"想换角色只能重输密码"的直达
/// 入口。选中走 ame129b_switchAccountAtIndexPath（switchToProfile：
/// refresh 重绑，免密码）；长按 contextMenu（Task129b）保留，双入口共用。
- (void)ame130b_switchRoleTapped:(UIButton *)sender {
    NSNumber *rowNum = objc_getAssociatedObject(sender, "ame130b_row");
    if (![rowNum isKindOfClass:NSNumber.class]) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:rowNum.integerValue inSection:0];
    if (indexPath.row >= self.accountList.count) return;   // 列表已变（删除/刷新后旧按钮）
    NSDictionary *accountData = self.accountList[indexPath.row];
    NSArray *profiles = accountData[@"availableProfiles"];
    if (![profiles isKindOfClass:NSArray.class]) return;

    NSString *currentProfileId = accountData[@"profileId"];
    NSString *displayName = accountData[@"username"] ?: @"";
    NSString *message = [NSString stringWithFormat:localize(@"account.switch_role.title", @"切换角色 — %@"), displayName];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:message
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *p in profiles) {
        if (![p isKindOfClass:NSDictionary.class]) continue;
        NSString *pid = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : nil;
        NSString *pname = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
        if (pid.length == 0) continue;
        NSString *title = pname;
        // ✓ 当前角色（UUID 归一化比较，与长按菜单同口径）
        NSString *pidNorm = [pid stringByReplacingOccurrencesOfString:@"-" withString:@""];
        NSString *curNorm = [currentProfileId stringByReplacingOccurrencesOfString:@"-" withString:@""];
        if ([pidNorm isEqualToString:curNorm]) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                [self ame129b_switchAccountAtIndexPath:indexPath toProfile:p];
            }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    // iPad：actionSheet 以 popover 锚定在按钮旁（悬浮面板）；iPhone 底部弹出。
    alert.popoverPresentationController.sourceView = sender;
    alert.popoverPresentationController.sourceRect = sender.bounds;
    alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    [self presentViewController:alert animated:YES completion:nil];
}

/// Task 129b：执行角色切换（长按菜单的 action 回调）
- (void)ame129b_switchAccountAtIndexPath:(NSIndexPath *)indexPath toProfile:(NSDictionary *)profile {
    if (indexPath.row >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[indexPath.row];
    NSString *loadKey = accountData[@"accountId"];
    if (loadKey.length == 0) loadKey = accountData[@"username"];
    if (loadKey.length == 0) return;

    NSLog(@"[AccountList] Task129b: switching profile for %@ -> %@", loadKey, profile[@"name"]);
    [NMToast showMessage:[NSString stringWithFormat:localize(@"account.switch_role.working", @"正在切换到 %@ …"), profile[@"name"]]];

    ThirdPartyAuthenticator *auth = [ThirdPartyAuthenticator loadSavedName:loadKey];
    if (!auth) return;
    [auth switchToProfile:profile callback:^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                NSLog(@"[AccountList] Task129b: profile switch OK (%@)", profile[@"name"]);
                [NMToast showMessage:[NSString stringWithFormat:localize(@"account.switch_role.done", @"已切换到 %@"), profile[@"name"]]];
                [self reloadAccountList];
            } else {
                NSString *errMsg = [status isKindOfClass:[NSError class]] ? [(NSError *)status localizedDescription]
                                 : ([status isKindOfClass:[NSString class]] ? status : localize(@"Error", nil));
                [NMToast showMessage:[NSString stringWithFormat:localize(@"account.switch_role.failed", @"切换失败：%@"), errMsg ?: @"?"]];
            }
        });
    }];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // TODO: invalidate token

        // 用 accountId 作为文件名（唯一标识），同名账户删除互不影响
        // 若 accountId 缺失（旧格式账户未迁移），回退到 username
        NSString *accountId = self.accountList[indexPath.row][@"accountId"];
        if (accountId.length == 0) {
            accountId = self.accountList[indexPath.row][@"username"];
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
        if (self.whenDelete != nil) {
            self.whenDelete(accountId);
        }
        NSString *xuid = self.accountList[indexPath.row][@"xuid"];
        if (xuid) {
            [MicrosoftAuthenticator clearTokenDataOfProfile:xuid];
        }
        [fm removeItemAtPath:path error:nil];
        // 若删除的正是当前选中账户，清空 selected_account，避免下次启动尝试加载已删除的账户
        if ([getPrefObject(@"internal.selected_account") isEqualToString:accountId]) {
            setPrefObject(@"internal.selected_account", @"");
            [BaseAuthenticator setCurrent:nil];
        }
        [self.accountList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // 所有账户行都可滑动删除
    return UITableViewCellEditingStyleDelete;
}

- (NSDictionary *)parseQueryItems:(NSString *)url {
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithString:url].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value;
    }
    return result;
}

- (void)actionAddAccount:(UIView *)sender {
    // 参照 FCL：push 卡片式登录方式选择页（替代原来的 ActionSheet）
    AccountLoginViewController *loginVC = [[AccountLoginViewController alloc] init];
    loginVC.onSelectLoginType = ^(AccountLoginType type) {
        // 选完登录方式后 pop 回账户列表，再触发对应登录流程
        [self.navigationController popViewControllerAnimated:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (type) {
                case AccountLoginTypeMicrosoft:
                    [self actionLoginMicrosoft:sender];
                    break;
                case AccountLoginTypeLittleSkin:
                    [self actionLoginLittleSkin:sender];
                    break;
                case AccountLoginTypeThirdParty:
                    [self actionLoginThirdParty:sender];
                    break;
                case AccountLoginTypeLocal:
                    [self actionLoginLocal:sender];
                    break;
            }
        });
    };
    [self.navigationController pushViewController:loginVC animated:YES];
}

- (void)actionLoginLocal:(UIView *)sender {
    if (getPrefBool(@"warnings.local_warn")) {
        setPrefBool(@"warnings.local_warn", NO);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"login.warn.title.localmode", nil) message:localize(@"login.warn.message.localmode", nil) preferredStyle:UIAlertControllerStyleActionSheet];
        // 修复：sender 为 nil 时（从 addAccountTapped -> actionAddAccount:nil 链路进入），
        // ActionSheet 在 iPad/LiveContainer 等 popover 场景下必须提供 sourceView，
        // 否则会因 popoverPresentationController.sourceView 为 nil 而崩溃。
        // 回退顺序：sender -> addAccountButton -> self.view 中心点。
        UIView *sourceView = sender ?: self.addAccountButton;
        if (sourceView) {
            alert.popoverPresentationController.sourceView = sourceView;
            alert.popoverPresentationController.sourceRect = sourceView.bounds;
        } else {
            alert.popoverPresentationController.sourceView = self.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
            alert.popoverPresentationController.permittedArrowDirections = 0;
        }
        UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {[self actionLoginLocal:sender];}];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:localize(@"Sign in", nil) message:localize(@"login.option.local", nil) preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"login.alert.field.username", nil);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *usernameField = textFields[0];
        if (usernameField.text.length < 3 || usernameField.text.length > 16) {
            controller.message = localize(@"login.error.username.outOfRange", nil);
            [self presentViewController:controller animated:YES completion:nil];
        } else {
            id callback = ^(id status, BOOL success) {
                if (self.whenItemSelected) self.whenItemSelected();
                [self dismissViewControllerAnimated:YES completion:nil];
            };
            [[[LocalAuthenticator alloc] initWithInput:usernameField.text] loginWithCallback:callback];
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionLoginThirdParty:(UIView *)sender {
    // 参照 FCL：push 卡片式第三方登录表单页（替代原 UIAlertController 三字段输入）
    ThirdPartyLoginViewController *vc = [[ThirdPartyLoginViewController alloc] init];
    vc.mode = ThirdPartyLoginModeCustom;
    __weak typeof(self) weakSelf = self;
    vc.onLoginComplete = ^(BOOL success, NSString *errorMessage) {
        if (success) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            if (weakSelf.whenItemSelected) weakSelf.whenItemSelected();
        }
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)actionLoginLittleSkin:(UIView *)sender {
    // 参照 FCL：push 卡片式 LittleSkin 登录表单页（替代原 UIAlertController 双字段输入）
    // LittleSkin 端点固定为 https://littleskin.cn/api/yggdrasil，由 VC 内部预设
    ThirdPartyLoginViewController *vc = [[ThirdPartyLoginViewController alloc] init];
    vc.mode = ThirdPartyLoginModeLittleSkin;
    __weak typeof(self) weakSelf = self;
    vc.onLoginComplete = ^(BOOL success, NSString *errorMessage) {
        if (success) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            if (weakSelf.whenItemSelected) weakSelf.whenItemSelected();
        }
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)actionLoginMicrosoft:(UIView *)sender {
    NSURL *url = [NSURL URLWithString:@"https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];

    self.authVC =
        [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"ms-xal-00000000402b5328"
        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error)
    {
        if (callbackURL == nil) {
            if (error.code != ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
            }
            return;
        }
        // NSLog(@"URL returned = %@", [callbackURL absoluteString]);

        NSDictionary *queryItems = [self parseQueryItems:callbackURL.absoluteString];
        if (queryItems[@"code"]) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                self.modalInPresentation = YES;
                self.tableView.userInteractionEnabled = NO;
                // 仅当 sender 是 UITableViewCell 时才显示加载指示器
                if ([sender isKindOfClass:[UITableViewCell class]]) {
                    [self addActivityIndicatorTo:(UITableViewCell *)sender];
                }
            });
            id callback = ^(id status, BOOL success) {
                if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"] && success) {
                    showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
                }
                dispatch_async(dispatch_get_main_queue(), ^(){
                    UITableViewCell *cell = [sender isKindOfClass:[UITableViewCell class]] ? (UITableViewCell *)sender : nil;
                    [self callbackMicrosoftAuth:status success:success forCell:cell];
                });
            };
            [[[MicrosoftAuthenticator alloc] initWithInput:queryItems[@"code"]] loginWithCallback:callback];
        } else {
            if ([queryItems[@"error"] hasPrefix:@"access_denied"]) {
                // Ignore access denial responses
                return;
            }
            showDialog(localize(@"Error", nil), queryItems[@"error_description"]);
        }
    }];

    self.authVC.prefersEphemeralWebBrowserSession = YES;
    self.authVC.presentationContextProvider = self;

    if ([self.authVC start] == NO) {
        showDialog(localize(@"Error", nil), @"Unable to open Safari");
    }
}

- (void)addActivityIndicatorTo:(UITableViewCell *)cell {
    UIActivityIndicatorViewStyle indicatorStyle = UIActivityIndicatorViewStyleMedium;
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:indicatorStyle];
    cell.accessoryView = indicator;
    [indicator sizeToFit];
    [indicator startAnimating];
}

- (void)removeActivityIndicatorFrom:(UITableViewCell *)cell {
    UIActivityIndicatorView *indicator = (id)cell.accessoryView;
    [indicator stopAnimating];
    cell.accessoryView = nil;
}

- (void)callbackMicrosoftAuth:(id)status success:(BOOL)success forCell:(UITableViewCell *)cell {
    if (status != nil) {
        if (success) {
            // Task 126：登录成功/状态提示改走 NMToast（新拟物卡片，自动消失，
            // 点击"查看"无动作需求）。旧 showDialog 的 level-1000 系统窗在
            // OK 后泄漏在场（"弹窗要手动删"的根源），且登录成功本无需用户
            // 做任何决定——非侵入提示即可。错误分支仍走 showDialog（错误
            // 详情需要阅读，且已修复 window 回收）。
            NSString *ame126_msg = nil;
            if ([status isKindOfClass:NSError.class]) {
                ame126_msg = [(NSError *)status localizedDescription];
            } else if ([status isKindOfClass:NSString.class]) {
                ame126_msg = (NSString *)status;
            }
            if (ame126_msg.length > 0) {
                [NMToast showMessage:[NSString stringWithFormat:@"%@：%@",
                    localize(@"login.title", @"账户"), ame126_msg]
                                  duration:6.0];
            }
            if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"]) {
                // 演示模式警告仍需用户知悉（影响后续离线体验预期），保留弹窗
                showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
            }
            // 登录成功后刷新列表以显示新账户
            if (cell) [self removeActivityIndicatorFrom:cell];
            self.modalInPresentation = NO;
            self.tableView.userInteractionEnabled = YES;
            [self reloadAccountList];
            if (self.whenItemSelected) self.whenItemSelected();
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            // 认证失败：恢复交互并展示错误
            self.modalInPresentation = NO;
            self.tableView.userInteractionEnabled = YES;
            if (cell) [self removeActivityIndicatorFrom:cell];

            if ([status isKindOfClass:[NSError class]]) {
                NSData *errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
                if (errorData) {
                    NSString *errorStr = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
                    NSLog(@"[MSA] Error: %@", errorStr);
                    showDialog(localize(@"Error", nil), errorStr);
                } else {
                    showDialog(localize(@"Error", nil), [status localizedDescription]);
                }
            } else if ([status isKindOfClass:[NSString class]]) {
                showDialog(localize(@"Error", nil), status);
            } else {
                showDialog(localize(@"Error", nil), localize(@"login.error.invalid_response", nil));
            }
        }
    } else if (success) {
        // 成功登录，无消息
        if (cell) [self removeActivityIndicatorFrom:cell];
        self.modalInPresentation = NO;
        self.tableView.userInteractionEnabled = YES;
        [self reloadAccountList];
        if (self.whenItemSelected) self.whenItemSelected();
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

/// 重新加载账户列表并刷新表格（FCL 风格：登录/删除后刷新卡片视图）
- (void)reloadAccountList {
    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }
    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    for (NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if (!isDir && [file hasSuffix:@".json"]) {
            [self.accountList addObject:parseJSONFromFile(path)];
        }
    }
    [self.tableView reloadData];
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - ASWebAuthenticationPresentationContextProviding
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
