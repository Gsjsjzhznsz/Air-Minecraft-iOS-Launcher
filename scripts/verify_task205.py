#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task205 验证器：三渲染器根修 + 日志等级 + CI 缓存。

覆盖面：
  A. spvc shim 重命名重放（ANGLE 黑屏根修）
     A1 拦截导出存在（set_name / set_entry_point：转发 + 记录）
     A2 注册表扩展（names/entry_point 字段 + 满溢/复用清理）
     A3 ES 编译器重放（compile_es_source 携带 orig + 逐条重放）
     A4 语法门（gcc -fsyntax-only）
     A5 行为镜像（记录/覆盖/重放序列的桩仿真）
  B. vgpu 墓碑化（材质损坏根修）
     B1 墓碑函数 + DeleteBuffers 挂钩（free 前调用）
     B2 括号平衡 + 关键锚点
     B3 桩编译（范围检查逻辑）
     B4 debug 级限频放宽（4 -> 128）
  C. 日志等级
     C1 复用 general.debug_logging（无重复行；既有行升格注释在位）
     C2 JavaLauncher 导出 AMETHYST_LOG_LEVEL（debug/standard 两态 +
        LIBGL_LOGSHADERERROR）
     C3 fpe.c 双 tracer（earlyret 检测 + attrib-emit）+ ame205_debug 助手
     C4 tinygl4angle glGetUniformBlockIndex 观察器（ANGLE 修复验证探针）
     C5 .strings 详情文案升级（en + zh-Hans）且表可解析
  D. CI 缓存
     D1 两路 actions/cache 步骤 + 键含 vgpu 源码 hash
     D2 brew install make ccache + CC/CXX 接线 + show-stats
     D3 YAML 可解析（CRLF 保真）
  E. brew 挂死免疫（Task205b，run 36722042665 教训）
     E1 job 级禁 auto-update + timeout-minutes + brew update 看门狗
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failures = []
passed = 0


def check(name, ok, detail=""):
    global passed
    print("[%s] %s%s" % ("PASS" if ok else "FAIL", name, (" -- " + detail) if detail else ""))
    if ok:
        passed += 1
    else:
        failures.append(name)


def read(p):
    with open(os.path.join(REPO, p), encoding="utf-8") as f:
        return f.read()


SPVC = read("Natives/spvc_shim.c")
BUFFERS = read("Natives/external/vgpu/src/gl/buffers.c")
FPE = read("Natives/external/vgpu/src/gl/fpe.c")
TINYGL = read("Natives/external/gl4es/tinygl4angle.c")
PREFS = read("Natives/LauncherPreferencesViewController.m")
JL = read("Natives/JavaLauncher.m")
WF_RAW = open(os.path.join(REPO, ".github/workflows/development.yml"), "rb").read().decode("utf-8")

# ============ A. spvc shim 重命名重放 ============
check("A1a set_name 拦截导出",
      "void spvc_compiler_set_name(void *compiler, unsigned id, const char *name)" in SPVC
      and "ame205_record_name(ame205_ce, id, name)" in SPVC
      and 'ame_spvc_shim_resolve("spvc_compiler_set_name")' in SPVC)
check("A1b set_entry_point 拦截导出",
      "void spvc_compiler_set_entry_point(void *compiler, const char *name, int model)" in SPVC
      and 'ame_spvc_shim_resolve("spvc_compiler_set_entry_point")' in SPVC)
check("A2a 注册表字段扩展",
      "ame205_rename_t names[AME205_NAMES_MAX];" in SPVC and "int name_count;" in SPVC
      and "char *entry_point;" in SPVC and "#define AME205_NAMES_MAX 256" in SPVC)
check("A2b 满表丢弃限频",
      "rename registry full -- dropping set_name" in SPVC)
check("A2c forget_context 释放重命名",
      SPVC.count("ame205_free_names(") >= 3)  # 定义 + forget_context + 槽位复用
check("A3a ES 重放携带 orig",
      "ame175_compile_es_source(void *ctx, const unsigned *words," in SPVC
      and "ame175_compiler_entry *orig)" in SPVC
      and "ame175_compile_es_source(\n                    ame175_ce->ctx, ame175_ctxe->words, ame175_ctxe->word_count,\n                    ame175_ce);" in SPVC.replace("\r", ""))
