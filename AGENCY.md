# Agency

## Status and scope

Proposal. This document specifies the system sketched in
[DESIGN.md](DESIGN.md) §5, "Agency". It records the decisions made so far,
proposes the agency contract, and defines three scenarios to test it before
implementation.

Agency answers one question: **at a decision point, given what this agent
believes and wants, what does it do next?** It also tells perception what
matters to each agent.

It fills the remaining stubs left by the other systems:

- decision points ([ACTIONS.md](ACTIONS.md) §5)
- dispositions toward reservations (ACTIONS.md §7)
- salience ([KNOWLEDGE.md](KNOWLEDGE.md) §5, §7)

See [ARCHITECTURE.md](ARCHITECTURE.md) for how it fits with the other systems.

Out of scope here, except where they touch agency:

- institutional obligations and sanctions (§6)
- pacing and pressure generators, such as RimWorld's storyteller
- the format for content: methods, consideration curves, norms (see
  [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md); its three-valued matching
  gives methods their residual subgoals)

## Decisions so far

1. **Three layers, with no general planner:**
   - *motivation* chooses goals by fixed-point utility
   - *methods* (HTN style, built on recipes) decide how
   - *activities* do the work
2. **Every input comes from the knowledge view.** Utility considerations,
   method preconditions, and bindings never read world state or truth.
3. **Needs are body state perceived through interoception.** There are no
   separate need meters, and misperception is possible.
4. **Intentions persist.** A goal is reconsidered only at decision points.
   It is replaced only when another goal beats it by a margin that includes
   the cost of interrupting the current activity.
5. **Routines are default goals with time windows**, coming from commitments
   and habits. Habits are strengths that others can form beliefs about, so
   breaking a habit is salient to those who know it.
6. **Dispositions and internal norms weight utility.** Norm evaluation uses
   the agent's *belief* about being observed.
7. **Agency provides salience** and splits the attention budget according to
   how demanding the current activity is.
8. **Each agent has a private motivation store** next to its knowledge store,
   written by agency at decision points and outside change commitment.
9. **Fidelity levels are reserved in the contract.** Nothing may assume that
   every agent is simulated in full detail. Their design comes later.
10. **The player can delegate decisions to agency** for their own character,
    through autopilot modes. Control returns on salient interruptions.
11. **The gain from a lie is of two kinds**: escaping a consequence the
    agent believes the truth would bring (asked where the purse is, the
    one who took it believes the truth gets it arrested; INSTITUTIONS.md),
    and advancing one of its goals (sending a rival to the wrong place).
    Each is scored like any other consideration, against honesty and the
    risk of being found out.

## Terms

| Term | Meaning |
| --- | --- |
| Agent | An entity with a `Mind` component: a knowledge store, a motivation store, and dispositions |
| Decision point | A moment when an agent must choose (ACTIONS.md §5) |
| Goal | A desired state or ongoing condition, such as "not hungry", "shift worked", "wrench in hand", or "promise kept" |
| Goal generator | A source of candidate goals: needs, routines, commitments, reactions, social requests |
| Consideration | One scored input to a goal's utility, such as urgency, credence, cost, or risk. A fixed-point curve over a knowledge-view value. |
| Utility | A goal's score: considerations combined in fixed point |
| Intention | The goal currently pursued, with its chosen method and how far its plan has got |
| Margin | How much better another goal must score to replace the current intention |
| Method | An HTN-style way to achieve a goal: preconditions, a decomposition, and alternatives |
| Need | Pressure from a perceived body condition: hunger, fatigue, pain, cold, breathlessness |
| Interoception | The sense through which an agent perceives its own body |
| Commitment | A goal the agent is bound to: a shift, a promise, a debt. It has a deadline or a time window. |
| Routine | The default goals in force at a given time, from commitments and habits |
| Habit | A learned preference in a context, such as "wrench back on the hook" or "this route home", with a strength |
| Disposition | A per-agent weight: honesty, respect for reservations, risk tolerance, curiosity, loyalty |
| Internal norm | A personal rule weighting kinds of action, such as "don't take what isn't yours" |
| Salience | How much a percept or proposition matters to this agent now |
| Attention budget | How much an agent can perceive and interpret per boundary |
| Motivation store | An agent's private goals, intentions, commitments, and habit strengths |
| Fidelity level | How fully an agent is simulated: full, reduced, or background |
| Autopilot | Agency acting for the player's character in a mode the player chose |

