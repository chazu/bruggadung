# Review: technical debt, and how Triangle is used

## Status and scope

A review of the whole repository as of `fa2e056` (2026-11-09): the design
docs, Triangle's engine (`triangle/`), the content (`lab/content/`), the
lab's code (`lab/src/`), Tessera, the build and CI. It is an outside
reading, not a design doc: nothing here is decided, and every proposal is
a suggestion to argue with.

It has two parts, in this order because that is the order of leverage:

- §2 and §3: how Triangle is used to author the simulation, and how it
  could be used for more genericity, composability and emergent play.
- §4: the technical debt worth paying down, ranked.

§5 puts both into one order of work. §6 lists what is in good shape and
should be kept as it is.

How it was done, and its limits:

- Read: every root vocabulary file and about half the topics in full,
  every content file's header, CONTENT_LANGUAGE.md, DESIGN.md,
  DETAIL_REGIMES.md, METHODS.md, the READMEs and AGENTS.md; the lab's code
  by section (all effect bodies, agency's interpreter, the small domains,
  the scenario) and by grep elsewhere; Triangle's sources by module.
- Run: only read-only commands. `triangle check`, `export`, `inspect` and
  `fmt --check` from `triangle/build/`, against the content and against
  scratch `.tri` files outside the repository; small C probes linked
  against the existing `build/libtriangle.a`, also outside it; `git log`
  and `gh run list`. **Nothing was built, and `make check` was not run**,
  so whether the tests and scenario hashes pass locally today is not
  established here.
- Each finding says how it is known: **ran** (reproduced), **read** (from
  the code or the content), or **counted** (grep, or `git show
  --numstat`). Counts from grep are good to a few per cent.
- It tries to keep to GLOSSARY.md. Where it needs a word the glossary
  doesn't have (a *value slot*, a *declared effect*), the word is marked as
  proposed, and would need an entry if the idea were taken up.

## Summary

1. **Content says what things are and what agents know to do; code says
   everything that happens.** All 59 effects, every progression in time,
   every need, every kind of consideration, condition and premise, the
   market's and the deals' protocols, and every scenario's placement and
   daily commitments are Odin. Content names a mechanism; it cannot define
   one. The last eleven topics added 2,948 lines of content and 3,592
   lines of hand-written Odin outside tests and scenarios, and none was
   added without changing the lab's code (§2).
2. **The largest single step toward genericity is effects as data**, and
   Triangle can already do it: an operation that states its roles *after*
   the effect, with tags and arithmetic, is resolved by plain unification
   into the fields to set and the things to make (ran, §3.1). 38 of the 58
   effect procedures are instances of about seven primitives. Declared
   effects also give agents something to *expect*, which DESIGN.md §1 asks
   for and opaque code cannot provide.
3. **The same "value as of a time, read in closed form, with a wake at a
   threshold" is written six times** (hunger, lamp oil, trace strength,
   ripening, regrowth, perishing). DETAIL_REGIMES.md already designs the
   one mechanism that would replace them; building it at full detail
   first would retire three domains outright (§3.2).
