#!/usr/bin/env python3
"""Task161 六案根修验证器。

用户反馈（9c66184 构建，1e6f796 日志）：
  1. "怎么都没有fsr放大和锐化呀连zink都没有了" —— auto 实例不消费 mg 后端键，
     恒解析 libMobileGL（Vulkan 直连，FSR 退休链）。
  2. "第一次启动重启之后壁纸设置中，好像盖了什么东西，所有文字和按钮都看不到，
     但是只有滑块滑动不了" —— Task160 glass backdrop insertSubview 进
     UITableView（view==tableView 的 table 控制器）。
  3. "bing壁纸还是要重启才能静默加载" —— removeGlobalBackground 清空
     currentWindow/currentSplitVC，后续 setBingBackgroundImageAtPath 应用分支
     双 nil 空转。
  4. "外观模式默认跟随系统" —— 默认值 light→auto + 历史默认迁移。
  5. "右边信息栏点击启动器版本，jit和2个内存扩展闪退" —— 深链对折叠分区
     越界 selectRowAtIndexPath。
  6. "26.3遇到光标能正常弹出键盘，而26.2及以下都不行" —— GLFW 路径无文本
     输入协议；T/斜杠 + 开界面启发式自动弹键盘。

用法：python3 scripts/verify_task161.py
"""
import os
import sys

