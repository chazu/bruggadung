# Scripts and plans in agents: prior work

A literature note, gathered 2026-11-06, for [METHODS.md](../METHODS.md).
The question it answers: how do agent architectures structure the ways an
agent reaches a goal, so that it doesn't do what a way needs when the need
is met already (a second axe, the coffer's coins with coins in hand), and
so that a failed way leads to a different way, not to a step of the same
one? Each section says what the work proposes, then what it means for
bruggadung's methods (AGENCY.md §5).

Sources marked *(unverified)* are from memory and weren't checked against
the text in this pass.

## 1. Scripts, plans, goals (Schank & Abelson, 1977) *(unverified)*

*Scripts, Plans, Goals and Understanding* splits stereotyped behaviour
into **scripts**: fixed sequences of scenes with roles and props, such as
the restaurant script. **Plans** are goal-directed means, assembled when
no script fits. A goal is reached by a script if one fits, else by a plan
that decomposes it into subgoals ("delta-goals": get to a place, get
control of an object, get knowledge).

**For us:** the delta-goals are exactly the subgoals our ladders flatten
into a goal's ways: be by the stall, hold the coins, know a price.
Schank's split also matches ours. A recipe (`sequence: true`, ACTIONS.md
§6) is a script; a method with subgoals is a plan.

## 2. Teleo-reactive programs (Nilsson, 1994)

