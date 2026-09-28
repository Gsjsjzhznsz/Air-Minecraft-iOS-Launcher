#!/usr/bin/env python3
"""Task193: 收集本轮 i18n 迁移范围的唯一中文字符串。

范围（UI chrome，用户在英文模式直接看到的）：
  - Natives/MultiplayerViewController.m
  - Natives/PLCrashView.m
  - Natives/AI/AIMessageCell.m, AIInputBarView.m, AISystemPromptEditorViewController.m
  - 其余小文件（Shader/Mod/AssetVersionVC、DownloadVC、VersionCardCell、
    VersionManagerVC、ModpackExportVC、LauncherHelpVC、LauncherPreferencesVC、
    LauncherRightPanelVC、installers）
排除：
  - localize(...) 行（已有 key）
  - NSLog/printf/注释
  - ProfileSettingsViewController 的内部中文键体系（显示已映射 localize）
  - AI 工具描述/崩溃分析内容（模型面向，下轮）
输出唯一串清单 + 每串出现计数，供翻译与迁移脚本消费。
"""
import json
import os
import re
import sys
from collections import OrderedDict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CJK = re.compile(r"[\u4e00-\u9fff]")
LITERAL = re.compile(r'@"((?:[^"\\]|\\.)*)"')
EXCLUDE = re.compile(r"NSLog|printf|LOGD|LOGE|LOGW|SHUT_LOGD|//|^\s*\*|^\s*#|fprintf|NSDebugLog|localize\s*\(")

TARGET_FILES = [
    "Natives/MultiplayerViewController.m",
    "Natives/PLCrashView.m",
    "Natives/AI/AIMessageCell.m",
    "Natives/AI/AIInputBarView.m",
    "Natives/AI/AISystemPromptEditorViewController.m",
    "Natives/ShaderVersionViewController.m",
    "Natives/ModVersionViewController.m",
    "Natives/AssetVersionViewController.m",
    "Natives/DownloadViewController.m",
    "Natives/VersionCardCell.m",
    "Natives/VersionManagerViewController.m",
    "Natives/ModpackExportViewController.m",
    "Natives/LauncherHelpViewController.m",
    "Natives/LauncherPreferencesViewController.m",
    "Natives/LauncherRightPanelViewController.m",
    "Natives/ThirdPartyLoginViewController.m",
    "Natives/installer/NeoForgeDirectInstaller.m",
    "Natives/installer/ForgeDirectInstaller.m",
    "Natives/installer/ModLoaderInstallViewController.m",
]

strings = OrderedDict()   # text -> {count, files}
for rel in TARGET_FILES:
    path = os.path.join(REPO, rel)
    if not os.path.exists(path):
        continue
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except Exception:
        continue
    for i, line in enumerate(lines, 1):
        if EXCLUDE.search(line):
            continue
        for m in LITERAL.finditer(line):
            txt = m.group(1)
            if CJK.search(txt):
                ent = strings.setdefault(txt, {"count": 0, "files": set(), "lines": []})
                ent["count"] += 1
                ent["files"].add(rel)
                ent["lines"].append(f"{rel}:{i}")

out = {k: {"count": v["count"], "files": sorted(v["files"]), "lines": v["lines"]} for k, v in strings.items()}
dst = os.path.join(REPO, "scripts", "task193_i18n_strings.json")
json.dump(out, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"unique strings: {len(out)}")
for k, v in out.items():
    print(f"  [{v['count']}x {len(v['files'])}f] {k[:70]}")
