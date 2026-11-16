# 12. A worked example: brewing

This chapter reads one topic of the lab from start to end. The topic is
brewing. Its author wrote it as a test of the design: *can a new topic add
no code?* It can. The lab has no procedure for brewing. The code of the
lab did not change, apart from the test of the topic and the generated
component structs.

One caution: brewing runs only in that test
(`lab/src/test_brewing.odin`). No scenario puts a vat in the village, so no
villager brews.

The file is
[lab/content/brewing/brewing.tri](../../../lab/content/brewing/brewing.tri).
This chapter shows parts of it. The numbers in brackets are the practices
of [chapter 11](11-modelling-practices.md).

## What the topic says

A brewer takes a portion of grain from the larder. At a lit stove, the
brewer mashes the grain. The result is wort. The brewer puts the wort in a
vat.

After five days in the vat, the wort is ale. Wort that is left out of the
vat becomes sour in two days. Ale is food.

## The header

The file starts with its cut points [17]. The last of them follow. `...`
shows where this chapter omits text.

```cue
...
// - frozen:   nobody brews; wort in a vat becomes ale all the same.
// - becoming: wort is something that becomes (perishing/'s #Becoming), on
//             two courses: left out, it sours; in a vat, it works. The vat
//             does it, as a tan pit does a hide's (tanning/): wort taken
//             out early is wort again, its working lost. Water, malting
//             and yeast are left out.
// - cooking:  grain is cooking/'s, and says what it mashes into there; a
//             stove to mash at is lit as one to cook at is (its
//             `stove_lit`).
// - hunger:   ale is hunger/'s #Food, not raw: drunk as a meal is eaten
//             (eating.tri's eat). There is no thirst.
// - perception: that wort has become ale is seen by looking into the
//             vat, as anything in a container is.
// - village:  nobody in the village brews: no scenario places a vat.
// - code:     none of its own: mashing is declared (a thing made of what
//             is consumed, as heavy: `madeAs`); setting to work is putting in; wort's time in
//             the vat and out of it, and its becoming ale, are the
//             perishing domain's (src/domains_perishing.odin).
```

A reader learns from the header what the topic uses from other topics. The
header also says what the topic does not model: water, malting, yeast and
thirst. And it says that the village does not use the topic.

## The package and the vat

```cue
package brewing

// A vat: where wort works.
#Vat: #Container & {}

vat_seen: #Seen & { kindOf: "#Vat" } @family(seen)

vat: #Vat & { material: "wood", mass: 40kg, capacity: 20 }
```

- The file is in the package `brewing` [16].
- `#Vat` is a container. It adds no fields. It is a new type so that other
  declarations can name it.
- `vat_seen` says that an agent can tell a vat by sight [10].
- `vat` is the blueprint. Its material is `"wood"`, which is an enum, so
  each vat is oak or birch. Its other fields are concrete.

Because a vat is a `#Container`, each operation on containers works on it:
to put in, to take, to look in. The topic writes none of them.

## A field on food

```cue
hunger.#Food: {
    mashesInto: *"" | text @field(content, saved, inspect, perceive(sight))
}
```

Brewing adds a field to the food of a different topic [3]. The default `""`
means that the food does not mash [4]. The value is the name of a blueprint
[11]. Grain says `mashesInto: "wort"` in the cooking topic.

The flag `perceive(sight)` is necessary. A method matches only what the
agent perceives. Without the flag, a brewer could not find grain to mash.

## Wort: an entity that becomes

```cue
#Wort: #Body & #Becoming & {
    keepsFor:      2d
    becomes:       "sour_wort"
    ending:        "soured"
    within:        "#Vat"
    keepsWithin:   5d
    becomesWithin: "ale"
    endingWithin:  "brewed"
}

wort_seen: #Seen & { kindOf: "#Wort" } @family(seen)

// Its mass is the grain's it was mashed of.
wort: #Wort & { material: "food", mass: 1g }
```

Wort has the ability to become something different [1]. The component
`#Becoming` is from the perishing topic. Wort only sets its fields:

- Left out, it keeps two days, then becomes `sour_wort`.
- In a `#Vat`, it keeps five days, then becomes `ale`.

The perishing domain does the work, for all entities that become. It keeps
the time at which each entity becomes. It asks the lab to run it one time,
at the next such time. It does not step [13]. Thus wort becomes ale at
frozen detail too, where no agent decides.

This is the most important point of the example. Fermentation needs no
code, because the lab already had a general mechanism. An entity becomes a
different entity after some time, and the place can change the course.
Tanning uses the same mechanism: a hide in a tan pit becomes leather.

## Ale

```cue
ale: #Stack & #Food & { material: "food", raw: false, nourishment: 20, keepsFor: 20d, unit: "ale", unitMass: 250g, count: 1 }
```

Ale conjoins two abilities [1]. It is a stack, so measures of ale join into
one entity. It is food, so the operation `eat` of the hunger topic applies.
It keeps twenty days, by the same `#Becoming` that food has.

## The operation: mash

```cue
mash: #Operation & {
    duration: 1200s
    uses:     ["hands"]
    roles: {
        actor:       #Agent & { id: $a }
        item:        #Food & #Body & { id: $i, raw: true, mashesInto: $w, mass: $m & 250g, place: #Held & { by: $a } }
        destination: #Combustor & #Body & { lit: true }
    }
    makes:    [{ blueprint: $w, at: #Held & { by: $a }, called: "wort", splitFrom: $i, madeAs: #Body & { mass: $m } }]
    consumes: [{ consumed: $i, because: "mashed" }]
} @family(operations)
```

The operation writes three roles: `actor`, `item` and `destination`. Thus
its roles have the type `#PlacingRoles` [6]. Read the roles as
requirements [7]:

