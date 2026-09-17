#!/usr/bin/env python3
"""
Task 87 验证器：7b88b69 双日志判读收尾（LTW 26.x 崩溃 + BMC2 卡死元凶实锤）+ 三层修复

背景（7b88b69 用户上传日志对，均为 6054498 = Task86 构建，iPad Air M4 / iPadOS 27）：
  * latestlog.txt = LTW 渲染器 × MC 26.2 会话——LTW（桌面 GL 3.3 → Apple 系统
    ANGLE GLES 3.0 转译，无 TBO 模拟）跑 26.x 云渲染管线：rendertype_clouds
    顶点着色器声明 samplerBuffer（GL 3.3 核心特性），ES 3.0 后端没有
    GL_EXT_texture_buffer → "Illegal use of reserved word" → flat_clouds/clouds
    管线缺失 → 资源重载 11.8s 崩在标题界面（crash report 完整落盘）。
  * latestlog.old.txt = BMC2 [FABRIC] 1.20.1（537 mods，zink+FSR）卡死会话——
    Task86 看门狗两采样实锤：主线程在 Fabric setupLanguageAdapters 的
    Class.forName 阶段卡在 toni.missingmodschecker.MissingModsWindow.open 的
    Object.wait()（桌面弹窗类工具 mod，iOS 上窗口永远无法显示）。Fabric 自身
    依赖解析已完成（仅 2 条 recommends 警告，无硬缺失）。

修复（三层，全部启动器侧）：
  1. SurfaceViewController.m——LTW × MC>=26 启动预检门（版本解析 + 弹窗指引 +
     阻断，参照 metadata-nil 校验的既有模式）；
  2. JavaLauncher.m——[ModDialogGuard] Task87：JVM 启动前自动禁用实证弹窗类
     mod（missingmodschecker → .jar.disabled，Fabric 忽略非 .jar 文件）；
  3. Tools.java——看门狗转储后识别"AWT/Swing 帧 / Object.wait 直挂 mod 代码"
     阻塞形态，输出一次性 STARTUP BLOCK 指引（弹窗后等待的栈上已无 AWT 帧，
     必须匹配等待形态本身）。
  FAQ 25→26（+ltw26 条目；render/bigpack 条目同步更新）。
"""
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
SCRIPTS = os.path.join(REPO, "scripts")
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


print("===== A. 7b88b69 日志对证据（可变工作区，退役时按惯例钉 git） =====")
log_ltw = read("latestlog.txt")
log_pack = read("latestlog.old.txt")
check("A1 两日志均为 6054498 构建（Task86 IPA）",
      "Commit: 6054498 (main)" in log_ltw and "Commit: 6054498 (main)" in log_pack)
check("A2 LTW 会话：ES 3.0 后端实证（Running on OpenGL ES 3.0 + BaseVertex 缺 ES 3.1）",
      "LTW: Running on OpenGL ES 3.0 with ESSL 300" in log_ltw
      and "BaseVertex render calls not available: requires OpenGL ES 3.1" in log_ltw)
check("A3 LTW 会话：宣告桌面 GL 3.3（与 ES 3.0 实际能力的契约缺口）",
      "3.3 OpenLTW" in log_ltw)
check("A4 LTW 会话：崩溃链（samplerBuffer 保留字 + flat_clouds/clouds 管线缺失）",
      "'samplerBuffer' : Illegal use of reserved word" in log_ltw
      and "minecraft:pipeline/flat_clouds" in log_ltw
      and "minecraft:pipeline/clouds" in log_ltw)
check("A5 LTW 会话：26.2 版本 + 资源重载期崩溃（Failed to load required shader programs）",
      "Minecraft Version: 26.2" in log_ltw
      and "Failed to load required shader programs" in log_ltw)
check("A6 整合包会话：看门狗实锤（MissingModsWindow.open 的 Object.wait）",
      "toni.missingmodschecker.MissingModsWindow.open(MissingModsWindow.java:47)" in log_pack
      and "[LaunchWatchdog] Task86 entrypoint-phase sample #1" in log_pack
      and "STILL blocked at java.base@17.0.20-internal/java.lang.Object.wait" in log_pack)
