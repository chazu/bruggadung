# The simulation laboratory: first slice

This is the plan for the first code of the bruggadung framework itself:
item 4 of "What comes next" in [ARCHITECTURE.md](../ARCHITECTURE.md), and
step 3 of the development sequence in [DESIGN.md](../DESIGN.md). It builds
the parts every system stands on (entities, component stores, relations,
change commitment, the clock and scheduler), loads its content from Triangle,
and proves them on COMPONENTS.md's first scenario, *The marked nail*, run
headless with its acceptance checks.

## Goal

At the end of this slice:

- `lab/` is a mulle-sde project in mulle Objective-C, linking the Triangle
  engine built without its TDL front end.
- Component kinds are declared once, in `.tri` content. Their C structs and
  field registry are generated from it. No field is declared twice.
- Entities are built from blueprints with seeds, through change commitment.
- Every change to world state goes through commitment: ordered by phase and
  a seeded permutation, validated, applied atomically, with IDs allocated in
  commit order, committed events, reactions for up to R rounds, rejections
  with reasons, and traces.
- A scenario harness runs *The marked nail* and its variants A and B from a
  scripted input log, and checks all seven acceptance checks, determinism
  included.

Out of scope for this slice, planned for the next ones: domains beyond the
protocol, activities with stages and effort, operations matched from content
(the action menu), perception and knowledge, agency, saves, and the
interactive command interface and map view.

## Decisions for this slice

1. **Component data is generated C structs; component behaviour is
   Objective-C.** COMPONENTS.md says component kinds are classes, and
   CONTENT_LANGUAGE.md says stores use the generated structs. Both hold: a
   store keeps records as the struct `tri-components` generates for the kind,
   in an array sorted by entity ID, and a `BGComponentKind` subclass per kind
   supplies behaviour (reactions, validators). Components stay cold data,
   with no pointers, only entity IDs.
2. **The field registry is generated too.** `tri_component_header` gains a
   registry section: for each component, its fields' names, offsets, value
   kinds, quantity kinds, and flags. Construction, inspection, traces, and
   later saves read fields through it, so they work for every kind without
   hand-written code.
3. **The generated header is committed**, at `lab/src/generated/BGComponents.h`,
   with a script to regenerate it. At startup the lab compares the header's
   content hash with the loaded content's and refuses to run on a mismatch.
4. **Triangle is built by CMake from its own sources** (a small
   `triangle/CMakeLists.txt`, with `TRI_NO_TDL`), added to the lab with
   `add_subdirectory`. Nothing is copied. The Makefile stays for Triangle's
   own tests.
5. **Manual retain/release, no properties, no ARC.** The code builds with
   mulle-clang against MulleObjC and MulleFoundationBase (the full
   MulleFoundation needs mulle-clang 23.1.3, not released). A second build
   with Apple clang and Foundation (`make apple`) is a fast check, as for
   `BGContent`. mulle-objc is the authority.
6. **No hash-order iteration anywhere.** Stores, relations, and tombstones
   are sorted arrays keyed by ID. Foundation collections are used only where
   order doesn't matter or is imposed.
7. **The world is driven by scripted inputs for now.** Without activities
   and the action menu, the scenario submits system groups from an input log
   at stated simulation times. The input log is the replay log of
   ARCHITECTURE.md, so the same mechanism later carries player commands.
8. **A test runner is built into the executable.** `lab test` runs the unit
   tests and the scenarios and exits non-zero on any failed check. `lab run
   <scenario>` runs one and prints its trace.

## Layout

```
lab/
  PLAN.md                 this plan, then the slice's status
  CMakeLists.txt, cmake/  the mulle-sde project
  Makefile                make apple: the Apple clang build; make gen: regenerate
  content/                *.tri: component kinds, blueprints for the scenarios
  src/
    generated/BGComponents.h
    core/                 BGTypes (IDs, time, units), BGStore, BGWorld
    relations/            BGLocation, BGEdges, BGTombstones
    commit/               BGProposal, BGProposalGroup, BGCommitter, BGEvent, BGTrace
    kinds/                BGComponentKind and the kinds' behaviour (BGStackKind, …)
    sched/                BGClock, BGScheduler, BGRunPolicy, BGInputLog, BGDomain
    scenario/             BGScenario, BGMarkedNail
    test/                 unit tests
    main.m
```

## Milestones

