# 11. Practices for reusable models

This chapter is a list of ways to model phenomena in Triangle. Other texts
call such ways "design patterns". This book calls them **practices**,
because a pattern is a term of Triangle.

The authors of the content of the lab found each practice while they wrote
that content. Each practice has the same parts: the problem, the practice,
an example from the lab, why it works, and its limit. Where an example is
shortened, `...` shows what is omitted.

The practices have one common aim. A new topic uses the mechanisms that
exist. It does not need a mechanism of its own.

| Group | Practices |
| --- | --- |
| Kinds of entity | 1 to 5 |
| Operations and effects | 6 to 9 |
| Declarations that code reads | 10 to 12 |
| Time | 13 |
| Agents | 14 and 15 |
| Organisation | 16 and 17 |

## Kinds of entity

### 1. One component for one ability

**Problem.** Many kinds of entity share an ability. Food, hides and wort
all become something different as time passes.

**Practice.** Declare the ability as a component kind of its own. A kind of
entity has the ability if its type conjoins that component. The code that
implements the ability asks only for the component.

```cue
#Becoming: {
    @component(Becoming)
    keepsFor:  *0ms | time & >=0ms & <=100d    @field(content, saved, inspect)
    becomesAt: *0ms | time & >=0ms & <=10000d  @field(saved, proposable, inspect)
    becomes:   *"spoiled_food" | text          @field(content, saved, inspect)
    ending:    *"spoiled" | text               @field(content, saved, inspect)
    ...
}

#Spoiled: #Body & #Perishable & { keepsFor: 10d, becomes: "" }
```

`#Perishable` is a type below `#Becoming`. Spoiled food rots away to
nothing in ten days. The code that does this does not refer to spoiled
food. It refers to `#Becoming`.

**Why it works.** An entity type is a conjunction of component types. The
ability goes with the component, not with a list of kinds in the code.

**Limit.** Do not put two abilities in one component. An entity that needs
one then gets the fields of the other.

### 2. A common type above a shared field

**Problem.** Two types need the same field. A feature has only one type
that introduces it.

**Practice.** Declare the field on a small type above both. The type often
has only that one field.

```cue
#Looks:  { look: text }
#OfKind: { kindOf: text }
#Look:   #Looks & #OfKind & { prevails: *0 | int }
#Seen:   #OfKind & {}
```

`#Look` and `#Seen` both say which kind of entity they are about. `kindOf`
is on `#OfKind`, and both inherit it.

**Why it works.** The field has one meaning in all content. Code that reads
`kindOf` works for each type below `#OfKind`.

**Limit.** If the two fields have different meanings, they are different
fields. Give them different names, or put them in different packages.

### 3. An addition to the type of a different topic

**Problem.** A new topic needs a field on a type that a different topic
owns. Brewing needs to know what raw food mashes into. Food belongs to
hunger.

**Practice.** Add the field from the new topic, by the qualified name of
the type.

```cue
package brewing

hunger.#Food: {
    mashesInto: *"" | text @field(content, saved, inspect, perceive(sight))
}
```

**Why it works.** The topic that owns the meaning owns the field. The file
of hunger does not change. If an author removes the brewing topic, the
field goes with it.

**Limit.** Think about what an open field does to a match. A `text` field
can stay open in a blueprint. But then a method that needs
`mashesInto: "wort"` gets *unknown* for each food, not *incompatible*. The
default `""` makes each food that does not mash incompatible.

### 4. A default that means "none"

**Problem.** A field of a blueprint must be concrete or have a range, and
an open field makes a match unknown. Many fields apply to only some
entities.

**Practice.** Give the field a default that means "none": `0ms` for a time,
`""` for text, `false` for a flag.

```cue
keepsWithin: *0ms | time & >=0ms & <=100d    @field(content, saved, inspect)
```

**Why it works.** A blueprint says only what is special about it. The spec
is still complete, and a pattern that tests the field gets a definite
result.

**Limit.** The code must treat the value as "none". Say so in the comment
of the field. Where "none" and zero are different, do not use this
practice: use a different component (practice 1).

### 5. A let for what blueprints share

**Problem.** Some blueprints have the same values for many fields. Grain is
a single portion, and it is also a sack of sixty portions.

**Practice.** Give the shared values a name with `let`. Each blueprint
conjoins the name.

```cue
let raw_grain = { material: "food", raw: true, nourishment: 15, cooking: 35, mashesInto: "wort" }
grain:      #Body & #Food & raw_grain & { mass: 250g }
grain_sack: #Stack & #Food & raw_grain & { unit: "grain", unitMass: 250g, count: 60 }
```

