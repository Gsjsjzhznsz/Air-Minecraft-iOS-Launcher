//
//  ServerDetailViewController.m
//  Amethyst
//

#import "ServerDetailViewController.h"
#import "NeomorphKit/UIView+Neomorph.h"
#import "BackgroundManager.h"
#import "InlineMessageView.h"
#import "PLProfiles.h"
#import "ServerService.h"
#import "UIKit+AFNetworking.h"
#import "utils.h"

@interface ServerDetailViewController ()
@property (nonatomic, strong) ServerItem *serverItem;
@property (nonatomic, assign) ServerDownloadAPI api;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UITextView *descTextView;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UIButton *addressCopyButton;
@property (nonatomic, strong) UIButton *joinButton;
@property (nonatomic, strong) UIButton *downloadPackButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) InlineMessageView *currentMessageView;
@end

@implementation ServerDetailViewController

- (instancetype)initWithServerItem:(ServerItem *)item api:(ServerDownloadAPI)api {
    self = [super init];
    if (self) {
        _serverItem = item;
        _api = api;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // 适配自定义启动器背景：将当前视图控制器透明化，使全局背景壁纸能够透出
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    [[BackgroundManager sharedManager] applyEffectToView:self.view];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = localize(@"i18n_str_958", nil);

    [self setupUI];
    [self populateUI];

    // 自动加载详情（补充服务器地址、关联整合包信息）
    [self loadServerDetails];

    // 监听背景 UI 效果变化通知，当用户切换背景效果（半透明/毛玻璃）时重新应用透明化
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// 背景效果改变时重新应用透明化（由 BackgroundUIEffectChanged 通知触发）
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];

    // 图标
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.layer.cornerRadius = 16;
    self.iconView.clipsToBounds = YES;
    self.iconView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [content addSubview:self.iconView];

    // 标题
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.titleLabel.numberOfLines = 2;
    [content addSubview:self.titleLabel];

    // 元信息（来源/类型/下载量）
    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metaLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.metaLabel.textColor = [UIColor secondaryLabelColor];
    self.metaLabel.numberOfLines = 0;
    [content addSubview:self.metaLabel];

    // 描述
    self.descTextView = [[UITextView alloc] init];
    self.descTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.descTextView.editable = NO;
    self.descTextView.scrollEnabled = NO;
    self.descTextView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.descTextView.backgroundColor = [UIColor clearColor];
    self.descTextView.textContainerInset = UIEdgeInsetsZero;
    self.descTextView.textContainer.lineFragmentPadding = 0;
    [content addSubview:self.descTextView];

    // 服务器地址标签
    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressLabel.font = [UIFont fontWithName:@"Menlo" size:15] ?: [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    self.addressLabel.numberOfLines = 0;
    self.addressLabel.textColor = [UIColor labelColor];
    [content addSubview:self.addressLabel];

    // 复制地址按钮
    self.addressCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addressCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addressCopyButton setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    [self.addressCopyButton setTitle:[@" " stringByAppendingString:localize(@"i18n_str_2060", nil)] forState:UIControlStateNormal];
    self.addressCopyButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.addressCopyButton addTarget:self action:@selector(copyAddress) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.addressCopyButton];

    // 加入服务器按钮
    self.joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.joinButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.joinButton setTitle:localize(@"i18n_str_960", nil) forState:UIControlStateNormal];
    // Task89：全灰新拟态主按钮
    [self.joinButton setTitleColor:[NMTheme nm_label] forState:UIControlStateNormal];
    [self.joinButton nm_convexRadius:10 shadowRadius:5];
    self.joinButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.joinButton addTarget:self action:@selector(joinServer) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.joinButton];

    // 下载服务端文件包按钮
    self.downloadPackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.downloadPackButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.downloadPackButton setTitle:localize(@"i18n_str_961", nil) forState:UIControlStateNormal];
    // Task89：全灰新拟态次按钮
    [self.downloadPackButton setTitleColor:[NMTheme nm_label] forState:UIControlStateNormal];
    [self.downloadPackButton nm_convexRadius:10 shadowRadius:5];
    self.downloadPackButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.downloadPackButton addTarget:self action:@selector(downloadServerPack) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.downloadPackButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [self.iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.iconView.widthAnchor constraintEqualToConstant:64],
        [self.iconView.heightAnchor constraintEqualToConstant:64],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.iconView.centerYAnchor],

        [self.metaLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:12],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.descTextView.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:12],
        [self.descTextView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.descTextView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],

        [self.addressLabel.topAnchor constraintEqualToAnchor:self.descTextView.bottomAnchor constant:16],
        [self.addressLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.addressLabel.trailingAnchor constraintEqualToAnchor:self.addressCopyButton.leadingAnchor constant:-8],

        [self.addressCopyButton.centerYAnchor constraintEqualToAnchor:self.addressLabel.centerYAnchor],
        [self.addressCopyButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.addressCopyButton.heightAnchor constraintEqualToConstant:32],

        [self.joinButton.topAnchor constraintEqualToAnchor:self.addressLabel.bottomAnchor constant:20],
        [self.joinButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.joinButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.joinButton.heightAnchor constraintEqualToConstant:44],

        [self.downloadPackButton.topAnchor constraintEqualToAnchor:self.joinButton.bottomAnchor constant:12],
        [self.downloadPackButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.downloadPackButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.downloadPackButton.heightAnchor constraintEqualToConstant:44],

        [self.downloadPackButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24]
    ]];
}

