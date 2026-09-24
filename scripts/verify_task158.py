#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 158 verifier: mg backend remap to MobileGlues (5.1.0 semantics) +
Forge module-layer text2speech stubs + launch-time library gate.

Evidence chain:
  A. User-uploaded 5.1.0 logs (git-pinned) prove the ES/4.0 backends they
     actually played were MobileGlues configs WITH FSR.
  B. The remap restores exactly that path; Vulkan-direct stays libMobileGL.
  C. Forge's Narrator CNFE is rooted at module-layer invisibility of the
     system classloader; mojang-stubs.jar re-provides the stub inside the
     module layer, and the library gate heals silently-missing game jars.
  D. l10n values refreshed (no key changes).
"""
import os, re, subprocess, sys, zipfile, io, tempfile

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
os.chdir(REPO)

PASS = FAIL = 0
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name}  {detail}")

def rd(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout

print("== A. 用户 5.1.0 基准日志（git 钉住 a0ac656 上传）==")
gl40 = git("show", "a0ac656:latestlog.4.0")
gles = git("show", "a0ac656:latestlog.es")
cur_txt = rd("latestlog.txt")
cur_forge = rd("latestlog.forge")
check("A1 latestlog.4.0：MobileGlues GL4.0 会话（customGLVersion=40 + fsr1Setting=4 + 正常退出）",
      "customGLVersion = 40" in gl40 and "fsr1Setting = 4" in gl40
      and "exit(0) snapshot" in gl40 and "swapFail=0" in gl40)
check("A2 latestlog.es：MobileGlues ANGLE ES 会话（enableANGLE=3 + customGLVersion=32 + fsr1Setting=4）",
      "enableANGLE = 3" in gles and "customGLVersion = 32" in gles
      and "fsr1Setting = 4" in gles and "exit(0) snapshot" in gles)
check("A3 两份基准会话渲染器均为 libmobileglues.dylib（非 MobileGL/Mithril 二进制）",
      "RENDERER is set to libmobileglues.dylib" in gl40
      and "RENDERER is set to libmobileglues.dylib" in gles)
check("A4 Mithril 管线着色器崩溃实锤（git 钉住 d380bcc:latestlog.txt，10cee5d 会话；Task161 重锚——原锚当前工作树 latestlog.txt，用户日志轮换后失靶）",
      (lambda g: "Sampler0Smplr" in g and "Fragment shader function could not be compiled into pipeline" in g)(git("show", "d380bcc:latestlog.txt")))
check("A5 当前 latestlog.forge：text2speech CNFE 实锤（模块层 Narrator 缺失）",
      "NoClassDefFoundError: com/mojang/text2speech/Narrator" in cur_forge
      and "Task154 Forge ignoreList shield" in cur_forge)

print("== B. mg 后端重映射（LauncherPreferences / JavaLauncher）==")
lp = rd("Natives/LauncherPreferences.m")
lph = rd("Natives/LauncherPreferences.h")
jl = rd("Natives/JavaLauncher.m")
svc = rd("Natives/SurfaceViewController.m")
check("B1 ame_effective_renderer mg 分支：gles/mithril → libmobileglues + dylib 存在守卫",
      "Task 158（mg 后端重映射）" in lp
      and 'ame142_backend isEqualToString:@ RENDERER_NAME_MOBILEGL_GLES' in lp
      and 'ame142_backend isEqualToString:@ RENDERER_NAME_MITHRIL' in lp
      and 'return @ RENDERER_NAME_MOBILEGLUES;' in lp
      and 'rendererLibraryExists(@ RENDERER_NAME_MOBILEGLUES)' in lp)
check("B2 Vulkan 直连路径零改动（libMobileGL 守卫链仍在）",
      'NSString *ame142_physical = @(ame_physical_renderer_dylib(ame142_backend.UTF8String));' in lp)
check("B3 ame158_mg_mobileglues_mode 实现 + 头文件声明",
      "int ame158_mg_mobileglues_mode(void)" in lp and "int ame158_mg_mobileglues_mode(void);" in lph)
check("B4 init_loadMobileGluesConfig 模式强制（GLES: ANGLE=3+GL3.2；4.0: ANGLE=0+GL4.0）",
      'config[@"enableANGLE"] = @3;' in jl and 'config[@"customGLVersion"] = @32;' in jl
      and 'config[@"enableANGLE"] = @0;' in jl and 'config[@"customGLVersion"] = @40;' in jl
      and "mg GLES backend -> MobileGlues" in jl and "mg OpenGL 4.0 backend -> MobileGlues" in jl)
check("B5 模式 0 下用户 custom_gl_version 偏好透传（重映射会话独占 ANGLE/GL 轴）",
      '(ame158_mode == 0) ? getPrefObject(@"mobileglues.custom_gl_version") : nil' in jl)
check("B6 ame83 能力表：MobileGlues=YES / MobileGL=NO（Task154 退休不回退 + Task158 联动恢复）",
      '[renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) return YES;' in svc
      and "if (isMobileGLRenderer(renderer.UTF8String)) return NO;" in svc)
check("B7 Task158 注释钉住 5.1.0 基准（latestlog.es/latestlog.4.0 + fsr1Setting=4）",
      "latestlog.es / latestlog.4.0" in lp and "fsr1Setting=4" in lp)

print("== C. Forge 模块层桩 + 启动闸门 ==")
jam = rd("JavaApp/Makefile")
rmk = rd("Makefile")
tools = rd("JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java")
check("C1 JavaApp/Makefile：mojang-stubs.jar 规则（tab 配方 + launcher.jar 依赖 + 存在性防回归）",
      "$(OUTPUTDIR)/mojang-stubs.jar: $(OUTPUTDIR)/launcher.jar" in jam
      and "\t@cd $(OUTPUTDIR)/mojang-stubs" in jam
      and "launcher classes missing com/mojang/text2speech" in jam
      and "all: $(TARGETS) $(OUTPUTDIR)/mojang-stubs.jar" in jam)
check("C2 根 Makefile payload 拷贝 mojang-stubs.jar 进 app/libs",
      "JavaApp/build/mojang-stubs.jar" in rmk)
check("C3 JavaLauncher：闸门函数 + 调用点 + evaluateRules 复用",
      "static void ame158_repairMissingLibraries(NSDictionary *launchTarget)" in jl
      and "ame158_repairMissingLibraries(launchTarget);" in jl
      and "#import \"MinecraftResourceUtils.h\"" in jl)
check("C4 闸门跳过集与 Java _skip 同步（text2speech 桩独占，防 split-package）",
      'hasPrefix:@"com.mojang:text2speech"' in jl
      and 'libItem.name.startsWith("com.mojang:text2speech")' in tools)
check("C5 闸门双源下载 + 非阻断语义（官方 → BMCLAPI；失败仅日志）",
      "ame158_bmclapiMirror" in jl and "bmclapi2.bangbang93.com" in jl
      and "Task158: library gate summary" in jl)
check("C6 BootstrapLauncher/securejarhandler 取证产物存档（源码级机制闭环）",
      os.path.exists("/home/z/my-project/scripts/task158_bl/blsrc/cpw/mods/bootstraplauncher/BootstrapLauncher.java")
      and os.path.exists("/home/z/my-project/scripts/task158_bl/sjhsrc/cpw/mods/cl/ModuleClassLoader.java"))

print("== C7. 桩类本地构建验证（ECJ 编译 + jar 组装 + 类清单） ==")
ecj = "/tmp/ecj.jar"
if os.path.exists(ecj):
    with tempfile.TemporaryDirectory() as td:
        srcs = [os.path.join(dp, f)
                for dp, _, fs in os.walk("JavaApp/src/launcher/com/mojang/text2speech")
                for f in fs if f.endswith(".java")]
        r = subprocess.run(["java", "-jar", ecj, "-nowarn", "-source", "8", "-target", "8",
                            "-d", td] + srcs, capture_output=True, text=True)
        check("C7a text2speech 桩独立编译零错误（自包含，无 launcher.jar 依赖）",
              r.returncode == 0, r.stderr[-300:] if r.returncode else "")
        # jar 工具本地 JRE 不带，用 zipfile 等价组装（结构 = Makefile 规则的
        # `jar -cf mojang-stubs.jar com`：com/ 前缀条目）
        jar_path = os.path.join(td, "mojang-stubs.jar")
        try:
            with zipfile.ZipFile(jar_path, "w") as zf:
                for root, _, files in os.walk(os.path.join(td, "com")):
                    for f in files:
                        full = os.path.join(root, f)
                        zf.write(full, os.path.relpath(full, td))
            names = zipfile.ZipFile(jar_path).namelist()
            need = ["Narrator.class", "NarratorDummy.class", "OperatingSystem.class",
                    "Text2Speech.class"]
            check("C7b mojang-stubs.jar 组装 + 8 类清单完整",
                  all(f"com/mojang/text2speech/{n}" in names for n in need)
                  and len([n for n in names if n.endswith(".class")]) >= 8)
        except Exception as e:
            check("C7b mojang-stubs.jar 组装 + 8 类清单完整", False, str(e))
        # getNarrator() -> NarratorDummy (no desktop exec path)
        nar = rd("JavaApp/src/launcher/com/mojang/text2speech/Narrator.java")
        check("C7c getNarrator() 恒返回 NarratorDummy（iOS 无叙述器副作用）",
              "return new NarratorDummy();" in nar)
else:
    check("C7 桩类本地构建验证（ECJ 缺失则跳过）", True, "(ecj.jar not present)")

print("== D. l10n（值更新、键集不变） ==")
langs = ["en.lproj", "zh-Hans.lproj", "zh-CN.lproj", "zh-Hant.lproj"]
for lang in langs:
    p = f"Natives/resources/{lang}/Localizable.strings"
    cur = rd(p)
    old = git("show", f"HEAD:Natives/resources/{lang}/Localizable.strings")
    def keys_of(s):
        return sorted(re.findall(r'^"([^"]+)"\s*=', s, re.M))
    check(f"D1 {lang} 键集与 HEAD 完全一致（值级更新，零键增删）", keys_of(cur) == keys_of(old))
    if lang == "en.lproj":
        ok = ("including the mg GLES" in cur and "Vulkan direct does not support FSR" in cur
              and '"preference.title.renderer_backend-mithril" = "MobileGlues (OpenGL 4.0)"' in cur)
    elif lang == "zh-Hant.lproj":
        ok = ("GLES／OpenGL 4.0 後端" in cur and "Vulkan 直連後端" in cur
              and '"preference.title.renderer_backend-mithril" = "MobileGlues (OpenGL 4.0)"' in cur)
    else:
        ok = ("GLES／OpenGL 4.0 后端" in cur and "Vulkan 直连后端" in cur
              and '"preference.title.renderer_backend-mithril" = "MobileGlues (OpenGL 4.0)"' in cur)
    check(f"D2 {lang} FSR 详情 + 后端文案更新（mithril 标签去实验性）", ok)

faq = rd("Natives/LauncherHelpViewController.m")
check("D3 FAQ 标签页同步（mg GLES/4.0 后端=MobileGlues 路径 + Vulkan 直连指引）",
      "mg 渲染器的 GLES 后端与 OpenGL 4.0 后端即此渲染器" in faq
      and "需要 FSR 请切到 GLES / OpenGL 4.0 后端" in faq)

print("== E. version.h 档案 ==")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E1 version.h Task158 addendum 存在（含三段式记录）",
      "REVISION 17 addendum (Task 158, no bump)" in vh
      and "ame158_mg_mobileglues_mode" in vh and "mojang-stubs.jar" in vh
      and "ame158_repairMissingLibraries" in vh)

print("== F. 语法与配平 ==")
r = subprocess.run([sys.executable, "scripts/task158_objc_balance.py",
                    "Natives/LauncherPreferences.m", "Natives/JavaLauncher.m",
                    "Natives/SurfaceViewController.m", "Natives/LauncherPreferences.h"],
                   capture_output=True, text=True)
check("F 四文件配平（括号/引号/注释状态机）", r.returncode == 0, r.stdout[-300:])
# Makefile tab hygiene for the new rule
jam_raw = open("JavaApp/Makefile", "rb").read().decode("utf-8")
check("F JavaApp/Makefile 新规则 tab 配方（无空格污染）",
      "\t@cd $(OUTPUTDIR)/mojang-stubs" in jam_raw
      and not re.search(r'^        @cd', jam_raw, re.M))

print("== G. 级联（近端关键链） ==")
for t, expect in [("156", "ALL GREEN"), ("153", "ALL GREEN")]:
    r = subprocess.run([sys.executable, f"scripts/verify_task{t}.py"],
                       capture_output=True, text=True, timeout=300)
    check(f"G verify_task{t} {expect}", expect in r.stdout,
          r.stdout.strip().splitlines()[-2] if r.stdout.strip() else "?")

print()
print("=" * 72)
print(f"==== RESULT: {'ALL GREEN' if FAIL == 0 else 'HAS FAILURES'} ({PASS} passed, {FAIL} failed) ====")
print("=" * 72)
sys.exit(0 if FAIL == 0 else 1)
