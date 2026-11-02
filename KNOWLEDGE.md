# Knowledge

## Status and scope

Proposal. This document specifies the system sketched in
[DESIGN.md](DESIGN.md) §4, "Events, evidence, observations, and beliefs".
We call it the **knowledge system**. It covers:

- history (what happened)
- traces (physical evidence)
- perception
- observations, interpretations, claims, and beliefs
- memory
- the player's view of the world

It implements the knowledge-view stubs in [ACTIONS.md](ACTIONS.md) §3, and it
is the only route by which any agent, the player's character included, learns
anything. See [ARCHITECTURE.md](ARCHITECTURE.md) for how it fits with the
other systems.

Out of scope here:

- why agents act on their beliefs (§5)
- whether institutions recognize claims (§6)
- the language for propositions and interpretation rules, now in
  [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md) (§9–11 there cover matching,
  recognition by unification, and memory decay as generalisation)

## Proposed decisions

These were made while writing this document and have not yet been reviewed.

1. **Eight layers, kept distinct:** world state, history, traces, records,
   observations, interpretations, claims, and beliefs. Agents never read
   world state or history directly.
2. **Traces are component state** on bodies and tiles. They age
   analytically, computed when read with no per-step cost. Operations that
   remove traces declare the traces they leave behind.
3. **Appearance is separate from truth.** Components may declare appearance
   fields, such as surface material, that differ from the true fields.
   Perception reads appearance. Analysis operations reach deeper.
4. **Senses are capabilities.** Instruments extend them through the same
   instrument chains as manipulation (ACTIONS.md §2).
5. **Beliefs are about referents, not entity IDs.** A referent is an
   agent-local handle such as "the figure in the dark coat". Its link to the
   true entity is visible only to developers. This is what makes
   misidentification, disguise, and confusing two things possible.
6. **Beliefs are time-indexed.** "The door was open at 09:40" is stored. "The
   door is open" is inferred from it, using how long that kind of fact usually
   persists. Stale knowledge is the normal state of affairs.
7. **Credence is fixed-point log-odds.** Evidence is grouped by perceived
   root source, and each group counts once. Repetition is therefore not
   corroboration, *as far as the agent can tell*. The system records true
   ancestry separately, so the developer can see false corroboration.
8. **Knowledge stores are private, and written only by the knowledge
   system** in a perception phase after each boundary's commit rounds. They
   do not go through change commitment. Change commitment remains the only
   writer of shared world state.
9. **The player's character uses the same machinery as every NPC.** The map,
   the inspector, and the notebook view are views of that character's
   knowledge store. Physical notebooks are records that can be stolen. The
   player's own out-of-character notes live in the UI only.
10. **Memory decays analytically**, losing detail and strength, and is
    bounded per agent, with deterministic eviction by salience.
