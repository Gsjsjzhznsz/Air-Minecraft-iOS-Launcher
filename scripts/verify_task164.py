#!/usr/bin/env python3
"""Task164 验证器：ES/4.0 黑屏（RCAS 对齐）+ 壁纸默认值 + Vulkan FSR 矩阵。

用户反馈（56c8173 上传日志，678a76f 构建）：
  1. "es和4.0黑屏" —— latestlog.txt（ES 会话）：FSR/RCAS 全 engage、fps=58、
     swap 100% OK，屏幕黑；5.1.0 健康基线（a0ac656 latestlog.es/4.0）同管线
     但 EASU-only 有画面；mod 组合两场一致（continuity/iris 都在）→ delta
     = Task130 RCAS pass。四项对齐 zink 已验证形态：
     ① FsrRcasLoadF 边界 clamp（texelFetch 越界在 ANGLE Metal = UB）
     ② directToSurface 两分支 disable GL_STENCIL_TEST（五件套）
     ③ RCAS draw 显式 glActiveTexture(GL_TEXTURE0) + 每帧 sampler re-pin
     ④ 一次性 GPU 探针（fb0 边缘单像素 readback 分诊锚点）
  2. "现在的壁纸默认为半透明60%0%" —— 从未保存键被范围检查当已保存值：
     integerForKey 未保存返回 0 = 枚举半透明；floatForKey 未保存返回 0.0
     过 "< 0.0" 检查。三键统一 objectForKey == nil 判定。
  3. "vulkan没有fsr" —— libMobileGL 二进制零 FSR/EASU/RCAS 符号、无 config
     接口、伪 EGL（Task154 三重实证）→ 上游不可行；公告/FAQ 明示矩阵。

用法：python3 scripts/verify_task164.py
"""
import os
import sys

ROOT = os.environ.get('TASK164_REPO', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # Task168: portable default

def rd(rel):
    return open(f"{ROOT}/{rel}", encoding="utf-8", errors="replace").read()

results = []
def check(label, cond):
    results.append((label, bool(cond)))
    print(f"  [{'PASS' if cond else 'FAIL'}] {label}")

print("== A. RCAS 边界 clamp（FSRRCASSource.h，三 TU 共享）==")
rc = rd("Natives/ctxbridges/FSRRCASSource.h")
check("A1 FsrRcasLoadClamped 定义（textureSize 自查边界）",
      "AF4 FsrRcasLoadClamped(ASU2 p) {" in rc
      and "ASU2(textureSize(uInputTex, 0)) - ASU2(1)" in rc
      and "clamp(p, ASU2(0), ame164_max)" in rc)
check("A2 FsrRcasLoadF 转发到 clamp 版（原裸 texelFetch 退役）",
      "AF4 FsrRcasLoadF(ASU2 p) { return FsrRcasLoadClamped(p); }" in rc
      and "return texelFetch(uInputTex, p, 0); }" not in rc)
check("A3 病历注释（ANGLE Metal 越界 UB 与黑屏形态）",
      "MTLTexture read" in rc and "越界读是未定义行为" in rc or "undefined" in rc.lower() and "black" in rc.lower())
check("A4 原型链完整（FsrRcasF 前向声明仍在）",
      "AF4 FsrRcasLoadF(ASU2 p);" in rc)
# 括号平衡（原始字符串内的 GLSL）
check("A5 括号平衡（shader 源字符状态机）",
      rc.count("{") == rc.count("}") and rc.count("(") == rc.count(")"))

print("== B. FSR1.cpp RCAS/EASU pass 状态防护（zink 五件套对齐）==")
fsr = rd("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp")
check("B1 rcasOn 分支 disable 五状态（含 STENCIL）",
      fsr.count("GLES.glDisable(GL_STENCIL_TEST);") >= 2)
check("B1b EASU-only directToSurface 分支同样五状态",
      "Task164：stencil 对齐 zink 五件套" in fsr)
check("B2 RCAS draw 前显式 glActiveTexture(GL_TEXTURE0)",
      "GLES.glActiveTexture(GL_TEXTURE0);" in fsr)
check("B3 RCAS sampler 每帧 re-pin（zink 形态，location>=0 守卫）",
      "GLES.glUniform1i(FSR1_Context::g_rcasInputTexLoc, 0);" in fsr
      and "g_rcasInputTexLoc >= 0" in fsr)
check("B4 GPU 探针（fb0 边缘单像素 + glGetError 清扫 + 分诊文案）",
      "Task164 RCAS GPU probe" in fsr
      and "nonzero = draw landed on GPU" in fsr
      and "all-zero = RCAS quad never landed" in fsr)
check("B5 探针只执行一次（s_rcasEngaged 一次性块内）",
      "static bool s_rcasEngaged = false;" in fsr)
check("B6 EASU pass 仍画 targetFBO（管线顺序不变：EASU→target，RCAS→fb0）",
      fsr.find("GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, FSR1_Context::g_targetFBO);")
      < fsr.find("GLES.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);"))
check("B7 文件括号平衡",
      fsr.count("{") == fsr.count("}"))

print("== C. 壁纸首启默认值（BackgroundManager.m）==")
bm = rd("Natives/BackgroundManager.m")
check("C1 键判定（Task180 重锚：效果/背景透明度/按钮透明度/模糊 四键 objectForKey == nil）",
      "[defaults objectForKey:kBackgroundUIEffectKey]" in bm
      and "[defaults objectForKey:kBackgroundBgOpacityKey]" in bm
      and "[defaults objectForKey:kBackgroundBtnOpacityKey]" in bm
      and "[defaults objectForKey:kBackgroundBlurIntensityKey]" in bm)
check("C2 nil → BackgroundUIEffectBlur（默认毛玻璃）",
      "_uiEffect = BackgroundUIEffectBlur; // Task162/164：默认毛玻璃效果" in bm)
check("C3 nil → 0.75 / 1.0 / 0.0（Task180 重锚：背景 75% / 按钮 100% / 模糊 0%，用户备注定稿）",
      "_backgroundOpacity = 0.75;" in bm
      and "_buttonOpacity = 1.0;" in bm
      and "_blurIntensity = 0.0;" in bm)
check("C4 病历注释（范围检查的两个漏洞）",
      "枚举 0 = 半透明" in bm and "默认模糊 0%" in bm)
check("C5 显式保存值尊重（半透明/0% 可选）——越界兜底仍保留",
      "越界值（历史损坏数据）兜底毛玻璃" in bm)
check("C6 旧式 integerForKey/floatForKey 直接读默认的形态已退役",
      "_uiEffect = [defaults integerForKey:kBackgroundUIEffectKey];" not in bm
      and "_blurIntensity = [defaults floatForKey:kBackgroundBlurIntensityKey];" not in bm)

print("== D. Vulkan FSR 矩阵（公告 + version.h + libMobileGL 实证）==")
an = rd("announcements.json")
check("D1 Task164 公告在列（id 锚点）",
      "task164-fsr-blackscreen-defaults-2026-09-25" in an)
# Task169 重锚（诚实勘误，同 Task166 对 task165 矩阵的处理）：本检查原锚
# "Vulkan 直连后端暂不支持 FSR"——该结论已被 Task166/167 推翻（Metal 呈现层
# 拦截方案让 Vulkan 直连支持 FSR，装机实测工作）。旧口径在 Task169 的
# v6.0.0 发行文案改写中从发行公告退役；现在锚定发行公告的正式版口径。
check("D2 发行公告明示 Vulkan 直连支持 FSR（Task166/169 修订口径；旧『暂不支持』结论已退役）",
      "Vulkan 直连后端通过 Metal 呈现层拦截方案支持 FSR" in an
      and "切到 GLES 或 OpenGL 4.0" in an)
check("D3 公告明示 GLES/4.0 = 完整 FSR（EASU+RCAS）",
      "EASU 高质量放大 + RCAS 锐化" in an)
check("D4 v6.0.0 失实表述已修正（旧'全后端 FSR 修复'退役；Task169 重锚：错误的『Vulkan 暂不支持』矩阵同步退役，正式版口径=三后端全支持）",
      "MobileGL 全后端 FSR 修复" not in an
      and "暂不支持 FSR" not in an
      and "全部三个后端均支持 FSR" in an)
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D5 version.h Task164 addendum（含上游不可行结论）",
      "Task 164" in vh and "upstream-impossible" in vh)
