#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# verify_task190.py -- Task 190 交付校验
# 用户定稿四件套：
#   ① 安装方式页每个按钮的间距 = 版本号页（卡间 section 头 10 -> 4，净距 12pt）
#   ② 用户界面账号选项 = 已安装版本页同构（AME190AccountCardCell：
#      圆形头像 / 标题为正文 / 灰字为账号类型 / 右侧无箭头 / 选中徽章同款）
#   ③ 长按菜单全账户化：(person.circle) 选用账号 + (红字 trash) 删除账号
#     （Task129b 第三方多角色角色项原样保留；Task130b 行内按钮退役）
#   ④ BackgroundManager 泛型管线：applyEffectToTableViewCell 与版本页
#      applyEffectToCollectionViewCell 共用 Task172 三段式同一实现
import os, re, io, json, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)
N = "Natives"

PASS, FAIL = [], []
def rdrepo(p):
    return io.open(p, encoding="utf-8", errors="replace").read()

def check(group, name, cond, detail=""):
    (PASS if cond else FAIL).append((group, name, detail))
    print(("  PASS " if cond else "  FAIL ") + f"[{group}] {name}" + ("" if cond else f"  -- {detail}"))

# ============ A. BackgroundManager 泛型管线抽取 ============
print("== A. BackgroundManager 泛型管线（Collection/Table 共用 Task172 三段式） ==")
bm = rdrepo("Natives/BackgroundManager.m")
bmh = rdrepo("Natives/BackgroundManager.h")
check("A", "泛型实现 ame190_applyCardPipelineToCell 存在",
      "- (void)ame190_applyCardPipelineToCell:(UIView *)cell contentView:(UIView *)contentView {" in bm)
check("A", "Collection 包装转发泛型实现（contentView 类型化传参）",
      "- (void)applyEffectToCollectionViewCell:(UICollectionViewCell *)cell {" in bm
      and bm.count("[self ame190_applyCardPipelineToCell:cell contentView:cell.contentView];") == 2)
check("A", "Table 包装 applyEffectToTableViewCell 转发泛型实现",
      "- (void)applyEffectToTableViewCell:(UITableViewCell *)cell {" in bm)
_gm = bm.split("- (void)ame190_applyCardPipelineToCell:", 1)[1].split("- (void)applyCardEffectToCell:", 1)[0]
check("A", "泛型方法体内零 cell.contentView（CI run 36403614574：UIView 基类无此属性）",
      "cell.contentView" not in _gm and "contentView" in _gm)
check("A", "泛型实现正文保留壁纸感知单路径（Task210 重锚：新拟态三段式退役；注释留档不计）",
      "hasBackground" in bm.split("ame190_applyCardPipelineToCell", 1)[1]
      and "ame_applyNeumorphSurface" not in "\n".join(l.split("//")[0] for l in bm.split("ame190_applyCardPipelineToCell", 1)[1].split("\n"))
      and "cardsNeumorphEnabled" not in "\n".join(l.split("//")[0] for l in bm.split("\n")))
_decl = bmh.find("- (void)applyEffectToTableViewCell:(UITableViewCell *)cell;")
check("A", "头文件声明 + 注释（与 Collection 同一条管线）",
      _decl >= 0 and "Task210" in bmh[max(0, _decl - 300):_decl])

# ============ B. 安装方式页间距 = 版本号页 ============
print("== B. 安装方式页卡间距（净距 12pt = 版本号页） ==")
ml = rdrepo("Natives/installer/ModLoaderInstallViewController.m")
dv = rdrepo("Natives/DownloadViewController.m")
check("B", "卡间 section 头 10 -> 4", "if (section < (NSInteger)_loaders.count) return 4;" in ml
      and "return 10;" not in ml.split("heightForHeaderInSection")[1].split("}")[0])
check("B", "注释写明净距 12pt 推导（4 下内缩 + 4 头 + 4 上内缩）",
      "12pt" in ml.split("Task190", 1)[1].split("*/", 1)[0] if "Task190" in ml else False)
check("B", "卡片上下内缩 4pt 语义未动（版本卡同款）",
      ml.count("self.contentView.topAnchor constant:4]") >= 3
      and ml.count("self.contentView.bottomAnchor constant:-4]") >= 3)