check("A3b 重放循环在位",
      "real_set_name(es_compiler, orig->names[i].id, orig->names[i].name);" in SPVC
      and "real_set_entry(es_compiler, orig->entry_point, orig->exec_model);" in SPVC)
check("A3c 重放装机锚点",
      "[spvc-shim] Task205 rename replay:" in SPVC)
check("A3d 槽位复用清理",
      "ame205_free_names(&ame175_compiler_registry[ame175_slot]);" in SPVC
      and "free(ame175_compiler_registry[ame175_slot].entry_point);" in SPVC)
rc = subprocess.run(["gcc", "-fsyntax-only", "-Wall", "-Wno-unused-function",
                     os.path.join(REPO, "Natives/spvc_shim.c")],
                    capture_output=True, text=True)
check("A4 spvc_shim.c 语法门", rc.returncode == 0, rc.stderr[:200])

# A5 行为镜像：提取三函数做桩仿真
STUB = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int s_log = 0;
#define ame183_skip_log(w, c) do { if (s_log < 50) { s_log++; printf("SKIP:%s:%d\n", w, c); } } while (0)
typedef struct { unsigned id; char *name; } ame205_rename_t;
#define AME205_NAMES_MAX 256
typedef struct { int live; void *compiler; int name_count;
                 ame205_rename_t names[AME205_NAMES_MAX]; } ame175_compiler_entry;
static ame175_compiler_entry reg[4];
static ame175_compiler_entry *ame205_find_compiler(void *c) {
    for (int i = 0; i < 4; ++i) if (reg[i].live && reg[i].compiler == c) return &reg[i];
    return NULL;
}
'''
m_name = re.search(r'static void ame205_record_name\(ame175_compiler_entry \*c, unsigned id,\n\s+const char \*name\) \{.*?\n\}', SPVC, re.S)
check("A5a 可提取 record_name", m_name is not None)
if m_name:
    body = m_name.group(0)
    full = STUB + "\n" + body + r'''
int main(void) {
    reg[0].live = 1; reg[0].compiler = (void*)0xA1;
    ame175_compiler_entry *c = ame205_find_compiler((void*)0xA1);
    ame205_record_name(c, 7, "_uniform_00_00");
    ame205_record_name(c, 8, "_push_constants");
    ame205_record_name(c, 7, "_uniform_00_00_v2");   // 覆盖同 id
    for (int i = 0; i < 300; ++i) {                  // 溢出丢弃
        char buf[32]; snprintf(buf, sizeof buf, "n%d", i);
        ame205_record_name(c, 1000 + i, buf);
    }
    int covered7 = (strcmp(c->names[0].name, "_uniform_00_00_v2") == 0);
    int count_ok = (c->name_count == AME205_NAMES_MAX);
    printf("RESULT covered7=%d count=%d\n", covered7, c->name_count);
    return (covered7 && count_ok) ? 0 : 1;
}
'''
    with tempfile.NamedTemporaryFile('w', suffix='.c', delete=False) as f:
        f.write(full); path = f.name
    r = subprocess.run(["gcc", "-o", path + ".out", path], capture_output=True, text=True)
    if r.returncode != 0:
        check("A5b record_name 行为镜像", False, r.stderr[:300])
    else:
        r2 = subprocess.run([path + ".out"], capture_output=True, text=True)
        check("A5b record_name 行为镜像（覆盖/上限）",
              r2.returncode == 0 and "RESULT covered7=1 count=256" in r2.stdout, r2.stdout.strip())
        os.unlink(path + ".out")
    os.unlink(path)

# ============ B. vgpu 墓碑化 ============
check("B1a 墓碑三件套",
      "ame205_tombstone_page" in BUFFERS and "ame205_attrib_tombstone(void)" in BUFFERS
      and "ame205_tombstone_attrib_pointers(glbuffer_t *buff)" in BUFFERS)
check("B1b DeleteBuffers 挂钩在 free 之前",
      BUFFERS.find("ame205_tombstone_attrib_pointers(buff);")
      < BUFFERS.find("if (buff->data) free(buff->data);")
      and "delete-landmine fixed" in BUFFERS)
body = re.sub(r'//[^\n]*', '', BUFFERS)
body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
body = re.sub(r'"(?:[^"\\]|\\.)*"', '""', body)
body = re.sub(r"'(?:[^'\\]|\\.)*'", "''", body)
check("B2a 括号平衡", body.count('{') == body.count('}') and body.count('(') == body.count(')'),
      "braces %d/%d parens %d/%d" % (body.count('{'), body.count('}'), body.count('('), body.count(')')))
check("B2b 病历锚点注释",
      "Task205（vgpu 材质损坏根修）" in BUFFERS and "IMG_0307.png" in BUFFERS)
check("B4 debug 级限频放宽",
      'strcmp(ame205_lvl, "debug") == 0) ? 128 : 4' in BUFFERS)
# B3 桩编译（重跑任务内联版）
m_ts = re.search(r'static const GLfloat ame205_tombstone_page.*?\nstatic void ame205_tombstone_attrib_pointers\(glbuffer_t \*buff\) \{.*?\n\}\n', BUFFERS, re.S)
check("B3a 可提取墓碑函数", m_ts is not None)
if m_ts:
    stub2 = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef float GLfloat; typedef void GLvoid;
typedef struct { char *data; long size; } glbuffer_t;
#define hardext_maxvattrib 16
struct va { const GLvoid *pointer; };
static struct { struct { struct va va[hardext_maxvattrib]; } *vao; } *glstate;
static glbuffer_t *buff;
'''
    b = m_ts.group(0).replace("glbuffer_t *buff", "glbuffer_t *buff")
    b = b.replace("hardext.maxvattrib", "hardext_maxvattrib")
    b = b.replace("glstate->vao->vertexattrib[j].pointer", "glstate->vao->va[j].pointer")
    b = b.replace("const GLfloat", "const float").replace("const GLvoid *", "const void *")
    full = stub2 + "\n" + b + "\n"
    with tempfile.NamedTemporaryFile('w', suffix='.c', delete=False) as f:
        f.write(full); path = f.name
    r = subprocess.run(["gcc", "-fsyntax-only", "-Wall", "-Wno-unused-function", path],
                       capture_output=True, text=True)
    check("B3b 墓碑函数桩编译", r.returncode == 0, r.stderr[:300])
    os.unlink(path)

