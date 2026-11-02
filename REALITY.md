# The reality bubble

## Status and scope

How much of the world is simulated how exactly, and where. Today everything
is simulated at full detail everywhere, and every agent's every completion
makes a boundary at which every agent perceives and every mind decides: the
cost of a simulated second grows with the square of the agents. That is fine
for a workshop and fatal for a large roguelike or simulation.

This document is a draft. Nothing in it is built yet.

The aim is a world simulated exactly where it matters, and less exactly, by
degrees, further away, with the degrees, their reach, and what each thing
does at each, set in content and tunable, while running.

## Decisions so far

1. **Four levels of detail.** Every chunk of the world is at one of them:
   - **Full:** everything exact. Agents perceive and decide on what
     concerns them; the domains step exactly.
   - **Reduced:** agents act at a coarser cadence and perceive only what
     involves them directly; the domains take longer steps.
   - **Abstract:** no perception. What progresses, and how, is authored
     (decision 4): needs, schedules, a day's work, a crop's growth, done in
     bulk over the time that passed. The domains are summarised: a tank
     draining is a formula, a room cooling an exponential.
   - **Frozen:** nothing runs. Brought back up, a chunk is caught up for
     the time it was frozen (decision 6).
2. **Anchors set the levels.** An anchor is anything that projects detail
   around it: the players, by default, and any entity content or the game
   chooses (a camera, a character the story follows, a siege under way).
   Each kind of anchor has a radius for each level. A chunk takes the
   highest level any anchor in reach gives it. Entities, rooms and regions
   of air take the level of where they are; a room across chunks, the
   highest of its tiles.
3. **The dials are content.** The levels' radii per kind of anchor, the
   reduced cadences, the domains' step lengths at each level: all in
   Triangle, beside the rest, so a game tunes them without code, and the
   developer can change them while it runs. With no anchors at all, the
   whole world is full, as it is today, so every scenario keeps its
   results.
4. **What progresses away from the players is authored.** Content says,
   per kind of thing, what it does at each level below full: an agent's
   needs rise and its routine is worked through in bulk; a forge's day
   turns iron into horseshoes; a crop grows; a wound festers or heals; or,
   for gameplay, nothing at all until someone is there to see it. Some
   things may be held at a level whatever their distance (a plot's key
   character acts as its own anchor). Bulk progression is deterministic,
   drawn from the world's seed, the entity and the period.
5. **Levels are derived, with hysteresis.** A chunk's level is computed
   from the anchors' positions, again only when an anchor crosses a chunk
   edge. The radius to rise into a level is less than the radius to fall
   out of it, so an anchor walking along a chunk edge doesn't flap the
   world between levels. Derived from saved state, the levels need no
   saving of their own, and a game saved and resumed is the same.
6. **Changing level is a transition, with a catch-up.** Rising, a chunk
   is brought to now from the time it last advanced: frozen, by the
   authored progression for the time it was frozen; abstract, by its
   summaries settled into exact state (the formula's tank level, written
   as stock). Falling, exact state is summarised: activities under way are
   finished, suspended, or handed to the authored progression, as content
   says. A thing crossing between chunks of different levels (an agent
   walking into the bubble) is caught up before it enters.
7. **Within full detail, work is done when something happens.** The bubble
   bounds how many agents are at full detail; within it, an agent
   perceives only when an event lands within its senses (the spatial
   index), and decides only when what it decides from has changed: new
   knowledge, an activity of its ended, a wake it set, a need crossing a
   threshold. What rises with time alone (hunger, tiredness) is predicted,
   as a wake, not polled at every boundary.
