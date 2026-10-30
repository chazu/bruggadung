# Actions

## Status and scope

Proposal. This document specifies the system sketched in
[DESIGN.md](DESIGN.md) §1, "Capabilities, actions, and activities", and the
**change commitment** contract, which every system uses to change
authoritative state. It records the decisions made so far, proposes both
contracts, and defines three scenarios to test them before implementation.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how this fits with
[COMPONENTS.md](COMPONENTS.md) and [DOMAIN_SIMULATION.md](DOMAIN_SIMULATION.md).

Out of scope here, except through the stub interfaces defined below:

- knowledge and perception (§4)
- why agents choose actions (§5)
- institutional permission (§6)

## Decisions so far

1. **The five questions are separate functions**: formulate, appear
   beginnable, expect, resolve, and authorize. The action menu is
   *formulate ∩ appears beginnable*, never *can succeed*.
2. **Capabilities chain through instruments and fall short by degrees.** A
   hand's force goes through a wrench to become torque. Falling short of a
   requirement makes work slower, riskier, or rougher; only declared hard
   requirements forbid it.
3. **Operations apply effects, and targets interpret them** through the
   existing reactions channel. There is no success flag. The actor learns the
   outcome only through perception.
4. **Every action is an activity**, including a single step. There is no
   separate turn or energy system. Time is activity duration on the shared
   clock.
5. **Activities are entities.**
6. **Stages commit at their boundaries.** Progress visible in the world is
   committed as world state at checkpoints and on interruption.
7. **Reservations are soft.** They record intent and do not block commits.
   **Commit validation is hard.** Physical conflicts never resolve silently.
8. **Simultaneous conflicts are resolved by a seeded, fair permutation** per
   commit round, optionally weighted by a derived value such as reaction
   speed. Never by entity ID.
9. **Recipes expand through the actor's knowledge**, not through world truth.
   Until knowledge exists, recipes are authored and never consult hidden
   state.
10. **Change commitment is defined here.**
11. **Graded shortfall is curves**, the lookup tables agency's
    considerations use (AGENCY.md): the input is capacity as a percent of
    the requirement; an operation declares curves for its duration
    multiplier (percent), the chance of a mishap (thousandths), and the
    result's quality (percent).

## Terms

| Term | Meaning |
| --- | --- |
| Operation | A generic verb schema: roles, parameters, requirements, stages, and effects. Examples: *rotate*, *transfer*, *separate*. It never names target kinds, only constraints. |
| Role | A named position in an operation (actor, target, instrument, recipient, destination), with constraints on what may fill it. |
| Binding | The assignment of entities to an action's roles. |
| Action | One attempt: actor, operation, bindings, parameters, intention, and expectation. |
| Activity | The execution of an action over time. An entity with an `Activity` component. |
| Stage | One step of an activity, with its own duration, requirements, and effects. |
| Recipe | A composite operation that expands into a plan of child activities. |
| Capability | What a provider can contribute: kind, capacity, conditions, costs, and compatibility. |
| Provider | The entity offering a capability: a body part, tool, machine, surface, another agent, or an office holder. |
| Transformer | A provider that turns an input capability into an output capability. A wrench turns grip and force into torque. |
| Instrument chain | Providers linked from the actor to a requirement, such as hand → wrench → pipe extension. |
| Requirement | A constraint on bound entities and on capabilities reachable from them. Either hard or graded. |
| Shortfall | How far the best available capability falls below a graded requirement, or exceeds a limit. Sets duration, risk, and result quality. |
| Reach | The set of entities an actor may draw candidates from. |
| Effect | A committed physical or semantic change that an operation applies, such as "30 Nm applied to handle H". |
| Expectation | The actor's predicted outcome, recorded on the activity. |
| Decision point | A moment when an actor must choose what to do next. For the player, the run policy waits for input. |
| Reservation | A soft, reified record of intent to use something. |
| Proposal | A requested change to authoritative state. |
| Proposal group | Proposals that commit atomically, all or nothing. |
| Commit round | One pass that validates and applies proposal groups. |
| Boundary | A scheduler step boundary, where commit rounds run. |
| Rejection | A group refused by validation, with a reason, delivered to its source. |