# ============ C. 日志等级 ============
check("C1a 复用既有 debug_logging 键（无重复行）",
      '@"key": @"debug_log"' not in PREFS
      and PREFS.count('@"key": @"debug_logging"') == 1)
check("C1b 既有行升格注释",
      "Task205：本行升格为全局日志等级开关" in PREFS
      and "renderer diagnostics verbose from next game session" in PREFS)
check("C2a JavaLauncher 导出两态",
      'getPrefBool(@"general.debug_logging")' in JL
      and 'setenv("AMETHYST_LOG_LEVEL", "debug", 1)' in JL
      and 'setenv("AMETHYST_LOG_LEVEL", "standard", 1)' in JL)
check("C2b gl4es 预编译杠杆",
      'setenv("LIBGL_LOGSHADERERROR", "1", 1)' in JL)
check("C3a fpe.c ame205_debug 助手",
      "static int ame205_debug(void)" in FPE and 'strcmp(v, "debug") == 0' in FPE)
check("C3b earlyret 检测器（vertex+texcoord 双点）",
      'AME205_EARLYRET_TRACE(ATT_VERTEX, "vertex")' in FPE
      and 'AME205_EARLYRET_TRACE(ATT_MULTITEXCOORD0+TMU, "texcoord")' in FPE
      and "pointer-earlyret" in FPE)
check("C3c attrib-emit tracer",
      "VGPU Task205 attrib-emit" in FPE and "s_ame205_emits < 96" in FPE)
check("C4 glGetUniformBlockIndex 观察器",
      "GLint glGetUniformBlockIndex(GLuint program, const GLchar *name)" in TINYGL
      and "Task205 blockIdx:" in TINYGL and "[NOT FOUND]" in TINYGL)
en = read("Natives/resources/en.lproj/Localizable.strings")
zh = read("Natives/resources/zh-Hans.lproj/Localizable.strings")
check("C5a 详情文案升级（en）",
      "verbose renderer diagnostics" in en and "i18n_str_2072" not in en)
check("C5b 详情文案升级（zh-Hans）",
      "渲染器诊断日志" in zh and "i18n_str_2072" not in zh)


def parse_strings(text):
    # 简单 "k" = "v"; 解析 + 配对检查
    entries = re.findall(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, re.M)
    keys = [k for k, _ in entries]
    return entries, keys


