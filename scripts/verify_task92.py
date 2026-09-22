#!/usr/bin/env python3
"""
Task 92 验证器：StikDebug JIT26 脚本兼容性加固

背景（用户提问：StikDebug 有 JS 脚本功能，部分模拟器必须用特定 JS 才能开启
JIT，Amethyst 用特定 JS 是否兼容性更高）：

调研结论：
  - StikDebug 的 JS = 调试器端脚本，经 GDB 远程协议（get_pid/send_command/
    prepare_memory_region/log）应答目标 App 的 brk 陷阱，为其准备可执行内存
    （TXM 时代 JIT）。各家约定不同：UTM/Dolphin legacy = brk 0x69(x0=地址,
    x1=大小)；Geode 0x69/0x70/0x71；Amethyst = Universal 脚本（brk 0xf00d
    x16 分发 + brk 0x68 运行时注入）+ 本仓库 Extension（legacy 0x69 覆写为
    x0=大小/返回值=分配地址，commands 3/4 = SetDetachAfterFirstBr/
    PrepareRegionForPatching）。用错脚本 = 协议不配 = 崩溃/垃圾返回值。
  - 上游 StikDebug/StikDebug 已按应用名（"Amethyst"）自动分配内置
    universal.js（AutoScriptAssignments.swift）；旧侧载版内置名
    Amethyst-MeloNX.js。弹窗里旧括号说明已过时。
  - 本仓库打包的 UniversalJIT26.js（2025-10-10）落后上游 universal.js
    （2026-29-03）一个防回归改动：continuesWithSignal 开关。

修复项：
  A. UniversalJIT26.js 字节级同步上游 2026-29-03（协议不变，仅加
     continuesWithSignal 直通开关）。
  B. main.m 预启动主动导出 UniversalJIT26.js 到 $POJAV_HOME/Documents——
     此前该副本只在"检测到 legacy 脚本"的失败路径补拷，用户得先失败一次
     才能在 StikDebug Assign Script 里选到文件；改为每次启动导出
     （内容一致跳过写盘）。
  C. JavaLauncher.m 两处 legacy 脚本报错弹窗更新：新版 StikDebug 按应用名
     自动分配（升级最简单）；旧侧载版同名内置 Amethyst-MeloNX.js；手动
     Assign Script → Documents/UniversalJIT26.js（启动时自动导出）。

协议回归护栏：Task91 的 SIGTRAP 安全网、0x690000E0 哨兵、Extension 注入、
SetDetachAfterFirstBr、stikjit:// script-data 通路全部不得改动。
"""
import os
import re
import subprocess
import sys