## The action contract

### 1. Operations

Each operation declares:

- **Roles**, each with constraints over the components, fields, and
  capabilities of the entity that fills it, and whether the role is
  required.
- **Parameters**, typed with units. Examples: angle, amount, force setting.
- **Requirements**, per role and per stage, each hard or graded.
- **Stages**, each declaring:
  - an effort model (base effort, and how the rate depends on capabilities
    and shortfall)
  - stage requirements
  - the effects committed on completion
  - any partial effects for interruption and checkpoints
  - whether the stage can be suspended
- **Stopping conditions**: stage count, or a goal predicate. **Goal
  predicates may reference only state the actor can perceive.** An activity
  never stops at a moment that reveals hidden state.
- **Observability**: what others can perceive while the activity runs, such
  as noise, motion, or the posture of the actor.

Operations are mostly content, written in the content language; see
[CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md) and COMPONENTS.md §10. Code supplies effect functions for operation families.

**Initial operation set**, covering the scenarios in all three docs:

| Operation | Roles | Effect committed |
| --- | --- | --- |
| move | actor, destination | The actor's location changes |
| take / put | actor, item, source / destination | The item's location changes |
| apply force (rotate, strike, push) | actor, target, instrument? | Force or torque of a stated magnitude applied to the target |
| separate / connect | actor, assembly, part, instrument? | `partOf` removed or added |
| transfer | actor, source, destination | A stock transfer between holders, or a domain contribution |
| divide | actor, item, instrument | Individuation: a split or carve |
| inspect | actor, target | An observation event for the actor (§4 hook); may trigger anatomy reveal |
| copy | actor, original, medium, instrument | A new inscription, plus new content if altered |
| communicate | actor, listener(s), content | An utterance event (§4 hook) |
| wait / rest | actor | None. Registers watches. |

New operations are added only when a scenario needs one.

### 2. Capabilities and requirements

- **Capability record**: provider, kind, capacity with units, conditions,
  costs, and compatibility. Components offer capabilities through the
  capabilities channel (COMPONENTS.md §4).
- **Providers** can be body parts, tools, machines, environment features (a
  ledge to brace against), assisting agents, and office holders. Office
  holders provide institutional capabilities, such as issuing a permit,
  through §6. Those capabilities are matched in the same way. Holding the
  capability to issue is different from permission to act, which stays a
  separate question.
- **Transformers** declare their input capabilities, their output capability
  as a function of the inputs (torque = force × lever length), their own
  limits (bends above 80 Nm), and compatibility (fits a 19 mm fastener).

**Chain search**

1. Search backwards from each requirement to providers in reach.
2. The depth is bounded, initially to 3.
3. The candidate order is deterministic: by declared score, then by stable
   ID.
4. The score prefers chains that meet the requirement, then the smallest
   shortfall, then the lowest cost.

When the player or an agent binds an instrument explicitly, there is no
search.

**Hard and graded requirements**

- **Hard**: unmet means the activity cannot begin, or halts when the
  requirement is rechecked. Example: rotating with no grip at all.
- **Graded**: a declared function from the ratio of capacity to requirement
  gives:
  - a duration multiplier
  - risk: the chance of declared mishaps, such as slipping, a trace, damage,
    or injury
  - result quality
- Excess can be graded too. Too much torque can strip a thread or bend the
  instrument.

**Reach and costs**

- **Reach** includes the actor's body, what it holds and wears, carried
  containers (with an access cost), adjacent tiles, and the reach of any
  agents assisting.
- **Costs** are committed per stage as proposals:
  - wear and traces on tools
  - energy, as contributions to domains
  - consumed materials, subject to commit validation

### 3. The five questions

