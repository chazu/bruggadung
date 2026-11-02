#!/usr/bin/env python3
"""Drives `triangle lsp` over stdio against a small content directory.

    python3 tests/lsp_test.py build/triangle
"""
import json
import os
import subprocess
import sys
import tempfile

TYPES = """// Something you can hold.
#Tool: {
    size: length
    // how worn it is
    wear: *0 | >=0
}

"steel": "mild" | "forged"
"""

INSTANCES = """// The miller's wrench.
wrench: #Tool & { size: 19mm }

spare: #Tool & { size: 13mm, wear: 2 }
"""

SHOP = """package shop
#Bench: { legs: int }
bench: #Bench & { legs: 4 }
other: wrench & {}
"""

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL", what)
    else:
        print("ok  ", what)


class Server:
    def __init__(self, exe):
        self.p = subprocess.Popen([exe, "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.next_id = 1
        self.notes = []

    def send(self, obj):
        body = json.dumps(obj).encode()
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.p.stdin.flush()

    def read(self):
        length = None
        while True:
            line = self.p.stdout.readline()
            if not line:
                raise EOFError("server closed its output")
            if line in (b"\r\n", b"\n"):
                break
            if line.lower().startswith(b"content-length:"):
                length = int(line.split(b":")[1])
        return json.loads(self.p.stdout.read(length))

    def request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            m = self.read()
            if m.get("id") == rid:
                return m
            self.notes.append(m)

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def diagnostics(self, uri):
        """The last diagnostics published for uri, after a round trip."""
        self.request("workspace/symbol", {"query": "\0none"})
        found = None
        for n in self.notes:
            if n.get("method") == "textDocument/publishDiagnostics" and n["params"]["uri"] == uri:
                found = n["params"]["diagnostics"]
        return found


def pos(text, needle, offset=0):
    i = text.index(needle) + offset
    line = text.count("\n", 0, i)
    return {"line": line, "character": i - (text.rfind("\n", 0, i) + 1)}


def main(exe):
    d = tempfile.mkdtemp()
    files = {"types.tri": TYPES, "instances.tri": INSTANCES}
    for name, text in files.items():
        with open(os.path.join(d, name), "w") as f:
            f.write(text)
    uri = {name: "file://" + os.path.join(d, name) for name in list(files) + ["shop.tri"]}

    s = Server(exe)
    init = s.request("initialize", {"processId": None, "rootUri": "file://" + d, "capabilities": {}})
    caps = init["result"]["capabilities"]
    check(caps["hoverProvider"] and caps["definitionProvider"], "initialize advertises hover and definition")
    s.notify("initialized", {})

    s.notify("textDocument/didOpen", {"textDocument": {"uri": uri["instances.tri"], "languageId": "triangle",
                                                       "version": 1, "text": INSTANCES}})
    check(s.diagnostics(uri["instances.tri"]) == [], "clean content has no diagnostics")
    check(s.diagnostics(uri["types.tri"]) == [], "files not open are published too")

    # hover on a type: its doc, its declaration, its supertypes
    h = s.request("textDocument/hover", {"textDocument": {"uri": uri["instances.tri"]},
                                         "position": pos(INSTANCES, "#Tool", 2)})["result"]
    v = h["contents"]["value"]
    check("**type** `#Tool`" in v and "Something you can hold." in v and "size: length" in v, "hover on a type")
    check("// how worn it is" in v, "hover keeps comments inside a declaration")
    check("\"steel\"" not in v, "hover stops before the next declaration")

    # hover on an instance: its spec with origins
    h = s.request("textDocument/hover", {"textDocument": {"uri": uri["instances.tri"]},
                                         "position": pos(INSTANCES, "wrench:")})["result"]
    v = h["contents"]["value"]
    check("The miller's wrench." in v and "Spec:" in v and "wear: 0" in v, "hover on an instance shows its spec")

    # definition across files
    r = s.request("textDocument/definition", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": pos(INSTANCES, "#Tool", 1)})["result"]
    check(len(r) == 1 and r[0]["uri"] == uri["types.tri"] and r[0]["range"]["start"] == {"line": 1, "character": 0}
          and r[0]["range"]["end"] == {"line": 1, "character": 5}, "definition of a type in another file")

    # references, with and without the declaration
    r = s.request("textDocument/references", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": pos(INSTANCES, "#Tool"),
                                              "context": {"includeDeclaration": True}})["result"]
    check(len(r) == 3, "references to a type, declaration included (%d)" % len(r))
    r = s.request("textDocument/references", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": pos(INSTANCES, "#Tool"),
                                              "context": {"includeDeclaration": False}})["result"]
    check(len(r) == 2, "references to a type, declaration left out")

    # document symbols
    r = s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri["instances.tri"]}})["result"]
    check([x["name"] for x in r] == ["wrench", "spare"], "document symbols")
    check(r[0]["detail"] == "The miller's wrench." and r[0]["range"]["end"]["line"] == 1, "symbol range and detail")

    r = s.request("workspace/symbol", {"query": "tool"})["result"]
    check([x["name"] for x in r] == ["#Tool"], "workspace symbols")

    # completion
    text = INSTANCES + "x: #T"
    s.notify("textDocument/didChange", {"textDocument": {"uri": uri["instances.tri"], "version": 2},
                                        "contentChanges": [{"text": text}]})
    r = s.request("textDocument/completion", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": pos(text, "#T", 2)})["result"]
    labels = {i["label"] for i in r["items"]}
    check({"#Tool", "wrench", "size", "wear", "length"} <= labels, "completion offers names, features, built-ins")
    item = next(i for i in r["items"] if i["label"] == "#Tool")
    check(item["textEdit"]["range"]["start"] == pos(text, "#T"), "completion replaces the word typed")
    r = s.request("textDocument/completion", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": {"line": 0, "character": 0}})["result"]

    # a syntax error, then a semantic one
    s.notify("textDocument/didChange", {"textDocument": {"uri": uri["instances.tri"], "version": 3},
                                        "contentChanges": [{"text": INSTANCES + "bad: #Tool & { size: }\n"}]})
    dg = s.diagnostics(uri["instances.tri"])
    check(len(dg) == 1 and dg[0]["severity"] == 1 and dg[0]["range"]["start"]["line"] == 4, "a syntax error")
    check(not dg[0]["message"].startswith("/"), "the message has no location prefix")
    # navigation still works on the declarations before the error
    r = s.request("textDocument/definition", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": pos(INSTANCES, "#Tool", 1)})["result"]
    check(len(r) == 1, "definition survives a syntax error")
    text = INSTANCES + "bad: #Tool & { size: \"big\" }\n"
    s.notify("textDocument/didChange", {"textDocument": {"uri": uri["instances.tri"], "version": 4},
                                        "contentChanges": [{"text": text}]})
    dg = s.diagnostics(uri["instances.tri"])
    check(len(dg) >= 1 and dg[0]["range"]["start"]["line"] == 4, "a conflict, at its line: %s" % (dg and dg[0]["message"]))
    # the spec on hover comes from the last good build
    h = s.request("textDocument/hover", {"textDocument": {"uri": uri["instances.tri"]},
                                         "position": pos(text, "spare")})["result"]
    check("Spec:" in h["contents"]["value"], "hover uses the last good build")
    s.notify("textDocument/didChange", {"textDocument": {"uri": uri["instances.tri"], "version": 5},
                                        "contentChanges": [{"text": INSTANCES}]})
    check(s.diagnostics(uri["instances.tri"]) == [], "fixing the error clears it")

    # a new file, not on disk, in a package
    s.notify("textDocument/didOpen", {"textDocument": {"uri": uri["shop.tri"], "languageId": "triangle",
                                                       "version": 1, "text": SHOP}})
    check(s.diagnostics(uri["shop.tri"]) == [], "a package file not yet saved")
    r = s.request("textDocument/definition", {"textDocument": {"uri": uri["shop.tri"]},
                                              "position": pos(SHOP, "#Bench &", 1)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"]["line"] == 1, "a package's plain name is its own")
    r = s.request("textDocument/definition", {"textDocument": {"uri": uri["shop.tri"]},
                                              "position": pos(SHOP, "wrench")})["result"]
    check(len(r) == 1 and r[0]["uri"] == uri["instances.tri"], "else the root's")
    r = s.request("textDocument/documentSymbol", {"textDocument": {"uri": uri["shop.tri"]}})["result"]
    check([x["name"] for x in r] == ["#Bench", "bench", "other"], "symbols in a package are unqualified")
    r = s.request("textDocument/completion", {"textDocument": {"uri": uri["instances.tri"]},
                                              "position": {"line": 4, "character": 0}})["result"]
    check("shop.bench" in {i["label"] for i in r["items"]}, "completion qualifies another package's names")

    # strings: escapes and raw strings lex as one token, and resolve by meaning
    STRINGS = ('#Mark: "a\\"b" | "plain"\n'
               '"a\\"b": "a\\"b c" | "a\\"b d"\n'
               '#Tag: { mark: #Mark, note: text }\n'
               't1: #Tag & { note: #"x\\"# , mark: "a\\u0022b" }\n'
               't2: #Tag & { note: "say \\"wrench\\"", mark: "plain" }\n')
    suri = "file://" + os.path.join(d, "strings.tri")
    s.notify("textDocument/didOpen", {"textDocument": {"uri": suri, "languageId": "triangle",
                                                       "version": 1, "text": STRINGS}})
    check(s.diagnostics(suri) == [], "escapes and raw strings load")
    r = s.request("textDocument/definition", {"textDocument": {"uri": suri},
                                              "position": pos(STRINGS, "a\\u0022b")})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == {"line": 1, "character": 0}, "an escaped spelling finds its atom")
    r = s.request("textDocument/references", {"textDocument": {"uri": suri}, "position": pos(STRINGS, "a\\\"b"),
                                              "context": {"includeDeclaration": True}})["result"]
    check(len(r) == 3, "references to an atom across spellings (%d)" % len(r))
    r = s.request("textDocument/hover", {"textDocument": {"uri": suri},
                                         "position": pos(STRINGS, "wrench")})["result"]
    check(r is None, "a quote escaped in a string doesn't end it")
    INTERP = STRINGS + 't4: #Tag & { note: "a \\(" #Tag ") b", mark: "plain" }\n'
    s.notify("textDocument/didChange", {"textDocument": {"uri": suri, "version": 2},
                                        "contentChanges": [{"text": INTERP}]})
    check(s.diagnostics(suri) == [], "an interpolation with a string inside loads")
    r = s.request("textDocument/references", {"textDocument": {"uri": suri}, "position": pos(INTERP, "#Tag"),
                                              "context": {"includeDeclaration": True}})["result"]
    check(len(r) == 4, "a name inside an interpolation's string is not a reference (%d)" % len(r))
    BADRX = STRINGS + 't3: #Tag & { note: =~#"(ab"# , mark: "plain" }\n'
    s.notify("textDocument/didChange", {"textDocument": {"uri": suri, "version": 2},
                                        "contentChanges": [{"text": BADRX}]})
    dg = s.diagnostics(suri)
    check(len(dg) == 1 and "missing )" in dg[0]["message"] and dg[0]["range"]["start"] == pos(BADRX, '#"(ab'),
          "a bad regex is reported on its pattern")
    s.notify("textDocument/didChange", {"textDocument": {"uri": suri, "version": 3},
                                        "contentChanges": [{"text": STRINGS}]})
    check(s.diagnostics(suri) == [], "and cleared when fixed")
    r = s.request("textDocument/definition", {"textDocument": {"uri": suri},
                                              "position": pos(STRINGS, "mark: \"plain", 1)})["result"]
    check(len(r) == 0, "a field label is not a declaration")

    # references, paths into other declarations, and lets
    REFS = ('#Fit: { instrument: #Tool, steps: [...length] }\n'
            'let gap = 1mm\n'
            'fit: #Fit & {\n'
            '    let twice = .instrument.size * 2\n'
            '    instrument: { size: 19mm, wear: 1 }\n'
            '    steps: [twice, .steps[0] + gap]\n'
            '}\n'
            'other: #Fit & { instrument: { size: fit.instrument.size } }\n'
            'nested: #Fit & { instrument: { size: .instrument.wear } }\n')
    ruri = "file://" + os.path.join(d, "refs.tri")
    s.notify("textDocument/didOpen", {"textDocument": {"uri": ruri, "languageId": "triangle",
                                                       "version": 1, "text": REFS}})
    dg = s.diagnostics(ruri)
    check(len(dg) == 1 and "the reference .instrument.wear" in dg[0]["message"] and
          dg[0]["range"]["start"] == pos(REFS, ".instrument.wear"), "a reference's conflict is reported on it")
    REFS = REFS.replace("nested: #Fit & { instrument: { size: .instrument.wear } }\n", "")
    s.notify("textDocument/didChange", {"textDocument": {"uri": ruri, "version": 2},
                                        "contentChanges": [{"text": REFS}]})
    check(s.diagnostics(ruri) == [], "references and lets load")
    r = s.request("textDocument/definition", {"textDocument": {"uri": ruri},
                                              "position": pos(REFS, ".instrument.size", 3)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(REFS, "size: 19mm"), "a reference goes to its field")
    r = s.request("textDocument/definition", {"textDocument": {"uri": ruri},
                                              "position": pos(REFS, ".steps[0]", 2)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(REFS, "steps: [t"), "and through a list index to its list")
    h = s.request("textDocument/hover", {"textDocument": {"uri": ruri},
                                         "position": pos(REFS, ".instrument.size", 3)})["result"]
    check("**reference** `.instrument.size` in `fit`" in h["contents"]["value"] and "19mm" in h["contents"]["value"],
          "hover on a reference shows its value")
    r = s.request("textDocument/definition", {"textDocument": {"uri": ruri},
                                              "position": pos(REFS, "twice,", 1)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(REFS, "twice ="), "a let's use goes to its let")
    r = s.request("textDocument/definition", {"textDocument": {"uri": ruri},
                                              "position": pos(REFS, "+ gap", 3)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(REFS, "gap ="), "and to the file's let")
    h = s.request("textDocument/hover", {"textDocument": {"uri": ruri}, "position": pos(REFS, "+ gap", 3)})["result"]
    check("**let** `gap`" in h["contents"]["value"] and "let gap = 1mm" in h["contents"]["value"], "hover on a let")
    r = s.request("textDocument/definition", {"textDocument": {"uri": ruri},
                                              "position": pos(REFS, "fit.instrument", 1)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(REFS, "fit: #Fit"), "a path goes to its declaration")

    # references to a field, from a reference or from its label
    ctx = {"includeDeclaration": True}
    r = s.request("textDocument/references", {"textDocument": {"uri": ruri}, "position": pos(REFS, ".instrument.size", 3),
                                              "context": ctx})["result"]
    check(sorted(x["range"]["start"]["line"] for x in r) == [3, 4], "references to a field, from a reference")
    r = s.request("textDocument/references", {"textDocument": {"uri": ruri}, "position": pos(REFS, "size: 19mm"),
                                              "context": ctx})["result"]
    check(sorted(x["range"]["start"]["line"] for x in r) == [3, 4], "and from its label")
    r = s.request("textDocument/references", {"textDocument": {"uri": ruri}, "position": pos(REFS, "size: 19mm"),
                                              "context": {"includeDeclaration": False}})["result"]
    check([x["range"]["start"]["line"] for x in r] == [3], "without the label itself")
    r = s.request("textDocument/references", {"textDocument": {"uri": ruri}, "position": pos(REFS, ".steps[0]", 2),
                                              "context": ctx})["result"]
    check(len(r) == 2, "a list's references count its items as the list (%d)" % len(r))

    # completion of a reference: the fields at the path written so far
    def complete(text, at):
        s.notify("textDocument/didChange", {"textDocument": {"uri": ruri, "version": 9},
                                            "contentChanges": [{"text": text}]})
        s.diagnostics(ruri)
        res = s.request("textDocument/completion", {"textDocument": {"uri": ruri}, "position": pos(text, at, len(at))})
        return res["result"]["items"]
    typing = REFS.replace("steps: [twice,", "steps: [.instrument.w,")
    items = complete(typing, ".instrument.w")
    labels = sorted(i["label"] for i in items)
    check(labels == ["size", "wear"], "completion after .instrument. offers its type's fields (%s)" % labels)
    check(items and items[0]["textEdit"]["range"]["start"] == pos(typing, ".instrument.w", 12),
          "and replaces only the last segment")
    typing = REFS.replace("steps: [twice,", "steps: [.,")
    labels = sorted(i["label"] for i in complete(typing, "[."))
    check(labels == ["instrument", "steps"], "after a lone . the declaration's fields (%s)" % labels)
    s.notify("textDocument/didChange", {"textDocument": {"uri": ruri, "version": 10},
                                        "contentChanges": [{"text": REFS}]})
    check(s.diagnostics(ruri) == [], "back to clean")

    # comprehensions: a variable goes to its for, and its path's head counts
    COMP = ('#Pt: { input: int, output: int }\n'
            '#Cv: { points: [...#Pt] }\n'
            'let table = [[1, 2], [3, 4]]\n'
            'cv: #Cv & { points: [for i, p in table if i >= 0 { input: p[0], output: p[1] }] }\n')
    curi = "file://" + os.path.join(d, "comp.tri")
    s.notify("textDocument/didOpen", {"textDocument": {"uri": curi, "languageId": "triangle",
                                                       "version": 1, "text": COMP}})
    check(s.diagnostics(curi) == [], "comprehensions load")
    r = s.request("textDocument/definition", {"textDocument": {"uri": curi},
                                              "position": pos(COMP, "p[0]")})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(COMP, "p in"), "a variable goes to its for")
    r = s.request("textDocument/definition", {"textDocument": {"uri": curi},
                                              "position": pos(COMP, "i >=")})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(COMP, "i, p"), "and its key to the same for")
    h = s.request("textDocument/hover", {"textDocument": {"uri": curi}, "position": pos(COMP, "p[1]")})["result"]
    check("**for** `p`" in h["contents"]["value"], "hover on a variable names its for")
    r = s.request("textDocument/definition", {"textDocument": {"uri": curi},
                                              "position": pos(COMP, "table if", 1)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(COMP, "table ="), "a for's source can be a let")

    # built-in functions and hidden fields
    FN = ('#Fn: { n: int, s: text }\n'
          'fn: #Fn & {\n'
          '    _base: 3\n'
          '    n: len([1, 2]) + _base\n'
          '    s: strings.ToUpper("a")\n'
          '}\n')
    furi = "file://" + os.path.join(d, "fn.tri")
    s.notify("textDocument/didOpen", {"textDocument": {"uri": furi, "languageId": "triangle",
                                                       "version": 1, "text": FN}})
    check(s.diagnostics(furi) == [], "built-ins and hidden fields load")
    h = s.request("textDocument/hover", {"textDocument": {"uri": furi}, "position": pos(FN, "strings.ToUpper", 9)})["result"]
    check(h and "**function** `strings.ToUpper(string)`" in h["contents"]["value"], "hover on a built-in function")
    r = s.request("textDocument/definition", {"textDocument": {"uri": furi},
                                              "position": pos(FN, "+ _base", 3)})["result"]
    check(len(r) == 1 and r[0]["range"]["start"] == pos(FN, "_base:"), "a hidden field's use goes to it")
    h = s.request("textDocument/hover", {"textDocument": {"uri": furi}, "position": pos(FN, "+ _base", 3)})["result"]
    check("**hidden field** `_base`" in h["contents"]["value"], "and hovers as one")
    items = s.request("textDocument/completion", {"textDocument": {"uri": furi},
                                                  "position": pos(FN, "len(")})["result"]["items"]
    check("strings.ToUpper" in {i["label"] for i in items}, "completion offers the built-in functions")

    r = s.request("textDocument/hover", {"textDocument": {"uri": uri["instances.tri"]},
                                         "position": {"line": 0, "character": 3}})
    check(r["result"] is None, "hover in a comment is empty")
    r = s.request("textDocument/formatting", {"textDocument": {"uri": uri["instances.tri"]}, "options": {}})
    check(r.get("error", {}).get("code") == -32601, "an unsupported request is an error")

    s.request("shutdown", None)
    s.notify("exit", None)
    check(s.p.wait(timeout=5) == 0, "exits cleanly after shutdown")

    print("%d failed" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "build/triangle"))