- The item is raw food, 250 g of it, in a hand of the actor.
- The destination is something that burns, and it is lit.

Read the tags as the connections between the requirements and the effect
[7]:

| Tag | From | To |
| --- | --- | --- |
| `$a` | The actor | The holder of the item, and the hand that gets the wort |
| `$i` | The item | What is consumed, and what the wort is split from |
| `$w` | What the item mashes into | The blueprint of what is made |
| `$m` | The mass of the item | The mass of what is made |

The effect is two small entries [8]. `makes` constructs the entity that the
grain mashes into. `consumes` destroys the grain. The wort has the mass of
the grain, so mass is conserved.

The operation does not name wort as a type. It makes what the item
`mashesInto`. A different food that mashes into a different blueprint
needs no new operation.

## The goal and its methods

The brewer has three goals. This is one of them:

```cue
#Brewing: #Warming & { vat: #Body, store: #Body, work: #Body }
...
brew_on: #Goal & {
    title: "keep a brew on"
    done: {
        find:  ["vat", "work"]
        match: #Brewing & { vat: #Vat & { id: $v }, work: #Wort & { place: #Inside & { container: $v } } }
    }
    kept: true
} @family(goals)
```

The goal frame `#Brewing` has three slots of its own [14]. `vat` is the
vat. `store` is the larder, where the brewer keeps grain and ale. `work`
is the grain, the wort or the ale that the brewer handles. The goal is
done when the agent believes that wort is in the vat.
The tag `$v` says that the container of the wort is that vat.

Three methods achieve the goal. Each applies in a different situation:

| Rank | Method | Applies when the brewer believes | Step |
| --- | --- | --- | --- |
| 1 | `set_it_to_work` | It holds wort | Put the wort in the vat |
| 2 | `mash_it` | It holds a portion of raw food that mashes into wort | Light the stove (a subgoal), then mash |
| 3 | `take_grain_to_mash` | Raw food that mashes into wort is in the larder, and a hand is free | Take one portion |

The methods are not a fixed sequence. Each is a pattern over what the
agent knows. Of the methods that apply, the agent does the one with the
best score. The rank decides between equal scores.

After each step, the situation is different, and a different method
applies. If someone takes the wort from the brewer, the brewer starts
again from the grain. The lab has no code for that case.

`mash_it` reuses a goal of a different topic: `stove_lit`, from cooking.
The slot `stove` is on `#Warming`, which both goal frames share, so the
binding goes to the subgoal.

## The routine

```cue
brewing: #Routine & {
    keeps: [{ keep: "vat_seen_to", opens: 16h, closes: 18h, dutyTo: "home", bindings: [{ binding: "vat", own: "#Vat" }] },
            { keep: "ale_put_by", opens: 16h, closes: 18h, dutyTo: "home",
              bindings: [{ binding: "vat", own: "#Vat" }, { binding: "store", own: "#Larder" }] },
            { keep: "brew_on", opens: 16h, closes: 19h, dutyTo: "home",
              bindings: [{ binding: "vat", own: "#Vat" }, { binding: "stove", own: "#Stove" }, { binding: "store", own: "#Larder" }] }]
} @family(routines)
```

A routine says when an agent keeps which goals. This brewer works in the
evening. Each goal is bound to the brewer's own vat, stove and larder.

The first goal is to look into the vat. Its `done` is a condition of the
sort `#Looked` [15]. This goal is necessary.

The brewer does not know that the wort is now ale. The change occurred in
a container. An agent perceives what is in a container only when it looks
in. So the routine makes the brewer look.

## What the topic reused

| Need | Reused from |
| --- | --- |
| A container, and the operations on it | The root: `#Container`, `put_in`, `take`, `look_in` |
| An entity that changes after some time | perishing: `#Becoming` and its domain |
| Food and eating | hunger: `#Food`, `eat` |
| Stacks | The root: `#Stack` |
| A lit stove | cooking and heat: `#Combustor`, the goal `stove_lit` |
| The effect of mashing | The declared effect: `makes`, `consumes` |
| Goals, methods, routines | agency: `#Goal`, `#Method`, `#Routine` |
| Perception of the vat | knowledge: `#Seen` |

## What the example found

The topic added no code, but it found two limits of the general
mechanisms.
[EFFECTS.md](../../../EFFECTS.md) describes both.

1. **A made entity had the mass of its blueprint.** `makes` could not give
   the wort the mass of the grain. The correction was general: `madeAs`
   states fields of what is made. Hiring then used the same field for a
   different purpose.
2. **A method matches only what the agent sees.** An agent does not see on
   a sack that grain mashes. It knows this about grain as a kind. The lab
   has no place yet for what an agent knows about kinds. The content marks
   the field as seen. EFFECTS.md gives this limit as open.

This is the method of the project. A new topic is a test of the mechanisms.
Where the topic needs a special case, improve the mechanism for all topics,
or record the limit in a design doc.

## A procedure for a new topic

1. Write what the topic says, in plain sentences.
2. For each sentence, find the mechanism that exists: a component, a
   declared effect, a progression, a goal with methods.
3. Make a directory and a package for the topic.
4. Write the header with its cut points. Include what the topic does not
   model.
5. Declare the types. Conjoin the components that exist. Add fields to the
   types of other topics where the meaning is yours.
6. Declare the blueprints. Run `triangle check`.
7. Declare the operations with declared effects.
8. Declare the goals, the methods and the routine.
9. Run `triangle fmt`, then `make gen`, then the tests of the lab.
10. If a sentence needs code, stop. Find the general mechanism that is
    missing, and discuss it before you write a special case.

Previous: [11. Practices for reusable models](11-modelling-practices.md).
Back to the [contents](README.md)
