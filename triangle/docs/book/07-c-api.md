# 7. The C API

The engine is a C11 library with no dependencies. This chapter shows how a
program uses it. [API.md](../API.md) lists each function. The declarations
are in [`include/triangle.h`](../../include/triangle.h).

## Build and link

```sh
make                      # build/libtriangle.a and the tests
make game                 # build/libtriangle-game.a: no TDL front end
cc -std=c11 -Iinclude app.c build/libtriangle.a -o app
```

`libtriangle-game.a` does not contain the TDL front end, which is only for
tests and benchmarks ([chapter 8](08-engine.md)). The lab links a library
of the same sort through the Odin package: `make odin-lib` builds it into
`build/<platform>/libtriangle.a`.

## The four objects

| Type | What it is | Who owns it |
| --- | --- | --- |
| `TriContent *` | One content build: the types, the specs, the patterns. The API document calls it the content object | The program. Free it with `tri_content_free`. |
| `TriArena *` | A region of memory for feature structures | The program. Free it with `tri_arena_free`. |
| `const TriNode *` | A node of a feature structure | Its arena, or the content |
| `TriType` | The ID of a type: a small whole number | — |

## A complete program

This program loads the workshop content, constructs a nut, matches an
operation, and applies a pattern. Run it from the `triangle` directory.

```c
#include <stdio.h>
#include "triangle.h"

int main(void)
{
    const char *paths[] = {
        "examples/workshop/things.tri",     "examples/workshop/blueprints.tri",
        "examples/workshop/operations.tri", "examples/workshop/levers.tri",
        "examples/workshop/data.tri",       "examples/workshop/text.tri",
        "examples/workshop/rooms.tri",
    };
    TriContent *c = tri_content_load(paths, sizeof paths / sizeof *paths);
    for (size_t i = 0; i < tri_diag_count(c); i++) fprintf(stderr, "%s\n", tri_diag_message(c, i));
    if (!tri_content_ok(c)) { tri_content_free(c); return 1; }

    TriArena *a = tri_arena_new();
    char buf[512], err[256];

    /* 1. Construct an entity from a blueprint and a seed. */
    const TriNode *nut = tri_construct(c, "nut", 1, a);
    tri_print(c, nut, buf, sizeof buf);
    printf("constructed: %s\n", buf);

    /* 2. Match an operation against a description. */
    const TriNode *view = tri_value(c,
        "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut & { state: \"tight\" } }",
        a, err, sizeof err);
    if (!view) { fprintf(stderr, "%s\n", err); return 1; }
    TriMatchResult r;
    switch (tri_match_instance(c, "loosen", view, &r)) {
    case TRI_ENTAILED:     printf("loosen: entailed\n"); break;
    case TRI_INCOMPATIBLE: printf("loosen: incompatible at %s\n", r.failure.path); break;
    case TRI_UNKNOWN:
        printf("loosen: unknown; find out:");
        for (size_t i = 0; i < r.nresidual; i++) printf(" %s", r.residual[i]);
        printf("\n");
        break;
    }

    /* 3. Apply a pattern: unify it with a description, then read the result. */
    const TriNode *tool = tri_value(c, "#Use & { tool: #Wrench & { wear: 995 } }", a, err, sizeof err);
    if (!tool) { fprintf(stderr, "%s\n", err); return 1; }
    TriFailure f;
    const TriNode *used = tri_unify(c, tri_pattern(c, "use"), tool, a, &f);
    if (!used) { fprintf(stderr, "use fails at %s\n", f.path); return 1; }
    tri_print(c, tri_at(c, used, "after.wear"), buf, sizeof buf);
    printf("wear after use: %s\n", buf);

    tri_arena_free(a);
    tri_content_free(c);
    return 0;
}
```

The output is:

```text
examples/workshop/blueprints.tri:21:1: warning: hammer: conflicting defaults for material from #Wooden, #Metal; both dropped
constructed: #Nut & { mass: 39g, material: "brass", size: 12.4mm, state: "loose" }
loosen: unknown; find out: target.size
wear after use: 1000
```

The sections that follow explain each part.

## Rules for all calls

**Threads.** Use one content build from one thread at a time. Calls that
look like reads still use the scratch memory of the content build. Two
different content builds share nothing, so two threads can use them.

**Arenas.** Each call that makes a feature structure takes a `TriArena *`.
The result is in that arena. To release many results at one time, take a
mark and release to it:

```c
TriMark m = tri_arena_mark(a);
const TriNode *x = tri_construct(c, "nut", seed, a);
/* ... use x ... */
tri_arena_release(a, m);          /* x is gone */
```

**Sharing.** The result of `tri_unify` can share nodes with its inputs. Do
not free the arenas of the inputs while you use the result. The two inputs
must not share a node at two different positions: do not unify a feature
structure with one of its own parts. Use `tri_copy` to get a feature
structure that shares nothing.

**Read only.** Patterns and specs belong to the content build. Do not
change them.

**Strings.** The strings that the API returns belong to the content build.
They stay until `tri_content_free`. The result of `tri_save` is the exception:
free it with `free`.

