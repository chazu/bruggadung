# Architecture

## Status and scope

Overview of the whole framework as currently proposed. [DESIGN.md](DESIGN.md)
sets out the six systems and the development sequence. This document shows
how the specified systems fit together, which rules apply across all of them,
and what remains.

The contracts are proposals, tested by the scenarios in each document. Two
parts are built: the content language's engine ([triangle/](triangle/README.md))
and the first slice of the simulation laboratory ([lab/](lab/README.md)):
entities, component stores, relations, change commitment, and the scheduler,
proven on COMPONENTS.md's first scenario.

## Documents

| Document | Covers | State |
| --- | --- | --- |
| [DESIGN.md](DESIGN.md) | The six systems, ambitions, and development sequence | Proposal |
| [STACK.md](STACK.md) | Language: mulle Objective-C | Decided |
| [DOMAIN_SIMULATION.md](DOMAIN_SIMULATION.md) | §3: domains, stocks, horizons, the scheduler | Contract proposed, 3 scenarios; Scenario 3, and Scenario 1's atmosphere, run in [lab/](lab/README.md) |
| [COMPONENTS.md](COMPONENTS.md) | §2: entities, components, relations, identity on demand | Contract proposed, 3 scenarios; Scenario 1 runs in [lab/](lab/README.md) |
| [ACTIONS.md](ACTIONS.md) | §1: capabilities, actions, activities; change commitment | Contract proposed, 3 scenarios |
| [KNOWLEDGE.md](KNOWLEDGE.md) | §4: history, traces, perception, referents, claims, beliefs, memory | Contract proposed, 3 scenarios; Scenario 3's stale map and menu run in [lab/](lab/README.md), with event perception and claims believed |
| [AGENCY.md](AGENCY.md) | §5: goals, methods, needs, commitments, habits, dispositions, salience | Contract proposed, 3 scenarios; Scenario 1 runs, adapted, in [lab/](lab/README.md) |
| — | §6: institutions | Next |
| — | Latent physical assembly | Not started; hooks exist in COMPONENTS.md §7 |
| [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md) | Triangle, the content language: typed feature structures, TDL semantics, CUE-style syntax, the engine | Contract proposed, 3 scenarios |
| [CHAT.md](CHAT.md) | Original brainstorm. The setting is discarded. | Reference |

## The systems in one view

| System | Owns | Changes state through |
| --- | --- | --- |
| Components (§2) | Entity identity, the ID counter, component fields, relations including location and reified claims, tombstones | Change commitment |
| Domain simulation (§3) | The algorithms and checked-out stocks for physical quantities; derived structures | Advancing during steps; discrete proposals through commitment |
| Actions (§1) | Operations, capability matching, activities, reservations, recipes | Proposal groups through commitment |
| Change commitment (in ACTIONS.md) | Ordering, validation, atomic application, ID allocation, committed events | It is the only writer of shared world state outside domains |
| Knowledge (§4) | History, perception, agents' private knowledge stores (referents, observations, beliefs) | The perception phase writes knowledge stores. Traces and records are world state, changed through commitment. |
| Agency (§5) | Agents' private motivation stores; choosing activities at decision points; salience | The decision phase writes motivation stores. Actions go through activities. |
| Institutions (§6) | Membership, jurisdiction, authority, procedures, recognition of claims | To be specified |

### How they connect

```
              capabilities                      effects + costs
 Components ───────────────►  Actions  ───────────────────────┐
   │   ▲                        ▲                             ▼
   │   │ reactions              │ decision points     Change commitment
   │   └────────────────────────┼─────────── committed events ◄┤
   │ participation              │                              │
   ▼                            │                              │
 Domain simulation ── discrete proposals ──────────────────────┘
   │  watches ──────────────────┘
   │
   └─ measurements ──► Perception (§4) ──► Beliefs ──► Agency (§5)
                                                          │
                       Institutions (§6) ◄── claims ──────┘
                        (authorize, recognize)
```

