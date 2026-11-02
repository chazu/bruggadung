#!/usr/bin/env python3
"""The triangle command: export, and inspect on an instance without a spec.

    python3 tests/cli_test.py build/triangle      (make cli-test)
"""
import json
import subprocess
import sys

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def run(exe, *args):
    p = subprocess.run([exe, *args], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


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
    print("%d failed" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "build/triangle"))