## The agency contract

### 1. Where agency sits

Agency supplies two functions:

| Function | Called by | Returns |
| --- | --- | --- |
| `decide(agent, decisionPoint)` | The boundary's decision phase | Activity starts, suspends, resumes, or a wait with watches |
| `salience(agent, item)` | The knowledge system's perception phase | A fixed-point salience value, and whether it crosses an interruption threshold |

**Agency never changes the world directly.** Everything it does happens
through activities (ACTIONS.md).

### 2. The mind

An agent has a `Mind` component, which points to three things:

- **Knowledge store**, specified in KNOWLEDGE.md. Private.
- **Motivation store**, private, holding:
  - candidate goals and their last scores
  - the current intention: goal, method, plan position
  - commitments, with deadlines, sources, and, for promises, the claim
    content of the promise
  - habit strengths
  - the decision index and RNG state
- **Dispositions and internal norms**, which are ordinary component fields
  (`Disposition`) set by content and changed only through commitment, such
  as when a character's outlook changes after a significant event. Others
  cannot perceive dispositions directly. They form beliefs about them, such
  as trust, by watching behaviour.

### 3. The decision procedure

At a decision point:

1. **Gather candidate goals** from the generators (§4), plus the current
   intention.
2. **Score each goal.** Utility is a combination of considerations, each a
   fixed-point curve applied to a value from the knowledge view. The curves
   are lookup tables.
   - **Expected value uses credence.** A goal's benefit is weighted by how
     strongly the agent believes the situation calls for it.
   - **Costs come from beliefs:** the believed distance, the believed time
     needed, the believed risk.
3. **Apply commitment.** The current intention gets a continuation bonus:
   the margin plus an interruption cost, which depends on the current
   activity's progress and whether it can be suspended. Another goal replaces
   the intention only if it beats that total.
4. **Choose a method** for the winning goal (§5). Methods are tried in score
   order. The first whose preconditions hold *in the knowledge view* is
   expanded into recipes and operations, with bindings taken from the
   knowledge view.
5. **Output:** start, continue, suspend, or resume an activity. If no goal is
   worth acting on, the output is to **wait**, registering watches for what
   would change that. The output is submitted as proposal groups and
   committed at the same boundary (ACTIONS.md §9, step 8).
6. **When something fails:**
   - If a method's activity fails or is rejected, the next method is tried.
   - If every method's preconditions fail, the agent believes the goal
     impossible for now, drops it, and records why.
   - Failing can itself produce goals. A failed fetch produces *seek missing
     tool*.

**Rules:**

- Decisions are instantaneous in simulation time.
- Ties are broken by a seeded stream per agent and decision index.
- All arithmetic is fixed point.
- **The truth is never consulted.** Swapping the knowledge view for an
  omniscient stub must visibly change behaviour, and the scenarios check
  this.

### 4. Goal generators

The initial set:

| Generator | Goals | Driven by |
| --- | --- | --- |
| Needs | eat, rest, get warm, get air | Interoceptive beliefs (§6) |
| Routine | work shift, go home | Commitments and habits with time windows (§8) |
| Commitments | keep a promise, pay a debt | Commitment deadlines (§7) |
| Reactive | investigate disturbance, protect possession | Salient beliefs: an anomaly, a threat to something believed owned |
| Instrumental | seek missing tool | A method precondition the agent believes has failed |
| Social | request help, answer when addressed, comply with or refuse a request | Being addressed; needing a capability or knowledge someone else holds |

Generators produce candidates only from salient beliefs. An agent unaware of
a disturbance generates no goal to investigate it.

### 5. Methods

- A method declares:
  - the goal it serves
  - preconditions, over the knowledge view
  - a decomposition into subgoals, recipes (ACTIONS.md §6), and operations
  - how bindings flow between steps
  - its alternatives, in order
  - what to do on failure
- **Methods inherit the recipe rule: they never bind hidden facts.**
- **The method score** uses:
  - believed cost
  - a habit strength bonus, so habitual ways win ties
  - dispositions: a dishonest agent may prefer *take* over *ask*
  - norms
- **There is no general search.** A method may include bounded local choice,
  such as ordering the places to look by the belief that the item is there.
