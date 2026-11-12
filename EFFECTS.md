# Effects as data

## Status and scope

The decisions below were taken on 2026-11-11. Steps 1 and 2 of the order of
work are built: step 2 in Triangle (arithmetic that goes with a pattern;
`math.Min`, `math.Max`, `math.Clamp`), step 1 (`lab/src/act_declared.odin`): `after`, `moves` and `emits`, for
an operation or a stage. Looking, giving, opening a door, putting down,
putting in, and the last stage of dismantling a pump are declared. The rest
is a draft. It takes up
REVIEW.md §3.1 (and step 7 of its order of work) and turns it into a design
that could be built an operation at a time.

In scope: what an operation's effect is today, what is wrong with that, and
how content could state an effect so that one generic procedure applies it.

Out of scope: progressions (REVIEW.md §3.2), names in `text` (§3.3), and
moving each topic's `#Effect` atom into its own directory (§3.4). They are
related, and are noted where they touch this.

How each finding is known: **ran** (reproduced with scratch content outside
the repository, against `triangle/build/`), **read** (from the code or the
content), or **review** (REVIEW.md's count, not re-counted here).

Two terms are proposed, and have entries in GLOSSARY.md marked as such: a
**named effect** (today's `effect: "forage"`) and a **declared effect**
(the change stated in content).

## Decisions so far

1. **`after` and `changes` are both kept** (`changes` not built yet: see
   step 3). `after` states each role's
   fields as the effect leaves them, arithmetic included (`handfuls: $h -
   1`). `changes` is the coarse effect of DETAIL_REGIMES.md, as it stands
   there, for an operation that is also run below full detail as a
   periodic operation, or that adds to a field it doesn't read through a
   role. Where either would do, `after`.
2. **Clamping is a function of Triangle's arithmetic**: `math.Clamp(x,
   lo, hi)`, with `math.Min` and `math.Max`, over numbers and quantities.
   It is wanted often (every "add, to the bound"), so content says it, and
   the lab does not clamp `after` on content's behalf. It is called like a
   built-in, but cannot be one as they are now: see "The function".
3. **An operation with two cases that differ materially is two
   operations**, each on the action menu: cooking a portion of a stack,
   and cooking the whole of it. What they share is a type both are
   instances of. No mechanism of alternatives is added, at least for now.
4. **Start with three conversions that prove the procedure**: `look`
   (emits), `give` (moves), and one that sets a constant (`open_door`).
   Done.
5. **`changes` names its role and field in `text` for now.** The loader
   rejects a role the operation doesn't have and a field the role's type
   doesn't have. Ending the names in `text` is a later change (REVIEW.md
   §3.3).
6. **Forage stays a named effect until regrowth is a progression**
   (REVIEW.md §3.2): its effect sets `grewAt`, which is regrowth's
   business, and it would be converted twice.
7. **`after` as a goal's `done` is out of scope.** Nothing here prevents
   it; it wants its own design once expectation works.
8. **`after` and `changes` naming the same field of the same role is a
   load error.**
9. **Keeping the scenario hashes as they were is not a constraint.** A
   conversion that improves what happens regenerates them and says so.
10. **A law says what it forbids as a pattern over the operation**, not
    as an effect's name. Built: the pattern is a type of operation. A
    **taking** (`#Taking: #Operation & { roles: { actor: #Agent, item:
    #Body } }`) is an operation by which its actor comes to hold its
    item; `take`, `take_some`, `take_up`, `pick_up`, `gather` and
    `pry_out` are declared takings, and `theft_law` says `forbids:
    "#Taking"`. An action breaks the law if its operation's type is the
    one named or under it (`laws_broken`). So an operation is forbidden
    by what it is declared to be, whatever its effect and stages.
    Considered and left: a pattern over the effect itself ("anything
    whose `moves` put a thing into its actor's hand"). It needs matching
    within a list, and would make confiscating a taking; nothing yet
    wants it. Taking some of a stack, and gathering into a pack, were
    not theft before (their effect had another name): they are now.

## The issue

Content says whether an operation applies, what it costs, and what traces
it leaves. It cannot say what the operation does. It names code:

```cue
forage: #Operation & {
    effect:   "forage"
    duration: 10min
    uses:     ["hands"]
    roles: { actor: #Agent & { id: $a }, item: #Patch }
} @family(operations)
```

What follows from that:

- **Every topic with a new operation edits the lab's code.** A new atom in
  `#Effect` (`lab/content/actions.tri:27`), a procedure, and a row in the
  table. Eight of the last eleven topics did (review).
- **An agent has no idea what an operation does.** ACTIONS.md's `expect`
  and `resolve` are meant to be two questions with comparable answers. With
  the effect in code there is nothing to ask `expect` of, so an agent can't
  be surprised by an outcome, and agency can't look for an operation that
  would bring a goal about.
- **Named effects take no parameters, so they are reused by name and
  special-cased by name.** `effect_rest` sets fatigue to 0 whatever the
  duration, and four operations that only mean "wait" use it; `perform`
  hangs an air watch on any operation whose effect is `"rest"`
  (`act_actions.odin:3949`), and treats `"fill"` as an activity with no
  duration (`:3881`, `:3906`) (read).
- **The same requirement is written twice.** `effect_cook` checks that the
  stove is lit and the food is raw; `effect_forage` that the patch has a
  handful and a hand is free (read). These are role patterns, and belong
  with the operation's other requirements.

## How effects are handled now

1. An operation's `effect` (or a stage's) is an atom of the closed enum
   `#Effect`, 59 atoms on one line of `actions.tri`.
2. `act_actions.odin` holds a table from name to procedure (`effects`,
   `:3178`). Each procedure has the signature
   `proc(world, action, amount, group) -> string`: it reads the world's
   records for the bound entities, checks what it needs, adds proposals to
   the proposal group, and returns a reason if it can't.
3. `perform` matches the action from the actor's knowledge view
   (`match_action`). An instant operation's effect is applied at once
   (`apply_effect`, `:3965`); a timed one starts an activity, and each
   stage's effect is applied when the stage is due
   (`apply_named_effect`, `act_activities.odin:509`).
4. The group goes to the committer. Some proposals carry the value they
   expect to replace (`proposal_group_set_of_to_expecting`), so a group
   built on a stale reading is rejected whole.
5. An action has exactly three roles, `actor`, `item` and `destination`
   (the `Role` enum, `:20`), whatever its operation declares.

REVIEW.md sorts the 58 procedures as: 12 move a thing or some units of a
stack; 16 set or add to one field, or emit one event; 10 consume a thing or
turn it into the blueprint one of its fields names; 20 are procedural
(rotate, work, shoot, sow, walk and the like) (review).

## Proposal

### 1. A declared effect

An operation states its roles as its effect leaves them, in the same
language as the roles it requires, sharing tags with them:

```cue
forage: #Operation & {
    duration: 10min
    uses:     ["hands"]
    roles: {
        actor: #Agent & { id: $a, freeHands: >=1 }
        item:  #Patch & { handfuls: $h & >=1, yields: $y }
    }
    after: { item: #Patch & { handfuls: $h - 1 } }
    makes: [{ blueprint: $y, at: #Held & { by: $a } }]
} @family(operations)

cook_all: #Operation & {
    duration: 1200s
    roles: {
        actor:       #Agent & { id: $a }
        item:        #Food & { raw: true, nourishment: $n, cooking: $c,
                               mealKeepsFor: $k, place: #Held & { by: $a } }
        destination: #Combustor & { lit: true }
    }
    now:   $now
    after: { item: #Food & { raw: false, nourishment: math.Clamp($n + $c, 0, 100) }
                   & #Perishable & { spoilsAt: $now + $k } }
} @family(operations)
```

(Forage is the example because it is short; by decision 6 it is among the
last converted. Cooking a portion of a stack is a second operation,
decision 3.)

The vocabulary, all of it fields of `#Step`, so a stage can have its own:

| Field | Says | Becomes |
| --- | --- | --- |
| `after` | each role's fields as the effect leaves them: constants, values carried by tags, arithmetic over them | a set proposal for each concrete field, expecting the value it read |
| `makes` | things to construct: a `blueprint`, `at` a place, `called` what, and what it was carved from (`splitFrom`) | a create proposal each, and a split-from relation |
| `consumes` | a thing destroyed (`consumed`), whole or a `portion` of a stack, and `because` of what | a destroy, or a split and a destroy |
| `moves` | a thing (`moved`, by a tag on its role's `id`), or a `portion` of it, `into` a place | a move from where it was read to be, or a split; nothing, if it is there already |
| `emits` | events, by `event` (the kind), `subject` and `other` | an emit each |
| `changes` | coarse effects, `{ role, field, by }` | a set to the value read plus `by`, clamped to the field's bounds, expecting the value read |

`changes` is DETAIL_REGIMES.md's coarse effect, unchanged, so an operation
at full detail and a periodic operation below it can be written with the
same words. Its `by` may be a constant or a tag (`by: $c`).

An operation's `now` is bound to the time the effect commits, so content
can write `spoilsAt: $now + $k` (ran, inline: time arithmetic with a tag
works).

**The function.** Triangle's built-in functions are expanded on the
syntax when content loads, and take only values known then: `b:
math.Abs($x)` is a load error, "takes a number known when content loads",
even where `$x` is bound to -5 in the same instance (ran). So a clamp of a
tag cannot be added to `builtins.c`'s table. `math.Clamp`, `math.Min` and
`math.Max` are to be nodes of the arithmetic, beside `+ - * /`
(CONTENT_LANGUAGE.md §5): a constraint on intervals, computed forward,
open while an argument is open and narrowing as it narrows; the bounds of
an interval clamp to the bounds of the result. They need not narrow
backwards. Units must agree, as for a sum. Today a sum outside a field's
bounds fails (`nourishment: $n + $c` giving 110 is a load error, ran).
CONTENT_LANGUAGE.md §5 gains them in the change that builds them.

### 2. One procedure applies it

`resolve`, in ACTIONS.md's sense, for any operation with a declared effect:

1. Describe each bound entity from the truth: the truth projection, built
   as `match_action` builds the knowledge view's descriptions today.
2. Unify the operation's pattern with those descriptions (`tri_unify`). If
   it fails, the action fails, and the failure's path is the reason: a bare
   patch gives `roles.item.handfuls: >=1 & <=99 vs 0` (ran). The guards now
   inside effect procedures become role patterns and are checked here.
3. Read the result and build the proposal group in a fixed order:
   `moves` (a portion moved is its role from then on), `after` by role and
   field, then `changes`, `makes`, `consumes`, `emits`. A place such as `#Held & { by: $a }` names whose hands; the lab
   chooses which (today's `receiving`, with the operation's `stows`).

The requirement is thereby checked twice, on purpose: from the knowledge
view for the menu, three-valued, where unknown never excludes; and from the
truth when the effect commits, where it must hold.

### 3. Named effects stay

`effect:` remains for what is procedural, and an operation has one or the
other. `match_action` takes an operation to be one that has an `effect`
(`act_actions.odin:349`), so that test becomes "has an effect, named or
declared". Conversion is one operation at a time. As built: an operation
that states no `effect` has a declared one; unstated, the field prints as
its type, `#Effect`, and that is the test.

### 4. Expectation, after

`expect` is the same unification against the knowledge view's descriptions,
kept on the activity; where it differs from what was resolved is a surprise
the actor can perceive. This is the larger gain, and it is a second step: it
needs nothing more from content than step 1 gives it.

## What stands in the way

**Arithmetic did not survive a pattern at runtime (ran); fixed in step
2.** REVIEW.md §4.2
(5) found that a copy of an instance by name drops its arithmetic, and left
open whether `tri_unify` on a pattern does. It does: unifying a pattern
that states `after: { item: { handfuls: $h - 1 } }` with a description
where `handfuls` is 3 gives `handfuls: >=0 & <=98`, where the same
structure written inline exports 2. Tags are carried: a `makes` resolves to
`"berries"` held by `ref(7)`. Since the fix the same unification gives
`handfuls: 2`, and `nourishment: math.Clamp($n + $c, 0, 100)` gives 100
for 90 and 20 (ran).

**Type defaults do not leak into `after` (ran).** Unified at runtime
through `tri_pattern`, a role under `after` whose type has defaults
(`handfuls: *0`, `most: *3`) leaves them open; only what the operation
states is concrete. `triangle export` does apply them, so the lab reads
the pattern and never an exported spec.

**Proposal order matters to the hashes only for creates and splits
(read).** `world_state_hash` goes over state in entity-ID order
(`core_world.odin:2678`), so the order of sets cannot change it; the order
in which things are made decides their IDs. By decision 9 it doesn't
constrain the work.

**Some of the 38 are not as primitive as their class suggests (read).**
- `effect_forage` also sets `grewAt` when the patch was full. That is the
  regrowth progression's business (REVIEW.md §3.2), not foraging's.
- `effect_cook` cooks one portion of a stack into a free hand, or the whole
  stack if no hand is free, and sets `spoilsAt` only if the food has a
  `mealKeepsFor`. A declared effect has no "if", so by decision 3 these
  are two operations, and the methods that cook say which they try first.
  Today the code chooses.
- "One of a stack" recurs (eat, cook, give some) and wants one way of being
  said: a `units` on `consumes` and `moves`, and on a role in `after`.

**Roles.** A declared effect reads roles by name, which is the occasion to
drop the fixed `Role` enum for the roles the operation declares. It can be
done after: the first conversions use only the three there are.

## An order of work

1. Done. `#Step` has `after`, `moves` and `emits`; `effect` is optional.
   One generic procedure (`act_declared.odin`), for an operation or a
   stage; a move is onto a tile, into a container, or into a hand. Declared:
   looking (five operations, one `#Looking`), giving, opening a door,
   putting down, putting in (two operations), and dismantling's last
   stage. Their six procedures and `#Effect` atoms are gone. An operation
   or stage with no effect, named or declared, and no trace is refused
   when a world is made (`declared_check`).
2. Done, in Triangle, with regression tests (`test_arithmetic_with_patterns`,
   `test_arithmetic_min_max_clamp`). §4.2 (5): an instance's arithmetic
   was kept beside its pattern and passed along only when the instance's
   own spec was built; now a copy by name takes it, with the places of its
   tags, and `tri_unify` finds it by the pattern it is handed. `math.Min`,
   `math.Max` and `math.Clamp` are arithmetic: folded of constants,
   waiting on tags, evaluated at runtime. CONTENT_LANGUAGE.md §5 and
   REFERENCE.md say so. Two limits: the arithmetic does not go with the
   result of a unification into a further one, and a copy by name of an
   instance with several variants still drops it.
3. Done, but for `changes`. Stoking (`fuel: $f + $m`, the firewood
   consumed) and cooking are declared, their procedures gone. Cooking is
   `cook`, of all that is held, and `cook_portion`, with a hand free, of
   one portion; both are a `#Cook`, which clamps the nourishment
   (`math.Clamp`) and reckons `spoilsAt` from `now`. New in the
   vocabulary: `consumes`; a `portion` of a stack on `moves` and
   `consumes`; an operation's `now`. `changes` is left until something
   needs it: with `math.Clamp` in `after`, nothing at full detail does,
   and DETAIL_REGIMES.md's periodic operations will.
4. Under way: the rest of the primitive effects, a topic at a time; each
   topic's `- code:` cut point in its header goes as its effect does.
   Forage waits for regrowth (decision 6). `makes` is built. Declared so
   far: felling and splitting (firewood/: a thing made where the role
   was, by a tag on its `place`, and the role consumed) and lighting a
   stove (heat/, the topic's last procedure: fuel in it is now required
   of the role, where the procedure refused). Sawing is left in
   firewood/: a length cut off a trunk and a log cut through are two
   cases of one named effect, to be two operations (decision 3).
   Taking is declared, all six operations of it, with the stage of
   prying that marks the nail: an operation's `parameter` is the
   command's (how many, for `take_some`: `portion: $n`), and into a
   hand, of an operation that stows, is into a pack that bears it
   (`receiving`, as before). Installing a part is declared, on a move
   into an assembly.
5. `rest` and `fill`: the watches `perform` adds by effect name become
   fields of the operation.
6. Roles read generically.
7. Expectation kept on the activity, and compared.
8. Later, and separately: role and field names in `changes` checked as
   names, not `text` (decision 5).

The test REVIEW.md proposes holds here: the next topic adds no Odin outside
its tests.

## Found in building step 3

- **Units moved off a stack are that role from then on**: `after` speaks
  of the portion, and the rest of the stack is as it was. So `moves` is
  applied before `after`.
- **A move to where a thing already is moves nothing.** `cook_portion` of
  a single portion in hand is of that portion, where it is.
- **A tag is its declaration's.** `cook_portion: #Cook & { moves: [{
  moved: $i }] }` used `#Cook`'s `$i` without binding it again: it
  loaded, and moved nothing. An operation that extends a type binds the
  tags it uses again (`item: #Food & { id: $i }`). The lab now refuses
  it when a world is made (`declared_check`): what a step moves, consumes
  or emits of must be the `id` of one of the operation's roles.
