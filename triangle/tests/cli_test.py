#!/usr/bin/env python3
"""The triangle command: export, inspect on an instance without a spec, and fmt.

    python3 tests/cli_test.py build/triangle      (make cli-test)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def run(exe, *args, input=None):
    p = subprocess.run([exe, *args], capture_output=True, text=True, input=input)
    return p.returncode, p.stdout, p.stderr


MESSY = """

let  socket=30mm
let reach_of_arm = 2m
#Wrench: #Tool&{
  size:length @field(content)
        material : "steel"|"brass"   @field(content, saved)
\t// how heavy
  mass:mass   @field(content)
}



w:#Wrench&{ size:>= 10mm & <=24mm,mass:1kg }
shelf: #Shelf & {
  list: [ 13mm,17mm ]
       n: len( .list ) * 2
  ok: !false && .n>2
  steps: [
     #Do & {op: "take"},
  ]
}
spanner: #Wrench &
({ size: 13mm } | { size: 17mm })   
table: { rows: [[1, 2],
  [3, 4]] }
"""

TIDY = """let socket       = 30mm
let reach_of_arm = 2m
#Wrench: #Tool & {
    size:     length              @field(content)
    material: "steel" | "brass"   @field(content, saved)
    // how heavy
    mass:     mass                @field(content)
}


w:       #Wrench & { size: >=10mm & <=24mm, mass: 1kg }
shelf:   #Shelf & {
    list: [13mm, 17mm]
    n:    len(.list) * 2
    ok:   !false && .n > 2
    steps: [
        #Do & { op: "take" },
    ]
}
spanner: #Wrench &
    ({ size: 13mm } | { size: 17mm })
table:   { rows: [[1, 2],
                  [3, 4]] }
"""


def test_fmt(exe):
    rc, out, err = run(exe, "fmt", "-", input=MESSY)
    check(rc == 0 and out == TIDY, "fmt lays source out: spacing, indentation, alignment (%s)" % err.strip())
    rc, out, _ = run(exe, "fmt", "-", input=TIDY)
    check(rc == 0 and out == TIDY, "fmt is idempotent")
    rc, _, err = run(exe, "fmt", "-", input='x: "open\n')
    check(rc == 1 and "1:4: unterminated string" in err, "fmt refuses source it can't scan")
    for d in ("examples/workshop", "../lab/content"):
        if os.path.isdir(d):
            rc, out, _ = run(exe, "fmt", "--check", d)
            check(rc == 0 and out == "", "%s is formatted" % d)
    # in place: a directory's files rewritten, its meaning unchanged
    tmp = tempfile.mkdtemp()
    try:
        shutil.copytree("examples/workshop", os.path.join(tmp, "ws"))
        path = os.path.join(tmp, "ws", "things.tri")
        with open(path) as f:
            tidy = f.read()
        with open(path, "w") as f:
            f.write("\n".join(("  " + l.strip() + "   ") if l.strip() else l for l in tidy.split("\n")))
        _, before, _ = run(exe, "check", os.path.join(tmp, "ws"))
        rc, out, _ = run(exe, "fmt", "--check", os.path.join(tmp, "ws"))
        check(rc == 1 and os.path.normpath(out.strip()) == os.path.normpath(path), "--check lists what it would change, and fails")
        rc, _, err = run(exe, "fmt", os.path.join(tmp, "ws"))
        with open(path) as f:
            check(rc == 0 and f.read() == tidy, "fmt rewrites in place (%s)" % err.strip())
        _, after, _ = run(exe, "check", os.path.join(tmp, "ws"))
        check(before == after and "hash" in after, "and the content hashes the same")
    finally:
        shutil.rmtree(tmp)


def test_topics(exe):
    # a directory stands for its .tri files and its subdirectories'; a file
    # formatted in a topic directory is checked against its content root
    tmp = tempfile.mkdtemp()
    try:
        root = os.path.join(tmp, "content")
        os.makedirs(os.path.join(root, "topic"))
        with open(os.path.join(root, "things.tri"), "w") as f:
            f.write("#Tool: { size: length }\n")
        kept = os.path.join(root, "topic", "kept.tri")
        with open(kept, "w") as f:
            f.write("kept:   #Tool & { size: 22mm }\n")
        with open(os.path.join(root, ".hidden.tri"), "w") as f:
            f.write("this does not parse\n")
        rc, out, err = run(exe, "check", root)
        check(rc == 0 and "1 instances" in out, "check loads a topic directory with its root (%s)" % err.strip())
        rc, _, err = run(exe, "check", os.path.join(root, "topic"))
        check(rc != 0 and "#Tool" in err, "a topic directory alone is not the content")
        rc, out, _ = run(exe, "fmt", "--check", kept)
        check(rc == 1 and os.path.normpath(out.strip()) == os.path.normpath(kept), "fmt --check names a file in a topic directory")
        rc, _, err = run(exe, "fmt", kept)
        with open(kept) as f:
            check(rc == 0 and f.read() == "kept: #Tool & { size: 22mm }\n",
                  "and formats it, its meaning checked over the root (%s)" % err.strip())
    finally:
        shutil.rmtree(tmp)


def main(exe):
    ws = "examples/workshop"
    rc, out, err = run(exe, "export", "-e", "wrench_19", "-e", "nut", "-e", "gearbox", ws)
    check(rc == 0, "export succeeds (%s)" % err.strip())
    d = json.loads(out)
    check(d["wrench_19"] == {"mass": "850g", "material": "steel", "size": "19mm", "wear": 0},
          "a blueprint's spec: quantities keep their units, numbers are numbers")
    check(d["nut"]["size"] == ">=10mm & <=24mm", "an open value is its constraint")
    check(d["gearbox"]["teeth"] == [24, 48], "lists are arrays")
    rc, out, _ = run(exe, "export", "--seed", "1", "-e", "nut", ws)
    check(rc == 0 and json.loads(out)["nut"]["size"] == "12.4mm", "--seed constructs an entity")
    rc, out, _ = run(exe, "export", "--types", "-e", "loosen", ws)
    lo = json.loads(out)["loosen"]
    check(lo["#type"] == "#Roles" and lo["target"]["state"] == "tight", "a pattern as written, with --types")
    rc, _, err = run(exe, "export", "--concrete", "-e", "loosen", ws)
    check(rc == 1 and "loosen.instrument.size is not concrete: length" in err, "--concrete refuses open values")
    rc, out, _ = run(exe, "export", "--yaml", "-e", "gearbox", ws)
    check(rc == 0 and out.startswith("gearbox:\n") and "  teeth:\n    - 24\n    - 48\n" in out, "YAML")
    rc, out, _ = run(exe, "export", ws)
    check(rc == 0 and len(json.loads(out)) == 18, "every instance by default")
    rc, _, err = run(exe, "export", "-e", "nonesuch", ws)
    check(rc == 1 and "no instance named nonesuch" in err, "an unknown name is an error")
    rc, _, err = run(exe, "inspect", "loosen", ws)
    check(rc == 1 and "loosen has no spec" in err and "not concrete and has no bounds" in err and "hammer" not in err,
          "inspect says why an instance has no spec")
    test_fmt(exe)
    test_topics(exe)
    print("%d failed" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "build/triangle"))