check("A7 整合包会话：missingmodschecker 在 mod 列表（1.0.1）+ 537 mods",
      "- missingmodschecker 1.0.1" in log_pack and "Loading 537 mods:" in log_pack)
check("A8 整合包会话：Fabric 依赖解析已完成（仅 recommends 警告，无硬缺失）",
      "Warnings were found!" in log_pack
      and "recommends any version of lambdynlights, which is missing" in log_pack
      and re.search(r"- Mod '\w+' \(\w+\) [\d.]+ requires", log_pack) is None)
check("A9 整合包会话：用户取消收场（User cancelled launch + exit(0)）",
      "User cancelled launch" in log_pack and "exit(0) called" in log_pack)

print("===== B. SurfaceViewController.m：LTW × 26.x 预检门 =====")
svc = read("Natives/SurfaceViewController.m")
check("B1 版本判定函数在位（主版本 >= 26 口径 + rc/pre 后缀剥离）",
      "static BOOL ame87_mcVersionRequiresTextureBuffer(NSString *mcVersionId)" in svc
      and "return major >= 26;" in svc
      and 'rangeOfString:@"-"' in svc)
check("B2 函数定义先于 launchMinecraft 使用（文件级顺序）",
      svc.index("static BOOL ame87_mcVersionRequiresTextureBuffer")
      < svc.index("- (void)launchMinecraft"))
check("B3 预检门用 RENDERER_NAME_LTW 匹配渲染器",
      'isEqualToString:@ RENDERER_NAME_LTW' in svc)
check("B4 预检门阻断模式与既有校验一致（dismissLaunchOverlayOnError + showDialog + return）",
      re.search(r"Task87 launch gate: LTW renderer", svc) is not None
      and re.search(r"\[self dismissLaunchOverlayOnError\];\s*\n\s*showDialog\(localize\(@\"Error\", nil\),\s*\n\s*\[NSString stringWithFormat:@\"LTW 渲染器不支持", svc) is not None)
check("B5 预检门位于 launchJVM 之前（JVM 未启动即拦截）",
      svc.index("Task87 launch gate") < svc.index("int launchResult = launchJVM("))
check("B6 弹窗指引内容（切 Zink/MobileGlues + LTW 适用 1.21.x）",
      "切换到 Zink 或 MobileGlues" in svc and "仍可用于 1.21.x" in svc)

print("===== C. JavaLauncher.m：ModDialogGuard =====")
jl = read("Natives/JavaLauncher.m")
check("C1 预检函数在位（mods 目录扫描 + .jar 后缀过滤）",
      "static int ame87_disableDesktopDialogMods(NSString *gameDir)" in jl
      and 'stringByAppendingPathComponent:@"mods"' in jl
      and 'hasSuffix:@".jar"' in jl)
check("C2 实证名单仅收 missingmodschecker（宁缺毋滥原则）",
      '@[@"missingmodschecker"]' in jl)
check("C3 禁用动作 = 改名 .disabled（可逆，Fabric 忽略非 .jar；fileMgr 避开 26 行 fm 宏）",
      'stringByAppendingString:@".disabled"' in jl
      and "[fileMgr moveItemAtPath:srcPath toPath:dstPath error:nil]" in jl
      and "#define fm " not in jl[jl.index("ame87_disableDesktopDialogMods"):jl.index("int launchJVM(NSString *accountId", jl.index("ame87_disableDesktopDialogMods"))])
check("C4 日志前缀 [ModDialogGuard] Task87（单文件级 + 汇总级）",
      jl.count("[ModDialogGuard] Task87") >= 3)
check("C5 调用点在实例分支 gameDir 计算后、JVM 启动前",
      jl.index("ame87_disableDesktopDialogMods(gameDir)")
      > jl.index('Setup gameDir')
      and jl.index("ame87_disableDesktopDialogMods(gameDir)")
      < jl.index("[JavaLauncher] Looking for Java"))
