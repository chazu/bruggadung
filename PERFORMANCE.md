# Performance

## Status and scope

Measurements and proposals, nothing built yet. This document records
where the lab's time goes, on the village (VILLAGE.md), and proposes what
to change while the engine is small enough to change cheaply. The
question it answers: does the engine need a larger refactor now, such as
modelling derived state differentially, or will local fixes do?

The short answer: the physical world already costs almost nothing. The
cost is agents' minds, which redo all of their work from scratch, and the
number of times they run. Two changes deserve doing now, while there are
four topics and not ten:

- **journeys**: a walk to a place as one activity, so a mind isn't asked
  to decide at every tile;
- **incremental interpretation**: knowledge's rules re-run only for what
  changed.

The rest are local fixes. An engine-wide incremental-dataflow framework
isn't needed: the commit model already produces a stream of changes
(events), and the domains are already in closed form.

## Measurements

The village, three days and nights, twelve people, measured at commit
a9858de (after forgetting, KNOWLEDGE.md decision 19). Times are wall
times on an Apple-silicon Mac. The scheduler's own counters
(`Scheduler_Stats`: horizon, domains, commit, perception, decision) are
used, plus temporary timers inside `knowledge_perceive`. macOS `sample`
gave truncated stacks for the Odin binary, so it couldn't attribute time
to callers.

| | Unoptimised (`make`) | `-o:speed` |
| --- | --- | --- |
| Whole run | 60.9 s | 30.0 s |
| Perception | 38.1 s | 14.3 s |
| Decision | 18.0 s | 12.0 s |
| Commit (activities, inputs, commitment) | 4.0 s | 1.6 s |
| Horizons and domains | 0.4 s | 0.1 s |

Both builds end in the same state hash. Counts:

- boundaries: 33,620;
- perceptions: 59,465 (an agent perceiving at a boundary);
- decisions: 60,653;
- events in history: 301,047.

Within perception (`-o:speed`):

| Part | Time |
| --- | --- |
| Interpretation (`knowledge_interpret`) | 10.3 s |
| Recognition | 2.7 s |
| Observations, habits seen in others, traces | 0.2 s |
| Absence and forgetting | 0.15 s |
| The visible set | 0.14 s |
| Everything else | under 0.1 s |

Of the 24,544 activities in a run before forgetting, 23,808 (97%) were
walks of one tile. Nearly every boundary is the end of one.

Forgetting (KNOWLEDGE.md decision 19) took the unoptimised run from
69.4 s to 58.9 s. It cut referents across the village from 790 to 360,
and recognition compares each percept with each referent.

## Findings

1. **The world is cheap; minds are not.** Horizons, domains and commit
   are 6% of the optimised run. Perception and decision are 88%.
2. **Interpretation re-derives everything at every perception.** It runs
   every rule in content over every referent. For each, it:
   - reads the rule's metadata again through `tri.at` (which parses its
     path) and `tri.print`;
   - looks up the existing finding with a linear search;
   - checks each premise.

   One premise kind, the usual place (`know_usual_place`), is quadratic
   in observations, but costs only 0.7 s. Most of the 10.3 s is rereading
   rules that never change, for referents whose evidence hasn't changed.
3. **Decisions re-parse Triangle text.** `agency_match_supposing` builds
   descriptions as text and parses them back (`tri_value` →
   `parse_expr_string`) for every match. A decision also runs a path
   search for every tile walked.
4. **Recognition is percepts × referents**, each pair unified with
   Triangle. Forgetting halved the referents; an index by seen kind would
   cut most of the rest.
5. **History grows without bound.** 301,047 events in three days. About
   24,000 activities are created and ended, each with about ten field
   changes. Three weeks of farming would be about two million events, all
   saved: the village's save is already 323,000 lines.
6. **The default build is unoptimised.** `make` and `make check` run Odin
   at `-o:minimal`. `-o:speed` halves the time, with the same hashes.

## Why walking makes a mind work at every tile