**Text buffers.** A call that writes text works as `snprintf` does. It
writes at most `len` bytes, always with a terminator. It returns the length
of the full text. Call it with a length of 0 to learn the size.

**Paths.** A path is feature names with dots between them:
`"target.size"`. Lists use `first` and `rest`. The empty path is the root.

**Failure.** A call that can fail returns `NULL` or 0. Many calls take a
`TriFailure *` or a buffer for a message. Pass `NULL` if you do not need
it.

## Load content

| Function | Purpose |
| --- | --- |
| `tri_content_load(paths, n)` | Load from files |
| `tri_content_load_strings(names, sources, n)` | Load from memory. The names are for diagnostics |
| `tri_content_ok(c)` | True if there are no errors. Warnings are permitted |
| `tri_diag_count`, `tri_diag_message`, `tri_diag_is_error` | The diagnostics |
| `tri_log_count`, `tri_log_message` | The build log: each generated type, each pair of dropped defaults |
| `tri_content_hash(c)` | The content hash |
| `tri_content_free(c)` | Free the content |

The two load functions always return a content build, also when there are
errors. The program can then print the diagnostics. Do not use the content
build for other work unless `tri_content_ok` is true.

The load functions take file paths, not directories. The `triangle` command
finds the files of a directory itself.

If you pass a directory to `tri_content_load`, the result has an error:
`cannot read …: it is not a file`.

## Types

```c
TriType wrench = tri_type_named(c, "#Wrench");     /* TRI_BOTTOM if there is no such type */
TriType tool   = tri_type_named(c, "#Tool");
if (tri_subtype(c, wrench, tool)) { /* each wrench is a tool */ }
TriType m = tri_meet(c, wrench, tool);             /* TRI_BOTTOM if they are incompatible */
```

A `TriType` is a type ID. The type IDs are the same for the same content
hash. They change when the content changes. Do not save a type ID without
the content hash.

Other functions list the types, the features of a type, the component
kinds, and the fields of each component with their flags.

## Feature structures

| Function | Purpose |
| --- | --- |
| `tri_value(c, expr, out, err, errlen)` | Make a description from Triangle source, in runtime mode |
| `tri_at(c, node, path)` | Follow a path. `NULL` if the path does not exist |
| `tri_node_type(node)` | The type of a node |
| `tri_node_interval(node, &lo, &hi)` | The interval of a number, in quanta. 0 if the node is not a number or has no bounds |
| `tri_text(c, node, buf, len)` | The contents of a string or the name of an atom. `(size_t) -1` for all other nodes |
| `tri_print(c, node, buf, len)` | The feature structure as Triangle source |
| `tri_copy(c, node, out)` | A copy that shares nothing |

A number is exact when `lo == hi`. An open end is `INT64_MIN` or
`INT64_MAX`.

`tri_value` is stricter than content. A default (`*`) is an error. A
disjunction of feature structures, or of separate numbers, is an error.

## Blueprints

| Function | Purpose |
| --- | --- |
| `tri_spec(c, name)` | The spec of a blueprint |
| `tri_spec_variation_count`, `tri_spec_variation_path` | The variation points of a spec |
| `tri_construct(c, name, seed, out)` | An entity: each variation point has a value |
| `tri_inspect(c, name, buf, len)` | The spec as text, with the origin of each value |

### Derived fields

A field with the attribute `@fn(name)` gets its value from a function of
the program. In content (this `#Lever` is not the one of the workshop,
which uses arithmetic):

```cue
#Lever: #Tool & { force: force, arm: length, torque: torque @fn(lever_torque) }
```

Register the function before you construct:

```c
static int lever_torque(void *ctx, TriContent *c, const TriNode *owner, int64_t *lo, int64_t *hi)
{
    int64_t flo, fhi, llo, lhi;
    tri_node_interval(tri_at(c, owner, "force"), &flo, &fhi);
    tri_node_interval(tri_at(c, owner, "arm"), &llo, &lhi);
    if (flo != fhi || llo != lhi) return 0;        /* not known: do not set the field */
    *lo = *hi = flo * llo / 10000;                 /* mN × 0.1 mm → mN·m */
    return 1;
}

tri_register_fn(c, "lever_torque", lever_torque, NULL);
```

The function returns 1 with an interval, or 0 to leave the field as it is.
`tri_construct` calls it. `tri_derive` applies the functions to any other
feature structure.

This example is simple, and arithmetic can state it too
([chapter 5](05-computed-values.md)). Use a derived field for a value that
arithmetic cannot state, such as a value from a table.

## Match

| Function | Purpose |
| --- | --- |
| `tri_pattern(c, name)` | The pattern of an instance: no defaults |
| `tri_pattern_variant_count(c, name)`, `tri_pattern_variant(c, name, i)` | The pattern of each variant |
| `tri_match(c, pattern, description, &r)` | Match one pattern node |
| `tri_match_instance(c, name, description, &r)` | Match each variant of an instance |
| `tri_binding(c, name, tag, description)` | The node that a tag binds to |
| `tri_match_hypotheses(...)` | Match against hypotheses with credences |
| `tri_explain_instance(...)` | The match as text for a person |