| Channel | From → to | Defined in |
| --- | --- | --- |
| Participation | Component → domain | DOMAIN_SIMULATION.md §2 |
| Capabilities | Component → action | COMPONENTS.md §4, ACTIONS.md §2 |
| Modifiers | Component → derived value | COMPONENTS.md §4 |
| Reactions | Committed event → component | COMPONENTS.md §4 |
| Contributions | Domain → domain, commitment → domain | DOMAIN_SIMULATION.md §8 |
| Watches | Activity → domain | DOMAIN_SIMULATION.md §5–6, ACTIONS.md §5 |
| Proposals | Every system → commitment | ACTIONS.md §8 |
| Perception | Committed events, state, traces → knowledge stores | KNOWLEDGE.md §5, §14 |
| Knowledge view | Actions and agency → knowledge | ACTIONS.md §3, KNOWLEDGE.md §13 |
| Decision | Decision points → agency → activities | AGENCY.md §3, §12 |
| Salience | Agency → perception | AGENCY.md §10, KNOWLEDGE.md §5 |
| Authorization | Actions → institutions | ACTIONS.md §3; stubbed |

## The life of one boundary

Everything happens on one simulation clock. One scheduler step, end to end:

```
1. Bound the step
   bound ← min(run-policy stop, next input,
               activity stage completions and checkpoints,
               each active domain's safeStep and nextEvent)

2. Advance domains to the bound
   each domain reads a snapshot of the others at step start,
   applies its inbox, and advances its checked-out stocks;
   its outbox goes into transit for the next step

3. Commit at the bound (repeated for up to R rounds)
   gather groups: domain proposals, activity stage completions,
                  checkpoints, interruptions
   order: process phase, then action phase, then system phase;
          seeded permutation within each phase
   validate and apply one at a time; reject with reasons
   allocate IDs; emit committed events
   reactions → groups for the next round

4. Housekeeping
   rebuild dirty structures; update wake and sleep
   recheck activity bindings; evaluate watches
   deliver rejections

5. Perception phase (KNOWLEDGE.md §14)
   event, state, and trace perception for this boundary
   immediate interpretation within attention budgets
   belief updates; salience raises soft interruptions
   raise decision points

6. Decision phase (AGENCY.md §12)
   the player's decision point → input, or autopilot
   other agents' decision points → agency chooses
   new activity starts commit at this same boundary

7. clock ← bound
```

Steps are as long as horizons allow. A quiet world jumps; a busy one takes
small steps. The run policy only adds stopping points. It never sets step
size.

## Rules that apply everywhere

### Determinism

- A run is reproduced bit for bit by its initial state, world seed, and input
  log. The log records commands and stop boundaries with their simulation
  times.
- **No iteration in hash order.** Stores iterate by ID. Domains break ties by
  stable ID, rotated by step index. Commitment orders groups by seeded
  permutation.
- **IDs come from a counter, in commit order.** Anything that must not depend
  on order derives from seeds: per-unit hidden qualities, per-participant
  random streams.

### Numbers and units

- **Conserved stocks are integers** counted in a quantum per quantity kind.
  Coefficients are fixed point. Remainders of fractional flows are carried,
  never dropped mid-flow.
- **No floating point in authoritative state.** That includes agent
  decisions that change the world.
- **Units are compiler-checked** through one struct type per dimension.
  Runtime unit descriptors convert and label values for content, traces,
  inspectors, and saves.
- **Conservation is exact** and asserted in debug builds. It covers mass,
  count, stocks, and energy, including declared sources, sinks, and
  reservoirs.

### One owner per value

| Value | Owner | Everyone else |
| --- | --- | --- |
| A dynamic physical quantity (temperature, pressure, flow) | Its domain | Reads through the domain; posts contributions |
| A stock at rest | Its holder | Proposes conserving transfers |
| A checked-out stock | The structure that checked it out | Posts contributions |
| A component field | The component, through commitment | Proposes |
| A derived value | Nobody; it is computed | Contributes modifiers |
| A relation or claim | The relation store, through commitment | Proposes |
| Activity state | Its activity entity, through commitment | Observes |
| A trace | The body or tile it is on, through commitment | Perceives it |
| An agent's beliefs and referents | The knowledge system, in the perception phase | Only that agent queries them, through the knowledge view |
| An agent's goals, intentions, commitments, habits | Agency, in the decision phase | Others form beliefs about them by watching behaviour |