4. **About 1,100 references in content are names in `text`** (`goal:
   "eat_when_hungry"`, `op: "eat"`, `kindOf: "#Food"`), which neither
   `triangle check` nor the language server can check (ran). The root
   vocabulary also keeps closed lists of what topics add (`#Effect`,
   `#Skill`, `#Order`, carrying's `burdens`), although Triangle already
   lets a package add an atom to a root enum (ran). Both are cheap to fix
   (§3.3, §3.4).
5. **Little of what the village does is chosen.** Of 139 methods, 5 serve
   a goal declared in another topic; 52 of 88 goals have exactly one
   method; 4 goals arise from needs. A villager's day is 18
   `agency_undertake_every_with` calls in `scenario_village.odin`, though
   an animal's day is already content (`#Instinct`). Emergence wants fewer,
   more general goals that many topics offer ways to, and motives that
   come from needs and stocks (§3.6, §3.8).
6. **CI has been red on `main` since 2026-11-07**, on all three
   platforms, and because Triangle's step fails first, the lab's tests and
   scenario hashes are not checked in CI at HEAD (ran, §4.1).
7. **Triangle's engine has two memory-safety defects and four that give a
   wrong answer silently** (a 128-entry path stack with no bounds check;
   32-bit generation counters that crash on wrapping; attributes found only
   along primary parents; `@field` flags lost when two packages share a
   label; arithmetic dropped when an instance is copied by name; a content
   hash that ignores attributes and feature names). All were reproduced
   (§4.2).
8. **About a fifth of the engine is used by nothing in the lab**: definite
   clauses, regular expressions, comprehensions and built-in functions,
   interpolation, `@fn`, `@vary`, the quick check, `tri_unify`. Some of it
   is exactly what §3 needs (unification, arithmetic); the rest should be
   used or frozen (§3.10).

## 1. The project, as read

Bruggadung is a maximalist, tile-based roguelike built framework-first: six
systems (actions, components, domain simulation, knowledge, agency,
institutions) specified in design docs, proven in the lab by scenarios,
with the game to follow. Three commitments run through everything and are
kept unusually well: determinism on every platform (integers only, hashes
of every scenario in CI), two views that never leak (agents reason from
their knowledge view, never the truth), and content as the source of truth
for components.

Triangle is the content language: TDL's typed feature structures in CUE's
syntax, with units, YADU defaults, seeded variation and three-valued
matching. CONTENT_LANGUAGE.md decision 9 states the intent this review
measures the content against: *rules are feature structures applied by
fixed engines*, and (§10) *"a rule's conclusion or result is built by
unification once its premises match."*

The content is 48 `.tri` files, 7,057 lines: 1,131 types, 700 instances,
50 components (`triangle check lab/content`, hash `9a35a92960b04979`,
matching `lab/src/components.odin`). The lab is about 33,000 lines of Odin
outside tests and scenarios, 2,200 of scenarios and 15,000 of tests.

## 2. How Triangle is used today

### 2.1 Who says what

| Concern | Content | Code |
| --- | --- | --- |
| What a thing is: components, fields, units, bounds, flags | all of it | generated structs (`make gen`) |
| What a thing looks like, whether a kind shows at a glance | `#Look`, `#Seen` | generic |
| Whether an operation applies | role patterns, matched three-valued | generic (`match_action`) |
| What an operation costs: duration, stages, exertion, attention, range, graded curves, traces left | fields of `#Operation` | generic readers |
| **What an operation does** | a name: `effect: "forage"` | 58 procedures, one table (`act_actions.odin:3178`) |
| **How a quantity moves with time** | the periods (`emptiesIn`, `regrowsIn`, `keepsFor`) | the formula and the wake, once per topic (`domains_*.odin`) |
| What an agent can want, and the ways to it | 88 goals, 146 methods, their patterns | a generic interpreter, with exceptions (§3.9) |
| **What a consideration, a condition, a premise, an order is** | the instance | one branch each in an if-chain (12, 6, 8, 8) |
| **What an agent feels** | a threshold: `pressed: { need: "hunger", above: 40 }` | five needs, each a struct field and a formula |
| An animal's day | `#Instinct` | 20 generic lines |
| **A villager's day** | nothing | 18 calls in `scenario_village.odin:481-556` |
| **What is where in a scenario** | blueprints and the map | tables and 285 lines of `village_setup` |
| What is said, and what follows | the shapes of utterances | 45 Triangle expressions built with `tprintf`, a 14-way and an 8-way if-chain, `agency_deals.odin` (1,201 lines for 129 of content) |

The rows in bold are where the simulation's logic lives, and none of them
is in Triangle.

### 2.2 Measurements

Of the content (counted, by grep over `lab/content`):

| Measure | Count |
| --- | --- |
| Effect names in `#Effect` | 59 |
| ... used by exactly one operation | about 50 |
| References that are a name in `text`: `goal:` 144, `op:` 122, `look:` 122, `object:` 119, `kindOf:` 85, `unit:` 68, `subgoal:` 63, `target:` 42, `did:` 26, others ~110 | about 1,100 |
| `text`-typed fields in `agency.tri` alone | 24 |
| Methods whose goal another topic declares | 5 of 139 |
| Goals with exactly one method | 52 of 88 |
| Goals raised by a need (`pressed`) | 4 |
| `let person = #Hungry & { material: "flesh", hands: 2 }`, verbatim | 8 files |
| Lines using a tag | 213 |
| Lines of arithmetic | 1 (`things.tri:116`, a stack's mass) |
| `@fn`, `@vary`, `@variants`, `#Clause`, `#Fact`, field references, comprehensions, interpolation, regular expressions | 0 each |
| `@quickcheck` | 2 (of 77 operations) |

Of the lab's code, outside tests (counted):

| Measure | Count |
| --- | --- |
| `tri.at` / `tri.pattern` / `tri.type_named` | 357 / 116 / 113 |
| `tri.match` | 18 |
| `tri.construct` | 1 |
| `tri.unify`, `tri.solve`, `tri.register_fn` | 0 |
| `"Kind.field"` literals naming a topic's field (not a root kind's) | 99 distinct, 188 uses |
| Triangle expressions built as text and parsed (`tri.value`) | 45 sites |
| `BG_*` constants that are rules of the simulation, not sizes | about 60 |

So the lab uses Triangle mostly as a typed, well-checked configuration
tree: it looks a pattern up by name, walks to a field by name, and reads a
number. Matching is used where the design said it would be (the menu,
`pre` and `done`). Unification, the operation the language is built on, is
not called at all.

What the last eleven topics cost (counted, `git show --numstat`; "Odin"
leaves out tests, scenarios and `components.odin`):

| Topic (commit) | `.tri` added | Odin added | Scenario | Tests | Root vocabulary edited |
| --- | --- | --- | --- | --- | --- |
| hunger, reworked (18bbcdc) | 95 | 241 | 0 | 124 | things |
| cooking (2cb8066) | 258 | 68 | 105 | 65 | actions, agency |
| firewood (dd872c7) | 355 | 157 | 99 | 90 | actions, agency, things |
| farming (0610eec) | 283 | 339 | 91 | 212 | actions, agency, things |
| hunting (544260e) | 440 | 383 | 57 | 387 | actions, agency, knowledge |
| perishing (4c09ed7) | 70 | 125 | 22 | 125 | things |
| market (73968cb) | 498 | 434 | 153 | 139 | actions |
| carrying (742e662) | 553 | 239 | 71 | 99 | actions, agency |
| prices by stock (1fa473d) | 125 | 201 | 83 | 58 | none |
| deals (b7d29fe) | 136 | 1,221 | 0 | 176 | actions, agency |
| foraging (58f78ea) | 135 | 184 | 72 | 91 | actions, agency |

Eight of the eleven edited `actions.tri`, nearly always to add an effect's
name; seven edited `agency.tri` to add a kind of consideration, order or
step that then needed a branch in the interpreter. Adding a topic today
touches about fifteen files, six of them Odin.

### 2.3 What already works, and shows the way

These are the places where the intent of decision 9 is met, and each is
evidence that the rest can follow:

- **Applicability is all content.** Whether an operation is on the menu is
  a match of its role patterns against descriptions; unknown never
  excludes. No topic has a guard in code beyond a few repeated inside
  effects.
- **Descriptions are generic.** An entity's description is built from the
  generated field registry and the `perceive`, `inspect` and `appears`
  flags. A new perceivable field needs no code.
- **Methods compose across topics.** Foraging adds a way to hunger's
  `eat_when_hungry` without hunger knowing; carrying's handling goals
  serve market, firewood and hunting through `#Achieve`'s `with`. This is
  the mechanism emergence will come from; it is only little used (§3.8).
- **Animals are agents.** A deer is an `#Agent` with no hands, an
  `#Instinct`, and one rule that concludes `#Danger`. Nothing in agency
  knows what a deer is.
- **Topics own their fields** (decision 12), and `hunger.#Food: { raw: … }`
  in `cooking/` is open-world extension done right.
- **Transformations name their products in content** (`fellsInto`,
  `yields`, `spoiled`, `remains`). The code knows "it becomes what its
  field says", not "a tree becomes a trunk".
- **The cut-point headers are honest.** The `- code:` items were checked
  against the code for eleven topics and each was accurate. They are a
  reliable index of everything §3 proposes to move.

## 3. Using Triangle for more

Ordered by what each buys. §3.1 to §3.4 need little or nothing from the
engine; §3.5 onward need design.

### 3.1 Effects as data

**Now.** `effect: "forage"` names `effect_forage` in `act_actions.odin`.
There are 58 such procedures (1,145 lines) and `fill`, which has none and
is special-cased by name in `perform`. Reading every body, they divide:

| What it does | Procedures | Lines |
| --- | --- | --- |
| Moves a thing, or some units of a stack, to a place | 12 | 111 |
| Sets or adds a constant to one field, or emits one event | 16 | 82 |
| Consumes or transforms a thing into the blueprint one of its fields names | 10 | 193 |
| Genuinely procedural (rotate, work, reveal, install, shoot, sow, walk, …) | 20 | about 760 |

Having no parameters, effects are reused by accident of name. `mind_stall`,
`lie_in_wait`, `graze` and `bed_down` all take the effect `"rest"` to mean
"wait"; `effect_rest` sets `Agent.fatigue` to 0 whatever the duration
(`act_actions.odin:3155`), and `perform` hangs a carbon-dioxide watch on
anything whose effect is `"rest"` (`:3949`). So, by reading, ten minutes
minding a stall clears a day's fatigue. `effect_walk` reads its direction
out of the operation's *name* (`walk_north` → the letter after the
underscore, `:739`). `work_rate` asks whether the effect is `"walk"` to
decide if a burden slows it.

**What Triangle can already do.** An operation can state its roles as its
effect leaves them, sharing tags with the roles it requires. This loads
today, in a scratch file with the types cut down (ran):

```cue
// proposed: what an effect makes, and where; `after` is the roles as the
// effect leaves them
#Makes: { blueprint: text, at: #Place }

forage: #Operation & {
    duration: 10min
    roles: {
        actor: #Agent & { id: $a, freeHands: >=1 }
        item:  #Patch & { handfuls: $h & >=1, yields: $y }
    }
    after: { item: #Patch & { handfuls: $h - 1 } }
    makes: [{ blueprint: $y, at: #Held & { by: $a } }]
}

cook: #Operation & {
    duration: 1200s
    roles: { actor: #Agent & { id: $a }, item: #Food & { raw: true, place: #Held & { by: $a } } }
    after: { item: #Food & { raw: false } }
}
```

Unified with a description of the truth (`actor.id: ref(7)`,
`item.handfuls: 3`, `item.yields: "berries"`), `triangle export` gives
`after.item.handfuls: 2` and `makes: [{ blueprint: "berries", at: { by:
ref(7) } }]`. The engine worked out the effect; the lab would only have to
turn each concrete field under `after` into a proposal, construct what
`makes` lists, and destroy what a `consumes` lists. That is CONTENT_LANGUAGE
§10 as written, and its §17 example already has `effects: target: state:
"tight"`.

**What it needs.**

