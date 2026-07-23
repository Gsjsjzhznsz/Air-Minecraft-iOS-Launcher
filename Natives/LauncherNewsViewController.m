#import "LauncherNewsViewController.h"
#import "HomeCustomizeViewController.h"
#import "authenticator/BaseAuthenticator.h"
#import "LauncherPreferences.h"
#import "ModsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "ModpackImportViewController.h"
#import "BackgroundSettingsViewController.h"
#import "BackgroundManager.h"
#import "PLProfiles.h"
#import "utils.h"
#import "ios_uikit_bridge.h"
#import "MinecraftNewsService.h"
#import "MinecraftNewsItem.h"
#import "MinecraftNewsViewController.h"
#import "AnnouncementService.h"
#import "AnnouncementItem.h"
#import "AnnouncementListViewController.h"
#import "IconLoader.h"
#import <SafariServices/SafariServices.h>
#import <QuartzCore/QuartzCore.h>

// MARK: - Shortcut Action Constants

NSString * const kShortcutActionMods       = @"mods";
NSString * const kShortcutActionShaders    = @"shaders";
NSString * const kShortcutActionModpack    = @"modpack";
NSString * const kShortcutActionBackground = @"background";
NSString * const kShortcutActionVersions   = @"versions";

// MARK: - Color Helpers

static UIColor *colorFromHex(NSString *hex) {
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// MARK: - HomeTileConfig Implementation

@implementation HomeTileConfig

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _tileId = [coder decodeObjectOfClass:[NSString class] forKey:@"tileId"];
        _tileType = [coder decodeIntegerForKey:@"tileType"];
        _tileSize = [coder decodeIntegerForKey:@"tileSize"];
        _visible = [coder decodeBoolForKey:@"visible"];
        _customTitle = [coder decodeObjectOfClass:[NSString class] forKey:@"customTitle"];
        _iconName = [coder decodeObjectOfClass:[NSString class] forKey:@"iconName"];
        _accentColorHex = [coder decodeObjectOfClass:[NSString class] forKey:@"accentColorHex"];
        _shortcutAction = [coder decodeObjectOfClass:[NSString class] forKey:@"shortcutAction"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_tileId forKey:@"tileId"];
    [coder encodeInteger:_tileType forKey:@"tileType"];
    [coder encodeInteger:_tileSize forKey:@"tileSize"];
    [coder encodeBool:_visible forKey:@"visible"];
    [coder encodeObject:_customTitle forKey:@"customTitle"];
    [coder encodeObject:_iconName forKey:@"iconName"];
    [coder encodeObject:_accentColorHex forKey:@"accentColorHex"];
    [coder encodeObject:_shortcutAction forKey:@"shortcutAction"];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (_tileId) dict[@"tileId"] = _tileId;
    dict[@"tileType"] = @(_tileType);
    dict[@"tileSize"] = @(_tileSize);
    dict[@"visible"] = @(_visible);
    if (_customTitle) dict[@"customTitle"] = _customTitle;
    if (_iconName) dict[@"iconName"] = _iconName;
    if (_accentColorHex) dict[@"accentColorHex"] = _accentColorHex;
    if (_shortcutAction) dict[@"shortcutAction"] = _shortcutAction;
    return dict;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    HomeTileConfig *config = [[HomeTileConfig alloc] init];
    config.tileId = dict[@"tileId"];
    config.tileType = [dict[@"tileType"] integerValue];
    config.tileSize = [dict[@"tileSize"] integerValue];
    config.visible = [dict[@"visible"] boolValue];
    config.customTitle = dict[@"customTitle"];
    config.iconName = dict[@"iconName"];
    config.accentColorHex = dict[@"accentColorHex"];
    config.shortcutAction = dict[@"shortcutAction"];
    return config;
}

- (UIColor *)accentColor {
    if (_accentColorHex) return colorFromHex(_accentColorHex);
    // 默认颜色基于磁贴类型
    switch (_tileType) {
        case HomeTileTypeProfile:        return colorFromHex(@"#8B5CF6");
        case HomeTileTypeAnnouncement:   return colorFromHex(@"#3B82F6");
        case HomeTileTypeVersionRelease: return colorFromHex(@"#10B981");
        case HomeTileTypeVersionSnapshot:return colorFromHex(@"#F59E0B");
        case HomeTileTypeNews:           return colorFromHex(@"#EF4444");
        case HomeTileTypeShortcut:       return colorFromHex(@"#14B8A6");
        default:                         return [UIColor systemBlueColor];
    }
}