- (void)populateUI {
    ServerItem *item = self.serverItem;
    UIImage *placeholder = [UIImage imageNamed:@"DefaultProfile"];
    [self.iconView setImageWithURL:[NSURL URLWithString:item.iconURL] placeholderImage:placeholder];

    self.titleLabel.text = item.title.length ? item.title : item.serverID;

    NSString *sourceTag = (item.apiSource == ServerAPISourceCurseForge) ? @"CurseForge" : @"Modrinth";
    NSString *typeTag = item.projectType ?: @"server";
    self.metaLabel.text = [NSString stringWithFormat:localize(@"i18n_str_962", nil),
                           sourceTag, typeTag,
                           [item formattedDownloads], [item formattedLikes],
                           item.author.length ? item.author : @"-"];

    self.descTextView.text = item.serverDescription.length ? item.serverDescription : localize(@"i18n_str_29", nil);

    NSString *addr = item.serverAddress.length ? item.serverAddress : localize(@"i18n_str_963", nil);
    self.addressLabel.text = addr;

    // 没有关联整合包时禁用下载按钮
    BOOL hasModpack = (item.associatedModpackID.length > 0) || (item.serverPackDownloadURL.length > 0);
    self.downloadPackButton.enabled = hasModpack;
    self.downloadPackButton.alpha = hasModpack ? 1.0 : 0.5;

    // 没有地址时禁用加入按钮
    BOOL hasAddr = item.serverAddress.length > 0;
    self.joinButton.enabled = hasAddr;
    self.joinButton.alpha = hasAddr ? 1.0 : 0.5;
}

- (void)loadServerDetails {
    if (!self.serverItem.serverID.length) return;
    __weak typeof(self) weakSelf = self;
    [[ServerService sharedService] getServerDetailsWithAPI:self.api
                                                  serverID:self.serverItem.serverID
                                                 completion:^(ServerItem * _Nullable server, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !server) {
            NSLog(@"[ServerDetail] Failed to fetch details: %@", error.localizedDescription);
            // 详情获取失败不弹错误，保留搜索阶段已有的信息
            return;
        }
        // 合并详情字段（不覆盖已有的标题/描述，只补充地址和整合包信息）
        if (server.serverAddress.length > 0) {
            strongSelf.serverItem.serverAddress = server.serverAddress;
        }
        if (server.associatedModpackID.length > 0) {
            strongSelf.serverItem.associatedModpackID = server.associatedModpackID;
            strongSelf.serverItem.associatedModpackSource = server.associatedModpackSource;
        }
        if (server.serverPackDownloadURL.length > 0) {
            strongSelf.serverItem.serverPackDownloadURL = server.serverPackDownloadURL;
            strongSelf.serverItem.serverPackFileName = server.serverPackFileName;
            strongSelf.serverItem.serverPackFileSize = server.serverPackFileSize;
        }
        if (server.serverDescription.length > 0 && strongSelf.serverItem.serverDescription.length == 0) {
            strongSelf.serverItem.serverDescription = server.serverDescription;
        }
        [strongSelf populateUI];
    }];
}

