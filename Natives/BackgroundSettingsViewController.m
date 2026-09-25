#import "utils.h"
//
//  BackgroundSettingsViewController.m
//  Amethyst
//
//  Background wallpaper settings implementation
//

#import "BackgroundSettingsViewController.h"
#import "BackgroundManager.h"
#import "ImageCropperViewController.h"
// Task151：Bing 每日壁纸（开关/画廊/刷新）
#import "BingWallpaperManager.h"
#import "BingWallpaperGalleryViewController.h"

@interface BackgroundSettingsViewController ()
@property (nonatomic, strong) NSArray<NSArray *> *sections;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UISlider *opacitySlider;
@property (nonatomic, weak) UILabel *opacityValueLabel;
@end

@implementation BackgroundSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = localize(@"i18n_str_53", nil);
    
    // Set transparent background if global background is active
    if ([[BackgroundManager sharedManager] hasBackground]) {
        self.view.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundColor = [UIColor clearColor];
        self.tableView.backgroundView = nil;
    } else {
        // Task137：无自定义背景时回归原生页面底色（systemBackgroundColor，
        // 深浅色自适应；cell 走 applyEffectToCell 的透明默认分支，标准
        // 列表外观）。tableView 必须显式同色（默认即是，显式声明防漂移）。
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    }
    
    // Setup table view
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.tableFooterView = [[UIView alloc] init];
    
    // Setup preview header
    [self setupPreviewHeader];
    
    // Setup sections
    [self setupSections];
    
    // Add close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(closeTapped)];

    // 适配自定义启动器背景：将当前视图控制器透明化，让全局背景（图片/视频）能够透出显示。
    // 即使本页是背景设置页本身，也需要透明化以实时预览背景效果。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    // 监听背景 UI 效果变化通知：当用户在背景设置中切换毛玻璃/半透明或调整透明度时，
    // 重新调用 makeViewControllerTransparent 以应用最新的视觉效果，保证背景始终正确透出。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];

    // Task151：Bing 壁纸元数据刷新完成 → 刷新开关行状态文字（"今日：xxx"）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBingUpdate)
                                                 name:BingWallpaperDidUpdateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePreview];
    [self.tableView reloadData];
    
    // Maintain transparency
    // Task161：改走 makeViewControllerTransparent 单点——本页是
    // UITableViewController（view == tableView），模态毛玻璃底现在挂
    // tableView.backgroundView；旧代码此处 backgroundView = nil 会把
    // glass 每次出现都清掉（整页回透壁纸）。
    if ([[BackgroundManager sharedManager] hasBackground]) {
        [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    } else {
        // Task111：与 viewDidLoad 同步的无背景底色（主题切换后保持一致）
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    }
}

- (void)setupPreviewHeader {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 200)];
    
    // Transparent header if background is active
    if ([[BackgroundManager sharedManager] hasBackground]) {
        headerView.backgroundColor = [UIColor clearColor];
    } else {
        headerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }
    
    // Preview image view
    self.previewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, headerView.bounds.size.width - 32, 168)];
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.previewImageView.clipsToBounds = YES;
    self.previewImageView.layer.cornerRadius = 12;
    self.previewImageView.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    self.previewImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // Add placeholder label
    UILabel *placeholderLabel = [[UILabel alloc] init];
    placeholderLabel.text = localize(@"i18n_str_54", nil);
    placeholderLabel.textColor = [UIColor secondaryLabelColor];
    placeholderLabel.font = [UIFont systemFontOfSize:16];
    placeholderLabel.textAlignment = NSTextAlignmentCenter;
    placeholderLabel.tag = 100;
    placeholderLabel.frame = self.previewImageView.bounds;
    placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.previewImageView addSubview:placeholderLabel];
    
    [headerView addSubview:self.previewImageView];
    
    self.tableView.tableHeaderView = headerView;
}

- (void)updatePreview {
    BackgroundManager *manager = [BackgroundManager sharedManager];
    UIImage *preview = [manager backgroundPreview];
    
    if (preview) {
        self.previewImageView.image = preview;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = YES;
    } else if ([manager hasVideoBackground]) {
        self.previewImageView.image = nil;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = NO;
        placeholder.text = localize(@"i18n_str_55", nil);
    } else {
        self.previewImageView.image = nil;
        UILabel *placeholder = (UILabel *)[self.previewImageView viewWithTag:100];
        placeholder.hidden = NO;
        placeholder.text = localize(@"i18n_str_56", nil);
    }
}

