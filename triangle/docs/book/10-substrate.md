# 10. Triangle as a substrate for simulation

Bruggadung is a project to make a roguelike with many simulated systems.
The **lab**, in `lab/`, is the simulation laboratory of the project. It
implements the systems in Odin and proves them by scenarios. One scenario
is a village: twelve people and a watch officer, with work, a market and
homes.

This chapter explains how the lab uses Triangle. The aim of the design is
that an author adds a new topic to the simulation with content only, and
with no new code.

The examples are from [lab/content](../../../lab/content). In November 2026
that content was 1,309 types, 812 instances and 51 component kinds.

## The principle

**Content says what is true of the world. Code applies it in a fixed way.**

Each system of the lab applies one sort of Triangle rule. The action system
applies operations. The agency system applies goals and methods. The
knowledge system applies interpretation rules: content that says what an
agent concludes from what it perceives. Each system reads its Triangle
rules from content. No system searches without a limit.

This is the method of a DELPH-IN parser. The parser is fixed. The grammar
is data. A new grammar rule needs no new parser.

For each new feature of the simulation, ask these questions in order:

1. Can content say this with the mechanisms that exist?
2. If not, which general mechanism is missing?

Write a special case in code only when no general mechanism is possible.

## The life of content in the lab

| Step | What occurs | Command or code |
| --- | --- | --- |
| 1. Generate | A tool writes the component structs from the `@component` types | `make gen` writes `lab/src/components.odin` |
| 2. Load | The lab finds each `.tri` file below `lab/content`, sorts the names, and loads them | `tri.load_files` |
| 3. Check | The lab refuses content that does not agree with its code | `world_with_content` |
| 4. Run | The systems read specs and patterns, and make descriptions | The rest of this chapter |

Step 3 has four checks:

- The content hash must be the hash that `components.odin` was generated
  from. If not, the message tells you to run `make gen`.
- Each operation must do something. An operation with no effect and no
  trace is an error. (A **trace** is physical evidence that an event
  leaves.)
- A declared effect must name roles and fields that exist. The parts of a
  declared effect are in a later section of this chapter.
- Each progression must name a component and fields that exist.

These checks find, at the start, mistakes that would give no message
later.

## Components come from content

A type with `@component` is a component kind. Its features are the fields
of a record in the lab.

```cue
#Body: #Placed & {
    @component(Body)
    mass:      mass                    @field(content, saved, proposable, inspect, perceive(touch))
    material:  #Material               @field(content, saved, inspect, perceive(sight))
    // what its material looks like, if not itself (KNOWLEDGE.md §4): the
    // senses report it instead; an analysis reaches beneath it
    surface:   *"natural" | "metal" | "wood" | "flesh" | "paper" @field(content, saved, inspect, appears(material))
    bent:      *false | true           @field(saved, proposable, inspect, perceive(sight))
    toolMarks: *0 | int & >=0 & <=100  @field(saved, proposable, inspect, perceive(sight))
}
```

The generator writes one Odin struct for each component kind, and a table
that describes each field. The lab never writes the list of fields a second
time.

The flags of `@field` control general mechanisms. The engine enforces the
flag `content`. The lab reads the other flags from the table of fields.

| Flag | Effect in November 2026 |
| --- | --- |
| `content` | Content can set the field. The engine enforces this at load |
| `proposable` | An effect can propose a change to the field. The lab refuses a proposal to a field that does not have the flag |
| `perceive(sight)` | The field is in the description of what an agent perceives. The lab tests only that the flag is there. It does not test which sense the flag names |
| `appears(material)` | The field says what a different field looks like. The senses report it in place of that field |
| `saved` | The intent is that the lab saves the field. The lab does not test this flag: a save contains each field of each component |
| `inspect` | The intent is that tools for developers show the field. The lab tests it in one place: a description for developers and tests that includes fields which an agent cannot perceive |

Because of the flags and the table of fields, a new field needs no code to
be saved, proposed or perceived. The author writes the field and its
flags, and the general mechanisms apply.

An entity type conjoins component types. The blueprint `ale` has the type
`#Stack & #Food`. Thus ale has the components Body, Stack, Food and
Becoming.

## Entities come from blueprints

To make an entity, the lab calls `tri.construct` with the name of a
blueprint and a seed. The engine returns a feature structure in which each
field is concrete. The lab copies the values into the component records.

The same blueprint and the same seed give the same entity. In the content
of November 2026, variation is small: no blueprint uses `@vary`. Most
variation comes from an atom that is an enum. The blueprint `vat` says
`material: "wood"`, and wood is oak or birch, so each vat is one of the
two.

## Two sources of descriptions

The engine matches patterns against descriptions. The lab has two sources
of descriptions, and the difference is important.

| Source | What it contains | Who uses it |
| --- | --- | --- |
| The **truth projection** | The real values of the components of an entity | The lab, when it resolves what an action does. Never the reasoning of an agent |
| The **knowledge view** | What one agent believes: only what it perceived, as it remembers it | The action menu, goals, methods |