# Task163：ROOT 环境注入（沿用 TASK160_REPO 惯例）——原默认指向另一会话沙箱。
ROOT = os.environ.get('TASK161_REPO', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # Task180: portable default

def rd(rel):
    return open(f"{ROOT}/{rel}", encoding="utf-8", errors="replace").read()

results = []
def check(label, cond):
    results.append((label, bool(cond)))
    print(f"  [{'PASS' if cond else 'FAIL'}] {label}")

print("== A. FSR：auto 渲染器跟随 mg 后端键 ==")
lp = rd("Natives/LauncherPreferences.m")
check("A1 ame_effective_renderer auto 分支：Task161 注释 + ame142_effective_backend_key 消费",
      "Task161（auto 跟随后端键" in lp
      and "NSString *ame161_backend = ame142_effective_backend_key();" in lp)
check("A2 auto 分支 GLES/Mithril → libmobileglues + 存在守卫 + 缺失落回 auto",
      'ame161_backend isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES' in lp
      and 'ame161_backend isEqualToString:@ RENDERER_NAME_MITHRIL' in lp
      and 'return @ RENDERER_NAME_MOBILEGLUES;' in lp)
check("A3 auto 分支 Vulkan 默认语义保持（返回 auto 字符串，旧 MC ANGLE 回退不破坏）",
      '// (3) 关闭 / dylib 缺失：维持 auto（egl_bridge 按版本解析 gl4es/ANGLE）。' in lp
      and "return renderer;" in lp)
check("A4 ame158_mg_mobileglues_mode：auto/无键 profile 跟随后端键（ES 方块回归防线）",
      "BOOL ame161_autoProfile = (![ame158_pr isKindOfClass:NSString.class] ||" in lp
      and "[ame158_pr isEqualToString:@\"auto\"]);" in lp)
check("A5 非 auto 非 mg 的显式选择不受影响（legacy 家族键防御保留）",
      "if (!ame161_autoProfile &&\n        ![ame158_pr isEqualToString:@ RENDERER_KEY_MG]) {" in lp.replace("\r", ""))

print("== A2b. auto 渲染决策矩阵（Python 镜像）==")
def effective(profile_renderer, backend_key, mobileglues_exists=True):
    """镜像 ame_effective_renderer：返回 (结果, 语义说明)。"""
    if profile_renderer == "mg":
        if backend_key in ("libMobileGL-gles.dylib", "libmithril.dylib"):
            return "libmobileglues.dylib" if mobileglues_exists else "libMobileGL.dylib"
        if mobileglues_exists or True:
            return backend_key if backend_key else "libMobileGL.dylib"
    if profile_renderer not in (None, "", "auto"):
        return profile_renderer
    if backend_key in ("libMobileGL-gles.dylib", "libmithril.dylib") and mobileglues_exists:
        return "libmobileglues.dylib"
    return "auto"
cases = [
    # (profile, backend, 期望, 说明)
    (None, "libMobileGL.dylib", "auto", "A2b-1 无键+Vulkan 默认 → auto（现行为保持）"),
    (None, "", "auto", "A2b-2 无键+无后端 → auto"),
    (None, "libMobileGL-gles.dylib", "libmobileglues.dylib", "A2b-3 无键+GLES → MobileGlues+FSR（本修复主场景）"),
    (None, "libmithril.dylib", "libmobileglues.dylib", "A2b-4 无键+4.0 → MobileGlues+FSR（用户当前选择）"),
    ("auto", "libMobileGL-gles.dylib", "libmobileglues.dylib", "A2b-5 显式 auto+GLES → MobileGlues"),
    ("mg", "libMobileGL-gles.dylib", "libmobileglues.dylib", "A2b-6 mg+GLES → MobileGlues（Task158 既有）"),
    ("mg", "libMobileGL.dylib", "libMobileGL.dylib", "A2b-7 mg+Vulkan → libMobileGL（Task154 退休链保持）"),
    ("libOSMesa.8.dylib", "libmithril.dylib", "libOSMesa.8.dylib", "A2b-8 显式 zink 不受后端键干预（zink FSR 保持）"),
]
for prof, be, expect, label in cases:
    got = effective(prof, be)
    check(f"{label}: {got}", got == expect)

def mg_mode(profile_renderer, backend_key):
    """镜像 ame158_mg_mobileglues_mode。"""
    auto_p = profile_renderer in (None, "", "auto")
    if not auto_p and profile_renderer != "mg":
        if profile_renderer not in ("libMobileGL-gles.dylib", "libmithril.dylib"):
            return 0
    if backend_key == "libMobileGL-gles.dylib":
        return 1
    if backend_key == "libmithril.dylib":
        return 2
    return 0
mode_cases = [
    (None, "libMobileGL-gles.dylib", 1, "A2b-9 无键+GLES → mode1（ANGLE3+GL3.2 强制）"),
    (None, "libmithril.dylib", 2, "A2b-10 无键+4.0 → mode2（GL4.0 强制）"),
    (None, "libMobileGL.dylib", 0, "A2b-11 无键+Vulkan → mode0（透传）"),
    (None, "", 0, "A2b-12 无键+空 → mode0"),
    ("libmobileglues.dylib", "libMobileGL-gles.dylib", 0, "A2b-13 独立 MobileGlues 直选 → mode0（用户自有设置）"),
    ("zink", "libmithril.dylib", 0, "A2b-14 非 mg 家族显式 → mode0"),
]
for prof, be, expect, label in mode_cases:
    check(f"{label}: mode={mg_mode(prof, be)}", mg_mode(prof, be) == expect)

print("== B. 壁纸设置页被盖（glass 不进 UITableView）==")
bm = rd("Natives/BackgroundManager.m")
bsv = rd("Natives/BackgroundSettingsViewController.m")
lpv = rd("Natives/LauncherPreferencesViewController.m")
check("B1 table 控制器（view==tableView）glass 挂 backgroundView（Task161 分支）",
      "viewController.view == ((UITableViewController *)viewController).tableView" in bm
      and "ame161_table.backgroundView = ame161_glass;" in bm)
check("B2 非 table 路径保留 insertSubview atIndex:0（Task160 语义延续）",
      bm.count("insertSubview:glass atIndex:0") == 1)
check("B3 ame160 调用移到 makeViewControllerTransparent 末尾（table 分支 backgroundView=nil 之后）",
      "// Task161：模态弹窗页面级毛玻璃底收口到方法末尾" in bm)
check("B4 背景容器 blurView/dimView 显式关交互（触摸拦截保险带）",
      bm.count("blurView.userInteractionEnabled = NO;") >= 2
      and "dimView.userInteractionEnabled = NO;" in bm)
check("B5 壁纸设置页 viewWillAppear 不再 backgroundView=nil（改走单点）",
      "Task161：改走 makeViewControllerTransparent 单点" in bsv)
check("B6 壁纸设置页 reapplyBackgroundEffect 不再清 glass",
      "Task161：makeViewControllerTransparent 末尾的 ame160 会重铺" in bsv)
check("B7 设置页 viewWillAppear/reapply 同口径（不再手写三行）",
      "Task161：改走 makeViewControllerTransparent 单点" in lpv
      and "Task161：不再手动 backgroundView = nil" in lpv)

print("== C. Bing 壁纸需重启（宿主引用不再被清）==")
check("C1 removeGlobalBackground 的 Task161 根修注释在位",
      "Task161（Bing 壁纸“要重启才能加载”根修）：不再清空 currentWindow" in bm)
check("C2 清空两行已删（grep 不得出现独立清空语句）",
      "    self.currentWindow = nil;\n    self.currentSplitVC = nil;\n}" not in bm)
check("C3 applyBackgroundToWindow 的注册语义保留（先设宿主再移除旧容器）",
      "self.currentWindow = window;" in bm and "self.currentSplitVC = nil;" in bm)
check("C4 setBingBackgroundImageAtPath 应用链引用宿主（currentSplitVC/currentWindow 分支）",
      "if (self.currentSplitVC) {\n                [self applyBackgroundToSplitViewController:self.currentSplitVC];" in bm.replace("\r", ""))

print("== D. 外观模式默认跟随系统 ==")
plp = rd("Natives/PLPreferences.m")
sd = rd("Natives/SceneDelegate.m")
check("D1 PLPreferences 默认 ui_theme=auto",
      '@"ui_theme": @"auto",' in plp)
check("D2 显式选择标记键已注册（Setter 硬要求）",
      '@"ui_theme_explicit": @NO,' in plp)
check("D3 SceneDelegate 历史默认迁移（auto/light → dark（Task180 重锚），仅未显式选择设备）",
      "if (!getPrefBool(@\"general.ui_theme_explicit\")) {" in sd
      and "migrated to 'dark'" in sd)
check("D4 显式选择置标记（设置页 pick action）",
      'setPrefBool(@"general.ui_theme_explicit", YES);' in lpv)
check("D5 SceneDelegate 三档映射保持（light/dark/auto）",
      "UIUserInterfaceStyleLight" in sd and "UIUserInterfaceStyleUnspecified" in sd
      and "UIUserInterfaceStyleDark" in sd)

print("== E. 侧边栏信息卡深链闪退 ==")
check("E1 折叠分区先展开（prefSectionsVisibility[s]=YES + reloadSections）",
      "self.prefSectionsVisibility[s] = @YES;" in lpv
      and "reloadSections:[NSIndexSet indexSetWithIndex:s]" in lpv)
check("E2 行数防御（numberOfRows 越界只展开不选中）",
      "ame161_visibleRows" in lpv and "expanded only, no selection" in lpv)
check("E3 闪退机理注释钉住（check_update/jit_enabler/memory_limit_help）",
      "启动器版本卡（check_update）/ JIT 卡（jit_enabler）/" in lpv)

print("== F. 26.2 及以下聊天自动弹键盘 ==")
ib = rd("Natives/input_bridge_v3.m")
uh = rd("Natives/utils.h")
svc = rd("Natives/SurfaceViewController.m")
jl = rd("Natives/JavaLauncher.m")
check("F1 按键侧记录器（T=84/SLASH=53 + 时间窗判定）",
      "BOOL ame161_lastSentKeyWasChatOpener(NSTimeInterval withinSeconds) {" in ib
      and "ame161_lastSentKey != 84 && ame161_lastSentKey != 53" in ib
      and "BOOL ame161_inputPathIsGLFW(void) {" in ib)
check("F2 nativeSendKey 记录按下键（action==1）",
      "if (action == 1) {\n        ame161_lastSentKey = key;" in ib.replace("\r", ""))
check("F3 utils.h 声明（SurfaceViewController 可见）",
      "BOOL ame161_lastSentKeyWasChatOpener(NSTimeInterval withinSeconds);" in uh
      and "BOOL ame161_inputPathIsGLFW(void);" in uh)
check("F4 updateGrabState 消费：仅 GLFW 路径（ame161_inputPathIsGLFW，CI 9b57650 修复 g_sdlWindow static 可见性）+ 1.5s 窗",
      "if (ame161_inputPathIsGLFW()) {" in svc and "ame161_lastSentKeyWasChatOpener(1.5)" in svc)
check("F5 自动弹出标记 + 回游戏自动收起（手动 ⌨ 不受影响）",
      "static BOOL ame161_autoShown = NO;" in svc
      and "grab restored -> auto-shown keyboard dismissed" in svc)
check("F6 26.3 SDL 路径零影响（判定门 ame161_inputPathIsGLFW）",
      "仅 GLFW\n    // 路径（ame161_inputPathIsGLFW，MC ≤26.2）生效" in svc)
check("F7 日志锚点（chat key + ungrab）",
      "Task161: chat key + ungrab -> keyboard auto-shown" in svc)

print("== G. 过时文案更新（防下轮日志误判）==")
check("G1 JavaLauncher auto 警告改写（Task144/161 语义）",
      "renderer 'auto' (mg backend = Vulkan direct / default)" in jl)

print("== H. 括号平衡（字符状态机剥离注释/字符串）==")
import os
def strip_code(src):
    out, i, n = [], 0, len(src)
    state = "code"
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line_comment"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block_comment"; i += 2; continue
            if c == '"':
                state = "string"; i += 1; continue
            if c == "'":
                state = "char"; i += 1; continue
            out.append(c); i += 1
        elif state == "line_comment":
            if c == "\n":
                out.append("\n"); state = "code"
            i += 1
        elif state == "block_comment":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            if c == "\n":
                out.append("\n")
            i += 1
        elif state == "string":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            i += 1
        else:
            if c == "\\":
                i += 2; continue
            if c == "'":
                state = "code"
            i += 1
    return "".join(out)

for f in ["Natives/LauncherPreferences.m", "Natives/BackgroundManager.m",
          "Natives/BackgroundSettingsViewController.m", "Natives/LauncherPreferencesViewController.m",
          "Natives/PLPreferences.m", "Natives/SceneDelegate.m", "Natives/input_bridge_v3.m",
          "Natives/utils.h", "Natives/SurfaceViewController.m", "Natives/JavaLauncher.m"]:
    s = strip_code(rd(f))
    b = s.count("{") - s.count("}")
    p = s.count("(") - s.count(")")
    check(f"H {f}: brace=0 paren=0", b == 0 and p == 0)

failed = [l for l, ok in results if not ok]
print()
print(f"==== RESULT: {'ALL GREEN' if not failed else 'HAS FAILURES'} "
      f"({sum(1 for _, ok in results if ok)} passed, {len(failed)} failed) ====")
if failed:
    for l in failed:
        print(f"  FAILED: {l}")
sys.exit(0 if not failed else 1)