**Why it works.** The two blueprints cannot differ by accident. A `let` is
not a type, so it adds nothing to the hierarchy.

**Limit.** A `let` belongs to its file. If two files need the values, each
file declares the `let`, or the values become defaults of a type.

## Operations and effects

### 6. The roles of an operation are a type

**Problem.** Operations have different roles. Some have an item. Some have
an item and a destination.

**Practice.** Declare the sets of roles as a small hierarchy. The type of a
feature structure is the most general type that has all its features. Thus
an operation gets the correct type of roles from the roles that it writes.

```cue
#Bound:        {}
#Roles:        #Bound & { actor: #Agent }
#ItemRoles:    #Roles & { item: #Body }
#PlacingRoles: #ItemRoles & { destination: #Body }
```

An operation that writes `actor` and `item` has roles of the type
`#ItemRoles`. The author does not name the type.

**Why it works.** Code and content can ask "does this operation have an
item?" by the type of its roles.

**Limit.** A new role needs a new type in this hierarchy. Add the type at
the root, because the roles are vocabulary for all topics.

### 7. Before and after in one pattern

**Problem.** An operation changes the entities that fill its roles. The new
value often depends on the old value.

**Practice.** State the requirements in `roles`. State the result in
`after`. Connect the two with tags. Use arithmetic for the new value, and
`math.Clamp` to keep it in bounds.

```cue
forage: #Operation & {
    duration: 10min
    uses:     ["hands"]
    roles: {
        actor: #Agent & { id: $a }
        item:  #Patch & { handfuls: $h & >=1, yields: $y }
    }
    makes: [{ blueprint: $y, at: #Held & { by: $a }, called: "a handful" }]
    after: { item: #Patch & { handfuls: $h - 1 } }
} @family(operations)
```

**Why it works.** One unification with the truth projection checks the
requirements and computes the result ([chapter 10](10-substrate.md)). The
requirement `>=1` and the result `$h - 1` cannot disagree, because they are
about one node.

**Limit.** Put all that the operation needs into one description. The
arithmetic does not go into a second unification.

### 8. Small entries in lists, applied by one procedure

**Problem.** Effects are of a few sorts: an entity moves, an entity is
made, an entity is destroyed, an event occurs. A procedure for each
operation repeats the same code.

**Practice.** Give each sort of effect a small type. An operation has lists
of entries of those types. One procedure applies each sort.

```cue
#Moves: #OfSome & { moved: ref, into: #Place, passes: bool, lends: bool, until: time }

give: #Operation & {
    roles: {
        actor:       #Agent & { id: $a }
        item:        #Body & { id: $i, place: #Held & { by: $a } }
        destination: #Agent & { id: $d, freeHands: >=1 }
    }
    moves: [{ moved: $i, into: #Held & { by: $d }, passes: true }]
} @family(operations)
```

`give` has one entry in `moves`. The item goes into a hand of the
destination, and its ownership passes. The lab has no procedure for giving.

**Why it works.** The entries are data. The procedure that applies a move
is correct for each operation that moves something. A constraint such as
"mass is conserved" is in one place.

**Limit.** When an effect does not agree with the entry types, do not
change their meaning for one operation. Keep a named effect, or add an
entry type that many operations can use.

### 9. A type above operations that are the same in meaning

**Problem.** Some operations differ in how they proceed, but other content
must treat them as one. To take an item is instant. To take it up with care
takes one second. A law forbids both.

**Practice.** Write one operation for each case. Put what they share in a
type, and make each an instance of it. Other content, and code, refer to
the type.

```cue
#Taking: #Operation & { roles: { actor: #Agent, item: #Body } }

take:    #Taking & { contest: "quickness", ... }
take_up: #Taking & { contest: "quickness", duration: 1s, uses: ["hands"], hard: "fail", ... }

theft_law: #Law & { forbids: "#Taking", wrong: "anothers", brings: "arrest", weighs: 40, common: true }
```

The law forbids the type. Each operation below `#Taking` is a taking,
including one that a new topic adds later. In the same way, each operation
below `#Resting` is a rest, and the lab gives it a watch on the air.

The design doc for effects decided the same for two cases that change
different amounts: to cook a portion of a stack and to cook all of it are
two operations.

**Why it works.** Each operation stays a simple pattern. The agent sees two
entries on the menu and can choose. The type is the place where the common
meaning is.

**Limit.** For alternatives that differ only in a requirement, a
disjunction in the operation is simpler: `place: #Inside | #OnTile`. The
engine makes variants.

## Declarations that code reads

