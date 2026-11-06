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

### After the slice: activities and watches

Item 3's first part is built (`src/act/BGActivities`, `content/activities.tri`).
An activity is an informational entity with an Activity component: its
operation, its bound entities, an amount, a due time, a status, and an
optional watch. Operations with a `duration` are timed activities (drive
takes 4 s); fill_bucket is an activity that ends by its watch on the bucket,
or by the tap's "exhausted". The scheduler bounds steps by due times; the
fluid domain reads running activities' watches and reports "watched" in the
exact step a bucket reaches its amount; a round listener on the committer
ends the activities a round's events end (ACTIONS.md §5: "engine machinery,
not a component channel"). Watches are owned by activities and saved with
them, as ACTIONS.md answered DOMAIN_SIMULATION.md's open question 4.

The cistern's agents now fill their buckets as activities: in the base run
both end "exhausted" in the step the cistern runs dry; in the new variant
3e, A asks for 3 L and B for 10 L, and each watch ends its activity at
exactly that amount (3000 and 10000 mL), the crack draining the remaining
2000 mL. The marked nail's drive is timed; the save test saves in the
middle of it, and the restored world completes it.

What it settled:

- **A referent left open in a blueprint is none**, not an error: an
  activity's bindings are set when it starts.
- **Text fields travel through proposals** (an activity records its
  operation's name).
- **An operation's description carries its own features** (effect and
  duration) as well as its roles; without the duration, drive matched
  unknown.
- **A generated type has no writable name.** The bucket's type is the meet
  `glb[#Assembly & #WaterStore,#Body & #WaterStore]`, which completion made
  because two conjunction types share `#Body` and `#WaterStore`; the view
  describes such an entity by the conjunction of its components' types.
- **A duration counts from the command**, at the world's time when it is
  given.

Not yet: stages and effort rates from capabilities, interruption by the
actor's choice, suspension and resuming, provider allocation (hands), and
partial effects.

23 tests, 182 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the command interface, and stages

Item 5 is built (`src/play/`): `lab play workshop|cistern` is an interactive
session with a text map, the numbered menu, commands, run controls, saves,
and the developer inspector (`inspect`, and `why`, which follows causes from
a change back to the command that began it). The commands typed are the
replay log; a test plays a session twice and compares the state hashes.
Walking (`walk_north` and the rest) is the first operation that moves the
actor.

Then item 3's second part: stages and suspension. An operation may list
stages; an activity keeps its stage, the progress made in it, and when it
last started; `suspend` keeps the progress and `resume` rechecks reach and
runs what is left; after each round, a running activity whose bound
entities are gone or out of reach is suspended. `pry_out` (loosen 3 s, pull
2 s) is the example: walked away from after a second, it waits; resumed,
it finishes the loosening and pulls.

What it settled:

- **A stop is a boundary.** The run policy used to set the clock to the
  stop time without one, so the domains never advanced to it, and the next
  step advanced from the stop: the water between the last boundary and a
  `wait` was simply not delivered. ARCHITECTURE.md already said a stop
  request inserts a boundary; now it does, and the save tests' reference
  runs stop where the saving runs stop.
- **Checked-out records mirror the domain.** The inspector and the view read
  the holder's record; while checked out, the domain writes its values back
  after each step, and the record stays closed to commitment.
- **Activities have causes.** A completion follows from the event that
  created the activity, and an ending from the event that ended it, so
  `why` reaches the command.
- **An item merging away now suspends the drive** rather than failing it
  when due: the recheck notices first. A completion commitment rejects
  still fails (the fifth nail in a four-slot lock).
- **A duration counts from the command**, and the command commits at the
  next boundary; tests count that millisecond.

Not yet: effort rates from capabilities (graded requirements), partial
effects at checkpoints, provider allocation (hands), and per-stage
requirements (a resumed stage rechecks reach, not the operation's pattern).

26 tests, 212 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the floor

Item 4's second part: water spreads across the floor. The fluid domain's
structure includes the floor around wet tiles and below every tap; across
each adjacent pair it moves (difference × dt) / (8 τ) whole millilitres from
step-start values, with τ = 10 s as the safe step, so the scheme is stable
and order independent, and a puddle settles once neighbours differ by less
than 8 mL. When nothing flows or spreads, the whole region checks in and
sleeps. The cistern's 722 mL now spread from under the crack across the
floor, and the domain is asleep at the end of the run; every earlier check
still holds, the reversed order included.

Not yet: regions smaller than the whole structure (a puddle across the room
keeps the cistern's structure awake), walls and levels, and contributions
from other domains.

### After the slice: knowledge

Item 6's first part: perception and knowledge stores (`src/know/`). The
scheduler runs a perception phase after each boundary's commit rounds. Each
agent's private store holds referents with Triangle descriptions built from
percepts, believed places that name other referents, sight times, and a
developer-only truth link; recognition binds by kind and place. Contents of
a container are seen only by looking in (look_in, putting, taking,
reaching). The menu `lab play` shows comes from the knowledge view, and
performing a believed action resolves its referents on the world's side: if
the world rules it out, an "attempted" event commits and perception
corrects the belief. KNOWLEDGE.md's Scenario 3 runs in the workshop: the
worker looks into the bin and walks away, the smith takes the nails out of
sight, and back at the bin the worker's menu offers the nails it remembers;
the attempt finds them gone. Stores are saved.

What it settled:

- **Events record their actor**, so perception can tell what an agent did:
  an agent that put something into a container, or took from it, has looked
  into it.
- **An agent knows itself**: its own percept binds to its self referent,
  whatever recognition would say.
- **A third selector clash** (`describe:` on the store), caught by
  `make check`; the store's is `describeReferent:`.
- **Saved systems are one protocol** (`BGSavedSystem`): domains and the
  knowledge system both keep "domain <name> ..." lines.

Not yet: event perception (seeing things happen, not only how they are),
observations, propositions and interpretation rules, claims and
communication, credence, memory decay (`tri_generalize` is ready for it),
attention budgets, and the notebook.

27 tests, 237 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: agency

The first agency slice (`src/agency/`): a decision phase after perception;
per agent, a private motivation store (intentions as a stack with the
commitment at the bottom, the places searched, the decision count), saved;
and a decision log. AGENCY.md's Scenario 1 runs as "the missing nails": the
worker, committed to wedging the lock, walks to the bin it believes holds
nails and reaches in; the failed precondition yields *seek nails*; the
search follows its beliefs to the crate; with spares there it takes two and
wedges the lock, without them it drops the goal as impossible for now, with
the reason. On the omniscient stub (perception without limits) it never
visits the bin. The run is bit-identical on replay, decisions included.

What it settled:

- **A decision that only changes the intention is followed by another**, in
  the same phase (up to four), until the agent acts or waits; otherwise the
  next boundary might be the end of the run.
- **In mulle-objc, variadic methods can't use `va_start`**; see README.md.
- **Two nails, not one**: taking a single unit makes an individual, whose
  kind is `#Body`, not a stack of nails; the method takes two.

Not yet: goals and methods as content (AGENCY.md §5), scored goal
generation and consideration curves, needs, routines and habits,
dispositions and norms, salience, social behaviour (asking a coworker),
walking with a duration (agents walk a tile per millisecond), and the
decision committing at its own boundary.

28 tests, 255 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: goals and methods in content

Agency's goals and methods are content now (`content/agency.tri`, AGENCY.md
§5), and `BGAgency` interprets them; nothing about nails or locks is left in
its code. A goal has a `done` condition; a method has its goal, a `rank`, a
`pre` condition, an `order` for its candidates, an optional `search` slot,
and `steps`: `#Achieve` a subgoal, `#Do` an operation on slots. A condition
binds the slots it names (`find`) to referents believed present, depth
first, and matches the frame they describe (the type of its pattern, say
`#Wedging`) against its pattern: entailed holds, incompatible prunes,
unknown is followed but never holds. The missing nails is *wedge the lock*
(drive a nail in, after *have nails*) and *have nails* (fetch, else search),
and runs as before, its log saying what it does in content's words.

What it settled:

- **Slots are a frame type's features.** Triangle's types are closed, so a
  goal's slots are declared by a type, and a slot a goal shares with its
  subgoal is declared once on a type both frames inherit (`#WithNails`); its
  binding passes down when the subgoal is adopted and back up when it is
  done.
- **A condition lists the slots it binds**, in order. A slot left out of a
  description reads as its declared type, which a pattern that only names
  the type entails, so whether a slot was bound can't be read off a match.
- **Steps are re-read at every decision**, not tracked by position: a
  subgoal already done is passed over. The plan position AGENCY.md §2 keeps
  is derived from what the agent believes, so a belief that changes under a
  plan changes the plan.
- **Searched means seen inside since the goal was adopted.** Referents now
  keep when the agent last saw inside them (`insideSeen`, saved), so the
  bin it just reached into is passed over without the search being told.
- **Saves keep the groups submitted since the last boundary**, not only the
  deferred ones: the decision phase submits after the commit, and a save
  between boundaries had dropped the agent's next step. A run saved
  mid-search and restored into fresh knowledge and agency now ends in the
  same state, with the same decisions.

Open, then: recognition bound the crate's spare nails to the referent of
the bin's missing ones (same kind, the nearest absent referent). Settled by
the event perception slice: elsewhere, the features must unify too.

Not yet: method scores (believed cost, habits, dispositions), credence
thresholds and residuals as subgoals (`onUnknown`), parameters that are
values rather than referents (*have nails* should be *have some of a unit*),
and the rest of what the agency slice left open.

28 tests, 271 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: walking as an activity

A step is now an activity of a second (`#Walk`, with `duration: 1s`): the
walker arrives when it is done, so agents and the player cross the workshop
at a walking pace instead of a tile a millisecond. Operations declare the
providers they use (`uses: ["hands"]`, `["legs"]`; ACTIONS.md §5), and an
activity isn't started or resumed while a running one of the actor's uses
the same: two steps at once are refused, while prying goes on during a step
away and is suspended when the walker arrives out of reach. `lab play`'s
`walk` runs until the step lands. Agency needed no change: it waits while
its agent is busy, and decides again when the step is done.

What it settled:

- **An operation is described by its own type**, not always `#Operation`,
  and with its `uses`: otherwise a `#Walk` matched as unknown at its root.
- **The step's check is at arrival.** Walking off the map starts, and fails
  when the move would commit, with the reason.

Not yet: provider allocation counts only committed activities, so two
activities submitted for the same boundary both start (nothing does that
yet); walking speed from the walker (a tile a second for everyone);
movement along a path rather than a tile per decision.

28 tests, 276 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: event perception and communication

AGENCY.md Scenario 1's "ask a coworker" runs. An apprentice sees the smith
put the nails in a chest at the bottom of the map, then comes over by the
crate. The worker's search fails; *ask where nails are* (have nails' third
method) walks to the apprentice and asks; the apprentice answers from what
it saw; the worker believes it, walks to a chest it has never seen, takes
two, and wedges the lock. The variants: the apprentice didn't see (it says
"I don't know", and the goal is dropped); it doesn't answer (the worker
waits five seconds and gives up on it, a wait that survives a save); and
the omniscient stub, which asks no one.

- **Event perception** (KNOWLEDGE.md §5): an agent perceives the moves and
  utterances of actors in sight. A thing seen put somewhere is perceived
  there, inside a container too, though nothing else in it is. What it sees
  happen and hears said is kept as observations (§7), in its referents, and
  saved.
- **Saying** (§10): an action can carry content, and `say` commits a "said"
  event with it. Content is a Triangle structure (`content/talk.tri`:
  `#WhereIs`, `#IsIn`, `#DontKnow`) that names no referents; a method writes
  its question as one (`says:` on a `#Do` step).
- **Claims become beliefs**: a hearer binds what an `#IsIn` describes to its
  referents by recognition, or makes new ones, believes the thing in the
  container as of the claim's `when`, and marks it told by the speaker.
- **Answering** is a reflex for now: an agent agency controls answers every
  question put to it, from its knowledge view, saying whether it saw or was
  told.
- **Waiting for an answer** has a deadline, and the decision phase tells the
  scheduler when its next decision is due (`nextDecisionTime`), so a wait
  ends even when nothing else happens.

What it settled:

- **Recognition elsewhere needs the same looks.** Binding by kind and
  nearness made the apprentice, come over by the crate, take the crate for
  the chest it had seen the nails go into, and tell the worker the wrong
  place. A percept elsewhere than a referent was believed is bound to it
  only if their features unify; at the very place, kind is enough, so a
  stack that shrinks where it is stays itself. This also settles the open
  question the goals-and-methods slice left: the crate's spare nails are no
  longer taken for the bin's missing ones.
- **What is said names no referents.** Content describes things by kind,
  features, and tile, and the hearer recognizes them, so referents stay
  private to their agent.
- **Event details ride in the proposal's key**, which saves already keep:
  a deferred utterance survives a save.
- **A search slot passes over whoever was asked** since the goal was
  adopted, as it passes over a container looked into: both are read from
  what the agent perceived itself do.

Not yet: trust and credence (every claim is believed, at full strength),
attribution beyond "saw" and "heard", true and perceived ancestry, lying,
questioning sources, salience (every move and utterance in sight is kept),
answering as a goal scored against others rather than a reflex, talking
taking time, hearing that differs from sight, and saying things in `lab
play` (its menu offers `say`, which needs content the command can't give
yet).

29 tests, 317 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: credence, trust, and attribution

KNOWLEDGE.md Scenario 1, "the witness and the rumour", runs in the
workshop as *the rumour of the nails*. The apprentice (Marius) and a
neighbour (Nadia) see the smith put the nails in a chest. A carter (Teodor)
and a porter (Ulla) ask the apprentice where nails are; then the foreman
(Ines) hears from the carter, who names the apprentice, and from the
porter, who names no one. The foreman's credence is inflated, and the
inspector flags the false corroboration. Asked "who told you?", the porter
names the apprentice, the two claims merge into one group, and credence
falls to exactly the single-source run's. The neighbour, who saw for
themself, is an independent root, and credence rises. Variant A: the smith
keeps the nails, and the apprentice says it saw them go in. History records
a fabrication root, the apprentice's store marks its own utterance as not
believed, and the carter relays the claim in good faith. The foreman then
looks into the empty chest, finds the claim false, and trusts the carter
and the apprentice less. Questions are the test's; every answer is
agency's.

- **Agents have coats** (`#Agent.coat`, perceived by sight), so a claim can
  name a person by how they look ("I heard it from the one in the dark
  coat"), and the hearer recognizes them, or keeps a referent for someone
  only heard of.
- **Attribution is structure** (`content/talk.tri`): `#Saw`, `#Heard & {
  from: ... }`, or `#Heard` with no one named; `#WhoToldYou` asks for it,
  and the answer is the claim again with its source.
- **Testimony** (KNOWLEDGE.md §11's provenance items): a claim heard is
  kept with its source, its perceived root (the speaker for "saw", the one
  named for "heard from", unknown otherwise), its attribution, and, for
  the developer, the utterance it came in. A source repeating itself
  replaces what it said; it doesn't add to it.
- **Credence** is integer log-odds in decibans: a prior of -10 dB, plus,
  per group of testimony with the same perceived root, the strongest
  item's weight. That weight is the agent's trust in the source (20 dB
  untested), less 5 dB for hearsay (the lower of the trusts in source and
  root), or less 10 dB for a claim with no source named. Testimony with an
  unknown root is a group of its own. A claim is believed, and the thing
  placed, once its credence reaches 0 dB and no other claim of where the
  thing is weighs more.
- **Trust** is kept on each referent, and changes when a claim is settled:
  +5 dB when the agent sees it true, -15 dB when it looks into the
  container and the claim is false, for the source and for the root.
- **True ancestry** (developer-only) is traced when a claim is said, before
  the boundary's perception, from what the speaker knew when it spoke:
  seen (the speaker is the root), told (the claim relays the testimony
  that weighs most, and inherits its root), or believed nowhere (a
  fabrication root). The inspector shows each item's group, weight, and
  true root, and flags groups counted apart that share a true root.
- **Answers carry their source**: an agent that was told answers "heard
  from" whoever its strongest testimony names, by their looks.

What it settled:

- **Seeing a thing clears who told of it.** `toldBy` was kept after the
  agent saw the thing for itself, so a seen thing still answered as
  "heard". Now it is 0 once seen, as the field always said.
- **A description that says no more than its type names no one.** An open
  `#Agent` prints its defaults (`bent: false`, ...), which matched the
  hearer itself. Now a `from` whose concrete features are the bare type's
  is "no one named".
- **Looking in settles every claim about what is inside**, whether the
  thing is gone or seen elsewhere. That is naive: a claim true when it was
  made, about a thing moved since, is found false too.

Not yet: memory decay (variant B of the scenario), lying and questioning
as agency's choices (here the test speaks for the liar and the
questioner), trust beyond confirmation and refutation (relationships,
dispositions), claims other than where a thing is, credence for things
seen (sight is certain), and recognizing people by looks that don't
change while they hold things (`freeHands` is part of how an agent looks).

30 tests, 387 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: memory decay

KNOWLEDGE.md Scenario 1's variant B runs. The apprentice sees the nails go
into the chest, then goes off out of sight of it all. A day later it
remembers a wooden chest, not an oak one, nails of some metal, and the
smith in a dark coat rather than a brown one. On day 10 the foreman asks
it where nails are: it still says the chest, with no material, mass, or
unit left in its description, and says how sure it is (10 dB, down from
30). The foreman weighs the claim no higher than that, so its credence is
lower than a fresh account's. On day 20 the apprentice has forgotten, and
says it doesn't know. The run is the same on replay.

- **Hierarchies in content:** `#Material` is metal (iron, brass), wood
  (oak), flesh, or paper; coats are `#Colour`: dark (black, grey, brown,
  navy), light, or bright. Memory loses detail along them.
- **Detail decays when read** (KNOWLEDGE.md §12): for each memory step (a
  day) since a referent was last seen, every feature it keeps generalizes
  a step along its primary parent with Triangle's `tri_generalize`.
  Numbers without a declared `@widen`, and text, go in one step, and a
  feature generalized as far as it goes is dropped. Nothing is stored:
  descriptions, recognition, and answers all read memory through the
  store's `recall:`, from the world's time, so decay is exact across
  saves.
- **Strength fades**: a belief of where a thing is starts at 30 dB if seen
  (its credence if told), loses 2 dB a step, and below 0 dB the agent
  forgets where it is, at its next perception phase. Seeing it again
  restores detail and strength.
- **A claim of what the speaker saw says how sure it is** (`#Saw & {
  sure: ... }`), and the hearer weighs it no higher than that.

What it settled:

- **Recognition reads memory, not the last percept**, so a decayed
  description can bind a percept it once conflicted with: KNOWLEDGE.md's
  honest misidentification has a way in.
- **The kind does not decay.** Agency's slots and recognition both compare
  kinds exactly, and a stack forgotten as a body would no longer be the
  stack its testimony is about. Only features decay.

Not yet: forgetting at its own scheduled time (it happens at the next
perception phase after the strength falls), decay rates by salience and
repetition (every feature fades at one rate, a step a day), persistence
by feature (a coat changes daily, height doesn't, CONTENT_LANGUAGE.md's
recognition weighting), competing identity hypotheses, bounded stores
with eviction, and generalizing the kind for things whose kind memory
could lose.

31 tests, 411 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: salience and bounded stores

At rest, with nothing in mind, the worker sees the smith take the smith's
nails: routine, so it is not kept as an observation, though the worker
still sees where the nails went. Committed to wedging the lock, which
concerns the nails, it keeps the observation of the smith putting them
back. Then it sets to driving a nail of its own, and while it drives it
misses the smith taking them again. But a gossip asking it something is
noticed, and answered. The gossip keeps only four observations: asked five
things, it lets go first of what it said itself, then of the oldest.

- **Salience** (KNOWLEDGE.md §7, AGENCY.md §10) is a score per
  observation: being addressed 30, the agent's own deeds 20, something its
  goals concern 15, the rest 0. An observation is kept only if its score
  reaches the notice threshold, 10, raised by the `attention` the agent's
  running activity demands (driving and prying demand 10). A claim the
  agent didn't notice, it doesn't believe. What is seen still updates its
  referents.
- **Goals say what they concern** (`concerns: [...#Body]` in content):
  wedging the lock concerns the lock and nails. Agency tells knowledge
  (the `BGConcerns` protocol); an observation concerns a goal when its
  subject, or what was said, is entailed by one of the patterns.
- **Bounded stores**: an agent's `memory` (content, 64 by default) caps
  its observations. Over it, the least salient go first, the oldest of
  those first: deterministic.
- **Observations have serials**, never reused, so agency's place in what it
  has heard survives eviction and saves.

Not yet: anomalies and threats as salience (what contradicts a belief,
harm), salience for referents and testimony (only observations are
bounded), an interruption threshold (something salient enough stopping an
activity for a decision), attention budgets per boundary rather than a
threshold, and decay rates by salience.

32 tests, 458 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: saying things in `lab play`

The player's character can talk. `ask <R> where <R>` asks someone in
reach where something like a referent is; `ask <R> who <R>` asks who told
them where it is; `tell <R> <R>` says where the character believes it is,
with how it knows; and `tell <R> <R> in <R>`, for a container it doesn't
believe the thing is in, is a lie, said as "saw" and traced to a
fabrication root. The session runs agency for every agent but the one
played, so they answer, and waits a few boundaries for the answer. In the
test, the worker tells the smith where the nails are, asks where they are
(the smith answers that it heard so from someone in a blue coat), asks who
said so, then takes the nails and says they are still in the bin.

- **What an agent can say is composed in one place**: the knowledge store
  builds claims (`claimAbout:`, `claimThat:isIn:`) and questions
  (`askWhereIs:`, `askWhoToldOf:`) from what it knows, naming no
  referents. Agency's answers use the same code.
- **`as <id>` hands the agent played over**: agency lets it go, and takes
  back the one left. `control:` is idempotent, so the others keep their
  place in what they've heard. Saves in play include agency.

What it settled:

- **Sight outranks a claim about the present.** A claim that a thing is
  somewhere, as of a moment when the hearer saw it elsewhere, is found
  false at once, and the speaker is trusted less; seen elsewhere since the
  claim's moment, the claim is not believed but stays open. The smith,
  told by the worker holding the nails that they are in the bin, still
  can't tell those nails from others: it believes other nails are in the
  bin, until it looks.
- **A person named can be the hearer itself** ("you told me"): with
  descriptions that say no more than their type ruled out, recognizing
  oneself is no longer a false match.

Not yet: free content from the player (anything beyond where something
is), answering as a choice rather than agency's reflex, and conversations
that take turns over time.

33 tests, 472 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: answering as a choice

Being asked is a candidate goal (AGENCY.md §4's social generator, §11),
kept in the motivation store and weighed at every decision point. It is
worth the agent's trust in the asker (dB), plus its `helpful` disposition
(a new `#Agent` field, not perceivable, -30 to 30 dB, 0 by default), less
3 for each point of attention its running activity demands, less 5 if it
holds a goal of its own. Worth more than nothing, it answers. Worth nothing
only because it's busy, it puts the question off ("busy: not now") and
answers when it's free, if the asker can still be waiting (5 s). Otherwise
it refuses, saying `#WontSay`. A question waited on too long is let go.

In the tests, a surly apprentice (helpful -25) weighs the worker's
question at -5, says it won't, and the worker's goal is dropped. The
worker, driving a nail (attention 10), weighs the gossip's question at -15
and puts it off; at the boundary the drive completes, it weighs it at +15
and answers, before noting its goal done. A question put off is saved
with the mind.

Not yet: dispositions beyond helpfulness (honesty, so lying is agency's
choice too), refusing changing the asker's trust, comply or refuse for
requests other than questions, and consideration curves (the
considerations add, in dB, without curves).

33 tests, 488 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: traces

KNOWLEDGE.md Scenario 2's first half runs as *the cleaned workshop*, with
the workshop's lock. At night the smith wedges the lock, which leaves tool
marks on it and scuffs on the floor. The smith then washes the floor and
touches up the paint, and each removal leaves traces of its own: a damp
floor and a smell of soap, fresh paint and a smell of paint. The night
passes in a boundary or two. The damp floor runs out after six hours and
is removed exactly then. In the morning the foreman, by the lock, sees the
fresh paint and smells it, and smells a fainter soap. The tool marks, the
scuffs, and the damp are gone, and nothing in the foreman's store says
what made any of it. The developer finds each trace's creation in history,
in the operation that made it.

- **Traces are component state** (`content/traces.tri`): informational
  entities with a `#Trace` component (kind, bearer or tile, magnitude, made,
  runs out). Trace kinds are content (`@family(traces)`): the sense that
  perceives them, and how long they last.
- **Operations declare them**: `leaves` (kind, site, strength) and
  `removes` (kind, site), the site one of the operation's roles or the
  actor's tile. They are made and removed in the effect's own group, when
  an instant action is performed or an activity completes. Content holds to
  the rule that an operation that removes traces leaves some of its own,
  and the test checks it. New operations: `wash_floor`, `touch_up`, and a
  `tend` effect that changes nothing but traces.
- **Aging is analytic**: a trace's strength fades evenly from its
  magnitude to nothing at its expiry, computed when read
  (`BGTraceStrength`). The trace domain (`BGTraces`) costs nothing between:
  its horizon's next event is the earliest expiry, at which boundary it
  removes what has run out.
- **Perception** finds traces by their kind's sense: by sight on what the
  agent sees or on the floor in sight, by smell within a tile. It keeps the
  kind, the site, how strong it seemed, and when; a trace it perceived at
  a site it perceives again, and doesn't find, is gone. Saved, with a
  developer-only truth link.

Not yet: conditions that speed decay (rain, foot traffic), sense acuity
and kind floors (any strength above nothing is perceived), traces on
stacks individuating the units they're on, per-stage traces (an activity
leaves its traces when it completes), and traces from reactions.

34 tests, 510 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: appearance and truth

KNOWLEDGE.md Scenario 2's plated fitting: a fitting that looks brass and
is steel. The foreman sees brass. A scratch test reveals steel and leaves
a scratch; the foreman then knows steel however often it sees brass again.
The smith, who watched, sees the scratch, and still believes brass. On the
lock, which is what it looks like, the test says brass.

- **Appearance fields** (KNOWLEDGE.md §4): a component field may declare
  itself another's appearance, `appears(material)`. `#Body.surface` is
  what its material looks like: "natural" by default, or a material from
  the top of the hierarchy down. The view reports the appearance in the
  true field's place wherever it is set.
- **An analysis operation**, `test_scratch` (3 s, hands): its `analyse`
  effect commits an "analysed" event whose detail is what lies beneath,
  the true material, and it leaves a `scratch` trace.
- **What an analysis found is kept** with the referent (`deeper`), the
  analyser's own, and overrides its looks when the agent recalls it:
  descriptions, recognition, answers, and decay all read it. Saved.

What it settled:

- **An open enum field is a seeded variation point**, so a field like
  `surface` needs a default that means "nothing of its own"; an
  anonymous disjunction with a named enum type doesn't parse as one, so
  `surface` lists the material hierarchy's top atoms.

Not yet: appearance for fields other than material (a disguise's face and
coat), analyses reaching more than one level down, other agents learning
what an analysis found (by being told, or by examining the scratch), and
analysis operations beyond the scratch test (acid, comparing seals).

35 tests, 526 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: interpretation rules

KNOWLEDGE.md Scenario 2's second half. The smith wedges the lock at night,
with the porter, who can't paint, watching; the porter goes home, and the
smith touches up the paint. In the morning three come by the lock: the
foreman, a painter; the porter; and the carter, who neither paints nor saw
the marks. Everyone sees fresh paint. Only the foreman concludes that
something was done to the lock (*touched up*, which needs a painter's
eye). Only the porter, who saw the tool marks and finds them gone under
fresh paint, concludes they were painted over (*covered up*, which needs
that prior belief). The carter concludes nothing: paint is paint.

- **Rules are content** (`content/interpret.tri`, `@family(rules)`):
  premises over the thing a finding is about, a trace perceived on it now
  (`#Sign`) or perceived before and gone now (`#Formerly`); the expertise
  it needs (`skill`, `mastery`); the `#Finding` type it concludes; and the
  credence it lends.
- **Expertise is the agent's own**: skills are `#Agent` fields (`painting`
  for now), read from the world as what the agent knows of itself.
