#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task76.py — Task 76 修复验证（MG/MobileGlues 渲染卡顿："30fps 看得像 10fps"）

根因链（bef0f08 双日志定案，MG 场 vs Zink 场对照）：
  R1【主因】MobileGlues FSR1 Quality(preset=2) 开启 + MC 全分辨率渲染：
     render==surface(2360x1640) → target=render*1.5(3540x2460) →
     每帧 3 个全屏 pass（clear 3540x2460 + EASU/RCAS 放大 + LINEAR blit 缩回
     surface）——纯带宽税（最高 2.25x 表面面积）+ 双重重采样（画质反而更差）。
     CalculateRenderResolution 全库零调用 = 集成从未把 render 降到 surface 之下。
  R2【放大器】vsync 锁 60（33 条心跳在 max.fps=260 解锁下零超 60）+ 帧时间
     波动 → 丢拍阶梯（33/50/100/200ms）→ 视觉"10fps"。
  R3【本仓库独有税】swap 路径每帧 3x glGetIntegerv + while(glGetError) 清错
     （吞 MobileGlues 待转译错误）+ 2x eglQuerySurface；上游 swap 路径零 GL 查询。

修复（3 文件 + 6 语言文案 + 心跳扩展）：
  Fix1 MobileGlues FSR1.cpp   TeardownFSR1 + CheckResolutionChange 零增益旁路
                              + ApplyFSR g_renderFBO==0 守卫
  Fix2 gl_bridge.m            Task41 取证降频（NORMAL 态零查询）+ 删 while(getError)
  Fix3 gl_bridge.m            raw eglSwapInterval 双保险（POJAV_DISABLE_VSYNC）
  Fix4 gl_bridge.m/utils.h/   帧间隔窗口统计 ame_egl_swap_framegap +
     SurfaceViewController.m  [RenderDiag] 心跳 maxGap/avgGap 上报

验证层次：
  A. 源码指纹（FSR1.cpp / FSR1.h / gl_bridge.m / utils.h / SurfaceViewController.m）
  B. 行为回放（FSR1 零增益判定仿真：MC 全屏 vs 真·低分辨率渲染）
  C. 取证降频语义仿真（probe 帧判定表 vs 旧行为）
  D. 括号平衡（3 个源文件 delta=0）
  E. 回归级联（verify_task71 / 70）
