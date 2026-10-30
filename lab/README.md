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
./kitchen/Debug/lab run cistern         # the fluid domain: two taps and a leak on a dwindling cistern (also -b, -d, -e)
./kitchen/Debug/lab play workshop       # play: the map, the menu, commands, the inspector (also cistern)
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
| `content/` | `components.tri`: the component kinds and their field registry, plus what descriptions say besides fields (ids, places, free hands); `water.tri`: water stores and taps; `activities.tri`: the Activity component; `operations.tri`: the operations; `agency.tri`: goals and methods; `talk.tri`: what agents say, and the say operation; `workshop.tri`: the scenarios' blueprints |
| `src/generated/BGComponents.h` | Generated from `content/` by `make gen`: one struct per component, enums, and the field registry. Committed; the lab refuses to run on content with another hash. |
| `src/core/` | `BGTypes.h` (IDs, time, seeds, locations), `BGStore` (records of one kind, sorted by ID), `BGWorld` (all authoritative state, journaled for rollback) |
| `src/commit/` | `BGProposalGroup` (proposals, handles, unit references), `BGCommitter` (ordering, individuation, apply, validation, events, reactions) |
| `src/kinds/` | Component behaviour: `BGBodyKind`, the merge reaction |
| `src/domains/` | `BGFluidDomain`: water through open taps, with checkout, exact allocation, and exhaustion as the horizon |
| `src/sched/` | `BGScheduler`, with the domain and input-source protocols |
| `src/act/` | `BGView` (reach and descriptions: the knowledge view's stub), `BGActions` (the menu, matching, effects, performing), `BGActivities` (activities under way: completion, watches, ending) |
| `src/agency/` | `BGAgency`: agents that decide from their own knowledge, with intentions, a subgoal, and a decision log |
| `src/know/` | `BGKnowledge`: agents' knowledge stores, the perception phase, recognition |
| `src/save/` | `BGSave`: saves as text, and restoring them |
| `src/scenario/` | `BGWorlds` (the worlds' setups), `BGMarkedNail` and `BGCistern`: the scenarios, their input logs, and their checks |
| `src/play/` | `BGPlay`: the interactive session behind `lab play` |
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

## What agents know

Agents learn only through perception (KNOWLEDGE.md). After each boundary's
commit rounds, every agent perceives what is in sight through the fields
declared perceivable; what is inside a container only when it looks in, takes
from it, puts into it, or reaches into it. Its private knowledge store holds
referents (R1, R2, ...): agent-local handles with a kind, the features last
perceived, a believed place naming other referents, and when they were seen.
Recognition binds percepts by kind and place, never by the developer-only
truth link: a percept at the very place a referent was believed is that
referent; one elsewhere must also look the same (its features unify), so
the crate isn't taken for the chest. A referent believed where the agent
can see, and not seen there, is marked absent.

Agents also perceive what happens, by an actor in sight: a thing seen put
somewhere is perceived there, inside a container too, though nothing else in
it is. What they see happen, and hear said, they keep as observations, in
their referents. What is said is a Triangle structure (`content/talk.tri`)
carried by the "said" event; it describes things by kind, features, and
place, never by referents; people are described by how they look (their
coat). A claim heard (`#IsIn`: something like this is in that, as of then,
seen, heard from someone, or heard) is kept as testimony: its things bound
to the hearer's referents by recognition, or new ones, with its source and
the one it says saw it. Credence is integer log-odds (decibans), from the
hearer's trust in its sources, counting each perceived root once, so a
rumour heard twice from one source is inflated until someone asks "who told
you?". Once credence reaches 0 dB the claim is believed. Trust rises when a
claim is seen true and falls when one is found false. For the developer,
every claim said is traced to its true root, someone who saw it or someone
who made it up, and the dump flags false corroboration. Memory decays when
read: each day since a thing was seen, each feature it keeps generalizes a
step along the content's hierarchies (an oak chest becomes a wooden one,
then just a chest), the belief of where it is fades, and too faint, it is
forgotten. Agents keep observations only if they are salient: being
addressed, their own deeds, or what their goals concern, more than a busy
agent's activity demands of its attention; and only as many as their
`memory` holds, the least salient evicted first. The menu `lab play`
shows comes from this store, so it can
offer what is no longer so: performing it, the world's side finds the thing
gone, the attempt commits, and perception corrects the belief.

## Agents that decide

In the decision phase after perception, each agent agency controls decides
one step from its intention, reading only its own knowledge store, and acts
through the same believed actions a player uses.

Goals and methods are content (`content/agency.tri`). A goal is done when
its `done` condition holds: a condition names slots to bind to referents the
agent believes present, each tried in the condition's order (nearest, most
recently seen), and holds when the frame they describe is entailed by its
pattern; a partial binding the pattern already rules out isn't followed. A
goal's methods are tried by rank; the first whose `pre` holds is followed,
its steps re-read at each decision: a subgoal already done is passed over and
its bindings join the method's, one not done is adopted above the goal, and
an operation is performed once the agent has walked within reach of what it
names. A method's `search` slot is somewhere to look, passed over once the
agent has seen inside it since adopting the goal. When no method's `pre`
holds, the goal is impossible for now: dropped with the reason, and the
method that needed it has failed, so the goal beneath tries its next.

