#!/usr/bin/env python3
"""Writes examples/workshop/*.tri from the cue blocks of docs/GUIDE.md.

    python3 tools/guide-examples.py      (make examples)

The guide's blocks are one content file; the examples split it by topic.
test_docs_guide checks the two load to the same content hash.
"""
import os
import re

FILES = {
    "things.tri": ([1, 2, 3], "The things of the workshop: the types, enums and hierarchy of GUIDE.md\n"
                              "// sections 1 to 3."),
    "blueprints.tri": ([4, 5, 6, 7], "Blueprints: specific tools and fasteners, with defaults, variation and\n"
                                     "// alternatives (GUIDE.md sections 4 to 7)."),
    "operations.tri": ([8], "Patterns: operations that match a situation, with tags that share a\n"
                            "// value (GUIDE.md section 8)."),
    "levers.tri": ([9], "Arithmetic: a lever's torque from its force and arm, and a ratchet's reach\n"
                        "// (GUIDE.md section 9)."),
    "data.tri": ([10], "Data: comprehensions, built-in functions and hidden fields (GUIDE.md\n"
                       "// section 10)."),
    "text.tri": ([11], "Text: escapes, raw strings, regular expressions and interpolation\n"
                       "// (GUIDE.md section 11)."),
    "rooms.tri": ([12], "Definite clauses: doors between rooms, and the ways through them\n"
                        "// (GUIDE.md section 12)."),
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    doc = open(os.path.join(root, "docs", "GUIDE.md")).read()
    blocks, sec = [], None
    for m in re.finditer(r"^## (\d+)\. ([^\n]*)$|^```cue\n(.*?)\n```", doc, re.S | re.M):
        if m.group(1):
            sec = (int(m.group(1)), m.group(2))
        else:
            blocks.append((sec, m.group(3)))
    placed = {n for secs, _ in FILES.values() for n in secs}
    stray = sorted({s[0] for s, _ in blocks} - placed)
    if stray:
        raise SystemExit("guide-examples: no example file for section(s) %s; add them to FILES" % stray)
    out = os.path.join(root, "examples", "workshop")
    os.makedirs(out, exist_ok=True)
    for name, (secs, header) in FILES.items():
        parts, last = [], None
        for (n, title), src in blocks:
            if n not in secs:
                continue
            parts.append("// %d. %s\n\n%s" % (n, title, src) if n != last else src)
            last = n
        text = ("// %s\n//\n// Generated from docs/GUIDE.md: edit the guide, then rerun\n"
                "// `make examples`. test_docs_guide checks these files mean the same content.\n\n%s\n"
                % (header, "\n\n".join(parts)))
        with open(os.path.join(out, name), "w") as f:
            f.write(text)


if __name__ == "__main__":
    main()