### Identity on demand

There are three levels:

- **Stock**: divisible, owned by a domain
- **Stack**: identical units, as one entity
- **Individual**: one entity per unit

Something gains identity when anything needs to tell it apart. It loses
identity only when nothing physical distinguishes it. Latent assembly applies
the same rule to internal parts, and variable-resolution simulation will apply
it to crowds and regions. **Tombstones** keep references to vanished entities
resolvable.

### Two views, and no leaks

- **Developer view:** authoritative state, conservation ledgers, horizons,
  instrument chains, commit order, causal traces.
- **Player view:** built only through perception, from `perceive`
  declarations, appearance fields, measurements, and the character's
  knowledge store. The map, inspector, and notebook view are views of that
  store (KNOWLEDGE.md §15).

Rules that keep hidden state hidden:

- The action menu is *formulate ∩ appears beginnable*. Unknown never
  excludes.
- Goal predicates for stopping activities reference only perceivable state.
- Recipes never bind hidden facts.
- Outcome messages come from perception. There is no success flag.
- Domains and components never format text for the player.
- Beliefs refer to agent-local referents, never to entity IDs. Truth links
  are developer-only.
- Agents never read world state or history directly. They learn only through
  perception.

### Causality and traces

- Every change has a cause: a contribution source, a topology change, a
  committed event, an activity stage.
- Traces record:
  - domain stock deltas
  - applied commit groups and rejections, with their order positions
  - reactions
  - ID allocations

  From these, the developer inspector answers "why?" for any value. §4's
  evidence and provenance build on the same records.

### Saves

**Saved:**

- component stores and relations
- tombstones and the ID counter
- stocks, all checked in to their holders
- transit, ledgers, and carried remainders not yet dropped
- activities, reservations, and watches
- knowledge stores, retained history, and compaction summaries
- motivation stores and agency RNG state
- deferred commit groups
- the boundary index and RNG state

**Rebuilt on load:**

- domain structures
- indexes and caches
- derived values

A rebuilt world produces the same next step as one that never saved.

## A worked example across the systems

*The pump repair* appears in all three documents.

1. **Actions:** the player's *repair* recipe expands from their imperfect
   diagram and binds the wrong shutoff cock.
2. **Commitment:** each dismantling stage commits as a group. Removing the
   cover triggers the anatomy reveal, which creates part entities with
   `partOf` locations. IDs are allocated in commit order; qualities come from
   the unit's seed.
3. **Components:** extracting the piston changes its location to `onTile`,
   with its mass carved from the pump. The piston becomes a standalone domain
   participant.
4. **Domain simulation:** the topology change marks the pipe structure
   dirty. Its water checks in, the structure rebuilds, and if the outlet valve
   is the culprit, the header tank drains through the open cylinder onto the
   floor tiles. Total water is exact throughout.
5. **Actions:** the player's floor-water watch fires and interrupts the
   activity, which suspends with its progress kept.
6. **Knowledge:** the player perceives running water. An NPC later perceives
   a wet floor, tool marks, and an empty header tank, and its interpretation
   rules connect them to the pump work. Who it suspects depends on its
   referents and on what it has heard (KNOWLEDGE.md).
   **Agency** decides what the NPC does about it, weighing its duties,
   loyalties, and belief about who is watching (AGENCY.md).
7. **Institutions (to come):** the miller's claim covers the pump's parts,
   and the question of whose the new seal is gets resolved.

## What comes next

1. **§6: institutions**, which fills the authorization stub, claim
   recognition, and the open ownership questions (mixed goods, installed
   parts).
2. **Latent assembly:** materialization, consistency with history, and
   culprit attribution, carried over from Dewdrop and simplified.
3. **Content language (Triangle) prototype:** in [triangle/](triangle/README.md). Every
   feature the spec plans is built and tested, including randomised property
   tests and a leak check, with an Objective-C wrapper. The TDL front end
   loads the whole English Resource Grammar in 0.57 s. Checked against ACE:
   the same meet types, the same result on every one of 597,000
   unifications, and about 1.5 times the speed. See
   [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md) §18.