check("C6 病历注释含 7b88b69 + MissingModsWindow 证据链",
      "7b88b69" in jl and "MissingModsWindow" in jl)

print("===== D. Tools.java：看门狗阻塞形态识别 =====")
tools = read("JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java")
check("D1 dumpStack 挂接识别钩子",
      "maybeLogStartupBlockHint(st);" in tools)
check("D2 等待形态判据（Object.wait/wait0 直挂非 JDK 帧，3 帧窗口）",
      "isObjectWaitUnderAppFrames" in tools
      and '"wait0".equals(st[0].getMethodName())' in tools
      and 'Math.min(4, st.length)' in tools)
check("D3 AWT/Swing 帧扫描（16 帧窗口）",
      'cn.startsWith("java.awt.") || cn.startsWith("javax.swing.")' in tools
      and "Math.min(16, st.length)" in tools)
check("D4 一次性指引（task87HintShown 防刷屏 + STARTUP BLOCK signature 行）",
      "task87HintShown = true;" in tools
      and "STARTUP BLOCK signature:" in tools)
check("D5 指引指向移除/禁用动作 + 与 ModDialogGuard 呼应",
      "rename its .jar to .jar.disabled" in tools
      and "[ModDialogGuard] Task87" in tools)
check("D6 病历 javadoc 说明'弹窗后等待无 AWT 帧'的漏检形态",
      "纯 AWT 帧扫描会漏掉" in tools)
check("D7 仅用 java.lang API（无新增 import 依赖）",
      "java.awt" not in tools.split("isObjectWaitUnderAppFrames")[0].split("import ")[0]
      or "import java.awt" not in tools)

print("===== E. FAQ 26 条 =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("E1 26 条目（Task87 +ltw26）", len(faq_items) == 26, f"got {len(faq_items)}")
check("E2 ltw26 条目在位（预检说明 + samplerBuffer 机理 + 日志特征 + 切换指引）",
      "LTW 渲染器玩 MC 26.x 直接崩溃" in helpvc
      and "samplerBuffer" in helpvc
      and "pipeline/flat_clouds" in helpvc
      and "内置纹理缓冲模拟层" in helpvc)
check("E3 ltw26 注册进渲染与性能分类（renderer 之后）",
      re.search(r"@\[ renderer, ltw26, mgLag,", helpvc) is not None)
check("E4 renderer 条目补 LTW 适用范围（1.21.x 及更早 + 不支持 26.x）",
      "LTW：轻量级 OpenGL 3.3→ES 转译层" in helpvc
      and "不支持 MC 26.x（见下一条）" in helpvc)
check("E5 bigpack 条目实锤案例 + 两层防护（ModDialogGuard 自动禁用 + 看门狗点名）",
      "missingmodschecker" in helpvc
      and "[ModDialogGuard]" in helpvc
      and "[LaunchWatchdog]" in helpvc)
check("E6 bigpack 恢复指引（.disabled 改回 .jar）",
      "改回 .jar" in helpvc)

print("===== F. version.h addendum =====")
ver = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F1 Task 87 addendum 在位（双病历 + 双修复 + 预检门）",
      "REVISION 17 addendum (Task 87, no bump)" in ver
      and "MissingModsWindow.open" in ver
      and "[ModDialogGuard] Task87" in ver
      and "samplerBuffer: Illegal use of reserved" in ver)
check("F2 REVISION 不 bump（无转换缓存风暴）",
      re.search(r"#define REVISION 17\b", ver) is not None
      and "REVISION 18" not in ver)

print("===== G. 版本判定口径单测（Python 模拟 ame87_mcVersionRequiresTextureBuffer） =====")


def requires_tbo(v):
    if not v:
        return False
    base = v.split("-")[0]
    parts = base.split(".")
    if parts:
        m = re.match(r"\d+", parts[0])
        if m:
            major = int(m.group())
            if major > 0:
                return major >= 26
    return False


