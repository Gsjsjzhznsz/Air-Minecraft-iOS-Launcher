#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 140 verifier: renderer layering rebuild + Mithril attribs fix + FSR symbol
resolution + TouchController virtual buttons remediation, from the d089745 two-log
feedback. Checks A-G below; run from the repo root."""
import re, subprocess, sys, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASS = FAIL = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

def read(p):
    return open(p, encoding='utf-8', errors='replace').read()

print("== A. Mithril context attribs (gl_bridge.m) ==")
gb = read('Natives/ctxbridges/gl_bridge.m')
check("A1 attribs select by desktopGL (not mobileGL)",
      "desktopGL ? desktop_ctx_attribs : gles_ctx_attribs" in gb)
check("A2 Task140 case-file comment present",
      "Task 140：attribs 选择器从 mobileGL 改为 desktopGL" in gb)
check("A3 readback forensics after MakeCurrent",
      "Task140 make-current readback" in gb and "eglGetCurrentContext" in gb)
check("A4 readback log capped (first 3 only)",
      "ame140_rbLogs < 3" in gb)

print("== B. FSR symbol resolution (mgl_fsr.mm) ==")
mf = read('Natives/ctxbridges/mgl_fsr.mm')
check("B1 mgHandle member + source counters",
      "void *mgHandle;" in mf and "srcHandle, srcProc, srcDefault" in mf)
check("B2 ame119_resolve prefers dlsym(mgHandle)",
      "if (ame119_fsr.mgHandle != NULL) {" in mf and
      "void *p = dlsym(ame119_fsr.mgHandle, name);" in mf and
      mf.index("dlsym(ame119_fsr.mgHandle, name)") < mf.index("eglGetProcAddress(name)"))
check("B3 resolve log carries source buckets",
      "sources: handle=%d proc=%d default=%d" in mf)
check("B4 glCreateShader==0 no longer silent",
      "Task140 glCreateShader(stage=%u) returned 0" in mf)
check("B5 GLSL ver==0 no longer silent",
      "Task140 GLSL version query (pname 0x8B8C) returned 0" in mf)
check("B6 handle stored in resolve_gl",
      "ame119_fsr.mgHandle = mg;" in mf)
# ordering proof: RTLD_DEFAULT is the LAST resort
check("B7 RTLD_DEFAULT demoted to last resort",
      mf.rindex("dlsym(RTLD_DEFAULT, name)") > mf.rindex("dlsym(ame119_fsr.mgHandle, name)"))

print("== C. Renderer settings layering ==")
lp = read('Natives/LauncherPreferencesViewController.m')
ps = read('Natives/ProfileSettingsViewController.m')
rp = read('Natives/LauncherRightPanelViewController.m')
prefm = read('Natives/LauncherPreferences.m')
prefh = read('Natives/LauncherPreferences.h')
# C1 settings rows write global only
check("C1 ame140_writeRendererGlobal exists (dual-write retired)",
      "ame140_writeRendererGlobal" in lp and "ame139_writeRendererBoth" not in lp)
check("C2 global write helper writes video.renderer only (profile read is toast-only)",
      'setPrefObject(@"video.renderer", ame140_value);' in lp and
      'ame140_profile[@"renderer"] = ' not in lp and
      'ame140_prof[@"renderer"]' in lp)   # toast reads the override, never writes it
check("C2b profile-write code fully gone from settings page",
      "ame139_profile[\"renderer\"] = ame139_value;" not in lp)
check("C3 no [PLProfiles.current save] in the settings renderer write",
      "PLProfiles.current save" not in lp.split("ame140_writeRendererGlobal")[1].split("};")[0])
check("C4 shadow toast wired",
      "preference.warning.renderer_shadowed_by_profile" in lp and "NMToast showMessage:ame140_msg" in lp)
check("C5 mg display block has no unconditional MobileGL default",
      "return @ RENDERER_NAME_MOBILEGL;" not in lp.split('[key isEqualToString:@"renderer_backend"]')[1][:2500])
mgblock = lp.split('[key isEqualToString:@"renderer_backend"]')[1][:2500]
check("C6 mg display uses global key (not resolveKeyForCurrentProfile)",
      'ame140_global = getPrefObject(@"video.renderer")' in mgblock and
      "resolveKeyForCurrentProfile" not in mgblock)
check("C7 main renderer row displays global via helper",
      'if ([section isEqualToString:@"video"] && [key isEqualToString:@"renderer"]) {\n            NSString *ame140_global' in lp and
      "ame_renderer_display_name(ame140_val)" in lp)
check("C8 legacy auto+backend elevation preserved",
      "ame140_backend == 2" in lp and "RENDERER_NAME_MOBILEGL_GLES" in lp)
# C9 game editor
check("C9 editor loadSettings: nil = follow global",
      "ame140_rendererRaw" in ps and 'self.selectedRenderer = [ame140_rendererRaw isKindOfClass:NSString.class] ? ame140_rendererRaw : nil;' in ps)
check("C10 editor save: nil removes key",
      '[existing removeObjectForKey:@"renderer"];' in ps)
check("C11 editor no longer syncs global video.renderer",
      'setPrefString(@"video.renderer"' not in ps)
check("C12 editor picker includes family + follow-global",
      "getRendererFamilyKeys()" in ps and "rendererDisplayName:nil" in ps)
check("C13 editor checkmarks",
      ps.count('stringWithFormat:@"✓ %@"') >= 3)
check("C14 display helper handles nil -> follow-global label",
      "preference.profile.renderer_follow_global" in ps)
check("C15 helper declared in header",
      "ame_renderer_display_name" in prefh)
check("C16 helper implemented in LauncherPreferences.m",
      "NSString *ame_renderer_display_name(NSString *renderer)" in prefm)
# C17 RightPanel launch-time rewrite removed
rpblock = rp.split("if (profile) {")[1] if "if (profile) {" in rp else ""
check("C17 RightPanel no longer rewrites video.renderer at launch",
      'setPrefString(@"video.renderer"' not in rpblock and "Task 140：移除" in rp)
check("C18 RightPanel graphicsApi sync retained (minimal-diff scope)",
      'setPrefString(@"video.graphics_api"' in rp)
# C19 version manager key-mapped short names
vm = read('Natives/VersionManagerViewController.m')
check("C19 version manager short names mapped by key",
      "ame140_shortNames" in vm and '@ RENDERER_NAME_GL4ES: @"GL4ES"' in vm)

print("== D. TouchController virtual buttons ==")
jl = read('Natives/JavaLauncher.m')
sv = read('Natives/SurfaceViewController.m')
check("D1 clean-layout writer retired",
      "ame134_applyTouchControllerCleanLayout" not in jl)
check("D2 remediation function present",
      "ame140_remediateTouchControllerConfig" in jl)
check("D3 remediation only touches our cleanUuid pointer",
      "pointsToClean" in jl and "0196a1ba-6e9a-7b4c-8d5e-3f2a1c0e9b7d" in jl)
check("D4 empty-preset JSON payload gone (comments may still cite the name)",
      'name\" : \"Amethyst Clean' not in jl and
      'presetJson writeToFile' not in jl and
      '[ame134_fm createDirectoryAtPath:presetDir' not in jl)
check("D5 remediation anchors logged",
      "polluted empty-layout pointer" in jl)
check("D6 call site updated",
      jl.count("ame140_remediateTouchControllerConfig(gameDir)") == 1)
check("D7 gate unchanged (launcher-layer only)",
      "ame139_modControlsHidden" in sv and
      'getPrefBool(@"control.mod_touch_enable") &&' in sv)
check("D8 SurfaceVC comment documents the new semantics",
      "Task140 语义更新" in sv)

print("== E. l10n (4 languages) ==")
langs = ['en.lproj','zh-Hans.lproj','zh-CN.lproj','zh-Hant.lproj']
base = 'Natives/resources/'
counts = {}
for lg in langs:
    s = read(base + lg + '/Localizable.strings')
    n1 = '"preference.profile.renderer_follow_global"' in s
    n2 = '"preference.warning.renderer_shadowed_by_profile"' in s
    n3 = '"preference.touchcontroller.hide_controls"' in s
    check(f"E[{lg}] new keys present", n1 and n2 and n3)
    counts[lg] = s.count('\n"')
vals = set(counts.values())
check("E5 key count identical across 4 languages", len(vals) == 1, str(counts))
# hide_controls reworded (no longer claims "no controls at all")
for lg, want in [('zh-Hans.lproj','屏蔽启动器控件'), ('zh-Hant.lproj','遮蔽啟動器控制項'), ('en.lproj','Hide Launcher Controls')]:
    s = read(base + lg + '/Localizable.strings')
    check(f"E[{lg}] hide_controls reworded", want in s)

print("== F. publish assets ==")
import json
ann = json.load(open('announcements.json', encoding='utf-8'))
e = ann['announcements'][0]
check("F1 announcement updated with renderer layering",
      '渲染器设置分层' in e['content'] or '分层重构' in e['summary'])
check("F2 announcement hide-controls revised",
      '屏蔽启动器控件' in e['content'] or '保留模组自己的虚拟按钮' in e['content'])
check("F3 announcement mentions FSR fix",
      'FSR' in e['summary'])
rcn = read('README_CN.md')
ren = read('README.md')
check("F4 README_CN renderer row updated", '渲染器设置分层' in rcn)
check("F5 README_CN hide semantics updated", '保留模组自己的虚拟按钮' in rcn)
check("F6 README EN updated", 're-layered' in ren and 'Hide Launcher Controls' in ren)
rn = read('/home/z/my-project/download/v6.0.0-release-notes.md')
check("F7 release notes updated", '渲染器设置分层重构' in rn and 'Renderer & graphics' in rn)
vh = read('Natives/external/MobileGlues/MobileGlues-cpp/version.h')
check("F8 version.h addendum", 'REVISION 17 addendum (Task 140, no bump)' in vh)

print("== G. log-evidence anchors (d089745 logs, root cause documentation) ==")
cur = read('latestlog.txt') if os.path.exists('latestlog.txt') else ''
old = read('latestlog.old.txt') if os.path.exists('latestlog.old.txt') else ''
if cur:
    check("G1 GLES session shows the old broken resolve log form",
          "41/41 symbols (eglGetProcAddress=" in cur)
    check("G2 GLES session FSR unavailable (pre-fix evidence)",
          "Task119 FSR upscale unavailable" in cur)
else:
    print("  (latestlog.txt not present, skipping G1/G2)")
if old:
    check("G3 Mithril session crash signature",
          "There is no OpenGL context current in the current thread" in old)
    check("G4 Mithril session used ES attribs path (Binding to desktop OpenGL present, make-current OK)",
          "Binding to desktop OpenGL" in old and "eglSwapInterval(0) after eglMakeCurrent" in old)
else:
    print("  (latestlog.old.txt not present, skipping G3/G4)")

print(f"\n==== RESULT: {PASS} passed, {FAIL} failed ====")
sys.exit(1 if FAIL else 0)