- (void)setupSections {
    // Task151：新增 section 2 = Bing 每日壁纸（开关/画廊/刷新），原图片/视频与
    // 恢复/清除顺延为 3/4。
    // Sections: [UI效果设置], [选择背景类型], [Bing 壁纸(开关+画廊+刷新)], [图片背景, 视频背景], [恢复默认背景, 清除背景]
    self.sections = @[
        @[localize(@"i18n_str_57", nil), localize(@"i18n_str_1296", nil), localize(@"i18n_str_1297", nil), localize(@"background.cards.neumorph.title", nil)],
        @[localize(@"i18n_str_60", nil)],
        @[localize(@"bing.section.header", nil), localize(@"bing.toggle.title", nil), localize(@"bing.gallery.title", nil), localize(@"bing.refresh.title", nil)],
        @[localize(@"i18n_str_61", nil), localize(@"i18n_str_55", nil)],
        @[localize(@"i18n_str_62", nil), localize(@"i18n_str_63", nil)]
    ];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // 如果没有自定义背景，隐藏UI效果设置部分
    if (section == 0 && ![[BackgroundManager sharedManager] hasBackground]) {
        return 0;
    }
    return [self.sections[section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && ![[BackgroundManager sharedManager] hasBackground]) {
        return nil;
    }
    return self.sections[section][0];
}

// Task151：Bing 部分页脚说明（默认开启语义：用户自定义优先，清除背景后自动回到 Bing 每日图）
// Task156：section 0 页脚——两个滑块的语义说明（用户反馈“两个百分比不知道
// 干什么的”：上=透明度（材质不透明程度，越低越透），下=模糊程度（背景高斯
// 模糊强度，越低越清晰）。
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return localize(@"bing.footer.hint", nil);
    }
    if (section == 0) {
        return localize(@"background.effect.footer", nil);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"BackgroundCell";
    static NSString *sliderCellIdentifier = @"SliderCell";
    static NSString *blurSliderCellIdentifier = @"BlurSliderCell";
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    BOOL hasBackground = [manager hasBackground];
    
    // UI效果设置部分
    if (indexPath.section == 0 && hasBackground) {
        if (indexPath.row == 0) {
            // UI效果选择
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
            }
            
            cell.textLabel.text = localize(@"i18n_str_57", nil);
            
            NSString *effectName = manager.uiEffect == BackgroundUIEffectBlur ? localize(@"i18n_str_2017", nil) : localize(@"i18n_str_65", nil);
            cell.detailTextLabel.text = effectName;
            cell.imageView.image = [UIImage systemImageNamed:@"rectangle.split.3x3"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
            
        } else if (indexPath.row == 1) {
            // 透明度滑块
            // Task156：行内标题（用户反馈“毛玻璃下两个百分比无名”）——
            // sections[0][1]（i18n_str_1296“透明度”）此前从未被显示（原代码
            // textLabel.text = nil，只有滑块+百分比）。标题 UILabel 固定在
            // 图标之后，滑块右移让位。
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sliderCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sliderCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                // 标题标签（Task156：位于图标右侧，固定宽度，垂直居中）
                UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 95, 30)];
                titleLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
                titleLabel.font = [UIFont systemFontOfSize:15];
                titleLabel.textColor = [UIColor labelColor];
                titleLabel.tag = 202;
                [cell.contentView addSubview:titleLabel];
                
                // 创建滑块（Task156：起点右移到标题之后）
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(150, 0, cell.bounds.size.width - 230, 30)];
                slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                slider.minimumValue = 0.1f;
                slider.maximumValue = 1.0f;
                slider.tag = 200;
                [slider addTarget:self action:@selector(opacitySliderChanged:) forControlEvents:UIControlEventValueChanged];
                
                // 创建数值标签
                UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 80, 0, 60, 30)];
                valueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                valueLabel.textAlignment = NSTextAlignmentRight;
                valueLabel.tag = 201;
                valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
                
                [cell.contentView addSubview:slider];
                [cell.contentView addSubview:valueLabel];
                
                cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
            }
            
            [self styleCell:cell hasBackground:hasBackground];
            
            UILabel *titleLabel = (UILabel *)[cell.contentView viewWithTag:202];
            titleLabel.text = self.sections[0][1];
            
            UISlider *slider = [cell.contentView viewWithTag:200];
            slider.value = manager.uiOpacity;
            
            UILabel *valueLabel = [cell.contentView viewWithTag:201];
            valueLabel.text = [NSString stringWithFormat:@"%.0f%%", manager.uiOpacity * 100];
            valueLabel.textColor = hasBackground ? [UIColor labelColor] : [UIColor labelColor]; // Task91
            self.opacityValueLabel = valueLabel;
            
            cell.textLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"circle.lefthalf.filled"];
            
            return cell;
            
        } else if (indexPath.row == 2) {
            // 模糊程度滑块
            // Task156：行内标题（同透明度行，sections[0][2]“模糊程度”首次显示）。
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:blurSliderCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:blurSliderCellIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                // 标题标签（Task156）
                UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 95, 30)];
                titleLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
                titleLabel.font = [UIFont systemFontOfSize:15];
                titleLabel.textColor = [UIColor labelColor];
                titleLabel.tag = 302;
                [cell.contentView addSubview:titleLabel];
                
                // 创建滑块（Task156：起点右移到标题之后）
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(150, 0, cell.bounds.size.width - 230, 30)];
                slider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                slider.minimumValue = 0.0f;
                slider.maximumValue = 1.0f;
                slider.tag = 300;
                [slider addTarget:self action:@selector(blurIntensitySliderChanged:) forControlEvents:UIControlEventValueChanged];
                
                // 创建数值标签
                UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 80, 0, 60, 30)];
                valueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                valueLabel.textAlignment = NSTextAlignmentRight;
                valueLabel.tag = 301;
                valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
                
                [cell.contentView addSubview:slider];
                [cell.contentView addSubview:valueLabel];
                
                cell.contentView.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
            }
            
            [self styleCell:cell hasBackground:hasBackground];
            
            UILabel *titleLabel = (UILabel *)[cell.contentView viewWithTag:302];
            titleLabel.text = self.sections[0][2];
            
            UISlider *slider = [cell.contentView viewWithTag:300];
            slider.value = manager.blurIntensity;
            
            UILabel *valueLabel = [cell.contentView viewWithTag:301];
            valueLabel.text = [NSString stringWithFormat:@"%.0f%%", manager.blurIntensity * 100];
            valueLabel.textColor = hasBackground ? [UIColor labelColor] : [UIColor labelColor]; // Task91
            
            cell.textLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"drop.halffull"];
            
            return cell;
            
        } else if (indexPath.row == 3) {
            // Task168：卡片新拟态形态开关（实底 = 放弃壁纸透明度/模糊，
            // 一律规格表面色+双阴影；关 = 动态随透明度/模糊设置 + 双阴影叠加）
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CardsNeumorphSolidCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"CardsNeumorphSolidCell"];
                UISwitch *solidSwitch = [[UISwitch alloc] init];
                [solidSwitch addTarget:self action:@selector(cardsNeumorphSolidToggleChanged:) forControlEvents:UIControlEventValueChanged];
                solidSwitch.tag = 410;
                cell.accessoryView = solidSwitch;
            }
            UISwitch *solidSwitch = (UISwitch *)cell.accessoryView;
            solidSwitch.on = manager.cardsNeumorphSolid;

            cell.textLabel.text = self.sections[0][3]; // background.cards.neumorph.title
            cell.detailTextLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"square.on.square"];
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
        }
    }
    
    // Task151：Bing 每日壁纸部分（section 2）——开关行（Value1+UISwitch）+ 画廊/刷新行
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BingToggleCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"BingToggleCell"];
                UISwitch *bingSwitch = [[UISwitch alloc] init];
                [bingSwitch addTarget:self action:@selector(bingToggleChanged:) forControlEvents:UIControlEventValueChanged];
                bingSwitch.tag = 400;
                cell.accessoryView = bingSwitch;
            }
            UISwitch *bingSwitch = (UISwitch *)cell.accessoryView;
            bingSwitch.on = [BingWallpaperManager sharedManager].isEnabled;

            cell.textLabel.text = self.sections[2][1]; // bing.toggle.title
            cell.detailTextLabel.text = [self bingStatusText];
            cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
            cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle.angled"];
            [self styleCell:cell hasBackground:hasBackground];
            return cell;
        }

        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        }
        cell.textLabel.text = self.sections[2][indexPath.row];
        cell.detailTextLabel.text = nil;
        [self styleCell:cell hasBackground:hasBackground];
        if (indexPath.row == 1) {
            cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }

    // 其他部分
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }

    NSString *title = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = nil;

    [self styleCell:cell hasBackground:hasBackground];

    if (indexPath.section == 1) {
        // 选择背景类型标题
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"photo"];
            cell.accessoryType = [manager hasImageBackground] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else if (indexPath.row == 1) {
            cell.imageView.image = [UIImage systemImageNamed:@"film"];
            cell.accessoryType = [manager hasVideoBackground] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            // 恢复默认背景
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else if (indexPath.row == 1) {
            // 清除背景
            cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }

    return cell;
}

