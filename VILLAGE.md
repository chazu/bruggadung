# The village

## Status and scope

A design for the lab's first scenario of daily life: a dozen people in four
households, living for weeks in a village. They farm, gather firewood, hunt
and meet at a market. The watcher shows it (TESSERA.md), and `lab run
village` checks it, as the other scenarios are checked.

This document is a proposal, built a slice at a time: slices 1 (hunger
over weeks), 2 (looks in content), 3 (the village and its homes), 4
(cooking and the larder), 5 (firewood), 6 (farming), 7 (hunting), 8
(perishing), 9 (the market) and 10 (a week in the village) are built, and
carrying (decision 11). Each slice below is a ticket: slice n is GitHub issue #n
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
   - Built, as a plot, not a tile (content/farming/): a crop on every tile
     was a thousand entities a farmer saw and kept referents of, and took
     the village from 7.7 s to 4 min 18 s for three days, nearly all of it
     perception. A farmer reasons about a plot as a whole: a plot is an
     **area** (things.tri's `#Area`), one entity covering its tiles, seen
     when any of them is in sight and in reach from on it or beside it, so
     an agent knows it by one referent. The crop is the plot's state:
     what it grows, how it **stands** (bare, sown, ripe), the tiles sown or
     reaped so far, and when its last row was sown. Sowing and harvesting
     go a row at a time; its growth runs from its last row, and it stands
     ripe once grown: the plot's one wake. Two farmers working a plot at
     once can't both count the same row: each sets its count expecting the
     value it read, and the second's group fails.
   - Each household's tilled block is two plots: the Ashes' two of grain,
     the Brooks' grain and turnips. Each farmer tends one of them (a kept
     commitment, bound to the plot and the larder), so it carries one kind
     of seed. Seed is kept back in the larder, enough for each farmer to
     take a plot's worth; what is left is put back.
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
   d17); this is the scenario, for animals.
   - Built (content/hunting/). **Death is any body's**: whoever's injury
     reaches 100 dies, its **remains** (its blueprint's: a carcass, or a
     person's corpse) made where it was and as heavy, what it held
     dropped, its mind let go (AGENCY.md decision 21). Nothing in the
     village hurts a person, so only animals die.
   - An animal keeps its **instinct**'s goals, each over its hours: from
     05:00 to 21:00 it roams, wandering to a spot of woodland within ten
     tiles and grazing there an hour; from 21:00 it is bedded down where
     it is, two hours at a time, till 05:00. One that sees a person in
     sight now holds it a #Danger (KNOWLEDGE.md decision 23) and
     **bolts**, a dozen tiles in three seconds, out of sight; seen again,
     it bolts again.
   - Built after the slice: an animal bolts, where it ran off at a walk
     four tiles, still in sight, and a hunter walked up and shot again,
     seven times in a minute. At the map's edge a flight ran straight into
     it and stayed: it slides along the edge now.
   - **The hunt is a bow, while stalking.** A hunter crouches, hiding
     (seen only from beside it), and shoots game within three tiles (an
     operation's `range`). A shot strikes by a seeded draw, the bow's
     **aim** (80 in a hundred from beside) less its spread (25 a tile
     further), in the hunter's `stalking`: a wound of 40, three to bring
     a deer down; struck or missed, the shot gives the hunter away. Its
     day is a kept goal, the larder holding two deer's worth of venison:
     it takes home meat it holds, butchers a carcass it knows of, stalks
     game it sees, and otherwise **lies in wait** a quarter-hour at a
     time between short walks. Game coming into sight while it waits is a
     #Game finding (its `stalking` skill), and taking the shot interrupts.
   - A carcass is butchered where it lies, a hand free: its meat (a deer,
     forty cuts of raw venison, 20 kg) in hand, its hide left lying.
   - **Game comes in at the woods' edge** (the game domain, a scenario
     input): while fewer than six deer or four hares live, one walks in
     from the east edge every quarter-day.
8. **Food spoils, in closed form** (slice 8). Meat and cooked food are
   **perishable**: made at a time, good for so long, then spoiled. A
   spoiled thing still exists, but it isn't food any more. Salting and
   smoking are left out.
   - Built (content/perishing/). Food that keeps for some time (meat,
     three days) spoils at `spoilsAt`, set as it is made; a meal keeps two
     days from when it is cooked, whatever it was made of; grain and
     turnips keep. The time is all there is: nothing steps it. The
     perishing domain stamps food made at the last boundary (it was made
     at t0), and its horizon is the next food to spoil, its one wake.
   - Spoiled, food **becomes spoiled food**, as death makes remains: a
     new thing, as heavy, where it was, its mass carved from the food,
     which ends. It is made of **rot**, not food, so no method finds it to
     eat, `eat` can't take it, and nobody values it as food. Whoever sees
     the larder sees the meat gone and spoiled food there.
   - A stack spoils whole. Put with a stack of its unit and merged, the
     two spoil when the older would have: fresh meat put in with old
     spoils with the old.
   - In the village's three days nothing spoils yet (the first venison is
     three days old the morning after the run ends); the check that no
     food past its time is food still is there for the week (slice 10).
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
   - Built (content/market/, content/money/coins.tri; AGENCY.md decision
     22, KNOWLEDGE.md decision 24). Every household keeps a hundred coins
     in a **coffer** by its larder. Market day is the third, then every
     fourth. From 09:00 to 12:00 a household's first person keeps its
     stall on the green: it sets out a lot of what its trade makes (a
     recipe of the trade: grain, venison, firewood), keeping enough back
     at home, posts its price on the stall's board, and minds the stall
     ten minutes at a time. Its second buys what the household doesn't
     make, each a kept goal to stock its larder or woodpile to a level:
     it takes the coins from the coffer, reads the boards, and buys a lot
     at a time (ask, hand over, pay), taking each home. From 12:00 the
     seller takes its takings home, and the buyer what it didn't spend.
   - A buyer buys at the cheapest price it knows, the nearest of those,
     if no dearer than its own pricing (coins a unit, raised by the need
     the goods serve, `#Pricing`). A seller prices its spare goods without
     the need's raise, so every posted price is the kind's: grain 1,
     venison 2, firewood 1. With the raise, a hungry farmer asked more
     for grain than a hungry woodcutter would give, and nothing sold.
   - Farmers start with last year's harvest, two hundred portions of
     grain, so they have grain to spare before their plots ripen.
   - Built on the way: what is in a container is known only to whoever
     looked in it, so buyers look in the coffer and sellers in the supply;
     a buyer with both hands full (a woodcutter's axe and log, a hunter's
     bow and coins) puts down what it carries, never its coins, and a
     hunter takes its bow up again to hunt.