Each milestone ends with everything building under both compilers and
`lab test` passing.

### M0. Skeleton

- `mulle-sde init -m mulle-objc/objc-developer executable` in `lab/`, with
  vibecoding off, the `MulleFoundationBase` dependency, and
  `-DCFLAGS=-fobjc-tao`.
- `triangle/CMakeLists.txt` builds `libtriangle` with `TRI_NO_TDL`; the lab
  links it and `BGContent`.
- `main.m` loads `content/*.tri` through `BGContent`, prints diagnostics, and
  runs an empty test list.
- `.gitignore` for mulle-sde's build directories.
- `make apple` builds the same sources with Apple clang.

### M1. Content and the generated registry

- Extend `tri_component_header` with the registry section, guarded by
  `<PREFIX>_COMPONENT_REGISTRY`, with a test in Triangle.
- Lab content, `content/components.tri`:
  - `#Body` (Body): `mass`, `material`
  - `#Stack` (Stack): `count`, `unitMass`
  - `#Marks` (Marks): `bent`, `toolMarks`
  - `#Hands` (Hands): `hands`
  - `#Container` (Container): `capacity`, the number of entities it holds
  - `#Claim` (Claim): `kind`, `quantity`
- Blueprints, `content/workshop.tri`: `iron_nail` (the unit), `nail_stack`,
  `bin`, `lock`, `worker`, `smith`, `ownership_claim`.
- `make gen` regenerates the header; startup checks the hash.

### M2. World state

- `BGEntityID` (`uint64_t`), `BGTime` (`int64_t` ms), and the unit structs
  the slice needs (`BGMass`, `BGCount`).
- `BGStore`: records of one kind, sorted by ID; get, put, remove, iterate in
  ID order; field access through the registry.
- The entity table: each live entity's blueprint and seed.
- `BGLocation`: the exclusive location relation, with the forms `onTile(x, y,
  level)`, `in(container)`, `heldBy(agent, hand)`, `partOf(assembly, role,
  index)`, and the derived contents index.
- `BGEdges`: typed binary relations with indexes both ways: `splitFrom`,
  `claimant`, `claimSubject`.
- `BGTombstones`: ID, blueprint, ending event, successor, reason.
- `BGWorld` owns them, with the ID counter, the world seed, the clock, and
  the boundary index. A state hash over everything, in ID order, checks
  determinism.

### M3. Change commitment

- Proposals (C structs): set a field, set a location, create from a
  blueprint with a seed, destroy, split, merge, add or remove an edge, emit
  an event. Each carries its source and cause. Entities a group creates are
  named by group-local handles, resolved to IDs when the group applies.
- A target can name one unit of a stack (`{entity, unit}`), so a proposer
  can act on one nail without splitting first.
- `BGCommitter`, following ACTIONS.md §9:
  1. gather the boundary's groups
  2. order by phase (process, action, system), then a seeded permutation
     from the world seed, boundary index, and round
  3. per group, in order: automatic individuation rewrites it, then
     validation against the state the earlier groups left, then atomic apply
     or rejection with a reason
  4. allocate IDs in apply order; emit committed events with causes
  5. reactions to the round's events form the next round, up to R rounds;
     the rest are deferred to the next boundary and traced
  6. deliver rejections to their sources
- Validation: the target exists and is not a tombstone; location
  exclusivity and hand and container capacity; conservation of count and
  mass per group, except declared creation; edge cardinality; kind
  validators.
- Automatic individuation: a proposal that gives one unit of a stack
  distinguishing state (marks, a separate location, a claim of its own)
  first splits that unit off into an individual.
- Merging: units merge only when physically indistinguishable (same unit
  blueprint, no marks, no relations but location, no reified claim on the
  individual). Merged entities are tombstoned with the survivor as
  successor. Quantity claims carry over: a claim's subjects follow the
  merge, and its quantity is unchanged.
- Splits: every claim on the source extends to the new entity. A claim is
  resolved when its quantity covers every unit of its subjects; otherwise
  its allocation is reported as unresolved, never silently assigned.
- The Stack kind's reaction: when a stack or a unit is put into a container
  holding a stack of the same unit blueprint, propose a merge. A rejected
  merge is traced with its reason.

### M4. Content to components

- A create proposal constructs the blueprint with `tri_construct` and the
  entity's seed, then fills each component's record from the constructed
  structure through the registry. Entity seeds derive from the world seed
  and a stable key, never from the ID.