- (void)styleCell:(UITableViewCell *)cell hasBackground:(BOOL)hasBackground {
    // Task111：统一走 applyEffectToCell 的检测切换——有背景=毛玻璃/半透明
    // （背景图从 cell 下方透出），无背景=原生透明默认 cell（Task137：
    // 新拟态退役，标准列表外观）。
    [[BackgroundManager sharedManager] applyEffectToCell:cell];
    if (hasBackground) {
        cell.textLabel.textColor = [UIColor labelColor]; // Task91：写死白色改主题主文字色
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
    }
}

#pragma mark - Slider Actions

- (void)opacitySliderChanged:(UISlider *)slider {
    CGFloat value = slider.value;
    [BackgroundManager sharedManager].uiOpacity = value;
    
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    
    // 实时刷新UI效果
    [[BackgroundManager sharedManager] refreshUIEffect];
}

- (void)blurIntensitySliderChanged:(UISlider *)slider {
    CGFloat value = slider.value;
    [BackgroundManager sharedManager].blurIntensity = value;
    
    // 更新标签显示
    UITableViewCell *cell = (UITableViewCell *)slider.superview.superview;
    if ([cell isKindOfClass:[UITableViewCell class]]) {
        UILabel *valueLabel = [cell.contentView viewWithTag:301];
        valueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100];
    }
    
    // 实时刷新UI效果
    [[BackgroundManager sharedManager] refreshUIEffect];
}

