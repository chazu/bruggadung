#!/usr/bin/env python3
"""The Objective-C lab's names, and the Odin names the port gives them.

Reads lab/src's headers and prints a table every module's port follows, so
that modules ported apart call each other by the same names:

  - classes and protocols: BG stripped, Ada_Case (BGWorld -> World)
  - methods: the class's snake name, then the selector's first keyword in
    snake case, with more keywords added only where two of the class's
    selectors would otherwise meet (setField:of:value: and setField:of:text:
    -> world_set_field_of_value, world_set_field_of_text). A class method
    whose name starts with the class's drops the repeat
    (+worldWithContent:... -> world_with_content).
  - C functions and inline functions: BG stripped, snake case
    (BGIndexNew -> index_new)
  - typedefs: BG stripped, Ada_Case; enum constants: the enum's common prefix
    stripped, Ada_Case; #define constants: SCREAMING_SNAKE without BG

A name that is an Odin keyword or a builtin it would shadow takes a
trailing underscore.

  python3 lab/odin/port/names.py > lab/odin/port/NAMES.md
"""
import os
import re
import sys

SRC = os.path.join(os.path.dirname(__file__), '..', '..', 'src')

KEYWORDS = set('''in not_in map proc struct union enum bit_set bit_field dynamic context defer when where
cast auto_cast transmute distinct using or_else or_return or_break or_continue package import foreign
matrix typeid switch case fallthrough break continue return for if else do nil true false
len cap size_of align_of offset_of type_of min max abs clamp new free delete make append copy
clear resize reserve swizzle conj real imag jmag kmag soa_zip soa_unzip raw_data panic assert
print println printf string cstring rune any rawptr bool int uint'''.split())


def snake(name):
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', name)
    s = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', s)
    return s.lower()


def ada(name):
    out = '_'.join(p[:1].upper() + p[1:] for p in snake(name).split('_'))
    # an initialism stays one: EntityID -> Entity_ID, not Entity_Id
    return re.sub(r'_Id$', '_ID', re.sub(r'_Id_', '_ID_', out))


def safe(name):
    return name + '_' if name in KEYWORDS else name


def strip_bg(name):
    return name[2:] if name.startswith('BG') and len(name) > 2 and name[2].isupper() else name


TYPES = [
    (r'^BGEntityID$', 'Entity_ID'), (r'^BGTime$', 'Time'), (r'^NSUInteger$', 'uint'),
    (r'^NSInteger$', 'int'), (r'^BOOL$', 'bool'), (r'^bool$', 'bool'), (r'^int$', 'i32'),
    (r'^unsigned$', 'u32'), (r'^size_t$', 'uint'), (r'^double$', 'f64'), (r'^float$', 'f32'),
    (r'^char$', 'u8'), (r'^void$', ''),
    (r'^(u?int)(8|16|32|64)_t$', None),
    (r'^const char \*$', 'cstring'), (r'^char \*$', 'cstring'),
    (r'^NSString \*$', 'string'), (r'^NSMutableString \*$', '^strings.Builder'),
    (r'^NSString \*\*$', '^string'), (r'^NSArray \*$', '[]T'), (r'^NSMutableArray \*$', '^[dynamic]T'),
    (r'^NSArray \*\*$', '^[]T'), (r'^NSDictionary \*$', 'map[string]T'),
    (r'^NSError \*\*$', '^string'), (r'^id$', 'rawptr'),
    (r'^const void \*$', 'rawptr'), (r'^void \*$', 'rawptr'),
    (r'^id <(\w+)>$', None), (r'^id<(\w+)>$', None),
]