check("B", "行高 64 不变（卡 56 + 内缩 4+4）", "_tableView.rowHeight = 64;" in ml)
check("B", "版本号页基准仍在（minimumLineSpacing 4 + 内缩 4/4 + item 64）",
      "layout.minimumLineSpacing = 4;" in dv
      and "layout.itemSize = CGSizeMake(360, 64);" in dv
      and "layout.sectionInset = UIEdgeInsetsMake(8, 16, 8, 16);" in dv)

# ============ C. 账号卡 = 已安装版本页同构（AME190AccountCardCell） ============
print("== C. 账号卡同构（圆形头像/正文标题/灰字类型/无箭头/选中徽章） ==")
ac = rdrepo("Natives/AccountListViewController.m")
vm = rdrepo("Natives/VersionManagerViewController.m")
check("C", "AME190AccountCardCell 类存在并注册",
      "@interface AME190AccountCardCell : UITableViewCell" in ac
      and '[self.tableView registerClass:AME190AccountCardCell.class forCellReuseIdentifier:@"accountCardCell"];' in ac)
check("C", "VMTileBaseCell 阴影规格镜像（0.12/6/(0,3) + shadowPath 随帧）",
      "self.layer.shadowOpacity = 0.12;" in ac and "self.layer.shadowRadius = 6;"
      in ac and "bezierPathWithRoundedRect:shadowRect" in ac)
check("C", "contentContainer = 12pt 连续圆角 + 白 0.08 + 0.5pt 白 0.10（版本卡同款）",
      ac.count("self.contentContainer.layer.cornerRadius = 12;") >= 1
      and "self.contentContainer.layer.cornerCurve = kCACornerCurveContinuous;" in ac
      and "[[UIColor whiteColor] colorWithAlphaComponent:0.08]" in ac
      and "[[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor" in ac)
check("C", "卡面管线 = applyEffectToTableViewCell（Task172 三段式，版本页同管线）",
      "[[BackgroundManager sharedManager] applyEffectToTableViewCell:self];" in ac
      and "applyNeumorphCardEffectToView:cardView]" not in ac)
check("C", "圆形头像（dp:34 = 版本页 iconContainer 档；cornerRadius = 直径/2；AspectFill）",
      "[ScreenUtils dp:34]" in ac and "self.avatarView.layer.cornerRadius = ame190_avatarSize / 2;" in ac
      and "UIViewContentModeScaleAspectFill" in ac)
check("C", "标题 = 正文（版本页 nameLabel 规格 sp:15 semibold label 色）",
      "[UIFont systemFontOfSize:[ScreenUtils sp:15] weight:UIFontWeightSemibold]" in ac
      and "self.usernameLabel.textColor = [UIColor labelColor];" in ac)
check("C", "灰字 = 账号类型（版本页 versionLabel 规格 sp:11 secondary）",
      "[UIFont systemFontOfSize:[ScreenUtils sp:11] weight:UIFontWeightRegular]" in ac
      and "self.typeLabel.textColor = [UIColor secondaryLabelColor];" in ac
      and "ame190_accountTypeTextForAccount:" in ac)
check("C", "右侧无箭头（chevron 零出现）", "chevron" not in ac.lower())
check("C", "选中徽章 = 版本页同款（20pt accent 圆角方块 + 白勾 9pt bold，top+10/右-14）",
      "self.selectedBadge.widthAnchor constraintEqualToConstant:20]" in ac
      and "self.selectedBadge.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:10]" in ac
      and "self.selectedBadge.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-14]" in ac
      and "configurationWithPointSize:9 weight:UIFontWeightBold]" in ac)
check("C", "选中态三层强化（accent 1.5 边框 + 0.10 淡底，VMVersionCardCell 镜像）",
      "self.contentContainer.layer.borderWidth = 1.5;" in ac
      and "[accentColor() colorWithAlphaComponent:0.10]" in ac)
check("C", "几何：上下 4 内缩 + 左右 24 总边距（版本页 section 16 + item 8 语义）",
      ac.count("self.contentView.topAnchor constant:4]") >= 1
      and "constant:24]" in ac and "constant:-24]" in ac)
check("C", "触摸缩放弹簧（VMTileBaseCell 同款 0.96/0.25）",
      "CGAffineTransformMakeScale(0.96, 0.96);" in ac
      and "usingSpringWithDamping:0.7 initialSpringVelocity:0.8" in ac)
check("C", "正规复用（出列拆光重建退役）",
      "for (UIView *sub in cell.contentView.subviews)" not in ac
      and "- (void)prepareForReuse" in ac)