There is one matcher for both. A description from the knowledge view is
only more general. A field that the agent cannot perceive stays open. An
open field makes a match *unknown*, and unknown never forbids.

Thus an agent cannot use what it does not know. The lab does not give an
agent the truth and then hide parts of it. It gives the agent a description
that does not contain what the agent does not know.

In the knowledge system, an agent does not know entities. It knows
**referents**. A referent is what the agent takes to be one entity, from
what it has perceived. Two referents can be one entity, and the agent can
be wrong about that.

## Operations and the action menu

An operation is a pattern over the descriptions of the entities that fill
its roles.

```cue
// Eat what the actor holds: a while, with the hands, easily put down. It
// is gone (of a stack, one of it), and the actor is fed by what it gives.
eat: #Operation & {
    duration:  60s
    uses:      ["hands"]
    attention: 5
    roles: {
        actor: #Agent & { id: $a }
        item:  #Food & { id: $i, nourishment: $n, material: "food", place: #Held & { by: $a } }
    }
    changes:  [{ changedOf: "actor", changed: "satiety", changedBy: $n }]
    consumes: [{ consumed: $i, portion: 1, because: "eaten" }]
} @family(operations)
```

The `roles` are the requirements. The item is food, made of food, in a hand
of the actor. The tag `$a` says that the holder of the item is the actor.

To make the **action menu** of an actor, the lab does these steps for each
operation and each set of entities in reach:

1. It writes Triangle source for those entities, from what the actor
   perceives.
2. It makes a description from that source (`tri.value`).
3. It matches the operation against the description
   (`tri.match_instance`).
4. It excludes the operation only if the result is *incompatible*.

An operation with an unknown match stays on the menu. The agent can try it.
The truth decides if the action succeeds.

## The effect of an operation

An operation has an effect: what it changes. Content states the effect in
one of two ways.

- A **declared effect** is stated in the operation, as data.
- A **named effect** is the name of a procedure in the lab:
  `effect: "walk"`.

Most operations have a declared effect. One procedure applies all of them
(`lab/src/act_declared.odin`). The parts of a declared effect are:

| Field | Meaning |
| --- | --- |
| `after` | The roles as the effect leaves them. The effect sets each field that `after` states |
| `moves` | An entity goes into a place: a tile, a container, a hand |
| `makes` | The lab constructs a new entity from a blueprint |
| `consumes` | The lab destroys an entity, or a portion of a stack |
| `emits` | Events that agents can perceive |
| `changes` | A field of a role becomes more or less by an amount, in the bounds of its type |

### How the procedure applies it

To resolve a declared effect is one unification.

1. The lab writes the truth projection of the entities that fill the roles.
2. It unifies the pattern of the operation with that description
   (`tri.unify`). For an operation with variants, it uses the first variant
   that unifies.
3. If unification fails, a requirement does not hold. The path of the
   failure is the reason, and the action fails.
4. If unification succeeds, the tags carried the real values into `after`,
   `moves`, and the other parts. The lab reads each concrete value there
   and makes a **proposal** from it.

A proposal is a change that an effect asks for. The lab commits the
proposals of one effect together, or none of them.

For `eat`, the tag `$n` is the nourishment of the real food. After the
unification, `changes` holds that number. The lab proposes that the satiety
of the actor becomes that much more.

Arithmetic works in the same step. The operation that takes one handful
from a patch says, in part:

```cue
forage: #Operation & {
    ...
    roles: {
        ...
        item:  #Patch & { handfuls: $h & >=1, yields: $y }
    }
    ...
    after: { item: #Patch & { handfuls: $h - 1 } }
} @family(operations)
```

The pattern brings its arithmetic into the unification
([chapter 5](05-computed-values.md)). The lab reads the new number from the
result. The lab has no code that subtracts a handful.

### The lab uses the requirements two times

The lab uses the same `roles` two times, against the two sources:

- for the menu, against what the actor perceives: a match with three
  results
- to resolve the action, against the truth: a unification that succeeds or
  fails

Thus an agent can try an action that fails. It believed that the nut was
19 mm. The nut was not.

## Knowledge

What an agent knows about a referent is a description. The knowledge system
uses the three operations of [chapter 1](01-introduction.md):

| Need | Operation |
| --- | --- |
| A new percept of a known referent | Unification. The result is a more specific description |
| A percept that contradicts what is known | `tri.conflicts` gives each path. The system weighs them |
| Memory decay | `tri.generalize`: an atom goes up to its parent, a number becomes wider |
| An entity seen from far | `tri.generalize` too: the further, the more general |

The hierarchy of atoms decides how knowledge decays. The colours of the lab
are:

```cue
#Colour:  "dark" | "light" | "bright"
"dark":   "black" | "grey" | "brown" | "navy"
"light":  "white" | "beige"
"bright": "red" | "yellow" | "blue" | "green" | "purple" | "orange"
```

An agent that saw a grey coat remembers later only a dark coat. Then a
black coat can match its memory. The agent can take one person for another.
This mistake comes from the model, and it needs no special code.