| Function | Answers | Inputs | Stub until §4 or §6 exists |
| --- | --- | --- | --- |
| `formulate(actor, op, bindings)` | Does the actor know the operation and recognize the candidates for its roles? | The actor's knowledge | Every operation is known. Only entities the actor perceives can be bound. |
| `appearsBeginnable(actor, action)` | Do requirements appear satisfied? | The actor's perceived state | Perceivable fields are taken from the truth. **Hidden fields count as unknown, and unknown never excludes.** |
| `expect(actor, action)` | What does the actor predict? | The actor's model | An authored expectation from the operation schema, recorded only |
| `resolve` | What actually happens? | The world | Real: effects plus target reactions |
| `authorize(action)` | Which institutions permit or forbid it? | Institutions | Empty. **Never blocks an attempt.** |

**Menu contract**

- An actor's menu lists the operation-and-binding pairs that pass both
  `formulate` and `appearsBeginnable`.
- It is computed only from the actor's view and sorted deterministically.
- **It must never consult hidden state**, directly or through ordering,
  counts, or timing.
- The developer inspector may show `resolve` predictions alongside the menu,
  clearly separated from it.

### 4. Effects and resolution

- Completing a stage commits its **effects** as a proposal group. Effects can
  be:
  - physical: applied force, location changes, transfers, separations,
    divisions
  - semantic: utterances, inscriptions
  - observations, for the actor's perception
- **Targets interpret effects through reactions** (COMPONENTS.md §4). A
  target's components react to committed effect events in which their entity
  has a role. They propose consequences in the next commit round.
  - A seized valve that receives 15 Nm does nothing.
  - At 70 Nm the corrosion bond breaks, and the valve proposes its new
    position.
- **Effect magnitude** comes from the capability chain's capacity, limited
  by any parameter the actor sets, such as gentle or full force.
- **There is no success flag.** An activity ends:
  - when its stages complete
  - when a goal predicate over perceivable state holds
  - when the actor gives up at a decision point
  - on interruption or failure
- **Outcome messages come from perception.** The UI never states a reason
  the actor couldn't perceive. "You strain at the handle; it doesn't move."
- **Some effects are direct state changes**, such as *take* changing a
  location. These still pass commit validation, and targets may still react:
  a trapped chest reacts to being opened.

### 5. Activities

An activity is an informational entity with an `Activity` component, holding:

| Field | Meaning |
| --- | --- |
| actor | Who is acting |
| action | Operation, bindings, parameters, chosen instrument chain |
| intention, expectation | What the actor wants and predicts |
| stage, progress | The current stage and its effort completed, as integer effort units |
| status | running, suspended, completed, aborted, or failed |
| providers | Capability providers allocated to it, such as hands or voice |
| reservations, watches | Soft reservations it holds and domain watches it registered |
| parent, children | For recipes |
| history | Stage transitions, interruptions, rejections |

Others perceive an activity through its actor's position and the operation's
observability declarations.

**Stages and progress**

- `rate = f(capabilities, shortfall, actor modifiers)`
- The remaining time is a `nextEvent` for the scheduler. A change to any rate
  input, such as an injured hand or a better tool, recomputes it.
- At a stage's start, requirements are rechecked and providers allocated.
- At a stage's end, its effects and costs are submitted as one proposal
  group.

**World-visible progress**

- A stage whose progress is visible in the world declares **partial
  effects**: a half-sawn log, a half-dug trench.
- Partial effects are committed at declared checkpoints, which become step
  boundaries, and on interruption, in proportion to progress.
- Progress that isn't visible in the world stays on the activity.

**Provider allocation**

- Each capability provider belongs to at most one activity at a time.
- An actor may run several activities if their providers don't overlap:
  walking while talking works, two activities that both need the hands do
  not.
- This allocation is internal to the actor. It is separate from
  reservations and from commit validation.

**Interruption**

There are four sources:

1. a domain watch firing
2. a committed event in which the actor takes part (being hit, being
   addressed)
