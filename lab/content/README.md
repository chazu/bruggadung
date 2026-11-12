# Content: how it is laid out

## Status and scope

The rule for arranging the lab's Triangle content: what goes at the root,
what goes in a topic's directory, and the header every content file starts
with. It applies to all content, and to every agent and person adding to it.

## The rule

1. **A topic's content lives in one directory, at every level of detail.**
   A **topic** is one subject of the content that crosses systems: hunger
   is a body field, a felt need, a goal and its methods, an operation and
   the food it eats. Everything about it goes in its directory: its fields,
   operations, goals, methods, frames, rules, claims and blueprints, and,
   as DETAIL_REGIMES.md is built, its regimes and progressions. What it
   does at full, reduced, abstract and frozen detail is read in one place.
2. **The root holds the vocabulary, and only that.** The `.tri` files at
   the root are what every topic is written in, one file per system:
   `things.tri` (components), `actions.tri`, `activities.tri`,
   `agency.tri`, `knowledge.tri`, `reality.tri`. Something goes at the root
   only when it belongs to a system as a whole. The root never refers to a
   topic's declarations. A topic may refer to the root and to other topics.
3. **Every file starts with its header: what it holds, and its cut
   points.** A **cut point** is where the file's content stops and
   something else takes over:
   - **a level of detail**: what of the topic changes or stops at reduced,
     abstract and frozen detail, and what stands in for it. A line that is
     the same at several levels names them together. A topic with nothing
     of its own at some level says so, and names what does apply
     (`reality.tri`'s cut points, for agents).
   - **another topic**: what crosses between them, the field or effect
     through which they meet, named by its file.
   - **code**: what the code does that the content doesn't say: the effect
     function, the domain, a constant that isn't in content yet.

   The header comes before anything else in the file, so it is the first
   thing read. When a change moves a cut point, it updates the header in
   the same change.
4. **A declaration goes with the topic whose meaning it carries.**
   - A field goes with the topic that sets it, added to the root's
     component kind from the topic's directory: work's `hires` is
     `#Agent: { hires: ... }` in `work/work.tri`. A topic whose fields only
     some things carry declares a component of its own (hunger's `#Hungry`,
     in `hunger/body.tri`). A field that several
     topics set (`fatigue`: effort, rest, going without) stays at the root.
   - A frame goes with its goals.
   - A claim (`#Grievance`) goes with the topic it is about. The shapes all
     claims share (`#Utterance`, `#Telling`) go at the root.
   - A scenario's blueprints, its cast and props, go with the topic the
     scenario is about.
5. **One level of topic directories.** A topic doesn't nest inside
   another. A topic that grows splits into files by part, each with its own
   header (`hunger/body.tri`, `hunger/eating.tri`), not into
   subdirectories. The tools find the **content root** as the directory
   above a topic's directory, and the root holds `.tri` files of its own.
6. **Each topic directory is a package** named for it: every file in it
   begins, after its header, `package <topic>` (CONTENT_LANGUAGE.md decision
   12). So a topic owns its fields: farming's `larder` and cooking's are
   two, and neither topic edits the other's to have one. A name or label
   is written plainly; it is qualified (`cooking.#Food`, `cooking.larder:`)
   only where two packages have it and the type it is written against
   doesn't say which.
   - Adding to a root type is declaring it in the topic's file, as §4 says
     (`#Agent: { hires: ... }` in work/); adding to another topic's type
     names it qualified (`hunger.#Food: { raw: ... }` in cooking/). Either
     way the fields added are the topic's.
   - The root's files declare no package: they are the vocabulary.
   - Declaration order still never matters (§3), and moving a declaration
     into a package renumbers nothing. A `let` is the file's own, so a file
     that uses one (`person`) declares it.

## The header

```
// Hunger, eating: wanting to eat, the ways to, the eat operation, and food
// (AGENCY.md §6, Scenario 2, decision 16).
//
// Cut points:
// - full:     felt hunger above 40 raises eating something, ...
// - reduced:  the same, decided on the cadence's beat; ...
// - abstract: as reduced. How hunger and food work below reduced is open
//             (DETAIL_REGIMES.md).
// - frozen:   it doesn't decide, so it doesn't eat; ...
// - body:     eating nourishes the eater by the food's `nourishment`: the
//             body's code raises its satiety (body.tri). ...
// - code:     effect_eat (src/act_actions.odin) destroys the food and asks
//             the body to be nourished (bodies_nourish, domains_bodies.odin).
```

The title line names the topic, the part of it the file holds, and the
design docs it comes from. `Cut points:` follows, one `- name:` item to a
cut: the levels of detail first, then other topics, then code.

## The topics

| Directory | What it holds |
| --- | --- |
| `air/` | regions of air, doors, what breathes, stuffiness |
| `bonds/` | loyalty, from kinship, friendship and employment |
| `fastening/` | nuts and spanners; tightening a nut of uncertain size |
| `harm/` | striking and being struck: hitting back, getting clear |
| `heat/` | stoves and fuel, the heat of solids, cold |
| `home/` | beds, worksites, and the day's commitments: to work, home, to bed |
| `hunger/` | satiety and reserves (`body.tri`); what going without weakens (`weakness.tri`); eating and food's nourishment (`eating.tri`) |
| `cooking/` | raw food and meals, the larder, cooking at a lit stove, and the ways from a larder to a meal (`cooking.tri`) |
| `perishing/` | what becomes something else when its time comes (`#Becoming`); perishable food: how long it keeps, when it spoils, and spoiled food (`perishing.tri`) |
| `tanning/` | the tan pit, laying a hide in the tan, leather, and dressing hides (`tanning.tri`) |
| `farming/` | plots (areas) and their crops, seed kept back, sowing and harvesting a row at a time, ripening in closed form (`farming.tri`) |
| `hunting/` | deer and hares, their instincts and their wariness (`animals.tri`); the hunter, the bow, lying in wait and the shot (`hunting.tri`); carcasses and butchering (`butchering.tri`) |
| `firewood/` | trees, felling, bucking and splitting with an axe, the woodpile, stoking a stove (`firewood.tri`) |
| `institutions/` | laws and the watch (`law.tri`); content, copies, seals and permits (`permits.tri`) |
| `light/` | daylight and lamps |
| `looks/` | themes: what `lab play`'s map (`text.tri`) and the watcher (`tiles.tri`) draw for each look |
| `machines/` | latent assembly, wear and servicing (`latent.tri`); the pump and its repair (`pump.tri`) |
| `money/` | getting money: borrowing, taking; a loan repaid (`money.tri`); coins, the coffer, and what goods are worth in coins (`coins.tri`) |
| `carrying/` | packs (a backpack worn, a basket held), their loads, the burden that slows a walk, stowing, taking and returning a household's pack; and handling, the goals every topic uses to take a thing in hand where it goes (`carrying.tri`) |
| `market/` | stalls and their price boards, keeping a stall, buying to stock a household, the sale (`market.tri`) |
| `nails/` | nail stacks, wedging a lock, finding nails, putting them away |
| `promises/` | delivering: what a promise commits to |
| `reservations/` | a soft claim, its tag, respecting it |
| `rest/` | tiredness, and resting it off |
| `sawing/` | a log sawn through, its partial cut, its grading |
| `talk/` | utterances, accounts, a lie; records written and read |
| `terrain/` | terrain kinds, and the maps (`maps/`, brought in by `@embed`) |
| `traces/` | trace kinds, what is read from them, a disturbance investigated |
| `village/` | the village: its map, its villagers, their beds, larders, woodpiles and worksites |
| `valves/` | levers, wrenches and pipes; turning a seized valve |
| `water/` | stores and taps, and drawing from them |
| `work/` | employment: asking for work, hiring, a job, the wage |

## Tools

- The lab loads every `.tri` beneath `content/`, topic directories
  included (`load_content`, `src/test_test.odin`).
- `make gen` generates `src/components.odin` from all of them.
- `triangle check content` loads a directory with its subdirectories.
  Opened in the editor, a file in a topic directory loads with its content
  root, so the language server sees the root's types.