+ (NSArray<HomeTileConfig *> *)defaultTileConfigs {
    NSMutableArray *tiles = [NSMutableArray array];
    
    // 0. 用户资料 (全宽)
    HomeTileConfig *profile = [[HomeTileConfig alloc] init];
    profile.tileId = @"profile";
    profile.tileType = HomeTileTypeProfile;
    profile.tileSize = HomeTileSizeFull;
    profile.visible = YES;
    profile.iconName = @"person.crop.circle.fill";
    profile.accentColorHex = @"#8B5CF6";
    [tiles addObject:profile];
    
    // 1. 公告 (全宽) — 位于版本信息之前
    HomeTileConfig *announcement = [[HomeTileConfig alloc] init];
    announcement.tileId = @"announcement";
    announcement.tileType = HomeTileTypeAnnouncement;
    announcement.tileSize = HomeTileSizeFull;
    announcement.visible = YES;
    announcement.iconName = @"megaphone.fill";
    announcement.accentColorHex = @"#3B82F6";
    [tiles addObject:announcement];
    
    // 2. 最新正式版 (半宽)
    HomeTileConfig *release = [[HomeTileConfig alloc] init];
    release.tileId = @"latest_release";
    release.tileType = HomeTileTypeVersionRelease;
    release.tileSize = HomeTileSizeCompact;
    release.visible = YES;
    release.iconName = @"cube.box.fill";
    release.accentColorHex = @"#10B981";
    [tiles addObject:release];
    
    // 3. 最新快照 (半宽)
    HomeTileConfig *snapshot = [[HomeTileConfig alloc] init];
    snapshot.tileId = @"latest_snapshot";
    snapshot.tileType = HomeTileTypeVersionSnapshot;
    snapshot.tileSize = HomeTileSizeCompact;
    snapshot.visible = YES;
    snapshot.iconName = @"ant.fill";
    snapshot.accentColorHex = @"#F59E0B";
    [tiles addObject:snapshot];
    
    // 4. 新闻 (全宽)
    HomeTileConfig *news = [[HomeTileConfig alloc] init];
    news.tileId = @"news";
    news.tileType = HomeTileTypeNews;
    news.tileSize = HomeTileSizeFull;
    news.visible = YES;
    news.iconName = @"newspaper.fill";
    news.accentColorHex = @"#EF4444";
    [tiles addObject:news];
    
    // 5. 快捷入口: Mod管理 (半宽)
    HomeTileConfig *mods = [[HomeTileConfig alloc] init];
    mods.tileId = @"shortcut_mods";
    mods.tileType = HomeTileTypeShortcut;
    mods.tileSize = HomeTileSizeCompact;
    mods.visible = YES;
    mods.customTitle = @"Mod 管理";
    mods.iconName = @"puzzlepiece.extension.fill";
    mods.shortcutAction = kShortcutActionMods;
    mods.accentColorHex = @"#14B8A6";
    [tiles addObject:mods];
    
    // 6. 快捷入口: 光影管理 (半宽)
    HomeTileConfig *shaders = [[HomeTileConfig alloc] init];
    shaders.tileId = @"shortcut_shaders";
    shaders.tileType = HomeTileTypeShortcut;
    shaders.tileSize = HomeTileSizeCompact;
    shaders.visible = YES;
    shaders.customTitle = @"光影管理";
    shaders.iconName = @"sun.max.fill";
    shaders.shortcutAction = kShortcutActionShaders;
    shaders.accentColorHex = @"#F97316";
    [tiles addObject:shaders];
    
    // 7. 快捷入口: 整合包 (半宽)
    HomeTileConfig *modpack = [[HomeTileConfig alloc] init];
    modpack.tileId = @"shortcut_modpack";
    modpack.tileType = HomeTileTypeShortcut;
    modpack.tileSize = HomeTileSizeCompact;
    modpack.visible = YES;
    modpack.customTitle = @"整合包导入";
    modpack.iconName = @"shippingbox.fill";
    modpack.shortcutAction = kShortcutActionModpack;
    modpack.accentColorHex = @"#8B5CF6";
    [tiles addObject:modpack];
    
    // 8. 快捷入口: 壁纸设置 (半宽)
    HomeTileConfig *bg = [[HomeTileConfig alloc] init];
    bg.tileId = @"shortcut_bg";
    bg.tileType = HomeTileTypeShortcut;
    bg.tileSize = HomeTileSizeCompact;
    bg.visible = YES;
    bg.customTitle = @"壁纸设置";
    bg.iconName = @"photo.fill.on.rectangle.fill";
    bg.shortcutAction = kShortcutActionBackground;
    bg.accentColorHex = @"#EC4899";
    [tiles addObject:bg];
    
    return tiles;
}

+ (NSArray<HomeTileConfig *> *)loadSavedConfigs {
    NSArray *savedArray = [[NSUserDefaults standardUserDefaults] objectForKey:@"home_tiles_config"];
    if (!savedArray || ![savedArray isKindOfClass:[NSArray class]]) {
        return [self defaultTileConfigs];
    }
    
    NSMutableArray *configs = [NSMutableArray array];
    for (NSDictionary *dict in savedArray) {
        if ([dict isKindOfClass:[NSDictionary class]]) {
            [configs addObject:[self fromDictionary:dict]];
        }
    }
    return configs.count > 0 ? configs : [self defaultTileConfigs];
}