### M5. Clock, scheduler, inputs

- `BGClock`, `BGRunPolicy` (run until a time, or until the input log is
  exhausted), and `BGInputLog` (time-stamped inputs).
- `BGScheduler` runs the boundary loop of ARCHITECTURE.md: bound the step by
  the policy, the next input, and each active domain's horizon; advance
  domains; commit; housekeeping; advance the clock.
- The `BGDomain` protocol from DOMAIN_SIMULATION.md §13, with no domains yet.
  A test domain checks that horizons bound steps.

### M6. The marked nail

- `BGScenario` runs an input log against a fresh world and checks
  conditions as it goes.
- *The marked nail*, steps 1 to 3, with variants A (no marks: the nail merges
  and the reference resolves through its tombstone) and B (mixed goods: two
  quantity claims sum, and a split leaves them unresolved).
- The seven acceptance checks, each a named check in `lab test`:
  1. count and mass conserved exactly across every split and merge
  2. location exclusive at every boundary
  3. marking a nail inside a stack splits it off without being asked
  4. merging the bent nail is rejected, with the reason
  5. references to merged stacks resolve to tombstones with the right successor
  6. quantity claims sum on merge, and a split leaves them unresolved
  7. replaying gives bit-identical IDs and final state
- `lab run marked-nail` prints the trace: groups, order positions,
  rejections, events, and allocations.

## After this slice

In rough order, each driven by a scenario:

1. Saves and loading, with the rebuilt world producing the same next step.
2. Operations in content and the action menu, by matching operation patterns
   against a truth-projected description (the knowledge view stubbed).
3. Activities with stages, effort, interruption, and watches.
4. A tile-grid domain (heat or water) with horizons, checkout, and
   conservation ledgers: DOMAIN_SIMULATION.md's scenarios.
5. The command interface, a text map, and the developer inspector.
6. Perception and knowledge stores, then agency.

## Status

M0 to M6 are built. `lab test` runs 12 tests (111 checks), and all pass under
mulle-objc and under Apple clang, with AddressSanitizer and UBSan clean on the
Apple build. *The marked nail* and variants A and B pass all seven
acceptance checks, and a replay is bit-identical.

What building it settled or found:

- **Triangle needed three changes.** The generated header gained the field
  registry (names, offsets, value kinds, quantity kinds, flags) with its
  typedefs always visible and its tables behind `BG_COMPONENT_REGISTRY`.
  Writing it found two old bugs in the generator: a structure-valued field
  used `TriNode` before declaring it, and an empty component made an empty
  struct. `*false | true` now generates `bool`. `tri_format_quantity` prints
  raw quanta with their unit, for traces.
- **A stack's mass is Triangle arithmetic** (`mass: $u * $n`), so content
  can't give a stack the wrong mass.
- **Quantity claims follow units; only a claim on one unit alone pins it.**
  A split extends every claim on the stack to the new entity, so a nail split
  off a claimed stack carries the claim. Reading COMPONENTS.md's "no reified
  claims on the individual" as "no claim at all" stopped the unmarked nail of
  variant A from merging back; the rule is now that a claim whose only
  subject is that unit blocks the merge.
- **Units of a stack the same group creates can't be individuated yet**: the
  whole entity is meant. No scenario needs it.
- **The seeded permutation runs over submission order**, as ACTIONS.md §9
  says, so submission order can matter, deterministically. A key per group
  that ignores submission order would be stronger; nothing needs it yet.
- **The layout is flatter than planned.** The entity table, locations,
  edges, and tombstones live in `BGWorld` (each a sorted store), not in a
  `relations/` directory of their own; there is no `BGComponentKind` base
  class yet, only the `BGReactor` protocol.
- **The merge reaction belongs to Body, not Stack.** A reaction goes to the
  components of the event's subject, and the unit put into the bin may be an
  individual, which has no Stack.
- **Location queries scan.** The contents and spatial indexes come with the
  tile-grid domain.
- **In mulle-objc a selector has one signature across all classes**; see
  README.md.

- **Leaks are checked with mulle-testallocator** (`make leaks`), which sees
  mulle-allocated memory: objects, not the C `malloc` inside them.
  LeakSanitizer isn't supported on macOS arm64, and `leaks` can't attach here.

### After the slice: saves