3. a requirement failing when it is rechecked
4. the actor's choice

**Rechecking requirements**

- After each commit round, the activity system checks the commit report
  against an index from bound entities to the activities that bind them. A
  dropped wrench rechecks every activity bound to it.
- This is engine machinery, not a component channel.

**Outcomes of an interruption**

| Outcome | Progress | Partial effects | Reservations | Watches |
| --- | --- | --- | --- | --- |
| Suspend | Kept; resumable | Committed | Kept or released, as declared | Kept |
| Abort | Discarded | Committed | Released | Removed |
| Fail | Discarded | Committed | Released | Removed |

- Stages that have already committed stay in the world in every case. That is
  how a partially dismantled machine exists.
- **Soft interruptions**, such as being called, create a decision point. The
  player or the agent's §5 logic chooses whether to continue or suspend.
- **Hard interruptions**, such as a requirement failing, force a suspension
  or failure, as the stage declares.
- **Resuming** rechecks requirements and reallocates providers.

**Decision points**

A decision point arises when an activity completes, suspends, or fails, and
when a soft interruption occurs. For the player's actor, the run policy waits
for input. For other agents, §5 decides.

**Watches** are owned by activities. They are registered at the start of an
activity or stage, removed when it ends, and saved with it. This answers
DOMAIN_SIMULATION.md open question 4.

### 6. Recipes

- A recipe declares a goal, a plan template of operations, how bindings flow
  between steps, and conditions.
- **Expansion uses the actor's knowledge.**
  - A wrong diagram produces a wrong plan.
  - A recipe step can never bind a hidden fact. "Replace the culprit part" is
    impossible until the actor knows which part that is.
  - Until §4 exists, recipes are authored and expand only from state the
    actor can perceive.
- **A recipe activity has child activities.**
  - Interrupting a child propagates to the parent as a decision point.
  - Suspension resumes at the child.
- The player can work at either level: issue "repair" and trust their
  character, or drop to individual operations at any time.

### 7. Reservations

- A reservation is a reified relation, and so an entity, between a reserver
  (an activity or agent) and a target entity or quantity. It records intent
  and may carry an expiry.
- **It does not block commits.** Agents who know about a reservation may
  respect it, according to their dispositions (§5). A physical marker, such
  as a tag on a shelf, is a separate entity that agents can perceive.
- Institutions (§6) may treat some reservations as claims.

## The change commitment contract

Every change to authoritative state, from any system, goes through change
commitment. That covers component fields, relations (including location),
entity creation, destruction, splitting and merging, stocks at rest, and
committed events. There are three exceptions: checked-out stocks, which their
domains change during steps; agents' private knowledge stores, which the
knowledge system writes in its perception phase
([KNOWLEDGE.md](KNOWLEDGE.md) §14); and agents' private motivation stores,
which agency writes in its decision phase ([AGENCY.md](AGENCY.md) §12).

### 8. Proposals and groups

**Proposal kinds**

- setting a component field (only fields declared `proposable`)
- transferring a stock between holders while it is at rest
- adding, removing, or replacing a relation, including location
- creating an entity from a spec; destroying, splitting, or merging an
  entity
- emitting an effect event
- contributing to a domain (proposals against checked-out stocks become
  these)

Each proposal carries its **source** (an activity, a component reaction, a
domain, a process, or system content) and its **cause** (the event that led
to it).

**Groups** commit atomically, all or nothing. Groups come from:

- activity starts, stage completions, checkpoints, and interruptions
- reactions
- domains' discrete proposals at the end of a step
- system operations

**Validators** may be declared by component kinds and relation kinds. They
are pure: they can reject a group, never change it.

### 9. Commit at a boundary

At each boundary, after domains have advanced to the boundary time:

1. **Gather** the groups submitted for this boundary.
2. **Order** them:
   1. By phase: process groups (domains, processes) first, then action
      groups (activities, inputs), then system groups.
   2. Within a phase, by a **seeded permutation**. The permutation's seed
      comes from the world seed plus the boundary index plus the round
      number. It may be weighted, using a weighted sampling key per group
      drawn from the same seeded stream.