The result struct is:

```c
typedef struct {
    TriMatch   result;                              /* TRI_ENTAILED, TRI_UNKNOWN, TRI_INCOMPATIBLE */
    size_t     nresidual;
    char       residual[TRI_MAX_RESIDUAL][128];     /* the residual paths, 16 at most */
    TriFailure failure;                             /* set when incompatible */
} TriMatchResult;
```

The engine reports 16 residual paths at most. If `nresidual` is 16, there
can be more.

## Unify, compare, generalise

| Function | Purpose |
| --- | --- |
| `tri_unify(c, a, b, out, &failure)` | The most general feature structure that both describe, or `NULL` with the first path that fails |
| `tri_conflicts(c, a, b, paths, max)` | Each path where the two conflict |
| `tri_subsumes(c, a, b, &forward, &backward)` | Which one is more general. Both directions in one call |
| `tri_lgg(c, a, b, out)` | The most specific feature structure that is more general than both |
| `tri_generalize(c, node, path, steps, out)` | Memory decay: the node at the path goes up `steps` primary parents at most. A number becomes wider by its `@widen` step for each step |

### Apply a pattern

When one argument of `tri_unify` is the result of `tri_pattern`, the result
has what the arithmetic of the instance gives. Step 3 of the program above
does this. It is how a program builds the result of a Triangle rule from
what matched its premises.

Three conditions apply:

- Pass the pattern node itself. The engine finds the arithmetic by that
  node. A copy of the node does not have it.
- For an instance with variants, use `tri_pattern_variant`. The single
  pattern from `tri_pattern` is the variants anti-unified: what all of them
  say. It has no arithmetic.
- Put all that the pattern needs into one description. The arithmetic does
  not go with the result into a second `tri_unify`.

## Families and the quick check

```c
TriIndex *ix = tri_family_index(c, "operations");   /* NULL if there is no such family */
size_t cand[64];
size_t n = tri_index_candidates(ix, view, cand, 64);
for (size_t i = 0; i < n && i < 64; i++) {
    const char *op = tri_index_tag(ix, cand[i]);     /* the name of the instance */
    TriMatchResult r;
    tri_match(c, tri_index_pattern(ix, cand[i]), view, &r);
}
```

`tri_index_candidates` returns the number of all candidates. That number
can be more than the size of your array.

`tri_index_count` and `tri_index_tag` list all members of a family. A
program can use a family as a table of declarations of one kind.

To choose the quick-check paths, record failures while tests run:

```c
tri_record_failures(c, 1);
/* ... run the tests ... */
char attr[256];
tri_family_suggest_quickcheck(c, "operations", 8, attr, sizeof attr);
/* attr is an @quickcheck(...) attribute. Paste it into the content. */
```

## Definite clauses

```c
const TriNode *sol[16];
int truncated;
const TriNode *q = tri_value(c, "#Way & { from: \"kitchen\" }", a, NULL, 0);
size_t n = tri_solve(c, q, 10, sol, 16, a, &truncated);
```

The third argument is the depth limit. `truncated` is set if the limit
stopped a proof. Then more solutions can exist.

## Saves and migration

| Function | Purpose |
| --- | --- |
| `tri_save(c, node, by_id)` | Write a description as text. Free the result with `free` |
| `tri_restore(c, text, out, err, errlen)` | Read it back |
| `tri_migrate(from, to, node, out, err, errlen)` | Move a description from one content build to another |

A save by ID is small. It restores only into content with the same hash. A
save by name restores into changed content too. A restore fails, with the
reason, if a type or a feature no longer exists.

`tri_migrate` is for a reload of content while the program runs. The
program loads the new content, migrates each live description by name, and
frees the old content.

## Component structs

The types with `@component` describe the records of the program. The tool
`tri-components` writes a C header from them: one struct for each component
kind, and a table of the fields.

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

- A number is an `int64_t` of quanta.
- An enum is a `uint32_t` type ID.
- A referent is a `uint64_t`.

The table of fields gives the offset, the value kind, and the `@field`
flags of each field. With it, code can read and write a component that it
does not know.

The header contains the content hash. Generate it again each time the
content changes.

## From Odin

The Odin package [`odin/triangle`](../../odin/triangle) is the C API with
no `tri_` prefix. It adds some procedures that take and return Odin
strings.

```odin
import tri "../triangle/odin/triangle"

c, err := tri.load_files(paths)         // nil, with each diagnostic in err
defer tri.content_free(c)

a := tri.arena_new()
defer tri.arena_free(a)
made := tri.construct(c, "nut", 7, a)
view := tri.value(c, "#Roles & { ... }", a, nil, 0)
if m, residuals := tri.match_with_residuals(c, "loosen", view); m == .Unknown {
	fmt.println("find out:", residuals)
}
```

`tri-components -odin` writes the component structs as an Odin file. The
lab of Bruggadung uses this.

Previous: [6. Clauses, packages and tools](06-clauses-packages-tools.md).
Next: [8. The engine](08-engine.md)
