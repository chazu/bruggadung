# A guide to Triangle

This guide teaches Triangle, bruggadung's content language, by building one
small content file: the tools and fasteners of a workshop. It covers how to
write content and what the engine does with it. The rules themselves are in
[REFERENCE.md](REFERENCE.md), embedding the engine is in [API.md](API.md),
and the reasons behind the design are in
[CONTENT_LANGUAGE.md](../../CONTENT_LANGUAGE.md).

Every `cue` block in this guide belongs to the same file. Put them together
and the file loads; a test (`test_docs_guide`) does exactly that, and checks
the results quoted here. Blocks marked `text` show output or mistakes.

If you know CUE, the syntax will look familiar, but the meaning is TDL's:
typed feature structures, closed types, and unification. The differences that
catch people are listed in [Five things that surprise](#five-things-that-surprise).

## 1. Types and fields

A Triangle file is a list of declarations. A name starting with `#` is a
type:

```cue
// Anything with mass and a material.
#Physical: {
    @component(Physical)
    mass:     mass      @field(content, saved)
    material: #Material @field(content, saved)
}

#Sized: {
    @component(Sized)
    size: length @field(content, saved)
}
```

`#Physical` introduces two **features**, `mass` and `material`. Each field
names the type of value it holds: `mass` is the built-in quantity type for
masses, and `#Material` is a type we define next. A feature belongs to the
one type that introduces it; any type below `#Physical` has it too.

The attributes are for the game:

- `@component(Physical)` makes the type a component kind. Its features become
  the component's fields.
- `@field(content, saved)` sets the field's flags. Only fields flagged
  `content` may be set by content; the loader enforces that. The other flags
  pass through to the engine.

The comment directly above `#Physical` is its docstring. Tools read it with
`tri_doc`.

Order never matters in Triangle. `#Physical` uses `#Material` before it is
declared, and all files of a build are read before anything is resolved.

## 2. Enums

A disjunction of strings in a type is an **enum**. Each string becomes an
atom type below it:

```cue
#Material: "steel" | "brass" | "oak" | "ash"
"steel": "mild" | "forged"
```

The second line makes an atom an enum in turn: `"mild"` and `"forged"` are
kinds of `"steel"`. So `material: "steel"` still leaves a choice open between
mild and forged steel. That matters later, when entities are constructed.

## 3. A hierarchy

Types inherit by conjunction. The first conjunct is the **primary parent**,
which memory decay follows (§12):

```cue
#Tool: #Physical & #Sized & {
    @component(Tool)
    wear: *0 | >=0 & <=1000 @field(saved)
}

#Fastener: #Physical & #Sized & {
    @component(Fastener)
    state: "loose" | "tight" @field(content, saved)
}

#Wrench: #Tool
#Nut:    #Fastener
```

`wear: *0 | >=0 & <=1000` says the value lies in that range and defaults to
0. `&` binds tighter than `|`, so this is `*0 | (>=0 & <=1000)`.

`#Wrench: #Tool` declares a new type. Two types with the same features are
still different types: a `#Wrench` is never a `#Nut`.

## 4. A blueprint

A name without `#` is an **instance**. An instance whose type includes a
component is a blueprint:

```cue
wrench_19: #Wrench & {
    material: "steel"
    size:     19mm
    mass:     0.85kg
}
```

At load the engine resolves the blueprint into a **spec**: everything the
types say, unified with what the instance says, with defaults applied. The
spec prints as:

```text
#Wrench & { mass: 850g, material: "steel", size: 19mm, wear: 0 }
```

`0.85kg` became `850g`: masses are counted in whole grams, the **quantum** of
mass. Every quantity converts exactly. `0.8505kg` would be a load error, not a
rounding. `wear` took its default.

Content can only use features that its types introduce. Writing
`colour: "red"` in `wrench_19` would be the error
`unknown feature 'colour'`. Types are closed.

## 5. Defaults and specificity

Mixins can carry defaults:

```cue
#Metal:   #Physical & { material: *"steel" }
#Wooden:  #Physical & { material: *"oak" }
#Handled: #Wooden & { mass: <=2kg }

hammer: #Tool & #Metal & #Handled & { size: 30cm, mass: 1.2kg }
mallet: #Tool & #Handled & #Metal & { material: *"ash", size: 25cm, mass: 0.9kg }
```

A default from a more specific type beats one from a more general type. An
instance's own default beats them all. When defaults come from two types
that are unrelated, neither wins: both are dropped, with a warning, and the
field stays open. That is what happens to `hammer`:

```text
guide.tri:…: warning: hammer: conflicting defaults for material from #Wooden, #Metal; both dropped
```

`hammer`'s material is now a variation point, chosen when an entity is
constructed. `mallet` names its own default, so its material is `"ash"`. The
order of the conjuncts makes no difference to either.

A default never overrides a value. If `mallet` said `material: "oak"`, the
defaults would simply lose.

The developer inspector shows where each value came from:

```text
mallet: #Handled & #Metal & #Tool
  mass: 900g  <- the instance
  material: "ash"  <- default from the instance
  size: 250mm  <- the instance
  wear: 0  <- default from #Tool
```

## 6. Variation

Whatever a blueprint leaves open is variation. When the game constructs an
entity from a blueprint, it makes every open field concrete, drawing from the
entity's seed:

```cue
nut: #Nut & {
    material: "brass" | "steel" @vary(3, 1)
    size:     >=10mm & <=24mm @vary(mode: 13mm)
    mass:     >=5g & <=40g
    state:    *"loose" | "tight"
}
```

- `material` is chosen between the two atoms, brass three times as often as
  steel.
- `size` is drawn from the range, peaked at 13 mm (a triangular distribution).
- `mass` is drawn uniformly from its range.
- `state` defaults to `"loose"`, so it isn't variation.

Four seeds give four nuts:

```text
#Nut & { mass: 39g, material: "brass", size: 12.4mm, state: "loose" }
#Nut & { mass: 9g, material: "brass", size: 12mm, state: "loose" }
#Nut & { mass: 10g, material: "brass", size: 13.1mm, state: "loose" }
#Nut & { mass: 5g, material: "steel", size: 16mm, state: "loose" }
```

The same seed always gives the same entity. Each field draws from its own
seed, made from the entity's seed and the field's path, so adding a field to
a blueprint later leaves the other fields of existing entities alone.

`wrench_19` has variation too: `"steel"` is an enum (§2), so each wrench is
mild or forged steel.

Every field of a blueprint must be concrete or something construction can
draw. (`text` and `ref` fields are the exception: they stay open, to be bound
at runtime.) A field with nothing to choose from, such as `mass: mass` with
no range, is an error:

```text
nut: mass is not concrete and has no bounds to vary within
```

## 7. Alternatives of structures

A disjunction can hold whole structures. In an instance, each alternative
becomes a **variant** of the blueprint:

```cue
spanner: #Wrench & { material: "steel" } &
    ({ size: 13mm, mass: 0.2kg } | { size: 17mm, mass: 0.3kg } | { size: 19mm, mass: 0.35kg }) @vary(1, 2, 1)
```

`spanner` has three variants. Construction picks one, the 17 mm spanner half
the time. A `@vary` after a declaration weights its top-level alternatives.
Putting `*` on one alternative would make it the default, and the spec would
keep only that variant.

In a type, a disjunction of structures becomes part of the hierarchy: one
type for the disjunction, and one subtype for each alternative.

```cue
#Gripped: { grip: { kind: "bare" } | { kind: "wrapped", wraps: int & >=1 & <=6 } }

file_tool: #Tool & #Gripped & { material: "steel", size: 20cm, mass: 0.3kg }
```

A constructed file has either a bare grip or a wrapped one with 1 to 6
wraps. Unification picks an alternative as soon as something decides it: a
description that mentions `wraps`, or a `kind`, is the wrapped alternative.

The types the loader generates for this, and for every other implicit
construct, are listed in the build log (`tri_log_message`). They have long
names, such as `({ kind: "bare" } | { kind: "wrapped", ... })/{ kind: "bare" }`.

## 8. Patterns and tags

Instances without components are **patterns**: operations, rules, methods.
The game matches them against what an agent knows.

```cue
#Roles: { instrument: #Tool, target: #Fastener }

// Turn a tight nut loose with a wrench that fits it.
loosen: #Roles & {
    instrument: #Wrench
    target:     #Nut & { size: .instrument.size, state: "tight" }
} @family(operations) @quickcheck(target.state)

tighten: #Roles & {
    instrument: #Wrench & { size: $s }
    target:     #Nut    & { size: $s, state: "loose" }
} @family(operations)
```

`.instrument.size` is a **reference**: a path from the root of the
declaration it's written in. The two fields are one node, so the wrench and
the nut have the same size, whatever it turns out to be. Information flows
both ways: learn the nut's size and you know the wrench's.

`$s` in `tighten` is a **tag**, the same sharing under a name you choose.
Every `$s` in one top-level declaration is one node. A tag suits a value no
field is the obvious home of, and arithmetic between several fields. The
`$s` in another declaration is a different node.

Matching has three results. Here is `loosen` against four descriptions of a
wrench and a nut (the wrench is always 19 mm):

| What is known about the nut | Result | Residual |
| --- | --- | --- |
| 19 mm, tight | entailed | |
| between 17 and 21 mm, tight | unknown | `target.size` |
| 13 mm | incompatible: `target.size: 19mm vs 13mm` | |
| nothing | unknown | `target.size`, `target.state` |

**Unknown** means the description is too general to decide. Its residual
paths say exactly what to find out, and the game's agents adopt them as goals.
Unknown never excludes an action; only incompatible does.

The match explainer (`tri_explain_instance`) prints this for a person:

```text
result: unknown
bindings:
  .instrument.size = 19mm
residuals: target.size
```

`@family(operations)` puts both patterns in a family. The engine compiles an
index for each family at load. Given a description, the index returns only
the patterns that could match it. `@quickcheck(target.state)` names a path
where matches often fail; the index compares types at those paths before
trying a full match. For a loose nut, the index returns only `tighten`.

You don't have to guess quick-check paths. Turn on failure recording during
test runs, and the engine suggests the most frequent failure paths as a
`@quickcheck` attribute to paste in (see API.md).

## 9. Arithmetic

Fields can be related by arithmetic between tags:

```cue
#Lever: #Tool & {
    force:  $f & force & >=1N & <=500N
    arm:    $a & length
    torque: $f * $a
}

breaker: #Lever & { material: "steel", size: 60cm, mass: 2kg, arm: 0.5m, force: 80N }
```

`breaker`'s torque is `40Nm`. Units follow from the arithmetic: a force times
a length is a torque. Intermediate results don't need a kind of their own,
but the final result must convert to its field's kind.

Arithmetic is a constraint, not an assignment. While its arguments are open
ranges, so is its result, and it narrows as they do. It also narrows
backwards through sums, differences and scaling by a constant: if a total and
one part are known, so is the other part. A result that contradicts its field
is a failure like any other. Construction never draws a computed field; it
computes it.

References work in arithmetic like tags, and a `let` names a value for the
file (or for the struct it's in) without declaring an instance:

```cue
let socket = 30mm

#Ratchet: #Lever & { reach: .arm + socket }

ratchet: #Ratchet & { material: "steel", size: 30cm, mass: 1kg, arm: 0.25m, force: 60N }
```

`ratchet`'s reach is `280mm`. A `let` copies, as naming an instance does:
each use is its value afresh. Its name may not be an instance's or a built-in
type's, so it never hides one.

## 10. Definite clauses

Some questions need recursion, such as which rooms you can reach. Clauses are
ordinary instances of two built-in types, `#Fact` and `#Clause`:

```cue
#Room: "kitchen" | "hall" | "cellar" | "yard"
#Link: { from: #Room, to: #Room }
#Door: #Link & { width: length }
#Way:  #Link & { length: length }

d1: #Fact & { head: #Door & { from: "kitchen", to: "hall",   width: 90cm } }
d2: #Fact & { head: #Door & { from: "hall",    to: "cellar", width: 70cm } }
d3: #Fact & { head: #Door & { from: "cellar",  to: "yard",   width: 1m } }

way_one: #Clause & {
    head: #Way & { from: $x, to: $y, length: 1m }
    body: [#Door & { from: $x, to: $y }]
}
way_more: #Clause & {
    head: #Way & { from: $x, to: $z, length: $n + 1m }
    body: [#Door & { from: $x, to: $y }, #Way & { from: $y, to: $z, length: $n }]
}
```

Here `length` counts doors passed, a metre each. `#Door` and `#Way` share
`from` and `to` through `#Link`. Declaring them separately on both types
would be an error, because a feature has exactly one introducing type.

A query is a structure. `tri_solve` with `#Way & { from: "kitchen" }` finds
three solutions:

```text
#Way & { from: "kitchen", length: 3000mm, to: "yard" }
#Way & { from: "kitchen", length: 2000mm, to: "cellar" }
#Way & { from: "kitchen", length: 1000mm, to: "hall" }
```

They come in a fixed order: goals are proved left to right, and clauses are
tried in name order (`way_more` before `way_one`). The arithmetic `$n + 1m`
waits until the recursive goal fixes `$n`. A bound in the query filters:
`length: <=2m` leaves two solutions. A depth limit bounds each proof, and the
caller learns if it cut any short.

Clauses suit short relational inferences. Search over the map, such as
pathfinding, belongs in engine code.

## 11. Runtime values

The game builds descriptions at runtime from the same syntax:

```c
tri_value(c, "#Roles & { instrument: #Wrench & { size: 19mm }, target: #Nut }", arena, err, sizeof err);
```

A runtime value is stricter than content. A default (`*`) has no meaning in
it, and neither does a choice between separate numbers. Both are errors.
Free text and referents are welcome: `name: "the miller's wrench"` is a
`text` value, and `owner: ref(12)` is a handle to entity 12.

## 12. Knowledge and memory decay

An agent's knowledge of a thing is a description, usually less specific than
the truth. Two operations matter:

- **Recognition** unifies a new percept with what the agent knows. Where they
  conflict, `tri_conflicts` reports every conflicting path, not just the first.
- **Memory decay** generalises a description along primary parents:
  `"forged"` becomes `"steel"`, then `#Material`. A number widens by its
  field's `@widen` step, such as `height: length @widen(5cm)`; a number
  without one is forgotten in one step.

## Five things that surprise

1. **A feature has one introducing type.** Two unrelated types that both
   declare `from` are an error. The message names both, and suggests a
   common supertype: declare the field there and inherit it.
2. **Naming copies; references and tags share.** `wrench_19.size` copies
   another declaration's field, as CUE's references do. Within a declaration,
   `.instrument.size` and `$s` make one node, so a constraint at either end
   holds at both. In CUE, `x: y & >5` leaves `y` alone; here `x: .y & >5`
   constrains `y` too.
3. **Types are nominal and closed.** A structure may only use features its
   type has, and `#Wrench: #Tool` is a different type from `#Tool`.
4. **Specific defaults win.** CUE drops conflicting defaults. Triangle keeps
   the more specific one, and drops only defaults from unrelated types.
5. **A string some enum lists is that enum's atom.** `"steel"` is the atom of
   `#Material` everywhere. A string no enum lists is free `text`.

## Where next

- [REFERENCE.md](REFERENCE.md): the grammar, every attribute, the built-in
  types, units, and diagnostics.
- [API.md](API.md): loading content, matching, construction, and saves from C
  and Objective-C.
- [CONTENT_LANGUAGE.md](../../CONTENT_LANGUAGE.md): the specification, with the
  reasoning, scenarios, and research behind each decision.
