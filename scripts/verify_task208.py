#!/usr/bin/env python3
"""verify_task208.py -- Task208 verification (99a61eb three-renderer verdict).

A. ANGLE push-constant block-NAME root fix (rename redirect var<->type)
B. NG-GL4ES initialization-timing root fix (NO_INIT_CONSTRUCTOR + host boot)
C. JVM-fatal abort pass-through (no more wedged-app-after-crash)
D. version.h addendum + cascade (task206 43/43, syntax gates)

编号说明：并行会话的 UI 轮占用了 207（verify_task207.py = Shortcuts 卡片
验证器）；本渲染器修复轮按标准补救让出编号为 208（db581fa 提交的家法）。
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
results = []


def rd(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as f:
        return f.read()


def check(name, ok, detail=""):
    results.append((name, ok))
    print(("  PASS " if ok else "  FAIL ") + name + (f"  -- {detail}" if detail and not ok else ""))


def run(cmd, timeout=300):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=REPO)


# ============ A. ANGLE push-constant 块名根修 ============
print("== A. ANGLE 方块透明（块名碰撞）根修 ==")
shim = rd("Natives/spvc_shim.c")
log = rd("latestlog.old.txt")  # 99a61eb ANGLE 会话

check("A1 装机证据（99a61eb latestlog.old.txt）：选项已装但仍 NOT FOUND",
      "EMIT_PUSH_CONSTANT_AS_UNIFORM_BUFFER enabled on ES compiler" in log
      and log.count("name='_push_constants') -> 4294967295") >= 5
      and "name='_uniform_00_00') -> 0" in log,
      f"notfound={log.count(chr(39) + '_push_constants')}")

check("A2 扫描器在位（OpTypePointer 32 / OpVariable 59 / storage 9 全字面量）",
      "static int ame208_find_push_constant" in shim
      and "op == 32u" in shim and "op == 59u" in shim
      and "words[off + 2] == 9u" in shim and "words[off + 3] == 9u" in shim)

check("A3 重定向逻辑（pcType 命中改写 pcVar + 计数）",
      "orig->names[i].id == ame208_pcType" in shim
      and "real_set_name(es_compiler, ame208_pcVar, orig->names[i].name);" in shim)

check("A4 装机锚点日志（重定向生效的一次性打点）",
      "[spvc-shim] Task208: push-constant block rename redirected" in shim)

check("A5 扫描器健壮性（字数/畸形早退 + 单块保守门）",
      "word_count < 5" in shim and "wc == 0 || off + wc > word_count" in shim
      and "ame208_varPtr != ame208_ptr" in shim)

check("A6 函数头病历（emit_buffer_block_native 碰撞机制 + 复现出处）",
      "emit_buffer_block_native" in shim and "回退成【PC 变量的原始名】" in shim
      and "SPIRV-Cross a0fba56" in shim)

# ============ B. NG-GL4ES 初始化时序根修 ============
print("== B. NG-GL4ES 初始化时序根修 ==")
nglog = rd("latestlog.old")  # 99a61eb NG-GL4ES 崩溃会话
cml = rd("ThirdParty/ZalithLauncher2/CMakeLists.txt")
eb = rd("Natives/egl_bridge.m")
hardext = rd("ThirdParty/ZalithLauncher2/src/glx/hardext.c")

check("B1 装机证据（99a61eb latestlog.old）：构造器期 strstr SIGSEGV + 事后卡死",
      "_platform_strstr" in nglog and "GetHardwareExtensions" in nglog
      and "initialize_gl4es" in nglog
      and "STILL blocked at org.lwjgl.system.JNI.invokePP" in nglog
      and nglog.count("Initialising Krypton Wrapper") >= 1)

check("B2 构建：-DNO_INIT_CONSTRUCTOR（C+CXX 双 flags 行）",
      cml.count("-DNO_INIT_CONSTRUCTOR") >= 2)

check("B3 PROVENANCE 10/11（NO_INIT_CONSTRUCTOR 病历 + hardext NULL 守卫记录）",
      "# 10. -DNO_INIT_CONSTRUCTOR (Task208" in cml
      and "# 11. src/glx/hardext.c (Task208)" in cml)

check("B4 vendored 守卫：Exts NULL 退化空串 + 一次性日志",
      "if (Exts == NULL)" in hardext and 'Exts = "";' in hardext
      and "ame208_nullExtsLogged" in hardext)

check("B5 egl_bridge boot 函数（RTLD_NOLOAD 句柄 + resolver 注册 + 真上下文门）",
      "static void ame208_nggl4es_boot(void)" in eb
      and 'dlopen("@rpath/" RENDERER_NAME_NGGL4ES, RTLD_NOW | RTLD_NOLOAD | RTLD_GLOBAL)' in eb
      and "ame208_sgpa(ame204_gl4esProcResolver);" in eb
      and "eglGetCurrentContext" in eb
      and "initialize_gl4es" in eb)

check("B6 挂点：pojavMakeCurrent 尾部（br_make_current 之后）",
      eb.find("br_make_current(window);") < eb.find("ame208_nggl4es_boot();")
      and eb.count("ame208_nggl4es_boot();") == 1)

check("B7 幂等与渲染器门（s_ame208_done + AMETHYST_RENDERER 比较）",
      "s_ame208_done" in eb
      and 'strcmp(ame208_renderer, RENDERER_NAME_NGGL4ES) != 0' in eb)

check("B8 装机锚点（boot 完成打点）",
      "[egl_bridge] Task208: NG-GL4ES initialize_gl4es() called post-MakeCurrent" in eb)

# ============ C. JVM fatal abort 直通 ============
print("== C. JVM fatal abort 直通 ==")
mh = rd("Natives/main_hook.m")

check("C1 libjvm 回溯检测（backtrace + dladdr + strstr libjvm.dylib）",
      "Task208：JVM fatal 的 abort 直通" in mh
      and "backtrace(ame208_frames, 48)" in mh
      and 'strstr(ame208_info.dli_fname, "libjvm.dylib")' in mh)

check("C2 直通路径在 park 之前（handle_fatal_exit 仍保留给非 JVM abort）",
      mh.find("libjvm.dylib") < mh.find("handle_fatal_exit(SIGABRT);")
      and mh.count("handle_fatal_exit(SIGABRT);") == 1)

# ============ D. 文档 + 级联 ============
print("== D. 文档 + 级联 ==")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D1 version.h REVISION 18 Task208 附录（三主题 + 装机锚点 + 验证记录 + 尾部 SEP）",
      "Amethyst Task 208, 2026-10-01" in vh and "NO_INIT_CONSTRUCTOR" in vh
      and "ame208_find_push_constant" in vh and "hooked_abort parks" in vh
      and vh.rstrip().endswith("// ============================================================================"))

r206 = run([sys.executable, "scripts/verify_task206.py"], timeout=600)
check("D2 verify_task206 级联 43/43（本轮触改后重跑）",
      r206.returncode == 0 and "43/43" in r206.stdout and "ALL PASS" in r206.stdout,
      r206.stdout[-200:] if r206.returncode != 0 else "")

r205 = run([sys.executable, "scripts/verify_task205.py"], timeout=600)
check("D3 verify_task205 级联（D1a 重锚后全绿）",
      r205.returncode == 0 and "0 failed" in r205.stdout,
      r205.stdout[-200:] if r205.returncode != 0 else "")

r175 = run([sys.executable, "scripts/task175_syntax_gates.py"], timeout=300)
check("D4 task175 语法门（spvc_shim 等全绿）",
      r175.returncode == 0 and "ALL PASS" in r175.stdout)

rbal = run([sys.executable, "scripts/task158_objc_balance.py",
            "Natives/egl_bridge.m", "Natives/main_hook.m", "Natives/spvc_shim.c"],
           timeout=300)
check("D5 括号平衡（egl_bridge / main_hook / spvc_shim）",
      rbal.returncode == 0 and "FAIL" not in rbal.stdout)

rsyn = run(["gcc", "-fsyntax-only", "-Wall", "-Wno-unused-variable",
            "-Wno-unused-function",
            "-I", "ThirdParty/ZalithLauncher2/include/spirv_cross",
            "Natives/spvc_shim.c"], timeout=120)
check("D6 spvc_shim.c gcc -fsyntax-only 干净", rsyn.returncode == 0,
      rsyn.stderr[-200:] if rsyn.returncode != 0 else "")

rsyn2 = run(["bash", "-c",
             "gcc -fsyntax-only -DNOX11 -DNO_GBM -DNOEGL -DDEFAULT_ES=3 -DSHAREDLIB "
             "-I ThirdParty/ZalithLauncher2/include -I ThirdParty/ZalithLauncher2/src/gl "
             "ThirdParty/ZalithLauncher2/src/glx/hardext.c"], timeout=120)
check("D7 vendored hardext.c gcc -fsyntax-only 干净（守卫后）", rsyn2.returncode == 0,
      rsyn2.stderr[-200:] if rsyn2.returncode != 0 else "")

rsyn3 = run(["bash", "-c",
             "grep -rn 'constructor(101)' ThirdParty/ZalithLauncher2/src/gl/init.c | grep -v NO_INIT"],
            timeout=60)
check("D8 init.c 构造器确由 NO_INIT_CONSTRUCTOR 围起（开关语义成立）",
      "#ifdef NO_INIT_CONSTRUCTOR" in rd("ThirdParty/ZalithLauncher2/src/gl/init.c"))

# ============ summary ============
fails = [n for n, ok in results if not ok]
print()
print(f"==== Task208: {len(results) - len(fails)}/{len(results)} ====")
if fails:
    print("FAILED:")
    for n in fails:
        print("  " + n)
    sys.exit(1)
print("ALL PASS")
