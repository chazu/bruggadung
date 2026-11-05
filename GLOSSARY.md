# Glossary

## Status and scope

The ubiquitous language of bruggadung: the words the design docs, the
content, the code, commits and conversation all use, each in one sense.
Where the docs have used two words for one thing, the glossary names one
and lists the others under *Avoid*. Where they have used one word for two
things, it names each sense separately, and the section **Words with more
than one sense** at the end says which word goes with which.

Rules:
- Use these terms, in these senses, everywhere: docs, Triangle content,
  identifiers, comments, commit messages, and talk about the project.
- A word under *Avoid* is not used for that concept in new writing. Old
  text is corrected when it is next touched.
- A concept without an entry gets one, in the same change that introduces
  it. A term that changes meaning is changed here first.
- The design docs are authoritative for detail; each entry names the doc
  and section it comes from.

Doc abbreviations: ACT = ACTIONS.md, AGE = AGENCY.md, ARC =
ARCHITECTURE.md, CL = CONTENT_LANGUAGE.md, COM = COMPONENTS.md, DES =
DESIGN.md, DOM = DOMAIN_SIMULATION.md, DR = DETAIL_REGIMES.md, INS =
INSTITUTIONS.md, KNO = KNOWLEDGE.md, LAT = LATENT_ASSEMBLY.md, REA =
REALITY.md, PRF = PERFORMANCE.md, TER = TERRAIN.md, TES = TESSERA.md, VIL = VILLAGE.md. "d3" is a doc's decision
3; "§3" its numbered section.

## The project

- **Bruggadung**: the project: a maximalist, tile-based roguelike whose
  many deeply simulated systems connect into decisions the player notices.
  The framework is built first, then the game. (DES)
