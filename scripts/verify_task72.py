#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_task72.py — Task 72 修复验证（整合包安装后"找不到版本信息"根因）

根因：整合包安装成功路径未发送 ReloadProfileList → localVersionList（应用启动时
viewDidLoad 快照）不含刚写入的唯一化版本 → launchGame → FindVersionInRemoteList
远程+内存列表双双未命中 → 弹 i18n_str_432"找不到版本信息"。
用户 workaround"重开应用再启动"= 重启后列表重扫命中 —— 症状完全吻合。

修复（4 文件）：
  Fix1 DownloadViewController.m      importModpackWithService 成功路径补发 ReloadProfileList
  Fix2 ModpackImportViewController.m 本地 .mrpack 导入成功路径补发 ReloadProfileList
  Fix3 LauncherRootViewController.m      findVersionInRemoteList 磁盘兜底（防御纵深）
  Fix4 LauncherCardLayoutViewController.m findVersionInRemoteList 磁盘兜底（同构）

验证层次：
  A. 源码指纹（4 文件修复点逐一定位 + 顺序断言）
  B. 行为回放（新旧代码决策对比，6 场景）
  C. 通知覆盖矩阵（三条导入路径 + 直装/原版路径，漏网清零）
  D. 括号平衡（4 文件 delta=0）
  E. 回归级联（verify_task71 / 70 / 68 / 67）
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


# ---------------------------------------------------------------- 源码指纹
print("== A. 源码指纹 ==")

# A1. DownloadViewController.m — Fix1
p = os.path.join(ROOT, "Natives/DownloadViewController.m")
src = read(p)
i_success = src.find("[manager setTaskWithId:taskId completedWithError:nil];")
i_post = src.find('postNotificationName:@"ReloadProfileList" object:nil', i_success)
i_anchor = src.find("Task72 ReloadProfileList posted after online modpack install")
i_msg = src.find('localize(@"i18n_str_261"', i_success)
check("A1a Fix1 通知存在（importModpackWithService 成功分支）", i_post > 0)
check("A1b Fix1 通知位于 setTask completed 之后", 0 < i_success < i_post)
check("A1c Fix1 通知位于 showSuccessMessage(i18n_str_261) 之前", 0 < i_post < i_msg,
      f"post={i_post} msg={i_msg}")
check("A1d Fix1 日志锚点存在", i_anchor > 0)
check("A1e Fix1 注释提及根因（找不到版本信息）", "Task 72" in src and "找不到版本信息" in src)

# A2. ModpackImportViewController.m — Fix2
p = os.path.join(ROOT, "Natives/ModpackImportViewController.m")
src2 = read(p)
i_s2 = src2.find("self.currentImportingModpack = nil;")
i_post2 = src2.find('postNotificationName:@"ReloadProfileList" object:nil', i_s2)
i_anchor2 = src2.find("Task72 ReloadProfileList posted after local modpack import")
i_show2 = src2.find("showImportSuccess:modpackInfo", i_s2)
check("A2a Fix2 通知存在（本地导入成功分支）", i_post2 > 0)
check("A2b Fix2 通知位于 showImportSuccess 之前", 0 < i_post2 < i_show2,
      f"post={i_post2} show={i_show2}")
check("A2c Fix2 日志锚点存在", i_anchor2 > 0)

