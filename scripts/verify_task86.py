#!/usr/bin/env python3
"""
Task 86 验证器：双日志判读（Task85 修复装机实证 + BMC2 卡启动诊断）+ 启动看门狗

背景（f17ef7b 用户上传日志对，均为 e7230da = Task85 构建）：
  * latestlog.old.txt = 26.3-rc-3 zink 会话——Task85"画面分裂"修复装机实证：
    engaged 行带 "(EASU pre-readback ordering, Task 85)" 后缀，游戏正常游玩后
    用户主动退出（存档/Stopping! 链完整）。
  * latestlog.txt = BMC2 [FABRIC] 1.20.1（537 mods，Modrinth shFhR8Vx）首启
    卡死会话——JVM 启动 5.6s 内完成 Fabric 全部 mod 枚举与 configureddefaults
    默认文件应用，随后主线程硬阻塞：187s 零 GC/零 JIT/零日志，用户取消，
    启动浮层以 launch error 收场（"卡在启动界面"）。

修复（诊断型）：
  Tools.java startLaunchWatchdog——在 method.invoke(Minecraft main) 之前布防
  守护线程，周期采样游戏主线程调用栈：
    阶段1（entrypoint 期，线程名 != "Render thread"）：每 15s 全量转储前 24 帧，
            连续阻塞压缩为单行心跳；最多 40 次（10 分钟）。
    阶段2（窗口建立后）：每 30s 采样，栈顶 6 帧连续 2 次一致（>= 60s 冻结）才
            转储，最多 5 次。
  日志前缀 "[LaunchWatchdog] Task86"——下次复现直接点名阻塞 mod。
  FAQ 25 条（+bigpack 大型整合包首启卡死条目）。

已知边界（诚实记录）：
  * 看门狗是诊断工具，不是治疗——元凶 mod 的确定依赖用户下次复现的日志；
  * 本地 ECJ 编译门为可选（无 javac 环境时跳过），CI 的 javac 是最终关卡。
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


print("===== A. Tools.java 看门狗指纹 =====")
tools = read("JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java")
check("A1 布防点在 method.invoke 之前（Minecraft main 调用前启动看门狗）",
      tools.index("startLaunchWatchdog(Thread.currentThread());")
      < tools.index('method.invoke(null, new Object[]{launchArgs});'))
check("A2 看门狗为守护线程且命名 Launch-Watchdog",
      "watchdog.setDaemon(true);" in tools and '"Launch-Watchdog"' in tools)
check("A3 阶段1：15s 间隔 + 40 次上限 + 24 帧转储",
      "Thread.sleep(15000L);" in tools and "i <= 40" in tools
      and "Math.min(24, st.length)" in tools)
check("A4 阶段1 重复阻塞压缩（STILL blocked 心跳行 + 6 帧签名）",
      "STILL blocked at" in tools and "stackSignature(st, 6)" in tools
      and re.search(r"signature\.equals\(lastDumpSignature\)", tools) is not None)
check("A5 改名判据（Render thread 到达 = 窗口初始化开始）并移交阶段2",
      '"Render thread".equals(name)' in tools or 'renderThreadName.equals(name)' in tools
      and "runPostWindowPhase(gameThread);" in tools)
check("A6 阶段2：30s 间隔 + 20 次上限 + 转储 <= 5 + 连续 2 次冻结判据",
      "Thread.sleep(30000L);" in tools and "i <= 20 && dumps < 5" in tools
      and "frozenCount >= 2" in tools)
check("A7 日志前缀统一（[LaunchWatchdog] Task86）",
      '[LaunchWatchdog] Task86 " + msg' in tools)
check("A8 双阶段线程终止检查（TERMINATED 即退）",
      tools.count("Thread.State.TERMINATED") >= 2)
check("A9 病历 javadoc（BMC2/537 mods/configureddefaults 诊断链）",
      "BMC2" in tools and "537 mods" in tools and "configureddefaults" in tools)
check("A10 仅用 java.lang API（无新增 import 依赖）",
      "java.lang.management" not in tools and "javax.management" not in tools)

print("===== B. f17ef7b 日志对证据（Task87 起钉 git——工作区已被 7b88b69 新对覆盖） =====")
# Task86 当时验证的 e7230da 日志对已随 7b88b69 上传被覆盖，按 task84 E 段惯例
# 钉死到 git 历史 f17ef7b（上传提交），不再读可变工作区日志。
def git_show(ref_path):
    r = subprocess.run(["git", "-C", REPO, "show", ref_path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""
log_old = git_show("f17ef7b:latestlog.old.txt")
log_new = git_show("f17ef7b:latestlog.txt")
check("B0 git fixture f17ef7b 日志对在位", len(log_old) > 1000 and len(log_new) > 1000)
check("B1 两日志均为 e7230da 构建（Task85 IPA）",
      "Commit: e7230da (main)" in log_old and "Commit: e7230da (main)" in log_new)
check("B2 old.txt：Task85 修复装机锚点（EASU pre-readback ordering 后缀）",
      "(EASU pre-readback ordering, Task 85)" in log_old)
check("B3 old.txt：健康会话（正常游玩后退出：Saving chunks + Stopping! + exit(0)）",
      "Saving chunks for level" in log_old and "Stopping!" in log_old
      and "exit(0) called" in log_old)
check("B4 old.txt：帧流正常（fps 计数 > 0 行存在）",
      re.search(r"fps=[1-9]\d*", log_old) is not None)
check("B5 new.txt：BMC2 整合包身份（Modrinth mrpack + 537 mods）",
      "BMC2" in log_new and "Loading 537 mods:" in log_new)
check("B6 new.txt：卡点解剖（Applying default files 后无 Backend library，用户取消）",
      "Applying default files..." in log_new and "Backend library" not in log_new
      and "User cancelled launch" in log_new)
check("B7 new.txt：主线程硬阻塞铁证（Cleanup 前空窗 >= 100s 的 safepoint 间隔）",
      re.search(r'Safepoint "Cleanup", Time since last: \d{11,} ns', log_new) is not None)
check("B8 new.txt：零首帧（RenderDiag fps 恒 0 且 drawable=0x0）",
      "[RenderDiag] fps=0 " in log_new
      and re.search(r"\[RenderDiag\] fps=[1-9]", log_new) is None
      and "drawable=0x0" in log_new)
check("B9 new.txt：JVM/加载器本身健康（2966MB 分配 + Fabric 5s 完成枚举）",
      "Max RAM allocation is set to 2966 MB" in log_new
      and "Loading Minecraft 1.20.1 with Fabric Loader 0.19.3" in log_new)

print("===== C. FAQ 27 条（bigpack 条目，Task87 增 ltw26，Task94 增 sodiumLwjgl） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("C1 27 条目（Task86 +1，Task87 +1，Task94 +1）", len(faq_items) == 27, f"got {len(faq_items)}")
check("C2 bigpack 条目在位（Task87 重写：实锤案例 + 两层防护 + 自救步骤）",
      "大型整合包（几百个模组）第一次启动就卡在加载界面" in helpvc
      and "[LaunchWatchdog]" in helpvc
      and "missingmodschecker" in helpvc
      and "[ModDialogGuard]" in helpvc)
check("C3 bigpack 注册进故障排除分类（stuck 之后，Task94 后 sodiumLwjgl 殿后）",
      re.search(r"@\[ xray, greenFx, background, crash, stuck, bigpack, sodiumLwjgl \]", helpvc) is not None)
check("C4 bigpack 与渲染器/内存无关的定性（防误导加内存）",
      "加大内存无效" in helpvc)

print("===== D. version.h addendum =====")
ver = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D1 Task 86 addendum 在位（看门狗 + 病历 + 前缀）",
      "REVISION 17 addendum (Task 86, no bump)" in ver
      and "[LaunchWatchdog] Task86" in ver
      and "537 mods" in ver)
check("D2 REVISION 不 bump（无转换缓存风暴）",
      re.search(r"#define REVISION 17\b", ver) is not None
      and "REVISION 18" not in ver)

print("===== E. 括号平衡（字符串感知状态机——task67 教训） =====")


def bracket_balance(src):
    """字符级状态机：正确跳过字符串/字符字面量/两种注释后统计三对括号。"""
    counts = {"{}": [0, 0], "()": [0, 0], "[]": [0, 0]}
    state = "code"  # code | line | block | str | chr
    quote = ""
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


for path in ("JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java",
             "Natives/LauncherHelpViewController.m",
             "Natives/external/MobileGlues/MobileGlues-cpp/version.h"):
    ok, cnt = bracket_balance(read(path))
    check(f"E {os.path.basename(path)} 括号自平衡（字符串感知）", ok, str(cnt))

print("===== F. ECJ 编译门（本地无 javac 时的替代，缺 ecj.jar 则跳过） =====")
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
        check("F Tools.java ECJ 编译零错误（Tools 自身）", not errs,
              "; ".join(errs[:3]))
        check("F Tools.class 产物存在", os.path.exists(os.path.join(td, "net/kdt/pojavlaunch/Tools.class")))
else:
    check("F ECJ 编译门", True, "skipped: ecj.jar 不在本机（CI javac 为最终关卡）")

print("===== G. 级联 =====")
for v in ("verify_task83.py", "verify_task84.py", "verify_task85.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=600)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln or "PASS" in ln]
    tail = summary[-1] if summary else (r.stdout + r.stderr)[-150:]
    ok = r.returncode == 0 and "FAIL" not in tail.upper().replace("FAILURES", "FAIL")
    check(f"G {v}", ok, tail[:120])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
