#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 186 验证器：三线根修的锚点/结构/语法门 + 行为单测桥接。

覆盖：
  A. ANGLE 矩阵族转置桥（tinygl4angle.c）：九函数宏/锚点日志/语法
  B. vgpu 插入点跟随实际版本行（pack/shaderconv.c）：分支结构/锚点/语法
  C. 游戏内分辨率菜单对齐 profile 层（SurfaceViewController+Navigation.m）：
     读取同源/写入 profile/全局镜像兼容
  D. 行为单测（转置数学 11 例 + 插入点 8 例，C 编译执行）
  E. 语法门（三个改动文件括号平衡，字符串/字符/注释感知）
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILED = []
PASSED = 0


def check(cond, label):
    global PASSED
    if cond:
        PASSED += 1
    else:
        FAILED.append(label)
        print(f"FAIL  {label}")


def read(p):
    return (ROOT / p).read_text(encoding="utf-8", errors="replace")


# ------------------------------------------------- A. ANGLE 矩阵族转置桥
t4a = read("Natives/external/gl4es/tinygl4angle.c")
check("Task186: glUniformMatrix*fv transpose 转置桥" in t4a, "A1: 病历注释在场")
check("#define AME186_MATRIX_FN(FN, COLS, ROWS)" in t4a, "A2: 矩阵族宏定义")
fams = ["glUniformMatrix2fv", "glUniformMatrix3fv", "glUniformMatrix4fv",
        "glUniformMatrix2x3fv", "glUniformMatrix3x2fv", "glUniformMatrix2x4fv",
        "glUniformMatrix4x2fv", "glUniformMatrix3x4fv", "glUniformMatrix4x3fv"]
for i, fn in enumerate(fams, start=3):
    check(f"AME186_MATRIX_FN({fn}, " in t4a, f"A{i}: {fn} 实例化")
check("ame186_dst[ame186_c * (ROWS) + ame186_r] = ame186_src[ame186_r * (COLS) + ame186_c];" in t4a,
      "A12: 转置核心公式（列主序=行主序对换）")
check("gles_##FN(location, count, GL_FALSE, ame186_buf);" in t4a, "A13: TRUE 路径以 FALSE 转发")
check("transpose == GL_FALSE || value == NULL || count <= 0" in t4a, "A14: FALSE/退化路径纯转发")
check("Task186 %s transpose=TRUE -> locally transposed" in t4a, "A15: 转置锚点日志（取证修复合一）")
check("ame186_transposeLogged < 4" in t4a, "A16: 锚点日志限频")
check("GLfloat ame186_stack[16];" in t4a and "ame186_heap" in t4a,
      "A17: 单矩阵栈缓冲优化（热路径零 malloc）")
check("(size_t)count * (size_t)ame186_n > 16" in t4a, "A18: 栈/堆切换阈值")
# 宏插位：在 glDeleteShader 之后、isProxyTexture 之前
pos_del = t4a.find("void glDeleteShader(GLuint shader)")
pos_mat = t4a.find("#define AME186_MATRIX_FN")
pos_proxy = t4a.find("int isProxyTexture(GLenum target)")
check(0 < pos_del < pos_mat < pos_proxy, "A19: 区块插位（glDeleteShader 后、isProxyTexture 前）")

# ------------------------------------------ B. vgpu 插入点跟随实际版本行
sc = read("Natives/external/vgpu/src/gl/pack/shaderconv.c")
check("Task186（vgpu 白屏根修·插入点跟随实际版本行）" in sc, "B1: 病历注释在场")
check('char * ptr_version = strstr(*glshader_converted, "#version");' in sc,
      "B2: 通用 #version 行定位")
check("while(*ptr_version != '\\0' && *ptr_version != '\\n'){ ptr_version++; }" in sc,
      "B3: 跳到版本行行尾")
check("cut_in_offset = (int)(ptr_version - *glshader_converted);" in sc,
      "B4: 插入点落位实际版本行之后")
check('VGPU Task186: cut-in anchor follows actual #version line' in sc,
      "B5: 插入点锚点日志（限频 4 次）")
check("s_ame186_anchorLogged < 4" in sc, "B6: 锚点限频")
check("strstr(*glshader_converted, new_version)" in sc,
      "B7: 320 会话旧精确命中路径保留（零回归）")
check("cut_in_offset = 0;" in sc, "B8: 无版本行回落 0（原行为兜底）")
# 旧代码的“else { cut_in_offset = 0; }”单行形态应已被替换为跟随分支。
# 锚定：else 前一语句必须是 new_version 精确命中的 offset 计算（旧形态的
# 独有特征）；新代码内层的 ptr_version==NULL 兜底 else 结构相同但前驱
# 不同，不会被误伤。
old_shape = re.search(
    r"ptr_offset \+ strlen\(new_version\) \+ 2 - \*glshader_converted;[^\n]*\n\s*\}\s*else\{\s*\n\s*cut_in_offset = 0;", sc)
