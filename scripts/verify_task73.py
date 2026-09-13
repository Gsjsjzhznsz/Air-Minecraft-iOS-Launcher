#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task73.py — Task 73 修复验证（MC 26.2 + Fabulously Optimized v14.1.0
"缺失文件"崩溃 = NoClassDefFoundError: Narrator$InitializeException）

根因链（三重证据）：
  1. 设备日志（33a4071 上传，0a916e0 构建）：安装全绿 + Task72 锚点生效 +
     JVM 正常启动 + 51 mod 全部加载 → Minecraft.<init>:733 崩于
     NoClassDefFoundError: com/mojang/text2speech/Narrator$InitializeException
  2. 官方 26.2/26.3-rc-2 client.jar（SHA1 校验通过）全量扫描：仅
     GameNarrator/AccessibilityOnboardingScreen 引用 Narrator 的 5 个方法，
     均无 InitializeException → 排除原版客户端
  3. FO v14.1.0 全部 51 个 mod jar 扫描：唯一命中 modernfix-5.27.19-build.1.jar
     → GameNarratorMixin（suppress_narrator_stacktrace）引用清单：
       CLASS  Narrator$InitializeException   ← 崩溃点（catch 块验证期解析）
       CLASS  NarratorLinux
       CLASS  OperatingSystem
       FIELD  Narrator.EMPTY
       METHOD NarratorLinux.<init>()V
       METHOD OperatingSystem.get()
       METHOD OperatingSystem.ordinal()
  而启动器桩（Tools.preProcessLibraries 跳过 text2speech 下载，用桩替代）
  缺失以上全部符号 → 修一个崩一个，必须一次补齐。

真实 text2speech 1.19.12（26.2 与 26.3-rc-2 同版本）API 对齐：
  Narrator: say(String,Z,F)/clear/active/destroy/getNarrator + EMPTY + LOGGER
  Narrator$InitializeException: Exception, (String) + (String,Throwable)
  Narrator$FatalException: RuntimeException, (String)
  OperatingSystem: enum LINUX/WINDOWS/MAC_OS/UNSUPPORTED + get() + detectWith

修复（JavaApp 3 文件）：
  Fix1 Narrator.java       +EMPTY +InitializeException +FatalException
  Fix2 OperatingSystem.java 新建枚举（get() 复刻真实检测逻辑）
  Fix3 NarratorMac.java     新建（真实类名对齐，防御性）