// Task168：卡片新拟态形态开关（实底/动态）——落盘后走统一刷新链重建卡片
- (void)cardsNeumorphSolidToggleChanged:(UISwitch *)sender {
    [BackgroundManager sharedManager].cardsNeumorphSolid = sender.on;
    [[BackgroundManager sharedManager] refreshUIEffect];
}

#pragma mark - Task151：Bing 每日壁纸

// 开关切换：开 → 立即触发自动刷新+应用；关 → 若当前背景来自 Bing 则清除
// （用户自定义壁纸来源为 user，不受开关影响）
- (void)bingToggleChanged:(UISwitch *)sender {
    BingWallpaperManager *bing = [BingWallpaperManager sharedManager];
    bing.enabled = sender.on;

    if (sender.on) {
        [bing autoRefreshAndApplyIfEnabled];
    } else if ([[BackgroundManager sharedManager] isBingSource]) {
        [[BackgroundManager sharedManager] clearBackground];
        [self updatePreview];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
    }
    [self.tableView reloadData];
}

// 开关行副标题：今日壁纸标题（已同步）或"尚未同步"
- (NSString *)bingStatusText {
    BingWallpaperManager *bing = [BingWallpaperManager sharedManager];
    BingWallpaperItem *today = bing.items.firstObject;
    if (today) {
        NSString *name = today.title.length > 0 ? today.title : today.copyright;
        return [NSString stringWithFormat:localize(@"bing.status.today", nil), name];
    }
    return localize(@"bing.status.unsynced", nil);
}