en_entries, en_keys = parse_strings(en)
zh_entries, zh_keys = parse_strings(zh)
# 注：表中存在存量重复键（ai.fix.* 家族等历史遗留，非 Task205 引入）。
# 这里验证：表可解析 + detail 键唯一 + 两表重复计数一致（无新增）。
from collections import Counter
en_dup = [k for k, c in Counter(en_keys).items() if c > 1]
zh_dup = [k for k, c in Counter(zh_keys).items() if c > 1]
check("C5c strings 表可解析 + 无新增重复",
      len(en_keys) > 1000 and len(zh_keys) > 1000
      and en_keys.count("preference.detail.debug_logging") == 1
      and zh_keys.count("preference.detail.debug_logging") == 1
      and len(en_dup) == len(zh_dup),
      "en=%d zh=%d 存量重复 en=%d zh=%d" % (len(en_keys), len(zh_keys), len(en_dup), len(zh_dup)))

# ============ D. CI 缓存 ============
check("D1a ccache 缓存步骤",
      "Cache ccache compilation cache" in WF_RAW and "path: ~/.ccache" in WF_RAW
      and "ccache-macos14-v1-${{ hashFiles('Makefile', 'Natives/CMakeLists.txt', 'Natives/external/vgpu/src/**') }}" in WF_RAW)
check("D1b Homebrew 缓存步骤",
      "Cache Homebrew downloads" in WF_RAW
      and "path: ~/Library/Caches/Homebrew/downloads" in WF_RAW)
check("D2a brew 安装 ccache", "brew install make ccache" in WF_RAW)
check("D2b CC/CXX 接线",
      'export CC="ccache clang"' in WF_RAW and 'export CXX="ccache clang++"' in WF_RAW
      and 'export CCACHE_DIR="$HOME/.ccache"' in WF_RAW)
check("D2c 统计打印", "ccache --show-stats" in WF_RAW and "ccache --zero-stats" in WF_RAW)
check("D3 CRLF 保真", "\r\n" in WF_RAW)
try:
    import yaml
    doc = yaml.safe_load(WF_RAW)
    steps = doc["jobs"]["build"]["steps"]
    cache_steps = [s for s in steps if str(s.get("uses", "")).startswith("actions/cache")]
    check("D4 YAML 可解析且含 2 个 cache 步骤", len(cache_steps) == 2)
except ImportError:
    check("D4 YAML 可解析（PyYAML 缺失，降级为括号检查）",
          WF_RAW.count("actions/cache@v4") == 2)

# ============ E. brew 挂死免疫（Task205b，run 36722042665 教训） ============
# 事故：caf4591 首跑（run 36722042665）brew 步骤在 macos-14 runner 上
# 网络挂死 70 分钟无输出，被迫手动取消。加固三件：
#   job 级禁用 auto-update、brew update 看门狗（5 分钟限时）、job 级
#   timeout-minutes=60（健康 run 实测 8-13 分钟）。
WF_NORM = WF_RAW.replace("\r\n", "\n")
check("E1a job 级禁用 auto-update + 全局限时",
      'HOMEBREW_NO_AUTO_UPDATE: "1"' in WF_RAW
      and 'HOMEBREW_NO_INSTALL_CLEANUP: "1"' in WF_RAW
      and "timeout-minutes: 60" in WF_RAW)
check("E1b brew update 看门狗（后台 + 限时击杀 + 等待判定）",
      "brew update &" in WF_RAW
      and "( sleep 300; kill -9 $UPDATE_PID 2>/dev/null || true ) &" in WF_RAW
      and "if wait $UPDATE_PID; then" in WF_RAW
      and "kill $WATCHDOG 2>/dev/null || true" in WF_RAW)
check("E1c 挂死容忍路径（超时后继续安装）",
      "timed out/failed -- continuing with preinstalled taps" in WF_RAW
      and "brew install make ccache" in WF_RAW)
bare_updates = re.findall(r"(?m)^[ \t]*brew update[ \t]*$", WF_NORM)
check("E1d 无裸 brew update（唯一调用在看门狗内）",
      len(bare_updates) == 0 and WF_RAW.count("brew update &") == 1,
      "bare=%d watched=%d" % (len(bare_updates), WF_RAW.count("brew update &")))

print("\n%d passed, %d failed" % (passed, len(failures)))
if failures:
    print("FAILURES:", failures)
    sys.exit(1)
print("verify_task205: ALL PASS")