+ (void)saveConfigs:(NSArray<HomeTileConfig *> *)configs {
    NSMutableArray *arr = [NSMutableArray array];
    for (HomeTileConfig *c in configs) {
        [arr addObject:[c toDictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:@"home_tiles_config"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// MARK: - Festival Detection

static NSString *festivalGreeting(void) {
    NSDate *now = [NSDate date];
    NSCalendar *gregorian = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *solar = [gregorian components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
    NSInteger month = solar.month;
    NSInteger day = solar.day;
    
    // 公历节日
    if (month == 1  && day == 1)  return @"元旦快乐！🎊";
    if (month == 4  && (day >= 4 && day <= 6)) return @"清明节安康！🌿";
    if (month == 5  && day == 1)  return @"劳动节快乐！💪";
    if (month == 6  && day == 1)  return @"六一儿童节快乐！🎈";
    if (month == 9  && day == 10) return @"教师节快乐！🌹";
    if (month == 10 && (day >= 1 && day <= 7)) return @"国庆节快乐！🇨🇳";
    if (month == 12 && day == 24) return @"平安夜快乐！🌟";
    if (month == 12 && day == 25) return @"圣诞节快乐！🎄";
    
    // 农历节日 (使用中国日历)
    NSCalendar *chineseCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *lunar = [chineseCalendar components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
    NSInteger lunarMonth = lunar.month;
    NSInteger lunarDay = lunar.day;
    
    if (lunarMonth == 1  && lunarDay == 1)  return @"新春快乐！🎆";
    if (lunarMonth == 1  && lunarDay == 2)  return @"新春快乐！🧨";
    if (lunarMonth == 1  && lunarDay == 3)  return @"新春快乐！🎇";
    if (lunarMonth == 1  && lunarDay == 15) return @"元宵节快乐！🏮";
    if (lunarMonth == 5  && lunarDay == 5)  return @"端午节安康！🐲";
    if (lunarMonth == 7  && lunarDay == 7)  return @"七夕节快乐！💕";
    if (lunarMonth == 8  && lunarDay == 15) return @"中秋节快乐！🌕";
    if (lunarMonth == 9  && lunarDay == 9)  return @"重阳节安康！🏔️";
    if (lunarMonth == 12 && (lunarDay == 29 || lunarDay == 30)) return @"除夕夜快乐！🎇";
    
    // 非节日 - 按时段随机问候
    NSInteger hour = [gregorian component:NSCalendarUnitHour fromDate:now];
    if (hour < 6)       return @"夜深了，注意休息哦 🌙";
    if (hour < 12)      return @"早上好！美好的一天开始了 ☀️";
    if (hour < 14)      return @"中午好！记得吃午饭哦 🍚";
    if (hour < 18)      return @"下午好！今天也要加油哦 💪";
    return @"晚上好！放松一下吧 🌃";
}

// MARK: - HomeTileBaseCell

@interface HomeTileBaseCell : UICollectionViewCell
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) CAGradientLayer *accentBar;
- (void)setupBaseViews;
- (void)setAccentColor:(UIColor *)color;
@end

@implementation HomeTileBaseCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupBaseViews];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleBackgroundUIEffectChanged)
                                                     name:@"BackgroundUIEffectChanged"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleBackgroundUIEffectChanged {
    [[BackgroundManager sharedManager] applyEffectToCollectionViewCell:self];
}

- (void)setupBaseViews {
    // 阴影
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowOpacity = 0.15;
    self.layer.shadowRadius = 10;
    self.layer.masksToBounds = NO;
    
    // 渐变装饰条
    self.accentBar = [CAGradientLayer layer];
    self.accentBar.frame = CGRectMake(0, 0, self.contentView.bounds.size.width, 3);
    self.accentBar.startPoint = CGPointMake(0, 0.5);
    self.accentBar.endPoint = CGPointMake(1, 0.5);
    self.accentBar.cornerRadius = 1.5;
    [self.contentView.layer addSublayer:self.accentBar];
    
    // 内容容器
    self.contentContainer = [[UIView alloc] initWithFrame:self.contentView.bounds];
    self.contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.contentContainer.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:self.contentContainer];
    
    [[BackgroundManager sharedManager] applyEffectToCollectionViewCell:self];
}

- (void)setAccentColor:(UIColor *)color {
    CGFloat h, s, b, a;
    [color getHue:&h saturation:&s brightness:&b alpha:&a];
    UIColor *lighter = [UIColor colorWithHue:h saturation:s * 0.7 brightness:MIN(b * 1.3, 1.0) alpha:a];
    self.accentBar.colors = @[(id)color.CGColor, (id)lighter.CGColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.accentBar.frame = CGRectMake(0, 0, self.contentView.bounds.size.width, 3);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.contentView.bounds cornerRadius:16].CGPath;
}

// 弹簧按压动画
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:nil];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end

// MARK: - HomeProfileTileCell

@interface HomeProfileTileCell : HomeTileBaseCell
@property (nonatomic, strong) UIImageView *skinImageView;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *welcomeLabel;
@property (nonatomic, strong) UILabel *greetingLabel;
@end

@implementation HomeProfileTileCell

- (void)setupBaseViews {
    [super setupBaseViews];
    
    // 皮肤全身预览
    self.skinImageView = [[UIImageView alloc] init];
    self.skinImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.skinImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.skinImageView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.skinImageView.layer.shadowOffset = CGSizeMake(2, 4);
    self.skinImageView.layer.shadowOpacity = 0.35;
    self.skinImageView.layer.shadowRadius = 6;
    [self.contentContainer addSubview:self.skinImageView];
    
    // 头像 (圆形)
    self.avatarImageView = [[UIImageView alloc] init];
    self.avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarImageView.layer.cornerRadius = 26;
    self.avatarImageView.layer.masksToBounds = YES;
    self.avatarImageView.layer.borderWidth = 2.5;
    self.avatarImageView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    self.avatarImageView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.avatarImageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
    self.avatarImageView.tintColor = [UIColor systemGrayColor];
    [self.contentContainer addSubview:self.avatarImageView];
    
    // 欢迎文本
    self.welcomeLabel = [[UILabel alloc] init];
    self.welcomeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.welcomeLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    self.welcomeLabel.textColor = [UIColor labelColor];
    self.welcomeLabel.numberOfLines = 1;
    self.welcomeLabel.adjustsFontSizeToFitWidth = YES;
    self.welcomeLabel.minimumScaleFactor = 0.7;
    [self.contentContainer addSubview:self.welcomeLabel];
    
    // 节日/时段问候
    self.greetingLabel = [[UILabel alloc] init];
    self.greetingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.greetingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.greetingLabel.textColor = [UIColor secondaryLabelColor];
    self.greetingLabel.numberOfLines = 1;
    [self.contentContainer addSubview:self.greetingLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        // 皮肤预览 (左侧)
        [self.skinImageView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:18],
        [self.skinImageView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:10],
        [self.skinImageView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor constant:-8],
        [self.skinImageView.widthAnchor constraintEqualToAnchor:self.skinImageView.heightAnchor multiplier:0.55],
        
        // 头像 (皮肤右侧)
        [self.avatarImageView.leadingAnchor constraintEqualToAnchor:self.skinImageView.trailingAnchor constant:18],
        [self.avatarImageView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor constant:-14],
        [self.avatarImageView.widthAnchor constraintEqualToConstant:52],
        [self.avatarImageView.heightAnchor constraintEqualToConstant:52],
        
        // 欢迎文本
        [self.welcomeLabel.leadingAnchor constraintEqualToAnchor:self.avatarImageView.trailingAnchor constant:14],
        [self.welcomeLabel.centerYAnchor constraintEqualToAnchor:self.avatarImageView.centerYAnchor constant:-10],
        [self.welcomeLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-18],
        
        // 问候语
        [self.greetingLabel.leadingAnchor constraintEqualToAnchor:self.welcomeLabel.leadingAnchor],
        [self.greetingLabel.topAnchor constraintEqualToAnchor:self.welcomeLabel.bottomAnchor constant:4],
        [self.greetingLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-18],
    ]];
}

@end

// MARK: - HomeInfoTileCell

@interface HomeInfoTileCell : HomeTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@end

@implementation HomeInfoTileCell

