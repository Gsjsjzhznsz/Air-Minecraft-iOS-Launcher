#!/usr/bin/env python3
"""
Task 101 验证器：三卡图标/标题更正 + 七卡居中 + 灰字版本标签退场 + 侧栏图标对齐自愈

背景（用户实测截图 IMG_9133 反馈）：
  1. 三个卡片图标选用错误：
     - JIT 卡显示成了回退点阵（circle.grid.2x2）——根因：SF Symbols 全库
       （1.0→8.0 共 9476 个符号，联网核实 pat-in-a-hat/sf-symbols-reference
       全表）中根本不存在名为 "rabbit" 的符号，兔子的真名是 hare
       （SF Symbols 1.0 起就有，线框兔）。systemImageNamed:@"rabbit" 返回
       nil 后走了兜底链。更正为 hare。
     - 内存上限提升 → 更名「扩展内存限制」，图标改实心 ROM 芯片
       memorychip.fill（SF Symbols 3.0，联网核实存在）。
     - 扩展虚拟寻址 → 更名「扩展虚拟内存」，图标改空心 ROM 芯片 memorychip
       （SF Symbols 2.0，即原内存上限提升卡同款图标）。
  2. 左上角主界面（house.fill）图标有时刚打开软件时消失：启动早期偶发
     systemImageNamed: 拿到 nil 的时序问题，新增 refreshMenuIconImages
     幂等自愈（viewWillAppear + 外观刷新路径双入口，仅补 image 为空的按钮）。
     （Task102 注：单次补拉仍在竞态窗口内，已升级为重试自愈，见 verify_task102）
  3. 左侧菜单按钮新拟物高亮与图标偏差：原 imageEdgeInsets(-10,0,0,0) +
     空白标题（" "）布局把图标上移 10pt，而高亮面板是整个 50×50 按钮——
     图标偏离高亮中心。去空白标题与 insets，图标几何居中。
  4. 七张信息卡内容在卡内水平居中（原左侧贴边）。
     （Task102 注：此项系理解偏差已回退——用户要居中的是七卡并列位置而非卡片
     内容；本验证器 B 区已重锚为回退后的 Task96 左锚定布局）
  5. 头像下方灰字游戏版本（versionLabel，如 26.3）退场：与绿色游戏版本卡
     同数据源重复展示；滚动区上锚改接用户名标签。

护栏（零变化）：内存两卡 getEntitlementValue()（SecTask 签名口径，与启动
日志同源）、JIT isJITEnabled(NO) + TXM 三态判定链、刷新时机三件套、
7 卡顺序/46pt 高/12 圆角/15% 底/动态正文字色/超长缩放全部保持。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK101_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_objc(src):
    """字符串感知剥离：去 @"..." 字面量与注释（兼容 CRLF）。"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == '\\' else 1
            i += 1
            out.append('""')
        elif src.startswith("//", i):
            while i < n and src[i] != '\n':
                i += 1
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def git(args):
    return subprocess.run(["git", "-C", REPO] + args, capture_output=True, text=True)


def bracket_balance(code):
    return (code.count("{") == code.count("}")
            and code.count("(") == code.count(")")
            and code.count("[") == code.count("]"))


rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc(rp)
menu = read("Natives/LauncherMenuViewController.m")
menu_code = strip_objc(menu)

print("=" * 72)
print("A. 三卡图标/标题更正（联网核实：SF Symbols 无 rabbit，hare=兔）")
print("=" * 72)
check("A1  JIT 卡图标 = hare（SF 1.0 线框兔；rabbit 符号不存在导致 nil 回退）",
      'makeInfoCardWithIcon:@"hare" accent:cardOrange title:@"JIT"' in rp)
check("A2  rabbit 符号名零残留（旧名仅存于留档注释，代码路径不再引用）",
      'systemImageNamed:@"rabbit"' not in rp
      and 'makeInfoCardWithIcon:@"rabbit"' not in rp)
check("A3  扩展内存限制卡 = 实心 ROM memorychip.fill（SF 3.0）",
      'makeInfoCardWithIcon:@"memorychip.fill" accent:cardOrange title:@"扩展内存限制"' in rp)
check("A4  扩展虚拟内存卡 = 空心 ROM memorychip（SF 2.0，即原内存卡同款）",
      'makeInfoCardWithIcon:@"memorychip" accent:cardAmber title:@"扩展虚拟内存"' in rp)
check("A5  旧卡名/旧图标不再作为卡片标题/图标（旧名仅允许存于留档注释）",
      'title:@"内存上限提升"' not in rp
      and 'title:@"扩展虚拟寻址"' not in rp
      and 'makeInfoCardWithIcon:@"arrow.up.left.and.arrow.down.right"' not in rp)
check("A6  Task101 核实留档注释在案（9476 符号全表 + hare 真名）",
      "Task101" in rp and "hare" in rp and "9476" in rp)