Nilsson, *Teleo-Reactive Programs for Agent Control*, JAIR 1, 1994
([arXiv cs/9401101](https://arxiv.org/abs/cs/9401101)).

A **TR program** is a ranked list of condition → action rules. At every
moment the agent runs the action of the highest rule whose condition
holds. A program has the **regression property** when each rule's
condition is the regression of a higher rule's condition through its
action, so running a rule moves the agent up the list. A complete
program with the regression property is *universal*: it reaches the goal
from any state, if the actions succeed. TR programs have no failure
handling. A rule whose action fails stays the highest true rule and runs
again. Later work (Clark & Robinson's TeleoR) loosens the regression
property to "the action normally brings a state closer to the goal".
Colledanchise & Ögren show that behaviour trees generalise TR programs
(§5).

**For us:** most of the lab's multi-way goals are TR programs:
- the market's buying (bring it home ← unpack ← buy ← carry home ←
  fetch the coins ← look in the coffer ← go to the stalls);
- stocking the woodpile (stack ← gather ← split ← buck ← fell ← look for
  trees);
- hunting, tending a plot, setting out goods, returning a pack.

They work because the engine chooses afresh at every decision and the
actions mostly succeed. They break because the engine doesn't run them
with TR semantics (next section).

## 3. BDI agents: plan libraries, declarative goals, fail-and-retry

- Rao & Georgeff's BDI model and its systems (PRS, dMARS, JACK, Jason)
  *(unverified in detail)*.
- Winikoff, Padgham, Harland & Thangarajah, *Declarative & Procedural
  Goals in Intelligent Agent Systems*, KR 2002
  ([pdf](https://winikoff.github.io/pdf/kr2002.pdf)).
- Sardina & Padgham, *Goals in the Context of BDI Plan Failure and
  Planning*, AAMAS 2007
  ([pdf](https://www.ifaamas.org/Proceedings/aamas07/html/pdf/AAMAS07_0225_c59840c23cef3f87560501b929858053.pdf)).
- Sardina & Padgham, *A BDI agent programming language with failure
  handling, declarative goals, and planning*, JAAMAS 23(1), 2011
  ([dblp](https://dblp.org/rec/journals/aamas/SardinaP11)).

A BDI agent has a **plan library**. Each plan is a rule `e : ψ ← P`: for
event-goal *e*, *applicable* when its context condition ψ holds, with body
*P*. A body is actions, belief tests, and subgoals `!e'`. When a goal
arises, the agent collects its *relevant* plans and runs an *applicable*
one. If that plan fails, it tries another applicable one from the rest
(**fail-and-retry**). When none is left, the failure goes up to the goal
that posted the subgoal.

Winikoff et al. give a goal both a declarative and a procedural side:
`Goal(s, P, f)`, with success condition *s*, plans *P*, and failure
condition *f*. A rational agent's goals are:
- **persistent:** dropped only when they succeed or with good reason;
- **unachieved:** "A goal to achieve s should be dropped when s is true.
  … if we are in the middle of executing a plan P in order to bring about
  s and s becomes true, then the goal is dropped (with success) and the
  plan P aborted. A corollary is that a goal to achieve s where s already
  holds should trivially succeed without doing anything";
- **possible:** dropped with failure when *f* holds;
- **consistent** and **known**.

They decouple plan success from goal success: a plan that succeeds
without bringing about *s* leaves the goal standing (their cat's plan
reaches the table and finds the food gone). They also decouple plan
failure from goal failure.

Sardina & Padgham (CAN, CANPlan, CANPlan2) formalise this. Their 2007
paper adds that an agent shouldn't fanatically re-pursue a blocked
subgoal when the motivating goal has another way. Their example: the
shop is out of soda, so drop "buy soda" and buy a bottle of water. They
also adopt a goal only if some relevant plan exists for it. They note
how close BDI plan libraries are to HTN methods (§4).

**For us:** the engine is this, nearly to the letter:
- a goal's `done` is *s*;
- a method's `pre` is ψ;
- `#Achieve` posts a subgoal and passes over one whose `done` holds (the
  corollary of *unachieved*);
- the goal's `failed` mask is fail-and-retry;
- "nothing I know of will do: impossible for now" fails the way that
  posted the subgoal.

The fault is in the content. A plan library's plans for a goal are
alternative whole ways, each a body with subgoals. Ours are TR rungs,
each readying a higher one, and fail-and-retry over rungs falls to a rung
that serves the way that just failed. Two properties are partly missing
in the engine:
- *unachieved* is checked only for the innermost intention, not for the
  goals beneath it;
- there is no failure condition *f* apart from "no way left".

## 4. HTN planning (SHOP2 and games)

In hierarchical task network planning, a compound task has **methods**.
Each method is a precondition and an ordered list of subtasks, and a
task's methods are alternative decompositions of it. A planner searches
the decompositions ahead of time. A game HTN (Killzone 2, Transformers;
Humphreys, *Exploring HTN Planners through Example*, Game AI Pro)
*(unverified)* plans to primitive tasks and replans when the world
departs from the plan. Practitioners chose HTN over GOAP (§6) for
authored control and lower cost. A Charles University study found GOAP
agents slightly better but HTN easier to build
([pdf](https://artemis.ms.mff.cuni.cz/main/papers/2013-pddl_vs_htn.pdf)).

**For us:** AGENCY.md already calls methods "HTN-style", without the
search. HTN methods are alternatives over a task, never steps of one
another, which is the rule our ladders break.

## 5. Behaviour trees and PPA back-chaining

Colledanchise & Ögren, *Behavior Trees in Robotics and AI: An
Introduction*, 2018 ([arXiv 1709.00084](https://arxiv.org/abs/1709.00084)),
and their 2019 back-chaining paper.

A behaviour tree is ticked from its root at every step. A *fallback*
node tries its children until one doesn't fail, and a *sequence* runs its
children until one does. The **postcondition–precondition–action (PPA)**
pattern builds a tree from a goal. For a condition C, the tree is
`Fallback[C?, Sequence[pre₁, …, preₙ, action achieving C]]`, with one
such sequence for each action that achieves C. Each unmet precondition
is expanded the same way, with its own PPA subtree.

The tree is re-ticked from the root, so a condition already met is passed
over every tick: the agent is as reactive as a TR program. Failure falls
back only among the actions that achieve the *same* condition. The book
shows that BTs generalise TR programs and decision trees, and that
back-chained trees converge under stated conditions (see also
[arXiv 2308.08994](https://arxiv.org/abs/2308.08994)).

**For us:** PPA is the shape the redesign needs, and the engine already
runs it:
- a goal's `done` is the postcondition check;
- a goal's methods are the fallback;
- a method's `#Achieve` steps are the expanded preconditions;
- its last step is the action.

The engine decides again at each decision and skips subgoals already
done, which is the re-tick. So whole ways with subgoals keep the
ladders' reactivity (resuming mid-errand) and lose their fall-through.

## 6. Goal-oriented action planning (Orkin, F.E.A.R., 2005–06) *(unverified)*

In goal-oriented action planning (GOAP), actions declare preconditions
and effects over a small world state, and an A* search chains backward
from the goal to find a sequence. Nobody authors decompositions, and
designers add actions and goals. The costs are a search on every replan,
and that "how this culture does this" can't be authored except through
costs.

**For us:** the search would do our decomposition for us, at a cost per
decision across a village of agents (PERFORMANCE.md), and it would take
away the authored ways that topics are written in. Not chosen. If it is
ever wanted, PPA back-chaining (§5) is its bounded form, done at load
time over authored methods.

## 7. BDI in social simulation

- Adam & Gaudou, *BDI agents in social simulations: a survey*, KER 31(3),
  2016 ([HAL](https://hal.archives-ouvertes.fr/hal-01363962)).
- Caillou, Gaudou, Grignard, Truong & Taillandier, *A simple-to-use BDI
  architecture for agent-based modeling and simulation*, SSC 2015/2017
  ([repository](https://publications.ut-capitole.fr/id/eprint/28740/)).
- Taillandier et al., *A BDI agent architecture for the GAMA modeling and
  simulation platform*, MABS 2016.

The survey argues for BDI agents in social simulation: folk-psychological
concepts make the model legible to modellers and users. The GAMA
architecture names "complex plans with sub-objectives" (sub-intentions)
as the gap it fills for modellers, and it keeps the cost low enough for
many agents.

**For us:** this is the closest field to ours, and it settled on plan
libraries with sub-intentions, the structure proposed here.

## 8. Maintenance goals

- Duff, Harland & Thangarajah, *On Proactivity and Maintenance Goals*,
  AAMAS 2006 ([record](https://researchr.org/publication/DuffHT06)).
- *Maintenance Goals in Intelligent Agents*, Computational Intelligence
  30(1), 2014.

These distinguish **achievement goals** from **maintenance goals** (keep
C true). A maintenance goal is handled reactively (act once C fails) or
proactively (act when C is predicted to fail).

**For us:** "keep the grain stocked" and "keep the woodpile stocked" are
maintenance goals. Today they are achievement goals re-adopted by a
generator (a duty, a market day). Nothing here needs that to change, but
it is the literature to read when it does.

## 9. Games in practice *(unverified)*

- **The Sims:** objects *advertise* the needs they satisfy, and an agent
  picks the interaction with the best advertised gain, discounted by
  distance. Each interaction is then a short script. This is relevant to
  weighing whole ways against each other: the opportunity cost that
  lab/PLAN.md "A coin's worth" defers.
- **RimWorld:** a *think tree* picks a job, and a job driver runs it as a
  sequence of *toils*, each with fail conditions. A failed toil ends the
  whole job, and the think tree chooses afresh. Failure never drops to a
  lower step of the same job.

## Summary

| Approach | Ways of a goal are | Failure goes | Reactive |
| --- | --- | --- | --- |
| TR programs | rungs: each readies a higher | nowhere: the rung runs again | yes |
| BDI (CAN) | alternative whole plans; needs are subgoals | to another plan, then up | between steps |
| HTN | alternative decompositions | to another method, then up | replans |
| BT, PPA | fallback over actions achieving the condition; needs expanded | to a sibling achieving the same condition, then up | every tick |
| GOAP | found by search | replan | replans |
| The lab today | mixed: rungs, run with fail-and-retry | to any lower rung | every decision |

All the hierarchical approaches agree. A goal's ways are alternatives that
each achieve it. What a way needs is a subgoal, passed over while it
holds. A failed way gives way to another *way*, never to a step of
itself.
