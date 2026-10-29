# The simulation laboratory

The first code of the bruggadung framework, in mulle Objective-C: entities,
component stores, relations, change commitment, and the clock and scheduler,
with content loaded from Triangle. It runs COMPONENTS.md's first scenario,
*The marked nail*, headless, and checks its acceptance criteria. The plan
and its status are in [PLAN.md](PLAN.md).

```sh
mulle-sde craft                         # the real build: mulle-clang, MulleObjC, MulleFoundationBase
./kitchen/Debug/lab test                # unit tests and scenarios; non-zero exit on any failure
./kitchen/Debug/lab run marked-nail     # one scenario: trace, entities, checks (also -a, -b)
make gen                                # regenerate src/generated/BGComponents.h from content/
make test-apple                         # the same sources with Apple clang and Foundation
make asan                               # the Apple build under AddressSanitizer and UBSan
```

The first craft fetches and builds the mulle-objc dependencies. The build
passes `-fobjc-tao -DTRI_NO_TDL`, set once with `mulle-sde definition set
CFLAGS`.

## Layout

| Path | Contents |
| --- | --- |
| `content/` | `components.tri`: the component kinds and their field registry; `workshop.tri`: the scenario's blueprints |
| `src/generated/BGComponents.h` | Generated from `content/` by `make gen`: one struct per component, enums, and the field registry. Committed; the lab refuses to run on content with another hash. |
| `src/core/` | `BGTypes.h` (IDs, time, seeds, locations), `BGStore` (records of one kind, sorted by ID), `BGWorld` (all authoritative state, journaled for rollback) |
| `src/commit/` | `BGProposalGroup` (proposals, handles, unit references), `BGCommitter` (ordering, individuation, apply, validation, events, reactions) |
| `src/kinds/` | Component behaviour: `BGBodyKind`, the merge reaction |
| `src/sched/` | `BGScheduler`, with the domain and input-source protocols |
| `src/scenario/` | `BGMarkedNail`: the scenario, its input log, and its checks |
| `src/test/` | The test runner and the tests |
| `src/triangle/` | Symlinks to the Triangle engine and its Objective-C wrapper, compiled into the lab |

## How a change happens

Nothing writes world state except change commitment. A system builds a
`BGProposalGroup` (create, move, set a field, split, merge, relate, emit)
and submits it. At the next boundary the committer:

1. orders the groups by phase (process, action, system), then by a
   permutation seeded from the world seed, boundary, and round
2. rewrites each group for automatic individuation: a proposal that names
   one unit of a stack (`BGUnit(stack, 1)`) gets that unit split off first
3. applies the group with the world's journal open, and validates the
   result: entities exist, every physical entity has one location in a place
   that can hold it, and mass and each unit's count are conserved except
   where the group creates or destroys
4. keeps the group, or rolls it back whole and records the reason
5. lets components react to the committed events; their groups are the next
   round, up to R rounds, and the rest wait for the next boundary

Every step is in the trace: `lab run marked-nail` prints it.

## Notes for mulle-objc

- A selector has one signature across every class in mulle-objc. The world
  can't have `-content` returning `BGContent *` while `BGContent` has
  `-content` returning `TriContent *`; the runtime warns, and the world's is
  `-contentBuild`.
- The code uses manual retain/release, no properties, and no blocks, so the
  same sources build with Apple clang (`make test-apple`).
- The full MulleFoundation needs mulle-clang 23.1.3, which isn't released;
  the lab needs only MulleObjC and MulleFoundationBase.