- (void)setupBaseViews {
    [super setupBaseViews];
    
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [UIColor systemGreenColor];
    [self.contentContainer addSubview:self.iconView];
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.titleLabel.textColor = [UIColor tertiaryLabelColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    [self.contentContainer addSubview:self.titleLabel];
    
    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.valueLabel.textColor = [UIColor labelColor];
    self.valueLabel.numberOfLines = 2;
    self.valueLabel.adjustsFontSizeToFitWidth = YES;
    self.valueLabel.minimumScaleFactor = 0.6;
    [self.contentContainer addSubview:self.valueLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:18],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.iconView.widthAnchor constraintEqualToConstant:26],
        [self.iconView.heightAnchor constraintEqualToConstant:26],
        
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.iconView.centerYAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:8],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-16],
        
        [self.valueLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:10],
        [self.valueLabel.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-16],
    ]];
}

@end

// MARK: - HomeAnnouncementTileCell

@interface HomeAnnouncementTileCell : HomeTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *actionButton;
@end

@implementation HomeAnnouncementTileCell

- (void)setupBaseViews {
    [super setupBaseViews];
    
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.image = [UIImage systemImageNamed:@"megaphone.fill"];
    self.iconView.tintColor = colorFromHex(@"#3B82F6");
    [self.contentContainer addSubview:self.iconView];
    
    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.messageLabel.textColor = [UIColor labelColor];
    self.messageLabel.numberOfLines = 0;
    [self.contentContainer addSubview:self.messageLabel];
    
    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.actionButton.layer.cornerRadius = 8;
    self.actionButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.actionButton.clipsToBounds = YES;
    self.actionButton.hidden = YES;
    [self.contentContainer addSubview:self.actionButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:16],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.iconView.widthAnchor constraintEqualToConstant:22],
        [self.iconView.heightAnchor constraintEqualToConstant:22],
        
        [self.messageLabel.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:16],
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:10],
        [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-16],
        
        [self.actionButton.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:10],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.actionButton.widthAnchor constraintEqualToConstant:100],
        [self.actionButton.heightAnchor constraintEqualToConstant:30],
    ]];
}

@end

// MARK: - HomeNewsTileCell

@interface HomeNewsTileCell : HomeTileBaseCell
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation HomeNewsTileCell

- (void)setupBaseViews {
    [super setupBaseViews];
    
    // 左侧缩略图占位
    self.thumbnailView = [[UIImageView alloc] init];
    self.thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailView.clipsToBounds = YES;
    self.thumbnailView.layer.cornerRadius = 10;
    self.thumbnailView.layer.cornerCurve = kCACornerCurveContinuous;
    self.thumbnailView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.thumbnailView.image = [UIImage systemImageNamed:@"newspaper.fill"];
    self.thumbnailView.tintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    [self.contentContainer addSubview:self.thumbnailView];
    
    // 标题
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 2;
    [self.contentContainer addSubview:self.titleLabel];
    
    // 摘要
    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.summaryLabel.textColor = [UIColor tertiaryLabelColor];
    self.summaryLabel.numberOfLines = 2;
    [self.contentContainer addSubview:self.summaryLabel];
    
    // 占位提示
    self.placeholderLabel = [[UILabel alloc] init];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.placeholderLabel.textColor = [UIColor quaternaryLabelColor];
    self.placeholderLabel.text = @"即将推出";
    [self.contentContainer addSubview:self.placeholderLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:14],
        [self.thumbnailView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.thumbnailView.widthAnchor constraintEqualToConstant:80],
        [self.thumbnailView.heightAnchor constraintEqualToConstant:60],
        
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.thumbnailView.topAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumbnailView.trailingAnchor constant:14],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-14],
        
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        
        [self.placeholderLabel.bottomAnchor constraintEqualToAnchor:self.thumbnailView.bottomAnchor],
        [self.placeholderLabel.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-14],
    ]];
}

@end

// MARK: - HomeShortcutTileCell

@interface HomeShortcutTileCell : HomeTileBaseCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation HomeShortcutTileCell

- (void)setupBaseViews {
    [super setupBaseViews];
    
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [UIColor systemTealColor];
    [self.contentContainer addSubview:self.iconView];
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.7;
    [self.contentContainer addSubview:self.titleLabel];
    
    self.chevronView = [[UIImageView alloc] init];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
    self.chevronView.image = [UIImage systemImageNamed:@"chevron.right"];
    self.chevronView.tintColor = [UIColor tertiaryLabelColor];
    [self.contentContainer addSubview:self.chevronView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:16],
        [self.iconView.widthAnchor constraintEqualToConstant:28],
        [self.iconView.heightAnchor constraintEqualToConstant:28],
        
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-8],
        
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.contentContainer.centerYAnchor],
        [self.chevronView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-14],
        [self.chevronView.widthAnchor constraintEqualToConstant:12],
        [self.chevronView.heightAnchor constraintEqualToConstant:16],
    ]];
}

@end

// MARK: - LauncherNewsViewController

@interface LauncherNewsViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UIButton *customizeButton;

// 磁贴配置
@property (nonatomic, strong) NSMutableArray<HomeTileConfig *> *allTileConfigs;
@property (nonatomic, strong) NSArray<NSArray<HomeTileConfig *> *> *displaySections;

// 数据
@property (nonatomic, strong) NSString *latestRelease;
@property (nonatomic, strong) NSString *latestSnapshot;
@property (nonatomic, strong) NSString *currentUsername;
@property (nonatomic, strong) UIImage *currentSkin;
@property (nonatomic, strong) UIImage *currentAvatar;
@property (nonatomic, assign) BOOL isLoadingVersions;

// 公告/更新检测
@property (nonatomic, strong) NSString *announcementText;
@property (nonatomic, assign) BOOL hasUpdate;
@property (nonatomic, strong) NSString *latestVersion;
// 公告系统（从官网拉取 JSON 的最新一条公告）
@property (nonatomic, strong, nullable) AnnouncementItem *latestAnnouncement;

// MC 新闻（首页 News tile 预览用，展示最新一条）
@property (nonatomic, strong, nullable) MinecraftNewsItem *latestNewsItem;
@property (nonatomic, assign) BOOL isLoadingNews;