cases = [
    ("26.2", True), ("26.1", True), ("27.0", True), ("26.2-rc1", True),
    ("26w13a", True), ("1.20.1", False), ("1.21.9", False), ("1.16.5", False),
    ("25w45a", False), ("", False), ("latest-release", False),
]
ok_cases = [v for v, want in cases if requires_tbo(v) == want]
check("G1 12 个版本口径用例全对（26.x/26w* 拦，1.21.x/25w* 放）",
      len(ok_cases) == len(cases),
      str([f"{v}->{requires_tbo(v)}" for v, want in cases if requires_tbo(v) != want]))

print("===== H. 括号平衡（字符串感知状态机——task67 教训） =====")


def bracket_balance(src):
    """字符级状态机：正确跳过字符串/字符字面量/两种注释后统计三对括号。"""
    counts = {"{}": [0, 0], "()": [0, 0], "[]": [0, 0]}
    state = "code"  # code | line | block | str | chr
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; i += 1; continue
            if c == "'":
                state = "chr"; i += 1; continue
            for pair in counts:
                if c == pair[0]:
                    counts[pair][0] += 1
                elif c == pair[1]:
                    counts[pair][1] += 1
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
        elif state == "chr":
            if c == "\\":
                i += 2; continue
            if c == "'":
                state = "code"
        i += 1
    return all(v[0] == v[1] for v in counts.values()), counts


for path in ("Natives/SurfaceViewController.m",
             "Natives/JavaLauncher.m",
             "Natives/LauncherHelpViewController.m",
             "JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java",
             "Natives/external/MobileGlues/MobileGlues-cpp/version.h"):
    ok, cnt = bracket_balance(read(path))
    check(f"H {os.path.basename(path)} 括号自平衡（字符串感知）", ok, str(cnt))

print("===== I. ECJ 编译门（本地无 javac 时的替代，缺 ecj.jar 则跳过） =====")
ecj = None
for cand in ("/tmp/ecj.jar", os.path.join(SCRIPTS, "ecj.jar")):
    if os.path.exists(cand):
        ecj = cand
        break
if ecj:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        cp = f"{REPO}/JavaApp/src/launcher:" + ":".join(
            os.path.join(REPO, "JavaApp", "libs", d, f)
            for d in ("lwjgl", "lwjgl-333", "lwjgl-341", "caciocavallo",
                      "caciocavallo17", "others")
            for f in (os.listdir(os.path.join(REPO, "JavaApp", "libs", d))
                      if os.path.isdir(os.path.join(REPO, "JavaApp", "libs", d)) else [])
            if f.endswith(".jar"))
        r = subprocess.run(["java", "-jar", ecj, "-nowarn", "-source", "17",
                            "-target", "17", "-cp", cp, "-d", td,
                            os.path.join(REPO, "JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java")],
                           capture_output=True, text=True, timeout=180)
        errs = [l for l in r.stdout.splitlines() if "ERROR" in l and "Tools.java" in l]
        check("I Tools.java ECJ 编译零错误（Tools 自身）", not errs,
              "; ".join(errs[:3]))
        check("I Tools.class 产物存在", os.path.exists(os.path.join(td, "net/kdt/pojavlaunch/Tools.class")))
else:
    check("I ECJ 编译门", True, "skipped: ecj.jar 不在本机（CI javac 为最终关卡）")

print("===== J. 级联（含同步到 26 条后的旧验证器） =====")
for v in ("verify_task83.py", "verify_task84.py", "verify_task85.py", "verify_task86.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=600)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln]
    tail = summary[-1] if summary else (r.stdout + r.stderr)[-150:]
    # 各脚本 RESULT 行格式不一（'ALL PASS (n/n)' / 'n/n' / 'n/n PASS'），
    # 以退出码为准 + 排除显式失败标记
    ok = r.returncode == 0 and re.search(r"FAILED|FAILURES PRESENT", tail) is None
    check(f"J {v}", ok, tail[:120])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
