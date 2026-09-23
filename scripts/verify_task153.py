#!/usr/bin/env python3
"""Task153 verifier: FSR geometry arbitration on MobileGL + Forge bootclasspath isolation.

Fixes three device-reported defects (7d51c28 / 0aac3aa / 68f5706 log set):
  1. Vulkan 花屏 + ES 方块不渲染 -- the mgl_fsr pre-swap chain drew its
     EASU/RCAS output at the launcher-BELIEVED surface (ame_surfaceWidth,
     2360x1640) while the MobileGL renderer pins its EGL backbuffer to MC's
     window belief (1180x820 under Task83 FSR linkage): the oversized draw
     clipped to a quarter every frame. Task148's "builtin FSR1 redirect"
     theory is disproven for the shipped binary (strings: no fsr1Setting in
     libMobileGL.dylib -- config is MOBILEGL_* env vars only).
  2. Deferred FSR shrink -- launch MobileGL at the FULL window so the
     renderer creates a full-size backbuffer, then push the render window
     once the backbuffer is confirmed full (observed surface-stays-big
     behavior, 403a459 session). No-headroom fallback = direct present +
     CA scale (zero corruption either way).
  3. Forge 1.20.1 launch ResolutionException (split package
     com.mojang.blaze3d.platform between modules "minecraft" and "launcher")
     -- launcher-side jars move to -Xbootclasspath/a for Forge sessions
     (boot unnamed module: no split check, shadowing preserved via
     delegation), -cp keeps lwjgl only.

Checks: A mgl_fsr geometry / B deferred shrink state machine / C SurfaceVC
arming / D environ globals / E Forge isolation / F syntax & balance /
G log anchors.
"""
import os
import re
import sys

