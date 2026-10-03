#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task215 — VirGLRenderer(≤26.2) 移植 + ANGLE 深度清除修复 + 基线完整性

背景：本轮用户消息与 Task 212（并行会话）同源。Task 212 已完成
gl4es(≤26.2) 改名、holy gl4es 退役、CF 加固；Task 215 只补齐剩余两件：
A. ANGLE 深度清除 workaround（tinygl4angle）
B. VirGLRenderer(≤26.2) 完整移植（guest/server/桥/接线/构建/CI）
C. 基线完整性（Task212 成果未被本轮破坏）
D. 级联抽样
"""
import os
import re
import subprocess
import sys

# Task216 重锚：并行会话的硬编码工作区路径改为脚本位置自动探测
# （scripts/ 位于仓库根下一级，向上找即仓库根；任一 checkout 均可跑）
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PASS = 0
FAIL = 0

def check(cond, label, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {label}")
    else:
        FAIL += 1
        print(f"  FAIL  {label}" + (f"  {detail}" if detail else ""))

def read(path, mode="r"):
    with open(os.path.join(REPO, path), mode, **({"encoding": "utf-8", "errors": "replace"} if mode == "r" else {})) as f:
        return f.read()

def exists(path):
    return os.path.exists(os.path.join(REPO, path))

print("=" * 70)
print("A. ANGLE 深度清除 workaround（tinygl4angle.c）")
print("=" * 70)

t4a = read("Natives/external/gl4es/tinygl4angle.c")
check("static float ame215_clear_depth" in t4a, "A1 清除值跟踪变量")
check(t4a.count("void glClearDepth(GLdouble") == 1, "A2 glClearDepth 唯一定义（含记录）")
check(t4a.count("void glClear(GLbitfield") == 1, "A3 glClear 唯一定义")
check("gles_glClearBufferfv(0x0180 /*GL_DEPTH*/, 0, &ame215_d)" in t4a, "A4 Mode2 显式深度清除（头独立常量）")
check("AME_TINYGL4_DEPTH_CLEAR_FIX" in t4a, "A5 环境变量开关")
check("Task215 ANGLE-Metal depth-clear workaround armed" in t4a, "A6 一次性日志锚点")
check("fabsf(ame215_clear_depth - 1.0f) <= 0.001f" in t4a, "A7 ≈1.0 门槛（MobileGlues 同款）")
check(t4a.count("{") - t4a.count("}") == 0, "A8 花括号平衡")
check("\r" not in t4a, "A9 LF 行尾")
check("#include <math.h>" in t4a, "A10 math.h 引入")
check("Task212" in t4a or "Task209" in t4a, "A11 Task212/209 探针未被破坏")

print()
print("=" * 70)
print("B. VirGLRenderer(≤26.2) 移植")
print("=" * 70)

check(exists("Natives/external/virglrenderer/vtest/vtest_server.c"), "B1 vendored virglrenderer 1.3.0")
check(exists("Natives/external/libepoxy/src/dispatch_common.c"), "B2 vendored libepoxy")
epoxy_dc = read("Natives/external/libepoxy/src/dispatch_common.c")
check('@rpath/libEGL.framework/libEGL' in epoxy_dc, "B3 epoxy iOS 补丁（dlopen ANGLE）")
check("__ENVIRONMENT_IPHONE_OS__" in epoxy_dc, "B4 补丁仅 iOS 生效（macOS 分支保留）")
vshm = read("Natives/external/virglrenderer/vtest/vtest_shm.c")
check("mkstemp" in vshm and "Task 111" in vshm, "B5 vtest_shm memfd 回退补丁")
check("int vtest_main(int argc, char **argv)" in read("Natives/external/virglrenderer/vtest/vtest_server.c"),
      "B6 上游 vtest_main 导出确认")
check(exists("patches/mesa-215-osmesa-virgl.patch"), "B7 Mesa osmesa-virgl 补丁入库")
mesa_patch = read("patches/mesa-215-osmesa-virgl.patch")
check("virgl_vtest_winsys_wrap" in mesa_patch, "B8 vtest winsys 包装")
check("GALLIUM_DRIVER" in mesa_patch, "B9 GALLIUM_DRIVER 分发")
check("dep_libdrm.found()" in mesa_patch, "B10 无 libdrm 门控（iOS 路径）")

check(exists("Natives/ctxbridges/virgl_server.m"), "B11 virgl_server.m")
check(exists("Natives/ctxbridges/virgl_server.h"), "B12 virgl_server.h")
vs = read("Natives/ctxbridges/virgl_server.m")
check("vtest_main" in vs and "--use-gles" in vs and "--no-loop-or-fork" in vs, "B13 ZL2 同款启动参数")
check('"--socket-path"' in vs, "B14 显式 socket 路径")
check("VTEST_SOCKET_NAME" in vs and "GALLIUM_DRIVER" in vs, "B15 guest 环境变量")
check("eglCreatePbufferSurface" in vs, "B16 离屏宿主上下文")
check(vs.count("{") - vs.count("}") == 0, "B17 花括号平衡")

utils_h = read("Natives/utils.h")
check('#define RENDERER_NAME_VIRGL "libOSMesaVirgl.dylib"' in utils_h, "B18 RENDERER_NAME_VIRGL")

egl = read("Natives/egl_bridge.m")
virgl_pos = egl.find("RENDERER_NAME_VIRGL")
zink_pos = egl.find('hasPrefix:@"libOSMesa"')
check(0 < virgl_pos < zink_pos, "B19 egl_bridge virgl 分支位于 zink 前缀分支之前")
check("ame_virgl_start_server" in egl, "B20 服务引导调用")
check("ctxbridges/virgl_server.h" in egl, "B21 头引入")

jl = read("Natives/JavaLauncher.m")
check("RENDERER_NAME_VIRGL" in jl, "B22 JavaLauncher virgl 分支")
check('![renderer isEqualToString:@ RENDERER_NAME_VIRGL]' in jl, "B23 zink 前缀排除 virgl")

lp = read("Natives/LauncherPreferences.m")
check("RENDERER_NAME_VIRGL" in lp and "renderer.debug.virgl" in lp, "B24 渲染器表 virgl 条目")

ai = read("Natives/AI/AiSettingsTools.m")
ai_virgl = ai.find('containsString:@"virgl"')
ai_zink = ai.find('containsString:@"osmesa"')
check(0 < ai_virgl < ai_zink, "B25 AI 映射 virgl 在 osmesa 子串匹配之前")
check("VirGLRenderer(≤26.2) (libOSMesaVirgl.dylib)" in ai, "B26 AI 友好名")

cmk = read("Natives/CMakeLists.txt")
check("ctxbridges/virgl_server.m" in cmk, "B27 virgl_server.m 编入主程序")

virgl_langs = 0
for d in os.listdir(os.path.join(REPO, "Natives/resources")):
    p = os.path.join("Natives/resources", d, "Localizable.strings")
    if exists(p):
        txt = read(p)
        if re.search(r'"preference\.title\.renderer\.debug\.virgl"\s*=\s*"VirGLRenderer\(≤26\.2\)"', txt):
            virgl_langs += 1
check(virgl_langs >= 4, f"B28 l10n VirGLRenderer(≤26.2)（{virgl_langs} 个全语言）")

mk = read("Makefile")
check("dep_virgl:" in mk, "B29 Makefile dep_virgl 目标")
check("libvtestserver.dylib" in mk and "libOSMesaVirgl.dylib" in mk, "B30 三件套产物名")
check("mesa-215-osmesa-virgl.patch" in mk, "B31 Mesa 补丁接线")
check("archive.mesa3d.org" in mk, "B32 Mesa tarball 下载源（5 次重试）")
check("virgl-cross.txt" in mk, "B33 meson 交叉文件生成")
check("dep_virgl dep_angle_freeze" in mk, "B34 payload 依赖含 dep_virgl")
check(".PHONY: all clean check native java jre package dsym deploy help dep_virgl" in mk, "B35 .PHONY 登记")
check(mk.count("\t") > 550, "B36 Makefile TAB 完整")

wf = read(".github/workflows/development.yml", "rb")
check(b"brew install meson ninja bison" in wf, "B37 CI 安装 meson/ninja/bison")
check(b"brew --prefix bison" in wf, "B38 bison keg-only PATH 注入")
check(b"mako" in wf, "B39 mako 安装")
check(wf.count(b"\r\n") == wf.count(b"\n"), "B40 工作流 CRLF 完整（二进制口径）")

vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("REVISION 19 addendum (Task 215, no bump)" in vh, "B41 version.h Task 215 补遗（REVISION 19，并行 214 已升号）")

print()
print("=" * 70)
print("C. 基线完整性（Task 211/212 成果未破坏）")
print("=" * 70)

check('#define RENDERER_NAME_GL4ESZL2 "libgl4eszl2.dylib"' in utils_h, "C1 gl4eszl2 定义仍在")
check(not exists("Natives/resources/Frameworks/libgl4es_114.dylib"), "C2 holy 二进制仍为已删除")
zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings")
check('"gl4es(≤26.2)"' in zh, "C3 zh-Hans gl4es(≤26.2) 命名保留")
# C4 注：release.gl4es="holy gl4es" 是 Task212 净零交换后遗留的死键
#（代码对 renderer.release.* 零引用，2418 键数守恒需要它占位）——仅验证
# 可见的 debug.* 键无 holy 字样
check(re.search(r'"preference\.title\.renderer\.debug\.[^"]*"\s*=\s*"[^"]*holy', zh) is None,
      "C4 debug.* 键无 holy 字样（release 死键不计）")
cfa = read("Natives/installer/modpack/CurseForgeAPI.m", "rb")
check(b"modLoaderType" in cfa and b"sortField" in cfa, "C5 Task212 CF 参数修复保留")
check("ame212_migrateHolyGl4es" in lp, "C6 holy 迁移函数保留")

print()
print("=" * 70)
print("D. 级联抽样")
print("=" * 70)

for name in ["verify_task214.py", "verify_task213.py"]:
    try:
        r = subprocess.run(["python3", f"scripts/{name}"], cwd=REPO,
                           capture_output=True, text=True, timeout=280)
        check(r.returncode == 0, f"D 级联 {name}", r.stdout.strip().split("\n")[-1] if r.stdout else "")
    except subprocess.TimeoutExpired:
        check(False, f"D 级联 {name}", "TIMEOUT(级联时长)")

print()
print("=" * 70)
print(f"RESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
print("=" * 70)
sys.exit(0 if FAIL == 0 else 1)