@end

@implementation LauncherNewsViewController

- (id)init {
    self = [super init];
    if (self) {
        // 不设置 self.title，避免顶部导航栏出现"主页"标题黑条（参照 FCL 无 title 风格）
        self.latestRelease = @"检测中...";
        self.latestSnapshot = @"检测中...";
        self.isLoadingVersions = YES;
        self.announcementText = @"正在检查更新...";
        self.hasUpdate = NO;
    }
    return self;
}

- (NSString *)imageName {
    return @"MenuNews";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    self.navigationController.navigationBarHidden = YES;
    
    // 加载磁贴配置
    self.allTileConfigs = [[HomeTileConfig loadSavedConfigs] mutableCopy];
    [self rebuildDisplaySections];
    
    [self setupHeader];
    [self setupCollectionView];
    [self updateSkinDisplay];
    [self checkMinecraftVersions];
    [self checkForUpdate];
    [self loadLatestNewsForTile];
    [self loadAnnouncementsForTile];

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 本控制器为 UIViewController 子类，其 collectionView 为手动创建，
    // makeViewControllerTransparent 会设置 view 背景透明；collectionView 背景已在 setupCollectionView 中清空。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateSkinDisplay)
                                                 name:@"AccountChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateSkinDisplay)
                                                 name:@"UpdateAccountInfo"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: - Build Display Sections

- (void)rebuildDisplaySections {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *currentCompactGroup = nil;
    
    for (HomeTileConfig *tile in self.allTileConfigs) {
        if (!tile.visible) continue;
        
        if (tile.tileSize == HomeTileSizeCompact) {
            if (!currentCompactGroup) {
                currentCompactGroup = [NSMutableArray array];
            }
            [currentCompactGroup addObject:tile];
            if (currentCompactGroup.count >= 2) {
                [sections addObject:[currentCompactGroup copy]];
                currentCompactGroup = nil;
            }
        } else {
            if (currentCompactGroup.count > 0) {
                [sections addObject:[currentCompactGroup copy]];
                currentCompactGroup = nil;
            }
            [sections addObject:@[tile]];
        }
    }
    if (currentCompactGroup.count > 0) {
        [sections addObject:[currentCompactGroup copy]];
    }
    
    self.displaySections = sections;
}

// MARK: - Header Setup

- (void)setupHeader {
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerView];
    
    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.text = @"主页";
    self.headerTitleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    self.headerTitleLabel.textColor = [UIColor labelColor];
    [self.headerView addSubview:self.headerTitleLabel];
    
    self.customizeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.customizeButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *gearIcon = [UIImage systemImageNamed:@"slider.horizontal.3"];
    [self.customizeButton setImage:gearIcon forState:UIControlStateNormal];
    [self.customizeButton setTitle:@" 自定义" forState:UIControlStateNormal];
    self.customizeButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.customizeButton.tintColor = [UIColor secondaryLabelColor];
    [self.customizeButton addTarget:self action:@selector(openCustomize) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.customizeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:44],
        
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:20],
        [self.headerTitleLabel.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
        
        [self.customizeButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-20],
        [self.customizeButton.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
    ]];
}

// MARK: - Collection View Setup

- (void)setupCollectionView {
    UICollectionViewLayout *layout = [self createLayout];
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0);
    
    [self.collectionView registerClass:[HomeProfileTileCell class]      forCellWithReuseIdentifier:@"ProfileCell"];
    [self.collectionView registerClass:[HomeInfoTileCell class]         forCellWithReuseIdentifier:@"InfoCell"];
    [self.collectionView registerClass:[HomeAnnouncementTileCell class] forCellWithReuseIdentifier:@"AnnouncementCell"];
    [self.collectionView registerClass:[HomeNewsTileCell class]         forCellWithReuseIdentifier:@"NewsCell"];
    [self.collectionView registerClass:[HomeShortcutTileCell class]     forCellWithReuseIdentifier:@"ShortcutCell"];
    
    [self.view addSubview:self.collectionView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (CGFloat)heightForTileConfig:(HomeTileConfig *)config {
    switch (config.tileType) {
        case HomeTileTypeProfile:
            return config.tileSize == HomeTileSizeFull ? 170 : 140;
        case HomeTileTypeAnnouncement:
            return 90;
        case HomeTileTypeVersionRelease:
        case HomeTileTypeVersionSnapshot:
            return 100;
        case HomeTileTypeNews:
            return config.tileSize == HomeTileSizeFull ? 120 : 100;
        case HomeTileTypeShortcut:
            return 76;
        default:
            return 100;
    }
}

- (UICollectionViewLayout *)createLayout {
    __weak typeof(self) weakSelf = self;
    
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
        
        if (sectionIndex >= weakSelf.displaySections.count) return nil;
        
        NSArray *sectionTiles = weakSelf.displaySections[sectionIndex];
        HomeTileConfig *firstTile = sectionTiles.firstObject;
        BOOL isCompact = (firstTile.tileSize == HomeTileSizeCompact);
        CGFloat height = [weakSelf heightForTileConfig:firstTile];
        
        if (isCompact && sectionTiles.count >= 2) {
            // 双列紧凑布局
            NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]
                heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
            item.contentInsets = NSDirectionalEdgeInsetsMake(0, 5, 0, 5);
            
            NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
            NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];
            
            NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
            section.contentInsets = NSDirectionalEdgeInsetsMake(5, 15, 5, 15);
            section.interGroupSpacing = 10;
            return section;
            
        } else {
            // 全宽 / 单个紧凑磁贴
            CGFloat wFrac = isCompact ? 0.5 : 1.0;
            NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:wFrac]
                heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
            item.contentInsets = NSDirectionalEdgeInsetsMake(0, 5, 0, 5);
            
            NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
            NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];
            
            NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
            section.contentInsets = NSDirectionalEdgeInsetsMake(5, 15, 5, 15);
            return section;
        }
    }];
}

