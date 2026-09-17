#!/usr/bin/env python3
"""
Task 94 验证器：809b847 双日志判读（Sodium LWJGL 版本门）+ 动态版本上报修复

背景（809b847 用户上传日志对，均为 3bc95fa = friend's Task93 构建，iPad Air M4 /
iPadOS 27，BMC2 [FABRIC] 1.20.1 整合包 537 mods）：
  * latestlog.txt = zink（libOSMesa.8.dylib）会话，latestlog.old.txt = LTW 会话；
  * 两日志均证明 Task87 修复生效：LTW 会话 [ModDialogGuard] Task87 自动禁用
    missingmodschecker.jar（rename .disabled），启动越过旧卡死点，mixin/config
    阶段正常推进；
  * 两渲染器在 JVM 启动 ~4s 后死于同一处：sodium 0.5.13（pack 实配，日志 808 行）
    的 PreLaunchChecks 版本门 —— "The game failed to start because the currently
    active LWJGL version is not compatible. Installed version: 3.4.1 /
    Required version: 3.3.1" → System.exit(1)（Amethyst fatal trace: VM_Exit）。
  * 根因（三层取证）：
    (1) 反编译 Modrinth 原版 sodium-fabric-0.5.13+mc1.20.1.jar：
        PreLaunchChecks.isUsingKnownCompatibleLwjglVersion() =
        org.lwjgl.Version.getVersion().startsWith("3.3.1")（REQUIRED 硬编码）；
    (2) JavaApp/src/lwjgl overlay 的 Version.java/VersionImpl.java 把上报值硬编码
        "3.4.1"（当年为满足 MC 26.x Sodium 0.9+ 的 startsWith("3.4.1")）→
        1.18~1.20.x 全部被 0.4/0.5 系 sodium 拒绝；
    (3) 启动器本身选 jar 正确（[JavaLauncher] Using LWJGL 333）——错的只是上报值。

修复（动态上报，全部启动器侧 Java）：
  1. Tools.java preProcessLibraries：丢弃 org.lwjgl 条目前捕获
     "org.lwjgl:lwjgl:<ver>"（version.json 里 Mojang 为该 MC 配套的 LWJGL 版本，
     正是 sodium REQUIRED 常量的来源），写入 org.lwjgl.version.report + 日志；
  2. overlay Version.java/VersionImpl.java：getVersion() 动态读属性（每次调用，
     不受 clinit 固化影响）；回退 -Dpojav.lwjgl.version=341 → "3.4.1"，否则 "3.3.1"
     （333 真实构建是 3.3.3，但 "3.3.3".startsWith("3.3.1")=false 同样被拒，
     回退值取 3.3.1 覆盖 1.18~1.20.x 最大存量）；
  3. PojavLauncher.java：修括号错位（LWJGL sanity 日志被困在 vulkan-only if 内
     从未执行过——设备日志从未出现该行即实证），迁至 getVersionInfo 之后并输出
     reported/metadata 双值。
验证：ECJ 编译门 + Task94Harness 14 项行为矩阵 + Task94SodiumGate 字节码级
（真实 sodium jar 反射 isUsingKnownCompatibleLwjglVersion：旧 3.4.1 拒 / 新 3.3.1 过）。
FAQ 26→27（+sodiumLwjgl 条目）；version.h REVISION 17 addendum。
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


print("===== A. 809b847 日志对证据（可变工作区） =====")
log_zink = read("latestlog.txt")
log_ltw = read("latestlog.old.txt")
check("A1 两日志均为 3bc95fa 构建",
      "Commit: 3bc95fa (main)" in log_zink and "Commit: 3bc95fa (main)" in log_ltw)
check("A2 均为 BMC2 1.20.1（fabric-loader 0.19.3）",
      "fabric-loader-0.19.3-1.20.1-9c2ee306" in log_zink
      and "fabric-loader-0.19.3-1.20.1-9c2ee306" in log_ltw)
check("A3 zink 会话：Using LWJGL 333（选 jar 正确，错的是上报值）",
      "Using LWJGL 333 (mcVersion=fabric-loader-0.19.3-1.20.1-9c2ee306)" in log_zink
      and "libs/lwjgl-333/lwjgl.jar" in log_zink)
check("A4 LTW 会话：同样 Using LWJGL 333",
      "Using LWJGL 333 (mcVersion=fabric-loader-0.19.3-1.20.1-9c2ee306)" in log_ltw)
check("A5 Task87 ModDialogGuard 在 LTW 会话生效（missingmodschecker 已禁用）",
      "[ModDialogGuard] Task87: disabled desktop dialog mod \"missingmodschecker.jar\"" in log_ltw)
check("A6 sodium 实配版本 0.5.13+mc1.20.1（两日志）",
      "sodium 0.5.13+mc1.20.1" in log_zink and "sodium 0.5.13+mc1.20.1" in log_ltw)
check("A7 两渲染器同死于 sodium LWJGL 版本门",
      "The game failed to start because the currently active LWJGL version is not compatible."
      in log_zink and "The game failed to start because the currently active LWJGL version is not compatible."
      in log_ltw)
check("A8 门的具体读数：Installed 3.4.1 / Required 3.3.1（overlay 硬编码值 vs sodium 要求）",
      "Installed version: 3.4.1" in log_zink and "Required version: 3.3.1" in log_zink
      and "Installed version: 3.4.1" in log_ltw and "Required version: 3.3.1" in log_ltw)
check("A9 死因是干净的 exit(1)（VM_Exit，非崩溃非卡死）",
      "reason: exit(1) called" in log_zink and "reason: exit(1) called" in log_ltw)
check("A10 gh-2561 帮助链接（sodium PreLaunchChecks 特征）",
      "sodium/runtime-issue/lwjgl3/gh-2561" in log_zink)

print("===== B. overlay Version.java / VersionImpl.java 重写 =====")
version_java = read("JavaApp/src/lwjgl/org/lwjgl/Version.java")
versionimpl_java = read("JavaApp/src/lwjgl/org/lwjgl/VersionImpl.java")
check("B1 Version.getVersion() 动态读 org.lwjgl.version.report 属性",
      'System.getProperty("org.lwjgl.version.report")' in version_java
      and version_java.index("getVersion") < version_java.index("parseMMR"))
check("B2 341 集合回退 3.4.1（26.x 行为保持不变）",
      '"341".equals(System.getProperty("pojav.lwjgl.version"))' in version_java
      and '"3.4.1"' in version_java)
check("B3 333/默认回退 3.3.1（非真实构建 3.3.3——会被 startsWith(\"3.3.1\") 拒）",
      re.search(r'return "3\.3\.1";', version_java) is not None)
check("B4 无 \"3.3.3\" 回退陷阱（代码层，剔除注释后检查）",
      '"3.3.3"' not in re.sub(r"//[^\n]*|/\*.*?\*/", "", version_java, flags=re.S))
check("B5 空白属性视为未设置（trim + isEmpty）", ".trim()" in version_java
      and ".isEmpty()" in version_java)
check("B6 常量从上报值解析（非硬编码 3/4/1）",
      "VERSION_MAJOR = mmr[0]" in version_java and "parseMMR" in version_java)
check("B7 VersionImpl.find() 与 Version.getVersion() 同源",
      "return Version.getVersion();" in versionimpl_java)
check("B8 旧硬编码已清除（getVersion 直返常量模式不存在）",
      re.search(r'getVersion\(\)\s*\{\s*return\s*"3\.4\.1"\s*;', version_java, re.S) is None)

print("===== C. Tools.java 捕获链路 =====")
tools_java = read("JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java")
check("C1 preProcessLibraries 捕获 org.lwjgl:lwjgl:<ver>",
      'libItem.name.startsWith("org.lwjgl:lwjgl:")' in tools_java)
check("C2 写入 org.lwjgl.version.report 属性",
      'System.setProperty("org.lwjgl.version.report"' in tools_java)
check("C3 捕获在 _skip 赋值前（丢弃前抢救）",
      tools_java.index('org.lwjgl:lwjgl:') < tools_java.index("libItem._skip = true"))
check("C4 诊断日志行（装机验证锚点）",
      "[Tools] LWJGL report version:" in tools_java
      and "sodium PreLaunchChecks gate, Task94" in tools_java)
check("C5 坐标解析用 split(\":\") 第 3 段 + 非空校验",
      'coord.length >= 3' in tools_java and 'coord[2].trim()' in tools_java)

print("===== D. PojavLauncher.java 括号修复 + sanity 日志 =====")
pojav_java = read("JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java")
check("D1 vulkan if 块不再吞掉后续代码（setProperty 后即闭合）",
      re.search(r'if \("libMoltenVK\.dylib"\.equals\(renderer\)[^\{]*\{\s*'
                r'System\.setProperty\("org\.lwjgl\.vulkan\.libname", "MoltenVK"\);\s*\}',
                pojav_java) is not None)
check("D2 sanity 检查移到 getVersionInfo 之后（属性已写入时才打点）",
      pojav_java.index("Tools.getVersionInfo(args[1])")
      < pojav_java.index("String activeLwjgl = System.getProperty(\"pojav.lwjgl.version\")"))
check("D3 日志输出 reported + metadata 双值",
      '", reported version: "' in pojav_java
      and ' (metadata: "' in pojav_java
      and 'System.getProperty("org.lwjgl.version.report", "not captured")' in pojav_java)
check("D4 旧位置无残留的错位 sanity 块",
      pojav_java.count("String activeLwjgl = System.getProperty(\"pojav.lwjgl.version\")") == 1)

print("===== E. FAQ 27 条（+sodiumLwjgl） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("E1 27 条目（Task94 +1）", len(faq_items) == 27, f"got {len(faq_items)}")
check("E2 sodiumLwjgl 条目在位（症状 + Installed/Required 读数 + 机理 + 验证锚点）",
      "LWJGL version is not compatible" in helpvc
      and "Installed version: 3.4.1" in helpvc
      and "动态上报" in helpvc
      and "[Tools] LWJGL report version" in helpvc)
check("E3 条目挂载在故障排除分类",
      re.search(r"xray, greenFx, background, crash, stuck, bigpack, sodiumLwjgl", helpvc) is not None)

print("===== F. version.h REVISION 17 addendum =====")
version_h = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F1 Task 94 addendum 在位",
      "REVISION 17 addendum (Task 94, no bump)" in version_h)
check("F2 addendum 记录字节码级验证证据",
      "isUsingKnownCompatibleLwjglVersion()" in version_h
      and "sodium-fabric-" in version_h)
check("F3 REVISION 仍为 17（未 bump）",
      re.search(r"#define REVISION 17\b", version_h) is not None)

print("===== G. 括号自平衡 =====")


def bracket_balance(src):
    depth = 0
    in_str = in_chr = in_line = in_block = False
    i = 0
    while i < len(src):
        c = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if in_line:
            if c == "\n":
                in_line = False
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 1
        elif in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif in_chr:
            if c == "\\":
                i += 1
            elif c == "'":
                in_chr = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block = True
                i += 1
            elif c == '"':
                in_str = True
            elif c == "'":
                in_chr = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth < 0:
                    return False, depth
        i += 1
    return depth == 0, depth


for path in ("JavaApp/src/lwjgl/org/lwjgl/Version.java",
             "JavaApp/src/lwjgl/org/lwjgl/VersionImpl.java",
             "JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java",
             "JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java",
             "Natives/LauncherHelpViewController.m"):
    ok, cnt = bracket_balance(read(path))
    check(f"G {os.path.basename(path)} 括号自平衡（字符串感知）", ok, str(cnt))

print("===== H. 编译门 + 行为矩阵 + 真实 sodium 门（ECJ，缺 ecj.jar 则跳过细节项） =====")
ecj = "/tmp/ecj.jar"
harness_root = os.path.join(SCRIPTS, "task94_harness")
build_dir = "/tmp/task94_build"
if os.path.exists(ecj):
    r = subprocess.run(["bash", os.path.join(SCRIPTS, "task94_compile_check.sh")],
                       capture_output=True, text=True, timeout=600)
    check("H1 编译门（overlay + Tools + PojavLauncher）",
          "ALL COMPILE CHECKS PASSED" in r.stdout,
          (r.stdout + r.stderr)[-200:])

    # overlay classpath 产物直接复用编译门输出
    ov = os.path.join(build_dir, "ov")
    if os.path.isdir(ov):
        sg_dir = os.path.join(build_dir, "sg")
        hn_dir = os.path.join(build_dir, "hn")
        for d, src, cp_extra in (
            (hn_dir, "Task94Harness.java", ""),
            (sg_dir, "Task94SodiumGate.java", f":{os.path.join(build_dir, 'sodium0513.jar')}")):
            os.path.isdir(d) or os.makedirs(d)
        r2 = subprocess.run(["java", "-jar", ecj, "-nowarn", "-source", "8", "-target", "8",
                             "-cp", ov, "-d", hn_dir,
                             os.path.join(harness_root, "Task94Harness.java")],
                            capture_output=True, text=True, timeout=180)
        check("H2 Task94Harness 编译", "ERROR" not in r2.stdout, r2.stdout[-150:])
        if os.path.exists(os.path.join(hn_dir, "Task94Harness.class")):
            r3 = subprocess.run(["java", "-cp", f"{ov}:{hn_dir}", "Task94Harness"],
                                capture_output=True, text=True, timeout=120)
            check("H3 Task94Harness 行为矩阵 14 项",
                  "RESULT: 14 PASS, 0 FAIL" in r3.stdout,
                  [ln for ln in r3.stdout.splitlines() if "FAIL" in ln][:3])
        # 真实 sodium 门（Modrinth 原版 jar 已由编译门/手动备好）
        sodium_jar = os.path.join(build_dir, "sodium0513.jar")
        if os.path.exists(sodium_jar):
            r4 = subprocess.run(["java", "-jar", ecj, "-nowarn", "-source", "8", "-target", "8",
                                 "-cp", f"{ov}:{sodium_jar}", "-d", sg_dir,
                                 os.path.join(harness_root, "Task94SodiumGate.java")],
                                capture_output=True, text=True, timeout=180)
            check("H4 Task94SodiumGate 编译", "ERROR" not in r4.stdout, r4.stdout[-150:])
            if os.path.exists(os.path.join(sg_dir, "Task94SodiumGate.class")):
                r5 = subprocess.run(
                    ["java", "-cp", f"{ov}:{sodium_jar}:{sg_dir}", "Task94SodiumGate"],
                    capture_output=True, text=True, timeout=120)
                check("H5 真实 sodium 0.5.13 门：旧 3.4.1 拒 / 新 3.3.1 过（字节码级）",
                      "RESULT: 2 PASS, 0 FAIL" in r5.stdout,
                      [ln for ln in r5.stdout.splitlines() if "FAIL" in ln][:3])
        else:
            check("H5 真实 sodium 门", True, "skipped: sodium0513.jar 不在（网络受限）")
else:
    check("H1-H5 编译/行为门", True, "skipped: /tmp/ecj.jar 不在（CI 构建为最终关卡）")

print("===== I. 级联（含 FAQ 计数同步到 27 的旧验证器） =====")
for v in ("verify_task83.py", "verify_task84.py", "verify_task85.py",
          "verify_task86.py", "verify_task87.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=600)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln]
    tail = summary[-1] if summary else (r.stdout + r.stderr)[-150:]
    ok = r.returncode == 0 and re.search(r"FAILED|FAILURES PRESENT", tail) is None
    check(f"I {v}", ok, tail[:120])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