- **Immediate interpretation** runs after each perception phase, every
  rule the agent has the expertise for over its referents; a rule whose
  premises hold adds its finding, kept with the rule as its provenance,
  dumped, and saved.

Not yet: deliberate interpretation (investigating as an activity, with
costlier rules), expertise grading a conclusion's precision rather than
gating it, premises over beliefs other than traces (claims, features,
findings), retracting a finding when a premise is retracted, findings
feeding credence and agency, and attention budgets for interpretation.

36 tests, 543 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the notebook

KNOWLEDGE.md Scenario 3's remaining half. (The remembered map with its
ages, and the menu offering what is no longer so, ran already: the stale
belief test.) The worker looks into the bin, writes down where the nails
are in its notebook, puts the notebook in the bin, and goes. The smith
takes the notebook and reads it, and comes to believe the nails are in the
bin: testimony whose source and perceived root is the worker, recognized
by the looks the writing gives, read in the notebook. The worker's memory
is as it was. In `lab play`, `notebook` shows what the character knows,
as it knows it, and `note` keeps the player's own notes, which never reach
the character.

- **Records** (`content/talk.tri`): `#Record` bodies carry `writing`, a
  `#Writing` with its author, by their looks, and its entries, claims as
  `#IsIn`. `write_down` (the copy operation) appends a claim the writer
  composed from its beliefs (`writingAbout:`); `read` commits a "read"
  event carrying the writing, and the reader takes each entry as testimony
  from the author, `via` the record.
- **`lab play`**: `notebook` (what the character remembers where, what it
  was told and by whom, open questions where something is claimed in more
  than one place, its findings, the traces it sees), `write <R>`, `read
  <R>`, and `note <text>` / `notes`, the player's, out of character.

What it settled:

- **Free hands are not how someone looks.** A person described by their
  looks no longer carries `freeHands`, so the writer, holding the notebook
  when writing, is recognized by a reader who saw them with free hands.
- **Writing is composed as text, not reprinted.** Printing a parsed
  `#Agent` expands every open field, so the writing is kept as written,
  split at top-level commas (`BGSplitTopLevel`).
- **mulle's Foundation trims differently** (`stringByTrimmingCharactersInSet:`
  left what Apple's removes), so the splitter trims in C.

Not yet: true ancestry through records (what is read is untraced),
forging and destroying records, reading taking time, records other than
notebooks (ledgers, letters), and the player choosing which claim to
write beyond "where something is".

38 tests, 579 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: weighing goals (the false alarm)

AGENCY.md Scenario 2, *the false alarm*, variants A to D. A watchman walks
past the storeroom, sits down by the gate to eat supper, out of sight of
the storeroom and in earshot, and hears a cat knock something over beside
it. The rule *stirring* makes of the clatter that something stirred there.
*Investigate the disturbance* arises, and is weighed against supper.
- **A** (the noise alone): credence 0, worth 15 against supper's 20 plus
  the margin and the interruption, 30. It keeps eating.
- **B** (two rumours, neither naming a source): two groups, credence 20,
  worth 35. It puts supper down, walks over, and looks in. No one is
  there: the claim is found false, and it trusts the carter and the
  porter less. Then it goes back and resumes its supper where it left off.
- **C** (the same rumour, both naming the neighbour): one group, credence
  15, worth 30, not more than 30. It stays.
- **D** (B with noise after noise): the intention changes once.

The run is the same on replay, and saved mid-investigation, with supper
suspended beneath, it ends the same.

- **Worth** (AGENCY.md §3): goals declare considerations in content
  (`#Flat`, `#Cost`, `#Suspicion`), added in dB. A suspicion is the
  credence that something like the suspect is in the slot's referent: the
  strongest claim, with findings of the evidence about the place as a
  group of their own.
