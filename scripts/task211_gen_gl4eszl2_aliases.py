#!/usr/bin/env python3
"""task211_gen_gl4eszl2_aliases.py -- generate
ThirdParty/gl4es_extra_extra/src/gl/wrap/gl4eszl2_darwin_aliases.c

Task211 (ZL2 CLASSIC gl4es port, PojavLauncherTeam/gl4es_extra_extra).

Why this file exists (same disease as Task204's vgpu fix and Task206's NG
port, new -- much simpler -- macro dialect):
  attributes.h on __APPLE__ retires AliasExport to NOTHING
  (`#define AliasExport(name)`), so the ~1200 declarations shaped
      void glSampleCoverage(GLclampf, GLboolean) AliasExport("gl4es_glSampleCoverage");
  become bare prototypes and the plain gl* exports never exist. LWJGL/MC
  resolve GL entry points via dlsym(renderer_handle, name); without the
  plain names the search falls through the dependency closure to the
  BUNDLED raw ANGLE frameworks, bypassing the desktop-GL translation
  entirely (two GL id-namespaces on one context -- the exact "material
  corruption" mechanism root-caused for vgpu in Task204).

Classic dialect vs the NG generator (task206_gen_nggl4es_aliases.py):
  * single-arg form: `RET NAME(ARGS) AliasExport("gl4es_TARGET");` -- the
    alias fact is (NAME, TARGET), both recoverable by a backward scan from
    the AliasExport token;
  * STUB(ret, def, args) in glstub.c DEFINES gl4es_##def AND emits an
    AliasExport with a STRINGIZED arg ("gl4es_"#def) -- after substitution
    the stringize produces an ADJACENT STRING LITERAL pair that must be
    concatenated before the arg parse (the dead-session regex lesson);
  * THREE THUNK definitions in gl4eswraps.c (colors / vertexattrib /
    normalized) with ## pasting and # stringize, defined->used->undef'd
    twice -- point-of-use macro-table segmentation is mandatory (NG lesson
    #1) and substitute() must paste FIRST, then stringize, then plain
    (pasting on already-stringized text corrupts the quotes);
  * GL_GET_MAP / GETXXX / KHASH_* / DBG families carry no alias facts but
    are expanded generically anyway (a real preprocessor approximation).

Engine lessons inherited verbatim from Task206's four debugging rounds:
  1. point-of-use macro semantics (segments split at every table-changing
     directive);
  2. statements span newlines -- scanners are position-based over the
     expanded text, never line-regexes;
  3. one expanded line can carry MANY instances -- finditer everywhere;
  4. prototypes are not definitions (dangling guard needs `{` before `;`).

Guards (CI-round lessons inherited from task204/task206):
  * preprocessor conditionals evaluated with the build define set
    (NOX11 NO_GBM NOEGL DEFAULT_ES __APPLE__ NO_LOADER -- loader.h defines
    NO_LOADER itself on __APPLE__ -- and NO_INIT_CONSTRUCTOR);
  * dangling target: every alias target must have a surviving definition in
    the expanded text of the built set, else exit 1;
  * bare-name collision: a name already DEFINED as a plain function is
    never aliased (duplicate symbol);
  * idempotent: deterministic sorted output, byte-stable on re-run.

Regenerate after touching any AliasExport line, build define, or the
CMakeLists source list:
  python3 scripts/task211_gen_gl4eszl2_aliases.py
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TREE = REPO / "ThirdParty" / "gl4es_extra_extra"
CMAKE = TREE / "CMakeLists.txt"
ALIAS_FILE = TREE / "src" / "gl" / "wrap" / "gl4eszl2_darwin_aliases.c"

DEFINES = {"NOX11", "NO_GBM", "NOEGL", "DEFAULT_ES", "__APPLE__", "NO_LOADER",
           "NO_INIT_CONSTRUCTOR"}
LEAVES = {"AliasExport"}          # never expanded; the ARG carries the fact

# ---------------------------------------------------------------- 1. sources
cm = CMAKE.read_text(errors="replace")
src_block = cm[cm.index("set(GL4ESZL2_SRC"):cm.index("add_library(gl4eszl2")]
built = re.findall(r'(src/[A-Za-z0-9_/]+\.c)\s*$', src_block, re.M)
built = [b for b in built if not b.endswith("gl4eszl2_darwin_aliases.c")]
if not built:
    print("task211_gen_gl4eszl2_aliases: FAIL: no GL4ESZL2_SRC parsed from CMakeLists",
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

def split_args(s):
    """Split a macro argument list on top-level commas, KEEPING empty args."""
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

def substitute(body, params, args):
    """The dead-session ordering: PASTE first, then STRINGIZE, then plain.

    PASTE  : A##B -> concat(sub(A), sub(B)) -- each side substituted as a
             token (an argument name becomes that argument, verbatim).
    STRING : #A  -> C literal of the SUBSTITUTED argument (quotes escaped).
    PLAIN  : remaining parameter identifiers -> argument text.
    """
    amap = {p: args[i] for i, p in enumerate(params)} if params else {}

    def tok(t):
        t = t.strip()
        return amap.get(t, t)

    # -- 1. paste (repeat: chains like a##b##c)
    prev = None
    while prev != body:
        prev = body
        def do_paste(m):
            return tok(m.group(1)) + tok(m.group(2))
        body = re.sub(r'([A-Za-z_]\w*|\))\s*##\s*([A-Za-z_]\w*|\()',
                      do_paste, body, count=1)
    # -- 2. stringize (only macro PARAMS: #name where name in amap)
    def do_str(m):
        v = tok(m.group(1))
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    body = re.sub(r'#\s*([A-Za-z_]\w*)', do_str, body)
    # -- 3. plain
    if amap:
        def do_plain(m):
            return amap.get(m.group(1), m.group(1))
        body = re.sub(r'\b([A-Za-z_]\w*)\b', do_plain, body)
    return body

IDENT_CALL_RE = re.compile(r'\b([A-Za-z_]\w*)\s*\(')

def expand(text, table, depth=0):
    """Expand every function-like + object-like macro invocation (leaves and
    table misses pass through). Position-based; recursion-capped."""
    if depth > 60:
        return text
    out = []
    i = 0
    n = len(text)
    while i < n:
        m = IDENT_CALL_RE.search(text, i)
        if not m:
            out.append(text[i:]); break
        name = m.group(1)
        j = m.end()          # at the char after '('
        # find the closing ')' of the invocation (balanced, string-aware)
        depth_p, k = 1, j
        while k < n and depth_p:
            c = text[k]
            if c == '"':
                k += 1
                while k < n and text[k] != '"':
                    if text[k] == '\\':
                        k += 1
                    k += 1
            elif c == '(':
                depth_p += 1
            elif c == ')':
                depth_p -= 1
            k += 1
        if depth_p:          # unbalanced: emit and continue
            out.append(text[i:m.end()]); i = m.end(); continue
        inner = text[j:k - 1]
        mac = table.get(name)
        if mac is None or name in LEAVES:
            out.append(text[i:k]); i = k; continue
        if mac.params is None:
            # object-like: no args -- only expand if NOT followed by '(' ...
            # (IDENT_CALL_RE only matches with parens; object-like handled
            # separately below)
            out.append(text[i:k]); i = k; continue
        args = split_args(inner)
        if len(args) != len(mac.params):
            out.append(text[i:k]); i = k; continue
        body = substitute(mac.body, mac.params, args)
        out.append(text[i:m.start()])
        out.append(expand(body, table, depth + 1))
        i = k
    return "".join(out)

def expand_objectlike(text, table, depth=0):
    if depth > 20:
        return text
    changed = False
    def repl(m):
        nonlocal changed
        name = m.group(1)
        mac = table.get(name)
        if mac is None or mac.params is not None or name in LEAVES:
            return m.group(0)
        changed = True
        return mac.body
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r'\b([A-Za-z_]\w*)\b(?!\s*\()', repl, text, count=0)
        if not changed:
            break
    return text

# ------------------------------------------- 5. point-of-use expansion
# (the single-pass directive walker below handles table state + conditionals
# in one sweep; segments flush at every table-changing or conditional
# directive so macro uses expand with the table as of that region)

def build_table_and_expand(joined):
    table = {}
    out = []
    i = 0
    n = len(joined)
    seg_start = 0
    cond_stack = []   # each: [branch_active, any_taken]

    def active():
        return all(c[0] for c in cond_stack)

    def flush(end):
        if end > seg_start and active():
            seg = joined[seg_start:end]
            out.append(expand_objectlike(expand(seg, table), table))
            out.append("\n")

    dir_re = re.compile(r'^([ \t]*)#[ \t]*(\w+)[ \t]*(.*?)$', re.M)
    for m in dir_re.finditer(joined):
        d, rest = m.group(2), m.group(3)
        if d in ("define", "undef"):
            flush(m.start())
        if d in ("if", "ifdef", "ifndef"):
            flush(m.start())
            cond_stack.append([True, False])
            # evaluate below
        elif d == "elif" and cond_stack:
            flush(m.start())
            cond_stack[-1] = [False, cond_stack[-1][1]]
        elif d == "else" and cond_stack:
            flush(m.start())
            cond_stack[-1] = [False, cond_stack[-1][1]]
        elif d == "endif":
            flush(m.start())
            if cond_stack:
                cond_stack.pop()
        seg_start = m.end()
        # now handle the directive itself
        if d == "define":
            md = re.match(r'([A-Za-z_]\w*)(\(([^)]*)\))?[ \t]*(.*)$', rest)
            if not md:
                continue
            name, plist, body = md.group(1), md.group(3), md.group(4)
            params = None
            if plist is not None:
                params = [p.strip() for p in plist.split(",")] if plist.strip() else []
            table[name] = Macro(params, body)
        elif d == "undef":
            table.pop(rest.strip(), None)
        elif d in ("if", "ifdef", "ifndef"):
            if d == "ifdef":
                cond = rest.strip() in DEFINES
            elif d == "ifndef":
                cond = rest.strip() not in DEFINES
            else:
                cond = eval_cond(rest)
            cond_stack[-1] = [cond, cond]
        elif d == "elif" and cond_stack:
            cond = eval_cond(rest)
            cond_stack[-1] = [cond and not cond_stack[-1][1], cond_stack[-1][1] or cond]
        elif d == "else" and cond_stack:
            cond_stack[-1] = [not cond_stack[-1][1], True]
    flush(n)
    return "".join(out)

# --------------------------------------------------- 6. adjacent strings
def cat_strings(text):
    """Concatenate adjacent C string literals ("a" "b" AND "a""b" -- the
    stringize output `"lit"#arg` produces ZERO-space adjacency -> "lit""arg";
    the dead-session regex lesson: \\s* not \\s+)."""
    def repl(m):
        a = m.group(1)
        b = m.group(2)
        return '"' + a + b + '"'
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r'"((?:[^"\\]|\\.)*)"\s*"((?:[^"\\]|\\.)*)"', repl, text)
    return text

# --------------------------------------------------------- 7. main passes
def main():
    alias = {}         # NAME -> TARGET
    defined = set()    # gl4es_* functions DEFINED in the built set
    plain_defined = set()

    for rel in built:
        path = TREE / rel
        if not path.exists():
            print(f"FAIL: built source missing: {rel}", file=sys.stderr)
            sys.exit(1)
        raw = path.read_text(errors="replace")
        code = strip_comments(raw)
        joined = code.replace("\\\n", " ")
        expanded = cat_strings(build_table_and_expand(joined))

        # --- alias declarations: backward scan from every AliasExport(
        for m in re.finditer(r'\bAliasExport\s*\(', expanded):
            j = m.end()
            # parse the (single) string argument
            k = j
            while k < len(expanded) and expanded[k] in " \t":
                k += 1
            if k >= len(expanded) or expanded[k] != '"':
                continue          # not the string form (e.g. macro body text)
            e = k + 1
            while e < len(expanded):
                if expanded[e] == '\\':
                    e += 2; continue
                if expanded[e] == '"':
                    break
                e += 1
            target = expanded[k + 1:e]
            # backward: NAME( ... ) AliasExport
            p = m.start() - 1
            while p >= 0 and expanded[p] in " \t\n":
                p -= 1
            if p < 0 or expanded[p] != ')':
                continue
            depth = 1
            q = p - 1
            while q >= 0 and depth:
                c = expanded[q]
                if c == ')':
                    depth += 1
                elif c == '(':
                    depth -= 1
                q -= 1
            q += 1
            r = q - 1
            while r >= 0 and expanded[r] in " \t\n":
                r -= 1
            s = r
            while s >= 0 and (expanded[s].isalnum() or expanded[s] == '_'):
                s -= 1
            name = expanded[s + 1:r + 1]
            if not name:
                continue
            alias[name] = target

        # --- definitions (dangling guard + collision guard)
        for m in re.finditer(r'\b(gl4es_[A-Za-z_]\w*)\s*\(', expanded):
            # look ahead: balanced ')' then '{' before ';'
            k = m.end()
            depth = 1
            while k < len(expanded) and depth:
                c = expanded[k]
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                k += 1
            tail = expanded[k:k + 200]
            semi = tail.find(';')
            brace = tail.find('{')
            if brace != -1 and (semi == -1 or brace < semi):
                defined.add(m.group(1))
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*\([^;{)]*\)\s*\{', expanded):
            plain_defined.add(m.group(1))

    # --- guards
    dangling = sorted(n for n, t in alias.items() if t not in defined)
    if dangling:
        print("FAIL: dangling alias targets (not defined in the built set):",
              file=sys.stderr)
        for n in dangling[:20]:
            print(f"  {n} -> {alias[n]}", file=sys.stderr)
        sys.exit(1)
    # duplicate-symbol guard: an alias NAME that is ALSO plain-defined in the
    # EXPANDED built set (signature followed by `{`; alias DECLS end with `;`
    # after the AliasExport call, so they never match) -- the plain_defined
    # set covers macro-generated definitions (GETXXX/THUNK) too, which a raw
    # -text scan would miss.
    coll = sorted(n for n in alias if n in plain_defined)
    if coll:
        print("FAIL: alias names that are also plain-defined (duplicate symbol):",
              file=sys.stderr)
        for n in coll[:20]:
            print(f"  {n}", file=sys.stderr)
        sys.exit(1)

    # --- emit
    lines = sorted(alias.items())
    out = []
    out.append("// ============================================================================\n")
    out.append("// Task211 (ZL2 classic gl4es iOS port) -- GENERATED FILE, do not edit.\n")
    out.append("// Darwin branch-aliases for the plain gl* export names. Upstream\n")
    out.append("// attributes.h retires AliasExport(name) to NOTHING on __APPLE__, so every\n")
    out.append("// `RET NAME(ARGS) AliasExport(\"gl4es_NAME\");` declaration would otherwise\n")
    out.append("// export nothing. Pattern (CI-proven tinygl4angle/vgpu/NG form):\n")
    out.append("//     _name: b _target\n")
    out.append("//\n")
    out.append(f"// Coverage: {len(lines)} exports from the preprocessor-evaluated union of\n")
    out.append("// every AliasExport declaration + the STUB / THUNK / GL_GET_MAP macro\n")
    out.append("// families (token-paste + stringize expanded at point of use; adjacent\n")
    out.append("// string literals concatenated). Every target verified defined (dangling\n")
    out.append("// guard); alias names colliding with plain definitions rejected.\n")
    out.append("//\n")
    out.append("// Regenerate: python3 scripts/task211_gen_gl4eszl2_aliases.py\n")
    out.append("// ============================================================================\n")
    out.append("#if defined(__APPLE__)\n")
    for name, target in lines:
        out.append(f'__asm__(".global _{name}\\n\\t_{name}: b _{target}\\n");\n')
    out.append("#endif\n")
    text = "".join(out)
    if ALIAS_FILE.exists() and ALIAS_FILE.read_text() == text:
        print(f"task211_gen_gl4eszl2_aliases: unchanged ({len(lines)} aliases)")
        return
    ALIAS_FILE.write_text(text)
    print(f"task211_gen_gl4eszl2_aliases: wrote {ALIAS_FILE.name} ({len(lines)} aliases)")

if __name__ == "__main__":
    main()