# ============ D. 长按菜单全账户化 ============
print("== D. 长按菜单（person.circle 选用 / trash 红字删除 / 129b 角色项保留） ==")
check("D", "选用账号（person.circle -> ame190_selectAccountAtIndexPath）",
      'systemImageNamed:@"person.circle"' in ac
      and 'localize(@"account.menu.use"' in ac
      and ac.count("[self ame190_selectAccountAtIndexPath:indexPath];") >= 2)
check("D", "删除账号（trash + UIMenuElementAttributesDestructive -> ame190_deleteAccountAtIndexPath）",
      'systemImageNamed:@"trash"' in ac
      and "UIMenuElementAttributesDestructive" in ac
      and "UIActionAttributesDestructive" not in ac  # CI run 36397990325：本 SDK 无此旧别名（编译器点名真名）
      and ac.count("[self ame190_deleteAccountAtIndexPath:indexPath];") >= 2)
check("D", "Task129b 角色切换项保留（3P 多角色 + UUID 归一化打勾）",
      "ame129b_switchAccountAtIndexPath:indexPath toProfile:p];" in ac
      and "UIMenuElementStateOn" in ac
      and 'stringByReplacingOccurrencesOfString:@"-"' in ac)
check("D", "选择链收口（原 didSelect 主体迁入 ame190_selectAccountAtIndexPath）",
      "- (void)ame190_selectAccountAtIndexPath:(NSIndexPath *)indexPath {" in ac
      and "[[BaseAuthenticator loadSavedName:loadKey] refreshTokenWithCallback:callback];" in ac
      and "ame128_markSessionValidated" in ac)
check("D", "删除链收口（原 commitEditingStyle 分支迁入 ame190_deleteAccountAtIndexPath）",
      "- (void)ame190_deleteAccountAtIndexPath:(NSIndexPath *)indexPath {" in ac
      and "clearTokenDataOfProfile" in ac
      and 'setPrefObject(@"internal.selected_account", @"");' in ac
      and "deleteRowsAtIndexPaths" in ac)
check("D", "左滑删除入口保留（commitEditingStyle 委派删除链）",
      "UITableViewCellEditingStyleDelete" in ac
      and ac.count("[self ame190_deleteAccountAtIndexPath:indexPath];") == 2)

# ============ E. 退役断言 ============
print("== E. 退役（130b 行内按钮 / 旧 16pt 内联卡 / 类型胶囊 / 箭头） ==")
check("E", "ame130b_switchRoleTapped 与 person.2 按钮退役",
      "ame130b_switchRoleTapped" not in ac and '"person.2"' not in ac
      and "objc_setAssociatedObject" not in ac and "objc_getAssociatedObject" not in ac)
check("E", "旧卡面退役（白 0.10 + 16pt 圆角 + pinned 钉住 + 旧方勾勾）",
      "cardView.layer.cornerRadius = 16" not in ac
      and "ame_setNeumorphPinnedCornerRadius" not in ac
      and "checkmark.circle.fill" not in ac
      and "avatarView.widthAnchor constraintEqualToConstant:48" not in ac)
check("E", "Task136 类型胶囊退役（badgeLabel 零出现）",
      "badgeLabel" not in ac and "applyAccountTypeBadgeForAccount" not in ac)
check("E", "objc/runtime.h 引擎无关 import 退役（无 objc_ 符号）",
      "#import <objc/runtime.h>" not in ac)

# ============ F. 保留断言（历史修复零回退） ============
print("== F. 保留（180 去重 / 162 刷新 / 126 Toast / 引擎无关性） ==")
check("F", "Task180 读侧去重 + 坏文件过滤保留",
      "ame180_seenIds" in ac and "dedup account entry by id" in ac
      and "skipping unreadable account file" in ac)
check("F", "Task162 三触发口刷新保留",
      "ame162_handleAccountsChanged" in ac and ac.count('name:@"AccountChanged"') == 1
      and ac.count('name:@"UpdateAccountInfo"') == 1)
check("F", "Task126 Toast 收口保留", "ame126_msg" in ac and "NMToast showMessage:" in ac)
check("F", "底部添加账户浮动按钮保留", "setupAddAccountButton" in ac and "login.option.add" in ac)
check("F", "reloadAccountList 唯一实现（Task162 CI 教训）",
      ac.count("- (void)reloadAccountList {") == 1)
check("F", "账号文件全链仍走 accountId 键（128/129b/删除链口径一致）",
      ac.count('accountData[@"accountId"]') >= 3)

