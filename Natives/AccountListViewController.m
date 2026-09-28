#import <AuthenticationServices/AuthenticationServices.h>
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
#import "ScreenUtils.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface AccountListViewController()<ASWebAuthenticationPresentationContextProviding>

@property(nonatomic, strong) NSMutableArray *accountList;
@property(nonatomic) ASWebAuthenticationSession *authVC;

@end

#pragma mark - AME190AccountCardCell（Task190：已安装版本页同构账号卡片）

// 用户定稿：账号选项样式 = "已安装的版本"页面（VersionManagerViewController
// 的 VMTileBaseCell / VMVersionCardCell）同构——
//   - 外层 cell 全透明 + 卡面阴影规格照搬 VMTileBaseCell（0.12/6/(0,3) +
//     layoutSubviews 内 shadowPath 随帧更新，Task152 黑直角根修同款）
//   - contentContainer：12pt 连续圆角 + 白 0.08 基底 + 0.5pt 白 0.10 描边；
//     选中态换 accent 1.5pt 描边 + accent 0.10 淡底（VMVersionCardCell
//     规范 9.1 三层选中强化原样镜像）
//   - 卡面管线：applyEffectToTableViewCell（Task172 三段式泛型管线——与
//     版本页 applyEffectToCollectionViewCell 为同一条管线，新拟态开关两种
//     状态下行为逐字节一致；旧 applyEffectToCell: 是无开关旧管线，不采用）
//   - 左侧 = 圆形头像（用户：卡片左部的图标改成头像（圆形）；尺寸对齐
//     版本页 iconContainer 的 dp:34）
//   - 标题 = 账号名正文（版本页 nameLabel 规格 sp:15 semibold 原生 label 色）
//   - 灰字 = 账号类型（用户：灰字为账号类型；版本页 versionLabel 规格
//     sp:11 secondary。原 Task136 彩色类型胶囊随重写退役）
//   - 右侧无箭头（用户：把卡片右部的箭头删掉）；选中徽章 = 20pt accent
//     圆角方块 + 白勾（VMVersionCardCell selectedBadge 同位 top+10/-14）
//   - 触摸缩放弹簧动画（VMTileBaseCell 同款 0.96 / 0.25 spring）
//   - 上下 4pt 内缩（版本卡 item contentInsets 语义，相邻卡面净距 8pt =
//     版本页 iPhone 档）+ 左右 24pt 总边距（版本页 section 16 + item 8）
@interface AME190AccountCardCell : UITableViewCell
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UILabel *typeLabel;
@property (nonatomic, strong) UIView *selectedBadge;
- (void)ame190_configureWithUsername:(NSString *)username
                            typeText:(NSString *)typeText
                           avatarURL:(NSString *)avatarURLStr
                            selected:(BOOL)selected;
@end

@implementation AME190AccountCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self ame190_setupViews];
    }
    return self;
}

