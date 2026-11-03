# Embedding Triangle

This document covers using the Triangle engine from C and Odin. The
declarations are in [`include/triangle.h`](../include/triangle.h), and the
Odin package is [`odin/triangle`](../odin/triangle). The content language
itself is in [GUIDE.md](GUIDE.md) and [REFERENCE.md](REFERENCE.md).

- [Building and linking](#building-and-linking)
- [Rules that apply everywhere](#rules-that-apply-everywhere)
- [Loading content](#loading-content)
- [Types and components](#types-and-components)
- [Feature structures](#feature-structures)
- [Blueprints: specs and construction](#blueprints-specs-and-construction)
- [Matching](#matching)
- [Recognition and memory](#recognition-and-memory)
- [Families, indexes and the quick check](#families-indexes-and-the-quick-check)
- [Definite clauses](#definite-clauses)
- [Knowledge stores, saves and migration](#knowledge-stores-saves-and-migration)
- [Generated component structs](#generated-component-structs)
- [From Odin](#from-odin)
- [The TDL front end](#the-tdl-front-end)

## Building and linking

The engine is plain C11 with no dependencies.

```sh
make                      # build/libtriangle.a and the tests
make game                 # build/libtriangle-game.a: no TDL front end
cc -std=c11 -Iinclude app.c build/libtriangle.a -o app
```

The game links `libtriangle-game.a`, which is built with `-DTRI_NO_TDL`. In
it, `tri_content_load_tdl` returns content with one error.

## Rules that apply everywhere

**Threads.** A content object is single-threaded: call it from one thread at
a time. Even calls that look like reads use its scratch space, and some
resolve instances on first use. Separate content objects share nothing, so
they can be used on separate threads.

**Arenas.** Every call that makes a structure takes a `TriArena *out` and
allocates the result there. You own the arena. Free it with
`tri_arena_free`, or take a mark and release back to it:

```c
TriArena *a = tri_arena_new();
TriMark m = tri_arena_mark(a);
const TriNode *x = tri_construct(c, "nut", seed, a);
/* ... use x ... */
tri_arena_release(a, m);          /* x is gone */
```

Patterns, specs and type expansions belong to the content object. They stay
valid until `tri_content_free`, and they must never be modified.

**Structure sharing.** A result of `tri_unify` may share unchanged structure
with its inputs. So keep the inputs' arenas alive as long as the result is in
use. The two inputs must not share nodes at different positions, such as a
structure and one of its own substructures. Use `tri_copy` when you need a
structure that shares nothing.

**Strings.** Strings the API returns (names, docstrings, diagnostics, notes,
paths) belong to the content object and live as long as it does.
`tri_save` is the one exception: its result is `malloc`'d, and you free it.

**Text buffers.** Calls that write text (`tri_print`, `tri_inspect`,
`tri_explain`, `tri_component_header`, …) follow `snprintf`: they write at
most `len` bytes, always terminated, and return the length of the full text.
Call once with `len` 0 to size a buffer.

**Paths** are feature names joined by dots: `"roles.target.size"`. Lists are
reached through `first` and `rest`: the second item of `items` is
`"items.rest.first"`. The empty path is the root.

**Failures.** Calls that can fail return `NULL` (or 0). Many take an optional
`TriFailure *` (the failing path and both values), or an `err` buffer with a
message. Pass `NULL` when you don't need them.

## Loading content

```c
const char *paths[] = { "content/tools.tri", "content/ops.tri" };
TriContent *c = tri_content_load(paths, 2);
for (size_t i = 0; i < tri_diag_count(c); i++)
    fprintf(stderr, "%s\n", tri_diag_message(c, i));
if (!tri_content_ok(c)) { tri_content_free(c); return 1; }
/* ... */
tri_content_free(c);
```

- `tri_content_load(paths, n)` reads files. `tri_content_load_strings(names, sources, n)` reads
  sources from memory, using `names` in diagnostics. Both always return a
  content object, even on errors.
- `tri_content_ok` is true when there are no errors. Warnings are allowed.
- `tri_diag_count`, `tri_diag_message`, `tri_diag_is_error`: the diagnostics,
  as `file:line:col: error: message`. REFERENCE.md lists them.
- `tri_diag_location(c, i, &file, &line, &col)`: where a diagnostic points,
  for tools that place it themselves; 0 if it has none. Lines and columns
  count from 1, and columns count bytes. `tri_diag_text` is the message
  without the location and severity.
- `tri_decl_count`, `tri_decl(c, i, &decl)`: every declaration as written,
  in load order, with its kind (type, atom, or instance), its name qualified
  by its package, the location of its label, and its docstring. The
  prelude's are left out. A file with a syntax error keeps the declarations
  before the error, so an editor can still navigate it.
- `tri_log_count`, `tri_log_message`: the build log. It lists every type the
  loader generated and every pair of conflicting defaults it dropped.
- `tri_content_hash`: a hash of the content's meaning. It doesn't depend on
  file or declaration order. Saves and generated headers record it.
- `tri_content_stats`: counts and load timings (`TriStats`).
- `tri_instance_count`, `tri_instance_name`: the instances, in declaration order.
  `tri_instance_status` is the TDL `:status` of an instance, or empty.
- `tri_doc(c, name)`: the docstring of a type or instance, or `NULL`.

## Types and components

```c
TriType wrench = tri_type_named(c, "#Wrench");     /* TRI_BOTTOM if unknown */
TriType tool   = tri_type_named(c, "#Tool");
if (tri_subtype(c, wrench, tool)) { /* every wrench is a tool */ }
TriType m = tri_meet(c, wrench, tool);             /* the most general common subtype, or TRI_BOTTOM */
```

- `tri_type_count`, `tri_type_name`, `tri_primary_parent`.
- `tri_type_feature_count` and `tri_type_feature` list the features a type
  has, its own and inherited.
- `tri_function_count` and `tri_function` list the built-in functions content
  may call, with their signatures (REFERENCE.md, Built-in functions).
- Type IDs are dense and deterministic for a given content hash. They change
  when content changes.
- Components: `tri_component_count`, `tri_component_name`, and
  `tri_component_type` give the component kinds. `tri_type_components` gives
  an entity type's components. `tri_component_field_count` and
  `tri_component_field` give each component's fields, with their `@field`
  flags as a string.

## Feature structures

```c
const TriNode *d = tri_value(c, "#Nut & { size: 19mm }", a, err, sizeof err);
const TriNode *size = tri_at(c, d, "size");
int64_t lo, hi;
if (tri_node_interval(size, &lo, &hi) && lo == hi) { /* an exact size, in 0.1 mm quanta */ }
char buf[256];
tri_print(c, d, buf, sizeof buf);    /* #Nut & { mass: mass, material: #Material, size: 19mm, state: ... } */
```

- `tri_value` builds a description from an expression. It is stricter than
  content: no defaults, and no disjunctions of structures or separate numbers.
- `tri_at` follows a path. It returns `NULL` if the path doesn't exist, and
  it reads through lazy (recursive) nodes.
- `tri_node_type` gives a node's type. `tri_node_interval` gives a number's
  interval in quanta, and returns 0 when the node has no bounds or isn't a
  number. Open ends are `INT64_MIN` and `INT64_MAX`.
- `tri_print` prints a structure in Triangle syntax. Shared nodes print as
  tags (`$1`).
- `tri_text` gives the contents of a string value, decoded: a concrete text
  node's text, or an atom's name (`"steel"` gives `steel`). It returns the
  full length, writing as much as fits, or `(size_t) -1` for any other node.
  Use it instead of stripping the quotes from `tri_print`, which prints
  strings escaped.

## Blueprints: specs and construction

```c
const TriNode *spec = tri_spec(c, "nut");                 /* NULL if not an instance, or it failed */
for (size_t i = 0; i < tri_spec_variation_count(c, "nut"); i++)
    printf("varies: %s\n", tri_spec_variation_path(c, "nut", i));
const TriNode *entity = tri_construct(c, "nut", seed, a); /* every variation point drawn */
```

- `tri_pattern` is an instance's indefeasible structure, without defaults.
  Matching uses it. With variants, `tri_pattern_variant_count` and
  `tri_pattern_variant` give each one, and `tri_pattern` is their
  generalisation.
- `tri_spec` is the blueprint with its defaults resolved. Its open fields
  are its variation points (`tri_spec_variation_path`).
- `tri_spec_note` gives notes on how the spec was made: where each default
  came from, which defaults lost, and what the seed decides.
- `tri_inspect` prints the spec with each value's origin: the instance, a
  type, a default, or the seed.
- `tri_construct` makes every variation point concrete from `seed`, then
  computes the `@fn` fields. It returns `NULL` if the instance has no spec,
  or a computed value conflicts. The same seed always gives the same entity.

**Derived fields.** A field marked `@fn(name)` gets its value from a function
you register:

```c
static int lever_torque(void *ctx, TriContent *c, const TriNode *owner, int64_t *lo, int64_t *hi)
{
    int64_t flo, fhi, llo, lhi;
    tri_node_interval(tri_at(c, owner, "force"), &flo, &fhi);
    tri_node_interval(tri_at(c, owner, "arm"), &llo, &lhi);
    if (flo != fhi || llo != lhi) return 0;        /* not yet known: leave the field open */
    *lo = *hi = flo * llo / 10000;                 /* mN × 0.1 mm → mN·m */
    return 1;
}

tri_register_fn(c, "lever_torque", lever_torque, NULL);
```

The function receives the structure that holds the field. It returns 1 with
an interval (an exact value when `lo == hi`), or 0 to leave the field as it
is. Registering the same name again replaces the function. `tri_derive`
applies the functions to any structure; it returns `NULL` if a computed
value conflicts with what is already there.

## Matching

```c
TriMatchResult r;
switch (tri_match_instance(c, "loosen", view, &r)) {
case TRI_ENTAILED:     /* the description says everything the pattern needs */ break;
case TRI_UNKNOWN:      /* find out: r.residual[0 .. r.nresidual-1], e.g. "target.size" */ break;
case TRI_INCOMPATIBLE: /* ruled out at r.failure.path */ break;
}
```

- `tri_match(c, pattern, description, &r)` matches any pattern node against
  a description, without changing either.
- `tri_match_instance` matches against every variant of a named instance:
  entailed if any variant is, incompatible if all are, otherwise unknown.
- Residuals are paths in the description that are too general to decide. At
  most `TRI_MAX_RESIDUAL` (16) are reported.
- `tri_binding(c, instance, tag, description)` gives the node a pattern's tag
  binds to, by tag name without the `$`.
- `tri_match_hypotheses` matches against competing hypotheses, each with a
  credence. Credences are Q16 fixed point (65536 is 1). The result is the
  credence mass that is entailed, unknown and incompatible, plus the
  residuals of the unknown hypotheses.
- `tri_explain` and `tri_explain_instance` print a match for a person: the
  result, the bindings, the residuals, and the first failing path.

## Recognition and memory

- `tri_unify(c, a, b, out, &failure)` gives the most general structure that
  both describe, or `NULL` with the first failing path. Mind the sharing rule
  above.
- `tri_conflicts(c, a, b, paths, max)` gives every path where `a` and `b`
  conflict. Recognition weighs these against the paths that agree.
- `tri_subsumes(c, a, b, &forward, &backward)` tests both directions at once:
  `forward` is set when `a` subsumes `b` (is at least as general).
- `tri_lgg(c, a, b, out)` gives the most specific structure that subsumes
  both: their least general generalisation.
- `tri_generalize(c, node, path, steps, out)` is memory decay. It moves the
  node at `path` up to `steps` primary parents, and widens a number by its
  field's `@widen` step per step.

## Families, indexes and the quick check

Instances marked `@family(name)` form a family, and its index is compiled at
load:

```c
TriIndex *ix = tri_family_index(c, "operations");   /* owned by the content; NULL if no such family */
size_t cand[64];
size_t n = tri_index_candidates(ix, view, cand, 64);
for (size_t i = 0; i < n && i < 64; i++) {
    const char *op = tri_index_tag(ix, cand[i]);     /* the instance name */
    TriMatchResult r;
    tri_match(c, tri_index_pattern(ix, cand[i]), view, &r);
}
```

`tri_index_candidates` returns every pattern that could match, and maybe
some that can't. It never leaves out one that would match. It returns how
many candidates there are in all, which can be more than `max`.

**Choosing quick-check paths.** Record failures during test runs, then ask
for a suggestion:

```c
tri_record_failures(c, 1);
/* ... run scenarios: failed tri_match_instance calls on family members are counted ... */
char attr[256];
tri_family_suggest_quickcheck(c, "operations", 8, attr, sizeof attr);
/* attr is "@quickcheck(target.state, roles.instrument.size, ...)": paste it into content */
```

You can also build your own: `tri_qc_new` from paths, `tri_qc_from_failures`
from recorded failure paths, then `tri_index_new` and `tri_index_add` with
any tag pointer. Free them with `tri_index_free` and `tri_qc_free`. Indexes
from `tri_family_index` belong to the content object.

## Definite clauses

```c
const TriNode *sol[16];
int truncated;
const TriNode *q = tri_value(c, "#Way & { from: \"kitchen\" }", a, NULL, 0);
size_t n = tri_solve(c, q, 10, sol, 16, a, &truncated);
```

`tri_solve` proves the query against the content's `#Clause` and `#Fact`
instances. It writes up to `max` distinct solutions into `out`, in a fixed
order, and returns how many it found. `depth_limit` bounds each proof.
`*truncated` is set when the limit cut a proof short, which means more
solutions may exist. A bound of one million resolution steps also guards the
whole search.

## Knowledge stores, saves and migration

- `tri_copy(c, node, out)` makes a deep copy that shares nothing. A store
  compacts by copying its live descriptions into a fresh arena and freeing
  the old one.
- `tri_arena_bytes` and `tri_node_count` measure an arena and a structure, so
  a store can decide when to compact and keep to its memory bound.
- `tri_save(c, node, by_id)` writes a description as text, which you free.
  By ID is compact, but restores only into content with the same hash. By
  name restores into changed content too.
- `tri_restore(c, text, out, err, errlen)` reads it back. It fails, with the
  reason, if a type or feature no longer exists or the structure no longer
  fits its types. New features appear at their most general value.
- `tri_migrate(from, to, node, out, err, errlen)` moves a live description
  from one content build to another, by name, for reloads and mods.

The save format is text. It starts with a header line, `tri-save 1 <content
hash> names|ids`. Each node follows as `(type [=lo hi | ="text"] feature node
...)`, and a shared node is written once and referred to later as `@n`:

```text
tri-save 1 3b97bccfc37a50bf names
("#Wrench" "mass" ("mass" =850 850) "material" ("\"steel\"") "size" ("length" =190 190) "wear" ("int" =0 0))
```

## Generated component structs

`tri_component_header(c, prefix, buf, len)` writes a C header with one struct
per `@component` type, so the field registry is written only once, in
content. The `tri-components` tool wraps it:

```sh
./build/tri-components BG content/*.tri > components.h
```

```c
/* Physical, from #Physical */
typedef struct {
    int64_t         mass;    /* mass, in quanta of 1g; content, saved */
    uint32_t        material;    /* #Material: a type ID; content, saved */
} BGPhysical;
```

- Numbers are `int64_t` quanta.
- Enums are `uint32_t` type IDs, with an `enum` of their members.
- Text is a string, referents are `uint64_t`, and `bool` (or `true | false`
  with a default) is `bool`.
- Any other structure is a `const TriNode *`.

The header records the content hash (`BG_CONTENT_HASH`). Type IDs are valid
only for that content, so regenerate the header whenever the content changes.

The header also carries a **field registry**, so code can read and write any
component without knowing it: `BGComponentInfo` and `BGFieldInfo` describe
each component's fields, with their offsets, value kinds (`BG_VALUE_QUANTITY`,
`_TYPE`, `_TEXT`, `_REF`, `_BOOL`, `_NODE`), quantity kinds, and `@field`
flags. The types are always declared; define `BG_COMPONENT_REGISTRY` in one
source file to get the tables:

```c
#define BG_COMPONENT_REGISTRY
#include "BGComponents.h"

for (size_t i = 0; i < BG_COMPONENT_COUNT; i++)
    for (size_t j = 0; j < BGComponents[i].nfields; j++)
        printf("%s.%s at %zu\n", BGComponents[i].name, BGComponents[i].fields[j].name,
               BGComponents[i].fields[j].offset);
```

`tri_format_quantity(kind, quanta, buf, len)` prints a stored value the way
content writes it: `tri_format_quantity("mass", 850, …)` is `850g`.

## From Odin

The Odin package [`odin/triangle`](../odin/triangle) is the C API without its
`tri_` prefix (`triangle.odin`: `tri.content_hash(c)`, `tri.unify(...)`), and
a few procedures that take and give Odin strings (`content.odin`). It links
the game's library (no TDL front end), which `make odin-lib` builds into
`build/<platform>/`. Feature structures stay `^tri.Node`, so every C call
works on them directly. A constant string converts to a `cstring` as it is.

```odin
import tri "../triangle/odin/triangle"

c, err := tri.load_files(paths)         // nil, with every diagnostic in err
defer tri.content_free(c)
varies := tri.variation_paths(c, "nut")
fmt.println(tri.inspection(c, "nut"))

a := tri.arena_new()
defer tri.arena_free(a)
made := tri.construct(c, "nut", 7, a)
view := tri.value(c, "#Roles & { ... }", a, nil, 0)
if m, residuals := tri.match_with_residuals(c, "loosen", view); m == .Unknown {
	fmt.println("find out:", residuals)
}
```

| Procedure | C equivalent |
| --- | --- |
| `load_files`, `load_sources` | `tri_content_load`, `tri_content_load_strings`; nil unless `tri_content_ok` |
| `diagnostics`, `name_of`, `documentation` | the diagnostic messages, `tri_type_name`, `tri_doc` |
| `describe`, `inspection` | `tri_print`, `tri_inspect` |
| `variation_paths`, `notes` | `tri_spec_variation_path`, `tri_spec_note` |
| `match_with_residuals` | `tri_match_instance`, with the residuals as strings |
| `saved` | `tri_save`, as an Odin string |

`make odin` runs the package's tests. `tri-components -odin PACKAGE IMPORT
file.tri ...` writes a content build's component structs and field
registry as an Odin file (`tri_component_odin`), as the lab's `make gen`
does.

## The TDL front end

`tri_content_load_tdl(topfile)` loads a DELPH-IN grammar, such as the English
Resource Grammar's `english.tdl`, into the same engine. Instances resolve
lazily, and `tri_instance_status` gives each one's `:status`. It exists to test
and benchmark the engine against ACE (`bench/erg.c`, `bench/ace/`). The game
build leaves it out.