# Task168 重锚：FAQ 整体迁移到 help-faq.json（仓库根与随包双文件），且经用户
# 定稿更新了过时结论——FSR 矩阵现为"三后端均支持（Vulkan 经 Metal 呈现层，
# Task166/167）"，旧"Vulkan 暂不支持"句已在迁移中删除。
faq = rd("help-faq.json")
check("D6 FAQ fsr 条目矩阵仍在（Task168 重锚：JSON 化 + 三后端支持新口径）",
      "Metal 呈现层拦截放大" in faq and "Vulkan 直连无升采样呈现钩子" not in faq)

print("== E. 回归锚（zink 路径零扰动）==")
osm = rd("Natives/ctxbridges/osm_bridge.mm")
check("E1 zink RCAS 编译链原样（ame83_adapt_shader_version 消费共享源）",
      "ame83_adapt_shader_version(FSR_RCAS_FSSource" in osm)
check("E2 zink EASU/RCAS 结构未动（Task85 顺序注释在位）",
      "EASU pre-readback ordering" in osm)
mgl = rd("Natives/ctxbridges/mgl_fsr.mm")
check("E3 mgl_fsr Task154 退休门禁原样（不因本轮重启毁帧链）",
      "Task 154：整链退休" in mgl and "return false;" in mgl)
check("E4 mgl_fsr 同样消费 clamp 后的共享 RCAS 源（extern 借用形态不受影响）",
      "FSR_RCAS_FSSource" in mgl)
check("E5 worklog 未越权（本轮尚无 FSR1.cpp 的其它 TU 改动）",
      "Task164" in vh)

fails = [l for l, ok in results if not ok]
print(f"\n{'='*50}\nTask164: {len(results) - len(fails)}/{len(results)} PASS")
if fails:
    print("FAILED:")
    for l in fails:
        print(f"  - {l}")
    sys.exit(1)
print("ALL GREEN")