REPO = os.environ.get("TASK92_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
UPSTREAM = os.environ.get("TASK92_UPSTREAM", "/home/z/my-project/Amethyst-iOS-MyRemastered/universal.js")
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


print("=" * 72)
print("A. UniversalJIT26.js 同步上游 universal.js (2026-29-03)")
print("=" * 72)
js = read("Natives/resources/UniversalJIT26.js")

check("A1  头部日期更新为上游 2026-29-03",
      "last updated 2026-29-03" in js,
      "未找到 'last updated 2026-29-03'")
check("A2  新增 continuesWithSignal 开关（默认 true）",
      re.search(r"let continuesWithSignal = true;", js) is not None)
check("A3  信号直通块被 if (continuesWithSignal) 包裹",
      (lambda i_flag, i_vcont: i_flag != -1 and i_vcont > i_flag and i_vcont - i_flag < 400)
      (js.find("if (continuesWithSignal)"), js.find("vCont;S${signum}:${tid}")))
check("A4  协议常量未变 CMD_DETACH=0/CMD_PREPARE_REGION=1/CMD_NEW_BREAKPOINTS=2",
      "const CMD_DETACH = 0;" in js and "const CMD_PREPARE_REGION = 1;" in js
      and "const CMD_NEW_BREAKPOINTS = 2;" in js)
check("A5  legacyCommands 仍含 0x68/0x69/0xf00d 三档",
      "[0x68]: JIT26NewBreakpoints" in js and "[0x69]: JIT26HandleBrk0x69" in js
      and "[0xf00d]: JIT26HandleBrk0xf00d" in js)
check("A6  _M<size>,rx 调试器侧 RX 分配命令仍在",
      "_M${x1.toString(16)},rx" in js)
check("A7  runScriptAndCapture（BreakSendJITScript 注入通道）仍在",
      "function runScriptAndCapture(scriptText)" in js and "eval(scriptText)" in js)
check("A8  legacy 0x69 默认错误返回 E0000069 仍在",
      "P0=E0000069" in js)
check("A9  与上游副本字节一致（本地缓存存在时）",
      (not os.path.exists(UPSTREAM)) or open(UPSTREAM, "rb").read() ==
      open(os.path.join(REPO, "Natives/resources/UniversalJIT26.js"), "rb").read())

print()
print("=" * 72)
print("B. main.m 预启动主动导出脚本到 Documents")
print("=" * 72)
mm = read("Natives/main.m")
mm_s = strip_objc(mm)

check("B1  新增 init_exportJIT26Script() 函数",
      "void init_exportJIT26Script(void)" in mm)
check("B2  从 bundle 读取 UniversalJIT26.js",
      'pathForResource:@"UniversalJIT26" ofType:@"js"' in mm)
check("B3  目标为 $POJAV_HOME/UniversalJIT26.js",
      '%s/UniversalJIT26.js' in mm and 'getenv("POJAV_HOME")' in mm)
check("B4  内容一致时跳过写盘（isEqualToData 短路）",
      "isEqualToData:existing" in mm or "isEqualToData" in mm_s)
check("B5  createFileAtPath 落盘",
      "createFileAtPath:dst contents:bundleData" in mm)
check("B6  bundle 缺脚本时跳过（missing from bundle 日志）",
      "UniversalJIT26.js missing from bundle" in mm)
check("B7  函数带 Task92 标记注释",
      "Task92" in mm and "init_exportJIT26Script" in mm)
check("B8  调用点位于 init_setupCustomControls() 之后",
      re.search(r"init_setupCustomControls\(\);\s*\n\s*init_exportJIT26Script\(\);", mm) is not None)
check("B9  导出动作有 latestlog 日志（Exported Universal JIT script）",
      "Exported Universal JIT script to Documents" in mm)
check("B10 导出在 JIT 自启用分支之前（POJAV_HOME 已就绪）",
      mm.find("init_exportJIT26Script();") < mm.find("no-sandbox: YES, trying to enable JIT"))

print()
print("=" * 72)
print("C. JavaLauncher.m legacy 脚本报错弹窗文案更新（×2）")
print("=" * 72)
jl = read("Natives/JavaLauncher.m")
new_dialog = jl.count("On current StikDebug builds it is auto-assigned to Amethyst by app name")
old_dialog = jl.count('switch to Universal JIT script. To import it, long-press')

check("C1  旧句式 'To import it, long-press' 已清除",
      old_dialog == 0, f"残留 {old_dialog} 处")
check("C2  两处弹窗均更新为新文案",
      new_dialog == 2, f"仅 {new_dialog} 处")
check("C3  提及按应用名自动分配（auto-assigned by app name）",
      "auto-assigned to Amethyst by app name" in jl)
check("C4  旧侧载版内置名 Amethyst-MeloNX.js 保留为兼容说明",
      "older sideloaded builds bundled the same script as Amethyst-MeloNX.js" in jl)
check("C5  保留 Assign Script 手动指派指引（×2）",
      jl.count('\\"Assign Script\\"') >= 2)
check("C6  指明脚本来自 Documents 且启动时自动导出（×2）",
      jl.count("from Amethyst's Documents directory (exported automatically at every startup)") == 2)
check("C7  建议优先升级 StikDebug（easiest fix）",
      "updating StikDebug is the easiest fix" in jl)

print()
print("=" * 72)
print("D. JIT26 协议回归护栏（Task88/90/91 成果不受影响）")
print("=" * 72)
utils = read("Natives/utils.m")
utils_h = read("Natives/utils.h")

check("D1  JIT26CreateRegionLegacySafe 仍在 utils.m",
      "void* JIT26CreateRegionLegacySafe(size_t len)" in utils)
check("D2  SIGTRAP 安全网实现完整（sigsetjmp/siglongjmp）",
      "sigjmp_buf g_jit26TrapEnv" in utils and "siglongjmp(g_jit26TrapEnv, 1)" in utils
      and "sigaction(SIGTRAP, &sa, &oldsa)" in utils)
check("D3  utils.h 仍声明 JIT26CreateRegionLegacySafe",
      "void* JIT26CreateRegionLegacySafe(size_t len);" in utils_h)
check("D4  JavaLauncher 两处调用 LegacySafe",
      read("Natives/JavaLauncher.m").count("JIT26CreateRegionLegacySafe(getpagesize())") == 2)
check("D5  0x690000E0 哨兵判断仍在（×2）",
      read("Natives/JavaLauncher.m").count("(uint32_t)result != 0x690000E0") == 2)
check("D6  Extension 注入仍在（JIT26SendJITScript ×2）",
      read("Natives/JavaLauncher.m").count("JIT26SendJITScript(") == 2)
check("D7  SetDetachAfterFirstBr(!jit26AlwaysAttached) 仍在（×2）",
      read("Natives/JavaLauncher.m").count("JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached)") == 2)
check("D8  native brk 立即数未变（0x69 与 0xf00d）",
      'brk #0x69' in utils and 'brk #0xf00d' in utils)
check("D9  x16 命令编号未变（1..4）",
      re.search(r'void\* JIT26PrepareRegion\(void \*addr, size_t len\) \{\s*asm\("mov x16, #1', utils) is not None
      and re.search(r'void JIT26PrepareRegionForPatching\(void \*addr, size_t size\) \{\s*asm\("mov x16, #4', utils) is not None)
check("D10 stikjit:// 通路仍携带 script-data=（NavCtrl+RightPanel+Download）",
      sum(read(p).count('script-data=') for p in
          ["Natives/LauncherNavigationController.m", "Natives/LauncherRightPanelViewController.m",
           "Natives/DownloadViewController.m"]) >= 6)
check("D11 UniversalJIT26Extension.js 未被改动",
      "UniversalJIT26Extension.js" in git(["diff", "HEAD", "--stat"]).stdout or
      git(["diff", "HEAD", "--", "Natives/resources/UniversalJIT26Extension.js"]).stdout.strip() == "")
check("D12 JIT26Script.js（LiveContainer 注入载荷）未被改动",
      git(["diff", "HEAD", "--", "Natives/resources/JIT26Script.js"]).stdout.strip() == "")

print()
print("=" * 72)
print("E. 仓库卫生")
print("=" * 72)

check("E1  无未提交改动（提交后自然通过）",
      git(["status", "--porcelain"]).stdout.strip() == "",
      git(["status", "--porcelain"]).stdout.strip()[:200])
check("E2  仓库 worklog 含 Task 92 条目",
      os.path.exists(os.path.join(REPO, "worklog.md")) and
      "Task ID: 92" in read("worklog.md") + read("worklog-archive.md"))

print()
print("=" * 72)
print(f"RESULT: {PASS} passed, {FAIL} failed, total {PASS + FAIL}")
print("=" * 72)
sys.exit(1 if FAIL else 0)