A step can say something: *ask where nails are* puts a `#WhereIs` to the
nearest agent the worker knows of, then waits up to five seconds for the
answer (the scheduler wakes it then if nothing else does), and a search slot
passes over whoever it has asked since adopting the goal. Agents agency
controls answer when asked, from what they know: where they believe
something like it is, and whether they saw it or were told; or that they
don't know.

The missing nails runs on this content: *wedge the lock*
(drive a nail in, after *have nails*), and *have nails* (fetch them, else
search for them, else ask). With an apprentice who saw the smith put the
nails in a chest, the worker asks, is told, walks to a chest it has never
seen, and wedges the lock; with one who didn't, it is told "I don't know"
and drops the goal. Every decision is logged, including why a method was
passed over. Run on an omniscient knowledge view, the same agent walks
straight to the spare nails: the behaviour depends on what the agent knows.

## Playing

`lab play workshop` (or `cistern`) is an interactive session: `look` draws
the map as the actor knows it (what it sees, and what it remembers, with the
memory's age), `menu` numbers the actions it believes it can take, `do <n> [amount]` performs one, `walk n|s|e|w` takes a step (a second; the session runs until it lands), and `wait`,
`step`, and `idle` run time. `activities`, `suspend`, and `resume` manage
what the actor has under way. `ask <R> where <R>` and `ask <R> who <R>`
put a question to someone in reach, and `tell <R> <R> [in <R>]` says where
something is, as the actor believes it, or, in a container it doesn't
believe, a lie; the other agents answer through agency. The developer's
side: `inspect <id>` shows an
entity's truth, relations, activities, and history; `why <id>` follows the
chain of causes behind its last change back to the command that began it;
`knows [id]` shows an agent's store with its truth links; `trace`, `save`,
`load`, `hash`. The commands typed are the replay log
(`--log file`): feeding them back reproduces the session exactly.

## How an activity runs

Walking is one: a step is an activity of a second, and the walker arrives
when it is done. An operation declares what of the actor it `uses` (hands,
legs), and an actor runs two activities at once only if they use different
ones: it can walk away from a prying, which goes on until it arrives out of
reach, but not take two steps at once.

An operation with stages, or a `duration` (one stage), is a timed activity:
performing it commits an Activity entity, the scheduler puts a boundary at
the stage's due time, the stage's effect commits then, and the next stage
starts (`pry_out` loosens for 3 s, then pulls for 2 s). If commitment
rejects a stage's effect, the activity fails. Suspending keeps the stage's
progress and resuming runs what is left, after rechecking that everything
bound is there and in reach; after each round, a running activity whose
bound entities are gone or out of reach is suspended (walking away from a
job does it). `fill_bucket` is an
activity with a watch: it opens the tap, and the fluid domain, which reads
the watches of running activities, includes the moment the bucket reaches
the amount in its horizon and reports "watched" exactly then. The activity
system follows each commit round and ends what the round's events end: a
watch fired, or the tap's source ran dry. Activities and their watches are
components, so saves keep them.

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
- **Variadic methods don't receive their arguments through `va_start`**: the
  meta-ABI passes them differently, and reading them that way returns
  garbage. The lab's own methods are not variadic; callers format with
  `stringWithFormat:`, which MulleFoundation handles.
- The code uses manual retain/release, no properties, and no blocks, so the
  same sources build with Apple clang (`make test-apple`).
- The full MulleFoundation needs mulle-clang 23.1.3, which isn't released;
  the lab needs only MulleObjC and MulleFoundationBase.
