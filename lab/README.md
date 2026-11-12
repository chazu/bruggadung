# The simulation laboratory

The first code of the bruggadung framework, in Odin: entities,
component stores, relations, change commitment, the clock and scheduler,
saves, the action menu, and the first domain, with content loaded from
Triangle. It runs COMPONENTS.md's first scenario, *The marked nail*, and
DOMAIN_SIMULATION.md's third, *Two draws on a dwindling stock*, headless,
and checks their acceptance criteria. The plan
and its status are in [PLAN.md](PLAN.md).

It builds with Odin and the `Makefile`, linking Triangle's C library, on
macOS and Linux; [../ci/README.md](../ci/README.md) says what each needs
installed. `build/<platform>` is `build/darwin` or `build/linux`.

```sh
make                                     # build/<platform>/lab
make test                                # unit tests and scenarios; non-zero exit on any failure
make check                               # the tests, and every scenario's hashes
make asan                                # the tests under AddressSanitizer (Linux)
make gen                                 # regenerate src/components.odin from content/
./build/<platform>/lab run marked-nail   # one scenario: trace, entities, checks (also -a, -b)
./build/<platform>/lab save marked-nail  # the save of its end state
./build/<platform>/lab menu marked-nail 1000   # what the worker sees, and its menu, at 1000 ms
./build/<platform>/lab run cistern       # the fluid domain: two taps and a leak on a dwindling cistern (also -b, -d, -e)
./build/<platform>/lab run village       # the village: twelve people and a watch officer, a week of work, market and home, checked
./build/<platform>/lab run village --days 21 --log 241   # three weeks; what villager 241 thought, each night
./build/<platform>/lab play workshop     # play: the map, the menu, commands, the inspector (also cistern)
make watcher && ./build/<platform>/watcher crowd 40   # a world in a window: 40 workers on the yard (also cistern, marked-nail, ...)
./build/<platform>/watcher village --knows             # the village as a villager knows it (k: the truth, or back)
```

`make check` compares each scenario's hashes with
`ci/scenario-hashes.txt`, to show when a change has moved an outcome.

## Layout