def odin_type(t):
    t = ' '.join(t.replace('*', ' * ').split()).replace(' *', ' *').replace('* *', '**')
    t = t.replace(' * *', ' **').strip()
    t = re.sub(r'\s+\*', ' *', t)
    for pat, rep in TYPES:
        m = re.match(pat, t)
        if not m:
            continue
        if rep is not None:
            return rep
        if pat.startswith(r'^(u?int)'):
            return ('u' if m.group(1) == 'uint' else 'i') + m.group(2)
        return ada(strip_bg(m.group(1)))
    const = t.startswith('const ')
    base = t[6:] if const else t
    stars = base.count('*')
    base = base.replace('*', '').strip()
    if base.startswith('struct '):
        base = base[7:]
    inner = {'BGEntityID': 'Entity_ID', 'char': 'u8', 'int32_t': 'i32', 'int64_t': 'i64',
             'uint64_t': 'u64', 'uint32_t': 'u32', 'uint8_t': 'u8', 'NSUInteger': 'uint',
             'TriNode': 'tri.Node', 'TriContent': 'tri.Content', 'TriArena': 'tri.Arena',
             'TriIndex': 'tri.Index', 'TriType': 'tri.Type', 'TriMatch': 'tri.Match'}.get(base)
    if inner is None:
        inner = ada(strip_bg(base)) if base.startswith('BG') else base
    if stars == 0:
        return inner
    if stars == 1:
        # a pointer to many (an out array) or to one: the port decides by the
        # comment; ^ by default
        return '^' + inner
    return '^' * stars + inner


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def parse_methods(body):
    """(class?, selector, params, return) for each - or + declaration."""
    out = []
    for m in re.finditer(r'([-+])\s*\(([^)]*)\)\s*([^;{]+);', body):
        kind, ret, rest = m.group(1), m.group(2).strip(), ' '.join(m.group(3).split())
        parts = re.findall(r'(\w+)\s*:\s*\(([^)]*)\)\s*(\w+)', rest)
        if parts:
            sel = [p[0] for p in parts]
            params = [(p[2], p[1].strip()) for p in parts]
        else:
            sel = [rest.strip()]
            params = []
        out.append((kind, sel, params, ret))
    return out


SENDERS = {'world', 'committer', 'scheduler'}


def method_names(cls, methods, protocol=False):
    """The Odin proc name of each method, keywords added only to tell apart.
    A protocol method whose first keyword names its sender (world:,
    committer:, scheduler:) is named from its second."""
    cs = snake(cls)
    if protocol:
        methods = [(k, sel[1:] if len(sel) > 1 and snake(sel[0]) in SENDERS else sel, p, r)
                   for k, sel, p, r in methods]
    names = {}
    for depth in range(1, 8):
        groups = {}
        for i, (kind, sel, params, ret) in enumerate(methods):
            if i in names:
                continue
            n = '_'.join(snake(k) for k in sel[:depth])
            groups.setdefault(n, []).append(i)
        for n, idx in groups.items():
            if len(idx) == 1 or all(len(methods[i][1]) <= depth for i in idx):
                for i in idx:
                    names[i] = n
    out = []
    for i, (kind, sel, params, ret) in enumerate(methods):
        n = names.get(i, '_'.join(snake(k) for k in sel))
        if kind == '+' and n.startswith(cs + '_'):
            n = n[len(cs) + 1:]
        out.append(safe(cs + '_' + n))
    return out