- A small *declared effect* vocabulary (proposed term): `after`, `makes`,
  `consumes`, `emits`. DETAIL_REGIMES.md form 3 asks for the same thing
  for abstract detail (`{ role, field, by }`); one vocabulary should serve
  both, so an operation means the same at every level of detail.
- Clamping to a field's bounds in the lab, as DETAIL_REGIMES already
  notes: `satiety + nourishment` above 100 fails unification today.
- The engine defect in §4.2 (5) fixed first. The same structure reached by
  name, `forage & { roles: … }`, gives `handfuls: >=0 & <=99`: copying an
  instance by name drops its arithmetic (ran). Whether `tri_unify` on a
  pattern at runtime keeps it was not established.
- `effect:` kept as the way out for the twenty that are procedural. A
  named effect and a declared one can stand side by side, so this can be
  done one operation at a time, each with its scenario hashes unchanged.

**What it buys.**

- 38 procedures and about 390 lines go, with the `#Effect` edit that seven
  of the last eleven topics made. A topic like brewing or fishing becomes
  content only.
- *Expectation.* DESIGN.md §1 separates "what do they expect?" from "what
  actually happens?". With effects as data both are the same unification,
  once against the agent's knowledge view and once against the truth
  projection; where they differ is a surprise the agent can notice. With
  effects as code, an agent cannot be wrong about what an operation does,
  because it has no idea what it does.
- *Means-ends.* A goal's `done` and an operation's `after` are both
  patterns, so "which operations could bring this about" is a
  subsumption test. Not a planner, but enough for agency to propose an
  operation no method names, or for a tool to list goals nothing can
  achieve.
- More roles. The lab's `Role` enum is fixed at actor, item and
  destination, which is why `effect_rotate` searches for its own lever
  chain. Roles declared in content, read generically, lift that.

### 3.2 One progression, for full detail too

**Now.** A quantity kept as (value, as of a time, a period), read in
closed form, with a wake when it crosses a threshold, is implemented
separately for satiety and reserves (`domains_bodies.odin`), lamp oil
(`domains_light.odin`), trace strength (`domains_traces.odin`), a plot's
ripening (`domains_farming.odin`), a patch's regrowth
(`domains_foraging.odin`) and perishing (`domains_perishing.odin`); habit
and memory fading are two more outside the domains. The farming, foraging,
perishing and game domains are each about 60% the same scaffolding.

Because the read is in code, content cannot see a progressed value: the
generic description reads the stored record, so a pattern over `satiety`
sees it as of `fedAt`. That is why farming has to write `Plot.stands =
"ripe"` at a wake, where a pattern over growth would do.

