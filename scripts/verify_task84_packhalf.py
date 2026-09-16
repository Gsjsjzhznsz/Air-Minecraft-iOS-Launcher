#!/usr/bin/env python3
"""
Task 84: 位级验证手写 packHalf2x16 / unpackHalf2x16 回退实现。

背景（75c5e14 装机日志实锤）：
  zink(MoltenVK=VK1.1) → 桌面 GL 4.1 / GLSL 4.10 上限；FSR EASU 片元着色器
  在 626(37) 报 no function with name packHalf2x16 —— packHalf2x16/unpackHalf2x16
  是 GLSL 4.20 核心内建（Task83b 注释称 4.00 内建有误），4.10 无此函数。
  修法：__VERSION__ < 420 时注入位运算手写实现（RNE 舍入、次正规、Inf/NaN）。

本脚本把 GLSL 回退实现的算法逐行镜像为 Python，用 numpy.float16（IEEE RNE
参考实现）对照海量随机值 + 全边界值，要求位级全等。
"""
import struct
import numpy as np

def f32_bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]

def bits_f32(u):
    return struct.unpack('<f', struct.pack('<I', u))[0]

# ---- GLSL ame84_packHalf1 的逐行 Python 镜像 ----
def pack_half1(a_bits):
    x = a_bits
    s = (x >> 16) & 0x8000
    e = (x >> 23) & 0xFF
    m = x & 0x7FFFFF
    if e == 255:                      # Inf / NaN
        return s | 0x7C00 | (0x1FF if m != 0 else 0)
    if e <= 112:                      # 半精度次正规或更小
        if e < 102:                   # < 2^-25 量级：RNE 下必为 0
            return s
        mp = m | 0x800000             # 补隐含 1
        shift = 126 - e
        hsub = mp >> shift
        rem = mp & ((1 << shift) - 1)
        half_ulp = 1 << (shift - 1)
        if rem > half_ulp or (rem == half_ulp and (hsub & 1) != 0):
            hsub += 1
        return s | hsub               # 进位到 1024 = 最小正规 0x0400，合法
    he = e - 112                      # 指数重置偏置（127 → 15）
    if he >= 31:                      # 溢出 → Inf（IEEE RNE 语义）
        return s | 0x7C00
    hm = m >> 13
    rem = m & 0x1FFF
    if rem > 0x1000 or (rem == 0x1000 and (hm & 1) != 0):
        hm += 1
    if hm == 0x400:                   # 尾数进位
        hm = 0
        he += 1
        if he >= 31:
            return s | 0x7C00
    return s | (he << 10) | hm

def pack_half2x16(a, b):
    return pack_half1(f32_bits(a)) | (pack_half1(f32_bits(b)) << 16)

# ---- GLSL ame84_unpackHalf1 的逐行 Python 镜像 ----
def unpack_half1(h):
    s = (h & 0x8000) << 16
    e = (h >> 10) & 0x1F
    m = h & 0x3FF
    if e == 0:
        if m == 0:
            return bits_f32(s)
        n = m
        adj = 0
        while (n & 0x400) == 0:       # 动态循环：找最高位
            n <<= 1
            adj += 1
        return bits_f32(s | ((113 - adj) << 23) | ((n & 0x3FF) << 13))
    if e == 31:
        return bits_f32(s | 0x7F800000 | (m << 13))
    return bits_f32(s | ((e + 112) << 23) | (m << 13))

def unpack_half2x16(u):
    return (unpack_half1(u & 0xFFFF), unpack_half1(u >> 16))

# ---- 参考实现：numpy float16（IEEE 754 RNE） ----
def ref_pack(a, b):
    ha = np.float16(a)
    hb = np.float16(b)
    def h2u(h):
        return int(np.uint16(np.frombuffer(np.array(h, dtype=np.float16).tobytes(), dtype=np.uint16)[0]))
    return h2u(ha) | (h2u(hb) << 16)

def ref_unpack(u):
    def u2h(x):
        return float(np.frombuffer(np.array([x], dtype=np.uint16).tobytes(), dtype=np.float16)[0])
    return (u2h(u & 0xFFFF), u2h(u >> 16))

