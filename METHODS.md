# Methods: whole ways and subgoals

## Status and scope

Being built (lab/PLAN.md). Built: decisions 5 and 6, the market's buying
rewritten (decisions 1–4, "Built so far" below). This document extends
[AGENCY.md](AGENCY.md) §5 (methods) and generalises its decision 34 ("a
method is taken for what it does, not because it can be done"). It
covers how a goal's methods are written and run so that an agent doesn't
do what a way needs when the need is met already, and so that a failed
way leads to another way. The prior work it rests on is in
[research/scripts-and-plans.md](research/scripts-and-plans.md).

Not covered: how whole ways are weighed against each other (opportunity
cost: lab/PLAN.md, "A coin's worth"), maintenance goals as their own kind
(research §8), and search over methods (research §6, not chosen).

## The problem

A woodcutter with an axe in hand, and no tree in sight, took up a second
axe. Both hands full, it ate nothing for days. A buyer holding coins whose
buy failed went home and took the coffer's coins too. Decision 34 fixed
the axe and the bow one at a time. The cause is general.

**Most of the lab's goals with several methods are ladders.** Each lower
method exists to ready a higher one. Buying grain is eight methods, by
rank:

| Rank | Method | Precondition | Readies |
| --- | --- | --- | --- |
| 1 | bring it home | grain in hand | the goal |
| 2 | unpack it | by the supply, grain in the pack | 1 |
| 3 | put down what it carries | both hands full | 4, 6 |
| 4 | buy grain | coins in hand | 1, 5 |
| 5 | carry it home | grain in the pack | 2 |
| 6 | fetch the coins | a hand free, coins believed in the coffer | 4 |
| 7 | look in the coffer | — | 6 |
| 8 | go to the stalls | — | 4 (a price known) |

This is a teleo-reactive program (research §2). Written that way, it works
while every action succeeds, because the engine chooses afresh at each
decision and the highest method whose precondition holds moves the agent
up the ladder.

**The engine runs it as a plan library** (research §3). A failed method
is marked in the intention's `failed` mask, and the best remaining method
whose precondition holds is followed
(`src/agency_agency.odin`, `agency_decide`). Under those semantics every
rung is a way to the goal. So when "buy grain" fails (too dear, nobody
minding the stall), the agent falls to a rung that exists only to set up
the buy that just failed: it fetches more coins, or looks in the coffer.
The ladder was written as a teleo-reactive program and is run with BDI
fail-and-retry, and the two semantics disagree exactly on failure.

## Measurements

A three-week village run, logging every one of the 21 agents' thoughts
(`lab run village --days 21 --log …`, 70,299 trace lines, 4 FAILs, the
known timing ones: VILLAGE.md, three weeks). The tables below are the
output of [research/measure-fallthrough.sh](research/measure-fallthrough.sh)
over that trace.

**Buying:**

| After a failed buy | Then | Times | Right? |
| --- | --- | --- | --- |
| it knows no stall selling it | go to the stalls | 156 | yes: finding out |
| nobody minds the stall | go to the stalls | 16 | yes |
| it knows no stall selling it | look in the coffer | 12 | no: a rung of the failed buy |
| it knows no stall selling it | carry it home | 7 | yes: a lot already bought |
| nobody minds the stall | look in the coffer | 6 | no |
| it knows no stall selling it | fetch the coins | 2 | no: coins already in hand |
| no hand free, no room in the pack | look in the coffer | 1 | no |
| nobody minds the stall | carry it home | 1 | yes |

That's 21 of 201 failed buys falling to a rung of the buy that failed. 22
coin fetches in three weeks, and 2 were a second fetch in the same buying
with coins already in hand (agent 84, day 7; agent 20, day 11). Most of
these happen at home, beside the coffer, so they cost little time today.
They will cost more as soon as a buy can fail at the market for a reason
that a coin fetch can't mend.

**"Knows no stall selling it"** is the commonest failure, and it isn't a
failure of buying at all. The agent hasn't read a price yet. It is a
precondition unknown, which the engine already has a mechanism for
(`onUnknown`, a residual subgoal: AGENCY.md §5).

**Stocking the woodpile** (also a ladder: stack ← gather ← split ← buck ←
fell ← look for trees):
- 13 times a split that could not be done ("you don't know of a
  destination in reach") went on to *cut another length off*, more logs
  for the split that had just failed;
- 7 times a fell that could not be done went on to cut a length off;
- 4 times a cut went on to fell a tree.

Why those acts can't be done (a target believed in reach that isn't) is a
separate question. What follows them is this one.

**The engine, read against the research:**

| Property (research §3) | The engine | Where |
| --- | --- | --- |
| A goal already achieved succeeds without doing anything | yes: `#Achieve` passes over a subgoal whose `done` holds | `agency_follow` |
| A goal achieved mid-way is dropped | only the innermost intention's `done` is checked; a goal beneath a subgoal isn't, until the subgoal ends | `agency_decide` |
| Plan success isn't goal success | yes: after a method's act, the method is chosen again (or another), until `done` holds | `agency_decide` |
| Plan failure isn't goal failure: another plan is tried | yes: the `failed` mask | `agency_fail` |
| A subgoal impossible fails the way that posted it | yes: "has failed: it needed …" | `agency_decide` |
| A failure condition apart from "no way left" | no: impossible for now only when no method holds | — |
| A goal adopted only with a relevant method | yes in effect: a subgoal with no `done` fails the way | `agency_follow` |

The engine is close to the research's goal semantics (CAN, research §3).
The fault is mostly in how the content is written, plus one engine gap
(a goal achieved beneath a subgoal).

## Proposed decisions

1. **A goal's methods are whole ways.** Each method is an alternative
   way to the goal, and its last step brings about the goal's `done`
   (put the grain in the supply; stack the wood). No method exists only
   to ready another method of the same goal. A failed method gives way
   to another *way*, or the goal is impossible for now. This generalises
   AGENCY.md decision 34, and it is the plan-library rule of BDI and HTN
   and the fallback of a PPA behaviour tree (research §3–5).
2. **What a way needs is a subgoal.** Hands free, coins in hand, the
   grain in hand, a price known, by the supply: each is a goal with its
   own `done` and its own whole ways, posted by `#Achieve`. A subgoal
   whose `done` holds is passed over at every decision, so the agent
   resumes mid-errand as a ladder did (research §5: re-ticking a tree).
   A ladder's rungs become the ways of the subgoals they served: "fetch
   the coins" is a way of *coins in hand*, not of *buy grain*.
3. **A subgoal says how much, not just whether.** *Coins in hand* is done
   by any coins, and *coins enough* by enough for the lot it means to buy
   at the price it knows. Topping up is then a way of *coins enough*, and
   holding some coins never sends an agent for more it doesn't need.
   Comparing a held count against a believed price needs a condition the
   engine works out, as it does `#Reached` and `#Did` (content/agency.tri).
4. **What isn't known is found out first.** A way that needs a fact the
   agent lacks (a stall's price) says so in its precondition, and the
   unknown raises a find-out subgoal (`onUnknown`, AGENCY.md §5), instead
   of failing at the act. "It knows no stall selling grain" stops being
   a failure. Searching (look in the coffer, look for seed) is a way of
   a *known* subgoal, not a rung.
5. **A goal achieved is dropped at any depth.** At a decision, a goal's
   `done` is checked beneath the subgoals posted for it too. When it
   holds, it and every subgoal above it are dropped with success. This is
   the research's *unachieved* property: someone else stocks the larder
   while the buyer is fetching coins, so the coins go back. The stack is
   at most `BG_MAX_INTENTIONS` (8) deep.
6. **Fall-through is measured.** The run counts, for each goal, a way
   followed in the same intention after another failed, and prints the
   pairs (goal, failed way → next way) at the end, as this document's
   measurement did by hand. A change to content that adds a ladder shows
   up there.

## The work

### Engine (src/agency_agency.odin)

1. **Goals achieved beneath a subgoal** (decision 5): in `agency_decide`,
   before following the innermost intention, check `done` for each
   intention beneath it, outermost first. The first that holds is
   settled with success, and the intentions above it are dropped
   (settled, not failed). Cost: one condition per intention per
   deliberation. Measure it in `lab bench crowd` (PERFORMANCE.md).
2. **A condition for enough coins** (decision 3): an engine-evaluated
   condition, beside `#Reached` and `#Did`, holding when the coins in the
   agent's hands (and pack) come to the price of a lot of the goods at
   the cheapest fresh price it believes (AGENCY.md decision 30: a price
   lapses).
   - Open: whether it is market-specific (`#Affords & { what, units }`)
     or general (a slot's field compared with a believed price).
3. **The purchase's failures** (decision 4): `agency_purchase` keeps
   "dearer than it holds it worth", "nobody minds the stall", "it hasn't
   the coins", and "no hand free nor room". "It knows no stall selling
   it" becomes the unknown of a precondition, so it is never a failure.
   "It has enough coming" stays: the way is done, not failed.
4. **Fall-through counted** (decision 6): in `agency_fail` and the
   choice after it, record (goal, failed method, next method) per run,
   and print them under `--counters`.

### Content, in order

Each topic is rewritten to decisions 1–4, its header's cut points
updated, and the three-week run compared before and after (FAILs, the
fall-through table, the stock levels). Order is by measured harm, then
by how often the topic is run.

1. **market/ buying** (24 methods across three goals; the measured
   fall-through). Sketch, for grain:

   ```
   grain_stocked                       done: 20 kg of grain in the supply
     stock_it:      [#Achieve grain_in_hand, #Achieve by_the_supply,
                     put_in grain → supply]

   grain_in_hand                       done: grain held
     unpack_it:     pre: grain in its pack
                    [#Achieve by_the_supply, take from the pack]
     buy_it:        [#Achieve coins_in_hand, #Achieve price_known,
                     #Achieve coins_enough, #Purchase]

   coins_in_hand                       done: coins held
     fetch_coins:   [#Achieve hand_free, take the purse]   (the coffer: onUnknown → look in it)
   price_known                         done: a fresh price for grain believed
     read_prices:   go round the stalls
   coins_enough                        done: the coins for a lot (decision 3)
     top_up:        [#Achieve hand_free, take the purse]
   ```

   Unpacking goes before buying, so a lot already in the pack is taken
   home before another is bought.
   - `hand_free` (put down a burden: goods, a log, an axe, a bow, never
     coins) and `by_the_supply` are shared by carrying/, firewood/ and
     hunting/. They belong in carrying/.
   - The three goods share these through `let` templates as now.
2. **firewood/**: `woodpile_stocked` becomes stack it ← wood in hand ←
   (unpack | gather ← split wood near ← split ← a log near ← buck ← a
   trunk near ← fell ← a tree near ← look for trees). Each "near"
   subgoal has the ways that make one and the way that finds one. With
   decision 1, the 13 split-could-not → cut-another-length fall-throughs
   become a failed *split* way, and the next way is the next *log*.
3. **hunting/**: `game_hunted` (8 methods: meat home ← unpack ← butcher ←
   pick up the hide ← carry home ← shoot ← look for game) is the same
   shape. Its subgoals for a bow in hand, hidden and watched exist
   already.
4. **farming/** `plot_tended` (6), **carrying/** `pack_returned` (7),
   **market/** selling (`goods_set_out` 6, `unsold_home` 4,
   `takings_home` 3).
5. **cooking/** `have_a_meal` (3), **firewood/** `stove_stoked` (3),
   **nails/** `have_nails` (3), **farming/** `seed_in_hand` (2),
   **foraging/** `foraged` (2), **machines/** `mend_pump` (2). These are
   short ladders, mostly a fetch and a find-out, and decision 4 covers
   most of them.

Already whole ways, left as they are:
- `eat_when_hungry`: eat what's in hand, cook and eat, eat it raw, forage
  and eat;
- `eat_supper`, `food_along`, `get_money`, `repair_pump`, `tighten_nut`,
  `stove_lit`, `pack_carried`.

`cook_and_eat` and `forage_and_eat` are the model for the rest: a whole
way, with its needs as subgoals.

### Docs

- AGENCY.md: a decision recording decisions 1–5 here (building on
  decision 34), and rows for teleo-reactive programs, CAN and PPA
  behaviour trees in "What we take from other approaches".
- §5: "its alternatives, in order" becomes "the goal's other methods are
  its alternatives".
- GLOSSARY.md: **Ladder** (added with this proposal). **Method** says
  "a whole way".
- content/README.md: the authoring rule, with the grain sketch.
- lab/PLAN.md: "Coins fetched with coins in hand" folds into this.

## How it's checked

- `lab test` gains a test for each engine change:
  - a goal beneath a subgoal achieved meanwhile is dropped, with its
    subgoal;
  - the enough-coins condition at, under and over a lot's price, and with
    no fresh price;
  - a failed way's goal takes its next whole way, not a subgoal's way.
- The three-week run, before and after each content step:
  - no FAIL that wasn't there;
  - the fall-through table (decision 6) has no pair where the next way
    serves the failed one;
  - nobody takes a second tool or a second purse (the nightly "holds"
    lines).
- `ci/scenario-hashes.txt` regenerated, Linux checked identical.
- `lab bench crowd` before and after the engine's decision-5 check.

## Built so far

- **Decision 5** (`agency_decide`): a goal beneath, achieved meanwhile, is
  done, and its subgoals go with it ("… is done meanwhile: giving up …").
  Only the chain of subgoals counts, not a goal suspended beneath one
  that won. Test: `goal_done_beneath`.
  - It found a `done` too weak at once: "take something to eat" held
    with any food in hand, so the grain taken up to cook ended it, and the
    meal was given up half made.
  - Its `done` is now a meal in hand. Raw food taken along is its last
    resort, a method that **ends** its goal (`ends: true`, a `sequence`
    method's steps all done): the research's procedural goal.
- **Decision 6** (`--counters`): fall-through pairs, by goal.
- **Decisions 1–4, the market's buying** (content/market/):
  - Bringing goods in hand home comes first. Else one whole way: enough
    coming, then in hand, then put in.
  - Enough coming is a lot bought: the coins in hand, a price known, the
    coins for the lot, a hand free, the purchase.
  - `#Buying` is the condition the code works out (`agency_buying`, from
    the purchase's own lot and prices):
    - "coming" holds with a lot of it in hand, as much as it carries home
      at a time;
    - "affords" holds with any coins while no price is known;
    - with no more coins in the coffer (looked into on this errand) the
      coins in hand will do.
  - Three things the old ladder did by itself had to be said:
    - "room" is a free hand: the seller hands over only to a free hand;
    - a subgoal searches as its errand does, passing over stalls and
      coffers looked into since the outermost goal was adopted. Adopted
      afresh, a price subgoal re-read the same board 822 times;
    - a coffer seen empty before the errand began is looked into again.

Three weeks of the village after it:
- buying's fall-through is gone (none; 21 of 201 failed buys before);
- the market checks pass;
- 8 FAILs, against 4, explained below.

**What the working market showed.** The farmers bought 5 kg of venison on
day 7, which the old ladder never managed ("knows no stall selling
venison"). Rationing counts all food at home, so they stopped rationing.
But they cooked grain by habit, and the meat spoiled on day 10: the larder
was empty by day 11, against day 14 before. Two fixes:
- **What keeps least is taken first.** The order `"keeps"` (agency.tri)
  ranks a food by the `keepsFor` of its kind, a stack's by its unit. That
  meat keeps days and grain for good is knowledge of the kind; when this
  meat will spoil stays unseen. Taking food to cook, or along, is ordered
  `["own", "keeps", "habit", "near"]`.
- **What lies in something its own is its own.** The `"own"` order now
  counts a thing in a container the agent believes its own, as `#AtHome`
  already did. Meat bought has no ownership claim, so "own" put the
  household's grain ahead of it, and "keeps" never got a say.

The hunters then cook their own venison before it spoils, and take less
grain. So the larders check counts meat taken from a larder too, a 500 g
unit a portion: meat that spoils there is as heavy spoiled food, so it
isn't counted as taken.

After: the farmers' larder lasts to the harvest (3 kg at the least, day
14), and the larders check passes. 6 FAILs over three weeks, against 4.
They are timing ones in the lean days 12–16: a household rationing, hungry,
asking about instead of at work (lab/PLAN.md, "Asking in the village").

**Firewood and the hunt** (content/firewood/, content/hunting/), rewritten
the same way:
- Stocking the woodpile: firewood in hand is stacked; else firewood got
  into hand, then stacked. Firewood into hand comes out of the pack by the
  woodpile, is gathered, is split and then gathered, or the pack is carried
  home. Split firewood comes from a log split, or a log cut and split; a
  log from a trunk, or a tree felled and cut; a trunk from a tree felled,
  or the woods looked into.
- Each "one lying about" (`wood_split`, `log_cut`, `trunk_felled`) is a
  goal whose `done` binds the nearest. Goals take an `order` now (moved to
  `#Intent`).
- Gathering needs a hand free (`hand_for_wood`): the axe is put down by
  the wood, not the meal carried to eat at work, and taken up again to
  split. The ladder had never gathered with no hand free; written as a
  way, the gather was tried and refused over and over.
- The hunt: meat home, a hide home, a hide unpacked; else meat got into
  hand (`meat_from_the_hunt`), then put in. Meat into hand comes out of
  the pack by the larder, is butchered, the hide picked up, the pack
  carried home, or game brought down (`game_down`, the nearest carcass)
  and butchered.
- The chains are up to six goals deep, so `BG_MAX_INTENTIONS` is 16: a
  meal on top of a deep chain needs four more.
- Wandering (#Wander) fell back to a ring search that began past the
  radius, so near woodland the draws had missed was never found. One
  failed wander gave up the whole hunt, and the hunting week brought home
  half its venison. The ring now begins beside the agent.

Three weeks after: 3 FAILs, against 4 at the start. One is new: on day 19,
three sellers left their takings, 127 coins, on their stalls. Each first
cleared its unsold goods from the stall, then found "take the takings
home" impossible at once. The takings are a ladder still (content step 4).

Not yet: content step 4 (farming, carrying, the market's selling) and
step 5.

## Open questions

1. **Depth.** The woodpile's chain is about six goals deep, under the
   limit of eight, but a duty's goal sits beneath it already. Should
   `BG_MAX_INTENTIONS` grow? Or should the "near" subgoals of one chain
   be one goal with several ways?
2. **The enough-coins condition's shape** (work item 2): market-specific,
   or a general comparison of a held quantity with a believed one.
3. **A failure condition.** Should a goal declare when it is hopeless
   (research §3, *possible*), apart from no way holding? For example,
   the market closed for a buyer, or no trees left in the woods.
4. **Load-time back-chaining.** Methods could declare their effects and
   the loader could check decision 1: warn when a method's effect is only
   a sibling's precondition. That is the bounded, authored form of GOAP
   (research §6). Worth it once the content is rewritten, as a lint.
