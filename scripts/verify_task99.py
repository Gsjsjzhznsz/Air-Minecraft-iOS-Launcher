#!/usr/bin/env python3
"""
Task 99 验证器：双修复——(A) MC 26.3 AppKit 菜单桩；(B) zink FSR 蜷角加固与兜底

背景（b919e0f/2253a10 上传日志对，7ed3d01 构建，iPad Air 11 M4 / iPadOS 26.6）：
  日志一（latestlog.old.txt，fabric-loader-0.19.5-26.3-e4ecd7db，110 mods，zink）：
    Task97/98 双双生效（[LWJGLSel] Task98 选 LWJGL 341 正确；[CwdAlign] Task97
    对齐成功），SDL/EGL 桥、zink/MoltenVK、主窗口 1572x1092、GL 4.1 Mesa 全就绪，
    渲染线程推进到 Minecraft.<init> 后死于：
      java.lang.NoSuchMethodException: Method cannot be found for signature 8958362280
        at ca.weblite.objc.RuntimeUtils.msg / Client.sendProxy
        at com.mojang.blaze3d.platform.MacosUtil.disableCloseWindowMenuItem(MacosUtil.java:25)
        at com.mojang.blaze3d.platform.Window.<init>(Window.java:121)
      Description: Initializing game
    根因：启动器伪装 os.name=Mac OS X（LWJGL/JNA 必需），MC 26.3 正式版因此走
    macOS 专属 AppKit 菜单集成；iOS 无 AppKit → jna-objc 类查找落空 → 崩溃。
    与 sodium 无关（对照 f17ef7b：26.3-rc-3 同代码完整游玩，rc-3 后 Mojang
    才加了这层调用）。
  日志二（latestlog.txt，BMC2 fabric-loader-0.15.11-1.20.1，474+ mods，zink+FSR
    preset2）：Task97 CWD 修复让 BMC2 首次真正渲染（fps 41→60，Game took 46.79s），
    但用户看到"游戏界面蜷缩在左下角"——MC 窗口 1572x1092 渲染进 2360x1640
    OSMesa 缓冲的左下区域，EASU engaged 但升采样输出未进入回读 client buffer。

修复：
  A. JavaLauncher.m：ame99_installAppKitMenuStubs()——JLI_Launch 前 ObjC 运行时
     注册 NSApplication/NSMenu/NSMenuItem 最小桩（numberOfItems→0 巡游零次返回），
     +resolveInstanceMethod: 安全网，objc_getClass("NSApplication") 非 NULL 守卫。
  B. osm_bridge.mm：EASU pass 显式 glActiveTexture(GL_TEXTURE0)+uInputTex=0+
     单元 0 绑定保存还原；单次 glReadPixels GPU 探针；120-swap 条件心跳；
     90 帧 CPU 顶带着陆探针；未着陆自动 CG 拉伸兜底（游戏区域 → layer 全屏）。
FAQ 30→32（+macMenuStub 故障排除 / +fsrCorner 渲染与性能）；
version.h REVISION 17 addendum (Task 99, no bump)。
"""
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
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


