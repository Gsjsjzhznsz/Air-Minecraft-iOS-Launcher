#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# task190_reanchor.py -- Task 190 级联重锚
# ① l10n 计数锚 2155 -> 2157（account.menu.use/delete 两新键）
# ② 公告窗口族顺延：task190@2 插入，全体非钉位索引 >=2 再 +1，len 23 -> 24
# ③ verify_task136/137/130/184 中被 Task190 合法改动的 AccountList /
#    installer 锚点做诚实翻转（带重锚理由注释）
import io, re, os

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def rd(p): return io.open(p, encoding="utf-8").read()
def wr(p, s): io.open(p, "w", encoding="utf-8").write(s)

changed = []

# ---------- ① l10n 计数 2155 -> 2157 ----------
for fn in sorted(os.listdir("scripts")):
    if not (fn.startswith("verify_task") and fn.endswith(".py")):
        continue
    p = os.path.join("scripts", fn)
    s = rd(p)
    n = s.count("2155")
    if n == 0:
        continue
    s2 = s.replace("2155", "2157")
    if s2 != s:
        wr(p, s2)
        changed.append(f"{fn}: 2155->{2157} x{n}")

# ---------- ② 公告索引顺延（N>=2 全体 +1，len 23->24） ----------
# 仅处理真实代码行（跳过注释行，历史叙述注释保持原样）。
import json
ann_path = "announcements.json"
ann = json.load(open(ann_path, encoding="utf-8"))
ids = [a["id"] for a in ann["announcements"]]
assert "task190-account-card-installer-spacing-2026-09-28" in ids, "先插入 task190 公告再跑重锚"

IDXS = re.compile(r'\b(ann|anns|items)\[(\d+)\]')
def shift_line(line):
    if line.lstrip().startswith("#"):
        return line
    def rep(m):
        n = int(m.group(2))
        return f"{m.group(1)}[{n + 1}]" if n >= 2 else m.group(0)
    return IDXS.sub(rep, line)

TARGETS = ["verify_task178.py", "verify_task177.py", "verify_task174.py",
           "verify_task173b_neumorph.py", "verify_task170.py", "verify_task175.py",
           "verify_task171.py", "verify_task172.py", "verify_task168.py",
           "verify_task179.py", "verify_task173.py"]
for fn in TARGETS:
    p = os.path.join("scripts", fn)
    s = rd(p).split("\n")
    out = []
    hits = 0
    for line in s:
        new = shift_line(line)
        if new != line:
            hits += 1
        out.append(new)
    # len == 23 -> 24（公告总数锚）
    body = "\n".join(out)
    body2 = body.replace("len(ann) == 23", "len(ann) == 24").replace("len(ann) == 23  # Task184：+1", "len(ann) == 24  # Task190：+1")
    if body2 != body:
        hits += 1
        body = body2
    if hits:
        wr(p, body)
        changed.append(f"{fn}: announcement window shift x{hits}")

# ---------- ③ 逐文件诚实翻转 ----------
# verify_task136: G2 卡间距 10->4；F6 类型胶囊 -> 灰字类型；I2 账户卡 16 -> 12
p = "scripts/verify_task136.py"
s = rd(p)
s = s.replace(
    '''check("G2  卡片间距 10pt（无标题 section 头高 10 + footer 0.01）",
      "if (section < (NSInteger)_loaders.count) return 10;" in ml
      and "return 0.01;" in ml)''',
    '''check("G2  卡片间距（Task190 重锚：用户要求与版本号页一致——section 头 10->4，净距 = 4 下内缩 + 4 头 + 4 上内缩 = 12pt）",
      "if (section < (NSInteger)_loaders.count) return 4;" in ml
      and "return 0.01;" in ml)''')
s = s.replace(
    '''check("F6  账户类型徽章：高 24 + 圆角 12 + 12pt 字",
      "badgeLabel.heightAnchor constraintEqualToConstant:24" in read("Natives/AccountListViewController.m")
      and "badgeLabel.layer.cornerRadius = 12" in read("Natives/AccountListViewController.m")
      and "badgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]" in read("Natives/AccountListViewController.m"))''',
    '''check("F6  账户类型标识（Task190 重锚：用户定稿灰字为账号类型——类型判别口径保留，彩色胶囊退役）",
      "ame190_accountTypeTextForAccount:" in read("Natives/AccountListViewController.m")
      and '[UIFont systemFontOfSize:[ScreenUtils sp:11] weight:UIFontWeightRegular]' in read("Natives/AccountListViewController.m")
      and "self.typeLabel.textColor = [UIColor secondaryLabelColor];" in read("Natives/AccountListViewController.m"))''')
s = s.replace(
    '''check("I2  卡片圆角回归原生逐元素取值（版本卡 12/资源卡 12/Mod版本卡 12/账户卡 16/筛选 14/自定义行 12/崩溃卡 16）",
      "cardContainer.layer.cornerRadius = 12" in read("Natives/VersionCardCell.m")
      and "contentView.layer.cornerRadius = 12.0" in read("Natives/ResourceCardTableViewCell.m")
      and "cardContainer.layer.cornerRadius = 12" in read("Natives/ModVersionTableViewCell.m")
      and "cardView.layer.cornerRadius = 16" in read("Natives/AccountListViewController.m")''',
    '''check("I2  卡片圆角回归原生逐元素取值（Task190 重锚：账户卡与已安装版本页同构 = 12pt；版本卡 12/资源卡 12/Mod版本卡 12/筛选 14/自定义行 12/崩溃卡 16）",
      "cardContainer.layer.cornerRadius = 12" in read("Natives/VersionCardCell.m")
      and "contentView.layer.cornerRadius = 12.0" in read("Natives/ResourceCardTableViewCell.m")
      and "cardContainer.layer.cornerRadius = 12" in read("Natives/ModVersionTableViewCell.m")
      and "self.contentContainer.layer.cornerRadius = 12;" in read("Natives/AccountListViewController.m")''')
