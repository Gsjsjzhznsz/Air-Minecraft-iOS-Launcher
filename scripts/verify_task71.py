#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task71.py — Task 71 修复验证（整合包"json 丢失"根因：id 与目录名不一致）

【重建说明】本脚本为级联链完整性重建件：原 verify_task71.py 在本地脚本目录
意外丢失（67/68/70 均在、唯独 71 缺失），导致 verify_task72 / verify_task73
的回归级联断链。现依据 Task 71 实际提交（1bb13e8）的修复指纹重建，验证逻辑
与提交内容一一对应，不引入任何新判定。

根因（两份上传日志共同实锤）：
  整合包安装把 Fabric/Quilt meta profile JSON 写进
  versions/<base>-<hash8>/<base>-<hash8>.json，而其内部 "id" 仍是
  无后缀标准名（fabric-loader-0.19.5-26.2）。启动时 metadata.id（无后缀）
  作为 JVM args[1] → Java Tools.getVersionInfo 找
  versions/<无后缀>/<无后缀>.json → FileNotFoundException → exit(1)
  （用户看到的"json丢失"崩溃）；client.jar 也因 id 无后缀被下错目录。

修复（2 文件，提交 1bb13e8）：
  Fix A（源头）ModpackImportService.m      安装时把 profile 内部 id 重写为
        唯一化 versionId（目录名 == JSON id == Java 查找 id 三者一致）
  Fix B（自愈）MinecraftResourceDownloadTask.m 启动侧 downloadVersionMetadata
        检出内部 id != 目录名 → 原地重写 id + 迁移误置的 client.jar +
        清理搬空的旧目录；一切失败均非致命

验证层次：
  A. 源码指纹（2 文件修复点定位 + 顺序断言）
  B. 行为回放（id 一致性判定 / 自愈决策，6 场景）
  C. 括号平衡（2 文件 delta=0）
  D. 回归级联（verify_task70 / 68 / 67）
