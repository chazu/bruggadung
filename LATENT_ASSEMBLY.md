# Latent assembly

## Status and scope

The document COMPONENTS.md §7 points to: how a latent assembly's parts
come to exist (materialization), how they agree with what happened to the
unit (consistency with history), and which part a failure is due to
(culprit attribution). It adopts the rules the lab has run provisionally
(lab/content/latent.tri, `BGLatentKind`), and marks what is still to be
designed.

## Fixed by COMPONENTS.md §7

- An assembly (`Latent`) keeps what has been revealed and its history.
- Revealed parts are entities `partOf` it, their mass carved out of its
  own, so the total is unchanged.
- A part's properties come from the parent's seed and the part's role,
  never from an entity ID.
- Parts join no domains while inside; out, a part takes its share of the
  assembly's heat (DOMAIN_SIMULATION.md Scenario 2).

## Decisions so far

1. **A descriptor lists the parts** by role, each a part blueprint at a
   depth, and the culprit candidates for each kind of failure.
2. **Materialization is by opening**: opening an assembly to a depth
   reveals the parts at that depth, as entities, deterministically from
   the unit's seed and the roles.
3. **A culprit is marked only if it has been revealed**: a cause among
   parts not yet reached stays unresolved, and none is invented.

4. **An assembly's use is shared out as its parts' wear** (after dewdrop's
   latent anatomy). The assembly as a whole keeps how long it has been used,
   and how long of that it was abused (a pump worked dry). Its parts are
   never simulated one by one. Each role says how fast it wears (points per
   hundred hours of use) and how many times as fast under abuse. A revealed
   part's wear is that rate times the use, so opening early or late shows
   the same part worn by the same history.
5. **Use risks failure, and the culprit is weighted by wear.** Every hour of
   use risks each failure the descriptor names: its chance when new, up to
   four times that when its most worn candidate is worn through. The draw
   comes from the unit's seed and its use so far, so runs are reproducible.
   The culprit is drawn among the failure's candidates by the unit's seed,
   each weighted by its wear (plus a hundred hours' worth, so that a unit
   new to use is weighted by how fast each wears). It is decided once, at
   the failure, or, for a failure a scenario sets, when first opened. A
   culprit is worn at least 60, as a failure leaves it.
6. **A part's quality is hidden, from the unit's seed and its kind.** Each
   role's quality is 50, give or take 20 by the unit's seed, plus the
   blueprint's bias for that kind of part (a cheap pump whose leather is
   poor). Poor parts wear faster, half again as fast at 0, half as fast at
   100, and so are more often to blame.

## Provisional

- A part wears with use only: age alone (leather perishing on the shelf)
  doesn't wear it yet.
- A culprit's floor of 60, and a flow loss costing a pump 80 points of
  flow, are the lab's numbers, not derived.
- A candidate that is no part (the housing) wears at the default rate, two
  points per hundred hours, with a quality like any other.
- Neither maintenance nor replacing a part resets a role's wear yet: the
  failure chance and the culprit's weighting count the assembly's whole
  use, even past a new spare. A revealed part wears no further with use.