// "立即刷新"行：手动拉元数据 + 补下载今日图（已开 Bing 时顺带自动应用）
- (void)refreshBingManually {
    __weak typeof(self) weakSelf = self;
    [[BingWallpaperManager sharedManager] refreshWithCompletion:^(BOOL success, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (success) {
            [[BingWallpaperManager sharedManager] autoRefreshAndApplyIfEnabled];
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:success ? localize(@"bing.refresh.done", nil)
                                                                                       : localize(@"bing.refresh.failed", nil)
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
    }];
}

// Bing 元数据更新通知：仅重载表格（状态行文字更新）
- (void)handleBingUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    BOOL hasBackground = [manager hasBackground];
    
    // UI效果设置部分
    if (indexPath.section == 0 && hasBackground) {
        if (indexPath.row == 0) {
            [self showUIEffectPicker];
        }
        return;
    }
    
    if (indexPath.section == 2) {
        // Task151：Bing 部分——画廊跳转 / 立即刷新（开关行点击不做事，操作 UISwitch）
        if (indexPath.row == 1) {
            UICollectionViewController *gallery = [BingWallpaperGalleryViewController galleryController];
            [self.navigationController pushViewController:gallery animated:YES];
        } else if (indexPath.row == 2) {
            [self refreshBingManually];
        }
        return;
    }

    if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            [self selectImageBackground];
        } else if (indexPath.row == 1) {
            [self selectVideoBackground];
        }
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            [self restoreDefaultBackground];
        } else if (indexPath.row == 1) {
            [self clearBackground];
        }
    }
}

- (void)showUIEffectPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_66", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    BackgroundManager *manager = [BackgroundManager sharedManager];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_67", nil)
                                              style:manager.uiEffect == BackgroundUIEffectBlur ? UIAlertActionStyleDefault : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        manager.uiEffect = BackgroundUIEffectBlur;
        [manager refreshUIEffect];
        [self.tableView reloadData];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_68", nil)
                                              style:manager.uiEffect == BackgroundUIEffectTranslucent ? UIAlertActionStyleDefault : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        manager.uiEffect = BackgroundUIEffectTranslucent;
        [manager refreshUIEffect];
        [self.tableView reloadData];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundUIEffectChanged" object:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        alert.popoverPresentationController.sourceView = cell ?: self.view;
        alert.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Background Selection

- (void)selectImageBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_70", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_71", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openPhotoLibraryForImage];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_72", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openDocumentPickerForImage];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectVideoBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_73", nil)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_71", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openPhotoLibraryForVideo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_72", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self openDocumentPickerForVideo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreDefaultBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_62", nil)
                                                                   message:localize(@"i18n_str_74", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_75", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        // 清除背景
        [[BackgroundManager sharedManager] clearBackground];
        
        // 重置UI效果设置
        BackgroundManager *manager = [BackgroundManager sharedManager];
        manager.uiEffect = BackgroundUIEffectBlur;
        manager.uiOpacity = 0.7;
        
        [self updatePreview];
        [self.tableView reloadData];
        
        // 恢复默认背景色
        self.view.backgroundColor = [UIColor systemBackgroundColor]; // Task136：主题化页面底色
        self.tableView.backgroundColor = [UIColor systemBackgroundColor]; // Task136：主题化页面底色
        self.tableView.backgroundView = nil;

        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];

        // Task151：Bing 开启时，清除后立即回补每日壁纸（默认开启语义：
        // 无自定义壁纸即 Bing 每日图；彻底无背景请关闭 Bing 开关）
        [[BingWallpaperManager sharedManager] autoRefreshAndApplyIfEnabled];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearBackground {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_63", nil)
                                                                   message:localize(@"i18n_str_76", nil)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"resman.common.cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_77", nil)
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        [[BackgroundManager sharedManager] clearBackground];
        [self updatePreview];
        [self.tableView reloadData];
        
        // Restore default background color
        self.view.backgroundColor = [UIColor systemBackgroundColor]; // Task136：主题化页面底色
        self.tableView.backgroundColor = [UIColor systemBackgroundColor]; // Task136：主题化页面底色

        [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];

        // Task151：同恢复默认——Bing 开启时立即回补每日壁纸
        [[BingWallpaperManager sharedManager] autoRefreshAndApplyIfEnabled];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Image Picker

- (void)openPhotoLibraryForImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openPhotoLibraryForVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Document Picker