- (void)ame190_setupViews {
    // 外层 cell 全透明（plain 表格无 inset-grouped 系统白底，但选中高亮/
    // 复用重装仍防御性清一遍——ModLoaderInstall AME184ClearTableViewCellChrome
    // 同款配方）；裁剪逐层放行，阴影可越出卡片边界
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.clipsToBounds = NO;
    self.layer.masksToBounds = NO;
    self.contentView.clipsToBounds = NO;
    self.contentView.layer.masksToBounds = NO;
    UIView *clearSel = [[UIView alloc] init];
    clearSel.backgroundColor = [UIColor clearColor];
    clearSel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.selectedBackgroundView = clearSel;

    // 阴影：VMTileBaseCell 规范 5.2 中阴影档（0.12, 6, (0,3)）
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 3);
    self.layer.shadowOpacity = 0.12;
    self.layer.shadowRadius = 6;

    // ----- 卡片容器（VMTileBaseCell 规范 5.1：12pt 连续圆角卡面宿主）-----
    self.contentContainer = [[UIView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentContainer.layer.cornerRadius = 12;
    self.contentContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentContainer.layer.masksToBounds = YES;
    self.contentContainer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.contentContainer.layer.borderWidth = 0.5;
    self.contentContainer.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    [self.contentView addSubview:self.contentContainer];

    // 卡面管线：Task172 三段式泛型管线（与已安装版本页同一条，Task190
    // 新入口；管线在 init 单次挂载，引擎 layoutSubviews 按 bounds 自刷）
    [[BackgroundManager sharedManager] applyEffectToTableViewCell:self];

    // ----- 左侧圆形头像（dp:34，占位底色 + DefaultAccount 默认图）-----
    CGFloat ame190_avatarSize = [ScreenUtils dp:34];
    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.layer.cornerRadius = ame190_avatarSize / 2;
    self.avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    self.avatarView.layer.masksToBounds = YES;
    self.avatarView.backgroundColor = [UIColor tertiarySystemFillColor];
    self.avatarView.image = [UIImage imageNamed:@"DefaultAccount"];
    [self.contentContainer addSubview:self.avatarView];

    // ----- 标题 = 账号名（版本页 nameLabel 规格：sp:15 semibold label 色）-----
    self.usernameLabel = [[UILabel alloc] init];
    self.usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.usernameLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:15] weight:UIFontWeightSemibold];
    self.usernameLabel.textColor = [UIColor labelColor];
    self.usernameLabel.numberOfLines = 1;
    self.usernameLabel.adjustsFontSizeToFitWidth = YES;
    self.usernameLabel.minimumScaleFactor = 0.75;
    self.usernameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentContainer addSubview:self.usernameLabel];

    // ----- 灰字 = 账号类型（版本页 versionLabel 规格：sp:11 secondary）-----
    self.typeLabel = [[UILabel alloc] init];
    self.typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.typeLabel.font = [UIFont systemFontOfSize:[ScreenUtils sp:11] weight:UIFontWeightRegular];
    self.typeLabel.textColor = [UIColor secondaryLabelColor];
    self.typeLabel.numberOfLines = 1;
    self.typeLabel.adjustsFontSizeToFitWidth = YES;
    self.typeLabel.minimumScaleFactor = 0.7;
    self.typeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentContainer addSubview:self.typeLabel];

    // ----- 选中徽章（VMVersionCardCell selectedBadge 同款：20pt accent 圆角
    // 方块 + 白勾 9pt bold，top+10 / 右 -14）-----
    self.selectedBadge = [[UIView alloc] init];
    self.selectedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedBadge.backgroundColor = accentColor();
    self.selectedBadge.layer.cornerRadius = 10;
    self.selectedBadge.layer.cornerCurve = kCACornerCurveContinuous;
    self.selectedBadge.layer.masksToBounds = YES;
    self.selectedBadge.hidden = YES;
    [self.contentContainer addSubview:self.selectedBadge];

    UIImageView *checkmark = [[UIImageView alloc] init];
    checkmark.translatesAutoresizingMaskIntoConstraints = NO;
    checkmark.image = [UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIFontWeightBold]];
    checkmark.tintColor = [UIColor whiteColor];
    [self.selectedBadge addSubview:checkmark];

    CGFloat ame190_textLead = 14 + ame190_avatarSize + 10;   // 头像 leading 14 + 直径 + 10pt 间距
    [NSLayoutConstraint activateConstraints:@[
        // 卡片容器：上下 4 / 左右 24 内缩（版本页 section.contentInsets 16 +
        // item contentInsets 8 = 24pt 总边距语义）
        [self.contentContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.contentContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        [self.contentContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
        [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],

        // 头像：左 14，垂直居中，dp:34 圆
        [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:14],
        [self.avatarView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.avatarView.widthAnchor constraintEqualToConstant:ame190_avatarSize],
        [self.avatarView.heightAnchor constraintEqualToConstant:ame190_avatarSize],

        // 文字块：头像右侧 10；标题顶 16 / 灰字紧跟 3 / 灰字底 16——
        // 高度链完整，自动行高（约 70pt 卡面 + 8pt 行距 = 版本页同档）
        [self.usernameLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:ame190_textLead],
        [self.usernameLabel.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:16],
        [self.usernameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectedBadge.leadingAnchor constant:-8],

        [self.typeLabel.leadingAnchor constraintEqualToAnchor:self.usernameLabel.leadingAnchor],
        [self.typeLabel.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:3],
        [self.typeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.selectedBadge.leadingAnchor constant:-8],
        [self.typeLabel.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor constant:-16],

        // 选中徽章：右上（版本页同位）
        [self.selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-14],
        [self.selectedBadge.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:10],
        [self.selectedBadge.widthAnchor constraintEqualToConstant:20],
        [self.selectedBadge.heightAnchor constraintEqualToConstant:20],
        [checkmark.centerXAnchor constraintEqualToAnchor:self.selectedBadge.centerXAnchor],
        [checkmark.centerYAnchor constraintEqualToAnchor:self.selectedBadge.centerYAnchor],
    ]];
}

// Task152 镜像：阴影路径随卡片实际 frame 更新——透明 cell 的阴影若无
// shadowPath 会以直角 bounds 绘制，在圆角卡片四角外露出黑色直角
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect shadowRect = self.contentContainer.frame;
    if (!CGRectIsEmpty(shadowRect)) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowRect
                                                           cornerRadius:12.0].CGPath;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.avatarView.image = [UIImage imageNamed:@"DefaultAccount"];
    self.usernameLabel.text = nil;
    self.typeLabel.text = nil;
    self.selectedBadge.hidden = YES;
    [self ame190_applySelectedAppearance:NO];
}

