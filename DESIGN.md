# Maximalist Roguelike: Design Proposal

## Status and scope

This is an initial design proposal, not an implemented architecture. The next
step is to develop detailed scenarios and use them to refine the system contracts
before implementing the framework.

Confirmed direction:

- A maximalist, tile-based roguelike.
- Flesh out the systems first, build an engine or framework next, then build the
  game on that foundation.
- Build the framework for this roguelike, extracting reusable modules where useful.
- Use the language [STACK.md](STACK.md) specifies: Odin, and C for Triangle.
- Support simulation advancing in time slices, continuous running, and strict
  pausing for player input.
- Discard the proposed name and setting in [CHAT.md](CHAT.md). Examples here are
  system experiments and do not establish a setting.

The core proposal is a common framework for actions and consequences, with
specialized simulations underneath. Small, inspectable scenarios should prove
the framework before we build the larger game.

Simulation time and the policy for advancing it must be separate. The same world
should support stepping, continuous running, and pausing for player input.

## 1. Capabilities, actions, and activities

The action and change commitment contracts, decisions, and test scenarios are
in [ACTIONS.md](ACTIONS.md). [ARCHITECTURE.md](ARCHITECTURE.md) shows how all
the specified systems fit together.

Capabilities describe what something can contribute to an operation. They need
more structure than tags such as `can_repair`:

- **Provider:** a body part, tool, machine, assistant, or institution.
- **Capacity:** force, precision, throughput, range, or another relevant quantity.
- **Conditions:** requires power, a free hand, access, or particular surroundings.
- **Costs:** consumes material, energy, attention, durability, or time.
- **Compatibility:** fits this fastener, handles this substance, or applies in this
  jurisdiction.

This supports improvisation. A stone might provide adequate impact force for
driving a peg, but insufficient precision for repairing an instrument. A powered
machine might replace several manual tools while adding new dependencies.

An **action** binds participants to roles and proposes an attempt. An **activity**
preserves an attempt that takes time: preparation, progress, intermediate effects,
interruption, and completion.

Several distinctions deserve explicit representation:

| Question | Why it matters |
| --- | --- |
| Can the actor formulate the attempt? | Recognition, instructions, knowledge |
| Can they begin? | Reach, available equipment, immediate conditions |
| What do they expect? | Potentially mistaken understanding |
| What actually happens? | Authoritative domain resolution |
| Is it permitted, and by whom? | Authority and institutional consequences |

A repair interrupted halfway should leave a partially dismantled machine. Two
simultaneous activities cannot silently consume the same replacement part. An
unknown defect should not disappear from the action menu in a way that reveals
its existence.

## 2. Entities, components, and relationships

The component system's contract, decisions, and test scenarios are in
[COMPONENTS.md](COMPONENTS.md).

An entity supplies stable identity. Components supply particular kinds of state
and behavior. Relationships connect entities.

Distinguish three structures:

- **Behavioral composition:** an object participates in temperature, damage,
  storage, and other systems.
- **Physical assembly:** an object contains removable parts.
- **Relationships:** an object is possessed by someone, claimed by someone else,
  connected to machinery, or referenced by a document.

A thermal component is software machinery; a removable heating element is an
object in the world. Keeping those distinct lets us dismantle, replace, steal,
damage, or manufacture parts without making every software component a physical
item.

Each authoritative state field needs an owner and explicit mutation rules.
Several systems can influence a creature's temperature, but they must coordinate
their contributions instead of independently overwriting it.

This foundation should support creatures, equipment, terrain features,
organizations, and documents without requiring all of them to carry the same
enormous collection of properties.

## 3. Specialized simulations and shared time

This system is called **domain simulation**. Its contract, decisions, and test
scenarios are in [DOMAIN_SIMULATION.md](DOMAIN_SIMULATION.md).

Each simulation domain should declare:

- The state it owns and the information it reads.
- What activates it.
- How far it can safely advance.
- What changes it proposes.
- Its invariants and approximation limits.

Fluid flow, infection, market transactions, and memory decay can use different
algorithms and update frequencies.

Time has three separate concepts:

| Concept | Responsibility |
| --- | --- |
| Simulation clock | When things happen within the world |
| Scheduler | Which actions and processes advance, and in what order |
| Run policy | Whether advancement is stepped, wall-clock paced, or waiting for input |

