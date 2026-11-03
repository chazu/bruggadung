# Agent and AI information

## TRANSGRESSIONS PUNISHABLE BY DEATH

DO NOT `git revert` AND DO NOT clobber files with git `checkout`  or run
any other destructive git command. You will be shot and another better AI
will take your place.

## Building

The lab is Odin: `src/` is one Odin package, `lab`, linking Triangle's C library
(`../triangle`, built by its Makefile). The Odin release is pinned in
`../ci` (install-odin.sh, Dockerfile); `../ci/README.md` says what each
platform needs.

```sh
make              # build/<platform>/lab, with -vet -strict-style
make watcher      # build/<platform>/watcher: a world in a window (raylib)
make test         # the tests (TEST=name for those whose names contain it)
make check        # the tests, and every scenario's hashes
make asan         # the tests under AddressSanitizer (Linux)
make gen          # src/components.odin, after a content change to components
```

Run `make check` before committing a change to code. It must pass on macOS
and Linux. It type-checks the watcher, but doesn't link it: the lab itself
never links raylib, so the tests need no display.

## Writing the code

The lab was ported from Objective-C literally (README.md, "Notes on the
code"), and keeps its shape. Keep to it:

- **Objects keep reference counts** (`object.odin`): a class's struct starts
  with `using object: Object`, `object_new` makes one, and `retain`,
  `release` and `autorelease` work as they did. Autorelease pools drain
  once a test and at the end of main; each takes the temporary allocator
  back to where it was, so a temp string lives until then.
- **Never keep a temporary string or slice in an object**: clone it into
  `context.allocator`, and free it in the dealloc.
- **Protocols are structs of procedures** (`protocols.odin`), `data` first.
  A nil procedure is a method the conformer doesn't have.
- A `cstring` is for C's strings: interned names, Triangle's, records'
  text. An Odin `==` on cstrings compares contents, and a nil cstring
  equals `""`.

## Printing what printf printed

The scenario hashes are of printed text, which the Objective-C lab printed
with printf. Odin's fmt is not printf. `make test` checks the rules below
against libc (the `formatting` test, `test_formatting.odin`), so a new Odin
release that changes them shows up there.

- A width on a number pads with zeros unless the format has the space flag:
  printf's `%10d` is `% 10d`, `%10.1f` is `% 10.1f`. A `0` flag (`%016x`)
  pads with zeros in both. Strings pad with spaces (`%-14s`).
- `{` starts a placeholder: a literal brace is `{{`, and `}}` for `}`.
  Triangle descriptions are full of them: `"#A & {{ x: %d }}"`.
- `%d` prints any integer; there's no `%lld` or `%llu`.

## Writing Odin that does what it says

- **A range loop's end is evaluated on every iteration**: `for _ in 0 ..<
  f()` calls `f` each time round. Bind it to a variable first when it
  costs or has a side effect.
- `a if c else b` evaluates only the branch taken; it can't break before
  `else` across lines.
- A `@(private = "file")` name doesn't clash with the same name in another
  file of the Odin package.
- C's `context` is Odin's keyword: such a field or parameter is `context_`.

## The simulation is deterministic, everywhere

Every scenario must end in the same state on every platform.
`ci/scenario-hashes.txt` holds each scenario's hashes and `make check`
compares. A change meant to change a scenario regenerates it (`make
scenarios > ci/scenario-hashes.txt`) and says so in the commit.

- A sort orders ties fully (by ID, say): `slice.sort_by` isn't stable.
- Odin's `map` iterates in no fixed order: sort the keys where the order
  could reach output or state.
- Integer arithmetic only, where the simulation is concerned: the same
  widths and truncating division the C had.

## Content

Triangle content is laid out by topic: see content/README.md, and
../CLAUDE.md for the terminology rule.
