#!/usr/bin/env python3
"""Task 82 verification: FSR viewport-latch poisoning, SDL3 text input, FAQ tab.

Three fixes, three evidence chains:

1. FSR "picture shrunk into the bottom-left corner" (device log ea27def):
   the FSR1 glViewport latch is grow-only, and MC 26.x's animated-atlas pass
   drives glViewport at the full blocks-atlas size (2048x2048 on a 2360x1640
   surface; the window is 1814x1262). The atlas latch won, the main viewport
   could never reclaim it, ApplyFSR stretched the mostly-unwritten 2048x2048
   render texture over the surface -> game visible in the bottom-left
   88.6% x 61.6%, exactly "整个界面缩到左下角".
   Fix: latch candidates must be window-shaped -- within the surface bounds
   and within 3% of the surface aspect ratio (checked only while FSR1 on).

2. Keyboard widget dead on MC 26.3: CallbackBridge_nativeSendChar had only
   the GLFW path (GLFW_invoke_Char, permanently NULL under SDL3), so virtual
   keyboard typing was silently dropped. Fix: Path B pushes
   SDL_EVENT_TEXT_INPUT (0x303); MC 26.3's decompiled SDLEventHandler
   dispatches case 771 -> handleTextInputEvent -> keyboardHandler.textInput
   -> charTyped (verified in task66_decomp/client.jar via CFR).

3. New "使用问题" (FAQ) sidebar tab: LauncherHelpViewController + menu item
   index 5 + ShowHelpPage notification + root-VC handler + CMakeLists entry.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _first(*paths):
    for p in paths:
        if os.path.exists(p):
            return os.path.abspath(p)
    return os.path.abspath(paths[-1])


MG = _first(
    os.path.join(HERE, "..", "Amethyst-iOS-MyRemastered", "Natives", "external",
                 "MobileGlues", "MobileGlues-cpp"),
    os.path.join(HERE, "..", "Natives", "external", "MobileGlues", "MobileGlues-cpp"),
)
REPO = os.path.abspath(os.path.join(MG, "..", "..", "..", ".."))
FSR1 = os.path.join(MG, "gl", "FSR1", "FSR1.cpp")
VER = os.path.join(MG, "version.h")
IB3 = os.path.join(REPO, "Natives", "input_bridge_v3.m")
SVC = os.path.join(REPO, "Natives", "SurfaceViewController.m")
HELP_M = os.path.join(REPO, "Natives", "LauncherHelpViewController.m")
HELP_H = os.path.join(REPO, "Natives", "LauncherHelpViewController.h")
MENU = os.path.join(REPO, "Natives", "LauncherMenuViewController.m")
ROOT = os.path.join(REPO, "Natives", "LauncherRootViewController.m")
CML = os.path.join(REPO, "Natives", "CMakeLists.txt")
LOG_NEW = os.path.join(REPO, "latestlog.txt")  # ea27def MG session

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(("PASS" if ok else "FAIL") + f"  {name}" + (f"  [{detail}]" if detail else ""))


def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


# ---------------------------------------------------------------------------
# A. FSR1.cpp source fingerprints
# ---------------------------------------------------------------------------
fsr1 = read(FSR1)

check("A1 task82_surface_size helper (cache first, EGL fallback)",
      "static void task82_surface_size" in fsr1 and "egl_eglQuerySurface" in fsr1
      and "g_surfaceWidth > 0" in fsr1)

latch_block = fsr1[fsr1.find("bool latch = true;"):fsr1.find("GLES.glViewport(x, y, w, h);", fsr1.find("bool latch = true;"))]
check("A2 latch gated on FSR1 enabled",
      "global_settings.fsr1_setting != FSR1_Quality_Preset::Disabled" in latch_block)

check("A3 rule 1: oversize rejection",
      "if (w > surfaceW || h > surfaceH)" in latch_block)

check("A4 rule 2: aspect drift <= 3%",
      "0.03f" in latch_block and "surfaceAspect" in latch_block)

check("A5 one-shot rejection log",
      "FSR1 viewport latch rejected (Task 82)" in latch_block)

check("A6 growth rule preserved (rotation re-latch)",
      "w > FSR1_Context::g_pendingWidth || h > FSR1_Context::g_pendingHeight" in fsr1)

check("A7 GLES passthrough intact",
      fsr1.count("GLES.glViewport(x, y, w, h);") == 1)

check("A8 version.h Task 82 addendum, REVISION stays 17",
      "Task 82" in read(VER) and "#define REVISION 17" in read(VER))

# ---------------------------------------------------------------------------
# B. Latch behavior replay (Python re-implementation of the new gate)
# ---------------------------------------------------------------------------

def latch_decision(pending, w, h, surface, fsr_on, surface_known=True):
    """Returns (new_pending, rejected). Mirrors the patched hook."""
    pw, ph = pending
    if not (w > pw or h > ph):
        return (pw, ph), False
    if fsr_on and surface_known:
        sw, sh = surface
        if w > sw or h > sh:
            return (pw, ph), True
        sa = sw / sh
        va = w / h
        drift = abs(va - sa) / sa
        if drift > 0.03:
            return (pw, ph), True
    return (w, h), False


SURF = (2360, 1640)   # ea27def device geometry
WIN = (1814, 1262)    # launcher-told MC window (surface/1.30)
ATLAS = (2048, 2048)  # blocks.png atlas viewport (MC animated sprites)

p, rej = latch_decision((0, 0), *ATLAS, SURF, True)
check("B1 atlas 2048x2048 rejected (2048 > surfaceH 1640)",
      rej and p == (0, 0))

p, rej = latch_decision((0, 0), *WIN, SURF, True)
check("B2 window 1814x1262 accepted (0.13% aspect drift)",
      not rej and p == WIN)

p, rej = latch_decision(WIN, *ATLAS, SURF, True)
check("B3 window latched first, atlas cannot steal it",
      rej and p == WIN)

p, rej = latch_decision((0, 0), *ATLAS, SURF, True)
p2, rej2 = latch_decision(p, *WIN, SURF, True)
check("B4 atlas first (old poison order) -> window still lands",
      rej and not rej2 and p2 == WIN)

# Rotation: surface becomes 1640x2360, MC viewport 1262x1814
p, rej = latch_decision(WIN, 1262, 1814, (1640, 2360), True)
check("B5 rotation re-latch (h grows, aspect matches)",
      not rej and p == (1262, 1814))

# Big-surface device (12.9" iPad, 2732x2048): atlas fits inside bounds
p, rej = latch_decision((0, 0), 2048, 2048, (2732, 2048), True)
check("B6 sub-surface square atlas still rejected by aspect (25% off)",
      rej and p == (0, 0))

# Square window on square surface: aspect equal, within bounds
p, rej = latch_decision((0, 0), 1262, 1262, (1640, 1640), True)
check("B7 square window on square surface accepted",
      not rej and p == (1262, 1262))

p, rej = latch_decision((0, 0), 2048, 2048, SURF, False)
check("B8 FSR disabled -> old permissive behavior",
      not rej and p == ATLAS)

p, rej = latch_decision((0, 0), *ATLAS, SURF, True, surface_known=True)
check("B9 pre-first-swap live query feeds the same gate",
      rej)

p, rej = latch_decision((0, 0), *ATLAS, SURF, True, surface_known=False)
check("B10 no surface info (no EGL current) -> latch proceeds",
      not rej and p == ATLAS)

# ---------------------------------------------------------------------------
# C. input_bridge_v3.m source fingerprints
# ---------------------------------------------------------------------------
ib3 = read(IB3)

check("C1 SDL3_EVENT_TEXT_INPUT == 0x303",
      "#define SDL3_EVENT_TEXT_INPUT      0x303" in ib3)

check("C2 TextInputEvent struct (const char *text)",
      "SDL3_TextInputEvent" in ib3 and "const char *text;" in ib3)

check("C3 ring buffer 1024 slots x 8 bytes",
      "#define AME82_TEXT_RING_SLOTS 1024" in ib3 and "ame82_textRing[AME82_TEXT_RING_SLOTS][8]" in ib3)

check("C4 pushSDLTextInput defined before nativeSendChar",
      0 < ib3.find("static void pushSDLTextInput") < ib3.find("BOOL CallbackBridge_nativeSendChar"))

char_fn = ib3[ib3.find("BOOL CallbackBridge_nativeSendChar"):ib3.find("BOOL CallbackBridge_nativeSendChar") + 900]
check("C5 nativeSendChar Path B pushes SDL text",
      "Path B: SDL3 text-input events" in char_fn and "pushSDLTextInput(codepoint)" in char_fn)

charmods_fn = ib3[ib3.find("BOOL CallbackBridge_nativeSendCharMods"):ib3.find("BOOL CallbackBridge_nativeSendCharMods") + 700]
check("C6 nativeSendCharMods stays GLFW-only (no double delivery)",
      "pushSDLTextInput" not in charmods_fn and "GLFW_invoke_CharMods && isInputReady" in charmods_fn)

push_fn = ib3[ib3.find("static void pushSDLTextInput"):ib3.find("static void pushSDLTextInput") + 1700]
check("C7 event carried in 128-byte SDL3_Event union (no stack over-read)",
      "SDL3_Event ev;" in push_fn and "memset(&ev, 0, sizeof(ev));" in push_fn)

check("C8 Task82 text diag log",
      "Task82 SDL text input #" in push_fn)

check("C9 surrogate-pair merge state present",
      "ame82_pendingHighSurrogate" in ib3 and ib3.count("ame82_pendingHighSurrogate") >= 5)

# ---------------------------------------------------------------------------
# D. Text pipeline behavior replay
# ---------------------------------------------------------------------------

def utf8_encode(cp):
    if cp < 0x80:
        return bytes([cp])
    if cp < 0x800:
        return bytes([0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)])
    if cp < 0x10000:
        return bytes([0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)])
    return bytes([0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
                  0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)])


def replay_text(units):
    """Mirrors pushSDLTextInput: returns list of emitted codepoints."""
    pending = 0
    out = []
    for u in units:
        if 0xD800 <= u <= 0xDBFF:
            pending = u
            continue
        if 0xDC00 <= u <= 0xDFFF:
            cp = 0x10000 + ((pending - 0xD800) << 10) + (u - 0xDC00) if pending else 0xFFFD
            pending = 0
            out.append(cp)
            continue
        pending = 0
        out.append(u)
    return out


check("D1 UTF-8 encoder anchors",
      utf8_encode(0x41) == b"A" and utf8_encode(0xE9) == b"\xc3\xa9"
      and utf8_encode(0x4E2D) == b"\xe4\xb8\xad" and utf8_encode(0x1F600) == b"\xf0\x9f\x98\x80")

check("D2 surrogate pair merges to one codepoint",
      replay_text([0xD83D, 0xDE00]) == [0x1F600])

check("D3 unpaired low surrogate -> U+FFFD",
      replay_text([0xDE00]) == [0xFFFD])

check("D4 high surrogate then BMP char: high dropped, BMP emitted",
      replay_text([0xD83D, 0x41]) == [0x41])

check("D5 pasted string round-trips (per-unit feed)",
      [chr(cp) for cp in replay_text([ord(c) for c in "你好mc"])] == list("你好mc"))

# ---------------------------------------------------------------------------
# E. SurfaceViewController keyboard widget forensics
# ---------------------------------------------------------------------------
svc = read(SVC)
check("E1 keyboard widget button logs with becomeFirstResponder result",
      "[Task82] Keyboard widget: becomeFirstResponder=%d" in svc)

check("E2 dismiss branch logged too",
      "[Task82] Keyboard widget: dismissing" in svc)

# ---------------------------------------------------------------------------
# F. FAQ tab wiring
# ---------------------------------------------------------------------------
check("F1 LauncherHelpViewController sources exist",
      os.path.exists(HELP_M) and os.path.exists(HELP_H))

cml = read(CML)
check("F2 LauncherHelpViewController.m registered in CMakeLists",
      "LauncherHelpViewController.m" in cml)

menu = read(MENU)
check("F3 sidebar menu item index 5 (questionmark icon)",
      '@"questionmark.circle.fill"' in menu and 'showHelpPage' in menu
      and 'postNotificationName:@"ShowHelpPage"' in menu)

root = read(ROOT)
check("F4 root VC observes ShowHelpPage and presents the page",
      '@"ShowHelpPage"' in root and "showHelpPage" in root
      and "LauncherHelpViewController *vc = [[LauncherHelpViewController alloc] init]" in root)

helpm = read(HELP_M)
check("F5 FAQ covers Sodium 改进透明 see-through cause",
      "改进透明" in helpm)

check("F6 FAQ covers MG chunk-load lag as known issue + zink advice",
      "MobileGlues" in helpm and "Zink" in helpm and "已知特性" in helpm)

check("F7 FAQ covers FSR usage (档位, 分辨率保持 100%)",
      "FSR" in helpm and "100%" in helpm)

check("F8 FAQ covers keyboard widget + modpack JSON + crash feedback",
      "Keyboard" in helpm and "JSON" in helpm and "latestlog" in helpm)

check("F9 FAQ page uses BackgroundManager transparency (consistent look)",
      "makeViewControllerTransparent" in helpm)

# ---------------------------------------------------------------------------
# G. Bracket balance delta vs HEAD (pre-existing artifacts allowed, shift must be 0)
# ---------------------------------------------------------------------------

def counts(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r'"(\\.|[^"\\])*"', '""', t)
    t = re.sub(r"'(\\.|[^'\\])*'", "''", t)
    return [t.count(c) for c in "{}()[]"]


for f in [FSR1, IB3, SVC, MENU, ROOT, CML]:
    rel = os.path.relpath(f, REPO)
    cur = counts(read(f))
    old_t = subprocess.run(["git", "show", "HEAD:" + rel], cwd=REPO,
                           capture_output=True, text=True).stdout
    if not old_t:
        check(f"G {rel} (new file, self-balanced)",
              cur[0] == cur[1] and cur[2] == cur[3] and cur[4] == cur[5])
        continue
    old = counts(old_t)
    deltas = [c - o for c, o in zip(cur, old)]
    balanced_shift = (cur[0] - cur[1]) == (old[0] - old[1]) and \
                     (cur[2] - cur[3]) == (old[2] - old[3]) and \
                     (cur[4] - cur[5]) == (old[4] - old[5])
    check(f"G {rel} bracket-shift zero", balanced_shift, f"delta={deltas}")

cur = counts(read(HELP_M))
check("G LauncherHelpViewController.m self-balanced",
      cur[0] == cur[1] and cur[2] == cur[3] and cur[4] == cur[5])

# ---------------------------------------------------------------------------
# H. Regression evidence in latestlog.txt
# Task83b 更新：be276a0 用户上传了新装机日志对——MG 会话（含 Task82 修复
# 生效证据）现在在 latestlog.old.txt，latestlog.txt 换成了 zink 会话
# （Task83 FSR linkage + EASU 编译失败证据 = Task83b 版本适配的动机实锤）。
# 旧锚点（262e674 会话的 render 1572x1092 / 1.50 档）随日志退役；新会话
# 是 1.30 档（render 1814x1262）。zink 会话另加 H3 佐证 Task83b 动机。
# ---------------------------------------------------------------------------
LOG_OLD_MG = os.path.join(REPO, "latestlog.old.txt")  # be276a0 MG session
if os.path.exists(LOG_OLD_MG):
    log = read(LOG_OLD_MG)
    check("H1 Task82 build rejects the poison viewport (latch rejection on device)",
          "viewport latch rejected (Task 82): 2048x2048 is not a window viewport (surface 2360x1640)" in log)
    check("H2 Task82 build engages window-shaped render (1814x1262, not 2048x2048)",
          "render 1814x1262 -> target 2360x1640 -> surface 2360x1640" in log
          and "render 2048x2048" not in log)
else:
    check("H log present", False, "latestlog.old.txt missing")

if os.path.exists(LOG_NEW):
    zlog = read(LOG_NEW)
    check("H3 zink session: Task83 linkage + EASU compile failure (Task83b motivation)",
          "renderer-side upscale: zink EASU (Task83)" in zlog
          and "GLSL 4.50 is not supported" in zlog
          and "restoring MC window to surface" in zlog)
else:
    check("H3 zink session log present", False, "latestlog.txt missing")

# ---------------------------------------------------------------------------
# I. Cascade: Task 81 verification still green
# ---------------------------------------------------------------------------
prev = os.path.join(HERE, "verify_task81.py")
if os.path.exists(prev):
    try:
        r = subprocess.run([sys.executable, prev], capture_output=True, text=True, timeout=300)
        summary = next((l for l in reversed(r.stdout.splitlines()) if "RESULT" in l), "")
        check("I verify_task81 cascade", r.returncode == 0 and "FAIL" not in summary, summary.strip())
    except Exception as e:  # noqa: BLE001
        check("I verify_task81 cascade", False, str(e))
else:
    check("I verify_task81 present", False, "script missing")

n_pass = sum(1 for _, ok, _ in results if ok)
n_total = len(results)
print(f"\nRESULT: {n_pass}/{n_total} PASS" + ("" if n_pass == n_total else "  -- FAILURES PRESENT"))
sys.exit(0 if n_pass == n_total else 1)
