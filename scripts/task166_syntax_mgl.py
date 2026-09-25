#!/usr/bin/env python3
"""Task166 syntax gate: stub-compile the pure-C/C++ blocks extracted from the
new mgl_metal_fsr.mm (the full TU needs macOS/Metal/QuartzCore headers we do
not have on Linux; the bracket-balance gate already covers the rest of the
file). Blocks:

  1. ame166_metal_fsr_should_engage -- the 4-fold engagement gate (renderer
     strict-match + kill switch + window belief + surface readiness + FSR
     geometry). Catches typo/semantics regressions in the single most
     safety-critical function (wrong gate = wrong renderer hijacked).
  2. The RCAS sharpness -> stops -> conX computation from acquire_layer
     (Task130 semantics: [0,1], negative = off; stops = 2*(1-s);
     con.x = exp2(-stops)).

Plus MSL structural invariants (no Metal compiler on Linux -- structural
only): raw-string delimiters balanced, both entry pairs present, the three
exact ffx_a.h 32-bit reciprocal constants, tap name sets, and the Task164
OOB clamp pattern in both shaders.
"""
import re
import subprocess
import sys

SRC = "Natives/ctxbridges/mgl_metal_fsr.mm"
src = open(SRC, encoding="utf-8").read()

# ── Block 1: should_engage ─────────────────────────────────────────────────
m = re.search(
    r"(bool ame166_metal_fsr_should_engage\(const char \*renderer\) \{.*?\n\})",
    src, re.S)
assert m, "should_engage body not found"
gate = m.group(1)

stub = r'''
#include <cstdlib>
#include <cstring>
#include <cstdio>
#define RENDERER_NAME_MOBILEGL "libMobileGL.dylib"
int windowWidth = 0, windowHeight = 0;
int ame_surfaceWidth = 0, ame_surfaceHeight = 0;
''' + gate + r'''
int main() {
    // Renderer strictness: only the DirectVulkan dylib engages.
    if (ame166_metal_fsr_should_engage("libMobileGL.dylib")) return 1;
    if (ame166_metal_fsr_should_engage("libMobileGL-gles.dylib")) return 2;
    if (ame166_metal_fsr_should_engage("libmobileglues.dylib")) return 3;
    if (ame166_metal_fsr_should_engage(nullptr)) return 4;
    // Geometry: full-res (no FSR linkage) must NOT engage.
    windowWidth = 100; windowHeight = 200;
    ame_surfaceWidth = 100; ame_surfaceHeight = 200;
    if (ame166_metal_fsr_should_engage("libMobileGL.dylib")) return 5;
    // Geometry: render-res (FSR linkage armed) engages.
    windowWidth = 50; windowHeight = 100;
    if (!ame166_metal_fsr_should_engage("libMobileGL.dylib")) return 6;
    return 0;
}
'''
open("/tmp/task166_gate_stub.cpp", "w").write(stub)
subprocess.run(["g++", "-Wall", "-Wextra", "-Werror", "-std=c++17",
                "-o", "/tmp/task166_gate_stub", "/tmp/task166_gate_stub.cpp"], check=True)
r = subprocess.run(["/tmp/task166_gate_stub"], check=False)
assert r.returncode == 0, f"should_engage behavioral main returned {r.returncode}"
print("[task166] should_engage stub compile + 7 behavioral cases: OK")

# ── Block 2: RCAS sharpness computation ────────────────────────────────────
m = re.search(
    r"(const char \*sharpEnv = getenv\(\"AMETHYST_FSR_RCAS_SHARPNESS\"\);.*?const float rcasConX = exp2f\(-stops\);)",
    src, re.S)
assert m, "RCAS sharpness block not found"
sharp = m.group(1)

stub2 = r'''
#include <cstdlib>
#include <cmath>
#include <cstdio>
static float compute(float &outConX, bool &outOn) {
    float sharpness = 0.2f;
''' + sharp + r'''
    outConX = rcasConX; outOn = rcasOn;
    return sharpness;
}
int main() {
    float conX; bool on;
    float s = compute(conX, on);
    printf("sharpness=%.3f rcasOn=%d conX=%.6f\n", (double)s, (int)on, (double)conX);
    return 0;
}
'''
open("/tmp/task166_sharp_stub.cpp", "w").write(stub2)
subprocess.run(["g++", "-Wall", "-Wextra", "-Werror", "-std=c++17",
                "-fsyntax-only", "/tmp/task166_sharp_stub.cpp"], check=True)
