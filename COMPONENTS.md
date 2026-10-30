# Components

## Status and scope

Proposal. This document specifies the system sketched in
[DESIGN.md](DESIGN.md) §2, "Entities, components, and relationships". It
records the decisions made so far, proposes the component contract, and
defines three scenarios to test that contract before implementation.

The **component system** provides:

- identity
- per-entity state and behaviour
- relationships between entities
- the rules for when something has its own identity at all

It is the attachment point for the other systems. Components join domains
([DOMAIN_SIMULATION.md](DOMAIN_SIMULATION.md)), offer capabilities to actions
(§1), carry perceivable features (§4), and take part in claims and
institutions (§6).

Out of scope here, except where they touch components:

- change commitment, specified in [ACTIONS.md](ACTIONS.md)
- latent physical assembly, which will get its own document
- the action lifecycle
- perception and belief
- the content format, which will be evaluated separately

## Decisions so far

1. **An entity is an ID.** Component kinds are Objective-C classes. Each
   kind's instances live in a per-kind store keyed by entity ID. An entity is
   not an object that holds its components.
2. **One registration per component kind** declares every field once. Saving,
   content loading, the inspectors, proposals, and perception are all derived
   from that declaration.
3. **Components interact through a closed set of channels**, not a general
   event bus. The channels are domain participation, capabilities, modifiers,
   and reactions.
4. **Composition, assembly, and relationships are separate in the data.**
   Assembly is a location relation. Relationships live in a relation store.
5. **Location is exclusive.** Every physical entity is in exactly one place.
6. **Claims are entities.** Any relation kind may be declared reified, which
   makes each instance an entity. Claims are always reified.
7. **Informational content is separate from physical copies.**
8. **Identity on demand.** Things are stocks or stacks until something needs
   to tell one unit apart. Then a unit splits off as its own entity, with
   provenance. Units merge back only when nothing physically distinguishes
   them.
9. **Content uses a unification-style format.** Constraints merge and
   conflicts are errors. The language is specified in
   [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md): TDL semantics with CUE-style
   syntax.
10. **Unreferenced content is collected; history keeps it.** Content no
    copy, memory, derivation, or claim references is collected at the next
    save, and history keeps a summary (who made it, when), so the developer
    can still trace it. Tombstones compact into history summaries after a
    retention period that content declares.
11. **An installed part keeps its own claim.** Installing transfers
    nothing: the assembly's claim covers, through `partOf`, only parts
    with no claim of their own. Whether installing it was a gift, a sale,
    or a wrong is for people and institutions to settle (INSTITUTIONS.md:
    a grievance, a court), not the engine.

## Terms

| Term | Meaning |
| --- | --- |
| Entity | Anything with identity: a creature, object, tile feature, organization, document's content, or claim. Represented by a `BGEntityID`. |
| Component kind | An Objective-C class describing one kind of state and behaviour, such as `Body`, `ThermalBody`, `Stack`, or `Inscription`. |
| Component | One instance of a component kind, attached to one entity. |
| Store | All components of one kind, keyed by entity ID and iterated in ID order. |
| Field | A declared piece of component state, with a unit and flags. |
| Derived value | A value computed from a base value plus modifiers. Never stored as authoritative. |
| Modifier | A contribution from a component to a derived value on some entity. |
| Channel | One of the closed set of ways components interact. |
| Relation | A typed edge between entities, which may carry attributes. |
| Reified relation | A relation whose instances are entities, such as a claim. |
| Location | The exclusive relation that places a physical entity. |
| Physical entity | An entity with a `Body` (mass, volume, material) and a location. |
| Informational entity | An entity with no body and no location: content, an organization, a claim. |
| Stock | A divisible, conserved quantity owned by a domain, such as water. See the domain simulation doc. |
| Stack | One entity standing for a count of identical discrete units, such as 30 nails. |
| Individuation | Splitting units off a stack, or a piece off an individual, into a new entity with provenance. |
| Tombstone | The record left when an entity is destroyed, merged, or consumed. References to it still resolve. |
| Blueprint | Content describing what an entity is made of. Resolved at load into a flat spec. |
| Spec | A resolved, immutable blueprint, used to construct components. |

## The component contract

### 1. Entities and identity

- `BGEntityID` is a 64-bit integer, allocated from a counter in world state.
  IDs are never reused.