This allows a long activity to advance in slices, a world to run continuously, or
a classic roguelike interface to pause whenever the player needs to decide.

Numerically continuous processes would still use suitable integration steps.
Those steps should be independent of rendering frames and player turns.
Switching run policy should preserve ongoing activities and pending consequences.

We need explicit rules for simultaneous conflicts and coupled processes.
Broadcasting events and letting handlers mutate things is too weak a contract for
interactions such as fire consuming oxygen while ventilation replenishes it.

## 4. Events, evidence, observations, and beliefs

This system is called the **knowledge system**. Its contract, decisions, and
test scenarios are in [KNOWLEDGE.md](KNOWLEDGE.md).

This foundation supports substantially more than environmental chain reactions.

| Concept | Example |
| --- | --- |
| Event | Someone damaged a mechanism |
| Trace | A bent part and fresh tool marks remain |
| Observation | Someone sees the damage |
| Interpretation | They conclude it was deliberate |
| Claim | They tell another person who they suspect |
| Belief | That person accepts, doubts, or rejects the accusation |

An observation can also be a measurement of current conditions; it does not
require witnessing an event.

**Evidence can be manipulated through ordinary actions.** Cleaning, repairing,
moving, copying, and destroying things can alter what others can discover.

**Information has ancestry.** Three witnesses repeating one rumor are not three
independent confirmations. Provenance should let the system distinguish
repetition from corroboration.

The developer's causal inspector can expose authoritative explanations. The
player's inspector must expose only what their character can perceive or infer.
Those should be separate views from the beginning.

## 5. Agency

The agency contract, decisions, and test scenarios are in
[AGENCY.md](AGENCY.md).

The preceding foundations explain how actions work, but not why anyone acts.

NPCs need goals, needs, commitments, habits, and limited attention. They should
select actions using their knowledge and expectations, then execute through the
same action machinery as the player.

We do not need an unrestricted planner initially. A small set of meaningful
behaviors—investigate a disturbance, seek a missing tool, protect a possession,
request help—would already test whether knowledge actually influences conduct.

## 6. Institutions

Institutions deserve their own model: membership, jurisdiction, authority,
obligations, recognized ownership, and procedures.

A forged permit can affect a guard's belief without creating legitimate
authority. Conflicting institutions can recognize different owners.

Agency and institutions are essential if the eventual maximalism includes
deception, cooperation, trade, law, and social consequences.

## What makes this maximalist

The ambition should remain broad. These foundations could support:

- Materials and machinery.
- Anatomy and ecology.
- Crafting and invention.
- Combat and stealth.
- Communication and investigation.
- Trade and production.
- Organizations and obligations.
- Potentially supernatural systems, once their rules are decided.

For each domain, specify both its internal depth and its connections. Anatomy
changes manipulation capabilities. Injury affects work. Work affects production.
Scarcity changes incentives. Incentives influence theft. Theft leaves evidence.

Identify the decisions each connection creates. A detailed simulation earns its
place when players can notice it, reason about it, intervene in it, or experience
its consequences.

## Development sequence

1. **Design a scenario corpus.** Work through roughly a dozen varied situations:
   improvising a tool, interrupted treatment, contested ownership, deception,
   teaching, sabotage, simultaneous resource use, and an unattended process.
   Specify state, choices, uncertainty, consequences, and observable information.
2. **Define the framework contracts.** Identity, state ownership, spatial
   relationships, action lifecycle, time advancement, change commitment, and
   knowledge boundaries.
3. **Build a simulation laboratory** (in Odin; STACK.md). Include a small tile
   map, command interface, stepping/running controls, state inspection, and causal
   traces. Save/load and reproducibility should arrive early.
4. **Prove interactions through several small scenarios.** Add only enough domain
   behavior to test the contracts.
5. **Build the game on the demonstrated framework.** Content generation,
   progression, setting, and the larger gameplay structure follow.

## First integrated laboratory proposal

Use a damaged mechanism, transferable material, two agents, interchangeable tools,
an ownership claim, and an imperfect diagram. This is enough to test
improvisation, interruption, physical propagation, mistaken knowledge,
unauthorized action, and an NPC discovering a consequence.

The acceptance test should include a second, substantially different
scenario—perhaps treatment and consent—so the framework demonstrates usefulness
beyond machinery.

The next design step is to write these scenarios in detail and use them to
sharpen the six systems. This gives us concrete decisions to debate before
committing to engine interfaces.
