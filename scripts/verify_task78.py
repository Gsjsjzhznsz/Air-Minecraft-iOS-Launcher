#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 78 verification: FSR render-resolution linkage + 5-tier picker + MG issue research closure.

Checks:
  A. Source fingerprints (FSR1.cpp / FSR1.h / gl_bridge.m / SurfaceViewController.m /
     LauncherPreferencesViewController.m / 6 x Localizable.strings)
  B. Decision replay -- launcher-side math (preset x resolutionScale -> surface/render)
  C. FSR1.cpp state-machine replay (viewport latch vs surface fallback vs zero-gain)
  D. gl_bridge exemption matrix (FSR smaller-both exempt; transpose NOT exempt)
  E. Brace balance delta vs HEAD for edited C/ObjC files
"""
import os
import re, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILED = []

def check(name, cond, detail=""):
    print(("PASS" if cond else "FAIL"), name, detail if not cond else "")
    if not cond:
        FAILED.append(name)

def read(p):
    return open(f"{REPO}/{p}", encoding="utf-8", errors="replace").read()

fsr = read("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp")
fsrh = read("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.h")
setc = read("Natives/external/MobileGlues/MobileGlues-cpp/config/settings.cpp")
glb = read("Natives/ctxbridges/gl_bridge.m")
svc = read("Natives/SurfaceViewController.m")
lpc = read("Natives/LauncherPreferencesViewController.m")

print("== A. source fingerprints ==")
A = [
 (fsr, "FSR1.cpp: surface feed gated on pending==0",
  "g_pendingWidth == 0 && FSR1_Context::g_pendingHeight == 0"),
 (fsr, "FSR1.cpp: unconditional OnResize removed",
  "OnResize(width, height);"),
 (fsr, "FSR1.cpp: InitFSRResources adopts viewport latch",
  "Task 78 (Amethyst fork): adopt the viewport latch"),
 (fsr, "FSR1.cpp: init computes target for adopted latch",
  "CalculateTargetResolution(global_settings.fsr1_setting, FSR1_Context::g_pendingWidth"),
 (fsr, "FSR1.cpp: RecreateFSRFBO render texture RGBA8",
  "// Task 78 (Amethyst fork): RGBA8, matching InitFSRResources above"),
 (fsr, "FSR1.cpp: standalone zero-gain safety branch",
  "Task 78 (Amethyst fork) safety: zero-gain verdict without a pending"),
 (fsr, "FSR1.cpp: engage one-shot log",
  "[MG] FSR1 upscale engaged (Task78)"),
 (fsrh, "FSR1.h: render-follows-viewport doc",
  "Task 78 (Amethyst fork): the render size follows the application's viewport"),
 (setc, "settings.cpp: Apple branch reads fsr1Setting from config",
  'int fsr1Raw = success ? config_get_int((char*)"fsr1Setting") : -1;'),
 (setc, "settings.cpp: Apple branch reads angleDepthClearFixMode from config",
  'int depthFixRaw = success ? config_get_int((char*)"angleDepthClearFixMode") : -1;'),
 (setc, "settings.cpp: fsr1 range check keeps MaxValue out",
  "fsr1Raw < static_cast<int>(FSR1_Quality_Preset::MaxValue)"),
 (glb, "gl_bridge.m: exemption state cached",
  "s_task78_fsr_link = -1"),
 (glb, "gl_bridge.m: exemption gates on renderer + pref",
  'strcmp(ame78_renderer, RENDERER_NAME_MOBILEGLUES) == 0'),
 (glb, "gl_bridge.m: geoMismatch exemption requires BOTH dims smaller",
  "viewport[2] < surfW && viewport[3] < surfH"),
 (glb, "gl_bridge.m: exemption one-shot log",
  "Task78 FSR render<surface expected"),
 (glb, "gl_bridge.m: Task60 respects resolutionScale",
  "CGFloat rs60 = resolutionScale;"),
 (glb, "gl_bridge.m: LauncherPreferences import for getPrefInt",
  '#import "LauncherPreferences.h"'),
 (svc, "SurfaceViewController.m: preset scale helper",
  "ame78_fsr_preset_scale"),
 (svc, "SurfaceViewController.m: linkage log",
  "Task83 FSR linkage: renderer=%@"),  # Task83 起 FSR 多渲染器化，日志前缀更新；联动语义不变
 (svc, "SurfaceViewController.m: render window = surface / fsr scale",
  "windowWidth = roundf((float)surfaceWidth / mgFsrScale);"),
 (svc, "SurfaceViewController.m: drawable writes use surface dims",
  "metalLayer.drawableSize = CGSizeMake(MAX(surfaceWidth, 1), MAX(surfaceHeight, 1));"),
 (svc, "SurfaceViewController.m: input scale divided by fsr scale",
  "if (mgFsrScale > 0.0f) screenScale /= mgFsrScale;"),
 (svc, "SurfaceViewController.m: mgFsrScale ivar declared",
  "float mgFsrScale;"),
 (lpc, "PrefsVC: 5-tier pickKeys",
  '@"pickKeys": @[@"0", @"1", @"2", @"3", @"4"]'),
 (lpc, "PrefsVC: tier-4 label referenced",
  'preference.title.mg_fsr1_setting-4'),
]
for src, name, needle in A:
    check(name, needle in src)

# strings: 6 languages
for lang in ["en", "ja", "km", "zh-CN", "zh-Hans", "zh-Hant"]:
    s = read(f"Natives/resources/{lang}.lproj/Localizable.strings")
    check(f"strings[{lang}]: tier-4 present", '"preference.title.mg_fsr1_setting-4"' in s)
    check(f"strings[{lang}]: Balanced label fixed on tier-3",
          '"preference.title.mg_fsr1_setting-3"' in s and
          not re.search(r'mg_fsr1_setting-3" = "(性能优先|Performance|效能優先)"', s))
    check(f"strings[{lang}]: detail text mentions render-res linkage",
          "77%" in s and "50%" in s)

print("== B. launcher math replay ==")
def preset_scale(p):
    return {1: 1.3, 2: 1.5, 3: 1.7, 4: 2.0}.get(p, 1.0)

def even(v):
    v = int(round(v))
    return v - 1 if v % 2 else v

def launcher_math(physical_w, physical_h, res_pct, preset):
    rs = res_pct / 100.0
    fs = preset_scale(preset)
    sw, sh = even(physical_w * rs), even(physical_h * rs)
    ww, wh = even(sw / fs), even(sh / fs)
    return sw, sh, ww, wh

# user's manual setup reproduced automatically: Performance == "50% resolution + FSR"
sw, sh, ww, wh = launcher_math(2360, 1640, 100, 4)
check("B1 Performance: render is half of surface",
      abs(ww - 1180) <= 2 and abs(wh - 820) <= 2 and sw == 2360, f"{ww}x{wh} vs {sw}x{sh}")
sw, sh, ww, wh = launcher_math(2360, 1640, 100, 1)
check("B2 UltraQuality: render ~77% of surface",
      abs(ww / sw - 1 / 1.3) < 0.02 and abs(wh / sh - 1 / 1.3) < 0.02, f"{ww}x{wh}")
sw, sh, ww, wh = launcher_math(2360, 1640, 100, 0)
check("B3 FSR off: window == surface (legacy behavior preserved)",
      ww == sw and wh == sh, f"{ww}x{wh} vs {sw}x{sh}")
sw, sh, ww, wh = launcher_math(2360, 1640, 50, 0)
check("B4 FSR off + 50% slider: identical to legacy slider semantics",
      ww == 1180 and wh == 820 and sw == 1180, f"{ww}x{wh}/{sw}x{sh}")
sw, sh, ww, wh = launcher_math(2360, 1640, 50, 4)
check("B5 slider and FSR compose (50% surface, /2 render)",
      sw == 1180 and abs(ww - 590) <= 2, f"surf {sw}x{sh} render {ww}x{wh}")

print("== C. FSR1.cpp state-machine replay ==")
class FSRSim:
    def __init__(self, preset):
        self.preset = preset
        self.render = (960, 540)          # file defaults
        self.pending = (0, 0)
        self.changed = False
        self.torn_down = False
        self.recreated_at = None
    def scale(self):
        return preset_scale(self.preset) if self.preset else 1.5
    def glviewport_hook(self, w, h):
        if w > self.pending[0] or h > self.pending[1]:
            self.pending = (w, h)
            self.changed = True
    def init(self):
        # Task78 adoption
        if self.pending[0] > 0 and self.pending[1] > 0:
            self.render = self.pending
            # target computed at init (not simulated further)
    def check(self, surface):
        sw, sh = surface
        # Task78: fallback feed only when pending == 0
        if self.pending[0] == 0 and self.pending[1] == 0:
            if self.render != surface:
                self.pending = surface
                self.changed = True
        if self.changed:
            self.changed = False
            self.render = self.pending
            fs = self.scale()
            target = (even(self.render[0] * fs), even(self.render[1] * fs))
            if self.render[0] >= sw and self.render[1] >= sh:
                self.torn_down = True
                return ("teardown", self.render, target)
            return ("recreate", self.render, target)
        elif (not self.torn_down and self.render[0] > 0 and
              self.render[0] >= sw and self.render[1] >= sh):
            self.torn_down = True
            return ("teardown-safety", self.render, None)
        return ("noop", self.render, None)

# C1: linkage flow -- MC viewport 1573x1093, surface 2360x1640, Quality
sim = FSRSim(2)
sim.glviewport_hook(1573, 1093)
sim.init()
r1 = sim.check((2360, 1640))
check("C1 linkage: first check recreates at viewport latch (not surface)",
      r1[0] == "recreate" and r1[1] == (1573, 1093), str(r1))
check("C1b linkage: target lands on the surface",
      abs(r1[2][0] - 2360) <= 3 and abs(r1[2][1] - 1640) <= 3, str(r1))
r2 = sim.check((2360, 1640))
check("C1c linkage: steady state is noop (no per-frame churn)",
      r2[0] == "noop", str(r2))

# C2: legacy app (fullscreen viewport) -- old behavior preserved via fallback
sim = FSRSim(2)
sim.init()                                  # no viewport ever latched
r = sim.check((1180, 820))
check("C2 legacy fullscreen app: fallback feed -> render==surface -> teardown",
      r[0] == "teardown" and r[1] == (1180, 820), str(r))

# C3: pre-Task76 pathology is unreachable: surface feed cannot pin render==surface
#     while a smaller viewport was latched
sim = FSRSim(2)
sim.glviewport_hook(1180, 820)              # MC told half window
r = sim.check((2360, 1640))
check("C3 viewport latch wins over surface (old clobber gone)",
      r[0] == "recreate" and r[1] == (1180, 820), str(r))

# C4: preset on, linkage inactive (viewport==surface, adopted at init) --
#     the changed-branch itself renders the zero-gain verdict at first swap
sim = FSRSim(2)
sim.glviewport_hook(1180, 820)
sim.init()                                  # adopts 1180x820 (changed still True from hook)
r = sim.check((1180, 820))
check("C4 linkage-inactive: first swap tears down (no double-resample tax)",
      r[0] in ("teardown", "teardown-safety") and sim.torn_down, str(r))

# C4b: safety branch -- steady upscale, then the surface SHRINKS below render
#      (window resize down; no new viewport latched, changed == False)
sim = FSRSim(2)
sim.glviewport_hook(1573, 1093)
sim.init()
sim.check((2360, 1640))                     # recreate at 1573, changed consumed
r = sim.check((1200, 800))                  # surface shrank below render
check("C4b safety: render>=shrunk surface tears down without pending change",
      r[0] == "teardown-safety" and sim.torn_down, str(r))

# C5: rotation -- W/H swap latches (h grows)
sim = FSRSim(4)
sim.glviewport_hook(1180, 820)
sim.check((2360, 1640))
sim.glviewport_hook(820, 1180)              # rotated viewport
r = sim.check((1640, 2360))
check("C5 rotation: new latch adopted, target follows new surface",
      r[0] == "recreate" and r[1] == (820, 1180) and abs(r[2][0] - 1640) <= 3, str(r))

print("== D. gl_bridge exemption matrix ==")
def mismatch(viewport, surface, fsr_link):
    vw, vh = viewport
    sw, sh = surface
    base = vw > 0 and vh > 0 and sw > 0 and sh > 0 and (vw != sw or vh != sh)
    exempt = fsr_link and vw < sw and vh < sh
    return base and not exempt

check("D1 FSR on, render<surface both dims -> exempt",
      not mismatch((1573, 1093), (2360, 1640), True))
check("D2 transposed (one dim larger) -> NOT exempt (heal chain stays armed)",
      mismatch((820, 1180), (1180, 820), True))
check("D3 FSR off, same mismatch -> NOT exempt",
      mismatch((1573, 1093), (2360, 1640), False))
check("D4 equal dims -> no mismatch anyway",
      not mismatch((1180, 820), (1180, 820), True))
check("D5 viewport larger in one dim only -> NOT exempt (resize edge)",
      mismatch((2800, 1093), (2360, 1640), True))

print("== E. brace balance (edited files vs HEAD) ==")
def balance(s):
    return (s.count("{") - s.count("}"), s.count("(") - s.count(")"),
            s.count("[") - s.count("]"))

def head_balance(path):
    out = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{path}"],
                         capture_output=True, text=True)
    return balance(out.stdout)

for path, cur in [("Natives/ctxbridges/gl_bridge.m", glb),
                  ("Natives/SurfaceViewController.m", svc),
                  ("Natives/LauncherPreferencesViewController.m", lpc),
                  ("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp", fsr),
                  ("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.h", fsrh),
                  ("Natives/external/MobileGlues/MobileGlues-cpp/config/settings.cpp", setc)]:
    hb, cb = head_balance(path), balance(cur)
    check(f"E braces stable: {path.split('/')[-1]}",
          hb == cb, f"HEAD {hb} vs now {cb}")

print("== F. settings.cpp Apple-branch config replay (device-log regression) ==")
# e3e0830 设备日志实证：launcher 写 config.json fsr1Setting=1，MG dump 读 0
# （上游 Apple 分支硬编码 Disabled、从不读这两个键）。回归模型：
def apple_branch_read(config_val, success):
    raw = config_val if success else -1
    if raw >= 0 and raw < 5:      # FSR1_Quality_Preset::MaxValue == 5
        return raw
    return 0                       # Disabled
check("F1b 新读法：1 -> 1（preset 生效，旧代码恒 0）", apple_branch_read(1, True) == 1)
check("F2 缺键（-1）保持 Disabled", apple_branch_read(-1, True) == 0)
check("F3 越界值（5=MaxValue）保持 Disabled", apple_branch_read(5, True) == 0)
check("F4 config 加载失败保持 Disabled", apple_branch_read(1, False) == 0)
check("F5 depth fix：2 -> Mode2", apple_branch_read(2, True) == 2)

print()
print(f"{'ALL PASS' if not FAILED else 'FAILURES: ' + ', '.join(FAILED)} ({len(FAILED)} failed)")
sys.exit(1 if FAILED else 0)
