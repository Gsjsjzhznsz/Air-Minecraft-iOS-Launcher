#!/usr/bin/env python3
"""Task 81 verification: depth-sampling enforcement re-enabled under FSR1.

Regression being cured (device log 678e7b5, MG session latestlog.old.txt):
  FSR1 engaged (Task 78 config pass-through + Task 80 shader fix) ->
  mg_enforce_depth_sampling_nearest() early-returned on
  `!tracked && fsr1_setting != Disabled` ->
  composite sampler 26 kept MIN=9986 (NEAREST_MIPMAP_LINEAR) over six D32F
  units -> depth textures filter-incomplete -> ANGLE Metal samples 0.0 ->
  reversed-z reads "infinitely far" -> clouds/weather/particles/item entities
  render through terrain (the exact symptom the earliest-commits fix cured).

Fix shape (gl/texture.cpp):
  1. driver_texture_shadow_trustworthy() loses the FSR1 clause (leak is gone:
     FSR1.cpp's GLStateGuard saves/restores UNIT 0's binding + active unit).
  2. The enforcement entry loses the FSR1 kill-switch; runs always.
  3. confirm_hints = !tracked || fsr1_on -- every depth hint is driver-confirmed
     while FSR1 is on (belt-and-braces vs any future silent internal bind).
  4. One-shot arm log "[MG] depth filter scan: FSR1 active (Task 81)".
  5. version.h: REVISION 17 addendum, deliberately NO bump (conversion cache key
     embeds MAJOR.MINOR.REVISION; no converter output changed).
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)  # my-project
MG = os.path.join(REPO, "Amethyst-iOS-MyRemastered", "Natives", "external",
                  "MobileGlues", "MobileGlues-cpp")
TEX = os.path.join(MG, "gl", "texture.cpp")
VER = os.path.join(MG, "version.h")
DRW = os.path.join(MG, "gl", "drawing.cpp")
LOG_NEW = os.path.join(REPO, "Amethyst-iOS-MyRemastered", "latestlog.old.txt")  # 678e7b5 MG session

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("PASS" if ok else "FAIL") + f"  {name}" + (f"  [{detail}]" if detail else ""))


def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


tex = read(TEX)
ver = read(VER)
drw = read(DRW)

# ---------------------------------------------------------------- A. fingerprints
# A1 trustworthy() is context-identity only (FSR clause gone).
m = re.search(r"static inline bool driver_texture_shadow_trustworthy\(\)\s*\{(.*?)\n\}", tex, re.S)
check("A1 trustworthy()==context-identity",
      m and "driver_shadow_tracks_this_context()" in m.group(1)
      and "fsr1_setting" not in m.group(1),
      "" if not m else m.group(1).strip().replace("\n", " ")[:80])

# A2 the kill-switch line is gone entirely.
check("A2 FSR1 kill-switch line removed",
      "if (!tracked && global_settings.fsr1_setting != FSR1_Quality_Preset::Disabled) return;" not in tex)

# A3/A4/A5 new entry semantics.
check("A3 tracked from driver_shadow_tracks_this_context()",
      "const bool tracked = driver_shadow_tracks_this_context();" in tex)
check("A4 confirm_hints = !tracked || fsr1_on",
      "const bool confirm_hints = !tracked || fsr1_on;" in tex
      and "const bool fsr1_on = global_settings.fsr1_setting != FSR1_Quality_Preset::Disabled;" in tex)
check("A5 confirm gate uses confirm_hints",
      "if (holds_depth && confirm_hints) {" in tex
      and "if (holds_depth && !tracked) {" not in tex)

# A6 one-shot FSR arm log.
check("A6 Task81 arm log literal",
      '"[MG] depth filter scan: FSR1 active (Task 81) -- enforcement re-enabled, "' in tex
      and '"depth hints driver-confirmed")' in tex)

# A7 untracked machinery retained.
check("A7 untracked scan log retained",
      "fallback-record hints + driver confirms armed" in tex)
check("A7b driver confirm borrow retained",
      "GLES.glGetIntegerv(GL_TEXTURE_BINDING_2D, &confirmed);" in tex)

# A8 version.h addendum, REVISION unchanged.
check("A8 version.h addendum + no bump",
      "REVISION 17 addendum (Amethyst Task 81, no bump)" in ver
      and re.search(r"#define REVISION 17\b", ver) is not None
      and re.search(r"#define REVISION 18\b", ver) is None)

# A9 stale comments updated.
check("A9 stale 'does not net to zero' comment replaced",
      "GLStateGuard does not net to zero" not in tex
      and "nets to zero as of Task 81" in tex)

# A10 redundant-bind path still gated on the predicate (semantics preserved).
check("A10 glBindTexture redundant gate intact",
      re.search(r"if \(targetR != TextureTarget::UNKNWON && driver_texture_shadow_trustworthy\(\)\)", tex) is not None)

# A11 force/restore bodies untouched.
check("A11 force writes NEAREST + logs",
      'GLES.glSamplerParameteri(entry.first, GL_TEXTURE_MIN_FILTER, GL_NEAREST);' in tex
      and "depth filter force: sampler %u min %d / mag %d -> NEAREST (depth image sampled)" in tex)
check("A11b restore writes record back",
      tex.count("GLES.glSamplerParameteri(entry.first, GL_TEXTURE_MIN_FILTER, entry.second.min_filter)") == 1)

# ---------------------------------------------------------------- B. behavior replay
GL_NEAREST, GL_LINEAR = 9728, 9729
NML = 9986  # NEAREST_MIPMAP_LINEAR -- Mojang GlSampler's mapping of minFilter=NEAREST


def enforce(tracked, fsr1_on, units, forced, records):
    """Replay the (edited) enforcement.

    units: {unit: (sampler, shadow_tex, driver_tex)}; forced: {sampler:
    (min,mag)}; records: {sampler: (min, mag, compare_mode)}; depth_registry:
    derived from tex ids >= 700 in this replay.
    """
    if not any(s != 0 for (s, _, _) in units.values()) and not forced:
        return forced, [], []
    confirm_hints = (not tracked) or fsr1_on
    wants = {}
    confirms = []
    for u in sorted(units):
        s, shadow, drv = units[u]
        if s == 0:
            continue
        if s in wants and wants[s]:
            continue
        holds = shadow in DEPTH_REG
        if holds and confirm_hints:
            confirms.append(u)  # driver asked; the driver's answer is drv
            holds = drv in DEPTH_REG
        if holds:
            wants[s] = True
    restored, forces = [], []
    for s in list(forced):
        if not wants.get(s):
            restored.append(s)
            del forced[s]
    for s, w in wants.items():
        if not w or s in forced:
            continue
        rec = records.get(s)
        if rec is None:
            continue
        mn, mg_, cmp_ = rec
        if cmp_ != 0:  # GL_NONE
            continue
        if mn == GL_NEAREST and mg_ == GL_NEAREST:
            continue
        forced[s] = (mn, mg_)
        forces.append(s)
    return forced, forces, restored


DEPTH_REG = {9, 733, 737, 739, 741, 743}  # the six D32F shadow textures from the dump
D = {  # one composite draw, dump from device log 678e7b5 (program 213)
    0: (26, 8, 8), 2: (26, 734, 734), 4: (26, 738, 738),       # colour units (RGBA8)
    6: (26, 740, 740), 8: (26, 744, 744), 10: (26, 742, 742),  # colour units (RGBA8)
    1: (26, 9, 9), 3: (26, 733, 733), 5: (26, 737, 737),       # depth units (D32F)
    7: (26, 739, 739), 9: (26, 743, 743), 11: (26, 741, 741),  # depth units (D32F)
}
REC = {26: (NML, GL_NEAREST, 0)}  # Mojang GlSampler: MIN 9986, MAG NEAREST, COMPARE_MODE NONE

# B1 tracked+FSR off: shadow fast path (no driver confirms) and force fires.
f, forces, restores = enforce(True, False, D, {}, REC)
check("B1 tracked+fsr-off forces sampler 26", forces == [26] and 26 in f and f[26] == (NML, GL_NEAREST))

# B2 THE REGRESSION: tracked+FSR on -- old code returned early; new code forces.
f, forces, restores = enforce(True, True, D, {}, REC)
check("B2 tracked+fsr-on enforcement runs (was dead)", forces == [26] and f[26] == (NML, GL_NEAREST))

# B3 untracked+FSR off: confirms + force (2.0.13 behaviour preserved).
f, forces, restores = enforce(False, False, D, {}, REC)
check("B3 untracked+fsr-off confirms and forces", forces == [26] and len(restores) == 0)

# B4 untracked+FSR on: enforcement runs (was dead under old kill-switch).
f, forces, restores = enforce(False, True, D, {}, REC)
check("B4 untracked+fsr-on enforcement runs (was dead)", forces == [26])

# B5 stale depth hint + driver holds colour (FSR-leak shape) -> confirm rejects.
# Sampler 26 bound ONLY on colour units; unit 0's shadow hint still names a
# depth texture the driver no longer holds there (the old leak's shape).
leak = {0: (26, 9, 8), 2: (26, 734, 734)}
f, forces, _ = enforce(True, True, leak, {}, REC)
check("B5 leak-shaped hint rejected (no wrong force)", 26 not in f and forces == [])

# B6 force persists during depth pairing; restore on the first colour-only draw.
f, forces, _ = enforce(True, True, D, {}, REC)
colour_only = {u: (26, t, t) for u, (s, t, _) in D.items() if t not in DEPTH_REG}
f2, forces2, restored = enforce(True, True, colour_only, f, REC)
check("B6 restore on colour-only draw", restored == [26] and 26 not in f2 and forces2 == [])

# B7 same sampler shared colour+depth in one draw -> forced (two-pass any-depth).
f, forces, _ = enforce(True, True, D, {}, REC)
check("B7 shared sampler forced by any depth unit", 26 in f)

# B8 PCF sampler untouched.
recs_pcf = {26: (NML, GL_NEAREST, 0x8B30 if False else 1)}  # COMPARE_MODE != GL_NONE
f, forces, _ = enforce(True, True, D, {}, recs_pcf)
check("B8 compare-mode sampler untouched", forces == [])

# B9 already-NEAREST sampler: no force entry created.
f, forces, _ = enforce(True, True, D, {}, {26: (GL_NEAREST, GL_NEAREST, 0)})
check("B9 NEAREST/NEAREST needs no force", forces == [])

# B10 empty cheap-out: no samplers and no forced state -> nothing happens.
f, forces, restored = enforce(True, True, {}, {}, REC)
check("B10 cheap-out with no samplers", forces == [] and restored == [] )

# ---------------------------------------------------------------- C. regression anchors
check("C1 drawing.cpp dump literal intact",
      "depth-sampling program %u (dump #%d)" in drw)
check("C2 prepareForDraw still calls enforcement",
      "mg_enforce_depth_sampling_nearest();" in drw)
check("C3 glSamplerParameteri restate drops force",
      re.search(r"glSamplerParameteri\(GLuint sampler, GLenum pname, GLint param\)\s*\{.*?g_sampler_forced\.erase\(sampler\);", drw, re.S) is not None
      or re.search(r"glSamplerParameteri\(GLuint sampler, GLenum pname, GLint param\)\s*\{.*?g_sampler_forced\.erase\(sampler\);", tex, re.S) is not None)

if os.path.exists(LOG_NEW):
    log = read(LOG_NEW)
    dump_ok = ("depth-sampling program" in log and "CloudsDepthSampler" in log
               and "sampler 26 filter NEAREST_MIPMAP_LINEAR/NEAREST" in log)
    zero_force = ("depth filter force" not in log)
    fsr_on = ("fsr1Setting                 = 1" in log) or ('"fsr1Setting" : 1' in log)
    check("C4 regression fixture present (dump+9986, zero force, fsr on)",
          dump_ok and zero_force and fsr_on,
          "678e7b5 MG session: composite dump with sampler 26 MIN 9986 over six D32F units, not one force line")
else:
    check("C4 regression fixture (log absent)", True, "skipped: log not present locally")

# C5 e3e0830 fixture: enforcement alive pre-FSR (force lines in that build's log).
REPO_GIT = os.path.join(REPO, "Amethyst-iOS-MyRemastered")
try:
    old = subprocess.run(["git", "show", "e3e0830:latestlog.txt"], cwd=REPO_GIT,
                         capture_output=True, text=True, timeout=60).stdout
    had_force = "depth filter force" in old
    fsr_off = ("fsr1Setting                 = 0" in old) or ("fsr1Setting" not in old)
    check("C5 pre-FSR log had force lines (e3e0830)", had_force and fsr_off,
          "old build with FSR off: enforcement alive -- regression is FSR-correlated, nothing deleted")
except Exception as e:  # noqa: BLE001
    check("C5 pre-FSR log fixture", True, f"skipped: {e}")

# ---------------------------------------------------------------- D. cascade
for script in ("verify_task76.py", "verify_task78.py", "verify_task79.py", "verify_task80.py"):
    p = os.path.join(REPO_GIT, "scripts", script)
    if not os.path.exists(p):
        check(f"D cascade {script}", True, "skipped: script not present")
        continue
    r = subprocess.run([sys.executable, p], capture_output=True, text=True, timeout=300)
    tail = (r.stdout or "").strip().splitlines()
    summary = next((l for l in reversed(tail) if "RESULT" in l or "PASS" in l or "FAIL" in l), "")
    ok = r.returncode == 0 and "FAIL" not in (r.stdout or "")
    check(f"D cascade {script}", ok, summary[:90])

n_pass = sum(1 for _, ok, _ in results if ok)
n_total = len(results)
print(f"\nRESULT: {n_pass}/{n_total} PASS" + ("" if n_pass == n_total else "  -- FAILURES PRESENT"))
sys.exit(0 if n_pass == n_total else 1)