| Path | Contents |
| --- | --- |
| `content/` | The Triangle content, laid out by `content/README.md`. At the root, the vocabulary every topic is written in: `things.tri` (the shared component kinds and their field registry, and what descriptions say besides fields), `actions.tri` (what an operation is, and the operations every topic uses), `activities.tri`, `agency.tri` (goals, methods, considerations), `knowledge.tri` (findings, rules, persistence, seen kinds, the shapes of claims), `reality.tri` (anchors and levels of detail). Beneath it, a directory per topic (`hunger/`, `air/`, `institutions/`, ...), each holding everything about its topic, its scenarios' blueprints too, with its cut points in each file's header |
| `src/` | The lab: one Odin package, `lab`, a file for each part, named for its area (`core_`, `commit_`, ...). |
| `src/components.odin` | Generated from `content/` by `make gen`: one struct per component, enums, and the field registry. Committed; the lab refuses to run on content with another hash. |
| `src/types.odin`, `object.odin`, `foundation.odin`, `protocols.odin` | IDs, time, seeds and locations; objects' reference counts and autorelease pools; the string and number handling the lab's output depends on; the protocols, as structs of procedures |
| `src/core_*.odin` | `core_store` (records of one kind, sorted by ID), `core_world` (all authoritative state, journaled for rollback), `core_index`, `core_path`, `core_terrain`, `core_reality`, `core_wakes` |
| `src/commit_*.odin` | `commit_proposal_group` (proposals, handles, unit references), `commit_committer` (ordering, individuation, apply, validation, events, reactions) |
| `src/kinds_*.odin` | Component behaviour: the body kind's merge reaction, valves, latent assembly |
| `src/domains_*.odin` | `domains_fluid_domain`: water through open taps, with checkout, exact allocation, and exhaustion as the horizon; `domains_traces` and `domains_bodies`; `domains_atmosphere`: the air of a room and a stove's fire, conserved exactly, with fuel exhaustion and watch crossings as horizons; `domains_thermal`: the heat of solids, coupled to the air by contributions; `domains_light` |
| `src/sched_*.odin` | `sched_scheduler`, with the domain and input-source protocols; `sched_coupling`: the step-start snapshot and contributions between domains |
| `src/act_*.odin` | `act_view` (reach and descriptions: the knowledge view's stub), `act_actions` (the menu, matching, effects, performing), `act_activities` (activities under way: completion, watches, ending) |
| `src/agency_agency.odin` | Agents that decide from their own knowledge, with intentions, a subgoal, and a decision log |
| `src/know_*.odin` | Agents' knowledge stores, the perception phase, recognition |
| `src/save_save.odin` | Saves as text, and restoring them |
| `src/scenario_*.odin` | The worlds' setups, and *The marked nail*, the cistern and the village: the scenarios, their input logs, and their checks |
| `src/play_play.odin` | The interactive session behind `lab play` |
| `src/scene_truth.odin`, `src/scene_knowledge.odin`, `src/looks.odin`, `src/watcher.odin` | Tessera's truth scenes of a world, and knowledge scenes of what one agent knows of it; what things look like, and themes, from content; what the watcher can watch, and its running of it |
| `watcher/` | The watcher: a lab world in a window, its own executable (raylib), built by `make watcher` |
| `src/test_*.odin`, `main.odin` | The test runner and the tests; the command line |

## How an action happens

Operations are content (`content/actions.tri`, and each topic's): patterns
over the descriptions of the entities filling their roles, with tags
carrying bindings between roles. An actor's view (`View`) can bind only
what is in reach, and describes each entity by its type, id, place, and the
component fields whose `@field` flags say they can be perceived. A hidden
field stays open, so a match on it is unknown, and unknown never excludes.
The menu lists every operation and binding whose match isn't incompatible.
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
their referents. What is said is a Triangle structure (`content/talk/talk.tri`)
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
forgotten. Operations leave traces (tool marks, scuffs) and remove them,
and each removal leaves its own (a damp floor, a smell of soap); traces
fade with age, computed when read, and are removed when they run out,
with nothing to compute between. Agents perceive them by sight or smell,
never what made them. Perception has precision: from afar a size is an interval, and a match on
it is unknown, which a method can turn into a goal of looking closer.
Recognition is unification: a percept that differs from someone only in
what changes daily (a coat) may still be them, and the agent keeps an
identity hypothesis, which a later percept fitting both raises; at dusk
less is seen, and memory keeps the more specific. A component field can
declare another's appearance
(`#Body.surface` for `material`): perception reports the appearance, and
only an analysis (`test_scratch`) finds the truth beneath, which the
analyser then keeps. Interpretation rules in content draw findings from
what an agent perceives (fresh paint means something was touched up),
gated by its expertise and by what it saw before. Faint traces go
unnoticed in passing; investigating, a close look, notices them and draws
the rules that take thought. A notebook is a record: writing
in it copies a claim the character believes, and whoever reads it, a thief
included, takes the claim from its author; `lab play`'s `notebook` shows
what the character knows, and `note` keeps the player's own notes apart.
Agents keep observations only if they are salient: being
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

Goals and methods are content (`content/agency.tri`, and each topic's). A
goal is done when its `done` condition holds: a condition names slots to
bind to referents the agent believes present, each tried in the condition's
order (nearest, most recently seen), and holds when the frame they describe
is entailed by its pattern; a partial binding the pattern already rules out
isn't followed. A goal's methods are tried by rank; the first whose `pre`
holds is followed, its steps re-read at each decision: a subgoal already
done is passed over and its bindings join the method's, one not done is
adopted above the goal, and an operation is performed once the agent has
walked within reach of what it names. A method's `search` slot is somewhere
to look, passed over once the agent has seen inside it since adopting the
goal. When no method's `pre` holds, the goal is impossible for now: dropped
with the reason, and the method that needed it has failed, so the goal
beneath tries its next.

A step can say something: *ask where nails are* puts a `#WhereIs` to the
nearest agent the worker knows of, then waits up to five seconds for the
answer (the scheduler wakes it then if nothing else does), and a search slot
passes over whoever it has asked since adopting the goal. Being asked is a
choice for agents agency controls: answering is worth their trust in the
asker plus their `helpful` disposition, less what their running activity
demands of their attention and a little for a goal of their own. Worth
something, they answer from what they know: where they believe something
like it is, and how they know, or that they don't know. Busy, they answer
once they're done, if the asker can still be waiting; otherwise they say
they won't. Asked for something, they weigh complying the same way, less
the cost of parting with it, and give it or refuse.

Goals have worth, from considerations in content (credence among them),
and are raised by generators. A goal that arises from a finding (a noise
heard near the storeroom) is weighed against what the agent is doing,
mid-activity too: it wins only by a margin and the cost of interrupting,
then the agent suspends what it was doing and comes back to it after. An
agent's commitments (a shift from 8:00 to 16:00) are its routine: while a
window is open its goal is a candidate, worth its duty and an urgency that
rises toward the deadline. A promise is a communicate act: the promiser
commits to it, and hearers hold it as a claim about a time to come, kept or
broken as they find. Agents feel their hunger, a body stock that falls as
time passes, through interoception, dulled while they concentrate; the
needs generator raises eating, worth what they feel.

Methods are scored, by dispositions and norms (`honesty`, `scruples`) and
by whether the agent believes itself watched; one that scores below nothing
is unthinkable. Habits grow with repetition and fade: a habitual method
wins ties, a slot can prefer the habitual referent, and an observer who
saw someone do the same thing three times believes they usually do, and
finds it salient when they don't. Effects carry no success flag: turning a valve commits the torque the
actor's chain of tools applies, and the valve's reaction decides, by a
breakaway no menu or percept reveals; past a tool's limit there is risk,
not refusal. Recipes are methods done step by step, bound through what the agent knows
(a wrong diagram binds the wrong cock); a suspended step is resumed, and
resuming rechecks what it needs. Simultaneous takes are fair: one applies and the
other is rejected whole, ordered by a seeded permutation weighted by the
agents' quickness; reservations block nothing, though an agent told of one
may respect it. The player can hand their character to
agency on autopilot, and control comes back when something arises worth
more than the player said, or the goal is done.

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
A proposal group (create, move, set a field, split, merge, relate, emit)
and submits it. At the next boundary the committer:

1. orders the groups by phase (process, action, system), then by a
   permutation seeded from the world seed, boundary, and round
2. rewrites each group for automatic individuation: a proposal that names
   one unit of a stack (`unit(stack, 1)`) gets that unit split off first
3. applies the group with the world's journal open, and validates the
   result: entities exist, every physical entity has one location in a place
   that can hold it, and mass and each unit's count are conserved except
   where the group creates or destroys
4. keeps the group, or rolls it back whole and records the reason
5. lets components react to the committed events; their groups are the next
   round, up to R rounds, and the rest wait for the next boundary

Every step is in the trace: `lab run marked-nail` prints it.

## Notes on the code

The lab was Objective-C until 2026-11, and was ported to Odin literally:
the same algorithms, in the same order, so every test checks what it did
and every scenario ends in the same state. Its shape still shows it:
objects with reference counts (object.odin), protocols as structs of
procedures, names derived from the old selectors (`world_describe_entity`,
`world_content_build`). AGENTS.md has the rules that keep the output the
same everywhere.