// MARK: - UICollectionView DataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.displaySections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.displaySections[section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HomeTileConfig *config = self.displaySections[indexPath.section][indexPath.item];
    
    switch (config.tileType) {
        case HomeTileTypeProfile: {
            HomeProfileTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ProfileCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];
            
            NSString *name = self.currentUsername ?: @"玩家";
            cell.welcomeLabel.text = [NSString stringWithFormat:@"欢迎回来, %@!", name];
            cell.greetingLabel.text = festivalGreeting();
            cell.skinImageView.image = self.currentSkin ?: [UIImage systemImageNamed:@"person.fill"];
            if (self.currentAvatar) {
                cell.avatarImageView.image = self.currentAvatar;
            } else {
                cell.avatarImageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
                cell.avatarImageView.tintColor = [UIColor systemGrayColor];
            }
            return cell;
        }
            
        case HomeTileTypeVersionRelease: {
            HomeInfoTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"InfoCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];
            cell.titleLabel.text = config.customTitle ?: @"最新正式版";
            cell.valueLabel.text = self.latestRelease;
            cell.iconView.image = [UIImage systemImageNamed:config.iconName ?: @"cube.box.fill"];
            cell.iconView.tintColor = [config accentColor];
            return cell;
        }
            
        case HomeTileTypeVersionSnapshot: {
            HomeInfoTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"InfoCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];
            cell.titleLabel.text = config.customTitle ?: @"最新快照";
            cell.valueLabel.text = self.latestSnapshot;
            cell.iconView.image = [UIImage systemImageNamed:config.iconName ?: @"ant.fill"];
            cell.iconView.tintColor = [config accentColor];
            return cell;
        }
            
        case HomeTileTypeAnnouncement: {
            HomeAnnouncementTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AnnouncementCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];

            if (self.latestAnnouncement) {
                AnnouncementItem *ann = self.latestAnnouncement;
                NSString *previewLevel = getPrefObject(@"general.announcement_preview_level") ?: @"summary";

                if ([previewLevel isEqualToString:@"title_only"]) {
                    // 仅标题
                    cell.messageLabel.text = ann.title;
                } else if ([previewLevel isEqualToString:@"full"]) {
                    // 完整：标题 + 日期 + 摘要
                    cell.messageLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", ann.title, ann.formattedDateString, ann.summary];
                } else {
                    // summary（默认）：标题 + 摘要
                    cell.messageLabel.text = [NSString stringWithFormat:@"%@\n%@", ann.title, ann.summary];
                }

                // 如果有 actionURL，显示按钮
                if (ann.actionURL.length > 0 && ann.actionTitle.length > 0) {
                    cell.actionButton.hidden = NO;
                    [cell.actionButton setTitle:ann.actionTitle forState:UIControlStateNormal];
                    cell.actionButton.backgroundColor = colorFromHex(@"#3B82F6");
                    [cell.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    [cell.actionButton removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
                    [cell.actionButton addTarget:self action:@selector(openAnnouncementActionURL) forControlEvents:UIControlEventTouchUpInside];
                } else {
                    cell.actionButton.hidden = YES;
                }
            } else {
                // 无公告数据时显示更新检测结果
                cell.messageLabel.text = self.announcementText;

                if (self.hasUpdate) {
                    cell.actionButton.hidden = NO;
                    [cell.actionButton setTitle:@"前往下载" forState:UIControlStateNormal];
                    cell.actionButton.backgroundColor = colorFromHex(@"#3B82F6");
                    [cell.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    [cell.actionButton removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
                    [cell.actionButton addTarget:self action:@selector(downloadLatestVersion) forControlEvents:UIControlEventTouchUpInside];
                } else {
                    cell.actionButton.hidden = YES;
                }
            }
            return cell;
        }
            
        case HomeTileTypeNews: {
            HomeNewsTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"NewsCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];

            if (self.latestNewsItem) {
                // 显示最新一条新闻的标题/摘要/封面
                cell.titleLabel.text = self.latestNewsItem.title ?: @"Minecraft 新闻";
                cell.summaryLabel.text = self.latestNewsItem.summary ?: @"";
                cell.placeholderLabel.text = self.latestNewsItem.formattedDateString ?: @"";
                // 加载封面图（用 IconLoader，带缓存）
                [IconLoader cancelLoadingForImageView:cell.thumbnailView];
                if (self.latestNewsItem.imageURL.length > 0) {
                    [IconLoader loadIconForImageView:cell.thumbnailView
                                                 URL:self.latestNewsItem.imageURL
                                         placeholder:[UIImage systemImageNamed:@"newspaper.fill"]
                                            fallback:[UIImage systemImageNamed:@"newspaper.fill"]
                                        targetSize:CGSizeMake(160, 120)];
                } else {
                    cell.thumbnailView.image = [UIImage systemImageNamed:@"newspaper.fill"];
                }
            } else if (self.isLoadingNews) {
                cell.titleLabel.text = @"Minecraft 新闻";
                cell.summaryLabel.text = @"正在加载最新新闻...";
                cell.placeholderLabel.text = @"加载中...";
                cell.thumbnailView.image = [UIImage systemImageNamed:@"newspaper.fill"];
            } else {
                // 加载失败或未加载
                cell.titleLabel.text = @"Minecraft 新闻";
                cell.summaryLabel.text = @"点击查看 Minecraft 官方新闻";
                cell.placeholderLabel.text = @"点击进入 ✨";
                cell.thumbnailView.image = [UIImage systemImageNamed:@"newspaper.fill"];
            }
            return cell;
        }
            
        case HomeTileTypeShortcut: {
            HomeShortcutTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ShortcutCell" forIndexPath:indexPath];
            [cell setAccentColor:[config accentColor]];
            cell.titleLabel.text = config.customTitle ?: @"快捷入口";
            cell.iconView.image = [UIImage systemImageNamed:config.iconName ?: @"arrow.right.circle.fill"];
            cell.iconView.tintColor = [config accentColor];
            return cell;
        }
    }
    
    // Fallback
    return [collectionView dequeueReusableCellWithReuseIdentifier:@"InfoCell" forIndexPath:indexPath];
}

// MARK: - UICollectionView Delegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];

    HomeTileConfig *config = self.displaySections[indexPath.section][indexPath.item];

    if (config.tileType == HomeTileTypeShortcut) {
        [self handleShortcutAction:config.shortcutAction];
    } else if (config.tileType == HomeTileTypeVersionRelease || config.tileType == HomeTileTypeVersionSnapshot) {
        [self checkMinecraftVersions];
    } else if (config.tileType == HomeTileTypeNews) {
        // 跳转到 MC 新闻列表页
        MinecraftNewsViewController *newsVC = [[MinecraftNewsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:newsVC];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        // 适配自定义启动器背景：透明化导航栏，让全局背景透出
        [self presentViewController:nav animated:YES completion:nil];
    } else if (config.tileType == HomeTileTypeAnnouncement) {
        // 跳转到公告列表页
        AnnouncementListViewController *listVC = [[AnnouncementListViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

// MARK: - Shortcut Actions

- (void)handleShortcutAction:(NSString *)action {
    if ([action isEqualToString:kShortcutActionMods]) {
        // 切到中间内容区版本管理页并直接展开模组管理（参照 FCL 安卓，不再 FormSheet 弹窗）
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowModsManager" object:nil];

    } else if ([action isEqualToString:kShortcutActionShaders]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowShadersManager" object:nil];

    } else if ([action isEqualToString:kShortcutActionModpack]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowModpackImport" object:nil];

    } else if ([action isEqualToString:kShortcutActionBackground]) {
        BackgroundSettingsViewController *vc = [[BackgroundSettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];

    } else if ([action isEqualToString:kShortcutActionVersions]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShowVersionManager" object:nil];
    }
}

// MARK: - Customize

- (void)openCustomize {
    HomeCustomizeViewController *customVC = [[HomeCustomizeViewController alloc] init];
    customVC.tileConfigs = [self.allTileConfigs copy];
    
    __weak typeof(self) weakSelf = self;
    customVC.onConfigsChanged = ^(NSArray<HomeTileConfig *> *newConfigs) {
        weakSelf.allTileConfigs = [newConfigs mutableCopy];
        [HomeTileConfig saveConfigs:newConfigs];
        [weakSelf rebuildDisplaySections];
        
        // 重建布局并刷新
        weakSelf.collectionView.collectionViewLayout = [weakSelf createLayout];
        [weakSelf.collectionView reloadData];
    };
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:customVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // 毛玻璃背景
    if ([[BackgroundManager sharedManager] hasBackground]) {
        nav.view.backgroundColor = [UIColor clearColor];
    }
    
    [self presentViewController:nav animated:YES completion:nil];
}

// MARK: - Data Loading

- (void)updateSkinDisplay {
    BaseAuthenticator *auth = BaseAuthenticator.current;
    
    if (auth && auth.authData) {
        NSString *username = auth.authData[@"username"];
        if (username) {
            if ([username hasPrefix:@"Demo."]) {
                username = [username substringFromIndex:5];
            }
            self.currentUsername = username;
        } else {
            self.currentUsername = @"玩家";
        }
        
        // 加载头像 (与右侧面板相同来源)
        NSString *avatarURL = auth.authData[@"profilePicURL"];
        if (avatarURL) {
            avatarURL = [avatarURL stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:avatarURL]];
                if (data) {
                    UIImage *img = [UIImage imageWithData:data];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.currentAvatar = img;
                        [self reloadProfileSection];
                    });
                }
            });
        }
        
        // 加载皮肤全身图 (原有API)
        NSString *uuid = auth.authData[@"uuid"];
        if (uuid) {
            [self loadSkinForUUID:uuid];
        } else {
            [self loadDefaultSkin];
        }
    } else {
        self.currentUsername = @"未登录";
        self.currentAvatar = nil;
        [self loadDefaultSkin];
    }
    
    [self reloadProfileSection];
}

- (void)loadSkinForUUID:(NSString *)uuid {
    NSString *skinURL = [NSString stringWithFormat:@"http://111.170.35.224:3000/renders/body/%@?overlay", uuid];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:skinURL]];
        UIImage *skin = data ? [UIImage imageWithData:data] : nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (skin) {
                self.currentSkin = skin;
            } else {
                [self loadDefaultSkin];
                return;
            }
            [self reloadProfileSection];
        });
    });
}

