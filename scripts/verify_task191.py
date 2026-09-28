#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 191 验证器：六问题修复轮（dde0f82 装机反馈）。
A i18n（en.lproj 语法 + localize 兜底）
B vgpu direct-elements EBO 化（方块线条化/材质损坏根修）
C Forge 26.1.2 text2speech 包冲突（launcher.jar 剔除）
D 控件编辑器崩溃防御（insertObject 防护 + undo 清栈 + re-arm 锚点）
E 强制横屏方向反转（设备物理方向定向 + 180° 翻转 + 通知重评估）
F ANGLE 黑屏第三轮取证（UBO 绑定族 + phase-tag 噪音根修 + swap UBO 查询）
G 语法门（括号平衡 + vgpu 既有语法门）
"""
import re, subprocess, sys, os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(BASE)

PASS = FAIL = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        print(f"[PASS] {name}")
        PASS += 1
    else:
        print(f"[FAIL] {name} {detail}")
        FAIL += 1

def read(p):
    return open(p, encoding='utf-8', errors='replace').read()

# ============================== A. i18n ==============================
print("== A. i18n ==")
en = read("Natives/resources/en.lproj/Localizable.strings")
check("A1 en.lproj 内层引号已转义（Task188 下载完成文案）",
      chr(92) + '"%@' in [l for l in en.split(chr(10)) if 'download.done' in l][0],
      "expect escaped inner quotes")

r = subprocess.run([sys.executable, "scripts/task191_validate_strings.py"],
                   capture_output=True, text=True)
check("A2 严格 tokenizer：全部 .strings 零语法错误",
      r.returncode == 0 and "ERRORS" not in r.stdout, r.stdout[-200:])

utils_m = read("Natives/utils.m")
check("A3 localize() override 路径 zh-Hans 兜底",
      utils_m.count('pathForResource:@"zh-Hans"') == 2,
      "expect exactly 2 (override path + system path)")

# ============================== B. vgpu ==============================
print("== B. vgpu direct-elements EBO ==")
drawing = read("Natives/external/vgpu/src/gl/drawing.c")
check("B1 ame191_drawElementsViaEBO 函数在位",
      "static void ame191_drawElementsViaEBO" in drawing)
check("B2 上传序列：scratch_indices -> 单次 glBufferData -> fpe(NULL) -> 解绑（Task193 重锚：上传单次化）",
      all(s in drawing for s in [
          "gl4es_scratch_indices(bytes);",
          "gles_glBufferData(GL_ELEMENT_ARRAY_BUFFER, bytes, indices, GL_DYNAMIC_DRAW);",
          "fpe_glDrawElements(mode, count, type, NULL);",
          "gl4es_use_scratch_indices(0);"]))
check("B3 探针站点名 direct-elements-ebo（装机锚点）",
      '"direct-elements-ebo"' in drawing)
check("B4 ES2+ 才走 EBO 路径（hardext.esversion > 1 分支）",
      re.search(r'if\s*\(hardext\.esversion > 1\)\s*\{\s*ame191_drawElementsViaEBO', drawing) is not None)
check("B5 ES1.1 保持原 CPU 指针直传（回归保护）",
      re.search(r'\}\s*else\s*\{\s*gles_glDrawElements\(mode, count, ame191_type, ame191_ptr\);', drawing) is not None)
check("B6 病历锚点：0x0502 与 client-memory index array 定性",
      "0x0502" in drawing and "client-memory index array" in drawing)

# ============================== C. Forge ==============================
print("== C. Forge 26.1.2 text2speech ==")
mk = read("JavaApp/Makefile")
check("C1 stash 剔除序列（打 jar 前 mv 走）",
      "mv $(basename $@)/com/mojang/text2speech $(OUTPUTDIR)/.task191_t2s_stash" in mk)
check("C2 打包顺序：剔除在 jar -cf 之前",
      mk.find("mv $(basename $@)/com/mojang/text2speech") < mk.find("$(BOOTJDK)/jar -cf $@ -C $(basename $@) ."))
check("C3 stash 防御性清场（rm -rf 在 mv 前）",
      mk.find("@rm -rf $(OUTPUTDIR)/.task191_t2s_stash") < mk.find("mv $(basename $@)/com/mojang/text2speech"))
check("C4 打包后恢复目录（mojang-stubs cp 源保留）",
      "mv $(OUTPUTDIR)/.task191_t2s_stash $(basename $@)/com/mojang/text2speech" in mk)
check("C5 mojang-stubs.jar 规则未变（cp 源仍指向 launcher 目录）",
      "cp -R $(OUTPUTDIR)/launcher/com/mojang/text2speech $(OUTPUTDIR)/mojang-stubs/com/mojang/" in mk)
check("C6 病历锚点：ResolutionException 文案",
      "Modules mojang.stubs and" in mk)

# ============================== D. 控件编辑器 ==============================
print("== D. 控件编辑器崩溃防御 ==")
undo_m = read("Natives/CustomControlsViewController+UndoManager.m")
check("D1 doAddButton nil 防护（Task191 guarded 锚点）",
      "Task191: doAddButton guarded" in undo_m and
      "if (!button || !button.properties || !index)" in undo_m)
cc_vc = read("Natives/CustomControlsViewController.m")
check("D2 loadControlFile 清 undo 栈",
      re.search(r'loadControlFile:\(NSString \*\)file \{\s*// Task191.*?\[self\.undoManager removeAllActions\];',
                cc_vc, re.S) is not None)
sd = read("Natives/SceneDelegate.m")
check("D3 SceneDelegate re-arm 带装机锚点日志",
      "Task191: uncaught-exception handler re-armed at willConnect" in sd)

# ============================== E. 强制横屏 ==============================
print("== E. 强制横屏方向反转 ==")
check("E1 LandscapeRight -> +90°（内容顶部转屏幕右）",
      re.search(r'UIDeviceOrientationLandscapeRight\)\s*\{\s*angle = \(CGFloat\)M_PI_2;', sd) is not None)
check("E2 LandscapeLeft -> -90°",
      re.search(r'UIDeviceOrientationLandscapeLeft\)\s*\{\s*angle = \(CGFloat\)\(-M_PI_2\);', sd) is not None)
check("E3 ame191_landscapeBaseline 属性声明",
      "@property (nonatomic, assign) UIDeviceOrientation ame191_landscapeBaseline;" in sd)
check("E4 180° 翻转分支（CGAffineTransformMakeRotation((CGFloat)M_PI)）",
      "CGAffineTransformMakeRotation((CGFloat)M_PI)" in sd)
check("E5 方向变化通知注册 + 加速计采样",
      "UIDeviceOrientationDidChangeNotification" in sd and
      "beginGeneratingDeviceOrientationNotifications" in sd)
check("E6 sceneDidDisconnect 摘除方向监听",
      re.search(r'sceneDidDisconnect.*?UIDeviceOrientationDidChangeNotification', sd, re.S) is not None)
check("E7 旧的 interfaceOrientation 选向逻辑已退役",
      "scene.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown" not in sd)
check("E8 装机锚点日志（Task191 portrait window / landscape window flipped）",
      "Task191: portrait window -> content rotated" in sd and
      "Task191: landscape window flipped" in sd)
check("E9 逃生舱偏好保留",
      "general.disable_window_rotation_shim" in sd)

# ============================== F. ANGLE ==============================
print("== F. ANGLE 第三轮取证 ==")
tgl = read("Natives/external/gl4es/tinygl4angle.c")
check("F1 glBindBufferRange 显式转发 + UBO 日志",
      "void glBindBufferRange(" in tgl and "Task191 ubo: glBindBufferRange" in tgl)
check("F2 glBindBufferBase 显式转发 + UBO 日志",
      "void glBindBufferBase(" in tgl and "Task191 ubo: glBindBufferBase" in tgl)
check("F3 glUniformBlockBinding 显式转发 + 日志",
      "void glUniformBlockBinding(" in tgl and "Task191 ubo: glUniformBlockBinding" in tgl)
check("F4 非对齐 offset 检查（UNALIGNED-256 标记）",
      "UNALIGNED-256" in tgl)
glb = read("Natives/ctxbridges/gl_bridge.m")
check("F5 swap 探针新增 UBO 查询（uboAlign/uboBind）",
      "GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT" in glb and "GL_UNIFORM_BUFFER_BINDING" in glb and
      "uboAlign=%d uboBind=%d" in glb)
check("F6 phase-tag 前置清错（噪音根修）",
      re.search(r'// Task191 修正.*?\n.*?while \(es\.getError\(\)\) \{\}\s*\n\s*unsigned int ame188_err',
                glb, re.S) is not None)
check("F7 病历锚点（RenderPearl 纯 UBO）",
      "RenderPearl 纯 UBO 上传矩阵" in glb)

# ============================== G. 语法门 ==============================
print("== G. 语法门 ==")
def bracket_balance(content, strip_str_literals=False):
    # 粗平衡：去掉行注释与字符串字面量后数括号（.m 文件用严格模式）
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
    content = re.sub(r'//[^\n]*', '', content)
    content = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', content)
    content = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", content)
    depth = 0
    for ch in content:
        if ch == '{': depth += 1
        elif ch == '}': depth -= 1
        if depth < 0: return False
    return depth == 0

for f in ["Natives/SceneDelegate.m", "Natives/utils.m",
          "Natives/CustomControlsViewController.m",
          "Natives/CustomControlsViewController+UndoManager.m",
          "Natives/ctxbridges/gl_bridge.m"]:
    check(f"G 括号平衡 {os.path.basename(f)}", bracket_balance(read(f)))

check("G 括号平衡 tinygl4angle.c", bracket_balance(read("Natives/external/gl4es/tinygl4angle.c")))
check("G 括号平衡 drawing.c", bracket_balance(read("Natives/external/vgpu/src/gl/drawing.c")))

r = subprocess.run([sys.executable, "scripts/task189_vgpu_syntax.py"],
                   capture_output=True, text=True)
check("G vgpu 既有语法门（task189_vgpu_syntax.py）",
      r.returncode == 0 and "0 failure" in r.stdout, r.stdout[-150:])

# ============================== H. 级联 ==============================
print("== H. 级联 spot check ==")
for v in ["verify_task188.py", "verify_task189.py", "verify_task190.py"]:
    r = subprocess.run([sys.executable, f"scripts/{v}"], capture_output=True, text=True)
    ok = r.returncode == 0
    tail = r.stdout.strip().split("\n")[-1] if r.stdout.strip() else "(no output)"
    check(f"H 级联 {v}", ok, tail)

print(f"\nRESULT: {PASS} pass, {FAIL} fail")
sys.exit(1 if FAIL else 0)