3. **Validate and apply** groups one at a time in that order. Each group is
   validated against the state left by the groups before it. Validation
   covers:
   - location exclusivity and capacity
   - conservation of mass, count, and stocks
   - relation cardinality
   - the target still exists and is not a tombstone
   - capability conditions still hold (the tool is still in reach)
   - declared validators

   **Automatic individuation** rewrites the group first where needed. If
   validation passes, the group is applied. If not, it is rejected with a
   reason.
4. **Allocate IDs** in application order, and **emit committed events** for
   applied groups, with their causes.
5. **Reactions:** components react to this round's events. The resulting
   groups form the next round at the same boundary, up to a bound of R
   rounds. Groups left over are deferred to the next boundary and traced.
6. **Deliver rejections** to their sources. Activities fail or block, and
   rejected reactions are traced.
7. **Housekeeping:**
   - mark domain structures dirty where topology changed
   - update indexes
   - recheck activity bindings
   - evaluate watches
   - raise decision points
8. **Inputs** that arrive at a decision point, such as new activity starts,
   are committed at the same boundary before the scheduler computes the
   next step.

**Conflicts are resolved by order.** The earlier group in the permutation
wins, and the later one is rejected with a reason. The alternative, rejecting
every conflicting group, would leave both agents empty-handed for no gain.
Because the order is fair and seeded, nobody wins systematically by being
older, having a lower ID, or being processed first.

### 10. What commitment does not do

- **Decide what operations achieve.** Effects plus target reactions do that.
- **Judge permission.** Institutions do that.
- **Change checked-out stocks directly.** Proposals against them become
  contributions to the owning domain (DOMAIN_SIMULATION.md §3).

### 11. Determinism and traces

- Commit outcomes depend only on state, the world seed, the boundary index,
  and the round number. There is no hash ordering and no wall-clock input.
- Every applied group and every rejection is traced with its source, cause,
  and order position. The developer's causal inspector follows these chains
  from effect back to the original action or process.

## Observation, saves, and interface

### 12. Observation

- **Player view:** the menu is built from the actor's view. Outcomes are
  reported by perception. Activities by others are perceived through their
  observability declarations.
- **Developer view**, per action:
  - the five-question breakdown
  - the chosen instrument chain and shortfall factors
  - expectation versus actual result
  - commit groups, their order positions, and rejections

### 13. Saves

Saves contain:

- activities and reservations, as entities in their stores
- groups deferred to the next boundary
- the boundary index and RNG state
- provider allocations

### 14. Interface sketch

Illustrative only; this has not been compiled.

```objc
@protocol BGOperation
+ (BGOperationDeclaration *) declaration;   // roles, params, requirements, stages

- (void) completeStage:(NSUInteger) stage
           forActivity:(BGActivity *) activity
                  into:(BGProposalGroup *) group;

- (void) interruptStage:(NSUInteger) stage
            forActivity:(BGActivity *) activity
               progress:(BGFraction) progress
                   into:(BGProposalGroup *) group;
@end

@protocol BGKnowledgeView     // stubbed until §4
- (BOOL) actor:(BGEntityID) a canFormulate:(BGAction *) action;
- (BGPerceivedState *) perceivedStateFor:(BGEntityID) a;
- (BGExpectation *) expectationOf:(BGEntityID) a for:(BGAction *) action;
@end

@interface BGCommitter : NSObject
- (void) submit:(BGProposalGroup *) group;
- (BGCommitReport *) commitBoundary:(uint64_t) boundaryIndex;
@end
```

## Scenarios

Each scenario lists its purpose, setup, sequence, choices and uncertainty,
observable information, and acceptance checks. Numbers are illustrative.

### Scenario 1: The seized valve

**Purpose:** instrument chains, graded shortfall and excess, resolution
through effects with no success flag, and a menu that leaks nothing.