An agent walks by repeating a `walk_north`, `walk_south`, `walk_east` or
`walk_west` activity (actions.tri's `#Walk`): one tile, one second.
`agency_walk` chooses each tile by a path search toward the target, and
starts that one-tile activity. The intention isn't "go to the woodpile"
but "take the next tile toward the woodpile", over and over.

The design already says when a mind decides: an intention is
reconsidered only at a **decision point** (AGENCY.md decision 4), and a
decision point is an activity completed, suspended or failed, or a
**soft interruption** (ACTIONS.md §5). Because each walk ends after one
tile, every tile is a completed activity, so every tile is a decision
point. At each one the walker:

- perceives, because its own move concerns it (it sees new tiles);
- interprets, re-running every rule over every referent;
- decides: weighs its goals, matches its methods' conditions, and runs a
  path search of up to 4,096 tiles, to choose one tile.

A woodcutter walking forty tiles to the woods does that forty times. The
reasons were simplicity and responsiveness: re-deciding at every tile
means a walker reacts at once to what it sees, and replans over ground it
discovers as it goes (TERRAIN.md decision 7: unseen tiles are guessed
open, and a solid one is found on the way).

Responsiveness doesn't need deliberation at every tile. A person walking
home is not choosing each footfall, and only something salient makes them
stop and think: a wall where they expected a gap, someone calling their
name, a sudden hunger. The engine already has the parts for this:

- **Stages and checkpoints** (ACTIONS.md §5): one activity with many
  stages, each committing its effect when it completes. A stage ending
  isn't a decision point; the activity ending is.
- **Hard interruption**: a requirement failing (the next tile turns out
  solid, the legs no longer work) suspends or fails the activity, which
  is a decision point.
- **Soft interruption**: salience past the interruption threshold
  (AGENCY.md §10), a need crossing a band, a commitment's window opening:
  these already wake a mind by themselves.

So walking should be a **journey**: one activity toward a place, its way
found once when it starts, with a stage per tile. Each stage moves the
walker one tile and commits the move, so the world, and everyone who sees
the walker, sees it move as now. The walker still perceives at each tile:
it sees new things. But it decides only when it arrives, when the way is
blocked (and it plans again), or when something it perceives or feels is
salient enough to interrupt.

Impairment fits the same model. A drunk or exhausted walker might
interrupt more readily (a lower threshold), or fail a stage's
requirement (stumble), so it has more decision points, not fewer. The
model decides how often a mind is needed, by the state of the body and
the world, not by the clock.

## Proposed decisions

1. **Journeys** (above). A walk to a place is one activity with a stage
   per tile and a way found when it starts. It is a decision point only
   when it ends: arrived, blocked (a tile believed open is solid: found
   again from there, or given up), or interrupted. A soft interruption
   arises from what the walker perceives or feels, not from the walk.
   Expected: most of the decisions made while walking go, and most of
   the path searches with them. Boundaries stay, one a tile.
2. **Interpretation is incremental.** Rules are compiled once, when
   content loads: premise kinds, their arguments, what they conclude, and
   the expertise they need. A rule is weighed again for a referent only
   when its evidence changed since it was last weighed: the referent was
   perceived differently, a trace on it appeared or went, an observation
   about it was added, or a fading premise's wake fell due. This is
   differential computation on a small scale: findings are a view over
   referents, maintained from the changes perception makes.
3. **Agency parses once.** Method and goal conditions are kept as
   Triangle nodes, not rebuilt from text at each match. Referent
   descriptions are parsed once per change (knowledge already caches
   parsed text). Re-matching a goal only when its inputs change is the
   same idea as decision 2, for later.
4. **Recognition is indexed** by seen kind (KNOWLEDGE.md decision 17), so
   a percept is compared only with referents of its kind.
5. **Optimised builds for checks.** `make check` and CI build with
   `-o:speed`. The hashes are the same, so this is a change of build
   flags only.
6. **Measure as a matter of course.** The village prints the scheduler's
   counters when asked, and each slice records them in lab/PLAN.md, as
   slice 10 of VILLAGE.md proposes.

## Open questions

- **Continuous movement.** A journey keeps a boundary per tile. Movement
  in closed form (position as a function of time, as satiety is) would
  remove those too. Perception would then need to work out when a moving
  thing comes into or goes out of someone's sight, as a horizon, and
  everything that reads where someone is mid-journey would compute it.
  That is a larger change across perception, recognition and checks.
  Journeys first; measure; then decide.
- **History.** Whether history is compacted after a time (a snapshot,
  and the events before it dropped), and whether an activity's own
  bookkeeping (status, due, roles) needs to be world events at all.
  Knowledge reads events only from the last perception on, and saves
  hold them all.
- **Detail for minds.** REALITY.md's reduced detail already slows
  agents' cadence; the village keeps everyone at full detail (VILLAGE.md
  decision 1). A mind that interprets incrementally and decides only at
  real decision points may make that unnecessary for a village's size.
- **When a mind looks again.** A perception that makes news makes the
  agent perceive again at the next boundary. During a journey, the
  walker's own change of place shouldn't count as news that asks for a
  second look.

## Terms

| Term | Meaning |
| --- | --- |
| Journey | A walk to a place as one activity: its way found when it starts, a stage per tile; a decision point only when it ends (arrived, blocked, interrupted). Proposed (decision 1). |
| Incremental interpretation | Rules weighed again for a referent only when its evidence changed. Proposed (decision 2). |