- **What a neighbour is asked for comes from the first-ranked way's
  pattern** (`agency_wants`). A way to a meal that wanted `#Food & #Stack`
  asked for a stack, whose `count` nobody perceives, so nothing handed
  over was ever "like it". The way that cooks a portion wants the same
  food as the way that cooks it all.
- **A meal whose `mealKeepsFor` is 0 would spoil as it is cooked**
  (`spoilsAt: $now + $k`), where the procedure left `spoilsAt` unset. No
  food says 0.
- **The stove full is now a failure**: `fuel: $f + $m` past the field's
  1000 kg fails the stoking, where the procedure proposed it regardless.

- **A declared set expects the value it read, and a stale one is resolved
  again.** Two of a household stoking one stove in one step both read the
  same `fuel`. The second's set is rejected ("is no longer"); its activity
  is then pushed again, so the pattern is unified with the truth as it now
  is, up to 4 times (`BG_RESOLVE_AGAIN`). Without this the second kept its
  firewood in hand and failed. An instant operation's is resolved
  again by the committer, in the next round of the same boundary: its
  group carries how to build it afresh (`again`).
- **Stoking used to lose fuel, and the village was balanced on it.** The
  procedure set `fuel` without expecting what it read: of two armfuls
  stoked in one step, both were destroyed and one was counted. Now both
  count. Three weeks of the village went from 7 failed checks (all meals)
  to 20 (from day 13: not home, not in own bed, a pack not put back, two
  unfed). A build with the expectation switched off gives the 7 again,
  line for line, so nothing else in step 3 changes the village. The
  village's scenario hashes are regenerated. Traced since: fuel had
  nothing to do with it. Two households run out of food before the
  harvest in either build; the change shifted who was hungry when, and
  two hungry villagers each went to wait at the other's house for the
  other to come home, for good (hunger outweighs every duty). A wait is
  now an hour at most (NEGOTIATION.md decision 3), and the three weeks
  fail 7 checks again, all of them the two households short of food.

