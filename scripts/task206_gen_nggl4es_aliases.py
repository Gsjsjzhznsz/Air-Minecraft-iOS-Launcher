#!/usr/bin/env python3
"""task206_gen_nggl4es_aliases.py -- generate
ThirdParty/ZalithLauncher2/src/gl/wrap/nggl4es_darwin_aliases.c

Task206 (NG-GL4ES / "Krypton Wrapper" port, the gl4es used by ZalithLauncher 2).

Why this file exists (same disease as Task204's vgpu fix, new macro dialect):
  attributes.h on __APPLE__ retires the whole AliasExport family to bare
  prototypes (`#define AliasExport(RET,NAME,X,DEF) RET NAME##X DEF`), so the
  ~1200 declarations like
      AliasExport(void,glActiveTexture,,(GLenum texture));
  never create the plain gl* exports. LWJGL/MC resolve GL entry points via
  dlsym(renderer_handle, name); without the plain names the search falls
  through the dependency closure to the BUNDLED raw ANGLE frameworks,
  bypassing the desktop-GL translation entirely (two GL id-namespaces on one
  context -- the exact "material corruption" mechanism root-caused for vgpu
  in Task204).

NG-GL4ES dialect vs the vgpu generator (task204_vgpu_gen_aliases.py):
  * macro-ARG form: AliasExport(RET,NAME,X,DEF) with token-pasted NAME##X
    and target gl4es_##NAME (variants _A/_D/_D_1/_M/_V/_1; _A retargets via
    its 5th arg INM);
  * STUB(ret,def,args) in glstub.c DEFINES gl4es_##def AND emits an
    AliasExport inside its body -- expanded generically, both facts fall out;
  * GL_GET_MAP(t,type) in eval.c defines gl4es_glGetMap<t>v via ## pasting;
  * gl4eswraps.c THUNK families build the LEAF MACRO NAME ITSELF by pasting
    (AliasExport##M2##_1, M2 empty or _D) and take a trailing EMPTY arg
    (THUNK(s, GLshort, )) -- argument splitting must keep empty args, and
    ## pasting must run before leaf matching;
  * glesnative.cpp NATIVE_FUNCTION_HEAD defines the bare name directly on
    __APPLE__ (no name##ARB alias, unlike the non-Apple branch) -- those 9
    bare names must NOT be aliased (duplicate symbol) but their ARB twins
    MUST be added.

Engine design (the four debugging lessons of the first attempt, in order):
  1. point-of-use macro semantics: the file is processed in segments split
     at every table-changing directive (#define/#undef); each segment is
     expanded with the table as of that region. gl4eswraps.c defines THUNK
     TWICE with different params (define->use->undef, twice) -- an
     end-of-file table would expand family 1 uses with family 2's body;
  2. statements/invokees span newlines (AliasExport(...,\n ...) in glx.c,
     THUNK bodies after continuation-joining) -- the scanners are
     position-based over the expanded text, not line-regexes;
  3. prototypes must not count as definitions (the regression round: the
     Apple expansion of every AliasExport IS a `RET NAME DEF;` prototype at
     line start) -- a definition requires `{` before `;` after the balanced
     signature;
  4. one expanded line can carry MANY AliasExport/definition instances
     (THUNK bodies) -- finditer + all-candidates, never .search()/.match().

Guards (CI-round lessons inherited from task204):
  * preprocessor conditionals evaluated with the build define set
    (NOX11 NO_GBM NOEGL DEFAULT_ES __APPLE__ + NO_LOADER, which loader.h
    defines on __APPLE__ -- without it loader.c's dlopen branch would be
    wrongly scanned);
  * bare-name collision: a name already DEFINED as a plain function by a
    built TU (glesnative.cpp family) is never aliased (duplicate symbol);
  * dangling target: every alias target must have a surviving definition in
    the expanded text of the built set, else exit 1 (the glX* lesson);
  * idempotent: deterministic sorted output, byte-stable on re-run.

Regenerate after touching any AliasExport line, build define, or the CMake
source list:
  python3 scripts/task206_gen_nggl4es_aliases.py
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
NG = REPO / "ThirdParty" / "ZalithLauncher2"
CMAKE = NG / "CMakeLists.txt"
ALIAS_FILE = NG / "src" / "gl" / "wrap" / "nggl4es_darwin_aliases.c"

# Build define set = dep_nggl4es compile definitions + the platform macro +
# NO_LOADER (defined by loader.h itself on __APPLE__; without it the engine
# would scan loader.c's Linux dlopen branch).
DEFINES = {"NOX11", "NO_GBM", "NOEGL", "DEFAULT_ES", "__APPLE__", "NO_LOADER"}

# Leaf macros: never expanded (their ARGUMENTS carry the alias facts).
LEAVES = {
    "AliasExport", "AliasExport_A", "AliasExport_D", "AliasExport_D_1",
    "AliasExport_M", "AliasExport_V", "AliasExport_1",
    "NonAliasExportDecl", "AliasDecl",
    "NATIVE_FUNCTION_HEAD", "NATIVE_FUNCTION_END",
}
# Variants that carry (RET,NAME,X,DEF[,INM]) -> exported=NAME+X, target=gl4es_NAME
# (_A retargets to gl4es_INM). _V carries (RET,NAME).
VARIANT_ARGS = {
    "AliasExport": 4, "AliasExport_1": 4,
    "AliasExport_D": 4, "AliasExport_D_1": 4, "AliasExport_M": 5,
    "AliasExport_A": 5, "AliasExport_V": 2,
}

# ---------------------------------------------------------------- 1. sources
cm = CMAKE.read_text(errors="replace")
src_block = cm[cm.index("set(NGGL4ES_SRC"):cm.index("add_library(nggl4es")]
built = re.findall(r'(src/[A-Za-z0-9_/]+\.(?:c|cpp))\s*$', src_block, re.M)
built = [b for b in built if not b.endswith("nggl4es_darwin_aliases.c")]
if not built:
    print("task206_gen_nggl4es_aliases: FAIL: no NGGL4ES_SRC parsed from CMakeLists",
          file=sys.stderr)
    sys.exit(1)

# ------------------------------------------------- 2. string-aware comments
def strip_comments(text):
    out = []
    i, n = 0, len(text)
    state = "code"           # code | line | block | str | chr
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; out.append(c); i += 1; continue
            if c == "'":
                state = "chr"; out.append(c); i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                state = "code"; out.append("\n")
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            if c == "\n":
                out.append("\n")   # keep line structure
            i += 1
        elif state == "str":
            if c == "\\":
                out.append(c)
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2; continue
            if c == '"':
                state = "code"
            out.append(c); i += 1
        else:  # chr
            if c == "\\":
                out.append(c)
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2; continue
            if c == "'":
                state = "code"
            out.append(c); i += 1
    return "".join(out)

# ----------------------------------------------------- 3. #if evaluation
def eval_cond(expr):
    """Evaluate a #if/#elif expression over DEFINES (task204 semantics:
    defined()/!defined()/&&/||/bare macros; anything unparsable -> True
    (conservative; the dangling guard catches rare false-includes)."""
    e = expr.strip()
    e = re.sub(r"defined\s*\(\s*([A-Za-z_]\w*)\s*\)",
               lambda m: "True" if m.group(1) in DEFINES else "False", e)
    e = re.sub(r"defined\s+([A-Za-z_]\w*)",
               lambda m: "True" if m.group(1) in DEFINES else "False", e)
    def repl_id(m):
        w = m.group(1)
        if w in ("True", "False", "and", "or", "not"):
            return w
        return "True" if w in DEFINES else "False"
    e = re.sub(r"\b([A-Za-z_]\w*)\b", repl_id, e)
    e = e.replace("&&", " and ").replace("||", " or ").replace("!", " not ")
    e = e.replace(" not =", " !=")
    try:
        return bool(eval(e, {"__builtins__": {}}, {}))
    except Exception:
        return True

# ----------------------------------------------------- 4. expansion engine
class Macro:
    __slots__ = ("params", "body")
    def __init__(self, params, body):
        self.params = params   # None for object-like; list for function-like
        self.body = body

IDENT_RE = re.compile(r"\b([A-Za-z_]\w*)\b")

def split_args(s):
    """Split a macro argument list on top-level commas, KEEPING empty args
    (THUNK(s, GLshort, ) has three args, the last empty)."""
    args, depth, cur, i = [], 0, [], 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            args.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    args.append("".join(cur))
    return args

def find_call(text, start):
    """Find the next function-like macro invocation `NAME(` whose NAME is in
    the table (and not a leaf). Returns (name, open_paren, close_paren) or
    None. Newlines count as whitespace."""
    for m in IDENT_RE.finditer(text, start):
        name = m.group(1)
        if name in LEAVES or name not in _macros:
            continue
        j = m.end()
        while j < len(text) and text[j] in " \t\n\r":
            j += 1
        if j < len(text) and text[j] == "(":
            close = _balanced(text, j)
            if close != -1:
                return name, j, close
    return None

def _balanced(text, open_pos):
    depth = 0
    i, n = open_pos, len(text)
    in_str = in_chr = False
    while i < n:
        c = text[i]
        if in_str or in_chr:
            if c == "\\":
                i += 2; continue
            if in_str and c == '"':
                in_str = False
            elif in_chr and c == "'":
                in_chr = False
        elif c == '"':
            in_str = True
        elif c == "'":
            in_chr = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

def expand_segment(text, depth=0):
    """Iteratively expand every non-leaf function-like macro invocation,
    innermost-first via rescan, with a recursion cap."""
    if depth > 16:
        return text
    guard = 0
    while guard < 4000:
        guard += 1
        hit = find_call(text, 0)
        if hit is None:
            return text
        name, op, cp = hit
        mac = _macros[name]
        args = split_args(text[op + 1:cp])
        # parameter count mismatch: variadic or exotic -> leave untouched
        # (only logging macros are variadic in this corpus; skipping them is
        # safe: they never carry alias facts).
        if len(args) != len(mac.params):
            # try to skip past this invocation to avoid an infinite loop
            nxt = find_call(text, cp + 1)
            if nxt is None:
                return text
            n2, o2, c2 = nxt
            head = text[:cp + 1]
            tail = expand_segment_replace(text, cp + 1, n2, o2, c2, depth)
            text = head + tail
            continue
        body = mac.body
        for p, a in zip(mac.params, args):
            body = IDENT_RE.sub(
                lambda m, _p=p, _a=a: _a if m.group(1) == _p else m.group(1), body)
        body = re.sub(r"[ \t\r\n]*##[ \t\r\n]*", "", body)   # token paste
        text = text[:m_start(text, name, op)] if False else text  # noop guard
        # locate identifier start (find_call gave match end; recompute span)
        span_start = _ident_start(text, op)
        text = text[:span_start] + " " + body + " " + text[cp + 1:]
    return text

def expand_segment_replace(text, from_pos, name, op, cp, depth):
    """Expand a single invocation found at (name, op, cp) starting the scan
    at from_pos; used to step over arity-mismatched calls."""
    mac = _macros[name]
    args = split_args(text[op + 1:cp])
    if len(args) != len(mac.params):
        return text[cp + 1:]
    body = mac.body
    for p, a in zip(mac.params, args):
        body = IDENT_RE.sub(
            lambda m, _p=p, _a=a: _a if m.group(1) == _p else m.group(1), body)
    body = re.sub(r"[ \t\r\n]*##[ \t\r\n]*", "", body)
    span_start = _ident_start(text, op)
    inner = expand_segment(body, depth + 1)
    return text[:span_start] + " " + inner + " " + text[cp + 1:]

def m_start(text, name, op):     # pragma: no cover (noop guard kept simple)
    return 0

def _ident_start(text, open_paren):
    i = open_paren - 1
    while i >= 0 and (text[i].isalnum() or text[i] == "_"):
        i -= 1
    return i + 1

_macros = {}

# --------------------------------------------- 5. per-file sequential scan
def scan_file(rel):
    """Returns (pairs, plain_defs, native_heads):
    pairs        {exported_name: gl4es_target}
    plain_defs   {name: True} bare names DEFINED (with a body) by this TU
    native_heads [bare names from NATIVE_FUNCTION_HEAD instances]"""
    text = strip_comments((NG / rel).read_text(errors="replace"))
    # continuation joining OUTSIDE directives is done per-segment below;
    # directive bodies are joined during directive parsing.
    lines = text.split("\n")
    cond = []            # bool stack
    seg = []             # active, non-directive lines of current segment
    expanded = []        # expanded segments, in order

    def flush():
        if not seg:
            return
        raw = "\n".join(seg)
        raw = re.sub(r"\\\s*\n", " ", raw)          # continuations
        expanded.append(expand_segment(raw))
        seg.clear()

    i, n = 0, len(lines)
    while i < n:
        raw = lines[i]
        s = raw.strip()
        if s.startswith("#"):
            # join directive continuations
            dline = s
            while dline.rstrip().endswith("\\") and i + 1 < n:
                i += 1
                dline = dline.rstrip()[:-1] + " " + lines[i].strip()
            d = dline.strip()
            m_if = re.match(r"#\s*if\s+(.*)", d)
            m_ifdef = re.match(r"#\s*ifdef\s+(\w+)", d)
            m_ifndef = re.match(r"#\s*ifndef\s+(\w+)", d)
            m_elif = re.match(r"#\s*elif\s+(.*)", d)
            m_else = re.match(r"#\s*else\b", d)
            m_endif = re.match(r"#\s*endif\b", d)
            m_def = re.match(r"#\s*define\s+([A-Za-z_]\w*)\s*(.*)", d, re.S)
            m_undef = re.match(r"#\s*undef\s+([A-Za-z_]\w*)", d)
            if m_if:
                cond.append(eval_cond(m_if.group(1)))
            elif m_ifdef:
                cond.append(m_ifdef.group(1) in _macros or m_ifdef.group(1) in DEFINES)
            elif m_ifndef:
                cond.append(not (m_ifndef.group(1) in _macros or m_ifndef.group(1) in DEFINES))
            elif m_elif and cond:
                cond[-1] = (not cond[-1]) and eval_cond(m_elif.group(1))
            elif m_else and cond:
                cond[-1] = not cond[-1]
            elif m_endif and cond:
                cond.pop()
            elif (m_def or m_undef) and all(cond):
                # table-changing directive: close the current segment first
                flush()
                if m_def:
                    name, rest = m_def.group(1), m_def.group(2).strip()
                    mp = re.match(r"\(([^)]*)\)\s*(.*)", rest, re.S)
                    if mp:
                        params = [p.strip() for p in mp.group(1).split(",")] if mp.group(1).strip() else []
                        if any("..." in p for p in params):
                            _macros.pop(name, None)   # variadic: never expand
                        else:
                            _macros[name] = Macro(params, mp.group(2))
                    else:
                        _macros.pop(name, None)       # object-like: inert
                else:
                    _macros.pop(m_undef.group(1), None)
            # directives never enter the segment text
        else:
            if all(cond):
                seg.append(raw)
            else:
                # region boundary at inactive lines is NOT a table change;
                # keeping the segment open is fine (macros can't change in
                # an inactive region), but a #if boundary INSIDE the active
                # run was already handled above.
                pass
        i += 1
    flush()

    full = "\n".join(expanded)
    pairs, plain_defs, native_heads = {}, {}, []

    # ---- 5d. bare alias-attribute declarations (raw text, condition-agnostic).
    # string_utils.c declares 18 helper aliases as
    #     RET NAME(ARGS) __attribute__((alias("gl4es_target")));
    # for vgpu/shaderconv.c. Apple clang rejects the bare alias attribute on
    # darwin, so the vendored file guards them behind !__APPLE__ (Task206) --
    # which also hides them from the conditional-filtered scan above. This raw
    # pass finds them regardless of preprocessor activity: the quoted-target
    # form only exists there (the attributes.h / glesnative.cpp macro bodies
    # use alias(#name) -- a hash, not a string -- and never match).
    for m in re.finditer(
            r"\b([A-Za-z_]\w*)[ \t]*\(([^;()]*(?:\([^;()]*\)[^;()]*)*)\)"
            r"[ \t]*__attribute__\(\(alias\(\"([A-Za-z_]\w+)\"\)\)\)[ \t]*;",
            strip_comments((NG / rel).read_text(errors="replace"))):
        name, target = m.group(1), m.group(3)
        if name == "alias" or name.startswith("__"):
            continue
        if name not in pairs:
            pairs[name] = target

    # ---- 5a. AliasExport leaf instances (finditer: many per line)
    for m in re.finditer(r"\b(AliasExport(?:_A|_D_1|_D|_M|_V|_1)?)\s*\(", full):
        variant = m.group(1)
        if variant not in VARIANT_ARGS:
            continue
        cp = _balanced(full, m.end() - 1)
        if cp == -1:
            continue
        args = split_args(full[m.end():cp])
        if len(args) != VARIANT_ARGS[variant]:
            continue
        if variant == "AliasExport_V":
            name = args[1].strip()
            exported, target = name, "gl4es_" + name
        else:
            name = args[1].strip()
            suffix = args[2].strip()
            exported = name + suffix
            target = "gl4es_" + (args[4].strip() if variant == "AliasExport_A"
                                 else name)
        if not re.fullmatch(r"[A-Za-z_]\w*", exported):
            continue
        if exported in pairs and pairs[exported] != target:
            print(f"task206_gen_nggl4es_aliases: WARN: {rel}: duplicate "
                  f"{exported}: {pairs[exported]} vs {target} (keeping first)",
                  file=sys.stderr)
            continue
        pairs[exported] = target

    # ---- 5b. NATIVE_FUNCTION_HEAD instances (ARB twin additions)
    for m in re.finditer(r"\bNATIVE_FUNCTION_HEAD\s*\(", full):
        cp = _balanced(full, m.end() - 1)
        if cp == -1:
            continue
        args = split_args(full[m.end():cp])
        if len(args) >= 2 and re.fullmatch(r"[A-Za-z_]\w*", args[1].strip()):
            native_heads.append(args[1].strip())

    # ---- 5c. definitions: signature + `{` before `;` (prototypes excluded).
    # Anchor = statement boundary [;{}\n] (NOT line start: a THUNK expansion
    # is one long line carrying a dozen definitions -- lesson 4). Calls are
    # rejected by the after-paren `{`-before-`;` discriminator, control-flow
    # forms by the type-token-only prefix.
    for m in re.finditer(
            r"(?:\A|[;{}\n])[ \t]*(?:extern\s+\"C\"\s+)?"
            r"(?:[A-Za-z_][A-Za-z0-9_]*[ \t\*]+)*"
            r"(gl4es_[A-Za-z0-9_]+|glX[A-Za-z0-9_]+|gl[A-Za-z0-9_]+)"
            r"[ \t\r\n]*\(", full):
        # NOTE: name-to-paren may span a newline -- a multi-line macro
        # invocation keeps its argument whitespace in the substitution
        # (STUB(void, glColorTable,\n (args...)) -> gl4es_glColorTable \n
        # (args...) {), exactly like the real preprocessor.
        name = m.group(1)
        op = full.index("(", m.end() - 1)
        cp = _balanced(full, op)
        if cp == -1:
            continue
        rest = full[cp + 1:]
        # `{` before `;` (skipping attributes/whitespace) -> definition
        m2 = re.search(r"[;{]", rest)
        if m2 and m2.group(0) == "{":
            plain_defs[name] = True
    return pairs, plain_defs, native_heads

all_pairs, plain_defined, all_native = {}, {}, []
files_missing = []
for rel in built:
    if not (NG / rel).exists():
        files_missing.append(rel)
        continue
    pairs, pdefs, heads = scan_file(rel)
    for k, v in pairs.items():
        if k in all_pairs and all_pairs[k] != v:
            print(f"task206_gen_nggl4es_aliases: WARN: cross-file duplicate "
                  f"{k}: {all_pairs[k]} vs {v} (keeping first)", file=sys.stderr)
            continue
        all_pairs[k] = v
    plain_defined.update(pdefs)
    all_native.extend(heads)
if files_missing:
    print(f"task206_gen_nggl4es_aliases: FAIL: built files missing: "
          f"{files_missing}", file=sys.stderr)
    sys.exit(1)

# --- 6a. bare-name collision guard (glesnative.cpp family already exports)
collisions = sorted(set(all_pairs) & set(plain_defined))
if collisions:
    print(f"task206_gen_nggl4es_aliases: note: {len(collisions)} declared names "
          f"already defined as plain functions by built TUs -- not aliased: "
          f"{collisions[:6]} ...")
    for c in collisions:
        all_pairs.pop(c, None)

# --- 6b. ARB twins for NATIVE_FUNCTION_HEAD (Apple branch drops name##ARB).
# The leaf macro never gets expanded, so these names carry their own
# definedness (the Apple-branch body IS a definition of the bare name).
arb_added = {}
for name in all_native:
    if (name + "ARB") not in all_pairs:
        arb_added[name + "ARB"] = name
all_pairs.update(arb_added)

# --- 6c. dangling-target guard (CI round-1 lesson: glX family)
defined_anywhere = set(plain_defined) | set(all_native)
missing = sorted({t for e, t in all_pairs.items() if t not in defined_anywhere})
if missing:
    print(f"task206_gen_nggl4es_aliases: FAIL: alias targets with no surviving "
          f"definition (would dangle the link): {missing[:10]} "
          f"({len(missing)} total)", file=sys.stderr)
    sys.exit(1)

# --- 7. emit (idempotent, deterministic)
header = f"""// ============================================================================
// Task206 (NG-GL4ES iOS port) -- GENERATED FILE, do not edit.
// Darwin branch-aliases for the plain gl* export names. Upstream attributes.h
// retires the whole AliasExport family to bare prototypes on __APPLE__, so
// every AliasExport(RET,NAME,X,DEF) declaration would otherwise export
// nothing. Pattern (CI-proven tinygl4angle/vgpu AliasDecl form):
//     _name: b _target
//
// Coverage: {len(all_pairs)} exports from the preprocessor-evaluated union of
// every AliasExport/A/_D/_D_1/_M/_V/_1 declaration + STUB/GL_GET_MAP/THUNK
// macro families (token-paste expanded at point of use) + the NATIVE_FUNCTION
// _HEAD ARB twins (Apple branch drops name##ARB) - {len(collisions)} plain-
// defined names (glesnative.cpp family) deliberately not aliased (duplicate
// symbols); every target verified defined (dangling guard).
//
// Regenerate: python3 scripts/task206_gen_nggl4es_aliases.py
// ============================================================================
#if defined(__APPLE__)
"""

lines = [header]
for name in sorted(all_pairs):
    lines.append(f'__asm__(".global _{name}\\n\\t_{name}: b _{all_pairs[name]}\\n");\n')
lines.append("#endif\n")
out = "".join(lines)

if ALIAS_FILE.exists() and ALIAS_FILE.read_text(errors="replace") == out:
    print(f"task206_gen_nggl4es_aliases: unchanged ({len(all_pairs)} aliases)")
else:
    ALIAS_FILE.write_text(out)
    print(f"task206_gen_nggl4es_aliases: wrote {len(all_pairs)} aliases "
          f"({len(arb_added)} ARB twins from NATIVE_FUNCTION_HEAD; "
          f"{len(collisions)} plain-defined names skipped) -> "
          f"{ALIAS_FILE.relative_to(REPO)}")