wr(p, s)
changed.append("verify_task136.py: G2/F6/I2 重锚")

# verify_task137: D3 账户卡 16 -> 12
p = "scripts/verify_task137.py"
s = rd(p)
s = s.replace(
    '''check("D3  逐元素原生圆角（版本卡 12 / 账户卡 16 / 筛选 14 / 崩溃卡 16 / 磁贴 16 / 加载器名条 10）",
      "cardContainer.layer.cornerRadius = 12" in vc
      and "cardView.layer.cornerRadius = 16" in read("Natives/AccountListViewController.m")''',
    '''check("D3  逐元素原生圆角（Task190 重锚：账户卡与已安装版本页同构 = 12pt；版本卡 12 / 筛选 14 / 崩溃卡 16 / 磁贴 16 / 加载器名条 10）",
      "cardContainer.layer.cornerRadius = 12" in vc
      and "self.contentContainer.layer.cornerRadius = 12;" in read("Natives/AccountListViewController.m")''')
wr(p, s)
changed.append("verify_task137.py: D3 重锚")

# verify_task130: F1-F5（行内按钮退役 -> 长按菜单收敛）
p = "scripts/verify_task130.py"
s = rd(p)
s = s.replace(
    '''print("== F. 档案旁切换角色按钮（免密）==")
al = rd("Natives/AccountListViewController.m")
check("F1 ame130b_switchRoleTapped + actionSheet 形态",
      "ame130b_switchRoleTapped:(UIButton *)sender" in al
      and "UIAlertControllerStyleActionSheet" in al)
check("F2 按钮创建门（第三方 + availableProfiles>=2，与长按菜单同口径）",
      "ame130b_profiles.count >= 2" in al and 'systemImageNamed:@"person.2"' in al)
check("F3 关联对象 row 绑定（cell 复用安全）",
      'objc_setAssociatedObject(ame130b_switchBtn, "ame130b_row"' in al
      and 'objc_getAssociatedObject(sender, "ame130b_row")' in al)
check("F4 popover 锚定在按钮旁（iPad 悬浮形态）",
      "alert.popoverPresentationController.sourceView = sender;" in al)
check("F5 复用 ame129b_switchAccountAtIndexPath（switchToProfile 免密链）",
      al.count("ame129b_switchAccountAtIndexPath:indexPath toProfile:p") >= 2)''',
    '''print("== F. 切换角色（Task190 重锚：用户定稿账号卡与已安装版本页同构、卡片无多余控件——Task130b 行内 person.2 按钮 + actionSheet 退役，角色切换收敛进全账户长按菜单 Task129b 角色项；免密链零回退）==")
al = rd("Natives/AccountListViewController.m")
check("F1 行内按钮/actionSheet 退役（ame130b_switchRoleTapped 零残留）",
      "ame130b_switchRoleTapped" not in al
      and 'systemImageNamed:@"person.2"' not in al)
check("F2 关联对象 row 绑定随之退役",
      "objc_setAssociatedObject" not in al and "objc_getAssociatedObject" not in al
      and "#import <objc/runtime.h>" not in al)
check("F3 长按菜单保留 Task129b 角色项（免密链唯一入口）",
      al.count("ame129b_switchAccountAtIndexPath:indexPath toProfile:p") == 1
      and "contextMenuConfigurationForRowAtIndexPath" in al
      and "UIMenuElementStateOn" in al)
check("F4 account.switch_role.button l10n 四语言（键保留，未消费也保留）",
      all('"account.switch_role.button"' in rd(f"Natives/resources/{l}.lproj/Localizable.strings")
          for l in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))''')
wr(p, s)
changed.append("verify_task130.py: F1-F6 重锚（F6 保留）")

# verify_task184: D 组账号卡锚（旧卡面 -> 新同构卡）
p = "scripts/verify_task184.py"
s = rd(p)
s = s.replace(
    '''check('D', '账号列表凸起重写保留（管线 + 钉 16 + 裁剪放行）',
      'applyNeumorphCardEffectToView:cardView];' in ac
      and '[cardView ame_setNeumorphPinnedCornerRadius:16];' in ac
      and 'cell.contentView.layer.masksToBounds = NO;' in ac)''',
    '''check('D', '账号卡（Task190 重锚：与已安装版本页同构 AME190AccountCardCell——旧 Task180 内联卡面退役，管线换 Task172 三段式泛型入口）',
      'applyEffectToTableViewCell:self];' in ac
      and 'AME190AccountCardCell' in ac
      and 'cell.contentView.layer.masksToBounds = NO;' in ac)''')
wr(p, s)
changed.append("verify_task184.py: D 组重锚")

print("\n".join(changed))
print(f"reanchor done: {len(changed)} file groups")