### 10. Declare by kind, in a family

**Problem.** Code needs a fact about each kind of entity: can an agent tell
it by sight, what to draw for it, how long a feature lasts. A table in the
code must change for each new kind.

**Practice.** State each fact as a small instance that names the kind. Put
the instances in a family. The code reads the family.

```cue
vat_seen: #Seen & { kindOf: "#Vat" } @family(seen)

body_look:  #Look & { kindOf: "#Body", look: "body", prevails: -1 } @family(looks)
agent_look: #Look & { kindOf: "#Agent", look: "agent", prevails: 3 } @family(looks)

coat_persists: #Persistence & { feature: "coat", persists: 1d } @family(persistence)
```

The author writes the declaration next to the kind, in the file of its
topic. The code finds the type with `tri_type_named`, and tests an entity
with `tri_subtype`. Where more than one declaration applies, the most
specific kind wins, or a field such as `prevails` decides.

**Why it works.** A new kind brings its own facts. No central list exists.
A kind with no declaration gets the declaration of the kind above it.

**Limit.** This practice is for facts about a kind. A value that differs
for each entity is a field of a component.

### 11. A name in text for a late link

**Problem.** A declaration must refer to a blueprint, an operation, a goal
or a field. A reference to an instance copies it, and a copy is not what
the author needs.

**Practice.** Write the name as text. The code finds the declaration when
it needs it.

```cue
#Wort: #Body & #Becoming & { ..., becomes: "sour_wort", within: "#Vat", becomesWithin: "ale", ... }

steps: [#Do & { op: "put_in", object: "work", target: "vat" }]
```

**Why it works.** The link is loose. A method can name an operation of a
different topic. A blueprint can name what it becomes, which can name a
third blueprint.

**Limit.** The Triangle loader does not check that the name exists. This is
the weakest practice in the list. Add a check in the program at load, as
the lab does for progressions and for `changes`. A wrong name must be an
error at the start.

### 12. A table of points for a curve

**Problem.** A relation between two numbers is not a straight line: how
much attention a body loses as its reserves fall.

**Practice.** Write the curve as a list of points. One procedure reads all
curves: straight between the points, constant beyond the ends.

```cue
#Point:    { input: int, output: int }
#Weakness: { weakens: "attention" | "pace" | "perception" | "grip", lost: [...#Point] }

weak_attention: #Weakness & { weakens: "attention",
                              lost: [{ input: 0, output: 50 }, { input: 40, output: 25 }, { input: 80, output: 0 }] } @family(weakness)
```

**Why it works.** An author changes the behaviour with numbers. The numbers
are whole, so each machine computes the same result.

**Limit.** A curve has one input. A relation with two inputs needs two
curves, or code.

## Time

### 13. A time, not a step

**Problem.** Many states change slowly: growth, spoiling, hunger. To step
each of them on each tick is costly. It also fails when the lab does not
simulate a place for some time.

**Practice.** Keep the time at which the state was last known, and the
period of the change. Compute the state when something reads it. Put the
period in a field, so that each blueprint has its own.

```cue
#Patch: #Body & {
    @component(Patch)
    handfuls:  *0 | int & >=0 & <=100        @field(content, saved, proposable, inspect, perceive(sight))
    most:      *3 | int & >=1 & <=100        @field(content, saved, inspect)
    regrowsIn: *1d | time & >=1s & <=1000d   @field(content, saved, inspect)
    grewAt:    *0ms | time & >=0ms & <=10000d @field(content, saved, proposable, inspect)
    yields:    text                          @field(content, saved, inspect)
}

regrowth: #Rate & { progresses: "Patch", rises: "handfuls", upTo: "most", asOf: "grewAt", period: "regrowsIn" }
@family(progressions)
```

`regrowth` is a **progression**. It says that the `handfuls` of a patch
rise by one each period, up to the field `most`. A bramble sets `regrowsIn`
to one day, and a hazel to two days.

The lab has three forms of this practice, and content does a different
part of each ([chapter 10](10-substrate.md)):

- A progression is declared completely. It needs no code.
- A becoming (practice 1) sets fields. The perishing domain does the change
  for all entities that become.
- Hunger sets fields. Its formula is code for that one component.

**Why it works.** The result does not depend on how often the lab reads the
state. A plot that is frozen for a week is correct when the player comes
back.

**Limit.** The change must have a closed form. A change that depends on
many other states at each moment needs a domain in code.

## Agents

### 14. Goal frames with slots

**Problem.** A goal and its methods are about the same entities: the food,
the stove, the larder. Each must bind them, and a subgoal must get the
bindings.