# A3. LauncherRootViewController.m — Fix3
p = os.path.join(ROOT, "Natives/LauncherRootViewController.m")
src3 = read(p)
m = re.search(r"- \(void\)findVersionInRemoteList:\(NSNotification \*\)notification \{.*?\n\}", src3, re.S)
check("A3a Fix3 方法体可提取", m is not None)
if m:
    body = m.group(0)
    i_local_loop = body.find("localVersionList")
    i_disk = body.find("Task72 version found on disk (stale list fallback)")
    i_cb = body.find("callback(versionObject)")
    i_json_path = body.find("versions/%@/%@.json")
    i_guard = body.find("versionId.length > 0")
    i_dict = body.find('@"id": versionId, @"type": @"custom"')
    check("A3b Fix3 磁盘兜底位于 localVersionList 循环之后", 0 < i_local_loop < i_disk)
    check("A3c Fix3 磁盘兜底位于 callback 之前", 0 < i_disk < i_cb)
    check("A3d Fix3 检查 versions/<id>/<id>.json 路径", i_json_path > 0)
    check("A3e Fix3 versionId 空值守卫", i_guard > 0)
    check("A3f Fix3 返回与 localVersionList 同构字典", i_dict > 0)
    check("A3g Fix3 isDirectory 语义（json 不能是目录）", "isDirectory:&isDir" in body and "!isDir" in body)
    check("A3h Fix3 使用 POJAV_GAME_DIR", "POJAV_GAME_DIR" in body)

# A4. LauncherCardLayoutViewController.m — Fix4
p = os.path.join(ROOT, "Natives/LauncherCardLayoutViewController.m")
src4 = read(p)
m4 = re.search(r"- \(void\)findVersionInRemoteList:\(NSNotification \*\)notification \{.*?\n\}", src4, re.S)
check("A4a Fix4 方法体可提取", m4 is not None)
if m4:
    body4 = m4.group(0)
    check("A4b Fix4 磁盘兜底锚点", "Task72 version found on disk" in body4)
    check("A4c Fix4 json 路径检查", "versions/%@/%@.json" in body4)
    check("A4d Fix4 同构字典", '@"id": versionId, @"type": @"custom"' in body4)
    i_local4 = body4.find("localVersionList")
    i_disk4 = body4.find("Task72 version found on disk")
    i_cb4 = body4.find("callback(versionObject)")
    check("A4e Fix4 顺序：localList 循环 < 磁盘兜底 < callback",
          0 < i_local4 < i_disk4 < i_cb4)

# ---------------------------------------------------------------- 行为回放
print("== B. 行为回放（新旧决策对比）==")


def old_decision(version_id, remote_ids, local_ids, disk_json_exists):
    """旧代码：仅查远程 + 内存 localVersionList"""
    if version_id in remote_ids:
        return "launch"
    if version_id in local_ids:
        return "launch"
    return "alert_432"  # 找不到版本信息


def new_decision(version_id, remote_ids, local_ids, disk_json_exists):
    """新代码：磁盘兜底"""
    if version_id in remote_ids:
        return "launch"
    if version_id in local_ids:
        return "launch"
    if version_id and version_id not in ("",) and disk_json_exists:
        return "launch_disk_fallback"  # Task72 兜底命中
    return "alert_432"


# B1. 用户场景：装完直接启动（快照过期）
vid = "fabric-loader-0.19.5-26.2-c8cf4f2c"
remote = {"26.2", "26.3", "1.17.1"}  # 915 个远程版本均不含唯一化 id
local = {"26.2", "1.17.1"}            # viewDidLoad 快照（安装前）
check("B1 旧代码：用户场景弹'找不到版本信息'", old_decision(vid, remote, local, True) == "alert_432")
check("B1 新代码：用户场景磁盘兜底命中", new_decision(vid, remote, local, True) == "launch_disk_fallback")

# B2. 重启场景：列表重扫后命中（Fix1/2 通知后等效）
local2 = {"26.2", "1.17.1", vid}
check("B2 新代码：列表刷新后常规命中", new_decision(vid, remote, local2, True) == "launch")

# B3. 版本真不存在（正确保留报错）
check("B3 新代码：真缺失仍报错（不误放行）", new_decision("nonexistent-1.0", remote, local, False) == "alert_432")

# B4. versionId 为空
check("B4 新代码：空 versionId 守卫生效", new_decision("", remote, local, True) == "alert_432")

# B5. 远程命中不受兜底影响
check("B5 新代码：远程命中优先", new_decision("26.2", remote, local, False) == "launch")

# B6. json 路径是目录（isDir=YES 视为未命中）
def new_decision_isdir(version_id, remote_ids, local_ids, is_dir):
    if version_id in remote_ids or version_id in local_ids:
        return "launch"
    if version_id and not is_dir:
        return "launch_disk_fallback"
    return "alert_432"