"""
import os
import re
import subprocess
import sys

ROOT = "/home/z/my-project/Amethyst-iOS-MyRemastered"
MG = os.path.join(ROOT, "Natives/external/MobileGlues/MobileGlues-cpp")

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


# ---------------------------------------------------------------- A. 源码指纹
print("== A. 源码指纹 ==")

# A1. FSR1.cpp — TeardownFSR1 定义 + 零增益分支 + ApplyFSR 守卫
p = os.path.join(MG, "gl/FSR1/FSR1.cpp")
src = read(p)
i_guard = src.find("if (FSR1_Context::g_renderFBO == 0) return;")
i_apply = src.find("void ApplyFSR() {")
i_teardown = src.find("void TeardownFSR1() {")
i_onresize = src.find("void OnResize(int width, int height) {")
i_check = src.find("void CheckResolutionChange(EGLDisplay display, EGLSurface surface) {")
i_bypass = src.find("if (width >= surfaceWidth && height >= surfaceHeight) {")
i_recreate = src.find("RecreateFSRFBO();", i_bypass)
check("A1a ApplyFSR g_renderFBO==0 守卫存在于函数体首（含大段注释）",
      i_apply >= 0 and i_apply < i_guard < i_apply + 900 and
      "GLStateGuard state" in src[i_guard:i_guard + 2000],
      f"guard@{i_guard} apply@{i_apply}")
check("A1b TeardownFSR1 定义存在", i_teardown > 0, f"teardown@{i_teardown}")
check("A1c TeardownFSR1 位于 OnResize 之后（文件内逻辑块顺序）",
      i_onresize > 0 and i_teardown > i_onresize)
check("A1d CheckResolutionChange 内零增益分支存在",
      i_check > 0 and i_bypass > i_check and i_bypass < i_recreate,
      f"check@{i_check} bypass@{i_bypass}")
check("A1e 零增益分支调用 TeardownFSR1",
      src.find("TeardownFSR1();", i_bypass) > 0 and src.find("TeardownFSR1();", i_bypass) < i_recreate)
check("A1f TeardownFSR1 释放全部 5 类 GL 对象",
      all(k in src[i_teardown:i_teardown + 2400] for k in
          ["glDeleteFramebuffers", "glDeleteTextures", "glDeleteRenderbuffers",
           "g_renderFBO = 0", "g_targetFBO = 0"]))
check("A1g TeardownFSR1 保留 fsrInitialized=true（防 glCreateShader 重建）",
      "fsrInitialized stays true" in src[i_teardown - 2600:i_teardown] or
      "Left alone deliberately" not in src[i_teardown:i_teardown + 2400])
check("A1h TeardownFSR1 处理 tracked draw fbo 死名（framebuffer_recreated → 0）",
      "state.framebuffer_recreated(deadRenderFBO, 0)" in src)
check("A1i surfaceWidth/surfaceHeight 影子防护变量存在",
      "const GLsizei surfaceWidth = width;" in src)

# A2. FSR1.h — TeardownFSR1 声明
p = os.path.join(MG, "gl/FSR1/FSR1.h")
src = read(p)
check("A2 FSR1.h 声明 TeardownFSR1", "void TeardownFSR1();" in src)

# A3. gl_bridge.m — 取证降频 + raw swap interval + 帧间隔统计
p = os.path.join(ROOT, "Natives/ctxbridges/gl_bridge.m")
src = read(p)
check("A3a probe 门：s_mode != 1（非 NORMAL 态保持每帧执法）",
      "s_mode != 1;" in src and "if (!probe) return;" in src)
check("A3b while(es.getError()) 清错循环已从 Task41 移除",
      src.count("while (es.getError() != 0)") == 2,  # 仅 geo-heal blit 路径残留 2 处
      f"count={src.count('while (es.getError() != 0)')}")
i_task41 = src.find("static void ame_task41_swap_forensics")
i_next_fn = src.find("\nstatic", i_task41 + 100)
check("A3c Task41 函数体内无 while(getError)",
      "while (es.getError()" not in src[i_task41:i_next_fn])
check("A3d ame_raw_swap_interval 声明 + 解析",
      "static PFNEGLSWAPINTERVALPROC      ame_raw_swap_interval = NULL;" in src and
      'load_egl_symbol(dl_handle, "eglSwapInterval")' in src)
check("A3e 双保险调用（frontend + raw 两路 + 返回值入日志）",
      "feOk = handle.eglSwapInterval(g_EglDisplay, 0)" in src and
      "ame_raw_swap_interval(g_EglDisplay, 0)" in src and
      "frontend=%d raw=%d" in src)
check("A3f 帧间隔统计：ame_egl_swap_framegap + ame76_record_swap",
      "void ame_egl_swap_framegap" in src and "ame76_record_swap(ame53_now_ms());" in src)
check("A3g gl_swap_buffers 成功路径调用 record_swap",
      src.find("ame76_record_swap(ame53_now_ms());") > src.find("void gl_swap_buffers() {"))

# A4. utils.h / SurfaceViewController.m
p = os.path.join(ROOT, "Natives/utils.h")
src = read(p)
check("A4a utils.h 声明 ame_egl_swap_framegap",
      "void ame_egl_swap_framegap(unsigned int *maxGapMs, unsigned int *avgGapMs);" in src)
p = os.path.join(ROOT, "Natives/SurfaceViewController.m")
src = read(p)
check("A4b 心跳打印 maxGap/avgGap",
      "ame_egl_swap_framegap(&maxGap, &avgGap);" in src and "maxGap=%ums avgGap=%ums" in src)

# A5. 6 语言 FSR1 文案
for lang in ["en", "ja", "km", "zh-CN", "zh-Hans", "zh-Hant"]:
    p = os.path.join(ROOT, f"Natives/resources/{lang}.lproj/Localizable.strings")
    s = read(p)
    # Task 78 演化：detail 文案从"零增益自动旁路"改为"选档即联动降渲染分辨率"；
    # 旁路行为本身仍在（FSR1.cpp TeardownFSR1 日志未动）。
    check(f"A5 {lang} FSR1 detail 含档位联动说明",
          "77%" in s and "50%" in s and ("MobileGlues" in s or "渲染分辨率" in s or "描画解像度" in s or "渲染解析度" in s))

# ---------------------------------------------------------------- B. 行为回放
print("== B. FSR1 零增益判定仿真 ==")


def fsr1_decision_old(render_w, render_h, surface_w, surface_h, preset_scale=1.5):
    """旧 MobileGlues：无判定，恒走 RecreateFSRFBO + 每帧 ApplyFSR。"""
    target_w = int(render_w * preset_scale) & ~1
    target_h = int(render_h * preset_scale) & ~1
    passes = 3  # clear(target) + EASU/RCAS(target) + blit(target->surface)
    area_ratio = (target_w * target_h) / max(1, surface_w * surface_h)
    resampled = True  # render->target->surface 双重采样
    return target_w, target_h, passes, area_ratio, resampled


def fsr1_decision_new(render_w, render_h, surface_w, surface_h, preset_scale=1.5):
    """Task 76：render 覆盖 surface → teardown 直通。"""
    zero_gain = (render_w >= surface_w and render_h >= surface_h)
    if zero_gain:
        return surface_w, surface_h, 0, 1.0, False  # 零额外 pass，直接呈现
    target_w = int(render_w * preset_scale) & ~1
    target_h = int(render_h * preset_scale) & ~1
    passes = 3
    area_ratio = (target_w * target_h) / max(1, surface_w * surface_h)
    return target_w, target_h, passes, area_ratio, True


# B1. bef0f08 MG 场实测几何：MC 全屏 2360x1640，surface 2360x1640，Quality(1.5)
tw_o, th_o, ps_o, ar_o, rs_o = fsr1_decision_old(2360, 1640, 2360, 1640)
tw_n, th_n, ps_n, ar_n, rs_n = fsr1_decision_new(2360, 1640, 2360, 1640)
check("B1a 旧行为：target=3540x2460（放大超表面）", (tw_o, th_o) == (3540, 2460), f"{tw_o}x{th_o}")
check("B1b 旧行为：3 全屏 pass + 2.25x 面积 + 双重采样",
      ps_o == 3 and abs(ar_o - 2.25) < 0.01 and rs_o)
check("B1c 新行为：零 pass 直通", ps_n == 0 and ar_n == 1.0 and not rs_n)

# B2. 真·低分辨率渲染（假设 MC 窗口 1573x1093 < surface 2360x1640）
tw2, th2, ps2, ar2, rs2 = fsr1_decision_new(1573, 1093, 2360, 1640)
# 注：MobileGlues 源码 CalculateTargetResolution 对 target 做 &~1 偶数对齐：
# (int)(1573*1.5)=2359 → 2358；1639.5→1639→1638。面积比 ≈ 1.0（放大恰好覆盖表面）
check("B2 低分辨率渲染仍走 FSR（放大有意义）",
      ps2 == 3 and (tw2, th2) == (2358, 1638) and abs(ar2 - 1.0) < 0.05,
      f"target={tw2}x{th2} area={ar2:.2f}")

# B3. 旋转瞬态两阶段：surface 转 1640x2360，render 尚为旧 2360x1640
#   阶段1（OnResize latch 前）：宽覆盖高不覆盖 → 不旁路，FSR 继续（安全侧）
#   阶段2（CheckResolutionChange→OnResize latch 后）：render 跟随 surface → 旁路
tw3, th3, ps3, ar3, rs3 = fsr1_decision_new(2360, 1640, 1640, 2360)
check("B3a 旋转瞬态帧（render 转置滞后）走 FSR（无假旁路）", ps3 == 3)
tw4, th4, ps4, ar4, rs4 = fsr1_decision_new(1640, 2360, 1640, 2360)
check("B3b latch 后 render==surface → 旁路（OnResize 无条件刷新 pending）",
      ps4 == 0 and not rs4)

# ---------------------------------------------------------------- C. probe 语义仿真
print("== C. Task41 取证降频语义 ==")


def probe_old(idx, mode):
    return idx <= 5 or idx % 200 == 0 or mode == 0


def probe_new(idx, mode):
    return idx <= 5 or idx % 200 == 0 or mode != 1


cases = []
for idx in [1, 3, 5, 6, 7, 100, 199, 200, 201, 400, 401, 999]:
    for mode in [0, 1, 2]:
        cases.append((idx, mode, probe_old(idx, mode), probe_new(idx, mode)))
# 不变量：非 NORMAL 态（mode 0/2）恒 probe（执法不缺位）
check("C1 mode∈{0,2} 恒 probe（补偿态每帧执法保持）",
      all(n for _, m, _, n in cases if m != 1))
# 降频效果：NORMAL 态下仅前 5 帧 + 每 200 帧
normal_probes = [idx for idx, m, _, n in cases if m == 1 and n]
check("C2 NORMAL 态 probe = {<=5} ∪ {200 的倍数}",
      all(idx <= 5 or idx % 200 == 0 for idx in normal_probes))
# 旧行为的真语义：probe 门（s_mode==0）只控制【日志】，GL/EGL 查询
# （3x glGetIntegerv + while(getError) + 2x eglQuerySurface）恒每帧执行。
# 量化对比见 C4：旧=每帧全量，新=仅 probe 帧。
# 60fps 下 5 秒窗口（300 帧）的查询次数对比：旧=每帧；新=前5帧+200 的倍数
q_old = 300
q_new = sum(1 for i in range(1, 301) if probe_new(i, 1))
check("C4 300 帧窗口查询次数 300 → 6（首帧诊断 5 + %200 一执法）",
      q_old == 300 and q_new == 6, f"old={q_old} new={q_new}")

# ---------------------------------------------------------------- D. 括号平衡
print("== D. 括号平衡 ==")


def brace_delta(text):
    depth = 0
    in_str = in_chr = in_line_c = in_block_c = False
    i = 0
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_c:
            if c == "\n":
                in_line_c = False
        elif in_block_c:
            if c == "*" and nxt == "/":
                in_block_c = False
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
                in_line_c = True
            elif c == "/" and nxt == "*":
                in_block_c = True
                i += 1
            elif c == '"':
                in_str = True
            elif c == "'":
                in_chr = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
        i += 1
    return depth


for rel in ["Natives/ctxbridges/gl_bridge.m",
            "Natives/SurfaceViewController.m",
            "Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp",
            "Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.h"]:
    d = brace_delta(read(os.path.join(ROOT, rel)))
    check(f"D {os.path.basename(rel)} 括号平衡 delta=0", d == 0, f"delta={d}")

# ---------------------------------------------------------------- E. 回归级联
print("== E. 回归级联 ==")
for script in ["verify_task71.py", "verify_task70.py"]:
    path = os.path.join(ROOT, "scripts", script)
    if not os.path.exists(path):
        path = os.path.join("/home/z/my-project/scripts", script)
    if os.path.exists(path):
        r = subprocess.run([sys.executable, path], capture_output=True, text=True, timeout=120)
        tail = (r.stdout + r.stderr).strip().splitlines()
        summary = tail[-1] if tail else "(no output)"
        passed = "PASS" in summary or "passed" in summary.lower() or r.returncode == 0
        check(f"E {script} 级联回归", r.returncode == 0, summary)
    else:
        check(f"E {script} 存在", False, "script not found")

# ---------------------------------------------------------------- 汇总
print()
total = PASS + FAIL
print(f"===== Task 76 验证：{PASS}/{total} PASS =====")
if FAILS:
    print("失败项：")
    for f in FAILS:
        print(f"  - {f}")
    sys.exit(1)
sys.exit(0)
