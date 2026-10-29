# Triangle

Triangle is bruggadung's content language: TDL's typed feature structure
semantics with CUE-style syntax, specified in
[CONTENT_LANGUAGE.md](../CONTENT_LANGUAGE.md). This directory is a prototype
of its engine. It is plain C11 with no dependencies, so it builds without the mulle
toolchain.

```sh
make            # library and tests
make test       # run the tests
make asan       # rebuild and test with AddressSanitizer and UBSan
```

## Layout

| File | Contents |
| --- | --- |
| `include/triangle.h` | Public API |
| `src/parse.c` | Lexer and parser for the CUE-style syntax |
| `src/tdl.c` | TDL front end: DELPH-IN type description language into the same syntax tree |
| `src/units.c` | Quantity literals and exact conversion to quanta |
| `src/types.c` | Hierarchy: enums, conjunction types, completion (`glb[...]`), deterministic IDs, bit-vector meets, feature introduction |
| `src/fs.c` | Nodes, Tomabechi unification, copying with structure sharing, subsumption, paths, printing |
| `src/qc.c` | Quick check: path vectors, learning paths from failures, pattern indexes |
| `src/load.c` | Building from syntax, type expansion, instance patterns and specs, defaults, variation, construction, matching, generalisation |
| `src/util.c` | Arenas, symbols, maps, diagnostics |
| `tests/` | Core tests, the three scenarios from CONTENT_LANGUAGE.md, and a small TDL grammar |
| `bench/erg.c` | Benchmark against a TDL grammar such as the English Resource Grammar |
| `bench/ace/` | Comparison with ACE: glb dump, matched unification workload, and the patch to build ACE on Apple silicon |

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

Results on an Apple M3, ERG trunk of 22 May 2026 (commit `13b615a`). Timings
varied by up to about 2× with other load on the machine; these are from a
quiet run.

| Measure | Result |
| --- | --- |
| Load, end to end | 2.4 s, no diagnostics |
| Parsing | 0.1 s |
| Hierarchy: 4,730 generated meet types (the same as ACE's), 57,389 leaf (mostly string) types | 1.4 s |
| Expansion of every type | 0.3 s, 62 MB |
| Lexical entry resolution | 0.012 ms and about 5 KB each |
| Unification, rule daughters × entries | about 0.73 million per second, 93.6% failing |
| With the quick check (13 paths) | 97.6% of failures filtered, 2.1× faster, none wrongly rejected |
| Pattern index of 597 rule daughters | about 52 candidates per entry, 11 µs per query |
| Content hash | `289b67ed0fb3c9b1`, identical across runs, and with sharing on or off |
| Sanitizers | Clean under ASan and UBSan |

**Memory**, before and after the work on nodes and sharing:

| | 128-byte nodes, no sharing | 48-byte nodes, no sharing | 48-byte nodes, sharing |
| --- | --- | --- | --- |
| Type expansions | 324 MB | 146 MB | 62 MB |
| Per lexical entry | about 74 KB | about 34 KB | about 5 KB |
| Unifications per second | 0.46–0.69 M | 0.53 M | 0.73 M |

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
  glbs around it. They are now made only for Triangle sources. This changed
  the content hash to `289b67ed0fb3c9b1`.
- **Unification agrees pair by pair.** Both ran the 597 rule daughters
  against the same 1,000 lexical entries, 597,000 unifications in all. The
  same 38,191 succeed in both.
- **Unification speed is level.** Both were run in the same session,
  alternating:

  | | Unifications per second |
  | --- | --- |
  | Triangle (unify, and copy on success) | 0.75–0.80 M |
  | ACE, unify and copy the daughter on success | 0.72–0.81 M |
  | ACE, unify only | 0.86–1.00 M |

  ACE's copy also shares structure. Neither run used a quick check.
- **Type expansions take half the memory:** 62 MB here against 131 MB in ACE's
  image. ACE also expands every lexical entry when it compiles the grammar.
  Triangle resolves an entry when it is first asked for (0.012 ms against
  ACE's 0.021 ms).
- **Load times differ in what they include.** ACE takes 7.3 s to compile the
  ERG to a 279 MB image, including the parse-ranking model and the lexicon.
  After that it loads in 26 ms by mapping the file. Triangle takes 2.4 s and
  has no saved image yet. Hierarchy completion takes 0.3 s in ACE and 1.4 s
  here; type expansion 0.6 s in ACE and 0.3 s here.

Caveats:

- The subsumption rate (about 10 million tests per second) means little,
  because most sampled pairs differ at the root type.
- The unification rate includes copying the roughly 6% that succeed. With
  the quick check on, those copies are most of the remaining time.

## Status

Working, and tested by the scenarios:

- the parser
- the hierarchy and meets
- unification with tags
- closed typing
- intervals with units
- lists
- defaults with YADU-style specificity
- seed variation
- three-valued matching with residuals
- hypothesis masses
- generalisation along primary parents
- order-independent loading

Not yet built: see CONTENT_LANGUAGE.md §18.

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
