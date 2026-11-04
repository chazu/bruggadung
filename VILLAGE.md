# The village

## Status and scope

A design for the lab's first scenario of daily life: a dozen people in four
households, living for weeks in a village. They farm, gather firewood, hunt
and meet at a market. The watcher shows it (TESSERA.md), and `lab run
village` checks it, as the other scenarios are checked.

This document is a proposal, built a slice at a time: slices 1 (hunger
over weeks), 2 (looks in content), 3 (the village and its homes), 4
(cooking and the larder) and 5 (firewood) are built. Each slice below is a ticket: slice n is GitHub issue #n
(label `village`). A slice moves into `lab/PLAN.md` when it is built.

It is the first scenario that runs for weeks, not minutes. That forces two
things the lab put off:

- **Hunger on the scale of weeks.** Going without used to start harming
  the body 4.5 h after a meal (`lab/content/hunger/body.tri`). The user asked
  for hunger kept apart from finding, preparing and eating food, and for
  starvation over weeks that weakens strength and cognition (slice 1).
- **Things that change on their own over days**: crops ripening, meat
  spoiling. Both are read lazily (DETAIL_REGIMES.md decision 4), so nothing
  steps them between boundaries.

**Out of scope:**
- Institutions: no law, permits or tolls (INSTITUTIONS.md).
- Seasons, weather, births and the regrowing of woods.
- Hunger and food below reduced detail. Abstract detail stays open, as the
  user asked: the whole village runs at full detail.

## Decisions proposed

1. **A dozen people, all at full detail.** Four households of two to four
   people each. The reality bubble has no anchor, so everyone runs at full
   detail. Most of a day is long activities (a night's sleep, a shift in
   the plot), so boundaries stay few; slice 10 measures it.
2. **Hunger has two parts, and food is something else** (slice 1).
   - **Satiety** empties over hours and is what is felt: the need, its
     bands and the goal to eat. An empty stomach doesn't harm.
   - **Reserves** fall only while satiety is empty, run out over weeks,
     and refill slowly once the agent eats. Weakness comes from reserves,
     through curves in content: attention first, then the pace of work,
     then perception and grip. Injury comes only at the end.
   - Eating proposes **nourish by N**, where N is the food's
     `nourishment`. The body applies it. How the food was found, cooked
     or bought is no business of the body's.
   - Hunger becomes a component of its own (`#Hungry`) that only
     biological bodies carry.
   - Going without stops raising fatigue, so a nap no longer cures
     starving.
3. **A home is a building, a household is people.** A house is terrain:
   walls, a door, a floor, a room with its own air. Its things are a stove,
   a bed for each person, a larder and a woodpile, each owned by its
   household (ownership claims, things.tri). A household is its members'
   kin bonds (bonds.tri). No new entity is needed until abstract detail
   needs a **place** (DETAIL_REGIMES.md) to carry a larder's level.
   - Built: beds and larders just alike are told apart by where they are
     (KNOWLEDGE.md decision 18), and each of a household's people owns its
     stove, larder, grain and woodpile, knows them as its own, and takes
     from its own first. Before it, an agent passing a neighbour's
     door saw a bed like its own and believed its own had moved there, and
     the Brooks took the Hunts' larder for their own and ate from it; a
     colour each (a bed's blanket, a larder's paint) held it off until
     then, and is gone.