- **Allocation is deterministic.** IDs are assigned only when changes are
  committed, in the commit's deterministic order. Generated world content
  allocates IDs in generation order from the world seed. Domains break ties by
  ID, so allocation order is part of what replays reproduce.
- **IDs are not seeds.** Anything that must not depend on the order in which
  entities happen to be created derives from seeds instead. An example is the
  quality of a latent part, which derives from the parent's seed, role, and
  index. A latent part gets a counter-allocated ID when it is revealed, but its
  properties don't depend on that ID.
- **Tombstones.** When an entity is destroyed, merged, or consumed, a
  tombstone records:
  - its ID and blueprint
  - the event that ended it
  - its successor, if any (merged into, split into, or remains)

  Beliefs, evidence, and history can refer to entities that no longer exist.
  Those references resolve to the tombstone; they never dangle or get reused.

### 2. Component kinds and field registration

Each component kind declares its fields once. Each field declares:

| Declaration | Meaning |
| --- | --- |
| Type and unit | A typed struct with its unit descriptor, as in the domain simulation doc |
| Owner | `self` (stored on the component) or a domain (read through that domain and never stored on the component) |
| `content` | May be set by blueprints and instances |
| `saved` | Written to saves. Fields derivable from others are not saved. |
| `proposable` | Changes may be proposed through change commitment |
| `derived` | Computed from a base value plus modifiers (see the [Modifiers channel](#modifiers)) |
| `perceive` | Which senses or skills can perceive the field, and how precisely. This is the hook for the player's inspector (§4). |
| `inspect` | Shown in the developer inspector |

Rules:

- **Components hold no pointers** to other components or entities, only
  entity IDs and component kinds. This keeps saves trivial and avoids hidden
  aliasing.
- **Components may have methods**: pure computations over their own state, and
  handlers for the channels. **All authoritative changes are proposals**,
  including changes to the component's own state. A handler returns proposals;
  it never mutates anything. This keeps the causal trace complete. Components
  are cold data, so the extra step is cheap.
- Whether the field registry can be derived from mulle-objc's runtime property
  metadata, or has to be generated from declarations, is an open question.

### 3. Stores and queries

- There is one store per component kind, keyed by entity ID and **iterated in
  ID order**, never hash order.
- Supported queries:
  - by kind
  - by intersection of kinds, driven by the smallest store
  - by relation, through an index on each relation kind
  - by tile, through a spatial index derived from location
- Indexes are derived and rebuilt on load. Only stores, relations, tombstones,
  and the ID counter are saved.

### 4. Channels

Components interact only through these channels:

| Channel | Direction | Contract |
| --- | --- | --- |
| Domain participation | Component → domain | Declared joins, parameters, and stock holders. See the domain simulation doc. |
| Capabilities | Component → action (§1) | Offers a capability: provider, capacity, conditions, costs, and compatibility. Defined in [ACTIONS.md](ACTIONS.md) §2. |
| Modifiers | Component → derived value | See [Modifiers](#modifiers) below |
| Reactions | Committed event → component | See [Reactions](#reactions) below |

<a id="modifiers"></a>**Modifiers**

- A modifier names its target entity, the derived value it affects, a stage,
  a magnitude with units, and its source.
- **Stages are applied in a fixed order:**
  1. base value
  2. additive
  3. multiplicative
  4. clamp
  5. override

  Within a stage, operations commute: fixed-point sums and products.
  Overrides are resolved by declared priority, then by source ID. The result
  never depends on the order modifiers were collected in.
- Derived values declare what they depend on. The dependency graph must be
  acyclic, and this is checked at registration.
- Results may be cached, with invalidation when a modifier is added, removed,
  or changed, or when an input value changes.
- Physical dynamic values, such as temperature, are not derived values. They
  belong to domains. Modifiers are for values like manipulation precision,
  carrying capacity, or perceived trustworthiness.

<a id="reactions"></a>**Reactions**

- A component subscribes to kinds of committed event **in which its own entity
  takes part in a declared role**, such as `target` of a `hit`. There is no
  global broadcast.
- Reactions return proposals. Those proposals are committed in the next commit
  round at the same boundary. Each boundary allows a bounded number of rounds,
  and leftover proposals are deferred to the next boundary and traced.
- All reactions to a round see the same committed state, so the order
  reactions run in cannot change the result.

### 5. Relations

Each relation kind declares:

- its arity, which is binary for now, and which entity kinds it connects
- its cardinality: one-to-one, many-to-one, or many-to-many
- its exclusivity groups
- whether it is symmetric
- its attributes, typed with units
- whether it is reified

Relations are stored with indexes in both directions. They reference entity
IDs only.

**Reified relations.** Each instance is an entity, with components of its own
and participant edges (`claimant`, `subject`, `issuer`, and so on). A reified
instance can be referenced, forged, contested, copied, and remembered like any
other entity. Claims are always reified. Plain edges remain for cheap
structural relations such as adjacency and connections.

**Location** is the one mandatory exclusive relation group for physical
entities:

| Location form | Meaning |
| --- | --- |
| `onTile(x, y, level)` | On the map |
| `in(container, slot?)` | Inside a container |
| `heldBy(entity, hand)` | Held |
| `wornBy(entity, slot)` | Worn |
| `partOf(assembly, role, index)` | Installed in an assembly |

Rules:

- **Every physical entity has exactly one location at every commit boundary.**
  Informational entities have none. Commit validation enforces this.
- Moving an entity is a single change that replaces its location.
- Capacity limits are checked at commit: container volume, free hands, and
  slot compatibility.
- The spatial index and "everything inside X" queries are derived from
  location.

### 6. Physical entities and conservation

- A physical entity has a `Body`: mass, volume, material, and any traces
  (marks, damage, residue).
- A **container's total mass** is derived from its own body, plus the stocks
  it holds, plus the entities located inside it.
- **Body mass is conserved** by the commit rules for split, merge, assembly,
  and detachment. It is created or destroyed only by declared processes, such
  as combustion consuming fuel, with exact integer accounting. This matches
  the domain simulation doc.

### 7. Physical assembly

- An assembly is an entity with an `Assembly` component, which holds:
  - its latent descriptor and seed
  - which levels have been revealed
  - the aggregate parameters that domains read
- Revealed parts are entities with location `partOf(assembly, role, index)`.
  Their mass is carved out of the aggregate's mass, so the total is unchanged.
- **Parts inside an assembly join no domains.** Detaching a part changes its
  location to `onTile`, `heldBy`, or similar. It then joins domains in its own
  right, and domains treat the detachment as a topology change.
- **Inspection never changes aggregate parameters.** Physical operations on
  parts (replace, repair, damage) update the aggregate through the assembly's
  declared rule, **as a delta**: the old part's contribution is removed and
  the new one's added. Re-deriving everything from the parts would make the
  first inspection cause a jump in behaviour.
- The latent assembly document will specify materialization, consistency with
  history, and culprit attribution.

### 8. Informational content and physical copies

- **Content** is an informational entity with a `Content` component holding
  the text or diagram data. Its origin is the authoritative creation event in
  history. What the content *says* about its origin, such as "issued by the
  harbour office", is part of its data and may be false.
- **A copy** is a physical entity with an `Inscription` component, which
  references a content ID and carries physical features: hand, ink, seal
  impression, fidelity, wear.
- **Copying.** An exact copy is a new physical entity referencing the same
  content. An altered or imperfect copy creates new content with a
  `derivedFrom` relation to the original, so provenance forms a chain.
- **Destroying a copy** does not destroy its content. Content persists while
  anything references it: a copy, a memory, or a derivation. Unreferenced,
  it is collected, and history keeps a summary (decision 10).
- Organizations and claims are informational entities too. They have no
  location, although they may be represented by physical things: a seal, a
  ledger, a building.

### 9. Identity on demand

There are three levels of identity:

| Level | Represents | Example |
| --- | --- | --- |
| Stock | A divisible amount, owned by a domain and held by an entity | 8 L of water in a bucket |
| Stack | A count of identical discrete units, as one entity | 30 nails in a bin |
| Individual | One unit with its own identity | The bent nail with tool marks |

**Individuation**

- **Splitting a stack** creates a new entity (a stack of N, or an individual
  if N = 1). It gets a new ID, a `splitFrom` provenance edge, and the stack's
  unit spec.
- **Dividing an individual**, such as cutting a strip from a hide, creates a
  new entity whose body is carved from the original. The original persists,
  smaller.
- **Automatic individuation.** Any committed change that would give one unit
  of a stack distinguishing state must first split that unit off. Examples are
  a trace, damage, a claim on that one unit, or a part attaching. The commit
  machinery does this; proposers don't have to remember.

**Merging**

- Units merge into a stack only if they are **physically indistinguishable**:
  - the same unit spec
  - no traces or damage
  - no relations other than location (provenance edges such as `splitFrom`
    are history and don't count)
  - no reified claim on the individual alone. A quantity claim over several
    entities follows the units: splitting a claimed stack extends the claim
    to the split-off entity, so an unmarked nail carries the claim, and it
    still merges back. (Found by the laboratory's variant A.)
- **Knowledge does not prevent merging.** If an agent "knows which nail it
  was" but nothing physical distinguishes it, the identity is lost once it's
  mixed back in. That is realistic. The agent's belief now resolves to a
  tombstone whose successor is the stack.
- **Claims on stacks are quantity claims**, such as "the miller owns 25 of
  these 30". Merging adds up claim quantities per claim. Which units a split
  carries away is not assigned. How institutions resolve that is an open
  question; it is an opportunity for disputes about mixed goods.

The same principle applies at larger scales, such as crowds and regional
aggregates becoming individuals as they come into view. That is out of scope
here.

### 10. Blueprints and content

The format is specified in [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md). It
must meet these requirements:

- **Unification semantics.** A blueprint combines constraints from its
  parents, mixins, and instance overrides. Conflicting constraints are load
  errors; there is no silent last-write-wins.
- Blueprints resolve at load into flat, immutable **specs**. Runtime state is
  never written back into a blueprint.
- Values carry units and are converted through unit descriptors.
- Only fields declared `content` may be set by content.
- Constructing components from a spec is deterministic, given the spec, the
  seed, and the allocation order.
- A blueprint may reference latent assembly descriptors, unit specs for
  stacks, and domain participation parameters.

### 11. Change commitment hook

The change commitment contract is in [ACTIONS.md](ACTIONS.md) §8–11. The component system
requires it to provide:

- **Atomic changes spanning several entities**: split, merge, move, detach,
  install.
- **Validation of invariants before commit**: location exclusivity,
  conservation of mass and count, cardinality, capacity, and automatic
  individuation.
- **Deterministic ID allocation** in commit order.
- **Committed events** for reactions, traces, and history, with causes
  attached.
- **Rejections reported back to the proposer**, together with the reason.

### 12. Observation, traces, and saves

- **Developer inspector:** shows every field marked `inspect`, the relations,
  provenance chains, tombstones, and each derived value broken down into its
  modifiers.
- **Player view:** built by perception (§4) from the `perceive` declarations
  and the observer's senses and knowledge. Components never format anything
  for the player.
- **Traces:** each commit records field changes, relation changes, and ID
  allocations, with their causes.
- **Saves** contain the stores (each kind versioned by its field registry),
  the relations, the tombstones, and the ID counter. Indexes and caches are
  rebuilt on load.

### 13. Interface sketch

Illustrative only; this has not been compiled.

```objc
@interface BGThermalBody : BGComponent
@property BGHeatCapacity heatCapacity;    // content, saved, inspect
@property BGConductance  surfaceConductance;
@end

@implementation BGThermalBody
+ (void) declareFields:(BGFieldRegistry *) r
{
   [r field:@"heatCapacity"
       unit:BGUnitHeatCapacity
      flags:BGFieldContent|BGFieldSaved|BGFieldInspect];
   [r domainField:@"temperature"          // owned by the thermal domain
           domain:@"thermal"
          perceive:BGPerceiveTouch];
}
@end

// world-level access
BGStore  *bodies = [world storeFor:[BGThermalBody class]];
BGThermalBody *b = [bodies componentFor:entity];
```

## Scenarios

Each scenario lists its purpose, setup, sequence, choices and uncertainty,
observable information, and acceptance checks. Numbers are illustrative.

### Scenario 1: The marked nail

**Purpose:** splitting and merging stacks, automatic individuation, merging
blocked by physical distinction, tombstones as successors, and quantity
claims on fungible goods.

**Setup**

- A workshop bin containing a stack of 30 iron nails: one entity with a
  `Stack` component, count 30.
- A reified ownership claim: the smith owns 30 nails in this stack.
- Two agents: a worker and the smith.

**Sequence**

1. The worker takes 5 nails. The stack splits into the bin's stack of 25 and
   a new stack of 5, located `heldBy(worker)`, with `splitFrom` provenance.
2. The worker hammers one nail in to wedge a lock shut. That nail is first
   split off automatically as an individual. It then gets a bent body and
   fresh tool marks (traces) and is located `partOf` the wedged lock, or
   `onTile` if it is pulled out later.
3. Later the worker pulls the bent nail out and drops all 5 back into the bin.
   - The 4 clean nails merge into the bin stack, which becomes 29. Their
     entity, the stack of 4, is tombstoned with the bin stack as its
     successor.
   - The bent nail cannot merge. It stays an individual inside the bin.
4. An investigator searching the bin later can find the bent nail, which is
   evidence for §4.

**Variants**

- **A, no marks:** the worker uses an unmarked nail and returns it. It
  merges, and the smith's belief "that nail went back into the bin" resolves
  through a tombstone to the bin stack.
- **B, mixed goods:** the worker owns 10 nails of the same spec and pours
  them into the smith's bin. The stack becomes 35 or 40, carrying two
  quantity claims. Taking 5 out leaves it unresolved whose they are.

**Choices and uncertainty**

- The worker chooses whether to return the bent nail, hide it, or discard it
  elsewhere.
- Observers cannot tell clean nails apart, only marked ones.

**Observable information**

- **Player:** the stack count, if counted. The bent nail's marks if it is
  examined.
- **Developer:** provenance edges, tombstones and their successors, and the
  claim quantities.

**Acceptance checks**

1. **Count and mass are conserved exactly** across every split and merge.
2. **Location is exclusive** at every commit boundary.
3. **Automatic individuation:** marking a nail while it is still inside a
   stack splits it off before the trace is committed. A proposer that doesn't
   ask for the split still gets it.
4. **Merging is blocked** for the marked nail. A merge proposal is rejected
   with a stated reason.
5. **Tombstones:** every reference to a merged stack resolves to a tombstone
   with the correct successor.
6. **Quantity claims** sum correctly on merge in variant B. A split leaves the
   allocation explicitly unresolved, not silently assigned.
7. **Determinism:** IDs and the final state are bit-identical on replay.

### Scenario 2: The forged permit

**Purpose:** separating content from copies, provenance chains, claimed versus
actual origin, informational entities without a location, and authority that
can be traced only to legitimate entities.

**Setup**

- The harbour office: an organization, an informational entity.
- Permit content P, created by an office procedure. It authorizes Alun to
  enter the warehouse. The authorization is a reified relation, created by
  the office and linked to P.
- One copy, C1: paper, ink, the office seal's impression. Held by Alun.
- The office's ledger: a physical entity with an `Inscription` referencing
  register content, which lists P.

**Sequence**

1. A forger borrows C1 and makes C2, a hand copy with the name changed.
   - This creates new content P′: `derivedFrom` P, altered, and claiming the
     harbour office as issuer. Its actual creation event belongs to the
     forger.
   - C2's `Inscription` references P′ and carries physical features: the
     forger's handwriting traits, and a seal impression from a carved fake
     stamp, which is itself a physical entity.
2. The forger shows C2 to the warehouse guard. Perception gives the guard the
   claimed content and whatever features the guard can perceive. Whether the
   guard believes it is §4's business.
3. No authorization relation links to P′. Legitimate authority traces only to
   the reified authorization created by the office.

**Variants**

- **A, official duplicate:** a clerk makes C3, an exact copy of P. It is a new
  physical entity referencing P, and it is legitimate.
- **B, fire:** C1 burns. P persists, because the ledger and C3 reference it
  and Alun remembers it. Alun's references to C1 resolve to a tombstone.

**Choices and uncertainty**

- The forger chooses copy quality: hand, ink, effort on the seal.
- The guard does not know whether the seal is genuine. They may know what
  the office's seal should look like.

**Observable information**

- **Player:** the claimed content, plus the physical features their senses
  and skills can perceive.
- **Developer:**
  - actual versus claimed origin
  - the `derivedFrom` chain
  - which authorization relations exist, and where they came from

**Acceptance checks**

1. Content, organization, and authorization entities have **no location**.
   Copies, the ledger, and the stamp each have exactly one.
2. The `derivedFrom` chain from P′ to P is correct, and P′'s actual creation
   event names the forger.
3. **Claimed and actual origin are both stored.** The developer inspector
   shows both. The player view, built from `perceive` declarations, shows
   only the claimed origin and perceivable features.
4. **Destroying a copy never destroys content** that something else still
   references.
5. A query for authority over the warehouse returns only the authorization
   created by the office. P′ confers nothing.
6. The fake stamp, P′, C2, and the forger's creation event can all be found
   through provenance and traces, which is the hook for investigation.

### Scenario 3: The pump, from the component side

**Purpose:** assembly as a location relation, mass carving and conservation,
domain participation on detach, aggregate updates as deltas, dividing an
individual, and claims covering parts. This shares its setup with Scenario 2
of the domain simulation doc.

**Setup**

- The miller's hand pump: an entity with an `Assembly` component. The flow
  loss failure has been committed and nothing is revealed yet.
- A reified claim: the miller owns the pump. The claim kind declares that it
  covers parts through `partOf`.
- The player has a leather hide, an individual entity they own.

**Sequence**

1. Opening the cover reveals level 1. Part entities are created with
   `partOf(pump, role, index)`, and their mass is carved from the aggregate.
2. The player extracts the piston, which is itself an assembly with a nested
   seal.
   - Its location changes to `onTile`.
   - It joins domains as a standalone entity.
   - The domain simulation sees a topology change.
3. The player cuts a strip from their hide, dividing an individual. The hide
   persists, smaller. The strip is a new entity with a `splitFrom` edge.
4. The player shapes the strip into a replacement seal and installs it in the
   piston. The old seal becomes `onTile`. The assembly's declared rule
   updates the pump's aggregate flow capacity as a delta: the old seal's
   contribution is removed and the new seal's is added.
5. The player reinstalls the piston.

**Choices and uncertainty**

- The player can repair the pump, replace the whole unit, or leave it.
- They choose what material to use for the seal.
- They don't know whether the seal was the culprit until it is revealed.

**Observable information**

- **Player:** the revealed parts and their visible condition, and the pump's
  performance afterwards.
- **Developer:** location changes, mass carving, the delta applied to the
  aggregate, and claim coverage.

**Acceptance checks**

1. **Location is exclusive** throughout. Every part is `partOf` exactly one
   assembly, or located elsewhere.
2. **Mass is conserved:** the aggregate plus parts stays constant. The strip's
   mass is carved exactly from the hide.
3. **Part qualities don't depend on reveal order.** Revealing the piston's
   nested level before or after other level-1 parts gives the same qualities.
   IDs come from the counter.
4. **Inspection alone** never changes aggregate parameters. Replacing the seal
   changes them by exactly the delta for that seal.
5. **Claim coverage:** the miller's claim covers the pump's parts through
   `partOf`. The detached old seal is still covered through its provenance.
   The installed new seal keeps the player's claim, and the miller's does
   not reach it (decision 11): whether fitting it was a gift, a sale, or a
   wrong is for people and institutions to settle.
6. **Domain participation:** the piston is a domain participant only while it
   is detached.

## What we take from Qud and Dewdrop

| Source | Idea | Here |
| --- | --- | --- |
| Qud | Behaviour by composing parts | Component kinds in per-kind stores |
| Qud | Blueprints with inheritance | Unification-style blueprints, resolved into specs |
| Qud | Parts register arbitrary event handlers | Replaced by the closed channel set; reactions only on committed events where the entity has a role |
| Dewdrop | Property registry drives init, export, sensors, and actuators | The field registry drives content, saves, proposals, perception, and inspection |
| Dewdrop | Type → model → instance precedence | Unification instead of precedence; conflicts are errors |
| Dewdrop | Per-unit seeds from stable IDs | Seeds are kept separate from allocated IDs so that properties don't depend on order |
| Dewdrop | The same electrical and thermal fields on every component | Rejected; domains own dynamic values |

## Open questions

1. **Content format.** Decided in [CONTENT_LANGUAGE.md](CONTENT_LANGUAGE.md):
   a typed feature structure language with TDL semantics and CUE-style
   syntax. Its own open questions include whether it generates the
   component classes (open question 6 here).
2. **Mixed fungible goods.** How do quantity claims resolve after a split?
   Institutions decide, but what does the component layer record?
3. **Installed parts.** Decided: decision 11.
4. **Lifetime of informational entities.** Decided: decision 10.
5. **Reaction rounds.** What is the bound on reaction rounds per boundary, and
   what does the player see when proposals are deferred?
6. **Field registry.** Decided (CONTENT_LANGUAGE.md §3): it is generated
   from the content's `@component` declarations, which also generate the C
   structs the stores use.
7. **Stores at scale.** Should stores be sorted arrays or B-trees, and do we
   want stores partitioned by region for large worlds?
8. **Larger-scale aggregates.** How does identity on demand extend to crowds
   and regions, the variable-resolution idea in CHAT.md?
