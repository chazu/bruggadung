# The simulation laboratory

The first code of the bruggadung framework, in mulle Objective-C: entities,
component stores, relations, change commitment, the clock and scheduler,
saves, the action menu, and the first domain, with content loaded from
Triangle. It runs COMPONENTS.md's first scenario, *The marked nail*, and
DOMAIN_SIMULATION.md's third, *Two draws on a dwindling stock*, headless,
and checks their acceptance criteria. The plan
and its status are in [PLAN.md](PLAN.md).

```sh
mulle-sde craft                         # the real build: mulle-clang, MulleObjC, MulleFoundationBase
./kitchen/Debug/lab test                # unit tests and scenarios; non-zero exit on any failure
./kitchen/Debug/lab run marked-nail     # one scenario: trace, entities, checks (also -a, -b)
./kitchen/Debug/lab save marked-nail    # the save of its end state
./kitchen/Debug/lab menu marked-nail 1000   # what the worker sees, and its menu, at 1000 ms
./kitchen/Debug/lab run cistern         # the fluid domain: two taps and a leak on a dwindling cistern (also -b, -d)
make gen                                # regenerate src/generated/BGComponents.h from content/
make test-apple                         # the same sources with Apple clang and Foundation
make asan                               # the Apple build under AddressSanitizer and UBSan
make leaks                              # object leaks, through mulle-testallocator
make check                              # craft, test, and fail on runtime warnings or leaks
```

The first craft fetches and builds the mulle-objc dependencies. The build
passes `-fobjc-tao -DTRI_NO_TDL`, set once with `mulle-sde definition set
CFLAGS`.

## Layout

| Path | Contents |
| --- | --- |
| `content/` | `components.tri`: the component kinds and their field registry, plus what descriptions say besides fields (ids, places, free hands); `water.tri`: water stores and taps; `operations.tri`: the operations; `workshop.tri`: the scenarios' blueprints |
| `src/generated/BGComponents.h` | Generated from `content/` by `make gen`: one struct per component, enums, and the field registry. Committed; the lab refuses to run on content with another hash. |
| `src/core/` | `BGTypes.h` (IDs, time, seeds, locations), `BGStore` (records of one kind, sorted by ID), `BGWorld` (all authoritative state, journaled for rollback) |
| `src/commit/` | `BGProposalGroup` (proposals, handles, unit references), `BGCommitter` (ordering, individuation, apply, validation, events, reactions) |
| `src/kinds/` | Component behaviour: `BGBodyKind`, the merge reaction |
| `src/domains/` | `BGFluidDomain`: water through open taps, with checkout, exact allocation, and exhaustion as the horizon |
| `src/sched/` | `BGScheduler`, with the domain and input-source protocols |
| `src/act/` | `BGView` (reach and descriptions: the knowledge view's stub), `BGActions` (the menu, matching, effects, performing) |
| `src/save/` | `BGSave`: saves as text, and restoring them |
| `src/scenario/` | `BGMarkedNail` and `BGCistern`: the scenarios, their input logs, and their checks |
| `src/test/` | The test runner and the tests |
| `src/triangle/` | Symlinks to the Triangle engine and its Objective-C wrapper, compiled into the lab |

## How an action happens

Operations are content (`content/operations.tri`): patterns over the
descriptions of the entities filling their roles, with tags carrying
bindings between roles. An actor's view (`BGView`) can bind only what is in
reach, and describes each entity by its type, id, place, and the component
fields whose `@field` flags say they can be perceived. A hidden field stays
open, so a match on it is unknown, and unknown never excludes. The menu
lists every operation and binding whose match isn't incompatible.
Performing a command checks it is on the menu, then runs the operation's
effect function, which builds a proposal group for commitment.

## How a domain runs

The fluid domain owns water while it flows. At each boundary the scheduler
asks it for a horizon; if an open tap can draw, it forms a structure,
checking out the water of the stores and tiles involved (commitment then
refuses to change them), and answers with the exact time its source runs
dry. The scheduler jumps there. Flows are whole millilitres with the
fraction carried on the tap; a step that can't be met is shared pro rata,
with the leftover millilitres given in tap-ID order rotated by the boundary.
When nothing can flow it checks everything back in. A save checks in first
and keeps the carries, so a run restored mid-flow ends exactly where the
original does.

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
  `-contentBuild`. Describing an entity is `-describeEntity:` for the same
  reason. `make check` fails on any such warning.
- The code uses manual retain/release, no properties, and no blocks, so the
  same sources build with Apple clang (`make test-apple`).
- The full MulleFoundation needs mulle-clang 23.1.3, which isn't released;
  the lab needs only MulleObjC and MulleFoundationBase.
