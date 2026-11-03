#!/usr/bin/env python3
"""Doubles the braces in the format strings of Odin's fmt calls.

Odin's fmt reads `{` in a format as the start of a placeholder; a literal
brace is `{{` (and `}}` for `}`). The Objective-C formats the port carried
over print Triangle descriptions (`#Writing & { author: %s }`), so their
braces must be doubled. This finds each call to a fmt (or log) procedure
ending in `printf` or `f`, takes its format argument (the first, or the
second for those that take a writer or builder first), and doubles the
braces in the string literals that make it up. A literal that already has
`{{` or `}}` is taken as done. A format that isn't made of literals is
listed for a look by hand.

  python3 port/braces.py [--write] file.odin ...
"""
import re
import sys

FORMAT_FIRST = {'printf', 'println', 'tprintf', 'aprintf', 'eprintf', 'ctprintf', 'caprintf', 'panicf',
                'debugf', 'infof', 'warnf', 'errorf', 'fatalf'}
FORMAT_SECOND = {'sbprintf', 'bprintf', 'fprintf', 'wprintf', 'assertf'}


def tokens(src):
    """(kind, start, end) for strings, raw strings, runes and comments."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            yield ('comment', i, j)
            i = j
        elif src.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('/*', j):
                    depth += 1
                    j += 2
                elif src.startswith('*/', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            yield ('comment', i, j)
            i = j
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            yield ('string', i, j + 1)
            i = j + 1
        elif c == '`':
            j = src.find('`', i + 1)
            yield ('raw', i, j + 1)
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n and src[j] != "'":
                j += 2 if src[j] == '\\' else 1
            yield ('rune', i, j + 1)
            i = j + 1
        else:
            i += 1


def fix(src, path):
    spans = list(tokens(src))
    in_literal = {}
    for kind, a, b in spans:
        in_literal[a] = (kind, b)
    skip = [(a, b) for kind, a, b in spans]

    def inside(pos):
        for a, b in skip:
            if a <= pos < b:
                return True
        return False

    edits = []
    manual = []
    for m in re.finditer(r'\b(?:fmt|log)\.(\w+)\s*\(', src):
        name = m.group(1)
        if inside(m.start()):
            continue
        if name not in FORMAT_FIRST and name not in FORMAT_SECOND:
            continue
        if name == 'println':
            continue
        # split the call's arguments at top level
        i, depth, args, start = m.end(), 1, [], m.end()
        while i < len(src) and depth:
            if i in in_literal:
                i = in_literal[i][1]
                continue
            ch = src[i]
            if ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
                if depth == 0:
                    args.append((start, i))
                    break
            elif ch == ',' and depth == 1:
                args.append((start, i))
                start = i + 1
            i += 1
        k = 1 if name in FORMAT_SECOND else 0
        if len(args) <= k:
            continue
        a, b = args[k]
        arg = src[a:b]
        lits = [(kind, s, e) for kind, s, e in spans if a <= s and e <= b and kind in ('string', 'raw')]
        rest = arg
        for kind, s, e in sorted(lits, key=lambda t: -t[1]):
            rest = rest[:s - a] + rest[e - a:]
        if not lits or rest.replace('+', '').strip():
            line = src.count('\n', 0, m.start()) + 1
            manual.append(f'{path}:{line}: {name}({arg.strip()[:60]})')
            continue
        for kind, s, e in lits:
            text = src[s:e]
            if '{{' in text or '}}' in text:
                continue
            if '{' in text or '}' in text:
                edits.append((s, e, text.replace('{', '{{').replace('}', '}}')))
    for s, e, text in sorted(edits, reverse=True):
        src = src[:s] + text + src[e:]
    return src, len(edits), manual


def main():
    write = '--write' in sys.argv
    for path in [p for p in sys.argv[1:] if p != '--write']:
        src = open(path).read()
        out, n, manual = fix(src, path)
        if n:
            print(f'{path}: {n} format string(s) with braces')
        for line in manual:
            if '{' in line or 'fmt' in line:
                print('  look at: ' + line)
        if write and n:
            open(path, 'w').write(out)


if __name__ == '__main__':
    main()