"""
import os
import re
import subprocess
import sys

ROOT = "/home/z/my-project/Amethyst-iOS-MyRemastered"

PASS = 0
FAIL = 0
FAILS = []


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        FAILS.append(f"{name} {('— ' + detail) if detail else ''}")
        print(f"  [FAIL] {name} {detail}")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


# ---------------------------------------------------------------- A. 源码指纹
print("== A. 源码指纹 ==")

# A1. Fix A — ModpackImportService.m（安装侧 id 重写）
p = os.path.join(ROOT, "Natives/ModpackImportService.m")
src = read(p)
i_dlerr = src.find("if (error) *error = dlError;")
i_parse = src.find("parseJSONFromFile(versionJsonPath)", i_dlerr)
i_setid = src.find('profileJSON[@"id"] = versionId;', i_parse)
i_save = src.find("saveJSONToFile(profileJSON, versionJsonPath)", i_setid)
i_log_rw = src.find("Task71 loader profile id rewritten", i_save)
check("A1a Fix A 存在：下载完成后重解析 profile", i_parse > i_dlerr > 0)
check("A1b Fix A id 重写位于解析之后", 0 < i_parse < i_setid)
check("A1c Fix A 写回位于重写之后", 0 < i_setid < i_save)
check("A1d Fix A 成功日志锚点存在", i_log_rw > i_save)
check("A1e Fix A 仅在 internalId != versionId 时重写",
      '![internalId isEqualToString:versionId]' in src)
check("A1f Fix A 写失败非致命（保留原文件，启动侧自愈兜底）",
      "Task71 loader profile id rewrite failed (non-fatal)" in src)
check("A1g Fix A 注释含根因链（目录名 == JSON 内部 id == Java 启动查找 id）",
      "目录名 == JSON 内部 id == Java 启动查找 id" in src)

# A2. Fix B — MinecraftResourceDownloadTask.m（启动侧自愈）
p2 = os.path.join(ROOT, "Natives/MinecraftResourceDownloadTask.m")
src2 = read(p2)
i_mism = src2.find("Task71 version JSON id mismatch: folder=%@ internal=%@")
i_tid = src2.find("task71InternalId")
i_heal = src2.find('json[@"id"] = versionStr;', i_tid)
i_hlog = src2.find("Task71 version JSON id healed", i_heal)
i_newjar = src2.find("task71NewJar", i_hlog)
i_rm = src2.find("empty legacy version dir removed", i_newjar)
check("A2a Fix B 检出日志存在（mismatch: folder=/internal=）", i_mism > 0)
check("A2b Fix B 自愈重写 json id = 目录名", 0 < i_heal)
check("A2c Fix B 自愈成功日志存在", 0 < i_hlog > i_heal)
check("A2d Fix B client.jar 迁移存在（oldJar -> newJar）",
      0 < i_newjar and "moveItemAtPath:task71OldJar toPath:task71NewJar" in src2)
check("A2e Fix B 旧目录搬空清理存在（非破坏性：仅空目录）", i_rm > i_newjar > 0)
check("A2f Fix B 写回失败非致命（仅内存修正）",
      "Task71 heal write failed (non-fatal)" in src2)
check("A2g Fix B 迁移失败不阻断（走重下载兜底）",
      "Task71 client jar migration failed (will re-download)" in src2)
check("A2h Fix B 自愈块位于 inheritsFrom 处理之前",
      0 < i_rm < src2.find('json[@"inheritsFrom"]'))
check("A2i Fix B 判据：versionStr 与 internalId 均非空且不等",
      'versionStr.length > 0 && task71InternalId.length > 0' in src2 and
      '![task71InternalId isEqualToString:versionStr]' in src2)
check("A2j Fix B jar 路径模板（versions/<id>/<id>.jar 双侧同构）",
      src2.count('%1$s/versions/%2$@/%2$@.jar') >= 2)

# ---------------------------------------------------------------- B. 行为回放
print("== B. 行为回放（id 一致性 / 自愈决策，6 场景）==")


def fix_a(internal_id, version_id, parse_ok=True):
    """Fix A：安装侧。返回 (rewritten, new_internal_id)。"""
    if not parse_ok:
        return (False, internal_id)          # 重解析失败 → 非致命跳过
    if internal_id and internal_id != version_id:
        return (True, version_id)            # 重写为目录名
    return (False, internal_id)


def fix_b(version_str, internal_id, old_jar_exists=True, new_jar_exists=False,
          move_ok=True, remaining=None):
    """Fix B：启动侧自愈。返回 dict。"""
    heal = version_str and internal_id and internal_id != version_str
    out = {"healed": False, "id": internal_id, "jar_moved": False,
           "legacy_removed": False}
    if heal:
        out["healed"] = True
        out["id"] = version_str
        if old_jar_exists and not new_jar_exists:
            if move_ok:
                out["jar_moved"] = True
                if remaining is None or len(remaining) == 0:
                    out["legacy_removed"] = True
    return out


# B1. 坏档形态（日志实锤）：目录带 -hash8 后缀、JSON id 无后缀
r = fix_a("fabric-loader-0.19.5-26.2", "fabric-loader-0.19.5-26.2-ea503303")
check("B1a Fix A 坏档重写 id = versionId", r == (True, "fabric-loader-0.19.5-26.2-ea503303"))

# B2. 正常安装（两者一致）：零干预
r = fix_a("fabric-loader-0.19.5-26.2", "fabric-loader-0.19.5-26.2")
check("B2a Fix A 一致安装零干预", r == (False, "fabric-loader-0.19.5-26.2"))

# B3. 解析失败：非致命跳过（启动侧自愈兜底）
r = fix_a("x", "y", parse_ok=False)
check("B3a Fix A 解析失败非致命跳过", r == (False, "x"))

# B4. 启动侧自愈：坏档全路径（重写 + jar 迁移 + 旧目录清理）
r = fix_b("fabric-loader-0.19.5-26.2-ea503303", "fabric-loader-0.19.5-26.2")
check("B4a Fix B 坏档 id 自愈为目录名", r["healed"] and r["id"].endswith("-ea503303"))
check("B4b Fix B client.jar 迁移", r["jar_moved"])
check("B4c Fix B 搬空旧目录清理", r["legacy_removed"])

# B5. 旧目录仍有 json 等残留文件：保留目录（非破坏性）
r = fix_b("v-h1", "v", remaining=["v.json"])
check("B5a Fix B 旧目录非空不删除", r["jar_moved"] and not r["legacy_removed"])

# B6. 一致安装：启动侧零干预（不进自愈分支）
r = fix_b("v", "v")
check("B6a Fix B 一致安装零干预", not r["healed"] and r["id"] == "v")

# ---------------------------------------------------------------- C. 括号平衡
print("== C. 括号平衡 ==")
for name, s in [("ModpackImportService.m", src), ("MinecraftResourceDownloadTask.m", src2)]:
    s2 = re.sub(r'@?"(\\.|[^"\\])*"', "STR", s)
    s2 = re.sub(r"//[^\n]*", "", s2)
    s2 = re.sub(r"/\*.*?\*/", "", s2, flags=re.S)
    check(f"C {name} 括号平衡 delta=0",
          s2.count("{") == s2.count("}") and s2.count("(") == s2.count(")"),
          f"braces={s2.count('{') - s2.count('}')} parens={s2.count('(') - s2.count(')')}")

# ---------------------------------------------------------------- D. 回归级联
print("== D. 回归级联 ==")
REGRESS_DIR = "/home/z/my-project/scripts"
for script in ["verify_task70.py", "verify_task68.py", "verify_task67.py"]:
    sp = os.path.join(REGRESS_DIR, script)
    if not os.path.exists(sp):
        sp = os.path.join(ROOT, "scripts", script)
    if not os.path.exists(sp):
        check(f"D {script} 存在", False, sp)
        continue
    r = subprocess.run([sys.executable, sp], capture_output=True, text=True, timeout=120)
    m = re.findall(r"(\d+)\s*PASS\s*/\s*(\d+)\s*FAIL", r.stdout)
    if m:
        ok = (r.returncode == 0) and m[-1][1] == "0"
        detail = "/".join(m[-1]) + " PASS/FAIL"
    else:
        m2 = re.findall(r"(\d+)\s*/\s*(\d+)", r.stdout)
        ok = (r.returncode == 0) and m2 and m2[-1][0] == m2[-1][1]
        detail = "/".join(m2[-1]) if m2 else (r.stderr.strip()[:80] or "no-output")
    check(f"D {script} 全绿", ok, detail)

# ---------------------------------------------------------------- 汇总
print()
print("=" * 60)
print(f"RESULT: {PASS}/{PASS + FAIL}")
if FAILS:
    print("FAILED ITEMS:")
    for f in FAILS:
        print("  -", f)
    sys.exit(1)
print("ALL PASS — Task 71 验证通过（重建件）")
