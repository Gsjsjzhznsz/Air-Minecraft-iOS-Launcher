#!/usr/bin/env python3
"""verify_task166 -- Vulkan DirectVulkan 后端 Metal 层 FSR1 + ES/4.0 黑屏
DSA 根因修复的代码级验证。

A. DSA 黑屏根因法证（三会话 A/B 的代码内档案锚）
B. DSA 修复三处（PLPreferences 默认 / JavaLauncher config / ame130 分支停用）
C. ame166 反向迁移（仅匹配 1 / 一次性哨兵 / Task130 0->1 中和）
D. Metal FSR 模块 API 契约（mgl_metal_fsr.h 五函数）
E. Metal FSR 实现（drawable 包装 / Layer B / 环形纹理池 / 降级路径 / 日志锚点）
F. MSL 数学锚（ffx_a 常量 / AMD tap 布局 / RCAS limit / OOB clamp）
G. gl_bridge 集成（交换层 / render-res attribs / ame48 记 Layer B / reset / teardown）
H. SurfaceViewController 集成（ame83 重新纳入 Vulkan / -gles 维持排除 / 尺寸钩子）
I. 预交换 GL 链退休维持（Task166 修订：无双重点采样）
J. CMake 构建（源文件 / ObjC++ 属性 / Metal 框架）
K. 公告 + version.h 追记
L. 语法门 + 括号 delta + 级联（129/130 重锚形态 + 165）
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASS = 0
FAIL = 0

def rd(p):
    return open(os.path.join(REPO, p), encoding="utf-8").read()

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

mm = rd("Natives/ctxbridges/mgl_metal_fsr.mm")
mh = rd("Natives/ctxbridges/mgl_metal_fsr.h")
gb = rd("Natives/ctxbridges/gl_bridge.m")
svc = rd("Natives/SurfaceViewController.m")
jl = rd("Natives/JavaLauncher.m")
plp = rd("Natives/PLPreferences.m")
lp = rd("Natives/LauncherPreferences.m")
lph = rd("Natives/LauncherPreferences.h")
mglfsr = rd("Natives/ctxbridges/mgl_fsr.mm")
cml = rd("Natives/CMakeLists.txt")
ver = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("== A. DSA 黑屏根因法证（三会话 A/B 档案）==")
check("A1 JavaLauncher 病历锚：健康对 9e6fc27（DSA=0 可玩）入档",
      "9e6fc27" in jl and "DSA support not detected" in jl)
check("A2 JavaLauncher 病历锚：黑屏对 cc9bfe4 + 3368468（DSA=1）入档",
      "cc9bfe4" in jl and "3368468" in jl and "enabling DSA" in jl)
check("A3 机理锚：DSAWrapper 模拟层 + FSR1 fb0 重定向 + 10 次一次性 No-context",
      "DSAWrapper" in jl and "fb0" in jl and "No context is current" in jl)
check("A4 依据纠偏锚：Task129d 性能依据来自 zink（Mesa 原生 DSA）",
      "zink" in jl and "Mesa 原生 DSA" in jl)
check("A5 LauncherPreferences.h 病历：三会话 A/B + 哨兵键语义",
      "三会话 A/B" in lph and "task166_dsa_blackscreen_migrated" in lph)

print("== B. DSA 修复三处（默认归零）==")
check("B1 PLPreferences 默认 @NO（Task129d 的 @YES 时代结束）",
      '@"enable_ext_direct_state_access": @NO,' in plp
      and '@"enable_ext_direct_state_access": @YES,' not in plp)
check("B2 JavaLauncher config.json 默认 @0（覆盖链之前）",
      'config[@"enableExtDirectStateAccess"] = @0;' in jl
      and 'config[@"enableExtDirectStateAccess"] = @1;' not in jl)
check("B3 用户偏好覆盖链保留（设置页开关仍可强制开回）",
      'config[@"enableExtDirectStateAccess"] = [enableExtDirectStateAccess boolValue] ? @1 : @0;' in jl)
check("B4 ame130 迁移 DSA 分支停用（修订注释 + 缓存 32->128 保留）",
      "dsa branch retired by Task166" in lp
      and "[(NSNumber *)cache intValue] == 32" in lp
      and "[(NSNumber *)dsa intValue] == 0" not in lp)

print("== C. ame166 反向迁移 ==")
check("C1 函数声明 + 定义（.h 与 .m 双锚）",
      "void ame166_migrateMgDsaBlackScreen(void);" in lph
      and "void ame166_migrateMgDsaBlackScreen(void) {" in lp)
check("C2 仅匹配持久化 1（boolValue 路径保留；Task167 重锚为局部变量形态 + 双类型容错）",
      "dsaOn = [(NSNumber *)dsa boolValue];" in lp
      and "dsaOn = ([(NSString *)dsa intValue] != 0);" in lp)
check("C3 一次性哨兵（已迁移即返回；哨兵默认键注册）",
      'task166_dsa_blackscreen_migrated") boolValue]' in lp
      and '@"task166_dsa_blackscreen_migrated": @NO' in plp)
check("C4 Task130 哨兵已置位老设备补课路径（两处接线）",
      lp.count("ame166_migrateMgDsaBlackScreen();") == 2)

print("== D. Metal FSR 模块 API 契约（mgl_metal_fsr.h）==")
check("D1 五函数契约齐备（engage/acquire/update/reset/teardown）",
      all(s in mh for s in [
          "bool ame166_metal_fsr_should_engage(const char *renderer);",
          "CAMetalLayer *ame166_metal_fsr_acquire_layer(CAMetalLayer *viewLayer, int renderW, int renderH);",
          "void ame166_metal_fsr_update_size(int renderW, int renderH);",
          "void ame166_metal_fsr_context_reset(void);",
          "void ame166_metal_fsr_teardown(void);"]))
check("D2 extern C 包裹（gl_bridge.m 为 ObjC/方 C 混编消费方）",
      'extern "C"' in mh and "#pragma once" in mh)
check("D3 头注释：nil = 回退（da5918a 语义）约定",
      "nil = 回退" in mh and "da5918a" in mh)

print("== E. Metal FSR 实现（mgl_metal_fsr.mm）==")
check("E1 Ame166Drawable 实现 CAMetalDrawable 协议（MoltenVK 1.2.9 消费面）",
      "@interface Ame166Drawable : NSObject <CAMetalDrawable>" in mm)
check("E2 present 家族三入口全走包装核心",
      "- (void)present { [self ame166_presentWithTime:0.0 duration:0.0]; }" in mm
      and "- (void)presentAtTime:(double)presentationTime" in mm
      and "- (void)presentAfterMinimumDuration:(double)duration" in mm)
check("E3 Ame166SwapchainLayer 重写 nextDrawable（永不调 super）",
      "@interface Ame166SwapchainLayer : CAMetalLayer" in mm
      and "- (nullable id<CAMetalDrawable>)nextDrawable {" in mm)
check("E4 环形纹理池 8 槽 + 许可语义信号量（初值 1，注释含初值 0 教训）",
      "static const int kAme166RingSlots = 8;" in mm
      and "dispatch_semaphore_create(1)" in mm
      and "初值 0 会让首取空等超时" in mm)
check("E5 maximumDrawableCount=3 对齐 MoltenVK imageCount 期望",
      "layerB.maximumDrawableCount = 3;" in mm)
check("E6 降级路径：无设备/库编译/管线/队列失败 -> nil（回退全分辨率直呈）",
      "Task166 fallback: no MTLDevice" in mm
      and "EASU library compile failed" in mm
      and "RCAS library compile failed" in mm
      and "command queue alloc failed" in mm)
check("E7 present 期丢帧限频日志（绝不崩溃）",
      "Task166 present dropped (pipeline unavailable)" in mm
      and "(Layer A nextDrawable nil)" in mm
      and mm.count("% 600 == 0") >= 3)
check("E8 中转分配失败退化 EASU 单趟（Task83 语义）",
      "falling back to EASU-only this frame" in mm)
check("E9 自描述几何：源/目标尺寸取自纹理自身（不信启动器信念）",
      "const int inW = (int)_texture.width;" in mm
      and "const int outW = (int)real.texture.width;" in mm)
check("E10 kill switch + RCAS 锐化 env（Task130 口径：负值=关）",
      'getenv("AME166_MGL_METAL_FSR")' in mm
      and 'getenv("AMETHYST_FSR_RCAS_SHARPNESS")' in mm
      and "bool rcasOn = (sharpness >= 0.0f);" in mm)
check("E11 presentedHandler 转发 + 丢帧路径立即回调（信令不卡死）",
      "- (void)addPresentedHandler:" in mm
      and "ame166_fireHandlersOnReal" in mm
      and "立即回调" in mm)
check("E12 装机日志锚点（engaged / first frame / steady 600）",
      "[MGLFSR] Task166 Metal FSR engaged:" in mm
      and "Task166 first frame presented:" in mm
      and "Task166 steady: 600 frames upscaled" in mm)
check("E13 帧同步口径：设备级 hazard tracking + 完成回调归还信号量",
      "hazard tracking" in mm
      and "addCompletedHandler" in mm
      and "dispatch_semaphore_signal(slotSem)" in mm)
check("E14 同设备钉扎（跨层纹理共享前提）",
      "viewLayer.device = device;" in mm)
check("E15 目标格式跟随 Layer A（显示层drawable 格式）+ BGRA8 兜底",
      "MTLPixelFormat targetFmt = viewLayer.pixelFormat;" in mm
      and mm.count("MTLPixelFormatBGRA8Unorm") == 2)

print("== F. MSL 数学锚（AMD FSR 1.20210629 逐字移植）==")
easu = re.search(r'kAme166EasuMSL = @R"ame166_msl\((.*?)\)ame166_msl"', mm, re.S).group(1)
rcas = re.search(r'kAme166RcasMSL = @R"ame166_msl\((.*?)\)ame166_msl"', mm, re.S).group(1)
check("F1 ffx_a.h 32-bit 三常量（EASU 全需；RCAS 仅 medRcp）",
      all(c in easu for c in ("0x7ef07ebbu", "0x7ef19fffu", "0x5f347d74u"))
      and "0x7ef19fffu" in rcas)
check("F2 EASU 12-tap 命名齐全（t_b..t_o）+ AMD 偏移布局逐位",
      all(f"t_{t} = ame166_load(" in easu for t in "bcefghijklnno"[:12])
      and all(f"int2({o})" in easu for o in
              [" 0, -1", " 1, -1", "-1,  0", " 0,  0", " 1,  0", " 2,  0",
               "-1,  1", " 0,  1", " 1,  1", " 2,  1", " 0,  2", " 1,  2"]))
check("F3 EASU 4 组十字 setF + lob/clp 口径（AMD 公式）",
      easu.count("ame166_setF(") == 5  # 1 定义 + 4 调用
      and "float lob = 0.5 + (0.25 - 0.04 - 0.5) * len;" in easu)
check("F4 RCAS 5-tap（b,d,e,f,h）+ stops 语义 + limit 常量 + alpha 透传",
      all(f"ame166_load4(srcTex, sp + int2({o}), S)" in rcas for o in
          [" 0, -1", "-1,  0", " 1,  0", " 0,  1"])
      and "ame166_load4(srcTex, sp, S)" in rcas
      and "constexpr float kAme166RcasLimit = 0.25 - (1.0 / 16.0);" in rcas
      and "e4.a" in rcas)
check("F5 OOB 防御在装载器内（Task164 教训；两装载器都 clamp）",
      "p = clamp(p, int2(0), sz - 1);" in easu
      and "p = clamp(p, int2(0), sz - 1);" in rcas)
check("F6 顶点着色器 3 顶点全屏三角（两库同名 ame166_vs）",
      "ame166_vs" in easu and "ame166_vs" in rcas
      and "vertexCount:3" in mm)
check("F7 FsrEasuCon CPU 侧（con0 = 缩放 + 半像素偏移）",
      "0.5f * (float)inW / (float)outW - 0.5f" in mm)
check("F8 RCAS stops 换算（2*(1-s)，exp2(-stops)）",
      "const float stops = 2.0f * (1.0f - sharpness);" in mm
      and "const float rcasConX = exp2f(-stops);" in mm)

print("== G. gl_bridge 集成 ==")
check("G1 头引入 + 门控四重（渲染器/env/窗口信念/表面）",
      '#include "mgl_metal_fsr.h"' in gb
      and "ame166_metal_fsr_should_engage(ame166_rendererEnv)" in gb)
check("G2 私有交换层获取 + EGL attribs 改渲染分辨率（windowWidth 单点下发）",
      "ame166_metal_fsr_acquire_layer(" in gb
      and "static EGLint ame166_fsrAttribs[5];" in gb
      and "ame166_fsrAttribs[1] = (EGLint)MAX(1, windowWidth);" in gb)
check("G3 surface 创建消费交换层 + attribs（回退 = 视图层 + 全分辨率）",
      "(__bridge EGLNativeWindowType)swapLayerForEGL, attribsForEGL" in gb)
check("G4 ame48 守卫记录 Layer B（surface-vs-layer 恒等静止）",
      "ame48_record_creation(swapLayerForEGL, g_EglDisplay, bundle->surface);" in gb)
check("G5 新上下文复位 + 终止清理（teardown 于 gl_terminate）",
      "ame166_metal_fsr_context_reset();" in gb
      and "ame166_metal_fsr_teardown();" in gb)
check("G6 装机日志锚点（[GLGeo] Task166 FSR surface）",
      "[GLGeo] Task166 FSR surface:" in gb)

print("== H. SurfaceViewController 集成（ame83 联动）==")
check("H1 libMobileGL.dylib 重新纳入 FSR 联动（Task166 修订注释）",
      "if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGL]) return YES;" in svc)
check("H2 -gles 变体维持排除（isMobileGLRenderer 兜底 NO）",
      "if (isMobileGLRenderer(renderer.UTF8String)) return NO;" in svc)
check("H3 旋转/分辨率钩子（ame166_metal_fsr_update_size 于 heal 路径）",
      "ame166_metal_fsr_update_size(windowWidth, windowHeight);" in svc)
check("H4 头引入",
      '#import "ctxbridges/mgl_metal_fsr.h"' in svc)

print("== I. 预交换 GL 链退休维持（无双重点采样）==")
check("I1 ame_mgl_fsr_before_swap 维持硬退休（return false）",
      "return false;\n#if 0" in mglfsr)
check("I2 Task166 修订注释（退休理由更新：呈现端 Metal FSR 接管）",
      "Task 166 修订：退休维持" in mglfsr
      and "双重升采样" in mglfsr)
check("I3 装机日志更新（不再声称 full-res direct）",
      "Task166: present-side Metal FSR owns upscaling" in mglfsr)

print("== J. CMake 构建 ==")
check("J1 源文件注册",
      "ctxbridges/mgl_metal_fsr.mm" in cml)
check("J2 ObjC++/ARC/gnu++17 属性（与 mgl_fsr 同方言）",
      "set_source_files_properties(ctxbridges/mgl_metal_fsr.mm PROPERTIES" in cml
      and '-x;objective-c++;-fobjc-arc;-std=gnu++17"' in cml)
check("J3 Metal 框架链接",
      '"-framework Metal"' in cml)

print("== K. 公告 + version.h ==")
import json
anns = json.load(open(os.path.join(REPO, "announcements.json"), encoding="utf-8"))["announcements"]
a166 = [a for a in anns if a.get("id") == "task166-vulkan-fsr-dsa-2026-09-25"]
check("K1 task166 公告在列（Vulkan FSR 上线 + DSA 根因）",
      len(a166) == 1 and "Vulkan" in a166[0]["title"] and "DSA" in a166[0]["title"])
check("K2 task165 矩阵已诚实改写（Vulkan 行不再是不支持）",
      any("已被 Task166 推翻" in a.get("content", "") for a in anns if a.get("id") == "task165-blackscreen-rootcause-2026-09-25")
      and not any("❌ **Vulkan 直连后端**：暂不支持" in a.get("content", "")
                  for a in anns if a.get("id") == "task165-blackscreen-rootcause-2026-09-25"))
check("K3 公告含装机验证锚点（engaged / first frame）",
      "Task166 Metal FSR engaged" in a166[0]["content"]
      and "first frame presented" in a166[0]["content"])
check("K4 version.h REVISION 17 追记（Task 166 addendum，不 bump）",
      "Task 166 (REVISION 17 addendum" in ver
      and "ame166_migrateMgDsaBlackScreen" in ver
      and "0x5f347d74" in ver)

print("== L. 语法门 + 括号 delta + 级联 ==")
r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/task166_syntax_mgl.py")],
                   capture_output=True, text=True, timeout=120)
check("L1 task166_syntax_mgl 门（stub 编译 + 7 门控行为案例 + MSL 结构）",
      r.returncode == 0 and "all syntax gates passed" in r.stdout,
      r.stdout[-150:] + r.stderr[-150:])

TOUCHED = [
    "Natives/ctxbridges/mgl_metal_fsr.mm",
    "Natives/ctxbridges/mgl_fsr.mm",
    "Natives/ctxbridges/gl_bridge.m",
    "Natives/SurfaceViewController.m",
    "Natives/JavaLauncher.m",
    "Natives/PLPreferences.m",
    "Natives/LauncherPreferences.m",
    "Natives/LauncherPreferences.h",
    "Natives/CMakeLists.txt",
]
delta_ok = True
for p in TOUCHED:
    cur = rd(p)
    head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{p}"],
                          capture_output=True, text=True).stdout
    if not head:
        continue  # 新文件无 HEAD 基线
    if not all(cur.count(a) - cur.count(b) == head.count(a) - head.count(b)
               for a, b in [("{", "}"), ("(", ")"), ("[", "]")]):
        delta_ok = False
        print(f"    bracket delta mismatch: {p}")
check("L2 裸括号 delta 与 HEAD 一致（提交前工作树门）", delta_ok)

# 级联：129/130 的 Task166 重锚形态必须就位（D1/D3、E9/E10）
v129 = rd("scripts/verify_task129.py")
v130 = rd("scripts/verify_task130.py")
check("L3 verify_task129 D1/D3 重锚形态（Task166 黑屏反向）",
      "Task166 黑屏反向" in v129 and "task166_dsa_blackscreen_migrated" in v129)
check("L4 verify_task130 E9/E10 重锚形态（ame166 接线两处 + 仅匹配 1）",
      "Task166 反向迁移" in v130 and "ame166_migrateMgDsaBlackScreen();\") == 2" in v130)
r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/verify_task165.py")],
                   capture_output=True, text=True, timeout=300)
# task165 的输出格式是 "==== Task165: N/N ===="（无 ALL PASS 字样），判定口径
# = 退出码 0 + 分数行无失败计数。
m165 = re.search(r"==== Task165: (\d+)/(\d+) ====", r.stdout)
check("L5 verify_task165 级联（Task165 锚点不受 Task166 影响；A3 已 git 钉住 / G1 置顶区重锚）",
      r.returncode == 0 and m165 is not None and m165.group(1) == m165.group(2),
      r.stdout[-120:] if r.returncode else "")

print()
print(f"==== RESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}) ====")
sys.exit(1 if FAIL else 0)
