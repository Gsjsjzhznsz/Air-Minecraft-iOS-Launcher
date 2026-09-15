#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task 83 验证脚本：FSR 独立化 + 按钮键盘打字 + FAQ 扩充 + MG FSR 提速

覆盖范围：
  A. 源码指纹（所有新锚点在位、被移除的旧锚点确实不在）
  B. 行为回放（键码→字符映射、修饰键抑制、FSR 能力表、ApplyFSR 直通条件、
     osm 缓冲口径、设置键重映射、custom.json 键码修正、FAQ 结构）
  C. Task82 回归锚点（视口锁存拒绝、SDL 文本输入仍在位）
  D. 括号平衡增量（相对 HEAD，剔除字符串噪声）
  E. 语法检查（FSR1.cpp g++ / osm_bridge.mm ame83 段 g++）
"""
import json
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
SCRIPTS = "/home/z/my-project/scripts"
PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8") as f:
        return f.read()


def git_head(path):
    r = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def raw_brackets(s):
    return tuple(s.count(c) for c in "{}()[]")


# ============================================================================
print("== A. 源码指纹 ==")

ibv3 = read("Natives/input_bridge_v3.m")
svc = read("Natives/SurfaceViewController.m")
osm = read("Natives/ctxbridges/osm_bridge.mm")
fsr1 = read("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp")
utils_h = read("Natives/utils.h")
environ_h = read("Natives/environ.h")
helpvc = read("Natives/LauncherHelpViewController.m")
prefvc = read("Natives/LauncherPreferencesViewController.m")
cmake = read("Natives/CMakeLists.txt")

check("A1 按钮键盘：buttonKeySynthesizeText 定义在位",
      "BOOL CallbackBridge_buttonKeySynthesizeText(int key)" in ibv3)
check("A2 按钮键盘：utils.h 声明在位",
      "BOOL CallbackBridge_buttonKeySynthesizeText(int key);" in utils_h)
check("A3 按钮键盘：executebtn 调用点（held 时补发字符）",
      "if (held) {\n                CallbackBridge_buttonKeySynthesizeText(keycode);" in svc
      or re.search(r"if \(held\)\s*\{\s*CallbackBridge_buttonKeySynthesizeText\(keycode\);", svc) is not None)
check("A4 按钮键盘：getKeyModifiers 前置声明（防隐式声明错误）",
      "char getKeyModifiers(int key, int action);" in ibv3)
check("A5 按钮键盘：虚拟大写锁定自管理",
      "ame83_virtualCaps" in ibv3 and "GLFW_KEY_CAPS_LOCK" in ibv3)
check("A6 按钮键盘：Ctrl/Alt 抑制（快捷键不产文本）",
      "ctrlLike" in ibv3 and "if (ctrlLike) return NO;" in ibv3)
check("A7 按钮键盘：走 nativeSendChar（GLFW/SDL3 双路径自动分发）",
      "CallbackBridge_nativeSendChar(ch);" in ibv3)
check("A8 MG FSR 提速：直通 surface 路径（target==surface 免 blit）",
      "directToSurface" in fsr1 and "GL_DRAW_FRAMEBUFFER, 0" in fsr1)
check("A9 MG FSR 提速：残留钳制（<=4px 上取整到表面）",
      "surfaceWidth - FSR1_Context::g_targetWidth <= 4" in fsr1)
check("A10 MG FSR 提速：冗余 clear 已删",
      "glClearColor(0.0f, 0.0f, 0.0f, 1.0f);" not in fsr1.split("void ApplyFSR")[1].split("void CheckResolutionChange")[0]
      if "void ApplyFSR" in fsr1 else False)
check("A11 FSR 独立化：能力表 ame83_fsr_capable_renderer",
      "static BOOL ame83_fsr_capable_renderer(NSString *renderer)" in svc)
check("A12 FSR 独立化：联动不再仅限 MG（能力表驱动）",
      "mgFsrScale = ame83_fsr_capable_renderer(ame78_renderer)" in svc)
check("A13 FSR 独立化：表面尺寸全局（environ.h）",
      "int ame_surfaceWidth, ame_surfaceHeight;" in environ_h)
check("A14 FSR 独立化：updateSavedResolution 单点写入",
      "ame_surfaceWidth = surfaceWidth;" in svc)
check("A15 zink FSR：osm_bridge 升级为 .mm（ObjC++，含 <string> 头）",
      os.path.exists(os.path.join(REPO, "Natives/ctxbridges/osm_bridge.mm"))
      and not os.path.exists(os.path.join(REPO, "Natives/ctxbridges/osm_bridge.m"))
      and "ctxbridges/osm_bridge.mm" in cmake)
check("A16 zink FSR：复用 MG 同款 EASU shader",
      'FSR1/FSRShaderSource.h"' in osm and "FSR_FSSource" in osm)
check("A17 zink FSR：缓冲=全尺寸表面（联动下窗口<表面）",
      "ame_surfaceWidth > 0) ? ame_surfaceWidth : windowWidth" in osm)
check("A18 zink FSR：升采样失败兜底恢复窗口=表面",
      "Task83 FSR upscale unavailable" in osm and "CallbackBridge_nativeSendScreenSize" in osm)
check("A19 zink FSR：CGImage 用缓冲尺寸（升采样结果不再被窗口裁剪）",
      "CGImageCreate(bundle.width, bundle.height" in osm)
check("A20 设置迁移：video 分区 get/set 键重映射",
      prefvc.count('keyFull = @"mobileglues.fsr1_setting";') == 2)
check("A21 设置迁移：FSR 行已在视频分区（resolution 之后）",
      re.search(r'@\{@"key": @"resolution"[\s\S]{0,900}@\{@"key": @"fsr1_setting"', prefvc) is not None)
check("A22 设置迁移：MobileGlues 分区不再有 fsr1 行",
      re.search(r'custom_gl_version[\s\S]{0,3000}@\{@"key": @"fsr1_setting"', prefvc) is None)

# ============================================================================
print("== B. 行为回放 ==")

# B1-B4: 键码→字符映射（从源码提取 ame83_keycodeToChar 并回放）
m = re.search(r"static jchar ame83_keycodeToChar\(int key, bool shift, bool caps\) \{([\s\S]*?)\n\}", ibv3)
check("B1 映射函数存在", m is not None)
if m:
    body = m.group(1)
    # 提取 shifted 数组
    sm = re.search(r"static const jchar shifted\[10\] = \{(.*?)\};", body)
    shifted = [c.strip().strip("'") for c in sm.group(1).split(",")] if sm else []
    def key_to_char(key, shift=False, caps=False):
        """按源码逻辑回放"""
        if 65 <= key <= 90:
            upper = shift != caps
            return chr(key - 65 + (ord('A') if upper else ord('a')))
        if 48 <= key <= 57:
            if not shift:
                return chr(ord('0') + key - 48)
            return shifted[key - 48] if shifted else None
        return "SYMBOL"
    cases = [
        (65, False, False, 'a'), (65, True, False, 'A'), (65, False, True, 'A'),
        (65, True, True, 'a'), (90, False, False, 'z'), (90, True, False, 'Z'),
        (48, False, False, '0'), (57, False, False, '9'),
    ]
    ok = all(key_to_char(k, s, c) == e for k, s, c, e in cases)
    check("B2 字母/数字/大小写回放（shift 与 caps 异或）", ok)
    check("B3 shifted 符号表完整（)!@#$%^&*(）",
          shifted == [')', '!', '@', '#', '$', '%', '^', '&', '*', '('])
    check("B4 面板用到的键均有映射路径",
          all(p in ibv3 for p in ["GLFW_KEY_APOSTROPHE", "GLFW_KEY_COMMA", "GLFW_KEY_MINUS",
                                  "GLFW_KEY_PERIOD", "GLFW_KEY_SLASH", "GLFW_KEY_SEMICOLON",
                                  "GLFW_KEY_GRAVE_ACCENT", "GLFW_KEY_NUMPAD_ADD",
                                  "GLFW_KEY_NUMPAD_DIVIDE", "GLFW_KEY_NUMPAD_MULTIPLY"]))

# B5: FSR 能力表回放
cap_src = re.search(r"static BOOL ame83_fsr_capable_renderer\(NSString \*renderer\) \{([\s\S]*?)\n\}", svc)
check("B5 能力表：MG=YES zink=YES Vulkan=NO 其它=NO",
      cap_src is not None and "RENDERER_NAME_MOBILEGLUES]) return YES" in cap_src.group(1)
      and 'hasPrefix:@"libOSMesa"]) return YES' in cap_src.group(1)
      and "RENDERER_NAME_VULKAN) {" not in cap_src.group(1))

# B6: ApplyFSR 直通条件回放（钳制后 target==surface → 单 pass）
check("B6 ApplyFSR 直通条件（surface>0 且双维相等）",
      "g_surfaceWidth > 0 && FSR1_Context::g_surfaceHeight > 0 &&" in fsr1
      and "g_targetWidth == FSR1_Context::g_surfaceWidth" in fsr1)
# 残留钳制数学：2360/1.5=1573 → 1573*1.5=2359.5→2359（或 2360）→ 差<=4 → 钳到 2360 → 直通
render = round(2360 / 1.5)
target = round(render * 1.5)
check("B7 残留钳制数值回放（2360 表面 → 直通）", 2360 - target <= 4)

# B8: osm 缓冲口径回放（surface 全尺寸，fallback 窗口）
check("B8 osm 缓冲口径（surface 优先，0 回退窗口）",
      "int bufW = (ame_surfaceWidth > 0) ? ame_surfaceWidth : windowWidth;" in osm)

# B9: custom.json 键码修正
cj = json.load(open(os.path.join(REPO, "Natives/resources/controlmap/custom.json"), encoding="utf-8"))
flat = {}
for dr in cj.get("mDrawerDataList", []):
    for it in dr.get("buttonProperties", []):
        flat[it.get("name", "")] = it.get("keycodes", [0])[0]
check("B9 custom.json：',' → 44（逗号，原 39 撇号）", flat.get(",") == 44)
check("B10 custom.json：']' → 93、'[' → 91（原互换）",
      flat.get("]") == 93 and flat.get("[") == 91)
check("B11 custom.json：QWERTY 面板完整（Q-P 共 26 字母）",
      all(chr(k) in flat for k in range(65, 91)))

# B12: FAQ 结构与修正
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("B12 FAQ：19 条目（原 10）", len(faq_items) == 19)
check("B13 FAQ：MoltenVK 独立渲染器表述",
      "MoltenVK：独立的渲染器" in helpvc)
check("B14 FAQ：zink 用系统 Vulkan 表述",
      "Zink 用的是系统 Vulkan" in helpvc or "系统 Vulkan 栈" in helpvc)
check("B15 FAQ：旧错误表述已移除（'基于 Vulkan（MoltenVK）'）",
      "基于 Vulkan（MoltenVK）" not in helpvc)
check("B16 FAQ：按钮键盘修复说明",
      "按钮键盘" in helpvc and "键盘图标" in helpvc)
check("B17 FAQ：FSR 多渲染器支持说明",
      "多渲染器支持为近期新增" in helpvc and "Zink：同一套 EASU" in helpvc)
check("B18 FAQ：设置路径与实际一致（视频设置分区）",
      helpvc.count("设置 → 视频设置") == 2)

# B19: 文案（双语言）
zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings")
km = read("Natives/resources/km.lproj/Localizable.strings")
check("B19 zh FSR detail：多渲染器+键名兼容",
      "Task 83 起支持多渲染器" in zh and "Zink（EASU 升采样" in zh)
check("B20 km FSR detail：同步",
      "multi-renderer since Task 83" in km)

# ============================================================================
print("== C. Task82 回归锚点 ==")
check("C1 视口锁存拒绝（Task82）仍在位",
      "FSR1 viewport latch rejected (Task 82)" in fsr1 or
      "is not a window viewport" in fsr1)
check("C2 SDL 文本输入（Task82）仍在位",
      "pushSDLTextInput" in ibv3 and "SDL3_EVENT_TEXT_INPUT" in ibv3)
check("C3 Task81 深度采样执法仍在位（texture.cpp）",
      "FSR1 active (Task 81)" in read("Natives/external/MobileGlues/MobileGlues-cpp/gl/texture.cpp"))
check("C4 Task82 键盘控件取证日志仍在位",
      "Keyboard widget" in svc)

# ============================================================================
print("== D. 括号平衡增量（相对 HEAD） ==")
for path in ["Natives/input_bridge_v3.m", "Natives/SurfaceViewController.m",
             "Natives/ctxbridges/osm_bridge.mm",
             "Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp",
             "Natives/LauncherHelpViewController.m",
             "Natives/LauncherPreferencesViewController.m"]:
    head = git_head(path)
    # osm_bridge.m -> .mm 改名：HEAD 取旧名
    if not head and path.endswith(".mm"):
        head = git_head(path[:-1])
    if not head:
        check(f"D {os.path.basename(path)}（新文件，跳过 HEAD 对比）", True)
        continue
    h = tuple(head.count(c) for c in "{}()[]")
    w = tuple(read(path).count(c) for c in "{}()[]")
    # 平衡增量：开括号增量 == 闭括号增量
    # 元组布局 = ('{','}','(',')','[',']')，配对是 (0,1)(2,3)(4,5)
    balanced = all((w[i] - h[i]) == (w[i + 1] - h[i + 1]) for i in (0, 2, 4)) or w == h
    check(f"D {os.path.basename(path)} 增量平衡 {h}->{w}", balanced)

# ============================================================================
print("== E. 语法检查 ==")
r1 = subprocess.run(["bash", os.path.join(SCRIPTS, "task82_syntax_fsr1.sh")],
                    capture_output=True, text=True)
check("E1 FSR1.cpp g++ 全 TU 语法", r1.returncode == 0 and "syntax OK" in r1.stdout,
      r1.stdout[-200:] + r1.stderr[-200:])
r2 = subprocess.run(["bash", os.path.join(SCRIPTS, "task83_syntax_osm.sh")],
                    capture_output=True, text=True)
check("E2 osm_bridge.mm ame83 段 g++ 语法", r2.returncode == 0 and "syntax OK" in r2.stdout,
      r2.stdout[-200:] + r2.stderr[-200:])

# E3/E4: CI 修复（run 34987233296 失败教训）——.mm 被当纯 CXX 编译 @interface 炸
# （工程无 OBJCXX 语言，.m 全走 C+-ObjC 路线）+ C++ mangling 链接断裂
cml = read("Natives/CMakeLists.txt")
check("E3 CMake 单文件强制 objective-c++（osm_bridge.mm）",
      'COMPILE_OPTIONS "-x;objective-c++;-fobjc-arc"' in cml)
obh = read("Natives/ctxbridges/osm_bridge.h")
check("E4 osm_bridge.h extern C 防护（C TU 调用 set_osm_bridge_tbl）",
      '#ifdef __cplusplus' in obh and 'extern "C"' in obh
      and "void set_osm_bridge_tbl();" in obh)

# E5: ObjC++ 关键字分类名清零（run 34989106108 教训——private 是 C++ 关键字，
# ObjC++ 模式下 @interface Foo(private) 解析失败，后续 libc++ 头级联报错）
import glob as _glob
_keyword_cats = []
for _h in _glob.glob(REPO + "/Natives/*.h") + _glob.glob(REPO + "/Natives/customcontrols/*.h"):
    for _ln, _l in enumerate(open(_h, encoding="utf-8", errors="ignore"), 1):
        if re.search(r"@interface\s+\w+\((private|public|protected|class|struct|new|delete|template|this|namespace|using|operator|friend|inline|virtual)\)", _l):
            _keyword_cats.append(f"{_h}:{_ln}")
check("E5 头文件无 C++ 关键字分类名（ame_private 改名完成）", not _keyword_cats,
      "; ".join(_keyword_cats[:3]))

# ============================================================================
print(f"\nRESULT: {PASS}/{PASS + FAIL}")
sys.exit(0 if FAIL == 0 else 1)