// 规范 9.1 三层选中强化（VMVersionCardCell configure 原样镜像：边框 + 徽章 + 底色）
- (void)ame190_applySelectedAppearance:(BOOL)selected {
    self.selectedBadge.hidden = !selected;
    self.selectedBadge.backgroundColor = accentColor();
    if (selected) {
        self.contentContainer.layer.borderColor = accentColor().CGColor;
        self.contentContainer.layer.borderWidth = 1.5;
        self.contentContainer.backgroundColor = [accentColor() colorWithAlphaComponent:0.10];
    } else {
        self.contentContainer.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
        self.contentContainer.layer.borderWidth = 0.5;
        self.contentContainer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    }
}

- (void)ame190_configureWithUsername:(NSString *)username
                            typeText:(NSString *)typeText
                           avatarURL:(NSString *)avatarURLStr
                            selected:(BOOL)selected {
    self.usernameLabel.text = username;
    self.typeLabel.text = typeText;

    if (avatarURLStr.length > 0) {
        NSString *pic = [avatarURLStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        [self.avatarView setImageWithURL:[NSURL URLWithString:pic]
                        placeholderImage:[UIImage imageNamed:@"DefaultAccount"]];
    }
    [self ame190_applySelectedAppearance:selected];
}

// 触摸缩放弹簧动画（VMTileBaseCell 同款 0.96 / 0.25 spring）
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:nil];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

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
    // Task190：行高自动维度——卡面 ≈ 16+标题+3+灰字+16 + 上下 4pt 内缩
    //（约 78pt 行 / 70pt 卡，已安装版本页同档间距）
    self.tableView.estimatedRowHeight = 78;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    // 底部内边距避免最后一个 cell 被浮动按钮遮挡
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 80, 0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    // 注册卡片 cell（Task190：已安装版本页同构 AME190AccountCardCell，
    // 正规复用替代旧"出列拆光重建"内联卡）
    [self.tableView registerClass:AME190AccountCardCell.class forCellReuseIdentifier:@"accountCardCell"];

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

// Task162：重扫 accounts 目录由文末既有的 reloadAccountList（FCL 风格，
// 含 reloadData）承担——viewWillAppear / AccountChanged / UpdateAccountInfo
// 三个新触发口全部复用它，勿在此重复实现（CI 实锤 duplicate declaration）。
- (void)ame162_handleAccountsChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadAccountList];
    });
}

/// 背景效果改变时重新应用透明化（由 BackgroundUIEffectChanged 通知触发）
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

// Task162：pop 返回本页时重扫账号目录——添加账户流程（push 登录页 →
// 登录成功 pop 回来）后新账号立即可见，无需手动刷新（reloadAccountList
// 自带 reloadData）。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadAccountList];
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

