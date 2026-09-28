#!/usr/bin/env python3
# Task 193 -- (a) append the version.h addendum block (append-only, house format);
# (b) re-anchor the two announcement-index verifiers to the shifted window family
#     (task193 inserted at [2] pushes task190->3, task184->4, ..., task173-ten->12).
import io

VH = "Natives/external/MobileGlues/MobileGlues-cpp/version.h"
SEP = "// ============================================================================\n"

ADDENDUM = "\n" + (
    "// REVISION 18 addendum (Amethyst Task 193, no bump): the launcher app icon\n"
    "// (Light family) replaced with the user-uploaded grass-block cube artwork\n"
    "// (repo-root IMG_9288.jpeg, 690x690 -> LANCZOS 1024/152/120). Replaced set =\n"
    "// AppIcon-Light.appiconset all three appearance slots (universal/dark/tinted,\n"
    "// same-image x3 exactly as upstream shipped them) + AppIcon-Light60x60@2x\n"
    "// (iPhone primary per Info.plist CFBundlePrimaryIcon) + AppIcon-Light76x76@2x~ipad\n"
    "// (iPad primary). Provenance audit archived in verify_task193: ALL 14 icon files\n"
    "// were byte-identical to upstream herbrine8403/Amethyst-iOS-MyRemastered (Dark+\n"
    "// Development iconsets and the resources PNGs date to 2022-11-25, Light set to\n"
    "// 2025-05-29 'Add the final logo', AppLogo-Vector XMP 2025-05-25); per the user's\n"
    "// >1y rule those stay pristine. Zero code/config changes: Contents.json and\n"
    "// Info.plist untouched, icons are pure bitmaps referenced by filename only.\n"
    "// Verification: verify_task193 (A dims 5, B replaced-vs-upstream 5, C untouched\n"
    "// 9, D config purity 3, E provenance 3, F announcement 2, G source-present 1).\n"
) + SEP

def patch_version_h():
    with open(VH, encoding="utf-8") as f:
        txt = f.read()
    assert "Amethyst Task 193" not in txt, "already appended"
    assert txt.endswith(SEP), "unexpected version.h tail"
    with open(VH, "a", encoding="utf-8") as f:
        f.write(ADDENDUM)
    chk = open(VH, encoding="utf-8").read()
    assert chk.endswith(SEP) and "Amethyst Task 193" in chk
    print("version.h: addendum appended (Task 193)")

def patch_verify(path, subs):
    with open(path, encoding="utf-8") as f:
        txt = f.read()
    done = sum(1 for _, new in subs if new in txt)
    if done == len(subs):
        print(f"{path}: already re-anchored (idempotent skip)")
        return
    for old, new in subs:
        if new in txt:
            continue  # already applied
        assert txt.count(old) == 1, f"{path}: expected exactly one [{old}], got {txt.count(old)}"
        txt = txt.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(txt)
    print(f"{path}: re-anchored ({len(subs) - done} substitutions)")

# (a) version.h addendum -- MUST be invoked explicitly (first-run bug: defined but never called)
patch_version_h()

# (b) verify_task173.py M3: the whole task-window chain shifts +1 (comment updated to say why)
patch_verify(
    "scripts/verify_task173.py",
    [
        ('ann["announcements"][11]["id"] == "task173-ten-fixes-2026-09-26"  # Task184+190 各 +1',
         'ann["announcements"][12]["id"] == "task173-ten-fixes-2026-09-26"  # Task184+190+193 各 +1'),
        ('ann["announcements"][10]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"',
         'ann["announcements"][11]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"'),
        ('ann["announcements"][9]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"',
         'ann["announcements"][10]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"'),
        ('ann["announcements"][8]["id"] == "task175-six-fixes-2026-09-26"',
         'ann["announcements"][9]["id"] == "task175-six-fixes-2026-09-26"'),
        ('ann["announcements"][7]["id"] == "task177-neumorph-css-spec-2026-09-26"',
         'ann["announcements"][8]["id"] == "task177-neumorph-css-spec-2026-09-26"'),
        ('ann["announcements"][6]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"',
         'ann["announcements"][7]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"'),
        ('ann["announcements"][5]["id"] == "task179-eight-fixes-2026-09-26"',
         'ann["announcements"][6]["id"] == "task179-eight-fixes-2026-09-26"'),
        ('ann["announcements"][4]["id"] == "task180-opacity-dual-slider-2026-09-26"',
         'ann["announcements"][5]["id"] == "task180-opacity-dual-slider-2026-09-26"'),
        ('ann["announcements"][3]["id"] == "task184-revert-180-ui-whitespace-fix-2026-09-27"',
         'ann["announcements"][4]["id"] == "task184-revert-180-ui-whitespace-fix-2026-09-27"'),
    ],
)

# verify_task190.py: task190 entry moved from [2] to [3] by the task193 insert
patch_verify(
    "scripts/verify_task190.py",
    [
        ('json.loads(rdrepo("announcements.json"))["announcements"][2]["id"].startswith("task190-"))',
         'json.loads(rdrepo("announcements.json"))["announcements"][3]["id"].startswith("task190-"))'),
    ],
)

print("TASK193_DOCS_OK")
