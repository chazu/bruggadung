# Domain Simulation

## Status and scope

Proposal. This document names and specifies the system sketched in
[DESIGN.md](DESIGN.md) §3, "Specialized simulations and shared time". It
records the decisions made so far, proposes the domain contract, and defines
three scenarios to test that contract before implementation.

**Domain simulation** is the layer that evolves physical and quasi-physical
quantities over time: heat, gas, water, power, and later infection, decay, and
similar processes. Each **domain** owns one family of quantities and the
algorithm that advances them. A shared scheduler advances all domains along
one simulation clock.

Out of scope here, except where they touch domains: the action and activity
lifecycle (§1), the component model (§2), latent physical assembly (to get its
own document), and perception (§4).

Influences: Space Station 13's atmospherics (domain-wide aggregates, sleeping
regions, controlled exchange order), Caves of Qud's object parts (entity
composition), and Dewdrop (bindings, lagged cross-domain coupling, per-step
contribution reset). See [What we take from Dewdrop](#what-we-take-from-dewdrop).

## Decisions so far

1. **Domains are distinct from the component model.** Components describe
   what an entity is and what it takes part in. Domains describe how a
   quantity evolves across the world. A component joins a domain by declaring
   it; the domain then owns that component's dynamic quantity.
2. **Conserved stocks live on entities and tiles.** Domains merge them into
   working aggregates for computation and write them back on split, save, and
   other check-in points. Domain structures are rebuildable caches.
3. **Integer stocks, fixed-point coefficients.** Conserved quantities are
   integers counted in a fixed quantum per quantity kind. Rates and
   coefficients are fixed point. Fractional flows carry their remainder
   forward. Floating point never touches authoritative state.
4. **Units are tracked.** In code, each dimension is a distinct C struct type,
   checked by the compiler. At data boundaries (content, traces, inspectors,
   saves), runtime unit descriptors convert and label values.
5. **Clock, scheduler, and run policy are separate.** The run policy decides
   when to stop and wait. It never chooses step sizes.
6. **Coupling rule.** Processes that are tightly coupled belong in one domain
   and are computed together. Domains couple to each other only through
   values read at the start of a step and contributions delivered at the next
   step.

## Terms

| Term | Meaning |
| --- | --- |
| Domain | Owns one family of stock kinds and the algorithm that advances them. Examples: thermal, atmosphere, fluid. |
| Stock | A conserved quantity with a home: 400 L of water in a cistern, 2 MJ of heat in a stove body. |
| Stock kind | The type of a stock: water volume, heat, O₂ amount. Each stock kind is owned by exactly one domain. |
| Holder | The entity or tile that is a stock's home. |
| Participant | A component that joins a domain, such as `ThermalBody` or `Respirator`. It supplies parameters (capacity, conductance, rates) and identifies its holder's stocks. |
| Structure | A domain-internal working aggregate built from participants and topology: a connected pipe network, a room's air region, a thermal island. Never an entity, never saved. |
| Checkout | While a structure is active, it holds the authoritative value of the stocks it merged. The holders' records are marked checked out. |
| Check-in | The structure writes its stocks back to their holders, using the stock kind's split rule. |
| Contribution | A typed, unit-carrying, additive input to a domain for one step, tagged with its source for tracing. |
| Transit | Contributions produced in one step and not yet applied by their target domain. Counted in conservation totals. |
| Reservoir | A boundary outside the simulated region, such as the outdoors, with fixed state. Its net exchange is recorded in a ledger. |
| Horizon | A domain's answer to "how far may I advance?": a safe step and a next-event time. |
| Watch | A request, usually from an activity, to be notified when a domain quantity crosses a threshold. |
| Quiescent | A domain or region whose flows are all below its declared settle threshold. It can sleep. |

## Layering

| Layer | Owns | Example: a stove |
| --- | --- | --- |
| Component (§2) | Identity, parameters, discrete state, and which domains it joins | `ThermalBody`, `Combustor`, `FuelContainer`, `Ownership` |
| Domain (this doc) | The algorithm and the dynamic stocks | The thermal domain integrates solid heat. The atmosphere domain moves gas and runs combustion as a reaction inside it. |
| Capability and action (§1) | What a component contributes to an attempt | Lighting the stove needs an ignition capability. It changes `Combustor` state, which wakes the atmosphere domain. |

A component may join no domain at all; `Ownership` is an example. A domain's
participants are always components; a domain never reaches into an entity
except through them.

Discrete per-entity reactions in the style of Qud, such as a projectile hit
applying poison, still exist. They go through change commitment like any
other proposal. They never write domain stocks directly.

## The domain contract

### 1. Declaration

Each domain declares, statically:

- **Stock kinds owned**, each with:
  - quantum and storage width
  - split rule for check-in (by volume, by mass, by heat capacity)
  - settle threshold for quiescence
- **Participant kinds** it accepts, and the parameters it reads from each.
- **Reads** of other domains' values. These are always taken at step start.
- **Contributions accepted** from other domains and from change commitment.
- **Contributions emitted** to other domains.
- **Events emitted**: stock exhausted, threshold crossed, process completed.
- **Invariants**: conservation identities and range limits.
- **Approximation limits**: what the model gets wrong, and when.

### 2. Participation

- A component joins when its entity enters the world or acquires the
  component. It leaves when either goes away. Joining and leaving mark the
  affected structures dirty.
- Dynamic values (temperature, pressure, flow) are read through the domain,
  never cached on the component. Parameters (heat capacity, valve opening)
  live on the component. Changing a parameter wakes the affected region.
- Parts revealed inside an assembly do not join domains while they remain
  inside it. The assembly's aggregate participates for them. A part removed
  from the assembly becomes a standalone entity and joins domains in its own
  right, taking its share of the aggregate's stocks (see Scenario 2).

### 3. Stocks, checkout, and conservation

**At any instant, each stock has exactly one authoritative location.** That
location is its holder while the stock is at rest, and the structure that
checked it out while the stock is active.

- **Checkout** happens when a structure forms or absorbs a holder.
- **Check-in** happens:
  - when a structure dissolves, splits, or merges
  - before a save
  - on an explicit audit
  - when the stock's region goes to sleep
- **Splitting** uses the stock kind's declared rule. Integer remainders go to
  holders in stable entity-ID order. The rule is deterministic and
  independent of iteration order.
- **Who may change a stock:**
  - A stock at rest changes only through a conserving transfer committed by
    change commitment, such as pouring a bucket.
  - A checked-out stock changes only through its owning domain. Anything else
    that wants to change it posts a contribution to that domain.
- **Remainder carries are not stock.** A flow of 2.7 quanta moves 2 and owes
  0.7 on that edge next step. Stocks are always whole quanta. Dropping carries
  when a region sleeps does not break conservation, because nothing
  fractional ever moved.

**Conservation identity**, per stock kind, checked exactly after every step in
debug builds:

```
Σ holders (at rest) + Σ structures (checked out) + Σ transit
  + Σ produced by declared sources − Σ consumed by declared sinks
  − net reservoir exchange
= initial total
```

Sources and sinks are declared processes with integer conversion factors. For
example, combustion consumes fuel mass and O₂ and produces CO₂ and heat in
fixed integer ratios per quantum of fuel. Totals are therefore exact by
construction, not exact within a tolerance.

### 4. Structures

- A structure is derived entirely from participants, topology, and the
  checked-in stocks. It can be rebuilt at any time.
- Topology changes mark structures dirty: opening a valve, removing a wall,
  dismantling a pump. A dirty structure checks in, then rebuilds and checks
  out again, before the next step that touches it.
- Structures are never saved. Saving forces a check-in. Loading rebuilds the
  structures. A rebuilt structure must produce bit-identical results to the
  one it replaced.

### 5. Activation and sleep

- A domain tracks active regions. A region sleeps once all of its flows have
  stayed below the settle threshold for its declared settle interval. Its
  stocks then check in.
- A region wakes on:
  - topology change
  - participant parameter change
  - an incoming contribution
  - a participant joining or leaving
  - a watch registered on a quantity inside it
- A fully asleep domain has an infinite horizon and costs nothing per step.

### 6. Horizons

Before each step, every active domain reports a horizon:

- **`safeStep`:** the largest step for which its method stays stable and
  within its declared accuracy. Cross-domain couplings also cap it; see
  [Coupling](#7-coupling).
- **`nextEvent`:** the earliest time at which it might emit a discrete event.
  This includes stocks running out, watched thresholds being crossed, and
  processes completing.

`nextEvent` must be conservative: never later than the true event time.
Domains predict it using the step-start inputs, which stay fixed for the whole
step. If the event hasn't happened by the predicted boundary, the domain
predicts again from closer in. The **event tolerance** is the maximum delay
between a crossing and the boundary that reports it. Each domain declares it
and must keep to it.

A domain may run internal substeps or use implicit or analytic methods within
a scheduler step. Neither is visible to the scheduler.

### 7. Coupling

- **Within a domain:** processes are computed together, in whatever way the
  domain chooses. Fire consuming O₂ and ventilation replenishing it are both
  in the atmosphere domain for this reason.
- **Between domains:**
  - A domain reads other domains' values from a snapshot taken at step
    start.
  - Contributions it emits during step [t₀, t₁] are held in transit and
    applied by the target domain during [t₁, t₂].
  - A domain never sees another domain's mid-step state.
- **Consequences of this rule:**
  - Domain execution order within a step cannot affect results.
  - Domains could run in parallel.
  - Every cross-domain effect lags by one step. A coupling declares the error
    that lag introduces; for heat exchange, that is the transfer per step
    relative to the temperature difference. Both coupled domains cap
    `safeStep` to keep that error within bounds.
  - If a coupling needs very small steps to stay accurate, that is a sign the
    two processes belong in one domain.

### 8. Contributions and proposals

- Contributions are typed with units, additive, and tagged with their source.
  The target domain accumulates them per step and resets the accumulator at
  the start of each step. Without the reset, contributions from earlier steps
  would keep adding up (Dewdrop's "stress epoch" lesson).
- **Demand exceeding supply** within a step is resolved by the domain's
  declared allocation rule. That rule must not depend on iteration order. The
  default is pro rata by requested rate, with integer remainders given out in
  stable-ID order, rotated by step index so that no participant gains on
  average.
- **Domains allocate divisible stocks only.** Indivisible items, such as a
  single spare part, are entities. Conflicts over them are resolved by change
  commitment in the action system ([ACTIONS.md](ACTIONS.md) §9). They are
  never domain stocks.
- **Changes to non-domain state** go through change commitment
  ([ACTIONS.md](ACTIONS.md) §8–11) at the step
  boundary as proposals. An example is a combustor going out, which turns its
  `lit` state off.

### 9. Scheduler

```
loop:
    t     ← clock.now
    bound ← min(policy.stopTime, inputs.nextTime, activities.nextCompletion)
    for each active domain d:
        h     ← d.horizon(t)
        bound ← min(bound, t + h.safeStep, h.nextEvent)
    snapshot ← read values of all active domains at t
    for each active domain d (any order):
        d.advance(t → bound, snapshot, inbox[d]) → outbox, events, trace
    move outbox into next step's inboxes (transit)
    commit events and proposals (change commitment)
    rebuild dirty structures; update wake and sleep
    clock.now ← bound
    if policy says wait: block for input
```

Step boundaries come only from:

- domain horizons
- activity completions
- input times
- stop requests from the run policy

A stop request, such as wall-clock pacing or a pause, inserts a boundary and is
recorded in the replay log. Apart from those recorded boundaries, the step
sequence depends only on world state.

### 10. Observation and traces

- **Developer inspector:** reads authoritative values through the domain, plus
  the conservation ledger, horizons, and wake state.
- **Player view:** reads only through perception. Domains expose measurement
  reads ("air at this tile", "surface temperature of this entity"), and
  perception applies its own limits and noise to them. A domain never formats
  information for the player directly.
- **Causal traces:** each step records, per domain:
  - stock deltas with their causes (contribution source, topology change,
    internal process)
  - events emitted
  - the horizon that bounded the step

  Traces are what let the developer inspector answer "why is this room
  cold?"

### 11. Save, load, and determinism

- A save checks in every stock and records holders, component state, carries
  that were not dropped, transit, ledgers, watches, and RNG state.
- **Determinism:** the same initial state, seed, and input log reproduce a run
  bit for bit. The input log records commands and stop boundaries with their
  simulation times.
- **Randomness:** each domain derives random streams per participant or per
  region from the world seed plus stable IDs. It never draws from one shared
  stream in iteration order. Dewdrop's per-unit seed derivation is the model.

### 12. Numbers and units

- **Stock storage:** `int32_t` for per-tile and per-participant stocks, which
  keeps grids small and SIMD-friendly. `int64_t` for aggregates that need the
  range.
- **Arithmetic:**
  - Coefficients are fixed point, with `__int128` intermediates for 64-bit
    products.
  - No division in inner loops; precompute reciprocals.
  - Transcendental functions use lookup tables.
- **Overflow** is asserted in debug builds and never wraps silently. Quanta
  and widths are chosen so that declared ranges fit.
- **Units in code:** one struct type per dimension, with conversion functions
  only for physically meaningful combinations.

```c
typedef struct { int32_t q; } BGHeat;       // quantum declared per kind
typedef struct { int32_t q; } BGGasAmount;
typedef struct { int64_t ms; } BGTime;

static inline BGHeat BGHeatAdd(BGHeat a, BGHeat b);
static inline BGTemp BGTempFromHeat(BGHeat h, BGHeatCapacity c);
```

- **Units at boundaries:** a descriptor per quantity kind records its
  dimension, quantum, and display unit. Content can say `2.5 kg` and gets
  converted on load. Traces and inspectors print `2.5 kg`. Saves record each
  quantity's quantum.

Initial quanta to test in the scenarios. These are starting points, not
commitments:

| Quantity | Kind | Quantum | `int32_t` range | Notes |
| --- | --- | --- | --- | --- |
| Heat | stock | 100 J | ≈ 2×10¹¹ J | A tile of air at room temperature holds about 10⁴ quanta |
| Mass | stock | 1 g | ≈ 2,100 t | Fuel, solids |
| Gas amount | stock | 1 mmol | ≈ 2×10⁶ mol | A tile of air is about 10⁵ quanta |
| Water volume | stock | 1 mL | ≈ 2,100 m³ | |
| Temperature | derived | 0.01 K | | Computed from heat and capacity. Never a stock. |
| Time | clock | 1 ms | `int64_t` | |
| Length | content | 0.1 mm | | Wrench sizes come in half millimetres (CONTENT_LANGUAGE.md) |
| Force | content | 1 mN | | |
| Torque | content | 1 mN·m | | |

The descriptors, with each quantity's exponents over the base units, live in
one table (`triangle/src/units.c`); content arithmetic derives its products
from them, and the engine's unit structs will be generated from it.

### 13. Interface sketch

Illustrative only; this has not been compiled. `BGHorizon` holds a `safeStep`
and a `nextEvent`.

```objc
@protocol BGDomain
+ (BGDomainDeclaration *) declaration;

- (void) participantJoined:(BGParticipant *) p;
- (void) participantLeft:(BGParticipant *) p;
- (void) topologyChangedInRegion:(BGRegion) r;

- (BGHorizon) horizonAt:(BGTime) t;
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
            snapshot:(BGSnapshot *) others
               inbox:(BGContributionBatch *) inbox
              outbox:(BGContributionBatch *) outbox
              events:(BGEventSink *) events
               trace:(BGTraceSink *) trace;

- (void) registerWatch:(BGWatch *) w;
- (void) checkInAll;
- (BOOL) isQuiescent;
@end
```

The protocol stays at the boundary. Inner loops are plain C over the domain's
own arrays, so steps don't send an Objective-C message per participant.

## Scenarios

Each scenario lists its purpose, setup, sequence, the player's choices and
uncertainty, observable information, and acceptance checks against the
contract. Numbers are illustrative.

### Scenario 1: The unattended stove

**Purpose:** large time jumps, coupling within and between domains, sleep and
wake, exact conservation across a combustion process, and watches that
interrupt an activity.

**Setup**

- A 4×5-tile room with stone walls and floor, a closed door with a gap
  connecting it to a larger corridor region, and a stove.
- **Stove components:**
  - `ThermalBody`: an iron body, roughly 45 kJ/K heat capacity
  - `FuelContainer`: 3 kg of wood
  - `Combustor`: a `lit` flag, a damper setting, and burn-rate limits
  - `Duct`: a flue from the firebox to the outdoors
- **Outdoors:** a reservoir at 275 K with fixed air composition.
- **Character components:**
  - `Respirator`: consumes O₂ and emits CO₂ at a rate set by activity level
  - `ThermalBody`: body heat

**Domains**

- **Atmosphere** owns gas amounts by species and the heat carried by gas, for
  tiles, the firebox, and the flue. Combustion is a reaction inside it. While
  the stove is lit, the domain checks out the fuel stock. The reaction
  consumes fuel and O₂ and produces CO₂ and gas heat in fixed integer ratios.
- **Thermal** owns the heat of solids: the stove body, wall and floor tiles,
  and the character's body.
- **Atmosphere ↔ thermal:** surface heat exchange between gas and solids is a
  cross-domain coupling through contributions. Gas carries its own heat
  because moving air moves heat, which is tight coupling and belongs inside
  one domain. Gas-to-solid exchange is slower and can tolerate the one-step
  lag. This split is a hypothesis this scenario tests.

**Sequence**

1. The player lights the stove, an action in §1. `Combustor.lit` becomes true,
   and the firebox region wakes.
2. The player rests for 8 hours. Resting is an activity with watches:
   - wake if the air temperature at the character's tile leaves a comfort
     band
   - wake if CO₂ there exceeds a stuffiness threshold
   - wake when 8 hours have passed
3. Expected phases:
   - warm-up: short horizons
   - steady burn: longer steps
   - fuel nearly gone: `nextEvent` predicts exhaustion and becomes a step
     boundary
   - fire out: proposal `lit ← false`
   - cool-down and equalization
   - sleep: both domains are quiescent, and the scheduler jumps to the end of
     the rest

**Variants**

- **A, flue open:** a steady burn. The room warms and CO₂ stays low.
- **B, damper left closed:** flue gas leaks into the room. Room O₂ falls,
  burning becomes limited by O₂ and smoulders, and CO₂ rises. The stuffiness
  watch interrupts the rest.
- **C, same as A but stepped:** the player takes 480 one-minute steps instead
  of one 8-hour rest.

**Choices and uncertainty**

- The player chooses the damper setting, how much fuel to load, whether to
  leave the door open, and how long to rest.
- The player does not know the burn time or how airtight the room is.

**Observable information**

- **Player:** warmth (perceived through the character's body), the stove's
  glow and crackle while lit, smoke smell and stuffiness in variant B.
- **Developer:**
  - per-tile gas and heat
  - the conservation ledger
  - the step log with the horizon that bounded each step
  - wake and sleep state

**Acceptance checks**

1. **Exact conservation:** the identity holds after every step, both for
   energy (including heat released by combustion and net exchange with the
   reservoir) and for every gas species and fuel mass.
2. **Time jumps:** variant A's 8-hour rest takes on the order of hundreds of
   scheduler steps, not hundreds of thousands. Once the room equalizes, the
   remaining time passes in one step. Record the step count as a metric.
3. **Run policy:** compare variants A and C.
   - Conserved totals match exactly.
   - Final temperatures agree within the declared tolerance.
   - Each run replays bit-identically from its own log.
4. **Order independence:** shuffling the order domains run in within each
   step leaves results bit-identical.
5. **Watch precision:** in variant B, the rest is interrupted at a boundary no
   later than the event tolerance after the true CO₂ crossing, and never
   before it.
6. **Local wake:** after equalization, opening the door wakes only the room
   and corridor regions of the atmosphere domain. The thermal domain wakes
   only when its contributions arrive.

### Scenario 2: The interrupted pump repair

**Purpose:** topology changes in the middle of an activity, check-in, splitting
and rebuilding structures, a latent assembly interacting with a domain, and
partial-progress state surviving save and load.

**Setup**

- **The water system:** a low sump (holder, 300 L) → a crank-driven piston
  pump → a riser pipe → a raised header tank (holder, 100 L). The header tank
  feeds a trough.
- **The failure:** a "flow loss" failure was committed at hour 300. The pump
  delivers about 20% of its rated flow.
- **The pump's latent assembly schema:**
  - roles: housing, crank, connecting rod, piston, piston seal (leather cup),
    inlet valve, outlet check valve, gland
  - culprit candidates for flow loss: piston seal, inlet valve, outlet valve,
    housing
- **Domain:** fluid. It owns water in the sump, the header tank, pipe
  structures, and puddles on floor tiles. Floor tiles are holders.

**Sequence**

1. The player starts a "dismantle pump" activity with three stages:
   1. Remove the handle and crank pin (5 min).
   2. Remove the cover (10 min). This triggers materialization: the first
      level of internal parts is revealed, using the unit's seed and failure
      history.
   3. Extract the piston (10 min). The piston and its seal become standalone
      entities on the tile.
2. The activity is interrupted at the end of stage 3. Its stage and progress
   persist on the activity, and the pump stays partly dismantled.
3. Extracting the piston is a topology change. The pipe structure checks in,
   the domain rebuilds it, and the open cylinder becomes a new path from the
   riser to the floor tile, through the outlet check valve.

**Variants**

The culprit is decided at reveal by the unit's seed, history, and schema. It
is not chosen by the scenario.

- **Outlet valve is the culprit:** the leaky check valve lets the header tank
  drain back through the open cylinder onto the floor. The rate depends on the
  valve's leak conductance, which comes from its revealed wear. The puddle
  spreads to neighbouring tiles. Later, an NPC finds a wet floor and an empty
  header tank. That discovery is agency, outside this doc, but the trace has
  to support it.
- **Piston seal is the culprit:** the outlet valve holds and nothing drains.
  The worn leather cup is visible on the extracted piston.
- **Cause unresolved:** a schema variant where the failure mechanism has no
  candidate at the revealed level. Inspection shows no culprit at that level,
  and none is invented.

**Choices and uncertainty**

- The player does not know the culprit before opening the pump, so they
  cannot know whether pulling the piston will flood the floor.
- They can drain the header tank first, at the cost of time and water, or
  take the risk.
- An imperfect diagram (from the first integrated lab proposal) may show a
  shutoff cock that is actually on a different branch.

**Observable information**

- **Player:** sounds of running water, a growing puddle, the parts lying
  exposed, and the header tank level if they can see it.
- **Developer:**
  - the structure rebuild events and the check-in split
  - the water ledger
  - the culprit selection and the seed it came from

**Acceptance checks**

1. **Exact water conservation** across every topology change:
   sump + header tank + pipe structures + puddles + transit stays constant.
2. **Deterministic reveal:**
   - Opening at hour 300 or hour 400, with the same failure history, gives the
     same parts, qualities, and culprit. Only the wear split may differ,
     because it reflects the time of reveal.
   - Reloading a save made before opening gives the same result again.
3. **Mass and heat split:** the extracted piston's mass is subtracted from the
   pump's aggregate mass, so no mass is duplicated. If the thermal domain is
   present, the piston leaves with its share of the pump's heat, split by
   heat capacity.
4. **Participation:** internal parts join no domain while they are inside the
   assembly. The extracted piston joins as a standalone entity.
5. **Save mid-interruption:** after save and load, the world shows the same
   state: the cover off, the piston on the floor, the puddle state, and the
   activity resumable at stage 3. The next step after loading is
   bit-identical to the next step in a run that never saved.
6. **No leak through the action menu:** before opening, the available actions
   give no hint of the culprit. This is a §1 check, recorded here because the
   scenario exercises it.

### Scenario 3: Two draws on a dwindling stock

**Purpose:** demand exceeding supply within a step, allocation that doesn't
depend on iteration order, `nextEvent` for stock exhaustion, and the boundary
between allocating divisible stocks and reserving indivisible items.

**Setup**

- A cistern (holder) with 15 L of water, two taps, and a crack leaking
  0.5 L/min onto the floor.
- Agents A and B each start a "fill bucket" activity (10 L bucket) at taps 1
  and 2, at the same simulation time.
- Each tap delivers up to 5 L/min, falling as the head drops.
- **Domain:** fluid.

**Sequence**

1. Both draws and the leak share the cistern's head. Flows come from
   conductances, so most of the scarcity is handled by the physics.
2. `nextEvent` predicts the cistern emptying at about 1.4 minutes. The
   scheduler puts a boundary there.
3. In the final step, the remaining quanta are fewer than the requested
   quanta. The allocation rule applies: pro rata, with remainders given out in
   stable-ID order, rotated by step index.
4. Both activities receive "source exhausted" in the same step. Each bucket
   holds about 7 L, and the floor about 0.7 L.

**Variants**

- **3b:** Agent A starts one minute earlier and gets more water. This is a
  legitimate difference from timing, not from iteration order.
- **3c, the boundary:** a cupboard holds one spare piston seal, and both agents
  intend to take it in the same step. Domains do not arbitrate this. Change
  commitment resolves it ([ACTIONS.md](ACTIONS.md) Scenario 2). The seal is an
  entity, not a stock.
- **3d:** the domain's internal participant order is permuted, for example
  through different hash-map ordering.

**Choices and uncertainty**

- Each agent decides where to fill and when to give up.
- Neither agent knows how much water the cistern holds.

**Observable information**

- **Player:** the water flow from each tap slowing, then sputtering, and how
  full each bucket is.
- **Developer:** requested and granted amounts per participant per step, the
  allocation remainders, and the step bounded by exhaustion.

**Acceptance checks**

1. **Exact conservation:** buckets + puddle + cistern = 15 L, exactly.
2. **Order independence:** variant 3d is bit-identical to the base run.
3. **Fairness:** with equal requests, A and B differ by at most one quantum.
4. **No negative stock:** no step ever drives a stock negative. This is
   asserted.
5. **Simultaneous notification:** both activities receive exhaustion in the
   same step, at the boundary set by `nextEvent`.
6. **Boundary:** in variant 3c, no domain represents the seal. The conflict is
   resolved by change commitment.

## What we take from Dewdrop

| Dewdrop | Domain simulation |
| --- | --- |
| Bindings push component state into a solver and pull results back | Participants supply parameters. The domain owns dynamic values and is read through directly, with no copy-back. |
| One-tick lag between solvers instead of iterating to convergence | Snapshot coupling. Order independence and the option of parallel execution follow from it. |
| Stress epoch resets stale contributions | Per-step contribution accumulators, reset each step |
| Fixed multi-rate tick groups (10 / 1 / 0.1 Hz) | Generalized to per-domain horizons, so the scheduler can jump |
| The same electrical and thermal fields on every component | Per-domain stores holding only the participants |
| Binding registries freeze once ticking starts | Dirty marking and structure rebuilds; topology changes constantly |
| Dense nodal solves (gonum) | Grid stencils for tiles; small dense solves only for device networks |
| Latent anatomy | Kept as a separate system; this doc covers only how it touches domains |
| Sensors and actuators mediate the player | Perception reads domain measurements; the action system mediates control |
| Durable decision journal | Snapshot plus deterministic replay, for now |

## Open questions

1. **Gas heat ownership.** Does the atmosphere domain owning the heat in gas
   hold up, or does gas-to-solid exchange need tighter coupling than one step
   of lag? Scenario 1 tests this.
2. **Large steps in stiff regions.** Explicit integer exchange has a stability
   limit on step size. Should quiet regions use implicit solves or analytic
   relaxation, such as an exponential approach using lookup tables, to take
   long steps?
3. **Region granularity.** For activation and sleep, are regions rooms, fixed
   chunks, or connected components of active tiles?
4. **Watches.** What is the interface between activities and domains? Who
   registers and removes watches, and how does a watch behave across save and
   load?
5. **Tolerances.** What tolerances for run-policy comparison and for event
   timing are acceptable to a player?
6. **Assemblies and multiple domains.** When an assembly takes part in several
   domains, are stocks split per domain when a part is removed, or through one
   shared split rule?
7. **Parallelism.** It is permitted by the coupling rule. Do we want it in
   the first lab, or later?
