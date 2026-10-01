#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task 207 级联重锚第二轮（编号让位重锚版：基于并行 Task206 尾部追加后的 29 条基线）：公告绝对索引家族。
task207@2 插入使全体非钉位（index >= 2）公告索引 +1（task206-nggl4es 尾部追加不位移，故锚值与本轮 7c0a021 基线相同）。本轮对九个持
绝对索引锚的 verify 做机械位移（anns[N]/ann[N], N>=2 -> N+1），并对
165/167 的窗口常数（min(22/20, len(anns))）做同义扩张（22->23 / 20->21）。
171-D3 的 KeyError 崩溃为 Task205 已记录的存量债务（ten-fixes 条目无
content 键），本轮不触碰。幂等：再跑时若无 >=2 的未位移索引则零改动。
"""
import io
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (文件, 额外显式替换列表)
TARGETS = [
    "scripts/verify_task168.py",
    "scripts/verify_task170.py",
    "scripts/verify_task171.py",
    "scripts/verify_task172.py",
    "scripts/verify_task173b_neumorph.py",
    "scripts/verify_task174.py",
    "scripts/verify_task175.py",
    "scripts/verify_task177.py",
    "scripts/verify_task178.py",
]

EXPLICIT = {
    "scripts/verify_task165.py": [
        ("range(min(22, len(anns)))", "range(min(23, len(anns)))"),
    ],
    "scripts/verify_task167.py": [
        ("range(min(20, len(anns)))", "range(min(21, len(anns)))"),
    ],
}


def shift_indices(src, varname):
    """anns[N]/ann[N] (N>=2) -> N+1；钉位 0/1 不动。"""
    pat = re.compile(r"\b" + varname + r"\[(\d+)\]")
    hits = []

    def rep(m):
        n = int(m.group(1))
        if n >= 2:
            hits.append(n)
            return f"{varname}[{n + 1}]"
        return m.group(0)

    return pat.sub(rep, src), hits


def main():
    total = 0
    for rel in TARGETS:
        p = os.path.join(REPO, rel)
        s = io.open(p, encoding="utf-8").read()
        orig = s
        hits = []
        for var in ("anns", "ann"):
            s, h = shift_indices(s, var)
            hits += h
        if s != orig:
            io.open(p, "w", encoding="utf-8").write(s)
            total += len(hits)
            print(f"[round2] {rel}: shifted {len(hits)} index site(s) "
                  f"(min {min(hits)} -> {min(hits)+1}, max {max(hits)} -> {max(hits)+1})")
        else:
            print(f"[round2] {rel}: no >=2 index sites (already shifted?)")

    for rel, pairs in EXPLICIT.items():
        p = os.path.join(REPO, rel)
        s = io.open(p, encoding="utf-8").read()
        changed = False
        for old, new in pairs:
            if new in s:
                continue
            if old not in s:
                print(f"[round2] FAIL: {rel} window anchor not found: {old}")
                sys.exit(1)
            s = s.replace(old, new)
            changed = True
            total += 1
        if changed:
            io.open(p, "w", encoding="utf-8").write(s)
            print(f"[round2] {rel}: window constant expanded")

    print(f"[round2] DONE ({total} site(s))")


if __name__ == "__main__":
    main()