- **Arising** (§4's reactive generator): a goal with `arises` is a
  candidate for each recent finding of its kind about something of its
  kind (`of`), while the finding is salient (`lapse`). The agent doesn't
  investigate, after supper, a noise from a minute before.
- **Weighing**, at every decision point and mid-activity (a soft
  interruption): the best candidate wins only by more than the current
  intention's worth plus a margin (5), plus an interruption cost (5) while
  an activity runs. Winning, agency suspends the agent's activity, and
  puts the new goal on top; the old one stays beneath, and its activity is
  resumed, not begun again, when the agent comes back to it. A goal that
  arose about something is settled with it. The log gives each weighing's
  considerations and verdict, when the verdict changes.
- **Conditions of what the agent did**: `#Looked` (the slot's inside seen
  since adopting the goal) and `#Did` (an activity of the operation
  completed since).
- **Hearing**: traces have a third sense; a clatter is heard within 10
  tiles, out of sight too. The interpretation premise `#Near` holds for
  something at or beside a trace on the floor. A premise the interpreter
  can't read never holds.

Not yet: autopilot returning control to the player (variant E),
consideration curves (considerations add, without curves), risk weighted
by a risk-tolerance disposition, duty from a commitment rather than a flat
worth, needs and routines as generators, scoring methods as well as goals,
and the seeded tiebreak.

39 tests, 635 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: autopilot

AGENCY.md §14 and Scenario 2's variant E. The player hands the watchman to
agency to eat supper, to be called back for anything worth more than 25.
In B's conditions, the noise weighs 35: control returns at that weighing,
supper still under way, and nothing is looked into. In A's, it eats on,
and control returns when supper is done. In `lab play`, `autopilot <goal>
[n]` hands the character over and runs time until control returns: the
worker, having looked into the bin, fetches nails, wedges the lock, and is
handed back.

- **Autopilot** decides for the player's character exactly as for anyone,
  from its knowledge view. It takes up no goal of its own: a candidate
  worth more than the player's threshold hands control back, with a notice
  saying why; so does a goal done or impossible. The mind goes, and its
  log stays for the developer.
- **`logOf:` no longer makes a mind**: asking for the log of an agent
  agency didn't control had put it under agency's control.

Not yet: autopilot modes beyond "this goal" (a routine, auto-explore,
carrying out a recipe), and control returning at a salience crossing that
isn't a goal arising (a question asked of the character, say).

40 tests, 653 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the tempting purse

AGENCY.md Scenario 3. A purse on the merchant's counter; Kasimir, who owes,
beside it; the carter across the room; and Mira, a child, half hidden in a
doorway, who sees Kasimir unseen. The merchant turns away, and Kasimir's
debt falls due (*get money*, a commitment, no body's need). Taking the
purse scores 20 (30, less 5 for his low honesty and 5 for his weak
scruples, and no one he knows of watching), borrowing from a friend 10:
he takes it, though a witness is truly there. Mira, curious, keeps what
she saw. When the merchant comes back and asks her, she says Kasimir has
it, having seen it; the merchant believes her, and trusts her more when it
sees Kasimir with the purse.
- **A** (Kasimir sees Mira): he believes himself watched, and taking
  scores -20, unthinkable. He tries to borrow from everyone he knows of,
  and gives up.
- **B** (an honest Kasimir): taking scores -20 unwatched, too.
- **C** (no Mira): his decisions are the base case's, line for line.

- **Dispositions and a norm** (AGENCY.md §9) are `#Agent` fields:
  `honesty`, `curious`, and `scruples` (don't steal). Others can't
  perceive them.
- **Methods are scored** (§5): `score` considerations in content, `#Flat`,
  `#Trait` (tenths of a point per point of a disposition or norm), and
  `#Watched` (a penalty if the agent believes someone else is in sight of
  the slot's referent). Methods are tried best first, then by rank, and
  one that scores below nothing is unthinkable. Unscored methods keep rank
  order.
- **Hiding**: a hiding agent is seen only from a tile away, though it
  sees as well as anyone, so the believed and the true observers differ.
- **Curiosity** lowers the notice threshold: a curious agent keeps routine
  observations.
- **Claims about who holds something**: `#IsHeld` (a claim with a
  `holder`, beside `#IsIn` under a common `#Telling`), composed, believed,
  and answered.
- **Requests** (`#Request`) are questions; nobody grants them yet.

Not yet: commitments with deadlines and urgency curves (the debt is a
plain commitment), granting requests (lending, hiring), risk tolerance,
believing oneself observed from what one hears, the merchant acting on
what it learns, and sanctions (§6, institutions).

41 tests, 683 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: routines and commitments

AGENCY.md Scenario 1 as written: the worker's shift, an employment
commitment from 8:00, is what puts wedging the lock in its mind. The world
is quiet from the night's events until 8:00, when the scheduler wakes the
worker; the routine generator offers its commitment, worth its duty (20)
and no urgency yet, and with nothing else to weigh it against the worker
takes it up, and the missing nails play out as before. Done, or found
impossible, the commitment is settled for the shift and not taken up
again. A shift of five seconds closes mid-search, and the commitment is
dropped with what it needed. Taken up three tenths of the way through its
window, it is worth 6 more for urgency. Saved mid-shift, the run ends the
same.

- **Commitments** (AGENCY.md §7): an agent undertakes a goal for a window,
  from a source (`undertake:goal:from:until:source:`), kept in its
  motivation store and saved.
- **The routine generator** (§8): while a commitment's window is open, its
  goal is a candidate worth `BG_DUTY` plus an urgency rising evenly to
  `BG_URGENCY` at the deadline, weighed with the reactive candidates
  against what the agent is doing.
- **Windows**: the decision phase tells the scheduler when one opens or
  closes (`nextDecisionTime`), so a quiet world wakes for them. A window
  that closes drops its commitment and what it needed.

Not yet: habits (a context, a choice, a strength rising with repetition
and decaying), daily windows (each commitment is one window), promises
made by saying so, breaking a promise as a history event that lowers
trust, urgency curves other than a straight line, and the decision
re-weighing as urgency rises between boundaries.

42 tests, 702 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: needs and interoception

AGENCY.md §6. A hungry worker (70), idle, with its supper in hand: the
needs generator raises *eat something*, worth 35, the pressure of what it
feels, and it eats; the supper is gone and the worker is fed (80). A
worker driving a nail when it is 50 hungry feels only 30, its hunger dulled
by the attention the drive demands, and eats only once the drive is done.
A worker fed at 80 grows hungry a point every three minutes; the body
domain wakes it at each band of ten, and at 90 minutes it feels 50 and
eats, with nothing computed between.

- **A body stock** (`#Agent.fed`, as of `fedAt`) falls analytically,
  computed when read (`BGSatiety`). The body domain (`BGBodies`) proposes
  nothing; its horizon is the next time anyone's hunger crosses a band, so
  perception refreshes there.
- **Interoception** is a sense: each perception phase the agent feels its
  hunger, to the band below, dulled by twice its activity's attention
  demand; the knowledge store keeps what it feels, and saves it.
- **The needs generator**: a goal `pressed` by a need (`#Pressing`) is a
  candidate while the felt need is above its threshold, worth a `#Need`
  pressure over what the agent feels. Done or given up, it presses again
  only when the need is felt 20 more. A kept commitment now weighs its duty
  and urgency against candidates too.
- **Eating** is an effect: the food is gone, and the eater half again more
  fed.
- **An agent agency takes over decides at once**: `control:` asks for a
  decision at the next millisecond, so an idle agent doesn't wait for
  something else to happen.

Not yet: other needs (rest, warmth, air) and their stocks in other domains,
misperception from modifiers other than attention (adrenaline, numbness),
the body domain in `lab play`, starvation's consequences, and finding food.

43 tests, 719 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: habits

AGENCY.md §8. Each morning the worker comes in at the door and is handed
nails to put away. For three days it knows only the crate, two tiles off,
and puts them there, watched by a curious apprentice. On day 4 a bin
stands right beside it, and the worker walks past it to the crate, its
habit (the method's, and the crate's for the slot) deciding; a worker
without the habit uses the bin. By day 45 the habit has faded, and the bin
wins. The apprentice, having seen it three times, believes the worker
usually puts things in the crate, and the day-45 bin is an anomaly to it,
salient.

- **An agent's habits** are kept in its motivation store, with a
  context ("goal:method", "method.slot"), a choice (a referent, or none for
  a method), and a strength that gains 10 each time the agent performs
  the method's operation, up to 100, and fades a point a day, computed
  when read. Saved.
- **Method defaults**: a habitual method adds a tenth of its strength to
  its score, so habitual ways win ties; a slot ordered by `"habit"` tries
  its habitual referents first.
- **Others' habits**: the `#Repeated` premise holds for someone seen
  putting things into the same container at least so often, and the rule
  *usually puts* concludes a `#Habit` finding with that choice. Seeing them
  put something elsewhere is an anomaly, salience 25.
- **Committing to a goal wakes the agent**, as taking it over does.
- **Recognition no longer weighs free hands**: someone seen elsewhere,
  holding something they weren't, is still themselves.

Not yet: habits of routes (which way to walk), habits feeding back into
belief (Oskar believes the wrench is on the hook because he always hangs
it there), habit strength set by salience, and beliefs about habits
decaying.

44 tests, 741 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: promises

AGENCY.md §7. The smith, having looked into the bin, promises the worker
beside it that the nails will be in the crate within a minute. The promise
is the smith's commitment, from then until the deadline: it takes the
nails from the bin and puts them in the crate. The worker holds the promise
as a claim about then: looking into the crate early settles nothing, and
looking after the deadline, it finds the promise kept and trusts the smith
more. Given three seconds instead, the smith can't make it: the window
closes, the promise is broken, and the worker, finding the crate empty
after the deadline, trusts the smith less.

- **A promise is a claim about a time to come**: `#IsIn` with the
  attribution `#Pledged`, `when` its deadline (`promiseThat:isIn:by:`).
  Hearers hold it as testimony, not believed of now and counted toward no
  credence; it settles only when due, kept if they see the thing there,
  broken if they look and it isn't, and their trust in the promiser moves
  as for any claim. Promises aren't traced as claims of what is.
- **Making one is a communicate act** (`promise:to:goods:in:by:`): agency
  says it, and undertakes a commitment, with its slots bound (`deliver`,
  the goods and the destination), from now until the deadline. A promise
  whose window closes undone is logged as broken.
- **Commitments carry slot bindings**, adopted with the goal.
- **Goals with a subgoal for holding** (`deliver` needs `hold_it`) carry
  something from one place to another.

Not yet: breaking a promise as a history event others learn of without
looking, promises of things other than where something will be, the
player promising in `lab play`, and promises' worth beyond the duty (the
weight of one's word, a disposition).

45 tests, 768 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: granting requests

AGENCY.md §11, comply or refuse. In the tempting purse, the carter now
carries his wages. An honest Kasimir, who won't take the purse, asks the
carter to lend: the carter weighs it at its trust in him (20), less the
cost of parting with something (15), +5, and gives him his wages, saying
so. Kasimir has money; his debt's goal is done. A Kasimir who notices Mira
asks her first: she has nothing like it, and says so; then the carter
lends.

- **A request is a question** (`#Request`), heard and weighed like one:
  trust in the asker, the `helpful` disposition, busyness and its own
  goals, and `BG_PARTING` less. Granted, the agent gives what it holds like
  it (`give`, a new operation: into the receiver's free hand) and says
  `#Granted`; refused, `#WontSay`; with nothing like it in hand,
  `#HaveNone`.

Not yet: requests for help (doing something) rather than for a thing,
lending as a debt the borrower owes back, the value of what is parted with
(every thing costs the same), and asking for work.

45 tests, 775 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: investigation

KNOWLEDGE.md §9's deliberate mode, and Scenario 2's *investigate
workshop*. In the cleaned workshop's morning, the foreman by the lock sees
the fresh paint and smells it, but the smell of soap, a day old and faint,
goes unnoticed in passing. It watches closely for half a minute: at the
end it notices the soap on the floor beside the lock, and draws what takes
thought, that someone cleaned up there.

- **A perception floor**: a trace fainter than 30 goes unnoticed.
- **Investigating is an activity** (`watch_closely`, 30 s, attention 20):
  its effect commits an "investigated" event, and at that boundary the
  investigator looks closely: the floor drops to 5, smell reaches a tile
  further, and rules marked `deliberate` are drawn as well (`cleaned
  nearby`, from a faint soap smell beside something).
- **A glance can't miss what only a close look caught**: a faint trace
  isn't marked gone by ordinary perception.

Not yet: investigation choosing what to examine (it looks at everything in
range), deliberate rules costlier than a premise check, expertise grading
what a close look finds, examining a thing's history (trace perception of
age), and agency choosing to investigate.

45 tests, 778 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: two hands, one seal

ACTIONS.md Scenario 2. The spare piston seal lies on the bench, reserved
for A (the worker). A and B (the smith) start taking it up at the same
time; their takes complete at the same boundary, and exactly one applies:
the other is rejected whole, its activity fails with the reason, and the
loser sees the seal in the winner's hand. Over 1,000 seeds each wins about
half the time, and swapping their IDs changes nothing; weighted one to
three by quickness, B wins about three times in four; the same seed gives
the same winner; and the reservation blocks nothing. With agency: B, told
by A that the seal is A's and disposed to respect that, never starts (taking
it scores -30); B, who doesn't mind, races A for it.

- **A move can expect where its target is** (`move:to:expecting:`), and
  validation rejects the group if it isn't there any more. `take` and
  `take_up` expect the item where it was when the effect was built, so two
  simultaneous takes can't both apply. Saved with deferred groups.
- **Weighted fair order** (ACTIONS.md §8): an agent's `quickness` (a
  derived reaction speed) weights its groups; when weights differ, the
  order is drawn by successive weighted sampling from the same seeded
  stream, in integers. With equal weights the order is the seeded
  permutation as before.
- **Reservations** are reified claims (`#ClaimKind` "reservation") that
  never block a commit. Told of one (`#ReservedFor`, a claim naming a
  holder), an agent keeps a `#Reserved` finding about the thing, and a
  `#Respect` consideration, scaled by its `respectful` disposition, costs a
  method that takes what it believes reserved for someone else.
- **`take_up`**: taking up carefully, a second's activity.

Not yet: reservations perceived other than by being told (a tag on the
thing), grievances (A, who knew of the reservation, losing the seal), and
weights from other derived values.

46 tests, 1799 checks (a thousand of them the fairness draws), under both
compilers, ASan and UBSan, and leak-free.

### After the slice: the coat at dusk

CONTENT_LANGUAGE.md Scenario 3. The porter (Ulla) sees a visitor in a grey
coat by day. At dusk, a figure three tiles off, its coat looking only
dark: it unifies with the visitor, and the porter's memory keeps the more
specific grey. Next morning, a figure of the visitor's build in a brown
coat: recognition fails at exactly one path, the coat, and a coat changes
daily, so the porter makes a new referent and a hypothesis that it may be
the visitor (0 dB: five features agree, the coat doesn't). A week later
both coats have decayed past telling, and the brown-coated figure fits
both: that alone raises the hypothesis to +10. If the figure was a
stranger (B), the inspector flags a false merge; if it was the visitor in
a brown coat (A), the decayed memory found the right answer for a weak
reason.

- **Persistence** is content (`content/persistence.tri`): a coat lasts a
  day; a feature not listed, long.
- **Recognition weighs failure**: a percept that doesn't unify with a
  referent elsewhere is checked with `tri_conflicts`, every conflicting
  path; if all are short-lived (a week or less), the new referent gets an
  identity hypothesis (`BGIdentity`) with a credence from the paths that
  agree (+3 each) and conflict (-5 each), the failing paths recorded.
- **A later percept that fits both** referents of a hypothesis raises it by
  10, once a sighting.
- **Dusk** is a conditions stub: beyond arm's reach, what is seen is
  generalized a step (grey looks dark), and a match keeps memory's more
  specific values, as unified, only the features either had.
- **Coats are proposable**: people change them.

Not yet: merging referents when a hypothesis is believed, hypotheses about
things other than agents' looks, persistence feeding decay rates, light
from a domain rather than a flag, and compacting knowledge arenas.

47 tests, 1811 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the nut of unknown size

CONTENT_LANGUAGE.md Scenario 2. The worker, holding a 19 mm spanner, is to
tighten the pump's gland nut four tiles off. From there it sees the nut's
size only as 16 to 22 mm, so whether the spanner fits is unknown, with the
residual `nut.size`. The method's `onUnknown` makes that a goal: it walks
over, sees the nut plainly (19 mm), and tightens it. A: the nut is truly
22 mm, and up close the match is incompatible: the method fails. B: the
omniscient stub sees the size from afar and never looks closer. With a 22
mm spanner, the same closer look finds it incompatible. The run is the same
on replay.

- **Sizes** (`#Sized`, widening a millimetre a step), **fasteners** (loose
  or tight) and **spanners**, with a `tighten` operation whose roles share
  the size tag `$s`, and `peer_at`.
- **Acuity** is content (`#Acuity`, beside persistence): a feature blurs
  `blur` steps for each tile beyond arm's reach, by `tri_generalize`, so a
  number becomes an interval. A blurred percept keeps memory's more
  specific value.
- **`onUnknown`** (AGENCY.md §5): when a method's precondition is unknown
  rather than false, the first unknown full binding, and the path its match
  left unknown, are kept; a method that declares `onUnknown` adopts that
  goal first, with those bindings, and is followed again when it is done.
- **`#Reached`**: a goal done when the agent is within reach of a slot's
  referent.
- **What it settled**: Triangle finds `@widen` along primary parents only,
  so a type that mixes in `#Sized` lists it first.

Not yet: credence thresholds deciding whether to look first (variant C,
two hypotheses of the nut's size), residuals other than a feature to see
closer (asking, measuring), and the lamp (light as a condition).

48 tests, 1831 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the seized valve

ACTIONS.md Scenario 1. A valve on the water line is rated 12 Nm; hidden
corrosion has seized it, and it takes 70 Nm to break free. The worker's
menu offers *rotate valve*, exactly as for a valve that isn't seized. Bare
hands put 15 Nm to the handle; the valve answers with nothing. A wrench
gives 50 Nm: still nothing, and the wrench wears. The wrench with the pipe
over its handle reaches 0.6 m: 120 Nm, past the wrench's 80, so there is
risk, not refusal: over seeds, sometimes the wrench bends first, sometimes
the valve frees. A steady 75 Nm frees it with no risk. A blow with a stone
loosens the bond to 40 Nm, and the wrench alone turns it. The worker's
store never holds the breakaway.

- **Instrument chains**: `#Lever` (reach, the torque it bears, and whether
  it is a sleeve over another's handle), `#Wrench` and `#Pipe`; an agent's
  `grip` (N). The `rotate` effect searches what the actor holds the same way
  every time, to depth 3 (hand; hand, lever; hand, lever, sleeve), for the
  furthest reach, and applies grip times reach, held at the command's
  amount if given.
- **Effects with no success flag**: the stage commits "torqued", the
  torque applied with the turner's expectation from the rating; the valve's
  reactor (`BGValveKind`) turns it or holds, and records the attempt, its
  torque, breakaway, expectation, and outcome. A blow (`strike`) commits
  "struck", and the valve loosens.
- **Graded excess**: past a lever's limit, a seeded draw in proportion to
  the excess bends it (a trace, half the limit from then on), and it gives
  way before the valve does. Using a lever leaves tool marks, in the
  stage's group.
- **Events can carry amounts** (`emit:subject:other:amount:detail:`).

Not yet: agency choosing instruments and force (the test chooses), the
chain search over things in reach rather than in hand, sounds and visible
bending as percepts, the actor's exertion, and impact as a graded effect.

49 tests, 1895 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: rechecking on resume

ACTIONS.md Scenario 3's sixth check, and an item from the activities
slice's list. The worker, driving a nail of its own into the lock, puts the
drive down at two seconds; the smith, beside it, takes its nails. Still
within reach, but no longer in its hand: resuming is refused, with the
reason, and the drive stays suspended until the nails are back.

- **A resumed stage rechecks the operation's pattern** against what is so
  now (`BGMatchAction`), as well as reach and providers: incompatible
  blocks it with the failing path; unknown doesn't.

Not yet, of ACTIONS.md Scenario 3: recipes expanded through knowledge (a
diagram binding the wrong cock), child activities, a shout as a soft
interruption, partial effects on abort, and the watch on rising water.

50 tests, 1902 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the interrupted repair

ACTIONS.md Scenario 3, most of it. The worker holds a wrench and the
miller's diagram, which wrongly shows the trough line's cock as the pump's
shutoff. It reads the diagram and sets to *repair the pump* by the recipe:
shut off the pump's line, then dismantle the pump (three stages). The
recipe binds through what it knows, so it shuts the trough line's cock;
the omniscient stub, which needs no diagram, shuts the riser's. At 60% of
dismantling's last stage the worker is called away and puts the work down:
the progress is kept and nothing is committed. The smith, beside it, takes
the wrench. A save then restores the same. The worker goes back to the
recipe, and resuming is refused, with the reason; with the wrench back, it
resumes, and the pump is open.

- **Recipes** are `sequence` methods: their operations in order, once
  each; a timed one is done when its activity has completed since the goal
  was adopted, an instant one when performed (kept, and saved, with the
  intention). A recipe being followed with a suspended activity is
  followed again even if its precondition no longer holds: resuming
  rechecks what it needs.
- **Diagrams** are records whose entries are `#Serves` claims (which line
  something serves); a reader keeps what one says with the referent,
  beyond its looks, as it does an analysis's finding. `#Writing` entries are
  any `#Telling`.
- **The omniscient stub sees hidden fields** (`featuresOf:all:`): every
  content field the inspector shows.
- **Cocks** (`serves`, hidden; `shut`) and **the pump** (`opened`), with
  `shut_off` and the three-stage `dismantle`.

Not yet, of the scenario: talking while working as a voice provider (an
utterance is instant), abort committing partial effects, inspection
binding the faulty part, improvising another chain, and the watch on
rising water. The last three wait on latent assembly (the pump's parts and
culprit), which is to get its own document.

51 tests, 1921 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: a shout as a soft interruption

AGENCY.md §7's soft interruption, and ACTIONS.md Scenario 3's shout. At 60%
of dismantling's last stage the smith shouts the worker's name (a `#Call`).
Agency weighs it like a question, without the cost of being busy: trust 20,
less 5 for the worker's own goal, 15, more than the interruption (5). The
worker puts the dismantling down, answers (`#Here`), and goes back to it,
its progress kept, and the pump is opened.

- **Calls** (`#Call`, answered by `#Here`): worth more than the
  interruption, the agent suspends what it is doing (`putDown:why:`) and
  answers; otherwise it carries on.

51 tests, 1931 checks, under both compilers, ASan and UBSan, and leak-free.


### After the slice: the air (the unattended stove)

DOMAIN_SIMULATION.md Scenario 1, the atmosphere half. A room with a door
gap to the outdoors (275 K, fixed composition) and a stove holding 3 kg of
wood. The worker lights it and rests for eight hours, watching the room's
carbon dioxide. Flue open (A), the fire burns at 0.25 g a second and goes
out at 12,000 s, a predicted event that becomes a step boundary and a
proposal; the room is warmer; the rest runs its eight hours in 25 steps.
Damper closed (B), the stove draws from the room and vents into it, smoulders
as the oxygen falls, and the watch wakes the rest at the boundary it
crosses, within a second of the crossing and never before it. Stepped
minute by minute (C), it is exactly as conserved, the fuel all burned, and
the room within a kelvin of A.

- **BGAtmosphere** (`content/air.tri`: `#GasStore`, `#Combustor`,
  `#FuelContainer`, `#Stove`): whole millimoles of oxygen and carbon
  dioxide, whole joules of gas heat, milligrams of fuel, with carries for
  what is fractional, so that a ledger balances exactly after every step.
  It checks the fuel and gas out while anything moves, mirrors them into the
  records each step, and sleeps (an infinite horizon) when the room settles
  with no fire.
- **Horizons**: fuel exhaustion and a watch's crossing, predicted from the
  rates now (the rise only slows as the oxygen falls, so the prediction is
  never late), no sooner than the event tolerance.
- **Watches on a domain's quantity**: `watchDioxide` on a rest; the domain
  reports the crossing as an event for the activity.
- `light` and `while_away` (the rest) set up the fire and the watch.

Not yet, of the scenario: the thermal domain (the stove's iron, the walls,
the body) and the atmosphere ↔ thermal contributions, which the doc's open
question 1 needs; respiration; per-tile regions and the corridor; the
comfort band watch; order independence across domains (there is one); and
local wake on opening the door.

52 tests, 1954 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the solids (coupling domains)

The rest of DOMAIN_SIMULATION.md Scenario 1: a second domain, and coupling
between domains by snapshot and contribution (§7–8). The stove's iron
(45 kJ/K) takes three tenths of its fire's heat; the rest goes up the flue,
or, damper closed, into the room. The iron warms the air (20 W/K), and the
air the room's stone shell (100 W/K, 4 MJ/K), which loses heat to the
outdoors (50 W/K). In A the iron peaks at 343 K; eight hours on, the room
and its walls are near 278 K. The fire goes out exactly 12,000 s after it
is lit.

- **Coupling** (`BGCoupling`, `BGCoupledDomain`): every coupled domain
  publishes its values into a snapshot at step start. An active one
  advances reading the others from it, and puts what it gives them in an
  outbox. The scheduler hands each contribution (typed, additive, tagged
  with its source) to the domain that takes it, which holds it in transit
  for its next step. An arrival wakes it, and transit is saved with it.
- **BGThermal**: bodies' heat in whole joules (`ThermalBody`), the
  outdoors' exchange, and contributions applied. It sleeps until they
  arrive.
- **The atmosphere computes the gas-to-solid exchange** from the
  snapshot's solid temperatures. It takes the heat from the gas and sends it
  to the solid; below half a kelvin the exchange rests. The lag bounds its
  step to an eighth of the smaller capacity over the conductance.
- **Ledgers between domains**: each balances exactly, and what the
  atmosphere sent is what the thermal domain received plus what is in
  transit.
- **Acceptance checks run**:
  - 1, exact conservation, in each domain and between them;
  - 2, time jumps: about 300 steps for eight hours, and a step an hour
    once the iron cools to the air;
  - 3, A against C: both temperatures within a kelvin; determinism; and
    both domains' state saved;
  - 4, order independence: the domains added the other way round, bit for
    bit;
  - 5, the watch, within a second;
  - 6, in part: the thermal domain sleeps until the fire's heat arrives.
- **The prediction of fuel running out subtracts the milligram already
  burning**, so it is never late.

Open question 1, measured: gas heat owned by the atmosphere and the solids'
heat by another domain holds, at a price. The gas's small capacity (58 kJ/K)
against the shell's surface (100 W/K) caps steps at about 72 s while they
exchange, which is 300 steps against 25 without the solids. That is
acceptable at a room's scale. A room with more surface, or less air, would
want the exchange inside one domain, or an analytic step for it.

Not yet: respiration and the body's heat; the comfort band watch; per-tile
regions, the corridor, and opening the door (the rest of check 6); and
a domain's sleep once the room is near the outdoors but not at it (the
atmosphere steps hourly until then).

52 tests, 1963 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the lodger (breathing, body heat, the comfort band)

More of DOMAIN_SIMULATION.md Scenario 1's character. The one who lights the
stove and rests is a lodger: a `#Respirator`, taking oxygen from the air over
it (190 mmol a thousand seconds at rest, 600 at work), giving back four
fifths as much carbon dioxide and 448 J a mmol to its body, a `#ThermalBody`
at 310 K (245 kJ/K, 4 W/K to the air). In A its breath leaves the room near
2,300 mmol of carbon dioxide, well below stuffy. The room peaks near 288 K
three hours in. In D the lodger lies down two hours after lighting the
stove, resting easy only above 280 K. The fire goes out, the room cools,
and the rest wakes at the boundary where the air is 1 mK below the band.

- **Breathing** is in the atmosphere, at rest while the breather is the
  actor of a running rest. Its heat goes to the body as a contribution, as
  the fire's share goes to the stove's iron.
- **Temperature watches** (`watchCool`, `watchWarm`, from the respirator's
  `restsAbove` and `restsBelow`) are predicted at twice the rate the heat
  flows now give, so as never to be late, and predicted again from closer
  in. A watch already crossed wakes the domain at once.
- **The door gap passes 200 mmol a second** (about 17 m³ an hour), not 20.
  At 20, one sleeper's breath made the room stuffy in six hours. The
  scenario says the air stays fresh in A.

Found: a steady heat source (the lodger's 100 W) keeps the air more than
half a kelvin above the walls, so their exchange never rests, and the lag's
bound holds the steps near 72 s after the fire is out: about 400 steps for
the eight hours. "Once the room equalizes, the remaining time passes in one
step" holds only for an empty room. To jump through a steady state, the
coupling needs an analytic or implicit step (open question 2), or to live
inside one domain.

52 tests, 1968 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: local wake (regions, links, and a door)

DOMAIN_SIMULATION.md Scenario 1's check 6, and §5's per-region sleep. A
room of stale air (1,600 mmol of carbon dioxide) sits behind a tight door,
off a corridor ten times its size that opens to the outdoors; a back room
opens to the corridor through a gap. Everything else is fresh and at 275 K,
so both domains sleep, and an hour passes in a step. A worker opens the
door (`open_door`): the room and the corridor wake, and the room airs out
in 19 steps. The corridor settles with the outdoors over the next hours,
and everything sleeps again by 35 steps. The back room and the thermal
domain never step.

- **Links**: a region opens to another (`opensTo`) or to the outdoors,
  through its `gap`, or through its `door`'s `wide` while the door is ajar.
  Between regions, what one gains the other loses, so only the outdoors
  enters the ledger.
- **Per-region sleep**: a link rests while what it would carry is within
  the settle tolerances. A region is awake while a link to it moves, or a
  fire, a breather, a solid's surface, a contribution, or a crossed watch is
  in it. A door's change wakes the regions it joins. Each region counts the
  steps it was awake for.
- **A moving link bounds the step** to an eighth of the smaller side's air
  through it: an open door makes the room's steps 50 s, where the
  outdoors' gap allowed 3,600.

Not yet: per-tile regions inside a room, and resting a link inside the
settle tolerance changes the physics by at most that tolerance.

53 tests, 1980 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: curiosity widens a search

AGENCY.md Scenario 1's variant A. Spare nails are in a sack in the far
corner, which the worker saw on its way across. A search method now looks
into so many `places` before giving up (`search_for_nails`: two). The count
includes the places it has looked into or asked since the goal was adopted,
so the bin it reached into counts. The worker looks into the crate, has
looked enough, and drops *have nails* as impossible for now. A worker with
curiosity 50 (AGENCY.md §9; a place more for every 25) goes on to the sack,
finds the nails, and wedges the lock.

Not yet: search ordered by credence that the thing is there (the order is
still recency and distance), and curiosity weighing in elsewhere (which
methods to try, what to notice).

53 tests, 1990 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: seeking a spanner that fits

CONTENT_LANGUAGE.md Scenario 2's variant A, all of it. The nut is truly
22 mm, and the worker holds a 19 mm spanner. Up close the match is
incompatible, and the failed precondition yields *find a spanner that
fits*, AGENCY.md §5's *seek 22 mm wrench*. A 22 mm spanner lies on the
bench by the nut, so the worker picks it up and tightens the nut with it.
Knowing of none, or of only another 19 mm one, it finds the goal impossible
for now, and the nut stays loose.

- **A value parameter through the frame**: *find a spanner that fits*
  shares *tighten the nut*'s slots. Its `done` and its method tie the
  spanner's size to the nut's by the tag `$s`, so the size sought is the
  nut's as the agent believes it, with no parameter of its own.
- **A better way, unknown, is found out before a worse one is settled
  for**: a method whose precondition is unknown and which declares
  `onUnknown` goes first, ahead of a lower-ranked method that holds.

53 tests, 1999 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the repair's provider and save checks

Two of ACTIONS.md Scenario 3's acceptance checks that ran only in part:

- **3, provider allocation**: while dismantling, the worker says something
  to the smith, which runs alongside it (a voice is not the hands). A
  second dismantling is refused: "its hands are busy with activity …".
- **5, save and load during suspension**: the save is restored into a
  fresh world, committer, knowledge and agency. Nothing is due while the
  activity is suspended, so the next boundary is the run's stop. Both runs
  take it, and their state hashes and saves are the same.

Not yet: talking taking time as an activity on the voice, abort committing
partial effects, and the rest that waits on latent assembly.

53 tests, 2002 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: risk tolerance

AGENCY.md Scenario 2's "risk, weighted by risk tolerance" (§9's
disposition). An agent's `riskTolerance` (0 to 100, 50 by default) weighs
a goal's `#Cost`: in full at 50, double at 0, and not at all at 100. At the
default every decision stays as it was. A bold watchman (100), in variant
C's conditions, makes nothing of the risk: 35 against supper's 30, so it
gets up and looks. A timid one (0), in B's, makes double of it: 30, not
more than 30, so it stays at supper.

Not yet: risk as a believed quantity (it is a flat cost per goal), and
consideration curves.

53 tests, 2014 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the seal taken from under a reservation

ACTIONS.md Scenario 2's variant B, and a bug it found. B, who doesn't mind
A's reservation, and A start taking the seal up at the same boundary. Over
seeds, B wins a draw: the reservation doesn't block the commit. A's take
is rejected ("1 is no longer where it was taken from") and its activity
fails with that reason. A, who had told B the seal was its own, sees it in
B's hand. That is the hook for grievances, which wait on institutions.

- **Found: a completing stage didn't recheck what its operation needs.**
  When A's take began a boundary before B's, B's completed a boundary
  later and took the seal out of A's hand. A take's effect expects the
  item where it is when the effect is built, and by then the seal was in
  A's hand. A stage now rechecks the operation's pattern when it
  completes, as a resumed one does, and fails with the reason if the
  pattern no longer holds ("what it needs no longer holds, at
  roles.item.place").

53 tests, 2023 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the map's ages, checked

KNOWLEDGE.md Scenario 3's check 1, asserted. In a `lab play` session the
worker looks into the bin, then walks off. Its map still shows the nails in
the bin, "as you saw it 11s ago", from its store ("seen at 0ms"), and the
nails it took since aren't refreshed into it.

Needs design first: check 2's bump into a closed door. The lab has
`#Door` (the air's), but not yet:

- doors that make a tile impassable;
- whether a door's state can be seen from afar (if it can, the stale
  belief never reaches the menu);
- how a failed move leaves the actor where it can perceive what stopped it.

The last is ACTIONS.md §5's partial effects on failure, which are also
undesigned.

53 tests, 2025 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: feeling cold

AGENCY.md §6's warmth, the second need, with its stock in another domain.
A lodger stands by a cold stove, its body at 305 K. Interoception feels
the body's heat, which the thermal domain owns, as cold: ten points a
kelvin below 310 K, in bands of ten. At 50, above 30, the needs generator
raises *get warm*, worth what it feels, and the lodger lights the stove.
At 308.5 K it feels 10, and the stove stays cold.

- **The knowledge store keeps what it feels** of cold beside hunger, and
  saves it.
- **`get_warm`** is done once a stove the agent knows of is lit, and *light
  the stove* is its method.

Not yet:

- a horizon for cold crossing a band, as the body domain gives for hunger
  (cold is felt at whatever boundaries the domains give);
- numbness hiding cold (misperception);
- other ways to get warm (a coat, a warmer room).

54 tests, 2032 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: short of breath

AGENCY.md §6's third need, air. A breathing lodger beside a shut door, in
a room at 0.5% carbon dioxide, feels short of breath at 40: ten points for
every 0.1% above 0.1%, in bands of ten. That is above 30, so the needs
generator raises *air the room*, and the lodger opens the door to the
corridor. At 0.12% it feels nothing, and the door stays shut.

- **The air over the agent stands in for its blood gases.** §6 puts them
  in the atmosphere domain from respiration. The lab reads the region's
  carbon dioxide, which the atmosphere owns. Blood gases of the agent's
  own wait on a body that holds a breath.
- **`air_the_room`** is done once a door the agent knows of is ajar. The
  slot is `exit`, since `door` is GasStore's field.

55 tests, 2038 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: partial effects (a half-sawn log)

ACTIONS.md §5's world-visible progress, and the abort half of Scenario 3's
check 4. A worker saws a log through (`saw_through`, 8 s), and its cut shows
as it goes:

- **Checkpoints**: three, evenly spaced. Each is a step boundary, and
  commits the stage's `partial` effect in proportion: the log is 25% sawn
  at 2 s, 50% at 4 s, 75% at 6 s, and 100% when the stage completes.
- **On interruption**, the partial effect commits in the same group:
  - Suspended at 5 s, the log shows 62%, and its progress is kept. Resumed
    at 8 s, it reaches 75% at 9 s and 100% at 11 s.
  - Aborted (`abort:`, a new outcome), its progress is discarded, and the
    62% cut stays.
  - The saw taken from its hand: see below. The 62% stays.
- **Content**: a stage (or a one-stage operation) may declare `partial`
  (the field, the role it shows on, the whole it reaches) and
  `checkpoints`. The effect proper still commits on completion.
- **Found: a requirement failing after a commit didn't interrupt.** §5
  says a dropped tool rechecks the activities bound to it. The listener
  checked only for things gone or out of reach, so with the saw gone from
  its hand the sawing ran on to its due time and failed then. That would
  have committed its partial effect at 100%. A running activity now also
  rechecks its operation's pattern when an event touches what it binds,
  and is suspended (a hard interruption) when the pattern no longer holds.

Not yet: stages declaring fail rather than suspend on a hard interruption,
partial effects other than setting a field (a trench's length as a split,
an emptied stock), and the dismantling's stages showing progress.

56 tests, 2051 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: failing hard, as the stage declares

ACTIONS.md §5: "hard interruptions … force a suspension or failure, as the
stage declares." A step declares `hard`: "suspend" (the default) or
"fail". Taking something up (`take_up`) fails, since a thing snatched from
where it lay leaves nothing to come back to. The smith snatches the saw
from the bench half a second into the worker's take, and the take fails at
that boundary: "what it needs no longer holds, at roles.item.place". The
sawing, whose saw is taken from the hand, is suspended as before.

- **The match frame copies a step's own declarations**: `partial`,
  `checkpoints`, and `hard` join `duration` and the rest. Without that, an
  operation declaring them matched as unknown on its own fields.

57 tests, 2055 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: what the valve sounds like

ACTIONS.md Scenario 1's observable outcome: "whether the handle moves,
sounds, the wrench visibly bending". A valve breaking free leaves a
`creak` on it, and a lever giving leaves a `clang` on it. Both are traces
heard for two seconds. The worker perceives them as it does the cat's
clatter:

- freed at a steady 75 Nm, it hears the creak and sees the valve turned;
- bent, it hears the clang and sees the wrench bent;
- holding, it hears nothing.

None of it carries the breakaway torque.

- **`BGMakeTrace`**: a trace made in any group, by an effect or a reaction,
  not only the traces an operation declares.

Not yet: the actor's exertion as a percept, and impact as a graded effect.

57 tests, 2063 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: feeling cold when it happens

The horizon "feeling cold" left open. A lodger rests in a cold room at
307.1 K. At rest it breathes too little to keep warm, and cools. Before
this, the first step ran half an hour, and the thermal domain received
it in one lump: the body was 0.3 K past 307 K before it was felt. Now the
crossing is felt at a boundary 2 mK past it.

- **The atmosphere predicts an agent's body crossing its next whole
  kelvin.** It computes what the body gains or loses: the exchange with
  the air, and its breath's heat. It predicts the crossing at twice that
  rate, and again from closer in, as it does a temperature watch. The
  thermal domain applies that heat a step later, so the domain that knows
  the flow is the one that bounds it. A first try put the prediction in
  the thermal domain, from its last step's rate. It saw nothing until the
  first lump had landed.

57 tests, 2065 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: autopilot on Bela's beliefs, checked

AGENCY.md Scenario 2's check 5, asserted in variant E. When control
returns to the player, what autopilot weighed is in Bela's store, and it
isn't true:

- the storeroom as Bela knows it (R2);
- the disturbance its rule drew from the clatter it heard;
- an intruder inside that two rumours made up, a referent with no truth
  behind it.

57 tests, 2068 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: two more scenario checks asserted

- **COMPONENTS.md Scenario 1, step 4**: after the marked nail, the smith
  looks into the bin. Among the 29 clean nails it finds the bent one, an
  individual of its own, `bent: true`, with the tool marks on it. That is
  the evidence step 4 promises.
- **KNOWLEDGE.md Scenario 3, check 6**: an out-of-character note ("the
  nails are in the loft") doesn't change what the character says. The
  same session with and without the note ends in the same world, to the
  bit, and the claim made says nothing of the loft.

58 tests, 2075 checks, under both compilers, ASan and UBSan, and leak-free.

### Found: told referents and recognition (settled below)

Found trying AGENCY.md Scenario 2's variant C the long way. In B's
conditions, Bela asks the carter and the porter where the rumour came
from. Both heard it from the neighbour, out of Bela's earshot. The
answers would merge the groups and deflate it.

They answer "don't know". The carter's store keeps the told "someone in
the storeroom" as a vague `#Agent` referent. When the porter came back
into sight, recognition bound that referent to the porter, nearest and of
the same kind, its vague features unifying. So the carter's claim now
places the porter on a tile, and nothing matches the question.

Recognition needs a rule for told, featureless referents before this can
run:

- should seeing anyone of the kind ever resolve "someone"?
- should "someone" be a referent at all, or only a claim's content?
- should an identity hypothesis wait for evidence that ties them (the
  place, a description)?

The test drops the variant; C stays as it was, with the source named from
the start.

### What stays open, and why

The remaining scenario checks that aren't run, after the passes above:

- **Checks that hold by structure, with no test that could fail**:
  CONTENT_LANGUAGE.md Scenario 3's check 5 (recognition reads no truth
  links) and KNOWLEDGE.md Scenario 1's check 1 (no entity IDs in agent
  data). Descriptions use the store's own `ref(n)`; the truth link is a
  field the inspector alone prints. A text check can't tell entity IDs
  from store IDs, both small integers.
- **Needing design**, with where the docs leave it:
  - latent assembly's own rules: materialization, consistency with
    history, culprit attribution. COMPONENTS.md: "The latent assembly
    document will specify materialization …" The lab's are provisional
    (below), and so are the scenarios built on them.
  - institutions' own semantics: whether an institution permits or forbids,
    sanctions, grievances, reservations treated as claims, and offices'
    other capabilities. ARCHITECTURE.md: "Institutions (§6) … To be
    specified". (What COMPONENTS.md Scenario 2 and ACTIONS.md §3 fix runs;
    see below.)
  - how considerations combine (AGENCY.md's open question 1: product,
    weighted sum, or a mix). The lab's answer, until the question is
    settled: they are in "the units of credence (dB)" (agency.tri), and
    adding dB multiplies odds. So the sum is a product of odds factors,
    and a `#Flat` is a fixed factor. A mix (a veto, a ceiling) has no
    content form yet.
  - memory making feature hypotheses of its own: the docs give
    "half-remembers" (CONTENT_LANGUAGE.md Scenario 2, C), not how memory
    forms a doubt. (Testimony forms them: below.)
  - loyalty: no doc beyond AGENCY.md (searched every .md); "those it is
    loyal to" makes it a relation, with no word on its parties or on the
    *report* and *confront* goals it decides between.

### After the slice: the wrench was replaced

KNOWLEDGE.md Scenario 2's check 4, "wrench replaced". The worker sees the
workshop's worn wrench on the bench (tool marks 40) and goes off. The
wrench is swapped for a new one. Back, recognition takes the new one for
the old: same kind, same place. Its tool marks are gone, and they never
wear off, so the worker notices it as an anomaly and concludes it was
replaced (`replaced`, +15 dB). One who never saw the old wrench sees a new
one, and concludes nothing. The prior belief gates it.

- **`#Unworn` premises**: a field that wears on and never off. When a
  sighting refreshes a referent with less of it than before, perception
  keeps an `unworn` observation. It is salient as an anomaly, and saved.
  The rule's premise holds on it.
- **Recognizing the swap isn't needed**: the referent stays one thing in
  the agent's mind. What it learns is that the thing changed in a way
  things don't, which the rule reads as a swap.

59 tests, 2083 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: two hypotheses of the nut (credence mass)

CONTENT_LANGUAGE.md Scenario 2's variant C, with §9's matching per
hypothesis. The worker saw the nut plainly at 19 mm. Four tiles off, it
half remembers it was replaced with a 22 mm one. The test supposes that,
at 300 in 1000. Matching *tighten it* per hypothesis, 700 in 1000 entails.
The method's threshold is 900, so the precondition is unknown at
`nut.size`, and the worker looks closer first. Seen plainly, the doubt is
gone, and it tightens the nut. At 50 in 1000 the 950 that entail are sure
enough, and it tightens the nut without looking.

- **A referent may hold a competing hypothesis**: overrides of its
  features (`suppose:about:mass:`), with a credence mass in thousandths.
  The belief keeps the rest. A plain sighting settles it, a blurred one
  keeps it. It is saved, and the dump shows it.
- **Agency matches per hypothesis.** Entailed when the mass that entails
  reaches the method's `threshold` (1000 by default, so every method
  without one behaves as before). Incompatible when every hypothesis is.
  Otherwise unknown, at the doubted slot's overridden feature, which
  `onUnknown` makes a goal.

Not yet: perception and memory making hypotheses of their own (the test
supposes them).

59 tests, 2093 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the menu says how sure

The knowledge view's menu (ACTIONS.md §3, CONTENT_LANGUAGE.md §9) matches
per hypothesis too. Beside the nut, half remembering it 22 mm, the worker's
menu offers *tighten* as "unknown (700 in 1000 entails) (find out
destination.size)". It excludes an entry only when every hypothesis rules
it out. Without the doubt it is entailed, as before.

59 tests, 2095 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: more than one hypothesis

A referent holds up to three competing hypotheses (`BG_HYPOTHESES`), each
with its overrides and mass, and the belief keeps the rest. Agency and the
menu match each, and add up the mass that entails. The worker half
remembers the nut as 22 mm (60 in 1000) or 24 mm (50). 890 in 1000 entail,
under 900, so it looks closer first. With 24 mm at 30, 910 entail, and it
tightens the nut straight away. All of them are shown in the dump, saved,
and settled together by a plain sighting.

59 tests, 2104 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: consideration and urgency curves

AGENCY.md §3: "each a fixed-point curve applied to a value from the
knowledge view. The curves are lookup tables." In content, a consideration
over a value (a need's pressure, a trait) may give a `curve`: its points,
the `output` at an `input`, straight between them and level beyond the
ends. Without one, `per` scales the value as before. A committed goal may
give an `urgency` curve over how much of its window has passed, in
thousandths (§7). Without one, urgency rises straight to 20.

- *Get warm* rises the colder the lodger feels: cold 50 is worth 30 (the
  straight line gave 25).
- *Tighten the nut*, committed to, is barely urgent until its window's
  last tenth. At 90% the curve gives +2, where the line gives +18.

The open question that stays is how considerations combine. They still
add, in dB.

59 tests, 2107 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: exertion, fatigue, and rest

AGENCY.md §6's fourth need. Fatigue is a component field (`Agent.fatigue`,
0 to 100), as §6 has it. An operation's stage may declare `exertion`, the
fatigue its completion adds to the actor: sawing a log through takes 30.
Interoception feels the fatigue as tiredness, to the band. Above 50, the
needs generator raises *get some rest*, and the worker lies down
(`while_away`). Rested through, eight hours on, the fatigue is gone. A
worker at 40 saws a log, feels tired at 70, and rests. ACTIONS.md
Scenario 1's "their exertion" is that felt tiredness.

Not yet: a rest cut short by its watch restoring part of it, exertion from
force (the valve's torque) rather than per stage, and fatigue slowing work.

60 tests, 2116 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: exhaustion blurs hunger

AGENCY.md §6's misperception, "exhaustion blurs hunger": modifiers change
how precisely interoception feels, not the body. Worn out (fatigue 80 or
more), an agent feels its hunger only to the nearest twenty, not ten. Fed
to 70, it feels hunger 30, but 20 when exhausted. Its body is as hungry
either way.

The other modifiers §6 names follow below.

60 tests, 2119 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the knowledge arena, compacted

CONTENT_LANGUAGE.md §12's memory table, and Scenario 3's check 6. Each
knowledge store has an arena of parsed descriptions, `parsed:`, keyed by
their text: the same text, the same node. Recognition's conflict check
reads its descriptions from it. Housekeeping, after each store's
perception, compacts it as §12 says: the descriptions used since the last
compaction are copied (`tri_copy`) into a fresh arena and the old one is
freed, when live data is under half the arena. Forced at every boundary
(`setCompactAlways:`), the porter's arena compacts many times over the
coat at dusk, and the save and the dump are the same to the byte as
without.

Not yet: the rest of the store's parsing through the arena (it parses into
scratch arenas still), and §12's memory bound counted in bytes.

60 tests, 2122 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: light, and the bump in the dark

KNOWLEDGE.md §5: "Conditions limit perception: light … These come from a
conditions provider. Light and sound may become domains later; for now
they are stubs with authored values." The ambient light is authored: day,
dusk, or night. A shining `#Lamp` makes it day within its reach. At dusk,
what is beyond arm's reach is seen a step less precisely, as before. At
night, what is beyond it isn't seen, and isn't taken for absent either.
What is within reach is felt a step less precisely, unless the agent just
handled it.

KNOWLEDGE.md Scenario 3's check 2 runs:

1. By day, the worker sees the loft door open, and goes off.
2. Night falls, and the door is shut.
3. Back beside it in the dark, the worker can't make it out, and its
   memory keeps "open". The menu offers *go through*, from the stale
   belief.
4. Going through is a bump: the attempt is what happens. The worker felt
   it, so it now believes the door shut, and it stays where it was.

With a lamp, it sees the door shut beside it, and the menu doesn't offer
going through.

- **`go_through`** (`pass`): onto the door's tile.
- **Day is the default**, and `setDusk:` is the ambient's dusk.

Not yet: light as a domain (lamps burning down), sound conditions, and the
lamp in CONTENT_LANGUAGE.md Scenario 2's inspection.

61 tests, 2129 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: weak matches don't bind

KNOWLEDGE.md §6: "a strong match binds the percept to that referent; a
weak match may create a new referent, or tentatively link to one."
Elsewhere than it is believed to be, a referent known by nothing concrete
(a told "someone", all open fields) matches anyone, so it is a weak match,
and recognition no longer binds a percept to it. That settles the
carter's rumoured someone: it stays the rumour's subject, not the porter.

AGENCY.md Scenario 2's variant C now runs the long way. The neighbour
tells the carter and the porter, out of Bela's earshot. They tell Bela,
naming no one. Bela asks each where it came from, and both answer: the
neighbour. The two groups merge, credence falls to 15, and Bela stays at
supper, as in C with the source named from the start.

61 tests, 2139 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: pain, adrenaline, numbness

AGENCY.md §6's injury, "a component field", with interoception's percept of
it, and the modifiers of precision §6 names: "adrenaline dulls pain,
numbness hides cold". `Agent.injury` is felt as pain, to the band.
`Agent.adrenaline` dulls it point for point, and `Agent.numbness` hides as
much cold. Neither touches the body. A worker hurt at 45 feels pain 40, and
with adrenaline 30, pain 10, its injury still 45. A numb lodger (30) at
305 K feels cold 20, not 50, and leaves the stove cold.

§6 names no source for injury, adrenaline, or numbness, so they are
fields, authored like the light: harm, fright, and frostbite would set
them. Pain raises no goal, since §6 names none for it.

62 tests, 2145 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: believing by habit

AGENCY.md Scenario 1's "Oskar has a strong habit of hanging the wrench on
the hook. Oskar believes it is on the hook", and the habits slice's "habits
feeding back into belief". When memory of where a thing is fades too far,
the agent falls back on its own habit for it: where it remembers putting
that thing at least three times. It believes the thing there and doesn't
forget it. The worker puts the wrench in the bin three times, then once in
the crate, and goes off. A month on, it believes the wrench in the bin,
wrongly, as Oskar believes it on the hook. Having put it in the bin only
once, it simply doesn't know.

Not yet: habits by kind of thing (this one wrench, not any wrench), and
the belief by habit weighing less than one seen.

63 tests, 2157 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: content, copies, and the forged permit

COMPONENTS.md §8 and its Scenario 2, all six checks. It needed no
institutions: the office is an informational entity, and its authorization
is a reified relation.

- **Content** (`#Content`, component `Information`) holds text, and what
  it says of its origin (`issuer`), which may be false. It has no
  location. Its actual origin is its creation event.
- **Copies** (`#Copy`, component `Inscription`) are physical. Each
  references its content (`inscribed`) and carries what is seen of it:
  what it `reads`, the issuer it `claims`, the hand it is `penned` in, the
  seal's `impression`.
- **`copy_out`**: a copy set down in the copier's hand (`#Scribe`), pressed
  with the seal it holds. Copied as it is, it references the same content.
  In other words, it is new content, `derivedFrom` the original, still
  claiming the issuer, and its creation is the copier's.
- **Authority**: `#Authorization` grants a grantee something over an
  entity, linked (`authorizes`) to the content that states it.
  `BGAuthorizationsOver` returns those, and content no authorization links
  to confers nothing.
- **New relations**: `derivedFrom`, `authorizes`, `lists`. A ref field set
  to something the same group creates now resolves to its ID.

The forger borrows C1 and makes C2, the name changed and pressed with a
carved fake stamp. The guard sees what C2 says and how it looks: its hand,
the crude anchor. It doesn't see the origin. P′ derives from P, its
creation is the forger's, it still claims the office, and it confers no
authority. The stamp's use is in history. A clerk's exact duplicate C3
references P itself. C1 burns, leaving a tombstone, and P lives on, listed
by the ledger's register and copied in C3. The save restores it all.

Not yet: the guard deciding whether to believe it (§4 and institutions),
and how long content lives once nothing references it (COMPONENTS.md: an
open question).

64 tests, 2181 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: latent assembly, provisionally

COMPONENTS.md §7 and DOMAIN_SIMULATION.md Scenario 2's reveal, under
provisional rules (content/latent.tri) until the latent assembly document
gives its own. §7 fixes these:

- an assembly (`Latent`) keeps what is revealed and its history;
- revealed parts are entities `partOf` it, their mass carved out of its
  own, so the total is unchanged;
- a part's properties come from the parent's seed and role, never its ID;
- parts join no domains while inside.

Provisional, and for the document to replace:

- the descriptor lists roles, each a part blueprint at a depth, and the
  culprit candidates per failure;
- the culprit is drawn from the unit's seed and the failure alone, and is
  marked only if it is among the revealed parts;
- the culprit's wear is 60, plus a point every ten hours since the
  failure.

The crank pump, a "flow loss" committed at hour 300, opened two levels with
a wrench (`open_up`):

- **Six parts**, `partOf` it. 40 kg in all, 29.8 kg left in the pump.
- **Check 2**: opened at hour 300 or 400, the same parts and culprit (the
  piston seal); only its wear differs, 60 or 70. Reloading a save made
  before opening gives the same.
- **Variants**: over the units' seeds the culprit is the seal, or the
  outlet valve, or the housing. The housing is no part at these levels, so
  the cause is unresolved and none is invented. A failure with no
  candidates marks nothing.
- **Check 6**: the menu before opening is the same for every unit.
- **The committer** lets a part revealed `partOf` a latent assembly
  declare no new mass: its mass is carved, and the ledger checks the
  assembly lost as much.

Checks 1 and 3's heat, and the repair's inspection, follow.

65 tests, 2269 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the open cylinder drains the header tank

DOMAIN_SIMULATION.md Scenario 2's check 1 and its outlet-valve variant,
under the same provisional rules. The pump's descriptor names the part
whose extraction opens a path (`pathWhenOut`: the piston) and the part it
runs through (`pathThrough`: the outlet valve). The pump knows the store
it holds back (`riser`: the header tank). A reaction (`BGLatentKind`, on
parts moving) sees the piston out and opens the path: a leak, a tap
installed in the tank, at a rate in proportion to the valve's wear past
half. The fluid domain sees a new tap, which is a topology change: it
checks in, forms again, and drains the tank onto the floor.

- **Outlet valve the culprit (wear 60)**: 2 L a minute, and the 100 L tank
  is empty within the hour. Tank, floor, and checked-out water sum to
  100 L at every boundary.
- **Seal the culprit**: the valve (wear 2) holds, and nothing drains.

65 tests, 2281 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the piston takes its heat with it

DOMAIN_SIMULATION.md Scenario 2's check 3, the thermal half. A revealed
part records the assembly it came from. The first time it is out of it,
the reaction moves its share of the assembly's heat, and its heat
capacity, to it. The warm pump (305 K, 18 kJ/K) gives its extracted piston
(1.8 kJ/K) 549 kJ. The total is the same, and both are at 305 K. Inside,
the piston has none of its own, and its heat is the pump's.

Not yet: the split reaching a running thermal domain's ledger as a
transfer (the test runs without one).

66 tests, 2289 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: inspection binds the faulty part

ACTIONS.md Scenario 3's steps 3 and 4, "replace the faulty part (unbound
until inspection reveals one)", and its check 2, on the provisional latent
pump. *Mend the pump* has two ways:

- **Replace the worn part**: a part seen installed with wear of 60 or
  more, and a held spare that fits the same role (`fits`, a tag). Nothing
  can be bound to it until one is seen. It scores +10.
- **Open it further** with the wrench in hand.

The worker opens the pump a level at a time. It sees the seal worn,
replaces it with its spare (`replace_part`: the worn one out onto the
floor, the spare in its place), and the failure is mended. On a pump whose
culprit is the housing, no part is worn: opened through, it finds nothing
to replace, and none is invented.

- **Found: habits break ties, and ranks are not scores.** With both ways
  scoring 0, the habit "open it further" had formed won the tie after two
  openings (AGENCY.md: "habitual ways win ties"). The replacement now
  scores 10, as the better way once a worn part is seen.

66 tests, 2305 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the pump from the component side

COMPONENTS.md Scenario 3, all six checks, on the provisional latent
assembly. The miller owns the hand pump. A flow loss has left it at 20%.

1. Opening it reveals level 1, carved from the pump: 40 kg in all
   throughout. The piston is itself an assembly, with the seal inside.
   As the culprit, it takes the failure on rather than wearing.
2. Taken out, the piston joins the thermal domain; inside, it doesn't
   (`participates:`).
3. Opened, it shows its seal worn. The same seal shows whether it is
   opened in place or after it comes out.
4. The player cuts a strip from its own hide (`cut_strip`). The hide
   persists, 900 g, and the strip is 100 g, `splitFrom` it, its mass carved
   exactly. The player shapes it into a seal (`shape_seal`) and replaces
   the worn one. The pump's flow changes by the delta, from 20 to 100.
   Opening the pump, inspection alone, changed nothing.
5. The piston goes back (`install_part`), out of the domain again.

Claims (`BGClaimsCovering`): the miller's claim covers the pump's parts
through `partOf`, as the ownership kind declares (`coverage` content). It
covers the old seal by its provenance. The new seal is covered by the
miller's claim through the pump and by the player's through the hide it
was cut from, so its ownership is an open question (`BGOwnershipOpen`),
recorded, not settled.

- **The committer** lets an entity related `splitFrom` a source in the
  same group declare no new mass: it is carved from the source, which the
  group lowers as much.
- **Provisional additions**: a culprit that is an assembly takes the
  failure on, and a part's loss is 80 points of flow at wear 60.

67 tests, 2346 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the watch on rising water

ACTIONS.md Scenario 3's step 6 and check 7. An operation may declare a
`floodWatch`, an amount of water on the actor's tile. Its activity records
the watch where the actor stands (`watchFloor`, `watchX/Y/Level`). The
fluid domain reports it like a store's watch, at the boundary the tile
reaches it. Water reaches a neighbouring tile by spreading, in steps of at
most 10 s, which is the event tolerance.

Rising water is an interruption: the activity is suspended, "water is
rising at its feet", and its watch removed. The piston out of a pump with
a leaky outlet valve, the worker sets to clean out its cylinder
(`clean_out`, ten minutes, watching for 500 mL). The water at its feet
crosses 500 mL at 314 s, and the work is suspended at that boundary. With
the seal at fault nothing comes, and the work runs its ten minutes.

- **Found: a completed activity kept its watches.** They are removed now
  when it completes, as when it ends otherwise.

67 tests, 2359 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: improvising another instrument

ACTIONS.md Scenario 3's step 5: "Rechecking requirements finds no
instrument for the gland nut, so the activity is blocked. The player
improvises another chain." `improvise:with:` gives a suspended activity
another instrument for its item role. The operation's pattern is
rechecked with it, and the activity binds it from then on. Dismantling
turns the gland nut with any `#Turner`, a wrench or a spanner (a common
supertype). The wrench taken mid-dismantling, resuming is refused. The
wrench in the smith's hand won't do. A spanner taken up will, and the
dismantling goes on to the end.

68 tests, 2368 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the pump repair saved mid-interruption

DOMAIN_SIMULATION.md Scenario 2's check 5. The work is suspended by the
rising water, with the piston out and the puddle as it is. Saved then and
restored with its fluid domain, the world's state hash is the same. A
minute on, both runs' saves are the same to the byte. With checks 1, 2,
3, 4 (the piston in no domain while inside), and 6 already run, all of
Scenario 2's checks now run, on the provisional latent assembly.

68 tests, 2372 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the guard's doubt, and authorize(action)

Two parts of the forged permit that need no institution semantics:

- **Whether a guard believes it** (COMPONENTS.md Scenario 2: "Whether the
  guard believes it is §4's business"; "They may know what the office's
  seal should look like"). A stamp shows whose seal it is (`sealOf`). A
  rule (`forged_seal`, premise `#Misprinted`) concludes `#Forged` of a
  copy claiming an issuer whose seal the agent has seen, pressed with
  something else. The warehouse guard, who has never seen the office's
  seal, can't tell. A veteran who has seen it at the office finds C2
  forged, and C1, genuine, not.
- **`authorize(action)`** (ACTIONS.md §3), past its empty stub: the
  authorizations granting the actor something over what the action binds.
  Alun's going into the warehouse has the office's authorization, the
  forger's has none. It never blocks an attempt. Whether an institution
  permits or forbids stays §6's.

68 tests, 2377 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: told otherwise, two hypotheses

KNOWLEDGE.md §11: "Conflicting beliefs coexist as competing hypotheses,
each with its own credence." A new claim, `#IsLike` ("something like
`what` is like `as`"), says what a thing is like. The hearer binds the
thing by its looks. Where the claim's concrete features conflict with
what it believes, they become a competing hypothesis. Its mass is the
hearer's credence in the speaker, from dB to a probability. The worker has
seen the nut at 19 mm. The smith, whom it trusts at +20 dB, says it is
22 mm. The worker holds both: 19 mm, and "or, 990 in 1000: size: 22mm".
Only 10 in 1000 entail tightening it, so the worker looks closer first.
Seen plainly, the nut is 19 mm, and it tightens it.

68 tests, 2383 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: an office holder issues a permit

ACTIONS.md §2: "Office holders provide institutional capabilities, such as
issuing a permit … matched in the same way. Holding the capability to
issue is different from permission to act." An `#OfficeHolder` names the
organization it holds an office in. `issue_permit` is an operation like
any other, its actor an office holder. The harbour office's clerk, its
seal in hand, issues Alun a permit for the warehouse across the town, the
place given in the command's words. The issue makes:

- the permit's content, claiming the office as its issuer, with no
  location;
- the office's authorization over the warehouse, to Alun, linked to the
  content;
- a sealed copy, in the clerk's hand, in Alun's.

`authorize` then finds Alun's going into the warehouse authorized. A
worker who holds no office can't issue one. The clerk, who can, has no
authorization of its own to go in.

69 tests, 2393 checks, under both compilers, ASan and UBSan, and leak-free.

### After the slice: the chain searched in reach

ACTIONS.md §2: "Reach includes the actor's body, what it holds and wears,
carried containers (with an access cost), adjacent tiles". The seized
valve's chain search looked only in hand (the "Not yet" of the instrument
chains above).

- **Searched in reach**: `rotate` searches the levers the actor's view can
  reach, to the same depth 3, furthest reach first; at the same reach, the
  cheaper to bring to bear (held 0, on a tile 1, in a container 2), then
  ID order. Nothing in another's hand, or part of something, is a
  candidate.
- **Taken up in the stage's group**: a part not held moves into a free hand,
  expecting where it was, so if someone takes it first the stage fails. A
  chain needing more hands than are free isn't one. The torque's detail
  says "takes up one in reach" for each.

Checked: wrench and pipe beside it, taken up into both hands (75 Nm, it
turns); a pipe in a sack on its tile; not a bystander's pipe, nor one out
of reach; a held wrench before a spare beside it; the same on every replay.

Not yet: the access cost as time (it is a preference only), and agency
choosing instruments.

69 tests, 2411 checks, under both compilers, ASan, and leak-free.

### After the slice: a tag on the seal

ACTIONS.md §7: "A physical marker, such as a tag on a shelf, is a separate
entity that agents can perceive." The two-hands slice's "Not yet":
reservations perceived other than by being told.

- **`#Label`** (talk.tri): a record whose writing anyone within `legible`
  tiles of it reads at a glance. `seal_tag` is paper, legible from a step
  away.
- **Read on sighting**: perception reads a label when it sights it (a new
  referent, or one not seen for a minute, the same notion as a sighting for
  identity hypotheses) and is close enough. Each entry is believed from its
  author, through the label, as a read record's entries are; a
  `#ReservedFor` entry makes the `#Reserved` finding, as telling does.

Checked: B, respectful, sights A's tag beside the seal from a step away,
believes it reserved, and never starts (-30, as when told); a tag legible
only from on it says nothing a step away, and B takes the seal
("unreserved +0").

Not yet: grievances, and reservations as claims (institutions, open).

69 tests, 2420 checks, under both compilers, ASan, and leak-free.

### After the slice: bringing them to bear takes time

The reach slice's "Not yet": ACTIONS.md §2's access cost as time, not
only a preference.

- **`BGAccessDelay`**: the time to bring an action's instruments to bear,
  added to its first stage when it starts: take_up's duration for each
  part on a tile in reach, twice that from a container. The chain search
  is one function (`turning_chain`), so the delay and the effect find the
  same chain.

Checked: wrench and pipe beside it add 2 s, and the valve hasn't turned a
millisecond before the stage and the delay are done; a held wrench and a
pipe from a sack, 2 s too; both in hand, none.

Other operations don't search: they bind their instruments as roles
(`tighten`'s spanner, `drive`'s nail, held), and agency's methods get them
in hand first. ACTIONS.md §2: "When the player or an agent binds an
instrument explicitly, there is no search." Turning a valve is the one
that chooses its chain.

69 tests, 2421 checks, under both compilers, ASan, and leak-free.

### After the slice: resuming owes the delay as things lie then

- **Resuming a first stage** owes the stage's duration plus bringing its
  instruments to bear as they lie now (`BGAccessDelay` again), less the
  progress before suspending, never below nothing. Nothing is taken up
  until the stage completes, so what lay beside it may have moved.

Checked: suspended 1.5 s into turning with wrench and pipe beside it
(2 s + 2 s), the pipe put into a sack meanwhile, resumed at 5 s: due at
8.5 s (2 s + 1 s + 2 s − 1.5 s); not turned a moment before, turned after,
both in hand.

70 tests, 2429 checks, under both compilers, ASan, and leak-free.

### After the slice: a loan is a debt

The granting slice's "Not yet": lending as a debt the borrower owes back.
AGENCY.md's glossary: "Commitment: A goal the agent is bound to: a shift,
a promise, a debt. It has a deadline or a time window."

- **Owed on being granted**: the asker, hearing `#Granted` from the one it
  asked, binds what it now holds like the thing granted and undertakes
  `repay` (agency.tri) to the lender, source "debt", a commitment saved
  like any other. Its window is the loan's last day (`BG_LOAN_TERM`, a
  week; `BG_LOAN_DUE`, a day), so a borrower with nothing else to do
  doesn't hand it straight back.
- **`hand_it_back`**: give what was lent to the lender.
- **Found: an agent waiting on news never took up a commitment.** Settled
  into waiting after an "impossible for now", an agent stayed waiting when
  a commitment's window opened and its goal won the weighing, so it never
  acted on it. Adopting a newly weighed goal clears the wait.

Checked: the honest Kasimir, lent the carter's wages, owes them back
within the week (logged and saved); still holds them on the sixth day;
hands them back on the seventh.

Not yet: the lender expecting it back (a grievance if not, institutions),
interest, and loan terms from content or from what is said.

70 tests, 2436 checks, under both compilers, ASan, and leak-free.

### After the slice: a loan promised back

AGENCY.md §7: "Promises are commitments created by a communicate act...
Hearers hold it as a claim. Keeping or breaking a promise ... updates their
trust." The promises slice's "Not yet": promises of things other than where
something will be. The loan slice's: the lender expecting it back.

- **A promise of a thing in someone's hand** (`promiseThat:isHeldBy:by:`):
  `#IsHeld` with `#Pledged`. The borrower, owing the loan, says it to the
  lender, due on the loan's last day.
- **Kept** when the hearer sees the thing in the holder's hand (as any
  held claim settles); **broken** when it is due and the holder, in sight
  now, hasn't it. Trust moves as for any claim.
- **Found: a promise bound a new referent for a thing the hearer knew.**
  Recognizing what a claim names looked, by looks, only among things the
  hearer didn't know the place of. A promise is about a time to come, so
  where the thing is now says nothing against it: a pledged claim
  recognizes among all of them. The carter's wages, lent to Kasimir, are
  the wages promised back.

Checked: the carter holds Kasimir's promise; kept on the seventh day,
trust +5; with the wages lost on the third day, broken when due, with
Kasimir in sight, trust -15.

Not yet: hearing of a promise's outcome from others, and the weight of
one's word as a disposition.

70 tests, 2443 checks, under both compilers, ASan, and leak-free.

### After the slice: providers taken before they commit

ACTIONS.md §5: "Each capability provider belongs to at most one activity
at a time ... This allocation is internal to the actor. It is separate
from reservations and from commit validation." The "Not yet" of the
walking slice: allocation counted only committed activities, so two
submitted for the same boundary both started.

- **Pending activities count**: starting a timed activity checks the
  committer's waiting groups too: one by the same actor starting an
  activity whose operation uses the same providers refuses it ("its hands
  are taken by take_up, starting"). Not commit validation: the actor's own
  allocation, at the start.

Checked: taking up the seal and then the stone for the same boundary, the
second is refused; walking at the same time is not (legs); committed, the
stone is refused as busy; with the seal in hand, it can be taken up.

71 tests, 2451 checks, under both compilers, ASan, and leak-free.

### After the slice: remembered by repetition and salience

KNOWLEDGE.md §12: "Strength decays at a rate set by salience and
repetition." The bounded-stores slice's "Not yet": every belief faded at
one rate.

- **Sightings**: a referent counts how often it was sighted (seen after a
  minute unseen, the same notion labels and identity hypotheses use).
- **Salience**: a referent keeps the most salient observation it took part
  in (actor, subject, or other): its own deed 20, being addressed 30, an
  anomaly 25.
- **The rate**: `BG_FADE` a step, times 2 / (1 + sightings, at most 7),
  times `BG_NOTICE` / its salience (at least `BG_NOTICE`). Seen once,
  nothing salient: as before. Both are saved (`remembers`).

Checked: ten days on, a stone seen once has faded 20; sighted three times,
10; moved into a bin by the worker's own hand, 10. The habit-belief
scenario now waits six weeks, not a month: the wrench, the worker's own
doing, is remembered twice as long.

Not yet: detail (the feature hierarchy) by salience and repetition too.

72 tests, 2456 checks, under both compilers, ASan, and leak-free.

### After the slice: forgetting, scheduled

KNOWLEDGE.md §12: "When a belief's strength would fall below the
forgetting threshold, it is forgotten at a scheduled time, which is a
`nextEvent`."

- **`forgettingOf:`**: when a referent's strength will fall below
  `BG_BELIEVE` at the rate it fades now, solved from `strengthOf:`'s
  formula, not searched.
- **`nextForgetting`**, an optional part of the perception phase: the
  earliest such time after now across the stores. The scheduler bounds
  its next boundary by it, as by a decision's.

Checked: a stone seen once is forgotten on the sixteenth day; with nothing
else happening, a boundary comes then (two boundaries to an hour past it,
one to just before), and after it nothing is due.

73 tests, 2463 checks, under both compilers, ASan, and leak-free.

### After the slice: foot traffic wears floor traces

KNOWLEDGE.md §3: a trace holds "the conditions that speed up decay (rain,
foot traffic, heat)". The traces slice's "Not yet": conditions that speed
decay. Of the three, the lab has foot traffic (walking); no weather, and
heat on traces waits for a trace kind it would matter to.