check("A7  内存检测注释同步更名且口径说明保留（Task93 同源说明不动）",
      "刷新「扩展内存限制」「扩展虚拟内存」两张卡片的正文" in rp
      and "Task93" in rp and "Entitlements availability" in rp)

print()
print("=" * 72)
print("B. 七张信息卡布局（Task102 重锚：内容居中系误解已回退，恢复 Task96 左锚定；")
print("   居中的是七卡并列位置——updateInfoContentInset，见 verify_task102 A 区）")
print("=" * 72)
factory = rp[rp.find("- (UIView *)makeInfoCardWithIcon:"):rp.find("- (UIImage *)cardSymbolImageNamed:")]
check("B1  工厂无 stack 嵌套（Task101 内容组退役，图标/标题/正文直接挂卡片）",
      factory.count("UIStackView alloc") == 0
      and factory.count("[card addSubview:iconView]") == 1
      and factory.count("[card addSubview:titleLabel]") == 1
      and factory.count("[card addSubview:valueLabel]") == 1)
check("B2  Task96 左锚定回归：图标 leading 14 + 卡内垂直居中（20×20）",
      "iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14" in factory
      and "iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor" in factory
      and "iconView.widthAnchor constraintEqualToConstant:20" in factory
      and "iconView.heightAnchor constraintEqualToConstant:20" in factory)
check("B3  标题/正文接图标右侧（间距 10），trailing -12 内缩放截尾",
      "titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10" in factory
      and "valueLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10" in factory
      and "titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12" in factory
      and "valueLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12" in factory)
check("B4  标题贴顶 7 / 正文贴底 -7（原版紧凑排布；文字左对齐，工厂内无 Center）",
      "titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:7" in factory
      and "valueLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-7" in factory
      and "NSTextAlignmentCenter" not in factory)
check("B5  Task101 内容组零残留（contentStack/textContentStack/居中不等式全退场）",
      "contentStack" not in factory
      and "textContentStack" not in factory
      and "contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:14" not in factory)
check("B6  卡片基础样式保持：46pt 高 / 圆角 12 / 15% 透明同色底",
      "heightAnchor constraintEqualToConstant:46" in factory
      and "cornerRadius = 12" in factory
      and "colorWithAlphaComponent:0.15" in factory)
check("B7  正文字色与缩放保持：动态 #222222/#EEEEEE + adjustsFontSizeToFitWidth + 0.55",
      "0xEE / 255.0" in factory and "0x22 / 255.0" in factory
      and "colorWithDynamicProvider" in factory
      and "adjustsFontSizeToFitWidth" in factory and "minimumScaleFactor = 0.55" in factory)
check("B8  图标尺寸 20×20 保持（内容组内居中随动）",
      "iconView.widthAnchor constraintEqualToConstant:20" in factory
      and "iconView.heightAnchor constraintEqualToConstant:20" in factory)
check("B9  右面板括号配平（字符串感知）", bracket_balance(rp_code))

print()
print("=" * 72)
print("C. 灰字游戏版本标签退场（头像下方 26.3；与游戏版本卡同源重复）")
print("=" * 72)
check("C1  versionLabel 属性/创建/约束全部移除",
      "UILabel *versionLabel" not in rp_code
      and "self.versionLabel = [[UILabel alloc] init]" not in rp
      and "self.versionLabel.topAnchor" not in rp_code)
check("C2  滚动区上锚改接用户名标签（usernameLabel.bottom + 8）",
      "self.infoScrollView.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:8" in rp
      and "self.infoScrollView.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor" not in rp)
check("C3  外观刷新不再触碰 versionLabel（textColor 分支清理）",
      "self.versionLabel.textColor" not in rp)
check("C4  updateVersionInfo 只喂游戏版本卡（数据源单出口）",
      "self.gameVersionCardValue.text = versionId;" in rp
      and 'self.gameVersionCardValue.text = @"未选择";' in rp
      and "self.versionLabel.text" not in rp)
check("C5  版本选择入口不受影响（manageVersionBtn 弹窗仍在，原标签手势退场无碍）",
      rp_code.count("showVersionPicker") >= 2
      and "[self.manageVersionBtn addTarget:self action:@selector(showVersionPicker)" in rp)
check("C6  退场留档注释在案",
      "versionLabel" in rp and "Task101" in rp)

print()
print("=" * 72)
print("D. 侧栏菜单按钮：图标与新拟物高亮几何对齐（去空白标题与 insets）")
print("=" * 72)
check("D1  偏移元凶退役：btn.titleEdgeInsets/btn.imageEdgeInsets 赋值零残留（留档注释不计）",
      "btn.titleEdgeInsets" not in menu and "btn.imageEdgeInsets" not in menu)
check("D2  空白标题不再渲染（setTitle/setTitleColor titleLabel.font 零残留）",
      "[btn setTitle:" not in menu
      and "[btn setTitleColor:" not in menu
      and "btn.titleLabel.font" not in menu)