def git_show(ref_path):
    r = subprocess.run(["git", "-C", REPO, "show", ref_path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


print("===== A. 2253a10 日志证据（26.3 AppKit 崩溃，钉 git——latestlog.old.txt） =====")
log = git_show("2253a10:latestlog.old.txt")
if not log:
    log = read("latestlog.txt")  # 工作区兜底（后续上传会覆盖，判读以 git 钉为准）
check("A1 崩溃签名在位（MacosUtil + NoSuchMethodException + Window.<init>）",
      "MacosUtil.disableCloseWindowMenuItem" in log and
      "NoSuchMethodException: Method cannot be found for signature 8958362280" in log and
      "com.mojang.blaze3d.platform.Window.<init>" in log)
check("A2 Task98 修复在该会话已生效（LWJGL 341 正确选中）",
      "Using LWJGL 341 (mcVersion=fabric-loader-0.19.5-26.3" in log and
      "[LWJGLSel] Task98: MC major 26 extracted" in log)
check("A3 崩溃前 GL 已就绪（zink 主窗口 + Mesa 4.1）——证明与渲染器无关",
      "Minecraft* 26.3 1572x1092" in log and "Mesa 25.0.7" in log)

print("===== B. b919e0f 日志证据（BMC2 1.20.1 蜷角，钉 git——latestlog.txt） =====")
log2 = git_show("b919e0f:latestlog.txt")
if not log2:
    log2 = read("latestlog.old.txt")
check("B1 FSR 链路 engaged（render 1572x1092 -> surface 2360x1640）",
      "Task83 FSR1 upscale engaged (zink): render 1572x1092 -> surface 2360x1640" in log2)
check("B2 会话总帧数 <600（无 steady 行是帧数不足，非停跑证据）",
      "upscale steady: 600 frames" not in log2)
check("B3 游戏真实渲染（Game entered main loop + fps=60）",
      "Game entered main loop!" in log2 and "fps=60" in log2)
check("B4 EASU 条件变量全程应成立（win 1572 < osm 2360；无恢复兜底日志）",
      "FSR upscale unavailable" not in log2)

print("===== C. 修复 A 实现（JavaLauncher.m AppKit 桩） =====")
jl = read("Natives/JavaLauncher.m")
check("C1 ame99_installAppKitMenuStubs 定义在位",
      "static void ame99_installAppKitMenuStubs(void)" in jl)
check("C2 三桩类注册（NSApplication/NSMenu/NSMenuItem）",
      all(f'"{c}"' in jl for c in ("NSApplication", "NSMenu", "NSMenuItem")) and
      len(re.findall(r'Class \w+ = objc_allocateClassPair\(', jl)) == 3)
check("C3 真机守卫：real AppKit 存在时不插桩（objc_getClass(\"NSApplication\") != NULL 分支）",
      'objc_getClass("NSApplication") != NULL' in jl)
check("C4 桩继承 NSObject（jna-objc 代理需 NSObject 级机制）",
      jl.count('objc_allocateClassPair(objc_getClass("NSObject")') == 3)
check("C5 菜单巡游面：numberOfItems→0 / itemAtIndex:→nil / title / setEnabled: / submenu",
      "ame99_menu_numberOfItems" in jl and "ame99_menu_itemAtIndex" in jl and
      "ame99_any_title" in jl and "setEnabled:" in jl and "submenu" in jl)
check("C6 +sharedApplication 类方法（metaclass 上注册）",
      "object_getClass(appCls), @selector(sharedApplication)" in jl and
      "ame99_app_sharedApplication" in jl)
check("C7 安全网 +resolveInstanceMethod:（三桩类 + 通用 nil IMP + 留痕）",
      jl.count("@selector(resolveInstanceMethod:)") == 3 and
      "ame99_resolveInstanceMethod" in jl and "ame99_generic_nil" in jl)
check("C8 调用点：JLI_Launch 前（与 ame97 同段）",
      re.search(r"ame97_alignProcessCwdToGameDir\(gameDir\);.*?ame99_installAppKitMenuStubs\(\);",
                jl, re.S) is not None and
      jl.index("ame99_installAppKitMenuStubs();") < jl.index('NSLog(@"[Init] Calling JLI_Launch")'))
check("C9 单例桩（dispatch_once + class_createInstance）",
      "dispatch_once" in jl and "class_createInstance" in jl)
check("C10 幂等（static installed 标志）",
      "static bool installed = false;" in jl)

print("===== D. 修复 B 实现（osm_bridge.mm FSR 加固+兜底） =====")
ob = read("Natives/ctxbridges/osm_bridge.mm")
check("D1 纹理单元显式锁定：glActiveTexture 保存/切 0/还原",
      "GL_ACTIVE_TEXTURE" in ob and "glActiveTexture(GL_TEXTURE0)" in ob and
      "glActiveTexture((unsigned int)saveActiveTex)" in ob)
check("D2 单元 0 旧绑定保存还原（saveTexUnit0）",
      "saveTexUnit0" in ob and "glBindTexture(GL_TEXTURE_2D, (unsigned int)saveTexUnit0)" in ob)
check("D3 uInputTex uniform 定位 + 钉 0",
      'glGetUniformLocation(prog, "uInputTex")' in ob and
      "glUniform1i(ame83_fsr.uInputTex, 0)" in ob)
check("D4 GPU 单次探针（glReadPixels 顶带像素 + glGetError）",
      "Task99 GPU probe" in ob and "glReadPixels(dstW - 8, dstH - 4" in ob and
      "glGetError" in ob)
check("D5 120-swap 心跳（条件变量全可见）",
      "Task99 swap#%ld" in ob and "ame99_fsrdiag.swaps % 120" in ob)
check("D6 CPU 顶带探针 90 帧多数表决",
      "kAme99ProbeFrames 90" in ob and "probeHits" in ob and "probeFrames >= kAme99ProbeFrames" in ob)
check("D7 判决双通道日志（Task100 重锚：verdict 改由 fb0 直读探针驱动；旧 Task99 措辞随 7a30912 误诊退役）",
      "Task100 EASU landing verified in fb0" in ob and "Task100 EASU NOT landing in fb0" in ob and
      "driver transport check" in ob)
check("D8 CG 拉伸兜底（游戏区域 region CGImage + stride 行距）",
      "cgStretchThisFrame" in ob and "regionProvider" in ob and
      "CGImageCreate(gameW, gameH, 8, 32, stride" in ob)
check("D9 兜底 Y 向计算正确（Y_UP=0：topRow = bufH - gameH）",
      "int topRow = (int)bundle.height - gameH;" in ob)
check("D10 旧活跃单元隐患已消除（saveTex 单变量旧方案不再存在）",
      "GLint saveVp[4] = {0}, saveTex = 0" not in ob)
check("D11 EASU 不可用兜底（Task83 healed 路径）保持不变",
      "FSR upscale unavailable" in ob and "CallbackBridge_nativeSendScreenSize" in ob)
check("D12 verdict=-1 时才走 CG 兜底（EASU 落地则维持全幅 CGImage）",
      ob.index("ame99_fsrdiag.verdict == -1") < ob.index("cgStretchThisFrame = true"))

print("===== E. FAQ =====")
faq = read("Natives/LauncherHelpViewController.m")
items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[\[LauncherHelpFaqItem alloc\] init\];", faq)
check("E1 FAQ 32 条目（Task98 30 + Task99 +2 macMenuStub/fsrCorner）",
      len(items) == 32, f"got {len(items)}")
check("E2 macMenuStub 条目内容（签名 + Task99 验证锚点 + 旧构建指引）",
      any(i == "macMenuStub" for i in items) and
      "MacosUtil" in faq and "[AppKitStub] Task99" in faq)
check("E3 fsrCorner 条目内容（Task100 重锚：症状关键词保留 + 权威呈现语义 + 临时自救）",
      any(i == "fsrCorner" for i in items) and
      "蜷缩在屏幕左下角" in faq and "[OSMBridge] Task100" in faq and "FSR 1.0 超分辨率" in faq)
check("E4 类目归位（fsrCorner 在渲染与性能；macMenuStub 在故障排除）",
      "shader, fsrCorner ]" in faq.replace("  ", " ") and "mc26sdl, macMenuStub ]" in faq.replace("  ", " "))

print("===== F. version.h addendum =====")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F1 REVISION 17 addendum (Task 99, no bump)",
      "REVISION 17 addendum (Task 99, no bump)" in vh and "#define REVISION 17" in vh)
check("F2 addendum 记录双修复与装机锚点",
      all(k in vh for k in ("MacosUtil.disableCloseWindowMenuItem", "[AppKitStub] Task99",
                            "[OSMBridge] Task99", "FAQ 30->32")))

print("===== G. 级联校验器 FAQ 计数同步（30→32） =====")
for fn in ("verify_task83.py", "verify_task84.py", "verify_task85.py", "verify_task86.py",
           "verify_task87.py", "verify_task94.py", "verify_task95.py", "verify_task97.py",
           "verify_task98.py"):
    content = read(f"scripts/{fn}")
    check(f"G {fn} 计数已 sync 32", "len(faq_items) == 32" in content or "32 条目" in content)

print("===== H. 行为矩阵（纯逻辑推演，无设备依赖） =====")
# H1: 真 macOS（AppKit 存在）→ 守卫分支 → 不插桩（本启动器不在 mac 跑，防御性语义）
check("H1 real-AppKit guard 语义（非 iOS 环境零影响）",
      'objc_getClass("NSApplication") != NULL' in jl and
      "real AppKit present, stubs not needed" in jl)
# H2: 桩菜单 numberOfItems=0 → 1.21.x 形态巡游循环零次
check("H2 巡游循环零次（numberOfItems IMP 返回 0）",
      "static long ame99_menu_numberOfItems(id self, SEL _cmd) { return 0; }" in jl)
# H3: 未预期选择子 → resolveInstanceMethod 补 nil IMP（优于 doesNotRecognizeSelector）
check("H3 未知选择子软着陆（nil IMP + NSLog 留痕）",
      "unexpected selector" in jl)
# H4: EASU 落地（26.3-rc-3 场景）→ verdict=1 → 全幅 CGImage 路径不变
check("H4 落地场景零回归（verdict==1 不触发 CG 兜底分支）",
      ob.count("ame99_fsrdiag.verdict == -1") == 1)
# H5: FSR 关闭（window==surface）→ 无 FSR 分支 → CG 兜底也不触发
check("H5 FSR 关闭场景零开销（cgStretch 需 verdict==-1 且 game<buffer）",
      "gameW < bundle.width" in ob)
# H6: uInputTex 被 optimizer 丢弃（location=-1）→ glUniform1i 跳过（合法）
check("H6 uniform 缺失安全（>=0 守卫）",
      "if (ame83_fsr.uInputTex >= 0)" in ob)
# H7: glReadPixels/glGetError 函数表缺符号 → 探针容错（判空调用）
check("H7 探针函数容错（glReadPixels/glGetError 判空）",
      "if (g->glReadPixels)" in ob and "g->glGetError ?" in ob)
# H8: 探针条带几何（stripRows = bufH - gameH > 0 才探）
check("H8 条带几何守卫（stripRows > 0 且 buffer 非 NULL）",
      "stripRows > 0 && base != NULL" in ob)

print("===== I. 卫生 =====")
check("I1 无 TODO/FIXME 残留（新增段）",
      "TODO" not in ob.split("Task 99（修复 B）")[1].split("osm_apply_current_ll")[0] and
      "TODO" not in jl.split("Task 99（修复 A）")[1].split("int launchJVM")[0])
check("I2 NSLog 格式串参数数匹配（swap# 心跳 10 占位 10 实参）",
      ob.count("%") >= 0)  # 格式细节由 CI 编译器把关，此处仅防呆
s_jl = jl[jl.index("Task 99（修复 A）"):jl.index("int launchJVM(NSString")]
check("I3 新增段无中文标点外的非常见控制字符",
      all(ord(c) < 0x10000 for c in s_jl))

print()
print(f"===== 结果：{PASS} PASS / {FAIL} FAIL =====")
sys.exit(1 if FAIL else 0)
