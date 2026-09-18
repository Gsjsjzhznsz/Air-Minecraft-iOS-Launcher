#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task 84 验证脚本：zink FSR 编译三连关收官 + 日志判读闭环 + FAQ Arm ASR

背景（75c5e14 装机日志，Task83b IPA run 35097960207 会话）：
  * Task83b 版本自适应真机生效（#version adapted: 450 -> 410），
    但片元编译倒在下一关：no function with name packHalf2x16
    （GLSL 4.20 核心内建，zink/MoltenVK GLSL 4.10 上限没有）；
  * stage=35632 实锤 osm_bridge.mm 的 GL_FRAGMENT_SHADER 被误写 0x8B30
    （规范值 0x8B92=35730）；
  * 兜底恢复正常（无绿屏），键盘链路真机全通（executebtn → button text
    → SDL text input），会话全程全分辨率直渲（FSR 未启用）。

覆盖范围：
  A. osm_bridge.mm 枚举勘误（0x8B92 在位、0x8B30 绝迹、注释勘误）
  B. FSRShaderSource.h 半精度打包回退（守卫/顺序/完整性/MG 零变化）
  C. 算法位级验证（scripts/verify_task84_packhalf.py 对照 numpy float16）
  D. FAQ（Arm ASR 条目 + 注册 + greenFx 两轮措辞）
  E. 装机日志证据（75c5e14：编译链 + 兜底 + 键盘闭环 + 全分辨率会话）
  F. 级联（verify_task83 / 82 仍绿）
