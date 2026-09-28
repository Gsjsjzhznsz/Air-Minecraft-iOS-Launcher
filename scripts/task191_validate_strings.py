#!/usr/bin/env python3
"""Task191: strict .strings tokenizer (Apple old-style plist grammar).
Mimics CFPropertyList old-style parsing closely enough to catch
real syntax breakage: unbalanced quotes, missing semicolons,
stray characters outside comments/entries.
"""
import sys, glob

def tokenize(path):
    content = open(path, encoding='utf-8').read()
    n = len(content)
    i = 0
    entries = 0
    errors = []
    line = 1
    def skip_ws_comments(i, line):
        while i < n:
            c = content[i]
            if c == '\n':
                line += 1; i += 1
            elif c in ' \t\r':
                i += 1
            elif c == '/' and i+1 < n and content[i+1] == '/':
                while i < n and content[i] != '\n':
                    i += 1
            elif c == '/' and i+1 < n and content[i+1] == '*':
                j = content.find('*/', i+2)
                if j < 0:
                    errors.append((line, 'unterminated block comment'))
                    return n, line
                line += content.count('\n', i, j)
                i = j + 2
            else:
                break
        return i, line
    while True:
        i, line = skip_ws_comments(i, line)
        if i >= n:
            break
        if content[i] != '"':
            # tolerate stray ';' between entries? old plist is lenient, but flag it
            j = content.find('\n', i)
            errors.append((line, 'unexpected char %r (ctx %r)' % (content[i], content[i:j if j>0 else i+40])))
            i = (j + 1) if j > 0 else i + 1
            continue
        # parse quoted string
        i += 1
        buf = []
        while i < n:
            c = content[i]
            if c == '\\':
                if i+1 < n:
                    buf.append(content[i:i+2]); i += 2; continue
                errors.append((line, 'dangling escape at EOF')); i += 1; break
            if c == '"':
                i += 1; break
            if c == '\n':
                line += 1
            buf.append(c); i += 1
        else:
            errors.append((line, 'unterminated string'))
            break
        if i >= n or content[i-1] != '"':
            break
        key = ''.join(buf)
        # expect '='
        i, line = skip_ws_comments(i, line)
        if i >= n or content[i] != '=':
            errors.append((line, 'expected = after key %r' % key[:40]))
            if i < n: i += 1
            continue
        i += 1
        i, line = skip_ws_comments(i, line)
        if i >= n or content[i] != '"':
            errors.append((line, 'expected quoted value for key %r' % key[:40]))
            continue
        i += 1
        while i < n:
            c = content[i]
            if c == '\\':
                i += 2; continue
            if c == '"':
                i += 1; break
            if c == '\n':
                line += 1
            i += 1
        else:
            errors.append((line, 'unterminated value string for %r' % key[:40]))
            break
        # expect ';'
        i, line = skip_ws_comments(i, line)
        if i >= n:
            errors.append((line, 'missing final ; after %r' % key[:40]))
            break
        if content[i] != ';':
            errors.append((line, 'missing ; after value of %r (got %r)' % (key[:40], content[i])))
            continue
        i += 1
        entries += 1
    return entries, errors

def main():
    files = sys.argv[1:] or sorted(glob.glob('Natives/resources/*.lproj/Localizable.strings'))
    any_bad = False
    for f in files:
        entries, errors = tokenize(f)
        if errors:
            any_bad = True
            print('%-55s %d entries, %d ERRORS' % (f.split('resources/')[-1], entries, len(errors)))
            for line, msg in errors[:6]:
                print('    line %d: %s' % (line, msg))
        else:
            print('%-55s OK (%d entries)' % (f.split('resources/')[-1], entries))
    sys.exit(1 if any_bad else 0)

if __name__ == '__main__':
    main()