def main():
    headers = []
    for root, _, files in os.walk(SRC):
        for f in sorted(files):
            if f.endswith('.h') and f != 'BGComponents.h':
                headers.append(os.path.join(root, f))
    headers.sort()
    seen_types = {}
    print('# Names in the port\n')
    print('Generated by `port/names.py` from lab/src\'s headers: do not edit; rerun it.')
    print('Every module\'s port uses these names, so modules ported apart meet.\n')
    print('Parameter types are a mechanical first guess (a `^T` may be a `[^]T` out')
    print('array, a `[]T` an NSArray of what the comment says): the module that')
    print('implements a method settles its signature, and callers follow it.\n')
    for path in headers:
        rel = os.path.relpath(path, SRC)
        raw = open(path).read()
        text = strip_comments(raw)
        print(f'## {rel}\n')
        # typedefs
        for m in re.finditer(r'typedef\s+(struct|enum|union)?\s*(\w+)?\s*\{(.*?)\}\s*(\w+)\s*;', text, re.S):
            kind, _, body, name = m.groups()
            od = ada(strip_bg(name))
            seen_types.setdefault(od, []).append(rel)
            print(f'- type `{name}` → `{od}` ({kind or "typedef"})')
            if kind == 'enum':
                consts = [c.split('=')[0].strip() for c in body.split(',') if c.strip()]
                if all(c.startswith(name) and len(c) > len(name) for c in consts):
                    pre = name
                else:
                    pre = os.path.commonprefix(consts) if len(consts) > 1 else 'BG'
                while pre and not all(len(c) > len(pre) and (c[len(pre)].isupper() or c[len(pre)].isdigit()) for c in consts):
                    pre = pre[:-1]
                for c in consts:
                    member = c[len(pre):] if c.startswith(pre) and len(c) > len(pre) else strip_bg(c)
                    print(f'  - `{c}` → `.{safe(ada(member))}`')
        for m in re.finditer(r'typedef\s+(?!struct|enum|union)([^;{}]+?)\s+\*?\s*(\w+)\s*;', text):
            if '(' in m.group(0):
                continue
            name = m.group(2)
            od = ada(strip_bg(name))
            seen_types.setdefault(od, []).append(rel)
            print(f'- type `{name}` → `{od}` (= {odin_type(m.group(1))})')
        for m in re.finditer(r'^#define\s+(BG\w+)(\(([^)]*)\))?', raw, re.M):
            name, args = m.group(1), m.group(2)
            if name.endswith('_H'):
                continue
            if args:
                print(f'- macro `{name}{args}` → `{safe(snake(strip_bg(name)))}` (a proc)')
            else:
                print(f'- constant `{name}` → `{snake(strip_bg(name)).upper()}`')
        # extern globals: a table of constants is SCREAMING, a variable snake
        for m in re.finditer(r'^extern\s+([^;]*?)\b(BG\w+)\s*(\[[^\]]*\])?\s*;', text, re.M):
            ctype, name, arr = m.groups()
            if arr:
                print(f'- global `{name}{arr}` → `{snake(strip_bg(name)).upper()}` (a table)')
            else:
                print(f'- global `{name}` → `{snake(strip_bg(name))}` (a variable)')
        # opaque and function-pointer typedefs
        for m in re.finditer(r'typedef\s+struct\s+(\w+)\s+(\w+)\s*;', text):
            name = m.group(2)
            print(f'- type `{name}` → `{ada(strip_bg(name))}` (opaque: the module that has it defines it)')
        for m in re.finditer(r'typedef\s+[^;()]*\(\s*\*\s*(\w+)\s*\)\s*\(', text):
            name = m.group(1)
            print(f'- type `{name}` → `{ada(strip_bg(name))}` (a procedure type)')
        # functions (prototypes and static inlines), parameters balanced so
        # a pointer to an array, (*corners)[3], is one
        for m in re.finditer(r'^(?:static inline\s+)?([A-Za-z_][\w \*]*?)\s*\b(BG\w+)\s*\(', text, re.M):
            ret, name = m.groups()
            if ret.strip() in ('return', 'typedef', '#define') or name.endswith('_H') or ret.strip().startswith('typedef'):
                continue
            depth, j = 1, m.end()
            while j < len(text) and depth:
                depth += {'(': 1, ')': -1}.get(text[j], 0)
                j += 1
            after = text[j:j + 40].lstrip()
            if not after or after[0] not in ';{':
                continue
            print(f'- function `{name}` → `{safe(snake(strip_bg(name)))}`')
        # protocols and classes
        for m in re.finditer(r'@(protocol|interface)\s+(\w+)\s*(:\s*\w+)?\s*(\([^)]*\))?\s*(<[^>]*>)?(.*?)@end', text, re.S):
            what, name, sup, cat, protos, body = m.groups()
            body = re.sub(r'^\s*\{.*?\}', '', body, count=1, flags=re.S)
            od = ada(strip_bg(name))
            label = 'protocol' if what == 'protocol' else 'class'
            extra = f' {protos}' if protos else ''
            print(f'- {label} `{name}`{extra} → `{od}`' + (' (a struct of procs, `data: rawptr` first: PORTING.md)' if label == 'protocol' else f' (`^{od}`)'))
            methods = parse_methods(body)
            names = method_names(strip_bg(name), methods, label == 'protocol')
            for (kind, sel, params, ret), n in zip(methods, names):
                objc = kind + ''.join(f'{k}:' for k in sel) if params else kind + sel[0]
                is_init = kind == '-' and sel[0].startswith('init')
                ps = ([] if kind == '+' or label == 'protocol' or is_init else [f'self: ^{od}'])
                if label == 'protocol':
                    ps = ['data: rawptr']
                ps += [f'{safe(p)}: {odin_type(t)}' for p, t in params]
                r = f'^{od}' if ret == 'instancetype' or is_init else odin_type(ret)
                sig = f'proc({", ".join(ps)})' + (f' -> {r}' if r else '')
                field = n[len(snake(strip_bg(name))) + 1:] if label == 'protocol' else n
                print(f'  - `{objc}` → `{field}` :: {sig}')
        print()
    dups = {k: v for k, v in seen_types.items() if len(v) > 1}
    if dups:
        print('## Type names that meet\n')
        for k, v in sorted(dups.items()):
            print(f'- `{k}`: {", ".join(v)}')


if __name__ == '__main__':
    main()