- (void)loadDefaultSkin {
    NSString *steveSkinURL = @"http://111.170.35.224:3000/renders/body/8667ba71b85a4004af54457a9734eed7?overlay";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:steveSkinURL]];
        UIImage *steve = data ? [UIImage imageWithData:data] : nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentSkin = steve ?: [UIImage systemImageNamed:@"person.fill"];
            [self reloadProfileSection];
        });
    });
}

- (void)reloadProfileSection {
    // 找到 Profile 类型的 section 并刷新
    for (NSInteger s = 0; s < self.displaySections.count; s++) {
        for (HomeTileConfig *tile in self.displaySections[s]) {
            if (tile.tileType == HomeTileTypeProfile) {
                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:s]];
                return;
            }
        }
    }
}

- (void)loadLatestNewsForTile {
    if (self.isLoadingNews) return;
    self.isLoadingNews = YES;
    __weak typeof(self) weakSelf = self;
    [[MinecraftNewsService sharedService] fetchLatestNewsWithCompletion:^(NSArray<MinecraftNewsItem *> *items, NSInteger totalCount, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isLoadingNews = NO;
        if (items.count > 0) {
            strongSelf.latestNewsItem = items.firstObject;
        }
        // 刷新 News tile 显示最新标题/摘要/封面
        [strongSelf reloadNewsSection];
    }];
}

/// 重新加载 News tile 所在 section
- (void)reloadNewsSection {
    for (NSInteger s = 0; s < self.displaySections.count; s++) {
        for (HomeTileConfig *tile in self.displaySections[s]) {
            if (tile.tileType == HomeTileTypeNews) {
                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:s]];
                return;
            }
        }
    }
}

