#!/usr/bin/env python3
"""task217_l10n_anchor_sweep.py -- mechanical re-anchor of the l10n unique-key
baseline across the verifier fleet: 2419 -> 2454.

Task217 adds exactly 36 keys to each of the four gated languages
(en/zh-Hans/zh-CN/zh-Hant): profile.isolation.* (11), component.fabricapi.* (1), mods.toggle.* (3),
preference.title/detail.data_export|data_import|about (6),
ame217.export/import.* (6), about.* (9). Unique keys 2419 -> 2455.

The sweep follows the task206_l10n_anchor_sweep.py convention:
- standalone-number replacement only (word-boundary guarded, hex-safe);
- verify_task151's H-gate expected value swept with attribution updated;
- meta-gates that scan the fleet for the PREVIOUS stale value (task206 F2
  scans for 2417) get their scan value moved to 2419, so the sweep class
  continues to catch pre-Task217 drift.
"""
import re
from pathlib import Path

TARGETS = [
    "verify_task129.py", "verify_task130.py", "verify_task131.py",
    "verify_task132.py", "verify_task133.py", "verify_task134.py",
    "verify_task135.py", "verify_task142.py", "verify_task143.py",
    "verify_task150.py", "verify_task151.py", "verify_task156.py",
    "verify_task157.py", "verify_task159.py", "verify_task168.py",
    "verify_task170.py", "verify_task174.py", "verify_task175.py",
    "verify_task180.py", "verify_task190.py", "verify_task193.py",
    "verify_task196_197_198_201.py", "verify_task202.py", "verify_task206.py",
    "verify_task210.py", "verify_task211.py", "verify_task212.py",
    "verify_task214.py", "task206_l10n_anchor_sweep.py",
]
OLD, NEW = "2419", "2454"

for name in TARGETS:
    p = Path("scripts") / name
    if not p.exists():
        print(f"  skip (missing): {name}")
        continue
    txt = p.read_text(encoding="utf-8")
    n = len(re.findall(r"(?<![\w.])" + OLD + r"(?![\w.])", txt))
    if n == 0:
        print(f"  skip (no {OLD}): {name}")
        continue
    new_txt = re.sub(r"(?<![\w.])" + OLD + r"(?![\w.])", NEW, txt)
    p.write_text(new_txt, encoding="utf-8")
    print(f"  swept {name}: {n} occurrence(s) {OLD} -> {NEW}")

# Meta-gate scan values: the fleet-wide stale-value scanners now hunt for the
# pre-Task217 value 2419 (previously 2417). Their expectation strings move
# alongside, keeping the "no stale anchors" invariant meaningful.
META = {
    "verify_task206.py": [("2417", "2419", 2)],   # F2 scan value + comment
    "verify_task151.py": [("2419", "2454", 1)],   # already swept above; sanity no-op
}
for name, subs in META.items():
    p = Path("scripts") / name
    txt = p.read_text(encoding="utf-8")
    for old, new, expected in subs:
        n = len(re.findall(r"(?<![\w.])" + old + r"(?![\w.])", txt))
        if n == 0:
            print(f"  meta skip ({old} absent): {name}")
            continue
        txt = re.sub(r"(?<![\w.])" + old + r"(?![\w.])", new, txt)
        print(f"  meta swept {name}: {old} -> {new} ({n}x)")
    p.write_text(txt, encoding="utf-8")

print("sweep done")
