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

## Provisional, to be designed

- **Culprit attribution** draws the culprit from the unit's seed and the
  failure alone. It is to be weighted by the unit's history: use, abuse,
  and maintenance.
- **A culprit's wear** is 60, plus a point for every ten hours since the
  failure. It is to come from the part's actual age and use.