"""
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8") as f:
        return f.read()


print("===== A. osm_bridge.mm 枚举勘误 =====")
osm = read("Natives/ctxbridges/osm_bridge.mm")
check("A1 GL_FRAGMENT_SHADER 规范值 0x8B92",
      re.search(r"#define GL_FRAGMENT_SHADER\s+0x8B92", osm) is not None)
check("A2 错值 0x8B30 不再用于任何 #define（勘误注释中的历史引用除外）",
      re.search(r"#define\s+\w+\s+0x8B30", osm) is None)
check("A3 GL_VERTEX_SHADER 0x8B31 未动",
      re.search(r"#define GL_VERTEX_SHADER\s+0x8B31", osm) is not None)
check("A4 勘误注释在位（75c5e14 stage=35632 实锤记录）",
      "stage=35632" in osm and "0x8B92（35730）" in osm)
check("A5 Task83b 错误论断已修正（packHalf2x16 非 4.00 内建）",
      "4.20 核心" in osm and "Task83b 注释称 4.00 内建有误" in osm)

print("===== B. FSRShaderSource.h 半精度打包回退 =====")
fsrh = read("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h")
# raw string 完整性
check("B1 raw string 定界符完整（2 对）",
      fsrh.count('R"fsr_glsl(') == 2 and fsrh.count(')fsr_glsl"') == 2)
fs = fsrh.split('R"fsr_glsl(')[2].split(')fsr_glsl"')[0]  # FSR_FSSource 内容
start = fs.index("#if __VERSION__ < 420")
end = fs.index("#endif", fs.index("unpackHalf2x16(uint a)")) + len("#endif")
block = fs[start:end]
check("B2 __VERSION__ < 420 守卫（4.20+ 核心内建路径零变化）",
      block.count("#if") == 1 and block.count("#endif") == 1)
check("B3 回退函数四件套在位",
      all(k in block for k in ("ame84PackHalf1", "packHalf2x16(vec2 a)",
                                "ame84UnpackHalf1", "unpackHalf2x16(uint a)")))
check("B4 定义先于首次使用（AU1_AH1_AF1_x 调用点）",
      block.index("uint packHalf2x16(vec2 a)")
      < fs.index("AU1_AH1_AF1_x(AF1 a){return packHalf2x16"))
check("B5 回退块仅用 3.30+ 内建（无 image/atomic/barrier/fma）",
      "floatBitsToUint" in block and "uintBitsToFloat" in block
      and not re.search(r"\b(image|atomic|barrier|fma|memoryBarrier)", block))
check("B6 无 4.20+ 内建残留（imageLoad 仅注释行）",
      all(line.lstrip().startswith("//") or "imageLoad" not in line
          for line in fs.splitlines()))
check("B7 #version 450 首行未动（MG 原路径零变化）",
      fs.lstrip("\n").startswith("#version 450"))
check("B8 回退块无 ASCII 双引号（历史引号配对校验器安全）",
      '"' not in block)
check("B9 回退块花括号/圆括号平衡",
      block.count("{") == block.count("}") and block.count("(") == block.count(")"))
check("B10 RNE 三路径齐备（次正规/进位/Inf）",
      block.count("0x7c00u") == 3 and "126u - e" in block
      and "113u - adj" in block and "(he << 10)" in block)

print("===== C. 算法位级验证（numpy float16 RNE 参考） =====")
PACKHALF = os.path.join(REPO, "scripts", "verify_task84_packhalf.py")
if not os.path.exists(PACKHALF):
    PACKHALF = "/home/z/my-project/scripts/verify_task84_packhalf.py"
r = subprocess.run([sys.executable, PACKHALF],
                   capture_output=True, text=True, timeout=120)
check("C1 打包/解包算法位级全等（64k pack + 50k unpack + 4k roundtrip）",
      r.returncode == 0 and "ALL BIT-EXACT" in r.stdout, r.stdout.strip()[-120:])

print("===== D. FAQ（Arm ASR 条目） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("D1 34 条目（Task99 +2 macMenuStub/fsrCorner；Task86 +bigpack，Task87 +ltw26，Task94 +sodiumLwjgl，Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl，Task103 +sodiumGlsl，Task106 +sparkProfiler，Task85 时为 24）", len(faq_items) == 34, f"got {len(faq_items)}")
check("D2 armAsr 条目在位（问题 + 计算着色器/GL 4.1 边界 + Mali 调优定性）",
      "Arm ASR（Arm Accuracy Super Resolution）代替 FSR" in helpvc
      and "4.3 才有的计算着色器" in helpvc
      and "Mali GPU" in helpvc)
check("D3 armAsr 注册进渲染与性能分类（Task87 起 ltw26 插在 renderer 之后）",
      re.search(r"@\[ renderer, ltw26, mgLag, fsr, metalFx, armAsr, upscalerAlt, fpsUnlock", helpvc) is not None)
check("D4 armAsr 与 FSR1 同源定性（空间超分、无运动向量依赖）",
      "单帧空间超分" in helpvc and "从 FSR1 衍生" in helpvc)
check("D5 greenFx 两轮修复措辞",
      "已修复（两轮）" in helpvc and "半精度打包函数" in helpvc)
check("D6 fsr 条目 Zink 全面适配措辞更新",
      "版本自动降级 + 半精度打包函数补齐" in helpvc)

print("===== E. 装机日志证据（75c5e14，Task83b IPA 会话） =====")
# Task86 更新：用户上传了新日志对（f17ef7b：BMC2 卡死会话 + 26.3 zink 会话），
# Task83b IPA 会话证据钉死到 git 历史 75c5e14:latestlog.txt，不再读可变工作区日志。
_r = subprocess.run(["git", "show", "75c5e14:latestlog.txt"], cwd=REPO,
                    capture_output=True, text=True, timeout=60)
log = _r.stdout if _r.returncode == 0 else ""
if log:
    check("E1 Task83b 版本自适应真机生效（450->410）",
          "#version adapted: 450 -> 410" in log)
    check("E2 编译倒在 packHalf2x16（Task84 动机实锤）",
          "no function with name 'packHalf2x16'" in log)
    check("E3 错枚举上日志（stage=35632 = 0x8B30）",
          "stage=35632" in log)
    check("E4 兜底真实恢复（无绿屏：SDL 0x207 全分辨率）",
          "window size -> SDL 0x207 2360x1640" in log
          and "restoring MC window to surface 2360x1640" in log)
    check("E5 键盘链路真机闭环（executebtn T → button text 't' → SDL input）",
          "Task83b executebtn #3: name=T action=0 keycodes=[84,0,0,0]" in log
          and "Task83 button text #1: glfwKey=84 -> 't'" in log
          and 'Task82 SDL text input #1: U+0074 -> "t"' in log)
    check("E6 字母连打实证（button text >= 8 条，用户聊天输入）",
          len(re.findall(r"Task83 button text #\d+", log)) >= 8)
    check("E7 会话无 DEVICE_LOST（后台冻结未触发）",
          "DEVICE_LOST" not in log)
else:
    check("E log present", False, "git fixture 75c5e14:latestlog.txt missing")

print("===== F. 级联 =====")
for casc, name in (("scripts/verify_task83.py", "Task83"),
                   ("scripts/verify_task82.py", "Task82")):
    r = subprocess.run([sys.executable, os.path.join(REPO, casc)],
                       capture_output=True, text=True, timeout=180)
    tail = (r.stdout + r.stderr).strip().splitlines()[-1] if (r.stdout + r.stderr).strip() else ""
    check(f"F 级联 {name} 仍绿", r.returncode == 0, tail[:100])

print(f"\nRESULT: {PASS}/{PASS + FAIL} PASS" + ("" if FAIL == 0 else "  -- FAILURES PRESENT"))
sys.exit(0 if FAIL == 0 else 1)
