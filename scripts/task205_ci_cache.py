#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task205：CI 缓存编辑器（保 CRLF 行尾）。

对 .github/workflows/development.yml 做三处修改：
  1. ccache + Homebrew 两路 actions/cache 步骤（Select Xcode 之后）
  2. brew install make -> make ccache
  3. 构建步骤接线 CC/CXX=ccache + 结束时打印 ccache 统计
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

# ---- 1. 缓存步骤（锚：Install GNU Make 步骤名前插入）----
cache_block = nl.join([
    "      # Task205：CI 构建缓存（用户需求——加速 CI 出包）。",
    "      #   (1) ccache —— MobileGlues（glslang+SPIRV-Cross+MG 本体，实测 3.4 分钟",
    "      #       = 全构建最大单项）与 Natives cmake 侧（vgpu/tinygl4angle/垫片）",
    "      #       的 C/C++ 重编全量命中；键含 Makefile/CMakeLists hash，改构建",
    "      #       脚本自动失效，restore-keys 前缀命中保证小改动仍部分复用。",
    "      #   (2) Homebrew 下载缓存 —— make/temurin8/ldid 的 bottle 下载。",
    "      # 仓库级缓存配额 10GB：ccache 限 2G + brew 约 1G，余量充足；",
    "      # 发布产物走 artifact/release 不占 cache。",
    "      - name: Cache ccache compilation cache",
    "        uses: actions/cache@v4",
    "        with:",
    "          path: ~/.ccache",
    "          key: ccache-macos14-v1-${{ hashFiles('Makefile', 'Natives/CMakeLists.txt') }}",
    "          restore-keys: |",
    "            ccache-macos14-v1-",
    "",
    "      - name: Cache Homebrew downloads",
    "        uses: actions/cache@v4",
    "        with:",
    "          path: ~/Library/Caches/Homebrew/downloads",
    "          key: brew-macos14-v1-${{ hashFiles('.github/workflows/development.yml') }}",
    "          restore-keys: |",
    "            brew-macos14-v1-",
    "",
])
anchor1 = "      - name: Install GNU Make"
if "Cache ccache compilation cache" not in text:
    if anchor1 not in text:
        sys.exit("anchor1 (Install GNU Make) not found")
    text = text.replace(anchor1, cache_block + anchor1, 1)
    applied.append("cache-steps")

# ---- 2. brew install make -> make ccache ----
old2 = "          brew install make"
new2 = "          brew install make ccache"
if old2 in text and new2 not in text:
    text = text.replace(old2, new2, 1)
    applied.append("brew-ccache")

# ---- 3. 构建步骤 ccache 接线 ----
old3 = nl.join([
    "          set -o pipefail",
    "          export PATH=/opt/homebrew/bin:$PATH",
    "          export SLIMMED=0",
    "          export BUILD_MOBILEGL=\"${BUILD_MOBILEGL:-0}\"",
])
new3 = nl.join([
    "          set -o pipefail",
    "          export PATH=/opt/homebrew/bin:$PATH",
    "          export SLIMMED=0",
    "          export BUILD_MOBILEGL=\"${BUILD_MOBILEGL:-0}\"",
    "          # Task205：ccache 接线（仅影响 cmake 侧 C/C++ 编译；javac 不受",
    "          # 影响）。首次运行冷缓存无加速，第二次起 MobileGlues+vgpu 的重编",
    "          # 全部命中，预计省 3-4 分钟/次。",
    "          export CCACHE_DIR=\"$HOME/.ccache\"",
    "          ccache --set-config=max_size=2G || true",
    "          export CC=\"ccache clang\"",
    "          export CXX=\"ccache clang++\"",
    "          ccache --zero-stats 2>/dev/null || true",
])
if old3 in text and "CCACHE_DIR=\"$HOME/.ccache\"" not in text:
    text = text.replace(old3, new3, 1)
    applied.append("ccache-wiring")

# ---- 4. 结束时统计 ----
old4 = nl.join([
    "            gmake -j$(sysctl -n hw.ncpu) dsym package PLATFORM=${{ matrix.platform }} 2>&1 | tee build_output.log",
    "          fi",
])
new4 = nl.join([
    "            gmake -j$(sysctl -n hw.ncpu) dsym package PLATFORM=${{ matrix.platform }} 2>&1 | tee build_output.log",
    "          fi",
    "          echo '== Task205 ccache stats ==' 2>/dev/null || true",
    "          ccache --show-stats 2>/dev/null || true",
])
if old4 in text and "ccache --show-stats" not in text:
    text = text.replace(old4, new4, 1)
    applied.append("ccache-stats")

with open(PATH, "wb") as f:
    f.write(text.encode("utf-8"))

print("applied: %s (crlf=%s)" % (applied or ["<none, already applied>"], crlf))
if not applied and "Cache ccache compilation cache" not in text:
    sys.exit("no edits applied and cache steps missing -- investigate")
