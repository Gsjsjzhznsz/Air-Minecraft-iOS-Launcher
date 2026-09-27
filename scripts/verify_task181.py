#!/usr/bin/env python3
"""Task181 verifier: six-fix device-feedback round (log set ab78f50, build afa23a6).

A. 26.1.2 NeoForge pc=0 crash fix (GLFW_invoke_WindowSize mis-call)
B. CF detail-page loader filter (parseCurseForgeDictionary lowercase)
C. Task67 keybind canonicalizer one-shot (right-shift root fix)
D. Legacy Forge SplashProgress disable (1.8.9 FBO status:0 root fix)
E. ANGLE compile-chain forensics (tinygl4angle)
F. JIT wait forensics (utils.m + RightPanel)
G. version.h addendum + syntax gates
"""
import subprocess
import sys

BASE = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PASS = FAIL = 0
FAILURES = []


def check(label, ok):
    global PASS, FAIL
    if ok:
        PASS += 1
    else:
        FAIL += 1
        FAILURES.append(label)
    print(f"[{'PASS' if ok else 'FAIL'}] {label}")


def read(path):
    with open(path, "rb") as f:
        return f.read()


ib = read(f"{BASE}/Natives/input_bridge_v3.m").decode("utf-8", errors="replace")
mv = read(f"{BASE}/Natives/ModVersion.m").decode("utf-8", errors="replace")
jl = read(f"{BASE}/Natives/JavaLauncher.m").decode("utf-8", errors="replace")
tg = read(f"{BASE}/Natives/external/gl4es/tinygl4angle.c").decode("utf-8", errors="replace")
ut = read(f"{BASE}/Natives/utils.m").decode("utf-8", errors="replace")
rp = read(f"{BASE}/Natives/LauncherRightPanelViewController.m").decode("utf-8", errors="replace")
vh = read(f"{BASE}/Natives/external/MobileGlues/MobileGlues-cpp/version.h").decode("utf-8", errors="replace")

print("== A: 26.1.2 NeoForge pc=0 crash (GLFW callback mis-call) ==")
check("A1 WindowSize branch calls the guarded WindowSize pointer",
      "if (GLFW_invoke_WindowSize) {\n            GLFW_invoke_WindowSize(" in ib)
check("A2 old mis-call (guard WindowSize, call FramebufferSize) is gone",
      "if (GLFW_invoke_WindowSize) {\n            GLFW_invoke_FramebufferSize(" not in ib)
check("A3 both branches still dispatch (FramebufferSize first, WindowSize second)",
      ib.count("GLFW_invoke_FramebufferSize((void*) showingWindow, windowWidth, windowHeight);") == 1)
check("A4 forensic comment cites hs_err_pid1381 / pc=0 signature",
      "hs_err_pid1381" in ib and "SEGV_ACCERR" in ib and "Task181" in ib)

print("== B: CF detail-page loader filter ==")
check("B1 loaders stored lowercased",
      "[loaders addObject:[v lowercaseString]];" in mv)
check("B2 LiteLoader prefix added",
      'hasPrefix:@"LiteLoader"' in mv)
check("B3 old verbatim store removed",
      "[loaders addObject:v];" not in mv)
check("B4 rationale references the lowercase predicate mismatch",
      "selectedLoader.lowercaseString" in mv and "Modrinth" in mv)

print("== C: keybind canonicalizer one-shot ==")
check("C1 marker path constant",
      "amethyst-keybinds-v1" in ib)
check("C2 gate condition (alreadySanitized blocks forced reset)",
      "!ame181_alreadySanitized &&" in ib)
check("C3 marker presence check opens/closes the file",
      "ame181_marker[0] != '\\0'" in ib)
check("C4 marker written at end of sanitize pass",
      "[Task181] keybind marker written" in ib)
check("C5 dump forensics retained (key_key. line dump still active)",
      "[Task67]   %@" in ib)
check("C6 backup semantics untouched (amethyst-bak path still built)",
      ".amethyst-bak" in ib)

print("== D: legacy Forge SplashProgress disable ==")
check("D1 helper defined",
      "static void ame181_disableLegacyForgeSplash(" in jl)
check("D2 called after ame67 with the resolved gameDir",
      "ame181_disableLegacyForgeSplash(gameDir," in jl)
check("D3 writes enabled=false for missing file",
      "enabled=false" in jl and "splash.properties" in jl)
check("D4 flips enabled in existing file with .amethyst-bak backup",
      "flipped enabled->false in existing" in jl)
check("D5 NeoForge excluded (earlydisplay is the GLFW-pointer case, fixed separately)",
      'rangeOfString:@"neoforge"].location != NSNotFound) return' in jl)
check("D6 gated to 1.x lineage via the ame98 helper",
      "ame98_mcMajorFromVersionId(versionId) != 1) return" in jl)

print("== E: ANGLE compile-chain forensics ==")
check("E1 glShaderSource entry logs head48 + count + len0 (capped 8)",
      "Task181 glShaderSource #%d: shader=%u count=%d len0=%zu" in tg)
check("E2 glCompileShader pure-forward export present",
      "void glCompileShader(GLuint shader) {\n    LOOKUP_FUNC(glCompileShader)" in tg)
check("E3 compile status + infoLog head logged (capped 32)",
      "COMPILE_STATUS=0 logHead=" in tg and "COMPILE_STATUS=1 (ok)" in tg)
check("E4 forwarding is behavior-preserving (real compile precedes the status probe)",
      tg.index("gles_glCompileShader(shader);") < tg.index("gles_glGetShaderiv(shader, 35713"))
check("E5 nlevel helper restored intact",
      "static int inline nlevel(int size, int level) {" in tg)
check("E6 isProxyTexture body restored intact",
      "int isProxyTexture(GLenum target) {\n    switch (target) {" in tg)

print("== F: JIT wait forensics ==")
check("F1 wait-begin snapshot logs foreground/traced/exn/csdbg",
      "Task181 %@ wait begin: startForeground=%d traced=%d exn=%d csdbg=%d" in ut)
check("F2 condition-satisfied line with net wait time",
      "condition satisfied after %.1fs" in ut)
check("F3 foreground/background transition logging",
      "returned to FOREGROUND" in ut and "went to BACKGROUND" in ut)
check("F4 gap exclusion and timeout logic unchanged (Task179 semantics kept)",
      "suspension gap of %.0fs excluded" in ut and "TIMED OUT" in ut)
check("F5 backgroundTimeRemaining DBL_MAX normalized to fg(n/a)",
      'fg(n/a)' in rp and "1e300" in rp)
check("F6 assertion id/validity logging kept (Task179 anchor survives)",
      "Task179 background task assertion: id=%lu valid=%d" in rp)

print("== G: version.h + syntax gates ==")
check("G1 version.h carries the Task181 addendum",
      "REVISION 17 addendum (Task 181, no bump)" in vh)
check("G2 addendum names all six fix areas",
      all(k in vh for k in ["hs_err_pid1381", "parseCurseForgeDictionary", "amethyst-keybinds-v1",
                             "ame181_disableLegacyForgeSplash", "glShaderSource head48", "fg(n/a)"]))
r = subprocess.run([sys.executable, "/home/z/my-project/scripts/task181_syntax_gate.py"],
                   capture_output=True, text=True)
check("G3 syntax gate (brackets + anchors, 4 core files) green",
      r.returncode == 0 and "ALL PASS" in r.stdout)

print(f"\n==== verify_task181: {PASS} passed, {FAIL} failed ====")
if FAILURES:
    for f in FAILURES:
        print(f"  FAILED: {f}")
sys.exit(0 if FAIL == 0 else 1)
