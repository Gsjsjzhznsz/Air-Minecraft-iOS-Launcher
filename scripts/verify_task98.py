#!/usr/bin/env python3
"""
Task 98 验证器：MC 26.x Fabric/NeoForge/Forge 版本 ID 的 LWJGL 选择盲区修复

背景（2af8c45 装机日志，6c3d49d 构建，MC 26.3 Fabric 整合包 110 mods，
含 sodium 0.9.2+mc26.3 / iris 1.11.6+mc26.3 / lithium / modernfix，MG 渲染器
libOSMesa.8.dylib，iPad Air M4 / iPadOS 27）：
  用户报告"26.3 的 sodium 崩溃"。判读：sodium 本身无罪——Task94 动态上报
  生效（LWJGL report 3.4.3 双锚点在位），sodium 0.9.2 的版本门放行，110 mods
  全量打印，启动推进 ~2s 进入原版引导。真死因：MC 26.3 的
  NativeLibrariesBootstrap 按序加载 OpenAL,OpenGL,spvc,vma,SDL,shaderc,STB,
  freetype，第五项 SDL 需要 LWJGL 的 SDL3 绑定（org.lwjgl.sdl.SDL /
  SDLPlatform），而启动器因版本 ID 是 Fabric 形态
  "fabric-loader-0.19.5-26.3-e4ecd7db" 错选了 LWJGL 333 集合（旧解析按 "."
  切分取 parts[0]="fabric-loader-0" → intValue=0），333 集合无 lwjgl-sdl.jar
  → NoClassDefFoundError → "Loading library SDL" 崩溃，与渲染器无关。
  此前所有 26.3 装机会话均为原版形态 ID（"26.3-rc2" 等），旧解析恰好正确，
  Fabric 整合包首次暴露盲区。

修复：
  1. JavaLauncher.m 新增 ame98_mcMajorFromVersionId（1.x 谱系短路 + 锚定年份
     正则），ResolveLwjglVersion auto 路径改用之（[LWJGLSel] Task98 锚点）；
  2. JavaLauncher.h 导出共享；
  3. SurfaceViewController.m ame87 LTW×26.x 预检门同修（同款首连字符盲区，
     否则 Fabric 26.x 整合包会被放行到 LTW 必崩的标题界面）。
FAQ 29→30（+mc26sdl）；version.h REVISION 17 addendum (Task 98, no bump)。
"""
import os
import re
import subprocess
import sys
import zipfile

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def git_show(ref_path):
    r = subprocess.run(["git", "-C", REPO, "show", ref_path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


print("===== A. 2af8c45 日志证据（钉 git——工作区 latestlog.txt 会随未来上传漂移） =====")
log = git_show("2af8c45:latestlog.txt")
check("A0 git fixture 2af8c45 latestlog.txt 在位", len(log) > 1000)
check("A1 会话身份：6c3d49d 构建 + MC 26.3 Fabric 整合包",
      "Commit: 6c3d49d (main)" in log
      and "Launching Minecraft fabric-loader-0.19.5-26.3-e4ecd7db" in log
      and "Loading 110 mods:" in log)
check("A2 渲染器 MG（zink 家族）——渲染器无关论据",
      "profileRenderer=libOSMesa.8.dylib" in log)
check("A3 sodium 门已过（Task94 上报链生效，非 sodium 问题）",
      "[Tools] LWJGL report version: 3.4.3 (from version metadata; sodium PreLaunchChecks gate, Task94)" in log
      and "[PojavLauncher] LWJGL selected by launcher: 333, reported version: 3.4.3 (metadata: 3.4.3)" in log
      and "sodium 0.9.2+mc26.3" in log
      and "not compatible" not in log)
check("A4 吸烟枪：错选 LWJGL 333（版本 ID 为 Fabric 形态）",
      "Using LWJGL 333 (mcVersion=fabric-loader-0.19.5-26.3-e4ecd7db)" in log)
check("A5 下载期已跳过 lwjgl-sdl 桌面 jar（org.lwjgl 全跳过策略的一部分）",
      "[MDCL] Skipped library org.lwjgl:lwjgl-sdl:3.4.3" in log)
check("A6 崩溃主签名：Loading library SDL + NoClassDefFoundError org/lwjgl/sdl/SDL",
      "Description: Loading library SDL" in log
      and "java.lang.NoClassDefFoundError: org/lwjgl/sdl/SDL" in log
      and "com.mojang.blaze3d.platform.NativeLibrariesBootstrap.loadSdl" in log)
check("A7 崩溃前兆：SDLPlatform 同源缺失（Window.getPlatform 系统信息阶段）",
      "Failed to get system info for SDL Platform" in log
      and "java.lang.NoClassDefFoundError: org/lwjgl/sdl/SDLPlatform" in log)
check("A8 加载顺序证据：SDL 是第五项（index 4），前四项全过",
      "Loading order: OpenAL,OpenGL,spvc,vma,SDL,shaderc,STB,freetype" in log
      and "Loading index: 4" in log)
check("A9 lwjgl-sdl 是 26.3 官方版本清单成员（version.json 声明 3.4.3）",
      "org.lwjgl:lwjgl-sdl:3.4.3" in log)

print("===== B. JavaLauncher.m：解析修复 =====")
jl = read("Natives/JavaLauncher.m")
check("B1 ame98_mcMajorFromVersionId 定义在位（类型/空值守卫）",
      "NSInteger ame98_mcMajorFromVersionId(NSString *versionId) {" in jl
      and "![versionId isKindOfClass:[NSString class]]" in jl)
check("B2 1.x 谱系短路正则（防 forge 构建号误读）",
      '@"(?:^|[-_])1\\\\.\\\\d"' in jl)
check("B3 锚定年份正则（串首或 [-_] 后两位数字，后随 [.w]）",
      '@"(?:^|[-_])(\\\\d{2})(?=[.w])"' in jl)
check("B4 ResolveLwjglVersion auto 路径改用共享助手 + 341 判定 + 取证锚点",
      "NSInteger mcMajor = ame98_mcMajorFromVersionId(mcVersionId);" in jl
      and "if (mcMajor >= 26) {" in jl
      and '[LWJGLSel] Task98: MC major %ld extracted from version id' in jl)
check("B5 旧解析已移除（parts[0] 切分形态不复存在）",
      "mcVersionId componentsSeparatedByString" not in jl)
check("B6 profile 显式覆盖仍优先（333/341 原样使用）",
      '[profileValue isEqualToString:@"333"] || [profileValue isEqualToString:@"341"]' in jl)
check("B7 头注释含病历与口径说明（前缀盲区 + 两类防误伤）",
      "fabric-loader-0.19.5-26.3-e4ecd7db" in jl
      and "NativeLibrariesBootstrap" in jl
      and "十六进制哈希" in jl)

print("===== C. 共享导出与第二调用点 =====")
jh = read("Natives/JavaLauncher.h")
check("C1 JavaLauncher.h 导出声明（含用途注释）",
      "NSInteger ame98_mcMajorFromVersionId(NSString *versionId);" in jh
      and "ame87_mcVersionRequiresTextureBuffer" in jh)
svc = read("Natives/SurfaceViewController.m")
check("C2 ame87 LTW 门同修（调用共享助手，保留 >= 26 口径）",
      "ame98_mcMajorFromVersionId(mcVersionId)" in svc
      and "return major >= 26;" in svc)
check("C3 ame87 旧首连字符截断形态已移除",
      'NSRange dash = [mcVersionId rangeOfString:@"-"];' not in svc)

print("===== D. LWJGL 341 集合确实携带 SDL 绑定（修复生效的物质基础） =====")
sdl_jar = os.path.join(REPO, "JavaApp", "libs", "lwjgl-341", "lwjgl-sdl.jar")
check("D1 lwjgl-341/lwjgl-sdl.jar 在位", os.path.exists(sdl_jar))
if os.path.exists(sdl_jar):
    with zipfile.ZipFile(sdl_jar) as z:
        names = z.namelist()
    check("D2 SDL.class / SDLPlatform.class 均在（A6/A7 两签名类的来源）",
          "org/lwjgl/sdl/SDL.class" in names
          and "org/lwjgl/sdl/SDLPlatform.class" in names)
check("D3 lwjgl-333 集合确无 sdl jar（旧选择的缺失正是死因）",
      not any("sdl" in f for f in os.listdir(os.path.join(REPO, "JavaApp", "libs", "lwjgl-333"))))

print("===== E. FAQ 接线（LauncherHelpViewController.m） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("E1 FAQ 30 条目（Task97 29 + Task98 +1 mc26sdl）",
      len(faq_items) == 30, f"got {len(faq_items)}")
check("E2 mc26sdl 条目在位（两签名 + 前缀盲区机理 + 与 Sodium 无关澄清）",
      re.search(r"mc26sdl\.question.*26\.x 的 Fabric/NeoForge 整合包", helpvc, re.S) is not None
      and "Loading library SDL" in helpvc
      and "org/lwjgl/sdl/SDL" in helpvc
      and "Sodium 的版本检查此时已经通过" in helpvc)
check("E3 修复验证锚点 + 旧构建自救（LWJGLSel / Using LWJGL 341 / 手动 3.4.1）",
      "[LWJGLSel] Task98" in helpvc
      and "Using LWJGL 341" in helpvc
      and "手动指定为 3.4.1" in helpvc)
check("E4 注册在故障排除分类（cwdMismatch 之后殿后）",
      re.search(r"@\[ xray, greenFx, background, crash, stuck, bigpack, sodiumLwjgl, missingMods, cwdMismatch, mc26sdl \]", helpvc) is not None)

print("===== F. version.h addendum =====")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F1 REVISION 17 addendum (Task 98, no bump) 在位且不升版",
      "REVISION 17 addendum (Task 98, no bump)" in vh
      and "#define REVISION 17" in vh
      and "REVISION 18" not in vh)
check("F2 addendum 记录病历与双调用点修复",
      "Loading library SDL" in vh
      and "ame98_mcMajorFromVersionId" in vh
      and "ame87 LTW x 26.x gate" in vh
      and "FAQ 29->30 (+mc26sdl" in vh)

print("===== G. 行为矩阵（Python 镜像 ame98 + ResolveLwjglVersion auto 语义） =====")


def mc_major(v):
    if not v or not isinstance(v, str):
        return 0
    if re.search(r"(?:^|[-_])1\.\d", v):
        return 1
    m = re.search(r"(?:^|[-_])(\d{2})(?=[.w])", v)
    return int(m.group(1)) if m else 0


def resolve_auto(v):
    return "341" if mc_major(v) >= 26 else "333"


matrix = [
    ("26.3", "341"), ("26.2-rc1", "341"), ("26w14a", "341"), ("27.1", "341"),
    ("fabric-loader-0.19.5-26.3-e4ecd7db", "341"),
    ("fabric-loader-0.19.5-26w14a-abcdef12", "341"),
    ("neoforge-26.3-21.0.5", "341"),
    ("1.20.1", "333"), ("1.21.9", "333"), ("1.16.5", "333"),
    ("fabric-loader-0.19.3-1.20.1-9c2ee306", "333"),
    ("fabric-loader-0.15.11-1.20.1-88955f01", "333"),
    ("1.20.1-forge-47.3.0", "333"),
    ("quilt-loader-0.26.0-1.20.1-abcdef12", "333"),
    ("25w45a", "333"), ("", "333"), ("latest-release", "333"),
    ("0.19.5", "333"),
]
bad = [f"{v}->{resolve_auto(v)}" for v, want in matrix if resolve_auto(v) != want]
check("G1 18 个用例：auto 语义全对（26.x 任意形态→341；1.x/25w/别名→333）",
      not bad, str(bad))
check("G2 病历 ID 精确复算（2af8c45 的 ID 必须选出 341）",
      resolve_auto("fabric-loader-0.19.5-26.3-e4ecd7db") == "341")
check("G3 哈希防误伤（假想以 26 开头的十六进制哈希不吃年份正则）",
      mc_major("fabric-loader-0.19.5-1.21.9-26f3a1b2") == 1)

print("===== H. 仓库卫生 =====")
check("H1 工作日志含 Task 98 条目",
      "Task ID: 98" in read("worklog.md"))
check("H2 本验证器自身在 scripts/ 下",
      os.path.exists(os.path.join(REPO, "scripts", "verify_task98.py")))
check("H3 verify_task87 B1/G1 已重锚（helper 调用 + 18 用例含 loader 前缀形态）",
      "ame98_mcMajorFromVersionId(mcVersionId)" in read("scripts/verify_task87.py")
      and "fabric-loader-0.19.5-26.3-e4ecd7db" in read("scripts/verify_task87.py"))

print()
if FAIL == 0:
    print(f"RESULT: {PASS}/{PASS + FAIL} PASS")
    sys.exit(0)
else:
    print(f"RESULT: FAILED ({PASS}/{PASS + FAIL})")
    sys.exit(1)