- (void)checkMinecraftVersions {
    self.isLoadingVersions = YES;
    self.latestRelease = @"检测中...";
    self.latestSnapshot = @"检测中...";
    [self reloadVersionSections];
    
    NSString *downloadSource = getPrefObject(@"general.download_source");
    NSString *url;
    if ([downloadSource isEqualToString:@"bmclapi"]) {
        url = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";
    } else {
        url = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
    }
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isLoadingVersions = NO;
            if (data && !error) {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (json) {
                    NSDictionary *latest = json[@"latest"];
                    self.latestRelease = latest[@"release"] ?: @"未知";
                    self.latestSnapshot = latest[@"snapshot"] ?: @"未知";
                } else {
                    self.latestRelease = @"检测失败";
                    self.latestSnapshot = @"检测失败";
                }
            } else {
                self.latestRelease = @"网络错误";
                self.latestSnapshot = @"网络错误";
            }
            [self reloadVersionSections];
        });
    }];
    [task resume];
}

- (void)reloadVersionSections {
    for (NSInteger s = 0; s < self.displaySections.count; s++) {
        for (HomeTileConfig *tile in self.displaySections[s]) {
            if (tile.tileType == HomeTileTypeVersionRelease || tile.tileType == HomeTileTypeVersionSnapshot) {
                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:s]];
                return;
            }
        }
    }
}

// MARK: - Update Check

- (void)checkForUpdate {
    NSString *currentVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    if ([currentVersion rangeOfString:@"Preview" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        self.announcementText = @"欢迎使用 Amethyst iOS Remastered 测试版！";
        self.hasUpdate = NO;
        [self reloadAnnouncementSection];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:@"https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ((NSHTTPURLResponse *)response).statusCode != 200 || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.announcementText = @"欢迎使用 Amethyst iOS Remastered！";
                self.hasUpdate = NO;
                [self reloadAnnouncementSection];
            });
            return;
        }
        
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *latestVer = [self extractVersionFromHTML:html];
        
        if (!latestVer) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.announcementText = @"欢迎使用 Amethyst iOS Remastered！";
                self.hasUpdate = NO;
                [self reloadAnnouncementSection];
            });
            return;
        }
        
        if ([latestVer hasPrefix:@"v"]) {
            latestVer = [latestVer substringFromIndex:1];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSComparisonResult cmp = [self compareVersion:currentVersion withVersion:latestVer];
            if (cmp == NSOrderedAscending) {
                self.announcementText = [NSString stringWithFormat:@"发现新版本：v%@", latestVer];
                self.latestVersion = latestVer;
                self.hasUpdate = YES;
            } else {
                self.announcementText = @"欢迎使用 Amethyst iOS Remastered！当前已是最新版本。";
                self.hasUpdate = NO;
            }
            [self reloadAnnouncementSection];
        });
    }];
    [task resume];
}

- (void)reloadAnnouncementSection {
    for (NSInteger s = 0; s < self.displaySections.count; s++) {
        for (HomeTileConfig *tile in self.displaySections[s]) {
            if (tile.tileType == HomeTileTypeAnnouncement) {
                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:s]];
                return;
            }
        }
    }
}

// MARK: - Announcements (官网 JSON 公告)

/// 为首页公告磁贴拉取最新公告（取首条），失败时回退到更新检测文案
- (void)loadAnnouncementsForTile {
    __weak typeof(self) weakSelf = self;
    [[AnnouncementService sharedService] fetchAnnouncementsWithCompletion:^(NSArray<AnnouncementItem *> *items, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (items.count > 0) {
            strongSelf.latestAnnouncement = items.firstObject;
        }
        [strongSelf reloadAnnouncementSection];
    }];
}

/// 打开公告磁贴上 actionURL 指向的链接（SFSafariViewController 内嵌打开）
- (void)openAnnouncementActionURL {
    if (self.latestAnnouncement.actionURL.length > 0) {
        NSURL *url = [NSURL URLWithString:self.latestAnnouncement.actionURL];
        if (url) {
            SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
            safari.modalPresentationStyle = UIModalPresentationPageSheet;
            [self presentViewController:safari animated:YES completion:nil];
        }
    }
}

- (NSString *)extractVersionFromHTML:(NSString *)html {
    NSRange titleRange = [html rangeOfString:@"<title>"];
    if (titleRange.location == NSNotFound) return nil;
    
    NSString *afterTitle = [html substringFromIndex:NSMaxRange(titleRange)];
    NSRange endTitleRange = [afterTitle rangeOfString:@"</title>"];
    if (endTitleRange.location == NSNotFound) return nil;
    
    NSString *titleContent = [afterTitle substringToIndex:endTitleRange.location];
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"v([0-9]+\\.[0-9]+\\.[0-9]+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:titleContent options:0 range:NSMakeRange(0, titleContent.length)];
    
    if (match) {
        return [titleContent substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

- (NSComparisonResult)compareVersion:(NSString *)v1 withVersion:(NSString *)v2 {
    NSArray *c1 = [v1 componentsSeparatedByString:@"."];
    NSArray *c2 = [v2 componentsSeparatedByString:@"."];
    NSInteger max = MAX(c1.count, c2.count);
    
    for (NSInteger i = 0; i < max; i++) {
        NSInteger n1 = (i < c1.count) ? [c1[i] integerValue] : 0;
        NSInteger n2 = (i < c2.count) ? [c2[i] integerValue] : 0;
        if (n1 < n2) return NSOrderedAscending;
        if (n1 > n2) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (void)downloadLatestVersion {
    NSString *urlString = @"https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/releases/latest";
    NSURL *url = [NSURL URLWithString:urlString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

// MARK: - Cell Fade-In Animation

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    cell.alpha = 0;
    cell.transform = CGAffineTransformMakeTranslation(0, 12);
    [UIView animateWithDuration:0.35 delay:indexPath.section * 0.04 usingSpringWithDamping:0.85 initialSpringVelocity:0.3 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        cell.alpha = 1;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

// MARK: - Orientation

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 并手动清空 collectionView 背景色（UICollectionView 无 backgroundView 属性），
/// 确保全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.collectionView.backgroundColor = [UIColor clearColor];
}

@end