Item 1 of "After this slice" is built (`src/save/`). A save is text: the
entity table and ID counter, every component record (fields and types by
name), locations, edges, tombstones, history, the clock and boundary, and
the committer's position and deferred groups. `lab save marked-nail` prints
one. The tests save *The marked nail* halfway, restore it into a fresh world
with the same state hash, save again byte for byte, and carry on: the
restored world's run matches the one that never saved, state and trace. A
save names fields and types, so it reads into changed content; a field the
content lost, or a type it lost, is refused with the reason.

What it settled:

- **The text trace is not saved; history is.** The committer's trace is a
  developer log. Checks that must survive a save read the event history:
  the marked nail's individuation is checked as a split inside the group
  that marked it.
- **The commit position is saved state.** Events record their group's
  position, so a restored committer must continue the count.

15 tests, 131 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: operations and the action menu

Item 2 is built (`src/act/`, `content/operations.tri`). Operations are
Triangle patterns in the `operations` family: `take`, `take_some`,
`put_in`, and `drive`, each with an `effect` naming the code that builds its
group. The menu matches every binding of an operation's roles to entities in
the actor's reach against their descriptions; the stub of the knowledge view
describes an entity by its type, id, place, and perceivable fields only. The
marked nail now runs on commands: the worker takes five nails, drives one
into the lock, takes it out, and puts both back, each action performed
through the menu. `lab menu marked-nail 1000` shows what the worker sees and
can do.

What it settled:

- **Ids, places, and free hands are description types, not component
  fields.** `#Thing` (id), `#Placed` (place), and `#Handed` (freeHands) are
  inherited by the component types but are not components, so the generated
  structs don't carry them; the view fills them from relations and derived
  values.
- **An operation's roles type says which roles it has.** `#Roles`,
  `#ItemRoles`, and `#PlacingRoles`: a structure's type is the most general
  one with its features, so `take` has no destination to enumerate.
- **Perceivable means `perceive` in the field's flags.** The stack's count
  has none, so a pattern on it is unknown with `count` as the residual: the
  scenario's "the stack count, if counted".
- **The family index has an entry per variant**, so the menu takes each
  operation once.
- **`make check`** fails on mulle-objc's signature warnings, which caught a
  second clash (`describe:`).

16 tests, 151 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the first domain

Item 4's first part is built: a fluid domain (`src/domains/`) and the first
tile stock, proven on DOMAIN_SIMULATION.md's Scenario 3, *Two draws on a
dwindling stock*. Two agents open taps on a cistern of 15 L with a leaking
crack; the domain checks out the cistern, the buckets, and the floor tile,
predicts the exact step the cistern runs dry, and the scheduler jumps there:
the whole run is three boundaries. The buckets get 7140 and 7139 mL and the
floor 721 mL, 15 L exactly. All five of the scenario's checks that need a
domain pass (conservation at every boundary, order independence as variant
3d bit-identical to the base, fairness within a millilitre, no negative
stock, every tap told "exhausted" in the step the horizon predicted), and
variant 3b gives the earlier agent more. Variant 3c, the single seal, is
change commitment's (the seeded-order test).

What it settled:

- **A holder nothing draws from has no exhaustion time.** The first version
  asked every holder, and the empty floor said "now", stepping a
  millisecond at a time.
- **Tiles are checked out like entities.** While the domain has the floor,
  the world's value is stale, and the conservation sum must skip it; the
  first version counted the crack's first second twice.
- **What kind of thing something is, is perceived.** A `#Container` might
  be a `#Tap` as far as a description's type goes, so `open_tap` on the bin
  was unknown; the menu now rules out an entity whose kind is more general
  than the role's.
- **Carries survive check-in for taps that stay open, and saves keep them**
  (ARCHITECTURE.md's "carried remainders not yet dropped"), so a save in
  mid-flow changes nothing, for the run that saved or the one restored.
- **Domains have a save interface**: `checkInAll`, `savedState`,
  `restoreSavedState:`, with "domain <name> ..." lines in the save.

Not yet: water spreading between tiles (a real grid stencil), wake and sleep
by region, contributions between domains, and bucket capacity (overflow).

21 tests, 171 checks, under both compilers, ASan and UBSan, and leak-free.

Next: activities with stages, effort, interruption, and watches (item 3),
now that there is a domain to watch: the scenario's agents should *fill a
bucket*, an activity that stops when the source is exhausted.