**Setup**

- A valve on a water line. Its rating says 12 Nm to turn.
- Hidden: corrosion has seized it, and breaking it free takes 70 Nm.
- An actor whose hands provide grip and about 200 N of force, enough for
  about 15 Nm on the bare handle.
- In reach:
  - a 0.25 m wrench, limit 80 Nm before bending
  - a 0.6 m length of pipe that fits over the wrench handle
  - a fist-sized stone

**Sequence**

1. The actor's menu offers *rotate valve*. It is identical to the menu for an
   unseized valve.
2. **Bare hands:** the stage commits "15 Nm to the handle". The valve reacts
   with nothing. The actor perceives no movement, and the activity ends at a
   decision point ("it won't budge").
3. **With the wrench:** the chain is hand → wrench, giving 50 Nm. Still
   nothing moves. The wrench gets a minor trace.
4. **Wrench plus pipe:** the chain is hand → wrench → pipe, giving up to
   120 Nm, which exceeds the wrench's 80 Nm limit.
   - At full force, the excess risk applies. Depending on the seeded draw,
     the wrench either bends (a trace and changed capacity) or the valve
     frees at 70 Nm first.
   - At a "steady" force setting of 75 Nm, the valve frees with no excess
     risk.
5. **Alternative:** striking the valve body with the stone is an impact
   effect. The valve reacts by loosening the bond, which lowers its breakaway
   torque.

**Choices and uncertainty**

- The actor chooses instruments, the force setting, and whether to strike
  first.
- They don't know the breakaway torque or the wrench's limit, unless their
  knowledge provides it.

**Observable information**

- **Player:** whether the handle moves, sounds, the wrench visibly bending,
  and their exertion.
- **Developer:** the chain chosen, effect magnitudes, the valve's breakaway
  threshold, excess-risk draws, and expectation versus actual result.

**Acceptance checks**

1. **No leak:** in otherwise identical worlds with a seized and an unseized
   valve, the menu, its order, and its timing are identical.
2. **Deterministic chain search** finds hand → wrench → pipe within depth 3,
   with the same choice on every replay.
3. **Excess** above the instrument's limit produces risk, not a hard
   refusal.
4. **Outcome messages** contain only perceivable facts. The breakaway torque
   never appears in player text.
5. **Expectation versus actual** is recorded for each attempt.
6. Tool wear and traces are committed as costs in the stage's group.

### Scenario 2: Two hands, one seal

**Purpose:** simultaneous conflicts, atomic groups, fair seeded ordering,
soft reservations, and rejection delivery.

**Setup**

- One spare piston seal on a workbench.
- Worker A reserved it yesterday for the pump repair, as a reified
  reservation.
- B either doesn't know about the reservation or ignores it.
- A and B each start *take seal* so that their take stages complete at the
  same boundary.

**Sequence**

1. Both groups are gathered in the action phase. The seeded permutation
   orders them.
2. The first group applies: the seal is now `heldBy` its winner. The second
   group fails validation because the seal is no longer at the source, and is
   rejected with that reason.
3. The loser's activity fails. They perceive the seal in the other's hand.

**Variants**

- **A:** B knows about the reservation and is disposed to respect it, so B
  never starts. (The §5 stub decides.)
- **B:** B ignores the reservation and wins the draw. The reservation does
  not block the commit. A, who knew about the reservation, perceives the seal
  gone. This is a hook for grievances in §4 and §6.
- **C, weighting:** B has a higher reaction-speed derived value. Over many
  seeds, B wins in proportion to the weights.

**Choices and uncertainty**

- Whether B respects reservations.
- When each agent starts.

**Observable information**

- **Player:** who ends up holding the seal.
- **Developer:** both groups, their order keys, and the rejection reason.

**Acceptance checks**

1. **Exactly one take** applies. The other is rejected atomically, with no
   partial effects.
