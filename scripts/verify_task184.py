#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task184.py -- Task 184 交付校验
用户裁决："先撤销180task的UI效果调整，先修好这两样"

交付一（撤销）：Task180 双滑条透明度体系整体退役——引擎 opacity 变体删除、
  BackgroundManager 回归 uiOpacity/cardsNeumorphOpacity 单键时代、设置页
  回归 透明度+新拟态透明度 双行（Task178 形态）、20+ 接线点回归恒定底色。
交付二（白框根修 + 重写）：安装方式页（加载器选择/附加开关/版本选择子页）
  三个 cell 类与 VersionCardCell（版本号选择界面）完全同构——内层
  cardContainer 承载视觉 + 凸起管线 init 挂一次 + 系统 inset-grouped 白底
  /选中高亮清除（"钉死的底层白框"根修）。
保留：180 的账号复制双保险 / 头像防御（双挂点）/ 账号列表凸起重写 /
  card 布局与深色默认值。
"""
import io, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
N = os.path.join(ROOT, 'Natives')
PASS, FAIL = [], []

def check(group, name, cond, detail=''):
    (PASS if cond else FAIL).append(f'[{group}] {name}' + (f' -- {detail}' if detail and not cond else ''))

def rd(p):
    return io.open(os.path.join(N, p), encoding='utf-8').read()

# ============ A. 安装方式页重写（VersionCardCell 同构 + 白框根修） ============
ml = rd('installer/ModLoaderInstallViewController.m')
check('A', '三 cell 均挂凸起管线于内层 cardContainer（init 单次范式）',
      ml.count('[[BackgroundManager sharedManager] applyNeumorphCardEffectToView:_cardContainer];') == 3)
check('A', 'contentView 直挂/逐帧重铺范式退役',
      'applyNeumorphCardEffectToView:cell.contentView];' not in ml and 'applyEffectToCell:cell];' not in ml)
check('A', '系统白底清除辅助存在（backgroundView 换装透明空视图）',
      'static void AME184ClearTableViewCellChrome' in ml and 'cell.backgroundView = clearBg;' in ml)
check('A', '系统选中高亮清除', 'cell.selectedBackgroundView = clearSel;' in ml)
check('A', 'cell/contentView/layer 三重透明', ml.count('cell.backgroundColor = [UIColor clearColor];') >= 1
      and 'cell.contentView.backgroundColor = [UIColor clearColor];' in ml
      and 'cell.layer.masksToBounds = NO;' in ml)
check('A', '镀层清理在 init 与 prepareForReuse 双点重放（防复用重装白底）',
      ml.count('AME184ClearTableViewCellChrome(self);') >= 6)
check('A', '内层容器圆角 12 continuous ×3（版本卡同款）',
      ml.count('_cardContainer.layer.cornerRadius = 12;') == 3
      and ml.count('_cardContainer.layer.cornerCurve = kCACornerCurveContinuous;') == 3)
check('A', '容器上下内缩 4pt（版本卡 sectionInset 语义）',
      ml.count('self.contentView.topAnchor constant:4]') >= 3
      and ml.count('self.contentView.bottomAnchor constant:-4]') >= 3)
check('A', '图标容器 40x40 圆角 10 masksToBounds（版本卡规格）',
      'widthAnchor constraintEqualToConstant:40],' in ml
      and 'heightAnchor constraintEqualToConstant:40],' in ml
      and '_iconContainer.layer.cornerRadius = 10;' in ml
      and '_iconContainer.layer.masksToBounds = YES;' in ml)
check('A', '品牌色淡底容器（createIconBadge 同源 0.15）',
      'colorWithAlphaComponent:0.15];' in ml and 'brandColorForLoader' in ml)
check('A', '名称 16 semibold / 状态 12（版本卡文字规格）',
      'systemFontOfSize:16 weight:UIFontWeightSemibold' in ml
      and '_stateLabel.font = [UIFont systemFontOfSize:12];' in ml)
check('A', '规格文字色（引擎符号）', ml.count('AmeNeumorphPrimaryTextColor()') >= 3
      and ml.count('AmeNeumorphSecondaryTextColor()') >= 3)
check('A', 'chevron 14x14 tertiary（版本卡规格）',
      '_chevronView.widthAnchor constraintEqualToConstant:14]' in ml
      and 'chevron.right' in ml)
check('A', '版本子页 cell 同配方（cardContainer + 管线 + 圆角 12）',
      '_versionLabel.textColor = AmeNeumorphPrimaryTextColor();' in ml)
check('A', '版本子页表无分隔线（画在透明 cell 上会横切卡面）',
      'separatorStyle = UITableViewCellSeparatorStyleNone;' in ml)
check('A', '主表行高 64 / 子页行高 50（卡 56/42）',
      '_tableView.rowHeight = 64;' in ml and '_tableView.rowHeight = 50;' in ml)
check('A', '开关行 cell 同配方（标题 16 + 描述 12 + switch 右 -14）',
      ml.count('@interface ModLoaderSwitchCell : UITableViewCell') == 1
      and '_switchControl.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor constant:-14]' in ml)
check('A', '引擎头 import（规格文字色符号可见）', '#import "../UIKit+NativeSurface.h"' in ml)
check('A', '互斥/兼容逻辑保留（configureWithRow 入参不变）',
      'incompatibleReasonForLoaderId' in ml and 'configureWithRow:' in ml)

# ============ B. 透明度体系撤销（回退态关键点） ============
h = rd('UIKit+NativeSurface.h'); m = rd('UIKit+NativeSurface.m')
bm = rd('BackgroundManager.m'); bh = rd('BackgroundManager.h')
check('B', '引擎 opacity 变体退役', 'opacity:(CGFloat)opacity;' not in h)
check('B', 'BackgroundManager 新属性退役', 'CGFloat backgroundOpacity;' not in bh and 'CGFloat buttonOpacity;' not in bh)
check('B', 'BackgroundManager 旧属性回归', '@property (nonatomic, assign) CGFloat uiOpacity;' in bh
      and '@property (nonatomic, assign) CGFloat cardsNeumorphOpacity;' in bh)
check('B', '旧键回归 / 新键退役',
      'background_ui_opacity' in bm and 'background_cards_neumorph_opacity' in bm
      and 'background_bg_opacity' not in bm and 'background_btn_opacity' not in bm)
check('B', '新拟态挂点喂 cardsNeumorphOpacity',
      '[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];' in bm)
st = rd('BackgroundSettingsViewController.m')
check('B', '设置页回归 500 系滑条 tags', 'slider.tag = 500;' in st and 'slider.tag = 600;' not in st)
check('B', '设置页无 ButtonOpacityCell', '@"ButtonOpacityCell"' not in st)
# 全仓残留扫描（vendor 变更日志除外）
residual = []
for dirpath, _, files in os.walk(N):
    if 'MobileGlues' in dirpath:
        continue
    for fn in files:
        if fn.endswith(('.m', '.h')):
            p = os.path.join(dirpath, fn)
            s = io.open(p, encoding='utf-8').read()
            if ('buttonOpacity' in s or 'backgroundOpacity' in s
                    or 'background_bg_opacity' in s or 'background_btn_opacity' in s):
                residual.append(os.path.relpath(p, N))
check('B', '全仓无透明度体系残留（vendor 除外）', not residual, str(residual))

# ============ C. 头像防御双挂点保留（180 功能修复） ============
rp = rd('LauncherRightPanelViewController.m')
nw = rd('LauncherNewsViewController.m')
am = rd('AvatarManager.m')
check('C', 'RightPanel 挂点（username 回退）', 'usernameFallback:currentAuth.authData[@"username"]' in rp)
check('C', '主页/新闻挂点（username 回退）', 'usernameFallback:auth.authData[@"username"]' in nw)
check('C', 'AvatarManager 双参查询原语', 'usernameFallback:(NSString *)username {' in am)
check('C', 'RightPanel 按钮透明度接线已撤（底色恒定）',
      'self.downloadCenterButton.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];' in rp
      and 'buttonOpacity' not in rp)

# ============ D. 保留项（180 重写 + 默认值） ============
ac = rd('AccountListViewController.m')
check('D', '账号列表凸起重写保留（管线 + 钉 16 + 裁剪放行）',
      'applyNeumorphCardEffectToView:cardView];' in ac
      and '[cardView ame_setNeumorphPinnedCornerRadius:16];' in ac
      and 'cell.contentView.layer.masksToBounds = NO;' in ac)
ba = rd('authenticator/BaseAuthenticator.m')
check('D', '账号复制双保险保留（写盘收口 + 读侧去重）',
      'ame180_savedAccountId' in ba and 'ame180_seenIds' in ac)
sc = rd('SceneDelegate.m')
check('D', 'card 布局默认 / dark 主题迁移保留（180 定稿）',
      'if ([layout isEqualToString:@"vs"]) {' in sc
      and "setPrefObject(@\"general.ui_theme\", @\"dark\");" in sc)

# ============ E. CI 防回归（引擎符号 import 纪律，Task180 G 组教训常驻） ============
def uses_engine_symbols(s):
    return any(sym in s for sym in (
        'AmeNeumorphPrimaryTextColor', 'AmeNeumorphSecondaryTextColor',
        'ame_setNeumorphPinnedCornerRadius', 'AmeNeumorphShadowView',
        'ame_applyNeumorphSurface', 'ame_applyCardSurfaceWithRadius',
        'ame_applyPanelSurfaceWithRadius', 'ame_applyNeumorphCardOpacity'))
for fn in ['installer/ModLoaderInstallViewController.m', 'AccountListViewController.m',
           'LauncherRightPanelViewController.m', 'LauncherMenuViewController.m',
           'LauncherNewsViewController.m', 'VersionCardCell.m']:
    s = rd(fn)
    if uses_engine_symbols(s):
        check('E', f'{fn} 引擎头 import', ('UIKit+NativeSurface.h' in s), 'uses engine symbols without header')

# ============ 汇总 ============
print(f'PASS {len(PASS)}  FAIL {len(FAIL)}')
for f in FAIL:
    print('  FAIL:', f)
sys.exit(1 if FAIL else 0)
