#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task204.py -- Task204 renderer-fix wave from the a599782 device logs.

A. gl4es backend-pin injection (egl_bridge.m + libgl4es_114.dylib forensics)
B. vgpu darwin alias regeneration (coverage closure, +187 exports)
C. ANGLE round-2 observers + geo-probe pname hygiene (tinygl4angle.c/gl_bridge.m)
D. incremental regression (203/192/193/202 green; syntax gates)
E. docs (version.h addendum)
"""
import os
import re
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASS = FAIL = 0
def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name}")

def rd(p):
    return open(p, encoding="utf-8", errors="replace").read()

print("== A. gl4es backend pin (egl_bridge.m + binary) ==")
eb = rd("Natives/egl_bridge.m")
check("A1 resolver 定义（gl* 走 eglGetProcAddress→框架句柄；gl* 禁走 RTLD_DEFAULT）",
      "static void *ame204_gl4esProcResolver(const char *name)" in eb
      and "ame204_gl4esEgpa(name)" in eb
      and "dlsym(ame204_gl4esGles2, name)" in eb
      and "绝不回落 RTLD_DEFAULT" in eb)
# Task212 重锚：holy gl4es（libgl4es_114.dylib）整体退役——egl_bridge 的
# Task204 注入链（A2-A7）与离线二进制布局法证（A8 起）全部随 dylib 退役。
# resolver 函数（ame204_gl4esProcResolver）与全局句柄存续：由 NG-GL4ES 的
# ame208_nggl4es_boot 与 ZL2 经典版的 ame211_gl4eszl2_boot 复用（各自
# set_getprocaddress 钉扎——Task204 的"通道"在两个源码构建渲染器上延续）。
def _strip_comments(text):
    import re as _re
    text = _re.sub(r"/\*.*?\*/", "", text, flags=_re.S)
    text = _re.sub(r"//[^\n]*", "", text)
    return text
_eb_code = _strip_comments(eb)
check("A2 egl_bridge 注入链随 holy 退役收档（Task212：注入代码清零；文档注释里的历史偏移合法保留）",
      "holy gl4es（libgl4es_114.dylib）整体退役" in eb
      and "0x1de038" not in _eb_code and "0x1de040" not in _eb_code
      and "Task204: gl4es backend pin" not in eb)
check("A3 resolver 函数存续（NG/ZL2 双 boot 复用同一通道）",
      "ame204_gl4esProcResolver" in eb
      and eb.count("ame204_gl4esProcResolver") >= 3)
check("A4 接棒 boot 的 resolver 钉扎（ame211_gl4eszl2_boot 内 set_getprocaddress）",
      "ame211_sgpa(ame204_gl4esProcResolver)" in eb)
check("A5 dylib 已从仓库移除（Task212 退役）",
      not os.path.exists("Natives/resources/Frameworks/libgl4es_114.dylib"))
check("A6 补丁脚本保留为历史工件（rtld_default + ggstr_nullguard）",
      os.path.exists("scripts/patch_gl4es_rtld_default.py")
      and os.path.exists("scripts/patch_gl4es_ggstr_nullguard.py"))
print("== B. vgpu darwin aliases (collision-aware regeneration) ==")
gen = rd("scripts/task204_vgpu_gen_aliases.py")
al = rd("Natives/external/vgpu/src/gl/wrap/vgpu_darwin_aliases.c")
check("B1 生成器入库（幂等 + 注释剥离 + 预处理器感知 + 布局不缩 + 碰撞守卫）",
      os.path.exists("scripts/task204_vgpu_gen_aliases.py")
      and "def strip_comments" in gen and "never shrink" in gen
      and "DEFINES = " in gen and "NOX11" in gen
      and "def plain_name_definitions" in gen)
names = set(re.findall(r'\.global _([A-Za-z0-9_]+)', al))
# CI round-2 lesson: pack.c (vgpu_pack) already DEFINES 286 plain-name GL
# forwarders -> those names are exported by their defining TU; an alias is a
# duplicate symbol. The core family therefore needs NO alias -- the original
# round-1 "export gap" theory is retracted for that family.
pack_text = rd("Natives/external/vgpu/src/gl/pack/pack.c")
pack_defs = set(re.findall(r'^\s*(?:[A-Za-z_][A-Za-z0-9_ \*]*?\*?\s*)?(gl[A-Za-z0-9_]+)\s*\([^;]*\)\s*\{',
                           re.sub(r'/\*.*?\*/', '', re.sub(r'//[^\n]*', '', pack_text), flags=re.S), re.M))
core = ["glEnable", "glGenTextures", "glDeleteTextures", "glBindTexture",
        "glTexParameteri", "glTexImage2D", "glTexSubImage2D", "glActiveTexture",
        "glGetError", "glDrawArrays", "glDrawElements", "glBufferData",
        "glBufferSubData", "glBindBuffer", "glBindFramebuffer",
        "glCheckFramebufferStatus", "glUseProgram", "glUniformMatrix4fv",
        "glVertexAttribPointer", "glViewport", "glClear", "glBlendFunc",
        "glGetString", "glGenFramebuffers", "glFramebufferTexture2D"]
check("B2 核心族导出双路覆盖（pack.c 定义导出 OR asm 别名——不依赖单一机制）",
      all((("_" + n + "\\n") in al) or (n in pack_defs) for n in core))
check("B3 无重复 .global 条目", len(names) == al.count(".global _"))
check("B4 覆盖规模（>=944 遗留 + 真空缺增量；碰撞族由 pack.c 承担）",
      len(names) >= 944 and len(names) <= 1000)
check("B5 幻影防护（注释块内的 glGetVertexAttribdv 不导出——其声明被注释包裹；ARB 变体保留）",
      ".global _glGetVertexAttribdv\\n" not in al and ".global _glGetVertexAttribdvARB\\n" in al)
# CI round-1 lesson: the guarded-out glX* family MUST NOT be aliased (their
# definitions live inside #ifndef NOX11 which the build compiles away).
glx_now = sorted(n for n in names if n.startswith("glX"))
LEGACY_GLX = {"glXGetProcAddress", "glXGetProcAddressARB", "glXReleaseBuffersMESA",
              "glXSwapInterval", "glXSwapIntervalMESA", "glXSwapIntervalSGI",
              "glXWaitGL", "glXWaitX"}
check("B6 CI 教训锚一：glX 守卫族排除（NOX11 编译掉定义体的家族不得导出；仅留 8 个无条件遗留项）",
      set(glx_now) == LEGACY_GLX
      and ".global _glXCreateContext\\n" not in al
      and ".global _glXChooseFBConfig\\n" not in al)
# CI round-2 lesson: NO alias may duplicate a plain-name definition in a built TU.
dupes = sorted(n for n in names if n in pack_defs)
check("B7 CI 教训锚二：别名与 pack.c 裸名定义零交集（重复符号=链接失败）", not dupes)
# idempotency + internal guards: rerun the generator, expect exit 0
# and a byte-identical file.
before = open("Natives/external/vgpu/src/gl/wrap/vgpu_darwin_aliases.c", "rb").read()
r = subprocess.run([sys.executable, "scripts/task204_vgpu_gen_aliases.py"],
                   capture_output=True, text=True)
after = open("Natives/external/vgpu/src/gl/wrap/vgpu_darwin_aliases.c", "rb").read()
check("B8 生成器重跑幂等 + 内建守卫（exit 0 且文件字节不变）",
      r.returncode == 0 and before == after)

print("== C. ANGLE round-2 + 探针卫生 ==")
tg = rd("Natives/external/gl4es/tinygl4angle.c")
gb = rd("Natives/ctxbridges/gl_bridge.m")
check("C1 数据面观察器（BufferSubData/BufferData/MapBufferRange 计数化）",
      "Task204 ubo: glBufferSubData #" in tg and "Task204 ubo: glBufferData #" in tg
      and "Task204 ubo: glMapBufferRange #" in tg)
check("C2 经典 uniform 计数化（glUniform1i/1iv；Task203 静默版升级）",
      "Task204 uniform: glUniform1i #" in tg and "Task204 uniform: glUniform1iv #" in tg
      and "if (ame204_ptr_u1iv) ame204_ptr_u1iv(" in tg
      and "ame203_ptr_u1iv" not in tg)
check("C3 无重复定义（glBindBufferBase/Range 仍为 Task191 单份）",
      tg.count("void glBindBufferBase(") == 1 and tg.count("void glBindBufferRange(") == 1)
check("C4 探针 pname 退役（0x8CA9/0x8CAA 查询 → 0x8CA6；heal-blit 绑定目标 0x8CA8/0x8CA9 保留）",
      "es.getIntegerv(0x8CA6" in gb and "es.getIntegerv(0x8CA9" not in gb
      and "es.getIntegerv(0x8CAA" not in gb
      and "es.bindFramebuffer(0x8CA8" in gb and "es.bindFramebuffer(0x8CA9" in gb)
check("C5 病历注释（8/8 相关性 + ANGLE 'Invalid pname' 判读入册）",
      "Task204" in gb and "Invalid pname" in gb)
tx = rd("Natives/external/vgpu/src/gl/texture.c")
check("C6 vgpu 纹理探针预排干（三路径：RESIZE/DIRECT/texsub——真归因修复）",
      tx.count("while (gles_glGetError && gles_glGetError()) {}") >= 3
      and "Task204：探针帧预排干" in tx)

print("== D. 增量回归 ==")
def run(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)
for label, cmd, want in [
    ("D1 verify_task203（重锚后全绿）", "python3 scripts/verify_task203.py", 0),
    ("D2 verify_task192", "python3 scripts/verify_task192.py", 0),
    ("D3 verify_task193", "python3 scripts/verify_task193.py", 0),
    ("D4 verify_task202", "python3 scripts/verify_task202.py", 0),
    ("D5 tinygl4angle 语法门（task193_tinygl_syntax.sh）", "bash scripts/task193_tinygl_syntax.sh", 0),
]:
    rc, out = run(cmd)
    check(label, rc == want)

print("== E. 文档 ==")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E1 version.h Task204 附录（no bump；四主题 + 验证记录）",
      "Task 204, no bump" in vh and "task204_vgpu_gen_aliases.py" in vh
      and "0x8CA6" in vh)

print("=" * 60)
print(f"RESULT: {PASS}/{PASS+FAIL}")
if FAIL:
    print("FAILED:")
    sys.exit(1)
print("ALL GREEN")