/// 账号类型文字（Task190：用户定稿"灰字为账号类型"——原 Task136 彩色
/// 类型胶囊随卡片同构重写退役，类型判别口径原样保留：微软=Microsoft、第三方、本地、Demo=演示）
- (NSString *)ame190_accountTypeTextForAccount:(NSDictionary *)accountData {
    NSString *username = accountData[@"username"] ?: @"";
    if ([username hasPrefix:@"Demo."]) {
        return localize(@"login.option.demo", @"演示");
    } else if (accountData[@"clientToken"] != nil) {
        return localize(@"login.option.3rdparty", @"第三方");
    } else if (accountData[@"xboxGamertag"] == nil) {
        return localize(@"login.option.local", @"本地");
    }
    return @"Microsoft";
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
    // Task190：账号卡 = 已安装版本页同构 cell（AME190AccountCardCell，见
    // 文件头类注释）。旧实现每次出列拆除全部子视图重建（Task137/180 多轮
    // 内联卡叠加，卡面 = 白 0.10 + 16pt 圆角 + 旧管线，与版本页观感不一致
    // ——用户实测"白色外框里有了一条边"），现随新 cell 类正规复用；
    // 读侧去重/坏文件过滤（Task180 双保险）在 reloadAccountList 原样保留。
    AME190AccountCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"accountCardCell" forIndexPath:indexPath];
    if (indexPath.row >= self.accountList.count) return cell;
    NSDictionary *accountData = self.accountList[indexPath.row];

    // 标题 = 账号名（Demo 账户去掉前缀展示）
    NSString *displayName = accountData[@"username"] ?: @"";
    if ([displayName hasPrefix:@"Demo."]) {
        displayName = [displayName substringFromIndex:5];
    }

    // 选中态：accountId 精确比对（同名账户也能正确区分）
    NSString *selectedAccountId = [self currentSelectedAccountId];
    BOOL isCurrentSelected = (selectedAccountId.length > 0 &&
                              [selectedAccountId isEqualToString:accountData[@"accountId"]]);

    [cell ame190_configureWithUsername:displayName
                              typeText:[self ame190_accountTypeTextForAccount:accountData]
                             avatarURL:accountData[@"profilePicURL"]
                              selected:isCurrentSelected];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self ame190_selectAccountAtIndexPath:indexPath];
}

/// Task190：账户选择流程收口（原 didSelectRowAtIndexPath 主体原样迁入）——
/// 点击卡片与长按菜单"选用账号"共用同一条选择链，杜绝双入口行为漂移。
- (void)ame190_selectAccountAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.accountList.count) return;
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

