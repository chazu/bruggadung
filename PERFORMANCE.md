# Performance

## Status and scope

Measurements and proposals. Decisions 1 (a walk as one activity, see
"Walks, measured"), 2 (incremental interpretation, see "Interpretation,
measured"), 5 and 6 are built; 3 and 4 are proposals. This document records
where the lab's time goes, on the village (VILLAGE.md), and proposes what
to change while the engine is small enough to change cheaply. The
question it answers: does the engine need a larger refactor now, such as
modelling derived state differentially, or will local fixes do?

The short answer: the physical world already costs almost nothing. The
cost is agents' minds, which redo all of their work from scratch, and the
number of times they run. Two changes deserve doing now, while there are
four topics and not ten:

- **a walk as one activity**: going to a place on foot is one activity,
  so a mind isn't asked to decide at every tile;
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

So going to a place should be one **walk**: one activity, its way
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

## Walks, measured

Built as decision 1 says (AGENCY.md decision 20). The village again,
before (a9858de) and after, by the same counters; a temporary probe also
counted path searches. Both end with all 23 of the village's checks
passing.

| | Before | Walks |
| --- | --- | --- |
| Whole run, unoptimised | 57.2 s | 32.1 s |
| Whole run, `-o:speed` | 27.3 s | 13.3 s |
| Perception (`-o:speed`) | 13.8 s | 9.3 s |
| Decision (`-o:speed`) | 11.6 s | 2.1 s |
| Commit (`-o:speed`) | 1.5 s | 1.7 s |
| Boundaries | 33,620 | 18,262 |
| Perceptions | 59,465 | 37,849 |
| Minds woken (decisions) | 60,653 | 39,037 |
| Deliberations (not busy: goals, methods, a step) | 26,147 | 2,860 |
| Path searches | 30,507 | 832 |
| Events in history | 301,047 | 157,033 |

- **Deliberation fell ninefold, path searches 37-fold.** A walker woken
  on the way is busy: it hears questions and weighs what has arisen, and
  checks its walk, which is cheap.
- **Boundaries nearly halved**, which the proposal didn't expect. A
  one-tile walk took two: one where it completed, and one where the next
  was committed after the walker decided on it. A walk's stages follow
  one another at the boundary where each completes. A tile now takes
  1,000 ms, not 1,001.
- **Events halved**: no activity created, started and ended for each
  tile.
- **832 walks in three days; 32 given up and found again**: 13 because
  a tile ahead was now believed solid, 17 because what the walker went to
  was not where it believed, 2 because it moved. Changes of intention
  mid-walk come through weighing, which puts the walk down itself.
- **Perception is now the cost**: 70% of the optimised run. Decision 2 is
  next.

What changed in behaviour, besides the numbers:

- A walker is busy, so something that arises on the way must beat its
  intention by the interruption cost as well as the margin. Between
  one-tile walks it had needed only the margin.
- A walk's way is any shortest one the search finds, not "the longer
  way first" that each one-tile choice preferred.
- A walk's intention isn't asked whether it is done before arrival. A
  worker going to peer at a nut walks all the way, though it may see the
  nut plainly a tile or two short. See the open questions.
- Saves carry a walk: the activity its way and stage, the mind what it
  set out for.

## Interpretation, measured

Built as decision 2 says (KNOWLEDGE.md decision 20), in two steps, each
ending in the same hashes for every scenario. The village at
`-o:speed`, by `lab run village --counters`:

| | Walks | Rules read once | Weighed only when changed |
| --- | --- | --- | --- |
| Interpretation | about 6.3 s (not timed: perception fell by 3.0 s) | 3.3 s | 0.5 s |
| Perception | 9.3 s | 6.3 s | 3.5 s |
| Whole run | 13.3 s | 10.5 s | 7.7 s |

Unoptimised, the whole run is 20.2 s (from 32.1 s with walks, and 57.2 s
before them).

- **Reading rules once.** Interpretation re-read every rule from content
  (`tri.at`, which parses a path, and `tri.print`) for every referent at
  every perception, several times a premise. The rules are now read when
  interpretation first runs, into plain structures.
- **Weighing what changed.** The store marks a referent when a trace it
  bears comes or goes, an observation of it is added or let go, or a
  finding about it is drawn or retracted; interpretation compares each
  referent's looks (a hash of its kind, features and place) with how they
  were. Of the 1.78 million pairs of a rule and a referent in the run,
  about 94% are skipped.
- **The misprint was most of what remained.** A misprint reads every
  referent's description as memory fades it, so its rule is weighed for
  every referent every time, and each weighing described every referent:
  2.4 s of 2.7 s. Memory generalizes what it knows key by key and never
  adds a key, so a referent whose kind and features don't mention a claim
  can't be a misprinted copy, and one that doesn't mention a seal can't
  be the seal. Checked first, the rule costs 0.2 s, and says the same.
- **Checked, not assumed.** The tests weigh every pair interpretation
  skips and fail if any would have concluded or retracted something; so
  did one run of the whole village. Breaking the marking on purpose (not
  marking a referent when an observation of it is added) fails the trace
  tests, naming the pairs.

Now: perception 3.5 s, decision 2.2 s, commit 1.7 s. Of perception, what
isn't interpretation (recognition, the visible set, absence, traces) is
the next to measure; recognition was 2.7 s (decision 4).

## Proposed decisions

1. **A walk is one activity** (above; built, AGENCY.md decision 20).
   Going to a place on foot is one activity with a stage per tile and a
   way found when it starts. It is a decision point only
   when it ends: arrived, blocked (a tile believed open is solid: found
   again from there, or given up), or interrupted. A soft interruption
   arises from what the walker perceives or feels, not from the walk.
   Expected: most of the decisions made while walking go, and most of
   the path searches with them. Boundaries stay, one a tile.
2. **Interpretation is incremental** (above; built, KNOWLEDGE.md decision
   20). Rules are read once, when interpretation first runs: premise kinds, their arguments, what they conclude, and
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
5. **Optimised builds for checks** (built). `make check`, and so CI,
   builds its own lab with `-o:speed` (`build/<platform>/speed/lab`) and
   runs the tests and scenarios on it; `make` and `make test` stay
   unoptimised, for debugging. The hashes are the same. On the Mac, the
   tests and scenarios take 44 s, from 1 min 45 s, and the optimised
   compile 12 s more.
6. **Measure as a matter of course** (built). `lab run village
   --counters` prints, on stderr, the scheduler's boundaries and phase
   times, and the events, perceptions, decisions (minds woken),
   deliberations (decisions not busy, which choose a way) and path
   searches. The run's own output, and its hash, are unchanged. Each
   slice records them in lab/PLAN.md, as slice 10 of VILLAGE.md
   proposes.

## Open questions

- **Continuous movement.** A walk keeps a boundary per tile. Movement
  in closed form (position as a function of time, as satiety is) would
  remove those too. Perception would then need to work out when a moving
  thing comes into or goes out of someone's sight, as a horizon, and
  everything that reads where someone is mid-walk would compute it.
  That is a larger change across perception, recognition and checks.
  Walks first; measure; then decide.
- **History** (settled: KNOWLEDGE.md decision 21). An activity's timing
  is a debug field, not logged; a walk's tiles before its arrival are
  diagnostic, compacted after a day into digests. The village's three
  days: 157,033 events, now 62,169, of which 32,861 are kept at the end
  (29,308 digested, in 84 digests); its save, 160,503 lines, now 36,416.
  Over weeks, history grows by about 6,000 events a day (what has a
  bearing on the world), plus a day or two of diagnostic ones. Segmenting
  history by region, and rotating it out of memory, is for a larger
  world.
- **Detail for minds.** REALITY.md's reduced detail already slows
  agents' cadence; the village keeps everyone at full detail (VILLAGE.md
  decision 1). A mind that interprets incrementally and decides only at
  real decision points may make that unnecessary for a village's size.
- **Done before arriving.** A walker doesn't ask whether its intention is
  done until it arrives. Asking at each perception would cost a
  condition's match per tile, which walks removed. Asking only when the
  perception made news about what the intention concerns may be cheap
  enough.
- **Journeys.** Travel by any means: walks, and rides on a coach or a
  ship, as legs of one journey that agency plans, perhaps across regions
  and levels of detail. The word is reserved for it (GLOSSARY.md); a walk
  is one leg on foot. A ride would be an activity like a walk, its stages
  the conveyance's, the rider carried.
- **When a mind looks again.** A perception that makes news makes the
  agent perceive again at the next boundary. During a walk, the
  walker's own change of place shouldn't count as news that asks for a
  second look.

## Terms

| Term | Meaning |
| --- | --- |
| Walk | Going to a place on foot as one activity: its way found when it starts, a stage per tile; a decision point only when it ends (arrived, blocked, given up). Built (decision 1; AGENCY.md decision 20). |
| Journey | Travel by any means, in legs (walks, rides). Reserved, not built (open questions). |
| Incremental interpretation | Rules weighed again for a referent only when what their premises read of it changed. Built (decision 2; KNOWLEDGE.md decision 20). |