- **`trodden`** (a trace kind's, 0 by default): the percent of the life a
  floor trace has left that each step onto its tile takes. Still analytic:
  the step shortens the trace's `expires` in its own group, so the trace
  fades faster from then on and nothing is computed between. The damp
  floor is trodden 25.

Checked: a step onto a mopped tile takes a quarter of the damp's six
hours; scuffs there, and the damp on the next tile, keep theirs; stepping
off changes nothing; on again, another quarter of what is left.

Not yet: rain and heat.

74 tests, 2474 checks, under both compilers, ASan, and leak-free.

### After the slice: a trace on a stack marks one unit

KNOWLEDGE.md §3: "Traces on stacks trigger automatic individuation
(COMPONENTS.md §9). Traces are physical distinctions, so marked units
never merge." The traces slice's "Not yet": traces on stacks
individuating the units they're on.

- **Individuated by commitment**: a group that puts a trace on a stack of
  more than one unit (its `Trace.bearer`) gets a unit split off first, and
  the trace goes on it; every trace the group puts on that stack goes on
  the same unit. Proposers don't have to remember, as for any unit.
- **No merging a traced unit**: a unit bearing a trace that hasn't run out
  won't merge ("units differ physically: one bears a trace"); once its
  traces have run out, it may.

Checked: a scratch and a creak on ten nails split one off, `splitFrom`
the stack, which bears both; it won't merge back. A nail with a creak
alone merges back once the creak has run out.

75 tests, 2482 checks, under both compilers, ASan, and leak-free.

### After the slice: an attention budget

KNOWLEDGE.md §5: "Each perceiver has an attention budget per boundary.
Salience decides what gets attention first." AGENCY.md: agency "splits the
attention budget according to how demanding the current activity is." The
salience slice's "Not yet": attention budgets per boundary rather than a
threshold.

- **The budget**: `BG_ATTENTION` (100) less the running activity's
  demand, `BG_PERCEPT_COST` (10) an event attended to: ten at rest.
- **Salience first**: the events noticed (over the threshold, which
  stays: a busy agent's rises too) wait as candidates; the most salient
  get attention, in event order among equals. Only those are kept,
  believed (what was said), and make news; the rest are news only as "no
  attention left".

Checked: curious Mira, with twelve workers taking up a stone each at one
boundary and the last speaking to her, attends to ten: the remark first,
then the first nine takes as committed; the other three go unnoticed.

Not yet: attention for state and trace perception (only events spend it).

76 tests, 2509 checks, under both compilers, ASan, and leak-free.

### After the slice: thinking it over takes attention too

KNOWLEDGE.md §9: "Immediate: cheap rules that run on observation, within
the attention budget." Deliberate interpretation (investigating) "spends
time" instead.

- **Immediate conclusions spend what the events left**: each finding an
  immediate rule draws costs a percept's worth; with none left, the rule
  waits for a boundary that has some ("no attention left to think R… over").
  Investigating isn't limited.

Checked: Mira, her attention spent on the twelve takes and the remark,
draws no disturbance from a clatter among them at that boundary; at the
next, quiet one, while it can still be heard, she does. With ten times the
budget, the same scene's checks fail: the budget is what holds.

76 tests, 2511 checks, under both compilers, ASan, and leak-free.

### After the slice: noticing a trace takes attention

The budget slice's "Not yet": attention for trace perception.

- **New traces wait for attention**: a trace the agent already knows is
  seen as it is now, freely; one new to it is a candidate, and the
  strongest get what the events left, one percept each ("no attention
  left for the clatter"). A close look (investigating) attends to all.
  Trace perception now runs after the events' share is settled, before
  interpretation, which gets what is left after both.

Checked: with twelve takes and a remark, Mira doesn't hear the clatter
among them; with eight, she hears it but has nothing left to think it over
with. At the next, quiet boundary she does both.

State perception stays free: what is in the field of view is seen, as
KNOWLEDGE.md §5 has it ("The classic roguelike field of view and
remembered map are exactly this system"); attention limits what happens
and what is new on the floor, not what is in view.

76 tests, 2534 checks, under both compilers, ASan, and leak-free.

### After the slice: autopilot, "continue my routine"

AGENCY.md §14's autopilot modes: "keep working until something happens,
continue my routine, auto-explore, carry out this recipe. The player
chooses the goal set and the interruption threshold." The autopilot
slice's "Not yet": modes beyond "this goal".

- **`autopilotRoutine:threshold:`**: the goal set is the character's
  commitments. Agency takes them up as their windows open, worth what they
  are, past the threshold too: that is what the player asked for.
  Anything else worth more than the threshold returns control, as before.
- **Waiting for it**: with nothing to do and a commitment still to keep,
  the character waits (the window's opening wakes it); with none left,
  control returns ("its routine is done"). Saved (`routine`).

Checked: Oskar, handed over at the start with a threshold of 10 and a
shift to tighten the nut between 60 s and 120 s, waits with control kept;
at 60 s takes it up (worth 20); tightens it; and control returns, his
routine done.

Not yet: auto-explore (what exploring is isn't specified), and carrying
out a recipe (recipes expand through knowledge, ACTIONS.md §6, not built).

77 tests, 2541 checks, under both compilers, ASan, and leak-free.

### What stays open, and why (as of the attention and routine slices)

Each item below waits on something the documents leave to be decided; the
text they give is quoted.

- **Institutions' own rules** (permit or forbid, sanctions, reservations as
  claims, offices' other capabilities): ARCHITECTURE.md, "Institutions (§6)
  ... To be specified". What ACTIONS.md §3 and COMPONENTS.md Scenario 2 fix
  runs.
- **Grievances**: ACTIONS.md Scenario 2, B: "This is a hook for grievances
  in §4 and §6", the only mention of them in any document.
- **Protecting a possession**: AGENCY.md §4, "a threat to something
  believed owned"; nothing says how an agent comes to believe it owns
  something (ownership claims are institutions').
- **Lying as agency's choice**: AGENCY.md §11, "weighted by the honesty
  disposition and the believed gain"; the gain is defined nowhere.
- **Asking for work**: named once, AGENCY.md Scenario 3 ("*ask for
  work*"); no word on who employs, what the work is, or how it pays.
- **Merging referents when an identity hypothesis is believed**:
  KNOWLEDGE.md open question 4, "How often should merge and split errors
  happen".
- **Graded shortfall (effort rates from capabilities)**: ACTIONS.md open
  question 4, "How should graded shortfall functions be represented in
  content, and with what units?"
- **Recipe knowledge** (how an agent comes to know a recipe, and recipes
  over §4 beliefs): ACTIONS.md open question 7, "How is recipe knowledge
  represented". Recipes themselves run: a `sequence` method, expanded
  through what the agent knows.
- **Latent assembly's own rules, how considerations combine, memory making
  hypotheses of its own, loyalty**: as listed above.

### After the slice: talking takes time

ACTIONS.md §5: "An actor may run several activities if their providers
don't overlap: walking while talking works"; AGENCY.md §11:
"Conversations are alternating communicate activities". Until now `say`
was instant. The "Not yet"s: talking taking time, talking while working
as a voice provider.

- **`say` is a second on the voice** (a new provider): an activity whose
  words (`Activity.words`, saved) are said when it ends. Walking or
  working meanwhile is fine; a second remark at once isn't ("its voice is
  taken by say, starting").
- **Talking occupies the voice, not the mind**: agency's `busy:` leaves
  out activities that use the voice alone, so an agent decides, and starts
  work, while it speaks.
- **`lab play`** waits for what the player's character says to be said,
  as for a step, and for a question, a little longer for the answer.
- **Tests**: a scripted remark (`stage_say`) waits three seconds, to say
  it and hear a second's answer; the attention scene's remark starts a
  second before the takes so they land together, and it has an activity
  system now (speech needs one); the repair's shout starts a second early
  and is heard at 60% of the last stage, as before.

Checked: a remark isn't said half a second in, and is at the second, with
its words; the speaker walked meanwhile; a second remark at once is
refused; once said, it can speak again. Every conversation scenario
(promises, the rumour, decay, asking, the purse, play) runs as before.

Every remark is a second: what is said is content (talk.tri), not words,
and no document says how its length becomes time.

78 tests, 2550 checks, under both compilers, ASan, and leak-free.

### After the slice: autopilot, "auto-explore"

AGENCY.md §14 names it; roguelikes fix what it means: go toward the
nearest place not yet seen until there is none.

- **`autopilotExplore:threshold:`**: with nothing else to do, agency walks
  the player's character a step toward the nearest tile on its level its
  map memory has never seen (lowest row, then column, among equals). The
  map's extent is the frame's (32 by 32), as a roguelike's map size is
  known to the player; what has been seen is the character's own memory.
  Something worth more than the threshold returns control, as for the
  other modes; nothing left unseen does too. Saved (`explore`).

Checked: a worker alone in the middle of the map explores it, a step a
second, until every tile is seen, and control returns ("there is nothing
left to explore"); saved midway, the mode is restored.

Not yet: exploring around what blocks the way (the lab has no walls; a
refused step is only logged).

79 tests, 2557 checks, under both compilers, ASan, and leak-free.

### After the slice: autopilot, "carry out this recipe"

AGENCY.md §14's last mode. A recipe is a `sequence` method (agency.tri,
ACTIONS.md §6), its bindings found through what the character knows.

- **`autopilot:recipe:threshold:`**: commits the character to the recipe's
  goal, as "this goal" does, and carries that goal out by the recipe
  alone; subgoals it needs, by any method. Anything but a `sequence`
  method is refused. Saved (`recipe`).

Checked: at the mill, the worker reads the diagram and is handed over to
follow the recipe: it shuts the trough line the diagram names, opens the
pump, and control returns; saved midway, the recipe is kept; handing it
over to `borrow_money` is refused.

80 tests, 2565 checks, under both compilers, ASan, and leak-free.

### After the slice: looking first where it is most believed

AGENCY.md §5: "A method may include bounded local choice, such as
ordering the places to look by the belief that the item is there." The
curiosity slice's "Not yet": search ordered by credence that the thing is
there.

- **`likely`**, an order: the place where the agent holds the most
  credible claim of something like what the method `seeks` (a new field of
  a method), believed or not; the prior with none. `search_for_nails`
  orders `likely`, then recent, then near.

Checked: a stranger, beside the far sack, glimpses nails in it and tells
the worker, barely sure (sure 5): not believed, so the worker doesn't go
to fetch them there; but when the bin it believed held its nails is empty,
its search goes to the sack first, before the nearer crate, and it wedges
the lock. Without `likely`, the same scene searches the crate, gives up,
and the lock stays unwedged.

80 tests, 2574 checks, under both compilers, ASan, and leak-free.

### After the slice: a trace kind's floor

KNOWLEDGE.md §3: "A trace whose perceivability would fall below its kind's
floor is removed at that time, which the trace system reports to the
scheduler as a `nextEvent`." Every trace ran to its expiry.

- **`floor`** (a trace kind's, 0 by default): below it, the trace is gone.
  `BGTraceGone` solves for the first such moment from the even fade; the
  traces domain's next event is the earliest, and it removes what is gone
  there. The soap smell's floor is 20: a smell is there or it isn't.

Checked: a soap smell made at 60 to last a day is gone at 16 h, at a
boundary of its own (one boundary to just before, two to an hour after);
scuffs beside it, with no floor, stay.

81 tests, 2580 checks, under both compilers, ASan, and leak-free.

### The "Not yet" lists, audited

Each slice's "Not yet" was written when it was; many were done later. As
of the slice above, every one of them is in one of three places.

**Done by a later slice** (its heading above): event perception,
observations, rules, claims, credence and trust, memory decay and its
rates, scheduled forgetting, salience and bounded stores, attention
budgets (events, new traces, interpretation), the notebook, goals and
methods in content, method scores, `onUnknown`, needs (hunger, cold, air,
rest, pain), routines, commitments and urgency curves, habits and belief
by habit, promises (made by saying, kept or broken, of a thing held),
granting and lending, risk tolerance, walking as an activity, provider
allocation (committed and pending), interruption, suspension, resuming,
partial effects, failing hard, talking taking time, answering as a
choice, saying and asking in `lab play`, traces (on stacks, worn by foot
traffic, kind floors), appearance and analysis, competing hypotheses
(identity, features, testimony), the knowledge arena, light and the lamp,
credence thresholds, the seized valve's chain (in reach, with access
time), its sounds, exertion and fatigue, the interrupted repair (recipe
through a diagram, the shout, the watch on rising water, inspection,
improvising, saves), all four autopilot modes, reservations by a tag, and
search ordered by belief.

**Waiting on a decision** (the document text in "What stays open, and
why" above, and):
- *Retracting a finding when a trace premise is* (KNOWLEDGE.md §9): a
  trace fading isn't a premise found false (fresh paint dries; it was
  still touched up), and `covered_up` rests on a trace gone. Which is a
  retraction isn't said. Repetition's premise runs, provisionally (below).
- *Rates from capabilities and shortfall* (walking speed from the walker,
  impact as a graded effect): ACTIONS.md §5 "rate = f(capabilities,
  shortfall, actor modifiers)", f being open question 4. The modifiers'
  part runs, provisionally (below).
- *Weights from other derived values*: ACTIONS.md open question 8.
- *Light and sound as domains*: KNOWLEDGE.md open question 2.
- *How long content lives once unreferenced*: COMPONENTS.md, open.
- *Threats as salience*: AGENCY.md §10 lists "harm to the agent or to
  those it is loyal to"; there is no harm, and loyalty is open.
- *Trust beyond confirmation and refutation, the weight of one's word,
  the value of what is parted with, interest and loan terms, starvation's
  consequences, detail fading by salience*: no document says.
- *Routes as habits, exploring around obstacles*: the lab has no walls.

**Buildable, not yet done**: none, as of the slices below; each built since has its heading.

### After the slice: a commitment every day

AGENCY.md §8: "A routine is the set of default goals active in a time
window. It is built from commitments (a shift from 8 to 16 ...)". Each
commitment was one window.

- **`undertake:...every:`**: a commitment recurring each period, its
  window no longer than the period. When the window closes, kept or not,
  the next opens a period later, unsettled. Agency wakes at a recurring
  window's close even when it was kept, so the next is due on time. Saved
  (`recurs`).

Checked: Oskar tightens the nut in its window on day one; loosened
overnight, he tightens it again on day two at 60 s past midnight, exactly
a day on; saved between, it recurs; a window longer than its period is
refused.

82 tests, 2587 checks, under both compilers, ASan, and leak-free.

### After the slice: reading takes time

The notebook slice's "Not yet": reading taking time. As talking does: a
second (`read`'s duration), and what the record holds is taken in when it
ends. It uses no provider: reading while walking is fine. `lab play`
waits for it, as for a step. The scenarios that read (the repair's
diagram, the notebook) had the time already.

Checked: half a second into reading a diagram nothing is read; at the
second, it is.

83 tests, 2590 checks, under both compilers, ASan, and leak-free.

### After the slice: traces left per stage

ACTIONS.md §2: "Costs are committed per stage as proposals: wear and
traces on tools". An activity left its traces when it completed.

- **`leaves` and `removes` belong to a step** now (`#Step`, of which an
  operation is one): a stage of a staged operation leaves its own traces
  in the group that commits its effect; the operation's, when it
  completes, as before. Prying a nail out scratches it as it loosens.

Checked: prying a nail from the lock, no scratch two seconds in; at three
and a half, the loosening done and the pulling under way, the nail bears
a scratch; at six, the activity has completed, the nail in hand.

84 tests, 2594 checks, under both compilers, ASan, and leak-free.

### After the slice: the piston's heat with the domain running

The heat slice's "Not yet": the split reaching a running thermal domain's
ledger. It needed no change: the domain loads its bodies from their
records before it works, so the reaction's move between steps reaches it,
and the total is the same. Now checked, with `yard_pump` (the warm pump,
out in the yard: 50 W/K to the outdoors).

Checked: ten minutes of cooling, the domain stepping; the piston taken
out joins the domain at the pump's temperature (warmer only by the
second's cooling the pump had since, 15 mK); the ledger balances then and
an hour on, the pump cooler than the piston, which has no outdoors of its
own.

85 tests, 2604 checks, under both compilers, ASan, and leak-free.

### After the slice: learning a promise's outcome from others

AGENCY.md §7: keeping or breaking a promise is a history event, "which
hearers perceive when they learn the outcome." The promises slice's "Not
yet": learning it other than by looking.

- **Learned on someone's word**: a hearer that comes to believe, told,
  where a promised thing is as of after the deadline (newly, or told
  again what it believed) settles the promise: kept if it is where it was
  promised, broken if elsewhere; trust moves as when it looks.

Checked: the worker doesn't look after the deadline; a carter who looked
into the crate tells it the nails are there, and the worker finds the
smith's promise kept on the carter's word, trusting the smith more; it
looked only the once, early.

85 tests, 2613 checks, under both compilers, ASan, and leak-free.

### After the slice: tired work goes slower, provisionally

ACTIONS.md §5: "rate = f(capabilities, shortfall, actor modifiers)"; "A
change to any rate input, such as an injured hand ..., recomputes it."
Open question 4 leaves f open; as with latent assembly, the lab runs a
provisional one, to be replaced when it is settled.

- **`BGWorkRate`** (provisional): the actor modifiers only, and only for a
  stage that takes effort (`exertion`): 200 / (200 + fatigue + injury)
  percent of the declared pace, so half again as long at 100 together.
  Resting, waiting, talking go at their pace.
- **Progress is effort**: a stage keeps the pace it started at
  (`Activity.pace`); elapsed time counts as effort at that pace, for
  checkpoints and partial effects, suspension, and what resuming owes. A
  new stage, or resuming, takes the actor as it is then: that is the
  recompute, at stage boundaries (not yet mid-stage).

Checked: sawing a log takes a fresh worker 8 s; a worn-out one (fatigue
100) shows its quarters at about 3, 6 and 9 s and is through at about
12 s; suspended at 6 s, it has done 3960 ms of sawing and the log shows
49. The tired worker's rest, which takes no effort, is as long as before.

Not yet: capabilities and shortfall (open question 4).

86 tests, 2628 checks, under both compilers, ASan, and leak-free.

### After the slice: a change of pace mid-stage

ACTIONS.md §5: "A change to any rate input, such as an injured hand ...,
recomputes it." With a rate to recompute, the activity system, told of a
committed change to a running actor's fatigue or injury, re-paces the
stage: what it has done kept, it goes on from then at the pace now, and
its due time moves (a group of its own, caused by the change).

Checked: a fresh worker sawing cuts its hand two seconds in; from then it
saws at the hurt pace: a quarter through at 4.9 s, half at 5.1 s (not 4),
three quarters at 11 s, through at 11.2 s (not 8).

86 tests, 2636 checks, under both compilers, ASan, and leak-free.

### After the slice: a habit belief retracted as the habit moves

KNOWLEDGE.md §9: "An interpretation's provenance records the rule and its
premises, so interpretations can be retracted when a premise is." Of the
lab's premises, repetition (`#Repeated`: seen to put things in the same
place so often) is the one that can stop holding without merely fading:
the usual place moves on. Provisionally, the other premises stay as they
were (see "What stays open").

- **Weighed again**: a rule over repetition re-checks a finding it drew,
  each perception; if its premise no longer gives the same place, the
  finding is retracted ("no longer #Habit") and, if it holds of another,
  drawn again (`retractFinding:about:`).

Checked: the worker, after four days of the crate, uses the bin from day
45: on the fifth day of the bin (more than the crate), the apprentice's
belief is the bin; on the fourth (as many), still the crate.

86 tests, 2658 checks, under both compilers, ASan, and leak-free.

### Decided since: the open items, now buildable

Each item "What stays open, and why" listed has been decided, in its
design document:

- institutions (organizations acting through members, rules as content,
  grievances, sanctions as operations, knowing the rules):
  INSTITUTIONS.md 1–8;
- lying's gain, loyalty, harm and threats, how considerations combine
  (a dB sum with vetoes), employment and posted deals, worth, going
  without, loan terms: AGENCY.md decisions 11–18;
- retraction only when a premise is contradicted, doubts from decay,
  confusion, distraction, impairment and poor sight, merging referents
  past a threshold, light and sound as domains, trust, detail fading as
  strength: KNOWLEDGE.md decisions 11–16;
- graded shortfall as curves, recipe knowledge, commit weights per
  operation, talking by what is said: ACTIONS.md decisions 11–14;
- content lifetime, installed parts' claims: COMPONENTS.md decisions
  10–11;
- latent assembly: LATENT_ASSEMBLY.md (the lab's rules adopted; culprits
  by history and wear by use still to design);
- Triangle packages: CONTENT_LANGUAGE.md decision 12.

### After the slice: laws, and what breaks them

INSTITUTIONS.md decisions 2 and 3: an organization's rules are content it
issues; whether an act breaks one is true; nothing blocks it.

- **`#Law`** (content/institutions.tri): content (`#Content`) with what it
  `forbids` (an operation's effect), what makes that a wrong (`"anothers"`:
  the thing claimed by someone else, owned or in custody, with no
  authorization over it; `"unauthorized"`: no authorization at all), what
  breaking it `brings` (arrest, a fine, confiscation), the organization it
  is the law of, and whether it is common knowledge. The town and its law
  against theft are the first.
- **`BGLawsBroken(action)`**: the laws an action breaks, true, for the
  inspector and for whoever acts on it. A reservation is no claim to a
  thing (institutions could make one so later).
- **COMPONENTS.md decision 11 applied**: an installed part keeps its own
  claim, and an assembly's claim covers only parts with none. Scenario 3's
  check 5 now reads so: the new seal is the player's; whether fitting it
  was a gift is for people to settle.

Checked: Kasimir taking the merchant's purse breaks the town's law, and
takes it all the same; the merchant taking its own, or Kasimir given an
authorization over it, or taking a seal only reserved for the merchant,
breaks none.

87 tests, 2666 checks, under both compilers, ASan, and leak-free.

### After the slice: knowing the law, and weighing it

INSTITUTIONS.md decisions 5 and 8: people keep the rules because they
believe breaking them brings consequences, weighed against whether they
believe themselves seen; everyone knows its society's common rules from
the start.

- **Known laws**: a knowledge store knows its society's common laws from
  the start (`learnCommonLaws`), by what they say (`BGKnownLaw`: forbids,
  wrong, brings, weighs), never by entity.
- **Believed another's**: `#OwnedBy`, a claim like `#ReservedFor`, makes an
  `#Owned` finding about the thing, its choice the owner.
- **`#Unlawful`**, a consideration: if the agent knows a law against the
  act on the slot's referent as it believes it to be (another's), what the
  law `weighs`, when it believes itself seen; unseen, nothing. The purse's
  flat `#Watched` penalty becomes it: the same numbers, grounded in a law.

Checked: the merchant tells Kasimir the purse is its own and turns away;
Kasimir knows the town's law against theft from the start. Unseen, he
takes it ("unlawful, unwatched +0"); seeing Mira, he doesn't ("unlawful,
watched -40"); honest, he doesn't. Untold whose it is, seeing Mira watch,
he knows the law but not that it applies ("lawful +0"), and takes it.

87 tests, 2679 checks, under both compilers, ASan, and leak-free.

### After the slice: a grievance, told to the watch

INSTITUTIONS.md decision 6: wrongs reach an institution through people; a
grievance is a claim told to an office holder, ordinary knowledge, weighed
by who says it.

- **Taken, seen**: an agent who sees someone take into their hand a thing
  it believes is another's (`#Owned`, not theirs) draws `#Taken` about it,
  its choice the taker.
- **`report_wrong`**: a goal arising from `#Taken`; its method,
  `tell_the_watch`, goes to the nearest agent it sees wearing the watch's
  badge (`OfficeHolder.badge`, perceivable) and says a `#Grievance`: what,
  whose, taken by whom, built from what it believes (`grievanceAbout:`).
- **Heard**: a grievance makes the hearer's `#Owned` (if new) and `#Taken`
  findings, at its trust in the speaker. A thing it never saw gets a
  referent, as said (and likewise for any naming claim).

Checked: Mira overhears the merchant tell Kasimir the purse is its own,
sees him take it, and tells the officer of the watch beside her; the
officer, who saw none of it, now holds that the purse is the merchant's
and that Kasimir took it, on her word.

Not yet: the officer acting on it (sanctions, next), and grievances by
the wronged themselves when they find their things gone.

87 tests, 2686 checks, under both compilers, ASan, and leak-free.

### After the slice: the watch acts

INSTITUTIONS.md decisions 4 and 7: an organization acts only when a member
acts in office; sanctions are ordinary operations its office gives its
holders, each an activity the holder chooses.

- **`arrest` and `confiscate`** (institutions.tri), operations for an
  office holder: arrest takes someone into the watch's custody (a
  `custody` claim, and an "arrested" event they perceive); confiscate
  takes a thing from someone's hand into the officer's, in custody too.
  Custody isn't ownership: the purse is still the merchant's.
- **`enforce`**, a goal arising from `#Taken` only for one whose office's
  badge is the watch (`#Arising`'s new `duty`): worth its office's duty,
  weighed like any goal. Its method arrests the taker and takes the thing
  back, in that order: who took it is who holds it, until it is taken.
- The purse is truly the merchant's in the scene now (an ownership claim),
  as well as told so.

Checked: the officer, told by Mira, walks to Kasimir, arrests him and
takes the purse back; the purse is in the officer's hand, both in the
watch's custody, and still the merchant's.

Not yet: what the arrested does (comply, resist, flee: next); the officer
not also "reporting the theft" to itself (a goal arising for everyone but
the watch has no form yet: harmless, it finds no one to tell); and
returning confiscated things to their owners.

87 tests, 2692 checks, under both compilers, ASan, and leak-free.

### After the slice: arrested, complying or fleeing

INSTITUTIONS.md decision 7: the target of a sanction complies, resists, or
flees, as its own agency decides.

- **`#Arrested`**: an agent perceives its own arrest (the "arrested" event
  naming it), and by whom.
- **`flee_arrest`**: a goal arising from it, worth 40 for getting away,
  less the agent's disposition to abide (`Agent.abiding`, new, 50 by
  default: decision 5's "disposition to abide"), so by default it
  complies. Its method runs off from the warden (`flee`: four tiles
  straight away, four seconds, on the legs).
- `lab play`'s menu has `flee` for anyone in reach of someone; the scripted
  talk session's menu numbers moved by one.

Checked: arrested by the officer, Kasimir, disposed to abide, stays where
he is; not disposed to (abiding 0), he runs off, four tiles from the
officer.

Not yet: resisting (it needs harm: AGENCY.md decision 13, not built), the
officer pursuing one who flees, and what custody leads to (a court, a
fine, release: INSTITUTIONS.md's procedures, as decided only so far).

87 tests, 2700 checks, under both compilers, ASan, and leak-free.

### After the slice: a law learned

INSTITUTIONS.md decision 8: particular rules are learned like anything
else, "by reading a posted notice, being told".

- **`#LawSays`**: a claim stating a law (the law as a nested `#Law`
  description). Heard, or read (a record's entry, or a label at a
  glance), it teaches the law (`learnLaw`); `statementOfLaw:` states one
  the agent knows, to tell or write.
- **Saved**: the laws a store knows (`law` lines); common ones are known
  again anyway.
- **The firewood ordinance** (`wood_law`): not common, "unauthorized", a
  fine.

Checked: the worker beside a notice reads the ordinance and knows two
laws; the smith, out of range, knows the common one only; told it by the
worker, two; saved and restored, both still know them.

Not yet: `#Unlawful` weighing "unauthorized" laws (an agent's belief about
its own permits); seeing someone sanctioned as a way to learn a law; fines
and revoking a permit as operations.

88 tests, 2705 checks, under both compilers, ASan, and leak-free.

### After the slice: harm, threats, and resisting arrest

AGENCY.md decision 13: harm is injury and loss; a threat is a belief that
harm is happening, salient, which can interrupt.

- **`hit`**: a blow to someone in reach, a second on the hands: 15 of
  injury (the existing `Agent.injury`, felt as pain), and a `struck` event.
- **`#Struck`**: the one hit knows it, and from whom: a finding about the
  attacker (rule "felt"), so a goal can arise from it. Witnesses don't yet
  draw it (perception reads witnessed moves and speech only).
- **Weighing a threat**: struck, `hit_back` (worth `Agent.temper`, new,
  0 by default, less 10) and `get_clear` (worth the injury, less the
  temper) arise, against what the agent is doing.
- **Resisting arrest** (INSTITUTIONS.md decision 7): `resist_arrest`
  arises with getting away, worth less (20 against 40) but raised by the
  temper; its method hits the warden.
- **`#Arising.exempt`**: a goal that never arises for an office's holders;
  reporting a theft is exempt for the watch, whose duty is its own goal.
- **A method fails when what it names is believed gone** from where it
  was, rather than trying the step again. Fleeing fails, not suspends,
  when the one fled from is out of reach.

Checked: with a temper (100) and no disposition to abide, arrested,
Kasimir hits the officer (resist +60 over get away +40), then runs. The
officer is hurt (15), knows by whom, weighs getting clear (+7) after its
duty is done, backs away, and finds Kasimir gone. It doesn't report the
theft to itself.

Not yet: witnesses of a blow; harm to one's loyalties (needs decision
12); a law against assault (a third kind of wrong); a threat that is
about to happen, not happening (a raised fist).

88 tests, 2717 checks, under both compilers, ASan, and leak-free.

### After the slice: loyalty, and trust from it

AGENCY.md decision 12: loyalty is a weighted relation, formed by kinship,
employment, or authored; it raises the worth of goals that serve them, and
makes harm to them salient. KNOWLEDGE.md decision 15: trust comes from
relationships, disposition and conduct.

- **`#Bond`** (bonds.tri): a reified relation, like a claim, with no body
  and no location: its holder (`bondOf`), `toward` whom, its `tie` (kin,
  employ, sworn) and `loyalty` (0 to 100). `kin_bond` (60), `work_bond` (30).
- **Known on recognition**: the holder's referent for the other carries
  its loyalty, set whenever perception binds it to the other (its own
  disposition; a mistaken identity takes the loyalty with it). Saved with
  the referent.
- **Trust** (`trustIn:`) is now conduct (the referent's `trust`, as
  before), plus a tenth of a point a point of loyalty, plus the agent's
  `trusting` disposition (new, dB, 0 by default); within the trust limit.
- **`#Loyal`**: a consideration, the agent's loyalty to the slot's
  referent, or to whom it believes owns it. Reporting a theft weighs it.
- **Salient**: an event moving one it is loyal to, or what it believes
  theirs, is noticed as a concern is.

Checked: Mira, the merchant's daughter, knows her bond to him, trusts him
by 6 more and her disposition's 3, and reporting the theft of his purse is
worth +33 to her (+15, loyal +18), against +15 to her as a stranger.
Kasimir owes him nothing. The loyalty is in the save.

Not yet: loyalty to an organization (it is never seen, so never
recognized: it needs a referent of its own); employment forming a bond
(decision 15, next); a bond known before the other is first seen.

88 tests, 2726 checks, under both compilers, ASan, and leak-free.

### After the slice: what a thing is worth, and what lending it costs

AGENCY.md decision 16: worth is believed and to the agent, authored by
kind, raised for what serves its needs now; giving costs the worth, and
lending less, by the trust that it comes back.

- **`#Valuing`** (`values` family): a `value` for things believed like
  `valued`, raised by a `pressure` the agent feels, `per` tenths a point.
  Money (cloth) is 30; food 10, plus half the hunger felt. Unvalued, 10
  (`BG_WORTH`).
- **Lending** costs the thing's worth times (30 − trust) / 60: all of it
  at the least trust, none at the most. It replaces the flat
  `BG_PARTING` (15) in weighing a request.

Checked: the carter, asked for its wages (30) by Kasimir, whom it trusts
at 20, finds lending costs 5 and grants at +15 (it was +5). Disposed to
trust no one (−20), it trusts him at 0, lending costs 15, and it refuses
at −15. The worker's supper is worth 10 plus half the hunger it feels.

Not yet: gifts as opposed to loans (every request is a loan now); the
raise for tools in use; worth in trade (no trade yet).

88 tests, 2737 checks, under both compilers, ASan, and leak-free.

### After the slice: a loan's terms

AGENCY.md decision 18: a loan's terms are part of the deal, said when
lending; with none said, a default by relationship (between friends, a
week, no interest).

- **`#Granted.owedIn`**: the term the lender says. To one it is loyal to
  (a friend), it says none; to anyone else, a day (`BG_LOAN_SHORT`).
- **The borrower** owes it back within the term said, or, none said, the
  default by its own bond to the lender: a week to a friend, a day
  otherwise. It repays in the term's last seventh (a day of a week).
- **Friendship** is a tie (`friend_bond`, 20). In the purse scenario the
  carter and Kasimir are friends, as the scenario has it; that raises the
  carter's trust in him by 2, so lending costs 4, not 5.

Checked: friends, the carter grants with no terms, and Kasimir owes the
wages back in a week; strangers, the carter says a day (`owedIn:
86400000ms`), and Kasimir owes them six days sooner.

Not yet: interest (things lent are single bodies; it needs divisible
money); a borrower proposing terms; terms written down.

88 tests, 2744 checks, under both compilers, ASan, and leak-free.

### After the slice: employment, a deal

AGENCY.md decision 15: an employer weighs a request for work like any
request; granting it, it gives the worker a commitment and promises pay on
completion, a promise it can keep or break; loyalty forms with it.

- **`#AskWork`** (work.tri): a question, "have you work, for something
  like `what`?". `ask_for_work`, a way to get money after borrowing.
- **`#Job`**: a `task` (a goal, its first two slots bound to what is like
  `what` and `within`), a `shift`, the `pay`, and what having it done is
  worth to the employer (`gain`). An employer offers the one its
  `Agent.hires` names (`crate_job`: a stone into the crate in the hour).
- **Weighed like a request**: trust in the asker, helpfulness, less busy
  and committed, plus the gain, less the pay's worth to it (decision 16).
  Granting, it `hire`s the asker (an operation: a `work_bond`, the
  worker's loyalty, 30), says the job, and undertakes `pay_wage` as a
  promise, in the shift's last seventh.
- **The worker** undertakes the task for the shift (an employment) with
  its slots bound to what it recognizes, and holds the pay as the
  employer's promise. A job whose things it can't make out it doesn't
  take on.
- **Paying** (`pay_up`): if the employer believes the job done, it hands
  over the wage; its honesty weighs in, and a dishonest one can't bring
  itself to.
- **Fixes and generalizations** on the way: borrowing asks the friend it
  is most loyal to first (`"loyal"`, a slot order), and a stranger is
  barely worth asking (a `#Loyal` curve); a search passes over only those
  asked the same kind of thing, so one asked for a loan can still be asked
  for work; a promise of something into the hearer's hand binds to what
  the promiser holds; an answer can't be what was said at the asking;
  `lab play`'s scripted session finds its menu number by name.

Checked: neither stranger lends; the foreman hires Kasimir (+10: trust 0,
gain 40, pay 30); he carries the stone to the crate; his loyalty to the
foreman is 30; at the shift's end the foreman pays, and Kasimir finds the
promise kept. A dishonest foreman doesn't pay (−20, unthinkable), and
Kasimir finds the promise broken and trusts it less.

Not yet: posted deals (a flyer or an ad naming a job and where to
answer: next); recurring shifts; a job's task checked generically by the
employer (`pay_up` knows deliveries only); being paid ending the need
that sent one looking.

88 tests, 2766 checks, under both compilers, ASan, and leak-free.

### After the slice: a deal posted

AGENCY.md decision 15: "deals can also be posted in the world: a flyer or
a classified ad is a record offering one, and an agent who reads it can
take it up, going to the employer".

- **`#Hiring`** (work.tri): a claim, someone like `holder` hires, for pay
  like `what`; find them at `site`. Read (or heard), the reader believes
  the employer there, unless it has seen them, and draws a `#Hires`
  finding about them, as credible as the author.
- **`flyer`**: a label legible from two tiles, its writing a `#Hiring` by
  the employer.
- **`"hiring"`**: a slot order, those believed hiring first; asking for
  work uses it.

Checked: with the foreman out of sight and its flyer by Kasimir, he reads
it at a glance, walks to where it says, and is hired, does the job, and is
paid. Without the flyer, he asks the nearest, the carter, who has no work
(`#HaveNone`), and gives up.

Not yet: answering an ad as it says (a written reply, a place to call);
ads that expire; a posted job read by someone not looking for work.

88 tests, 2782 checks, under both compilers, ASan, and leak-free.

### After the slice: vetoes

AGENCY.md decision 14: considerations add in dB, and some veto: a
consideration content declares a veto rules the option out when it
applies, whatever else scores.

- **`#Consideration.veto`**: when a veto counts against the option at
  all, it counts `BG_VETO` (−1000): more than anything can weigh, so a
  goal is never adopted and a method is unthinkable. The log marks it
  ("gentle −10, a veto").
- **`Agent.gentle`** (new, 0 by default): a deeply held norm against
  striking anyone. It vetoes resisting arrest and hitting back.

Checked: with a temper and no disposition to abide, but gentle, Kasimir
doesn't resist arrest (resist is vetoed, though his temper adds 40); he
runs instead.

88 tests, 2788 checks, under both compilers, ASan, and leak-free.

### After the slice: going without harms the body

AGENCY.md decision 17: a body stock below its threshold adds fatigue and
then injury over time (hunger slowly, cold faster, air fastest), world
state, which slows work and is felt as pain.

- **The bodies domain** now proposes: an agent starving (hunger 90 or
  more), freezing (cold 50: 5 K below 310 K), or smothering (short of
  breath 50: 0.6% carbon dioxide) takes a point of harm every period
  (10 minutes, 1 minute, 10 seconds), at each multiple of it: fatigue up
  to 50, then injury. Its horizon is the next point. What it reads is the
  body (`BGColdness`, `BGBreathlessness`), not what is felt: numbness
  doesn't spare it.
- Already in place: fatigue and injury slow effortful work, and injury is
  felt as pain.

Checked: the worker, fed 5 and tired 49, with nothing to eat and left to
itself, is at fatigue 50 and injury 2 after 31 minutes; fed 50, unharmed.
The lodger in 1% carbon dioxide takes three points of fatigue in its first
thirty seconds, the door opened and the air still clearing; at 0.5%, none.

Not yet: death at the extreme (a scenario of its own, as decided);
freezing checked end to end (the same accrual, untested with the thermal
domain); recovery from injury.

89 tests, 2792 checks, under both compilers, ASan, and leak-free.

### After the slice: lying to escape a consequence

AGENCY.md decision 11: the gain from a lie is escaping a consequence the
agent believes the truth would bring, or advancing one of its goals,
scored against honesty and the risk of being found out.

- **`#Lie`** (`lies` family): weighed like a method, by its score, with
  `what` bound to what the agent holds like what it was asked about. Worth
  more than nothing, the agent says it doesn't know.
- **`#Exposing`**: what the truth would expose: holding what it believes
  another's, the law it knows against taking it weighs.
- **`deny_it`**: exposing, less honesty (half a point a point), less 20 if
  it believes someone can see the thing.
- `#Scored` (an intent with a score) and `#Acting` (a consideration about
  an act) are now common supertypes, as features are declared once.

Checked: asked where the purse is, Kasimir, holding it and told it is the
merchant's, denies knowing (+15: exposing 40, honesty −5, watched −20);
never told whose it was, he has nothing to hide (−25) and says he has it.

Not yet: the second kind of gain, a lie that serves a goal (sending a
rival to the wrong place); a lie naming a false place rather than denying;
being found out (the asker seeing it in his hand and believing him less).

89 tests, 2802 checks, under both compilers, ASan, and leak-free.

### After the slice: retracted only when contradicted

KNOWLEDGE.md decision 11: a conclusion is retracted only when its premise
is contradicted, never because a trace fades: contradicted, the agent sees
again, closely, no trace where one should still be. (A conclusion over
repetition was already retracted as the repetition moves on, and others
were already kept when their traces faded.)

- **Contradiction**: on a close look (an investigation), for each sign
  premise, a trace the agent remembers on the thing and no longer finds,
  that should still be there: as strong as it seemed, less what fading
  evenly over its kind's `lasts` takes since, above its kind's floor and
  10. Then the conclusion is retracted, with news saying why.

Checked: the paint on the lock is scrubbed off hours after it was put on.
The porter, glancing, sees it gone and still concludes the tool marks were
covered up; the painter looks closely, finds no paint where there should
still be some, and no longer concludes the lock was touched up.

Not yet: being told a credible other cause.

89 tests, 2806 checks, under both compilers, ASan, and leak-free.

### After the slice: trust lost to harm and wrongs

KNOWLEDGE.md decision 15: being harmed or wronged by someone lowers trust
in them, as does seeing them break a rule.

- **`BG_WRONGED`** (10): trust lost in one who strikes the agent, and in
  one it sees take what it believes another's.

Checked: Mira, having seen Kasimir take the merchant's purse, trusts him at
10, not 20; the officer, struck by him, trusts him at 10 or less.

Not yet: seeing someone lie (lies aren't seen through yet); the
relationship's own starting trust beyond loyalty (coworker, employer, as
kinds of tie).

89 tests, 2808 checks, under both compilers, ASan, and leak-free.

### After the slice: detail fades as strength does

KNOWLEDGE.md decision 16: a memory's features generalize at the same rate
its strength fades, slower for what was salient or seen again and again.

- **`recall:`** generalizes each feature by the memory steps since it was
  seen, scaled as strength is: by 2 × `BG_NOTICE` / ((1 + sightings) ×
  salience). Seen once with nothing salient, a step a day, as before.

Checked: a stone seen once has lost its details a day later; sighted three
times, it still has them a day later, and loses them the next.

89 tests, 2810 checks, under both compilers, ASan, and leak-free.

### After the slice: doubts of perception's own

KNOWLEDGE.md decision 12: memory and perception form doubts of their own
whenever forming a memory goes worse than usual: decay, confusion,
distraction, impairment, poor sight.

- **Impairment and distraction** degrade perception as poor light already
  did (each feature a step less precise): fatigue and injury together 100
  or more (`BG_IMPAIRED`), or adrenaline 50; or a running activity
  demanding half the agent's attention.
- **A doubt**: seen degraded so, what it half took in lingers as a
  competing hypothesis on the referent (`BG_DOUBT`, 300 in 1000), blurred
  by distance as the percept is. Seen plainly again, the doubt is settled,
  as other hypotheses already were.
- **Confusion** and **poor sight** between two known things were already
  in place as identity hypotheses ("R5 may be R2: it fits both").

Checked: worn out, the worker sees the smith's coat as dark, maybe brown
(a doubt at 300); rested, it sees it plainly, brown, and no doubt remains.
The nut of unknown size, blurred by distance only, forms no doubt.

Not yet: decay's doubt (the specific value lingering as a memory
generalizes, fading with it); distraction checked end to end (no
operation yet demands half the attention); intoxication.

90 tests, 2813 checks, under both compilers, ASan, and leak-free.

### After the slice: believed the same, two referents merge

KNOWLEDGE.md decision 13: past a credence threshold content declares, an
identity hypothesis merges two referents into one: features unified,
beliefs and testimony pooled. A wrong merge stands until evidence splits
them (both seen at once).

- **`identities_merge`** (persistence.tri, `recognition` family): merge at
  20 dB.
- **`mergeReferent:into:`**: the newer into the older. How it looks and
  where it is come from whichever was seen last; sightings add; salience
  and loyalty are the more of the two; trust moves by both's conduct;
  every testimony, finding, observation, trace, containment and identity
  hypothesis naming the newer names the older. Perception merges at the
  end of each pass.
- **Split**: seen both at once, perception binds the merged referent to
  one and makes a new one for the other, as it would for any second
  thing.

Checked: in the coat at dusk, a third sighting of the brown-coated
stranger, fitting both, raises the hypothesis to 20 and the porter holds
one referent, the visitor's, now the stranger's look, and no hypothesis.
Wrong, it stands; the two seen together, the porter holds two again.

Not yet: undoing what was pooled when they split (beliefs gathered under
the merged referent stay with it).

90 tests, 2816 checks, under both compilers, ASan, and leak-free.

### After the slice: talking takes as long as what is said

ACTIONS.md decision 14: a second, and a second more for each claim or
entry, so an account takes longer than a yes; it occupies the voice.

- **`#Account`** (talk.tri): an utterance of several claims (`entries`,
  now declared once on `#Entries`, which `#Writing` shares). Saying one
  takes the say's second again for each claim after the first, added as
  the access delay is; a hearer takes in each claim, in order.
- A single utterance, claim or question, still takes a second.

Checked: an account of where three things are takes three seconds, the
voice busy throughout, and the hearer holds three claims; one claim alone
is said within the second.

Not yet: agents composing accounts themselves (they answer with one claim).

91 tests, 2826 checks, under both compilers, ASan, and leak-free.

### After the slice: what weights a contest, declared

ACTIONS.md decision 13: an operation declares the derived value that
weights the commit permutation when its groups conflict, in the action
phase only; without one, the draw is unweighted; process and system phases
never are.

- **`#Operation.contest`**: the actor's field that weights its groups;
  `take`, `take_some` and `take_up` declare `"quickness"`.
- **The group carries its weight** (`BGContestWeight`, set by `BGPerform`
  and by an activity's stage completion), and it is saved with deferred
  groups. The committer weighs only action-phase groups, by that weight;
  every other group counts 10 (an even draw among equals).

Checked: two taking the seal at quickness 10 and 30, the quicker wins
about three in four of 1,000 seeds; the same pair in an operation that
declares nothing wins about half each.

Not yet: shoving (strength) and talking over someone (voice), as there are
no such operations.

91 tests, 2827 checks, under both compilers, ASan, and leak-free.

### After the slice: graded shortfall as curves

ACTIONS.md decision 11: the input is capacity as a percent of the
requirement; an operation declares curves for its duration multiplier,
the chance of a mishap (thousandths), and the result's quality.

- **`#Operation.graded`** (`#Graded`): what one role offers (a field of
  its entity's) against what another demands; `slowing` (percent of the
  time), `mishap` (thousandths) with its `slip` (a trace), and `quality`
  (percent) set on the demander's `grades` field.
- **The pace** is the work rate slowed by the curve (`BGGradedRate`),
  applied wherever the rate is set (starting, a next stage, resuming, a
  change of pace), so progress, checkpoints and resumption stay right.
- **Mishap and quality** are applied as the effect commits, with the
  operation's traces: a seeded draw for the mishap (a `mishap` event and
  its trace), the quality set on the result.
- `BGCurveAt` is now shared: agency's considerations use the same curves.
- **Sawing** declares one: the saw's `sharpness` against the log's
  `hardness` (both new, 60 by default); the cut's `finish` (new).

Checked: a saw as sharp as the oak is hard cuts in 8 s, finish 90, no
slip; half as sharp, about three times as long, finish 40, and a slip on
about half of 40 seeds; sharper than needed, no faster, finish 100.

Not yet: excess (too much, as the valve's lever already has in its own
code), injury as a mishap, other operations declaring grades.

92 tests, 2874 checks, under both compilers, ASan, and leak-free.

### After the slice: knowing a recipe

ACTIONS.md decision 12: knowing a recipe is knowledge, held as a rule is:
an agent kind starts with its trade's recipes; others are learned by being
taught or by reading; without a recipe an agent can't choose it; with a
wrong one it follows it wrongly.

- **`Agent.trade`** (new; the workshop's `worker` is a fitter) and
  **`#Method.ofTrade`**: a recipe (a `sequence` method) of a trade is
  known to those of it; one with none, to anyone.
- **`#RecipeSays`** (talk.tri): a claim naming a recipe; read in a manual
  or told, it teaches it (`learnRecipe:`), saved with the knowledge.
- **Agency** considers only the recipes the agent knows, and won't take
  autopilot on one it doesn't.
- **`rash_recipe`**: a wrong recipe for the pump, nobody's trade, only to
  be learned: take it apart with the line still open.

Checked: at the mill, the smith, no fitter, can't repair the pump; having
read a manual with the recipe, it shuts the line and opens the pump, and
the recipe is saved; having read a bad manual, it opens the pump with the
line still open.

Not yet: learning by practice; a fitter's knowing being shown in its
menu or plan.

93 tests, 2889 checks, under both compilers, ASan, and leak-free.

### After the slice: light and sound as domains

KNOWLEDGE.md decision 14: light and sound are domains, giving perception
its conditions. Light: lamps and fires burn their fuel down, daylight
follows the clock, rooms and doors shade it. Sound: it propagates through
rooms and doors, walls muffle it, and noise masks what is quieter.

- **`BGLight`** (a new domain): daylight by the clock, as authored
  (`daylight`: dawn 6h, nightfall 18h, an hour's twilight either side);
  a step darker in a room with a door (an air region), unless the door is
  open; a lamp shining lights its reach while it has oil (`Lamp.oil`,
  `oilAt`, new; computed when read), and goes out spent; a lit fire glows
  a tile round. Its horizon is the next change of daylight, or the next
  lamp to burn out. Knowledge given the domain (`setLight:`) takes its
  light from it; without, the old ambient setting stands, so the existing
  scenarios are unchanged.
- **Sound** (`BGLoudness`, in the traces domain): a sound's strength less
  3 a tile, and from another room 10 through an open door between them, 30
  through a wall or a shut door. Heard if as loud as the trace floor, and
  not 20 or more quieter than the loudest heard there. A sound needn't be
  seen to be heard: unseen, it is heard from where it came.

Checked: noon is day in the yard and dusk in the shut room, day with its
door open; before dawn, dusk outdoors and dark within; at midnight, dark
but by the lamp, which goes out when its hour of oil is spent, and the
worker by it can't see the crate until morning. A clatter in the room is
heard beside it, not through the wall from the corridor, but through the
open door; a clang by the listener drowns it.

Not yet: lamps lit and put out by operations; daylight by season; sound
masking speech (what is said is heard by earshot, not by loudness).

95 tests, 2901 checks, under both compilers, ASan, and leak-free.

### After the slice: wear from use, after dewdrop

LATENT_ASSEMBLY.md's provisional rules, designed (decisions 4-6, after
dewdrop's latent anatomy); and COMPONENTS.md decision 10 revised:
unreferenced content is kept, and saving never changes the world.

- **Use and abuse** (`Latent.used`, `abused`, new): working a pump
  (`work_pump`, an hour; effect "work") lifts water from the store it
  `draws` from into its riser, at its `lift` times its flow; what the
  store can't supply, it is worked dry, abused for. Seized, it can't be
  worked.
- **Wear shared out**: a role `wears` points per hundred hours of use,
  `strain` times as fast abused (the leather cup 5, three times dry; the
  valves 3; iron 1; the cover 0), faster the poorer it is. Revealing a part
  gives it that wear, no longer from the seed alone; the culprit is worn at
  least 60. An assembly within takes on its parent's use.
- **Hidden quality**: 50, give or take 20 by the unit's seed, plus the
  schema's `biases` for a kind of part (`cheap_pump`: leather -30).
- **Failure from use**: each hour risks each failure its `chance` in a
  thousand per hundred hours, four times that with its most worn candidate
  worn through, drawn from the seed and the use so far. Failing, the
  culprit is drawn then, weighted by wear, and kept (`Latent.blamed`); a
  flow loss costs the pump 80 points of flow if the culprit is a part. A
  failure a scenario sets gets its culprit when first opened. Replacing
  the culprit clears both.
- `text_feature` returns NO for a missing feature instead of crashing.
- `pump_drain` and `flood_run` build world 157, as `pump_open` and
  `mend_run` do, so a key is the same unit throughout; "pump 2" is now the
  seal's unit.

Checked: an hour lifts the tank full from the well; dry, the hour is
abuse; half the lift in the well, half; seized, no work. After 400 hours
the cup is worn most, then the valves, iron least, the cover not at all;
dry, the cup three times as worn; the cheap make's cup more. Among 24
units worked dry a thousand hours, the cup is blamed more often than among
new ones, not always. The rickety pump with 2000 hours behind it fails
within a hundred hours' work, the same hour and culprit again and after a
save; of 12 units, more worn ones fail in 20 hours than new ones.

Not yet: maintenance, and replacement, resetting a role's wear; age
wearing parts; agents working pumps of their own accord.

96 tests, 3079 checks, under both compilers, ASan, and leak-free.

### After the slice: a part's wear is its own

LATENT_ASSEMBLY.md decision 7: once a role is opened, its wear is the
part's in it, so replacing a part resets the role to the spare's own wear.

- **Part condition** (`Part.attrition`, `grade`, new): a part's wear in
  ten-thousandths of a point, and its hidden quality. Revealed, a part gets
  its role's wear and quality from the assembly; a spare's quality is from
  its own seed, its wear what content made it.
- **Opened parts wear on**: working an assembly wears each part in it as
  its role wears, by the part's own quality; an assembly within is used as
  long, and so on in. Out of place, a part wears no further. A culprit
  already opened is worn to 60 at the failure; one that is an assembly
  takes the failure on.
- **Risk and blame read what is fitted**: an opened role's wear is its
  part's (an empty one, none); unopened roles still come from the history,
  exactly as before.

Checked: a seal worked dry 1000 hours is worn through, stays so, and the
valves wear on; a new cup in its place starts at 0 and wears on, the old
one on the floor no further; a cup fitted worn 30 starts there and wears
the same; the same after a save; the cheap make's own cup wears faster,
but a new cup wears the same in either make. Of 12 rickety pumps worn
1000 hours, fewer fail in 20 hours with a new cup, and fewer blame it.

Not yet: maintenance reducing wear; age wearing parts; a pump refusing
work with a role empty; agents working pumps of their own accord.

97 tests, 3184 checks, under both compilers, ASan, and leak-free.

### After the slice: servicing

LATENT_ASSEMBLY.md decision 8: servicing an opened part undoes part of its
wear since it was last serviced. Its content is the first written in
Triangle's newer syntax, and it found a gap: a bound couldn't name its
value, so Triangle now takes `wear: <worn_through` (CONTENT_LANGUAGE.md §2).

- **Servicing** (`service_part`, effect "service", new; ten minutes, with
  hands): a part in place short of worn through (`let worn_through = 60`,
  which `replace_part` now names too) has its role's `mends` per cent of
  the wear since it was last serviced undone, and keeps that as where it
  was last serviced (`Part.tended`, new). The cup 60, the valves and the
  handle 50; the piston and cover none ("servicing won't help it"). Worn
  through, it is past servicing; an assembly within has its own parts to
  service.
- **Content in the newer syntax:** `latent.tri`'s pumps share a body by
  `let` (`crank_body`, `warm_iron`), the rickety pump copies its parts from
  `#CrankPumpParts.parts`; `workshop.tri` and `permits.tri` make their
  people from `let person`, and nail stacks from `let nail_stack`. The
  content hash is unchanged by these (aa02c564fb79b95b before the slice's
  own additions), so they change nothing loaded.

Checked: of a pump 400 hours used, dressing the cup undoes 60 per cent of
its wear, cleaning a valve half, and the piston nothing; serviced again at
once, nothing more. Worked 100 hours on, it wears as its twin left alone
does, and servicing undoes 60 per cent of that, no more; saved and
restored, it remembers. A cup worked dry 1000 hours is past servicing. Of
12 rickety pumps 900 hours used, worked 40 hours, none fails sooner with
its parts serviced, and three later or not at all.

Not yet: servicing using up grease or tallow; agents servicing of their
own accord (a goal to keep a machine in order); age wearing parts; a pump
refusing work with a role empty.

98 tests, 3282 checks, under both compilers, UBSan (ASan can't start with
this machine's clang), and leak-free.

### After the slice: servicing of one's own accord

AGENCY.md decision 19: an agent who sees a part worn may service it of its
own accord, as diligent as it is.

- **Diligence** (`Agent.diligent`, new; 50 by default): how readily an
  agent does work nothing makes it do.
- **Seeing wear** (`wearing_part`, a rule; the `#Wearing` premise and the
  `#Worn` finding, new): a part seen worn 20 or more is drawn as #Worn,
  and weighed again as it is seen, so a part serviced stops being so.
- **The goal** (`service_worn`, arising from #Worn; method `service_it`):
  worth -10, and 4 tenths of a point for each point of diligence; the part
  it can service is a path to what `service_part` takes
  (`service_part.roles.item`), so the threshold stays in one place.
- **Arising again:** a goal that arose and was settled arises again about
  the same referent only from a finding drawn since (the settled record
  keeps when, in seconds; settled again, it is moved on). Before, a goal
  settled about something never arose about it again; no existing goal
  re-draws its finding, so nothing else changes.
- **Free, it looks again:** an agent whose last intention is done decides
  again at once, weighing what arose meanwhile, rather than waiting for
  the next thing to happen.

Checked: by a pump 600 hours used, an agent of the usual diligence weighs
servicing the worn seal at +10 against nothing, and does it, 60 per cent of
its wear undone; a lazy one (10) weighs it at -6 and lets it be. A diligent
one (90) services the seal, then both valves, which look worn too, one
after the other; the seal worn again, it services it once more, and only
once. The lazy one leaves the reworn seal too.

Not yet: servicing using up grease or tallow; agents working pumps of their
own accord; diligence weighing other unbidden work (tidying, mending).

99 tests, 3300 checks, under both compilers, UBSan, and leak-free.

### After the slice: terrain, step 1

TERRAIN.md: what each tile at each level is, a terrain kind per cell, so
walking, sight, sound, light, air, water and Tessera can read one
structure. Step 1: kinds, maps, changes, and walls that stop things.

- **Kinds in content** (`terrain.tri`, the `terrain` family): `solid`,
  `opaque`, `floored`, `madeOf`, and a `look` for Tessera. Five so far:
  open floor (a world with no map), plank floor, stone wall, a doorway,
  open air.
- **Maps** (`#Map`): a legend of characters to kinds, a fill, and levels
  drawn in characters, each embedded from a file
  (`rows: _ @embed(file="maps/shed.0.map", type=text)`, Triangle's new
  `@embed`, as CUE's). The world's extent is the drawing's
  (`-[BGWorld setTerrainMap:error:]`, before any tile holds a stock).
- **The store** (`BGTerrain`, plain C): a kind index per cell, from the
  source (the drawing, or a fill), with a 32 x 32 chunk stored only once
  something in it changes. Asking a cell is an array lookup while nothing
  has changed.
- **Changes by commitment** (`-[BGProposalGroup setTerrain:at:]`):
  journaled, so a rejected group leaves terrain as it was; emitted as a
  `terrain` event; saved as the map's name and the chunks that differ from
  it; part of the state hash.
- **Solid terrain takes nothing in:** change commitment rejects a move or
  a creation onto a solid tile, as it does one off the map, so walls stop
  walkers and everything else.

Checked: a world with no map is open floor, 32 x 32, nothing past it. The
shed's drawing gives the extent (16 x 7) and the kinds, the fill past a
short row. A worker can't walk into the wall, walks out through the
doorway; nothing is put into a wall. The doorway walled up by commitment is
an event, and stops the worker; a group with an unknown kind is rejected
whole. Saved, the map and only the chunk changed; restored, the same state
hash; set back as drawn, no chunk differs.

Not yet: line of sight and agents' memory of terrain (step 2); rooms from
terrain (step 3); levels and falling (step 4); the fluid domain and the
explorer past 32 x 32; pathfinding around walls.

100 tests, 3323 checks, under both compilers, UBSan, and leak-free.

### After the slice: terrain, step 2: sight and memory

TERRAIN.md decision 7, built: sight stops at what is opaque, and what an
agent has seen of the terrain costs a bit per tile, not a copy.

- **Line of sight** (`-[BGKnowledge inSight:from:]`): within BG_SIGHT, on
  its level, nothing opaque on a straight line between, either way. Seeing
  a tile is that, and light; seeing what happens is that, without light
  (as before, only nearer).
- **Terrain seen** (`BGSeenChunk`): per chunk an agent has seen any of, a
  bit per tile (128 bytes) and when it last saw the chunk. It replaces the
  8 KB grid of times per agent, whose precision nothing read: exploring
  asks "ever seen", the map "seen now" (perception's own question).
- **Missed changes** (`BGTerrainRecall`): a terrain change is an event; an
  agent that had seen the tile and doesn't see it change keeps the kind it
  saw, until it sees the tile again. What it believes a tile is
  (`believedTerrainAtX:y:level:`): never seen, nothing; recalled, that; else
  what it is.
- **Saved**: a line per chunk seen (its bits in hex), and one per recall.
- **The map** (BGPlay `look`) draws the terrain the actor believes: `#`
  for what is solid. A new play world, `shed`, is the shed map with a
  bucket past its doorway.
- The explorer passes over solid tiles, and scans the world's extent.

Checked: in the shed, a worker sees the bucket through the doorway, not the
one three tiles off behind the wall, nor does that tile see it; the wall it
sees, it believes a wall; the whole shed is one chunk of bits. Walked away,
the doorway walled up: it believes a doorway, after a save too; back, a
wall, and nothing recalled. Played, the map shows the walls, the bucket
through the doorway, the tile behind the wall blank.

Not yet: pathfinding around walls (agents walk greedily); perception still
looks over every body in the world for each agent, which a large world
will need an index for.

101 tests, 3337 checks, under both compilers, UBSan, and leak-free.

### After the slice: terrain, step 3: rooms from terrain

TERRAIN.md step 3: a region of air is a room found from the terrain, not a
rectangle written by hand; every air scenario is a map.

- **Rooms** (`BGTerrainRoomAt`): cells of a level joined side by side,
  neither solid nor `divides` (a new kind property: a doorway belongs to
  neither room it joins), numbered by flood fill when asked, and again
  after terrain changes.
- **The air over a tile** (`-[BGWorld airRegionAt:]`): the GasStore whose
  tile (`atX`, `atY`, `atLevel`, replacing `west`, `north`, `east`,
  `south`) is in the tile's room. `BGAirOver`, light's rooms and sound's
  regions read it.
- **`rooms_map`**: 32 x 32, the room and the back room where they were, a
  wall row below with their doorways (the room's door stands in its own),
  the corridor a row lower; open ground outdoors. Maps may say a size
  larger than their drawing (`width`, `height`).
- Every air scenario (the stove, the airing, the lodgers, light, sound)
  draws it, and gives the results it gave; the corridor's listener is a
  tile further from the clatter, and still hears it through the open door.

Checked besides: the room, the back room and the corridor are three rooms;
walls and doorways in none; the ground outdoors a room with no air; the air
over a tile is its room's; a wall knocked through joins the rooms.

Not yet: air merging when rooms join, or a room split; regions' links
found from doorways; rooms found per chunk for large worlds.

102 tests, 3366 checks, under both compilers, UBSan, and leak-free.


### After the slice: terrain, step 3's open questions

TERRAIN.md step 3, finished: rooms that scale, regions' links from
doorways, and air that follows terrain.

- **Rooms found from a cell out** (`BGTerrainRoomAt`): enclosed, at most
  `BG_ROOM_MAX` (4096) cells, none at the world's edge; else open ground,
  in no room. Labelled per chunk, only where asked; a change lets go of
  the rooms beside it alone, and a wall parting open ground floods each
  side for one it enclosed. A room's size, first cell and doorways
  (`BGTerrainRoomSize`, `BGTerrainRoomCorner`, `BGTerrainRoomDoorways`).
- **The air over a tile**: each room's air kept by room number in the
  world (`-[BGWorld airOfRoom:]`), made again when the GasStore store
  changes (a change count on `BGStore`) or rooms are let go.
- **Links from doorways** (`-[BGWorld airOpeningsOf:]`): a doorway at a
  region's room's side, the region beyond or the outdoors, the door in it
  (its `wide` ajar, nothing shut), or the doorway's `draught` (a new
  terrain property). `opensTo` and `door` gone; `gap` the leak to the
  outdoors. The atmosphere keeps a list of links, measured from the
  smaller side, its carries per link, saved per link. Light's "shut in"
  and sound's "open between" read the openings.
- **Air follows terrain**, in the committer, in the commit that changes
  it: joined rooms' air summed into the first's, the others ended with it
  as successor (the atmosphere passes their heat in transit on); a room
  parted gives each side cut off `parted_air`, its share by tiles; a room
  opened to the outdoors airs out, a hundredth of its total a second.
- **`rooms_map`**: the corridor walled at its west end, since a room
  reaching the edge is open.
- `-[BGAtmosphere balanced]` is true before the domain's first step.

Checked besides: rooms, sizes, first cells, doorways; openings with no
door, a door shut, and ajar; a join with every stock kept and the joined
air ended into the first; a part, half and half; a group refused undoing a
join; a hole to the outdoors, the air airing out to within the domain's
rest; the ledger balanced throughout; the atmosphere saved mid-flow with
its links. At scale: a 1024 x 1024 plain in no room; a hut a room when its
last wall closes; a hall past `BG_ROOM_MAX` open, parted into two rooms.

104 tests, 3399 checks, under both compilers, UBSan, and leak-free.


### After the slice: terrain that scales

Pathfinding, a spatial index, and nothing sized by the map.

- **Pathfinding** (`BGPath`): bounded A* (4096 tiles expanded) to a
  target's reach, or breadth-first to what it looks for, deterministic in
  every tie. Agents walk over the ground they believe; on open ground the
  step is the one they took before. The explorer searches for the nearest
  unseen tile instead of scanning the map.
- **The spatial index** (`BGIndex`; `-[BGWorld entitiesNear:radius:...]`,
  `entitiesOnTile:`, `entitiesIn:`, `thingsNear:`, `tracesNear:`): by chunk
  on the ground, by thing for what it holds, and traces by chunk or
  bearer; kept with every change, every rollback, and a restore. Sight,
  hearing (within `BG_SOUND_REACH`), a step's traces, a doorway's door and
  `entitiesAt:` read it.
- **Sparse tile stocks**: water per chunk, only where ever wet;
  `-[BGWorld wetTiles:max:]`; saves and the state hash read the wet tiles.
  The fluid domain works on any map from the wet tiles, its holders
  growing as needed, and water stops at walls.
- **Caps gone**: a room's doorways, a region's openings (light's "shut
  in" and sound's "open between" are world queries now); the room-to-air
  cache kept while only stocks change. Trace tiles up to 1,000,000.
- **A bug**: activities ended in one round, past 64, read off the end of a
  buffer; it grows now.

Checked besides: a maze, a box, a nearest-of search and an endless plain
for BGPath; an explorer finding its way out of the room and round the
building; the index against a scan of every location and trace, through
moves, a refused group and a restore; 40 L of water spreading over 581
tiles of a 96 by 64 yard and not past a wall, every millilitre kept.

108 tests, 3425 checks, under both compilers, UBSan, and leak-free.


### After the slice: no silent caps, and activities that don't pile up

The audit's items 5 and 2.

- **Caps gone**: the atmosphere's regions, links, stoves, surfaces,
  breathers and reported watches, and the thermal domain's bodies, are
  growing arrays kept in entity order and found by halving; a region's
  watch crossed is read once, not once per watch. An agent binding a slot
  ranks every referent that fits, not the first 64 it met.
- **Activities indexed** in the world: by actor (`copyActivitiesOf:`), by
  what they take part in (`copyActivitiesTouching:`), and those that
  watch (`copyWatchingActivities`), kept like the spatial index. Every
  per-agent scan reads them: an agent's busyness, attention, providers,
  its "did it since", putting down and suspending, a breather at rest,
  the domains' watches, the cistern, play. A round's events are matched
  with the activities they concern, not every one.
- **Activities let go** (`-[BGActivities letGo]`, one group a boundary,
  read from the world alone): an ended activity goes unless it is its
  actor's latest or, per operation, the completed one that started last.
- Activity times bounded at 10,000 days, as the rest.
- `-[BGAtmosphere watches:]` renamed `airWatches:`: mulle-objc wants one
  signature per selector, and the fluid domain's differs.

Checked besides: an explorer's dozens of walks leave five activities at
most, and the index agrees with the store.

108 tests, 3431 checks, under both compilers, UBSan, and leak-free.


### After the slice: work when something happens (REALITY.md step 1, begun)

- `lab bench crowd [agents] [seconds]`: a crowd on the yard, half
  exploring, starting through the first second; boundaries, perceptions,
  decisions, and each phase's wall time (`-[BGScheduler stats]`).
- **What changed, noted**: `-[BGWorld takeTouched:]` (records and
  locations changed) and `takeVacated:` (ground tiles left), taken by
  perception each boundary, let go by the scheduler after.
- **Perception when concerned**: the agents that changed or took part;
  within sight of what changed, of an event, of what left (further for
  sounds, lamps, doors); breathing air that changed; who saw a tile whose
  terrain changed. With nothing happening, at a wake: a belief fading, a
  promise due, hunger's next band, a trace fading, the daylight turning.
  Again next boundary when short of attention or having learnt something.
  Each store's last perception and next wake are saved; a store's next
  forgetting is kept between perceptions.
- **Decision when due**: perceived, a wake due, an answer late, a
  commitment's window crossed; `decidedAt` saved.
- **Ended activities let go per round**, per actor, a group each.
- `storeOf:` and `mindOf:` by halving.
- Tests that read "seen" as "now" read it as "when it last looked";
  compaction at every boundary is a test's (`compactAlways`) alone.

Measured, wall time a world second: 20 agents 17 → 3 ms, 40 76 → 8 ms, 80
394 → 25 ms. Next: a queue of wakes, and perception's own cost.

109 tests, 3447 checks, under both compilers, UBSan, and leak-free.


### After the slice: work when something happens, made to scale (REALITY.md step 1)

- `BGWakes` (lab/src/core): a heap of when each thing is next due,
  stale entries checked and let go as they come up. Perception (each
  agent's next look, next forgetting), decision (each mind's next due:
  wake, answer late, a commitment's window), activities (next stage or
  checkpoint; the world tells them of every Activity change,
  `setActivityObserver:`). Minds looked up are nudged: checked at the
  next boundary, which comes at once; a restore nudges none.
- Kept rather than read again: blur by its arguments; an entity's
  appearance until it changes (a container changes with its contents);
  `-[BGWorld creationOf:]`; `kindNamed:` by the name's address, checked.
- `-[BGCommitter setTracing:]`; BGPath's table cleared by stamps.
- `lab bench spread [agents] [seconds]` on `plain_map` (1024 x 1024).

Wall time a world second: spread 100 → 9 ms, 400 → 39 ms, 1600 → 181 ms
(linear in the agents); crowd 80 → 14 ms (394 ms before step 1).

109 tests, 3447 checks, under both compilers, UBSan, and leak-free.


### After the slice: the reality bubble, anchors and levels (REALITY.md step 2)

- `content/reality.tri`: `#Reach`, `#AnchorKind` (family `anchors`:
  `player`, `distant`), `#Contact` (`contact`: said, struck, arrested,
  moved; 60 s).
- `BGReality` (lab/src/core): anchor kinds from content; anchors in entity
  order, each centred on a chunk with a margin of hysteresis; the level of
  a tile, the highest any anchor gives; leases, the later end kept, ended
  ones let go each boundary.
- `BGWorld`: `setAnchor:kind:`, `removeAnchor:`, `settleAnchors` (the
  scheduler, after commitment), `detailAt:`, `detailOf:`,
  `leaseContactsFrom:` (the committer, after each group); anchors and
  leases saved and hashed.
- Play: `anchor <kind>|off`, `reality` (a chunk map around the actor).
- Nothing reads the levels yet. The audit of what stands in the way of
  threads is in REALITY.md step 6.

Checked besides: no anchors, all full; levels across, up and down; the
centre staying within its margin and following past it; a word to someone
at reduced detail leasing them full, saved and restored, and running out.

110 tests, 3463 checks, under both compilers, UBSan, and leak-free.


### After the slice: reduced detail (REALITY.md step 3)

- `content/reality.tri`: `#Level` (`senses`: all | own; `every`), family
  `levels`; `reduced`: own senses, every 10 s.
- `BGRealityOwnSensesAt`, `BGRealityCadenceAt`, `BGRealityBeat`.
- Perception: those concerned only by being near something are dropped if
  their senses are their own; perception and forgetting wakes on the beat.
- Decision: a mind's due time on the beat below full.
- `lab bench crowd|spread N S anchor`: the first agent anchors; levels
  counted.

Measured: crowd 160 47.8 → 37.8 ms a world second; spread 1,600 unchanged
(each agent's own loop, kept at reduced, is the cost: steps 4 and 5).

111 tests, 3487 checks, under both compilers, UBSan, and leak-free.


### After the slice: frozen, and catching up (REALITY.md step 4, for agents)

- Frozen agents: no perception (`perceive_by_now`, `forget_by_now`, the
  due loop), no decision (`isDue:`, `mind_due_now`), activities waiting
  (`dueOf:` never).
- What rose: `BGRealityKeepAnchors`, `BGRealityKeptBox`,
  `BGRealityKeptSame`, `BGRealityDetailKept`; the world compares the
  anchors as last settled with as they are, over the moved anchors' reach;
  contact raises a frozen party; `takeRisen:` (perception), the activity
  observer told of each risen agent's activities; `markAnchorsSettled` on
  restore.
- `lab bench ... anchor=<kind>`.

Measured: 1,600 spread, `distant` anchor (871 frozen): 180 → 83 ms a
world second.

112 tests, 3498 checks, under both compilers, UBSan, and leak-free.


### After the slice: content by topic (content/README.md)

- `content/`: at the root, the vocabulary every topic is written in
  (`things.tri`, `actions.tri`, `activities.tri`, `agency.tri`,
  `knowledge.tri`, `reality.tri`); beneath it, a directory per topic
  (`hunger/`, `air/`, `institutions/`, ...) holding everything about it, at
  every level of detail, each file headed by its cut points. Moved, not
  changed: the content hash (82409220f2de70ec), the generated components,
  and every spec are as they were.
- `BGLoadContent` and `make gen` read the topic directories. The `triangle`
  tool loads a directory with its subdirectories; its language server,
  `fmt` and the Emacs mode load a file with its content root.

112 tests, 3498 checks, under Apple clang; the mulle build not yet run on
it.


### After the slice: clang and GNUstep, on macOS, Linux and Windows (ci/README.md)

- Off mulle-objc and mulle-sde, for standard tools and for Linux and Windows
  builds: clang with Apple's Foundation on the Mac, GNUstep's (libobjc2 2.3,
  gnustep-base 1.31.1) on Linux and on Windows under MSYS2's clang64. The
  mulle-sde project (`.mulle/`, `cmake/`, `CMakeLists.txt`, `src/reflect`,
  `src/generic`, the `src/triangle` links) is gone.
- `Makefile`: per-object, incremental, one build directory per platform;
  `make check` builds with warnings as errors, tests, and compares every
  scenario's hashes with `ci/scenario-hashes.txt`, the same on every
  platform; `make asan`.
- Portability: a `qsort` tie in Triangle's default resolution that C
  libraries broke differently (a diagnostic named its sources in another
  order on Windows); `int64_t` printed as `long long`; null pointers with
  a count of 0 kept from `memcpy`, `memset` and `qsort`; Windows'
  `near`, `far` and `_daylight` macros; blocks off; binary stdio for the
  language server on Windows.
- `ci/linux/Dockerfile`, `ci/windows/setup-msys2.sh`, and
  `.github/workflows/build.yml`, running both suites on all three.

112 tests, 3498 checks, on macOS, Linux and Windows; every scenario ends in
the same state on each.


### After the slice: the lab in Odin (STACK.md)

- Ported from Objective-C to Odin, literally, by the rules in its guide
  (in this file's commit history, `lab/odin/port/PORTING.md`): one package
  in `src/`, names derived from the old selectors by a generated table,
  reference counts and autorelease pools so every object kept its
  lifetime, formats changed to print what printf printed.
- Triangle generates the component records in Odin too (`tri-components
  -odin`); its Objective-C wrapper is gone, and `triangle/odin/triangle`
  serves the lab. Tessera, ported before the lab, is Odin.
- Found on the way: Odin's fmt reads `{` as a placeholder and pads widths
  on numbers with zeros (the `formatting` test holds both rules to libc);
  a range loop's end is evaluated each time round; a C extent check in
  Tessera that could wrap; buffers the C read past when Triangle cut a
  text.
- GNUstep, MSYS2's GNUstep and the Linux image built from source are gone:
  macOS and Linux build with Odin's release and clang. Windows builds
  Triangle only, until Odin's MSVC link is set up there.

113 tests (the formatting test added), 3522 checks, on macOS and Linux,
clean under AddressSanitizer; every scenario ends in the same state as the
Objective-C lab's (the hashes in `ci/scenario-hashes.txt` are unchanged).


### After the slice: the watcher (TESSERA.md slices 2 and 4, in part)

- Truth scenes of a world (`src/scene_truth.odin`): terrain by its `look`,
  water, light, and a mark for each entity on the ground or held, keyed by
  its blueprint's name until looks are content (slice 3).
- The first window backend, `tess_raylib` (`../tessera/raylib/`): glyph
  tiles in DejaVu Sans Mono (built in), camera, focus level, selection, a
  panel. TESSERA.md's decision 8 now names raylib, which comes with Odin,
  not sokol.
- The watcher (`watcher/`, `make watcher`): a crowd on the yard, the
  cistern or the marked nail, run on the viewer's clock, paused, stepped a
  boundary at a time, or up to an hour a second; the inspector shows what
  is selected, and an agent's concerns and latest decisions. It runs only
  the boundaries due and puts none in, so watching changes nothing: the
  `watcher` test runs a crowd in uneven slices, a pool drained after each,
  and gets the state the same crowd reaches in one go. The lab itself
  never links raylib.

114 tests, 3565 checks, on macOS and Linux; the scenario hashes unchanged.


### After the slice: hunger over weeks (VILLAGE.md slice 1, issue #1)

- Hunger is a component of its own, `#Hungry` (content/hunger/body.tri),
  that people carry: `satiety`, the stomach, emptying over 8 h, felt as
  hunger as `fed` was; and `reserves`, falling only while the stomach is
  empty, over 21 days, and refilling over 7 while it isn't. Both are kept
  as of `fedAt` and computed when read; the bodies domain wakes at the
  bands, as before, and where reserves run out.
- Eating no longer does the body's arithmetic: the food says what it gives
  (`#Food`'s `nourishment`, the supper's 50) and `bodies_nourish` applies
  it.
- Weakness (content/hunger/weakness.tri), curves from reserves: attention
  (the percept budget), the pace of work (`work_rate`), perception (seen as
  if worn out at half or more lost), grip. Starving injures a point every
  2 h once reserves are gone, and no longer tires, so a rest doesn't mend
  it; cold and bad air harm as before.
- A perceived kind names only the components the senses can tell, and of
  them the most specific (`view_kind_of`): a person is `#Agent`, not
  `#Thing & #Hungry & #Body & #Agent`, as nobody can see a stomach.
- Tests that run for days about something else feed everyone each morning
  (`test_breakfast`); `going_without` and `starving_sight` test the closed
  form, the harm and the weakness.

115 tests, 3582 checks. The scenario hashes changed: agents' records have
`Hungry` in place of `Agent.fed`, and the content's new types move a type
number in the trace; every scenario's printed trace is otherwise the same.


### After the slice: the village and its homes (VILLAGE.md slice 3, issue #3)

- `content/village/`: the village's map, 160 by 100 (woods north and east,
  four houses either side of the path east, plots south), drawn on four new
  terrain kinds (grass, tilled soil, woodland, dirt path; `earth`, a
  material); its villagers (farmers, woodcutters, hunters), beds, larders,
  woodpiles and worksites.
- `content/home/`: beds and worksites, and the day's commitments: to work
  07:00–15:00, home by one's bed until 22:00, a night's sleep in one's own
  bed. `agency_undertake_every_with` undertakes a recurring commitment with
  its slots bound.
- `lab run village` (src/scenario_village.odin): twelve people in four
  households, kin to each other, each bed owned by its sleeper and the
  household's things by its eldest; three days and nights, checked at
  11:00, 21:00 and 02:00. The run goes boundary by boundary to each check,
  putting none in, so a watched village is the same run. About 4 s on this
  Mac.
- Found on the way: beds just alike were taken for each other. An agent
  passing a neighbour's door saw a bed like its own and believed its own
  had moved there; a bed is now known by its blanket's colour (two colours
  added, purple and orange, for twelve). Sight is four tiles, so each
  villager is shown its worksite and its home before the first morning.
- The watcher watches the village (`watcher village --from 15`), with
  glyphs for its ground and things until looks are content (issue #2).

116 tests, 3597 checks. The scenario hashes changed: the content's new
types (a material, two colours, the terrain kinds) move type numbers in
the traces and state; each scenario's printed trace is otherwise the same.


### After the slice: looks in content (VILLAGE.md slice 2, TESSERA.md slice 3, issue #2)

- A look is a `#Look` (content/things.tri), declared beside its kind: the
  kind (a type, or a blueprint) and its appearance key. A thing looks as its
  blueprint's look, else its type's, else that type's parents' in turn; a
  kind several at once as the look that `prevails` (an assembly over a
  water store over a body). A field refined down the types can't do it:
  Triangle won't let a subtype's default override its parent's.
- Themes in content (content/looks/): `text`, `lab play`'s map, which
  draws as before (its glyph table is gone), and `tiles`, the watcher's
  glyphs and colours (its table, and Tessera's terrain defaults, gone).
  Terrain kinds share `look` with things through `#Looks`.
- Truth scenes key each mark by its look (src/looks.odin); the `looks` test
  checks the rules, and that every physical thing in the workshop, the
  cistern and the village, and every terrain kind, has a look the tiles
  theme draws.
- Found on the way: the watcher's clock stopped whenever the world had no
  boundary due (it was held a quarter second past the last), so a world
  with nothing to do sat at its last boundary's time; now it is held only
  while the world is behind.

117 tests, 3696 checks. The scenario hashes changed by type numbers only:
each scenario's printed trace is otherwise the same.

### After the slice: cooking and the larder (VILLAGE.md slice 4, issue #4)

- content/cooking/: food is raw or not (cooking's fields on hunger's
  `#Food`), and `cook`, twenty minutes at a lit stove, adds the food's
  `cooking` to its nourishment (grain: 15 raw, 50 cooked). Each house's
  `#Larder` holds a sack of grain, sixty portions, painted the household's
  colour so that it is told from the others.
- Hunger's ways to food: eat a meal in hand; else make one and eat it
  (`have_a_meal`: cook what is in hand at a stove, lit first; take a
  portion from where food is kept, hands empty; look in the nearest
  containers, with a stove to cook at); else eat it raw. Taking from,
  cooking at and looking in go by habit first, so a villager keeps to its
  own larder and stove. The morning's commitment is something to eat at
  work, the evening's supper, both made the same way.
- Agency: a goal can be `kept`, an ongoing condition (work, home). Its
  commitment arises again whenever it no longer holds, through its window,
  and its urgency doesn't rise. Resuming a suspended activity walks back
  within reach of what it names first (a sleep, after going to the larder
  in the night, used to fail where it stood).
- Commitment: a stack's split carries the stack's other components (its
  food, say): the units are alike. Before, a portion split off a sack was a
  body and nothing more.
- The village: villagers' stomachs empty over 12 hours; the setup tour
  takes each past its larder and its stove. Eight new checks: everyone
  takes a meal to work at 07:30 and has eaten it there by 14:30, each
  household ate from its own larder (three to five portions a person a
  day; it is four), and nobody's reserves fell.
- Cost: the village does 4016 boundaries in three days, not 891, at the
  same 5 ms each: about 20 s. Walking to larders and stoves is a boundary a
  step. Slice 10 measures it; a portion eaten stays a referent, so over
  weeks recognition will slow (VILLAGE.md, open questions).

118 tests, 3713 checks. The other scenarios' hashes changed by type
numbers only.

### After the slice: seen kinds (KNOWLEDGE.md decision 17, issue #12)

- What a thing is seen as comes from one rule: the most specific kinds it
  is that the `seen` family lists (`#Seen`, content/knowledge.tri, each
  entry declared beside its kind as its look is); none, `#Thing`; what has
  no body (a claim, a bond), its type. Before, it depended on how a
  blueprint was written: a named type was seen as its name, inner states
  and all, and a meet through the components with a perceived field.
- Listed, not inherited: a kind no entry names shows as the listed kinds
  above it, which is how a seen kind will have an appearance other than its
  truth. `#Look` and `#Seen` share `#OfKind`.
- The list is what was seen before (the components with a perceived field,
  and the named types blueprints were written with), so every kind comes
  out as it did: checked for every blueprint and every entity of the
  village after three days, and every scenario prints the same but for
  type numbers. A new `seen_kinds` test.
- Found on the way: the beds' blankets were never what made a bed seen (its
  blueprint's type was named `#Bed`); they only tell beds apart (#13).

### After the slice: identity from context (KNOWLEDGE.md decision 18, issue #13)

- Recognition: a thing like one believed still elsewhere is another thing.
  It is taken for that one, moved, only if the agent believes it gone from
  where it was, it goes about by itself (an agent), the agent sees where it
  was now, or it saw it moved (src/know_knowledge_2.odin).
- The village's stopgaps are gone: no blankets, no paint, no `#Bed` or
  `#Larder` components (`#Bed` is a seen kind with no fields; a larder is a
  plain container). Beds and larders are told apart by where they are, and
  every check passes as before.
- Every other scenario behaves exactly as before. A new
  `identity_from_context` test: a bed like mine across the green is
  another; a neighbour seen there is the neighbour; my bed seen gone from
  home, then seen across the green, is mine, moved. With the rule off, it
  fails.
- Not yet: an identity hypothesis between a thing found gone and one like
  it seen elsewhere before (so a thing moved unseen is taken for two until
  it is seen moved), and ownership known as a relation a method asks after.

### After the slice: lost and found, and one's own (KNOWLEDGE.md decision 18, issue #14)

- Lost and found: a referent keeps when it was first seen. Finding a thing
  gone from where it was, the agent holds each thing like it first seen
  since as an identity hypothesis (`BG_FOUND`, 20 dB, if there is only
  one, so it merges at once; less for each other), so a thing moved while
  it wasn't looking is found again as itself. Knowledge saves the
  first-seen time.
- One's own: what an agent owns it knows as its own when it sees it (an
  `#Owned` finding, itself the choice), as it knows whom it is bound to.
  Agency's `own` order puts what it believes its own first; cooking's
  methods order by it, then habit, then nearness.
- The village: each of a household's people owns its stove, larder, grain
  and woodpile. Every check passes; the other scenarios behave exactly as
  before.
- Two new tests, `identity_lost_and_found` and `identity_own` (a hungry
  farmer takes from its own sack though the neighbour's is nearer); each
  fails with its part switched off.

### After the slice: firewood (VILLAGE.md slice 5, issue #5)

- content/firewood/: trees (oak, birch), an axe; `fell` (a tree into a
  trunk where it stood), `buck` (a length off a trunk, a log of its own,
  with sawing's effect; the log is related `splitFrom` the trunk, so its
  mass is carved, not made), `split` (a log into twenty pieces of
  firewood), `stoke` (firewood in hand into a stove's fuel), and a generic
  `put_down` (actions.tri). A stove's fuel is seen.
- The woodcutters' work is a kept commitment to stock their woodpile:
  stack what is in hand, gather what is split, split, buck, fell, take up
  the axe, and with no tree in sight go into the woods (`#Explore &
  { beside: "woodland" }`, a new method step: toward the nearest unseen
  tile beside ground of that kind). Every household stokes its stove for
  the night (19:00–21:00), and a stove lit to cook is stoked first if it
  is empty (cooking's `stove_lit`). The village runs the atmosphere
  domain.
- Agency, found on the way:
  - Habit breaks ties only between methods of the same rank (AGENCY.md
    §5's "habitual ways win ties"): it had been added to every score, so a
    practised later way came before an earlier one (cooking's double
    take, a saw put down and taken up in circles, felling all day).
  - A kept goal found impossible is tried again ten minutes later, not
    given up for its window (a woodcutter who lost the axe to the other
    idled all day). Saved.
  - A suspended activity binding what is gone or out of reach is given
    up, once the agent is in reach of what its method names now.
- The village: new checks, every stove has fuel at 02:00 each night and
  the woodcutters' woodpile rises each working day (20 pieces at first,
  over 600 a day); a woodcutter at work is one stocking its woodpile,
  wherever in the woods. Plain-wood blueprints say oak, as "wood" now has
  two kinds below it; birch firewood is its own stack.
- Cost: 32,178 boundaries in three days (from 4,016), about 68 s: the
  woodcutters walk between the woods and home all day. VILLAGE.md, open
  questions.

123 tests, 3798 checks; the other scenarios behave exactly as before.

### After the slice: forgetting, and text defaults (KNOWLEDGE.md decision 19)

- Triangle: a default among text, `*"firewood_20" | text`, was read as a
  disjunction of structures, and its default never became text (the lab
  saw `Log.splitsInto` empty). Text with strings or regexes beside it is
  now text, its default the string; a string an enum lists beside text is
  an error. `#Log` has its default back.
- A referent nothing holds is forgotten (KNOWLEDGE.md decision 19). A
  destroyed thing's event says where it was; an agent that perceives
  things end where it believed them, and finds them gone, knows they
  ended (as many as ended there, none if it can't tell which), and an
  ended referent is no candidate for recognition. A referent not believed
  anywhere is forgotten once it ended or has faded below belief, unless an
  observation, testimony, identity hypothesis, a referent in or on it,
  agency (intentions, commitments, questions) or its being someone holds
  it; findings go with it. A reaction's event (a stack merging in the bin
  it was put in) is perceived as its cause's actor's.
- Found on the way: an agent's sixteen habits filled within a day with
  portions eaten, and nothing could be learned after; now a new habit
  takes the weakest's place, the oldest of equals (AGENCY.md §8). Habits
  no longer keep a referent from being forgotten.
- The village: referents across its twelve people after three days, 360
  (from 790), level from the second day; 58.9 s (from 69.4 s), though its
  people now choose differently: 33,620 boundaries.

125 tests; the other scenarios behave exactly as before.

### After the slice: a walk as one activity (PERFORMANCE.md decision 1, AGENCY.md decision 20)

- Going somewhere on foot is one `walk` (actions.tri, a `#Walk` that
  fails on a hard interruption, off the menu as it needs a way), whose
  activity carries its way (`Activity.way`, a letter a tile) and runs a
  stage a tile, each a one-tile walk (src/act_activities.odin). The path
  search gives the whole way (`Path_Query.way`). An activity's stage limit
  is now 4,096, a search's budget. "Journey" is kept for travel by any
  means, in legs (GLOSSARY.md), and isn't built.
- Agency finds the way once, toward what a method names or the nearest
  unseen tile, and sets out. Woken on the way, the walker is busy; at each
  perception it gives the walk up if its intention changed, what it
  goes to is believed elsewhere or gone, the tile it explores toward was
  seen, or a tile ahead is believed solid. Put down for something else, a
  walk is aborted, not suspended. A mind's save holds what its walk
  was set out for.
- The village: 32.1 s (from 57.2 s), 13.3 s at `-o:speed` (from 27.3 s);
  18,262 boundaries (from 33,620); 2,860 deliberations (from 26,147); 832
  path searches (from 30,507). Its checks all pass. PERFORMANCE.md,
  "Walks, measured".
- Saves change for every scenario (an activity's new field); only the
  village behaves differently.

125 tests, 3808 checks: a test of the activities kept after exploring
checks fewer, as one walk is kept, not a one-tile walk each way.

### After the slice: measuring (PERFORMANCE.md decisions 5 and 6)

- `make check` builds its own lab with `-o:speed` (`build/<platform>/speed/lab`)
  and runs the tests and scenarios on it: the same hashes, 44 s from
  1 min 45 s on the Mac, plus 12 s to compile. `make` and `make test` stay
  unoptimised.
- `lab run village --counters` prints what the run cost on stderr:
  boundaries, events, perceptions, decisions, deliberations, path searches,
  and each phase's wall time. Agency counts deliberations and path
  searches.
- The village now: 18,262 boundaries, 157,033 events, 37,849 perceptions,
  39,037 decisions, 2,860 deliberations, 832 path searches; perception
  9.5 s, decision 2.2 s, commit 1.7 s at `-o:speed`.

### After the slice: incremental interpretation (PERFORMANCE.md decision 2, KNOWLEDGE.md decision 20)

- Interpretation's rules are read once (`Read_Rule`), not re-read from
  content for every referent at every perception.
- A rule is weighed again for a referent only when what it reads of it
  changed: the store marks a referent when a trace it bears comes or goes,
  an observation of it is added or let go, or a finding about it changes;
  its looks are compared by hash. Weighed for everyone: a rule newly
  within expertise, a misprint, `near` when the floor changed, a usual
  place when a kind changed or a referent is new, and everything when
  investigating or after a merge or a forgetting.
- A misprint checks for a claim, and a seal, in what is known before
  describing anything: memory never adds a key.
- Every test weighs what interpretation skips and fails if anything would
  have changed; the whole village was checked once the same way.
- The village at `-o:speed`: 7.7 s (from 13.3 s); interpretation 0.5 s
  (from about 6.3 s, inferred). Unoptimised, 20.2 s. Every scenario's hashes as
  before. `lab run village --counters` shows interpretation's time.

125 tests, 3808 checks.

### After the slice: history compaction (KNOWLEDGE.md decision 21)

- History keeps what has a bearing on the world, for good. A field
  flagged `debug` (an activity's pace, progress, started, due) has its
  changes committed and saved but not logged, unless `lab --debug-history`
  asks; asked, every scenario's hashes are as before, and the village's
  counters are the same either way.
- An operation's `diagnosticStages` (actions.tri; `walk` has them) marks
  what each stage but the last does diagnostic: a walk's tiles before its
  arrival. A world with a history window (the village: a day) compacts at
  each multiple of it: diagnostic events older than the last compaction
  go, counted into digests by chunk, kind and actor. Indices stay;
  `world_event_at` finds a compacted one gone, `world_history` is what is
  kept. Saves hold history's place, the digests, and each event's mark.
- Compaction changes nothing in the world: the village's save, history
  apart, is the same with it or without, and so is every history event.
- The village: 62,169 events from 157,033; 32,861 kept at the end, 29,308
  digested; its save 36,416 lines from 160,503. A new test walks a worker
  for five minutes with a minute's window, and saves and resumes across
  compactions, to the last digest.

126 tests, 3873 checks.

### After the slice: farming (VILLAGE.md slice 6, issue #6)

- content/farming/: a plot is an **area** (things.tri's `#Area`: placed on
  its north-west tile, so many tiles east and south), and its crop is its
  state: what it grows, how it stands (bare, sown, ripe), the tiles sown or
  reaped so far, and when its last row was sown. Seed (`#Seed`) sows a
  crop, a unit to a tile. `sow` and `harvest` work a row at a time
  (effect_sow, effect_harvest); the last row sown, the plot grows in closed
  form from then, and the farming domain (src/domains_farming.odin) sets it
  ripe at the moment it is grown, its one wake.
- An area is near, seen and in reach by the nearest of its tiles
  (world_entities_near, perception, view_can_reach, and a referent's believed
  reach from its seen `east` and `south`); agency walks to its nearest tile.
  An agent knows a plot by one referent (KNOWLEDGE.md decision 22).
- A crop on every tile was tried first: about 1,086 crop entities took the
  three-day village from 7.7 s to 4 min 18 s at `-o:speed` (perception
  190 s: recognition weighs every percept against every referent), and
  farmers deciding at once sowed the same tile together.
- Commitment: a field may be set expecting the value it was read with
  (`proposal_group_set_of_to_expecting`): two farmers sowing a plot at once
  don't both count a row; the second's group fails.
- Agency: a `search` slot bound already (a commitment's larder) is passed
  over once its inside was seen, as one found is; a farmer whose household's
  seed others held looked in its larder every millisecond.
- The village: each household's tilled block is two plots (the Ashes' two
  of grain, the Brooks' grain and turnips), each farmer committed to one,
  bound to it and the larder; seed is kept back in the larder, enough for
  each to take a plot's worth (300), the rest put back. A new check: every
  plot sown the first day. 8.8 s at `-o:speed` (from 7.7 s): 19,039
  boundaries, 66,302 events, 40,830 perceptions, 42,383 decisions;
  perception 4.1 s, decision 2.5 s.
- Three weeks of a plot (test_farming_weeks): sown the first day, the seed
  left put back, ripe exactly when grown at every boundary and growing as
  its closed form says between, harvested once into the larder, and sown
  again. The village run three weeks (35 s, by hand) shows it hungry from
  the fifth day, with no market; VILLAGE.md, open questions.
- Every scenario's hashes change: three new component kinds and a new
  material renumber the content's types (an activity's status, as saved and
  traced); only the village behaves differently.

128 tests, 3937 checks.


### After the slice: hashes by name

Every content change used to change every scenario's hashes: content
renumbers its types, components and terrain kinds whenever anything is
added, and the hashes read those numbers. Farming changed them all, and
only a by-hand diff against the last commit showed that only the village
behaved differently.

- The state hash reads a field that holds a type by the type's name, the
  components in order of their names (those no entity has passed over),
  and terrain kinds by name. A "changed" event that set a field to a
  type is hashed, traced (`changed: 10, "exhausted", Activity.status`)
  and saved by the type's name; so is a deferred proposal that sets one,
  and what it expected. Saves were meant to load under other content
  ("by name"), and these events and proposals didn't: now they do.
- `ci/scenario-hashes.sh` hashes a save without its `content` line,
  which any content change changes and loading skips.
- Checked by hand: content adding a component, a terrain kind, and types
  sorted ahead of all others (a topic `aaa/`) leaves every scenario's
  hashes as they were. test_farming saves a plot's events and a waiting
  proposal, both by name, and restores them to the same save and state.
- Every scenario's hashes change once, for the new hashing; the runs
  differ only in the trace's named types.

### After the slice: topics are packages, and own their fields (CONTENT_LANGUAGE.md decision 12)

A field's name was global: one type in all the content introduced it.
Farming hit that four times in one slice. For `larder` it had to add a
shared `#Keeping` frame to cooking/. For `wide`, `ground` and `tended` it
had to rename. Each new topic would hit it again.

- Triangle: a feature is the package's whose file introduces it.
  - Two packages may each introduce a field of one name. Within one
    package (or the root) it is one type's, as before.
  - A plain label means the field of the type it is written against, else
    the package's own, else the root's, else the only one.
  - A plain name means the package's own, else the root's, else the only
    package's.
  - A name or label is qualified (`cooking.#Food`, `cooking.larder:`) only
    where that leaves two.
  - A type the root declares stays the root's. A package's file adds to it
    by declaring it, and to another package's by its qualified name
    (`hunger.#Food: { … }`). The fields a file adds are its package's.
  - Names print plainly where unambiguous, generated names likewise.
    Ordering is by plain name first, so packaging renumbers nothing.
  - Triangle tests: test_packages (revised), test_package_features,
    test_package_additions; 88 tests.
- The lab: every topic directory is a package (`package <topic>` after
  each file's header; content/README.md §6).
  - cooking/ adds to `hunger.#Food`, and firewood/ to `sawing.#Log`.
  - With nothing else changed, src/components.odin, every test and every
    scenario's hashes came out as they were.
  - Then cooking's `#Cooking` has its own `larder` again, and farming's
    `#Farming` its own, without `#Keeping`. Tests and hashes as they were.

128 tests, 3940 checks.

### After the slice: hunting (VILLAGE.md slice 7, issue #7)

Animals, death, the bow, butchering, and the herds kept up; the Hunts
hunt in the village.

- **Death** is any body's (VILLAGE.md decision 7): `injure` sets the
  injury and, at 100, `die` makes the body's `remains` (harm/'s field: a
  carcass, a corpse) where it was, carved from it so its mass is the
  same, drops what it held, and destroys it. Agency lets a dead agent's
  mind go at the next boundary. test_death.
- **Animals** (hunting/animals.tri): deer and hares, `#Animal`s with no
  hands, `wary` 100, and an `instinct` to roam, which agency takes on for
  any agent that has one as it first perceives (AGENCY.md decision 21).
  Roaming is a kept goal done "lately" (`#Did`'s new `lately`): wander
  (`#Wander`, a new step: a tile of woodland within ten, chosen from the
  agent and the time) and graze an hour; a kept goal so done is woken
  again when it lapses. A `#Sighted` premise (KNOWLEDGE.md decision 23)
  over a person in sight now draws a #Danger, weighed at every perception
  and drawn afresh while it holds, and `keep_away` runs from it. An
  operation's new `range` (actions.tri) lets fleeing start from four
  tiles off, and agency walks only within range. test_animals.
- **The bow** (hunting/hunting.tri): crouch (hiding, bow in hand), and
  shoot within three tiles, a wound of the bow's 40; the shot gives the
  hunter away. test_bow.
- **Butchering** (hunting/butchering.tri): a carcass, a hand free, is so
  many cuts of raw meat in that hand (made a cut at a time and merged, so
  count and mass are declared), its hide lying where it was, the rest
  waste. test_butcher.
- **The hunter's day**: `game_hunted`, kept through working hours, done at
  40 kg of venison in the larder; meat home, butcher, stalk and shoot,
  else lie in wait a quarter-hour between short walks. A `stalking` skill
  draws #Game from deer and hares in sight, and `take_the_shot`
  interrupts the wait. The game domain (src/domains_hunting.odin) brings
  one in at the woods' edge every so often while there are fewer than so
  many. test_hunting_week: a week, 120 cuts home, the deer running when
  they see the hunter, the herd between 2 and 4 of its 4.
- **The village**: the Hunts hold bows and hunt the eastern woods; seven
  head of game to start, up to six deer and four hares, coming in from
  the east edge. Two new checks: meat in the Hunts' larder (80 cuts of
  venison and a hare by the third night), and the herds alive and within
  bounds. 11.7 s at `-o:speed` (from 8.8 s): 25,803 boundaries, 54,038
  perceptions, 57,850 decisions. Hunters walking all day doubled the
  boundaries until they lay in wait; animals grazing an hour, not twenty
  minutes, cut them again.
- **Found on the way**: a stack's count isn't perceived, so a condition
  on it never held of what an agent knows: the woodcutters' woodpile was
  never "stocked". It reads mass now (three tonnes), and names the bound
  woodpile in its `find`. Fleeing walked up to whom it fled, before
  `range`. `test_farming_weeks` released its activities twice
  (`activities_with_world` already autoreleases), which an Odin
  `-sanitize:address` build found once more tests ran after it.
- Every scenario's hashes change: agents have four new fields (`remains`,
  `wary`, `instinct`, `stalking`); the cistern and marked-nail runs differ
  only in those.

133 tests, 3986 checks.

### After the slice: a harder hunt, and animals that sleep

- **A shot can miss** (hunting/hunting.tri): it strikes by a seeded draw,
  the bow's `aim` from beside (80) less its `spread` (25) for each tile
  further, in the hunter's `stalking`. A farmhand, with none, never
  strikes. Struck or missed, the shot gives the hunter away. test_aim:
  a hundred shots from each distance; test_bow shoots a `sure_bow`.
- **Animals bolt**: their own `bolt` (a flight a dozen tiles in three
  seconds; an operation's new `run`, actions.tri, how far a flight
  carries), where they fled four tiles at a walk, still in sight, and the
  hunter walked up and shot again, seven times in a minute. A flight
  straight into the map's edge stayed put; it slides along it now.
- **Animals sleep**: an `instinct` names an `#Instinct`, the goals an
  animal keeps each over its hours (AGENCY.md decision 21). A grazer's:
  roam 05:00 to 21:00, bedded down 21:00 to 05:00, two hours at a time
  (kept, so it lies up again after a bolt, and stops near dawn). Each
  window is taken on a day early, so a night under way is kept.
  test_animals checks a night, a day, and the next night; the village
  checks the game bedded down at 02:00 each night.
- test_hunting_week: two deer home, from 33 shots, 236 bolts; the herd
  between 3 and 4 of its 4. The village: 29 checks, 13.1 s at
  `-o:speed` (from 11.7 s): 34,170 boundaries, the bolts and the night's
  lying up. Only the village's hashes change.
- Not done: tiredness from hours awake (AGENCY.md open question 10).

134 tests, 3994 checks.

### After the slice: perishing (VILLAGE.md slice 8, issue #8)

Food that spoils, in closed form.

- **Perishable food** (content/perishing/): perishing adds to hunger's
  `#Food` how long it keeps once made (`keepsFor`: 0, it keeps; meat,
  three days), when it spoils (`spoilsAt`), how long a meal made of it
  keeps (`mealKeepsFor`, two days), and what it is spoiled (`spoiled`).
  A component can't be added to a thing by setting a field, so every
  food carries them, and grain's say it keeps.
- **The perishing domain** (src/domains_perishing.odin): every domain
  advances at every boundary from the last commit's time, so food made
  then is stamped exactly, `t0 + keepsFor`; cooking sets a meal's
  (effect_cook). Its horizon is the next food to spoil, so a larder's
  meat across ten days is two boundaries.
- **Spoiling is becoming**: `become` (act_actions.odin), which death now
  uses too, makes the new thing where the old was, as heavy, its mass
  carved from it, and ends the old. Spoiled food is made of a new
  material, "rot": `eat` and the food valuing take anything made of
  "food" (the farmers' seed grain too), so spoiled food made of food
  would have been edible.
- **Merging**: the Body kind's merge into a larder's stack also gives it
  the earlier of the two times.
- test_perishing: meat spoils exactly three days on, across ten days of
  nothing, in four boundaries; grain keeps; spoiled meat can't be eaten;
  older meat put with fresher takes the older's time; a cooked meal
  spoils two days on. The village has the domain and a check that no
  food past its time is food still: nothing spoils in its three days.
  Only the village's hashes change (food's new fields).

135 tests, 4013 checks.

### After the slice: the market (VILLAGE.md slice 9, issue #9)

Coins, stalls with price boards, and the sale in three acts.

- **Coins** (content/money/coins.tri): a stack of the unit `coin`, a
  hundred in each household's coffer. `#Pricing`: what a unit of goods is
  worth to an agent in coins, raised by the need it serves; worth (in dB,
  a kind's) can't price quantities.
- **The stall** (content/market/): a container on the green, and its
  price board standing on it (a `#Label`; first the stall was both, which
  made every container a possible record, and every bin offered "read").
  The seller's `stall_kept`: set out a lot of its trade's goods (a recipe
  `ofTrade`: an agent's trade isn't perceived, even by itself), post its
  price (`post`: a `#Priced` claim written by the agency), mind the stall
  ten minutes at a time (kept: as "be by the stall", it was already done
  for a seller starting beside it).
- **Buying**: `grain_stocked`, `meat_stocked`, `firewood_stocked`, kept
  goals to stock a supply to a level, a lot at a time: a `#Purchase`
  step (agency code) asks whoever minds the cheapest, nearest stall it
  knows (`#Buy`); the seller weighs it as a deal, `hand_over`s the lot
  and says `#Sold`; the buyer `pay`s (a split into the stall, merged with
  the takings: the Body kind now merges what is split into a container,
  too). `takings_home` and `coins_home` take the coins back to the coffer.
- **Known prices** (KNOWLEDGE.md decision 24): one to a board and unit,
  saved with the store. A label is read on coming within reading distance,
  not only on a fresh sighting: a buyer that first saw a board from four
  tiles never read it at three.
- **Found on the way**: a condition describes only the slots in its
  `find`, so a bound slot it names must be found too (this was known, and
  bit again); what is in a container is known only by looking in; a mind
  held at most eight commitments (now sixteen); a buyer told to "put down
  what it carries" put down its coins (now: goods, a log, an axe, a bow).
- test_market: a farmer keeps a stall, a woodcutter buys its larder up to
  twenty kilograms a lot at a time, coins and grain conserved, and the
  takings and the rest of the coins go home. The village: market day is
  the third; every household sells (grain twice, venison, firewood) and
  buys, 400 coins at 13:00, the takings home. 31 checks. 22 s (from
  13 s): see VILLAGE.md's open question on the market's cost.

136 tests, 4040 checks.

### After the slice: the market's cost (PERFORMANCE.md decision 7)

Profiled with macOS's `sample` on an `-o:speed -debug` build (the lab's
own counters say which phase, not which function). Three things were
worked out from text again and again, each a function of the content:

- `kind_of_entity` (what an entity is seen as) looped over every seen
  kind and every component kind each call, for each entity in sight at
  each perception; the stalls and boards at the crossroads made it the
  top of the profile. Kept per entity (`World.seenAs`), with its
  blueprint, until it gains or loses a component.
- `knowledge_store_recall` parsed and generalized a referent's features
  for every description of it. Kept by kind, steps and features
  (`World.recalled`, bounded).
- `match_described`, `agency_match_supposing` and
  `knowledge_looks_alike` built a description as text, parsed and matched
  it. Kept by the text and the pattern (`World.matched`, bounded).

The village: 14.0 s, from 22 s; perception 5.2 s (from 10.4), decision
6.3 s (from 7.8). Every scenario's hash is unchanged. What's left is
spread thin; `text_at` (printing content nodes) is the largest, and not
all its nodes are the content's own.

### After the slice: carrying (VILLAGE.md decision 11)

A backpack and a basket for each household, loads, and a burdened walk.

- **Packs** (content/carrying/): `#Pack`, a container with a `load`
  (kg), `worn` or not. A worn pack is held on the back: a hand slot past
  the hands (`BG_BACK`), which the committer allows only for a worn pack,
  and which `free_hands` doesn't count. The committer keeps the load (a
  placement obstacle, like capacity). `shoulder` and `put_back` are new
  effects.
- **The burden**: `burdened_rate` (work_rate, for a walk) slows a walk by
  what the walker carries (hands, back, and what is in them) past the
  burden's `light`, half pace at `light + slows` (15 kg; 55 kg). A first
  curve (10; 30) made a woodcutter with a full pack and a lot in hand walk
  at 38%: carrying more would have been slower.
- **Stowing**: an operation's `stow` sends what it takes or is handed to
  a pack its taker carries, if it fits by count and load, else a free hand
  (`receiving`). `hand_over` and `butcher` stow; `gather` and `pick_up`
  (family `stowing`, out of the menus) are stowing take_some and take.
- **Agency**: a `#Reached` precondition with a find (AGENCY.md decision
  23), so a pack is unpacked by the supply; `#Purchase` buys only the
  supply's shortfall (counting hand and pack), and only with somewhere to
  put the lot. A carried pack's contents are perceived by its carrier
  (KNOWLEDGE.md decision 25): otherwise a seller believed its unsold
  goods still at the stall and walked between stall and larder to unpack
  them.
- **Content**: `pack_worn`, `pack_carried`, `pack_returned` (emptied into
  larder and woodpile, then put back); the market's buyers and sellers,
  the hunters (meat and hide home), the woodcutters (a packful and a
  handful a trip) use them. `#Larder`, `#Woodpile` and `#Hide` are kinds:
  the coffer and packs by the larder had food searches looking in them
  first, and the leather backpack was "brought home" as a hide.
- **Found on the way**: payments split into a stall go unseen by its
  seller (it looks in, now); a buyer with its axe in hand and its pack full
  of firewood was refused, and forgot the price; a hunter left in the
  village after the market had no woodland near to wander (it now heads
  for the nearest); the market check counts the households that had goods
  to sell (the Hunts may bring nothing home in two days).
- test_carrying; the village: 35 checks (packs back by their larders,
  empty, each night; a hide home), 15.5 s, 37,319 boundaries. Only the
  village's hashes change.

137 tests, 4069 checks.

### After the slice: a week in the village (VILLAGE.md slice 10, issue #10)

`lab run village` runs seven days (`VILLAGE_DAYS`), 79 checks.

- **New checks** (VILLAGE.md's Testing): each night, everyone fed that
  day (`Hungry.fedAt` since the day's start) and nobody's reserves below
  50, in place of the end's "reserves full"; at the end, every plot still
  growing or harvested once ripe. The woodpile's daily check accepts a
  stocked woodpile: the woodcutters reach their three tonnes on the sixth
  day and stop.
- **The week**: two market days (the third and the seventh), every
  household with goods to sell sells, the takings home, 400 coins; three
  things spoiled; packs back every night; a hide home.
- **Determinism across platforms**: every scenario's hashes, the week's
  included, are the same on macOS (arm64) and on Linux in the CI image
  (arm64, under Docker), built from a copy of the tree so the two
  platforms' Triangle objects don't mix. CI checks Linux on x86-64.
- **Cost**: 34 s a week at `-o:speed`, 4.9 s a world day: 75,120
  boundaries, 157,347 perceptions (12.9 s), 168,715 decisions (16.1 s),
  domains 0.1 s. `make check` takes 128 s, the village 103 s of it (run
  three times: the test, the scenario's run, its save). Not cut; how to,
  if CI wants it: VILLAGE.md's Testing.

137 tests, 4069 checks.

### After the slice: the knowledge view in the watcher (VILLAGE.md slice 11, issue #11)

The watcher shows the village as one villager knows it (TESSERA.md slice
2's knowledge scenes).

- **The producer**: `scene_knowledge(knowledge, agent, extent, seq)`
  (src/scene_knowledge.odin) builds a knowledge scene from one store:
  - cells: the tiles it has seen, with the terrain it believes there;
  - marks: its referents, by referent id, where it believes them, looking
    as the kind it believes;
  - flags: itself the `Actor`, those seen at its latest perception
    `In_Sight`, those not where it last saw them `Gone`.
  Tiles in sight now get their light and water as perceived. A remembered
  tile is dark and dry, `seen` when the store last saw its chunk (it keeps
  no time a tile: TESSERA.md's open questions). It reads no other entity
  and makes no store.
- **Drawing it** (tessera/raylib): a tile never seen is black; one
  remembered is at half its brightness, fading to a quarter over two days;
  a mark believed gone isn't drawn.
- **The watcher**: `k` switches between the truth and the knowledge of the
  agent selected. There, `tab` goes to the next agent's, `f` follows a
  referent where it is believed, and the inspector says what the agent
  recalls of the referent (`knowledge_store_recall`), where and since when;
  of itself, its concerns and log. `--knows` opens as the first agent knows
  it, following it.
- **Tests**: `scene_knowledge` (a farmer sees a sack beside it; gone off,
  it still has the sack where it was after the sack is carried off unseen;
  back, it sees it gone). `watcher` also builds a worker's knowledge scene,
  and what it recalls of itself, between slices: the crowd still ends where
  it does unwatched.

138 tests, 4138 checks.

### After the slice: the village's small open questions (VILLAGE.md)

- **What spoils** is `#Perishable` (content/perishing/), a type of its own
  that food, a carcass and spoiled food are each a kind of; the
  perishing domain reads its store. With nothing to become (`spoiled:
  ""`) a thing rots away: spoiled food ten days after it spoiled. A
  carcass left two days unbutchered is **carrion** (hunting/), which
  rots away too.
- **A merge averages**: two stacks of food merged spoil at their times
  weighed by mass (src/kinds_body_kind.odin).
- **Seed is kept back**: once a harvest, holding more than a sack of
  seed's worth (12.5 kg of grain), a farmer carves a sack off as seed
  (`keep_seed`, the food's `keptAs`), marks the plot `kept` till it is
  sown again, and sows from it. A turnip sack is 350 units now, seven
  turnips' worth.
- **A backpack each**: a household keeps one for each of its people who
  go out to work. With three alike, a hunter mistook one for another and
  believed a hide in the one it carried: what a carrier believes is in
  the pack it carries, not seen there, is now not where it was, wherever
  it saw it put in (KNOWLEDGE.md decision 25).
- **A hunter crouches again** straight after a shot. Over the hunting
  test's week: 80 venison home as before, from 17 shots (36), and 9
  bolts (215).
- **A basket is wicker**: `"plant"` is a supertype of grain and turnip,
  so a basket of it was made of one of them at random.
- **Memory** (PERFORMANCE.md decision 8): the village ran its week in one
  autorelease pool, 7.3 GB at its peak and 8.3 GB with the above, and the
  system killed `make check`. Each boundary has a pool of its own now
  (`village_step_until`, `watcher_step_until`): 2.5 GB, the same state
  hash with the pools as without.
- **Tests**: `keep_seed` (a farmhand keeps seed back from a ripe plot of
  16 by 4, and sows it again from it); `perishing` checks the average,
  spoiled food rotting away, and carrion. The village's hashes changed;
  the other scenarios' didn't.

139 tests, 4153 checks.