- Methods are content, in the content language
  ([CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md)). A precondition match is
  entailed, incompatible, or unknown; each method declares its credence
  threshold and whether an unknown result becomes a subgoal for the
  residual paths.

### 6. Needs and interoception

- Body conditions are world state:
  - metabolism and hydration as stocks
  - body heat in the thermal domain
  - blood gases from respiration, in the atmosphere domain
  - injury and fatigue as component fields
- **Interoception** is a sense (KNOWLEDGE.md §5). It produces percepts such as
  "hungry", "cold", "short of breath", or "pain in left hand", each with a
  precision.
- **Need pressure** is a consideration curve over the interoceptive belief,
  not over the true body state.
- **Misperception is possible.** Modifiers affect how precise interoception
  is, not the body: adrenaline dulls pain, numbness hides cold, exhaustion
  blurs hunger. The agent acts on what it feels.

### 7. Commitments and intentions

- **Intentions persist.** They are reconsidered only at decision points:
  - an activity completes, suspends, or fails
  - a soft interruption
  - salience crosses a threshold

  They are not reconsidered every boundary.
- **Commitments** hold:
  - a goal
  - a deadline or time window
  - a source: self, employment, or a promise
  - an urgency curve that rises toward the deadline
- **Promises** are commitments created by a *communicate* act, whose content
  is the promise itself. Hearers hold it as a claim.
  - Keeping or breaking a promise is a history event, which hearers perceive
    when they learn the outcome. It updates their trust in the promiser.
  - Whether a promise is an *obligation* with sanctions is §6's business.

### 8. Routines and habits

- **A routine** is the set of default goals active in a time window. It is
  built from commitments (a shift from 8 to 16, an employment obligation from
  §6) and habits (eat at noon).
- **A habit** is a context, a choice, and a strength.
  - Strength rises with repetition and decays analytically.
  - Habits supply method defaults: where to put things, which route to
    take.
- **Others form beliefs about habits.** Interpretation rules turn repeated
  observations into propositions such as "Piet usually leaves by the front".
  **Breaking a habit is salient** to anyone who holds such a belief. This is
  how routine becomes evidence.

### 9. Dispositions and internal norms

- **Dispositions** are fixed-point weights: honesty, respect for
  reservations, risk tolerance, curiosity, loyalty, and others as scenarios
  need them.
- **Internal norms** weight kinds of action, such as taking what is believed
  to be owned by someone else, lying, breaking a promise, or harming
  someone.
- **Norm considerations include two beliefs:**
  - **Being observed:** which observers the agent believes could perceive the
    act. This is computed from believed positions, using the same perception
    model the world uses.
  - **Consequences:** what the agent believes about sanctions. Institutions
    are §6.

  An agent may act against a norm when it believes it is unobserved, and it
  can be wrong about that.
- **Respecting reservations** (ACTIONS.md §7) is a norm weighted by
  disposition. It applies only to reservations the agent knows about.

### 10. Salience and attention

The salience function draws on:

- **Goals and needs:** items relevant to the current intention or a pressing
  need
- **Possessions:** anything near or affecting what the agent believes it
  owns or is responsible for
- **Threats:** harm to the agent or to those it is loyal to
- **Anomalies:** events that contradict beliefs, including broken habits and
  "the workshop should be empty"
- **Being addressed**
- **Curiosity**, as a disposition

**Attention:**

- Each operation declares its attentional demand.
- The attention budget left after the current activity's demand is what
  perception and immediate interpretation can use (KNOWLEDGE.md §5, §9). A
  busy agent notices less.
- **Interruption threshold:** when salience exceeds the agent's threshold
  for its current activity, it raises a soft interruption and a decision
  point.

### 11. Social behaviour

- **Requesting** is communicating a request: help, an item, information.
- **Being addressed** raises a decision point. The *answer* and *comply or
  refuse* goals are scored by trust in the asker, disposition, the agent's own
  commitments, and the cost of the request.
- **Conversations** are alternating communicate activities, each reply
  chosen at a decision point. NPC-to-NPC conversation uses exactly the same
  machinery.
- **Lying** is a method alternative, weighted by the honesty disposition and
  the believed gain. It is recorded as a fabrication root (KNOWLEDGE.md §10).

### 12. The decision phase and ownership

