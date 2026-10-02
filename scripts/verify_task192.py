#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 192 验证器：六问题修复轮（956ea9b 装机反馈 + 82d9ece 日志轮）。
A i18n（AI 界面批次注册 + localize 永不返回 nil + 四文件迁移归零）
B vgpu 材质损坏（scratch EBO 虚拟 id 根修 + 探针窗口摘要）
C gl4es 崩溃（RTLD_NEXT→RTLD_DEFAULT 二进制补丁 + payload 接线 + RTLD_GLOBAL 预载）
D 控件仓库崩溃（CCMenuViewController pickerView 越界 nil 防护）
E Forge 26.1.2（launcher.jar 剔除 com/mojang/blaze3d/platform）
F ANGLE 黑屏（tinygl4angle DSA buffer 族）
G 崩溃处理器（定时复挂）
H 语法门（两 Makefile TAB 审计 + 括号平衡 + 级联）
"""
import re
import shutil
import subprocess
import sys
import os
import tempfile

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(BASE)

PASS = FAIL = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f" -- {detail}" if detail and not cond else ""))
    if cond:
        PASS += 1
    else:
        FAIL += 1

def read(p):
    return open(p, encoding='utf-8', errors='replace').read()

def bracket_balance_text(text):
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r'"(\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(\\.|[^'\\])*'", "''", text)
    return text.count("{") - text.count("}"), text.count("[") - text.count("]")

# ============================== A. i18n ==============================
print("== A. i18n ==")
en = read("Natives/resources/en.lproj/Localizable.strings")
zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings")
for key in ("ame192.ai.title", "ame192.ai.pc.intro", "ame192.ai.mode_safe_desc", "ame192.ai.sl.msg_count"):
    check(f"A1 键注册 en+zh-Hans: {key}",
          f'"{key}"' in en and f'"{key}"' in zh)

r = subprocess.run([sys.executable, "scripts/task191_validate_strings.py"],
                   capture_output=True, text=True)
check("A2 严格 tokenizer：全部 .strings 零语法错误",
      r.returncode == 0 and "ERRORS" not in r.stdout, r.stdout[-200:])

utils_m = read("Natives/utils.m")
check("A3 localize() 永不返回 nil（Task192 出口加固）",
      "Task192：localize() 永不返回 nil 加固" in utils_m and
      "if (value == nil || [value length] == 0) {" in utils_m and
      utils_m.count("Task192：localize() 永不返回 nil 加固") == 1)

import struct as _s
def has_cjk_literal(line):
    for m in re.finditer(r'@"([^"\\]*(?:\\.[^"\\]*)*)"', line):
        if re.search(r'[\u4e00-\u9fff]', m.group(1)):
            return True
    return False

clean_files = ["AI/AIViewController.m", "AI/AiSafetyManager.m",
               "AI/AISessionListViewController.m", "AI/AIProviderConfigViewController.m"]
for f in clean_files:
    src = read(f"Natives/{f}")
    bad = [i for i, l in enumerate(src.split("\n"), 1)
           if has_cjk_literal(l) and l.strip() not in ("//",) and not l.strip().startswith("//")
           and "NSLog" not in l]
    check(f"A4 硬编码中文归零: {f}", len(bad) == 0, f"剩余行 {bad[:4]}")

for f in clean_files:
    check(f"A5 utils.h 已导入: {f}", 'import "utils.h"' in read(f"Natives/{f}"))

# ============================== B. vgpu ==============================
print("== B. vgpu scratch EBO ==")
gl4es_c = read("Natives/external/vgpu/src/gl/gl4es.c")
check("B1 gl4es_scratch_indices 用真驱动 id（Task193 重锚：函数退役为绑定+名字保障，上传单次化）",
      "gles_glGenBuffers(1, &glstate->scratch_indices);" in gl4es_c and
      "Task193：本函数退役为" in gl4es_c)
check("B2 gl4es_scratch_vertex 用真驱动 id",
      "gles_glGenBuffers(1, &glstate->scratch_vertex);" in gl4es_c and
      "Task192：虚拟 id 根修" in gl4es_c)
check("B3 裸 glGenBuffers 不再出现于两个 scratch 函数",
      gl4es_c.count("\n        glGenBuffers(1,") == 0)
drawing_c = read("Natives/external/vgpu/src/gl/drawing.c")
check("B4 afterDraw 窗口摘要锚点",
      "Task192 afterDraw window closed" in drawing_c and "lastFailSite" in drawing_c)
check("B5 scratch EBO 分配锚点日志",
      "scratch EBO allocated (real driver id=" in gl4es_c)

r = subprocess.run([sys.executable, "scripts/task189_vgpu_syntax.py"],
                   capture_output=True, text=True)
check("B6 vgpu 语法门 + 行为镜像全绿", r.returncode == 0 and "0 failure(s)" in r.stdout,
      r.stdout[-200:])

# ============================== C. gl4es ==============================
print("== C. gl4es RTLD patch ==")
patch_src = read("scripts/patch_gl4es_rtld_default.py")
check("C1 补丁脚本在位（RTLD_NEXT→RTLD_DEFAULT）",
      "0x92800020" in patch_src and "RTLD_DEFAULT" in patch_src)
mk = read("Makefile")
# Task212 重锚：holy gl4es（libgl4es_114.dylib）整体退役——补丁接线随 dylib 移除，
# 补丁脚本作为历史工件保留在 scripts/（源码法证与复现记录），仓库不再随包该 dylib。
check("C2 payload 接线已随退役移除（Task212 重锚）",
      "patch_gl4es_rtld_default.py" not in mk
      and "holy gl4es（libgl4es_114.dylib）退役删除" in mk)
import os as _os
check("C3 仓库不再携带 holy gl4es dylib（Task212 退役）",
      not _os.path.exists("Natives/resources/Frameworks/libgl4es_114.dylib"))
check("C4 补丁脚本作为历史工件保留（可复现记录）",
      _os.path.exists("scripts/patch_gl4es_rtld_default.py"))

egl = read("Natives/egl_bridge.m")
check("C8 egl_bridge 引导链随退役收档（Task212 重锚：Task192/193/202/204 的 holy 构造器铺垫退役，改道 ame211_gl4eszl2_boot）",
      "holy gl4es（libgl4es_114.dylib）整体退役" in egl and
      "ame211_gl4eszl2_boot" in egl and
      "Task212: renderer '%@' -> ZL2 classic gl4es" in egl)

# ============================== D. 控件仓库崩溃 ==============================
print("== D. CCMenu picker guards ==")
cc = read("Natives/CustomControlsViewController.m")
check("D1 didSelectRow 双守卫（值边界 + 可变数组检查）",
      "ame192_val" in cc and "isKindOfClass:[NSMutableArray class]" in cc and
      "keycode write skipped" in cc)
check("D2 viewDidLoad keycodes 补零 + NSNotFound 钳位",
      "ame192_padded" in cc and "if (ame192_idx == NSNotFound) ame192_idx = 0;" in cc)
check("D3 病历锚点注释（dSYM+IPA 反汇编定位）",
      "956ea9b" in cc and "仓库里面的控件崩溃" in cc)
b, s = bracket_balance_text(cc)
check("D4 括号平衡", b == 0 and s == 0, f"b={b} s={s}")

# ============================== E. Forge ==============================
print("== E. Forge blaze3d ==")
jm = read("JavaApp/Makefile")
check("E1 blaze3d stash 接线（jar 前 mv 走）",
      ".task192_blaze3d_stash" in jm and jm.count(".task192_blaze3d_stash") == 4)
check("E2 Task191 text2speech stash 仍在（无回归）",
      ".task191_t2s_stash" in jm and jm.count(".task191_t2s_stash") == 4)
r = subprocess.run(["make", "-C", "JavaApp", "-n", "build/launcher.jar"],
                   capture_output=True, text=True)
seq_ok = ("task192_blaze3d_stash" in r.stdout and "jar -cf build/launcher.jar" in r.stdout
          and r.stdout.find("mv build/launcher/com/mojang/blaze3d build/.task192_blaze3d_stash")
              < r.stdout.find("jar -cf build/launcher.jar")
          and r.stdout.find("mv build/.task192_blaze3d_stash build/launcher/com/mojang/blaze3d")
              > r.stdout.find("jar -cf build/launcher.jar"))
check("E3 make -n 干解析：stash 在 jar 前、恢复在 jar 后", seq_ok and "separator" not in r.stderr,
      r.stderr[-150:])
# TAB 审计
def tab_audit(path):
    bad = []
    for i, line in enumerate(read(path).split("\n"), 1):
        if line.startswith("        ") and any(line.lstrip().startswith(c) for c in
                ("@", "rm ", "mv ", "if ", "fi", "python3", "echo", "cd ")):
            bad.append(i)
    return bad
check("E4 JavaApp/Makefile TAB 完整（无空格缩进命令行）", tab_audit("JavaApp/Makefile") == [])
check("E5 根 Makefile TAB 完整", tab_audit("Makefile") == [])

# ============================== F. ANGLE DSA ==============================
print("== F. tinygl4angle DSA ==")
tgl = read("Natives/external/gl4es/tinygl4angle.c")
for fn in ("glCreateBuffers", "glNamedBufferData", "glNamedBufferSubData",
           "glBindBuffersBase", "glBindBuffersRange", "glGetNamedBufferParameteriv"):
    check(f"F1 DSA 函数实现: {fn}", f"void {fn}(" in tgl)
check("F2 DSA 探针日志锚点（Task192 dsa:）",
      tgl.count("Task192 dsa:") >= 5 and "DSA probe should now SUCCEED" in tgl)
check("F3 COPY_WRITE_BUFFER 语义（bind-free 模拟）",
      tgl.count("GL_COPY_WRITE_BUFFER") >= 6)
check("F4 Task191 UBO 转发仍在（无回归）",
      "Task191 ubo: glBindBufferRange" in tgl and "Task191 ubo: glUniformBlockBinding" in tgl)
b, s = bracket_balance_text(tgl)
check("F5 括号平衡", b == 0 and s == 0, f"b={b} s={s}")

# ============================== G. 崩溃处理器 ==============================
print("== G. handler timer ==")
sd = read("Natives/SceneDelegate.m")
check("G1 定时复挂（2s→30s 降频 + STOLEN 锚点）",
      "s_ame192_timer" in sd and "STOLEN" in sd and "NSGetUncaughtExceptionHandler" in sd)
check("G2 Task191 willConnect re-arm 仍在（无回归）",
      "Task191: uncaught-exception handler re-armed at willConnect" in sd)
b, s = bracket_balance_text(sd)
check("G3 括号平衡", b == 0 and s == 0, f"b={b} s={s}")

# ============================== H. 级联 ==============================
print("== H. cascade ==")
r = subprocess.run([sys.executable, "scripts/verify_task191.py"], capture_output=True, text=True)
check("H1 verify_task191 全绿（无回归）",
      r.returncode == 0 and "FAIL" not in r.stdout, r.stdout[-300:])
r = subprocess.run([sys.executable, "scripts/task189_vgpu_syntax.py"], capture_output=True, text=True)
check("H2 task189_vgpu_syntax 全绿", r.returncode == 0 and "0 failure(s)" in r.stdout)

print(f"\n===== Task192 verify: {PASS} passed, {FAIL} failed =====")
sys.exit(1 if FAIL else 0)
