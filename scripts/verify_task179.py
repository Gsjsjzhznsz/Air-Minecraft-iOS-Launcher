#!/usr/bin/env python3
"""Task179 verifier: eight-symptom device-feedback round (cc8ced8 logs).

A. ANGLE ES3-context switch + desktop-identity spoof (gl_bridge.m, tinygl4angle.c)
B. vgpu NOEGL + proc_address framework handles (CMakeLists, load.c, loader.c, hardext.c)
C. JIT wait suspension-gap exclusion (utils.m, RightPanel)
D. Hotbar guiScale reads the ACTUAL instance options.txt (input_bridge_v3, JavaLauncher)
E. Right-shift toggle semantics (SurfaceViewController)
F. CF/Modrinth loader-less request interception + no-data hardening
G. Version filter low-version expansion (DownloadViewController)
H. AvatarManager main-thread guards (LauncherNewsViewController)
I. Syntax gates (bracket balance + task175 gates + C syntax)
J. Docs (announcements task179@2, version.h addendum)
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"PASS  {name}")
    else:
        FAIL += 1
        print(f"FAIL  {name}  {detail}")


def rd(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace", newline="") as f:
        return f.read()


# ---------------- A. ANGLE ----------------
gl_bridge = rd("Natives/ctxbridges/gl_bridge.m")
check("A1 gl_bridge ame179_angleEs special case present（CI 修复轮：UTF8String + strcmp 家法，不再 NSString 直传 strstr）",
      'strcmp(ame179_rendererUtf8, RENDERER_NAME_MTL_ANGLE) == 0' in gl_bridge
      and "strstr(renderer" not in gl_bridge)
check("A2 ame179_angleEs forces desktopGL=NO（CI 修复轮：判定上移到函数开头，先于 attribs/eglBindAPI/ctx-attribs 三处消费点）",
      "if (ame179_angleEs) {" in gl_bridge
      and gl_bridge.find("if (ame179_angleEs) {") < gl_bridge.find("EGL_RENDERABLE_TYPE, desktopGL ?")
      and gl_bridge.find("if (ame179_angleEs) {") < gl_bridge.find("handle.eglBindAPI(EGL_OPENGL_API)")
      and gl_bridge.find("if (ame179_angleEs) {") < gl_bridge.find("desktopGL ? desktop_ctx_attribs : gles_ctx_attribs"))
check("A3 ANGLE ES3 anchor log present",
      "Task179 ANGLE on real ES3 context" in gl_bridge)

tinygl = rd("Natives/external/gl4es/tinygl4angle.c")
check("A4 ame179_spoofDesktopVersion present",
      "static const char *ame179_spoofDesktopVersion(const char *s)" in tinygl)
check("A5 ame179_spoofDesktopGlsl present",
      "static const char *ame179_spoofDesktopGlsl(const char *s)" in tinygl)
check("A6 GL_VERSION prefix match length 12 (OpenGL ES 3.)",
      'strncmp(s, "OpenGL ES 3.", 12) == 0' in tinygl)
check("A7 GLSL prefix match length 18 (OpenGL ES GLSL ES )",
      'strncmp(s, "OpenGL ES GLSL ES ", 18) == 0' in tinygl)
check("A8 GLSL spoof chains into Task173 normalization (no early return between)",
      "s = ame179_s;" in tinygl and tinygl.find("s = ame179_s;") < tinygl.find('strncmp(s, "OpenGL GLSL ", 12)'))
check("A9 spoof emits 3.3.0 (facade form)",
      '"3.3.0%s"' in tinygl)
check("A10 spoof emits OpenGL GLSL 3.30 (facade form)",
      '"OpenGL GLSL 3.30%s"' in tinygl)

# ---------------- B. vgpu ----------------
cmake = rd("Natives/CMakeLists.txt")
check("B1 vgpu defines include NOEGL",
      "NOX11 NO_GBM NOEGL DEFAULT_ES=3 SHAREDLIB" in cmake)
load_c = rd("Natives/external/vgpu/src/gl/pack/load.c")
check("B2 framework handle globals declared",
      "void *vgpu_gles_handle = NULL;" in load_c and "void *vgpu_egl_handle = NULL;" in load_c)
check("B3 load_all stores handles + opens EGL framework",
      "vgpu_gles_handle = libGL;" in load_c and "vgpu_egl_handle = dlopen(LIB_EGL_NAME, flags);" in load_c)
import re as _re
_load_no_comment = _re.sub(r"//[^\n]*", "", _re.sub(r"/\*.*?\*/", "", load_c, flags=_re.S))
check("B4 dlclose(libGL) retired (code, comments excluded)",
      "dlclose(libGL)" not in _load_no_comment)
loader_c = rd("Natives/external/vgpu/src/gl/loader.c")
check("B5 proc_address Apple branch uses explicit handles",
      "dlsym(vgpu_egl_handle, name)" in loader_c and "dlsym(vgpu_gles_handle, name)" in loader_c)
check("B6 proc_address keeps RTLD_NEXT then RTLD_DEFAULT fallbacks",
      'dlsym((void*)(~(uintptr_t)0), name)' in loader_c and 'dlsym((void*)0, name)' in loader_c)
hardext_c = rd("Natives/external/vgpu/src/glx/hardext.c")
check("B7 Exts NULL fallback",
      'if (Exts == NULL) Exts = "";' in hardext_c)
check("B8 vendor/renderer NULL guards",
      'if (!vendor) vendor = "";' in hardext_c and 'if (!renderer) renderer = "";' in hardext_c)

# ---------------- C. JIT wait ----------------
utils_m = rd("Natives/utils.m")
check("C1 suspension-gap exclusion in ame169_waitForJITCondition",
      "suspension gap" in utils_m and "dateByAddingTimeInterval:ame179_gap" in utils_m)
check("C2 gap threshold 2.0s",
      "ame179_gap > 2.0" in utils_m)
rightpanel = rd("Natives/LauncherRightPanelViewController.m")
check("C3 background-task assertion validity log",
      "Task179 background task assertion" in rightpanel)

# ---------------- D. Hotbar options.txt source ----------------
ib = rd("Natives/input_bridge_v3.m")
check("D1 readGuiScaleFromOptions tries CWD first",
      'fopen("options.txt", "r")' in ib)
check("D2 POJAV_GAME_DIR is fallback (not primary)",
      ib.find('fopen("options.txt", "r")') < ib.find('"%s/options.txt", gameDir'))
check("D3 sanitizer reads AME67_INSTANCE_GAME_DIR",
      'getenv("AME67_INSTANCE_GAME_DIR")' in ib)
jl = rd("Natives/JavaLauncher.m")
check("D4 JavaLauncher sets AME67_INSTANCE_GAME_DIR after gameDir resolution",
      'setenv("AME67_INSTANCE_GAME_DIR", gameDir.UTF8String, 1);' in jl)
check("D5 early (pre-gameDir) sanitizer call removed",
      jl.find("ame67_sanitizeOptionsKeybinds();") - jl.find('setenv("AME67_INSTANCE_GAME_DIR"') > 0 or
      jl.count("ame67_sanitizeOptionsKeybinds();") == 1)
check("D6 exactly one sanitizer call site (post-resolution)",
      jl.count("ame67_sanitizeOptionsKeybinds();") == 1)

# ---------------- E. Right-shift toggle ----------------
svc = rd("Natives/SurfaceViewController.m")
check("E1 toggle set present",
      "s_ame179_toggledMods" in svc)
check("E2 toggle ON log",
      "Task179 mod toggle ON" in svc)
check("E3 toggle OFF log",
      "Task179 mod toggle OFF" in svc)
check("E4 old latch set retired",
      "s_ame176_latchedMods" not in svc)
check("E5 auto-release-on-next-input retired",
      "sticky mod auto-release after key" not in svc and "ame176_hasNonModInput" not in svc)
check("E6 hold clears toggle (momentary priority)",
      svc.find("长按释放：常规 UP") != -1 or "long-press" in svc.lower())

# ---------------- F. CF/Modrinth loader interception ----------------
cfa = rd("Natives/installer/modpack/CurseForgeAPI.m")
check("F1 CF loader-less guard present",
      "ame179_loaderLessType" in cfa)
check("F2 CF guard returns before loaderMap",
      cfa.find("if (ame179_loaderLessType) {") < cfa.find("ame173_loaderMap[loader.lowercaseString]"))
check("F3 CF guard covers resourcepack/shader/datapack/world",
      all(t in cfa for t in ('isEqualToString:@"resourcepack"', 'isEqualToString:@"shader"',
                             'isEqualToString:@"datapack"', 'isEqualToString:@"world"')))
check("F4 no-data branch retries then errors",
      "Task179 search response missing data array" in cfa and
      'reason:@"missing data array"' in cfa and
      "CurseForge API returned no data array" in cfa)
modrinth = rd("Natives/installer/modpack/ModrinthAPI.m")
check("F5 Modrinth facet guard",
      "ame179_loaderLessType" in modrinth and "loader.length > 0 && !ame179_loaderLessType" in modrinth)
dlvc = rd("Natives/DownloadViewController.m")
check("F6 autoApply loader only on mod/modpack tabs",
      "ame179_loaderAwareTab" in dlvc)
check("F7 leaving loader tabs clears the loader (no cross-tab pollution)",
      "离开模组 tab 时清掉残留的加载器选择" in dlvc)

# ---------------- G. Version filter ----------------
check("G1 lower bound extended to 1.7",
      "ame179_minor < 7) continue" in dlvc)
check("G2 old-minor last-patch subsample",
      "ame179_minor <= 15" in dlvc and "ame179_versionsContainMinor" in dlvc)
check("G3 helper method defined",
      "- (BOOL)ame179_versionsContainMinor:" in dlvc)
check("G4 64-cap retired",
      "versions.count > 64" not in dlvc)
check("G5 fallback list includes 1.7.10",
      '@"1.7.10"' in dlvc)
check("G6 fallback classic minors are last-patch only",
      '@"1.15.2",' in dlvc and '@"1.14.4",' in dlvc and '@"1.12.2",' in dlvc)

# ---------------- H. Avatar main-thread guards ----------------
news = rd("Natives/LauncherNewsViewController.m")
check("H1 reloadProfileSection main-thread guard",
      "- (void)reloadProfileSection {" in news and
      news.find("![NSThread isMainThread]") > news.find("- (void)reloadProfileSection {") and
      news.find("![NSThread isMainThread]") < news.find("找到 Profile 类型的 section"))
check("H2 fetch completion dispatches to main",
      "Task179：completion 全体主线程化" in news)
check("H3 dispatch block closed",
      "});  // Task179：dispatch_async(main) 收口" in news)

# ---------------- I. Syntax gates ----------------
def strip_code(text):
    out = []
    i, n = 0, len(text)
    state = "code"
    while i < n:
        c = text[i]
        if state == "code":
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                state = "line"; i += 2; continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; i += 1; continue
            if c == "'":
                state = "chr"; i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                state = "code"; out.append("\n")
            i += 1
        elif state == "block":
            if c == "*" and i + 1 < n and text[i + 1] == "/":
                state = "code"; i += 2; continue
            i += 1
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            i += 1
        elif state == "chr":
            if c == "\\":
                i += 2; continue
            if c == "'":
                state = "code"
            i += 1
    return "".join(out)


EDITED = [
    "Natives/ctxbridges/gl_bridge.m",
    "Natives/external/gl4es/tinygl4angle.c",
    "Natives/external/vgpu/src/gl/pack/load.c",
    "Natives/external/vgpu/src/gl/loader.c",
    "Natives/external/vgpu/src/glx/hardext.c",
    "Natives/utils.m",
    "Natives/LauncherRightPanelViewController.m",
    "Natives/input_bridge_v3.m",
    "Natives/JavaLauncher.m",
    "Natives/SurfaceViewController.m",
    "Natives/installer/modpack/CurseForgeAPI.m",
    "Natives/installer/modpack/ModrinthAPI.m",
    "Natives/DownloadViewController.m",
    "Natives/LauncherNewsViewController.m",
]
bal_ok = True
for f in EDITED:
    code = strip_code(rd(f))
    b = code.count("{") - code.count("}")
    p = code.count("(") - code.count(")")
    k = code.count("[") - code.count("]")
    if b or p or k:
        bal_ok = False
        print(f"      imbalance in {f}: b={b} p={p} k={k}")
check("I1 bracket balance on all 15 edited files", bal_ok)

r = subprocess.run([sys.executable, os.path.join(REPO, "scripts/task175_syntax_gates.py")],
                   capture_output=True, text=True)
check("I2 task175 syntax gates still pass", r.returncode == 0, r.stdout[-200:] + r.stderr[-200:])

syntax_ok = True
for f in ["Natives/external/vgpu/src/gl/pack/load.c",
          "Natives/external/vgpu/src/gl/loader.c",
          "Natives/external/vgpu/src/glx/hardext.c"]:
    r = subprocess.run(
        ["gcc", "-fsyntax-only", "-DNOX11", "-DNO_GBM", "-DNOEGL", "-DDEFAULT_ES=3",
         "-DSHAREDLIB", "-DNDEBUG", "-I", "Natives/external/vgpu/include",
         "-I", "Natives/external/vgpu/src/gl", f],
        cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        syntax_ok = False
        print("      gcc errors in", f, r.stderr[:300])
check("I3 vgpu C files compile under NOEGL defines", syntax_ok)

# ---------------- Local E2E binaries ----------------
SCRIPTS = os.path.join(REPO, "scripts")
def run_bin(name, path):
    r = subprocess.run([path], capture_output=True, text=True, timeout=60)
    check(name, r.returncode == 0, r.stdout[-300:] + r.stderr[-200:])
    return r

# spoof unit test
r = subprocess.run(["bash", "-c",
                    f"cd {SCRIPTS} && python3 task179_transform.py >/dev/null && "
                    f"gcc -I . -I task179_inc -o task179_spoof_test task179_spoof_test.c "
                    f"task179_inc/string_utils.c -lpthread 2>/dev/null && ./task179_spoof_test"],
                   capture_output=True, text=True)
check("I4 spoof unit test (ES -> facade forms byte-identical, fail-safe passthroughs)",
      r.returncode == 0 and "SPOOF ALL PASS" in r.stdout, r.stdout[-200:] + r.stderr[-200:])

r = subprocess.run(["bash", "-c",
                    f"cd {SCRIPTS} && gcc -I . -I task179_inc -o task179_glgetstring_test "
                    f"task179_glgetstring_test.c task179_inc/string_utils.c -lpthread 2>/dev/null && "
                    f"./task179_glgetstring_test"],
                   capture_output=True, text=True)
check("I5 glGetString chain E2E (spoof -> normalize; renderer passthrough)",
      r.returncode == 0 and "GLGETSTRING CHAIN ALL PASS" in r.stdout,
      r.stdout[-300:] + r.stderr[-200:])

r = subprocess.run(["bash", "-c",
                    f"cd {SCRIPTS} && gcc -I task179_inc -o task179_harness "
                    f"task179_tinygl_harness.c task179_inc/string_utils.c -lpthread 2>/dev/null && "
                    f"./task179_harness"],
                   capture_output=True, text=True)
check("I6 tinygl4angle delivery harness (ES300 byte-identical upload)",
      r.returncode == 0 and "ALL CASES DELIVERED" in r.stdout,
      r.stdout[-300:] + r.stderr[-200:])

# ---------------- J. Docs ----------------
ann = json.load(open(os.path.join(REPO, "announcements.json"), encoding="utf-8"))
items = ann["announcements"]
check("J1 announcements task179 at index 2",
      len(items) > 2 and items[2]["id"] == "task179-eight-fixes-2026-09-26")
check("J2 pinned entries intact (server/task169 at 0/1)",
      items[0]["id"].startswith("server-") and items[1]["id"] == "task169-four-fixes-2026-09-25")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("J3 version.h Task179 addendum present",
      "REVISION 17 addendum (Amethyst Task 179, no bump)" in vh)

print()
print(f"RESULT: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