## Found in building step 1

- **A feature has one introducing type across all content**, so the
  vocabulary's field names had to be ones nothing else uses: `moved` and
  `into` (not `what` and `to`), `event` (not `kind`). `makes`, `consumes`
  and `changes` will meet the same.
- **`after` is typed `#Bound`, a new empty supertype of `#Roles`.** Typed
  `#Roles`, every stage of every operation carried a whole `#Agent`, and
  the description `match_described` prints and parses overflowed its
  buffer; the description then failed to build and the action was refused.
  The buffer is now 4096 bytes and still a fixed cap that truncates
  silently (REVIEW.md §4.4).
- **The truth projection is new** (`truth_describe_entity`,
  `act_view.odin`): every field of every component, as it is. The menu's
  match was, and is, of the perceivable fields only.
- **A set expects the value it read.** `effect_open_door` set `Door.ajar`
  whatever it was; the declared effect is rejected if the door was opened
  by another in the same commit round. Likewise the move in giving.
- **A law forbade by effect name** (`forbids: "take"`). It names a type
  of operation since (decision 10).
- **A feature's name is its package's first.** carrying/ has its own
  `into` (`#Handling`'s), so `moves: [{ moved: $i, into: ... }]` there is
  "no type has all of these features". Saying the element's type settles
  it: `moves: [#Moves & { moved: $i, into: ... }]`.
- **Taking none is refused by the pattern** (`parameter: $n & >=1`):
  "take_some fails at parameter", where the procedure said "take how
  many?".
- **A declared effect made its operation "unknown" on the menu.** The
  menu's match is of the whole operation against a description of its
  roles, so a value a tag carries into `moves` (which thing, into what)
  was something the description didn't say: `put_in item 7 destination 1:
  unknown (find out moves)`. Giving and opening a door had the same from
  step 1, unnoticed: no test asked, and the scenario hashes did not move.
  `match_described` now drops residuals inside `after`, `moves` and
  `emits`, an operation's or a stage's: what it does is no requirement.
  The menu test asserts it. Better would be for the match to be of the
  requirements only; that goes with the builder that replaces
  print-and-parse (PERFORMANCE.md decision 3).
- **Putting down now requires ground in its roles** (`actor: #Agent & {
  place: $p & #OnTile }`), where the procedure refused when the effect
  committed. An actor not on a tile no longer has it on its menu.
- **A move into an assembly (`#Installed`) is built** since, with
  installing a part (machines/) declared on it: the assembly by a tag,
  the role by the part's `fits`.
- **The check for an operation that does nothing is the lab's, when a
  world is made**, not `triangle check`'s: the editor doesn't show it.

## Open questions

None open. The shape of a law's pattern (decision 10) is the law topic's
to design.
