#!/usr/bin/env python3
"""task204_vgpu_gen_aliases.py -- regenerate Natives/external/vgpu/src/gl/wrap/vgpu_darwin_aliases.c

Task204 root cause (a599782 device log latestlog.txt, vgpu 1.8.9 session):
  [dlsym] Task202 NULL records #7-#15 (glEnable, glGenTextures, glDeleteTextures,
  glBindTexture, glTexParameteri, glTexImage2D, glTexSubImage2D, glActiveTexture,
  glGetError) -- the core GL entry points resolve to NULL for a secondary
  consumer, and (worse) MC's OWN caps resolutions for these names fall through
  dlsym(libvgpu.dylib, name) to the DEPENDENCY-IMAGE search (macOS dlsym(handle)
  searches the image AND its LC_LOAD_DYLIB closure), landing on the BUNDLED
  libGLESv2.framework's RAW ANGLE implementations -- BYPASSING vgpu's desktop-GL
  translation entirely.

  Mechanism: attributes.h on __APPLE__ expands AliasExport(name) to NOTHING, so
  the ~1000 per-file declarations like
      void glTexImage2D(...) AliasExport("gl4es_glTexImage2D");
  become bare prototypes; the linker binds vgpu's internal references to the
  framework, and the dylib never exports the plain names. The Task173 generator
  (scripts/task173_vgpu_gen_aliases.py, since deleted from the tree) only
  covered gl4eswraps.c's declarations: 944 exports shipped, 219+ core names
  missing (the whole texture/enable/buffer/framebuffer/draw family living in
  gles.c, texture.c, texture_params.c, buffers.c, framebuffers.c, drawing.c,
  program.c, shader.c, uniform.c, vertexattrib.c, ...).

  Consequence on device: MC's texture pipeline runs on RAW ES3 ANGLE while the
  fixed-pipeline half runs through vgpu's shaderconv translation -- TWO GL
  id-namespaces on one context, vgpu's tracked state blind to MC's binds, and
  vgpu's internal wrap-FBO textures colliding with MC's texture ids:
  "vgpu材质损坏".

Fix: regenerate the alias file as the UNION of
  (a) every name already exported by the current file (never shrink -- those
      944 are device-proven), and
  (b) every single-line `... NAME(ARGS) AliasExport("TARGET");` declaration in
      the vgpu sources that the CMake build actually compiles (VGPU_PACK_SRC +
      VGPU_CORE_SRC from Natives/CMakeLists.txt), so the branch target is
      guaranteed to exist at link time.

Idempotent; safe to re-run after touching any AliasExport line or the CMake
source lists. Output is deterministic (sorted by name).
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VGPU = REPO / "Natives" / "external" / "vgpu"
CMAKE = REPO / "Natives" / "CMakeLists.txt"
ALIAS_FILE = VGPU / "src" / "gl" / "wrap" / "vgpu_darwin_aliases.c"

# --- 1. built source files (link-time existence guarantee for branch targets)
cm = CMAKE.read_text(errors="replace")
built = set()
for m in re.finditer(r'set\(VGPU_(?:PACK|CORE)_SRC(.*?)\n\)', cm, re.S):
    for f in re.findall(r'"[^"]*?/(src/[a-z0-9_/]+\.c)"', m.group(1)):
        built.add(f)
if not built:
    print("task204_vgpu_gen_aliases: FAIL: no VGPU_*_SRC files parsed from CMakeLists", file=sys.stderr)
    sys.exit(1)
built.discard("src/gl/wrap/vgpu_darwin_aliases.c")

# --- 2. existing exports (base set, never shrink)
existing = {}
if ALIAS_FILE.exists():
    for line in ALIAS_FILE.read_text(errors="replace").splitlines():
        m = re.search(r'\.global _([A-Za-z0-9_]+)\\n\\t_\1: b _([A-Za-z0-9_]+)', line)
        if m:
            existing[m.group(1)] = m.group(2)

# --- 3. AliasExport declarations in built files
DECL = re.compile(
    r'^\s*[A-Za-z_][A-Za-z0-9_ \*]*?\*?\s*'
    r'([A-Za-z][A-Za-z0-9_]*)\s*\([^;]*\)\s*'
    r'AliasExport\("([A-Za-z0-9_]+)"\);')

def strip_comments(text):
    """Remove /*...*/ blocks and // comments. Declarations living inside
    comment blocks are phantoms -- their branch targets may not exist
    (device-proof: vertexattrib.c's commented-out glGetVertexAttribdv block)."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

declared = {}
for rel in sorted(built):
    p = VGPU / rel
    if not p.exists():
        print(f"task204_vgpu_gen_aliases: WARN: built file missing: {rel}", file=sys.stderr)
        continue
    for line in strip_comments(p.read_text(errors="replace")).splitlines():
        m = DECL.match(line)
        if m:
            name, target = m.group(1), m.group(2)
            if name in declared and declared[name] != target:
                print(f"task204_vgpu_gen_aliases: WARN: duplicate decl {name}: "
                      f"{declared[name]} vs {target} (keeping first)", file=sys.stderr)
                continue
            declared[name] = target

# --- 4. union + sanity
union = dict(existing)
for name, target in declared.items():
    if name in union and union[name] != target:
        print(f"task204_vgpu_gen_aliases: WARN: existing {name} -> {union[name]} "
              f"!= declared {target} (keeping existing)", file=sys.stderr)
        continue
    union[name] = target

# every branch target must be a gl4es_* implementation referenced by a
# declaration, an existing alias, or a definition scan (best-effort guard
# against branch-to-undefined -> link error)
defs = set()
for rel in sorted(built):
    text = (VGPU / rel).read_text(errors="replace")
    for m in re.finditer(r'\b(?:gl4es_[A-Za-z0-9_]+)\s*\(', text):
        defs.add(m.group(0)[:-1].strip())
missing_targets = sorted({t for t in union.values()
                          if t.startswith("gl4es_") and t not in defs and t != "gl4es_noop"})
if missing_targets:
    print(f"task204_vgpu_gen_aliases: WARN: branch targets with no definition "
          f"found in built sources: {missing_targets[:6]} ({len(missing_targets)} total)", file=sys.stderr)

# --- 5. emit
header = f"""// ============================================================================
// Task173 (iOS port) + Task204 regeneration -- GENERATED FILE, do not edit.
// Darwin branch-aliases for the plain gl* export names. attributes.h retires
// AliasExport on __APPLE__ (Apple clang rejects the bare alias attribute), so
// every `void glFoo(...) AliasExport("gl4es_glFoo");` line would otherwise be
// a dead prototype. Pattern (CI-proven tinygl4angle AliasDecl form):
//     _name: b _target
//
// Task204 coverage fix: the original generator only scanned gl4eswraps.c, so
// 219+ core names (glEnable/glGenTextures/glBindTexture/glTexImage2D/
// glTexSubImage2D/glActiveTexture/glGetError/glBufferData/glDrawArrays/...)
// were silently unexported -- MC's caps then fell through dlsym(handle, name)
// to the DEPENDENCY images (raw bundled ANGLE), bypassing vgpu's desktop-GL
// translation and corrupting textures (two GL id-namespaces, one context).
// This file now covers AliasExport declarations from EVERY built source file.
//
// Regenerate after touching any AliasExport line or the CMake source lists:
//   python3 scripts/task204_vgpu_gen_aliases.py
//
// Coverage: {len(union)} exports ({len(existing)} legacy + {len(union) - len(existing)} Task204 additions).
// ============================================================================
#if defined(__APPLE__)
"""

lines = [header]
for name in sorted(union):
    lines.append(f'__asm__(".global _{name}\\n\\t_{name}: b _{union[name]}\\n");\n')
lines.append("#endif\n")
out = "".join(lines)
ALIAS_FILE.write_text(out)
print(f"task204_vgpu_gen_aliases: wrote {len(union)} aliases "
      f"({len(union) - len(existing)} added, {len(existing)} kept) -> {ALIAS_FILE.relative_to(REPO)}")