REPO = os.environ.get("AME_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
FAILED = []
PASSED = 0


def check(name, cond, detail=""):
    global PASSED
    if cond:
        PASSED += 1
        print(f"  [PASS] {name}")
    else:
        FAILED.append(name)
        print(f"  [FAIL] {name}  {detail}")


def rd(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8") as f:
        return f.read()


def balance(path_rel):
    src = rd(path_rel)
    depth = 0
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 1
                i += 1
        elif c == "'":
            i += 1
            while i < n and src[i] != "'":
                if src[i] == "\\":
                    i += 1
                i += 1
        elif src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        elif c in "{}":
            depth += 1 if c == "{" else -1
        i += 1
    return depth


mf = rd("Natives/ctxbridges/mgl_fsr.mm")
jl = rd("Natives/JavaLauncher.m")
sv = rd("Natives/SurfaceViewController.m")
eh = rd("Natives/environ.h")

print("== A. mgl_fsr 真实后缓冲几何仲裁 ==")
check("A1 病历注释：MobileGL surface 钉在窗口信念 + 信念尺寸溢出裁切机理记录",
      "MobileGL" in mf and "把 EGL window surface" in mf.replace("\n", " ") or
      ("钉在 MC 窗口信念" in mf and "只有左下四分之一落图" in mf))
check("A2 EGL 查询入口三件套解析（eglGetCurrentDisplay/CurrentSurface/QuerySurface）",
      all(f'{{"{s}"' in mf for s in
          ["eglGetCurrentDisplay", "eglGetCurrentSurface", "eglQuerySurface"]))
check("A3 查询函数存在且防御完整（无 display/surface/非正尺寸全 false）",
      "static bool ame153_query_backbuffer(int *outW, int *outH)" in mf and
      mf.count("return false;") >= 5 and
      "AME153_EGL_WIDTH   0x3057" in mf and "AME153_EGL_HEIGHT  0x3056" in mf and
      "AME153_EGL_DRAW    0x3059" in mf)
check("A4 目标尺寸改用实测后缓冲（upscale 调用点传 bbW/bbH，不再传 ame_surfaceWidth）",
      "ame119_fsr_upscale(inW, inH, bbW, bbH)" in mf and
      "ame119_fsr_upscale(inW, inH, surfW, surfH)" not in mf)
check("A5 查询失败零开销跳过（绝不按信念盲画）+ 一次性日志",
      "Task153 backbuffer query unavailable" in mf)
check("A6 自愈恢复窗口尺寸用实测后缓冲（防二次溢出）",
      "restoring MC window to backbuffer %dx%d" in mf and
      "CallbackBridge_nativeSendScreenSize(bbW, bbH);" in mf)
check("A7 视口闸门改按实测后缓冲（vp <= bbW 而非 surfW）",
      "vp[2] <= bbW && vp[3] <= bbH" in mf and
      "vp[2] <= surfW && vp[3] <= surfH" not in mf)

print("== B. 延迟缩窗状态机（mgl_fsr 消费侧） ==")
check("B1 武装时先确认后缓冲全尺寸（believed-8 容差）再下发缩窗",
      "ame153_fsr_deferred_armed" in mf and
      "bbW >= believedW - 8 && bbH >= believedH - 8" in mf and
      "ame153_fsr_pending_render_w" in mf)
check("B2 缩窗下发日志锚点",
      "Task153 deferred shrink applied" in mf)
check("B3 无余量兜底：直呈零花屏 + 输入除数归一（Task139 同款）",
      "no upscale headroom" in mf and
      mf.count("ame139_fsr_heal_reset_input_scale()") >= 2)
check("B4 缩窗当帧返回不采样（让 MC 消化窗口变更）",
      mf.find("CallbackBridge_nativeSendScreenSize(ame153_fsr_pending_render_w,") < mf.find("本帧让 MC 消化窗口变更"))

print("== C. SurfaceViewController 武装侧（Task154 重锚：延迟缩窗已退役）==")
check("C1 延迟分支退役：MobileGL 不再全尺寸特殊启动，走统一 renderW 路径",
      "Task153 MobileGL deferred FSR shrink" not in sv and
      "windowWidth = ame153_renderW;" in sv and
      "延迟缩窗分支退役" in sv.replace("\n", ""))
check("C2 非 MobileGL（zink/MobileGlues）直缩路径保留",
      sv.find("ame153_fsr_deferred_armed = 0;") > 0 and
      sv.find("windowWidth = ame153_renderW;") > sv.find("ame153_fsr_deferred_armed = 0;"))
check("C3 武装全局清理：armed 残留清零（跨渲染器会话不复用旧武装位）",
      "ame153_fsr_pending_render_w = ame153_renderW;" not in sv and
      "清零以防残留" in sv.replace("\n", ""))

print("== D. environ.h 全局声明 ==")
check("D1 四项全局（armed + pending render + believed surface）按 AME_ENVIRON_DECL 声明",
      "AME_ENVIRON_DECL int ame153_fsr_deferred_armed;" in eh and
      "AME_ENVIRON_DECL int ame153_fsr_pending_render_w, ame153_fsr_pending_render_h;" in eh and
      "AME_ENVIRON_DECL int ame153_fsr_believed_surface_w, ame153_fsr_believed_surface_h;" in eh)

print("== E. Forge 隔离（Task154 重锚：ignoreList 方案替代 bootclasspath）==")
check("E1 病历注释：ResolutionException split package 机理链记录",
      "ResolutionException" in jl and "split package" in jl)
check("E2 Forge 判定 = 版本 JSON mainClass 含 cpw.mods.bootstraplauncher",
      'containsString:@"cpw.mods.bootstraplauncher"' in jl)
check("E3 启动器侧 jar 回归普通 -cp（bootAppendBuilder 已撤销）",
      "[bootAppendBuilder appendFormat:@\"%@/%@:\", librariesPath, libFile];" not in jl and
      "[classpathBuilder appendFormat:@\"%@/%@:\", librariesPath, libFile];" in jl)
check("E4 ignoreList 注入替代 bootclasspath 推送（同名 -D 后者生效 + 并入 JSON 自带值）",
      'PUSH_MARGV_FORMAT(@"-DignoreList=%@", ame154_ignore);' in jl and
      "Task154 Forge ignoreList shield" in jl and
      'PUSH_MARGV_FORMAT(@"-Xbootclasspath/a:%@", bootAppendBuilder);' not in jl)
check("E5 非 Forge 会话 classpath 组装原样（lwjgl 通配 + launchJar 前插不变）",
      '[classpathBuilder appendFormat:@"%@/%@:", librariesPath, libFile];' in jl and
      "launchTarget, classpath];" in jl)
check("E6 launchJar（headless 安装器）路径不受影响（isForgeLaunch 判定含 !launchJar）",
      "if (!launchJar && [launchTarget isKindOfClass:NSDictionary.class]) {" in jl)

print("== F. 语法与配平 ==")
for f in ["Natives/ctxbridges/mgl_fsr.mm", "Natives/JavaLauncher.m",
          "Natives/SurfaceViewController.m", "Natives/environ.h"]:
    check(f"F 配平 {f}", balance(f) == 0, f"delta={balance(f)}")

print("== G. 既有锚点不回归 ==")
check("G1 Task148 仲裁块原样（builtin 探测保留）",
      "ame148_detect_builtin_fsr_redirect" in mf and
      "Task148 arbitration verdict" in mf)
check("G2 Task119/130 engaged/RCAS 锚点原样",
      "Task119 FSR1 upscale engaged (MobileGL)" in mf and
      "Task130 RCAS engaged (MobileGL)" in mf)
check("G3 gl_bridge 调用点次序不变（卫兵后、swap 前）",
      "ame_mgl_fsr_before_swap();" in rd("Natives/ctxbridges/gl_bridge.m"))
check("G4 Task139 复位入口仍被 mgl_fsr 引用（>=2 处）",
      rd("Natives/ctxbridges/mgl_fsr.mm").count("ame139_fsr_heal_reset_input_scale()") >= 2)

print()
print(f"Result: {PASSED} passed, {len(FAILED)} failed")
if FAILED:
    print("FAILED:", *FAILED, sep="\n  - ")
    sys.exit(1)
print("ALL GREEN")