The decision phase runs after the perception phase at each boundary
(ARCHITECTURE.md, "The life of one boundary"):

1. Collect the agents with decision points.
2. Call `decide` for each, in stable ID order. Each decision depends only on
   committed state, that agent's knowledge store, and its motivation store,
   so the order cannot change results.
3. Submit their outputs as proposal groups, to be committed at the same
   boundary.

Other rules:

- **The motivation store is private.** Agency writes it here and nowhere
  else. Like knowledge stores, it bypasses change commitment because it is
  private and cannot conflict with other agents. Every write is traced.
- **Cost:** agents that are mid-activity, with no interruption, cost nothing
  in this phase.

### 13. Fidelity levels (reserved)

- Every agent has a fidelity level: **full**, **reduced**, or **background**.
- **Contract obligations, starting now:**
  - No system may assume every agent is at full fidelity.
  - Changing fidelity must preserve consistency with history, traces,
    records, and other agents' beliefs. Promotion works like latent
    assembly: it may reveal detail, but never contradict what has already
    been observed.
  - Demotion summarizes. It never deletes evidence that others have
    referenced.
- **To be designed later:** what each level computes, coarse routine
  simulation, promotion triggers, summary traces.

### 14. The player and autopilot

- The player's character reaches decision points like any agent. The choice
  comes from input.
- **Autopilot modes** hand decisions to agency for the player's character:
  - *keep working until something happens*
  - *continue my routine*
  - *auto-explore*
  - *carry out this recipe*
- The player chooses the goal set and the interruption threshold. Any soft
  interruption above that threshold returns control.
- **Autopilot sees only the character's knowledge view**, exactly as NPCs do.
  It cannot act on information the character lacks.

### 15. Observation

- **Player view:** other agents' minds are never shown. The player perceives
  behaviour, and their character forms beliefs about intentions, dispositions,
  and habits through interpretation.
- **Developer view, per decision point:**
  - the candidate goals with each consideration's value
  - the margin and interruption cost
  - the chosen method, and rejected methods with the preconditions that
    failed
  - the salience values that triggered the decision
  - a comparison against an omniscient decision, for the knowledge-dependence
    checks

### 16. Saves and determinism

- **Saved:** motivation stores, `Disposition` components, habit strengths,
  commitments, decision indexes, and agency RNG state.
- **Determinism:** fixed-point utilities, ties broken by seeded streams per
  agent and decision, and decisions that don't depend on order.

### 17. Interface sketch

Illustrative only; this has not been compiled.

```objc
@protocol BGGoalGenerator
- (void) candidatesFor:(BGEntityID) agent
                  view:(id <BGKnowledgeView>) view
                  into:(BGGoalList *) goals;
@end

@protocol BGMethod
+ (BGMethodDeclaration *) declaration;      // goal, preconditions, decomposition
- (BOOL) applicableFor:(BGEntityID) agent view:(id <BGKnowledgeView>) view;
- (BGPlan *) expandFor:(BGEntityID) agent view:(id <BGKnowledgeView>) view;
@end

@interface BGAgency : NSObject
- (BGDecision *) decide:(BGEntityID) agent
                     at:(BGDecisionPoint *) point
                   view:(id <BGKnowledgeView>) view;
- (BGSalience) salienceFor:(BGEntityID) agent of:(id) item;
@end
```

## Scenarios

Each scenario lists its purpose, setup, sequence, choices and uncertainty,
observable information, and acceptance checks. Names are illustrative.

### Scenario 1: The missing wrench

**Purpose:** acting on stale beliefs, a failed precondition producing an
instrumental goal, search ordered by belief, asking for information, and
commitment persisting through a subgoal. It follows on from ACTIONS.md
Scenario 3, where an NPC took the wrench.

**Setup**

- Oskar, a fitter, has a shift from 8 to 16 at the mill (an employment
  commitment).
- Oskar has a strong habit of hanging the wrench on the hook. Oskar believes
  it is on the hook: last confirmed yesterday at 16:00, and tool locations
  usually persist for days.
- In truth, the wrench is in a sack in the loft.
- Ulla, a coworker, saw the visitor carrying a wrench yesterday.

**Sequence**

1. At 08:00 the routine generator scores *work shift* highest. The method
   *maintain pump* requires the wrench, and the precondition holds *in
   Oskar's view*.
