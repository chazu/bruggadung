# Systems at each level of detail

## Status and scope

What each system does at each level of detail (REALITY.md decisions 1, 4,
11 and 13), how content says so, and how far Triangle can express it. This
is a draft: nothing here is built. It expands REALITY.md step 5 (abstract
progression) and is the design that step is to be built from.

In scope:
- how content declares, per kind of thing and per level, which systems run,
  how, or not at all
- each system the lab has (perception, decision, needs, activities, heat,
  air, water, light, traces, wear, law, bonds, work), and two it needs (news,
  and the condition of places), at full, reduced, abstract and frozen
- the forms authored progression takes, and for each, what Triangle can
  compute and what the engine must
- what this needs that the lab doesn't have yet, and the first slice to
  build

Out of scope: threads (REALITY.md step 6), outdoor plumes (step 7), and the
design of rumour proper (how news distorts beyond generalising, who hears
first), which wants a document of its own.

## Decisions so far

1. **A regime per kind of thing.** Content declares, per kind and per level
   below full, a mode for each system. Regimes are a family of instances,
   each with a pattern saying what it `applies` to. Where several apply, the
   most specific wins, field by field: Triangle decides which pattern is
   more specific by subsumption, so a smith's regime overrides an agent's
   for the fields it sets, and the agent's holds for the rest.
2. **Regimes are resolved per blueprint, at load.** A regime's `applies`
   reads only fields content fixes (a kind, a trade), never state that
   changes, so the regime of each blueprint is worked out once, at load, and
   nothing evaluates regimes per entity per tick.
3. **Five modes.**

   | Mode       | Meaning                                                                             |
   |------------|-------------------------------------------------------------------------------------|
   | `exact`    | Runs as at full detail.                                                             |
   | `coarse`   | Runs, on a cadence or with its own senses only (REALITY.md step 3).                 |
   | `progress` | Replaced by the authored bulk progression.                                          |
   | `deferred` | Doesn't run; caught up, on rising, for the time that passed (REALITY.md step 4).    |
   | `paused`   | Doesn't run, and that time is lost: on rising it resumes as though none had passed. |

   `deferred` and `paused` are both "suspended" and behave very
   differently: a deferred fuse has burnt down when the player arrives; a
   paused one is as they left it. `paused` is for gameplay: content chooses,
   per system.
4. **Continuous change is read, not stepped.** A field that moves
   continuously at a level (hunger rising, a room cooling, a part wearing)
   is kept as a value, the time it was so, and the regime that moves it;
   reading it computes it for now. Far away it costs nothing until read.
   Hunger already works this way (`BGSatiety`: `fed`, `fedAt` and a
   period).
