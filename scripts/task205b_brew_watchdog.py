#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task205b：brew 挂死免疫编辑器（保 CRLF 行尾）。

事故背景（run 36722042665，caf4591 首跑）：Install GNU Make 步骤的
brew update 在 macos-14 runner 上 tap git fetch 网络挂死，70 分钟无输出
被迫手动取消。macos-14 的 brew update 慢/挂是 runner 侧已知顽疾。

对 .github/workflows/development.yml 做两处修改：
  1. job 级 env（HOMEBREW_NO_AUTO_UPDATE / NO_INSTALL_CLEANUP）
     + timeout-minutes: 60（健康 run 稳定 8-13 分钟；BUILD_MOBILEGL=1
     场景约 30-45 分钟，60 = 全场景安全上限）
  2. Install GNU Make 里的 brew update 换成 5 分钟看门狗模式：
     后台跑，超时击杀并继续（失败模式从"挂死 1 小时"退化成
     "沿用镜像自带 tap 继续"）。
幂等：已应用过则跳过。
"""
import sys

PATH = ".github/workflows/development.yml"

with open(PATH, "rb") as f:
    raw = f.read()
text = raw.decode("utf-8")
crlf = "\r\n" in text
nl = "\r\n" if crlf else "\n"

applied = []

# ---- 1. job 级 env + timeout（锚：permissions 块与 steps 之间插入）----
old1 = nl.join([
    "    # 发布 nightly release 需要 contents: write",
    "    permissions:",
    "      contents: write",
    "",
    "    steps:",
])
new1 = nl.join([
    "    # 发布 nightly release 需要 contents: write",
    "    permissions:",
    "      contents: write",
    "",
    "    # Task205b：brew 挂死免疫 + 全局限时（run 36722042665 教训：",
    "    # macos-14 runner 上 brew 步骤网络挂死 70 分钟无输出，只能手动取消）。",
    "    #   (1) job 级禁用 brew auto-update——runner 镜像自带较新 tap，且",
    "    #       bottle 下载走 Homebrew downloads 缓存；显式 update 只保留",
    "    #       Install GNU Make 里带看门狗的一次。",
    "    #   (2) timeout-minutes=60：健康 run 稳定 8-13 分钟（近 10 次实测），",
    "    #       BUILD_MOBILEGL=1 场景约 30-45 分钟，60 分钟全覆盖；挂死类",
    "    #       故障从\"无限等到手动取消\"变成\"限时自动失败可重跑\"。",
    "    env:",
    "      HOMEBREW_NO_AUTO_UPDATE: \"1\"",
    "      HOMEBREW_NO_INSTALL_CLEANUP: \"1\"",
    "    timeout-minutes: 60",
    "",
    "    steps:",
])
if 'HOMEBREW_NO_AUTO_UPDATE: "1"' not in text:
    if old1 not in text:
        sys.exit("anchor1 (permissions/steps) not found")
    text = text.replace(old1, new1, 1)
    applied.append("job-env-timeout")

# ---- 2. brew update 看门狗（锚：Install GNU Make 步骤体整体替换）----
old2 = nl.join([
    "      - name: Install GNU Make",
    "        run: |",
    "          brew update",
    "          brew install make ccache",
])
new2 = nl.join([
    "      - name: Install GNU Make",
    "        # Task205b：brew update 看门狗（run 36722042665：tap git fetch",
    "        # 挂死 70 分钟）。后台跑 brew update，5 分钟未完成即击杀放弃——",
    "        # 失败模式从\"挂死 1 小时\"退化成\"沿用镜像自带 tap 继续\"（runner",
    "        # 镜像 tap 较新，bottle 404 概率低，且下载有 Homebrew downloads",
    "        # 缓存兜底）。auto-update 已被 job 级 env 全局禁用，本步骤是全",
    "        # workflow 唯一显式 update 点。kill -9 后遗留的孤儿 git 进程对",
    "        # 后续 brew install 无害（install 不再触碰 tap 的 git 元数据）。",
    "        run: |",
    "          brew update &",
    "          UPDATE_PID=$!",
    "          ( sleep 300; kill -9 $UPDATE_PID 2>/dev/null || true ) &",
    "          WATCHDOG=$!",
    "          if wait $UPDATE_PID; then",
    "            echo \"[brew] tap update ok\"",
    "          else",
    "            echo \"[brew] tap update timed out/failed -- continuing with preinstalled taps\"",
    "          fi",
    "          kill $WATCHDOG 2>/dev/null || true",
    "          brew install make ccache",
])
if "brew update &" not in text:
    if old2 not in text:
        sys.exit("anchor2 (Install GNU Make step body) not found")
    text = text.replace(old2, new2, 1)
    applied.append("brew-watchdog")

with open(PATH, "wb") as f:
    f.write(text.encode("utf-8"))

print("applied: %s (crlf=%s)" % (applied or ["<none, already applied>"], crlf))
if not applied and "brew update &" not in text:
    sys.exit("no edits applied and watchdog missing -- investigate")
