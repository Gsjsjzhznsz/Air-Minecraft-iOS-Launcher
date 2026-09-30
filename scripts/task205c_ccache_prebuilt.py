#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task205c：ccache 移出 brew + 撤销看门狗（保 CRLF 行尾）。

证据链（三份装机日志定谳）：
  - run 36722042665（原始 70 分钟）：brew update 33 秒正常完成；卡点是
    brew install ccache 触发 LLVM/Clang 源码编译（依赖树 llvm@22/rust/
    ruby/gcc 均无 arm64_sonoma bottle）——"网络挂死"为误诊，cmake --build
    近零输出酷似挂死。
  - run 36735179980 attempt 1：同链路，openssl@3 3.6.5 源码编译 3m33s 后
    brew link 撞镜像内 openssl@1.1 符号冲突，llvm@22 cmake --build 被取消。
  - run 36735179980 attempt 2：Task205b 看门狗击杀在途 brew update -> tap
    半更新毒化 -> ChecksumMismatchError: SHA-256 mismatch。看门狗 RETRACTED。

终案：
  1. brew install 只装 make（ccache 移出）
  2. ccache 用官方预编译 darwin 通用包（x86_64+arm64，仅链系统库），
     解包进 ~/.local/ccache-tool，本体进 actions/cache（键含版本）
  3. brew update 容错（|| true）；挂死类极端交 timeout-minutes=60 兜底
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

# ---- 1. job 级注释块更新（看门狗描述撤销）----
old1 = nl.join([
    "    # Task205b：brew 挂死免疫 + 全局限时（run 36722042665 教训：",
    "    # macos-14 runner 上 brew 步骤网络挂死 70 分钟无输出，只能手动取消）。",
    "    #   (1) job 级禁用 brew auto-update——runner 镜像自带较新 tap，且",
    "    #       bottle 下载走 Homebrew downloads 缓存；显式 update 只保留",
    "    #       Install GNU Make 里带看门狗的一次。",
    "    #   (2) timeout-minutes=60：健康 run 稳定 8-13 分钟（近 10 次实测），",
    "    #       BUILD_MOBILEGL=1 场景约 30-45 分钟，60 分钟全覆盖；挂死类",
    "    #       故障从\"无限等到手动取消\"变成\"限时自动失败可重跑\"。",
])
new1 = nl.join([
    "    # Task205b/c：brew 加固 + 全局限时（run 36722042665 教训）。",
    "    #   (1) job 级禁用 brew auto-update——auto-update 可在任意 brew",
    "    #       调用里复发；显式 update 只在 Install GNU Make 容错跑一次",
    "    #       （Task205c 撤销看门狗：击杀在途 update 会毒化 tap）。",
    "    #   (2) timeout-minutes=60：健康 run 稳定 8-13 分钟（近 10 次实测），",
    "    #       BUILD_MOBILEGL=1 场景约 30-45 分钟，60 分钟全覆盖；任何",
    "    #       挂死类故障从\"无限等到手动取消\"变成\"限时自动失败可重跑\"。",
])
if "Task205b：brew 挂死免疫" in text:
    if old1 not in text:
        sys.exit("anchor1 (job comment block) not found")
    text = text.replace(old1, new1, 1)
    applied.append("job-comment")

# ---- 2. Install GNU Make 整步替换 + ccache 工具缓存/安装步骤 ----
old2 = nl.join([
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
new2 = nl.join([
    "      - name: Cache ccache tool itself",
    "        # Task205c：ccache 本体也进缓存（官方预编译 darwin 包 ~2MB，",
    "        # x86_64+arm64 通用二进制）。键含版本号：升版本自动失效重取。",
    "        uses: actions/cache@v4",
    "        with:",
    "          path: ~/.local/ccache-tool",
    "          key: ccache-tool-macos14-v1-4.14.1",
    "",
    "      - name: Install GNU Make",
    "        # Task205c（撤销 Task205b 看门狗，RETRACTED）：三份日志定谳——",
    "        # 原始 70 分钟\"网络挂死\"实为 brew install ccache 触发 LLVM/Clang",
    "        # 源码编译（cmake --build 近零输出酷似挂死）；brew update 本体",
    "        # 三次实测 30-33 秒。看门狗击杀在途 update 反而毒化 tap",
    "        # （36735179980 attempt 2：ChecksumMismatchError）。现方案：",
    "        # update 容错（快速失败继续用镜像 tap），挂死类极端情况交给",
    "        # job 级 timeout-minutes=60 兜底。",
    "        run: |",
    "          brew update || true",
    "          brew install make",
    "",
    "      - name: Install ccache (upstream prebuilt, brew-free)",
    "        # Task205c：ccache 移出 brew。brew 的 ccache 在 macos-14 上解析",
    "        # 出 llvm@22/rust/ruby/gcc 依赖树：llvm@22 无 arm64_sonoma",
    "        # bottle -> 源码编译 LLVM+Clang（1-2 小时级，即 36722042665",
    "        # 的 70 分钟\"挂死\"真身）；openssl@3 3.6.5 同样源码编译且",
    "        # brew link 撞镜像内 openssl@1.1 符号冲突。官方 release 的",
    "        # darwin 包仅链系统库（libSystem/libc++）——解包即用 ~5 秒。",
    "        env:",
    "          CCACHE_TOOL_VERSION: \"4.14.1\"",
    "        run: |",
    "          set -e",
    "          PREFIX=\"$HOME/.local/ccache-tool\"",
    "          mkdir -p \"$PREFIX/bin\"",
    "          if [ -x \"$PREFIX/bin/ccache\" ] && \"$PREFIX/bin/ccache\" --version 2>/dev/null | head -1 | grep -q \"$CCACHE_TOOL_VERSION\"; then",
    "            echo \"[ccache-tool] cache hit: $(\"$PREFIX/bin/ccache\" --version | head -1)\"",
    "          else",
    "            echo \"[ccache-tool] fetching upstream prebuilt (brew dependency tree avoided)\"",
    "            curl -fsSL \"https://github.com/ccache/ccache/releases/download/v${CCACHE_TOOL_VERSION}/ccache-${CCACHE_TOOL_VERSION}-darwin.tar.gz\" -o /tmp/ccache-darwin.tar.gz",
    "            tar -xzf /tmp/ccache-darwin.tar.gz -C /tmp",
    "            cp \"/tmp/ccache-${CCACHE_TOOL_VERSION}-darwin/ccache\" \"$PREFIX/bin/ccache\"",
    "            chmod +x \"$PREFIX/bin/ccache\"",
    "            \"$PREFIX/bin/ccache\" --version | head -1",
    "          fi",
    "          echo \"$PREFIX/bin\" >> \"$GITHUB_PATH\"",
])
if "Cache ccache tool itself" not in text:
    if old2 not in text:
        sys.exit("anchor2 (Install GNU Make watchdog step) not found")
    text = text.replace(old2, new2, 1)
    applied.append("make-step-and-ccache-tool")

# ---- 3. 构建步骤 PATH 前置 ccache-tool（防任何同名遮蔽）----
old3 = "          export PATH=/opt/homebrew/bin:$PATH"
new3 = "          export PATH=\"$HOME/.local/ccache-tool/bin:/opt/homebrew/bin:$PATH\""
if old3 in text and new3 not in text:
    text = text.replace(old3, new3, 1)
    applied.append("build-path")

with open(PATH, "wb") as f:
    f.write(text.encode("utf-8"))

print("applied: %s (crlf=%s)" % (applied or ["<none, already applied>"], crlf))
if not applied and "Cache ccache tool itself" not in text:
    sys.exit("no edits applied and ccache tool steps missing -- investigate")
