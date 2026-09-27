#!/usr/bin/env python3
"""Task 183 verification: device-feedback four-root-cause round (59d4b48 logs).

User symptoms on the Task-182 build (all three logs Commit: 59d4b48, Task182
anchors present = genuinely on the fixed build):
  1. ANGLE black screen  -> spvc-shim registry exhaustion (96 slots vs 392
     live contexts at storm peak; 584/782 shaders silently got DESKTOP GLSL
     330 -> ANGLE ES3.0 line-1 errors -> "Failed to load required shader
     programs" -> black frames at 58fps) + OIT dynamic output-array indexing
     + clouds isamplerBuffer/GL_EXT_texture_buffer.
  2. vgpu white screen   -> GLSLHeader replaced #version 120 with hardcoded
     "#version 320 es" regardless of the (correct) capability probe.
  3. JIT second-menu hang (1 of 3 sessions) -> last completion dependency in
     the launch chain: UIKit_launchMinecraftSurfaceVC's UIView completion.
  4. Right-Shift still dead -> Task181 stopped future washing but never
     repaired the washed binding (sneak sat at left.shift with marker present).

This verifier checks all four fixes + anchors + syntax gates + unit tests.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []
COUNT = 0


def check(name, cond, detail=""):
    global COUNT
    COUNT += 1
    if cond:
        print(f"  ok: {name}")
    else:
        print(f"  FAIL: {name} {detail}")
        FAILS.append(name)


def read(p):
    with open(os.path.join(REPO, p), encoding="utf-8", errors="replace") as f:
        return f.read()


def main():
    print("== A. spvc_shim.c (ANGLE A/B/C families) ==")
    s = read("Natives/spvc_shim.c")
    check("A1 registry capacity 96 -> 1024",
          "#define AME175_REGISTRY_MAX 1024" in s and "AME175_REGISTRY_MAX 96" not in s)
    check("A2 ctx eviction (oldest by seq) present",
          "evicting oldest" in s and "ame183_seq_counter" in s)
    check("A3 fallback registry 256 -> 1024", "#define AME176_FALLBACK_MAX 1024" in s)
    check("A4 B-family fix fn present",
          "static char *ame183_fix_output_arrays" in s)
    check("A5 C-family fix fn present",
          "static char *ame183_emulate_texture_buffers" in s)
    check("A6 sanitize entry present", "static char *ame183_sanitize_essl" in s)
    check("A7 sanitize hooked after rewrite (both paths)",
          s.count("ame183_sanitize_essl(ame176_final)") == 1)
    check("A8 skip logging on silent branches",
          s.count("ame183_skip_log(") >= 4 and "compiler unregistered" in s
          and "ctx missing or ir mismatch" in s)
    check("A9 texelFetch fold constant width 255/8 (matches 2D bridge)",
          "& 255, (%.*s) >> 8" in s)
    check("A10 no raw memmem (Darwin undeclared)",
          re.search(r"[^_a-zA-Z0-9]memmem\(", s) is None)
    check("A11 marker-based decl protection",
          "@@A183OUT%d@@" in s)
    check("A12 constant-index copies inserted before main close",
          "constant-index fragment-output copies" in s)

    print("== B. tinygl4angle.c (leak detector + texbuffer bridge) ==")
    t = read("Natives/external/gl4es/tinygl4angle.c")
    check("B1 gles_glBindTexture declared",
          "void(*gles_glBindTexture)(GLenum target, GLuint texture);" in t)
    check("B2 glBindTexture export with GL_TEXTURE_BUFFER retarget",
          "void glBindTexture(GLenum target, GLuint texture)" in t
          and "if (target == GL_TEXTURE_BUFFER) target = GL_TEXTURE_2D;" in t)
    check("B3 texbuffer PBO bridge present",
          "ame183_texbuffer_to_2d" in t and "GL_PIXEL_UNPACK_BUFFER" in t)
    check("B4 glTexBuffer routes TEXTURE_BUFFER to bridge",
          "if (target == GL_TEXTURE_BUFFER) {\n        ame183_texbuffer_to_2d" in t)
    check("B5 bridge width 256 (aligned with shader fold)",
          "int width = 256;" in t)
    check("B6 desktop-leak detector in glShaderSource",
          "DESKTOP source reached GLES upload" in t)
    check("B7 R32I mapping present (clouds integer data)",
          "0x8235" in t)

    print("== C. vgpu shaderconv.c (white screen) ==")
    v = read("Natives/external/vgpu/src/gl/pack/shaderconv.c")
    check("C1 GLSLHeader capability-driven version",
          "ame183_ver" in v and '"#version 300 es"' in v and '"#version 310 es"' in v)
    check("C2 replace uses probed version not fixed new_version",
          "pot = replace_common(old_version, ame183_ver, source, 1);" in v)
    check("C3 probe-follow log anchor",
          "GLSLHeader version follows capability probe" in v)
    check("C4 glsl300es branch now yields 300 es",
          re.search(r"glsl300es\)\{\s*ame183_ver = \"#version 300 es\"", v) is not None)

    print("== D. ios_uikit_bridge.m (JIT residual completion) ==")
    u = read("Natives/ios_uikit_bridge.m")
    check("D1 launch: no completion-wrapped root swap",
          "completion:^(BOOL b){\n            [window resignKeyWindow];" not in u)
    check("D2 launch: synchronous root swap present",
          "window.rootViewController = [[SurfaceViewController alloc] initWithMetadata:metadata];"
          in u and "[window makeKeyAndVisible];" in u)
    check("D3 launch: fade fire-and-forget (no completion arg)",
          re.search(r"animateWithDuration:0\.2 animations:\^\{\n            window\.alpha = 1;\n        \}\];", u) is not None)
    check("D4 return: synchronous swap present",
          "Task183 returning to split view (synchronous root swap)" in u)
    check("D5 launch anchor log",
          "Task183 launching SurfaceViewController (synchronous root swap" in u)
    check("D6 tmpRootVC guarded (no clobber of preserved root)",
          "if (tmpRootVC == nil) {" in u)

    print("== E. JIT anchor logs (RightPanel + NavCtrl) ==")
    rp = read("Natives/LauncherRightPanelViewController.m")
    nv = read("Natives/LauncherNavigationController.m")
    check("E1 RightPanel wait-completed anchor",
          "Task183 wait-completed block entered on main" in rp)
    check("E2 RightPanel invoking-handler anchor",
          "Task183 invoking launch handler" in rp)
    check("E3 NavCtrl wait-completed anchor",
          "[NavCtrl] Task183 wait-completed block entered on main" in nv)
    check("E4 NavCtrl invoking-handler anchor",
          "[NavCtrl] Task183 invoking launch handler" in nv)
    check("E5 RightPanel still dismisses with completion:nil (Task182 intact)",
          rp.count("dismissViewControllerAnimated:YES completion:nil") >= 2)

    print("== F. input_bridge_v3.m (Shift v2 restore) ==")
    ib = read("Natives/input_bridge_v3.m")
    check("F1 v2 marker path defined",
          "amethyst-keybinds-v2" in ib)
    check("F2 v2 gated on v1 presence (damage cohort only)",
          "ame183_v2Needed = ame181_alreadySanitized;" in ib)
    check("F3 new-format restore (left.shift -> right.shift)",
          '"key.keyboard.left.shift"' in ib and '"key.keyboard.right.shift"' in ib)
    check("F4 old-numeric restore (42 -> 54)",
          'isEqualToString:@"42"]' in ib and 'ame183_target = @"54"' in ib)
    check("F5 restore counts as repair (write-back pipeline)",
          'nsline = [NSString stringWithFormat:@"key_key.sneak:%@", ame183_target];' in ib)
    check("F6 v2 marker written post-evaluation",
          "keybind v2 marker written" in ib)
    check("F7 restore log anchor",
          "[Task183] keybind v2 RESTORE sneak" in ib)
    check("F8 Task181 v1 logic intact (one-shot wash preserved)",
          "ame181_alreadySanitized &&\n                            ![value isEqualToString:" in ib)

    print("== G. Syntax gates + unit tests ==")
    r = subprocess.run(
        ["bash", "-c",
         "cd %s && gcc -fsyntax-only -Wall -Werror=implicit-function-declaration "
         "Natives/spvc_shim.c" % REPO],
        capture_output=True, text=True)
    check("G1 spvc_shim.c gcc syntax gate", r.returncode == 0,
          r.stderr[-300:])

    r = subprocess.run(
        ["bash", "-c",
         "cd %s/scripts && python3 task179_transform.py >/dev/null 2>&1 && "
         "gcc -fsyntax-only -I . -I task179_inc -Wall -Wno-unused-variable "
         "task179_inc/tinygl4angle_harness.c task179_inc/string_utils.c" % REPO],
        capture_output=True, text=True)
    check("G2 tinygl4angle.c harness syntax gate (post-transform)", r.returncode == 0,
          r.stderr[-300:])

    r = subprocess.run(
        ["bash", "-c",
         "cd %s/scripts && gcc -fsanitize=address -g -o /tmp/task183_v "
         "task183_sanitize_test.c -lpthread -ldl 2>/dev/null && "
         "ASAN_OPTIONS=detect_leaks=0 /tmp/task183_v 2>/dev/null | tail -1" % REPO],
        capture_output=True, text=True)
    check("G3 sanitize unit test (ASAN) ALL PASS",
          r.returncode == 0 and "SANITIZE TEST ALL PASS" in r.stdout,
          r.stdout[-200:] + r.stderr[-200:])

    r = subprocess.run(
        ["bash", "-c",
         "cd %s/scripts && gcc -O2 -o /tmp/task183_v2 task183_sanitize_test.c "
         "-lpthread -ldl 2>/dev/null && /tmp/task183_v2 2>/dev/null | tail -1" % REPO],
        capture_output=True, text=True)
    check("G4 sanitize unit test (O2) ALL PASS",
          r.returncode == 0 and "SANITIZE TEST ALL PASS" in r.stdout,
          r.stdout[-200:] + r.stderr[-200:])

    print("== H. Objective-C bracket balance (delta vs HEAD) ==")
    for f in ["Natives/ios_uikit_bridge.m",
              "Natives/LauncherRightPanelViewController.m",
              "Natives/LauncherNavigationController.m",
              "Natives/input_bridge_v3.m"]:
        src = read(f)
        bal = src.count("{") - src.count("}")
        par = src.count("(") - src.count(")")
        # 存量基线对拍：字符串/注释里的括号属文件固有形态（input_bridge_v3.m
        # 的 parens=-1 为 HEAD 既有），本轮引入的差值必须为 0。
        r = subprocess.run(
            ["bash", "-c", "cd %s && git show HEAD:%s" % (REPO, f)],
            capture_output=True, text=True)
        hbal = hpar = 0
        if r.returncode == 0:
            hbal = r.stdout.count("{") - r.stdout.count("}")
            hpar = r.stdout.count("(") - r.stdout.count(")")
        check(f"H balance {os.path.basename(f)} braces={bal}(d{bal - hbal}) parens={par}(d{par - hpar})",
              bal - hbal == 0 and par - hpar == 0)

    print()
    print(f"RESULT: {COUNT - len(FAILS)}/{COUNT} passed")
    if FAILS:
        print("FAILED:", FAILS)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
