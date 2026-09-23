#!/usr/bin/env python3
"""Task 156: insert dep_mithril_glshim target + payload hook into Makefile,
tab-preserving (the Edit tool re-indented the whole file to spaces -- fatal
for make recipes). Idempotent."""
import sys

MK = "Makefile"

with open(MK, "r", encoding="utf-8", newline="") as f:
    src = f.read()

if "dep_mithril_glshim" in src:
    print("[task156] Makefile already patched -- no-op")
    sys.exit(0)

T = "\t"

target = (
    "dep_mithril_glshim:\n"
    + T + "echo '[Amethyst v$(VERSION)] dep_mithril_glshim - start'\n"
    + T + "# Task 156: Mithril GL provider shim (libmithril_glshim.dylib).\n"
    + T + "# - re-export every libmithril.dylib symbol (dep_openal_shim pattern;\n"
    + T + "#   its install name is already @rpath/libmithril.dylib -- no LC_ID fix\n"
    + T + "#   needed). LWJGL points -Dorg.lwjgl.opengl.libname at the shim, so the\n"
    + T + "#   Delegate per-name dlsym lands on Mithril's own implementations.\n"
    + T + "# - local glGetIntegerv/glGetInteger64v win over the re-exports and floor\n"
    + T + "#   zero limit enums (GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT=0 caused MC 26.2\n"
    + T + "#   DynamicUniformStorage divide-by-zero; see Natives/mithril_gl_shim.c).\n"
    + T + "xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \\\n"
    + T + T + "-install_name @rpath/libmithril_glshim.dylib \\\n"
    + T + T + "-Wl,-reexport_library,$(SOURCEDIR)/Natives/resources/Frameworks/libmithril.dylib \\\n"
    + T + T + "-o $(WORKINGDIR)/libmithril_glshim.dylib \\\n"
    + T + T + "$(SOURCEDIR)/Natives/mithril_gl_shim.c || exit 1\n"
    + T + "echo '[Amethyst v$(VERSION)] dep_mithril_glshim - end'\n"
    + "\n"
)

anchor = "assets:\n"
idx = src.index(anchor)
src = src[:idx] + target + src[idx:]

old_payload = "payload: native dep_mg java jre assets dep_shader_shims dep_openal_shim dep_angle_freeze dep_sdl3_guard"
new_payload = "payload: native dep_mg java jre assets dep_shader_shims dep_openal_shim dep_mithril_glshim dep_angle_freeze dep_sdl3_guard"
assert src.count(old_payload) == 1, "payload line not found exactly once"
src = src.replace(old_payload, new_payload)

with open(MK, "w", encoding="utf-8", newline="") as f:
    f.write(src)
print("[task156] Makefile patched (tab-preserving): dep_mithril_glshim + payload hook")