2. Oskar fetches from the hook. Perception finds it empty, and the belief is
   updated. The precondition fails, so there is a decision point.
3. The instrumental generator proposes *seek missing tool*.
   - The search method orders places by Oskar's belief that the wrench is
     there: workbench, toolbox, by the pump.
   - The loft scores low.
4. The search fails. Next comes the *ask coworker* method alternative. Ulla
   answers: "I saw the visitor with it yesterday." Oskar's credence that the
   visitor took it rises.
5. The wrench is the miller's. Oskar's norms and loyalty favour *report to
   miller* over *confront visitor*.
6. Throughout, *work shift* remains the intention. *Seek missing tool* is a
   subgoal, and Oskar returns to the shift once it resolves, or abandons it
   once it is believed impossible.

**Variants**

- **A:** a higher curiosity disposition widens the search, which then reaches
  the loft and finds the wrench.
- **B, omniscient stub:** with an omniscient knowledge view, Oskar walks
  straight to the loft. This shows the dependency on knowledge is real.

**Choices and uncertainty**

- Oskar doesn't know where the wrench is, or who took it.
- Ulla's claim may be wrong.

**Observable information**

- **Player:** Oskar's visible behaviour: going to the hook, searching,
  talking to Ulla, going to the miller.
- **Developer:** each decision point's candidates, considerations, method
  order, and failed preconditions.

**Acceptance checks**

1. **The knowledge view drives everything.** Every precondition, binding,
   and search ordering comes from it. Variant B's behaviour differs
   observably.
2. **Failure produces a goal:** the failed precondition yields *seek missing
   tool* deterministically.
3. **Search order** follows Oskar's beliefs, not the truth.
4. **Commitment persists:** *work shift* stays the intention through the
   subgoal.
5. **The decision log** explains every choice.
6. **Determinism:** replay is bit-identical.

### Scenario 2: The false alarm

**Purpose:** utility weighted by credence, the margin and interruption cost,
resistance to dithering, trust updates, and autopilot returning control.

**Setup**

- Night. Bela, a watchman, is on a guard-duty commitment and is eating supper
  at the gate. Eating is a suspendable activity.
- An unattributed rumour has reached Bela: "someone's been getting into the
  warehouse at night." This uses the rumour pattern from KNOWLEDGE.md
  Scenario 1.
- A cat knocks over a tin in the warehouse. Bela hears it at a distance,
  muffled.

**Sequence**

1. The noise is perceived, and interpretation produces "something moved in
   the warehouse". It is salient: an anomaly, plus the duty commitment.
2. Utility for *investigate disturbance* combines:
   - credence of an intrusion (rumour plus noise)
   - duty
   - risk, weighted by risk tolerance
3. It is compared against eating supper plus the margin and interruption
   cost.

**Variants**

- **A, no rumour:** the noise alone falls below the threshold. Bela keeps
  eating, and notes it.
- **B, rumour:** Bela investigates, finds the cat, and updates beliefs. Bela's
  trust in the rumour lowers credence in its claim.
- **C, rumour deflated first:** Bela earlier asked where the rumour came
  from, which merged its groups and lowered credence. The same noise no
  longer triggers an investigation.
- **D, repeated noises:** a series of small noises at slightly varying
  salience. Bela's intention does not flip back and forth between eating and
  investigating.
- **E, autopilot:** the player controls Bela, with the autopilot mode *keep
  watch*. In variant B's conditions, the noise exceeds the player's threshold
  and control returns to the player.

**Choices and uncertainty**

- Bela doesn't know whether the rumour is true or what made the noise.

**Observable information**

- **Player:** whether Bela gets up, and what is found.
- **Developer:** the consideration values in each variant, the margin
  comparisons, and trust before and after.

**Acceptance checks**

1. **Credence changes the decision:** the same noise leads to different
   decisions in variants A, B, and C, driven only by credence.
2. **Margin and interruption cost** decide the comparison with supper.
3. **No dithering:** in variant D, the intention changes at most once.
4. **Trust** in the source decreases after the cat is found.
5. **Autopilot:** in variant E, control returns at the salience crossing,
   and autopilot never uses information Bela lacks.
6. **Determinism.**

### Scenario 3: The tempting purse

