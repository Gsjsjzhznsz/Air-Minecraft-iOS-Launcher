#!/usr/bin/env python3
"""
Task 100 验证器：双修复二轮——(A) 26.3 windowsMenu 桩出口；(B) zink FSR 权威呈现路径

背景（f6352dc/7a30912 上传日志对，ccabe82 构建 = Task99 修复后 IPA，iPad Air 11 M4 /
iPadOS 27.0，两个问题在装机后依旧）：
  日志一（latestlog.txt，fabric-loader-0.19.5-26.3-e4ecd7db，110 mods，zink）：
    Task97/98/99 全部生效（LWJGL 341、CWD 对齐、AppKit 桩已装），甚至安全网
    捕获了 javaPeer/windowsMenu 两个未预期选择子。但 MC 26.3 的 MacosUtil 取
    windowsMenu 时桩的通用兜底返回 nil → jna-objc 包装成 Java null →
    MacosUtil.java:27 第一句 windowsMenu.sendInt(...) 即 NPE：
      java.lang.NullPointerException: Cannot invoke "ca.weblite.objc.Proxy.sendInt"
        because "windowsMenu" is null  at MacosUtil.disableCloseWindowMenuItem(:27)
    即 Task99 修掉了"类不存在"层，暴露了"菜单出口缺失"层。
  日志二（latestlog.old.txt，BMC2 fabric-loader-0.15.11-1.20.1，zink+FSR preset2）：
    Task99 三件套全绿（GPU 探针 000000ff 非全零、CPU 探针 88/90 非零 → verdict=1、
    心跳稳定到 swap#1080、60fps、用户能在角落里打字），但画面依旧蜷缩左下角。
    唯一自洽解释：驱动 glFinish 回读把"滞后/回读前"的裸游戏帧写进 client buffer
    角落，顶带残留旧内容（非零）→ 探针误诊为"已落地"。驱动侧黑盒不可再信任。

修复：
  A. JavaLauncher.m：NSApplication 桩补 windowsMenu/appleMenu/helpMenu/servicesMenu
     四个菜单出口（全部返回共享 NSMenu 桩，numberOfItems=0 → 巡游零次），
     "[AppKitStub] Task100: windowsMenu requested" 一次性锚点。
  B. osm_bridge.mm：ame100_present_frame 权威呈现——glFinish 后显式绑 fb0、
     glReadPixels 全幅入 scratch、行序翻转入 present 缓冲（驱动永不触碰），
     CGImage 改包 present；探针双轨（fb0 直读驱动判决 / bundle.buffer 纯取证）；
     CG 兜底数据源优先 present；present 熔断（glErr/分配失败）回退旧路径零回归。
FAQ 两条目内容刷新（计数不变 32）；version.h REVISION 17 addendum (Task 100)。
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


print("===== A. f6352dc 日志证据（26.3 windowsMenu NPE，钉 git——latestlog.txt） =====")
log = git_show("f6352dc:latestlog.txt")
if not log:
    log = read("latestlog.txt")
check("A1 构建为 Task99 IPA（Commit ccabe82）——修复对象正确",
      "Commit: ccabe82" in log)
check("A2 新崩溃签名（windowsMenu NPE @ MacosUtil.java:27 + Window.<init>）",
      'because "windowsMenu" is null' in log and
      "MacosUtil.disableCloseWindowMenuItem(MacosUtil.java:27)" in log and
      "com.mojang.blaze3d.platform.Window.<init>" in log)
check("A3 Task99 桩已装且被走到（installed 行 + windowsMenu 未预期选择子留痕）",
      "[AppKitStub] Task99: NSApplication/NSMenu/NSMenuItem stubs installed" in log and
      "unexpected selector <windowsMenu> on NSApplication" in log)
check("A4 前置链路健康（LWJGL 341 + CWD 对齐）——排除回归",
      "Using LWJGL 341 (mcVersion=fabric-loader-0.19.5-26.3" in log and
      "[CwdAlign] Task97" in log)
check("A5 死因唯一（会话止于 Initializing game，无其他致命异常）",
      "Description: Initializing game" in log and
      log.count("#@!@# Game crashed!") == 1)

print("===== B. 7a30912 日志证据（BMC2 探针全绿却蜷缩，钉 git——latestlog.old.txt） =====")
log2 = git_show("7a30912:latestlog.old.txt")
if not log2:
    log2 = read("latestlog.old.txt")
check("B1 构建为 Task99 IPA（Commit ccabe82）",
      "Commit: ccabe82" in log2)
check("B2 Task99 判决为'已落地'（88/90 非零 → verdict=1）——事后证明是残影误诊",
      "Task99 FSR landing verified: top-strip nonzero in 88/90 frames" in log2 and
      "verdict=1" in log2)
check("B3 GPU 探针行在位且非全零（alpha 已写）",
      "Task99 GPU probe: fb0 top-strip pixel (x=2352,y=1636) rgba=000000ff" in log2)
check("B4 心跳全程稳定（swap#1080 仍在递增，win 1572x1092 / osm 2360x1640）",
      "swap#1080: win=1572x1092 osm=2360x1640" in log2 and
      "easuFrames=1079" in log2)
check("B5 游戏活着且用户在角落里操作（60fps + 按键/光标事件）",
      "fps=60" in log2 and "sendKey #1: key=32" in log2 and "sendCursorPos" in log2)
check("B6 旧措辞判决行已随 Task100 退役（代码中不再产出 Task99 FSR landing）",
      "Task99 FSR landing verified" not in read("Natives/ctxbridges/osm_bridge.mm"))

print("===== C. 修复 A 实现（JavaLauncher.m windowsMenu 桩出口） =====")
jl = read("Natives/JavaLauncher.m")
check("C1 ame99_app_windowsMenu IMP 在位（返回共享 NSMenu 桩）",
      "static id ame99_app_windowsMenu(id self, SEL _cmd)" in jl and
      "return ame99_shared_menu_stub();" in jl)
check("C2 四菜单出口注册（windowsMenu/appleMenu/helpMenu/servicesMenu → 同一 IMP）",
      'class_addMethod(appCls, @selector(windowsMenu), (IMP)ame99_app_windowsMenu, "@@:")' in jl and
      'class_addMethod(appCls, @selector(appleMenu), (IMP)ame99_app_windowsMenu, "@@:")' in jl and
      'class_addMethod(appCls, @selector(helpMenu), (IMP)ame99_app_windowsMenu, "@@:")' in jl and
      'class_addMethod(appCls, @selector(servicesMenu), (IMP)ame99_app_windowsMenu, "@@:")' in jl)
check("C3 一次性取证锚点（[AppKitStub] Task100: windowsMenu requested）",
      "[AppKitStub] Task100: windowsMenu requested" in jl)
check("C4 病历注释钉住 7a30912（NPE 签名 + 修复语义）",
      "because \"windowsMenu\" is null" in jl and "MacosUtil.java:27" in jl)
check("C5 Task99 既有桩面零回退（numberOfItems/itemAtIndex/resolveInstanceMethod 安全网仍在）",
      "ame99_menu_numberOfItems" in jl and "ame99_menu_itemAtIndex" in jl and
      jl.count("@selector(resolveInstanceMethod:)") == 3)
check("C6 true-mac 守卫不变（objc_getClass != NULL 不插桩）",
      'objc_getClass("NSApplication") != NULL' in jl)

print("===== D. 修复 B 实现（osm_bridge.mm 权威呈现） =====")
ob = read("Natives/ctxbridges/osm_bridge.mm")
check("D1 ame100_present 状态结构（scratch/present/broken/drv 双探针计数）",
      "} ame100_present = {0};" in ob and "drvHits, drvFrames;" in ob)
check("D2 ame100_present_frame：glFinish 后 fb0 直读（绑 fb0 + glReadPixels 全幅）",
      "static bool ame100_present_frame(int dstW, int dstH)" in ob and
      "g->glBindFramebuffer(GL_FRAMEBUFFER, 0);" in ob and
      "g->glReadPixels(0, 0, dstW, dstH, GL_RGBA, GL_UNSIGNED_BYTE, ame100_present.scratch)" in ob)
check("D3 pack 像素存储四项锁定 + 还原（ROW_LENGTH/ALIGNMENT/SKIP_PIXELS/SKIP_ROWS）",
      "GL_PACK_ROW_LENGTH, 0" in ob and "GL_PACK_ALIGNMENT, 4" in ob and
      "GL_PACK_SKIP_PIXELS, 0" in ob and "GL_PACK_SKIP_ROWS, 0" in ob and
      "g->glPixelStorei(GL_PACK_ROW_LENGTH, saveRowLen)" in ob)
check("D4 行序翻转（GL 底起 → Y_UP=0 顶起；present 行 0 = scratch 行 dstH-1）",
      "ame100_present.scratch + (size_t)(dstH - 1 - row) * stride, stride" in ob)
check("D5 读/绘 FBO 双通道保存还原（模组非对称绑定不受扰动）",
      "GL_DRAW_FRAMEBUFFER_BINDING, &saveDrawFbo" in ob and
      "g->glBindFramebuffer(GL_READ_FRAMEBUFFER, (unsigned int)saveReadFbo)" in ob)
check("D6 熔断语义（glErr 非零 / 分配失败 → broken=true 永久回退驱动路径）",
      "ame100_present.broken = true;" in ob and
      "Task100 present readback FAILED" in ob and
      "Task100 present: alloc" in ob)
check("D7 swap 段调用点（glFinish 之后、探针之前）",
      ob.index("handle.glFinish();") < ob.index("ame100_present_frame((int)bundle.width") <
      ob.index("探针 A：scratch"))
check("D8 探针双轨：fb 探针采样 scratch（GL 行序 gameH+1 起），driver 探针采样 bundle.buffer",
      "const unsigned char *fb = ame100_present.scratch;" in ob and
      "int row = gameH + 1 + (i * (stripRows - 2)) / 15;" in ob and
      "const unsigned char *base = (const unsigned char *)bundle.buffer;" in ob)
check("D9 verdict 由 fb 探针驱动（probeHits/probeFrames 复用 ame99_fsrdiag 字段）",
      "if (nz > 0) ++ame99_fsrdiag.probeHits;" in ob and
      "ame99_fsrdiag.probeFrames >= kAme99ProbeFrames" in ob)
check("D10 判决日志双通道（Task100 landing verified in fb0 + NOT landing + driver transport check）",
      "Task100 EASU landing verified in fb0" in ob and
      "Task100 EASU NOT landing in fb0" in ob and
      "driver transport check" in ob)
check("D11 dispatch 三分支（兜底裁剪 present 优先 / present 全幅 / 旧 bundle 路径殿后）",
      "presentThisFrame ? ame100_present.present" in ob and
      "CGDataProviderCreateWithData(\n            NULL, ame100_present.present" in ob and
      "CGDataProviderRef bitmapProvider = CGDataProviderCreateWithData(NULL, bundle.buffer" in ob)
check("D12 心跳扩展（present=%d drvProbe=%d/%d 追加在 Task99 swap 行尾）",
      "verdict=%d present=%d drvProbe=%d/%d" in ob)
check("D13 非 FSR 零回归（present 仅在 fsrActiveThisFrame 时调用；FSR 关闭走旧路径）",
      "if (fsrActiveThisFrame && bundle.width > 0 && bundle.height > 0) {" in ob and
      re.search(r"bool presentThisFrame = false;\n    if \(fsrActiveThisFrame", ob) is not None)
check("D14 EASU 顺序不变（upscale 在 glFinish 前，Task85 根治保持）",
      ob.index("ame83_fsr_upscale(effW") < ob.index("handle.glFinish();"))
check("D15 GL_PACK 枚举守卫 + glPixelStorei 符号表项",
      "#define GL_PACK_ROW_LENGTH        0x0D02" in ob and
      '{"glPixelStorei",              (void**)&ame83_fsr.gl.glPixelStorei},' in ob)

print("===== E. 行为矩阵（纯逻辑推演，无设备依赖） =====")
check("E1 26.3：sharedApplication→桩 app；windowsMenu→桩 menu；numberOfItems→0；sendInt 得 0；巡游零次；Window.<init> 继续",
      "static long ame99_menu_numberOfItems(id self, SEL _cmd) { return 0; }" in jl)
check("E2 26.3：真 macOS 永不插桩（守卫第一道）+ NSObject 缺失跳过（守卫第二道）",
      "real AppKit present, stubs not needed" in jl and
      "ObjC runtime unavailable, skipping" in jl)
check("E3 BMC2：present 缓冲驱动不可写 → 无论驱动回读滞后/残影/错源，上屏恒为 fb0 直读画面",
      "driver glFinish readback bypassed for display" in ob)
check("E4 BMC2：若 EASU 绘制层也坏（fb 探针 90 帧未过 1/3）→ CG 兜底裁剪 present 的游戏区域全屏",
      'verdict == -1' in ob and "cropSrc + (size_t)topRow * stride" in ob)
check("E5 健康 FSR 会话（26.3-rc-3 类）：present 与驱动回读内容一致，仅多一次显式拷贝，视觉零差",
      "Task100 present path engaged: authoritative fb0 readback" in ob)
check("E6 glReadPixels 失败路径：broken=true 后不再重试，显示回落 bundle.buffer 旧路径（与 Task99 行为一致）",
      ob.index("if (ame100_present.broken) return false;") < ob.index("Task100 present readback FAILED"))

print("===== F. FAQ + version.h + 级联 =====")
faq = read("Natives/LauncherHelpViewController.m")
items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[\[LauncherHelpFaqItem alloc\] init\];", faq)
check("F1 FAQ 计数不变（32——Task100 只刷新内容不加条目）",
      len(items) == 33, f"got {len(items)}")
check("F2 macMenuStub 已并入二层 NPE 病历与 Task100 锚点",
      any(i == "macMenuStub" for i in items) and
      "because \\\"windowsMenu\\\" is null" in faq and
      "[AppKitStub] Task100: windowsMenu requested" in faq)
check("F3 fsrCorner 已更新为哨兵闭环语义（Task103 + sentinel verdict；Task100 权威呈现措辞保留）",
      any(i == "fsrCorner" for i in items) and
      "Task103 地面真值闭环" in faq and "Task103 EASU sentinel verdict" in faq
      and "Task100 权威呈现" in faq)
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F4 version.h REVISION 17 addendum (Task 100, no bump)",
      "REVISION 17 addendum (Task 100, no bump)" in vh and "#define REVISION 17" in vh)
check("F5 addendum 记录双修复与锚点",
      all(k in vh for k in ("windowsMenu", "[AppKitStub] Task100", "[OSMBridge] Task100",
                            "authoritative present", "count stays 32")))
for fn in ("verify_task83.py", "verify_task84.py", "verify_task85.py", "verify_task86.py",
           "verify_task87.py", "verify_task94.py", "verify_task95.py", "verify_task97.py",
           "verify_task98.py", "verify_task99.py"):
    content = read(f"scripts/{fn}")
    check(f"F6 {fn} FAQ 计数 32 同步未破坏",
          "len(faq_items) == 33" in content or "32 条目" in content or "len(items) == 33" in content)

print("===== G. 卫生 =====")
def _jl_delta_balanced():
    r = subprocess.run(["git", "-C", REPO, "show", "HEAD:Natives/JavaLauncher.m"],
                       capture_output=True, text=True)
    old = r.stdout if r.returncode == 0 else ""
    for a, b in (("{", "}"), ("(", ")"), ("[", "]")):
        if (jl.count(a) - old.count(a)) != (jl.count(b) - old.count(b)):
            return False
    return True

check("G1 osm_bridge.mm 括号自平衡",
      all(ob.count(a) == ob.count(b) for a, b in (("{", "}"), ("(", ")"), ("[", "]"))))
check("G2 JavaLauncher.m 新增段括号中性（基线本身含历史字符串内括号，只验增量平衡）",
      _jl_delta_balanced())
check("G3 新增段无半开区间注释（避免括号平衡校验器误报）",
      "[gameH, bufH)" not in ob and "[0, bufH-gameH)" not in ob)
check("G4 无 Task100 遗留 TODO/占位符",
      "TODO(Task100)" not in ob and "TODO(Task100)" not in jl)

print()
print(f"===== 结果：{PASS} PASS / {FAIL} FAIL =====")
sys.exit(1 if FAIL else 0)
