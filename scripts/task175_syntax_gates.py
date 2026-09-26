#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task175 syntax gates: state-machine bracket/paren/brace balance on every
file this task touched. Reuses the verify_task174 F-group checker (a proper
string/comment state machine -- the earlier naive stripper false-positives on
URL literals containing //)."""
import os
import sys

FILES = [
    "Natives/spvc_shim.c",
    "Natives/installer/modpack/CurseForgeAPI.m",
    "Natives/DownloadViewController.m",
    "Natives/LauncherRootViewController.m",
    "Natives/LauncherNewsViewController.m",
    "Natives/environ.h",
    "Natives/SurfaceViewController.m",
    "Natives/input_bridge_v3.m",
    "Natives/ModpackImportService.m",
    "Natives/JavaLauncher.m",
    "Natives/BackgroundManager.m",
    "Natives/UIKit+NativeSurface.m",
    "Natives/UIKit+NativeSurface.h",
]

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def balance(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    depth = {"{": 0, "(": 0, "[": 0}
    pair = {"}": "{", ")": "(", "]": "["}
    i, n, state = 0, len(src), "code"
    while i < n:
        c = src[i]
        if state == "code":
            if c == '"':
                state = "str"
            elif c == "/" and i + 1 < n and src[i + 1] == "/":
                state = "line"
                i += 1
            elif c == "/" and i + 1 < n and src[i + 1] == "*":
                state = "block"
                i += 1
            elif c in depth:
                depth[c] += 1
            elif c in pair:
                depth[pair[c]] -= 1
        elif state == "str":
            if c == "\\":
                i += 1
            elif c == '"':
                state = "code"
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                state = "code"
        i += 1
    return all(v == 0 for v in depth.values())


fails = 0
for rel in FILES:
    ok = balance(os.path.join(REPO, rel))
    print(("OK  " if ok else "FAIL"), rel)
    if not ok:
        fails += 1

print("\nRESULT:", "ALL PASS" if fails == 0 else f"{fails} FILE(S) FAILED")
sys.exit(1 if fails else 0)