# ============ G. l10n（×4 主语言 + 计数 2228） ============
print("== G. l10n account.menu.use/delete ×4 + 计数 2228->2157 ==")
RES = "Natives/resources"
expect = {
    "en":      ("Use account", "Delete account"),
    "zh-Hans": ("选用账号", "删除账号"),
    "zh-CN":   ("选用账号", "删除账号"),
    "zh-Hant": ("選用帳號", "刪除帳號"),
}
for lang, (u, d) in expect.items():
    s = rdrepo(f"{RES}/{lang}.lproj/Localizable.strings")
    keys = set(re.findall(r'^"([^"]+)" =', s, re.M))
    check("G", f"{lang} account.menu.use/delete 键值", f'"account.menu.use" = "{u}";' in s
          and f'"account.menu.delete" = "{d}";' in s)
    check("G", f"{lang} 唯一键总数 == 2417", len(keys) == 2417, f"got {len(keys)}")
    check("G", f"{lang} account.switch_role.* 历史键保留",
          'account.switch_role.button' in keys and 'account.switch_role.title' in keys)

# ============ H. CI 防回归纪律 ============
print("== H. CI 防回归（引擎符号 import 纪律 + 括号平衡 + @localize 扫描） ==")
def uses_engine_symbols(s):
    return any(sym in s for sym in (
        'AmeNeumorphPrimaryTextColor', 'AmeNeumorphSecondaryTextColor',
        'ame_setNeumorphPinnedCornerRadius', 'AmeNeumorphShadowView',
        'ame_applyNeumorphSurface', 'ame_applyCardSurfaceWithRadius',
        'ame_applyPanelSurfaceWithRadius', 'ame_applyNeumorphCardOpacity'))
bad = []
for fn in ['installer/ModLoaderInstallViewController.m', 'AccountListViewController.m',
           'LauncherRightPanelViewController.m', 'LauncherMenuViewController.m',
           'LauncherNewsViewController.m', 'VersionCardCell.m', 'VersionManagerViewController.m']:
    s = rdrepo(f"Natives/{fn}")
    if uses_engine_symbols(s) and 'UIKit+NativeSurface.h' not in s:
        bad.append(fn)
check("H", "引擎符号文件全部带引擎头 import（Task180 G 组教训常驻）", not bad, str(bad))
check("H", "AccountList 已不用引擎符号且不再 import 引擎头（经 BackgroundManager 转介）",
      not uses_engine_symbols(ac) and '#import "UIKit+NativeSurface.h"' not in ac)
_stray = []
for _root, _dirs, _fs in os.walk(N):
    for _f in _fs:
        if _f.endswith((".m", ".mm")):
            _p = os.path.join(_root, _f)
            _s = re.sub(r'//(?!\*)[^\n]*', '', rdrepo(_p))
            _s = re.sub(r'/\*.*?\*/', '', _s, flags=re.S)
            _s = re.sub(r'@"(?:[^"\\]|\\.)*"', '""', _s)
            if re.search(r'@localize\(', _s):
                _stray.append(_p)
check("H", "全仓零 @localize( 杂散 @（Task189 G12 常驻）", not _stray, str(_stray[:3]))
for fn in ("Natives/AccountListViewController.m", "Natives/BackgroundManager.m",
           "Natives/installer/ModLoaderInstallViewController.m"):
    s = re.sub(r'@"(?:[^"\\]|\\.)*"', '""', rdrepo(fn))   # 先剥字符串（URL 内 // 不得触发注释剥除，Task188 门同序）
    s = re.sub(r'//(?!\*)[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    stack = []
    ok = True
    pairs = {')': '(', ']': '[', '}': '{'}
    for ch in s:
        if ch in '([{':
            stack.append(ch)
        elif ch in ')]}':
            if not stack or stack[-1] != pairs[ch]:
                ok = False
                break
            stack.pop()
    check("H", f"{os.path.basename(fn)} 严格栈匹配括号平衡", ok and not stack)
check("H", "announcements/task190 条目存在（Task209 重锚：@2 插入后顺延至 [6]）",
      json.loads(rdrepo("announcements.json"))["announcements"][8]["id"].startswith("task190-"))

print("=" * 72)
print(f"PASS {len(PASS)}  FAIL {len(FAIL)}")
if FAIL:
    for g, n, d in FAIL:
        print(f"  FAIL [{g}] {n}  {d}")
    sys.exit(1)
print("ALL GREEN -- Task 190")