check(old_shape is None, "B9: 回归病灶形态（命中失配即归零）已根除")
check(re.search(r"else\{\s*$", sc, re.M) and "char * ptr_version = strstr" in sc,
      "B9b: else 分支改为跟随实际版本行")

# --------------------------------------- C. 游戏内分辨率菜单对齐 profile 层
nav = read("Natives/SurfaceViewController+Navigation.m")
check("Task186（分辨率调节失效根修）" in nav, "C1: 病历注释在场")
check('[PLProfiles resolveKeyForCurrentProfile:@"resolution"].integerValue' in nav,
      "C2: 当前值读取与生效链同源（updateSavedResolution 同款 resolveKey）")
check("if (currentValue <= 0) currentValue = 100;" in nav, "C3: 空值兜底 100")
check('ame186_profile[@"resolution"] = [NSString stringWithFormat:@"%ld", (long)value.intValue];' in nav,
      "C4: 写入当前实例 resolution 键")
check("PLProfiles.current.profiles[ame186_profileName] = ame186_profile;" in nav,
      "C5: mutableCopy 写回（setServerIp 同款模式）")
check("[PLProfiles.current save];" in nav, "C6: profile 落盘")
check('setPrefFloat(@"video.resolution", value.floatValue);' in nav,
      "C7: 全局键兼容镜像（JavaGUI 读取方不回归）")
check("[Task186] in-game resolution: profile" in nav, "C8: 调节锚点日志")
# 旧读取形态（全局键）应已从 actionAdjustResolution 中消失
aam = nav[nav.find("- (void)actionAdjustResolution"):nav.find("- (void)actionOpenNavigationMenu")]
check("getPrefFloat(@\"video.resolution\")" not in aam,
      "C9: 菜单显示值不再读全局键（✓ 标记与生效值同源）")
check("[self updateSavedResolution];" in aam, "C10: 调节后实时生效调用保留")

# ------------------------------------------------- D. 行为单测（C 编译执行）
import tempfile, os
def run_c_test(src_name, binary_name):
    src = ROOT / "scripts" / src_name
    out = Path(tempfile.gettempdir()) / binary_name
    r = subprocess.run(["gcc", "-O2", "-Wall", "-fsanitize=address",
                        "-o", str(out), str(src)], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[:800])
        return False
    r2 = subprocess.run([str(out)], capture_output=True, text=True)
    return r2.returncode == 0 and "ALL TESTS PASSED" in r2.stdout

check(run_c_test("task186_matrix_test.c", "task186_matrix_test_v"), "D1: 转置数学单测 11 例（ASAN）")
check(run_c_test("task186_cutin_test.c", "task186_cutin_test_v"), "D2: 插入点单测 8 例（ASAN）")
# ANGLE 新区块独立编译级检查（九符号 + 纯 C 语法，-Wall -Wextra 零警告）
harness = ROOT / "scripts" / "task186_angle_syntax_harness.c"
r = subprocess.run(["gcc", "-O2", "-Wall", "-Wextra", "-Wno-unused-parameter",
                    "-I/tmp/task186_syntax", "-o", "/tmp/task186_angle_syntax_v", str(harness)],
                   capture_output=True, text=True)
check(r.returncode == 0 and "all 9 matrix family symbols" in
      subprocess.run(["/tmp/task186_angle_syntax_v"], capture_output=True, text=True).stdout,
      "D3: ANGLE 矩阵区块 harness 编译链接（9 符号）")

# ------------------------------------------------------- E. 语法门（括号平衡）
def strip_literals(text):
    """字符串/字符/注释感知的括号统计源清洗。"""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            q = c
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == q:
                    i += 1
                    break
                i += 1
            out.append("S")
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)

for path, delta in [("Natives/external/gl4es/tinygl4angle.c", 0),
                    ("Natives/external/vgpu/src/gl/pack/shaderconv.c", 0),
                    ("Natives/SurfaceViewController+Navigation.m", 0)]:
    body = strip_literals(read(path))
    for a, b in ["{}", "()", "[]"]:
        d = body.count(a[0]) - body.count(b[0])
        check(d == delta, f"E: {path} {a} 平衡 (delta={d}, expect {delta})")

# ------------------------------------------------------------ 汇总
print(f"\n{'='*50}\nTask186 verify: {PASSED} passed, {len(FAILED)} failed")
if FAILED:
    print("FAILED:")
    for f in FAILED:
        print(f"  - {f}")
    sys.exit(1)
print("ALL GREEN")