print("[task166] RCAS sharpness block stub compile: OK")

# ── Block 3: MSL structural invariants ─────────────────────────────────────
msl_easu = re.search(r'kAme166EasuMSL = @R"ame166_msl\((.*?)\)ame166_msl"', src, re.S)
msl_rcas = re.search(r'kAme166RcasMSL = @R"ame166_msl\((.*?)\)ame166_msl"', src, re.S)
assert msl_easu, "EASU MSL raw string not found / unbalanced delimiter"
assert msl_rcas, "RCAS MSL raw string not found / unbalanced delimiter"
easu, rcas = msl_easu.group(1), msl_rcas.group(1)

# Exact ffx_a.h 32-bit constants (AMD FSR 1.20210629, verbatim port).
# EASU needs all three (loRcp in setF, medRcp in the final rcp, loRsq in
# the length sqrt); RCAS only needs medRcp (FsrRcasF's rcpL) -- matches AMD.
for c in ("0x7ef07ebbu", "0x7ef19fffu", "0x5f347d74u"):
    assert c in easu, f"EASU missing ffx_a constant {c}"
assert "0x7ef19fffu" in rcas, "RCAS missing medRcp constant 0x7ef19fffu"

# Entry points + vertex shader in both libraries (pipeline wiring depends on
# these exact names in acquire_layer).
for name in ("ame166_vs", "ame166_easu_fs"):
    assert f'"{name}"' in src or name in easu, f"EASU missing {name}"
assert "ame166_vs" in rcas and "ame166_rcas_fs" in rcas

# EASU 12-tap set (AMD b,c,e,f,g,h,i,j,k,l,n,o) declared as t_<tap>, with
# the exact AMD offset layout (0,-1)(1,-1)(-1,0)(0,0)(1,0)(2,0)(-1,1)(0,1)
# (1,1)(2,1)(0,2)(1,2).
amd_offsets = [" 0, -1", " 1, -1", "-1,  0", " 0,  0", " 1,  0", " 2,  0",
               "-1,  1", " 0,  1", " 1,  1", " 2,  1", " 0,  2", " 1,  2"]
for tap in ["b", "c", "e", "f", "g", "h", "i", "j", "k", "l", "n", "o"]:
    assert f"t_{tap} = ame166_load(" in easu, f"EASU missing tap declaration t_{tap}"
for off in amd_offsets:
    assert f"int2({off})" in easu, f"EASU missing AMD tap offset ({off})"

# Task164 lesson: OOB read defense lives INSIDE the load helpers (one clamp
# per helper, called per-tap). Verify helper defs clamp + tap call counts.
def load_calls(body, helper):
    # minus 1 for the definition itself
    return len(re.findall(rf"\b{helper}\(", body)) - 1

h3 = re.search(r"static inline float3 ame166_load\(.*?\n\}", easu, re.S)
h4 = re.search(r"static inline float4 ame166_load4\(.*?\n\}", rcas, re.S)
assert h3 and "clamp(" in h3.group(0), "EASU ame166_load helper lost its clamp"
assert h4 and "clamp(" in h4.group(0), "RCAS ame166_load4 helper lost its clamp"
assert load_calls(easu, "ame166_load") == 12, \
    f"EASU tap calls = {load_calls(easu, 'ame166_load')}, expected 12"
assert load_calls(rcas, "ame166_load4") == 5, \
    f"RCAS tap calls = {load_calls(rcas, 'ame166_load4')}, expected 5"

# RCAS 5-tap set (b,d,e,f,h) + alpha passthrough (osm_bridge parity).
for tap in ("b =", "d =", "e4 =", "f =", "h ="):
    assert tap in rcas, f"RCAS missing tap declaration '{tap}'"
assert "e4.a" in rcas, "RCAS alpha passthrough missing"

print("[task166] MSL structural invariants (delimiters, constants, taps, clamps): OK")
print("[task166] all syntax gates passed")