- (void)openDocumentPickerForImage {
    NSArray<UTType *> *contentTypes = @[
        UTTypeJPEG,
        UTTypePNG,
        UTTypeImage
    ];
    
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openDocumentPickerForVideo {
    NSArray<UTType *> *contentTypes = @[
        UTTypeMovie,
        UTTypeVideo,
        UTTypeMPEG4Movie
    ];
    
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        [picker dismissViewControllerAnimated:YES completion:^{
            [self processSelectedImage:image];
        }];
    } else if ([mediaType isEqualToString:@"public.movie"]) {
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [picker dismissViewControllerAnimated:YES completion:^{
            [self processSelectedVideo:videoURL];
        }];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    
    NSURL *url = urls.firstObject;
    NSString *extension = url.pathExtension.lowercaseString;
    
    // 修复上游 Issue #92：DocumentPicker 返回安全范围 URL，
    // 必须先 startAccessingSecurityScopedResource，否则 fileExistsAtPath:
    // 和 copyItemAtURL: 都会失败（报"文件不存在"）。
    BOOL accessing = [url startAccessingSecurityScopedResource];
    
    if ([@[@"jpg", @"jpeg", @"png", @"heic"] containsObject:extension]) {
        UIImage *image = [UIImage imageWithContentsOfFile:url.path];
        if (image) {
            [self processSelectedImage:image];
        }
        if (accessing) [url stopAccessingSecurityScopedResource];
    } else if ([@[@"mp4", @"mov", @"m4v"] containsObject:extension]) {
        // 视频复制是异步的（BackgroundManager 中 dispatch_async 到后台队列），
        // 需要保持安全范围访问直到复制完成。
        // 传递 needsStopAccessing 标记，由 processSelectedVideo 在 completion 中 stop。
        [self processSelectedVideo:url needsStopAccessing:accessing];
    } else {
        if (accessing) [url stopAccessingSecurityScopedResource];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Cancelled
}

#pragma mark - Process Selection

- (void)processSelectedImage:(UIImage *)image {
    if (!image) return;
    
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_78", nil)
                                                                             message:localize(@"i18n_str_79", nil)
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    [[BackgroundManager sharedManager] setImageBackground:image completion:^(BOOL success, NSError * _Nullable error) {
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                [self updatePreview];
                [self.tableView reloadData];
                
                // Apply transparency
                self.view.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundView = nil;
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
                
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_80", nil)
                                                                                      message:localize(@"i18n_str_81", nil)
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil)
                                                                                    message:error.localizedDescription ?: localize(@"i18n_str_82", nil)
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
        }];
    }];
}

- (void)processSelectedVideo:(NSURL *)videoURL {
    [self processSelectedVideo:videoURL needsStopAccessing:NO];
}

- (void)processSelectedVideo:(NSURL *)videoURL needsStopAccessing:(BOOL)needsStop {
    if (!videoURL) return;
    
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_78", nil)
                                                                             message:localize(@"i18n_str_83", nil)
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    [[BackgroundManager sharedManager] setVideoBackgroundWithURL:videoURL completion:^(BOOL success, NSError * _Nullable error) {
        // 视频复制已完成（无论成功或失败），现在可以释放安全范围访问
        if (needsStop) [videoURL stopAccessingSecurityScopedResource];
        
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                [self updatePreview];
                [self.tableView reloadData];
                
                // Apply transparency
                self.view.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundColor = [UIColor clearColor];
                self.tableView.backgroundView = nil;
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"BackgroundChanged" object:nil];
                
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_80", nil)
                                                                                      message:localize(@"i18n_str_84", nil)
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:localize(@"i18n_str_42", nil)
                                                                                    message:error.localizedDescription ?: localize(@"i18n_str_85", nil)
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:localize(@"i18n_str_44", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
        }];
    }];
}

/// 重新应用背景效果：当 BackgroundUIEffectChanged 通知到达时调用，
/// 通过 BackgroundManager 重新设置当前视图控制器的透明度/毛玻璃效果，
/// 并手动清空 tableView 背景与 backgroundView，确保全局背景能够正常透出。
- (void)reapplyBackgroundEffect {
    // Task161：makeViewControllerTransparent 末尾的 ame160 会重铺模态
    // 毛玻璃底（table 控制器挂 backgroundView）；旧代码随后一句
    // backgroundView = nil 会把它清掉，改为只补背景色清零。
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
    self.tableView.backgroundColor = [UIColor clearColor];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end