8. **Built for threads, threaded later.** Perception and decision read
   only committed state and the agent's own memory; they can run in
   parallel, agent by agent, their proposals then committed one at a time
   in a fixed order, so the result is the same however many threads ran.
   The levels give the work units: the full chunks' agents across workers,
   catch-ups in batches. What is shared (interned strings, caches, the
   path search's buffers) is to be audited before any thread runs.
9. **The outdoors is a sink.** Outdoor air is a reservoir of fixed
   temperature and composition, as it is now, not a volume simulated.
   Local conditions out of doors (smoke from a fire, dust, mist, what they
   do to sight and breath) are sparse plumes: kept per chunk only near
   their source, spreading and decaying to the background, nothing where
   nothing disturbs the air. Built when a scenario needs it.

10. **Contact pulls up, by lease, and lets go.** Whatever a full-detail
    agent perceives or acts on is raised to full for as long as the contact
    lasts: content says what counts as contact (seeing, speaking, fighting,
    trading) and how long its lease runs after the contact ends. A raised
    thing holds a lease, not an anchor: when every lease has run out and no
    anchor reaches it, it falls back past the hysteresis, through the same
    transition as anything leaving the bubble (decision 6). Leases are
    state: saved, and part of the hash.
11. **Abstract progression is coarse.** Abstract agents don't take this
    object or open that door; they work on coarse state: needs, stocks,
    skills, standing, the condition of their things and places. What
    changes in a place while no one watches (a house falling into
    disrepair, a larder emptied, a field gone to weed) is the place's own
    authored progression, made concrete when the place rises: its catch-up
    may turn a condition into things (rubble, dust, a broken shutter).
12. **Reach is chunks across and levels up and down.** Each kind of anchor
    has, per level, a radius in chunks across and a reach in levels up and
    down, separately: a mine's levels below matter less than a street
    across.

13. **Each kind says which systems run at each level.** Content declares,
    per kind of thing and per level, which systems are suspended and which
    are engaged in their stead: these agents, at reduced, keep perception
    and decision on a cadence; at abstract, suspend both and engage their
    progression; this forge, at abstract, suspends the fire's domain and
    engages a day's work. Progression is authored two ways, both in
    Triangle:
    - **Rates on fields:** a field declares how it moves at a level
      (`hunger` rises so much an hour while abstract; a house's `repair`
      falls so much a season). Closed form, so catching up is one sum;
      most of the volume: needs, decay, growth.
    - **Periodic operations:** for processes that turn one thing into
      another under a condition: what they apply to (a pattern, matched as
      methods' `pre` are), a period, and effects in the existing effect
      vocabulary (a day at the forge: iron less, horseshoes more, while
      there is iron). Caught up period by period, or in one step where
      the effects are linear and the condition holds throughout.

## Steps

Each keeps every existing scenario as it is: with no anchors, everything is
full.

1. **Work when something happens** (decision 7). Perception per agent only
   for events within its senses, and for its own; decision only for minds
   whose inputs changed; needs that rise with time predicted as wakes.
   Measured: boundaries and agents worked per simulated second, before and
   after, on a crowd.
2. **Anchors, levels and leases** (decisions 2, 3, 5, 10, 12). The
   content (`#Reality`: per kind of anchor and level, the reach across and
   up and down; the cadences; what counts as contact, and its lease),
   anchors, the chunk level map with hysteresis, leases, and the developer's view of it (a
   Tessera overlay once Tessera draws).
3. **Reduced detail.** Agents' coarser cadence and narrower perception;
   the domains' longer steps.
4. **Frozen, and catching up** (decision 6). A chunk's clock; catch-up on
   rising: the domains in closed form, activities finished or failed as
   they would have.
5. **Abstract progression** (decision 4). Authored progression in content,
   applied in bulk, deterministic by seed; summaries settled on rising;
   activities handed over on falling.
6. **Threads** (decision 8). The audit of shared state; perception and
   decision across workers; a fixed commit order.
7. **Outdoor plumes** (decision 9), with their first scenario.

## Open questions

- **Catching up fast, and reading what lags** (a known unknown, deferred).
  A frozen chunk lags the world's clock until caught up. Every system will
  need a fast catch-up (closed form, or bulk by period), and anything
  reading a lagging chunk from outside (an agent far off asking about it,
  a save) must see it as of when it last advanced, or catch it up first.
  Settled system by system as each is built.
- **News across the world** (deferred; an idea noted). Agents abstract
  perceive nothing, yet news
  should travel: a death in one town known in the next a week later. One
  direction: below full detail, knowledge is held by communities (a place,
  a household, a guild), not by each agent; news moves between communities
  along routes, with a delay and a fidelity set by the route (trade, a
  road, a messenger); an agent rising is told what its community knows
  (KNOWLEDGE.md's testimony and rumour, at a coarser grain). How rumour
  distorts, and who hears first, wants a design of its own.
- **Contests across levels.** Abstract progression should not take what
  someone at full detail could see taken; keeping it to coarse state
  (decision 11) and to what is its own (its home, its work) does most of
  that. What is left (a town's market supplied from abstract farms while a
  player shops there) is settled through stocks, not objects.
