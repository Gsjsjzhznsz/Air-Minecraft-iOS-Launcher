#!/usr/bin/env python3
"""
Task 102 验证器：七卡并列位置整体居中 + 主界面按钮首启自愈升级 + 头像对齐执行Jar按钮

背景（用户 Task 101 IPA 实测反馈）：
  1. 七卡"居中"系理解偏差回退：用户要的是七张卡片的并列位置落在右侧栏中部
     （整组垂直居中），而非卡片内容居中。实现：
     - 卡工厂回退 Task96 左锚定布局（内容居中已在 Task101 误改，撤销）；
     - 滚动区内容总高不足视口时上下均分 contentInset（updateInfoContentInset），
       内容超高时归零恢复普通滚动；viewDidLayoutSubviews + contentSize KVO
       双触发，偏移钳制让小内容立即落位居中位置。
  2. 主界面按钮首启不显示（Task101 单次 viewWillAppear 补拉无效）：
     根因收窄——主界面按钮是 setupSidebar 循环里第一个调 systemImageNamed:
     的控件，进程冷启动首调用存在 CoreUI 符号注册竞态，首调用偶发 nil 而
     后续调用全部正常（所以只有主界面消失、其他按钮都在；点其他菜单项时
     updateButtonColors→refreshMenuIconImages 补拉成功即"恢复"）。
     升级：beginMenuIconSelfHeal 短周期重试（0.25s×16 次≈4s，全部就绪即停），
     viewWillAppear / viewDidLayoutSubviews 双入口，dealloc 清理定时器。
  3. 头像与执行Jar按钮对齐：宽度与执行Jar按钮等宽（原固定 72pt），高度跟随
     宽度保持正方形、viewDidLayoutSubviews 动态圆角（宽/2）保持正圆；距面板
     顶部间距与执行Jar按钮距面板底部间距共用 AmePanelVerticalEdgeInset（12），
     对称关系由常量保证。

护栏（零变化）：内存两卡 getEntitlementValue()（SecTask 签名口径，与启动
日志同源）、JIT isJITEnabled(NO) + TXM 三态判定链、刷新时机三件套、
7 卡顺序/图标/标题/46pt 高/12 圆角/15% 底/动态正文字色/超长缩放全部保持，
ARC 出参签名（Task98）不被回退。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK102_REPO", "/home/z/my-project/workspace/Air-Minecraft-iOS-Launcher")
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
print("A. 七卡并列位置整体居中（updateInfoContentInset + 双触发 + 偏移钳制）")
print("=" * 72)
check("A1  updateInfoContentInset 方法定义且唯一",
      rp_code.count("- (void)updateInfoContentInset") == 1
      and "updateInfoContentInset" in rp_code)
check("A2  上下均分 contentInset（(视口-内容)/2，UIEdgeInsetsMake(inset,0,inset,0)）",
      "(scrollView.bounds.size.height - scrollView.contentSize.height) / 2.0" in rp_code
      and "UIEdgeInsetsMake(inset, 0, inset, 0)" in rp_code)
check("A3  内容超高归零（inset < 0 → 0，恢复普通滚动不破 Task96 可滚动能力）",
      "if (inset < 0) inset = 0;" in rp_code)
check("A4  幂等护栏（UIEdgeInsetsEqualToEdgeInsets 相等不写回，避免布局抖动）",
      "UIEdgeInsetsEqualToEdgeInsets(scrollView.contentInset, target)" in rp_code)
check("A5  偏移钳制：小内容落位 -inset，拖拽/减速中不干预（isDragging/isDecelerating）",
      "CGPointMake(scrollView.contentOffset.x, -inset)" in rp_code
      and "scrollView.isDragging" in rp_code and "scrollView.isDecelerating" in rp_code)
check("A6  双触发：viewDidLayoutSubviews 调用 + contentSize KVO context 分支调用",
      re.search(r"- \(void\)viewDidLayoutSubviews \{[\s\S]{0,600}?\[self updateInfoContentInset\];", rp_code)
      and re.search(r"if \(context == AmeInfoContentSizeContext\) \{\s*\[self updateInfoContentInset\];", rp_code))
check("A7  KVO 注册/注销配对（context 区分下载进度 KVO；dealloc @try 移除）",
      rp.count('forKeyPath:@"contentSize"') == 2
      and "removeObserver:self" in rp_code
      and "@catch (NSException *e)" in rp_code)
check("A8  contentSize context 静态定义（唯一地址指针惯用法）",
      "static void *AmeInfoContentSizeContext = &AmeInfoContentSizeContext;" in rp_code)
check("A9  用户澄清留档：居中的是并列位置，不是卡片内容（注释在案）",
      "并列位置" in rp and "不是卡片内容" in rp)
check("A10 右面板括号配平（字符串感知）", bracket_balance(rp_code))

print()
print("=" * 72)
print("B. 卡片内容居中误解回退（Task96 左锚定回归；与 verify_task101 重锚互补）")
print("=" * 72)
factory = rp[rp.find("- (UIView *)makeInfoCardWithIcon:"):rp.find("- (UIImage *)cardSymbolImageNamed:")]
check("B1  工厂无 stack 嵌套（内容组退役）",
      factory.count("UIStackView alloc") == 0)
check("B2  Task96 左锚定回归（图标 leading 14/卡内垂直居中，标题贴顶 7，正文贴底 -7）",
      "iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14" in factory
      and "iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor" in factory
      and "titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:7" in factory
      and "valueLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-7" in factory)
check("B3  工厂内文字左对齐（无 Center）",
      "NSTextAlignmentCenter" not in factory)
check("B4  内容组零残留（contentStack/textContentStack 全文件退场）",
      "contentStack" not in rp_code and "textContentStack" not in rp_code)

print()
print("=" * 72)
print("C. 头像与执行Jar按钮对齐（等宽/高度跟随/动态正圆/顶底间距对称）")
print("=" * 72)
check("C1  头像宽度 = 执行Jar按钮宽度（等宽约束）",
      "self.avatarImageView.widthAnchor constraintEqualToAnchor:self.executeJarBtn.widthAnchor" in rp_code)
check("C2  头像高度跟随宽度（正方形随动）",
      "self.avatarImageView.heightAnchor constraintEqualToAnchor:self.avatarImageView.widthAnchor" in rp_code)
check("C3  固定 72pt 退场（widthAnchor constraintEqualToConstant:72 零残留）",
      "self.avatarImageView.widthAnchor constraintEqualToConstant:72" not in rp_code
      and "self.avatarImageView.heightAnchor constraintEqualToConstant:72" not in rp_code)
check("C4  共享常量 AmePanelVerticalEdgeInset = 12（对称关系由常量保证）",
      "static const CGFloat AmePanelVerticalEdgeInset = 12;" in rp_code)
check("C5  顶底对称：头像顶部 +inset，执行Jar/管理版本底部 -inset（同一常量三处）",
      "self.avatarImageView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:AmePanelVerticalEdgeInset" in rp_code
      and "self.executeJarBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-AmePanelVerticalEdgeInset" in rp_code
      and "self.manageVersionBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-AmePanelVerticalEdgeInset" in rp_code)
check("C6  动态正圆：viewDidLayoutSubviews 内 cornerRadius = 宽/2（等宽后尺寸随动）",
      "self.avatarImageView.layer.cornerRadius = avatarSide / 2.0;" in rp_code
      and "if (avatarSide > 0)" in rp_code)

print()
print("=" * 72)
print("D. 主界面按钮首启自愈升级（重试定时器；根因：进程内首次 systemImageNamed: 竞态）")
print("=" * 72)
check("D1  beginMenuIconSelfHeal 定义且唯一 + allMenuIconsLoaded 就绪判定",
      menu_code.count("- (void)beginMenuIconSelfHeal") == 1
      and menu_code.count("- (BOOL)allMenuIconsLoaded") == 1)
check("D2  重试参数：0.25s 周期 × 16 次上限（约 4s）",
      "timerWithTimeInterval:0.25 repeats:YES" in menu_code
      and "attempts >= 16" in menu_code)
check("D3  就绪即停 + 重试不叠加（allMenuIconsLoaded 返回 + 定时器已存在检查）",
      "if ([self allMenuIconsLoaded]) return;" in menu_code
      and "if (self.menuIconSelfHealTimer) return;" in menu_code)
check("D4  定时器属性 + dealloc invalidate（runloop 强持有显式解除）",
      "@property(nonatomic, strong) NSTimer *menuIconSelfHealTimer;" in menu
      and "[self.menuIconSelfHealTimer invalidate];" in menu_code)
check("D5  双入口：viewWillAppear / viewDidLayoutSubviews → beginMenuIconSelfHeal",
      re.search(r"- \(void\)viewWillAppear:[\s\S]{0,300}?\[self beginMenuIconSelfHeal\];", menu_code)
      and re.search(r"- \(void\)viewDidLayoutSubviews \{[\s\S]{0,600}?\[self beginMenuIconSelfHeal\];", menu_code))
check("D6  Task101 直补路径保留（updateButtonColors → refreshMenuIconImages）",
      "updateButtonColors" in menu_code
      and menu.count("[self refreshMenuIconImages];") >= 2)
check("D7  根因留档注释（首调用 CoreUI 符号注册竞态 / 只有主界面消失的原因）",
      "systemImageNamed" in menu and "竞态" in menu and "beginMenuIconSelfHeal" in menu)
check("D8  菜单括号配平（字符串感知）", bracket_balance(menu_code))

print()
print("=" * 72)
print("E. 护栏（检测口径/结构零变化）")
print("=" * 72)
check("E1  内存两卡签名口径零变化（getEntitlementValue 恰两处调用）",
      rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2
      and 'getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")' in rp
      and 'getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing")' in rp)
check("E2  JIT 三态判定链零变化",
      "BOOL enabled = isJITEnabled(NO);" in rp_code
      and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in rp_code
      and "JIT26IsLikelyDebuggerKeepAttached()" in rp_code)
check("E3  刷新时机三件套零变化（setupUI 尾/viewWillAppear/DidBecomeActive）",
      re.search(r"\[self updateJITStatus\];\s*\[self updateMemoryEntitlementStatus\];", rp)
      and rp.count("selector:@selector(updateMemoryEntitlementStatus)") == 1
      and rp.count("selector:@selector(updateJITStatus)") == 1)
check("E4  七卡顺序与图标保持（cube/gamecontroller/设备/applelogo/hare/memorychip.fill/memorychip）",
      rp.find('makeInfoCardWithIcon:@"cube.transparent"') < rp.find('makeInfoCardWithIcon:@"gamecontroller"')
      < rp.find("makeInfoCardWithIcon:deviceIconName") < rp.find('makeInfoCardWithIcon:@"applelogo"')
      < rp.find('makeInfoCardWithIcon:@"hare"') < rp.find('makeInfoCardWithIcon:@"memorychip.fill"')
      < rp.find('makeInfoCardWithIcon:@"memorychip"'))
check("E5  ARC 出参签名保持（Task98 修复不被回退）",
      "UILabel * __strong *)outValueLabel" in rp)
check("E6  卡片基础样式保持：46pt 高 / 圆角 12 / 15% 透明同色底 / 动态正文字色",
      "heightAnchor constraintEqualToConstant:46" in factory
      and "cornerRadius = 12" in factory
      and "colorWithAlphaComponent:0.15" in factory
      and "colorWithDynamicProvider" in factory
      and "minimumScaleFactor = 0.55" in factory)
check("E7  滚动区四边锚定保持（Task96/101 结构不动）",
      "self.infoScrollView.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:8" in rp
      and "self.infoScrollView.bottomAnchor constraintEqualToAnchor:self.launchButton.topAnchor constant:-8" in rp
      and "self.infoScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12" in rp
      and "self.infoScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12" in rp)

print()
print("=" * 72)
print("F. 仓库卫生")
print("=" * 72)
check("F1  math.h 导入（fabs 居中钳制依赖，显式声明不赌传递包含）",
      "#include <math.h>" in rp)
check("F2  仓库 worklog 含 Task 102 条目",
      os.path.exists(os.path.join(REPO, "worklog.md")) and "Task ID: 102" in read("worklog.md"))
check("F3  无未提交改动（提交后自然通过）",
      git(["status", "--porcelain"]).stdout.strip() == "",
      git(["status", "--porcelain"]).stdout.strip()[:200])

print()
print("=" * 72)
print(f"RESULT: {PASS} passed, {FAIL} failed, total {PASS + FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