**Proposal.** Build DETAIL_REGIMES.md's form 1 (a rate on a field) and
decisions 4 and 5 (read, don't step; thresholds as wakes) as a family of
instances, and use it at *full* detail first, where there are six working
implementations to check it against:

```cue
// a sketch: what moves, by how much, how often, between what, and what a
// threshold does
regrowth: #Progression & {
    applies: #Patch
    moves:   "handfuls"
    by:      1
    every:   "regrowsIn"
    asOf:    "grewAt"
    upTo:    "most"
} @family(progressions)
```

The glossary's *progression* is "what a thing does below full detail";
this stretches it to every level of detail, on purpose: the abstract
column of DETAIL_REGIMES then needs no second mechanism, only a regime
that picks a coarser progression. Three domains (about 310 lines) go
outright, about 200 more from bodies, light and traces, and descriptions
gain a generic lazy reader, so content can at last match a progressed
value. Atmosphere, heat and water stay code: they couple, and
DETAIL_REGIMES is right that Triangle cannot help there.

### 3.3 Names that are checked

**Now.** A method names its goal, its subgoals and its operations in
`text`; a `#Seen`, a `#Look`, a rule's `concludes` and a `#Sighted` premise
name a *type* in `text` (`"#Food"`, `"#Danger"`, `"#Agent"`); a slot is
named in `text` in `find`, `search`, `binds` and `to`. A scratch file with
`goal: "g_typo"` loads without a diagnostic (ran). The lab checks them
when they are used, not at load: a wrong subgoal is a method failing with
"there is no goal …" (`agency_agency.odin:2130`), a wrong operation an
action refused (`act_actions.odin:263`), in whichever run first reaches
it.

The content is not consistent about this. `#Arising` takes its kind as a
pattern (`of: #Spoiled`), as do `#Valuing` (`valued: #Body & { material:
"food" }`) and `#AtHome` (`stocked: #Food`); `#Seen` and `#Rule` take
theirs as a string. The pattern form is checked, completes in the editor,
and generalises (any pattern, not only a named type).

**Proposals, cheapest first.**

1. Where a field names a *kind*, make it a pattern: `kindOf: #Food`,
   `concludes: #Danger`, `sighted: #Agent`. No engine change. 85 `kindOf`
   and 14 others.
2. Where a field names an *instance* (a goal, an operation, a blueprint),
   add one attribute to the engine, say `goal: text @names(goals)`: the
   text must name an instance in that family, checked at load, with
   go-to-definition and completion in the language server (which already
   resolves a string to "the instance it names" for hover). About 500
   references become checked for one small feature.
3. Where a field names a *slot*, the frame's type already knows its slots;
   a load-time check in the lab (every name in `find`, `search`, `binds`,
   `object`, `target` is a feature of the method's frame) needs no engine
   change.

### 3.4 Open vocabularies

**Now.** lab/content/README.md's rule 2 says the root never refers to a
topic's declarations. In practice the root keeps closed lists of what
topics add:

- `#Effect` (`actions.tri:27`): 59 atoms on one line, 51 of them a topic's
  (`"cook"`, `"butcher"`, `"forage"`).
- `#Skill: "painting" | "wary" | "stalking"` (`knowledge.tri`): two are
  hunting's.
- `#Order`'s `"keeps"` is perishing's; `#Material`'s `"rot"` likewise.
- `#AtHome` and `#ByLight` are root considerations with one user each
  (cooking's rationing, foraging).
- Carrying enumerates other topics' things: `let burdens = #Food & #Stack
  | #Seed & #Stack | #Stack & { unit: "firewood" } | #Hide | #Log | #Axe |
  #Bow` (`carrying.tri:129`), and again as `kept`; market's `goods`
  likewise. A new tool or good means editing carrying and market.

**Triangle already allows the fix** (ran): a package's file that declares
`#Effect: "forage"` adds that atom to the root's enum, and without that
line `effect: "forage"` is a load error. So each topic can declare its
own atom beside the operation that uses it, and `actions.tri` keeps only
the seven the root's own operations use. The same holds for `#Skill` and
`#Order`.

For the lists of things, use a trait type that a topic opts its own kinds
into: `#Burden: #Body & {}` in carrying, and `#Log: #Body &
carrying.#Burden & { … }` in firewood. That loads across packages (ran),
points the dependency the right way (the specific topic knows the general
one), and a new tool is put down to free a hand without carrying being
edited. `#Sellable` would do the same for market's `goods`.

### 3.5 Writing a thing once

**Now.** Three kinds of repetition, each with a different cause.

*Per-good copies.* Buying grain, meat and firewood are twelve declarations
each, alike "but for their unit and the level" (`market.tri:383-500`, the
comment is the content's own): `grain_stocked`, `grain_coming`,
`grain_priced`, `coins_for_grain`, `grain_in_hand` and seven methods, then
the same for `meat_` and `firewood_`. `scenario_village.odin:1059` then
lists the goal names again. A fourth good is forty more lines and an Odin
edit. The cause: a goal's slots hold only referents, so "which good" has
to be baked into the goal's name.

*Per-topic re-wrapping.* Firewood and hunting each declare `let
out_of_the_pack = { … subgoal: "thing_in_hand", with: [{ binds: "thing",
to: "wood" }, …] }` and a `wood_packed` / `meat_packed` pattern, the same
shape under different slot names; market has a third. The cause: every
topic names its own slots (`wood`, `meat`, `goods`), so the shared goal is
reached through a renaming.

*Per-file lets.* `let person = …` in 8 files, `raw_grain` in 2. The cause:
a `let` is its file's own.

**Proposals.**

1. *Value slots* (proposed term): let a frame carry a value from content
   beside its referents, and let a commitment bind it. This loads today
   (ran):

   ```cue
   #Good:     { of: text, lot: int & >=1 & <=100, level: mass }
   #Stocking: #Frame & { good: #Good & { of: $u }, goods: #Stack & { unit: $u }, supply: #Body }
   grain: #Good & { of: "grain", lot: 10, level: 20kg } @family(goods)
   ```

   `#Stocking & { good: grain }` resolves `goods.unit` to `"grain"`
   through the tag. One `stocked` goal with its seven methods then serves
   every good, a new good is one line, and the lab stops naming goods. The
   change is in agency (a slot bound to a structure, not only a referent;
   an intention identified by its goal *and* its value slots), not in the
   engine.
2. *Shared slot names.* Where a topic's slot is carrying's `thing` under
   another name, call it `thing`. `#Handling` already declares `thing` and
   `into`; the topics' frames inherit it and then rename. Most `with:`
   lists, and the `out_of_the_pack` lets, go.
3. *Methods as types.* `#Walk: #Operation & { … }` with `walk_north:
   #Walk` is already the idiom for operations. `eat_what_i_have` and
   `eat_it` (`hunger/eating.tri`) are the same method for two goals; a
   `#EatHeld: #Method & { pre: …, steps: … }` with two one-line instances
   says so. (This also sidesteps §4.2 (5), since a type's constraints are
   expanded, not copied.)
4. *In the engine*, in order of value: a `let` a package exports (ends the
   eight `person`s); comprehensions that make declarations over an enum or
   a family, which CONTENT_LANGUAGE §2 chose not to adopt and which the
   per-good copies argue for reopening if value slots are not taken up.

A caution found while checking the sketches: one type introduces a feature
per package, so `#Makes: { place: … }` and `#Good: { unit: … }` are load
errors beside `#Body.place` and `#Stack.unit`. The rule is sound, and its
diagnostic is good, but it pushes authors toward a different word for the
same idea in every structure (`place`/`at`, `unit`/`of`). Worth watching as
vocabularies grow.

### 3.6 Routines and scenarios in content

**Now.** `scenario_village.odin:481-556` undertakes each villager's
commitments by name and hour: at work 07–15, home 15–22, asleep 22–30,
food along 06–07, supper 18–21, the stove 19–21, and by worksite the
woodpile, the hunt, the plot, the stall. Seventeen goals are named in Odin
strings, with their slot names. Meanwhile `hunting/animals.tri` has:

```cue
grazing: #Instinct & {
    keeps: [{ goal: "roam", from: 5h, until: 21h },
            { goal: "bedded_down", from: 21h, until: 29h }]
} @family(instincts)
```

read by twenty generic lines (`agency_take_on_instinct`). The header says
why people differ ("a person's is none: its days are its commitments"),
but the commitments are still a fixed list by trade.

Likewise what stands where: household, plot, game and forage tables and a
285-line `village_setup`; herd sizes in `game_add_herd` calls, with the
herd's state kept outside the world in `domains_hunting.odin`; ownership
set up at fifteen sites across thirteen files.

**Proposals.**

- A *routine* by trade and household role, in content, in `#Instinct`'s
  shape plus the slots each commitment binds and how (the household's
  larder, the agent's own bed). DETAIL_REGIMES.md's abstract detail needs
  exactly this ("a schedule and an authored routine"), so it is owed
  anyway.
- A world as content: map legend entries that place blueprints, households
  as instances that own what is placed in them. `@embed` maps are most of
  the way there. The tests' 485 `proposal_group_create` calls are the same
  need at small scale.

### 3.7 Needs, considerations, conditions

**Now.** Five needs (hunger, cold, stuffy, tired, pain) are each a struct
field, a `feel_*` procedure and a formula in `know_knowledge_2.odin`; the
coldness and breathlessness formulas, and the body's 310,000 mK, appear
again in `domains_bodies.odin`. Twelve kinds of consideration are told
apart in `agency_sum` by which feature is present; `#Need`, `#Trait`,
`#ByLight` and `#AtHome` are all "a curve over a named quantity of the
agent's". About sixty constants that are rules sit in code (`BG_BUSY_COST`,
`BG_DUTY`, a hit is 15 injury, a need presses again when felt 20 more,
sight reaches 4 tiles), though `burden`, `daylight` and `weakness` show
the idiom for holding them in content: a one-instance family.

**Proposals.**

- A need as an instance: what it is read from (a field, through a
  progression), its curve, its band, what dulls it, what it harms when
  unmet. Thirst becomes a topic, not a change to the knowledge store.
- One consideration over a named *quantity* (proposed term), with the
  quantities registered: a need's pressure, a trait, daylight, a believed
  stock. Four kinds become one, and the fifth costs a registration, not a
  branch.
- Move the rule constants to content families. No new mechanism;
  `int_feature(tc, tri.pattern(tc, "burden"), "light", 0)` is the existing
  idiom.

### 3.8 Toward emergence

The framework's parts for emergent play are built: three-valued matching,
residuals that become goals to find out, hypotheses, memory that
generalises, considerations that add. What the content gives them to work
on is narrow, in four ways.

1. **Goals are specific, so ways don't compete.** 52 of 88 goals have one
   method: that is a script with a precondition. Only `eat_when_hungry`
   has ways from three topics, and it is the most alive behaviour in the
   village (eat, cook, eat raw, forage, then ask a neighbour). The same
   could hold for *be warm* (stoke, light, go indoors, dress, huddle), *have
   coins* (work, sell, borrow, take), *have food at home* (farm, hunt,
   forage, buy, ask). Each topic would add a way and a consideration, and
   which is taken would depend on the agent's traits, beliefs and
   circumstances. Value slots (§3.5) are what make a general goal
   writable.
2. **Work comes from the clock.** The hunter hunts because it is 07:00.
   `#AtHome` already measures a believed stock against a curve; used as a
   goal's worth, a woodcutter would cut because the pile is low and stop
   when it isn't, a household short of grain would send someone to buy,
   and a bad harvest would change what people do without anyone authoring
   the change. METHODS.md names this ("maintenance goals as their own
   kind") as not covered; it is the next thing after whole ways.
3. **Kinds are closed over what was thought of.** `wary_of_people` is a
   rule over `sighted: "#Agent"`. As a pattern (§3.3) with the danger a
   trait of the feared (`#Predator`), a wolf added in one topic makes deer
   bolt and makes villagers wary, with no edit to either. The same
   argument applies to `burdens` and `goods` (§3.4). Every closed list in
   content is an interaction that cannot happen until someone edits the
   list.
4. **Agents cannot be wrong about what an operation does** (§3.1), and
   cannot read a progressed value (§3.2). Both are what mistaken plans,
   and so stories, are made of.

Two smaller things. Only 11 interpretation rules exist, over 8 kinds of
premise that are each coded; a premise that is a pattern over an
observation (as CONTENT_LANGUAGE §17's `recently_cleaned` is) would let
content add inferences freely. And no blueprint uses `@vary` weights or
structural alternatives, and `tri.construct` is called from one site:
seeded variation, the cheapest source of difference between two villagers
or two deer, is built and tested and nearly unused.

### 3.9 Topics inside agency

`agency_agency.odin` is generic over goal names, with these exceptions
(read): the market block, `agency_pricing` through
`agency_settle_purchase` (`:2486-2989`, 14 procedures, about 440 lines),
which tests for `"#Stall"`, builds `#Stack & { unit: "coin" }` and names
the slot `"supply"` and the operations `"hand_over"` and `"pay"`; `op ==
"post"` special-cased in the method interpreter (`:2283`); the `#Purchase`
and `#HandOver` step kinds and the `buying` condition; `"pay_wage"` and
hiring; `OfficeHolder.badge` in goal selection. `agency_deals.odin` is
1,201 lines for a topic of 129. In the committer, `Pack.worn`, `Pack.load`
and five `GasStore` fields are enforced by name; a stack's merge averages
`Perishable.spoilsAt` in `kinds_body_kind.odin`.

METHODS.md's open question 2 asks whether "enough coins" should be
"market-specific, or a general comparison of a held quantity with a
believed one". This review's answer is the general one: with a condition
that compares two quantities (§3.7) and a step that asks and waits for an
answer of a declared type, buying is content. Conversation as a whole (the
45 formatted expressions, the two if-chains) is a research item; a table
from utterance type to handler and reply types would at least put the
dispatch in one place. For merging and placement, a field flag (`@field(…,
merge(mean_by_mass))`, a container's limit) would take perishing and packs
out of the committer and the body's reactor.

### 3.10 Use it or freeze it

Engine features with tests and no use in the lab (counted):

| Feature | Engine | Use in content | Use in the lab's code |
| --- | --- | --- | --- |
| Definite clauses (`clause.c`, `tri_solve`) | 258 lines | 0 | 0 |
| Regular expressions (`regex.c`, `text.c`) | 806 lines | 0 | n/a |
| Comprehensions, built-in functions | about 1,000 lines | 0 | n/a |
| Interval arithmetic (`arith.c`) | about 650 lines | 1 line | n/a |
| Quick check, pattern indexes (`qc.c`) | 153 lines | 2 attributes | the index used as a list |
| `@fn`, `@vary`, `@variants`, alternatives | n/a | 0 | `construct`: 1 |
| `tri_unify`, `tri_lgg`, `tri_match_hypotheses`, `tri_binding`, `tri_explain`, `tri_save`/`restore`/`migrate` | n/a | n/a | 0 each |
| The TDL front end (`tdl.c`) | 485 lines | n/a | left out of the game's library |

Some of this is what §3 wants: unification and arithmetic for declared
effects and progressions, variation for difference, `@quickcheck` once
methods number in the thousands, `tri_binding` and `tri_explain` for a
developer's "why didn't it". Clauses have a named future use (routes with
delays, DETAIL_REGIMES form 4). The rest (regular expressions,
interpolation, most built-ins, TDL beyond its role as a test oracle) has
no use in sight. Unused code still costs: `tri_unify` runs a settling pass
over every result if the content has any arithmetic anywhere, and the
clause prelude is the cause of §4.2 (9). Either give each a first real
use in content or put it behind a build flag and say "frozen" in the
README.

Units are a smaller case of the same: nine kinds in a compiled-in table,
copied into the exporter, the language server, the Emacs mode and the
reference. Content types `heat`, `heatCapacity` and gas amounts as bare
`int` (`heat/heat.tri:44`), and by a rough count 108 fields are `int` or
`fixed` against 35 with a quantity kind, so the unit checking the language
is proud of covers a quarter of the numbers. Unit descriptors loaded as
data (triangle/README.md's known shortcuts already expect them) would let
a topic declare a rate, a price or a heat capacity.

### 3.11 The seam between them

The API is shaped like text, and the lab pays for it:

- Every lookup takes a C string and interns it: 357 `tri.at`, 116
  `tri.pattern`, 113 `tri.type_named` outside tests, many per decision.
  There are no handles for features, paths, instances or families.
- The only way to build a description is to print Triangle source and
  parse it (`tri.value`, 45 sites, with `err` passed as nil at those
  read). `agency_match_supposing` prints a referent's description and
  re-parses it; PERFORMANCE.md decision 3 (not built) and a text-keyed
  memo on the World are the compensation.
- A plain name stops resolving when any package adds a homonym (§4.2
  (7)), and `tri_at` returns nil for "ambiguous" as for "absent".

Proposal: resolve at load. One pass after `load_content` turns every goal,
method, operation and rule into an Odin struct holding handles (the
compiled path of each field read, the pattern, the family index), and
fails loudly on anything missing; a small builder (`tri_node_new`,
`tri_set`) replaces print-and-parse. That is also where the checks of
§3.3 live, and it turns today's silent "field absent, default used"
(`operation_run` returns 4 when `run` is missing or malformed) into a
load error.

## 4. Technical debt

Ranked within each part. Sizes are S (hours), M (days), L (a week or
more).

### 4.1 Stop the line: CI is red, and the lab's gate isn't running

- **CI fails on `main` on all three platforms** (ran, `gh run list`: the
  runs of 2026-11-07 and 11-09 fail; the last success is 11-04).
  - macOS and Linux fail in Triangle's `cli-test`: the content isn't as
    `triangle fmt` writes it. `triangle fmt --check lab/content` lists
    `farming/farming.tri`, `firewood/firewood.tri`, `hunting/hunting.tri`
    and `market/market.tri` (ran, with the build of 11-05).
  - Windows fails to compile: `strndup` at `triangle/src/types.c:48` is
    not C11 and not in MSYS2's clang64 headers; it came in with packages
    (`e22f407`).
  - The workflow's steps run in order (`.github/workflows/build.yml`), so
    with Triangle's step failing, Tessera's and the lab's never run. **The
    scenario hashes, the project's determinism guarantee, are not being
    checked in CI.**
- **`make check` doesn't check what CI checks.** lab/AGENTS.md names it as
  the gate before a commit, but `lab/Makefile:63-66` doesn't run `fmt
  --check`, so following the rule still breaks CI. That is how HEAD got
  there.
- **The installed `triangle` is stale and says "ok"** (ran).
  `~/.local/bin/triangle` (2026-11-02) predates topic directories: on
  `lab/content` it reports `318 types, 33 instances, 8 components` where
  the current build reports 1,131, 700 and 50. Both print `triangle
  0.1.0`. triangle/README.md's Emacs snippet points the mode at the
  installed one. `triangle/build/triangle` itself is older than
  `libtriangle.a`, because `make test` doesn't build `all`.

Paydown (S, all of it): replace `strndup`; format the four files and run
`make gen`; add `fmt --check content` to `make check`; make the three
steps independent jobs (or `if: always()`), with `make asan` in the Linux
one; stamp `triangle version` with the git revision and have the lab and
the Emacs mode refuse a mismatch.

### 4.2 Triangle's engine: defects

All reproduced with scratch files or probes outside the repository, unless
marked. Those marked † were checked a second time, independently (re-run,
or for (1) re-read at the lines cited).

| # | Defect | Evidence | Size |
| --- | --- | --- | --- |
| 1 | **The unifier's path stack is 128 entries, unchecked**, and a list is a chain of `rest` arcs, so a list's length is depth. | `src/internal.h:451`, `src/fs.c:460` (read †). A conflict in item 128 of a list reports the wrong path; the write lands on the neighbouring `depth` field. Inside a struct, so ASan doesn't see it. | S |
| 2 | **Generation counters are 32-bit and wrap into a crash.** | `src/fs.c:14`. After 2^32 operations a stale scratch pointer is trusted: SIGSEGV. The README lists the limit as a shortcut; at its own 1.6 M unifications a second it is 45 minutes of engine time. | S |
| 3 | **Field attributes are found only along primary parents.** | `field_attr`, `src/load.c:3168`. `@widen` on `#Sized` applies to `#Sized & #Thing` and not to `#Thing & #Sized`; an `@fn` there is never called. No diagnostic. The content works around it already: "(Sized first: its size widens as #Sized says.)", `fastening/fastening.tri:27`. | M |
| 4 | **`@field` flags vanish when two packages add a same-named field to one type.** | `src/types.c:1658` resolves the label in the type's package, not the declaring file's. Decision 12's own example (`cooking.larder`, `farming.larder`) yields both registry entries with no flags, and the content-field check is skipped. Latent: no component has two yet. | S |
| 5 | **Copying an instance by name drops arithmetic, variant correlations and defaults.** † | `base: #Box & { girth: ($w + $h) * 2 }`, `derived: base & { w: 10mm, h: 20mm }` exports `girth: "length"`; inlined, `60mm`. CONTENT_LANGUAGE decision 5 says a name unifies a copy of its constraints. Blocks §3.1 by name. | M |
| 6 | **The content hash ignores attributes and feature names.** † | Changing `@field` flags and `@vary`'s mode leaves the hash as it was. The hash guards `components.odin` and saves by ID; flags, generated field names and seeded construction can all change under it. | S |
| 7 | **A plain name stops resolving when an unrelated package adds a homonym.** | `tri_type_named(c, "#Food")` returns bottom once a second package has a `#Food`; `tri_restore` and `tri_migrate` fail on the saved feature name. A mod that adds a homonym breaks saves and any of the lab's 113 `type_named` calls that name it. | M |
| 8 | **Match results are truncated silently.** | `residual[16][128]` (`include/triangle.h:205`): a 17th residual is dropped, a long path cut at 127 characters (and may then resolve to a *different* node). Residuals are what agency turns into goals to find out. | S |
| 9 | **A comment can break a load.** † | The clause prelude is injected on `strstr(src, "#Clause") \|\| strstr(src, "#Fact")` (`src/load.c:4310`). A file with `// see #Fact` and a type with a field `head` fails: "feature 'head' is introduced by both #Animal and #Clause". `#Factory` triggers it too. | S |
| 10 | **Misspelt attributes are accepted.** † | `@feild(content)`, `@widen(banana)`, `@famly(x)` load with no diagnostic. A misspelt `@field` leaves a field unregistered; a misspelt `@family` drops a goal from agency without a word. | S |
| 11 | **The symbol table only grows, and runtime text lives in it.** | Two million `tri_value` calls with distinct text: 2.3 MB to 220 MB. Lookups intern their argument even on a miss, through a cast-away `const`. Matters once names and utterances are generated. | M |
| 12 | **One syntax error hides every other diagnostic.** | `perr` keeps the first error per file, and `finish_load` skips the hierarchy if any file failed. With 48 files in one build, the editor loses all type feedback while any file is mid-edit. | M |

1, 2 and 6 are small and should not wait. 3 and 5 decide what content can
be written, so they come before §3.1 and §3.5.

### 4.3 Triangle's engine: structure and API

- **`src/load.c` is fourteen modules in one file** (4,578 lines, about 200
  functions): building from syntax, type expansion, variants, arithmetic
  settling, defaults and specs, construction, the inspector and explainer,
  matching, memory decay, the content hash, the field registry, packages,
  the comprehension evaluator, and the load driver. They share one `Build`
  struct, and pass parameters as fields of `TriContent` (`varskip`,
  `cyclic`, `depth`, `pathstack`). `fs.c` calls up into `load.c`, so the
  kernel depends on the loader. `src/internal.h` exposes the whole
  60-field `TriContent` to every file, and its section labels are wrong in
  places. Cut along those fourteen lines, pass an explicit operation
  context, and move type expansion beneath `fs.c`. (M–L; mechanical once
  the context is explicit.)
- **Six styles of error reporting**: diagnostics as strings with no codes,
  an `err` buffer, `TriFailure`'s fixed buffers, a bare NULL, `(size_t)-1`,
  a count and a flag. `tri_node_type` and `tri_node_interval` dereference
  NULL, and docs/API.md's own `@fn` example chains them onto `tri_at`.
  Pick one convention. (M)
- **Game concepts in the engine's library**: `@component` and `@field`
  with the `content` flag, "a blueprint is an instance with a component",
  the C and Odin struct generators (`src/runtime.c:231-540`), credence
  masses, sizes "for a knowledge store". None is wrong for a prototype
  with one consumer, but the generators at least belong in `tools/`. (S)
- **Three lexers** (`src/parse.c`, `tools/fmt.c`, `tools/lsp.c`), and the
  language server re-implements package resolution; its attribute table
  omits `@embed`, which the content uses nine times. Expose the library's
  token stream and name resolution to the tools. (M)
- **Tests miss the lab's shapes.** 95 test functions and about 725 checks,
  with property tests, fuzzing and a leak check: good. But nothing tests
  `tri_arena_mark`/`release` (the lab's memory pattern) or
  `tri_component_odin` (the lab's build depends on it); `@widen` and `@fn`
  are tested only on the declaring type; nothing goes deeper than 64;
  `test_example_file` and `test_docs_guide` print "(skipped)" and pass
  when the file isn't found from the working directory. Add the
  regressions for §4.2, and make a skip a failure. (S–M)
- **The design doc has drifted from the engine**: CONTENT_LANGUAGE §12
  says the load arena is dropped after specs are frozen (it stays; the
  README says so); §8 lays specs out "by position" (arcs are sorted); §18
  says "about 7,800 lines, with 2,000 lines of tests" (about 13,400 and
  3,750); its status line still reads "Proposal". Of 95 diagnostic
  messages in `src`, 29 aren't in docs/REFERENCE.md's list. (S)
- **The Odin binding is mirrored by hand** (207 lines, one 48-line test,
  no size or offset assertions), and `load_files` drops warnings on a
  successful load. (S)

### 4.4 The lab's code

- **STACK.md's reason for Odin, "allocators in place of reference
  counts", hasn't happened** (counted). 34 structs begin `using object:
  Object`; 52 `retain`, 73 `release`, 373 `autorelease` (338 in tests);
  200 `make`, 168 `delete`, 151 `free` by hand; 6 procedures take an
  allocator; no arena from `core:mem` anywhere. Ownership is carried by
  Cocoa naming and 87 comments. `object_new` transmutes `proc(^T)` to
  `proc(^Object)` on the strength of `object` being the first field, with
  no `#assert`. Tessera, written in Odin from the start, has none of this.
  An incremental way through, cheapest first:
  1. the layout `#assert`, and a tracking allocator in `run_tests` (S);
  2. the stateless "classes" as plain values: the three `kinds_*`, and
     farming, perishing and foraging (which §3.2 removes anyway) (S);
  3. per-call objects (`View`, `Menu`, `Snapshot`) on the temporary
     allocator (S–M);
  4. `Proposal_Group` from an arena per boundary, owned by the committer
     (M);
  5. an arena per `World`, per knowledge store, per mind (M);
  6. the systems as owned fields of one struct with a `destroy` (L).
- **Leak checking got weaker with the port.** The Objective-C lab recorded
  "leak-free" per slice; the Odin lab has `make asan`, on Linux only and
  not in CI. One double release has already been found that way
  (lab/PLAN.md:4977). (S, with §4.1.)
- **Five files hold most of the code, each several things.**
  - `agency_agency.odin` (4,658 lines, 152 procedures; `agency_weigh`,
    `agency_decide` and `agency_follow` about 260 lines each): reading
    content, conditions, walking, following methods, the market, talk and
    jobs, weighing, deciding, saves. Cut along those, as
    `agency_deals.odin` already was.
  - `act_actions.odin` (3,976): matching, the menu, then 3,300 lines of
    effects. Per topic until §3.1 shrinks it.
  - `know_knowledge_store.odin`, `_1`, `_2` (6,869): one Objective-C file
    cut by line number ("part 1", then "part 3 of 3").
    `knowledge_perceive` is one procedure of 848 lines. Cut by concern:
    sight, recognition, testimony, interpretation, forgetting, saves.
  - `core_world.odin` (2,802, 165 procedures): tile stocks, the journal,
    records, spatial queries, edges, room air, history, the state hash.
  - `commit_committer.odin` (1,233): 410 of them "air follows terrain",
    with `GasStore` fields by name.
  - `test_tests_1..3.odin` (11,600): one test file cut by line number, so
    a topic's tests straddle files. (M each; mechanical in one Odin
    package.)
- **The layering leaks upward in a few named places.** `World` holds
  caches belonging to bodies, looks, knowledge, agency and the atmosphere
  (`core_world.odin:136-159`). Production code is wired by test fixtures:
  `main.odin`, `play_play.odin` and `watcher.odin` call `test_world` and
  `test_committer`, and 18,000 lines of tests are compiled into the
  binary. A composition file outside `test_` fixes the second; real Odin
  packages would make the layering something the compiler checks. (M)
- **C written in Odin.** 914 C-style loops against 227 range loops; 349
  many-pointers; 173 fixed `u8` buffers; no `or_return`, no tagged unions
  (`Proposal` overloads fields by kind; `Event.amount` doubles as a type
  ID); `realloc` and `grow` shims copied five times each. And **fixed caps
  that skip silently**: `BG_MAX_*` of 8 or 16 at
  `agency_agency.odin:2150, 3931, 1874, 4509`. Convert as files are
  touched; turn the silent caps into errors now. (S for the caps.)
- **Mutable globals** stand in the way of the threading REALITY.md
  decision 8 plans: path-search scratch (`core_path.odin:69-94`), the
  `ranking` condition set around a sort (`agency_agency.odin:563`), the
  autorelease pools, `debug_history`. (S–M)
- **Things that grow without end in a long run** (read, not measured):
  each mind's decision log, the committer's `sources` map, the committer's
  causal record unless switched off. Window them as history is. (S)

### 4.5 Determinism and saves

- **The scenario hashes cover less than they seem to.** The four cistern
  rows have the same run and save hash and no state hash: `main.odin:165`
  sends any `cistern*` name to a run that ignores `save`. An unknown
  `cistern-…` name silently runs the reversed variant. The village's save
  is `save(world, c, nil)`: no saved systems, so no knowledge, agency,
  bodies or air. `world_state_hash` leaves out knowledge stores and
  motivation stores. Agents' minds are pinned only through what they have
  done to the world so far. (S–M: a `hash` procedure per saved system,
  folded in.)
- **The hashes change with nearly every change, and can't say where.**
  `scenario-hashes.txt` changed in 33 of the 49 git commits since the
  port; the village row in every one of the last 18 that touched it.
  Adding a field to `#Agent` rehashes every scenario ("their runs differ
  only in those fields" is the commit message's claim, checked by nobody).
  The check is a `diff` of 16-digit digests, so a mismatch says only
  "different"; stderr is hashed too. As an equality check across platforms
  it is excellent; as a regression check it relies on the author's eye.
  Leave zero and default values out of dumps (so adding a field is
  hash-neutral), hash by section, and keep the small scenarios' printed
  text as goldens that diff. (M)
- **Saves have one version and no migration.** `BG_SAVE_VERSION :: 1`,
  compared for equality, though the format has since gained terrain,
  anchors, leases, history and digests. Enums are written as ordinals, so
  reordering one corrupts old saves quietly. Each system writes its own
  text by hand (`agency_restore_saved_state` is 182 lines, knowledge's
  246), and each caller lists the systems to save. No test saves the
  village mid-week, restores it, and finishes with the same state hash;
  ARCHITECTURE.md's "a rebuilt world produces the same next step" is
  unproven at the size that matters. (M)
- **"What printf printed" is a rule that has outlived its reason.** The
  formatting test pinned parity with the Objective-C lab at the port;
  every hash has been regenerated many times since. Keep the test as a pin
  on Odin's `fmt`, drop the rule. (S)

### 4.6 Tests

- 152 tests, all registered in a table kept by hand, about 1,900 checks:
  broad. But **no fixture**: 147 `test_world(`, 134
  `scheduler_init_with_world`, 98 `activities_with_world`, and the same
  ten lines of wiring in each agency test. The same helper exists under
  three names (`test_own`, `test_own_it`, `village_own`); "the referent of
  an entity" is written eight times. A `Fixture` and §3.6's worlds in
  content would remove most of it. (M)
- 209 assertions match printed text with literal entity IDs
  (`test_tests_1.odin:627`); they break when anything earlier creates an
  entity.
- **No generative tests for the simulation**, where Triangle has property
  tests and fuzzing. The committer's validation is a ready oracle: random
  legal actions on small worlds, checking conservation of mass and count,
  that a rolled-back journal is a no-op, that save, restore and hash
  agree, that a replay agrees. (M, and high value.)
- `make check` ran the village week three times (test, run, save) for 103
  of its 128 seconds when last measured (lab/PLAN.md:5170); take both
  hashes from one run. The three-week run is red outside CI, and the docs
  disagree on by how much (4, 6, 7 or 8 failures). (S)

### 4.7 Performance

PERFORMANCE.md's header lists decisions 1, 2, 5 and 6 as built; its body
also marks 7 and 8. Not built:

- **Decision 3, agency parses once.** `agency_match_supposing` still
  prints and re-parses (`agency_agency.odin:1262-1279`), behind a memo
  cleared wholesale at 4,096 entries. §3.11's builder removes the cause.
- **Decision 4, recognition indexed by seen kind**: percept × referent
  loops at `know_knowledge_2.odin:231-249`.
- Also read: `agency_concerns_of` scans every mind and re-reads each
  goal's `concerns` from content per perceiving agent (quadratic when all
  perceive); every agent is scanned when any gas store changes; 210
  `world_kind_named(w, "Name")` and 106 field lookups by string at
  runtime behind a 64-entry cache; the closed-form domains rescan their
  whole component store for each horizon.

### 4.8 Docs and planning

All 269 git commits are by one author, 267 with an AI co-author: the docs
and AGENTS.md are the project's working memory, which raises the cost of
their drift.

- **Status lines that no longer hold.** DESIGN.md: "an initial design
  proposal, not an implemented architecture". ACTIONS, AGENCY, COMPONENTS,
  DOMAIN_SIMULATION, KNOWLEDGE and CONTENT_LANGUAGE all open "Proposal".
  ARCHITECTURE.md's table says of REALITY "nothing built" (steps 1–4
  are), of TESSERA "nothing draws yet", of METHODS "not built", and omits
  VILLAGE and PERFORMANCE. lab/README.md and the head of lab/PLAN.md
  describe the first slice, under mulle-objc. There is no README at the
  root and no reading order. (S)
- **Objective-C residue.** 116 lines in twelve top-level docs name `BG…`
  classes; the "contract" sections of AGENCY and KNOWLEDGE are
  `@protocol` sketches matching neither `protocols.odin` nor the API.
  `institutions/law.tri` cites `BGLawsBroken`; `water/water.tri` cites an
  `effect_fill` that doesn't exist. (S, one sweep.)
- **lab/PLAN.md is a 5,450-line log**, 186 of its 193 sections "After the
  slice: …", changed in 35 of 49 recent commits. Open questions sit in
  thirteen docs, some answered in place. GitHub issues #6–#11 are open
  for slices VILLAGE.md says are built. The five core design docs carry no
  mark of which decisions are built. Call PLAN.md the changelog it is,
  keep one list of open questions, and tag each decision `built
  (test_name)`. (S–M)
- **Raw chat logs at the top**: CHAT.md (105 KB) and tfs_chat.md, which
  nothing cites. INSTITUTIONS.md is 43 lines, untouched since October,
  though laws and permits are in content and code. DETAIL_REGIMES.md is
  honestly marked unbuilt, and §3.1 and §3.2 lean on it.
- **A glossary slip**, which CLAUDE.md asks to be flagged: AGENCY.md says
  "fidelity level" eight times and ARCHITECTURE.md twice, where the
  glossary's table says *detail*.

### 4.9 Tessera, the build, housekeeping

- **Tessera is small and sound, and mostly unused.** `encode_frame`,
  `encode_diff` and `decode`, about 60% of it, are called nowhere in the
  lab: the watcher draws in-process. The raylib backend and the watcher
  are type-checked in CI, never linked or run. `lab play` keeps a second
  renderer of its own. Give the codec a consumer (recording and replaying
  a watcher session) or mark it frozen; link the watcher in CI. (S)
- **The lab doesn't relink when Triangle changes**: the library is an
  order-only prerequisite (`lab/Makefile:43`). The Odin release is pinned
  in two files with no checksum; `components.odin` is generated and
  committed, with drift caught at run time by the content hash, not by
  `make gen && git diff --exit-code` in CI. (S)
- The local branch `agency-scenario-1` is 91 behind `main` and 0 ahead.

## 5. An order of work

**Now** (days; nothing here needs a design decision):

1. CI green, and the lab's gate running: `strndup`, the four files,
   `fmt --check` in `make check`, independent jobs, `make asan` on Linux,
   the installed binary and the version stamp (§4.1).
2. The engine's memory safety and the hash: §4.2 (1), (2), (6), and (9),
   (10) while there. Regression tests for each.
3. Open vocabularies (§3.4): each topic declares its own `#Effect` atom,
   `#Skill`, `#Order`; `#Burden` and `#Sellable` as traits. Content only.
4. Kinds as patterns (§3.3, proposal 1). Content, and the few readers.
5. Fixed caps that skip silently become errors (§4.4).

**Next** (the leverage; each proves itself against existing scenario
hashes):

6. §4.2 (3) and (5), which decide what content can say.
7. Declared effects for the 38 primitive ones, an operation at a time
   (§3.1), with roles read generically.
8. One progression at full detail, retiring farming's, foraging's and
   perishing's domains (§3.2). This is also DETAIL_REGIMES.md's step 1.
9. `@names(family)` and resolving content into handles at load (§3.3,
   §3.11); a builder in place of print-and-parse, which is PERFORMANCE.md
   decision 3.
10. Routines in content, by the path instincts already take (§3.6).
11. A test fixture, and the generative tests (§4.6); the state hash over
    every saved system, and the village saved and restored mid-week
    (§4.5).

**Later** (needs design):

12. Value slots, and general goals with ways from many topics (§3.5,
    §3.8); maintenance goals from believed stocks.
13. Needs and quantities as declarations; rule constants into content
    (§3.7).
14. The market, hiring and deals out of agency's interpreter (§3.9).
15. Worlds as content (§3.6).
16. `load.c` cut along its fourteen lines; one error convention (§4.3).
17. The lab's memory model, steps 3 to 6 (§4.4); the five large files, as
    each is next touched.
18. The docs' status lines and the changelog (§4.8) can go at any time;
    they are cheap and nothing waits on them.

A test of whether this is working: **the next topic adds no Odin outside
its tests.** Brewing (a progression, two declared effects, a way to *have
something to drink* and one to *have coins*) or fishing would do.

## 6. In good shape

So that none of the above is read as a verdict on the whole:

- **Determinism** is designed in and kept: integers only, sorted ties,
  hashes that name content and never number it, IDs from names in the
  engine, no iteration over hash maps, a randomised test that declaration
  order never matters.
- **The engine's testing** is beyond what a prototype of its age usually
  has: property tests of the algebra, source fuzzing, a counting-allocator
  leak check, a comparison against ACE on the English Resource Grammar
  that found a real bug. `lab/content` loads in about 30 ms.
- **Diagnostics** give both locations and often the fix ("declare it once
  on a new common supertype (say #HasEdge)").
- **`triangle fmt`** refuses to write unless tokens and the content hash
  are unchanged.
- **The content's layout**: topics as packages that own their fields, and
  the cut-point header on every file. The headers are accurate, which is
  rare for comments of that kind, and they made this review possible.
- **The glossary** is kept (changed in 33 of the last 49 commits), and
  the commit messages say what changed and why.
- **Performance work is measured**, before and after, with the numbers
  recorded and counters built in.
- **The docs know their own limits.** METHODS.md measured its problem over
  a three-week run before proposing anything; DETAIL_REGIMES.md says
  plainly what Triangle can and cannot compute; the README's "known
  shortcuts" list is honest. Most of §3 is this project's own stated
  intent (decision 9, DETAIL_REGIMES forms 1 and 3, METHODS's open
  question 2) carried through.

## Appendix: reproductions

Scratch content, outside the repository, with `triangle/build/triangle`
(built 2026-11-05).

A package adds an atom to a root enum (§3.4). Without the package's
`#Effect` line this is `conflict at effect: "forage" vs #Effect`:

```cue
// root.tri
#Effect: "take" | "eat"
#Op:     { effect: #Effect }
// topic/t.tri
package topic
#Effect: "forage"
forage: #Op & { effect: "forage" }
```

A name in `text` isn't checked (§3.3); this loads:

```cue
#Goal:   { title: text }
#Method: { goal: text }
g1: #Goal & { title: "x" }
m1: #Method & { goal: "g_typo" }
```

An instance copied by name loses its arithmetic (§4.2 (5)); `derived`
exports `girth: "length"`, `inline` exports `"60mm"`:

```cue
#Box: { w: length, h: length, girth: length }
base:    #Box & { w: $w, h: $h, girth: ($w + $h) * 2 }
derived: base & { w: 10mm, h: 20mm }
inline:  #Box & { w: $w, h: $h, girth: ($w + $h) * 2 } & { w: 10mm, h: 20mm }
```

The content hash ignores attributes (§4.2 (6)); both of these are
`17eb0494cbc992d5`:

```cue
#B: { @component(B)
  size: length @field(content, saved) }
b: #B & { size: >=1mm & <=9mm @vary(mode: 2mm) }
// and the same with @field(content) and @vary(mode: 8mm)
```

A comment brings in the clause prelude (§4.2 (9)):

```cue
// see #Fact in the docs
#Animal: { head: text }
```

Not established by this review: whether `make check` and `make asan` pass
locally today; whether the English Resource Grammar still loads and
matches ACE since packages; whether the village ever reaches a `BG_MAX_*`
cap, a list of 128 items, or 2^32 engine operations in one run; the
memory growth of §4.4's logs; and that `mind_stall` clearing fatigue is
unintended (it follows from the code as read; it was not run).