5. **Discrete change goes on the wake queues.** A threshold crossed (a
   household starving, a pump breaking) and a periodic operation that
   changes other things (a day's work, a wage paid) is a wake on the queues
   step 1 built (`BGWakes`), applied when it falls due. Nothing far away
   does work each tick.
6. **Triangle declares; the engine evaluates.** Triangle says what
   progresses, how, under what condition, with what chance, and computes
   what its arithmetic can (rates, thresholds, coefficients). The engine
   clamps, takes exponentials, counts periods, and solves what couples.

## The shape in content

A sketch, not yet checked against the loader:

```
#Mode:    "exact" | "coarse" | "progress" | "deferred" | "paused"
#Systems: { perceive: #Mode, decide: #Mode, act: #Mode, needs: #Mode,
            heat: #Mode, air: #Mode, water: #Mode, wear: #Mode, news: #Mode }
#Regime:  { applies: #Thing, reduced: #Systems, abstract: #Systems, frozen: #Systems }

agent_regime: #Regime & {
    applies:  #Agent
    abstract: { perceive: "paused", decide: "progress", needs: "progress", act: "progress" }
} @family(regimes)

smith_regime: #Regime & {
    applies:  #Agent & { trade: "smith" }
    abstract: { act: "progress" }
} @family(regimes)
```

The progressions a `progress` mode engages are declared beside it, in the
four forms below.

Where they go (lab/content/README.md): a progression, and a regime for one
topic's things, go in that topic's directory, beside what the topic does at
full detail, and its files' cut points say what each level of detail
changes. A regime for every agent, or every thing of a kind, goes at the
content root, in `reality.tri`.

## The systems, level by level

The first nine exist; the last two are new.

| System | Full | Reduced | Abstract | Frozen, and rising |
| --- | --- | --- | --- | --- |
| **Perception, memory** | exact | own senses (built) | none; memory's fading is already reckoned from timestamps | deferred; caught up for free (built) |
| **Decision** (goals, methods) | exact | on a cadence (built) | replaced by a **schedule** (where it is by hour: home, work, the tavern) and an authored routine | deferred; decides at once on rising (built) |
| **Needs** (hunger, cold, stuffy, tired) | exact | exact | hunger is a rate, paired with a routine ("eats from the larder daily, the larder one less"), or everyone far away starves | caught up through the same closed form |
| **Activities** | exact | at full pace (built) | on falling: finished, suspended or aborted, as the operation declares | wait; a stage overdue ends on rising (built, crude) |
| **Heat** | exact | longer steps (an explicit solver goes unstable, so the step is capped) | per room: an exponential approach to a steady state, a lit stove a constant input | the same closed form over the gap |
| **Air, CO₂** | exact | longer steps | per room: its occupants (by schedule) breathing against its leak, toward a steady state | the same |
| **Water** | exact | longer steps | stores drain at their rate (linear, stopping at empty); what spills is a stock of the room's | the same; on rising, the room's stock is spread over its tiles |
| **Light, traces** | exact | exact | nothing: light is a function of the time; traces already fade by timestamp (with no foot traffic far away) | nothing to do |
| **Wear** (latent parts) | per use | per use | a wear rate for machines in daily use; reaching `worn_through` is an event ("the pump broke") | caught up through the closed form |
| **Law, bonds, work** | exact | exact | sentences count down; loyalty drifts toward a baseline; wages are paid each shift as a periodic transfer (unpaid, loyalty falls) | caught up by periods |
| **News** (new) | utterances, agent to agent (built) | only what is said to it | held by **communities**, moving between them along routes, with a delay; distorted by generalising | arrivals are the time it happened plus the delay, so catching up is arithmetic; a risen agent is told what its community heard |
| **Condition of places** (new: disrepair, larders) | none: a place is its things | the same | a `condition` rate: falling unoccupied, rising maintained | on rising, the condition is **settled into things**: rubble, a broken shutter, dust |

## The forms of progression, and what Triangle can do with each

### 1. A rate on a field (linear)

Triangle can do it, but for clamping.

- Its arithmetic carries units, so `{ by: 5, per: 1h }` over an elapsed time
  is a sum and a scaling. There is no per-time quantity kind, so a rate is
  written as a `by` and a `per`, which needs no change to the language.
- It narrows constraints backwards through scaling by a constant, so it can
  also solve **when** a field crosses a threshold: the wake for an abstract
  thing ("starving at 14:00", decision 5), with nothing ticking.
- **The gap:** a result outside a field's bounds makes unification fail; it
  doesn't clamp. The engine clamps to the field's declared bounds, which
  every field already states (`loyalty: int & >=0 & <=100`).

### 2. An approach to a level (exponential, or along a curve)

Triangle can't evaluate it: it has no exponentials, and no min or max.
Triangle declares the shape and the engine evaluates it, one of three ways:

- **`toward`:** a target and a half-life.
- **`curve`:** a piecewise-linear curve over the elapsed time, in the form
  the consideration curves already take.
- **`@fn(...)`:** a named code function, the existing way out
  (CONTENT_LANGUAGE.md §5).

Triangle can still derive the coefficients: a room's time constant is
`heatCapacity / toAir`, a quotient computed forward, which it supports.

### 3. A periodic operation (a day at the forge, a wage, a meal from the larder)

Half Triangle, half engine.

- **Triangle:**
  - what it applies to: a pattern, matched as methods' `pre` are
  - its condition
  - a chance per period, drawn deterministically: the existing per-point
    seed (CONTENT_LANGUAGE.md §7), with the period's index in its path
- **The engine:**
  - **counting the periods:** `min(periods elapsed, iron ÷ 2)`, since
    Triangle has neither `min` nor loops. Where the effects are linear and
    the condition holds throughout, all the periods are applied in one
    step; else period by period.
  - **a coarse effect vocabulary.** Today's `#Effect` names code that moves
    objects ("take", "put_in"); abstract things change fields and stocks
    instead (REALITY.md decision 11): `{ role: "smithy", field:
    "horseshoes", by: 8 }`. A small new declarative vocabulary.

### 4. A change of grain (news, money and stocks, a place settled into things)

Triangle fits these best.

- **News distorts by generalising** along the type hierarchy: "a smith in a
  blue coat" becomes "a man". Memory's decay already generalises along
  primary parents (KNOWLEDGE.md). Which news travels is a pattern over a
  `#Telling`: a death travels, a coat's colour doesn't.
- **Routes with delays summed** are the reachability example of Triangle's
  own definite clauses (CONTENT_LANGUAGE.md §10). That serves only small
  route graphs: clauses enumerate solutions and can't take a minimum, so a
  large network of routes wants a shortest-path search in engine code, as
  pathfinding is.
- **Settling a condition into things** is constructing from blueprints,
  with seeded variation, so which shutter breaks is deterministic, and the
  same in a game saved and resumed.

### In short

| Triangle can | The engine must |
| --- | --- |
| declare regimes, with specificity by subsumption | clamp to bounds |
| compute linear rates, with units | evaluate exponentials and curves |
| solve when a linear rate crosses a threshold | count periods (`min`), and loop |
| match what a progression applies to, and its condition | apply coarse effects |
| draw chance per period, deterministically | solve what couples (heat, air, occupants) |
| distort news by generalising | find the shortest delays over large route networks |
| reach over small route graphs | |
| settle conditions into things, by seeded construction | |

## What this needs that the lab doesn't have

1. **Abstract presence.** A room's air needs who is in it; rising needs a
   place to put an agent; a witness must be somewhere. A **schedule**
   saying where an abstract agent counts as being (by hour, and by roles
   bound to its bonds and claims: its employer's site, its home) is what
   most of the abstract column stands on. It is the first piece.
2. **Places as entities.** Rooms are labels found from the terrain.
   Disrepair, larders and communities need an entity to carry their fields:
   a building, a household.
3. **Coarse stocks beside objects.** Money and food are objects at full
   detail and counts at abstract. Falling sums objects into a count; rising
   settles the count back into objects.
4. **Fields read lazily** (decision 4): every reader of a progressed field
   goes through an accessor that computes it for now, since the committed
   record holds it as of when it was last set.
5. **Coupled systems.** Heat, air and occupants move each other. The engine
   solves each room in closed form with its inputs held constant between
   changes of schedule, stepping segment by segment. Triangle can't help
   here.

## Steps

1. **Regimes, rates read, the schedule, and one periodic operation.** The
   regime family, resolved per blueprint at load; linear rates read lazily,
   with their thresholds as wakes; abstract presence by schedule; one
   periodic operation with coarse effects. Hunger with "eats from the
   larder" covers all four in one scenario: a far-off household that either
   eats or starves, and is right when the player arrives.
2. **Places as entities, and coarse stocks.** Buildings and households;
   objects summed into stocks on falling, settled back on rising.
3. **The domains in closed form.** Heat and air per room toward a steady
   state, water draining, at abstract and over a frozen gap.
4. **News.** Communities, routes, delays, distortion by generalising, and a
   risen agent told what its community heard.
5. **The condition of places.** Disrepair as a rate, settled into things on
   rising.

## Open questions

- **When a regime may read state that changes.** Decision 2 keeps `applies`
  to fields content fixes. A regime chosen by state (a wounded agent
  progressing differently) would need regimes resolved again when the
  entity is touched; deferred until a scenario needs it.
- **Commitments falling due while abstract.** A promise between two
  abstract parties could settle by an authored rule (kept or broken by a
  draw weighted by honesty, its bond changed accordingly); one to a party at
  full detail, late on rising. Content's choice, per kind of commitment.
- **How rumour distorts beyond generalising, and who hears first.** As
  REALITY.md's open question on news.
