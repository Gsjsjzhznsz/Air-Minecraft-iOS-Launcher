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
  (since lost from the tree) only covered gl4eswraps.c's declarations: 944
  exports shipped, 219+ core names missing (the whole texture/enable/buffer/
  framebuffer/draw family living in gles.c, texture.c, texture_params.c,
  buffers.c, framebuffers.c, drawing.c, program.c, shader.c, uniform.c,
  vertexattrib.c, ...). Consequence on device: two GL id-namespaces on one
  context, corrupted materials ("vgpu材质损坏").

Fix: regenerate the alias file as the UNION of
  (a) every name already exported by the current file (never shrink -- those
      944 are device-proven), and
  (b) every single-line `... NAME(ARGS) AliasExport("TARGET");` declaration in
      the vgpu sources that SURVIVES the build's preprocessor, evaluated with
      the same define set the CMake target uses (NOX11 NO_GBM NOEGL
      DEFAULT_ES=3 SHAREDLIB) plus __APPLE__ -- CI round 1 proved the naive
      scan dangles the glX* family (their definitions live inside
      #ifndef NOX11 blocks that the real build compiles away).

Idempotent; safe to re-run after touching any AliasExport line, any build
define, or the CMake source lists. Output is deterministic (sorted by name).
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VGPU = REPO / "Natives" / "external" / "vgpu"
CMAKE = REPO / "Natives" / "CMakeLists.txt"
ALIAS_FILE = VGPU / "src" / "gl" / "wrap" / "vgpu_darwin_aliases.c"

# Build define set: CMake target_compile_definitions for vgpu_pack/vgpu_core
# (Natives/CMakeLists.txt Task179 block) + the platform macro every TU of the
# dylib is compiled with.
DEFINES = {"NOX11", "NO_GBM", "NOEGL", "DEFAULT_ES", "SHAREDLIB", "__APPLE__"}

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

# --- 3. preprocessor-aware scanner
def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

def eval_cond(expr):
    """Evaluate a #if/#elif expression over DEFINES. Supports defined(X),
    !defined(X), && and || chains, and bare macros. Unknown syntax -> True
    (conservative: keep scanning; a rare false-include is caught by the
    dangling-target check below)."""
    expr = expr.strip()
    def repl_defined(m):
        return "True" if m.group(1) in DEFINES else "False"
    e = re.sub(r'defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)', repl_defined, expr)
    e = re.sub(r'defined\s+([A-Za-z_][A-Za-z0-9_]*)', repl_defined, e)
    # bare identifiers: defined -> True, else False
    e = re.sub(r'\b([A-Za-z_][A-Za-z0-9_]*)\b',
               lambda m: "True" if m.group(1) in DEFINES
                         else ("True" if m.group(1) in ("True", "False") else "False"), e)
    e = e.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    e = e.replace(" not =", " !=")  # keep != intact if any
    try:
        return bool(eval(e, {"__builtins__": {}}, {}))
    except Exception:
        return True

def active_lines(text):
    """Yield (line, active) with preprocessor conditionals evaluated."""
    stack = []          # list of bool: all must be True for the line to be active
    seen_else = []
    for line in text.splitlines():
        s = line.strip()
        m_if = re.match(r'#\s*if\s+(.*)', s)
        m_ifdef = re.match(r'#\s*ifdef\s+(\w+)', s)
        m_ifndef = re.match(r'#\s*ifndef\s+(\w+)', s)
        m_elif = re.match(r'#\s*elif\s+(.*)', s)
        m_else = re.match(r'#\s*else\b', s)
        m_endif = re.match(r'#\s*endif\b', s)
        if m_if:
            stack.append(eval_cond(m_if.group(1)))
            seen_else.append(False)
        elif m_ifdef:
            stack.append(m_ifdef.group(1) in DEFINES)
            seen_else.append(False)
        elif m_ifndef:
            stack.append(m_ifndef.group(1) not in DEFINES)
            seen_else.append(False)
        elif m_elif and stack:
            stack[-1] = (not stack[-1]) and eval_cond(m_elif.group(1))
        elif m_else and stack:
            stack[-1] = not stack[-1]
        elif m_endif and stack:
            stack.pop()
            seen_else.pop() if seen_else else None
        yield line, all(stack)

DECL = re.compile(
    r'^\s*[A-Za-z_][A-Za-z0-9_ \*]*?\*?\s*'
    r'([A-Za-z][A-Za-z0-9_]*)\s*\([^;]*\)\s*'
    r'AliasExport\("([A-Za-z0-9_]+)"\);')

def scan_declarations(rel):
    """Return {name: target} for AliasExport lines that survive the
    preprocessor under the build's define set."""
    text = strip_comments((VGPU / rel).read_text(errors="replace"))
    out = {}
    for line, active in active_lines(text):
        if not active:
            continue
        m = DECL.match(line)
        if m:
            name, target = m.group(1), m.group(2)
            if name in out and out[name] != target:
                print(f"task204_vgpu_gen_aliases: WARN: duplicate decl {name}: "
                      f"{out[name]} vs {target} (keeping first)", file=sys.stderr)
                continue
            out[name] = target
    return out

def plain_name_definitions(rel):
    """Names DEFINED as plain (non-gl4es_) functions in preprocessed source --
    their defining TU already exports them; an alias would duplicate the symbol
    (CI round-2 lesson: pack.c's 286 forwarders)."""
    text = strip_comments((VGPU / rel).read_text(errors="replace"))
    defs = set()
    for line, active in active_lines(text):
        if not active:
            continue
        m = re.match(r'^\s*(?:[A-Za-z_][A-Za-z0-9_ \*]*?\*?\s*)?(gl[A-Za-z0-9_]+|glX[A-Za-z0-9_]+)\s*\([^;]*\)\s*\{', line)
        if m:
            defs.add(m.group(1))
    return defs

def definitions_present(rel):
    """Set of function names defined (signature line) in preprocessed source.
    Over-inclusive by design (prototypes count too): the preprocessor guard
    evaluation is what removes NOX11/NO_GBM/NOEGL code; a genuinely missing
    definition would have failed the original Linux alias build too."""
    text = strip_comments((VGPU / rel).read_text(errors="replace"))
    defs = set()
    for line, active in active_lines(text):
        if not active:
            continue
        m = re.match(r'^\s*(?:[A-Za-z_][A-Za-z0-9_ \*]*?\*?\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\(', line)
        if m:
            defs.add(m.group(1))
    return defs

declared = {}
all_defs = set()
plain_defined = set()   # names some built TU already DEFINES as a plain function
for rel in sorted(built):
    p = VGPU / rel
    if not p.exists():
        print(f"task204_vgpu_gen_aliases: WARN: built file missing: {rel}", file=sys.stderr)
        continue
    declared.update(scan_declarations(rel))
    all_defs |= definitions_present(rel)
    plain_defined |= plain_name_definitions(rel)

# CI round-2 lesson: vgpu_pack's pack.c already DEFINES 286 plain-name GL
# forwarders (void glTexImage2D(...) { _LOAD_GLES gl4es_glTexImage2D(...); })
# -- merged into the same dylib, an asm alias for those names is a DUPLICATE
# SYMBOL and fails the link. A name with a plain definition in any built TU is
# already exported by its defining TU (default visibility); never alias it.
collisions = sorted(set(declared) & plain_defined - set(existing))
if collisions:
    print(f"task204_vgpu_gen_aliases: note: {len(collisions)} declared names already "
          f"defined as plain functions by built TUs (pack.c family) -- not aliased: "
          f"{collisions[:6]} ...")
    for n in collisions:
        declared.pop(n, None)

# --- 4. union + sanity
union = dict(existing)
for name, target in declared.items():
    if name in union and union[name] != target:
        print(f"task204_vgpu_gen_aliases: WARN: existing {name} -> {union[name]} "
              f"!= declared {target} (keeping existing)", file=sys.stderr)
        continue
    union[name] = target

# dangling guard: any NEW alias whose target has neither a preprocessed
# definition nor a legacy entry would break the link (CI round-1 lesson:
# the glX* family). Existing entries are exempt (device-proven).
missing_targets = sorted({t for n, t in union.items()
                          if n not in existing and t not in all_defs})
if missing_targets:
    print(f"task204_vgpu_gen_aliases: FAIL: new alias targets with no surviving "
          f"definition (would dangle the link): {missing_targets[:8]} "
          f"({len(missing_targets)} total)", file=sys.stderr)
    sys.exit(1)

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
// This file now covers AliasExport declarations from EVERY built source file,
// preprocessor-evaluated with the build's define set (NOX11 NO_GBM NOEGL
// DEFAULT_ES=3 SHAREDLIB) so guarded-out code (the glX* family) cannot dangle.
//
// Regenerate after touching any AliasExport line, build define, or the CMake
// source lists:
//   python3 scripts/task204_vgpu_gen_aliases.py
//
// Coverage: {len(union)} exports (legacy base never shrinks; additions are\n// collision-guarded against plain-name definitions in built TUs).
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
      f"(base had {len(existing)}; total {len(union)}) -> {ALIAS_FILE.relative_to(REPO)}")