## Agency

A goal and a method are patterns over the knowledge view.

```cue
eat_what_i_have: #Method & {
    title: "eat what I have"
    goal:  "eat_when_hungry"
    rank:  1
    pre: {
        find:  ["food"]
        match: #Supper & {
            me:   #Agent & { id: $me }
            food: #Food & #Body & { material: "food", raw: false, place: #Held & { by: $me } }
        }
    }
    steps: [#Do & { op: "eat", object: "food" }]
} @family(methods)
```

`#Supper` is a **goal frame**: a feature structure with a slot for the
agent (`me`) and a slot for each entity that the goal is about (`food`).
The condition `pre` says which slots to bind (`find`) and what must be true
of them (`match`). The agency system binds each slot to a referent that the
agent believes present. Then it matches.

The three results have these meanings for a method:

- Entailed: the method applies.
- Incompatible: the method does not apply.
- Unknown: the method does not apply now. If the method names a goal in
  `onUnknown`, the agent takes that goal first: to find out.

## Families as tables

The lab uses a family as a table of declarations of one sort. The code asks
for the family, reads its members in order, and reads fields from each
pattern. Some families of the lab:

| Family | Members | Read by |
| --- | --- | --- |
| `operations` | Operations on the action menu | The action system |
| `goals`, `methods`, `routines` | What agents want, how they get it, and when | The agency system |
| `rules` | Interpretation rules | The knowledge system |
| `seen` | Which kinds of entity an agent can tell by sight | Perception |
| `looks`, `glyphs` | What to draw for each kind of entity | The viewers |
| `progressions` | What an entity does by itself as time passes | The progressions domain |
| `values`, `prices` | The value of entities to an agent, and their prices in coins | Agency, the market |
| `terrain` | The terrain kinds | The terrain system |

To add a member, an author writes one declaration. No list in the code
changes. [Chapter 11](11-modelling-practices.md) calls this practice
"declare by kind".

## Time

Some states change as time passes: a crop ripens, food spoils, a stomach
empties. The lab does not step these states on each tick. It keeps a time,
and computes the state when something reads it.

A **domain** is the part of the lab that owns one sort of state and the
algorithm that changes it. The lab has three mechanisms for slow change.
Content takes a different part in each.

| Mechanism | What content says | What code does |
| --- | --- | --- |
| A **progression** | All of it: the component, the fields, the period | One procedure applies each progression |
| A **becoming** | The fields of `#Becoming`: how long, and what the entity becomes | The perishing domain ends the entity and makes the other, for all that becomes |
| Hunger | The fields of `#Hungry`: the periods | The bodies domain has the formula for this one component |

A progression is the most general:

```cue
// A plot standing sown stands ripe `ripensIn` after its last row was sown.
ripening: #Turn & { progresses: "Plot", turned: "stands", turnedFrom: "sown", turnedTo: "ripe", asOf: "sownAt", period: "ripensIn" }
@family(progressions)
```

The lab has two progressions in November 2026: this one, and the regrowth
of a patch. A new entity that ripens or regrows needs one declaration.

## Levels of detail and cut points

The lab simulates what is near the player at full detail, and what is far
at less detail. There are four levels of detail: full, reduced, abstract
and frozen.

Each content file starts with a header that lists its **cut points**. A
cut point is a place where the content of the file stops and something
different continues: a different level of detail, a different topic, or
code. The header is the place where an author states the limits of the
file.

## Saves

- A save of the lab contains the content hash, so a reader can see which
  content made it.
- The save writes types and fields by name. Thus a lab with changed content
  can still read it.
- A save does not contain specs. The content has them.

## What the lab does not use

The engine has functions that the lab does not call in November 2026,
outside its tests. Do not assume them when you read the code of the lab.

| Engine function | State in the lab |
| --- | --- |
| The index of a family as a filter (`tri_index_candidates`), and the quick check | Not used. The menu matches each operation. The lab uses a family only as a table |
| Definite clauses (`tri_solve`) | Not used |
| Matching against hypotheses (`tri_match_hypotheses`) | Not used |
| `tri_binding`, `tri_lgg`, `tri_subsumes` | Not used |
| `tri_save`, `tri_restore`, `tri_migrate` | Not used. The lab has its own save format, and keeps what an agent knows as text |

These functions are tested in the engine. They are there for the systems
when they need them.

## What stays in code

Content cannot say everything, and should not. These parts stay in the lab:

- the domains: the algorithms for air, heat, water, light
- search on the map: a path, a line of sight
- perception: who perceives which event
- the named effects: `#Effect` in `actions.tri` lists 22 names, such as
  `walk`, `strike` and `shoot`
- how the lab commits proposals, and which proposal wins a conflict

The aim of the work is to make this list shorter.
[EFFECTS.md](../../../EFFECTS.md) gives the progress.

Previous: [9. What Triangle borrows](09-heritage.md).
Next: [11. Practices for reusable models](11-modelling-practices.md)
