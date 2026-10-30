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
