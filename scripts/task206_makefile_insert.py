#!/usr/bin/env python3
"""task206_makefile_insert.py -- insert the dep_nggl4es target into the Makefile
and wire it into the payload dependency line.

Written as a PURE PYTHON patcher (not the Edit tool) because the Edit tool
rewrites the whole file and has historically converted recipe TABs to spaces
(three documented incidents -- the CI "missing separator" family). This script
inserts bytes verbatim and audits TAB integrity before/after (cat -A style).
"""
from pathlib import Path

MK = Path("Makefile")
text = MK.read_text()

TAB_BLOCK = """dep_nggl4es:
\techo '[Amethyst v$(VERSION)] dep_nggl4es - start'
\t# Task206: NG-GL4ES ("Krypton Wrapper", BZLZHH/NG-GL4ES) -- the gl4es used
\t# by ZalithLauncher 2, vendored at ThirdParty/ZalithLauncher2 (see its
\t# CMakeLists PROVENANCE header). Built as its own cmake tree against the
\t# dep_mg glslang statics (pinned f5f664d 15.0.0 + lvalue-nullguard +
\t# pool-zero/size-guards -- inheriting the crash-family fixes; NG's vendored
\t# 15.4 headers were removed so headers and libs cannot drift) and the
\t# prebuilt SPIRV-Cross C API impl dylib (header verified byte-identical).
\t# Output libnggl4es.dylib rides the payload "cp $(WORKINGDIR)/*.dylib".
\tmg_bindir=$(WORKINGDIR)/mobileglues/3rdparty/glslang; \\
\tmg_spirv_a=$$mg_bindir/SPIRV/libSPIRV.a; \\
\t[ -f "$$mg_spirv_a" ] || mg_spirv_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libSPIRV.a -print -quit 2>/dev/null); \\
\tmg_glslang_a=$$mg_bindir/glslang/libglslang.a; \\
\t[ -f "$$mg_glslang_a" ] || mg_glslang_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang.a -print -quit 2>/dev/null); \\
\tmg_rl_a=$$mg_bindir/glslang/libglslang-default-resource-limits.a; \\
\t[ -f "$$mg_rl_a" ] || mg_rl_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang-default-resource-limits.a -print -quit 2>/dev/null); \\
\tif [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \\
\t\techo "ERROR: glslang static libs unresolved (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a) - dep_mg must run first"; \\
\t\texit 1; \\
\tfi; \\
\textra_glslang_libs=""; \\
\tfor l in libOGLCompiler.a libOSDependent.a; do \\
\t\tif [ -f "$$mg_bindir/glslang/$$l" ]; then \\
\t\t\textra_glslang_libs="$$extra_glslang_libs;$$mg_bindir/glslang/$$l"; \\
\t\tfi; \\
\tdone; \\
\tngg_libs="$$mg_spirv_a;$$mg_glslang_a;$$mg_rl_a$$extra_glslang_libs"; \\
\techo "[nggl4es] linking against glslang statics: $$ngg_libs"; \\
\tmkdir -p $(WORKINGDIR)/nggl4es; \\
\tcd $(WORKINGDIR)/nggl4es && cmake \\
\t\t-DMACOS="1" \\
\t\t-DCMAKE_CROSSCOMPILING=true \\
\t\t-DCMAKE_SYSTEM_NAME=Darwin \\
\t\t-DCMAKE_SYSTEM_PROCESSOR=aarch64 \\
\t\t-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \\
\t\t-DCMAKE_OSX_ARCHITECTURES=arm64 \\
\t\t-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \\
\t\t-DCMAKE_C_FLAGS="-arch arm64" \\
\t\t-DCMAKE_BUILD_TYPE=RelWithDebInfo \\
\t\t-DNGGL4ES_GLSLANG_INCLUDE="$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang" \\
\t\t-DNGGL4ES_GLSLANG_LIBS="$$ngg_libs" \\
\t\t-DNGGL4ES_SPVC_IMPL="$(SOURCEDIR)/Natives/resources/Frameworks/libspirv-cross-c-shared.0.impl.dylib" \\
\t\t-DNGGL4ES_FRAMEWORK_DIR="$(SOURCEDIR)/Natives/resources/Frameworks" \\
\t\t$(SOURCEDIR)/ThirdParty/ZalithLauncher2/ || exit 1
\tcmake --build $(WORKINGDIR)/nggl4es --config RelWithDebInfo -j$(JOBS) --target nggl4es || exit 1
\tcp $(WORKINGDIR)/nggl4es/libnggl4es.dylib $(WORKINGDIR)/ || exit 1
\techo '[Amethyst v$(VERSION)] dep_nggl4es - end'

"""

# --- audit helper -----------------------------------------------------------
def tab_lines(t):
    return sum(1 for ln in t.split("\n") if ln.startswith("\t"))

pre_tabs = tab_lines(text)

# --- 1. insert the target right before dep_angle_freeze ---------------------
anchor = "dep_angle_freeze:"
assert text.count(anchor) == 1, f"anchor {anchor!r} count != 1"
assert "dep_nggl4es:" not in text, "dep_nggl4es already present"
text = text.replace(anchor, TAB_BLOCK + anchor)

# --- 2. wire into payload ---------------------------------------------------
old_payload = ("payload: native dep_mg java jre assets dep_shader_shims "
               "dep_openal_shim dep_mithril_glshim dep_angle_freeze dep_sdl3_guard")
new_payload = ("payload: native dep_mg java jre assets dep_shader_shims "
               "dep_openal_shim dep_mithril_glshim dep_nggl4es dep_angle_freeze dep_sdl3_guard")
assert text.count(old_payload) == 1, f"payload line count != 1: {text.count(old_payload)}"
text = text.replace(old_payload, new_payload)

# --- 3. write + audit -------------------------------------------------------
MK.write_text(text)
post = MK.read_text()
post_tabs = tab_lines(post)
block_lines = TAB_BLOCK.count("\n\t")   # recipe lines starting with TAB
assert post_tabs == pre_tabs + block_lines, \
    f"TAB audit failed: {pre_tabs} -> {post_tabs} (expected +{block_lines})"
assert "dep_nggl4es:" in post and post.count("dep_nggl4es") == 2  # target + payload
print(f"Makefile: dep_nggl4es inserted (+{block_lines} TAB lines, "
      f"{pre_tabs} -> {post_tabs}); payload wired")
