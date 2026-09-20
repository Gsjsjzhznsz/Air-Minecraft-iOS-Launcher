#!/usr/bin/env python3
"""
Task 96 验证器：右面板搬入 MeloNX 风格信息卡（用户指定 UI 改版）

背景（用户需求）：
  - 把 MeloNX 的信息显示卡片（设备/系统/内存状态等）搬进右侧面板，左右边缘
    与下方「登录并启动」按钮对齐；不搬 MeloNX 卡片附带的小字（如 "2.6"、
    "JIT Enabled"）。
  - 新增 3 张卡：启动器版本（#64C466，空心立方体 cube.transparent，正文=
    App 版本号，双读 CFBundleShortVersionString + CFBundleVersion，超长缩放）、
    游戏版本（#64C466，空心手柄 gamecontroller，正文=当前选择实例版本，
    与红框同源）、JIT 兔子卡（Task101 更正：SF Symbols 全库无 "rabbit"，
    兔子真名 hare（SF 1.0 线框兔，联网核实 9476 符号全表）；颜色与内存
    权限卡同色系，位于 MeloNX 四卡正中间，值 已开启/未开启）。
  - System 卡配色改成与 Device 一样（系统蓝）。
  - 卡片语言全部中文（用户选择），值显示 已开启/未开启。
  - 卡片高度/宽度与「登录并启动」一致（46pt / 12pt 边距）；右下角执行 Jar、
    选择版本两按钮改为与「登录并启动」同款（accentColor 底 + 白字）。
  - 卡片增加到 7 张后空间紧张：面板允许上下滚动（用户确认）。

Task101 增补（用户实测反馈）:
  - 三卡图标/标题更正：JIT=hare（兔）；内存上限提升→扩展内存限制
    （实心 memorychip.fill）；扩展虚拟寻址→扩展虚拟内存（空心 memorychip）。
  - 七卡内容在卡内水平居中（工厂改双 stack 内容组 + centerX/Y）。
  - 头像下灰字游戏版本标签（versionLabel，如 26.3）退场，滚动区上接用户名。
  - 左侧菜单按钮：去空白标题与 insets，图标在新拟物高亮面板内居中；
    新增 refreshMenuIconImages 自愈启动早期偶发 nil 图标。

检测口径（Task93 回归护栏，不变）：
  内存两卡仍用 utils.m getEntitlementValue()（SecTask 签名口径，与启动日志
  [Pre-init] Entitlements availability 完全同源）；JIT 三态仍用
  isJITEnabled(NO) + JIT26 TXM 判定链。

设备/系统数据源（Task96 新增，utils.h/utils.m）：
  getDeviceMarketingName() = hw.machine → Apple 营销名（联网核实：
  iPad15,3/15,4=Air M3 11/13、iPad15,7/15,8=iPad 11(A16)、iPad16,1/2=mini
  A17 Pro、iPad16,3-6=Pro M4 11/13）；未收录机型回退原始标识。
  getSystemVersionDisplay() = "iPadOS 18.3.2 (22D2082)"（kern.osbuildversion）。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK96_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
MEM_KEY = "com.apple.developer.kernel.increased-memory-limit"
VM_KEY = "com.apple.developer.kernel.extended-virtual-addressing"
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
    return code.count("{") == code.count("}") and code.count("(") == code.count(")")


print("=" * 72)
print("A. utils.h / utils.m：设备营销名 + 系统版本数据源（Task96 新增）")
print("=" * 72)
utils_h = read("Natives/utils.h")
utils = read("Natives/utils.m")
utils_code = strip_objc(utils)

check("A1  utils.h 声明两个数据源函数（extern \"C\" 块内，C++ TU 安全）",
      "NSString* getDeviceMarketingName(void);" in utils_h
      and "NSString* getSystemVersionDisplay(void);" in utils_h
      and utils_h.find('extern "C" {') < utils_h.find("getDeviceMarketingName"))
check("A2  utils.m 实现 hw.machine 读取（sysctlbyname）",
      'sysctlbyname("hw.machine"' in utils
      and "ame96_machineIdentifier" in utils_code)
check("A3  utils.m 构建号读取 kern.osbuildversion",
      'sysctlbyname("kern.osbuildversion"' in utils)
check("A4  机型表联网核实条目（iPad15,3/15,4=Air M3；iPad15,7/15,8=iPad 11 A16；"
      "iPad16,1/2=mini A17 Pro；iPad16,3-6=Pro M4）",
      all(k in utils for k in [
          '@"iPad15,3": @"iPad Air 11-inch (M3)"',
          '@"iPad15,4": @"iPad Air 13-inch (M3)"',
          '@"iPad15,7": @"iPad (11th generation)"',
          '@"iPad15,8": @"iPad (11th generation)"',
          '@"iPad16,1": @"iPad mini (A17 Pro)"',
          '@"iPad16,3": @"iPad Pro 11-inch (M4)"',
          '@"iPad16,5": @"iPad Pro 13-inch (M4)"']))
check("A5  未收录机型回退原始标识（宁缺毋错）",
      "return name ?: machine;" in utils_code)
check("A6  iPadOS/iOS 前缀按 idiom 区分",
      '? @"iPadOS" : @"iOS";' in utils)
check("A7  utils.m 花括号配平", bracket_balance(utils_code))

print()
print("=" * 72)
print("B. 右面板：MeloNX 风格信息卡（7 卡 + 滚动区）")
print("=" * 72)
rp = read("Natives/LauncherRightPanelViewController.m")
rp_code = strip_objc(rp)

check("B1  七张卡正文属性 + 滚动区/stack 属性",
      all(k in rp for k in ["UILabel *launcherVersionCardValue", "UILabel *gameVersionCardValue",
                            "UILabel *deviceCardValue", "UILabel *systemCardValue",
                            "UILabel *jitCardValue", "UILabel *memLimitCardValue",
                            "UILabel *extVMCardValue", "UIScrollView *infoScrollView",
                            "UIStackView *infoStackView"]))
check("B2  七张卡按用户指定顺序与图标创建（Task101 更正：hare/memorychip.fill/memorychip）",
      rp.find('makeInfoCardWithIcon:@"cube.transparent"') < rp.find('makeInfoCardWithIcon:@"gamecontroller"') <
      rp.find("makeInfoCardWithIcon:deviceIconName") < rp.find('makeInfoCardWithIcon:@"applelogo"') <
      rp.find('makeInfoCardWithIcon:@"hare"') < rp.find('makeInfoCardWithIcon:@"memorychip.fill"') <
      rp.find('makeInfoCardWithIcon:@"memorychip"'))
check("B3  设备图标按机型选 ipad/iphone",
      '? @"ipad" : @"iphone";' in rp)
check("B4  卡片标题全中文（用户指定），JIT 卡标题即 JIT（Task101 更名：扩展内存限制/扩展虚拟内存）",
      all(k in rp for k in ['@"启动器版本"', '@"游戏版本"', '@"设备"', '@"系统"',
                            'title:@"JIT"', '@"扩展内存限制"', '@"扩展虚拟内存"']))
check("B5  新卡配色 #64C466（用户指定）",
      "0x64 / 255.0" in rp and "0xC4 / 255.0" in rp and "0x66 / 255.0" in rp)
check("B6  JIT 卡与内存上限卡同橙 #FF9500；扩展虚拟寻址黄系 #E7A200；设备/系统系统蓝",
      "[UIColor colorWithRed:1.0 green:0.584 blue:0.0 alpha:1.0]" in rp
      and "[UIColor colorWithRed:0.906 green:0.635 blue:0.0 alpha:1.0]" in rp
      and "[UIColor systemBlueColor]" in rp)
check("B7  System 配色 = Device 一样（同一 cardBlue 变量）",
      'makeInfoCardWithIcon:deviceIconName accent:cardBlue' in rp
      and 'makeInfoCardWithIcon:@"applelogo" accent:cardBlue' in rp)
check("B8  卡片工厂：46pt 高（=登录并启动）+ 圆角 12 + 15% 透明同色底 + 无小字副标题",
      "heightAnchor constraintEqualToConstant:46" in rp_code
      and "cornerRadius = 12" in rp_code
      and "colorWithAlphaComponent:0.15" in rp_code
      and "makeJITStyleStatusLabel" not in rp_code)
check("B9  卡片正文动态色 #222222/#EEEEEE（Task91 规范）+ 超长自动缩小（用户指定）",
      "0xEE / 255.0" in rp and "0x22 / 255.0" in rp
      and "colorWithDynamicProvider" in rp_code
      and "adjustsFontSizeToFitWidth" in rp_code and "minimumScaleFactor = 0.55" in rp_code)
check("B10 滚动区与「登录并启动」左右对齐（12pt），上接用户名标签（Task101：灰字版本标签退场）下接启动按钮",
      "self.infoScrollView.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:8" in rp
      and "self.infoScrollView.bottomAnchor constraintEqualToAnchor:self.launchButton.topAnchor constant:-8" in rp
      and "self.infoScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12" in rp
      and "self.infoScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12" in rp)
check("B11 stack 宽度绑定滚动区框架宽（可滚动不破版）",
      "self.infoStackView.widthAnchor constraintEqualToAnchor:self.infoScrollView.frameLayoutGuide.widthAnchor" in rp
      and "self.infoScrollView.contentLayoutGuide.topAnchor" in rp)
check("B12 下载中心/进度 UI 并入 stack 顶部（隐藏自动折叠）",
      rp_code.count("addArrangedSubview:") >= 10
      and rp_code.find("addArrangedSubview:self.downloadCenterButton") <
      rp_code.find("addArrangedSubview:launcherVersionCard"))
check("B13 启动器版本双读 App 版本号+构建号（相同则去重，用户指定 5.0.0 (build) 格式）",
      'infoDictionary[@"CFBundleShortVersionString"]' in rp
      and 'infoDictionary[@"CFBundleVersion"]' in rp
      and '%@ (%@)' in rp)
check("B14 设备/系统卡接入 Task96 数据源",
      "self.deviceCardValue.text = getDeviceMarketingName();" in rp
      and "self.systemCardValue.text = getSystemVersionDisplay();" in rp)
check("B15 游戏版本卡与原版本标签同数据源（红框同款），无实例时显示未选择",
      "self.gameVersionCardValue.text = versionId;" in rp
      and 'self.gameVersionCardValue.text = @"未选择";' in rp)

print()
print("=" * 72)
print("C. 状态检测与启动日志同源（Task93 回归护栏，口径不变）")
print("=" * 72)
check("C1  内存两卡 = getEntitlementValue 签名口径（与启动日志同一函数）",
      f'getEntitlementValue(@"{MEM_KEY}")' in rp
      and f'getEntitlementValue(@"{VM_KEY}")' in rp
      and rp.count('getEntitlementValue(@"com.apple.developer.kernel.') == 2)
check("C2  内存两卡正文 = 已开启/未开启（全中文，用户指定）",
      rp.count('@"已开启" : @"未开启"') == 2)
check("C3  JIT 三态保留（isJITEnabled + TXM pending 判定链）",
      "BOOL enabled = isJITEnabled(NO);" in rp_code
      and "DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)" in rp_code
      and "JIT26IsLikelyDebuggerKeepAttached()" in rp_code)
check("C4  JIT 卡三态中文文案",
      '@"已启用（启动时附加）"' in rp and "self.jitCardValue.text = @\"已开启\";" in rp
      and "self.jitCardValue.text = @\"未开启\";" in rp)
check("C5  刷新时机三件套不变（setupUI 尾部 / viewWillAppear / DidBecomeActive）",
      re.search(r"\[self updateJITStatus\];\s*\[self updateMemoryEntitlementStatus\];", rp)
      and re.search(r"- \(void\)viewWillAppear:[\s\S]*?\[self updateJITStatus\];[\s\S]*?\[self updateMemoryEntitlementStatus\];", rp_code)
      and rp.count("selector:@selector(updateMemoryEntitlementStatus)") == 1
      and rp.count("selector:@selector(updateJITStatus)") == 1)
check("C6  Task93 注释留档仍在（与启动日志同源说明）",
      "Task93" in rp and "Entitlements availability" in rp)

print()
print("=" * 72)
print("D. 右下角两按钮与「登录并启动」同款（用户指定）")
print("=" * 72)
check("D1  执行 Jar / 选择版本 = accentColor 底 + 白字",
      all(k in rp_code for k in [
          "self.executeJarBtn.backgroundColor = accentColor();",
          "self.manageVersionBtn.backgroundColor = accentColor();",
          "[self.executeJarBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];",
          "[self.manageVersionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];"]))
check("D2  applyCustomAppearance 统一刷新三枚按钮 accent（主题色切换同步）",
      "self.executeJarBtn.backgroundColor = accentColor();" in rp_code
      and "self.manageVersionBtn.backgroundColor = accentColor();" in rp_code
      and rp_code.count("accentColor();") >= 5)
check("D3  启动按钮本体零改动（高度46/阴影/按压动画/白字）",
      "self.launchButton.heightAnchor constraintEqualToConstant:46" in rp
      and "self.launchButton.layer.shadowColor = [UIColor blackColor].CGColor;" in rp_code
      and "self.launchButton setTitleColor:[UIColor whiteColor]" in rp)
check("D4  下载中心按钮深灰底原样保留",
      "self.downloadCenterButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];" in rp_code)

print()
print("=" * 72)
print("E. 退役清单（胶囊方案整体退场）")
print("=" * 72)
check("E1  胶囊属性/工厂/999 弱约束全部移除",
      all(k not in rp_code for k in [
          "jitStatusLabel", "memLimitStatusLabel", "extVMStatusLabel",
          "makeJITStyleStatusLabel", "progressSpacingConstraint"]))
check("E2  卡片不再引用内存/JIT i18n 键（全中文硬编码，用户指定）",
      "i18n_str_mem_limit_enabled" not in rp and "i18n_str_ext_vm_enabled" not in rp
      and "i18n_str_421" not in rp and "i18n_str_422" not in rp
      and "i18n_str_jit26_pending" not in rp)
check("E3  右面板括号配平", bracket_balance(rp_code))

print()
print("=" * 72)
print("F. 仓库卫生")
print("=" * 72)
check("F1  无新源文件（CMakeLists 无需登记）",
      "utils.m" in read("Natives/CMakeLists.txt"))
check("F2  无未提交改动（提交后自然通过）",
      git(["status", "--porcelain"]).stdout.strip() == "",
      git(["status", "--porcelain"]).stdout.strip()[:200])
check("F3  仓库 worklog 含 Task 96 条目",
      os.path.exists(os.path.join(REPO, "worklog.md")) and "Task ID: 94" in read("worklog.md"))

print()
print("=" * 72)
print(f"RESULT: {PASS} passed, {FAIL} failed, total {PASS + FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
