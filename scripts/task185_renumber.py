#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 185 改号脚本：把本地 Task184 轮全部标识改号为 185（家法让位——
远程已由并行会话占用 Task 184 = UI 回退 + 安装页重写轮）。
仅处理【我方】改动文件；远程侧 AME184ClearTableViewCellChrome 尚未进入
本地树（变基后才进来），此时改名是安全的。
"""
import re
from pathlib import Path

ROOT = Path("/home/z/my-project/Amethyst-iOS-MyRemastered")

# 我方本轮全部落盘文件（源码 + 脚本 + 文档）
FILES = [
    "Natives/utils.h",
    "Natives/utils.m",
    "Natives/installer/NeoForgeVersionFetcher.m",
    "Natives/installer/ModLoaderInstallViewController.m",
    "Natives/installer/ForgeInstallViewController.m",
    "Natives/LauncherRightPanelViewController.m",
    "Natives/LauncherNavigationController.m",
    "Natives/authenticator/MicrosoftAuthenticator.m",
    "Natives/AvatarManager.h",
    "Natives/AvatarManager.m",
    "Natives/LauncherNewsViewController.m",
    "Natives/external/MobileGlues/MobileGlues-cpp/version.h",
    "scripts/verify_task169.py",
    "scripts/verify_task172.py",
    "scripts/verify_task180.py",
]

# 替换规则（顺序执行；先长后短防误替换）
SUBS = [
    ("ame184_loaderVersionMatchesGameVersion", "ame185_loaderVersionMatchesGameVersion"),
    ("ame184_dispatchToMainSelfHealing", "ame185_dispatchToMainSelfHealing"),
    ("ame184_loaderCandidates", "ame185_loaderCandidates"),
    ("ame184_gameCandidates", "ame184_gameCandidates_PLACEHOLDER"),  # 防双段误拼
    ("ame184ShowAllSentinel", "ame185ShowAllSentinel"),
    ("ame184ShowAllRow", "ame185ShowAllRow"),
    ("ame184_fetchForgeFallbackJSON", "ame185_fetchForgeFallbackJSON"),
    ("ame184_openJITEnablerURL", "ame185_openJITEnablerURL"),
    ("ame184_fetchAvatarForAuthData", "ame185_fetchAvatarForAuthData"),
    ("ame184_numericHead", "ame185_numericHead"),
    ("__AME184_SHOW_ALL__", "__AME185_SHOW_ALL__"),
    ("AME184_SHOW_ALL", "AME185_SHOW_ALL"),
    ("Task184-matcher", "Task185-matcher"),
    ("task184_matcher_test", "task185_matcher_test"),
    ("verify_task184", "verify_task185"),
    ("Task 184", "Task 185"),
    ("Task184", "Task185"),
    ("task184", "task185"),
    ("ame184", "ame185"),
    ("AME184", "AME185"),
    ("ame184_gameCandidates_PLACEHOLDER", "ame185_gameCandidates"),  # 还原
]

total = {}
for rel in FILES:
    p = ROOT / rel
    if not p.exists():
        print(f"SKIP (missing) {rel}")
        continue
    text = p.read_text(encoding="utf-8", errors="replace")
    orig = text
    for a, b in SUBS:
        text = text.replace(a, b)
    if text != orig:
        p.write_text(text, encoding="utf-8")
        n = sum(orig.count(a) for a, _ in SUBS[:len(SUBS)-1])
        total[rel] = n
        print(f"OK   {rel}")
    else:
        print(f"---- {rel} (no change)")

# 脚本改名
renames = [
    ("scripts/verify_task184.py", "scripts/verify_task185.py"),
    ("scripts/task184_matcher_test.py", "scripts/task185_matcher_test.py"),
]
for src, dst in renames:
    s, d = ROOT / src, ROOT / dst
    if s.exists():
        s.rename(d)
        print(f"RENAME {src} -> {dst}")

print("\nDone. Files changed:", len(total))