// Task190：长按菜单全账户化（用户定稿：长按呼出选项 —— (person.circle)
// 选用账号、(红字 trash) 删除账号）。原 Task129b 仅第三方多角色账户有
// 长按菜单、Task130b 又为其补了行内 person.2 按钮（长按发现性补偿）——
// 随卡片同构重写统一收敛到这一个长按菜单：所有账户均有两项主操作；
// 第三方多角色账户在两项之间保留 Task129b 的角色切换项
//（ame129b_switchAccountAtIndexPath → switchToProfile refresh 重绑，免密）。
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
    point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (indexPath.row >= self.accountList.count) return nil;
    NSDictionary *accountData = self.accountList[indexPath.row];
    NSString *displayName = accountData[@"username"] ?: @"";
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];

    // ① 选用账号（person.circle）——与点击卡片同一条选择链
    [actions addObject:[UIAction actionWithTitle:localize(@"account.menu.use", @"选用账号")
                                           image:[UIImage systemImageNamed:@"person.circle"]
                                      identifier:nil
                                          handler:^(UIAction *action) {
        [self ame190_selectAccountAtIndexPath:indexPath];
    }]];

    // ② 第三方多角色账户：Task129b 角色切换项原样保留（当前角色打勾）
    NSString *ame128_type = accountData[@"accountType"];
    BOOL is3P = [ame128_type isEqualToString:@"thirdparty"] ?: (accountData[@"clientToken"] != nil);
    NSArray *profiles = accountData[@"availableProfiles"];
    if (is3P && [profiles isKindOfClass:[NSArray class]] && profiles.count >= 2) {
        NSString *currentProfileId = accountData[@"profileId"];
        for (NSDictionary *p in profiles) {
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSString *pid = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : nil;
            NSString *pname = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
            if (pid.length == 0) continue;
            // UUID 归一化比较（服务器可能返回无连字符形式）
            NSString *pidNorm = [pid stringByReplacingOccurrencesOfString:@"-" withString:@""];
            NSString *curNorm = [currentProfileId stringByReplacingOccurrencesOfString:@"-" withString:@""];
            UIAction *action = [UIAction actionWithTitle:pname image:nil identifier:nil
                handler:^(UIAction *a) {
                    [self ame129b_switchAccountAtIndexPath:indexPath toProfile:p];
                }];
            action.state = [pidNorm isEqualToString:curNorm] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [actions addObject:action];
        }
    }

    // ③ 删除账号（trash，红色破坏性）——与左滑删除同一条删除链
    UIAction *ame190_delete = [UIAction actionWithTitle:localize(@"account.menu.delete", @"删除账号")
                                                  image:[UIImage systemImageNamed:@"trash"]
                                             identifier:nil
                                                 handler:^(UIAction *action) {
        [self ame190_deleteAccountAtIndexPath:indexPath];
    }];
    ame190_delete.attributes = UIActionAttributesDestructive;
    [actions addObject:ame190_delete];

    UIMenu *menu = [UIMenu menuWithTitle:displayName children:actions];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            return menu;
        }];
}

// Task190：Task130b 行内「切换角色」按钮（person.2 + actionSheet）随账号
// 卡片同构重写退役——卡片右侧仅保留选中徽章（用户定稿卡片无多余控件），
// 角色切换入口收敛进全账户长按菜单的 Task129b 角色项（ame129b_
// switchAccountAtIndexPath 免密链原样保留，见上方 contextMenu 实现）。

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
        [self ame190_deleteAccountAtIndexPath:indexPath];
    }
}

/// Task190：删除流程收口（原 commitEditingStyle 删除分支原样迁入）——
/// 左滑删除与长按菜单"删除账号"共用同一条删除链：whenDelete 回调、
/// MSA token 清理、账户文件删除、选中态清空、行删除动画。
- (void)ame190_deleteAccountAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.accountList.count) return;
    NSDictionary *accountData = self.accountList[indexPath.row];

    // 用 accountId 作为文件名（唯一标识），同名账户删除互不影响
    // 若 accountId 缺失（旧格式账户未迁移），回退到 username
    NSString *accountId = accountData[@"accountId"];
    if (accountId.length == 0) {
        accountId = accountData[@"username"];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), accountId];
    if (self.whenDelete != nil) {
        self.whenDelete(accountId);
    }
    NSString *xuid = accountData[@"xuid"];
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
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
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
    // Task180：复制 bug 双保险②——读侧兜底。①按 accountId（缺省退文件名）
    // 去重：历史残留的重复 .json 只展示一份（写盘侧清理见 BaseAuthenticator
    // saveChanges 的 Task180 钩子，存量随每次选择逐步消除）；②过滤解析失败
    // 文件（parseJSONFromFile 失败时返回 @{@"NSErrorObject": ...}，旧代码照单
    // 全收会渲染成空白行，同样被用户感知为“多出来的条目”）。
    NSMutableSet *ame180_seenIds = [NSMutableSet set];
    for (NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if (!isDir && [file hasSuffix:@".json"]) {
            NSDictionary *data = parseJSONFromFile(path);
            if (data == nil || data[@"NSErrorObject"] != nil) {
                NSLog(@"[Task180] skipping unreadable account file: %@", file);
                continue;
            }
            NSString *ame180_key = data[@"accountId"] ?: [file stringByDeletingPathExtension];
            if ([ame180_seenIds containsObject:ame180_key]) {
                NSLog(@"[Task180] dedup account entry by id: %@", ame180_key);
                continue;
            }
            [ame180_seenIds addObject:ame180_key];
            [self.accountList addObject:data];
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
