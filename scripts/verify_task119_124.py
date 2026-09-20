#!/usr/bin/env python3
"""verify_task119_124.py -- Tasks 119-124（5.1.0 第二轮实测反馈修复）验证器。

任务对照（用户 4 条实测反馈 -> 代码落点）：
  A. Task119  MobileGL Vulkan 路径 FSR 修复（蜷缩 -> 预交换 EASU 放大）
  B. Task120  mobilegl_vulkan 布尔开关 -> mobilegl_backend 单一选项（默认 Vulkan）
  C. Task121  l10n 补齐（en/zh-Hans 23 键 + zh-CN/zh-Hant 22 键 + 新文案）
  D. Task124  新上传 log 判读（zink 被回退 vk + vk 崩溃）-> 同根修复锚点
  E. 语法门（括号平衡 + .strings 语法 + 开关残留清扫）
  F. 级联（verify_task112_118 B 区重锚后仍全绿）
"""
import os
import re
import subprocess
import sys

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

def rd(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()

jl = rd("Natives/JavaLauncher.m")
lp = rd("Natives/LauncherPreferences.m")
lph = rd("Natives/LauncherPreferences.h")
lpvc = rd("Natives/LauncherPreferencesViewController.m")
plp = rd("Natives/PLPreferences.m")
plpt = rd("Natives/PLPrefTableViewController.m")
gsv = rd("Natives/GameSurfaceView.m")
svc = rd("Natives/SurfaceViewController.m")
gb = rd("Natives/ctxbridges/gl_bridge.m")
gbh = rd("Natives/ctxbridges/gl_bridge.h")
fsr = rd("Natives/ctxbridges/mgl_fsr.mm")
cml = rd("Natives/CMakeLists.txt")

print("== A. Task119 MobileGL FSR（mgl_fsr.mm 预交换 EASU）==")
check("A1 mgl_fsr.mm 存在且含任务头注释（蜷缩根因记录）",
      os.path.exists(os.path.join(REPO, "Natives/ctxbridges/mgl_fsr.mm")) and
      "Task 119" in fsr and "蜷缩" in fsr)
check("A2 CMakeLists 收录 mgl_fsr.mm 且强制 objective-c++ 方言（Task83 教训）",
      "ctxbridges/mgl_fsr.mm" in cml and
      cml.find("set_source_files_properties(ctxbridges/mgl_fsr.mm") > 0)
check("A3 gl_swap_buffers 挂钩：ame48 卫兵之后、eglSwapBuffers 调用之前",
      gb.find("ame_mgl_fsr_before_swap();") > gb.find("ame48_swap_geometry_guard(currentBundle);") and
      gb.find("ame_mgl_fsr_before_swap();") < gb.find("handle.eglSwapBuffers("))
check("A4 gl_init_context 成功后调用 ame_mgl_fsr_context_reset（上下文重建重编）",
      "ame_mgl_fsr_context_reset();" in gb and
      gb.find("ame_mgl_fsr_context_reset()") > gb.find("g_ame50_gl_owns_layer"))
check("A5 头文件声明两个对外入口",
      "bool ame_mgl_fsr_before_swap(void);" in gbh and
      "void ame_mgl_fsr_context_reset(void);" in gbh)
check("A6 Task78 豁免扩展到 MobileGL（补偿链不介入预交换 EASU 几何）",
      "isMobileGLRenderer(ame78_renderer)" in gb and
      "Task78 FSR linkage active" in gb)
check("A7 ame83_fsr_capable_renderer 认 MobileGL 两后端（联动覆盖感知）",
      "isMobileGLRenderer(renderer.UTF8String)) return YES" in svc)
check("A8 FSR 联动读有效渲染器（裸读 profile = 蜷缩根因之一）",
      "ame78_renderer = ame_effective_renderer()" in svc)
check("A9 兜底自愈：EASU 不可用 -> nativeSendScreenSize 恢复全分辨率",
      "CallbackBridge_nativeSendScreenSize(surfW, surfH)" in fsr and
      "healed" in fsr)
check("A10 视口自适应输入（Task105 同款：优先 MC 真实呈现视口）",
      "vpArea * 4 >= beliefArea" in fsr)
check("A11 状态保存/还原（FBO 双通道 + 纹理单元0，Task99 口径）",
      "GL_DRAW_FRAMEBUFFER_BINDING" in fsr and "GL_TEXTURE_BINDING_2D" in fsr)
check("A12 DirectGLES 档 shader 版本自适应（编不了 450 则停用并自愈）",
      "ame119_adapt_shader_version" in fsr)

print("== B. Task120 mobilegl_backend 单一选项（显式选择优先）==")
check("B1 ame_effective_renderer 定义 + 头文件声明（单一事实源）",
      "NSString *ame_effective_renderer(void)" in lp and
      "NSString *ame_effective_renderer(void);" in lph)
check("B2 显式渲染器选择优先（非 auto 原样返回）",
      '![renderer isEqualToString:@"auto"]' in lp and
      "return renderer;" in lp)
check("B3 档位解析：1/2 -> libMobileGL.dylib，3 -> Mithril 带存在性守卫",
      'getPrefInt(@"mobileglues.mobilegl_backend")' in lp and
      "rendererLibraryExists(@ RENDERER_NAME_MITHRIL)" in lp)
check("B4 JavaLauncher 消费 ame_effective_renderer（保留覆盖日志点）",
      "ame_effective_renderer()" in jl and
      "MobileGL backend override active" in jl)
check("B5 GLES 档切 DirectGLES（同二进制，MOBILEGL_BACKEND_TYPE）",
      'getPrefInt(@"mobileglues.mobilegl_backend") == 2' in jl and
      '"DirectGLES"' in jl)
check("B6 PLPreferences 默认 mobilegl_backend=1（Vulkan 默认），旧开关无残留",
      '"mobilegl_backend": @(1)' in plp and '"mobilegl_vulkan"' not in plp)
# Task 131 重锚：mobilegl_backend 独立 pick 行退役（用户四次反馈"设置项还是
# 分开的/二级菜单入口无法使用"），MobileGL 三后端回到渲染器悬浮菜单（上游
# 形态）；legacy：renderer=auto + mobilegl_backend=1/2/3 解析保留。
check("B7 mobilegl_backend 独立 pick 行已退役（Task131 回归锚）",
      '@"key": @"mobilegl_backend"' not in lpvc and
      '"mobilegl_backend": @(1)' in plp)
check("B8 渲染器列表含 MobileGL 家族三后端条目（Task131 恢复上游形态）",
      re.search(r'\{\s*@\"key\":\s*@ RENDERER_NAME_MOBILEGL,\n\s*@\"name\"', lp) is not None and
      re.search(r'\{\s*@\"key\":\s*@ RENDERER_NAME_MOBILEGL_GLES,\n\s*@\"name\"', lp) is not None and
      re.search(r'\{\s*@\"key\":\s*@ RENDERER_NAME_MITHRIL,\n\s*@\"name\"', lp) is not None)
check("B9 pick 行右侧显示本地化标签（存储值不进 UI）",
      "ame120_basePick" in lpvc and "ame120_keys" in lpvc)
check("B10 GameSurfaceView.layerClass 用 ame_effective_renderer（Task124 同根修复）",
      "ame_effective_renderer()" in gsv and "naturalDrawableSizeMVK" in gsv)
check("B11 旧 mobilegl_vulkan 键无代码引用（注释史料除外）",
      '@"mobilegl_vulkan"' not in jl + lp + lph + lpvc + plp + plpt + gsv + svc + gb)

print("== C. Task121 l10n 补齐 ==")
LANGS = ["en", "zh-Hans", "zh-CN", "zh-Hant"]
def l10n_keys(lang):
    ks = set()
    for line in rd(f"Natives/resources/{lang}.lproj/Localizable.strings").splitlines():
        m = re.match(r'^"([^"]+)"\s*=', line)
        if m:
            ks.add(m.group(1))
    return ks
en_keys = l10n_keys("en")
check("C1 en 键总数 >= 1875（审计基线 1858 + 补齐 23）",
      len(en_keys) >= 1875, f"got {len(en_keys)}")
for lang in LANGS[1:]:
    k = l10n_keys(lang)
    check(f"C2 {lang} 键集与 en 完全一致（缺失=0）",
          not (en_keys - k), f"missing={sorted(en_keys - k)[:5]}")
for lang in LANGS:
    s = rd(f"Natives/resources/{lang}.lproj/Localizable.strings")
    # Task 131 重锚：mobilegl_backend 行退役 -> 6 个死键已删（回归锚）；替代
    # 文案 = 渲染器菜单三后端条目（renderer.debug.mobilegl / mobilegl_gles）。
    ok = ('"preference.title.mobilegl_backend' not in s) and \
         '"preference.detail.mobilegl_backend' not in s and \
         '"preference.title.renderer.debug.mobilegl"' in s and \
         '"preference.title.renderer.debug.mobilegl_gles"' in s and \
         '"preference.title.renderer.debug.mithril"' in s
    check(f"C3 {lang} mobilegl_backend 死键已删 + 渲染器菜单三后端文案齐备（Task131）", ok)
# Task 129e 重锚：iPad 紧凑菜单（_presentMenuAtLocation 私有 API）分支已
# 退役，iPhone/iPad 统一为悬浮 actionSheet/popover；✓ 存储值比较保留。
check("C4 pick 弹窗 ✓ 标记按存储值比较（Task129e 统一单分支）",
      "ame121_cur " in plpt and "ame121_curPads" not in plpt
      and "[interaction _presentMenuAtLocation:location];" not in plpt
      and "popoverPresentationController.sourceView = cell;" in plpt)
check("C5 选中后 cell 显示本地化标签（统一分支 pickList[i]）",
      plpt.count("cell.detailTextLabel.text = pickList[i];") >= 1)
# 引用完整性：LPVC/LauncherPreferences 引用的 preference.* 键都有 en 文案
used = set(re.findall(r'localize\(@"(preference\.[^"]+)"', lpvc)) | \
       set(re.findall(r'localize\(@"(preference\.[^"]+)"', lp))
missing = {k for k in used if k not in en_keys and not k.startswith("preference.title.renderer.debug.")}
renderer_used = {k for k in used if k.startswith("preference.title.renderer.debug.")}
missing |= {k for k in renderer_used if k not in en_keys}
check("C6 代码引用的 preference.* 键在 en 全部有文案（回归清扫）",
      not missing, f"missing={sorted(missing)[:6]}")

print("== D. Task124 log 判读（zink 被回退 vk + vk 崩溃）==")
check("D1 layerClass 注释含事故链（naturalDrawableSizeMVK -> NSInvalidArgumentException）",
      "naturalDrawableSizeMVK" in gsv and "NSInvalidArgumentException" in gsv)
check("D2 gl_bridge 诊断探针（MobileGL + drawableSize 零值预警）",
      "Task124 WARN: MobileGL CAMetalLayer drawableSize still zero" in gb)
check("D3 崩溃判读入档 worklog（Task 124 条目）",
      "Task ID: 124" in rd("../worklog.md") if os.path.exists(os.path.join(REPO, "../worklog.md")) else
      "Task ID: 124" in rd("/home/z/my-project/worklog.md"))

print("== E. 语法门 ==")
def balance(src):
    state = depth = i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if state == 0:
            if c == '"': state = 1
            elif c == '/' and i + 1 < n and src[i+1] == '/': state = 3
            elif c == '/' and i + 1 < n and src[i+1] == '*': state = 4
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
        elif state == 1:
            if c == '\\': i += 1
            elif c == '"': state = 0
        elif state == 3:
            if c == '\n': state = 0
        elif state == 4:
            if c == '*' and i + 1 < n and src[i+1] == '/': state = 0; i += 1
        i += 1
    return depth
TOUCHED = ["Natives/JavaLauncher.m", "Natives/LauncherPreferences.m",
           "Natives/LauncherPreferences.h", "Natives/LauncherPreferencesViewController.m",
           "Natives/PLPreferences.m", "Natives/PLPrefTableViewController.m",
           "Natives/GameSurfaceView.m", "Natives/SurfaceViewController.m",
           "Natives/ctxbridges/gl_bridge.m", "Natives/ctxbridges/mgl_fsr.mm"]
for p in TOUCHED:
    check(f"E1 {os.path.basename(p)} 大括号平衡", balance(rd(p)) == 0)
for p in TOUCHED:
    cur = rd(p)
    head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{p}"],
                          capture_output=True, text=True).stdout or cur
    ok = all(cur.count(a) - cur.count(b) == head.count(a) - head.count(b)
             for a, b in [("{", "}"), ("(", ")"), ("[", "]")])
    check(f"E2 {os.path.basename(p)} 裸括号 delta 与 HEAD 一致", ok)
for lang in LANGS:
    s = rd(f"Natives/resources/{lang}.lproj/Localizable.strings")
    # 块注释状态机 + 逐行形态校验（跳过空行/注释；键=值; 形态）
    bad, in_block = [], False
    for l in s.splitlines():
        t = l.strip()
        if in_block:
            if "*/" in t:
                in_block = False
            continue
        if not t or t.startswith("//"):
            continue
        if t.startswith("/*"):
            if "*/" not in t:
                in_block = True
            continue
        if not re.match(r'^"[^"]+"\s*=\s*".*";\s*$', t):
            bad.append(t)
    check(f"E3 {lang} .strings 行语法（键=值; 形态）", not bad, f"bad={bad[:2]}")

print("== F. 级联：verify_task112_118 重锚后仍全绿 ==")
r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/verify_task112_118.py")],
                   capture_output=True, text=True)
check("F1 verify_task112_118 ALL PASS", r.returncode == 0,
      r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr[:200])

print(f"\n==== RESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL}) ====")
sys.exit(0 if FAIL == 0 else 1)