11. **A conclusion is retracted only when its premise is contradicted**
    (§9), never because a trace fades or vanishes: fresh paint dries, and
    the wall was still touched up; a mark gone is itself evidence of a
    cover-up. Contradicted means the agent learns the premise was wrong:
    it sees again, closely, no trace where one should still be, or is
    told a credible other cause. A premise over repetition is contradicted
    when the repetition moves on (the lab's habit beliefs).
12. **Memory and perception form doubts of their own** ("it was X, or
    maybe Y"; CONTENT_LANGUAGE.md Scenario 2's half-remembering), whenever
    forming or recalling a memory goes worse than usual. The sources so
    far, open to more:
    - *decay*: as a feature generalizes ("19 mm" to "a spanner size"), the
      specific value lingers as a competing hypothesis, fading with it;
    - *confusion*: two similar things, or events, encoded or recalled
      together;
    - *distraction*: little attention left when it was taken in (§5, the
      attention budget);
    - *impairment*: the perceiver's state (exhaustion, injury, adrenaline,
      intoxication) degrading what it takes in or recalls;
    - *poor sight*: seen in poor conditions (dusk, distance), something
      that could be either of two known things is held as both.
13. **Believed the same, two referents merge.** Past a credence threshold
    (content declares it), an identity hypothesis ("R5 may be R2") merges
    them into one: features unified, beliefs and testimony pooled. A wrong
    merge is the "two people taken for one" error (§6), and stands until
    evidence splits them again (both seen at once).
14. **Light and sound are domains** (DOMAIN_SIMULATION.md), giving
    perception its conditions (§5). Light: lamps and fires burn their fuel
    down, daylight follows the clock, rooms and doors shade it. Sound:
    it propagates through rooms and doors, walls muffle it, and noise
    masks what is quieter.
15. **Trust comes from relationships, disposition, and conduct.** Starting
    trust in someone comes from the relationship (kin, coworker, employer,
    stranger) and a trusting or suspicious disposition; loyalty
    (AGENCY.md decision 12) raises it; being harmed or wronged by them
    lowers it, as does seeing them lie or break a rule. Claims confirmed
    and refuted, and promises kept and broken, still move it (§10).
16. **Detail fades as strength does**: a memory's features generalize at
    the same rate its strength fades (§12), slower for what was salient or
    seen again and again, so a vivid or familiar thing keeps its
    specifics longer.

## Terms

| Term | Meaning |
| --- | --- |
| History | The log of committed events. Developer truth. |
| Event | One committed change set, with its roles, cause, time, and place (ACTIONS.md §9) |
| Trace | Physical evidence on a body or tile: tool marks, residue, a footprint, fresh paint, a bent part |
| Record | Content inscribed on a physical copy: a ledger, a diagram, a notebook page (COMPONENTS.md §8) |
| Appearance field | What a field looks like to the senses. It may differ from the true field. |
| Sense | A perceptual capability: vision, hearing, touch, smell, or an instrument reading |
| Conditions | What limits perception: light, distance, noise, occlusion, attention |
| Percept | What one act of perception yields: features with precision |
| Referent | An agent-local handle for something the agent thinks exists |
| Truth link | A referent's hidden link to zero or more true entities. Developer only. |
| Observation | A stored percept: observer, time, modality, conditions, the referents involved, and features |
| Proposition | A typed, time-indexed statement about referents and values |
| Interpretation | A proposition derived from observations and beliefs by a rule, given expertise |
| Claim | A proposition asserted by a source, carried in content: an utterance or a record |
| Attribution | The source a claim names for itself: "I saw", "Teodor told me", "the ledger says" |
| Belief | A proposition held by an agent, with credence and provenance |
| Credence | Degree of belief, stored as fixed-point log-odds |
| Provenance | What supports or undermines a belief: observations, claims, inferences |
| Perceived root | The original source of a piece of evidence, as far as the agent can tell |
| True root | The original source of a piece of evidence in fact: an observation or a fabrication |
| Salience | How much something matters to an agent. It drives what gets stored and remembered. |
| Knowledge store | One agent's referents, observations, and beliefs |
| Knowledge view | The interface that actions and agency use to query a knowledge store |

## The knowledge contract

### 1. The layers

| Layer | Example | Lives in | Who reads it |
| --- | --- | --- | --- |
| World state | The valve is seized | Components, domains | Engine; developer |
| History | Teodor applied 70 Nm to the handle at 09:41 | History log | Developer; the causal inspector |
| Traces | Fresh tool marks on the handle | Component state | Anyone who perceives them |
| Records | The maintenance ledger | Content and copies | Anyone who reads them |
| Observations | Marius saw a figure at the back door | A knowledge store | Its agent |
| Interpretations | "Someone forced the valve" | A knowledge store | Its agent |
| Claims | "Marius says a figure went in" | Content (utterances, records) | Anyone who hears or reads them |
| Beliefs | Ines thinks it was probably Piet | A knowledge store | Its agent |

**The rule:** agents learn only through perception. That means perceiving
events as they happen, examining state and traces, reading records, and
hearing claims. History is never an agent input.

### 2. History

- Every committed event from change commitment enters the history log, with
  its roles, cause, simulation time, location, and the committing group.
- **Retention tiers**, following Shadows of Doubt's warning about memory
  cost:
  1. **Significant**: kept indefinitely. Event kinds can be declared
     significant (deaths, transfers of ownership, institutional acts), or an
     event can be marked significant by its consequences.
  2. **Referenced**: kept while any trace, record, observation, belief, or
     open activity references it.
  3. **Routine**: compacted into per-region summaries once no reference
     remains.
- Compaction is deterministic and runs at declared intervals.
- History serves the developer's causal inspector and the provenance of
  traces. It is never a gameplay input. A trace whose cause event has been
  compacted keeps everything about itself; only the developer link becomes a
  summary.

### 3. Traces

- A trace is an entry in a body's or tile's trace list, holding:
  - kind and magnitude
  - creation time
  - a decay profile
  - the conditions that speed up decay (rain, foot traffic, heat)
  - its cause event, a developer-only link
- **Aging is analytic.** How perceivable a trace is gets computed from its age
  and conditions when someone perceives it. There is no per-step cost. A
  trace whose perceivability would fall below its kind's floor is removed at
  that time, which the trace system reports to the scheduler as a
  `nextEvent`.
- **Traces come from committed effects.** Operations and reactions declare
  the traces they leave: a wrench on a handle leaves tool marks, a body on a
  floor leaves scuffs, a fire leaves soot.
- **Evidence is manipulated through ordinary actions**: cleaning, repairing,
  repainting, replacing, moving, destroying. **Every operation that removes
  traces declares what it leaves**, such as a damp floor, a soap smell, fresh
  paint, or a missing tool. That rule is what makes cover-ups detectable
  rather than perfect.
- Traces on stacks trigger automatic individuation (COMPONENTS.md §9). Traces
  are physical distinctions, so marked units never merge.

### 4. Appearance and truth

- A component field may declare an **appearance field**: what the senses
  report, as opposed to what is true.
  - A plated fitting has surface material brass and true material steel.
  - A disguised person has an apparent face and clothing.
  - A forged seal impression looks like the office's seal.
- **Perception reads appearance fields** where they exist, and true fields
  only where the field declares itself directly perceivable.
- **Analysis operations reach deeper**: a scratch test, an acid test,
  unmasking, comparing a seal with a known genuine impression. Each is an
  ordinary operation (ACTIONS.md) whose observation effect reads the
  next-deeper field, and which may leave its own traces (a scratch).

### 5. Perception

**Inputs**

- **Senses are capabilities**, provided by body parts with capacities such as
  acuity, range, and spectrum. Instruments extend or transform them through
  instrument chains: eye → magnifier, hand → thermometer probe, ear →
  stethoscope. Injury reduces senses through modifiers.
- **Conditions** limit perception: light, distance, noise, occlusion. These
  come from a conditions provider. Light and sound may become domains later;
  for now they are stubs with authored values. Occlusion is terrain's
  (TERRAIN.md): sight stops at an opaque cell, and what an agent has seen of
  the terrain is kept as a bit per tile, not a copy.
- **Attention** is limited. Each perceiver has an attention budget per
  boundary. Salience decides what gets attention first.

**Three triggers**

1. **Event perception.** In the perception phase after each boundary's commit
   rounds, the system finds every committed event's perceivers through a
   spatial query bounded by sense range. Only entities with a `Perceiver`
   component count. Each perceiver gets a percept of the parts of the event
   their senses and conditions allow.
2. **State perception.** When a perceiver attends to something, it perceives
   that thing's current state, through its `perceive` field declarations
   (COMPONENTS.md §2). Attending happens through the *inspect* operation, on
   arriving somewhere, or when the field of view changes. Domains provide
   measurements, such as the air at a tile or the surface temperature of an
   entity. Perception turns those into percepts with the sense's precision:
   "warm", or "34 ± 2 °C" with a thermometer.
3. **Trace perception.** Examining an entity or tile perceives its traces,
   weighted by trace age, the sense used, and expertise.

**Field of view and map memory**

The classic roguelike field of view and remembered map are exactly this
system. What the player sees is their character's current percepts. What
they remember is their character's time-stamped beliefs.

**Output**

- Percepts are features with precision, attached to referents (§6). They are
  never attached to entity IDs.
- Perceptual noise is drawn from seeded streams per perceiver and event.

### 6. Referents

- A **referent** is an agent-local handle for something the agent thinks
  exists. It holds the features the agent associates with it, any names it
  goes by, and its kind as recognized.
- **Recognition** matches a new percept against the agent's existing
  referents, using perceived features and the agent's expertise:
  - a strong match binds the percept to that referent
  - a weak match may create a new referent, or tentatively link to one
- **The truth link is developer-only.** It records which true entities a
  referent actually tracks: one, several (two people confused for one), or
  none (an invention). **Agent reasoning never consults the truth link**, not
  even as an optimization.
- **Identification errors are first-class:**
  - *merging*: two people taken for one
  - *splitting*: one person taken for two
  - *misbinding*: a disguise succeeds
  - *invention*: a referent with nothing behind it

  The developer inspector shows each of these against the truth links.
- A referent may become linked to a **name**. A name is itself a claim: "that
  is Piet", told by someone or read on a document.

### 7. Observations

An observation holds:

- the observer
- the time
- the modality and sense chain used
- the conditions
- the referents involved, with their roles in what was perceived
- the features perceived, with their precision
- a developer-only link to the observed event or state

Observations are stored only when they are salient enough for that agent.
Salience comes from the agent's goals, norms, threats, anything unusual, and
explicit attention.

### 8. Propositions

- A proposition is a typed predicate over referents and values, each value
  carrying units and precision. Examples: `entered(R7, R2)`,
  `temperature(R3) ≈ 30 °C ± 2`, `owns(R4, R9)`, `caused(R11, R12)`.
- **Propositions are indexed by time**: at an instant, over an interval, or
  "since". Beliefs are stored as *what was the case when*.
- **Currency is inferred.** Each predicate kind declares how long its facts
  usually persist. A person's location changes within minutes, a door's state
  within hours, a building's existence within decades. The knowledge view
  derives "probably still true" from the age of the belief and that
  persistence. The engine never quietly keeps beliefs up to date.
- Propositions are written in the content language
  ([CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md) §5, §11): typed predicates,
  unification over features, and units, with precision as intervals.

### 9. Interpretation

- **Interpretation rules** derive propositions from observations and
  beliefs. Rules are content, and each declares the expertise it requires.
  - "Bright tool marks on old paint" ⇒ recent tool use.
  - "Damp floor and a soap smell in a dry workshop" ⇒ recently cleaned.
- **Expertise gates both which rules apply and how precise their results
  are.** A novice sees "scratches". A fitter sees "a 19 mm wrench slipped".
  This is where knowledge stops being a skill bonus and starts changing what
  a character can conclude, as CHAT.md proposed.
- **Two modes:**
  - **Immediate**: cheap rules that run on observation, within the attention
    budget.
  - **Deliberate**: investigating is an activity, with operations such as
    examining, comparing, reconstructing, or thinking it over. It spends time
    and runs costlier rules over the knowledge store.
- An interpretation's provenance records the rule and its premises, so
  interpretations can be retracted when a premise is.

### 10. Claims and communication

- **Utterances.** The *communicate* operation (ACTIONS.md) commits an
  utterance event, which references content. The content holds the claim's
  propositions and the attribution the speaker chose: "I saw", "I heard from
  Teodor", "everyone says". Content entities follow COMPONENTS.md §8.
- **Hearing.** Hearers perceive the utterance through event perception
  (hearing, conditions, language). Each hearer stores an observation that the
  speaker said this, then forms a belief through their trust in the speaker
  and the attribution given.
- **Records** work the same way. Reading is state perception of an
  inscription, so it yields "the ledger says …". Forged records carry claims
  whose actual origin differs from the origin they state.
- **Lying** is communicating propositions the speaker doesn't believe. The
  speaker's knowledge store marks it as such, and the history records a
  fabrication root (§11).
- **Questioning** is communication asking for attribution or detail: "Who
  told you?". Answers are claims and may themselves be false.

### 11. Beliefs and credence

A belief holds a proposition, a credence, its provenance, when it was
acquired, when it was last confirmed, and its salience.

**How credence is computed**

1. Credence is stored as **fixed-point log-odds**. Updates use lookup tables
   (ARCHITECTURE.md: no floating point in authoritative state).
2. Each provenance item contributes a log-likelihood ratio. The ratio depends
   on:
   - for an observation: the sense precision and conditions
   - for a claim: trust in the source, and the attribution given
   - for an interpretation: the rule's strength and the credence of its
     premises
3. Items are **grouped by perceived root**. Within a group, only the
   strongest item counts. Across groups, contributions add. So three people
   repeating what they all heard from Marius count once, *if the agent knows
   they all heard it from Marius*.
4. Items whose perceived root is unknown each form their own group. That is
   how rumours inflate: an agent who doesn't know two claims share a source
   counts them twice. Questioning sources (§10) can merge the groups and
   deflate the credence again.

**True ancestry versus perceived ancestry**

- **True ancestry** is the chain through history: the original observation or
  fabrication, then the utterances, then each hearer's belief, then their own
  utterances. The system records it for every claim, developer-only. This is
  how "the system distinguishes repetition from corroboration", as DESIGN.md
  §4 asks.
- **Perceived ancestry** is what the agent knows of the sources. Credence uses
  only perceived ancestry.
- The developer inspector flags **false corroboration** (groups the agent
  treats as independent that share a true root) and **fabrication roots**.

**Trust and conflict**

- **Trust** in a source is itself a set of beliefs about that source's
  referent. It is updated when the source's claims are confirmed or refuted.
- **Conflicting beliefs coexist** as competing hypotheses, each with its own
  credence. There is no forced single truth. The notebook view shows open
  questions and their competing hypotheses.

### 12. Memory

- Memory **decays analytically**, computed when read:
  - **Detail** degrades along a feature hierarchy: "grey wool coat" becomes
    "dark coat", which becomes "a coat".
  - **Strength** decays at a rate set by salience and repetition.
- When a belief's strength would fall below the forgetting threshold, it is
  forgotten at a scheduled time, which is a `nextEvent`.
- **Each knowledge store is bounded.** An agent kind declares a capacity.
  When it is exceeded, the least salient items are evicted first, ties broken
  by acquisition order. Eviction is deterministic.
- **Confirmation refreshes.** Perceiving something again updates
  `lastConfirmed` and restores detail.

### 13. The knowledge view

This implements the stubs in ACTIONS.md §3:

| Function | Implemented as |
| --- | --- |
| `formulate(actor, op, bindings)` | The actor has procedural knowledge of the operation (a belief about how to do it, from teaching, reading, or practice) and holds a referent for each role that recognition can resolve to the bound entity |
| `perceivedStateFor(actor)` | Current percepts plus beliefs, with inferred currency. Unknown stays unknown. |
| `expectationOf(actor, action)` | Predictions from the actor's beliefs and the operation's declared effects, interpreted through the actor's rules |
| Recipe expansion | Uses beliefs about structure. Reading a diagram creates beliefs whose provenance is the diagram's claims. |

Agency (§5) queries the same view to choose actions.

### 14. Ownership and the perception phase

- **Knowledge stores are private to their agents** and written only by the
  knowledge system. Updates never conflict across agents, so they do not go
  through change commitment.
- **The perception phase** runs after a boundary's commit rounds and before
  decision points:
  1. event perception for this boundary's committed events
  2. state and trace perception for attention that was requested
  3. immediate interpretation, within each agent's attention budget
  4. belief updates
  5. salience checks that raise soft interruptions and decision points (being
     startled, a suspicion crossing a threshold)
- Agents are processed in stable ID order. Each agent's update depends only
  on committed state and that agent's own store, so the order cannot change
  results.
- **Knowledge affects the world only through actions** chosen at decision
  points. Saying, writing, and acting all go through ACTIONS.md as usual.
- Every update to a knowledge store is traced for the developer inspector.

### 15. The player's view

- **The map** shows current percepts (field of view) plus remembered tiles,
  each displayed with its age. Remembered state is never refreshed by the
  engine.
- **The inspector** describes things at the level of recognition, appearance,
  and precision the character's senses and expertise allow.
- **The notebook view** shows the character's referents, beliefs, competing
  hypotheses, and provenance as the character perceives it. It is a view of
  memory, and cannot be stolen.
- **A physical notebook** is a record. Writing in it is the *copy* operation
  (ACTIONS.md), turning beliefs into content. A physical notebook can be
  stolen, read, forged, or destroyed. A thief who reads it gains beliefs whose
  provenance is that notebook.
- **Out-of-character notes** are the player's own annotations in the UI. They
  never enter the knowledge store and never affect `formulate`. What the
  player knows and what the character knows stay separate, as CHAT.md
  insists.
- **Outcome messages** (ACTIONS.md §4) are composed from the percepts of the
  boundary in which the outcome happened.

### 16. The developer inspector

For any agent or belief, the developer inspector shows:

- the belief's true ancestry and its perceived ancestry, side by side
- false corroboration and fabrication roots
- referents with their truth links, and identification errors
- traces with their cause events, and history around any entity
- "why does this agent believe X?" and "is X actually true?" as separate
  answers

### 17. Scale

- **Locality:** event perception is bounded by sense range, through the
  spatial index. Far-away events cost nothing per agent.
- **Salience filter:** most routine events are never stored by most agents.
- **Bounded stores** and history retention tiers cap memory.
- **Background agents:** agents far from the player may perceive and remember
  at reduced fidelity, with summarized observations. This is
  variable-resolution simulation applied to minds, and is an open question.
- **Analytic decay** of traces and memories means aging costs nothing until
  something is read.

### 18. Saves and determinism

- Saved: knowledge stores (referents, observations, beliefs, provenance),
  trace lists (as component state), the retained history, compaction
  summaries, and perception RNG state.
- Perception noise, recognition ties, and eviction are deterministic: seeded
  per agent, ordered by stable ID.

### 19. Interface sketch

Illustrative only; this has not been compiled.

```objc
@interface BGPercept : NSObject
@property BGReferentID   referent;      // agent-local
@property BGFeatureSet  *features;      // with precision
@property BGModality     modality;
@property BGConditions   conditions;
@end

@protocol BGKnowledgeStore
- (BGReferentID) recognize:(BGPercept *) p;
- (void) addObservation:(BGObservation *) o;
- (BGBelief *) beliefIn:(BGProposition *) p at:(BGTime) t;
- (BGCredence) credenceOf:(BGProposition *) p at:(BGTime) t;
- (NSArray *) provenanceOf:(BGBelief *) b;   // perceived only
@end

@interface BGKnowledgeSystem : NSObject <BGKnowledgeView>
- (void) perceptionPhaseForBoundary:(uint64_t) boundary
                             events:(BGCommitReport *) report;
@end
```

## Scenarios

Each scenario lists its purpose, setup, sequence, choices and uncertainty,
observable information, and acceptance checks. Names are illustrative.

### Scenario 1: The witness and the rumour

**Purpose:** referents and misidentification, claims with attribution,
repetition versus corroboration, true versus perceived ancestry, lies, and
memory decay.

**Setup**

- Night. Piet, wearing a grey wool coat, enters the warehouse by the back
  door.
- Marius watches from 30 m in poor light.
- Nadia passes under a lamp near the door. Nadia knows Piet by sight.
- Also present over the following days: Teodor, Ulla, and the investigator,
  Ines.

**Sequence**

1. **Marius's observation:** a figure in a dark coat entering by the back
   door. Marius creates a new referent, R_M ("dark-coat figure"), with no
   name.
2. **Nadia's observation:** Nadia recognizes Piet. The strong match binds the
   percept to Nadia's existing referent for Piet.
3. **Day 1:** Marius tells Teodor and Ulla, "I saw someone in a dark coat go
   into the warehouse at night."
4. **Day 2:**
   - Teodor tells Ines, attributing it: "Marius saw…"
   - Ulla tells Ines without attribution: "I heard someone went in."
5. **Ines's credence:** Teodor's claim has the perceived root Marius. Ulla's
   has an unknown root, so it forms its own group. Credence is inflated.
6. Ines questions Ulla: "Who told you?" Ulla answers "Marius". The groups
   merge, and credence drops to a single source.
7. **Day 3:** Nadia tells Ines, "I saw Piet go in the back door last night."
   This is a genuinely independent root. Credence rises. An interpretation
   rule (matching time, place, and a coat colour consistent with what Nadia
   saw) tentatively links Ines's referent for the figure to Piet.

**Variants**

- **A, lie:** Marius actually saw no one, and invents the claim. The history
  records a fabrication root, and Marius's store marks the claim as not
  believed.
- **B, decay:** Ines interviews Marius on day 10. By then Marius's
  description has decayed to "someone in a coat", and Marius's confidence
  has fallen.

**Choices and uncertainty**

- Ines chooses whom to question, whether to ask for sources, and how far to
  trust each witness.
- Ines cannot know which claims share a source unless told.

**Observable information**

- **Player (as Ines):** the claims as heard, with their attributions. The
  notebook shows open hypotheses and credences.
- **Developer:**
  - the true ancestry for every claim
  - false corroboration flagged at step 5
  - Marius's referent R_M truth-linked to Piet
  - the fabrication root in variant A

**Acceptance checks**

1. **No IDs in agent data:** Marius's knowledge store never contains Piet's
   entity ID. Only the developer truth link does.
2. **Credence follows perceived ancestry:** credence at step 5 is greater
   than at step 6, and step 6 equals the single-source case.
3. **Genuine corroboration:** Nadia's independent root raises credence above
   the single-source level.
4. **True ancestry** is correct in every case, and the inspector flags step
   5's false corroboration.
5. **Fabrication:** variant A records a fabrication root with no underlying
   observation.
6. **Decay** in variant B is deterministic, follows the feature hierarchy,
   and is identical on replay.

### Scenario 2: The cleaned workshop

**Purpose:** traces from committed effects, analytic aging, cover-ups that
leave their own traces, appearance versus truth, interpretation gated by
expertise and prior beliefs, and investigation as an activity.

**Setup**

- After the seized-valve scenario (ACTIONS.md Scenario 1), the scene holds:
  - bright tool marks on the valve handle's old paint
  - a bent wrench
  - scuffs on the floor
- The fitting next to the valve looks brass but is brass-plated steel.

**Sequence**

1. **The saboteur covers up:**
   - mops the floor, removing the scuffs and leaving a damp floor and a soap
     smell
   - swaps the bent wrench for an identical new one and hides the bent one in
     a sack in the loft
   - repaints the handle, covering the tool marks and leaving fresh paint and
     a paint smell
2. **The next morning:**
   - the damp floor has dried (its trace has expired)
   - the soap smell is faint
   - the paint is touch-dry but still smells
3. **The investigator** runs an *investigate workshop* activity:
   - Perception picks up the faint soap smell, the fresh paint, and a wrench
     on the hook that looks new.
   - The interpretation "the wrench was replaced" fires only if the
     investigator believes the workshop's old wrench was worn. Without that
     prior belief, a new-looking wrench means nothing.
   - The interpretation "the handle was repainted recently, so something
     happened to it" requires expertise in painting.
4. **The plated fitting:** the investigator identifies it as brass. A scratch
   test, an analysis operation, reveals steel underneath and leaves a scratch
   trace.

**Choices and uncertainty**

- The saboteur chooses what to clean, and accepts the traces cleaning leaves.
- The investigator chooses what to examine and whether to run analysis
  operations.
- The investigator doesn't know which traces are cover-up traces.

**Observable information**

- **Player (as investigator):** traces at their current perceivability, and
  interpretations the character's expertise permits.
- **Developer:** every trace's cause event, the cover-up's removal and
  creation of traces, and the true material.

**Acceptance checks**

1. **Traces are component state** with no per-step cost. Perceivability at
   inspection time follows each profile's age curve, and expired traces are
   removed at their scheduled times.
2. **Every removal leaves a trace:** each trace-removing operation in the
   cover-up adds its declared traces.
3. **Appearance:** perception reports brass. Only the scratch test reveals
   steel, and it leaves a scratch.
4. **Prior beliefs gate interpretation:** "wrench replaced" fires with the
   prior belief and not without it.
5. **Expertise gates interpretation:** the repaint inference requires
   expertise. A novice sees only "paint".
6. **No truth leaks:** the investigator's percepts never contain cause
   events. The developer inspector shows the full chain.

### Scenario 3: The player's map and notebook

**Purpose:** field of view and map memory as perception plus belief, stale
time-stamped beliefs, the menu built from the knowledge view, physical
notebooks as stealable records, and out-of-character notes.

**Setup**

- The player's character explores the mill and remembers its layout.
- While the character is away, an NPC closes the loft door and moves the
  ladder.

**Sequence**

1. **Returning:** the map shows the loft door as open, labelled with the age
   of that memory. The ladder appears where it was.
2. **The menu** offers *move through loft door*, built from the remembered
   open door. The move's stage commits an attempt to walk into a closed door.
   Perception updates the belief, and the outcome message says the door is
   closed.
3. **The notebook:** the character writes an entry in their notebook,
   recording a sketch of the pump and the suspicion "the saboteur used the
   loft". This is the *copy* operation: beliefs become content with the
   character as author.
4. **Theft:** an NPC steals the notebook and reads it. The thief gains
   beliefs whose provenance is the notebook, attributed to the character.
5. **Memory survives:** the character's memory is untouched, though its
   detail decays as usual. The player's out-of-character note ("check the
   loft again") stays in the UI.

**Choices and uncertainty**

- The player chooses what to write down, where to keep the notebook, and
  whether to trust their memory or go and look.
- The player doesn't know what changed while they were away.

**Observable information**

- **Player:** the map with ages on remembered tiles, the notebook view, and
  the physical notebook's presence or absence.
- **Developer:** the true layout, the thief's new beliefs and their
  provenance.

**Acceptance checks**

1. **The map renders only from the knowledge store** and current percepts.
   Remembered tiles carry their age, and the engine never refreshes them.
2. **The menu comes from the knowledge view:** *move through loft door* is
   offered from the stale belief. The bump updates the belief through
   perception.
3. **Notebook content** is a content entity authored by the character, with
   claims copied from beliefs at the time of writing.
4. **The thief's provenance:** the thief's beliefs cite the notebook, with
   the character as perceived root.
5. **Theft doesn't erase memory:** stealing the notebook leaves the
   character's knowledge store unchanged.
6. **Out-of-character notes** never appear in the knowledge store and never
   affect `formulate` or recipe expansion.

## What we take from Shadows of Doubt and CHAT.md

| Source | Idea | Here |
| --- | --- | --- |
| Shadows of Doubt | Everything can become evidence | Traces from committed effects; records; testimony |
| Shadows of Doubt | Evidence graph with suspicion propagated by reliability | Credence by log-odds, grouped by perceived root |
| Shadows of Doubt | Memory cost of keeping history discoverable | Retention tiers, analytic decay, bounded stores, salience filtering |
| CHAT.md | World, history, evidence, belief kept distinct | Eight layers; agents never read world state or history |
| CHAT.md | Claims with provenance and source | Content entities with attribution; true and perceived ancestry |
| CHAT.md | Identifying alloy by colour, wrong because of plating | Appearance fields and analysis operations |
| CHAT.md | Notebook as knowledge base; player and character knowledge differ | Notebook view, physical notebooks, and out-of-character notes |

## Open questions

1. **Proposition and rule language.** Specified in
   [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md). Knowledge remains its most
   demanding user: recognition, hypotheses, and decay all run on it.
2. **Light and sound.** Decided: decision 14.
3. **Background agents.** How does reduced-fidelity perception and memory work
   for distant agents, and how is a background agent promoted back to full
   fidelity?
4. **Recognition thresholds.** How do features, expertise, and conditions
   combine into a match? How often should merge and split errors happen to
   make good gameplay without being frustrating?
5. **Salience model.** What makes an event worth storing for a given agent?
   [AGENCY.md](AGENCY.md) §10 now supplies the salience function. Its
   weights and thresholds still need tuning against the scenarios.
6. **History compaction.** What do summaries contain, and is any of it
   gameplay-visible, as rumour or local lore?
7. **Procedural knowledge.** How are teaching and learning by practice
   represented? This was a DESIGN.md scenario and needs its own treatment.
8. **Shared and institutional knowledge.** How do group-level beliefs, such
   as what the guild knows, relate to individual stores? Waits on §6.