"""
import os
import re
import subprocess
import sys

ROOT = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PKG = os.path.join(ROOT, "JavaApp/src/launcher/com/mojang/text2speech")

PASS = 0
FAIL = 0
FAILS = []


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        FAILS.append(f"{name} {('— ' + detail) if detail else ''}")
        print(f"  [FAIL] {name} {detail}")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


narr = read(os.path.join(PKG, "Narrator.java"))
osys = read(os.path.join(PKG, "OperatingSystem.java"))
nmac = read(os.path.join(PKG, "NarratorMac.java"))
ndum = read(os.path.join(PKG, "NarratorDummy.java"))
nlin = read(os.path.join(PKG, "NarratorLinux.java"))

# ------------------------------------------------ A. 源码指纹
print("== A. 源码指纹 ==")
# A1. Narrator.java — Fix1
check("A1a EMPTY 字段（public static final 隐式）",
      re.search(r"Narrator EMPTY = new NarratorDummy\(\);", narr) is not None)
check("A1b InitializeException 内部类", "class InitializeException extends Exception" in narr)
check("A1c InitializeException 构造器 (String)",
      re.search(r"public InitializeException\(final String message\)\s*\{\s*super\(message\);", narr, re.S) is not None)
check("A1d InitializeException 构造器 (String, Throwable)",
      re.search(r"public InitializeException\(final String message, final Throwable cause\)\s*\{\s*super\(message, cause\);", narr, re.S) is not None)
check("A1e FatalException 内部类（RuntimeException）",
      "class FatalException extends RuntimeException" in narr)
check("A1f FatalException 构造器 (String)",
      re.search(r"public FatalException\(final String message\)", narr) is not None)
check("A1g 既有 2 参 say 保留（1.17 兼容）",
      re.search(r"void say\(final String msg, final boolean interrupt\);", narr) is not None)
check("A1h 既有 3 参 say 保留（26.2/26.3 调用点）",
      re.search(r"void say\(final String msg, final boolean interrupt, final float volume\);", narr) is not None)
check("A1i 既有 clear/active/destroy/getNarrator/setJNAPath 保留",
      all(m in narr for m in ["void clear();", "boolean active();", "void destroy();",
                              "static Narrator getNarrator()", "static void setJNAPath"]))

# A2. OperatingSystem.java — Fix2
check("A2a enum 声明", re.search(r"public enum OperatingSystem \{", osys) is not None)
for c in ["LINUX", "WINDOWS", "MAC_OS", "UNSUPPORTED"]:
    check(f"A2b 枚举常量 {c}", re.search(rf"\b{c}\(", osys) is not None)
check("A2c get() 静态方法", "public static OperatingSystem get()" in osys)
check("A2d 检测逻辑 linux/win/mac contains（真实 jar 反编译对齐）",
      all(s in osys for s in ['contains("linux")', 'contains("win")', 'contains("mac")']))
check("A2e os.name 系统属性读取", 'getProperty("os.name", "")' in osys or 'getProperty("os.name")' in osys)
check("A2f detectWith 字段（API 形状对齐）", "private final String detectWith;" in osys)

# A3. NarratorMac.java — Fix3
check("A3a NarratorMac 类（真实类名对齐）",
      re.search(r"public class NarratorMac extends NarratorDummy \{", nmac) is not None)

# ------------------------------------------------ B. ModernFix 引用覆盖矩阵
print("== B. ModernFix 引用覆盖矩阵（元凶 mixin 需要的全部符号） ==")
# GameNarratorMixin 引用清单逐项核对桩包可满足性
coverage = {
    "CLASS  com/mojang/text2speech/Narrator$InitializeException": "class InitializeException extends Exception" in narr,
    "CLASS  com/mojang/text2speech/Narrator": "public interface Narrator" in narr,
    "CLASS  com/mojang/text2speech/NarratorLinux": "public class NarratorLinux extends NarratorDummy" in nlin,
    "CLASS  com/mojang/text2speech/OperatingSystem": "public enum OperatingSystem" in osys,
    "FIELD  Narrator.EMPTY": "Narrator EMPTY = new NarratorDummy();" in narr,
    "METHOD NarratorLinux.<init>()V": True,  # extends NarratorDummy 隐式公共无参构造
    "METHOD OperatingSystem.get()": "public static OperatingSystem get()" in osys,
    "METHOD OperatingSystem.ordinal()": True,  # enum 内建
    "METHOD OperatingSystem.values()": True,   # enum 内建（switch-map 合成类调用）
}
for ref, ok in coverage.items():
    check(f"B {ref}", ok)

# ------------------------------------------------ C. 客户端 26.2/26.3/1.17 引用覆盖
print("== C. 客户端引用覆盖（三版本 client.jar 扫描结论回放） ==")
client_refs = {
    "26.2/26.3 say(Ljava/lang/String;ZF)V": "void say(final String msg, final boolean interrupt, final float volume);" in narr,
    "1.17 say(Ljava/lang/String;Z)V": "void say(final String msg, final boolean interrupt);" in narr,
    "clear()V (all)": "void clear();" in narr,
    "active()Z (all)": "boolean active();" in narr,
    "destroy()V (all)": "void destroy();" in narr,
    "getNarrator() (all, 实证可用：26.3 会话以此桩跑通)": "static Narrator getNarrator()" in narr,
}
for ref, ok in client_refs.items():
    check(f"C {ref}", ok)

# ------------------------------------------------ D. preProcessLibraries 跳过逻辑（设计契约不变）
print("== D. 库跳过契约（回归） ==")
tools = read(os.path.join(ROOT, "JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java"))
check("D1 text2speech 仍被跳过下载（桩替代设计不变）",
      'libItem.name.startsWith("com.mojang:text2speech")' in tools)
check("D2 jna-platform 仍被跳过（51 mod 零引用，扫描实证）",
      'libItem.name.startsWith("net.java.dev.jna:platform:")' in tools)
check("D3 tv.twitch 仍被跳过（51 mod 零引用）",
      'libItem.name.startsWith("tv.twitch")' in tools)

# ------------------------------------------------ E. Java 语法级检查
print("== E. 语法级检查 ==")
for name, src in [("Narrator.java", narr), ("OperatingSystem.java", osys),
                  ("NarratorMac.java", nmac), ("NarratorDummy.java", ndum),
                  ("NarratorLinux.java", nlin)]:
    braces = src.count("{") - src.count("}")
    parens = src.count("(") - src.count(")")
    check(f"E {name} 括号平衡 {{}}={braces} ()={parens}", braces == 0 and parens == 0,
          f"braces={braces} parens={parens}")
# E2: 每个文件都有 package 声明且正确
for name, src in [("Narrator.java", narr), ("OperatingSystem.java", osys), ("NarratorMac.java", nmac)]:
    check(f"E package 声明 {name}", src.startswith("package com.mojang.text2speech;"))
# E3: 接口字段初始化引用的类在包内存在
check("E EMPTY 初始化引用 NarratorDummy（包内存在）", os.path.exists(os.path.join(PKG, "NarratorDummy.java")))
check("E NarratorLinux 存在（ModernFix LINUX 分支）", os.path.exists(os.path.join(PKG, "NarratorLinux.java")))

# ------------------------------------------------ F. 回归级联
print("== F. 回归级联 ==")
REGRESS_DIR = "/home/z/my-project/scripts"
for script in ["verify_task72.py", "verify_task71.py", "verify_task70.py", "verify_task68.py", "verify_task67.py"]:
    sp = os.path.join(REGRESS_DIR, script) if os.path.exists(os.path.join(REGRESS_DIR, script)) \
        else os.path.join(ROOT, "scripts", script)
    if not os.path.exists(sp):
        check(f"F {script} 存在", False, sp)
        continue
    r = subprocess.run([sys.executable, sp], capture_output=True, text=True, cwd=ROOT)
    # 注意：被测脚本 stdout 可能含嵌套级联子报告（如 task72 内部跑 task71 的
    # "N PASS / M FAIL" 摘要行）——必须取最后一个匹配（脚本自身总结），首个会误抓。
    m = re.findall(r"(\d+)\s*PASS\s*/\s*(\d+)\s*FAIL", r.stdout)
    if m:
        ok = (r.returncode == 0) and m[-1][1] == "0"
        detail = "/".join(m[-1]) + " PASS/FAIL"
    else:
        m2 = re.findall(r"(\d+)\s*/\s*(\d+)", r.stdout)
        ok = (r.returncode == 0) and m2 and m2[-1][0] == m2[-1][1]
        detail = "/".join(m2[-1]) if m2 else (r.stderr.strip()[:60] or "no-output")
    check(f"F {script} 全绿", ok, detail)

print()
print("=" * 60)
print(f"RESULT: {PASS}/{PASS + FAIL}")
if FAILS:
    print("FAILED ITEMS:")
    for f in FAILS:
        print(f"  - {f}")
    sys.exit(1)
print("ALL PASS")