- **Framework**: the common engine for actions and consequences, with the
  systems beneath it. *Avoid:* engine (reserved for Triangle's and
  Tessera's engines). (DES)
- **The lab**: the simulation laboratory in `lab/` (Odin) that
  implements the system contracts and proves them by scenarios; it has
  stepping, inspection, causal traces and `lab play`. *Avoid:* simulation
  lab, harness (for the whole). (DES, lab/README.md)
- **Triangle**: the content language (typed feature structures, TDL
  semantics, CUE-style syntax), files `.tri`, and its C engine in
  `triangle/`. (CL)
- **Tessera**: the visual engine in `tessera/`: shows tile worlds with
  levels, from the two views; knows tiles, levels, layers, appearances,
  cameras; knows nothing of pumps or agents. (TES)
- **Content**: everything authored in Triangle: types, blueprints,
  operations, goals, methods, rules, dials. "Content is the source of
  truth." Not the `Content` component, nor the `content` field flag. (CL)
- **Contract**: one system's proposed interface and rules, tested by
  scenarios. (ARC)
- **Scenario**: a designed test case: purpose, setup, sequence, choices,
  observable information, acceptance checks. Run headless by the
  **scenario harness**. Every scenario keeps its results as the lab
  grows. (COM, ARC)
- **Acceptance check**: a verifiable criterion a scenario must meet. (COM)
- **Design doc**: one of the top-level `.md` documents. *Avoid:* spec
  (reserved for Triangle's resolved blueprint).
- **Developer view / player view**: the two views. The developer view
  shows the truth and its causes; the player view shows only what the
  character perceives or infers. Nothing in the player view may leak the
  truth (**no leaks**). (DES §4, ARC)
- **Developer inspector**: the developer's tool for causes: true and
  perceived ancestry, truth links, why an agent believes something. *Avoid:*
  causal inspector. The **player's inspector** describes things only as the
  character can. (KNO §15, §16)

## The systems

- **System**: one of the parts that run the world: actions, components,
  domains, knowledge, agency, institutions, with change commitment across
  them; and, for detail regimes, anything a regime can set a mode for
  (perception, decision, needs, a domain, news). Domains are systems; not
  all systems are domains. (DES, DR)
- **Actions**: the system of capabilities, operations, actions and
  activities. (ACT)
- **Components**: the system of entities, components, relations and
  identity on demand. (COM)
- **Domain simulation**: the system that evolves physical quantities over
  time, by domains. (DOM)
- **Knowledge**: the system of history, traces, perception, referents,
  claims, beliefs and memory; the only way any agent learns anything. (KNO)
- **Agency**: the system that decides what an agent does next, and tells
  perception what matters; it never changes the world directly. (AGE)
- **Institutions**: the system of organizations, offices, rules and
  sanctions; organizations act only through their members. (INS)

## Entities and components

- **Entity**: anything with identity: a creature, an object, an
  organization, a claim, an activity. It is an ID (`BGEntityID`, 64-bit,
  never reused). *Avoid:* object, thing (in technical writing). (COM d1)
- **Physical entity**: an entity with a `Body` and a location.
  **Informational entity**: one with neither (content, an organization, a
  claim, an activity, a trace). (COM)
- **Component**: one instance of a component kind on one entity. (COM)
- **Component kind**: a kind of state and behaviour (`Body`,
  `ThermalBody`, `Stack`), declared in content by `@component`. (COM, CL §3)
- **Blueprint**: content describing what an entity is made of: its
  component kinds and their fields' values, or the ranges and alternatives
  they are drawn from. A blueprint is a Triangle instance whose type
  includes at least one component kind (`cistern: #Assembly & #WaterStore
  & { ... }`); it combines the constraints of its parents, mixins and its
  own fields by unification, conflicts being load errors. At load it
  resolves into a **spec**, and entities are constructed from the spec,
  never from the blueprint; nothing at runtime is written back into it. A
  blueprint may name latent schemas, unit specs for stacks, and domain
  parameters. *Avoid:* template, prototype, archetype. (COM §10, CL §8)
- **Component store**: all components of one kind, keyed by entity and
  iterated in entity order. *Avoid:* bare "store". (COM §3)
- **Field**: a declared piece of component state, with a unit and flags.
  (COM §2)
- **Field registry**: the one declaration of every field, generated from
  content, from which saving, loading, inspection, proposals and perception
  are derived. (COM d2)
- **Field flags**: `content` (content may set it), `saved`, `proposable`,
  `derived`, `perceive(...)`, `inspect`. (COM §2)
- **Authoritative**: of state: true in the world, with one owner and
  explicit rules for changing it. (DES §2)
- **Owner**: the one party that may change a value; everyone else proposes
  or contributes. (ARC)
- **Derived value**: a value computed from a base and modifiers, never
  stored as authoritative. (COM)
- **Modifier**: a component's contribution to a derived value, applied in
  **modifier stages**: base, additive, multiplicative, clamp, override.
  (COM §4)
- **Channel**: one of the four ways components interact: domain
  participation, capabilities, modifiers, reactions. (COM d3)
- **Reaction**: a component's response to a committed event in which its
  entity has a role; it returns proposals, committed in the next commit
  round. (COM §4)
- **Relation**: a typed edge between entities, which may carry
  attributes. A **reified relation** is one whose instances are entities.
  (COM §5)
- **Claim**: a reified relation of ownership or authority (claimant,
  subject, issuer): ownership, custody, reservation. A **quantity claim**
  claims part of a stack. See *Words with more than one sense*. (COM d6)
- **Location**: the one exclusive relation that places a physical entity:
  `onTile`, `in`, `heldBy`, `wornBy`, `partOf`. (COM §5)
- **Body**: the component of mass, volume, material and traces. (COM §6)
- **Assembly**: an entity with removable parts, located `partOf` it, and
  aggregate parameters that domains read. (COM §7)
- **Stack**: one entity standing for a count of identical units (30 nails).
  An **individual** is one unit with its own identity. (COM §9)
- **Area**: a thing that covers ground (`#Area`): placed on its
  north-west tile, it covers so many tiles east and south. It is near,
  seen and in reach by the nearest of its tiles, so an agent knows it by
  one referent. A plot is one. *Avoid:* region (an air region's), zone.
  (VIL d5)
- **Identity on demand**: things stay stocks or stacks until something
  needs to tell one unit apart; then it splits off (**individuation**), and
  merges back only when **physically indistinguishable**. **Automatic
  individuation** is the committer doing this before a change that would
  distinguish a unit. (COM d8, §9)
- **Provenance**: an entity's ancestry (`splitFrom`, `derivedFrom`). For
  information, see *ancestry*. (COM §9)
- **Tombstone**: what a destroyed, merged or consumed entity leaves:
  its ID, blueprint, ending event and **successor**. (COM §1)
- **Content** (the component, written `Content`): an informational
  entity's text or diagram. A **copy** is a physical entity whose
  **inscription** references a content. *Avoid* confusing it with content
  in the authored sense. (COM §8)
- **Record**: a physical copy carrying content: a ledger, a notebook, a
  flyer, a posted notice. (KNO §1)

## Change and time

- **Change commitment**: the only writer of shared world state outside
  domains: proposals ordered, validated and applied atomically at
  boundaries. Short form **commit**; the code is the **committer**.
  *Avoid:* "commitment" alone (that is an agent's). (ACT §8-§11)
- **Proposal**: a requested change to authoritative state: set a field,
  transfer a stock, relate, create, destroy, split, merge, emit an event,
  contribute to a domain. It has a **source** (what proposed it) and a
  **cause** (the event that led to it). (ACT §8)
- **Proposal group**: proposals applied all or none. *Avoid:* bare
  "group" in docs. (ACT §8)
- **Commit round**: one pass validating and applying proposal groups;
  reactions seed the next, up to **R** rounds a boundary; what is left is
  **deferred** to the next boundary. (ACT §9)
- **Commit phase**: the order groups commit in within a round: process,
  then action, then system; a **seeded permutation**, weighted by
  **contest weight** in the action phase, orders groups within each. Not a
  boundary phase. (ACT §9, d8, d13)
- **Validation**: checking a group against the state earlier groups left;
  a **validator** is a pure check that can reject a group, never change it.
  A refused group is a **rejection**, undone through the **journal** and
  reported to its source with a reason. (ACT §9)
- **Committed event**: what applying a group emits, with its cause; read
  by reactions, traces, history and perception. Short form **event**. Not a
  domain event. (ACT §9, KNO)
- **Simulation clock**: when things happen in the world. (DES §3)
- **Scheduler**: what advances the world from boundary to boundary, asking
  domains for horizons and wake queues for what falls due. (DES §3)
- **Run policy**: whether the run steps, paces to the wall clock, or waits
  for input; it adds stopping points and never sets step size. (DES §3)
- **Boundary**: the simulation time at which a step ends and the boundary
  phases run: commit, housekeeping, perception, decision. *Avoid:* bound
  (for the moment), frame. (ARC)
- **Step**: the interval from one boundary to the next. (ARC)
- **Boundary phase**: one of commit, housekeeping, **perception phase**,
  **decision phase**, in that order. Not a commit phase. (ARC, AGE §12)
- **Housekeeping**: after commit: rebuild dirty structures, update
  indexes, recheck bindings, evaluate watches, deliver rejections. (ACT §9)
- **Wake**: a time at which something falls due by itself: a perception,
  a forgetting, a decision, an activity's stage, a threshold. Kept in
  **wake queues** (`BGWakes`), heaps checked against what is so when they
  come up. (REA step 1)
- **Touched / vacated**: what a boundary changed (records and locations),
  and the tiles something left; what perception is driven by. (REA step 1)
- **Nudge**: a mind marked to decide at the next boundary because
  something addressed it (another's deal, the player's word). (REA step 1)
- **Determinism**: a run reproduces bit for bit from initial state, world
  seed and input log: no hash-order iteration, entity order and commit
  order everywhere. (ARC)
- **Input log**: the recorded commands and stop boundaries that replay a
  session. *Avoid:* replay log. (ARC)
- **World seed**: the seed from which per-entity seeds and random streams
  derive. Distinct from an entity's **seed** (Triangle) and a unit's seed
  (latent assembly). (ARC)
- **State hash**: a hash of world state, to check that a game saved and
  resumed is the same. (REA)
- **Quantum**: the integer unit a quantity kind is counted in (1 g, 1 mL,
  1 ms, 100 J). No floating point in authoritative state. (ARC, CL §5)
- **Conservation**: exact accounting of stocks, with declared sources,
  sinks and reservoirs. (DOM §3)

## Actions

- **Operation**: a verb schema in content: roles, parameters,
  requirements, stages, effects; it names constraints, never target kinds.
  *Avoid:* verb, action (for the schema). (ACT §1)
- **Role**: a named slot in an operation (actor, item, destination,
  instrument, target), with what may fill it. Also a slot in an event, and
  in a latent schema. (ACT §1)
- **Binding**: entities (for agents, referents) assigned to roles or
  slots. (ACT)
- **Action**: one attempt: an actor, an operation, its bindings and
  parameters, an intention and an expectation. (ACT)
- **Activity**: an action's execution over time; an informational entity
  with an `Activity` component. Every action is an activity. (ACT d4-5)
- **Actor**: the role an agent plays in an action. (ACT)
- **Parameter**: an input the actor chooses (an amount, a force setting).
  (ACT §1)
- **Stage**: one step of an activity, with its duration, requirements and
  effect; its effect commits when it completes. Not a modifier stage. (ACT
  §1, §5)
- **Progress**: the work done in the current stage. **Pace**: how fast,
  from the actor. (ACT §5)
- **Checkpoint**: a point in a stage where partial effects commit; it
  makes a boundary. (ACT d6)
- **Walk**: going to a place on foot as one activity (`walk`), its
  **way** (a letter a tile) found by the walker when it sets out, a stage
  per tile; a decision point only when it ends: arrived, blocked, or given
  up. Given up, not suspended, when the walker no longer believes in it.
  A walk of one tile is `walk_north` and the rest; both are a `#Walk`.
  *Avoid:* journey (that is travel), route (news), path (the search).
  (PRF d1, AGE d20)
- **Journey** (reserved, not built): travel from place to place by any
  means, in **legs**: walks, and rides on a coach or a ship; planned by
  agency, possibly across regions and levels of detail. *Avoid* it for a
  walk. (PRF, open questions)
- **Partial effect**: a stage's progress shown in the world (a half-sawn
  log), committed at checkpoints and on interruption. (ACT §5)
- **Capability**: what a provider can contribute: kind, capacity,
  conditions, costs, compatibility. *Avoid:* tags like `can_repair`.
  (ACT §2)
- **Provider**: what offers a capability: a body part, tool, machine,
  surface, another agent, an office holder. **Provider allocation**: each
  provider (hands, legs, voice) serves one activity at a time. (ACT §2, §5)
- **Transformer**: a provider turning one capability into another (a
  wrench: grip and force into torque). (ACT §2)
- **Instrument chain**: providers linked from actor to requirement (hand,
  wrench, pipe), found by **chain search**, bounded and deterministic.
  (ACT §2)
- **Requirement**: a constraint on bound entities and their reachable
  capabilities: **hard** (unmet, cannot begin) or **graded** (met by
  degrees). (ACT §2)
- **Shortfall**: how far the best capability falls below a graded
  requirement; **excess**, how far above a limit. Both set duration, risk
  and quality through **graded shortfall curves**. A **mishap** is a
  declared bad outcome with a chance. (ACT §2, d11)
- **Reach**: what an actor may draw on: its body, what it holds and wears,
  carried containers, adjacent tiles, assistants' reach. Not an anchor's
  reach. (ACT §2)
- **Effect**: the committed change an operation applies; targets
  interpret it by reactions. **No success flag**: the actor learns the
  outcome by perception. (ACT d3, §4)
- **Expectation**: the actor's predicted outcome, kept on the activity.
  (ACT §3)
- **The five questions**: `formulate` (does it know the operation and
  have referents for the roles), `appearsBeginnable`, `expect`, `resolve`
  (what actually happens), `authorize` (which rules it breaks). (ACT d1)
- **Action menu**: the operation-and-binding pairs that pass formulate
  and appear beginnable, from the actor's knowledge only. **Unknown never
  excludes**: a menu must not reveal hidden facts. (ACT §3)
- **Decision point**: a moment an actor must choose: an activity
  completed, suspended or failed, or a soft interruption. (ACT §5)
- **Interruption**: **soft** (a decision point; carry on or not) or
  **hard** (a requirement failing: suspend or fail, as the stage declares).
  (ACT §5)
- **Suspend / resume / abort / fail**: an activity paused keeping its
  progress / continued after rechecking / given up by choice / ended by
  failure. **Activity status**: running, suspended, completed, exhausted,
  aborted, failed. (ACT §5)
- **Watch**: a request, made by an activity, to be told when a domain
  quantity crosses a threshold; kept and removed with it. (ACT §5, DOM)
- **Recipe**: a composite operation expanding into a plan of child
  activities, through what the actor knows; knowing it is knowledge. (ACT
  §6, d12)
- **Reservation**: a soft claim on a thing or a quantity, by an activity
  or agent; it blocks nothing. (ACT d7)
- **Contest**: groups competing for the same thing in one round; the
  seeded permutation, weighted by contest weight, decides. (ACT d13)

## Domains

- **Domain**: owns one family of stock kinds and the algorithm that
  advances them: atmosphere, thermal, fluid, light. *Avoid:* system (for
  these specifically). (DOM d1)
- **Stock**: a conserved, integer quantity with a home: 400 L in a
  cistern, heat in a stove. A **stock kind** is owned by one domain and
  declares its quantum and split rule. Below full detail, also a count
  standing for objects (a **coarse stock**). (DOM, DR)
- **Holder**: the entity or tile a stock is held by. A **water store** /
  **gas store** is the component that holds one. **Tile stock**: one held
  by a tile, stored sparsely. (DOM, TER)
- **Participant**: a component joining a domain (`ThermalBody`,
  `Respirator`); **participation** is that join. (DOM §2)
- **Parameter vs dynamic value**: parameters live on components; dynamic
  values (temperature, flow) are read through the domain. (DOM §2)
- **Structure**: a domain's working aggregate over checked-out stocks (a
  pipe network, a thermal island); never saved, rebuilt when **dirty**
  after a **topology** change. (DOM §4)
- **Checkout / check-in**: a structure holding a stock's authoritative
  value while it flows / writing it back to the holders by the **split
  rule**. (DOM §3)
- **Contribution**: an additive, unit-carrying input to a domain from
  another or from commitment; produced in one step, **in transit** until
  applied in the next. (DOM §8)
- **Snapshot coupling**: domains read each other from a snapshot at step
  start; order of execution can't change results. (DOM d6)
- **Horizon**: how far a domain may advance: its `safeStep` and
  `nextEvent`. (DOM §6)
- **Domain event**: a discrete happening a domain reports (exhausted,
  threshold crossed), which makes a boundary. Not a committed event.
  (DOM §1)
- **Quiescent**: below its settle threshold; an **active region** that
  stays so sleeps, and wakes on a change, a contribution or a watch.
  (DOM §5)
- **Reservoir**: what lies outside the simulated region at a fixed state
  (the outdoors); its exchange is kept in the **ledger**. (DOM)
- **Remainder carry**: the fraction of a flow owed to the next step; not
  stock. (DOM §3)
- **Allocation rule**: how a short supply is shared: pro rata by demand,
  remainders in stable order. (DOM §8)
- **Causal trace**: a domain's or the committer's per-step record of what
  changed and why. Always "causal trace", never bare "trace". (DOM §10)

## Knowledge

- **World state / history**: the truth now / the log of committed events.
  Agents read neither; history is developer truth. (KNO §1, §2) History
  keeps what has a bearing on the world, for good. A **diagnostic event**
  is a step along the way (a walk's tiles before its arrival): kept a
  **history window**, then **compacted** into **digests**, each the count
  of one kind, by one actor, in one chunk, over one window. A **debug
  field**'s changes (an activity's timing) aren't logged unless the world
  asks. *Avoid:* summary (that is detail's), routine event. (KNO d21)
- **Perception-only rule**: agents learn only by perceiving: events as
  they happen, state and traces examined, records read, claims heard.
  (KNO §1)
- **Trace**: physical evidence of an event on a body or tile: tool marks,
  a footprint, fresh paint. It fades by its age (**analytic aging**); an
  operation removing traces leaves its own (**cover-up rule**). Not a
  causal trace. (KNO §3)
- **Appearance**: what the senses report of a field, against its truth
  (brass plating on steel). An **analysis** operation reaches beneath it.
  (KNO d3, §4)
- **Sense**: a perceptual capability (sight, hearing, smell, touch,
  interoception) with acuity and range. *Avoid:* modality. (KNO §5)
- **Conditions** (of perception): light, distance, noise, occlusion,
  attention. (KNO §5)
- **Attention**: what an agent can perceive and interpret a boundary;
  operations declare an **attentional demand** on it. (KNO §5, AGE §10)
- **Perceiver**: an entity that can perceive. (KNO §5)
- **Percept**: what one act of perception yields: features with
  **precision**, about referents. (KNO §5)
- **Event, state and trace perception**: the three triggers: an event
  within the senses; attending to a thing; examining it. (KNO §5)
- **Concerned**: of an agent and a change: within its senses (at full
  detail) or involving it (below). (REA step 1, 3)
- **Referent**: an agent's own handle for something it thinks exists (R7),
  holding what it last perceived; beliefs are about referents, never
  entities. (KNO d5, §6)
- **Truth link**: a referent's developer-only link to the entities behind
  it. *Avoid:* truth projection (for this). (KNO §6)
- **Recognition**: matching a percept to the agent's referents by
  unification, weighing conflicts by persistence. (KNO §6, CL §11)
- **Seen kind**: a kind that shows at a glance (a bed, a stove), listed so
  (`#Seen`); an inner state's (hunger) doesn't. A thing is seen as the most
  specific seen kinds it is; a kind not listed shows as the listed kinds
  above it. (KNO d17, lab/content/knowledge.tri)
- **Identity from context**: which thing a percept is comes from
  continuity, place and whose it is before looks; a thing like one
  believed still elsewhere is another thing, not that one moved, until the
  first is found gone. An owner knows its own things as its own. (KNO d18)
- **Identity hypothesis**: a belief that two referents are one; past a
  threshold they **merge**. Errors of identity: merging, splitting,
  misbinding, invention. (KNO d13, §6)
- **Observation**: a stored percept, kept if salient. (KNO §7)
- **Proposition**: a typed, time-indexed statement about referents
  (`entered(R7, R2)`), written in content. (KNO §8)
- **Persistence**: how long a feature or proposition usually stays true
  (a coat a day). (KNO §8, CL §11)
- **Interpretation**: a proposition drawn from observations and beliefs by
  an **interpretation rule**, gated by **expertise**; **immediate** (cheap,
  on perceiving) or **deliberate** (investigating, an activity). Retracted
  only when a premise is contradicted. (KNO §9) **Incremental
  interpretation**: a rule weighed again for a referent only when what its
  premises read of it changed. (KNO d20, PRF d2)
- **Telling**: the content of a claim made in speech or writing, with its
  **attribution** ("I saw", "Teodor told me"). (KNO §10, lab/content/knowledge.tri)
- **Utterance**: the committed event of saying something; heard by event
  perception. (KNO §10)
- **Testimony**: what an agent has been told: tellings heard and believed
  by trust and attribution. (KNO d13)
- **Rumour**: testimony passed on from a root the hearer doesn't know;
  each unknown root counts on its own, so rumour inflates credence. (KNO
  §11)
- **Lie**: telling what the speaker doesn't believe; history records a
  **fabrication root**. (KNO §10)
- **Belief**: a proposition an agent holds, with credence, provenance,
  when acquired and last confirmed. Believed at credence ≥ 0 dB. (KNO §11)
- **Credence**: degree of belief, integer log-odds in decibans. *Avoid:*
  confidence. (KNO d7)
- **Ancestry**: where a belief's evidence came from. **Perceived
  ancestry** (as the agent can tell, grouped by **perceived root**) is all
  credence uses; **true ancestry** (to the **true root**) is developer-only.
  **Corroboration**: independent roots add; **repetition** from one root
  counts once; **false corroboration**: groups that share a true root.
  (KNO §11)
- **Trust**: beliefs about a source, rising and falling as its claims
  prove true or false. (KNO d15)
- **Competing hypotheses**: conflicting beliefs held at once, each with
  its credence. (KNO §11)
- **Memory**: a knowledge store as it decays: **detail** degrades by
  generalising, **strength** fades by salience and repetition until
  forgotten; a **capacity** evicts the least salient. **Confirmation**
  restores detail. A referent nothing holds is forgotten once it
  **ended** or faded below belief. (KNO d10, d16, d19, §12)
- **Ended**: of a referent: its agent perceived the thing end (eaten,
  burned, split, merged, felled) where it believed it. Forgotten unless
  something holds it. (KNO d19)
- **Generalise**: of a feature in memory or news: step to its primary
  parent ("grey wool coat", "dark coat", "a coat"). (KNO §12, CL §11)
- **Knowledge store**: one agent's private referents, observations and
  beliefs, written only by knowledge, outside change commitment. (KNO d8)
- **Knowledge view**: the interface through which actions and agency
  query a knowledge store; `BGView`. Not Tessera's view. (KNO §13)
- **Terrain memory**: an agent's record of the tiles it has seen and when;
  what it believes there is its **believed terrain**. (TER d7)
- **Interoception**: an agent sensing its own body (hunger, cold). (AGE §6)
- **Notebook**: a record an agent writes what it believes into; the
  **notebook view** is the player's view of the character's memory, which
  can't be stolen. (KNO §15)

## Agency

- **Agent**: an entity with a `Mind`: a knowledge store, a motivation
  store and dispositions. (AGE)
- **Mind**: what decides for an agent. (AGE §2)
- **Goal**: a desired state or ongoing condition ("not hungry", "promise
  kept"), done when its `done` pattern holds. Not a recipe's stopping
  condition. (AGE d1)
- **Goal generator**: a source of candidate goals: needs, routine,
  commitments, reactive, instrumental, social. (AGE §4)
- **Consideration**: one scored input to a goal's worth: a fixed-point
  **consideration curve** over a knowledge-view value; considerations add
  in dB; some **veto**. (AGE d14, §3)
- **Worth**: a goal's score, the sum of its considerations in dB. *Avoid:*
  utility, score. Not a thing's value. (AGE d14)
- **Value**: what a kind of thing is worth to an agent (`#Valuing`);
  giving costs it. (AGE d16)
- **Intention**: the goal being pursued, its method, and how far its plan
  has got; reconsidered only at decision points. (AGE d4)
- **Margin**: how much better another goal must score to replace the
  intention; with the **interruption cost**, the **continuation bonus**.
  *Avoid:* commitment (for persistence of intention). (AGE §3)
- **Method**: an HTN-style way to a goal: `pre` conditions over the
  knowledge view (three-valued), steps, alternatives tried by rank, a
  credence threshold, and what to do with unknown. (AGE d1, §5)
- **Subgoal**: a goal a method step raises; a **residual subgoal** is one
  raised from an unknown precondition's residual paths. (AGE §5)
- **Motivation store**: an agent's private goals, intentions,
  commitments, habit strengths. (AGE §2)
- **Decide**: agency's function at a decision point: start, suspend or
  resume activities, or wait with watches. (AGE §1)
- **Salience**: how much something matters to an agent now; past its
  **interruption threshold**, a soft interruption. (AGE d7, §10)
- **Need**: pressure from a perceived body condition (hunger, cold,
  stuffy, tired): a consideration over the interoceptive belief, not the
  body. Felt by **band**. **Going without** harms the body over time:
  cold and bad air by fatigue then injury, hunger by **weakness** as
  **reserves** run down, then injury. (AGE d3, d17)
- **Satiety**: how full the stomach is (`#Hungry`), emptying over hours;
  what is felt as hunger. An empty stomach doesn't harm. (VIL d2,
  lab/content/hunger/body.tri)
- **Reserves**: what the body draws on while satiety is empty, lasting
  weeks, and refilling while it isn't. (VIL d2)
- **Weakness**: what going without takes as reserves run down, by curves
  in content: attention, the pace of work, perception, grip. Not felt.
  (VIL d2, lab/content/hunger/weakness.tri)
- **Nourishment**: what a food (`#Food`) gives satiety when eaten; eating
  asks the body to be **nourished** by it, and the body's code applies it.
  (VIL d2)
- **Meal**: food that isn't **raw**: cooked (at a lit stove, adding its
  `cooking` to its nourishment) or never raw (a supper). *Avoid:* dish.
  (VIL slice 4, lab/content/cooking/cooking.tri)
- **Larder**: a household's container of food, a plain container, known
  from its neighbours' by where it is. (VIL d3, lab/content/cooking/)
- **Firewood**: split wood by the piece (a kilogram), a stack; stoked into
  a stove, its fuel. A tree is **felled** into a **trunk**, **bucked** a
  length at a time into **logs**, and a log **split** into firewood.
  (VIL d6, lab/content/firewood/firewood.tri)
- **Commitment**: a goal an agent is bound to (a shift, a promise, a
  debt), with a window or deadline and an **urgency curve**. Not change
  commitment. A commitment to a **kept** goal (an ongoing condition: at
  work through the shift) isn't settled when done: it arises again
  whenever the goal no longer holds, until the window closes, and its
  urgency doesn't rise; found impossible, it is tried again ten minutes
  later. (AGE d5, §7; VIL d4)
- **Promise**: a commitment made by saying it; hearers hold it as
  testimony (attributed `#Pledged`). *Avoid:* pledge, in prose. (AGE §7)
- **Deal**: an agreement (employment, a loan, a posted offer), said or
  written. **Employment**: a deal of work for pay; a **job** is its task,
  shift, pay. A **debt** is a commitment to pay. (AGE d15, d18)
- **Bond**: a reified relation from one agent toward another, with a
  **tie** (kin, friend, employ, sworn) and a **loyalty** weight. (AGE d12,
  lab/content/bonds/bonds.tri)
- **Loyalty**: the weight of a bond. *Avoid:* treating it as a
  disposition. (AGE d12)
- **Routine**: the goals in force at a time, from commitments and habits.
  (AGE §8)
- **Worksite**: what a household's day's work is done at (`#Worksite`: a
  scarecrow in a plot, a chopping block): its people's work commitment is
  bound to it. *Avoid:* workplace, place of work (a **place** is
  DETAIL_REGIMES.md's). (VIL d4, lab/content/home/home.tri)
- **Habit**: a learned preference in a context, with a strength that
  rises with repetition and decays. A habitual method wins a tie with
  another of the same rank; it never comes before an earlier way. (AGE §8,
  §5)
- **Disposition**: a per-agent weight: honesty, curiosity, diligence, risk
  tolerance, respect for reservations. *Avoid:* trait (in prose). (AGE §9)
- **Norm**: an agent's own rule weighting kinds of action ("don't take
  what isn't yours"), weighed with its belief about being observed. Not an
  institution's rule. *Avoid:* internal norm (redundant). (AGE d6, §9)
- **Harm / threat**: injury or loss to an agent or its loyalties / a
  belief that harm is coming; salient. (AGE d13)
- **Autopilot**: agency acting for the player's character in a mode the
  player chose, until something salient enough. (AGE d10)
- **Decision log**: the developer's record of candidates, considerations,
  margins and methods. (AGE §15)

## Institutions

- **Organization**: an entity with an `Organization` component; members
  hold offices in it. *Avoid:* institution (for one organization).
  (INS d1)
- **Office**: a position in an organization, held by an **office holder**,
  that gives its holder operations and capabilities. Not the organization.
  (INS d1)
- **Rule**: what an organization issues: a **law** (`#Law`), a licensing
  rule, a permit. Whether an act breaks one is objective. **Common rules**
  are known from the start; **particular rules** are learnt. Not a norm.
  (INS d2, d8)
- **Permit**: an issued authorization; revoked, it is void. *Avoid:*
  licence. (INS d7)
- **Authorize**: reports which rules an act breaks; never blocks. (INS d3)
- **Compliance**: each agent's own choice to keep rules. (INS d5)
- **Grievance**: a wrong told to an office holder. (INS d6)
- **Sanction**: an operation an office gives its holders: **arrest**,
  **fine** (a debt), **confiscate**, **revoke**. (INS d7)
- **Custody**: a location, and claim, held by an organization. (INS d7)
- **Posted notice**: a record conveying a rule or a deal (a flyer). (INS
  d8, AGE d15)

## Latent assembly

- **Latent assembly**: an assembly whose parts don't exist until
  revealed; it keeps its **use** and **abuse**. (LAT)
- **Latent schema**: its parts by **role** and **depth**, and the culprit
  candidates for each failure. (LAT d1)
- **Reveal**: opening an assembly to a depth makes its parts entities,
  from the unit's seed. Not analysis. *Avoid:* materialize, anatomy reveal.
  (LAT d2)
- **Latent part / revealed part**: a part before / after it is revealed.
  (LAT)
- **Wear**: a part's wear, its role's rate times use (faster when abused);
  **worn through** at 60. **Attrition**: a revealed part's own finer wear.
  (LAT d4, d7)
- **Grade**: a part's hidden quality, from the unit's seed and its
  blueprint's bias. *Avoid:* quality (as the field). (LAT d6)
- **Failure / culprit**: a failure kind risked each hour of use / the part
  it is blamed on, drawn by wear, marked only if revealed (else
  **unresolved**). (LAT d3, d5)
- **Servicing**: undoing a share (`mends`) of a part's wear since it was
  last `tended`. A **spare** replaces a part. (LAT d7, d8)
- **Use record**: an assembly's use, abuse and failures. *Avoid:* history
  (that is the event log). (LAT)

## Terrain

- **Tile**: one place on the grid at one level; one terrain kind. **Cell**:
  what is stored for a tile (the terrain kind's index; in Tessera, a
  `tess_cell`). Write "tile" for the place. (TER d1, d2)
- **Level**: a storey of the world (the z coordinate). Never a level of
  detail. *Avoid:* z-level, storey, floor. (TER d1)
- **Terrain**: what each tile is, per level; read by walking, sight, sound,
  light, air, water and Tessera. (TER)
- **Terrain kind**: an instance of the `terrain` family: `solid`,
  `opaque`, `floored`, `divides`, `draught`, material, look. (TER d2)
- **Open air**: a tile with no floor, showing the level below. (TER)
- **Chunk**: 32 by 32 tiles on one level: the unit of terrain storage,
  room labels, the spatial index, tile stocks, and detail. (TER d5)
- **Terrain source**: what tells the world a tile's kind: an **authored
  map** (text drawn with a **legend**), a plain fill, later a
  **generator**. Only **changed chunks** are stored. (TER d4, d5)
- **Terrain change**: the `setTerrain` proposal. (TER d6)
- **Doorway**: a tile whose kind `divides`: it joins two rooms and belongs
  to neither. A **door** is an entity standing in one, passing its `wide`
  when ajar, nothing when shut. (TER step 3)
- **Room**: the tiles of one level joined side by side, neither solid nor
  doorway, and enclosed (at most `BG_ROOM_MAX` tiles, not reaching the
  world's edge). Found from terrain, labelled per chunk. Not a place.
  (TER step 3)
- **Open ground**: ground in no room. **The outdoors**: open ground, or
  any room without air; for air, a sink. (TER step 3)
- **Air region**: a gas store whose tile lies in a room: that room's air.
  *Avoid:* bare "region". (TER step 3)
- **Link**: an opening between an air region and the next region or the
  outdoors, found at a doorway. *Avoid:* route (that is for news). (TER
  step 3)
- **Draught**: what a doorway kind passes with no door. **Gap**: an air
  region's leak to the outdoors through walls and windows. (TER step 3)
- **Join / part** (air): rooms knocked together merge their air into one
  (the others end with it as successor) / a room walled across divides its
  air by tiles. **Airing out**: a room opened to the outdoors exchanging
  air with it. (TER step 3)
- **Sight**: a tile is in sight when nothing opaque stands between,
  either way. (TER step 2)
- **Spatial index**: what stands where, filed by chunk or holder, read in
  entity order (`BGIndex`). (TER)
- **Path search**: bounded A* or breadth-first over tiles (`BGPath`),
  within a budget; it gives a walk its way. **Exploring**: a walk to the
  nearest tile never seen; a method step can explore (`#Explore`), beside
  ground of a kind the agent has seen (a woodcutter finding trees). (TER,
  AGE §5)
- **Sparse**: stored only where something is. (TER)

## The reality bubble and detail regimes

- **Reality bubble**: the scheme by which how exactly the world is
  simulated falls off with distance from anchors. (REA)
- **Detail**: how exactly a chunk, or a thing, is simulated: one of four
  **levels of detail**, written in full or as "detail", never as bare
  "level" (that is a storey). In code, `BGDetail`. (REA d1)
  - **Full**: everything exact.
  - **Reduced**: agents on a cadence, with own senses; domains in longer
    steps.
  - **Abstract**: no perception; authored progression; domains in closed
    form.
  - **Frozen**: nothing runs; caught up on rising.
- **Anchor**: an entity that projects detail around it (a player, a
  camera, a story's character). Its **anchor kind** (`#AnchorKind`, in the
  `anchors` family) gives, per detail, its **anchor reach**: chunks
  **across**, levels **up** and **down**. (REA d2, d12)
- **Margin**: how far, in tiles, an anchor must pass its chunk's edge
  before it is **re-centred**: the **hysteresis** that stops the world
  flapping between details. *Avoid:* settle (for anchors; the function is
  still `settleAnchors`). (REA d5, step 2)
- **Contact**: an event (said, struck, arrested, moved) between a thing at
  full detail and one below, raising the other by a **lease**: full detail
  while it runs. A lease is not an anchor. (REA d10)
- **Rise / fall**: a thing or chunk moving to more / less detail; a
  **transition**. What rose is **risen**. (REA d6)
- **Catch-up**: bringing a risen thing to now from when it last advanced.
  A chunk not yet caught up **lags**. *Avoid:* gap (for the time frozen;
  `gap` is a leak). (REA d6)
- **Cadence**: the interval below full detail that a thing's own wakes are
  put off to (`every`); each moment of it a **beat**. (REA step 3)
- **Own senses**: below full detail, sensing only what the agent takes
  part in. (REA step 3)
- **Regime**: an instance in the `regimes` family: what it `applies` to (a
  pattern over fields content fixes), and per detail below full, a mode for
  each system. The most specific applying regime wins, field by field;
  resolved per blueprint at load. (DR d1, d2)
- **Mode**: what a regime sets one system to: **exact** (as at full),
  **coarse** (on a cadence, own senses), **progress** (replaced by
  progression), **deferred** (doesn't run; caught up on rising),
  **paused** (doesn't run; the time is lost). Deferred and paused are both
  **suspended**. *Avoid:* mode for Tessera's views. (DR d3)
- **Progression**: what a thing does below full detail, authored in
  content and applied in bulk, deterministically by seed. Its **forms**:
  a **rate** on a field; an **approach** to a level (`toward`, `curve`,
  `@fn`); a **periodic operation** (a pattern, a **period**, a condition,
  coarse effects); a **change of grain**. (REA d4, d13, DR)
- **Coarse effect**: a declarative change to fields and stocks
  (`{ role, field, by }`), as against an `#Effect`, which names code that
  moves objects. (DR form 3)
- **Closed form**: a formula for the state after any elapsed time, so
  catching up is one computation. (REA d13)
- **Read lazily**: of a continuous field: kept as a value, when it was so,
  and what moves it; computed for now when read, through an **accessor**.
  (DR d4)
- **Settle**: make a coarse summary concrete on rising: a condition into
  things, a stock into objects or onto tiles. (REA d6, d11)
- **Grain**: how coarsely something is represented: objects or stocks,
  each agent's knowledge or its community's. (DR form 4)
- **Schedule**: where an abstract agent counts as being, by hour and by
  roles bound to its bonds and claims; **abstract presence**. Not the
  scheduler, nor the wake queues. (DR)
- **Place**: an entity carrying a building's or household's fields
  (condition, larder). Not a room. (DR)
- **Condition** (of a place): its state of repair or supply, a rate below
  full detail, settled into things on rising. (REA d11, DR)
- **News**: information travelling between communities below full
  detail. A **community** (a place, a household, a guild) holds knowledge
  below full detail; news moves along **routes**, with a **delay** and a
  **fidelity**, and distorts by generalising. (REA, DR)
- **Plume**: a sparse local outdoor condition (smoke, dust, mist), kept
  per chunk only near its source. (REA d9)
- **Dial**: a tunable setting in content: reaches, cadences, step
  lengths. (REA d3)

## Triangle

- **Feature structure (FS)**: a rooted graph of typed nodes, one arc per
  feature its type allows. What all content is written in. *Avoid:*
  structure (alone, in Triangle's sense). (CL)
- **Type**: a named point in the hierarchy (`#Wrench`, `"steel"`,
  `length`). Types are nominal and closed. (CL d4)
- **Hierarchy**: the partial order of types, completed so any two
  compatible types have one **meet** (their greatest lower bound; none is
  **bottom**). The loader makes **meet types** (`glb[...]`) and
  **conjunction types** (`#A & #B`). (CL §3)
- **Primary parent**: a type's first-listed supertype; generalising goes
  along it. (CL §3)
- **Feature**: a named attribute, introduced by exactly one type (its
  **introducing type**) and belonging to that file's package; two packages
  may each have one of a name (`cooking.larder`, `farming.larder`). Written
  in content as a field. (CL d4, d12)
- **Appropriateness**: which features a type has, and the most general
  value each allows. **Totally well-typed**: every node has every feature
  its type allows. **Closed**: no features beyond its type's. (CL §3)
- **Atom / enum**: a leaf value (`"steel"`) / a disjunction of atoms,
  which becomes their supertype. (CL §3)
- **Mixin**: a type conjoined with others to add features and defaults.
  (CL §3)
- **Unification**: combining two FSs into the most general one more
  specific than both, or failing. Written `&`. (CL §4)
- **Subsumption**: A subsumes B when A is more general: whatever A says,
  B says. (CL)
- **Tag**: `$name`, marking paths that share one node. A **field
  reference** (`.a.b`) is a tag named by its path; a **name** (`wrench_19`)
  copies its constraints. (CL d5)
- **Let**: a named expression, copied at each use. **Comprehension**: a
  `for`/`if` expanded at load. (CL §1)
- **Instance**: a top-level name without `#`; not in the hierarchy. (CL)
- **Blueprint**: see *Entities and components*. In Triangle's terms, an
  instance whose type includes a component kind; other instances
  (operations, methods, regimes) become patterns instead. (CL §8)
- **Spec**: a blueprint resolved at load: flat, immutable, its defaults
  decided, its variation points recorded; what construction reads. (CL §7,
  COM §10)
- **Construction**: making an entity from a spec and its **seed**. (CL §7)
- **Variation**: what a spec leaves open, drawn from the seed at
  construction, per **variation point** (seed hashed with the point's
  path). A **variant** is one expansion of a blueprint's structural
  disjunctions. (CL §7)
- **Default**: `*v`, used only if nothing more specific decides; resolved
  at load by specificity (YADU); never in specs or patterns. (CL §6)
- **Load mode / runtime mode**: the full language at load / conjunctive
  only, no defaults, at runtime. (CL d3)
- **Quantity**: a number with a dimension and an interval of quanta; a
  **quantity kind** (mass, length, time, heat, volume ...) gives its
  quantum. **Interval**: a numeric constraint `[lo, hi]`; unification
  intersects. (CL §5)
- **Arithmetic**: `+ - * /` as a constraint on intervals, forward, and
  backward through sums and scaling by a constant. (CL §5)
- **Pattern**: an FS used for matching: a role, a precondition, a premise,
  a regime's `applies`. (CL §9)
- **Description**: an FS describing something: a hypothesis about a
  referent (from the **knowledge view**) or a projection of a real entity
  (the **truth projection**, never seen by agent reasoning). (CL §9)
- **Match**: a pattern against a description, three-valued: **entailed**,
  **incompatible**, **unknown**, with **bindings** and, when unknown,
  **residual paths**: what would have to be learnt. Against competing
  hypotheses, a **credence mass** for each. (CL d10, §9)
- **Family**: instances grouped by `@family(name)`, with a pattern index
  and a **quick check**. (CL §8, §12)
- **Rule** (Triangle): a feature structure an engine applies in its own
  fixed way: an operation, recipe, method, interpretation rule, curve,
  norm. "No rule engine searches." Not an institution's rule. (CL d9, §10)
- **Definite clause**: `#Clause` / `#Fact`, solved by resolution with a
  depth limit, for short recursive inferences. (CL §10)
- **Attribute**: `@name(...)`: `@component`, `@field`, `@family`,
  `@vary`, `@widen`, `@fn`, `@embed`, `@quickcheck`, `@variants`. (CL §1)
- **Derived field**: a value computed by code named by `@fn`. (CL §5)
- **Package**: a file or directory of content scoping its names and
  features; a name is qualified (`cooking.#Food`) only where two packages
  have it. Each topic directory is one, named for it. Not Odin's unit of
  code (an **Odin package**, such as the lab's `lab` in `lab/src`). (CL d12)
- **Topic**: one subject of the content that crosses systems (hunger: a
  body field, a felt need, a goal and its methods, eating), kept in one
  directory of content with what it does at every level of detail. Not a
  system: a regime sets a mode per system, and a topic says what its parts
  do under each. *Avoid:* subject (a claim's), concern (see **concerned**).
  (lab/content/README.md)
- **Content root**: the directory content loads from. Its own `.tri` files
  hold the vocabulary every topic is written in; each topic is a directory
  beneath it. (lab/content/README.md)
- **Cut point**: where a content file's content stops and something else
  takes over: another level of detail, another topic, or code. Every
  content file lists its cut points in its header. (lab/content/README.md)
- **Content build / content hash**: one load of all content / its hash,
  stored in saves. (CL §8)
- **Arena**: a region allocator for nodes; compacted by copying. (CL §12)

## Tessera

- **Scene**: plain data: what to show for an **extent** (tiles, a range of
  levels, a **focus** level), built by a **producer**, drawn by a
  **backend**. (TES d1)
- **View** (Tessera): a scene's `truth` (developer) or `knowledge` (one
  character's, naming referents) side. A **truth scene** names entities, a
  **knowledge scene** referents. (TES d2)
- **Frame / diff**: a complete scene / the changes since one, by sequence
  number. (TES d4)
- **Mark**: a thing drawn on a tile: an entity or referent, with an
  appearance key. (TES)
- **Overlay**: a scalar field over tiles (heat, CO₂, light, knowledge age)
  with a range and palette. (TES)
- **Annotation**: a line, arrow, path or callout. *Avoid:* note. (TES)
- **Developer-only**: tagged so a player-view backend refuses it. (TES d2)
- **Look**: a kind's appearance in content (a `#Look`, beside the kind:
  the most specific kind's wins, and of a kind several at once the one
  that **prevails**); in a scene, its **appearance key**, mapped by a
  **theme** to glyphs, atlas cells and tints. Themes are content too
  (lab/content/looks/: text, tiles). (TES d6)
- **Viewer**: the program that displays scenes; the scene's `viewer` field
  is the entity whose knowledge it shows. (TES d5)
- **Watcher**: what runs a lab world and publishes its scenes to a viewer:
  `lab/watcher/`, in one process with its window. Not an activity's
  **watch**. (TES)

## The village (proposed)

- **Plot**: tilled ground a household farms (`#Plot`): an **area**, known
  to an agent as a whole, by one referent. It **stands** bare, sown or
  ripe; it is sown and reaped a **row** (its width in tiles) at a time.
  *Avoid:* field (a component's field). (VIL d5)
- **Crop**: what a plot grows, kept as the plot's state: sown a row at a
  time, growing from its last row, ripe after its growth, read lazily. Not
  an entity of its own. (VIL d5)
- **Seed to sow**: `#Seed`, a stack of what sows a crop (seed grain,
  turnip seed), a unit to a tile, **kept back** in a larder. See *Words
  with more than one sense*. (VIL d5)
- **Perishable**: good for so long after it was made, then spoiled. (VIL
  d8)
- **Carcass**: what an animal's body is once it has died, to butcher
  into meat (its `yields`, so many cuts) and a hide. (VIL d7)
- **Remains**: what any body is once its injury reaches 100 and it dies,
  as heavy as it was: its blueprint's `remains`, a carcass for an animal,
  a **corpse** for a person. (VIL d7)
- **Instinct**: the goals an animal keeps every day, each over its hours,
  taken on as it first perceives (a grazer's: to roam from dawn to dusk,
  bedded down the night). A person has none. (AG d21)
- **Bolt**: an animal's flight from a person in sight: a dozen tiles in
  three seconds, out of its sight, faster than anyone runs after it. How
  far a flight carries is its operation's `run`. (VIL d7)
- **Herd**: the game of a kind the woods hold, kept up to so many by
  animals coming in at the woods' edge (a scenario's input). (VIL d7)
- **Range**: how far an operation's other roles may be from its actor, in
  tiles: 1, beside it; a shot's 3. (AG d21)
- **Lie in wait**: a hunter's way of looking for game: crouched, bow in
  hand, a quarter-hour in one place, between short walks. (VIL d7)
- **Aim**: the chance in a hundred that a bow's shot from beside its mark
  strikes, in a master's hands; less its **spread** for each tile
  further, and a hundredth of it for each point of the hunter's
  `stalking`. A shot that misses gives the hunter away all the same.
  (VIL d7)
- **Stall**: where a seller sets out goods on **market day** (every fourth
  day, on the green), with its **posted prices**: written records of what
  it asks. (VIL d9)
- **Sale**: a deal of goods for coins, made on the spot. *Avoid:* trade
  (a craft, `Agent.trade`). (VIL d9)
- **Household**: the people of a home, joined by kin bonds. Not a
  **place**, until abstract detail needs one. (VIL d3)

## Words with more than one sense

Each row says which term to use for which sense.

| Word | Use for | For the other sense, write |
| --- | --- | --- |
| level | a storey (z) | **detail** / level of detail |
| trace | physical evidence of an event | **causal trace** (developer's record) |
| claim | a reified right: ownership, custody, reservation | **telling** (content said or written), **testimony** (heard) |
| event | a committed event | **domain event** (a domain's discrete happening) |
| commitment | an agent's bound goal: shift, promise, debt | **change commitment** / commit (writing state); **margin** (intention persisting) |
| content | authored Triangle material | `Content` (the component); `content` (the field flag) |
| store | always qualified | component store, knowledge store, motivation store, water store, gas store |
| reach | an actor's reach | **anchor reach**; a path's arrival distance; hearing range |
| region | always qualified | **air region**; a domain's **active region** |
| settle | a summary made concrete on rising | **re-centre** (anchors); **decide** (a contest) |
| schedule | an abstract agent's presence by hour | **wake queue**; **scheduler** |
| gap | an air region's leak to the outdoors | **lag**, the time frozen |
| worth | a goal's score | **value** (of a thing) |
| rule | an institution's rule | **norm** (an agent's own); a Triangle **rule** (a structure an engine applies) |
| phase | a boundary phase | **commit phase** (process, action, system) |
| stage | a stage of an activity | **modifier stage** |
| mode | a regime's setting for a system | **view** (Tessera) |
| view | Tessera's truth or knowledge | **knowledge view** (the query interface) |
| merge / split | always qualified | referents merging; stacks splitting; air joining and parting |
| history | the log of committed events | **use record** (an assembly's) |
| reveal | a latent part made an entity | **analysis** (reading beneath appearance) |
| hypothesis | competing beliefs | **identity hypothesis**; design hypotheses are not domain terms |
| generalise | memory decay and news, along primary parents | **anti-unify** (`tri_generalize`, structures) |
| spec | a resolved blueprint | **design doc** |
| seed | an entity's seed | **world seed**; a unit's seed (latent); **seed to sow** (`#Seed`), named by what it sows: seed grain, turnip seed |
| fidelity | how faithfully a route carries news | **detail** (AGENCY.md's "fidelity levels" are levels of detail) |
| loyalty | a bond's weight | (not a disposition) |
| office | a position in an organization | **organization** (the body) |
| subject | a claim's subject | **topic** (what a content directory is about) |
| package | Triangle's: content scoping names and features | **Odin package** (a directory of Odin code) |
| field | a component's field | **plot** (farmed ground) |
| trade | a craft (`Agent.trade`) | **sale** (goods for coins) |
| leg | the body's legs, a provider an activity uses | **leg of a journey** (reserved) |
| compaction | a Triangle arena's (copying what is live) | **history compaction** (diagnostic events into digests) |
