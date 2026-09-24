#!/usr/bin/env python3
"""Task158: lightweight ObjC source sanity gate (bracket/paren/brace balance
with string+comment awareness). Not a compiler -- catches the class of
accidents the Edit tool can introduce (dropped/added delimiters)."""
import sys

def check(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    state = "code"  # code | str | chr | line | block
    i, line = 0, 1
    errors = []
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if c == "\n":
            line += 1
            if state == "line":
                state = "code"
            i += 1
            continue
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; i += 1; continue
            if c == "'":
                state = "chr"; i += 1; continue
            if c in "([{":
                stack.append((c, line))
            elif c in ")]}":
                if not stack or stack[-1][0] != pairs[c]:
                    errors.append(f"line {line}: unmatched '{c}' (stack top: {stack[-1] if stack else None})")
                    if not stack:
                        pass
                else:
                    stack.pop()
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
        elif state == "chr":
            if c == "\\":
                i += 2; continue
            if c == "'":
                state = "code"
        elif state == "block":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
        i += 1
    if stack:
        errors.append(f"unclosed delimiters: {[(d, l) for d, l in stack[-3:]]}")
    if state not in ("code", "line"):
        errors.append(f"file ended inside {state}")
    return errors

ok = True
for path in sys.argv[1:]:
    errs = check(path)
    if errs:
        ok = False
        print(f"FAIL {path}")
        for e in errs[:10]:
            print("   ", e)
    else:
        print(f"PASS {path}")
sys.exit(0 if ok else 1)
