#!/bin/bash
# test_task47_e2e.sh — Task 47 端到端验证
#
# 链路：真实 Minecraft 26.3-pre-2 vanilla shader → 模拟 Mojang include
# resolver 的展开器（复刻 LWJGL 布局）→ glslangValidator 16.5.0（与设备
# glslang 同源同错误签名——本脚本第一步已在本机复现设备报错）→ SPIR-V。
#
# 步骤：
#   0. 验证未展开源码必然失败（复现 latestlog a5189d5 的设备报错）
#   1. 用 C 测试驱动（test_task47_e2e_driver.c）展开全部 vsh 夹具
#   2. glslangValidator -V（Vulkan target，模拟 impl 的调用形态）编译
#      展开后源码 → 必须 0 error
#   3. SPIR-V 魔数校验（0x07230203）
set -u
cd "$(dirname "$0")"
GLSLANG=${GLSLANG:-/tmp/bin/glslangValidator}
OUT=/tmp/task47_e2e
mkdir -p "$OUT"
FAIL=0

if [ ! -x "$GLSLANG" ]; then echo "FATAL: glslangValidator not found at $GLSLANG"; exit 1; fi

echo "== 0. 复现设备报错（未展开，必须失败）=="
if $GLSLANG -V -S vert --target-env vulkan1.2 task47_fixtures/terrain.vsh -o /dev/null >/dev/null 2>&1; then
    echo "  [FAIL] 未展开源码竟然编译通过——环境异常"; FAIL=1
else
    echo "  [PASS] 未展开源码失败（与设备 latestlog 同签名）"
fi

echo "== 1. 展开（驱动程序 + 模拟 resolver）=="
gcc -Wall -O2 -o "$OUT/driver" test_task47_e2e_driver.c ../Natives/shaderc_include.c || { echo "FATAL: driver build failed"; exit 1; }
for f in terrain entity clouds; do
    if ! "$OUT/driver" "task47_fixtures/$f.vsh" "$OUT/$f.expanded.vsh" "minecraft:core/$f"; then
        echo "  [FAIL] $f.vsh 展开失败"; FAIL=1
    else
        echo "  [PASS] $f.vsh 展开 OK"
    fi
done
if ! "$OUT/driver" "task47_fixtures/block.fsh" "$OUT/block.expanded.fsh" "minecraft:core/block"; then
    echo "  [FAIL] block.fsh 展开失败"; FAIL=1
else
    echo "  [PASS] block.fsh（fragment，含 oit 嵌套链）展开 OK"
fi

echo "== 2. glslangValidator 编译展开后源码（Vulkan/SPIR-V）=="
# --amb = --auto-map-bindings：等价 Mojang options 的 auto_bind_uniforms=true
# （glue 对应 GLSLANG_SHADER_AUTO_MAP_BINDINGS，设备路径已处理）。无 --amb
# 时 uniform 块报 'require layout(binding=X)'，且 entity 会级联出假性
# 'missing #endif'——均非展开器问题。
for f in terrain entity clouds; do
    spv="$OUT/$f.spv"
    err=$($GLSLANG -V -S vert --target-env vulkan1.2 --amb "$OUT/$f.expanded.vsh" -o "$spv" 2>&1)
    if echo "$err" | grep -q "ERROR"; then
        echo "  [FAIL] $f 编译错误:"; echo "$err" | head -8; FAIL=1
    else
        echo "  [PASS] $f -> SPIR-V 编译通过（vertex）"
    fi
done
spv="$OUT/block.spv"
err=$($GLSLANG -V -S frag --target-env vulkan1.2 --amb "$OUT/block.expanded.fsh" -o "$spv" 2>&1)
if echo "$err" | grep -q "ERROR"; then
    echo "  [FAIL] block.fsh 编译错误:"; echo "$err" | head -8; FAIL=1
else
    echo "  [PASS] block.fsh -> SPIR-V 编译通过（fragment，含 oit 三层嵌套链）"
fi

echo "== 3. SPIR-V 魔数校验 =="
for f in terrain entity clouds block; do
    spv="$OUT/$f.spv"
    if [ -f "$spv" ]; then
        magic=$(od -An -tx4 -N4 "$spv" | tr -d ' \n')
        if [ "$magic" = "07230203" ]; then
            sz=$(du -b "$spv" | cut -f1)
            echo "  [PASS] $f.spv 魔数 OK ($sz bytes)"
        else
            echo "  [FAIL] $f.spv 魔数 $magic != 07230203"; FAIL=1
        fi
    else
        echo "  [FAIL] $f.spv 不存在"; FAIL=1
    fi
done

echo
if [ "$FAIL" = "0" ]; then
    echo "E2E ALL PASS: 真实 26.3-pre-2 shader 经展开器后可被 glslang 编译为 SPIR-V"
else
    echo "E2E FAILED: $FAIL 处失败"
fi
exit $FAIL