**Purpose:** dispositions and norms, the belief about being observed versus
true observation, method alternatives, commitments as motivation that isn't
a body need, and consequences flowing through knowledge.

**Setup**

- A market stall. A purse lies on the counter. The merchant owns it (a
  reified claim).
- Kasimir:
  - has a debt due tomorrow, a commitment with an urgency curve
  - has low honesty, moderate risk tolerance, and a weak "don't steal" norm
- The merchant turns away to serve another customer.
- Mira, a child, stands half-hidden in a doorway, in view of the counter.

**Sequence**

1. The debt commitment generates *get money*. Its method alternatives are
   *borrow from a friend*, *ask for work*, and *take the purse*.
2. Scoring *take the purse* includes the belief about being observed:
   - The merchant is believed to be facing away.
   - Kasimir's attention is on the merchant, and Mira is partly occluded, so
     Kasimir has no referent for Mira. Kasimir believes no one is watching.
3. Kasimir takes the purse.
4. Mira perceives the event. Mira's knowledge store gains the observation,
   with a referent for Kasimir that Mira recognizes.
5. Later, Mira tells the merchant (a decision point for Mira: *answer when
   addressed*, or a reactive *report*). The merchant's beliefs and decision
   follow. Sanctions are §6.

**Variants**

- **A:** Kasimir notices Mira. The belief about being observed lowers *take
  the purse* below *borrow from a friend*, and Kasimir walks away.
- **B:** a high-honesty agent with the same debt never takes the purse,
  whatever the belief about being observed.
- **C:** Mira isn't actually there. Behaviour is identical to the base case,
  but there is no witness.

**Choices and uncertainty**

- Kasimir doesn't know about Mira.
- Mira chooses whether to tell, which depends on Mira's own dispositions and
  loyalties.

**Observable information**

- **Player:** depends on vantage point. The theft, Mira's presence, what Mira
  says later.
- **Developer:** Kasimir's believed observers versus true observers, and the
  scores for each method alternative.

**Acceptance checks**

1. **Belief, not truth, governs the decision.** The theft happens in the base
   case even though a witness is truly present. Variant C makes the same
   decision as the base case.
2. **Observation changes the outcome:** in variant A, noticing Mira changes
   the choice of method.
3. **Dispositions and norms** change the outcome in variant B.
4. **Commitments motivate:** the debt drives the goal without any body need.
5. **Consequences flow through knowledge:** Mira's observation and claim pass
   through KNOWLEDGE.md as specified.
6. **Determinism.**

## What we take from other approaches

| Source | Idea | Here |
| --- | --- | --- |
| Utility AI | Scoring competing goals with consideration curves | Goal selection in fixed point |
| HTN planning | Authored methods with preconditions and decompositions | Methods built on recipes; no search |
| BDI | Intentions persist until achieved, impossible, or overridden | Commitment margin with interruption cost |
| Shadows of Doubt | From precomputed routines to goals; reduced AI frequency far from the player | Routines as default goals; reserved fidelity levels |
| Dwarf Fortress | Independent jobs and needs generate situations | Generators for needs, routines, and reactions |
| RimWorld | A storyteller for pacing | Deliberately separate; agency only reacts |
| DESIGN.md | Investigate, seek a tool, protect a possession, request help | The initial reactive, instrumental, and social generators |

## Open questions

1. **Consideration curves.** How are they represented in content, and how are
   considerations combined (product, weighted sum, or a mix)?
2. **Theory of mind.** How deeply do agents model each other: trust,
   inferred goals, predicted reactions? Trust is the minimum.
3. **Fidelity levels.** What each level computes, how promotion and demotion
   work, and summary traces.
4. **Emotion and mood.** Fear, anger, and grief as modifiers on utility and
   attention. When, and how far?
5. **Learning.** Beyond habit strength: changing dispositions, and procedural
   knowledge (KNOWLEDGE.md open question 7).
6. **Coordination.** Groups, crews, crowds, and joint activities (ACTIONS.md
   open question 6).
7. **Wants beyond body needs and commitments.** Wealth, status, curiosity,
   faith: how generators for these arise, especially with §6 and economics.
8. **Autopilot.** Which modes are worth having, and how the player sets
   thresholds.
9. **Pressure generators.** A storyteller for pacing is outside agency, but
   we need to design one eventually.