2. **Rejection reasons** reach the losing activity.
3. **Fairness:** with equal weights, over 1,000 seeds each wins about half
   the time. Swapping their entity IDs leaves that distribution unchanged.
4. With weights, win frequencies track the weight ratio.
5. **Reservations never block** a commit.
6. **Determinism:** the same seed always gives the same winner.

### Scenario 3: The interrupted repair, from the action side

**Purpose:** recipe expansion through knowledge, child activities,
interruption and its outcomes, rechecking requirements on resume, provider
allocation, and activity watches. This shares its setup with Scenario 2 of
DOMAIN_SIMULATION.md and Scenario 3 of COMPONENTS.md.

**Setup**

- The miller's failed pump.
- The player holds an imperfect diagram. It shows a shutoff cock on the
  riser; in reality, the cock controls the trough line.
- A wrench is in the player's reach. An NPC wanders the workshop.

**Sequence**

1. The player issues *repair pump*, a recipe. It expands using the player's
   knowledge, which includes the diagram:
   1. close the shutoff (bound to the wrong cock)
   2. dismantle the pump (three stages)
   3. inspect the parts
   4. replace the faulty part (unbound until inspection reveals one)
2. The player talks to a visitor while working. *Communicate* uses the voice
   and *dismantle* uses the hands, so both run.
3. During stage 3 of dismantling (extracting the piston, 60% done, no
   world-visible progress), someone shouts the player's name. This is a soft
   interruption, so there is a decision point, and the player suspends the
   activity.
4. While it is suspended, the NPC takes the wrench.
5. The game is saved and loaded, and the player resumes. Rechecking
   requirements finds no instrument for the gland nut, so the activity is
   blocked. The player improvises another chain.
6. **If the outlet valve turns out to be the culprit:** the recipe's watch on
   floor water at the player's tile fires, and the rising water interrupts the
   activity.

**Choices and uncertainty**

- The player can trust the recipe or work step by step.
- They choose whether to continue or suspend when called, and what tool to
  improvise.
- They don't know that the diagram is wrong, or which part is the culprit.

**Observable information**

- **Player:** that the trough stops filling (the wrong cock was closed), the
  shout, the missing wrench, and water rising.
- **Developer:**
  - the recipe expansion with each binding's source (the diagram)
  - the child activity tree
  - suspension state and recheck results
  - the watch registration and when it fired

**Acceptance checks**

1. **Expansion uses knowledge only.** With the diagram, the plan binds the
   wrong cock. Swapping in an omniscient knowledge stub changes the binding.
   This shows the dependency is real.
2. **No hidden binding:** step 4 stays unbound until inspection reveals a
   culprit.
3. **Provider allocation:** talking and dismantling run together. Starting a
   second activity that needs the hands is refused with a reason.
4. **Suspension** keeps the 60% progress on the activity and commits nothing
   to the world. **Abort** of a stage with world-visible progress commits its
   partial effects.
5. **Save and load** during suspension: after loading, the next boundary is
   bit-identical to a run without the save.
6. **Rechecking on resume** detects the missing instrument and blocks the
   activity with a reason.
7. **The watch** interrupts within the domain's event tolerance, and is
   removed when the activity ends.

## Open questions

1. **Phase order.** Is process-first the right phase order within a commit
   round, or should process and action groups share one permutation?
2. **Reaction rounds.** What is the bound R per boundary (shared with
   COMPONENTS.md), and how do players perceive deferred reactions?
3. **Chain search.** What depth and scoring work well in practice?
4. **Shortfall curves.** Decided: decision 11.
5. **Outcome messages.** How exactly does perception compose them (§4)?
6. **Joint activities.** How do activities with several actors work, such as
   two people lifting a beam? Pooled capabilities, a shared activity entity,
   and dividing up the risk.
7. **Recipe knowledge.** How is recipe knowledge represented, and how do
   recipes interact with §4 beliefs?
8. **Weights.** Which derived values may weight the commit permutation, and
   in which phases?
