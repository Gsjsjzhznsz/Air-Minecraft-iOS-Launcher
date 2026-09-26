#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task180.py -- Task 180 交付校验
两滑条透明度体系（背景/按钮）+ 账号列表新拟态重写 + 复制bug双保险
+ 头像防御性修 + 安装方式页对齐版本卡 + 全局默认值定稿
"""
import io, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
N = os.path.join(ROOT, 'Natives')
PASS, FAIL = [], []

def check(group, name, cond, detail=''):
    (PASS if cond else FAIL).append(f'[{group}] {name}' + (f' -- {detail}' if detail and not cond else ''))

def rd(p):
    return io.open(os.path.join(N, p), encoding='utf-8').read()

# ============ A. 引擎层（UIKit+NativeSurface） ============
h = rd('UIKit+NativeSurface.h'); m = rd('UIKit+NativeSurface.m')
check('A', 'Flat opacity 原语 .h 声明', 'ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius\n                                       opacity:(CGFloat)opacity;' in h)
check('A', 'Panel opacity 原语 .h 声明', 'ame_applyPanelSurfaceWithRadius:(CGFloat)cornerRadius\n                                opacity:(CGFloat)opacity;' in h)
check('A', 'Flat opacity .m 实现', 'ame_applyNeumorphSurfaceFlatWithRadius:(CGFloat)cornerRadius\n                                       opacity:(CGFloat)opacity {' in m)
check('A', 'Flat opacity 内部 colorWithAlphaComponent', 'colorWithAlphaComponent:o' in m)
check('A', 'Flat opacity clamp [0,1]', 'MAX(0.0, MIN(1.0, opacity))' in m)
check('A', '旧 Flat 签名转发 opacity:1.0（失效安全）', '[self ame_applyNeumorphSurfaceFlatWithRadius:cornerRadius opacity:1.0];' in m)
check('A', 'Panel 签名转发', '[self ame_applyNeumorphSurfaceFlatWithRadius:cornerRadius opacity:opacity];' in m)

# ============ B. BackgroundManager（键/默认值/管线换源） ============
bm = rd('BackgroundManager.m'); bh = rd('BackgroundManager.h')
check('B', '新键 background_bg_opacity', 'kBackgroundBgOpacityKey = @"background_bg_opacity"' in bm)
check('B', '新键 background_btn_opacity', 'kBackgroundBtnOpacityKey = @"background_btn_opacity"' in bm)
check('B', '默认背景 0.75（用户备注）', '_backgroundOpacity = 0.75;' in bm)
check('B', '默认按钮 1.0（用户备注）', '_buttonOpacity = 1.0;' in bm)
check('B', '默认模糊 0.0（用户备注）', '_blurIntensity = 0.0;' in bm)
check('B', '背景透明度无下限 clamp', '_backgroundOpacity = MAX(0.0, MIN(1.0, backgroundOpacity));' in bm)
check('B', '.h 属性 backgroundOpacity', '@property (nonatomic, assign) CGFloat backgroundOpacity;' in bh)
check('B', '.h 属性 buttonOpacity', '@property (nonatomic, assign) CGFloat buttonOpacity;' in bh)
check('B', '旧 uiOpacity 属性退役', 'CGFloat uiOpacity;' not in bh)
check('B', '旧 cardsNeumorphOpacity 属性退役', 'CGFloat cardsNeumorphOpacity;' not in bh)
check('B', '旧键常量退役', 'static NSString * const kBackgroundUIOpacityKey' not in bm and 'static NSString * const kBackgroundCardsNeumorphOpacityKey' not in bm)
check('B', '挂点① 读 backgroundOpacity', '[target ame_applyNeumorphCardOpacity:self.backgroundOpacity];' in bm)
check('B', '挂点② 读 backgroundOpacity', '[view ame_applyNeumorphCardOpacity:self.backgroundOpacity];' in bm)
check('B', 'makeViewControllerTransparent 读新键（语义翻转为直读）',
      'viewController.view.backgroundColor = [base colorWithAlphaComponent:self.backgroundOpacity];' in bm)
check('B', 'applyEffectToCell 半透明档换键', 'colorWithAlphaComponent:self.backgroundOpacity];' in bm)
check('B', 'applyEffectToView 无壁纸 Flat 档接 opacity',
      'ame_applyNeumorphSurfaceFlatWithRadius:radius\n                                            opacity:self.backgroundOpacity];' in bm)
check('B', 'applyCardEffectToCell Flat 档接 opacity', '[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12\n                                                    opacity:self.backgroundOpacity];' in bm)
check('B', '导航栏/工具栏换键', bm.count('colorWithWhite:0.1 alpha:self.backgroundOpacity]') >= 4)
check('B', 'searchBar 输入框换键', 'textField.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:self.backgroundOpacity];' in bm)
check('B', 'saveUISettings 落盘双键', 'setFloat:self.backgroundOpacity forKey:kBackgroundBgOpacityKey]' in bm and 'setFloat:self.buttonOpacity forKey:kBackgroundBtnOpacityKey]' in bm)
check('B', 'loadUISettings 读双键', '[defaults objectForKey:kBackgroundBgOpacityKey]' in bm and '[defaults objectForKey:kBackgroundBtnOpacityKey]' in bm)

# ============ C. 设置页（两滑条行结构） ============
st = rd('BackgroundSettingsViewController.m')
check('C', 'sections[0] 第五项 = button.opacity.title', 'localize(@"background.button.opacity.title", nil)' in st)
check('C', 'sections[0] 无 neumorph.opacity 残留', 'background.cards.neumorph.opacity.title' not in st)
check('C', '无壁纸 section0 = 3 行', 'return 3;' in st)
check('C', '按钮透明度行 hasBackground ? 4 : 2', 'hasBackground ? 4 : 2' in st)
check('C', 'ButtonOpacityCell 标识', '@"ButtonOpacityCell"' in st)
check('C', '按钮滑条 tags 600/601/602', 'slider.tag = 600;' in st and 'viewWithTag:601]' in st and 'viewWithTag:602]' in st)
check('C', 'buttonOpacitySliderChanged 回调写 buttonOpacity', '[BackgroundManager sharedManager].buttonOpacity = slider.value;' in st)
check('C', '背景滑条回调写 backgroundOpacity', '[BackgroundManager sharedManager].backgroundOpacity = value;' in st)
check('C', '背景/模糊滑条 min 0.0', 'slider.minimumValue = 0.0f;\n                slider.maximumValue = 1.0f;' in st)
check('C', '背景滑条行值读 backgroundOpacity', 'slider.value = manager.backgroundOpacity;' in st)
check('C', '无旧 cardsNeumorphOpacitySliderChanged 残留', 'cardsNeumorphOpacitySliderChanged' not in st)
check('C', '恢复默认 0.75/1.0/0.0', 'manager.backgroundOpacity = 0.75;' in st and 'manager.buttonOpacity = 1.0;' in st and 'manager.blurIntensity = 0.0;' in st)
check('C', '新拟态开关行 tags 410 保留', 'neumorphSwitch.tag = 410;' in st)

# ============ D. l10n（×6 语言 + 计数 1955 保持） ============
RES = os.path.join(N, 'resources')
FOOTER_WORD = {'en': 'Background Opacity', 'zh-Hans': '背景透明度', 'zh-CN': '背景透明度', 'zh-Hant': '背景透明度', 'ja': '背景の不透明度', 'km': 'តម្លាភាពផ្ទៃខាងក្រោយ'}
for lang, expect_1296, expect_btn in [
    ('en', 'Background Opacity', 'Button Opacity'),
    ('zh-Hans', '背景透明度', '按钮透明度'),
    ('zh-CN', '背景透明度', '按钮透明度'),
    ('zh-Hant', '背景透明度', '按鈕透明度'),
    ('ja', '背景の不透明度', 'ボタンの不透明度'),
    ('km', 'តម្លាភាពផ្ទៃខាងក្រោយ', 'តម្លាភាពប៊ូតុង'),
]:
    s = io.open(os.path.join(RES, f'{lang}.lproj/Localizable.strings'), encoding='utf-8').read()
    keys = set(re.findall(r'^"([^"]+)" =', s, re.M))
    check('D', f'{lang} 1296 改值', f'"i18n_str_1296" = "{expect_1296}";' in s)
    check('D', f'{lang} button.opacity 键', 'background.button.opacity.title' in keys)
    check('D', f'{lang} neumorph.opacity 键退役', 'background.cards.neumorph.opacity.title' not in keys)
    check('D', f'{lang} footer 提及背景透明度', FOOTER_WORD[lang] in s)
tot = None
for lang in ['en', 'zh-Hans', 'zh-CN', 'zh-Hant']:
    s = io.open(os.path.join(RES, f'{lang}.lproj/Localizable.strings'), encoding='utf-8').read()
    keys = set(re.findall(r'^"([^"]+)" =', s, re.M))
    tot = len(keys) if tot is None else tot
    check('D', f'{lang} 唯一键总数 == 1955', len(keys) == 1955, f'got {len(keys)}')

# ============ E. 按钮透明度接线 ============
rp = rd('LauncherRightPanelViewController.m')
check('E', '启动/执行Jar/选择版本 ×buttonOpacity',
      rp.count('[accentColor() colorWithAlphaComponent:btnO]') == 3)
check('E', '下载中心按钮 ×buttonOpacity',
      'colorWithAlphaComponent:[BackgroundManager sharedManager].buttonOpacity];' in rp)
check('E', '信息卡 0.15×buttonOpacity', 'colorWithAlphaComponent:0.15 * [BackgroundManager sharedManager].buttonOpacity];' in rp)
check('E', 'RightPanel reapply 重刷按钮外观', '[self applyCustomAppearance];' in rp)
mn = rd('LauncherMenuViewController.m')
check('E', '菜单按钮选中底 ×buttonOpacity', mn.count('colorWithAlphaComponent:0.15 * [BackgroundManager sharedManager].buttonOpacity]') >= 2)
check('E', 'Menu reapply 重刷', '[self updateButtonColors];' in mn)
dl = rd('DownloadViewController.m')
check('E', 'importModpack ×buttonOpacity', '[[UIColor systemPurpleColor]\n        colorWithAlphaComponent:[BackgroundManager sharedManager].buttonOpacity];' in dl)
check('E', '侧栏筛选/重置按钮 ×buttonOpacity', dl.count('[[UIColor tertiarySystemFillColor]\n        colorWithAlphaComponent:[BackgroundManager sharedManager].buttonOpacity];') >= 2)
check('E', 'handleBackgroundUIEffectChanged 重刷按钮', 'self.importModpackButton.backgroundColor = [[UIColor systemPurpleColor] colorWithAlphaComponent:btnO];' in dl)
nt = rd('NMToast.m')
check('E', 'NMToast 小窗接按钮透明度', '[self.cardView ame_applyNeumorphCardOpacity:[BackgroundManager sharedManager].buttonOpacity];' in nt)
pc = rd('PLCrashView.m')
check('E', '崩溃窗 ame180_buttonColor 辅助', '- (UIColor *)ame180_buttonColor:(UIColor *)base {' in pc)
check('E', '重启/退出按钮走辅助', pc.count('[self ame180_buttonColor:') >= 2)

# ============ F. 大背景接线 ============
rt = rd('LauncherRootViewController.m')
check('F', 'Root 侧栏/右面板 Flat opacity', rt.count('ame_applyPanelSurfaceWithRadius:16 opacity:bgOpacity];') == 2)
bg = rd('BingWallpaperGalleryViewController.m')
check('F', '壁纸选择页接背景透明度', 'colorWithAlphaComponent:[BackgroundManager sharedManager].backgroundOpacity];' in bg)
tv = rd('DownloadTasksViewController.m')
check('F', '下载中心弹窗接背景透明度', 'colorWithAlphaComponent:[BackgroundManager sharedManager].backgroundOpacity];' in tv)
check('F', '下载页 tabSegment 接键', 'self.tabSegment.backgroundColor = [[UIColor systemBackgroundColor]\n        colorWithAlphaComponent:[BackgroundManager sharedManager].backgroundOpacity];' in dl)
check('F', '下载页搜索栏接入管线', '[[BackgroundManager sharedManager] applyEffectToSearchBar:self.searchBar];' in dl)
check('F', '胶囊轨道接键', '[[UIColor tertiarySystemFillColor]\n        colorWithAlphaComponent:[BackgroundManager sharedManager].backgroundOpacity];' in dl)
ps = rd('ProfileSettingsViewController.m')
check('F', '实例页 blurView 换键', 'blurView.alpha = MAX(0.5, [BackgroundManager sharedManager].backgroundOpacity);' in ps)

# ============ G. 账号/头像/安装页 ============
ac = rd('AccountListViewController.m')
check('G', '账号 cell 凸起管线', '[[BackgroundManager sharedManager] applyNeumorphCardEffectToView:cardView];' in ac)
check('G', '账号 cell 圆角钉 16', '[cardView ame_setNeumorphPinnedCornerRadius:16];' in ac)
check('G', '账号 cell 裁剪放行', 'cell.contentView.layer.masksToBounds = NO;' in ac)
check('G', '账号 cell 自绘阴影退场', 'shadowOpacity = 0.12' not in ac)
check('G', 'reloadAccountList 去重', 'ame180_seenIds' in ac and 'dedup account entry by id' in ac)
check('G', 'reloadAccountList 过滤坏文件', 'NSErrorObject' in ac and 'skipping unreadable account file' in ac)
ba = rd('authenticator/BaseAuthenticator.m')
check('G', 'saveChanges 漂移感知属性', 'ame180_savedAccountId' in ba)
check('G', '写盘成功后清理旧文件', 'account file migrated after accountId drift' in ba)
check('G', '写盘收口迁移头像', 'ame180_migrateAvatarFromAccount:ame180_old' in ba)
am = rd('AvatarManager.m')
check('G', 'username 回退查询', 'avatarForAccount:(NSString *)accountName\n             usernameFallback:(NSString *)username {' in am)
check('G', '头像迁移原语', 'ame180_migrateAvatarFromAccount:(NSString *)oldAccount' in am)
check('G', 'RightPanel username 回退调用', 'usernameFallback:currentAuth.authData[@"username"]' in rp)
nw = rd('LauncherNewsViewController.m')
check('G', '主页 username 回退调用', 'usernameFallback:auth.authData[@"username"]' in nw)
check('G', 'RightPanel fetch 失败日志锚', '[Task180] RightPanel avatar fetch failed' in rp)
ml = rd('installer/ModLoaderInstallViewController.m')
check('G', '安装页凸起管线 ×2', ml.count('[[BackgroundManager sharedManager] applyNeumorphCardEffectToView:cell.contentView];') == 2)
check('G', '安装页扁平调用退役', 'applyCardEffectToCell:cell];' not in ml)
check('G', '安装页 40pt 图标', '[ScreenUtils dp:40];' in ml)
check('G', '安装页 64 行高', '_tableView.rowHeight = 64;' in ml)
check('G', '安装页规格文字色', ml.count('AmeNeumorphPrimaryTextColor()') >= 3 and ml.count('AmeNeumorphSecondaryTextColor()') >= 4)
check('G', '安装页裁剪放行', 'cell.contentView.layer.masksToBounds = NO;' in ml)
check('G', '安装页引擎头 import', '#import "../UIKit+NativeSurface.h"' in ml)
sc = rd('SceneDelegate.m')
check('G', '布局默认 card（显式 vs 才三栏）', 'if ([layout isEqualToString:@"vs"]) {' in sc)
check('G', '主题迁移目标 dark（Task161 家法改靶）', "setPrefObject(@\"general.ui_theme\", @\"dark\");" in sc)
check('G', 'Layout 注释锚 [Task180]', 'Task180 用户定稿默认 = 卡片式便当盒布局' in sc)

# ============ 汇总 ============
print(f'PASS {len(PASS)}  FAIL {len(FAIL)}')
for f in FAIL:
    print('  FAIL:', f)
sys.exit(1 if FAIL else 0)