4. **A day's shape is a routine of commitments.** Each agent has
   commitments that recur every day (AGENCY.md §8): sleep at home through
   the night, and its work in the day's hours. Its needs (hunger, cold,
   tiredness) are weighed against them as any goal is. An agent that skips
   breakfast to finish a harvest is behaving as the design means it to.
   The lab already undertakes a goal over a window, every period
   (`agency_undertake_goal_from_until_source_every`), so the routine is
   content: what the commitments are and when.
   - Built (content/home/home.tri): to work 07:00–15:00, home by one's bed
     15:00–22:00, a night's sleep in one's own bed from 22:00. Each is
     undertaken with its slots bound (`agency_undertake_every_with`): the
     agent's bed, its household's **worksite** (a scarecrow in the plot, a
     chopping block, a hunting blind). Sight reaches four tiles, so each
     villager is shown its worksite and its home before the first morning;
     the rest of the way it finds as it walks.
   - Built (slice 4): work and home are **kept** goals (agency.tri): a
     villager who goes home to eat in its working hours, or to the stove
     in the evening, goes back. A kept goal has no deadline to rise
     toward, so its urgency is nil: it is worth its duty, all through.
   - Built (slice 4): something to eat at work, 06:00–07:00, and supper,
     18:00–21:00, are commitments too. A villager's stomach empties over
     12 hours (`village.tri`'s `person`), so hunger presses again some five
     hours after a meal: breakfast, the meal it carries, a meal on coming
     home, supper, and a night's sleep through. Over 8 hours it was five
     meals a day, and it woke at night to eat.
5. **Crops ripen in closed form** (slice 6). A crop is an entity on a plot
   tile, sown at a time. Its growth is a function of time since sowing,
   read when needed, with one wake when it ripens. Nothing steps it.
   Watering and weeds are left out.
6. **Firewood is the stove's fuel, end to end** (slice 5). A tree is felled
   into a trunk, the trunk sawn into logs (sawing.tri's `saw_through`), and
   each log split into firewood: a stack. Firewood carried home goes on
   the woodpile, and stoking puts it in the stove's fuel (heat.tri's
   `#FuelContainer`). The atmosphere domain burns it and warms the room,
   cold is felt, and `get_warm` lights the stove. All of that after
   stoking exists already.
   - Built (content/firewood/): the woodcutters work with an axe alone:
     it fells, bucks a trunk a length at a time (`buck`, with sawing's
     effect) and splits, so a hand is free for the firewood. Sawing with
     a saw in the other hand meant putting it down and taking it up, which
     ran in circles. Their work is a kept commitment to stock their
     woodpile, past more than a day's work; with no tree in sight they go
     into the woods to find one (an `#Explore` step, agency.tri).
   - Built: every household stokes its stove for the night (19:00–21:00)
     and before lighting it to cook if it is empty, from its woodpile. The
     village runs the atmosphere domain, so a lit stove burns its fuel. The
     other households' woodpiles start stocked: buying firewood is the
     market's (slice 9). Cold isn't felt yet: villagers aren't thermal
     bodies, so stoking for the night is a commitment, not a want.
7. **Animals are agents with few goals, and can die** (slice 7). A deer or
   a hare is an `#Agent` with no hands and a short list of goals: wander
   its range, and keep away from people it perceives. Hunting is
   stalking, then a blow or a shot (harm.tri). An animal whose injury
   reaches 100 dies: its entity becomes a **carcass**, a body to butcher
   into meat and a hide. Death was left for a scenario of its own (AGENCY.md
   d17); this is the scenario, for animals. Whether people can die too is
   an open question.
8. **Food spoils, in closed form** (slice 8). Meat and cooked food are
   **perishable**: made at a time, good for so long, then spoiled. A
   spoiled thing still exists, but it isn't food any more. Salting and
   smoking are left out.
9. **Selling at the market is a deal, struck at a stall** (slice 9).
   - Money becomes coins: a stack of a `coin` unit (money is cloth today).
   - On market days a seller sets out a **stall** on the green, with a
     **posted price**: a written record (talk.tri), so whoever reads it
     knows it without being told. A seller prices goods by what it values
     them at (`#Valuing`).
   - A buyer who values the goods above the coins asks for them and pays,
     and the seller hands them over. Haggling is left out.
   - A **sale** is a deal (AGENCY.md d15) of goods for coins, made on the
     spot. It is never "trade", which is the lab's word for a craft
     (`Agent.trade`).
10. **Looks come from content** (TESSERA.md slice 3; slice 2 below). Each
    blueprint names its look (`look: "tree.oak"`), resolved through the
    type hierarchy, and the watcher's theme gives each look a glyph and
    colours. A village has too many kinds of thing for the stopgap
    (blueprint names, first letters) to read well.

## The village

A map of 160 × 100 tiles on one level (`content/village/maps/`, built),
from north to south:

- **The woods**, in the north and east: woodland ground, and (with slices
  5 and 7) about 200 trees, oak and birch, with deer and hares.
- **Four houses round the green**, two on either side of the path east,
  each one room with a door onto the path, a stove, beds, a larder, and a
  woodpile by the door.
- **The green**, where the paths cross, where the market is to be held
  (slice 9), with a well later (water.tri's cistern and tap).
- **The plots**, in the south: tilled ground, a few hundred tiles to each
  farming household.
- **Paths** joining the plots, the green and the woods.

The households:

| Household | People | Work | Sells |
| --- | --- | --- | --- |
| The Ashes | 3: two adults, a grown son | farming: two plots of grain | grain |
| The Brooks | 4 | farming: grain, and turnips | grain, turnips |
| The Fells | 2 | woodcutting | firewood |
| The Hunts | 3 | hunting, and dressing hides | meat, hides |

Every household buys what it doesn't make. The farmers buy meat and
firewood, the woodcutters food, the hunters grain and firewood. The market
is what keeps a household with one kind of work fed and warm.

### A day

The day is the light domain's (daylight, dusk, night).

- **06:00, waking.** The night's commitment ends. A hungry agent cooks and
  eats from the larder. Cold, it stokes the stove.
- **07:00 to 15:00, work.** A farmer tends its plot, sowing or harvesting
  as the crop stands. A woodcutter fells, saws and splits. A hunter goes
  into the woods.
- **Midday.** Hunger rises enough to eat what the agent carries, or to go
  home for it.
- **Afternoon.** Firewood carried home, meat butchered, grain brought in.
  Every fourth day is market day: sellers stand at stalls on the green and
  the rest come to buy.
- **Evening.** Supper, the stove stoked, idle talk with whoever is near
  (talk.tri).
- **22:00 to 06:00, sleep.** At home, in the agent's own bed.

Over weeks: each crop ripens in about two weeks, woodpiles rise and fall,
the deer grow fewer and warier, and a household that sells too little goes
hungry, and slowly weaker.

## Content, by topic

Each topic is a directory (`lab/content/README.md`). Every file starts with
its cut points. The new and changed ones:

| Topic | Holds | New or changed |
| --- | --- | --- |
| `hunger/` | satiety and reserves (`body.tri`), the effect curves, eating, food's `nourishment` | changed (slice 1) |
| `cooking/` | the larder, cooking at a lit stove (raw food into a meal), meals | new (slice 4) |
| `perishing/` | perishable things: made at, keeps for, spoiled | new (slice 8) |
| `farming/` | plots, crops, sowing, ripening, harvesting, seed grain | new (slice 6) |
| `firewood/` | trees, felling, splitting, the woodpile, stoking | new (slice 5), with `sawing/` and `heat/` |
| `hunting/` | animals and their goals, stalking, dying, carcasses, butchering, hides | new (slice 7), with `harm/` |
| `market/` | coins, stalls, posted prices, the sale | new (slice 9), with `money/` and `talk/` |
| `home/` | houses, beds, sleeping at home, the day's commitments | new (slice 3), with `rest/` |
| `village/` | the map, the households and their blueprints, the scenario's cast | new (slice 3) |
| `terrain/` | grass, tilled soil, woodland ground, path, plank floor | changed (slice 3) |

Every file says the same at reduced detail as at full ("the same, decided on
the cadence's beat"), and at abstract "as reduced; open
(DETAIL_REGIMES.md)". Nothing in the village falls below full yet.

## Code

What content can't say yet:

- **Body fields** (slice 1): satiety and reserves read lazily, their
  wakes, and the effect curves applied where they act: the pace of work
  (`work_rate`), grip, the attention budget, and how precisely the agent
  perceives (knowledge's impairment). `effect_eat` stops doing the body's
  arithmetic (`fed = satiety + 50`); it proposes nourishment, and the bodies
  domain applies it.
- **Looks** (slice 2): the producer reads a blueprint's look. The watcher's
  theme comes from a content file of glyphs, not from code.
- **New effects**, each a small effect function: `cook`, `fell`, `split`,
  `stoke`, `sow`, `harvest`, `butcher`, `set_out` (a stall).
- **Ripening and spoiling** (slices 6, 8): accessors read lazily, as
  `satiety` and `lamp_oil` are, with a wake where a crossing changes what
  is perceived.
- **Death** (slice 7): a body whose injury reaches 100 is a carcass. The
  agency forgets its mind, and its activities end.
- **The scenario** (slice 10): `scenario_village.odin`, with its checks and
  hashes, run by `lab run village`, and watchable.

## Testing

`lab run village` runs a week of world time and checks:

- everyone ate every day and nobody's reserves fell below 50;
- every crop sown was harvested or is still growing;
- every stove had fuel each night;
- at least one sale was struck on each market day;
- no meat was eaten spoiled;
- the end state's hash (`ci/scenario-hashes.txt`).

Each slice brings its own tests too, as the lab's do. The `watcher` test
already proves that watching changes nothing.

## The plan, in slices

Each slice is one ticket, the issue of its number, and each can be watched
when it is built:

1. **Hunger over weeks**: satiety, reserves, nourishment, weakness
   (built).
2. **Looks in content** (TESSERA.md slice 3; built).
3. **The village and its homes**: the map, the households, beds, the day's
   commitments, sleeping at home (built).
4. **Cooking and the larder**: meals, eating at home (built).
5. **Firewood**: trees, felling, splitting, the woodpile, stoking (built).
6. **Farming**: plots, sowing, ripening, harvesting.
7. **Hunting**: animals, death, butchering.
8. **Perishing**: food that spoils.
9. **The market**: coins, stalls, posted prices, sales.
10. **A week in the village**: the scenario's checks and hashes in CI, and
    how fast it runs.
11. **The knowledge view in the watcher**: one agent's village as it
    remembers it (TESSERA.md slice 2's knowledge scenes).

Slice 1 comes first: everything after it depends on hunger working over
weeks. Slices 2 and 3 can be done alongside it. Slices 4 to 9 depend on
slice 3, and each can be done on its own, except that 8 wants 4 and 7 (it
spoils meals and meat). Slice 10 needs all of them, and 11 needs only 3.

## Terms

New, and entered in the glossary with this document:

| Term | Meaning |
| --- | --- |
| Satiety | How full the stomach is: hours of it, felt as hunger. (Built.) |
| Reserves | What the body has to draw on: falls while satiety is empty, over weeks; weakness comes from it. (Built.) |
| Nourishment | What a food gives satiety when eaten (`nourish by N`). (Built.) |
| Plot | Tilled ground a household farms. *Avoid:* field, which is a component's field. |
| Crop | A plant growing on a plot tile: sown at a time, ripe after its growth. |
| Perishable | Good for so long after it was made, then spoiled. |
| Carcass | What an animal's body is once it dies: something to butcher. |
| Stall | Where a seller sets out goods on market day, with its posted prices. |
| Posted price | A seller's written price for a kind of goods, read by buyers. |
| Sale | A deal of goods for coins, made on the spot. *Avoid:* trade, which is a craft. |
| Market day | Every fourth day, when stalls are set out on the green. |
| Household | The people of a home: kin bonds. Not a **place** (DETAIL_REGIMES.md's entity), until abstract detail needs one. |
| Worksite | What a household's day's work is done at: a scarecrow in a plot, a chopping block, a hunting blind. *Avoid:* workplace. (Built.) |
| Meal | Food that isn't raw: cooked, or never raw. (Built.) |
| Larder | A household's container of food, known from its neighbours' by where it is. (Built.) |
| Kept goal | An ongoing condition: a commitment to it arises again whenever it no longer holds, through its window. (Built.) |

## Open questions

- **Can people die?** Animals must (decision 7). With hunger over weeks
  and nothing violent among villagers, a person in the village shouldn't
  come close. The question is whether death is general from the start, or
  for animals only until a scenario needs it for people.
- **Where game comes from.** A few hunters over weeks would empty a fixed
  herd. Animals might come in from the woods' edge while there are fewer
  than so many, or the herd might breed. The first is a scenario input and
  simple. The second is a topic of its own.
- **Prices.** A posted price from the seller's values alone ignores what
  others ask. Whether sellers should read each other's stalls and follow is
  for after the first market works.
- **How weakness is felt.** Strength and cognition fall with reserves, but
  does the agent know it is weak? The interoceptive belief is hunger's.
  Weakness might be felt as fatigue, or as a need of its own.
- **Forgetting what was eaten.** Settled (KNOWLEDGE.md decision 19): a
  villager sees what it eats end, and forgets it; what it lost, it forgets
  once its memory of it fades. Its referents level off by the second day
  (360 across the village after three, from 790).
- **Cold.** Villagers aren't thermal bodies, so they don't feel the cold,
  rooms have no air of their own, and a stove only burns. Making people
  warm-blooded (the lodger's `#ThermalBody`) is a slice of its own, and
  would make stoking a want rather than a commitment.
- **What walking costs.** The woodcutters walk between the woods and home
  all day, a boundary a step. Walking to a place as one activity
  (AGENCY.md decision 20) halved the boundaries, to 18,000 in three days,
  and left a mind deciding only where a walk ends (PERFORMANCE.md).
  A boundary a step remains; carrying more at a time, or movement in
  closed form (PERFORMANCE.md, open questions), would cut it further.
- **Children.** The households are all adults. Children who eat but don't
  work would test the market harder.