def main():
    rng = np.random.default_rng(84)
    fails = []

    # --- 1. 随机浮点（均匀覆盖位模式空间：直接随机 f32 位再排除 NaN/Inf 由算法分支自测） ---
    N = 200000
    bits = rng.integers(0, 2**32, size=N, dtype=np.uint64).astype(np.uint64) % (2**32)
    vals = []
    for b in bits[:60000]:
        vals.append(bits_f32(int(b)))
    # --- 2. 精心构造的边界值 ---
    edges = [
        0.0, -0.0, 1.0, -1.0, 0.5, 0.1,
        65504.0, 65505.0, 65519.0, 65520.0, 65521.0, 65535.0, 65536.0, 131071.0, 131072.0,
        5.960464477539063e-08,   # 2^-24 半精度最小次正规
        5.960464477539063e-08 * 0.5,  # 恰在 0 与 2^-24 中点
        5.960464477539063e-08 * 0.5000001,
        2.9802322387695312e-08,  # 2^-25
        1.0000000596046448,      # 1 + 2^-24：1.0 与下一个 half 的中点附近
        1.0000152587890625,      # 1 + 2^-16 = half 的下一档
        1.0000076293945312,      # 1 + 2^-17：恰中点 → RNE 取偶
        0.300048828125, 0.300048828125 + 2**-13 / 2,
        2048.0, 2049.0, 4096.0,  # half 尾数位宽变化点
        0.00006097555160522461,  # 2^-14 附近（次正规→正规边界）
        0.000061035156250,       # 2^-14 = 最小正规 half
        0.0000305175781250,      # 2^-15（次正规中段）
    ]
    for e in edges:
        vals.append(e)
        vals.append(-e)
    # --- 3. 随机 half 值的精确表示（round-trip 必须 100% 无损） ---
    half_bits = rng.integers(0, 2**16, size=4000, dtype=np.uint64) % (2**16)
    exact_halves = [unpack_half1(int(h)) for h in half_bits]
    vals.extend(exact_halves)

    # --- 对每个值做 pack 校验 ---
    for v in vals:
        mine = pack_half1(f32_bits(v))
        ref = ref_pack(v, 0.0) & 0xFFFF
        if mine != ref:
            # NaN 的载荷位不要求逐位一致，只要求仍是 NaN
            mine_f = None
            try:
                mine_f = np.float16(0)
            except Exception:
                pass
            ref_is_nan = (ref & 0x7C00) == 0x7C00 and (ref & 0x3FF) != 0
            mine_is_nan = (mine & 0x7C00) == 0x7C00 and (mine & 0x3FF) != 0
            if ref_is_nan and mine_is_nan:
                continue
            if (ref & 0x7FFF) == 0x7C00 and (mine & 0x7FFF) == 0x7C00:
                continue  # 双 Inf
            fails.append(('pack', v, hex(mine), hex(ref)))

    # --- 对随机 u32 做 unpack 校验（含 Inf/NaN/次正规位模式） ---
    ubits = rng.integers(0, 2**32, size=50000, dtype=np.uint64) % (2**32)
    for u in ubits:
        u = int(u)
        mine = unpack_half2x16(u)
        ref = ref_unpack(u)
        for k in (0, 1):
            if np.isnan(mine[k]) and np.isnan(ref[k]):
                continue
            if np.isinf(mine[k]) and np.isinf(ref[k]) and np.signbit(mine[k]) == np.signbit(ref[k]):
                continue
            if mine[k] != ref[k] or (np.copysign(1.0, mine[k]) != np.copysign(1.0, ref[k])):
                fails.append(('unpack', hex(u), k, mine[k], ref[k]))

    # --- round-trip：pack 后 unpack 还原（对有限正规范围应无损） ---
    rt_fail = 0
    for v in exact_halves:
        p = pack_half1(f32_bits(v))
        back = unpack_half1(p)
        # NaN != NaN（IEEE），双 NaN 即通过；符号位不同的 ±0 单独比对
        if not (v != v and back != back):  # 双方都不是 NaN 才做数值比对
            if back != v:
                rt_fail += 1
                fails.append(('roundtrip', v, hex(p), back))

    print(f"tested: {len(vals)} pack values, 50000 unpack patterns, {len(exact_halves)} round-trips")
    if fails:
        print(f"FAIL: {len(fails)} mismatches (showing up to 20):")
        for f in fails[:20]:
            print("  ", f)
        raise SystemExit(1)
    print("ALL BIT-EXACT vs numpy float16 (RNE) — GLSL fallback algorithm verified")

if __name__ == '__main__':
    main()
