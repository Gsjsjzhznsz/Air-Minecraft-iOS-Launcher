#!/usr/bin/env python3
"""Task 193 v2: 符号化 727a291 构建的控件仓库崩溃栈（优化版）。"""
import bisect
import lief

DSYM = "/tmp/dsym_727/Contents/Resources/DWARF/AngelAuraAmethyst"
FRAMES = [0x10ac454d8, 0x10ac45848, 0x10ac47d0c, 0x10ac42e34, 0x10ac431f8,
          0x10ad149d0, 0x10ad17050, 0x10ad27644, 0x10abe4d00]

bin = lief.MachO.parse(DSYM)[0]
syms = []
for s in bin.symbols:
    try:
        if s.value and s.name:
            syms.append((s.value, s.name))
    except Exception:
        pass
syms.sort()
addrs = [a for a, _ in syms]
print(f"symtab symbols: {len(syms)}")


def best_match(off):
    i = bisect.bisect_right(addrs, off) - 1
    if i < 0:
        return None
    a, n = syms[i]
    return (a, n, off - a)


anchor = FRAMES[0]
# 锚定法：帧0落在某函数 f 内 → slide = anchor - f.addr
cands = set()
for a, n in syms:
    if 0x100001000 <= a <= 0x120000000:
        slide = anchor - a
        if 0 <= slide <= 0x40000000:
            cands.add(slide)
print(f"candidate slides: {len(cands)}")

results = []
for slide in cands:
    resolved = []
    ok = True
    for fr in FRAMES:
        m = best_match(fr - slide)
        if m is None or m[2] > 0x3000:
            ok = False
            break
        resolved.append(m)
    if ok:
        names = " ".join(n for _, n, _ in resolved)
        score = 0
        if "Picker" in names or "Control" in names or "Menu" in names:
            score += 2
        if "didSelect" in names or "tableView" in names:
            score += 2
        if "_main" in names or "start" in names.lower():
            score -= 3
        results.append((score, slide, resolved))

results.sort(key=lambda x: -x[0])
seen = set()
for score, slide, resolved in results[:8]:
    if slide in seen:
        continue
    seen.add(slide)
    print(f"\n===== slide=0x{slide:x} score={score} =====")
    for fr, (a, n, d) in zip(FRAMES, resolved):
        print(f"  0x{fr:x} -> {n} +0x{d:x}")