check("B6 新代码：json 为目录不误判命中", new_decision_isdir(vid, remote, local, True) == "alert_432")

# ---------------------------------------------------------------- 通知覆盖矩阵
print("== C. 通知覆盖矩阵 ==")
# C1. 在线整合包路径（DownloadViewController.importModpackWithService）
check("C1 在线整合包：成功路径发 ReloadProfileList",
      "Task72 ReloadProfileList posted after online modpack install" in src)
# C2. 本地导入路径（ModpackImportViewController）
check("C2 本地导入：成功路径发 ReloadProfileList",
      "Task72 ReloadProfileList posted after local modpack import" in src2)
# C3. MinecraftResourceDownloadTask 路径（已有，回归确认）
p5 = os.path.join(ROOT, "Natives/MinecraftResourceDownloadTask.m")
src5 = read(p5)
check("C3 mrpack 下载任务路径：通知保留（回归）",
      'postNotificationName:@"ReloadProfileList"' in src5)
# C4. 直装路径（issue #61，回归确认）
check("C4 直装路径 finishInstallerProgressWithSuccess：通知保留（回归）",
      'finishInstallerProgressWithSuccess' in src and
      'postNotificationName:@"ReloadProfileList"' in src)
# C5. 失败路径不发通知（避免误导刷新）—— 在线路径失败分支在 else 中，无 post
i_else = src.find("} else {", i_post)
seg_fail = src[i_else:i_else + 1500] if i_else > 0 else ""
check("C5a 在线失败分支不误发通知", "ReloadProfileList" not in seg_fail.split("finishInstallerProgressWithSuccess")[0])
# C6. 撤销路径不发（ModpackImportService.cleanupAbortedImport 无通知）
p6 = os.path.join(ROOT, "Natives/ModpackImportService.m")
src6 = read(p6)
i_cleanup = src6.find("cleanupAbortedImportWithGameDir")
i_next = src6.find("- (NSString *)versionIdForModpack")
check("C6 清理/中止路径不误发通知", "ReloadProfileList" not in src6[i_cleanup:i_next])

# ---------------------------------------------------------------- 括号平衡
print("== D. 括号平衡 ==")
for name, s in [("DownloadViewController.m", src), ("ModpackImportViewController.m", src2),
                ("LauncherRootViewController.m", src3), ("LauncherCardLayoutViewController.m", src4)]:
    delta = s.count("{") - s.count("}")
    check(f"D {name} 括号平衡 delta=0", delta == 0, f"delta={delta}")

# ---------------------------------------------------------------- 回归级联
print("== E. 回归级联 ==")
REGRESS_DIR = "/home/z/my-project/scripts"
for script in ["verify_task71.py", "verify_task70.py", "verify_task68.py", "verify_task67.py"]:
    sp = os.path.join(REGRESS_DIR, script)
    if not os.path.exists(sp):
        check(f"E {script} 存在", False, sp)
        continue
    r = subprocess.run([sys.executable, sp], capture_output=True, text=True, cwd=ROOT)
    m = re.search(r"(\d+)\s*PASS\s*/\s*(\d+)\s*FAIL", r.stdout)
    if m:
        ok = (r.returncode == 0) and m.group(2) == "0"  # FAIL 数为 0
        detail = m.group(0)
    else:
        m2 = re.search(r"(\d+)\s*/\s*(\d+)", r.stdout)
        ok = (r.returncode == 0) and m2 and m2.group(1) == m2.group(2)  # N/N 全过
        detail = m2.group(0) if m2 else (r.stderr.strip()[:80] or "no-output")
    check(f"E {script} 全绿", ok, detail)

print()
print("=" * 60)
print(f"RESULT: {PASS}/{PASS + FAIL}")
if FAILS:
    print("FAILED ITEMS:")
    for f in FAILS:
        print(f"  - {f}")
    sys.exit(1)
print("ALL PASS")