**Practice.** Declare a **goal frame**: a type with a slot for each entity.
A goal and a method both match against the goal frame. Declare a slot that
two goal frames share on a type above both.

```cue
#Frame:   { me: #Agent }
#Warming: #Frame & { stove: #Body }
#Brewing: #Warming & { vat: #Body, store: #Body, work: #Body }

set_it_to_work: #Method & {
    title: "set it to work"
    goal:  "brew_on"
    rank:  1
    pre: {
        find:  ["work", "vat"]
        match: #Brewing & { me: #Agent & { id: $me }, work: #Wort & { place: #Held & { by: $me } }, vat: #Vat }
    }
    steps: [#Do & { op: "put_in", object: "work", target: "vat" }]
} @family(methods)
```

`#Brewing` is below `#Warming`, so it has the slot `stove`. A subgoal that
lights the stove uses the goal frame `#Warming`. The binding of `stove`
goes from the goal to the subgoal, because it is the same feature.

**Why it works.** The condition is an ordinary pattern. Tags relate the
slots: the wort is in the hand of `me`. The three results of a match apply:
an unknown condition is something to find out.

**Limit.** A method matches only what the agent perceives. A field that the
method tests must have a `perceive` flag.

### 15. A type for each sort of condition

**Problem.** Most goals are done when a pattern holds. Some are done in a
different way: when the agent did an operation, when it looked somewhere,
or when nothing matches.

**Practice.** Make each sort of condition a type below `#Condition`. A goal
chooses the sort by the type of its `done`.

```cue
#Condition: { find: [...text], match: #Frame }
#Looked:    #Condition & { looked: text }
#Did:       #Condition & { did: text, lately: time }
#None:      #Condition & { none: true }

eat_when_hungry: #Goal & { ..., done: #Did & { did: "eat" }, ... }
vat_seen_to:     #Goal & { title: "see to the vat", done: #Looked & { looked: "vat" } } @family(goals)
```

`#None` holds when no referent that the agent believes in matches. The goal
"put the ale by" uses it: no ale is in the vat, and none is in hand.

**Why it works.** The agency system has one procedure for each sort of
condition. A goal of a new topic uses a sort that exists.

**Limit.** A new sort of condition needs code in the agency system.

## Organisation

### 16. A topic is a directory and a package

**Problem.** One topic crosses many systems. Hunger is a field of the body,
a feeling, a goal, methods, an operation, and food.

**Practice.** Put all content of one topic in one directory. Make the
directory a package. The root contains only the vocabulary that each topic
is written in.

```text
lab/content/actions.tri          the root: what an operation is
lab/content/hunger/body.tri      package hunger: the stomach
lab/content/hunger/eating.tri    package hunger: food, and the operation eat
```

**Why it works.** A reader finds all of a topic in one place. Two topics
can use the same field name. A topic refers to the root and to other
topics. The root never refers to a topic.

**Limit.** There is one level of directories. A topic that becomes large
divides into files, not into directories below it.

### 17. A header that states the limits

**Problem.** Content does not say everything. Some behaviour is in code.
Some changes at a lower level of detail. A reader cannot see this in the
declarations.

**Practice.** Start each file with a header that lists its **cut points**:
each place where the content stops and something different continues.

```cue
// Hunger, eating: wanting to eat, the ways to, the eat operation, and food
// ...
// Cut points:
// - full:     felt hunger above 40 raises eating something, ...
// ...
// - frozen:   it doesn't decide, so it doesn't eat; an eat under way waits.
// ...
// - perishing: how long food keeps, and when it spoils, are perishing's
//             fields on #Food (perishing/). ...
// - code:     none: eating is declared. ...
```

**Why it works.** The header states what the content does not do. "code:
none" is a claim that a reader can check. A change that moves a cut point
changes the header in the same commit.

**Limit.** A header can become wrong. A reviewer must read it with each
change.

## A short list of mistakes

| Mistake | Better |
| --- | --- |
| A list of kinds in the code | Declare by kind, in a family (practice 10) |
| A field on a base type that only some entities use | A component for the ability (practice 1) |
| A procedure for one operation | A declared effect (practices 7 and 8) |
| A counter that code steps on each tick | A time, not a step (practice 13) |
| The same field name declared on two types | A common type above (practice 2), or two packages |
| One operation with a special case that the reader cannot see | Two operations and a type (practice 9) |
| A name in text that nothing checks | A check at load (practice 11) |

Previous: [10. Triangle as a substrate for simulation](10-substrate.md).
Next: [12. A worked example: brewing](12-worked-example.md)
