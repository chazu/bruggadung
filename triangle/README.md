# Triangle

Triangle is bruggadung's content language: TDL's typed feature structure
semantics with CUE-style syntax, specified in
[CONTENT_LANGUAGE.md](../CONTENT_LANGUAGE.md). This directory is a prototype
of its engine. It is plain C11 with no dependencies, so it builds without the mulle
toolchain.

Documentation:

- [docs/GUIDE.md](docs/GUIDE.md): learn the language by building one content
  file, from types to blueprints, variation, patterns, arithmetic, and clauses
- [docs/REFERENCE.md](docs/REFERENCE.md): the grammar, built-in types, units,
  every attribute, the rules for defaults and variation, and every diagnostic
- [docs/API.md](docs/API.md): embedding the engine from C and Objective-C
- [The command-line tool and the editor](#the-command-line-tool-and-the-editor):
  `triangle check`, `triangle inspect`, the language server, and Emacs

```sh
make            # library and tests
make test       # the leak check, then the tests
make asan       # rebuild and test with AddressSanitizer and UBSan
make objc       # the Objective-C wrapper and its test (macOS: Foundation)
make game       # build/libtriangle-game.a, without the TDL front end
make install    # build/triangle into ~/.local/bin (PREFIX=... to change)
make lsp-test   # drive the language server over stdio
make emacs-test # the Emacs mode's tests
make examples   # regenerate examples/workshop from docs/GUIDE.md
./build/tri-components BG content/*.tri > components.h   # C structs for the components
TRI_PROPS_SCALE=10 ./build/test properties     # ten times the randomised cases
```

## Layout

| File | Contents |
| --- | --- |
| `include/triangle.h` | Public API |
| `src/parse.c` | Lexer and parser for the CUE-style syntax |
| `src/tdl.c` | TDL front end: DELPH-IN type description language into the same syntax tree |
| `src/units.c` | Quantity literals and exact conversion to quanta |
| `src/types.c` | Hierarchy: enums, conjunction types, disjunction and typed-list types, completion (`glb[...]`), deterministic IDs, bit-vector meets, feature introduction |
| `src/fs.c` | Nodes, Tomabechi unification, lazy nodes for recursive types, copying with structure sharing, subsumption, generalisation of two structures, paths, printing |
| `src/qc.c` | Quick check: path vectors, learning paths from failures, pattern indexes |
| `src/load.c` | Building from syntax, type expansion, instance variants, patterns and specs, defaults, variation and construction, derived fields, matching and explaining, memory decay, the inspector, the content hash |
| `src/runtime.c` | Docstrings, pattern families and their compiled indexes, saves |
| `src/arith.c` | Interval arithmetic over quantities, with units |
| `src/clause.c` | Definite clauses: resolution with a depth limit |
| `tools/tri-components.c` | Generates the C structs for a content build's components |
| `tools/triangle.c` | The `triangle` command: check, inspect, components, and the language server |
| `tools/lsp.c`, `tools/json.c` | The language server, and the JSON it speaks |
| `emacs/` | `triangle-mode`, the Emacs major mode, with its tests |
| `examples/workshop/` | The guide's content as `.tri` files, by topic |
| `tools/guide-examples.py` | Writes `examples/workshop` from the guide (`make examples`) |
| `src/xtree.c` | Syntax tree printing and construction |
| `src/util.c` | Arenas, symbols, maps, diagnostics |
| `objc/` | `BGContent`, the Objective-C wrapper, with its test; runs under Apple's runtime and mulle-objc |
| `docs/` | The guide, the language reference, and the embedding API |
| `tests/` | Core tests; the three scenarios and the example file from CONTENT_LANGUAGE.md; every feature; randomised property tests and source fuzzing; a small TDL grammar; a leak check against a counting allocator |
| `bench/erg.c` | Benchmark against a TDL grammar such as the English Resource Grammar |
| `bench/content.c` | Benchmark of a synthetic content build shaped like bruggadung's |
| `bench/ace/` | Comparison with ACE: glb dump, matched unification workload, and the patch to build ACE on Apple silicon |

## The command-line tool and the editor

`build/triangle` loads content from files, or from directories that stand for
the `.tri` files in them (the current directory by default):

```sh
triangle check examples/workshop             # diagnostics, or a summary and the content hash
triangle inspect mallet examples/workshop    # an instance's spec, each value with its origin
triangle inspect '#Wrench' examples/workshop # a type's docstring, supertypes and components
triangle components BG examples/workshop     # what tri-components prints
triangle lsp                                 # the language server, over stdio
```

`examples/workshop` is the content [docs/GUIDE.md](docs/GUIDE.md) builds,
as files split by topic: open one in Emacs to try the mode and the server.
The guide is its source: `make examples` regenerates the files, and
`test_docs_guide` fails if they drift. bruggadung's own content is in
[../lab/content](../lab/content).

`check` exits 1 when there are errors. Its diagnostics have the
`file:line:col:` form that compilation buffers and editors parse.

**The language server** treats the directory of the file being edited as one
content build. Every change reloads that directory, with the text of open
files in place of the files on disk; loading bruggadung's content takes a few
milliseconds. It provides:

- **Diagnostics** for every file in the directory, as the loader reports them.
- **Hover**: the declarations of the name under the cursor, with its
  docstring; a type's supertypes and components; an instance's spec, each
  value annotated with its origin.
- **Go to definition** (every declaration of a name, in any file),
  **references**, **document symbols** and **workspace symbols**.
- **Completion** of type and instance names (qualified where the package
  requires it), features, built-in types, and attributes after `@`.

Names resolve by the package rules: inside a package, a plain name is the
package's own if it declares one, else the root's. A string resolves to an
atom, or else to the instance it names (`unit: "iron_nail"`). Specs and
supertypes come from the last load without errors, so they stay available
while you fix one; names and locations work even past a syntax error.

**Emacs.** `emacs/triangle-mode.el` highlights `.tri` files, indents them in
the content's style (structures by `triangle-indent-offset`, elements aligned
under the first one when it shares the opener's line), indexes declarations
for imenu, and registers the server with both lsp-mode and eglot. `C-c C-c`
runs `triangle check` in a compilation buffer, and `C-c C-i` inspects the
name at point.

```elisp
(use-package triangle-mode
  :load-path "~/dev/objc/bruggadung/triangle/emacs"
  :mode "\\.tri\\'"
  :custom (triangle-program (expand-file-name "~/.local/bin/triangle"))
  :hook (triangle-mode . lsp-deferred))     ; or eglot-ensure
```

## A taste

```c
TriContent *c = tri_content_load(paths, n);
const TriNode *pattern = tri_pattern(c, "tighten_roles");
const TriNode *view = tri_value(c, "#Roles & { ... }", arena, err, sizeof err);

TriMatchResult r;
if (tri_match(c, pattern, view, &r) == TRI_UNKNOWN)
    printf("find out: %s\n", r.residual[0]);       /* "target.size" */
```

## The English Resource Grammar benchmark

The ERG is MIT-licensed. Its repository includes large treebanks and uses
git-lfs, so fetch only the TDL files:

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/delph-in/erg.git erg
cd erg && git sparse-checkout set --no-cone '*.tdl'
git -c filter.lfs.process= -c filter.lfs.smudge=cat -c filter.lfs.required=false restore --source=HEAD :/
```

Then:

```sh
cc -std=c11 -O2 -Iinclude bench/erg.c build/libtriangle.a -o build/erg
./build/erg path/to/erg/english.tdl 1000     # 1000 sampled lexical entries
TRI_TRACE=1 ./build/erg ...                  # trace hierarchy completion
```

The benchmark has three parts:

- **Load:** the whole grammar loads from `english.tdl`.
- **Unification:** every rule daughter (`ARGS.FIRST`, `ARGS.REST.FIRST`) is
  unified with a sample of lexical entries. This is shaped like the first
  step of parsing.
- **Subsumption:** pairs of sampled entries are tested.

It also reports where unification fails. Those failure paths are the raw
material for choosing quick-check paths.

Results on an Apple M3, ERG trunk of 22 May 2026 (commit `13b615a`). The
benchmarks report process CPU time, which holds up when the machine is busy;
wall-clock times on a quiet machine are within a few per cent of it.

| Measure | Result |
| --- | --- |
| Load, end to end | 0.57 s, no diagnostics |
| Parsing | 0.07 s |
| Hierarchy: 4,730 generated meet types (the same as ACE's), 57,391 leaf (mostly string) types | 0.28 s, of which completion 0.2 s |
| Expansion of every type | 0.18 s, 62 MB |
| Lexical entry resolution | 0.008 ms and about 5 KB each |
| Unification, rule daughters × entries | about 1.24 million per second with failure paths recorded, 1.6 million without; 93.6% failing |
| With the quick check (13 paths) | 97.6% of failures filtered, 2.2× faster, none wrongly rejected |
| Pattern index of 597 rule daughters | about 52 candidates per entry, 7 µs per query |
| Subsumption | about 17 million tests per second |
| Content hash | `3ea4a70b06b06265`, identical across runs, and with sharing on or off |
| Sanitizers | Clean under ASan and UBSan |

**Speed**, before and after profiling. Instruction counts are from
`/usr/bin/time -l`:

| | Before | After |
| --- | --- | --- |
| Load | 2.4 s, 22.3 billion instructions | 0.57 s, 14.4 billion instructions |
| Hierarchy completion | 1.4 s | 0.2 s |
| Instructions per unification | about 17,000 | about 11,500 |
| Unifications per second | 0.73–0.80 M | 1.5–1.6 M |

What changed:

- **Completion examines each pair once.** After the first round, each new
  meet type is paired only with the ancestors of its descendants, found
  through cached ancestor lists and deduplicated with a mark array. Before,
  every multi-parent type's ancestor pairs were enumerated again, about 11
  million per round for 0.5 million distinct pairs.
- **Codes carry their range of non-zero words**, so intersecting and hashing
  two codes touches only the words where both can have bits.
- **Meet types made in the same round find their containing sets through an
  index on their rarest bit**, not by comparing every pair.
- **The content hash walks structures** instead of printing them, and sorts
  instance names with `qsort` (an insertion sort was quadratic in the ERG's
  45,000 instances).
- **Unification formats a failure only when it is asked for**, walks the two
  sorted arc lists in step, and no longer copies each node's arcs.
- **The meet table has a direct-mapped cache in front of it**, scratch records
  and copied arcs skip zeroing, and an arena keeps one released chunk for
  reuse.

**Memory**, before and after the work on nodes and sharing:

| | 128-byte nodes, no sharing | 48-byte nodes, no sharing | 48-byte nodes, sharing |
| --- | --- | --- | --- |
| Type expansions | 324 MB | 146 MB | 62 MB |
| Per lexical entry | about 74 KB | about 34 KB | about 5 KB |
| Unifications per second | 0.46–0.69 M | 0.53 M | 0.73 M (1.5–1.6 M after profiling) |

`TRI_NOSHARE=1` turns sharing off. `TRI_DUMP=file` writes the canonical text
behind the content hash. Comparing the two dumps, they are byte-identical.

**Quick-check paths against ACE's.** The ERG ships ACE's own quick-check
paths in `ace/ace-erg-qc.txt`. The paths learned here from failures agree with
them closely:

- `SYNSEM.LOCAL.CAT.HEAD` is first in both.
- `SYNSEM`, `VAL.COMPS`, `--SLASHED.BOOL`, `SPR.FIRST.OPT`, and `HEAD.INV` rank
  high in both.
- `SYNSEM.--MIN` and `SYNSEM.--SIND` are the same nodes as ACE's #3 and #1.
  They are joined by tags in `sign`, and our unifier reaches them under the
  alphabetically earlier feature.
- `INFLECTD` ranks higher here (ACE ranks it 25th) because this workload feeds
  uninflected lexical entries straight to rules.

**Against ACE 0.9.34**, built natively on the same machine. `bench/ace/`
has the drivers, the patch ACE needs on Apple silicon, and the steps.

- **Meet types are identical.** Each glb was compared as its set of declared
  supertypes, which identifies it uniquely. Both have the same 4,730 sets.
  ACE's summary line says 4,737, but its finished hierarchy holds 4,730.
  Matching them found one bug here: Triangle's conjunction types (CONTENT_LANGUAGE.md §3) were
  also being made for TDL. That added a type below three ERG types and two
  glbs around it. They are now made only for Triangle sources.
- **Unification agrees pair by pair.** Both ran the 597 rule daughters
  against the same 1,000 lexical entries, 597,000 unifications in all. The
  same 38,191 succeed in both.
- **Unification is faster here.** Both were run in the same session,
  alternating, timed in process CPU time:

  | | Unifications per second |
  | --- | --- |
  | Triangle (unify, and copy on success) | 1.53–1.61 M |
  | ACE, unify and copy the daughter on success | 1.06–1.08 M |
  | ACE, unify only | 1.28–1.34 M |

  ACE's copy also shares structure. Neither run used a quick check. Before
  the profiling work, Triangle and ACE were level (0.75–0.80 M against
  0.72–0.81 M).
- **Type expansions take half the memory:** 62 MB here against 131 MB in ACE's
  image. ACE also expands every lexical entry when it compiles the grammar.
  Triangle resolves an entry when it is first asked for (0.008 ms against
  ACE's 0.021 ms).
- **Load times differ in what they include.** ACE takes 7.3 s to compile the
  ERG to a 279 MB image, including the parse-ranking model and the lexicon.
  After that it loads in 26 ms by mapping the file. Triangle takes 0.57 s and
  has no saved image. Hierarchy completion takes 0.3 s in ACE and 0.2 s
  here; type expansion 0.6 s in ACE and 0.18 s here.

Caveats:

- The subsumption rate means little, because most sampled pairs differ at
  the root type.
- The unification rate includes copying the roughly 6% that succeed. With
  the quick check on, those copies are most of the remaining time.

## A content build of bruggadung's shape

`bench/content.c` generates content like the game's: 40 component kinds,
material and finish mixins with defaults, blueprints with variation, `@vary`
weights, and alternatives, and 200 operations in a family with quick-check
paths. With 20,000 blueprints:

| Measure | Result |
| --- | --- |
| Load, end to end, including every blueprint's spec | 0.18 s |
| Instances and specs | about 5.5 µs per blueprint |
| Construction from a seed | about 790,000 entities per second |
| Matching after the family index | about 200,000 matches per second |

## Status

Every feature in CONTENT_LANGUAGE.md is built, including the definite-clause
layer and arithmetic, which the first version of the spec had deferred, and
the spec's decisions on its former open questions. Each feature has tests,
listed by area below.

| Area | Tests |
| --- | --- |
| Parser, hierarchy, meets, closed typing, tags, units, lists | `test_core.c` |
| The three scenarios: defaults, variation, conflicts, matching, hypotheses, recognition, decay | `test_scenarios.c` |
| The example file of §17, read from the spec | `test_example_file` |
| The guide's examples and the results it quotes, read from `docs/GUIDE.md` | `test_docs_guide` |
| `bool`, `text`, `ref`, Celsius; blueprints resolved at load; the field registry | `test_features.c` |
| Disjunction of structures in types and instances, variants, default alternatives, the variant cap | `test_features.c` |
| `@vary` weights, typed open lists, recursive types, numbers in memory decay (`@widen`) | `test_features.c` |
| Both locations of a conflict, the inspector, the match explainer, docstrings | `test_features.c` |
| Families and compiled indexes, derived fields (`@fn`), saves and migration, generalisation, hypothesis residuals | `test_features.c` |
| Findings of an independent audit of the spec against the code: residuals and bindings for tags, alternatives chosen by a value, every conflicting path, compaction, `int` and `fixed`, strict runtime values, the build log, and items that had no test | `test_features.c` |
| Arithmetic over quantities: folding, propagation, suspension, units, errors; definite clauses: reachability, accumulated distances, depth limits | `test_features.c` (`test_arithmetic`, `test_clauses`) |
| The decided open questions: path-keyed variation seeds and `@vary(mode:)`, units from exponents and backward narrowing, distinct clause solutions, generated component structs, failure recording for `@quickcheck`, store sizes, migration | `test_features.c` |
| Randomised properties: unification is commutative, associative, and idempotent; subsumption, matching, and generalisation agree with it; the quick check never rejects a success; saves round-trip; declaration order never changes the content; construction is concrete and a function of the seed | `test_props.c` |
| Interval arithmetic is sound and exact; every clause solution is an instance of its query | `test_properties_arithmetic`, `test_properties_clauses` |
| Fuzzed sources never crash the loader | `test_fuzz_sources` |
| Every allocation is freed, error paths included | `tests/leakcheck` |
| The Objective-C wrapper | `objc/test_objc.m` |

The randomised tests were run at twenty times their usual size, under the
sanitizers, and with sharing off. They found five bugs, now fixed:

- Declaration order changed the content when anonymous enums shared atoms,
  when generated meet types were added as parents, and when typed lists gave
  `#Null` its parents. Each order now comes from names.
- Generalising two structures with lazy (recursive) nodes could invent tags.
- The lexer leaked each attribute's text.

Probing by hand found five more: a default overridden by a more specific one
came back when that one was dropped in a tie; `*5 | int` was rejected;
blueprint errors appeared only when a spec was asked for; `bool`, `text`, and
`ref` were missing; and content could set a field the registry does not mark
`content`.

**The wrapper and mulle-objc.** `BGContent` uses manual retain/release and
needs only MulleObjC and MulleFoundationBase. Built with mulle-clang 22.1.8
in a mulle-sde project (`-m mulle-objc/objc-developer`, plus
`mulle-sde dependency add --objc --github MulleFoundation MulleFoundationBase`,
crafted with `mulle-sde -DCFLAGS="-fobjc-tao" craft`), it and the library run
its test under the mulle-objc runtime with no failures. With Apple clang and
Foundation it builds and passes the same test (`make objc`).

The full MulleFoundation does not build on this Mac (macOS 14, arm64): in
`NSTask+System.m`, mulle-clang emits an empty inline-assembly barrier for
`@try` with every local variable as a memory operand, 30 in that method, and
arm64 runs out of registers. The wrapper doesn't need that part. mulle-clang
has fixed this on its `mulle/23.1.3` branch (commit 2759313016, batching the
operands), not yet in a release; the tap's `--HEAD` build is an older line
(17.0.6) and no help. Built from that branch, mulle-clang 23.1.3 compiles the
whole MulleFoundation, where 22.1.8 fails on exactly that file, and the
wrapper's test passes against the full MulleFoundation.

An independent audit (a separate agent reading only the spec and the code)
then found eleven gaps, now closed or recorded. Residuals and bindings for a
tag depended on feature order. A value alone did not pick an alternative.
Unification gave only the first conflict. There was no way to compact a
knowledge arena. `fixed` rejected whole numbers. Runtime values silently
accepted defaults and separate numbers. The build log was missing. Clash
errors gave one location. Several behaviours had no test.

Known shortcuts:

- The generation counters are 32-bit and never reset. That gives about 4
  billion operations per content object.
- Each default applied while resolving a spec copies the whole structure. This
  only happens at load, but it is wasteful.
- **Structure sharing has a contract.** A unification result may share
  unchanged structure with its inputs, so their arenas must outlive it. The
  two inputs must not share nodes at different positions, for example a
  structure and one of its own substructures.
- **Expansions are used directly only in top-level operations.** A nested
  operation (a lazy expansion inside a unification) could overwrite the
  scratch of shared nodes that the outer operation is using. The first
  version of sharing had exactly this bug: it silently lost information in 79
  ERG types. The dump comparison above is how it was caught.
- **A lazy node prints as its type.** A recursive type's constraint is applied
  only where something adds structure. Paths (`tri_at`), subsumption,
  matching, and generalisation read through it to the type's expansion.
- **Generated type names are long.** An alternative's type is named after its
  text, such as `({ shape: "flat" } | { shape: "round" })/{ shape: "flat" }`.
- **A string an enum lists is that enum's atom.** Where free text is
  expected it becomes text again, but the two are different values.
- **The load arena stays.** Specs are frozen into their own arena, but the
  syntax tree and load-time structures are kept: TDL lexical entries and
  non-blueprint specs resolve on request.
- **Units are a table in `units.c`** until the unit descriptors of
  DOMAIN_SIMULATION.md §12 exist.
- **Arcs are sorted, not positional** (CONTENT_LANGUAGE.md §12).
