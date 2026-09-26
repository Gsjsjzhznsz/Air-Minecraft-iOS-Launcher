#!/usr/bin/env python3
"""Task179 honest re-anchor: task179 announcement inserted at index 2 pushes
every non-pinned entry (old index >= 2) down by one. Patches the index-based
announcement anchors in the affected historical verifiers (same family style
as the Task178 re-anchor scripts)."""
import re

def bump_idx_gt2(m):
    idx = int(m.group(2))
    if idx >= 2:
        return f"{m.group(1)}[{idx + 1}]"
    return m.group(0)

FILES = [
    "scripts/verify_task165.py",
    "scripts/verify_task167.py",
    "scripts/verify_task168.py",
    "scripts/verify_task170.py",
    "scripts/verify_task171.py",
    "scripts/verify_task172.py",
    "scripts/verify_task173.py",
    "scripts/verify_task173b_neumorph.py",
    "scripts/verify_task174.py",
    "scripts/verify_task175.py",
    "scripts/verify_task177.py",
    "scripts/verify_task178.py",
]

idx_pat = re.compile(r"\b(anns)\[(\d+)\]")

for f in FILES:
    src = open(f, encoding="utf-8", errors="replace", newline="").read()
    lines = src.splitlines(keepends=True)
    out = []
    changed = 0
    for line in lines:
        newline = line
        # bump anns[N] where N >= 2 (id-order checks; anns[0]/anns[1] are pinned)
        def repl(m):
            global changed
            idx = int(m.group(2))
            if idx >= 2:
                changed += 1
                return f"anns[{idx + 1}]"
            return m.group(0)
        newline = idx_pat.sub(repl, newline)
        # bump window sizes in range(min(K, len(anns))) constructs
        def winrepl(m):
            global changed
            changed += 1
            return f"range(min({int(m.group(1)) + 1}, len(anns)))"
        newline = re.sub(r"range\(min\((\d+), len\(anns\)\)\)", winrepl, newline)
        out.append(newline)
    if changed:
        open(f, "w", encoding="utf-8", newline="").write("".join(out))
    print(f"{f}: {changed} index literals bumped")
print("done")