check("D3  图标居中对齐：内容水平/垂直双居中保持",
      "btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;" in menu
      and "btn.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;" in menu)
check("D4  侧栏选中态原生 accent 高亮（Task137 重锚：凸出面板退役，双入口 accent 0.15）",
      menu.count("[accent colorWithAlphaComponent:0.15]") == 2
      and "nm_convexRadius" not in menu)
check("D5  菜单图标清单原样（house.fill 等 6 项未动）",
      all(k in menu for k in ['@"house.fill"', '@"arrow.down.circle.fill"', '@"sparkles"',
                              '@"puzzlepiece.fill"', '@"gearshape.fill"', '@"questionmark.circle.fill"']))
check("D6  菜单括号配平（字符串感知）", bracket_balance(menu_code))

print()
print("=" * 72)
print("E. 主界面图标消失自愈（启动早期偶发 systemImageNamed: nil）")
print("=" * 72)
check("E1  refreshMenuIconImages 方法存在且幂等（Task111 重锚：填充式/强制式双路径，稳态仅补 nil）",
      "- (void)refreshMenuIconImages {" in menu_code
      and "refreshMenuIconImagesForced:(BOOL)forced" in menu_code
      and "if (!forced && current) continue;" in menu_code
      and "[btn imageForState:UIControlStateNormal]" in menu
      and menu_code.count("- (void)refreshMenuIconImages") == 2)
check("E2  自愈入口链（Task111 重锚）：viewWillAppear/viewDidLayoutSubviews → beginMenuIconSelfHeal 强制式首拉，updateButtonColors 直补仍保留",
      re.search(r"- \(void\)viewWillAppear:[\s\S]{0,300}?\[self beginMenuIconSelfHeal\];", menu_code)
      and re.search(r"- \(void\)viewDidLayoutSubviews \{[\s\S]{0,600}?\[self beginMenuIconSelfHeal\];", menu_code)
      and "[self refreshMenuIconImagesForced:YES];" in menu_code
      and menu.count("[self refreshMenuIconImages];") >= 1)
check("E3  viewWillAppear 正确调用 super",
      "- (void)viewWillAppear:(BOOL)animated {" in menu
      and "[super viewWillAppear:animated];" in menu)
check("E4  自愈重取走同一符号表（menuItems icon 字段，不引入第二份图标清单；Task111 重锚 iconName 变量路径）",
      'self.menuItems[idx][@"icon"]' in menu
      and "[UIImage systemImageNamed:iconName]" in menu)
check("E5  越界防御（tag 与 menuItems.count 校验）",
      "idx >= (NSInteger)self.menuItems.count" in menu)

print()
print("=" * 72)
print("F. 护栏与仓库卫生（检测口径 / 结构 / worklog）")
print("=" * 72)
check("F1  内存两卡签名口径零变化（getEntitlementValue 恰两处调用）",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2
      and 'getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")' in rp
      and 'getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")' in rp)
check("F2  JIT 三态判定链零变化",
      "BOOL enabled = isJITEnabled(NO);" in rp_code
      and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in rp_code
      and "JIT26IsLikelyDebuggerKeepAttached()" in rp_code)
check("F3  刷新时机三件套零变化（setupUI 尾/viewWillAppear/DidBecomeActive）",
      re.search(r"\[self updateJITStatus\];\s*\[self updateMemoryEntitlementStatus\];", rp)
      and rp.count("selector:@selector(updateMemoryEntitlementStatus)") == 1
      and rp.count("selector:@selector(updateJITStatus)") == 1)
check("F4  七卡顺序与配色变量保持（cardGreen/cardBlue/cardOrange/cardAmber）",
      rp.find('makeInfoCardWithIcon:@"cube.transparent"') < rp.find('makeInfoCardWithIcon:@"gamecontroller"')
      < rp.find("makeInfoCardWithIcon:deviceIconName") < rp.find('makeInfoCardWithIcon:@"applelogo"')
      < rp.find('makeInfoCardWithIcon:@"hare"') < rp.find('makeInfoCardWithIcon:@"memorychip.fill"')
      < rp.find('makeInfoCardWithIcon:@"memorychip"')
      and all(k in rp for k in ["UIColor *cardGreen", "UIColor *cardBlue",
                                "UIColor *cardOrange", "UIColor *cardAmber"]))
check("F5  ARC 出参签名保持（Task98 修复不被回退）",
      "UILabel * __strong *)outValueLabel" in rp)
check("F6  仓库 worklog 含 Task 101 条目",
      os.path.exists(os.path.join(REPO, "worklog.md")) and "Task ID: 101" in read("worklog.md"))
check("F7  无未提交改动（提交后自然通过）",
      git(["status", "--porcelain"]).stdout.strip() == "",
      git(["status", "--porcelain"]).stdout.strip()[:200])

print()
print("=" * 72)
print(f"RESULT: {PASS} passed, {FAIL} failed, total {PASS + FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