#pragma mark - Actions

- (void)copyAddress {
    NSString *addr = self.serverItem.serverAddress;
    if (addr.length == 0) {
        self.currentMessageView = [InlineMessageView showInViewController:self
                                                                    title:localize(@"i18n_str_388", nil)
                                                                 message:localize(@"i18n_str_964", nil)
                                                                    type:InlineMessageTypeInfo];
        return;
    }
    [UIPasteboard generalPasteboard].string = addr;
    self.currentMessageView = [InlineMessageView showInViewController:self
                                                                title:localize(@"i18n_str_965", nil)
                                                             message:addr
                                                                type:InlineMessageTypeSuccess];
}

- (void)joinServer {
    NSString *addr = self.serverItem.serverAddress;
    if (addr.length == 0) {
        self.currentMessageView = [InlineMessageView showInViewController:self
                                                                    title:localize(@"i18n_str_388", nil)
                                                                 message:localize(@"i18n_str_966", nil)
                                                                    type:InlineMessageTypeInfo];
        return;
    }

    NSString *profileName = [PLProfiles.current selectedProfileName];
    NSError *error = nil;
    BOOL ok = [[ServerService sharedService] joinServer:addr forProfile:profileName error:&error];
    if (ok) {
        NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_967", nil), profileName, addr];
        self.currentMessageView = [InlineMessageView showInViewController:self
                                                                    title:localize(@"i18n_str_968", nil)
                                                                 message:msg
                                                                    type:InlineMessageTypeSuccess];
    } else {
        self.currentMessageView = [InlineMessageView showInViewController:self
                                                                    title:localize(@"Error", nil)
                                                                 message:error.localizedDescription
                                                                    type:InlineMessageTypeError];
    }
}

- (void)downloadServerPack {
    ServerItem *item = self.serverItem;
    if (item.serverPackDownloadURL.length == 0) {
        // 如果有关联整合包 ID 但没有直接下载链接，提示先查看关联整合包
        if (item.associatedModpackID.length > 0) {
            NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_969", nil), item.associatedModpackID];
            self.currentMessageView = [InlineMessageView showInViewController:self
                                                                        title:localize(@"i18n_str_388", nil)
                                                                     message:msg
                                                                        type:InlineMessageTypeInfo];
        } else {
            self.currentMessageView = [InlineMessageView showInViewController:self
                                                                        title:localize(@"i18n_str_388", nil)
                                                                     message:localize(@"i18n_str_970", nil)
                                                                        type:InlineMessageTypeInfo];
        }
        return;
    }

    NSString *profileName = [PLProfiles.current selectedProfileName];
    if (profileName.length == 0) profileName = @"default";

    self.joinButton.enabled = NO;
    self.downloadPackButton.enabled = NO;
    self.currentMessageView = [InlineMessageView showInViewController:self
                                                                title:localize(@"i18n_str_138", nil)
                                                             message:item.serverPackFileName ?: item.serverPackDownloadURL.lastPathComponent
                                                                type:InlineMessageTypeLoading];

    __weak typeof(self) weakSelf = self;
    [[ServerService sharedService] downloadServerPack:item
                                            toProfile:profileName
                                             progress:^(NSProgress *progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        double p = progress.fractionCompleted;
        NSString *msg = [NSString stringWithFormat:localize(@"i18n_str_971", nil),
                         p * 100, progress.completedUnitCount, progress.totalUnitCount];
        [strongSelf.currentMessageView updateMessage:msg];
    } completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.joinButton.enabled = YES;
        strongSelf.downloadPackButton.enabled = YES;
        if (error) {
            strongSelf.currentMessageView = [InlineMessageView showInViewController:strongSelf
                                                                              title:localize(@"Error", nil)
                                                                           message:error.localizedDescription
                                                                              type:InlineMessageTypeError];
        } else {
            strongSelf.currentMessageView = [InlineMessageView showInViewController:strongSelf
                                                                              title:localize(@"i18n_str_227", nil)
                                                                           message:localize(@"i18n_str_972", nil)
                                                                              type:InlineMessageTypeSuccess];
        }
    }];
}

@end