4. **The simulation laboratory:** in [lab/](lab/README.md), in mulle
   Objective-C, with content from Triangle. The first slice is built:
   entities, component stores generated from content, relations, tombstones,
   change commitment with automatic individuation and reactions, the clock
   and scheduler, and a scenario harness that runs *The marked nail* and its
   variants with all seven acceptance checks. Since then: saves, the action
   menu with operations from content, a fluid domain with tile stocks
   running DOMAIN_SIMULATION.md's Scenario 3, activities with stages,
   suspension, and watches, and `lab play`: an interactive session with a
   text map, the menu, and the developer inspector, water spreading across
   the floor, and agents' knowledge stores filled by perception, with the
   menu and map built from them, and a first slice of agency: agents that
   decide from what they know, with a subgoal when a belief fails them,
   following goals and methods written as content; walking that takes
   time; event perception and communication, so an agent can ask a
   coworker who saw where something went; and credence, trust, and
   attribution, so a rumour heard twice from one source is weighed once it
   is traced, and a lie is recorded as a fabrication root; and memory
   that decays along the content's hierarchies; and salience, so agents
   keep what matters to them within a bounded memory; and talking in `lab
   play`, asking, telling, and lying; and answering as a choice weighed by
   trust, disposition, and how busy the agent is; and traces that operations
   leave and remove, aging analytically, so a cover-up leaves its own; and
   appearance that differs from the truth until an analysis reaches beneath
   it; interpretation rules gated by expertise and prior beliefs; and a
   notebook that can be written, stolen, and read; and goals weighed by
   credence against what the agent is doing, with a margin against
   dithering (AGENCY.md's false alarm); and autopilot, which hands control
   back to the player when something worth it arises; and methods scored by
   dispositions, norms, and the belief about being watched (AGENCY.md's
   tempting purse); and commitments with windows and rising urgency, the
   routine generator; and needs felt through interoception, the needs
   generator; and habits, an agent's own and those others believe it has.
   And promises, a speaker's commitment and a hearer's claim about a time
   to come; requests, granted or refused; and investigation, a close look
   that notices faint traces and draws the rules that take thought; and
   fair, weighted conflict resolution with soft reservations (ACTIONS.md's
   two hands, one seal); and recognition weighing failure paths by
   persistence into identity hypotheses (CONTENT_LANGUAGE.md's coat at
   dusk); perception's precision, with unknown matches made goals (the nut
   of unknown size); instrument chains, graded excess, and effects with no
   success flag (ACTIONS.md's seized valve); and recipes bound through
   knowledge, suspended, and resumed with their requirements rechecked
   (the interrupted repair).

## Cross-cutting open questions

Each document has its own list. These questions span more than one system:

- **Phase order in commit rounds.** Process before actions, or one shared
  permutation? (ACTIONS.md)
- **The reaction round bound R**, and how players perceive deferred
  reactions. (COMPONENTS.md, ACTIONS.md)
- **Large steps in stiff regions.** Implicit or analytic methods, which
  affect how far quiet worlds can jump. (DOMAIN_SIMULATION.md)
- **Lifetime of informational entities and tombstones** over long runs.
  (COMPONENTS.md)
- **Ownership edge cases** (mixed goods, installed parts), waiting on §6.
  (COMPONENTS.md)
- **Joint activities** with several actors. (ACTIONS.md)
- **Background agents:** reduced-fidelity perception and memory for distant
  agents, which interacts with variable-resolution simulation.
  (KNOWLEDGE.md, COMPONENTS.md)
- **Fidelity levels** for agents, reserved in AGENCY.md §13, with
  consistency obligations similar to latent assembly's.
- **Coordination and joint activities** across actions and agency.
  (ACTIONS.md, AGENCY.md)
- **Code generation from content:** whether `@component` types generate the
  Objective-C component classes and field registry. (CONTENT_LANGUAGE.md,
  COMPONENTS.md)