10. **Looks come from content** (TESSERA.md slice 3; slice 2 below). Each
    blueprint names its look (`look: "tree.oak"`), resolved through the
    type hierarchy, and the watcher's theme gives each look a glyph and
    colours. A village has too many kinds of thing for the stopgap
    (blueprint names, first letters) to read well.
11. **What is carried is carried in a pack, and weighs on a walk**
    (asked for after slice 9). A household keeps a **backpack** and a
    **basket** by its door. A backpack is worn on the back, held by no hand,
    so both stay free; a basket is held in a hand. Each bears no more than
    its **load** (25 kg; 8 kg). What an agent carries in all slows its walk
    past a light amount (15 kg): half pace at 55 kg.
    - Built (content/carrying/). A woodcutter or a hunter takes the
      backpack as it leaves home in the morning, the first of the household
      to want it; whoever finds it gone does without, with its hands. On
      market day the seller takes a pack, and then the buyer, the backpack
      or else the basket.
    - Operations that **stow** put what is taken, or handed over, into a
      pack the agent carries if it fits, else a free hand: a woodcutter's
      gathering (forty pieces home at a time, not twenty), butchering (the
      meat, the bow still in hand), picking up a hide, a purchase (lots
      bought until the supply's need is met, then carried home once), the
      seller's unsold goods.
    - By the supply (a precondition can be within reach of a slot, AGENCY.md
      decision 23), what is in the pack is taken out and put away. At
      15:00 every pack is emptied (food and hides into the larder, firewood
      onto the woodpile) and put back by the larder.
    - What is in a pack its carrier carries, the carrier knows (KNOWLEDGE.md
      decision 25).
    - Built on the way: larders and woodpiles are kinds of their own, seen
      as such, so looking for food doesn't look in the coffer and the pack
      by the larder first; a hide is `#Hide` (a leather pack was "brought
      home" into the larder); a seller looks in its stall for takings
      paid in unseen; a buyer frees a hand, or checks its pack has room,
      before asking; with no woodland near, a wanderer heads for the
      nearest.

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
- **Market day**, every fourth (the third first), 09:00 to 12:00: a
  seller from each household stands at its stall on the green, and
  another comes to buy; the takings and the coins go home by 13:00.
- **Afternoon.** Firewood carried home, meat butchered, grain brought in.
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
| `perishing/` | perishable food: how long it keeps, when it spoils, spoiled food | new (slice 8) |
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
- **Its history** is compacted daily (KNOWLEDGE.md decision 21): what has
  a bearing on the world is kept; the tiles of walks are counted into
  digests after a day.

## Testing

`lab run village` runs a week of world time and checks:

- everyone ate every day and nobody's reserves fell below 50;
- every plot sown the first day (built), and every one harvested once
  ripe, or still growing;
- every stove had fuel each night;
- at least one sale was struck on each market day;
- no meat was eaten spoiled;
- the end state's hash (`ci/scenario-hashes.txt`).

Each slice brings its own tests too, as the lab's do. The `watcher` test
already proves that watching changes nothing.

Built (slice 10): `lab run village` runs seven days and checks them as it
goes, 79 checks in all: the design's above, each night (everyone fed that
day, reserves at 50 or more, stoves fuelled, packs back), each market day,
and at the end. No meat can be eaten spoiled (spoiled food isn't food); the
check is that nothing past its time is food still (three things spoiled in
the week). Its hashes are in `ci/scenario-hashes.txt`, the same on macOS
and on Linux (run in the CI image on arm64 as well as CI's x86-64).

What it costs, on an M-series Mac at `-o:speed`: 34 s for the week, 4.9 s
a world day; 75,120 boundaries, 157,347 perceptions (12.9 s), 168,715
decisions (16.1 s), the domains 0.1 s. `make check` runs it three times
(the village test, and the scenario's run and save) and takes 128 s in
all, the village 103 s of it. Not cut: if CI needs it faster, the save's
hash could come from the same run as the run's, and the test could run
three days, a week's cost once.

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
6. **Farming**: plots, sowing, ripening, harvesting (built).
7. **Hunting**: animals, death, butchering (built).
8. **Perishing**: food that spoils (built).
9. **The market**: coins, stalls, posted prices, sales (built).
10. **A week in the village**: the scenario's checks and hashes in CI, and
    how fast it runs (built).
11. **The knowledge view in the watcher**: one agent's village as it
    remembers it (TESSERA.md slice 2's knowledge scenes).
12. **Carrying**: backpacks and baskets, loads, a burdened walk (built;
    decision 11).

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
| Plot | Tilled ground a household farms: an area, known as a whole. *Avoid:* field, which is a component's field. (Built.) |
| Crop | What a plot grows: sown a row at a time, growing from its last row, ripe after its growth. (Built, as the plot's state.) |
| Perishable | Good for so long after it was made, then spoiled. (Built.) |
| Spoiled food | What perishable food is once its time has come: as heavy, made of rot, not food. (Built.) |
| Carcass | What an animal's body is once it dies: something to butcher. |
| Stall | Where a seller sets out goods on market day, with its posted prices. (Built.) |
| Posted price | A seller's written price for a kind of goods, read by buyers. (Built.) |
| Sale | A deal of goods for coins, made on the spot. *Avoid:* trade, which is a craft. (Built.) |
| Market day | Every fourth day, when stalls are set out on the green. (Built.) |
| Household | The people of a home: kin bonds. Not a **place** (DETAIL_REGIMES.md's entity), until abstract detail needs one. |
| Worksite | What a household's day's work is done at: a scarecrow in a plot, a chopping block, a hunting blind. *Avoid:* workplace. (Built.) |
| Meal | Food that isn't raw: cooked, or never raw. (Built.) |
| Larder | A household's container of food, a kind of its own, known from its neighbours' by where it is. (Built.) |
| Pack | A container carried: a backpack on the back, a basket in a hand, bearing so much. (Built.) |
| Kept goal | An ongoing condition: a commitment to it arises again whenever it no longer holds, through its window. (Built.) |

## Open questions

- **Can people die?** Settled (decision 7): any body whose injury reaches
  100 dies, a person into a corpse. Nothing in the village comes close.
- **Where game comes from.** Settled (decision 7): it comes in at the
  woods' edge while there are fewer than so many, a scenario input. A herd
  that breeds is a topic of its own.
- **Hides.** A hunter with the backpack carries the hide home to the
  larder (decision 11). Dressing them (the Hunts' other trade), and
  selling them, wait: nobody buys hides yet.
- **The hunt is fair, but the game never learns.** A shot can miss, and a
  deer bolts out of sight from a shot that gives the hunter away. Over a
  week, one hunter in a small wood brings home its two deer from 33
  shots, where before every shot struck and it filled its larder in a
  day or two. Game that learns where hunters wait, wind that carries
  scent, or a wounded animal that runs further and heals would make it
  harder still. And a hunter that has shot goes on uncrouched for up to
  twenty minutes (`hidden` is having crouched lately, not hiding now).
- **What becomes of spoiled food.** It stays where it spoiled: in a
  larder, beside the food, for good. Nobody throws it out, and nothing
  rots it away. Clearing out the larder is a chore with no goal yet;
  spoiled food that rots to nothing over weeks would be a second closed
  form, after the first.
- **Meat merged spoils with the oldest.** A larder's venison is one
  stack, and a stack spoils whole, so a fresh deer's meat put in with
  three-day-old meat spoils the next day. Keeping each day's meat apart
  (stacks that merge only when made the same day) would be truer, but
  then a condition on "forty kilograms of venison" reads one stack, and
  the hunters' would never hold. Eating the oldest first is the
  household's answer, and it isn't modelled.
- **Carcasses keep.** A carcass left unbutchered never spoils; only its
  meat does. A carcass that spoils is perishing on a body, not food.
- **What a stack is seen as.** A stack's count isn't perceived, only its
  mass, so a condition on a count never holds of what an agent knows.
  The woodcutters' "past three thousand pieces" was one, never done; it
  is three tonnes now, and the hunters' two deer forty kilograms.
- **Prices.** A posted price from the seller's values alone ignores what
  others ask. Whether sellers should read each other's stalls and follow is
  for after the first market works. Today it is the kind's price, the
  same at every stall: a seller prices spare goods without its need's
  raise, and only a buyer's pricing moves (with its hunger).
- **Carrying.** Settled (decision 11): a backpack and a basket. A barrow
  (a big load pushed with both hands, on open ground) is left for later.
  The basket is little used: a buyer with the basket in one hand and its
  coins in the other has no hand for the goods but the basket.
- **One pack to a household.** Three hunters share one backpack: the first
  out takes it, and the others hunt with their hands, leaving hides. A
  pack each, or a peg for each, is a question of what a household owns.
- **Unsold goods stay on the stall.** What wasn't sold stays set out on
  the green till the next market, perishable meat spoiling there. Taking
  it home after is a goal of its own.
- **A buyer always pays.** Handed the goods, the buyer pays at once; one
  who walked off without paying would be a thief, a case for the law
  (INSTITUTIONS.md), not built.
- **What the market costs.** Settled (PERFORMANCE.md decision 7): the
  stalls and boards stand at the crossroads, which nearly every walk
  passes, and working out what each entity seen is, and recalling and
  matching descriptions, was done from text every time. Done once now,
  the village takes 14 s, from 22 s (13 s before the market), with the
  same hashes.
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
- **The week's balance.** The woodcutters stock their three tonnes by the
  sixth day and stop, and sell thirty pieces a market; the Hunts may have
  nothing to sell on a market day (the seventh, in the checked run). What
  a household makes and what the others buy aren't matched yet: prices
  don't move with plenty, and nobody works more for want of coins.
- **Three weeks of the village.** A plot sown the first day ripens in a
  fortnight, so the village's own checks see sowing, not harvest; a plot
  of its own (src/test_farming.odin) is checked for three weeks. Run for
  three weeks (35 s), the village finds what happens past its food: each
  larder holds 60 portions and there is no market, so households go
  hungry from the fifth day. Some farmers then hold firewood fetched for a
  stove they couldn't stoke, and a raw portion, and with no hand free
  can't harvest a ripe plot. A slice that runs that long (10) wants the
  market first, and something that puts down what a finished goal left in
  hand.
- **Seed from the harvest.** Seed is kept back at the start and isn't
  made: a harvest yields food only, so a household sows again from what
  is left, and the Ashes' second plot runs short. Keeping back part of a
  harvest as seed is a method of its own.
- **Grouped perception.** A plot is one entity, so it is one referent. Many
  like things seen as one (a stand of trees, a herd) would be knowledge's
  to group, a larger change (KNOWLEDGE.md). The herds of slice 7 didn't
  need it: ten animals at most, each its own agent and referent.
- **Children.** The households are all adults. Children who eat but don't
  work would test the market harder.
