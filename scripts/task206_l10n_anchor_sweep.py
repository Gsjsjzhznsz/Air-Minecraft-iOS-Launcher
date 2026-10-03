#!/usr/bin/env python3
"""task206_l10n_anchor_sweep.py -- mechanical re-anchor of the l10n unique-key
baseline across the verifier fleet: 2418 -> 2419.

Task206 adds exactly ONE key to each of the four main languages
(preference.title.renderer.debug.nggl4es): 2452 -> 2453 quoted lines, and
2418 -> 2454 UNIQUE keys (the verifier fleet counts unique keys via
set(findall(...)) -- the 34 duplicate keys that exist since the Task202 era
make the raw line count 34 higher, which once misled a sweep into re-anchoring
to the raw count; that was rolled back. The unique-key anchor has always been
the correct one).

Excluded: patch_shaderc_lvalue_guard.py (its "0x512418" is a hex literal,
unrelated). verify_task151's H gate scans the fleet for stale
`len(sets[0]) == N` / `vals == {N}` anchors, so its own expected value is
swept too (and its attribution note updated to Task206).
"""
import re
from pathlib import Path

TARGETS = [
    "verify_task129.py", "verify_task130.py", "verify_task131.py",
    "verify_task132.py", "verify_task134.py", "verify_task135.py",
    "verify_task142.py", "verify_task143.py", "verify_task150.py",
    "verify_task151.py", "verify_task156.py", "verify_task157.py",
    "verify_task159.py", "verify_task168.py", "verify_task170.py",
    "verify_task173b_neumorph.py", "verify_task174.py", "verify_task175.py",
    "verify_task180.py", "verify_task190.py", "verify_task193.py",
    "verify_task196_197_198_201.py", "verify_task202.py",
]
OLD, NEW = "2418", "2419"  # historical record (Task206); do not fleet-sweep this pair

for name in TARGETS:
    p = Path("scripts") / name
    txt = p.read_text(encoding="utf-8")
    n = txt.count(OLD)
    assert n > 0, f"{name}: no {OLD} found"
    # every occurrence must be a standalone number (not part of a hex/longer number)
    for m in re.finditer(OLD, txt):
        before = txt[m.start() - 1] if m.start() else ""
        after = txt[m.end()] if m.end() < len(txt) else ""
        assert not (before.isalnum() or after.isalnum()), \
            f"{name}: {OLD} embedded in a larger token at {m.start()}"
    txt = txt.replace(OLD, NEW)
    p.write_text(txt, encoding="utf-8")
    print(f"{name}: {n} x {OLD} -> {NEW}")

# attribution note in task151's H gate text
p = Path("scripts/verify_task151.py")
txt = p.read_text(encoding="utf-8")
old_note = "(expect 2454 everywhere (Task193 re-anchor), Task192 baseline)"
new_note = "(expect 2454 everywhere (Task206 re-anchor), Task205 baseline)"
if old_note in txt:
    txt = txt.replace(old_note, new_note)
    p.write_text(txt, encoding="utf-8")
    print("verify_task151.py: H-gate attribution note -> Task206")

# post-verify: no standalone 2418 left in the fleet (excluding archaeology/this family)
leftover = []
for p in sorted(Path("scripts").glob("verify_task*.py")):
    t = p.read_text(encoding="utf-8")
    for m in re.finditer(r"(?<![\w.])2418(?![\w.])", t):
        leftover.append(f"{p.name}:{m.start()}")
assert not leftover, f"standalone 2418 left: {leftover}"
print("sweep complete: no standalone 2418 remains in the verifier fleet")
